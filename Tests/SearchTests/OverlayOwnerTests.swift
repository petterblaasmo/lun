import AppKit
import XCTest
@testable import Search

/// One overlay holds the keyboard at a time: Welcome, the list of what is
/// hidden on a site, the bookmarks' list and ⌘K's field. And ⌘K ends when
/// its field is put away, by whatever puts it away.
@MainActor
final class OverlayOwnerTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    func testPuttingTheFieldAwayEndsTheSwitcher() throws {
        let browser = try makeBrowser()
        defer { browser.closeAll() }
        browser.summon()
        XCTAssertTrue(browser.summoning)
        XCTAssertEqual(browser.fieldMode, .switcher)

        // What a link from another app, Paste and Go and a page opening a
        // tab each do to the field.
        browser.editing = false
        XCTAssertFalse(browser.summoning, "⌃Tab's switcher is no longer refused")
        XCTAssertEqual(browser.fieldMode, .blank)
    }

    func testRaisingOnePutsAwayTheOneUp() throws {
        let browser = try makeBrowser()
        defer { browser.closeAll() }
        browser.bookmarksOpen = true
        browser.reviewing = true
        XCTAssertTrue(browser.reviewing)
        XCTAssertFalse(browser.bookmarksOpen, "the hidden list replaces the bookmarks' list")

        browser.summon()
        XCTAssertTrue(browser.summoning)
        XCTAssertFalse(browser.reviewing)

        // The switcher's field goes with the switcher.
        browser.bookmarksOpen = true
        XCTAssertTrue(browser.bookmarksOpen)
        XCTAssertFalse(browser.summoning)
        XCTAssertFalse(browser.editing, "⌘K's field is not left under the list")

        // Putting away one that isn't up leaves the one that is.
        browser.reviewing = false
        XCTAssertTrue(browser.bookmarksOpen)
    }

    func testWelcomeHasTheKeyboardToItself() throws {
        let browser = try makeBrowser()
        defer { browser.closeAll() }
        browser.reviewing = true
        browser.welcoming = true
        XCTAssertFalse(browser.reviewing, "Welcome puts away what was up")

        browser.reviewing = true
        browser.bookmarksOpen = true
        browser.summon()
        XCTAssertFalse(browser.reviewing, "nothing comes up over Welcome")
        XCTAssertFalse(browser.bookmarksOpen)
        XCTAssertFalse(browser.summoning)
        XCTAssertFalse(browser.editing)
        XCTAssertTrue(browser.welcoming, "Welcome is left by its own button")

        browser.welcoming = false
        browser.reviewing = true
        XCTAssertTrue(browser.reviewing)
    }

    /// A browser on a page: the field raised over a page is put away whole,
    /// where a blank tab's own field stays.
    private func makeBrowser() throws -> Browser {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        browser.welcoming = false
        browser.newsShowing = false
        let tab = try XCTUnwrap(browser.active ?? browser.tabs.last)
        tab.restore(url: try XCTUnwrap(URL(string: "https://one.example/")), title: "one")
        XCTAssertEqual(browser.active?.isBlank, false)
        return browser
    }
}
