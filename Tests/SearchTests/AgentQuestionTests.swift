import AppKit
import SwiftUI
import XCTest
@testable import Search

/// A coding agent's question (AgentBanner) on the house's controls: its two
/// boxes are the house tick, its two answers are pills, and its card is an
/// elevation. Each is still only pressed by a click that landed on it
/// (AgentRules.isClick), so the spot a click is checked against has to be
/// as large as what gives under the pointer. Drawn in a borderless window
/// far off every screen, never activated. LUN_PICTURES keeps the pictures.
@MainActor
final class AgentQuestionTests: XCTestCase {
    private var browsers: [Browser] = []
    private var windows: [NSWindow] = []

    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func tearDown() async throws {
        AgentControl.shared.showForTest(nil)
        for window in windows { window.contentView = nil; window.close() }
        for browser in browsers { browser.window = nil; browser.closeAll() }
        windows.removeAll()
        browsers.removeAll()
        try await Task.sleep(for: .milliseconds(200))
        try await super.tearDown()
    }

    /// The air left around the question, for its shadow.
    private static let air: CGFloat = 40

    /// The question up in a window of `browser`'s, asked by "Claude Code".
    private func ask(dark: Bool) async throws -> (browser: Browser, host: NSView) {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        browsers.append(browser)
        AgentControl.shared.showForTest("Claude Code", in: browser, asking: true)
        let host = NSHostingView(rootView: AgentBar(browser: browser).frame(width: 484).padding(Self.air).background(Palette.ground))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: host.fittingSize),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        windows.append(window)
        browser.window = window
        try await Task.sleep(for: .milliseconds(450))
        host.layoutSubtreeIfNeeded()
        return (browser, host)
    }

    private func picture(_ host: NSView, dark: Bool, name: String? = nil) async throws -> NSBitmapImageRep {
        try await Task.sleep(for: .milliseconds(450))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if let name, let folder = ProcessInfo.processInfo.environment["LUN_PICTURES"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
        return rep
    }

    /// Whether any pixel is a colour and not a grey: the Mac's checkbox,
    /// ticked, is the accent's blue.
    private func coloured(_ rep: NSBitmapImageRep) -> Bool {
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.5 else { continue }
                if max(c.redComponent, c.greenComponent, c.blueComponent) - min(c.redComponent, c.greenComponent, c.blueComponent) > 0.12 {
                    return true
                }
            }
        }
        return false
    }

    private func grey(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> CGFloat {
        let scale = CGFloat(rep.pixelsWide) / rep.size.width
        return rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB)?.redComponent ?? -1
    }

    func testTheQuestionIsDrawnWithTheHousesControls() async throws {
        let agents = AgentControl.shared
        for dark in [false, true] {
            let (_, host) = try await ask(dark: dark)
            let session = try XCTUnwrap(agents.session)
            let look = dark ? "dark" : "light"
            _ = try await picture(host, dark: dark, name: "agent-question")

            // Each control has its spot in the window.
            let tabs = try XCTUnwrap(agents.tabsBox), allow = try XCTUnwrap(agents.allowButton),
                refuse = try XCTUnwrap(agents.refuseButton)
            XCTAssertNotNil(tabs.window, look)
            XCTAssertNotNil(allow.window, look)
            XCTAssertNotNil(refuse.window, look)
            // The two answers are the same pill, one filled: as tall as
            // each other, where the refusal was bare words.
            XCTAssertEqual(allow.bounds.height, 28, look)
            XCTAssertEqual(refuse.bounds.height, 28, look)
            XCTAssertGreaterThan(refuse.bounds.width, 60, "\(look): Don't Allow has a ground of its own to press")
            // The box's spot is what gives under the pointer: the tick's
            // 16 points and the four over and under that Ticked takes.
            XCTAssertEqual(tabs.bounds.height, 24, accuracy: 1.5, look)

            // Ticked by a click on it, and drawn in ink: the Mac's box was
            // the accent's blue.
            let on = try XCTUnwrap(agents.madeClick(on: "tabs", inside: true, stale: false))
            agents.toggleTabs(event: on)
            XCTAssertTrue(session.wantsTabs, "\(look): a click on the box ticks it")
            let ticked = try await picture(host, dark: dark, name: "agent-question-ticked")
            XCTAssertFalse(coloured(ticked), "\(look): a tick is ink, not the accent's blue")
            // The tick itself: ink at the box's corner, inside its edge.
            let scale = host.bounds.height
            let box = tabs.convert(tabs.bounds, to: host)
            let top = host.isFlipped ? box.minY : scale - box.maxY
            XCTAssertEqual(grey(ticked, box.minX + 3, top + 4 + 3), dark ? 0.93 : 0.09, accuracy: 0.05, look)

            // A click beside the box, or one from before the question was
            // up, ticks nothing.
            agents.toggleTabs(event: agents.madeClick(on: "tabs", inside: false, stale: false))
            XCTAssertTrue(session.wantsTabs, "\(look): beside the box")
            agents.toggleTabs(event: nil)
            XCTAssertTrue(session.wantsTabs, "\(look): a press with no click behind it")

            // The card is the floating elevation: on the raised ground,
            // a step off the window's in the dark. Read in the air over
            // its words, clear of its corner.
            let inside = grey(ticked, Self.air + 16 + 100, Self.air + 8), around = grey(ticked, 4, 4)
            if dark {
                XCTAssertGreaterThan(inside, around + 0.015, "A floating card is a step lighter than the dark ground")
            } else {
                XCTAssertEqual(inside, around, accuracy: 0.01, "White on the white ground")
            }

            agents.showForTest(nil)
            windows.last?.contentView = nil
        }
    }

    /// Don't Allow answers, by a click on it and by nothing else.
    func testTheAnswersTakeOnlyAClickOnThem() async throws {
        let agents = AgentControl.shared
        let (_, _) = try await ask(dark: false)
        let session = try XCTUnwrap(agents.session)
        agents.answer(allow: true, event: agents.madeClick(on: "allow", inside: false, stale: false))
        XCTAssertEqual(session.consent.state, .asking, "A click beside Allow allows nothing")
        agents.answer(allow: true, event: agents.madeClick(on: "refuse", inside: true, stale: false))
        XCTAssertEqual(session.consent.state, .asking, "A click on Don't Allow is not one on Allow")
        agents.answer(allow: true, event: nil)
        XCTAssertEqual(session.consent.state, .asking, "A press with no click behind it")
    }
}
