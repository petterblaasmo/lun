import XCTest
@testable import Search

/// Settings after the cut: the switches Lun took out are neither drawn nor
/// found and read as their defaults, eleven pages are eight, and each page
/// opens on a few rows with the rest one press away.
@MainActor
final class RetiredSettingsTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    private var rail: [SettingsPanel.Page] { SettingsPanel.Page.blocks.flatMap { $0 } }

    func testRetiredRowsAreNeitherListedNorFound() {
        let listed = Set(SettingsIndex.items.map(\.id))
        XCTAssertTrue(listed.isDisjoint(with: RetiredSettings.rows), "\(listed.intersection(RetiredSettings.rows))")
        for words in ["downloads button", "shorter tab bar", "backspace", "glass style", "reduce animations", "news by email"] {
            XCTAssertTrue(SettingsIndex.find(words).allSatisfy { !RetiredSettings.rows.contains($0.id) }, words)
        }
        XCTAssertTrue(SettingsIndex.find("backspace goes back").isEmpty)
    }

    func testStoredChoicesArePutAsideOnce() throws {
        let name = "retired-\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        store.set(true, forKey: "tabs.compact")
        store.set("always", forKey: "pages.120.mode")
        store.set(false, forKey: "pins.home")
        store.set("letters", forKey: "glyph")
        store.set(true, forKey: "spaces")

        RetiredSettings.settle(store)
        XCTAssertNil(store.object(forKey: "tabs.compact"))
        XCTAssertNil(store.object(forKey: "pages.120.mode"))
        XCTAssertNil(store.object(forKey: "pins.home"))
        XCTAssertEqual(store.object(forKey: RetiredSettings.aside("tabs.compact")) as? Bool, true)
        XCTAssertEqual(store.string(forKey: RetiredSettings.aside("pages.120.mode")), "always")
        // The mark of an install from before, and a setting that is kept.
        XCTAssertEqual(store.string(forKey: "glyph"), "letters")
        XCTAssertTrue(store.bool(forKey: "spaces"))

        // Again, with nothing stored: what was put aside is not overwritten.
        RetiredSettings.settle(store)
        XCTAssertEqual(store.object(forKey: RetiredSettings.aside("tabs.compact")) as? Bool, true)
    }

    func testTheFixedOnesAreWrittenOn() throws {
        let name = "fixed-\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        store.set("tab", forKey: "downloads.open")
        store.set(false, forKey: "tabs.give")

        RetiredSettings.settle(store)
        XCTAssertEqual(RetiredSettings.fixed.count, 21)
        // Not HTTPS first: sites without HTTPS stayed blank while it was on.
        XCTAssertFalse(RetiredSettings.fixed.contains { $0.key == "privacy.httpsFirst" })
        XCTAssertTrue(RetiredSettings.keys.contains("privacy.httpsFirst"))
        for (key, _) in RetiredSettings.fixed where key != "downloads.open" {
            XCTAssertEqual(store.object(forKey: key) as? Bool, true, key)
        }
        XCTAssertEqual(store.string(forKey: "downloads.open").flatMap(DownloadsOpening.init), .popover)
        // What was chosen before is kept aside; what was never set has nothing to keep.
        XCTAssertEqual(store.string(forKey: RetiredSettings.aside("downloads.open")), "tab")
        XCTAssertEqual(store.object(forKey: RetiredSettings.aside("tabs.give")) as? Bool, false)
        XCTAssertNil(store.object(forKey: RetiredSettings.aside("commandbar")))

        // The column's slow slide was fixed on for a day: off again, so
        // ⌘S is as quick as it was.
        XCTAssertNil(Motion.slide(out: true))
        store.set(true, forKey: Motion.slidesKey)
        RetiredSettings.settle(store)
        XCTAssertNil(store.object(forKey: Motion.slidesKey))

        // A link from another app opens in a tab: the small window's switch
        // is gone, and a stored "on" (a new install's default) is cleared.
        XCTAssertNil(SettingsIndex.item("links.little"))
        store.set(true, forKey: Preferences.littleKey)
        RetiredSettings.settle(store)
        XCTAssertNil(store.object(forKey: Preferences.littleKey))

        // Again: already as fixed, nothing more is put aside.
        RetiredSettings.settle(store)
        XCTAssertEqual(store.string(forKey: RetiredSettings.aside("downloads.open")), "tab")
    }

    /// Roomier tabs is retired at off: no row, nothing found, a stored "on"
    /// put aside, and a tab's row the one height. The code behind it stays.
    func testRoomierTabsIsRetiredAtTheOneHeight() throws {
        XCTAssertNil(SettingsIndex.item("sidebar.roomy"))
        XCTAssertTrue(SettingsIndex.find("roomier tabs").allSatisfy { $0.id != "sidebar.roomy" })
        XCTAssertFalse(WhatsNew.toggles.contains { $0.title == "Roomier tabs" })
        XCTAssertFalse(RetiredSettings.fixed.contains { $0.key == "sidebar.roomy" })

        let name = "roomy-\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        store.set(true, forKey: "sidebar.roomy")
        RetiredSettings.settle(store)
        XCTAssertNil(store.object(forKey: "sidebar.roomy"))
        XCTAssertEqual(store.object(forKey: RetiredSettings.aside("sidebar.roomy")) as? Bool, true)

        let prefs = Preferences()
        let was = (prefs.roomyTabs, prefs.sidebar, prefs.sideIcons)
        defer { (prefs.roomyTabs, prefs.sidebar, prefs.sideIcons) = was }
        (prefs.roomyTabs, prefs.sidebar, prefs.sideIcons) = (false, true, false)
        XCTAssertEqual(prefs.sideRow, 32)
        XCTAssertEqual(prefs.sideTitle, 13)
    }

    /// Switches that came back: their row again, and the choice put aside
    /// when they were retired put back, once.
    func testReturnedSwitchesGetTheirChoiceBack() throws {
        for (key, wasFixed) in RetiredSettings.returned {
            XCTAssertFalse(RetiredSettings.keys.contains(key), key)
            XCTAssertFalse(RetiredSettings.fixed.contains { $0.key == key }, key)
            XCTAssertTrue(SettingsIndex.items.contains { $0.keys.contains(key) }, "\(key) has its row")

            let name = "returned-\(UUID().uuidString)"
            let store = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { store.removePersistentDomain(forName: name) }
            // What was put aside: an "on" for one retired at its default,
            // an "off" for one fixed on, which wrote "on" over it.
            let chosen = !wasFixed
            store.set(chosen, forKey: RetiredSettings.aside(key))
            if wasFixed { store.set(true, forKey: key) }
            RetiredSettings.settle(store)
            XCTAssertEqual(store.object(forKey: key) as? Bool, chosen, key)
            XCTAssertNil(store.object(forKey: RetiredSettings.aside(key)), key)
            // Once: what is chosen on its row from then on stands.
            store.set(!chosen, forKey: key)
            RetiredSettings.settle(store)
            XCTAssertEqual(store.object(forKey: key) as? Bool, !chosen, key)

            // Nothing put aside: one fixed on is at its default again.
            let fresh = "returned-\(UUID().uuidString)"
            let other = try XCTUnwrap(UserDefaults(suiteName: fresh))
            defer { other.removePersistentDomain(forName: fresh) }
            if wasFixed { other.set(true, forKey: key) }
            RetiredSettings.settle(other)
            XCTAssertNil(other.object(forKey: key), key)
        }
    }

    func testEveryRetiredKeyBelongedToARetiredRow() {
        // A key of a row that is still drawn must never be put aside.
        let kept = Set(SettingsIndex.items.flatMap(\.keys))
        XCTAssertTrue(kept.isDisjoint(with: RetiredSettings.keys), "\(kept.intersection(RetiredSettings.keys))")
        let fixed = Set(RetiredSettings.fixed.map(\.key))
        XCTAssertTrue(kept.isDisjoint(with: fixed), "\(kept.intersection(fixed))")
        XCTAssertTrue(fixed.isDisjoint(with: RetiredSettings.keys), "fixed on and put aside at once")
    }

    func testEightPagesAndTheOldNamesStillOpenOne() {
        XCTAssertEqual(rail.filter { $0 != .ai }, [.general, .appearance, .tabs, .browsing, .privacy, .extensions, .keyboard, .about])
        XCTAssertEqual(SettingsPanel.Page.named("themes"), .appearance)
        XCTAssertEqual(SettingsPanel.Page.named("spaces"), .tabs)
        XCTAssertEqual(SettingsPanel.Page.named("passwords"), .privacy)
        XCTAssertEqual(SettingsPanel.Page.named("mouse"), .browsing)
        XCTAssertEqual(SettingsPanel.Page.named("keyboard"), .keyboard)
        XCTAssertEqual(SettingsPanel.Page.keyboard.title, "Shortcuts")
        for item in SettingsIndex.items { XCTAssertTrue(rail.contains(item.page) || item.page == .ai, item.id) }
    }

    func testThemingIsAllOnAppearance() {
        for id in ["look", "pages.dusk", "window.glass", "window.glass.clear", "window.glass.grain", "space.colour", "home.theme", "home.grid"] {
            XCTAssertEqual(SettingsIndex.item(id)?.page, .appearance, id)
        }
    }

    func testEachPageOpensOnAFewRows() {
        let essential = SettingsIndex.essential
        XCTAssertEqual(essential.count, 25)
        for id in essential { XCTAssertNotNil(SettingsIndex.item(id), id) }
        for page in [SettingsPanel.Page.general, .appearance, .tabs, .browsing, .privacy, .about] {
            let rows = SettingsIndex.groups(of: page).flatMap { SettingsIndex.items(in: $0.id) }
            let first = rows.filter { essential.contains($0.id) }
            XCTAssertTrue((3...7).contains(first.count), "\(page.rawValue): \(first.count)")
            XCTAssertLessThanOrEqual(rows.count - first.count, 14, page.rawValue)
        }
    }

    func testDeveloperRowsAreBehindTheirOwnLine() {
        let developer = Set(SettingsIndex.items(in: SettingsIndex.developer).map(\.id))
        XCTAssertEqual(developer, ["inspector.chrome", "inspector.dark", "sites.styles", "clear.cache", "devtools", "bench", "agents", "developer.local"])
        XCTAssertTrue(developer.isDisjoint(with: SettingsIndex.essential))
        XCTAssertEqual(SettingsIndex.group(SettingsIndex.developer)?.page, .about)
    }

    func testTheBookmarksBarIsOneChoiceOverTwoKeys() {
        let prefs = Preferences()
        let was = (prefs.sidebar, prefs.bookmarksBar, prefs.bookmarksInSidebar)
        defer { prefs.sidebar = was.0; prefs.bookmarksBar = was.1; prefs.bookmarksInSidebar = was.2 }
        prefs.sidebar = true
        prefs.bookmarksPlace = .side
        XCTAssertTrue(prefs.bookmarksBar && prefs.bookmarksInSidebar)
        XCTAssertEqual(prefs.bookmarksPlace, .side)
        prefs.bookmarksPlace = .above
        XCTAssertTrue(prefs.bookmarksBar && !prefs.bookmarksInSidebar)
        prefs.bookmarksPlace = .off
        XCTAssertFalse(prefs.bookmarksBar)
        // Across the top there is no sidebar: a bar kept for it shows above.
        prefs.bookmarksPlace = .side
        prefs.sidebar = false
        XCTAssertEqual(prefs.bookmarksPlace, .above)
        XCTAssertEqual(BookmarksPlace.choices(sidebar: false), [.off, .above])
        XCTAssertTrue(SettingsIndex.apply("bookmarks.bar", "off", to: prefs))
        XCTAssertEqual(SettingsIndex.values(prefs)["bookmarks.bar"] as? String, "off")
    }

    func testWhatsNewOffersNoRetiredSwitch() {
        XCTAssertTrue(WhatsNew.toggles.allSatisfy { !RetiredSettings.offers.contains($0.title) })
    }

    func testOldPageNamesStillWorkAsCommands() {
        let names = SettingsPanel.Page.allCases.flatMap { AddressCommand.page($0).aliases }
        for name in ["Themes Settings", "Passwords Settings", "Spaces & Pins Settings", "Keyboard & Mouse Settings", "Shortcuts Settings"] {
            XCTAssertTrue(names.contains(name), name)
        }
    }

    func testRowsLeft() {
        let drawn = SettingsIndex.items.filter { !$0.findOnly }
        print("ROWS drawn=\(drawn.count) essential=\(drawn.filter { SettingsIndex.essential.contains($0.id) }.count) developer=\(SettingsIndex.items(in: SettingsIndex.developer).count)")
        for page in rail {
            let rows = SettingsIndex.groups(of: page).flatMap { SettingsIndex.items(in: $0.id) }
            print("ROWS \(page.rawValue) \(rows.count): \(rows.map(\.id).joined(separator: " "))")
        }
        XCTAssertLessThanOrEqual(drawn.count, 90)
    }
}
