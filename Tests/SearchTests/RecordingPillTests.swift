import AppKit
import SwiftUI
import XCTest
@testable import Search

/// The "is sharing your screen" pill can be dragged off what it covers, by
/// anywhere but its Stop, and comes back where it was left.
@MainActor
final class RecordingPillTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func setUp() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
    }

    private let size = CGSize(width: 300, height: 38)
    private let main = CGRect(x: 0, y: 80, width: 1440, height: 795)
    private let second = CGRect(x: 1440, y: 0, width: 1920, height: 1055)

    func testNeverMovedItRestsAtTheFootOfTheScreen() {
        let frame = PillPlace.frame(size: size, left: nil, screens: [main, second], home: main)
        XCTAssertEqual(frame, CGRect(x: 570, y: 104, width: 300, height: 38))
        // On whichever screen Lun is on.
        XCTAssertEqual(PillPlace.frame(size: size, left: nil, screens: [main, second], home: second).midX, second.midX)
    }

    func testItComesBackWhereItWasLeft() {
        // Up in a corner of the other screen: its lower edge's middle is kept.
        let left = CGPoint(x: 3000, y: 900)
        let frame = PillPlace.frame(size: size, left: left, screens: [main, second], home: main)
        XCTAssertEqual(frame, CGRect(x: 2850, y: 900, width: 300, height: 38))
        // With other words it is still centred on the same spot.
        let wide = PillPlace.frame(size: CGSize(width: 420, height: 38), left: left, screens: [main, second], home: main)
        XCTAssertEqual(wide.midX, 3000)
        XCTAssertEqual(wide.minY, 900)
    }

    func testASpotNoLongerOnAScreenIsNotFollowed() {
        // The second screen unplugged: back to the foot of the one Lun is on.
        let gone = PillPlace.frame(size: size, left: CGPoint(x: 3000, y: 900), screens: [main], home: main)
        XCTAssertEqual(gone, PillPlace.frame(size: size, left: nil, screens: [main], home: main))
        // Left against an edge, or under where the Dock is now: whole on that screen.
        let edge = PillPlace.frame(size: size, left: CGPoint(x: 1430, y: 80), screens: [main, second], home: main)
        XCTAssertEqual(edge.maxX, main.maxX)
        XCTAssertEqual(edge.minY, main.minY)
        let top = PillPlace.frame(size: size, left: CGPoint(x: 10, y: 870), screens: [main], home: main)
        XCTAssertEqual(top.minX, main.minX)
        XCTAssertEqual(top.maxY, main.maxY)
        for frame in [edge, top] { XCTAssertTrue(main.contains(frame), "\(frame)") }
    }

    func testWhereItWasLeftIsKept() throws {
        let name = "pill-\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        XCTAssertNil(PillPlace.left(in: store))
        PillPlace.leave(CGRect(x: 100, y: 500, width: 300, height: 38), in: store)
        XCTAssertEqual(PillPlace.left(in: store), CGPoint(x: 250, y: 500))
        // Something else under the key is no place at all.
        store.set("top", forKey: PillPlace.key)
        XCTAssertNil(PillPlace.left(in: store))
    }

    private func press(_ type: NSEvent.EventType, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    func testDraggedItFollowsThePointerAndRemembers() throws {
        let name = "pill-\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        let window = NSWindow(contentRect: CGRect(x: 570, y: 104, width: 300, height: 38), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let grip = PillGrip.Handle(frame: CGRect(origin: .zero, size: size))
        window.contentView?.addSubview(grip)
        var pointer = CGPoint(x: 600, y: 120)
        grip.pointer = { pointer }
        grip.store = store
        XCTAssertFalse(grip.mouseDownCanMoveWindow)
        XCTAssertTrue(grip.acceptsFirstMouse(for: nil))

        // A press let go where it was: not moved, nothing kept.
        grip.mouseDown(with: try press(.leftMouseDown, in: window))
        grip.mouseDragged(with: try press(.leftMouseDragged, in: window))
        grip.mouseUp(with: try press(.leftMouseUp, in: window))
        XCTAssertEqual(window.frame.origin, CGPoint(x: 570, y: 104))
        XCTAssertNil(PillPlace.left(in: store))

        // Taken up and to the right, in two steps.
        grip.mouseDown(with: try press(.leftMouseDown, in: window))
        pointer = CGPoint(x: 700, y: 400)
        grip.mouseDragged(with: try press(.leftMouseDragged, in: window))
        XCTAssertEqual(window.frame.origin, CGPoint(x: 670, y: 384))
        XCTAssertNil(PillPlace.left(in: store), "kept when it is let go, not on the way")
        pointer = CGPoint(x: 900, y: 600)
        grip.mouseDragged(with: try press(.leftMouseDragged, in: window))
        grip.mouseUp(with: try press(.leftMouseUp, in: window))
        XCTAssertEqual(window.frame.origin, CGPoint(x: 870, y: 584))
        XCTAssertEqual(PillPlace.left(in: store), CGPoint(x: 1020, y: 584))

        // The pointer moving with no button down moves nothing.
        pointer = CGPoint(x: 100, y: 100)
        grip.mouseDragged(with: try press(.leftMouseDragged, in: window))
        XCTAssertEqual(window.frame.origin, CGPoint(x: 870, y: 584))
    }

    /// The pill as it is drawn: a press on its words or its ground is the
    /// grip's, one on Stop is not.
    func testAnywhereButStopTakesThePill() throws {
        let indicator = RecordingIndicator()
        indicator.update([RecordingLine(id: "meet", name: "meet.google.com", what: "is sharing your screen")])
        defer { indicator.update([]) }
        var stopped: [String] = []
        indicator.onStop = { stopped.append($0) }
        let host = NSHostingView(rootView: PillView(indicator: indicator))
        let fitted = host.fittingSize
        host.frame = CGRect(origin: .zero, size: fitted)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(fitted.width, 200)

        func hit(_ x: CGFloat) -> NSView? {
            let point = CGPoint(x: x, y: fitted.height / 2)
            return host.hitTest(host.superview.map { host.convert(point, to: $0) } ?? point)
        }
        // The pill's own edge, the dot, the words, and past Stop.
        for x in [6, 17, 60, fitted.width / 2, fitted.width - 3] as [CGFloat] {
            XCTAssertTrue(hit(x) is PillGrip.Handle, "x \(x): \(String(describing: hit(x)))")
        }
        // Stop, at the trailing end, stays a button: the grip isn't there.
        XCTAssertTrue(hit(fitted.width - 30) === host, "\(String(describing: hit(fitted.width - 30)))")
        XCTAssertTrue(stopped.isEmpty)
    }

    func testTheGripIsNotThereOverAStop() {
        let grip = PillGrip.Handle(frame: CGRect(origin: .zero, size: size))
        grip.holes = [CGRect(x: 240, y: 7, width: 53, height: 24)]
        XCTAssertTrue(grip.hitTest(CGPoint(x: 100, y: 19)) === grip)
        XCTAssertTrue(grip.hitTest(CGPoint(x: 296, y: 19)) === grip, "the pill's edge past Stop")
        XCTAssertNil(grip.hitTest(CGPoint(x: 260, y: 19)))
        XCTAssertNil(grip.hitTest(CGPoint(x: 400, y: 19)), "off the pill")
    }
}
