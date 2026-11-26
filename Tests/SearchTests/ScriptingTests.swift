import AppKit
import XCTest
@testable import Search

/// AppleScript's `current tab`, which a script may also set: one of the
/// window's own tabs comes to the front, and nothing else is taken.
@MainActor
final class ScriptingTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func setUp() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
    }

    private var made: [(Browser, NSWindow)] = []

    override func tearDown() async throws {
        for (browser, _) in made {
            if Browsers.all.contains(where: { $0 === browser }) { Browsers.discard(browser) }
            browser.window = nil
            // Nothing of these windows for the next test's to start with:
            // a session left behind comes back as its first tabs.
            Session.write(now: true, space: browser.spaceID, Session.Shape(tabs: [], active: 0))
        }
        made = []
    }

    /// A window with three pages, none loaded, the last one in front.
    private func makeWindow() throws -> (Browser, NSWindow, [Tab]) {
        let browser = Browser(record: WindowRecord())
        browser.welcoming = false
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        browser.window = window
        Browsers.register(browser)
        made.append((browser, window))
        var tabs: [Tab] = []
        for name in ["one", "two", "three"] {
            let tab = Tab()
            tab.restore(url: try XCTUnwrap(URL(string: "https://\(name).example/")), title: name)
            browser.prepare(tab)
            browser.insert(tab, at: browser.tabs.count)
            tabs.append(tab)
        }
        browser.select(tabs[2])
        return (browser, window, tabs)
    }

    func testSettingTheCurrentTabGoesToIt() throws {
        let (browser, window, tabs) = try makeWindow()
        XCTAssertEqual(browser.activeID, tabs[2].id)
        let listed = window.scriptTabs
        XCTAssertEqual(listed.count, browser.tabs.count)
        let wanted = try XCTUnwrap(browser.tabs.firstIndex { $0 === tabs[0] })

        // As Cocoa scripting sets it: by the key Search.sdef names.
        window.setValue(listed[wanted], forKey: "scriptCurrentTab")
        XCTAssertEqual(browser.activeID, tabs[0].id)
        XCTAssertTrue(Scripting.front(of: window)?.tab === tabs[0])
        XCTAssertEqual(Scripting.front(of: window)?.index, wanted)

        // The tab already in front: nothing to do, and no refusal.
        XCTAssertTrue(Scripting.go(to: window.scriptTabs[wanted], in: window))
        XCTAssertEqual(browser.activeID, tabs[0].id)
    }

    func testOnlyATabOfThatWindowIsTaken() throws {
        let (browser, window, _) = try makeWindow()
        let (other, otherWindow, _) = try makeWindow()
        let front = browser.activeID
        let otherFront = other.activeID
        let rows = (browser.tabs.map(\.id), other.tabs.map(\.id))

        XCTAssertFalse(Scripting.go(to: otherWindow.scriptTabs[0], in: window), "another window's tab")
        XCTAssertFalse(Scripting.go(to: nil, in: window), "missing value")
        XCTAssertEqual(browser.activeID, front)
        XCTAssertEqual(other.activeID, otherFront)
        XCTAssertEqual(browser.tabs.map(\.id), rows.0)
        XCTAssertEqual(other.tabs.map(\.id), rows.1)

        // A window that is no browser's has no tabs to go to.
        let plain = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        plain.isReleasedWhenClosed = false
        XCTAssertFalse(Scripting.go(to: window.scriptTabs[0], in: plain))
        XCTAssertEqual(browser.activeID, front)
    }

    func testAPrivateTabIsNeverGoneTo() throws {
        let (browser, window, tabs) = try makeWindow()
        let shy = Tab(shy: true)
        shy.restore(url: try XCTUnwrap(URL(string: "https://private.example/")), title: "private")
        browser.prepare(shy)
        browser.insert(shy, at: browser.tabs.count)
        browser.select(shy)
        XCTAssertEqual(browser.activeID, shy.id)
        // In front and private: no current tab, and not among the tabs.
        XCTAssertNil(window.scriptCurrentTab)
        XCTAssertEqual(window.scriptTabs.count, browser.tabs.count - 1)
        XCTAssertFalse(Scripting.shown(in: window).contains { $0 === shy })

        // A script's own stand-in for it is refused: it is not in the list.
        XCTAssertFalse(Scripting.go(to: ScriptTab(shy, index: 0, in: window), in: window))
        XCTAssertEqual(browser.activeID, shy.id)

        // Away from it, to a tab the script was shown, is allowed.
        let listed = window.scriptTabs
        let at = try XCTUnwrap(browser.tabs.filter { !$0.shy }.firstIndex { $0 === tabs[1] })
        XCTAssertTrue(Scripting.go(to: listed[at], in: window))
        XCTAssertEqual(browser.activeID, tabs[1].id)
    }

    /// The dictionary says what the code does: `current tab` can be set,
    /// there is a `set` to set it with, and everything else is to read.
    func testTheDictionaryLetsCurrentTabBeSet() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sdef = try XMLDocument(contentsOf: root.appendingPathComponent("Search.sdef"))
        let properties = try sdef.nodes(forXPath: "//property").compactMap { $0 as? XMLElement }
        let writable = properties.filter { $0.attribute(forName: "access")?.stringValue != "r" }
        XCTAssertEqual(writable.map { $0.attribute(forName: "name")?.stringValue }, ["current tab"])
        XCTAssertEqual(writable.first?.attribute(forName: "access")?.stringValue, "rw")
        let keys = try sdef.nodes(forXPath: "//property[@name='current tab']/cocoa/@key").compactMap(\.stringValue)
        XCTAssertEqual(keys, ["scriptCurrentTab"])
        let commands = try sdef.nodes(forXPath: "//command/cocoa/@class").compactMap(\.stringValue)
        XCTAssertEqual(Set(commands), ["NSCountCommand", "NSSetCommand"])
        let elements = try sdef.nodes(forXPath: "//element/@access").compactMap(\.stringValue)
        XCTAssertTrue(elements.allSatisfy { $0 == "r" })
    }
}
