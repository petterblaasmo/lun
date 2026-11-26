import AppKit
import SwiftUI
import XCTest
@testable import Search

/// The Downloads page as the board has it: this week's pictures shown
/// large, and over the list how many files it holds and what they come to.
/// Nothing is kept for it: a file's size is asked of the file.
final class DownloadsTallyTests: XCTestCase {
    func testTheTallySaysHowManyAndHowMuch() {
        XCTAssertEqual(DownloadsPanel.tally(files: 1, bytes: nil), "1 file")
        XCTAssertEqual(DownloadsPanel.tally(files: 3, bytes: nil), "3 files", "Not yet measured: the count alone")
        XCTAssertEqual(DownloadsPanel.tally(files: 3, bytes: 0), "3 files", "Nothing to weigh says nothing")
        let size = ByteCountFormatter.string(fromByteCount: 1_400_000_000, countStyle: .file)
        XCTAssertEqual(DownloadsPanel.tally(files: 214, bytes: 1_400_000_000), "214 files, \(size)")
        XCTAssertEqual(DownloadsPanel.tally(files: 1, bytes: 1_400_000_000), "1 file, \(size)")
    }

    func testFilesAreWeighedWhereTheyLieAndOnesGoneCountForNothing() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("downloads-tally-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = folder.appendingPathComponent("ferry-timetable.pdf"), two = folder.appendingPathComponent("week-48.ics")
        try Data(count: 3_000).write(to: one)
        try Data(count: 1_200).write(to: two)
        XCTAssertEqual(DownloadsPanel.bytes(of: [one.path, two.path]), 4_200)
        XCTAssertEqual(DownloadsPanel.bytes(of: [one.path, folder.appendingPathComponent("moved-or-deleted.pdf").path]), 3_000)
        XCTAssertEqual(DownloadsPanel.bytes(of: []), 0)
    }

    func testThisWeeksPicturesAreThisWeeks() throws {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        func day(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
        }
        // Thursday 26 November 2026; its week runs Monday 23 to Sunday 29.
        let now = try day(2026, 11, 26)
        XCTAssertTrue(DownloadsPanel.thisWeek(now, now: now, calendar: calendar))
        XCTAssertTrue(DownloadsPanel.thisWeek(try day(2026, 11, 23), now: now, calendar: calendar), "Monday")
        XCTAssertFalse(DownloadsPanel.thisWeek(try day(2026, 11, 22), now: now, calendar: calendar), "The Sunday before")
        XCTAssertFalse(DownloadsPanel.thisWeek(try day(2025, 11, 26), now: now, calendar: calendar), "The same week a year ago")
    }
}

/// The Downloads page drawn in a tab, in a borderless window far off every
/// screen: a picture from this week is shown large over the list, and the
/// same file from a month ago is only a line of it. LUN_PICTURES keeps the
/// pictures.
@MainActor
final class DownloadsPageDrawnTests: XCTestCase {
    private var browsers: [Browser] = []
    private var windows: [NSWindow] = []
    private var folder: URL?
    private var added: [Keep] = []

    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func tearDown() async throws {
        for keep in added { Shared.loot.forget(keep) }
        added.removeAll()
        for window in windows { window.contentView = nil; window.close() }
        for browser in browsers { browser.closeAll() }
        windows.removeAll()
        browsers.removeAll()
        if let folder { try? FileManager.default.removeItem(at: folder) }
        try await Task.sleep(for: .milliseconds(200))
        try await super.tearDown()
    }

    /// A small picture of two greys and a hill, so a thumbnail has
    /// something to show.
    private func hill(to url: URL, sky: CGFloat, land: CGFloat) throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 192, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep)).cgContext
        context.setFillColor(gray: sky, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 192))
        context.setFillColor(gray: land, alpha: 1)
        context.move(to: CGPoint(x: 0, y: 0))
        context.addLine(to: CGPoint(x: 0, y: 60))
        context.addLine(to: CGPoint(x: 90, y: 130))
        context.addLine(to: CGPoint(x: 170, y: 70))
        context.addLine(to: CGPoint(x: 230, y: 110))
        context.addLine(to: CGPoint(x: 300, y: 50))
        context.addLine(to: CGPoint(x: 300, y: 0))
        context.closePath()
        context.fillPath()
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    private func picture(_ host: NSView, dark: Bool, name: String?) async throws -> NSBitmapImageRep {
        try await Task.sleep(for: .milliseconds(700))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if let name, let folder = ProcessInfo.processInfo.environment["LUN_PICTURES"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
        return rep
    }

    /// How much of the page differs between two pictures of it, in square
    /// points: the same on a screen of one pixel to the point as of two.
    private func differs(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> CGFloat {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return .infinity }
        let scale = CGFloat(a.pixelsWide) / a.size.width
        var count = 0
        for y in 0..<a.pixelsHigh {
            for x in 0..<a.pixelsWide {
                guard let p = a.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let q = b.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                // As little as a tile's ground on the page's counts: the
                // picture itself may still be on its way.
                if abs(p.redComponent - q.redComponent) > 0.03 { count += 1 }
            }
        }
        return CGFloat(count) / (scale * scale)
    }

    func testThisWeeksPicturesAreShownLargeAndOlderOnesAreNot() async throws {
        _ = NSApplication.shared
        let folder = TestWorld.home.appendingPathComponent("downloads-drawn-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        let browser = Browser(record: WindowRecord())
        browsers.append(browser)
        let loot = browser.loot

        func keep(_ name: String, from: String, bytes: Int? = nil, ago days: Double) throws -> Keep {
            let file = folder.appendingPathComponent(name)
            if let bytes { try Data(count: bytes).write(to: file) }
            let keep = Keep(name: name, from: from, path: file.path, date: Date().addingTimeInterval(-days * 86_400))
            added.append(keep)
            return keep
        }
        try hill(to: folder.appendingPathComponent("geirangerfjord-from-the-deck.png"), sky: 0.86, land: 0.52)
        try hill(to: folder.appendingPathComponent("lofoten-at-midnight.png"), sky: 0.90, land: 0.62)
        let files = [
            try keep("hurtigruten-deck-plans.pdf", from: "kart.example", bytes: 4_800_000, ago: 14),
            try keep("week-48.ics", from: "tide.example", bytes: 3_000, ago: 1),
            try keep("waffle-iron-manual.pdf", from: "kettle.example", bytes: 1_200_000, ago: 0),
            try keep("trip-budget-west-norway.csv", from: "ledger.example", bytes: 14_000, ago: 0),
            try keep("geirangerfjord-from-the-deck.png", from: "atlas.example", ago: 0),
        ]
        // The same picture twice over: once from a month ago, once from now.
        let old = try keep("lofoten-at-midnight.png", from: "atlas.example", ago: 30)
        let new = Keep(name: old.name, from: old.from, path: old.path, date: Date())

        for dark in [false, true] {
            let look = dark ? "dark" : "light"
            for file in files { loot.add(file) }
            loot.add(old)
            let page = DownloadsPanel(browser: browser, loot: loot).environment(\.asTab, true)
                .frame(width: 900, height: 520).background(Palette.ground)
            let host = NSHostingView(rootView: page)
            let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 520),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            window.orderFrontRegardless()
            windows.append(window)

            let one = try await picture(host, dark: dark, name: nil)
            loot.add(new)
            let two = try await picture(host, dark: dark, name: "downloads")
            // A second picture in the row over the list: 150 by 96 points
            // of it, where there was the page's ground.
            XCTAssertGreaterThan(differs(one, two), 150 * 96 * 0.6, "\(look): this week's picture is shown large")
            XCTAssertEqual(DownloadsPanel.bytes(of: files.map(\.path)), 4_800_000 + 3_000 + 1_200_000 + 14_000
                           + DownloadsPanel.bytes(of: [files[4].path]), look)
            window.contentView = nil
        }
    }
}
