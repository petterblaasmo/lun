import AppKit
import SwiftUI
import XCTest
@testable import Search

/// Settings › Privacy › "Show Sites…": the row's pill lets the list of what
/// each site was answered down under it, where the list hung there by
/// itself and the pill forgot every answer at once. Forget All… is in the
/// list. Nothing new is kept: the list is read from the answers.
@MainActor
final class ShowSitesTests: XCTestCase {
    private var browsers: [Browser] = []

    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func tearDown() async throws {
        for key in Store.settings.dictionaryRepresentation().keys where key.hasPrefix("capture.") {
            Store.settings.removeObject(forKey: key)
        }
        for browser in browsers { browser.closeAll() }
        browsers.removeAll()
        try await super.tearDown()
    }

    func testThePillSaysWhatItWillDo() {
        XCTAssertEqual(SettingsPanel.sitesPill(shown: false), "Show Sites…", "The board's words")
        XCTAssertEqual(SettingsPanel.sitesPill(shown: true), "Hide Sites")
        // What forgets every answer still asks first, in its own words.
        XCTAssertEqual(SettingsPanel.Wiping.choices.yes, "Forget")
        XCTAssertTrue(SettingsPanel.Wiping.choices.question.hasSuffix("?"))
    }

    func testTheSitesAreListedByNameEachWithItsAnswers() throws {
        let suite = "ShowSitesTests.\(UUID())"
        let settings = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { settings.removePersistentDomain(forName: suite) }
        CaptureChoices.set(true, for: .camera, origin: "https://meet.example", in: settings)
        CaptureChoices.set(true, for: .microphone, origin: "https://meet.example", in: settings)
        CaptureChoices.set(false, for: .location, origin: "https://kart.example", in: settings)
        CaptureChoices.set(true, for: .notifications, origin: "https://tide.example", in: settings)
        let saved = CaptureChoices.saved(in: settings)

        let all = PermissionSites.listed(saved, kind: nil, matching: "")
        XCTAssertEqual(all.map(\.origin), ["https://kart.example", "https://meet.example", "https://tide.example"])
        XCTAssertEqual(all[1].entries.map(\.kind), [.camera, .microphone])
        XCTAssertEqual(all[0].entries.map(\.choice), [.refuse])

        let cameras = PermissionSites.listed(saved, kind: .camera, matching: "")
        XCTAssertEqual(cameras.map(\.origin), ["https://meet.example"])
        XCTAssertEqual(cameras[0].entries.map(\.kind), [.camera], "Only the permission picked")

        XCTAssertEqual(PermissionSites.listed(saved, kind: nil, matching: "  TIDE ").map(\.origin), ["https://tide.example"])
        XCTAssertTrue(PermissionSites.listed(saved, kind: .location, matching: "tide").isEmpty)
        XCTAssertTrue(PermissionSites.listed([], kind: nil, matching: "").isEmpty)
    }

    // MARK: drawn

    private func picture(_ view: some View, dark: Bool, name: String) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.frame(width: 600).padding(16).background(Palette.ground))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if let folder = ProcessInfo.processInfo.environment["LUN_PICTURES"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
        return rep
    }

    /// The row as Settings draws it, shut and with its list let down.
    func testTheListIsUnderItsRowOnlyOnceAskedFor() throws {
        let browser = Browser(record: WindowRecord())
        browsers.append(browser)
        let prefs = Shared.prefs
        let item = try XCTUnwrap(SettingsIndex.items.first { $0.id == "privacy.forget" })
        func row(shown: Bool) -> some View {
            Card {
                SettingRow(icon: item.icon, title: item.title, detail: item.detail) {
                    Pill(SettingsPanel.sitesPill(shown: shown)) {}
                }
                if shown {
                    PermissionSites(browser: browser, prefs: prefs, forgetAll: {})
                }
            }
        }
        for dark in [false, true] {
            let look = dark ? "dark" : "light"
            for key in Store.settings.dictionaryRepresentation().keys where key.hasPrefix("capture.") {
                Store.settings.removeObject(forKey: key)
            }
            let shut = try picture(row(shown: false), dark: dark, name: "sites-shut")
            // Asked for with nothing answered yet: it says so.
            let empty = try picture(row(shown: true), dark: dark, name: "sites-none")
            XCTAssertGreaterThan(empty.size.height, shut.size.height + 30, "\(look): an empty list says it is empty")

            CaptureChoices.set(true, for: .camera, origin: "https://meet.example")
            CaptureChoices.set(true, for: .microphone, origin: "https://meet.example")
            CaptureChoices.set(false, for: .location, origin: "https://kart.example")
            CaptureChoices.set(true, for: .notifications, origin: "https://tide.example")
            let open = try picture(row(shown: true), dark: dark, name: "sites-shown")
            // Its head (the words, the field, the filter and Forget All…)
            // and a line of 44 points and a hairline for each of three sites.
            XCTAssertGreaterThan(open.size.height, shut.size.height + 3 * 44 + 60, "\(look): three sites under the row")
            XCTAssertGreaterThan(open.size.height, empty.size.height, look)
        }
    }
}
