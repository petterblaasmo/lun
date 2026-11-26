import XCTest
@testable import Search

/// ⌃⇧↑ and ⌃⇧↓ move the tab in front one place among the tabs beside it.
@MainActor
final class MoveTabKeysTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    private func browser(_ words: [String]) -> Browser {
        let browser = Browser(record: WindowRecord())
        browser.prefs.usesTabGroups = false
        for word in words {
            if browser.tabs.last?.isBlank == false { browser.newTab() }
            browser.tabs.last?.restore(url: URL(string: "https://example.com/\(word)")!, title: word)
        }
        return browser
    }

    private func titles(_ browser: Browser) -> [String] { browser.tabs.map(\.title) }

    func testMovesOnePlaceAndStopsAtTheEnds() {
        let browser = browser(["one", "two", "three"])
        defer { browser.closeAll() }
        browser.select(browser.tabs[1])
        browser.nudgeTab(1)
        XCTAssertEqual(titles(browser), ["one", "three", "two"])
        XCTAssertEqual(browser.active?.title, "two", "the tab moved stays the one in front")
        browser.nudgeTab(1)
        XCTAssertEqual(titles(browser), ["one", "three", "two"], "the last stays last")
        browser.nudgeTab(-1)
        browser.nudgeTab(-1)
        XCTAssertEqual(titles(browser), ["two", "one", "three"])
        browser.nudgeTab(-1)
        XCTAssertEqual(titles(browser), ["two", "one", "three"], "the first stays first")
    }

    func testBothKeysAreCommandsWithTheirOwnKeys() throws {
        let up = try XCTUnwrap(Command.named("tabs.moveUp"))
        let down = try XCTUnwrap(Command.named("tabs.moveDown"))
        XCTAssertEqual(up.title, "Move Tab Up")
        XCTAssertEqual(down.title, "Move Tab Down")
        XCTAssertNotNil(ShortcutStore.shared.key(for: up.id))
        XCTAssertNotEqual(ShortcutStore.shared.key(for: up.id), ShortcutStore.shared.key(for: down.id))
    }
}
