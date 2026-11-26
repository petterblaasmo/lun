import AppKit
import WebKit
import XCTest
@testable import Search

/// window.close() from a page: it closes a tab a page opened (a sign-in
/// window, once done), and never one you opened yourself.
@MainActor
final class SelfClosingTabTests: XCTestCase {
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
        browser?.closeAll()
        browser = nil
        super.tearDown()
    }

    private func tab(_ name: String, from opener: Tab? = nil) -> Tab {
        let tab = Tab(configuration: Web.configuration(space: browser.spaceID))
        tab.opener = opener?.id
        tab.restore(url: URL(string: "about:blank#\(name)")!, title: name)
        browser.prepare(tab)
        return tab
    }

    func testATabYouOpenedStaysWhenItsPageClosesItself() {
        let before = tab("before")
        let yours = tab("yours")
        browser.showRow([before, yours], active: yours.id)

        browser.webViewDidClose(yours.web)

        XCTAssertEqual(browser.tabs.map(\.id), [before.id, yours.id])
        XCTAssertEqual(browser.activeID, yours.id)
    }

    func testATabAPageOpenedClosesItselfAndYouAreBackOnThatPage() {
        let other = tab("other")
        let page = tab("page")
        let signIn = tab("sign-in", from: page)
        browser.showRow([page, other, signIn], active: signIn.id)

        browser.webViewDidClose(signIn.web)

        XCTAssertEqual(browser.tabs.map(\.id), [page.id, other.id])
        XCTAssertEqual(browser.activeID, page.id)
    }
}
