import AppKit
import XCTest
@testable import Search

/// With its last window closed the app keeps running, and the menus act on
/// that window's browser. A new tab asked for then brings the window back
/// first, instead of being made where nobody sees it.
@MainActor
final class ShutWindowNewTabTests: XCTestCase {
    private var browser: Browser!

    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        browser = Browser(record: WindowRecord())
    }

    override func tearDown() {
        browser?.closeAll()
        browser = nil
        super.tearDown()
    }

    func testANewTabBringsTheShutWindowBack() {
        browser.shut = true

        browser.launch()

        XCTAssertFalse(browser.shut)
    }

    func testANewPrivateTabBringsTheShutWindowBack() {
        browser.shut = true

        browser.newShyTab()

        XCTAssertFalse(browser.shut)
        XCTAssertEqual(browser.active?.shy, true)
    }

    /// One tucked behind another profile's window is not a closed window:
    /// a new tab in it brings nothing forward.
    func testATuckedWindowIsLeftWhereItIs() {
        browser.tucked = true
        browser.shut = true

        browser.launch()

        XCTAssertTrue(browser.shut)
        XCTAssertTrue(browser.tucked)
    }
}
