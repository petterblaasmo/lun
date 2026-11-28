import AppKit
import XCTest
@testable import Search

/// chrome.sidePanel's getLayout, onOpened and onClosed, on the browser's
/// side: which side the panel is on, and that every way a window's panel
/// comes and goes is said to an extension that listens.
@available(macOS 15.4, *)
@MainActor
final class SidePanelEventsTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    func testThePanelIsOnTheSideAwayFromTheColumn() {
        let browser = Browser(record: WindowRecord())
        let (sidebar, position) = (browser.prefs.sidebar, browser.prefs.sidePosition)
        defer { browser.prefs.sidebar = sidebar; browser.prefs.sidePosition = position }
        browser.prefs.sidebar = true
        browser.prefs.sidePosition = .left
        XCTAssertEqual(browser.sidePanelSide, "right")
        browser.prefs.sidePosition = .right
        XCTAssertEqual(browser.sidePanelSide, "left")
        // The tabs across the top: on the right, wherever the column was.
        browser.prefs.sidebar = false
        XCTAssertEqual(browser.sidePanelSide, "right")
    }

    func testAWindowsPanelComingAndGoingIsSaidToItsExtension() throws {
        let id = "side-panel-events"
        var told: [[String: Any]] = []
        let ear = ExtensionEar(extensionID: id, say: { told.append($0) }, hears: { true })
        ExtensionWatch.panel.add(ear)
        defer { ExtensionWatch.panel.remove(ear) }
        let browser = Browser(record: WindowRecord())
        let url = try XCTUnwrap(URL(string: "webkit-extension://\(id)/pages/panel.html?for=a"))

        browser.sidePanel = .page(extensionID: id, url: url, tab: nil)
        browser.sidePanelShown = true
        let opened = try XCTUnwrap(told.last?["opened"] as? [String: Any])
        // No extension by that name is loaded here, so nothing it gave to
        // compare with: the page's own place in the package, query and all.
        XCTAssertEqual(opened["path"] as? String, "pages/panel.html?for=a")
        XCTAssertNil(opened["tabId"], "the window's panel names no tab")

        browser.closeSidePanel()
        XCTAssertEqual(told.count, 2)
        XCTAssertEqual((told.last?["closed"] as? [String: Any])?["path"] as? String, "pages/panel.html?for=a")
    }

    func testATabsOwnPanelIsSaidWithTheExtensionsNumberForThatTab() throws {
        let id = "side-panel-events-tab"
        var told: [[String: Any]] = []
        let ear = ExtensionEar(extensionID: id, say: { told.append($0) }, hears: { true })
        ExtensionWatch.panel.add(ear)
        let tab = UUID()
        ExtensionShims.panelTabIDs[id] = [42: tab]
        defer { ExtensionWatch.panel.remove(ear); ExtensionShims.panelTabIDs[id] = nil }
        let browser = Browser(record: WindowRecord())
        let url = try XCTUnwrap(URL(string: "webkit-extension://\(id)/panel.html"))

        browser.sidePanel = .page(extensionID: id, url: url, tab: tab)
        XCTAssertEqual((told.last?["opened"] as? [String: Any])?["tabId"] as? Int, 42)
        browser.sidePanel = nil
        XCTAssertEqual((told.last?["closed"] as? [String: Any])?["tabId"] as? Int, 42)
    }
}
