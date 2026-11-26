import AppKit
import WebKit
import XCTest
@testable import Search

/// The floating video's window under two fingers: a swipe too short to be a
/// flick places it point for point, a pinch sizes it to where the fingers
/// lift, and one that begins over it is its own whichever window has the
/// keys.
///
/// Everything here is arithmetic and a window off every screen handed made-up
/// events: what a trackpad sends, and how any of it feels, is by hand.
@MainActor
final class FloatGestureTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    /// A screen made up far off the real ones, and the window in its middle.
    private let screen = NSRect(x: -30000, y: -30000, width: 1440, height: 900)
    private var middle: NSPoint { NSPoint(x: screen.midX - 220, y: screen.midY - 123) }

    // MARK: - what a swipe comes to

    func testOnlyASwipePastANudgeIsAFlick() {
        XCTAssertFalse(Float.flies(CGVector(dx: 12, dy: -16), lifted: true), "20 points, lifted: placed")
        XCTAssertTrue(Float.flies(CGVector(dx: 13, dy: -16), lifted: true), "a little more, lifted: a flick")
        XCTAssertFalse(Float.flies(CGVector(dx: 72, dy: 96), lifted: false), "120 points, fingers down: not yet")
        XCTAssertTrue(Float.flies(CGVector(dx: 73, dy: 96), lifted: false), "past that it goes without waiting")
        XCTAssertFalse(Float.flies(.zero, lifted: true))
    }

    func testAShortSwipePlacesItPointForPointWithFlicksOn() throws {
        try withFloat(flicks: true) { _, panel, controls in
            let from = panel.frame
            swipe(controls, by: CGVector(dx: 12, dy: -7), steps: 4)
            XCTAssertEqual(panel.frame.minX, from.minX + 12, accuracy: 0.01)
            XCTAssertEqual(panel.frame.minY, from.minY - 7, accuracy: 0.01)
            XCTAssertEqual(panel.frame.size, from.size)
            // And again from there, the other way: each swipe starts where
            // the last one left it.
            swipe(controls, by: CGVector(dx: -3, dy: 2), steps: 1)
            XCTAssertEqual(panel.frame.minX, from.minX + 9, accuracy: 0.01)
            XCTAssertEqual(panel.frame.minY, from.minY - 5, accuracy: 0.01)
        }
    }

    func testALongSwipeIsUnderTheFingersUntilItFliesToItsCorner() throws {
        try withFloat(flicks: true) { _, panel, controls in
            let from = panel.frame
            let fingers = Fingers()
            fingers.part = .began
            controls.scrollWheel(with: fingers)
            fingers.part = .changed
            fingers.move(dx: 30, dy: 30)
            controls.scrollWheel(with: fingers)
            controls.scrollWheel(with: fingers)
            XCTAssertEqual(panel.frame.minX, from.minX + 60, accuracy: 0.01, "under the fingers until it is a flick")
            XCTAssertEqual(panel.frame.minY, from.minY + 60, accuracy: 0.01)
            // Past 120 points it goes: to the corner it would have gone to
            // from where it rested, not from where the fingers had it.
            controls.scrollWheel(with: fingers)
            let corner = Float.corner(for: from, in: screen, toward: CGVector(dx: 90, dy: 90))
            XCTAssertEqual(panel.frame.origin, corner)
            XCTAssertEqual(corner, NSPoint(x: screen.maxX - 12 - from.width, y: screen.maxY - 12 - from.height))
            // The rest of the swipe is the same flick.
            controls.scrollWheel(with: fingers)
            fingers.part = .ended
            fingers.move(dx: 0, dy: 0)
            controls.scrollWheel(with: fingers)
            XCTAssertEqual(panel.frame.origin, corner)
        }
    }

    func testASwipeLiftedPastANudgeStillFlies() throws {
        try withFloat(flicks: true) { _, panel, controls in
            let from = panel.frame
            swipe(controls, by: CGVector(dx: -60, dy: 0), steps: 6)
            XCTAssertEqual(panel.frame.origin, Float.corner(for: from, in: screen, toward: CGVector(dx: -60, dy: 0)),
                           "to the left, as from where it rested")
        }
    }

    /// At a side, a swipe at that side is the pull it was: the window gives
    /// from where it rested, a third of the way, and is not placed first.
    func testASwipeAtTheSideItIsAgainstIsStillAPull() throws {
        try withFloat(flicks: true) { _, panel, controls in
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 12 - panel.frame.width, y: screen.midY))
            let from = panel.frame
            let fingers = Fingers()
            fingers.part = .began
            controls.scrollWheel(with: fingers)
            fingers.part = .changed
            fingers.move(dx: 4, dy: 0)
            controls.scrollWheel(with: fingers)
            XCTAssertEqual(panel.frame.minX, from.minX, accuracy: 0.01, "not moved out before the pull takes it")
            for _ in 0..<9 { controls.scrollWheel(with: fingers) }
            XCTAssertEqual(panel.frame.minX, from.minX + 40 * Float.Controls.give, accuracy: 0.01)
            fingers.part = .ended
            fingers.move(dx: 0, dy: 0)
            controls.scrollWheel(with: fingers)
            XCTAssertEqual(panel.frame.origin, from.origin, "let go short of docking: back where it rested")
        }
    }

    func testWithFlicksOffASwipeMovesItAsItDid() throws {
        try withFloat(flicks: false) { _, panel, controls in
            let from = panel.frame
            swipe(controls, by: CGVector(dx: 150, dy: -90), steps: 10)
            XCTAssertEqual(panel.frame.minX, from.minX + 150, accuracy: 0.01)
            XCTAssertEqual(panel.frame.minY, from.minY - 90, accuracy: 0.01)
        }
    }

    // MARK: - sizing

    func testSizingKeepsTheShapeAndFitsTheScreenBothWays() {
        let was = NSRect(x: 100, y: 100, width: 440, height: 247)
        let room = NSSize(width: 1440, height: 900)
        let centre = NSPoint(x: was.midX, y: was.midY)

        let twice = Float.sized(was, to: 880, around: centre, least: 260, within: room)
        XCTAssertEqual(twice.size.width, 880)
        XCTAssertEqual(twice.height, 494, accuracy: 0.01)
        XCTAssertEqual(twice.midX, was.midX, accuracy: 0.01, "about the pointer")
        XCTAssertEqual(twice.midY, was.midY, accuracy: 0.01)

        // About a place a quarter in from the left, three quarters up: it
        // stays that far in.
        let hand = NSPoint(x: was.minX + 110, y: was.minY + 185.25)
        let grown = Float.sized(was, to: 660, around: hand, least: 260, within: room)
        XCTAssertEqual((hand.x - grown.minX) / grown.width, 0.25, accuracy: 0.0001)
        XCTAssertEqual((hand.y - grown.minY) / grown.height, 0.75, accuracy: 0.0001)

        XCTAssertEqual(Float.sized(was, to: 10, around: centre, least: 260, within: room).width, 260, "no narrower than its least")
        XCTAssertEqual(Float.sized(was, to: 5000, around: centre, least: 260, within: room).width, 1440 * 0.85, accuracy: 0.01)

        // A wide screen: by its width alone the window was 2924 by 1641, on
        // a screen 1440 high.
        let wide = Float.sized(was, to: 5000, around: centre, least: 260, within: NSSize(width: 3440, height: 1440))
        XCTAssertEqual(wide.height, 1440 * 0.85, accuracy: 0.01)
        XCTAssertEqual(wide.width / wide.height, was.width / was.height, accuracy: 0.0001)

        // By its corner: the top left stays where it is.
        let dragged = Float.sized(was, to: 600, least: 260, within: room)
        XCTAssertEqual(dragged.minX, was.minX)
        XCTAssertEqual(dragged.maxY, was.maxY, accuracy: 0.01)

        // The window's own shape, where it has one, and not its frame's,
        // which is a point out as often as not.
        let rounded = NSRect(x: 100, y: 100, width: 441, height: 247)
        let own = Float.sized(rounded, to: 880, around: centre, shape: NSSize(width: 440, height: 247), least: 260, within: room)
        XCTAssertEqual(own.height, 494, accuracy: 0.001)
        XCTAssertEqual(Float.sized(rounded, to: 880, around: centre, shape: .zero, least: 260, within: room).height,
                       880 * 247 / 441, accuracy: 0.001, "no shape of its own: the frame's")

        // In whole points, the top edge kept: left to itself a window is
        // taken out to the pixels around it, wider at every step.
        XCTAssertEqual(Float.whole(NSRect(x: 99.4, y: 100.3, width: 450.56, height: 252.93)),
                       NSRect(x: 99, y: 100, width: 451, height: 253))
        XCTAssertEqual(Float.whole(was), was)
    }

    func testTheLastOfAPinchIsTakenAsTheFingersLift() throws {
        try withFloat(flicks: false) { _, panel, controls in
            let fingers = Fingers()
            fingers.part = .began
            fingers.pinch = 0.012
            controls.magnify(with: fingers)
            XCTAssertEqual(panel.frame.width, 440, "less than a step of a page laid out again each time: not yet")
            fingers.part = .changed
            fingers.pinch = 0.012
            controls.magnify(with: fingers)
            // A window is as wide as a whole number of points: 450.56 is 451.
            XCTAssertEqual(panel.frame.width, 451)
            fingers.pinch = 0.01
            controls.magnify(with: fingers)
            XCTAssertEqual(panel.frame.width, 451)
            fingers.part = .ended
            fingers.pinch = 0
            controls.magnify(with: fingers)
            XCTAssertEqual(panel.frame.width, 455, "what was left is taken as they lift, from 450.56 and not from 451")
            XCTAssertEqual(panel.frame.height, 255)

            // The smallest pinch there is does something.
            let before = panel.frame.width
            fingers.part = .began
            fingers.pinch = -0.004
            controls.magnify(with: fingers)
            fingers.part = .ended
            fingers.pinch = 0
            controls.magnify(with: fingers)
            XCTAssertEqual(panel.frame.width, 453)
            XCTAssertEqual(before, 455)
        }
    }

    /// Fine steps add up to where the fingers are: taken from the window's
    /// width, in whole points, each was a whole point or nothing.
    func testManyFineStepsEndWhereTheFingersDo() throws {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 700))
        try withFloat(flicks: false, page: web, picture: NSRect(x: 0, y: 12.5, width: 1200, height: 675)) { _, panel, controls in
            let fingers = Fingers()
            fingers.part = .began
            fingers.pinch = 0.003
            controls.magnify(with: fingers)
            fingers.part = .changed
            for _ in 0..<99 { controls.magnify(with: fingers) }
            XCTAssertEqual(panel.frame.width, (440 * pow(1.003, 100)).rounded())
            XCTAssertEqual(panel.frame.height, (440 * pow(1.003, 100) * 247 / 440).rounded(), "and its shape is the one it had")
            // Out as far as it goes, and held there: back in from that at once.
            fingers.pinch = 5
            controls.magnify(with: fingers)
            XCTAssertEqual(panel.frame.width, 1224)
            fingers.pinch = -0.1
            controls.magnify(with: fingers)
            XCTAssertEqual(panel.frame.width, 1102)
            XCTAssertEqual(web.frame.size, NSSize(width: 1200, height: 700))
        }
    }

    func testAPageThatKeepsItsSizeIsPinchedInFineSteps() throws {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 700))
        try withFloat(flicks: false, page: web, picture: NSRect(x: 0, y: 12.5, width: 1200, height: 675)) { _, panel, controls in
            let fingers = Fingers()
            fingers.part = .began
            fingers.pinch = 0.005
            controls.magnify(with: fingers)
            XCTAssertEqual(panel.frame.width, 442, "nothing is laid out again: the window follows the fingers")
            XCTAssertEqual(web.frame.size, NSSize(width: 1200, height: 700))
        }
    }

    func testADockedWindowTakesNoPinch() throws {
        try withFloat(flicks: true) { _, panel, controls in
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 12 - panel.frame.width, y: screen.midY))
            swipe(controls, by: CGVector(dx: 100, dy: 0), steps: 10)
            XCTAssertNotNil(controls.docked)
            let docked = panel.frame
            XCTAssertEqual(docked.minX, screen.maxX - Float.Controls.sliver, accuracy: 0.01)
            let fingers = Fingers()
            fingers.part = .began
            fingers.pinch = 0.3
            controls.magnify(with: fingers)
            XCTAssertEqual(panel.frame, docked)
        }
    }

    // MARK: - a pinch finds the window

    /// macOS sends a pinch to the window with the keys, the browser's,
    /// whatever is under the fingers.
    func testAPinchBegunOverTheFloatingWindowIsItsOwn() throws {
        let key = NSWindow(contentRect: NSRect(x: -30400, y: -30400, width: 900, height: 640),
                           styleMask: [.titled], backing: .buffered, defer: false)
        key.isReleasedWhenClosed = false
        defer { key.close() }
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 440, height: 247))
        web.allowsMagnification = true
        var gone: Float?
        try withFloat(flicks: false, page: web) { floater, panel, _ in
            gone = floater
            XCTAssertFalse(web.allowsMagnification, "the page in it is not what a pinch zooms")
            @MainActor func pinch(_ amount: CGFloat, _ part: NSEvent.Phase, at spot: NSPoint) -> Bool {
                let fingers = Fingers()
                fingers.kind = .magnify
                fingers.part = part
                fingers.pinch = amount
                fingers.host = key
                fingers.spot = key.convertPoint(fromScreen: spot)
                return Float.steer(fingers)
            }
            let size = panel.frame.size
            let over = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
            XCTAssertTrue(pinch(0, .began, at: over))
            XCTAssertTrue(pinch(0.25, .changed, at: over))
            XCTAssertEqual(panel.frame.size, NSSize(width: 550, height: 309))
            // Its own while the fingers are down, wherever the pointer is by then.
            XCTAssertTrue(pinch(-0.2, .changed, at: NSPoint(x: panel.frame.maxX + 300, y: over.y)))
            XCTAssertEqual(panel.frame.size, size)
            XCTAssertTrue(pinch(0, .ended, at: over))
            XCTAssertEqual(web.magnification, 1)

            // Begun anywhere else, it is the page's, as it always was.
            let sized = panel.frame
            let beside = NSPoint(x: panel.frame.maxX + 300, y: panel.frame.midY)
            XCTAssertFalse(pinch(0, .began, at: beside))
            XCTAssertFalse(pinch(0.3, .changed, at: beside))
            XCTAssertFalse(pinch(0, .ended, at: beside))
            XCTAssertEqual(panel.frame, sized)

            // Closed under the fingers: the rest of that pinch is nobody's,
            // and the page behind never gets a pinch it didn't see begin.
            let inside = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
            XCTAssertTrue(pinch(0, .began, at: inside))
            floater.drop()
            XCTAssertTrue(web.allowsMagnification)
            XCTAssertTrue(pinch(0.3, .changed, at: inside))
            XCTAssertTrue(pinch(0, .ended, at: inside))
            XCTAssertFalse(pinch(0, .began, at: inside), "a window that is gone takes none")
        }
        XCTAssertEqual(gone?.showing, false)
    }

    // MARK: -

    /// What two fingers send: a scroll or a pinch, with its phase.
    private final class Fingers: NSEvent {
        var kind: NSEvent.EventType = .scrollWheel
        var part: NSEvent.Phase = []
        var pinch: CGFloat = 0
        var host: NSWindow?
        var spot: NSPoint = .zero
        private var dx: CGFloat = 0
        private var dy: CGFloat = 0

        /// Fingers going `dx` across and `dy` up the screen.
        func move(dx: CGFloat, dy: CGFloat) {
            self.dx = dx
            self.dy = -dy
        }

        override var type: NSEvent.EventType { kind }
        override var phase: NSEvent.Phase { part }
        override var momentumPhase: NSEvent.Phase { [] }
        override var isDirectionInvertedFromDevice: Bool { true }
        override var scrollingDeltaX: CGFloat { dx }
        override var scrollingDeltaY: CGFloat { dy }
        override var magnification: CGFloat { pinch }
        override var window: NSWindow? { host }
        override var locationInWindow: NSPoint { spot }
    }

    /// Fingers down, `by` across and up the screen in `steps` moves, up.
    private func swipe(_ controls: Float.Controls, by: CGVector, steps: Int) {
        let fingers = Fingers()
        fingers.part = .began
        controls.scrollWheel(with: fingers)
        fingers.part = .changed
        fingers.move(dx: by.dx / CGFloat(steps), dy: by.dy / CGFloat(steps))
        for _ in 0..<steps { controls.scrollWheel(with: fingers) }
        fingers.part = .ended
        fingers.move(dx: 0, dy: 0)
        controls.scrollWheel(with: fingers)
    }

    /// The floating window up in the middle of the made-up screen, where
    /// nothing glides: under Reduce Motion it is simply where it goes.
    private func withFloat(
        flicks: Bool, page: NSView? = nil, picture: NSRect? = nil,
        _ body: (Float, NSWindow, Float.Controls) throws -> Void
    ) throws {
        _ = NSApplication.shared
        let was = (Float.benchAway, Float.benchScreens, Float.flicks, Motion.testReduceMotion,
                   Store.settings.object(forKey: "float.frame"))
        Store.settings.removeObject(forKey: "float.frame")
        Float.benchAway = middle
        Float.benchScreens = [screen]
        Float.flicks = flicks
        Motion.testReduceMotion = true
        let floater = Float()
        defer {
            floater.drop()
            (Float.benchAway, Float.benchScreens, Float.flicks, Motion.testReduceMotion) = (was.0, was.1, was.2, was.3)
            Store.settings.set(was.4, forKey: "float.frame")
        }
        floater.lift(page ?? NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 247)), picture: picture)
        let panel = try XCTUnwrap(floater.benchWindow)
        let controls = try XCTUnwrap(panel.contentView?.subviews.compactMap { $0 as? Float.Controls }.first)
        XCTAssertEqual(panel.frame, NSRect(origin: middle, size: NSSize(width: 440, height: 247)))
        XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(panel.frame) }, "off every screen")
        try body(floater, panel, controls)
    }
}
