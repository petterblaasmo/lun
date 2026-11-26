import AppKit
import XCTest
@testable import Search

/// A tab keeps its page's icon when the look goes from dark to light and
/// the light one has not come yet, also once another page of its site gets
/// its own. The lists (History, bookmarks) go by this look's alone.
@MainActor
final class IconLookTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    func testATabKeepsItsDarkIconInTheLightUntilItsLightOneComes() async throws {
        _ = NSApplication.shared
        let look = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .aqua)
        defer { NSApp.appearance = look }
        XCTAssertFalse(Favicons.dark)

        let icons = Favicons.shared
        let site = "\(UUID().uuidString.lowercased()).example"
        let sent = try XCTUnwrap(URL(string: "https://\(site)/sent"))
        let inbox = try XCTUnwrap(URL(string: "https://\(site)/inbox"))
        // Seen only in the dark: nothing kept for the light.
        await icons.download([try icon(.blue)], site: site, page: "/sent", dark: true, shy: false)
        XCTAssertNil(icons.cached(for: sent), "a list shows its letter, not a drawing made for the dark")
        let dark = try XCTUnwrap(icons.worn(for: sent), "a tab wears the page's dark icon meanwhile")

        let tab = Tab(bench: true)
        defer { tab.close() }
        tab.restore(url: sent, title: "sent")
        XCTAssertTrue(tab.icon === dark)

        // Another page of the site gets its light icon, and every tab of
        // the site is asked to put its icon on again.
        await icons.download([try icon(.red)], site: site, page: "/inbox", dark: false, shy: false)
        let light = try XCTUnwrap(icons.cached(for: inbox))
        XCTAssertFalse(light === dark)
        tab.adoptIcon()
        XCTAssertTrue(tab.icon === dark, "the tab kept its icon, where it fell back to its letter")

        // Its own light one comes, and is worn.
        await icons.download([try icon(.green)], site: site, page: "/sent", dark: false, shy: false)
        tab.adoptIcon()
        XCTAssertTrue(tab.icon === icons.cached(for: sent))
        XCTAssertFalse(tab.icon === dark)
    }

    private enum Ink: Int { case red, green, blue }

    /// A small PNG of one colour, as a data: address a page could declare.
    private func icon(_ ink: Ink) throws -> URL {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try XCTUnwrap(rep.bitmapData)
        for y in 0..<16 {
            for x in 0..<16 {
                let at = y * rep.bytesPerRow + x * 4
                for part in 0..<3 { bytes[at + part] = part == ink.rawValue ? 220 : 40 }
                bytes[at + 3] = 255
            }
        }
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        return try XCTUnwrap(URL(string: "data:image/png;base64," + png.base64EncodedString()))
    }
}
