import AppKit
import SwiftUI

// Back, forward and the address, with the column folded away (#48).
//
// Folded, the page has the whole window, and nothing in it says where the
// page is or takes it back one: the buttons and the address are the
// column's, and the whole column brought out over the page is a long way
// round for one of them. A pointer resting against the window's top edge,
// about its middle, brings them down alone: a small card with the column's
// own three buttons and the page's site, which is ⌘L's field once clicked.
// It goes a moment after the pointer leaves it.
//
// Only with the column folded away. Beside the page, or out over it, the
// column has them; the strip across the top, folded, comes down whole from
// the same edge (Fold.swift). Never with the address above the page, where
// they stay in sight (Toolbar.swift). Not in full screen, where the top edge is the
// menu bar's. And not a setting: the middle of the top edge brought nothing
// before, and nothing that moved moves differently for it.

/// Whether the card is down, and the pointer's say in that. The browser's
/// own, apart from it, so only the card is drawn again when it comes or goes.
@MainActor
final class EdgeBarState: ObservableObject {
    @Published private(set) var shown = false
    /// Down once the pointer has rested on the edge.
    private var arriving: DispatchWorkItem?
    /// Gone once the pointer has stayed away.
    private var leaving: DispatchWorkItem?
    /// Where the pointer was last seen, to tell one still rising.
    private var last: CGPoint?

    /// How long the pointer rests on the edge before the card comes: the
    /// folded strip's wait, for the same reason, since the top edge is
    /// crossed on every trip to the menu bar.
    static let dwell: TimeInterval = Fold.dwell
    /// The rest this one waits for: `dwell`, or longer in a test that moves
    /// the pointer with real sleeps, which a slow runner stretches past 0.05 s.
    var resting: TimeInterval = EdgeBarState.dwell
    /// How long after the pointer has left the card it stays, for a hand
    /// that overshoots one of its buttons: longer than the column's grace,
    /// as it is a far smaller thing to stay on.
    static let grace: TimeInterval = 0.25

    /// The pointer at `point`, from the window's top left, in a window of
    /// `size`; nil once it has left the window. `pressed`: a button is down,
    /// and something is on its way across the edge, a tab or the window
    /// itself.
    func pointer(at point: CGPoint?, in size: CGSize, pressed: Bool) {
        let last = self.last
        self.last = point
        if shown {
            if let point, EdgeBar.holds(point, in: size) {
                leaving?.cancel()
                leaving = nil
            } else if leaving == nil {
                let going = DispatchWorkItem { [weak self] in self?.putAway() }
                leaving = going
                DispatchQueue.main.asyncAfter(deadline: .now() + EdgeBarState.grace, execute: going)
            }
        } else if let point, !pressed, EdgeBar.brings(point, in: size) {
            // Still rising, from the top left: on its way past the edge to
            // the menu bar, so the wait starts again (Fold.rising).
            if let last, point.y < last.y {
                arriving?.cancel()
                arriving = nil
            }
            guard arriving == nil else { return }
            let coming = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.arriving = nil
                self.shown = true
            }
            arriving = coming
            DispatchQueue.main.asyncAfter(deadline: .now() + resting, execute: coming)
        } else {
            // Crossed the edge without stopping.
            arriving?.cancel()
            arriving = nil
        }
    }

    /// Gone at once, and nothing on its way: the column is back, the field
    /// is up, or one of its own buttons was the address.
    func putAway() {
        arriving?.cancel()
        arriving = nil
        leaving?.cancel()
        leaving = nil
        if shown { shown = false }
    }
}

extension Browser {
    /// Nothing of the column is in the window, and nothing has the screen
    /// or the keys in its place: the top edge may bring the card (EdgeBar).
    /// Not with the address above the page, which has all of it there,
    /// folded or not (Toolbar).
    var edgeBarWanted: Bool {
        prefs.sidebar && !prefs.toolbar && folded && !peeking && !frontFillsHere && !editing
            && !fullScreen && window?.styleMask.contains(.fullScreen) != true
    }
}

/// Over the window's top, in its middle: the card, and what watches the
/// pointer for it while it could come.
struct EdgeBar: View {
    let browser: Browser
    @ObservedObject var state: EdgeBarState
    /// Browser.edgeBarWanted, as the window last said it.
    let wanted: Bool

    /// As wide as it gets, and as near the window's sides.
    static let width: CGFloat = 420
    static let margin: CGFloat = 16
    static let height: CGFloat = 40
    /// How far under the top edge it hangs: clear of the band the window
    /// is dragged by where the pointer brought it down.
    static let top: CGFloat = 8
    /// How far round the card the pointer is still on it.
    static let slack: CGFloat = 16

    /// Where the card stands in a window of `size`, from its top left.
    static func frame(in size: CGSize) -> CGRect {
        let wide = min(width, max(0, size.width - 2 * margin))
        return CGRect(x: ((size.width - wide) / 2).rounded(), y: top, width: wide, height: height)
    }

    /// Whether a pointer at `point` is where the card comes from: against
    /// the top edge, as near it as the column's edge is to find
    /// (Fold.edge), above where the card will stand. Not the rest of the
    /// top edge, which is on the way to everything else up there.
    static func brings(_ point: CGPoint, in size: CGSize) -> Bool {
        let frame = frame(in: size)
        return point.y >= 0 && point.y < Fold.edge && point.x >= frame.minX && point.x <= frame.maxX
    }

    /// Whether a pointer at `point` keeps the card down: on it, a little
    /// round it, or between it and the edge it came from.
    static func holds(_ point: CGPoint, in size: CGSize) -> Bool {
        let frame = frame(in: size)
        return point.y >= 0 && point.y <= frame.maxY + slack
            && point.x >= frame.minX - slack && point.x <= frame.maxX + slack
    }

    var body: some View {
        ZStack(alignment: .top) {
            if wanted {
                EdgeWatch { point, size in
                    state.pointer(at: point, in: size, pressed: NSEvent.pressedMouseButtons != 0)
                }
                // Over the whole window, and nothing of it there to press:
                // what lies under it takes every click, as before.
                .allowsHitTesting(false)
            }
            if wanted, state.shown {
                card.transition(.bar(.top))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // It comes on its spring and goes quickly, as the field does.
        .animation(state.shown ? Motion.settle : Motion.quick, value: wanted && state.shown)
        .onChange(of: wanted) { _, wanted in
            if !wanted { state.putAway() }
        }
    }

    private var card: some View {
        HStack(spacing: 6) {
            // The column's own, with whichever of them Settings hides hidden.
            if browser.prefs.helmDoors > 0 { Helm(browser: browser) }
            EdgeAddress(browser: browser) { state.putAway() }
        }
        .padding(.horizontal, 7)
        .frame(height: EdgeBar.height)
        .frame(maxWidth: EdgeBar.width)
        // On the raised ground, as the row under the tabs across the top.
        .environment(\.greys, .white)
        // It hangs in what AppKit takes for title bar, where a press on
        // anything starts the window's drag before the thing hears of it:
        // a strip under it holds the window while the pointer is over one
        // of its buttons, as the column's own corner does (DragStrip).
        .background { DragStrip() }
        .elevated(.float, in: RoundedRectangle(cornerRadius: Radius.float, style: .continuous))
        .padding(.horizontal, EdgeBar.margin)
        .padding(.top, EdgeBar.top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation")
    }
}

/// Where the page in front is from, as the address bar says it at rest
/// (AddressLine): pressed, it is ⌘L, whose field comes up over the page as
/// it does whenever the column is folded away.
private struct EdgeAddress: View {
    @ObservedObject var browser: Browser
    /// Told as it is pressed: the card has done its part.
    let pressed: () -> Void

    var body: some View {
        if let tab = browser.active {
            Shown(browser: browser, tab: tab, pressed: pressed).id(tab.id)
        } else {
            Line(help: "Open a new tab") {
                pressed()
                browser.newTab()
            } label: {
                Ask()
            }
        }
    }

    private struct Ask: View {
        var body: some View {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
            Text("Search or enter address")
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
        }
    }

    /// Watches the tab: its address changes with nothing of the browser's.
    private struct Shown: View {
        let browser: Browser
        @ObservedObject var tab: Tab
        let pressed: () -> Void

        var body: some View {
            Line(help: "Type an address or a search") {
                pressed()
                // An empty tab's field is the one in the middle of the window.
                if tab.isBlank { browser.askFocus() } else { browser.edit() }
            } label: {
                if let title = tab.page?.title {
                    // One of Lun's own pages: its name.
                    Text(title).foregroundStyle(Palette.ink).lineLimit(1)
                } else if let rest = AtRest.of(tab.page?.url ?? tab.address) {
                    if rest.kind == .notSecure {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.unsafe)
                            .help("Not secure")
                            .accessibilityLabel("Not secure")
                    }
                    AtRestLine(rest: rest, size: 13, ink: Palette.ink, dim: Palette.muted, says: false, weight: .regular)
                } else {
                    Ask()
                }
            }
        }
    }

    /// The line itself: a well on the card, a little darker under the
    /// pointer, that gives under a press.
    private struct Line<Label: View>: View {
        let help: String
        let act: () -> Void
        @ViewBuilder let label: Label
        @State private var hovering = false

        var body: some View {
            Button(action: act) {
                HStack(spacing: 6) {
                    label
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 26)
                .background(hovering ? Palette.fillHover : Palette.fill,
                            in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
            }
            .buttonStyle(Gives(to: 0.98))
            .hovers($hovering)
            .shortcutHelp(help, "file.openAddress")
            .accessibilityLabel("Address")
        }
    }
}

/// Tells where the pointer is over the window, from its top left, on every
/// move, and that it has gone when it leaves: a view that takes no click,
/// whose tracking hears the pointer over whatever lies under it, the page
/// included. There only while the card could come.
private struct EdgeWatch: NSViewRepresentable {
    let moved: (CGPoint?, CGSize) -> Void

    func makeNSView(context: Context) -> Tracker {
        let view = Tracker()
        view.moved = moved
        return view
    }

    func updateNSView(_ view: Tracker, context: Context) {
        view.moved = moved
    }

    static func dismantleNSView(_ view: Tracker, coordinator: ()) {
        view.moved = nil
    }

    final class Tracker: NSView {
        var moved: ((CGPoint?, CGSize) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited,
                                                                  .activeInActiveApp, .inVisibleRect],
                                           owner: self, userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) { tell(event) }
        override func mouseMoved(with event: NSEvent) { tell(event) }
        override func mouseExited(with event: NSEvent) { moved?(nil, bounds.size) }

        private func tell(_ event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            moved?(CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y), bounds.size)
        }
    }
}
