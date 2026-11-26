import AppKit
import SwiftUI
import XCTest
@testable import Search

/// The column's resize edge is a view of AppKit's own: the left-right arrows
/// are its cursor rectangle and are shown again at every step of a pull, so
/// they stay until the edge is let go.
@MainActor
final class EdgeHandleTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func setUp() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
    }

    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows { window.contentView = nil; window.close() }
        windows = []
    }

    /// What the edge told its owner, in order.
    private final class Told {
        var hover: [Bool] = []
        var pulled: [CGFloat] = []
        var ended = 0
        var twice = 0
        var arrows = 0
    }

    private func makeEdge() -> (EdgeHandle.Edge, Told, NSWindow) {
        let told = Told()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 200), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        windows.append(window)
        let edge = EdgeHandle.Edge(frame: CGRect(x: 240, y: 0, width: 9, height: 200))
        edge.handle = EdgeHandle(hover: { told.hover.append($0) }, pulled: { told.pulled.append($0) },
                                 ended: { told.ended += 1 }, twice: { told.twice += 1 })
        edge.arrows = { told.arrows += 1 }
        window.contentView?.addSubview(edge)
        return (edge, told, window)
    }

    /// A mouse event at a point of the window: on the edge unless said.
    private func event(_ type: NSEvent.EventType, in window: NSWindow, at x: CGFloat = 244, clicks: Int = 1) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 100), modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1))
    }

    private func entered(_ edge: EdgeHandle.Edge, _ type: NSEvent.EventType) throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                             windowNumber: edge.window?.windowNumber ?? 0, context: nil, eventNumber: 0,
                                             trackingNumber: 0, userData: nil))
    }

    func testAPullSaysHowFarAndKeepsTheArrows() throws {
        let (edge, told, window) = makeEdge()
        var pointer: CGFloat = 500
        edge.pointer = { pointer }

        edge.mouseDown(with: try event(.leftMouseDown, in: window))
        // Under a point: a shaky click, not a pull.
        pointer = 500.5
        edge.mouseDragged(with: try event(.leftMouseDragged, in: window))
        XCTAssertTrue(told.pulled.isEmpty)
        XCTAssertFalse(edge.pulling)

        // Wider, then back past where it started: from the press each time.
        for x in [512, 560, 470] as [CGFloat] {
            pointer = x
            edge.mouseDragged(with: try event(.leftMouseDragged, in: window, at: x - 256))
        }
        XCTAssertEqual(told.pulled, [12, 60, -30])
        XCTAssertTrue(edge.pulling)
        // The arrows are shown again at every step, wherever the pointer is.
        XCTAssertEqual(told.arrows, 3)

        edge.mouseUp(with: try event(.leftMouseUp, in: window, at: 214))
        XCTAssertEqual(told.ended, 1)
        XCTAssertEqual(told.twice, 0)
        XCTAssertFalse(edge.pulling)
        // Let go off the edge: no longer over it.
        XCTAssertEqual(told.hover, [false])

        // The pointer moving with no button down pulls nothing.
        pointer = 900
        edge.mouseDragged(with: try event(.leftMouseDragged, in: window))
        edge.mouseUp(with: try event(.leftMouseUp, in: window))
        XCTAssertEqual(told.pulled.count, 3)
        XCTAssertEqual(told.ended, 1)
    }

    func testHeldTheEdgeStaysLitThoughThePointerLeavesIt() throws {
        let (edge, told, window) = makeEdge()
        var pointer: CGFloat = 500
        edge.pointer = { pointer }

        edge.mouseEntered(with: try entered(edge, .mouseEntered))
        edge.mouseExited(with: try entered(edge, .mouseExited))
        XCTAssertEqual(told.hover, [true, false])

        edge.mouseEntered(with: try entered(edge, .mouseEntered))
        edge.mouseDown(with: try event(.leftMouseDown, in: window))
        pointer = 540
        edge.mouseDragged(with: try event(.leftMouseDragged, in: window))
        // The pointer runs ahead of the edge: still held, still lit.
        edge.mouseExited(with: try entered(edge, .mouseExited))
        XCTAssertEqual(told.hover, [true, false, true])
        // Let go back on it: over it still.
        edge.mouseUp(with: try event(.leftMouseUp, in: window))
        XCTAssertEqual(told.hover, [true, false, true])
        XCTAssertEqual(told.ended, 1)
    }

    func testADoubleClickIsNotAPull() throws {
        let (edge, told, window) = makeEdge()
        edge.pointer = { 500 }
        edge.mouseDown(with: try event(.leftMouseDown, in: window))
        edge.mouseUp(with: try event(.leftMouseUp, in: window))
        XCTAssertEqual(told.twice, 0, "one click does nothing")
        edge.mouseDown(with: try event(.leftMouseDown, in: window, clicks: 2))
        edge.mouseUp(with: try event(.leftMouseUp, in: window, clicks: 2))
        XCTAssertEqual(told.twice, 1)
        XCTAssertEqual(told.ended, 0)
        XCTAssertTrue(told.pulled.isEmpty)
    }

    func testTheArrowsAreTheEdgesOwnToShow() throws {
        let (edge, told, _) = makeEdge()
        XCTAssertFalse(edge.mouseDownCanMoveWindow)
        XCTAssertTrue(edge.acceptsFirstMouse(for: nil))
        // Asked which pointer to show over it, it answers itself.
        edge.cursorUpdate(with: try entered(edge, .cursorUpdate))
        XCTAssertEqual(told.arrows, 1)
        edge.updateTrackingAreas()
        XCTAssertEqual(edge.trackingAreas.count, 1)
        XCTAssertTrue(edge.trackingAreas[0].options.contains([.cursorUpdate, .mouseEnteredAndExited]))
    }

    /// The column as drawn: the handle lies over its inner edge, and a
    /// press there is the handle's.
    func testTheColumnsEdgeIsTheHandle() async throws {
        let browser = Browser(record: WindowRecord())
        browser.welcoming = false
        let prefs = browser.prefs
        let was = (prefs.sidebar, prefs.sideIcons, prefs.sidePosition, prefs.narrowed)
        defer {
            (prefs.sidebar, prefs.sideIcons, prefs.sidePosition, prefs.narrowed) = was
            browser.closeAll()
        }
        (prefs.sidebar, prefs.sideIcons, prefs.sidePosition, prefs.narrowed) = (true, false, .left, false)
        let width = prefs.columnWidth
        let host = NSHostingView(rootView: SideBar(browser: browser, prefs: prefs).frame(width: width, height: 360))
        host.frame = CGRect(x: 0, y: 0, width: width, height: 360)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        windows.append(window)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()

        func find(_ view: NSView) -> EdgeHandle.Edge? {
            (view as? EdgeHandle.Edge) ?? view.subviews.lazy.compactMap(find).first
        }
        let edge = try XCTUnwrap(find(host), "the column has its edge")
        let frame = edge.convert(edge.bounds, to: host)
        XCTAssertEqual(frame.width, 9)
        XCTAssertEqual(frame.maxX, width, accuracy: 0.5, "at the column's inner edge")
        XCTAssertEqual(frame.height, 360, accuracy: 0.5)
        let point = CGPoint(x: frame.midX, y: 180)
        XCTAssertTrue(host.hitTest(host.superview.map { host.convert(point, to: $0) } ?? point) === edge)
        XCTAssertFalse(window.isVisible, "never ordered in")
    }

    /// The pointer over the column's edge is no longer pushed and popped by
    /// a SwiftUI hover, which is what lost the arrows mid-pull.
    func testTheColumnDoesNotPushTheCursorItself() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let side = try String(contentsOf: root.appendingPathComponent("Sources/Search/Side.swift"), encoding: .utf8)
        XCTAssertFalse(side.contains("NSCursor.resizeLeftRight.push()"))
        XCTAssertTrue(side.contains("EdgeHandle("))
    }
}
