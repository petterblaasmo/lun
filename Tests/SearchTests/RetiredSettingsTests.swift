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
        XCTAssertEqual(RetiredSettings.fixed.count, 25)
        for (key, _) in RetiredSettings.fixed where key != "downloads.open" {
            XCTAssertEqual(store.object(forKey: key) as? Bool, true, key)
        }
        XCTAssertEqual(store.string(forKey: "downloads.open").flatMap(DownloadsOpening.init), .popover)
        // What was chosen before is kept aside; what was never set has nothing to keep.
        XCTAssertEqual(store.string(forKey: RetiredSettings.aside("downloads.open")), "tab")
        XCTAssertEqual(store.object(forKey: RetiredSettings.aside("tabs.give")) as? Bool, false)
        XCTAssertNil(store.object(forKey: RetiredSettings.aside("commandbar")))

        // Again: already as fixed, nothing more is put aside.
        RetiredSettings.settle(store)
        XCTAssertEqual(store.string(forKey: RetiredSettings.aside("downloads.open")), "tab")
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
            XCTAssertLessThanOrEqual(rows.count - first.count, 12, page.rawValue)
        }
    }

    func testDeveloperRowsAreBehindTheirOwnLine() {
        let developer = Set(SettingsIndex.items(in: SettingsIndex.developer).map(\.id))
        XCTAssertEqual(developer, ["inspector.chrome", "inspector.dark", "sites.styles", "clear.cache", "devtools", "bench", "agents"])
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
        XCTAssertLessThanOrEqual(drawn.count, 75)
    }
}
