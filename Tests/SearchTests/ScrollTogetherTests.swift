import AppKit
import XCTest
@testable import Search

/// The divider's menu › Scroll Together: one split's own, off until asked
/// for, kept with the session, and what a page's word of its scroll counts
/// as a move of its own. The pages themselves following one another is
/// Tests/scroll_together.py, in a hidden copy of the app: a page's word
/// waits for an animation frame, which a web view in no window never gets.
@MainActor
final class ScrollTogetherTests: XCTestCase {
    private var browsers: [Browser] = []
    private var restorePreferences: (() -> Void)?

    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func tearDown() async throws {
        for browser in browsers { browser.closeAll() }
        browsers.removeAll()
        restorePreferences?()
        try await super.tearDown()
    }

    // MARK: - what counts as a move

    func testAPageMovedByItsOwnSaysHowFar() {
        XCTAssertEqual(Tab.step(from: 100, to: 340, first: false, echo: false), 240)
        XCTAssertEqual(Tab.step(from: 340, to: 100, first: false, echo: false), -240, "up as well as down")
    }

    func testADocumentsFirstWordIsNoMove() {
        XCTAssertNil(Tab.step(from: nil, to: 500, first: true, echo: false), "a page restored half way down")
        XCTAssertNil(Tab.step(from: 2000, to: 0, first: true, echo: false), "a new page in the same tab starts at its top")
        XCTAssertNil(Tab.step(from: nil, to: 500, first: false, echo: false), "nothing known to have moved from")
    }

    func testAnEchoIsNoMove() {
        XCTAssertNil(Tab.step(from: 100, to: 340, first: false, echo: true), "put there by the page beside it")
        XCTAssertNil(Tab.step(from: 100, to: 100, first: false, echo: false), "said again, where it was")
        XCTAssertNil(Tab.step(from: 100, to: .nan, first: false, echo: false))
    }

    // MARK: - the split's own

    func testOffUntilAskedForAndOneSplitsOwn() throws {
        let (browser, t) = make(4)
        browser.pair(t[1], with: t[0], onLeft: false)
        browser.pair(t[3], with: t[2], onLeft: false)
        XCTAssertEqual(browser.splits.map(\.scrollsTogether), [false, false], "off to begin with")
        browser.focusPane(t[0])
        browser.toggleScrollTogether()
        XCTAssertEqual(browser.split(for: t[0])?.scrollsTogether, true)
        XCTAssertEqual(browser.split(for: t[2])?.scrollsTogether, false, "the other split is not asked")
        browser.swapSplit()
        XCTAssertEqual(browser.split(for: t[0])?.scrollsTogether, true, "kept when its pages change sides")
        browser.toggleScrollTogether()
        XCTAssertEqual(browser.split(for: t[0])?.scrollsTogether, false, "and off again from the same line")
    }

    func testNothingToTurnOnWithoutASplit() {
        let (browser, t) = make(2)
        browser.select(t[0])
        browser.toggleScrollTogether()
        XCTAssertTrue(browser.splits.isEmpty)
    }

    // MARK: - kept with the session

    func testWrittenOnlyWhenOnAndReadFromOlderFiles() throws {
        let off = try JSONEncoder().encode(Session.Split(tabs: [0, 1], sizes: [0.5, 0.5]))
        XCTAssertFalse(String(decoding: off, as: UTF8.self).contains("together"), "nothing new in a file while it is off")
        let on = try JSONEncoder().encode(Session.Split(tabs: [0, 1], sizes: [0.5, 0.5], together: true))
        XCTAssertEqual(try JSONDecoder().decode(Session.Split.self, from: on).together, true)
        let older = Data(#"{"tabs":[0,1],"axis":"horizontal","sizes":[0.5,0.5]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(Session.Split.self, from: older).together, "a file from before reads as off")
    }

    // MARK: - what the following page is told

    func testTheFollowingPageGoesAtOnceAndMarksWhereItWasPut() {
        let script = ScrollRelay.follow(by: -120.5)
        XCTAssertTrue(script.contains("top: -120.5"), script)
        XCTAssertTrue(script.contains("behavior: 'instant'"), "whatever the page's own scroll-behavior")
        XCTAssertTrue(script.contains("window.\(ScrollRelay.mark) = window.scrollY"), "for its word of it to be known as an echo")
        XCTAssertTrue(ScrollRelay.script.contains("window.\(ScrollRelay.mark)"), "and the page's word looks for the same mark")
    }

    // MARK: - helpers

    private func make(_ count: Int) -> (Browser, [Search.Tab]) {
        _ = NSApplication.shared
        let prefs = Shared.prefs
        let previous = (prefs.usesTabGroups, prefs.splitView)
        restorePreferences = { (prefs.usesTabGroups, prefs.splitView) = previous }
        let browser = Browser(record: WindowRecord())
        browsers.append(browser)
        browser.prefs.usesTabGroups = false
        browser.prefs.splitView = true
        for number in 1...count {
            if browser.tabs.last?.isBlank == false { browser.newTab() }
            browser.tabs.last?.restore(url: URL(string: "about:blank#\(number)")!, title: "Tab \(number)")
        }
        return (browser, browser.tabs)
    }
}
