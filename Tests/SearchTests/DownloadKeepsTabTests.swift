import AppKit
import WebKit
import XCTest
@testable import Search

/// A download closes the tab it started in only when a link opened that tab
/// for the file and nothing was ever shown in it: never a tab with a page.
@MainActor
final class DownloadKeepsTabTests: XCTestCase {
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
        browser?.parked = [:]
        browser?.closeAll()
        browser = nil
        super.tearDown()
    }

    private func home() -> Tab {
        let tab = Tab(configuration: Web.configuration(space: browser.spaceID))
        tab.restore(url: URL(string: "about:blank#home")!, title: "home")
        return tab
    }

    private func opened(by opener: Tab? = nil) -> Tab {
        let tab = Tab(configuration: Web.configuration(space: browser.spaceID))
        tab.opener = opener?.id
        browser.prepare(tab)
        return tab
    }

    private func spin(for seconds: TimeInterval, until done: () -> Bool) {
        let end = Date().addingTimeInterval(seconds)
        repeat {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.001))
        } while !done() && Date() < end
    }

    func testATabALinkOpenedForAFileCloses() {
        let home = home()
        let link = opened(by: home)
        browser.showRow([home, link], active: link.id)

        browser.dropEmpty(link.web)

        XCTAssertEqual(browser.tabs.map(\.id), [home.id])
        XCTAssertEqual(browser.activeID, home.id, "back on the page whose link it was")
    }

    /// The tab's own word on its page can be missing; WebKit's list of what
    /// the view has shown is not.
    func testATabWithAPageBehindItStays() throws {
        let home = home()
        let link = opened(by: home)
        browser.showRow([home, link], active: link.id)
        let web = link.web
        // The page comes in unheard, as one did in a tab of another space.
        // From a file: a page given as a string leaves nothing in the list.
        web.navigationDelegate = nil
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kept-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let page = folder.appendingPathComponent("page.html")
        try Data("<p>a page</p>".utf8).write(to: page)
        web.loadFileURL(page, allowingReadAccessTo: folder)
        spin(for: 10) { web.backForwardList.currentItem != nil && !web.isLoading }
        _ = try XCTUnwrap(web.backForwardList.currentItem, "the page never came in")
        XCTAssertNil(link.committed)

        browser.dropEmpty(web)

        XCTAssertEqual(browser.tabs.map(\.id), [home.id, link.id])
        XCTAssertEqual(browser.activeID, link.id)
    }

    func testAPageThatComesInWhileItsTabIsInAnotherSpaceIsThatTabsPage() {
        let home = home()
        browser.showRow([home], active: home.id)
        let away = opened(by: home)
        browser.parked[UUID()] = Parked(tabs: [away], active: nil)
        let page = URL(string: "https://kept.invalid/arrived")!

        away.web.loadHTMLString("<p>a page</p>", baseURL: page)
        spin(for: 10) { away.committed != nil }

        XCTAssertEqual(away.committed, page)
    }
}
