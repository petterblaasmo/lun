import AppKit
import SwiftUI
import XCTest
@testable import Search

/// A row that gives under the press (View.pressed) still does its thing on
/// the click, once: the press is watched by a gesture of its own beside the
/// tap, and one that swallowed the click would leave a list's rows dead. A
/// real mouse down and up, sent to a window that is never shown.
@MainActor
final class PressedRowTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    private final class Count: ObservableObject {
        var clicks = 0
    }

    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.close() }
        windows = []
        try await super.tearDown()
    }

    private func window(_ view: some View) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 200, height: 80), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view.frame(width: 200, height: 80))
        window.orderFrontRegardless()
        window.contentView?.layoutSubtreeIfNeeded()
        windows.append(window)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        return window
    }

    private func click(at point: NSPoint, in window: NSWindow) throws {
        let start = ProcessInfo.processInfo.systemUptime
        for (type, after) in [(NSEvent.EventType.leftMouseDown, 0.0), (.leftMouseUp, 0.05)] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: start + after,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1))
            window.sendEvent(event)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
    }

    func testARowThatGivesStillTakesItsClick() throws {
        let count = Count()
        let row = HStack { Text("Reload"); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .pressed { count.clicks += 1 }
        let window = window(row)
        try click(at: NSPoint(x: 100, y: 40), in: window)
        XCTAssertEqual(count.clicks, 1, "One click, done once")
        try click(at: NSPoint(x: 100, y: 40), in: window)
        XCTAssertEqual(count.clicks, 2)
    }

    /// The row's own buttons keep their clicks: a press on one is not a
    /// press on the row.
    func testAButtonInTheRowTakesItsOwnClick() throws {
        let count = Count()
        let inner = Count()
        let row = HStack(spacing: 0) {
            Color.clear
            Button { inner.clicks += 1 } label: { Color.clear.frame(width: 60, height: 80).contentShape(Rectangle()) }
                .buttonStyle(Gives())
        }
        .contentShape(Rectangle())
        .pressed { count.clicks += 1 }
        let window = window(row)
        // The window's points start at its foot; the button is its last 60 across.
        try click(at: NSPoint(x: 170, y: 40), in: window)
        XCTAssertEqual(inner.clicks, 1, "The button's click")
        XCTAssertEqual(count.clicks, 0, "and not the row's")
        try click(at: NSPoint(x: 40, y: 40), in: window)
        XCTAssertEqual(count.clicks, 1)
        XCTAssertEqual(inner.clicks, 1)
    }
}
