import AppKit
import SwiftUI
import XCTest
@testable import Search

/// The ⌃Tab switcher drawn, and a card pressed where it is drawn: the frames
/// the cards send up are the ones a press is matched against, the card
/// pressed is drawn smaller (it gives), and the tab is taken when the button
/// comes up. In a borderless window far off every screen, never activated.
/// LUN_PICTURES keeps the pictures.
@MainActor
final class TabSwitcherPressTests: XCTestCase {
    private var windows: [NSWindow] = []

    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func tearDown() async throws {
        for window in windows { window.contentView = nil; window.close() }
        windows.removeAll()
        try await Task.sleep(for: .milliseconds(200))
        try await super.tearDown()
    }

    private func picture(_ host: NSView, dark: Bool, name: String) async throws -> NSBitmapImageRep {
        try await Task.sleep(for: .milliseconds(450))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if let folder = ProcessInfo.processInfo.environment["LUN_PICTURES"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
        return rep
    }

    /// How many pixels differ between two pictures inside `frame` (points,
    /// from the top left).
    private func differs(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, in frame: CGRect) -> Int {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return Int.max }
        let scale = CGFloat(a.pixelsWide) / a.size.width
        var count = 0
        for y in max(0, Int(frame.minY * scale))..<min(a.pixelsHigh, Int(frame.maxY * scale)) {
            for x in max(0, Int(frame.minX * scale))..<min(a.pixelsWide, Int(frame.maxX * scale)) {
                guard let p = a.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let q = b.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if abs(p.redComponent - q.redComponent) + abs(p.greenComponent - q.greenComponent)
                    + abs(p.blueComponent - q.blueComponent) > 0.06 { count += 1 }
            }
        }
        return count
    }

    func testACardDrawnGivesWhereItIsPressed() async throws {
        _ = NSApplication.shared
        let was = Motion.testReduceMotion
        Motion.testReduceMotion = false
        defer { Motion.testReduceMotion = was }
        for dark in [false, true] {
            let look = dark ? "dark" : "light"
            // Pages that are never loaded: a card's mark and its title.
            let tabs = ["Seven fjords worth the ferry", "Brown cheese waffles, done properly", "Trip budget, West Norway"]
                .enumerated().map { index, title in
                    let tab = Search.Tab()
                    tab.restore(url: URL(string: "about:blank#\(index)")!, title: title)
                    return tab
                }
            let ids = tabs.map(\.id)
            let switcher = TabSwitcher()
            switcher.step(row: ids, current: ids[0], backwards: false)
            switcher.step(row: ids, current: ids[0], backwards: false)
            XCTAssertTrue(switcher.visible, look)
            var taken: [Search.Tab.ID] = []

            let overlay = TabSwitcherOverlay(switcher: switcher, tab: { id in tabs.first { $0.id == id } }, current: nil,
                                             pick: { taken.append($0) })
            let host = NSHostingView(rootView: overlay.frame(width: 720, height: 300).background(Palette.ground))
            let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 720, height: 300),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            window.orderFrontRegardless()
            windows.append(window)

            let rest = try await picture(host, dark: dark, name: "switcher")
            XCTAssertEqual(Set(switcher.cardFrames.keys), Set(ids), "\(look): every card says where it is")
            let frame = try XCTUnwrap(switcher.cardFrames[ids[2]])
            XCTAssertTrue(switcher.panelFrame.contains(frame), "\(look): in the panel")

            // The card the keys are on, pressed: nothing else changes, so
            // what differs is the give.
            XCTAssertEqual(switcher.selectedID, ids[2], look)
            XCTAssertTrue(switcher.press(at: CGPoint(x: frame.midX, y: frame.midY)), look)
            XCTAssertEqual(switcher.pressedID, ids[2], look)
            let held = try await picture(host, dark: dark, name: "switcher-pressed")
            XCTAssertGreaterThan(differs(rest, held, in: frame), 40, "\(look): the card pressed is drawn smaller")
            let beside = try XCTUnwrap(switcher.cardFrames[ids[0]])
            XCTAssertEqual(differs(rest, held, in: beside), 0, "\(look): and no other card moves")

            XCTAssertTrue(switcher.lift(at: CGPoint(x: frame.midX, y: frame.midY)) { switcher.finish(picking: $0).map { taken.append($0) } }, look)
            XCTAssertEqual(taken, [ids[2]], "\(look): taken when the button comes up")
            XCTAssertFalse(switcher.visible, look)

            window.contentView = nil
        }
    }
}
