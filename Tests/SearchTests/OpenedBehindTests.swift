import AppKit
import XCTest
@testable import Search

/// A link opened in a tab behind the page says so when the tabs are folded
/// away, where nothing else shows the click did anything; with the tabs in
/// sight, or the new tab in front, it says nothing.
@MainActor
final class OpenedBehindTests: XCTestCase {
    private var browser: Browser!
    private var lazy = false

    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        browser = Browser(record: WindowRecord())
        browser.welcoming = false
        // A tab behind waits to be looked at: nothing is loaded here.
        lazy = browser.prefs.lazyTabs
        browser.prefs.lazyTabs = true
    }

    override func tearDown() {
        browser.prefs.lazyTabs = lazy
        browser.closeAll()
        browser = nil
    }

    private func link(_ name: String) -> URL { URL(string: "https://\(name).example/")! }

    /// The middle button on a link in the page in front, as the page's
    /// script reports it (MiddleRelay): `front` with ⇧ held.
    private func middleClick(_ url: URL, front: Bool = false) throws -> Tab {
        let page = try XCTUnwrap(browser.active)
        let before = Set(browser.tabs.map(\.id))
        try XCTUnwrap(page.onMiddleClick)(page, url, front)
        return try XCTUnwrap(browser.tabs.first { !before.contains($0.id) })
    }

    func testALinkOpenedBehindSaysSoOnlyWithTheTabsFoldedAway() throws {
        let page = try XCTUnwrap(browser.active ?? browser.tabs.last)
        page.restore(url: link("page"), title: "page")

        // The tabs in sight: the new tab in the row is the sign.
        browser.folded = false
        var tab = try middleClick(link("one"))
        XCTAssertNotEqual(browser.activeID, tab.id)
        XCTAssertNil(browser.announcement)

        // Folded away, but slid out over the page for a look: in sight.
        browser.folded = true
        browser.peeking = true
        tab = try middleClick(link("two"))
        XCTAssertNil(browser.announcement)
        browser.peeking = false

        // Folded away, the new tab in front: the page changing is the sign.
        tab = try middleClick(link("three"), front: true)
        XCTAssertEqual(browser.activeID, tab.id)
        XCTAssertNil(browser.announcement)
        browser.select(page)

        // Folded away and behind: one short line.
        tab = try middleClick(link("four"))
        XCTAssertEqual(browser.activeID, page.id)
        XCTAssertEqual(browser.announcement, "Opened in a new tab")
    }

    func testOnlyATabOfThisWindowThatIsOutOfSightIsSaid() throws {
        let page = try XCTUnwrap(browser.active ?? browser.tabs.last)
        page.restore(url: link("page"), title: "page")
        browser.folded = true

        // The tab on screen, or one this window doesn't hold: nothing.
        browser.sayOpenedBehind(page)
        XCTAssertNil(browser.announcement)
        browser.sayOpenedBehind(Tab())
        XCTAssertNil(browser.announcement)

        let behind = browser.open(link("behind"), foreground: false, from: page, mayWait: true, link: true)
        XCTAssertNil(browser.announcement, "opening a tab alone says nothing: only a link clicked open does")
        browser.sayOpenedBehind(behind)
        XCTAssertEqual(browser.announcement, Browser.openedBehind)
    }
}
