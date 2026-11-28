import AppKit
import SwiftUI
import XCTest
@testable import Search

/// Open in Small Window is in a tab's menu whatever `links.little` says:
/// that switch is retired at off (RetiredSettings), and the menu is the
/// way to a small window that is left. The menu is built, never shown.
@MainActor
final class SmallWindowMenuTests: XCTestCase {
    private var browser: Browser!
    private var oldLittleLinks = false

    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        browser = Browser(record: WindowRecord())
        oldLittleLinks = browser.prefs.littleLinks
        browser.prefs.littleLinks = false
        browser.closeAll()
    }

    override func tearDown() {
        browser?.closeAll()
        browser?.prefs.littleLinks = oldLittleLinks
        browser = nil
        super.tearDown()
    }

    private func tab(_ name: String) -> Search.Tab {
        let tab = Search.Tab(configuration: Web.configuration(space: browser.spaceID))
        tab.restore(url: URL(string: "about:blank#\(name)")!, title: name)
        return tab
    }

    private func item(in menu: NSMenu) -> NSMenuItem? {
        menu.update()
        return menu.items.first { $0.title == "Open in Small Window" }
    }

    func testATabsMenuOffersTheSmallWindowWithLinksLittleOff() throws {
        guard #available(macOS 14.4, *) else { throw XCTSkip("NSHostingMenu needs macOS 14.4") }
        let (a, b) = (tab("A"), tab("B"))
        browser.showRow([a, b], active: a.id)
        XCTAssertFalse(browser.prefs.littleLinks)
        let menu = NSHostingMenu(rootView: TabMenu(browser: browser, tab: a, close: {}))
        let offered = try XCTUnwrap(item(in: menu), "\(menu.items.map(\.title))")
        XCTAssertTrue(offered.isEnabled)
    }

    /// A pin is the row's: the item isn't in its menu, as before.
    func testAPinsMenuStillLeavesItOut() throws {
        guard #available(macOS 14.4, *) else { throw XCTSkip("NSHostingMenu needs macOS 14.4") }
        let (a, b) = (tab("A"), tab("B"))
        browser.showRow([a, b], active: a.id)
        browser.pin(a)
        let menu = NSHostingMenu(rootView: TabMenu(browser: browser, tab: a, close: {}))
        menu.update()
        XCTAssertFalse(menu.items.isEmpty, "the menu was built")
        XCTAssertNil(item(in: menu))
    }
}
