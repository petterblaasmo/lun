import AppKit
import XCTest
@testable import Search

/// The address above the page (Toolbar.swift): only with the address in
/// sight, put there, and the tabs down a side; while it is, the column
/// gives up back, forward, reload and the extensions, so each is drawn
/// once, and the card from the top edge stays away.
@MainActor
final class ToolbarTests: XCTestCase {
    override class func setUp() { TestWorld.enter(); super.setUp() }

    func testOnlyAboveThePageWithTheTabsDownASide() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let prefs = browser.prefs
        prefs.hidesExtensionsDoor = false
        prefs.addressLine = true
        prefs.sidebar = true
        prefs.addressPlace = .side
        XCTAssertFalse(prefs.toolbar, "In the column: no row above the page")
        XCTAssertEqual(prefs.rowHelmDoors, prefs.helmDoors, "the lights' row keeps its doors")
        XCTAssertTrue(prefs.footPuzzle, "and the foot its puzzle")

        prefs.addressPlace = .page
        XCTAssertTrue(prefs.toolbar, "Above the page with the tabs down a side")
        XCTAssertEqual(prefs.rowHelmDoors, 0, "back, forward and reload go up to the row")
        XCTAssertEqual(Metrics.helm(prefs), 0, "and the lights' row makes no room for them")
        XCTAssertFalse(prefs.footPuzzle, "the puzzle goes up to the row too")

        prefs.sidebar = false
        XCTAssertFalse(prefs.toolbar, "Tabs across the top: the row under them has all of it")
        XCTAssertEqual(prefs.rowHelmDoors, prefs.helmDoors)

        prefs.sidebar = true
        prefs.addressLine = false
        XCTAssertFalse(prefs.toolbar, "The address not shown: no row for it")
    }

    /// Folded away, the card that comes down from the top edge has back,
    /// forward and the address (EdgeBar): not while the row above the page
    /// is there with the same three.
    func testTheTopEdgesCardStaysAwayWhileTheRowIsUp() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let prefs = browser.prefs
        prefs.addressLine = true
        prefs.sidebar = true
        prefs.addressPlace = .side
        browser.folded = true
        XCTAssertTrue(browser.edgeBarWanted, "folded, nothing of the column in the window")
        prefs.addressPlace = .page
        XCTAssertFalse(browser.edgeBarWanted, "the row has them, folded or not")
        prefs.addressLine = false
        XCTAssertTrue(browser.edgeBarWanted, "no address in sight: the edge brings it again")
    }

    /// ⌘L opens the address where it is in sight (Browser.edit): above the
    /// page that is with the column folded away too, where the column's own
    /// line is gone and the field comes up over the page.
    func testCommandLOpensInTheRowWithTheColumnFoldedAway() throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        browser.welcoming = false
        browser.newsShowing = false
        let prefs = browser.prefs
        prefs.addressLine = true
        prefs.sidebar = true
        browser.newTab()
        try XCTUnwrap(browser.active).go(to: URL(string: "about:blank")!)
        browser.folded = true

        prefs.addressPlace = .side
        browser.edit()
        XCTAssertFalse(browser.editingInline, "folded, the column's line is out of the window")
        browser.editing = false

        prefs.addressPlace = .page
        browser.edit()
        XCTAssertTrue(browser.editingInline, "the row above the page is still there")
        browser.editing = false
    }

    func testInTheColumnUnlessAskedForAndListed() throws {
        let store = UserDefaults(suiteName: "toolbar-\(UUID().uuidString)")!
        XCTAssertNil(store.string(forKey: "address.place").flatMap(AddressPlace.init))
        XCTAssertEqual(AddressPlace(rawValue: "page"), .page)
        XCTAssertNil(AddressPlace(rawValue: "nonsense"), "an unknown value falls back to the column")

        let item = try XCTUnwrap(SettingsIndex.item("address.place"))
        XCTAssertEqual(item.parent, "address.shown")
        XCTAssertFalse(RetiredSettings.rows.contains(item.id))
        XCTAssertTrue(SettingsIndex.find("toolbar").contains { $0.id == "address.place" })

        let prefs = Shared.prefs
        prefs.addressLine = true
        prefs.sidebar = true
        XCTAssertTrue(SettingsIndex.applies(item, prefs))
        prefs.sidebar = false
        XCTAssertFalse(SettingsIndex.applies(item, prefs), "across the top the address has its row already")

        let offer = try XCTUnwrap(WhatsNew.toggles.first { $0.title == item.title })
        prefs.sidebar = true
        prefs.addressPlace = .side
        XCTAssertFalse(offer.get(prefs), "off until turned on")
        offer.set(prefs, true)
        XCTAssertEqual(prefs.addressPlace, .page)
        XCTAssertTrue(offer.get(prefs))
        offer.set(prefs, false)
        XCTAssertEqual(prefs.addressPlace, .side)
    }

    /// Inside the card the row is centred on the lights' line, as the
    /// column's top row is: one title bar across the two.
    func testTheRowInTheCardIsOnTheLightsLine() {
        let prefs = Shared.prefs
        prefs.sidebar = true
        XCTAssertEqual(Metrics.cardGap + Toolbar.inCard / 2, Metrics.strip / 2)
        XCTAssertEqual(Toolbar.height, Metrics.strip)
        XCTAssertGreaterThanOrEqual(Toolbar.inCard, 30, "room for the 28 point address and the buttons' band")
    }
}
