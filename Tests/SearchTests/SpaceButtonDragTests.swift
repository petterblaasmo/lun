import AppKit
import SwiftUI
import XCTest
@testable import Search

/// A space's button dragged along its row moves the space (#247): the
/// arithmetic of where it is over and how the others stand aside
/// (SpaceCarry), and, in a window far off every screen, that a press which
/// doesn't move is still a click, a drag moves the space without ever
/// switching to it, and Escape or letting go off the row moves nothing.
@MainActor
final class SpaceButtonDragTests: XCTestCase {
    private var windows: [NSWindow] = []
    private var activationPolicy: NSApplication.ActivationPolicy?

    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func tearDown() async throws {
        for window in windows { window.contentView = nil; window.close() }
        windows.removeAll()
        if let activationPolicy { NSApp.setActivationPolicy(activationPolicy) }
        try await super.tearDown()
    }

    // MARK: - the arithmetic

    private func carry(from: Int, count: Int = 5, along: CGFloat = 0, across: CGFloat = 0) -> SpaceCarry {
        SpaceCarry(id: UUID(), from: from, count: count, step: 28, along: along, across: across)
    }

    func testAStepIsAButtonAndTheGapAfterIt() {
        XCTAssertEqual(SpaceCarry.step(length: 5 * 26 + 4 * 2, count: 5), 28)
        XCTAssertEqual(SpaceCarry.step(length: 3 * 20 + 2 * 2, count: 3), 22, "squeezed to 20 each")
        XCTAssertEqual(SpaceCarry.step(length: 0, count: 0), 0)
    }

    func testItIsOverThePlaceItsCentreIsNearest() {
        XCTAssertEqual(carry(from: 1).over, 1)
        XCTAssertEqual(carry(from: 1, along: 13).over, 1, "not yet halfway to the next")
        XCTAssertEqual(carry(from: 1, along: 15).over, 2)
        XCTAssertEqual(carry(from: 1, along: 3 * 28).over, 4, "the last of five to the front is one drag")
        XCTAssertEqual(carry(from: 4, along: -4 * 28).over, 0)
        XCTAssertEqual(carry(from: 1, along: -15).over, 0)
        XCTAssertEqual(carry(from: 1, along: -28 - 20).over, 0, "a little past the row's end is still its end")
    }

    func testLettingGoMovesItOnlyOnTheRowAndOnlyToAnotherPlace() {
        XCTAssertNil(carry(from: 2, along: 6).landing, "its own place: nothing to move")
        XCTAssertEqual(carry(from: 2, along: 30).landing, 3)
        XCTAssertEqual(carry(from: 2, along: 30, across: SpaceCarry.reach).landing, 3, "a button's height off the line")
        XCTAssertNil(carry(from: 2, along: 30, across: SpaceCarry.reach + 1).landing, "off the row")
        XCTAssertNil(carry(from: 2, along: 30, across: -SpaceCarry.reach - 1).landing)
        XCTAssertNil(carry(from: 2, along: 2 * 28 + SpaceCarry.reach + 1).landing, "past the row's end")
        XCTAssertNil(carry(from: 2, along: -2 * 28 - SpaceCarry.reach - 1).landing, "and past its start")
        XCTAssertNil(carry(from: 0, count: 1, along: 40).landing, "one space has nowhere to go")
    }

    func testTheOnesItPassesStandAsideOnePlace() {
        // Carried right, from 1 to over 3: 2 and 3 move one place left.
        let right = carry(from: 1, along: 2 * 28 + 3)
        XCTAssertEqual((0..<5).map { right.offset(of: $0) }, [0, 2 * 28 + 3, -28, -28, 0])
        // Carried left, from 3 to over 0: 0, 1 and 2 move one place right.
        let left = carry(from: 3, along: -3 * 28)
        XCTAssertEqual((0..<5).map { left.offset(of: $0) }, [28, 28, 28, -3 * 28, 0])
        // The one in hand is kept to the row.
        XCTAssertEqual(carry(from: 3, along: 28 + 20).offset(of: 3), 28)
        XCTAssertEqual(carry(from: 3, along: -3 * 28 - 20).offset(of: 3), -3 * 28)
        // Off the row, every button is back in its place.
        let off = carry(from: 1, along: 60, across: 80)
        XCTAssertEqual((0..<5).map { off.offset(of: $0) }, [0, 0, 0, 0, 0])
    }

    // MARK: - in a window

    func testAPressThatDoesNotMoveIsStillAClick() async throws {
        let (browser, window) = try await row()
        defer { browser.closeAll() }
        let order = browser.spaces.map(\.id)
        XCTAssertEqual(browser.spaceID, order[0])
        // Within the slop: a click, which goes to that space.
        let at = try centre(2, in: window)
        try await send(.leftMouseDown, at: at, in: window)
        try await send(.leftMouseDragged, at: NSPoint(x: at.x + SpaceCarry.slop - 2, y: at.y), in: window)
        try await send(.leftMouseUp, at: NSPoint(x: at.x + SpaceCarry.slop - 2, y: at.y), in: window)
        try await settle()
        XCTAssertEqual(browser.spaceID, order[2], "a click still switches")
        XCTAssertEqual(browser.spaces.map(\.id), order, "and moves nothing")
        XCTAssertEqual(CarryGuard.count, 0)
    }

    func testADragMovesTheSpaceAndNeverSwitches() async throws {
        let (browser, window) = try await row()
        defer { browser.closeAll() }
        let order = browser.spaces.map(\.id)
        // The last to the front, in one drag.
        let last = order.count - 1
        try await drag(from: try centre(last, in: window), to: try centre(0, in: window), in: window)
        var wanted = moved(order, from: last, to: 0)
        XCTAssertEqual(browser.spaces.map(\.id), wanted)
        XCTAssertEqual(browser.spaceID, order[0], "dragging another space's button doesn't go to it")
        // The space on screen, dragged: still the one on screen.
        try await drag(from: try centre(1, in: window), to: try centre(2, in: window), in: window)
        wanted = moved(wanted, from: 1, to: 2)
        XCTAssertEqual(browser.spaces.map(\.id), wanted)
        XCTAssertEqual(browser.spaceID, order[0])
        XCTAssertEqual(CarryGuard.count, 0)
    }

    func testLettingGoOffTheRowPutsItBack() async throws {
        let (browser, window) = try await row()
        defer { browser.closeAll() }
        let order = browser.spaces.map(\.id)
        let from = try centre(3, in: window), over = try centre(1, in: window)
        try await drag(from: from, through: [over, NSPoint(x: over.x, y: over.y + SpaceCarry.reach + 20)], in: window)
        XCTAssertEqual(browser.spaces.map(\.id), order)
        XCTAssertEqual(browser.spaceID, order[0])
        XCTAssertEqual(CarryGuard.count, 0)
    }

    func testEscapePutsItBackAndTheReleaseMovesNothing() async throws {
        let (browser, window) = try await row()
        defer { browser.closeAll() }
        let order = browser.spaces.map(\.id)
        let from = try centre(3, in: window), over = try centre(1, in: window)
        try await send(.leftMouseDown, at: from, in: window)
        for step in 1...14 {
            try await send(.leftMouseDragged, at: NSPoint(x: from.x + (over.x - from.x) * CGFloat(step) / 14, y: from.y), in: window)
        }
        XCTAssertEqual(CarryGuard.count, 1, "in hand")
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                    timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                                    charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.sendEvent(escape)
        try await settle()
        XCTAssertEqual(CarryGuard.count, 0, "put back")
        // Still held, and carried on: nothing is picked up again.
        try await send(.leftMouseDragged, at: try centre(0, in: window), in: window)
        try await send(.leftMouseUp, at: try centre(0, in: window), in: window)
        try await settle()
        XCTAssertEqual(browser.spaces.map(\.id), order)
        XCTAssertEqual(browser.spaceID, order[0])
        XCTAssertEqual(CarryGuard.count, 0)
    }

    func testTheRowStoodOnItsEndIsDraggedUpAndDown() async throws {
        let (browser, window) = try await row(vertical: true)
        defer { browser.closeAll() }
        let order = browser.spaces.map(\.id)
        try await drag(from: try centre(0, in: window, vertical: true), to: try centre(2, in: window, vertical: true), in: window)
        XCTAssertEqual(browser.spaces.map(\.id), moved(order, from: 0, to: 2))
        XCTAssertEqual(browser.spaceID, order[0])
    }

    // MARK: - helpers

    /// The order with one of them taken to another place.
    private func moved(_ order: [UUID], from: Int, to: Int) -> [UUID] {
        var order = order
        order.insert(order.remove(at: from), at: to)
        return order
    }

    /// Four spaces or more (the test world may hold some already), the
    /// first on screen, and their buttons in a window of their own.
    private func row(vertical: Bool = false) async throws -> (Browser, NSWindow) {
        _ = NSApplication.shared
        activationPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        browser.prefs.usesSpaces = true
        while browser.spaces.count < 4 { browser.addSpace(named: "Space \(browser.spaces.count)") }
        browser.switchSpace(to: browser.spaces[0].id)
        let size = vertical ? NSSize(width: 200, height: 600) : NSSize(width: 600, height: 200)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SpaceButtons(browser: browser, vertical: vertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity))
        window.orderFrontRegardless()
        XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(window.frame) }, "never on a screen")
        windows.append(window)
        try await settle()
        return (browser, window)
    }

    /// The middle of the button now in place `index`, in the window: found
    /// by the right-click catcher each button has over it.
    private func centre(_ index: Int, in window: NSWindow, vertical: Bool = false) throws -> NSPoint {
        func catchers(in view: NSView) -> [RightClick.Catcher] {
            (view as? RightClick.Catcher).map { [$0] } ?? [] + view.subviews.flatMap(catchers(in:))
        }
        let frames = catchers(in: try XCTUnwrap(window.contentView)).map { $0.convert($0.bounds, to: nil) }
            // From the top down, the window's coordinates running up.
            .sorted { vertical ? $0.midY > $1.midY : $0.midX < $1.midX }
        XCTAssertGreaterThanOrEqual(frames.count, 4)
        return NSPoint(x: frames[index].midX, y: frames[index].midY)
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(300))
    }

    private func drag(from start: NSPoint, to end: NSPoint, in window: NSWindow) async throws {
        try await drag(from: start, through: [end], in: window)
    }

    /// Not held still long, or a tooltip ends it (PinDragTests.drag).
    private func drag(from start: NSPoint, through points: [NSPoint], in window: NSWindow) async throws {
        try await send(.leftMouseDown, at: start, in: window)
        var last = start
        for target in points {
            let steps = max(1, Int((hypot(target.x - last.x, target.y - last.y) / 4).rounded(.up)))
            for step in 1...steps {
                let f = CGFloat(step) / CGFloat(steps)
                try await send(.leftMouseDragged, at: NSPoint(x: last.x + (target.x - last.x) * f, y: last.y + (target.y - last.y) * f), in: window)
            }
            last = target
        }
        try await Task.sleep(for: .milliseconds(120))
        try await send(.leftMouseUp, at: last, in: window)
        try await settle()
    }

    private func send(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) async throws {
        NSApp.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        )))
        try await Task.sleep(for: .milliseconds(30))
    }
}
