import AppKit
import SwiftUI
import XCTest
@testable import Search

/// Back, forward and the address down from the top edge while the column
/// is folded away (#48): where the pointer brings the card from, where it
/// keeps it, and the waits either way. The card in a window, and when it
/// may come at all, is Tests/edge_bar.py, in a hidden copy of the app.
@MainActor
final class EdgeBarTests: XCTestCase {
    private let window = CGSize(width: 1100, height: 700)
    private var browsers: [Browser] = []
    private var windows: [NSWindow] = []
    private var restorePreferences: (() -> Void)?
    private var activationPolicy: NSApplication.ActivationPolicy?

    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func tearDown() async throws {
        for window in windows { window.contentView = nil; window.close() }
        for browser in browsers { browser.window = nil; browser.closeAll() }
        restorePreferences?()
        if let activationPolicy { NSApp.setActivationPolicy(activationPolicy) }
        windows.removeAll()
        browsers.removeAll()
        try await super.tearDown()
    }

    // MARK: - where

    func testItStandsInTheMiddleOfTheTop() {
        let frame = EdgeBar.frame(in: window)
        XCTAssertEqual(frame.midX, 550, accuracy: 0.5)
        XCTAssertEqual(frame.width, EdgeBar.width)
        XCTAssertEqual(frame.minY, EdgeBar.top)
        let narrow = EdgeBar.frame(in: CGSize(width: 320, height: 500))
        XCTAssertEqual(narrow.width, 320 - 2 * EdgeBar.margin, "a narrow window's, less the air at its sides")
        XCTAssertEqual(narrow.midX, 160, accuracy: 0.5)
        XCTAssertEqual(EdgeBar.frame(in: CGSize(width: 10, height: 500)).width, 0, "never less than nothing")
    }

    func testOnlyTheEdgeOverItsPlaceBringsIt() {
        let frame = EdgeBar.frame(in: window)
        XCTAssertTrue(EdgeBar.brings(CGPoint(x: 550, y: 0), in: window), "against the edge")
        XCTAssertTrue(EdgeBar.brings(CGPoint(x: frame.minX, y: Fold.edge - 1), in: window))
        XCTAssertFalse(EdgeBar.brings(CGPoint(x: 550, y: Fold.edge), in: window), "as near the edge as the column's is")
        XCTAssertFalse(EdgeBar.brings(CGPoint(x: frame.minX - 1, y: 2), in: window), "the edge beside it is on the way elsewhere")
        XCTAssertFalse(EdgeBar.brings(CGPoint(x: frame.maxX + 1, y: 2), in: window))
        XCTAssertFalse(EdgeBar.brings(CGPoint(x: 3, y: 2), in: window), "the corner is the column's")
        XCTAssertFalse(EdgeBar.brings(CGPoint(x: 550, y: -4), in: window), "above the window")
    }

    func testWhereThePointerKeepsIt() {
        let frame = EdgeBar.frame(in: window)
        XCTAssertTrue(EdgeBar.holds(CGPoint(x: frame.midX, y: frame.midY), in: window), "on it")
        XCTAssertTrue(EdgeBar.holds(CGPoint(x: frame.midX, y: 1), in: window), "between it and the edge it came from")
        XCTAssertTrue(EdgeBar.holds(CGPoint(x: frame.minX - EdgeBar.slack, y: frame.maxY + EdgeBar.slack), in: window), "a little round it")
        XCTAssertFalse(EdgeBar.holds(CGPoint(x: frame.minX - EdgeBar.slack - 1, y: frame.midY), in: window))
        XCTAssertFalse(EdgeBar.holds(CGPoint(x: frame.midX, y: frame.maxY + EdgeBar.slack + 1), in: window))
    }

    // MARK: - when

    func testItComesOnceThePointerHasRestedOnTheEdge() async throws {
        let state = EdgeBarState()
        state.pointer(at: CGPoint(x: 550, y: 2), in: window, pressed: false)
        XCTAssertFalse(state.shown, "not at once: the edge is on the way to the menu bar")
        try await wait(EdgeBarState.dwell + 0.15)
        XCTAssertTrue(state.shown)
    }

    func testAPointerCrossingTheEdgeBringsNothing() async throws {
        let state = EdgeBarState()
        state.pointer(at: CGPoint(x: 550, y: 2), in: window, pressed: false)
        state.pointer(at: CGPoint(x: 550, y: 90), in: window, pressed: false)
        try await wait(EdgeBarState.dwell + 0.15)
        XCTAssertFalse(state.shown, "on into the page")
        state.pointer(at: CGPoint(x: 550, y: 2), in: window, pressed: false)
        state.pointer(at: nil, in: window, pressed: false)
        try await wait(EdgeBarState.dwell + 0.15)
        XCTAssertFalse(state.shown, "and on out of the window")
    }

    func testNothingComesWithAButtonDown() async throws {
        let state = EdgeBarState()
        state.pointer(at: CGPoint(x: 550, y: 2), in: window, pressed: true)
        try await wait(EdgeBarState.dwell + 0.15)
        XCTAssertFalse(state.shown, "a tab or the window itself is on its way across")
    }

    func testItStaysUnderThePointerAndGoesAMomentAfter() async throws {
        let state = EdgeBarState()
        let frame = EdgeBar.frame(in: window)
        state.pointer(at: CGPoint(x: 550, y: 2), in: window, pressed: false)
        try await wait(EdgeBarState.dwell + 0.15)
        state.pointer(at: CGPoint(x: frame.midX, y: frame.midY), in: window, pressed: false)
        try await wait(EdgeBarState.grace + 0.15)
        XCTAssertTrue(state.shown, "on it for however long")
        state.pointer(at: CGPoint(x: 100, y: 400), in: window, pressed: false)
        XCTAssertTrue(state.shown, "left: not gone at once")
        state.pointer(at: CGPoint(x: frame.midX, y: frame.midY), in: window, pressed: false)
        try await wait(EdgeBarState.grace + 0.15)
        XCTAssertTrue(state.shown, "back in time, it stays")
        state.pointer(at: nil, in: window, pressed: false)
        try await wait(EdgeBarState.grace + 0.15)
        XCTAssertFalse(state.shown, "out of the window and not back: gone")
    }

    func testPutAwayIsAtOnceAndCallsOffWhatWasComing() async throws {
        let state = EdgeBarState()
        state.pointer(at: CGPoint(x: 550, y: 2), in: window, pressed: false)
        state.putAway()
        try await wait(EdgeBarState.dwell + 0.15)
        XCTAssertFalse(state.shown, "called off before it came")
        state.pointer(at: CGPoint(x: 550, y: 2), in: window, pressed: false)
        try await wait(EdgeBarState.dwell + 0.15)
        XCTAssertTrue(state.shown)
        state.putAway()
        XCTAssertFalse(state.shown)
    }

    func testTheWaitIsTheFoldedStrips() {
        XCTAssertEqual(EdgeBarState.dwell, Fold.dwell, "one wait at the top edge, whatever comes down from it")
    }

    // MARK: - when it may come, and what it does

    func testOnlyWithTheColumnFoldedAway() {
        let browser = make()
        XCTAssertFalse(browser.edgeBarWanted, "the column beside the page has them")
        browser.folded = true
        XCTAssertTrue(browser.edgeBarWanted)
        browser.peeking = true
        XCTAssertFalse(browser.edgeBarWanted, "out over the page, the column has them")
        browser.peeking = false
        browser.editing = true
        XCTAssertFalse(browser.edgeBarWanted, "the field up: nothing in its way")
        browser.editing = false
        browser.fullScreen = true
        XCTAssertFalse(browser.edgeBarWanted, "in full screen the top edge is the menu bar's")
        browser.fullScreen = false
        browser.prefs.sidebar = false
        XCTAssertFalse(browser.edgeBarWanted, "the strip across the top comes down whole")
    }

    /// The card in a window off every screen, down, and its address pressed:
    /// ⌘L's field comes up, and the card is put away.
    func testAPressOnItsAddressRaisesTheField() async throws {
        let browser = make()
        browser.folded = true
        let size = CGSize(width: 900, height: 500)
        let host = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                            styleMask: .borderless, backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.contentView = NSHostingView(rootView: Hosted(browser: browser).frame(width: size.width, height: size.height))
        host.orderFrontRegardless()
        XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(host.frame) }, "never on a screen")
        windows.append(host)
        browser.edgeBar.pointer(at: CGPoint(x: size.width / 2, y: 2), in: size, pressed: false)
        try await wait(EdgeBarState.dwell + 0.5)
        XCTAssertTrue(browser.edgeBar.shown)
        XCTAssertFalse(browser.editing)
        let frame = EdgeBar.frame(in: size)
        // Well to the right of the three buttons, in the line.
        let point = NSPoint(x: frame.maxX - 80, y: size.height - frame.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: host.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1))
            host.sendEvent(event)
            try await wait(0.05)
        }
        try await wait(0.3)
        XCTAssertTrue(browser.editing, "the address pressed is ⌘L")
        XCTAssertFalse(browser.edgeBar.shown, "and the card has done its part")
        XCTAssertFalse(browser.edgeBarWanted)
    }

    private func make() -> Browser {
        _ = NSApplication.shared
        if activationPolicy == nil {
            activationPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.prohibited)
        }
        let prefs = Shared.prefs
        let previous = (prefs.sidebar, prefs.sideHides, prefs.splitView)
        if restorePreferences == nil {
            restorePreferences = { (prefs.sidebar, prefs.sideHides, prefs.splitView) = previous }
        }
        let browser = Browser(record: WindowRecord())
        browsers.append(browser)
        browser.prefs.sidebar = true
        browser.prefs.sideHides = false
        browser.prefs.splitView = false
        browser.tabs.last?.restore(url: URL(string: "about:blank#one")!, title: "one")
        if let tab = browser.tabs.last { browser.select(tab) }
        browser.folded = false
        return browser
    }

    private func wait(_ seconds: TimeInterval) async throws {
        try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }
}

/// The card as the window hosts it: told by the browser whether it may come.
private struct Hosted: View {
    @ObservedObject var browser: Browser

    var body: some View {
        Color.white.overlay(alignment: .top) {
            EdgeBar(browser: browser, state: browser.edgeBar, wanted: browser.edgeBarWanted)
        }
    }
}
