import AppKit
import SwiftUI
import WebKit

// "● Loom is recording your screen — Stop": a small pill of Search's own,
// floating at the foot of the screen for as long as an extension records
// anything — the screen, a window, the camera or the microphone — beside
// macOS's own sharing item and dots, and with its own Stop. It never takes
// the keys or the focus from what you are doing. What is recording is
// ExtensionCapture's to say (see ExtensionCapture.swift); this only shows it.
//
// An offscreen document that records (Tella, Vidyard…) has nowhere WebKit
// counts as seen, and WebKit won't start a capture from a page nobody sees.
// While it records, its page is lent to the pill — a 2×2 point view behind
// the pill's content — and given back after: the thing that lets it record
// is the thing that says it is recording.
//
// It comes up at the foot of the screen, which is where Meet and others
// keep their own controls. So it can be taken by anywhere but its Stop and
// put somewhere else, and it comes back where it was left (PillPlace).

/// One line of the pill: who is recording, and what.
struct RecordingLine: Identifiable, Equatable {
    let id: String
    /// The extension's name.
    let name: String
    /// "is recording your screen", "is using your camera and microphone"…
    let what: String
}

@MainActor
final class RecordingIndicator: ObservableObject {
    static let shared = RecordingIndicator()

    /// What the pill says, one line per extension recording.
    @Published private(set) var lines: [RecordingLine] = []
    /// What Stop does, for a line's extension.
    var onStop: ((String) -> Void)?

    private var panel: PillPanel?
    /// Offscreen pages lent to the pill while they record, with where each
    /// came from, to be given back.
    private var hosted: [(web: WKWebView, home: NSView?)] = []

    /// The lines as they are now, and the pages capturing: shown when
    /// there are any, or a page is lent to the pill; gone when there are
    /// none. A tab whose page is among them wears a mark in the row.
    func update(_ lines: [RecordingLine], pages: [WKWebView] = []) {
        if self.lines != lines { self.lines = lines }
        let capturing = Set(pages.map(ObjectIdentifier.init))
        for browser in Browsers.all {
            for tab in browser.tabs {
                let now = tab.built.map { capturing.contains(ObjectIdentifier($0)) } ?? false
                if tab.recording != now { tab.recording = now }
            }
        }
        settle()
    }

    /// A line's Stop.
    func stop(_ id: String) { onStop?(id) }

    // MARK: - lending an offscreen page (phase 2)

    /// An offscreen document's page, lent to the pill so that WebKit counts
    /// it as seen while it records. Asked again for the same page, nothing
    /// more happens.
    func host(_ web: WKWebView) {
        guard !hosted.contains(where: { $0.web === web }) else { return }
        hosted.append((web, web.superview))
        let panel = ownPanel()
        web.removeFromSuperview()
        panel.lend(web)
        settle()
    }

    /// Given back to where it was, or to nowhere if it had no home.
    func release(_ web: WKWebView) {
        guard let index = hosted.firstIndex(where: { $0.web === web }) else { return }
        let home = hosted.remove(at: index).home
        web.removeFromSuperview()
        if let home { home.addSubview(web) }
        settle()
    }

    /// Whether a page is lent to the pill now, for the bench.
    func hosts(_ web: WKWebView) -> Bool { hosted.contains { $0.web === web } }

    // MARK: - on screen

    /// Up while anything records or a page is lent to it; down otherwise.
    /// A test run keeps it off every screen, whatever it would show: its
    /// model is what is tested there (see Bench, recording).
    private func settle() {
        hosted.removeAll { $0.web.superview == nil && $0.web.window == nil && !isLent($0.web) }
        let wanted = !lines.isEmpty || !hosted.isEmpty
        guard wanted else {
            panel?.orderOut(nil)
            return
        }
        let panel = ownPanel()
        panel.fit()
        guard !Store.testing else { return }
        if !panel.isVisible {
            panel.orderFrontRegardless()
            Motion.arrive(panel)
        }
    }

    private func isLent(_ web: WKWebView) -> Bool { panel?.holds(web) == true }

    private func ownPanel() -> PillPanel {
        if let panel { return panel }
        let made = PillPanel(indicator: self)
        panel = made
        return made
    }

    /// The pill as it is drawn, as a picture, for the bench: the view alone,
    /// laid out off every screen.
    func picture(dark: Bool) -> NSBitmapImageRep? {
        let view = NSHostingView(rootView: PillView(indicator: self))
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = view.fittingSize
        view.frame = NSRect(origin: .zero, size: NSSize(width: max(size.width, 10), height: max(size.height, 10)))
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }
}

/// The panel: borderless, never key or main, over every space and full
/// screen app, at the foot of the screen Search is on.
private final class PillPanel: NSPanel {
    private let content: NSHostingView<PillView>
    /// Where lent pages go: behind the pill's own content, 2×2 points.
    private let lending = NSView(frame: NSRect(x: 2, y: 2, width: 2, height: 2))

    init(indicator: RecordingIndicator) {
        content = NSHostingView(rootView: PillView(indicator: indicator))
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 40),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        // Moved by PillGrip, which also writes down where it was left.
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        let root = NSView(frame: .zero)
        root.addSubview(lending)
        root.addSubview(content)
        contentView = root
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func lend(_ web: WKWebView) {
        web.frame = lending.bounds
        lending.addSubview(web)
    }

    func holds(_ web: WKWebView) -> Bool { web.superview === lending }

    /// Its size for what it says. Coming up, it is where it was last left,
    /// or at the foot of the screen, centred; already up, it stays put.
    func fit() {
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let screen = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = PillPlace.frame(size: size, left: PillPlace.left(), screens: NSScreen.screens.map(\.visibleFrame), home: area)
        content.frame = NSRect(origin: .zero, size: size)
        if isVisible { setFrame(NSRect(origin: self.frame.origin, size: size), display: true) } else { setFrame(frame, display: false) }
    }
}

/// Where the pill is: at the foot of the screen Lun is on until it is
/// dragged, then where it was left, on any screen, for as long as that
/// spot is still on one. What is kept is the middle of its lower edge, so
/// a pill with more or fewer words comes back centred on the same spot.
enum PillPlace {
    static let key = "recording.pill.place"
    /// How far above the foot of the screen it rests when never moved.
    static let rise: CGFloat = 24

    /// The frame for a pill of `size`. `screens` are the visible parts of
    /// every screen, `home` that of the screen Lun is on. A spot left on a
    /// screen since unplugged, or under where the Dock is now, isn't
    /// followed out of sight: the pill is kept whole on the screen the
    /// spot is on, or goes back to the foot of `home`.
    static func frame(size: CGSize, left: CGPoint?, screens: [CGRect], home: CGRect) -> CGRect {
        let rest = CGRect(x: home.midX - size.width / 2, y: home.minY + rise, width: size.width, height: size.height)
        guard let left, let screen = screens.first(where: { $0.insetBy(dx: -1, dy: -1).contains(left) }) else { return rest }
        let x = min(max(left.x - size.width / 2, screen.minX), max(screen.minX, screen.maxX - size.width))
        let y = min(max(left.y, screen.minY), max(screen.minY, screen.maxY - size.height))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Where it was last left, if it ever was.
    static func left(in store: UserDefaults = Store.settings) -> CGPoint? {
        guard let kept = store.array(forKey: key) as? [Double], kept.count == 2 else { return nil }
        return CGPoint(x: kept[0], y: kept[1])
    }

    /// Left here, by hand.
    static func leave(_ frame: CGRect, in store: UserDefaults = Store.settings) {
        store.set([Double(frame.midX), Double(frame.minY)], forKey: key)
    }
}

/// Where each Stop is in the pill, for the grip to leave alone.
private struct StopPlaces: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) { value += nextValue() }
}

/// Laid over the whole pill: a press anywhere that isn't Stop takes the
/// pill, and it goes where the pointer goes until it is let go. A view of
/// AppKit's own, laid over rather than under: the pill's words and its
/// outline take a press meant for anything SwiftUI has behind them, and a
/// SwiftUI drag would move the view inside the panel, not the panel. Over
/// a Stop it isn't there, and the button is pressed as before.
struct PillGrip: NSViewRepresentable {
    /// The Stops, in the pill's own coordinates, from its top left.
    var holes: [CGRect] = []

    func makeNSView(context: Context) -> Handle { Handle() }
    func updateNSView(_ view: Handle, context: Context) { view.holes = holes }

    final class Handle: NSView {
        var holes: [CGRect] = []
        /// Where the pointer is on the screen; a test's own stands in.
        var pointer: () -> CGPoint = { NSEvent.mouseLocation }
        /// Where a pill let go of is written down.
        var store: UserDefaults = Store.settings
        /// The pointer and the window's corner as the press began.
        private var held: (pointer: CGPoint, corner: CGPoint)?
        private var moved = false

        /// From the top left, as the holes are given.
        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        /// The panel is never the key window: the first press is the drag.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Not there over a Stop, for a press or for the pointer alone.
        override func hitTest(_ point: NSPoint) -> NSView? {
            let here = superview.map { convert(point, from: $0) } ?? point
            guard bounds.contains(here), !holes.contains(where: { $0.contains(here) }) else { return nil }
            return self
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            held = (pointer(), window.frame.origin)
            moved = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, let held else { return }
            let now = pointer()
            let corner = CGPoint(x: held.corner.x + now.x - held.pointer.x, y: held.corner.y + now.y - held.pointer.y)
            guard corner != window.frame.origin else { return }
            moved = true
            window.setFrameOrigin(corner)
        }

        override func mouseUp(with event: NSEvent) {
            defer { held = nil }
            // A press that went nowhere leaves nothing to remember.
            guard held != nil, moved, let window else { return }
            PillPlace.leave(window.frame, in: store)
        }
    }
}

/// What the pill draws: a line per extension recording, each with Stop.
struct PillView: View {
    @ObservedObject var indicator: RecordingIndicator

    private var corner: CGFloat { indicator.lines.count > 1 ? Radius.panel : 19 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(indicator.lines) { line in
                HStack(spacing: 8) {
                    // The pill's one colour: a recording is known at a
                    // glance by its red dot, as in Chrome and Loom.
                    Circle()
                        .fill(Palette.recording)
                        .frame(width: 7, height: 7)
                    (Text(line.name).font(.system(size: 12.5, weight: .semibold))
                        + Text(" \(line.what)").font(.system(size: 12.5)))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 12)
                    Pill("Stop", filled: true) { indicator.stop(line.id) }
                        .accessibilityLabel("Stop \(line.name)")
                        .anchorPreference(key: StopPlaces.self, value: .bounds) { [$0] }
                }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        // A capsule for one line (half its 38 points); a panel's corners
        // round a taller card.
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        // Taken by anywhere that isn't Stop, to be moved off what it covers.
        .overlayPreferenceValue(StopPlaces.self) { stops in
            GeometryReader { geometry in PillGrip(holes: stops.map { geometry[$0] }) }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording")
    }
}
