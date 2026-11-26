import AppKit
import SwiftUI
import XCTest
@testable import Search

/// The address field raised over a page: in a light window the page under
/// it is a step darker than the field's card, where it was white under
/// white; in a dark window it is as it was.
@MainActor
final class FieldDimTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    private var browser: Browser!
    private var hides = false

    override func setUp() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        browser = Browser(record: WindowRecord())
        browser.welcoming = false
        hides = browser.prefs.fieldHidesPage
        browser.prefs.fieldHidesPage = false
        let tab = try XCTUnwrap(browser.active ?? browser.tabs.last)
        tab.restore(url: try XCTUnwrap(URL(string: "https://one.example/")), title: "one")
        // ⌘L's field, up over the page.
        browser.inlineEdit = false
        browser.editing = true
        XCTAssertTrue(browser.fieldShowing)
        XCTAssertFalse(browser.editingInline)
    }

    override func tearDown() async throws {
        browser.editing = false
        browser.prefs.fieldHidesPage = hides
        browser.closeAll()
        browser = nil
    }

    /// A view drawn off every screen, 900 by 520, light or dark.
    private func picture(_ view: some View, dark: Bool, name: String? = nil) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.frame(width: 900, height: 520))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 520)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = host.appearance
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if let name, let folder = ProcessInfo.processInfo.environment["LUN_PICTURES"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
        return rep
    }

    /// The field over a white page, as the window draws it.
    private func field(dark: Bool) throws -> NSBitmapImageRep {
        try picture(ZStack {
            Color.white
            Omnibox(browser: browser, over: true, high: true)
        }, dark: dark, name: "field-over-page")
    }

    /// A white page under the cover alone, as it was before the dim: the
    /// ground let through at 74%.
    private func coverAlone(dark: Bool) throws -> NSBitmapImageRep {
        try picture(ZStack {
            Color.white
            Palette.ground.opacity(0.74)
        }, dark: dark)
    }

    /// 0…255 at a point from the picture's top left.
    private func grey(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> CGFloat {
        let scale = CGFloat(rep.pixelsWide) / rep.size.width
        let white = rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB)?.redComponent ?? -1
        return (white * 255).rounded()
    }

    func testALightWindowDimsThePageUnderTheField() throws {
        let rep = try field(dark: false)
        let top = Omnibox.top(in: CGSize(width: 900, height: 520))
        // The page, well clear of the card and its shadow; and the card.
        let page = grey(rep, 40, 480)
        let card = grey(rep, 450, top + 24)
        let before = grey(try coverAlone(dark: false), 40, 480)
        XCTAssertEqual(before, 255, accuracy: 1, "white let through over white was white")
        XCTAssertEqual(card, 255, accuracy: 1, "the card is the ground's white")
        // A tenth of black over it: a step darker than the card, no more.
        XCTAssertGreaterThanOrEqual(card - page, 15, "the page reads as behind the field")
        XCTAssertLessThanOrEqual(card - page, 35, "set back, not blacked out")
    }

    func testADarkWindowIsAsItWas() throws {
        let page = grey(try field(dark: true), 40, 480)
        let before = grey(try coverAlone(dark: true), 40, 480)
        XCTAssertEqual(page, before, accuracy: 1)
        XCTAssertLessThan(page, 128, "and darker than a white page already")
    }

    func testTheDimIsALightWindowsOnly() throws {
        func alpha(_ name: NSAppearance.Name) -> CGFloat {
            var found: CGFloat = -1
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                found = Palette.NS.fieldDim.usingColorSpace(.sRGB)?.alphaComponent ?? -1
            }
            return found
        }
        XCTAssertEqual(alpha(.aqua), 0.10, accuracy: 0.001)
        XCTAssertEqual(alpha(.darkAqua), 0, accuracy: 0.001)
    }
}
