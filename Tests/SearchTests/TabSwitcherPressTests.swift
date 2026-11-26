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

    /// The whole way, through the window's own monitor, which takes the
    /// click before any view does: a real mouse down on a card leaves the
    /// switcher up with that card pressed and the tab unchanged, and the
    /// mouse up takes the tab. Sent through the app, as a hand's arrive.
    func testAClickThroughTheWindowTakesTheTabWhenTheButtonComesUp() async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        browser.welcoming = false
        for number in 1...3 {
            if number > 1 { browser.newTab() }
            browser.tabs.last?.restore(url: URL(string: "about:blank#\(number)")!, title: "Tab \(number)")
        }
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 600),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(browser: browser))
        window.orderFrontRegardless()
        defer {
            ContentView.forget(browser)
            window.contentView = nil
            window.close()
            browser.closeAll()
        }
        func wait(_ what: String, until done: () -> Bool) async throws {
            for _ in 0..<150 where !done() { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertTrue(done(), what)
        }
        // The monitor is in once the window's keys are watched.
        try await wait("the window watches its keys") { ContentView.keyHooks[ObjectIdentifier(browser)] != nil }

        let switcher = browser.tabSwitcher
        let start = try XCTUnwrap(browser.activeID)
        browser.switchTabs(backwards: false)
        browser.switchTabs(backwards: false)
        XCTAssertTrue(switcher.visible)
        try await wait("every card says where it is") { switcher.cardFrames.count == 3 && switcher.panelFrame != .zero }
        let target = try XCTUnwrap(switcher.candidates.first { $0 != start && $0 != switcher.selectedID })
        let frame = try XCTUnwrap(switcher.cardFrames[target])
        let height = try XCTUnwrap(window.contentView).bounds.height
        let spot = NSPoint(x: frame.midX, y: height - frame.midY)
        func mouse(_ type: NSEvent.EventType) throws {
            NSApp.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: spot, modifierFlags: [.control], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1)))
        }

        try mouse(.leftMouseDown)
        XCTAssertEqual(switcher.pressedID, target, "The card under the button is pressed")
        XCTAssertEqual(switcher.selectedID, target)
        XCTAssertTrue(switcher.visible, "The switcher is still up while the button is down")
        XCTAssertEqual(browser.activeID, start, "and the tab is not taken yet")

        try mouse(.leftMouseUp)
        XCTAssertFalse(switcher.visible, "Let go on the card: the switcher goes")
        XCTAssertNil(switcher.pressedID)
        XCTAssertEqual(browser.activeID, target, "and the tab is the card's")
    }
}
