import AppKit
import SwiftUI

// An edge that is pulled to resize what is beside it, as a view of AppKit's
// own.
//
// The column's edge was a SwiftUI view: the left-right arrows were pushed on
// the cursor stack as the pointer came over it and popped as it left. Pulled,
// the edge moves under the pointer, a step behind it or ahead, so the pointer
// left and came back many times over one pull and the arrows flickered to the
// plain pointer and back; a push or a pop missed left the wrong one for good.
// Here the arrows are a cursor rectangle of the view's, as a window's own
// edge has them, and are set again at every step of a pull, wherever the
// pointer has got to, until the button comes up.
//
// What a pull does is the caller's: this only says how far the pointer has
// gone across since the press, when it was let go, and a double-click.

struct EdgeHandle: NSViewRepresentable {
    /// The pointer over the edge, or gone from it. Held, it counts as over
    /// until it is let go.
    var hover: (Bool) -> Void = { _ in }
    /// How far across the pointer is from where it pressed, in points, to
    /// the right counted up. Not before it has moved a point: a click is
    /// no pull.
    let pulled: (CGFloat) -> Void
    /// Let go after a pull.
    let ended: () -> Void
    /// Double-clicked.
    var twice: () -> Void = {}

    func makeNSView(context: Context) -> Edge {
        let view = Edge()
        view.handle = self
        return view
    }

    func updateNSView(_ view: Edge, context: Context) { view.handle = self }

    /// Taken out mid-pull, the button's release never reaches it: the
    /// arrows are let go of here.
    static func dismantleNSView(_ view: Edge, coordinator: ()) { view.letGo() }

    final class Edge: NSView {
        var handle: EdgeHandle?
        /// Where the pointer is across the screen, by the event's own
        /// place in its window (not where the mouse is by the time it is
        /// read, which a synthesised event never moves); a test's own
        /// stands in.
        var pointer: (NSEvent) -> CGFloat = { event in
            event.window.map { $0.convertPoint(toScreen: event.locationInWindow).x } ?? NSEvent.mouseLocation.x
        }
        /// The arrows, shown; counted by a test.
        var arrows: () -> Void = { NSCursor.resizeLeftRight.set() }

        /// How far the pointer goes before a press is a pull.
        static let slack: CGFloat = 1

        /// Where the pointer pressed, while the button is down.
        private var pressed: CGFloat?
        private(set) var pulling = false
        private var inside = false

        /// Never the window's to drag from: the press is the edge's.
        override var mouseDownCanMoveWindow: Bool { false }
        /// A pull is the same in a window behind: no click to bring it
        /// forward first.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds,
                                           options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                           owner: self, userInfo: nil))
        }

        /// Ours to answer, not passed up: the view under the edge would
        /// answer with the plain pointer.
        override func cursorUpdate(with event: NSEvent) { arrows() }

        override func mouseEntered(with event: NSEvent) {
            inside = true
            handle?.hover(true)
        }

        override func mouseExited(with event: NSEvent) {
            inside = false
            // Held, the edge is still lit: the pointer runs ahead of it.
            if pressed == nil { handle?.hover(false) }
        }

        override func mouseDown(with event: NSEvent) {
            pressed = pointer(event)
            pulling = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let pressed else { return }
            let across = pointer(event) - pressed
            if !pulling {
                guard abs(across) >= Edge.slack else { return }
                pulling = true
            }
            // At every step: the page the pointer is over by now, or a
            // cursor rectangle crossed on the way, may have set its own.
            arrows()
            handle?.pulled(across)
        }

        override func mouseUp(with event: NSEvent) {
            guard pressed != nil else { return }
            let pulled = pulling
            pressed = nil
            pulling = false
            if pulled {
                handle?.ended()
            } else if event.clickCount == 2 {
                handle?.twice()
            }
            // Let go off the edge: no longer over it, and the pointer is
            // whatever is under it now.
            let over = window != nil ? bounds.contains(convert(event.locationInWindow, from: nil)) : inside
            if !over {
                inside = false
                handle?.hover(false)
                window?.invalidateCursorRects(for: self)
            }
        }

        /// Gone from the window with the button still down.
        func letGo() {
            guard pressed != nil else { return }
            pressed = nil
            pulling = false
            NSCursor.arrow.set()
        }
    }
}
