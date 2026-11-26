import AppKit
import SwiftUI
import XCTest
@testable import Search

/// History › Archived Tabs… drawn in a tab, in a borderless window far off
/// every screen: each day's tabs as tiles, their second line at 12 points
/// as every line of text is. LUN_PICTURES keeps the pictures.
@MainActor
final class ArchivePageDrawnTests: XCTestCase {
    private var browsers: [Browser] = []
    private var windows: [NSWindow] = []
    private var files: [String] = []

    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func tearDown() async throws {
        for window in windows { window.contentView = nil; window.close() }
        for browser in browsers { browser.closeAll() }
        for name in files { try? FileManager.default.removeItem(at: Store.file(name)) }
        windows.removeAll()
        browsers.removeAll()
        files.removeAll()
        try await Task.sleep(for: .milliseconds(200))
        try await super.tearDown()
    }

    private func picture(_ view: some View, dark: Bool, name: String?) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.environment(\.asTab, true).frame(width: 900, height: 440).background(Palette.ground))
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 440),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        windows.append(window)
        try await Task.sleep(for: .milliseconds(500))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if let name, let folder = ProcessInfo.processInfo.environment["LUN_PICTURES"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
        window.contentView = nil
        return rep
    }

    /// How many pixels in a band of the picture (points from the top) are
    /// not the ground's: something is drawn there.
    private func drawn(_ rep: NSBitmapImageRep, rows: Range<Int>) -> Int {
        let scale = rep.pixelsWide / max(1, Int(rep.size.width))
        guard let ground = rep.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB) else { return 0 }
        var count = 0
        for y in stride(from: rows.lowerBound * scale, to: min(rep.pixelsHigh, rows.upperBound * scale), by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if abs(c.redComponent - ground.redComponent) > 0.03 { count += 1 }
            }
        }
        return count
    }

    func testEachDaysTabsAreTilesUnderItsName() async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        browsers.append(browser)
        let name = "archive-drawn-\(UUID().uuidString).json"
        files.append(name)
        let archive = Archive(file: name)
        let now = Date()
        // Today's and yesterday's, whatever the hour the test runs at.
        let today = Calendar.current.startOfDay(for: now)
        for (index, page) in [("Deploying, Fjell docs", "docs.fjell.example/deploying", 1),
                              ("Packing list", "ledger.example/d/packing", 1),
                              ("koselig, adjective", "ord.example/koselig", 1),
                              ("Caching, Fjell docs", "docs.fjell.example/caching", 0),
                              ("Where to eat in Ålesund", "atlas.example/alesund", 0),
                              ("Bus 450, Bergen to Odda", "kart.example/routes/450", 0)].enumerated() {
            let closed = page.2 == 0 ? min(now, today.addingTimeInterval(6 * 3_600 + 2_400 * Double(index - 3)))
                                     : today.addingTimeInterval(-3_600 * Double(index + 2))
            archive.add(try XCTUnwrap(URL(string: "https://\(page.1)")), title: page.0, at: closed)
        }
        XCTAssertEqual(archive.tabs.count, 6)
        XCTAssertEqual(ArchivePanel.Tile.left(closed: now, now: now), "30 days")
        XCTAssertEqual(ArchivePanel.Tile.left(closed: now.addingTimeInterval(-28.5 * 86_400), now: now), "1 day")
        XCTAssertEqual(ArchivePanel.Tile.left(closed: now.addingTimeInterval(-40 * 86_400), now: now), "0 days", "Never less than none")
        for dark in [false, true] {
            let look = dark ? "dark" : "light"
            let rep = try await picture(ArchivePanel(browser: browser, archive: archive), dark: dark, name: "archived")
            // Two days, each with its heading and a row of tiles under it:
            // the page is drawn well below its title.
            XCTAssertGreaterThan(drawn(rep, rows: 110..<230), 2_000, "\(look): the first day's tiles")
            XCTAssertGreaterThan(drawn(rep, rows: 250..<400), 2_000, "\(look): and yesterday's")
        }
    }
}
