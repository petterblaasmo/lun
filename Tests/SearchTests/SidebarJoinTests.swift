import AppKit
import SwiftUI
import XCTest
@testable import Search

/// A tab carried down the column and held lying across another makes a
/// split of the two (#22). Nothing about moving a tab changes for it: the
/// rows make way where they did (Carried.slot is not asked anything new),
/// and only a hand at rest on the middle third of the way between two
/// resting places is shown a split, and makes one by letting go. Hosted as
/// SidebarSplitDragTests is, far off every screen.
@MainActor
final class SidebarJoinTests: XCTestCase {
    private var browsers: [Browser] = []
    private var windows: [NSWindow] = []
    private var restorePreferences: (() -> Void)?
    private var activationPolicy: NSApplication.ActivationPolicy?

    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func tearDown() async throws {
        TabDrag.testPointer = nil
        CarryGuard.endAll()
        for window in windows { window.contentView = nil; window.close() }
        for browser in browsers { browser.window = nil; browser.closeAll() }
        restorePreferences?()
        if let activationPolicy { NSApp.setActivationPolicy(activationPolicy) }
        windows.removeAll()
        browsers.removeAll()
        try await Task.sleep(for: .milliseconds(250))
        try await super.tearDown()
    }

    // MARK: - where along the way

    /// Rows of 30 with their gaps: a neighbour makes way 15 along.
    private let even: [CGFloat] = [30, 30, 30, 30]

    func testRoundARestingPlaceNothingIsLainAcross() {
        XCTAssertNil(Carried.across(at: 30, carrying: 1, in: even), "where it was picked up")
        XCTAssertNil(Carried.across(at: 30 + 9, carrying: 1, in: even), "the first two thirds of the way down move it and nothing else")
        XCTAssertNil(Carried.across(at: 30 - 9, carrying: 1, in: even), "and of the way up")
        XCTAssertNil(Carried.across(at: 60 + 2, carrying: 1, in: even), "a place on, at rest there")
    }

    func testTheLastThirdOfTheWayLiesAcrossTheNeighbour() throws {
        // Among the others (one, three, four): three is place 1, one is 0.
        let down = try XCTUnwrap(Carried.across(at: 30 + 11, carrying: 1, in: even))
        XCTAssertEqual(down.place, 1)
        XCTAssertTrue(down.after, "the one after it")
        let up = try XCTUnwrap(Carried.across(at: 30 - 11, carrying: 1, in: even))
        XCTAssertEqual(up.place, 0)
        XCTAssertFalse(up.after)
    }

    func testTheSameNeighbourOnceItHasMadeWay() throws {
        // 16 down: three has made way and stands before it now, half under
        // it still. Whether or not the row has been drawn again since.
        let moved = try XCTUnwrap(Carried.across(at: 30 + 16, carrying: 1, in: even))
        XCTAssertEqual(moved.place, 1)
        XCTAssertFalse(moved.after, "before it now")
        let redrawn = try XCTUnwrap(Carried.across(at: 30 + 16, carrying: 2, in: even))
        XCTAssertEqual(redrawn.place, 1, "the same place among the others")
        XCTAssertNil(Carried.across(at: 30 + 21, carrying: 2, in: even), "and let go of a third of the way on")
    }

    func testTwoThirdsOfTheWayIsForMovingAlone() {
        // Every half point of a tab's way down two places: a third of them
        // lie across a neighbour, round where each makes way.
        var across = 0
        for edge in stride(from: CGFloat(30), to: 90, by: 0.5) {
            if Carried.across(at: edge, carrying: 1, in: even) != nil { across += 1 }
        }
        XCTAssertEqual(Double(across) / 120, 1.0 / 3, accuracy: 0.02, "two thirds of the way is for moving alone")
    }

    func testNothingPastTheEnds() {
        XCTAssertNil(Carried.across(at: -40, carrying: 0, in: even), "above the first")
        XCTAssertNil(Carried.across(at: 200, carrying: 3, in: even), "below the last")
        XCTAssertNil(Carried.across(at: 0, carrying: 7, in: even), "no such place")
    }

    func testASplitsLinesAreReachedAtTheirOwnLength() throws {
        // one, a split of two lines, four: four carried up. The split makes
        // way 29 up; the last third of that way lies across it.
        let steps: [CGFloat] = [30, 58, 30]
        XCTAssertNil(Carried.across(at: 88 - 18, carrying: 2, in: steps))
        let found = try XCTUnwrap(Carried.across(at: 88 - 21, carrying: 2, in: steps))
        XCTAssertEqual(found.place, 1)
        XCTAssertFalse(found.after)
    }

    func testOneShownIsKeptALittleFurtherBack() {
        XCTAssertNil(Carried.across(at: 30 + 8, carrying: 1, in: even))
        XCTAssertNotNil(Carried.across(at: 30 + 8, carrying: 1, in: even, holding: 1), "four points of slack")
        XCTAssertNil(Carried.across(at: 30 + 5, carrying: 1, in: even, holding: 1))
        XCTAssertNil(Carried.across(at: 30 - 8, carrying: 1, in: even, holding: 1), "the other neighbour has none")
    }

    // MARK: - the real gesture

    // "one", "two", "three", "four" down the column; "three" is carried.

    func testHeldAcrossAnotherTabThenLetGoSplitsTheTwo() async throws {
        let (browser, t, window) = try await setUp()
        try await carry(row: 2, up: reach * 0.8, in: window)
        XCTAssertNil(TabJoin.shared.shown, "nothing shown to a hand still on its way")
        try await rest()
        XCTAssertEqual(TabJoin.shared.shown?.targetID, t[1].id, "the split is shown on the tab it lies across")
        XCTAssertEqual(TabJoin.shared.shown?.sourceID, t[2].id)
        XCTAssertEqual(browser.tabs.map(\.id), t.map(\.id), "and nothing has moved")
        try await letGo(in: window)
        let pair = try XCTUnwrap(browser.split(for: t[2]), "a split")
        XCTAssertEqual(pair.tabs, [t[1].id, t[2].id], "the carried tab after the one it was let go on")
        XCTAssertEqual(browser.tabs.map(\.id), t.map(\.id), "where that one stands")
        XCTAssertEqual(browser.activeID, t[2].id)
        XCTAssertNil(TabJoin.shared.shown, "and the hint is gone")
    }

    func testJustAfterTheOtherMadeWayItIsStillThatOne() async throws {
        let (browser, t, window) = try await setUp()
        try await carry(row: 2, up: reach * 1.2, in: window)
        XCTAssertEqual(browser.tabs.map(\.id), [t[0], t[2], t[1], t[3]].map(\.id), "made way at half, as always")
        try await rest()
        XCTAssertEqual(TabJoin.shared.shown?.targetID, t[1].id)
        try await letGo(in: window)
        XCTAssertEqual(browser.split(for: t[2])?.tabs, [t[1].id, t[2].id])
        XCTAssertEqual(browser.tabs.map(\.id), t.map(\.id))
    }

    func testCarriedPastWithoutStoppingOnlyMovesIt() async throws {
        let (browser, t, window) = try await setUp()
        try await carry(row: 2, up: reach * 1.2, in: window)
        try await letGo(in: window)
        XCTAssertTrue(browser.splits.isEmpty, "let go at once: no split")
        XCTAssertEqual(browser.tabs.map(\.id), [t[0], t[2], t[1], t[3]].map(\.id), "moved a place, as it always did")
    }

    func testHeldAtAPlaceOfItsOwnOnlyMovesIt() async throws {
        let (browser, t, window) = try await setUp()
        try await carry(row: 2, up: reach * 2, in: window)
        try await rest()
        XCTAssertNil(TabJoin.shared.shown, "at rest a whole place up: nothing is lain across")
        try await letGo(in: window)
        XCTAssertTrue(browser.splits.isEmpty)
        XCTAssertEqual(browser.tabs.map(\.id), [t[0], t[2], t[1], t[3]].map(\.id))
    }

    func testMovingOnLetsGoOfIt() async throws {
        let (browser, t, window) = try await setUp()
        try await carry(row: 2, up: reach * 0.8, in: window)
        try await rest()
        XCTAssertNotNil(TabJoin.shared.shown)
        try await carry(on: reach * 1.2, in: window)
        XCTAssertNil(TabJoin.shared.shown, "carried on to a place of its own")
        try await letGo(in: window)
        XCTAssertTrue(browser.splits.isEmpty)
        XCTAssertEqual(browser.tabs.map(\.id), [t[0], t[2], t[1], t[3]].map(\.id))
    }

    func testCalledOffShowsAndSplitsNothing() async throws {
        let (browser, t, window) = try await setUp()
        try await carry(row: 2, up: reach * 0.8, in: window)
        try await rest()
        XCTAssertNotNil(TabJoin.shared.shown)
        // Escape, with the button down (TabDrag's own monitor asks the Mac
        // whether it is, which a test's events never make true).
        TabDrag.shared.cancel()
        try await settle()
        XCTAssertNil(TabJoin.shared.shown)
        try await letGo(in: window)
        XCTAssertTrue(browser.splits.isEmpty)
        XCTAssertEqual(browser.tabs.map(\.id), t.map(\.id))
    }

    func testHeldAcrossASplitJoinsIt() async throws {
        let (browser, t, window) = try await setUp()
        browser.pair(t[1], with: t[0], onLeft: false)
        try await settle()
        // The split stands as two lines; "three" is the row under them.
        let line = browser.prefs.sideRow
        let start = NSPoint(x: 70, y: window.frame.height - Metrics.strip - (2 * line + 2) - line / 2)
        try await carry(from: start, up: (2 * line + 2) / 2 * 0.8, in: window)
        try await rest()
        XCTAssertEqual(TabJoin.shared.shown?.targetID, t[1].id, "beside the page of it that is nearest")
        try await letGo(in: window)
        XCTAssertEqual(browser.split(for: t[2])?.tabs, [t[0].id, t[1].id, t[2].id])
    }

    func testAPairsHalfIsNotJoinedButComesApartAsBefore() async throws {
        let (browser, t, window) = try await setUp()
        browser.pair(t[3], with: t[2], onLeft: false)
        try await settle()
        // "three" is the first line of the split now, still the third row.
        try await carry(row: 2, up: reach * 0.8, in: window)
        try await rest()
        XCTAssertNil(TabJoin.shared.shown, "a split's page held across a tab is not put beside it")
        try await letGo(in: window)
        XCTAssertNotEqual(browser.split(for: t[2])?.tabs.contains(t[1].id), true)
    }

    /// The column with the split shown, and after, for looking at by eye:
    /// only when SIDEBAR_JOIN_SHOTS names a folder.
    func testLooks() async throws {
        guard let folder = ProcessInfo.processInfo.environment["SIDEBAR_JOIN_SHOTS"] else { return }
        for dark in [false, true] {
            let (_, _, window) = try await setUp()
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            try await settle()
            let look = dark ? "dark" : "light"
            func shoot(_ name: String) throws {
                guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(folder)/join-\(name)-\(look).png"))
            }
            try shoot("before")
            try await carry(row: 2, up: reach * 0.8, in: window)
            try shoot("carried")
            try await rest()
            try shoot("shown")
            try await letGo(in: window)
            try await settle()
            try shoot("after")
        }
    }

    // MARK: - helpers

    /// How far a row is carried before its neighbour makes way: half a
    /// row and its gap.
    private var reach: CGFloat { (Shared.prefs.sideRow + 2) / 2 }
    private var hand = NSPoint.zero

    private func setUp() async throws -> (Browser, [Search.Tab], NSWindow) {
        _ = NSApplication.shared
        activationPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.prohibited)
        let prefs = Shared.prefs
        let previous = (prefs.sidebar, prefs.usesTabGroups, prefs.splitView, prefs.listsPins, prefs.roomyTabs, prefs.addressLine)
        restorePreferences = {
            (prefs.sidebar, prefs.usesTabGroups, prefs.splitView, prefs.listsPins, prefs.roomyTabs, prefs.addressLine) = previous
        }
        let browser = Browser(record: WindowRecord())
        browsers.append(browser)
        browser.prefs.sidebar = true
        // The address bar above the rows would move every row this presses.
        browser.prefs.addressLine = false
        browser.prefs.usesTabGroups = false
        browser.prefs.splitView = true
        browser.prefs.listsPins = false
        browser.prefs.roomyTabs = false
        for word in ["one", "two", "three", "four"] {
            if browser.tabs.last?.isBlank == false { browser.newTab() }
            browser.tabs.last?.restore(url: URL(string: "about:blank#\(word)")!, title: word)
        }
        let t = browser.tabs
        browser.select(t[0])
        let side = browser.prefs.sideWidth
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: side, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SideBar(browser: browser, prefs: browser.prefs).frame(width: side))
        window.orderFrontRegardless()
        XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(window.frame) }, "never on a screen")
        windows.append(window)
        browser.window = window
        try await settle()
        return (browser, t, window)
    }

    /// The middle of the row at `index`, counted from the top.
    private func rowPoint(_ index: Int, in window: NSWindow) -> NSPoint {
        let line = Shared.prefs.sideRow
        return NSPoint(x: 70, y: window.frame.height - Metrics.strip - CGFloat(index) * (line + 2) - line / 2)
    }

    private func carry(row: Int, up distance: CGFloat, in window: NSWindow) async throws {
        try await carry(from: rowPoint(row, in: window), up: distance, in: window)
    }

    /// Down on a row and up the column by `distance`, two points a move.
    private func carry(from start: NSPoint, up distance: CGFloat, in window: NSWindow) async throws {
        hand = start
        try await send(.leftMouseDown, at: start, in: window)
        // The press opens the tab on the main queue: wait for it, as a
        // hand would, before carrying.
        try await Task.sleep(for: .milliseconds(150))
        try await carry(on: distance, in: window)
    }

    /// The hand, already down, `distance` further up.
    private func carry(on distance: CGFloat, in window: NSWindow) async throws {
        let end = hand.y + distance
        while hand.y < end {
            hand.y = min(end, hand.y + 2)
            try await send(.leftMouseDragged, at: hand, in: window)
        }
    }

    private func letGo(in window: NSWindow) async throws {
        try await send(.leftMouseUp, at: hand, in: window)
        try await settle()
    }

    /// Still for longer than a split shown on a row waits for.
    private func rest() async throws {
        try await Task.sleep(for: .milliseconds(Int(TabDrag.parting * 1000) + 250))
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(250))
    }

    private func send(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) async throws {
        TabDrag.testPointer = window.convertToScreen(NSRect(origin: point, size: .zero)).origin
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        ))
        window.sendEvent(event)
        try await Task.sleep(for: .milliseconds(30))
    }
}
