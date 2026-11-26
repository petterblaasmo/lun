import AppKit
import WebKit

// Pages out of sight load a few at a time.
//
// A page loading runs its scripts on a processor of its own. Twenty tabs
// asked for at once (a folder of bookmarks opened, a run of links opened
// behind the page being read, tabs reloaded by an extension) are twenty
// pages each wanting a whole processor, and the window's own thread then
// waits its turn among them: ready, and not running. Typing and the column
// stall for as long as they load (SpeedBenchTests.testBackgroundTabsLoading).
//
// So a page out of sight starts loading only while fewer than `most` others
// out of sight are; the rest wait, in the order they were asked for. What
// never waits:
// - a page on screen, or about to be: the tab in front, a page of its split,
//   a peek (Tab.onScreen);
// - a page that comes into sight while it waits. Picked, it loads as its
//   view lands in the window (Tab.revive, `hurry`); put in a window any
//   other way, in the step after (PageView.viewDidMoveToWindow, `shown`).
//
// And every page that waits does load. A turn ends when its page stops
// loading; `unstarted` seconds on if the page never began; `longest` seconds
// on whatever it is doing. A page that never says it is done holds up no
// other for longer than that, and a link just opened goes ahead of pages
// asked for many at a time or only coming back, so a folder of bookmarks
// opening or a row of tabs reloading doesn't keep it waiting
// (LoadTurnsTests).

@MainActor
final class LoadTurns {
    static let shared = LoadTurns()

    /// How many pages out of sight load at once: half the Mac's processors,
    /// from two to eight. Set by the tests and the measurement.
    static var most = min(8, max(2, ProcessInfo.processInfo.activeProcessorCount / 2))
    /// How long a turn is kept for a page that hasn't begun to load: a load
    /// WebKit didn't take holds up nobody.
    static var unstarted: TimeInterval = 2
    /// How long a turn lasts at most. A page still loading after this long
    /// is waiting for its network, not using a processor.
    static var longest: TimeInterval = 10

    /// Who asked. One page somebody just asked for (a link opened in a new
    /// tab, an address gone to) goes ahead of pages asked for many at a time
    /// (a folder of bookmarks opened) and of pages only coming back
    /// (reloaded, woken, recovered).
    enum Kind { case asked, batch }

    /// A load: true when it asked WebKit for a page, false when it found it
    /// was no longer wanted (another load came after it, its view went).
    typealias Load = () -> Bool

    private final class Turn {
        weak var view: PageView?
        var watch: NSKeyValueObservation?
        var started = false
        var ends: [DispatchWorkItem] = []
    }

    private struct Waiting {
        weak var view: PageView?
        let kind: Kind
        let load: Load
    }

    private var turns: [ObjectIdentifier: Turn] = [:]
    private var waiting: [Waiting] = []

    /// How many pages out of sight are loading in their turn, and how many
    /// wait for one.
    var loadingCount: Int { turns.count }
    var waitingCount: Int { waiting.count }

    /// Whether a load for `view` is waiting its turn.
    func waits(for view: PageView) -> Bool { waiting.contains { $0.view === view } }

    /// In a window that shows: not out of every window, nor in the room off
    /// every screen where a script's or an agent's tabs are laid out
    /// (PageRoom).
    static func inSight(_ view: PageView) -> Bool {
        guard let window = view.window else { return false }
        return window !== PageRoom.shared.window
    }

    /// `load` for `view`: now, if the page is `wanted` on screen, in sight
    /// already, or a turn is free; otherwise once one is. A load asked for
    /// again replaces the one waiting.
    func start(_ view: PageView, _ kind: Kind, wanted: Bool, _ load: @escaping Load) {
        waiting.removeAll { $0.view == nil || $0.view === view }
        finish(ObjectIdentifier(view), next: false)
        if wanted || Self.inSight(view) {
            _ = load()
        } else if turns.count < Self.most {
            run(view, load)
        } else if kind == .asked, let behind = waiting.firstIndex(where: { $0.kind == .batch }) {
            waiting.insert(Waiting(view: view, kind: kind, load: load), at: behind)
        } else {
            waiting.append(Waiting(view: view, kind: kind, load: load))
        }
        next()
    }

    /// The tab was picked while its load waited: the load once the view is
    /// in a window, or a second on with none, as a tab woken waits for the
    /// stage (Tab.continueLoadAndVerify has why). False with nothing waiting.
    func hurry(_ view: PageView) -> Bool {
        guard let index = waiting.firstIndex(where: { $0.view === view }) else { return false }
        let load = waiting.remove(at: index).load
        if view.window != nil {
            _ = load()
        } else {
            view.whenInWindow(within: 1) { _ = load() }
        }
        return true
    }

    /// The view came into a window. In sight, what it waits for starts in
    /// the next step (its size comes after its window: see
    /// PageView.viewDidMoveToWindow), and the turn it held goes to another.
    func shown(_ view: PageView) {
        guard Self.inSight(view) else { return }
        finish(ObjectIdentifier(view))
        guard let index = waiting.firstIndex(where: { $0.view === view }) else { return }
        let load = waiting.remove(at: index).load
        DispatchQueue.main.async { _ = load() }
    }

    /// The view is going (its tab closed, or put to sleep): what waited for
    /// it is dropped, and the turn it held goes to another.
    func forget(_ view: PageView) {
        waiting.removeAll { $0.view == nil || $0.view === view }
        finish(ObjectIdentifier(view))
    }

    private func run(_ view: PageView, _ load: Load) {
        let id = ObjectIdentifier(view)
        let turn = Turn()
        turn.view = view
        turns[id] = turn
        // This turn, not one the same view was given later.
        let key = ObjectIdentifier(turn)
        turn.watch = view.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
            MainActor.assumeIsolated {
                guard let self, let turn = self.turns[id], ObjectIdentifier(turn) == key else { return }
                if view.isLoading { turn.started = true } else if turn.started { self.finish(id) }
            }
        }
        for (after, unlessStarted) in [(Self.unstarted, true), (Self.longest, false)] {
            let end = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let turn = self.turns[id], ObjectIdentifier(turn) == key,
                          !(unlessStarted && turn.started) else { return }
                    self.finish(id)
                }
            }
            turn.ends.append(end)
            DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: end)
        }
        // Asked again while still loading, it may never stop loading in
        // between to say it started.
        if !load() {
            if turns[id] === turn { finish(id, next: false) }
        } else if view.isLoading {
            turn.started = true
        }
    }

    private func finish(_ id: ObjectIdentifier, next more: Bool = true) {
        guard let turn = turns.removeValue(forKey: id) else { return }
        turn.watch?.invalidate()
        turn.ends.forEach { $0.cancel() }
        if more { next() }
    }

    private func next() {
        // A view gone without a word since it took its turn gives it back.
        for (id, turn) in turns where turn.view == nil { finish(id, next: false) }
        while turns.count < Self.most, !waiting.isEmpty {
            let first = waiting.removeFirst()
            guard let view = first.view else { continue }
            if Self.inSight(view) {
                _ = first.load()
            } else {
                run(view, first.load)
            }
        }
    }
}
