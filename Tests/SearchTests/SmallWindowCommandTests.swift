import AppKit
import XCTest
@testable import Search

/// Print, Share, Save Page As and Export as PDF in a small window are about
/// its own page, not the browser's tab behind it. No sheet is ever opened
/// here: which page a command is about is asked (Browser.filed), and the
/// key is pressed on a small window with nothing to print.
@MainActor
final class SmallWindowCommandTests: XCTestCase {
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
        browser.closeAll()
    }

    override func tearDown() {
        for little in LittleWindow.all { little.close() }
        browser?.closeAll()
        browser = nil
        super.tearDown()
    }

    private func tab(_ name: String) -> Tab {
        let tab = Tab(configuration: Web.configuration(space: browser.spaceID))
        tab.restore(url: URL(string: "about:blank#\(name)")!, title: name)
        return tab
    }

    private func little(_ tab: Tab) throws -> (LittleWindow, NSWindow) {
        LittleWindow.show(tab, for: browser, front: false)
        let little = try XCTUnwrap(LittleWindow.all.last)
        return (little, try XCTUnwrap(NSApp.window(withWindowNumber: little.windowNumber)))
    }

    func testTheCommandsAreAboutTheSmallWindowsPageWhileItHasTheKeys() throws {
        let (a, b) = (tab("A"), tab("B"))
        browser.showRow([a, b], active: a.id)
        let (small, window) = try little(tab("Receipt"))
        XCTAssertTrue(browser.filed(in: window) === small.tab, "the small window's own page, not the tab in front")
        XCTAssertTrue(browser.filed(in: nil) === a)
        XCTAssertTrue(browser.filed(in: NSWindow()) === a, "any other window: the tab in front, as before")
        small.close()
        XCTAssertTrue(browser.filed(in: window) === a, "closed, it has no page to be about")
    }

    /// ⌘P is the small window's, not left to File › Print…, which is greyed
    /// by the browser's tab. Its page here is empty, so nothing is printed.
    func testTheSmallWindowTakesPrintItself() throws {
        let empty = Tab(configuration: Web.configuration(space: browser.spaceID))
        XCTAssertFalse(empty.isWeb)
        let (_, window) = try little(empty)
        let press = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "p", charactersIgnoringModifiers: "p", isARepeat: false, keyCode: 35))
        XCTAssertNil(LittleWindow.handle(press))
    }
}
