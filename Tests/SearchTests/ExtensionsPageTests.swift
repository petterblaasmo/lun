import XCTest
@testable import Search

/// Extensions have a page of their own, as History and Downloads do:
/// search://extensions, opened by the menu's Extensions… and the puzzle's
/// Manage Extensions….
@MainActor
final class ExtensionsPageTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    func testItsAddress() throws {
        let page = try XCTUnwrap(InternalPage(url: XCTUnwrap(URL(string: "search://extensions"))))
        XCTAssertEqual(page.kind, .extensions)
        XCTAssertEqual(page.title, "Extensions")
        XCTAssertEqual(page.url.absoluteString, "search://extensions")
        XCTAssertNotNil(page.glyph)
    }

    func testExtensionsOpensItsOwnTabAndOnlyOne() {
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        XCTAssertNil(browser.pageTab(.extensions))
        browser.showExtensions()
        let tab = browser.pageTab(.extensions)
        XCTAssertNotNil(tab)
        XCTAssertEqual(browser.activeID, tab?.id)
        XCTAssertFalse(browser.tuning, "not Settings: a page of its own")
        // Asked for again, it goes to the one already open.
        browser.newTab()
        browser.showExtensions()
        XCTAssertEqual(browser.activeID, tab?.id)
        XCTAssertEqual(browser.tabs.filter { $0.page?.kind == .extensions }.count, 1)
    }
}
