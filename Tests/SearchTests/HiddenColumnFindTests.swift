import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import Search

/// The column hidden until the pointer reaches the edge, with Find on Page
/// open in Split View: the column stood out while the pointer was over the
/// page and went as it came to the edge. The Find bar there is in a hosting
/// view of its own, and it watched the whole Browser, though all it draws is
/// in `seeking`. A second host hearing `peeking` announced had SwiftUI draw
/// the window in the middle of the announcement, the old value still in
/// place, and the column stayed one step behind from then on. Which host
/// hears first is settled anew for every window, so several are tried.
@MainActor
final class HiddenColumnFindTests: XCTestCase {
    private var browsers: [Browser] = []
    private var windows: [NSWindow] = []
    private var restorePreferences: (() -> Void)?
    private var activationPolicy: NSApplication.ActivationPolicy?

    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func tearDown() async throws {
        for window in windows { window.contentView = nil; window.close() }
        for browser in browsers { browser.closeAll() }
        restorePreferences?()
        if let activationPolicy { NSApp.setActivationPolicy(activationPolicy) }
        windows.removeAll()
        browsers.removeAll()
        try await Task.sleep(for: .milliseconds(400))
        try await super.tearDown()
    }

    func testTheColumnIsDrawnWhereItIsWithFindOpenInSplitView() async throws {
        for round in 1...6 {
            let (browser, window, web) = try await makeWindow()
            XCTAssertFalse(columnIsOut(in: window, over: web), "window \(round): hidden to begin with")
            browser.openFind()
            try await settle()
            XCTAssertTrue(browser.finding)
            for turn in 1...2 {
                browser.peek(true)
                try await settle()
                XCTAssertTrue(columnIsOut(in: window, over: web), "window \(round), turn \(turn): out over the page")
                browser.peek(false)
                try await settle()
                XCTAssertFalse(columnIsOut(in: window, over: web), "window \(round), turn \(turn): away again")
            }
        }
    }

    // MARK: - helpers

    /// Whether a press a hundred points in from the column's edge would land
    /// on the column rather than on the page: where it is drawn, and hit.
    private func columnIsOut(in window: NSWindow, over web: WKWebView) -> Bool {
        guard let frame = window.contentView?.superview ?? window.contentView else { return false }
        let hit = frame.hitTest(frame.convert(NSPoint(x: 100, y: window.frame.height / 2), from: nil))
        return !(hit === web || hit?.isDescendant(of: web) == true)
    }

    private func makeWindow() async throws -> (Browser, NSWindow, WKWebView) {
        _ = NSApplication.shared
        if activationPolicy == nil {
            activationPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.prohibited)
            let prefs = Shared.prefs
            let previous = (prefs.sidebar, prefs.splitView, prefs.sideHides, prefs.sidePosition)
            restorePreferences = { (prefs.sidebar, prefs.splitView, prefs.sideHides, prefs.sidePosition) = previous }
        }
        let browser = Browser(record: WindowRecord())
        browsers.append(browser)
        browser.prefs.sidebar = true
        browser.prefs.sidePosition = .left
        browser.prefs.splitView = true
        browser.prefs.sideHides = true
        browser.folded = true
        // The welcome would lie over the whole window.
        browser.welcoming = false
        let tab = browser.benchOpen(URL(string: "about:blank#one")!)
        browser.activeID = tab.id
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 1000, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(browser: browser))
        window.orderFrontRegardless()
        windows.append(window)
        browser.window = window
        try await Task.sleep(for: .milliseconds(600))
        return (browser, window, try XCTUnwrap(tab.built))
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(350))
    }
}
