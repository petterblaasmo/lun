import AppKit
import XCTest
@testable import Search

/// A whole address typed or pasted into ⌘K's or ⌘T's field finds the tab
/// that has that page, tracking tags or not, on either side.
@MainActor
final class PastedLinkOpenTabTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    private let site = "http://127.0.0.1:9"

    func testALinkPastedWithTrackingTagsFindsItsOpenTab() throws {
        let browser = try pages(["/article?id=5", "/other"])
        defer { browser.closeAll() }
        let article = browser.tabs[0].id
        let pasted = site + "/article?utm_source=news&id=5&fbclid=IwAR2xYz&utm_medium=mail"

        XCTAssertEqual(browser.openPages(matching: pasted).map(\.tab), [article], "⌘K")
        XCTAssertEqual(browser.tabOffers(for: pasted).map(\.tab), [article], "⌘T")
        // Without the scheme, as an address is often typed.
        XCTAssertEqual(browser.openPages(matching: "127.0.0.1:9/article?id=5&gclid=abc").map(\.tab), [article])
    }

    func testACleanLinkFindsTheTabOpenWithTrackingTags() throws {
        let browser = try pages(["/article?id=5&utm_campaign=spring", "/other"])
        defer { browser.closeAll() }
        let article = browser.tabs[0].id

        XCTAssertEqual(browser.openPages(matching: site + "/article?id=5").map(\.tab), [article])
        XCTAssertEqual(browser.tabOffers(for: site + "/article?id=5").map(\.tab), [article])
    }

    func testAnotherPageIsNotTheOneTyped() throws {
        let browser = try pages(["/article?id=5", "/article#notes"])
        defer { browser.closeAll() }
        let notes = browser.tabs[1].id

        // What the page needs to be the page is kept: another id is another page.
        XCTAssertTrue(browser.openPages(matching: site + "/article?id=6&utm_source=news").isEmpty)
        XCTAssertTrue(browser.tabOffers(for: site + "/article?id=6&utm_source=news").isEmpty)
        // A link to a part of a page is no reason to go to a tab elsewhere on it.
        XCTAssertTrue(browser.openPages(matching: site + "/article?id=5#comments").isEmpty)
        XCTAssertEqual(browser.openPages(matching: site + "/article?utm_source=news#notes").map(\.tab), [notes])
        // And the other way: the page, wherever its tab has got to.
        XCTAssertEqual(browser.openPages(matching: site + "/article").map(\.tab), [notes])
    }

    func testWordsMatchAsTheyDid() throws {
        let browser = try pages(["/article?id=5", "/other", "/article/more"])
        defer { browser.closeAll() }
        let ids = browser.tabs.prefix(3).map(\.id)

        // The one looked at last first, the address typed out or not.
        XCTAssertEqual(browser.openPages(matching: "article").map(\.tab), [ids[2], ids[0]])
        XCTAssertEqual(browser.openPages(matching: "127.0.0.1/article").map(\.tab), [ids[2], ids[0]])
        XCTAssertEqual(browser.tabOffers(for: "127.0.0.1/article").map(\.tab), [ids[2], ids[0]])
        XCTAssertTrue(browser.openPages(matching: "nowhere").isEmpty)
        XCTAssertTrue(browser.tabOffers(for: "utm_source").isEmpty)
    }

    /// The pages, each in a tab, and one more in front: the tab in front is
    /// never offered.
    private func pages(_ paths: [String]) throws -> Browser {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        browser.welcoming = false
        browser.newsShowing = false
        for path in paths + ["/front"] {
            browser.newTab()
            try XCTUnwrap(browser.active).go(to: XCTUnwrap(URL(string: site + path)))
        }
        return browser
    }
}
