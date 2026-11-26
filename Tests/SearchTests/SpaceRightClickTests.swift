import AppKit
import SwiftUI
import XCTest
@testable import Search

/// A right-click on a space's dot opens the space's menu: on the one you're
/// in, and on another, which takes you there first so the menu is its own.
@MainActor
final class SpaceRightClickTests: XCTestCase {
    private var windows: [NSWindow] = []

    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func tearDown() async throws {
        for window in windows { window.contentView = nil; window.close() }
        windows.removeAll()
        try await super.tearDown()
    }

    private func catchers(in view: NSView) -> [RightClick.Catcher] {
        (view as? RightClick.Catcher).map { [$0] } ?? [] + view.subviews.flatMap(catchers(in:))
    }

    func testEveryDotAnswersARightClickWithItsSpacesMenu() async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        browser.prefs.usesSpaces = true
        while browser.spaces.count < 2 { browser.addSpace(named: "Other \(browser.spaces.count)") }
        let first = browser.spaces[0], second = browser.spaces[1]
        browser.switchSpace(to: first.id)

        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 300, height: 60),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SpaceButtons(browser: browser))
        window.orderFrontRegardless()
        windows.append(window)
        try await Task.sleep(for: .milliseconds(300))

        let found = catchers(in: try XCTUnwrap(window.contentView)).sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
        XCTAssertEqual(found.count, browser.spaces.count, "a right-click catcher on every dot")
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                     windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))

        // The one you're in: its menu, and you stay there.
        let here = try XCTUnwrap(found[0].menu(for: event))
        XCTAssertTrue(here.items.contains { $0.title.hasPrefix("Rename “\(first.name)”") }, "\(here.items.map(\.title))")
        XCTAssertEqual(browser.spaceID, first.id)

        // Another: there first, then the menu is that space's.
        let other = try XCTUnwrap(found[1].menu(for: event))
        XCTAssertEqual(browser.spaceID, second.id)
        XCTAssertTrue(other.items.contains { $0.title.hasPrefix("Rename “\(second.name)”") }, "\(other.items.map(\.title))")
    }
}
