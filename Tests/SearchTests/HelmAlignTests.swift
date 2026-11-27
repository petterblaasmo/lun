import AppKit
import SwiftUI
import XCTest
@testable import Search

/// Back, forward and reload beside the window's buttons (upstream #1633,
/// idea 1276), drawn offscreen, never in a window: their symbols sit on the
/// line through the centres of the window's three buttons, and with nowhere
/// to go they are dimmed but still plain to see.
@MainActor
final class HelmAlignTests: XCTestCase {
    override class func setUp() { TestWorld.enter(); super.setUp() }

    /// Rows of ink, darkest ink, drawn on the ground in a band as tall as
    /// the strip the lights are centred in.
    private func ink(_ view: some View, band: CGFloat, dark: Bool = false) throws
        -> (top: CGFloat, bottom: CGFloat, darkest: CGFloat, ground: CGFloat) {
        let host = NSHostingView(rootView: view.frame(width: 120, height: band).background(Palette.ground))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = CGRect(x: 0, y: 0, width: 120, height: band)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let scale = CGFloat(rep.pixelsHigh) / band
        func level(_ x: Int, _ y: Int) -> CGFloat? {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return nil }
            return dark ? max(c.redComponent, c.greenComponent, c.blueComponent)
                        : min(c.redComponent, c.greenComponent, c.blueComponent)
        }
        let ground = try XCTUnwrap(level(0, 0))
        var top = Int.max, bottom = -1
        var darkest = ground
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let l = level(x, y) else { continue }
                if abs(l - ground) > 0.03 { top = min(top, y); bottom = max(bottom, y) }
                darkest = dark ? max(darkest, l) : min(darkest, l)
            }
        }
        XCTAssertLessThan(top, Int.max, "nothing drawn")
        return (CGFloat(top) / scale, CGFloat(bottom + 1) / scale, darkest, ground)
    }

    func testOnTheLightsLineAndDimmedNotGone() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        browser.closeAll()
        // A new tab: nowhere to go back or forward to, so all three dimmed.
        let band = Lights.centre.y * 2
        let drawn = try ink(Helm(browser: browser), band: band)
        let centre = (drawn.top + drawn.bottom) / 2
        XCTAssertEqual(centre, Lights.centre.y, accuracy: 0.5, "the symbols' middle is the lights' middle")
        try dimmedNotGone(drawn, band: band, dark: false)
    }

    func testDimmedNotGoneInTheDark() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        browser.closeAll()
        let band = Lights.centre.y * 2
        try dimmedNotGone(try ink(Helm(browser: browser), band: band, dark: true), band: band, dark: true)
    }

    /// Dimmed as every button that can't be pressed (Gives): further off the
    /// ground than the 0.3 of the ground's grey the doors were drawn at,
    /// which all but hid them, and still well short of a door that can be
    /// used.
    private func dimmedNotGone(_ drawn: (top: CGFloat, bottom: CGFloat, darkest: CGFloat, ground: CGFloat),
                               band: CGFloat, dark: Bool) throws {
        let lit = try ink(Door(icon: "chevron.left") {}, band: band, dark: dark)
        let was = try ink(Door(icon: "chevron.left") {}.opacity(0.3), band: band, dark: dark)
        func off(_ level: CGFloat) -> CGFloat { abs(level - drawn.ground) }
        XCTAssertGreaterThan(off(drawn.darkest), off(was.darkest) * 1.2, "dimmed doors are still plain to see")
        XCTAssertLessThan(off(drawn.darkest), off(lit.darkest) * 0.6, "and plainly dimmer than a door that can be used")
    }
}
