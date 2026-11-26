import AppKit
import Darwin
import WebKit
import XCTest
@testable import Search

/// Pages out of sight load a few at a time (LoadTurns), and every one of
/// them does load: none is left blank, whatever the others are doing. The
/// tab on screen, and one picked while it waits, never wait; a link just
/// opened goes ahead of pages only coming back. Real pages from a loopback
/// server, in views far off every screen.
@MainActor
final class LoadTurnsTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    private var browser: Browser!
    private var window: NSWindow!
    private var server: TurnsServer!
    private var was: (most: Int, unstarted: TimeInterval, longest: TimeInterval)!

    override func setUpWithError() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        was = (LoadTurns.most, LoadTurns.unstarted, LoadTurns.longest)
        browser = Browser(record: WindowRecord())
        window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 800, height: 600),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        server = try TurnsServer()
    }

    override func tearDown() {
        server.stop()
        browser.closeAll()
        window.close()
        // Whatever the closed tabs left in turn or waiting is let go.
        spin(for: 0.05) { false }
        LoadTurns.most = was.most
        LoadTurns.unstarted = was.unstarted
        LoadTurns.longest = was.longest
        browser = nil
        window = nil
        server = nil
    }

    // MARK: - every page loads

    /// Twenty-four links opened behind the page being read, three turns:
    /// never more than three load at once, each row says it is loading from
    /// the moment it was opened, and every one of them ends up loaded, with
    /// its own page, asked for once.
    func testEveryTabOpenedBehindLoadsAndOnlyAFewAtOnce() {
        LoadTurns.most = 3
        server.reply = { path in .init(body: Self.page(path), after: 0.12) }
        let tabs = (0..<24).map { browser.open(server.url("/page/\($0)"), foreground: false) }

        XCTAssertEqual(LoadTurns.shared.loadingCount, 3, "Three start at once")
        XCTAssertEqual(LoadTurns.shared.waitingCount, 21, "The rest wait their turn")
        XCTAssertTrue(tabs.allSatisfy(\.loading), "Each says it is loading from the moment it is asked for, as it always did")
        // Quitting now would lose none of them: each is in the row to save.
        let saved = browser.session(browser.tabs, active: browser.activeID).tabs.map(\.url)
        XCTAssertEqual(saved.filter { $0.hasPrefix(server.url("/page/").absoluteString) }.count, 24)

        var most = 0
        spin(for: 90) {
            most = max(most, tabs.filter { $0.built?.isLoading == true }.count)
            return tabs.allSatisfy { !$0.loading && $0.title.hasPrefix("Page ") }
        }
        for (n, tab) in tabs.enumerated() {
            XCTAssertEqual(tab.title, "Page \(n)", "Tab \(n) has its page")
            XCTAssertFalse(tab.loading, "Tab \(n) is done")
            XCTAssertEqual(tab.built?.url, server.url("/page/\(n)"))
            XCTAssertEqual(server.requests("/page/\(n)"), 1, "Page \(n) was asked for once")
        }
        XCTAssertLessThanOrEqual(most, 3, "Never more than three loading at once")
        XCTAssertLessThanOrEqual(server.mostAtOnce, 3, "as the server saw it too")
        XCTAssertEqual(LoadTurns.shared.waitingCount, 0)
        XCTAssertEqual(LoadTurns.shared.loadingCount, 0)
        // In the order they were opened: the first three first, the last three last.
        let order = server.order.compactMap { Int($0.dropFirst("/page/".count)) }
        XCTAssertEqual(Set(order.prefix(3)), [0, 1, 2])
        XCTAssertEqual(Set(order.suffix(3)), [21, 22, 23])
    }

    /// Pages that never finish (a stream, a server that stops answering)
    /// keep their turn for `longest` and no longer: the pages behind them
    /// load all the same.
    func testPagesThatNeverFinishHoldUpNoOtherForGood() {
        LoadTurns.most = 2
        LoadTurns.longest = 0.6
        server.reply = { path in
            let n = Int(path.dropFirst("/page/".count)) ?? 0
            return .init(body: Self.page(path), stalls: n < 4)
        }
        let tabs = (0..<10).map { browser.open(server.url("/page/\($0)"), foreground: false) }
        spin(for: 60) { tabs[4...].allSatisfy { !$0.loading && $0.title.hasPrefix("Page ") } }
        for n in 4..<10 { XCTAssertEqual(tabs[n].title, "Page \(n)", "Tab \(n) loaded behind four pages that never finish") }
        for n in 0..<4 { XCTAssertEqual(server.requests("/page/\(n)"), 1, "And each of the four was asked for too") }
        XCTAssertEqual(LoadTurns.shared.waitingCount, 0)
    }

    /// A load WebKit never takes up gives its turn back after `unstarted`
    /// seconds, one that finds it is no longer wanted gives it back at once,
    /// and a view gone while it waits is passed over.
    func testATurnNeverTakenUpIsGivenBack() {
        LoadTurns.most = 1
        LoadTurns.unstarted = 1
        let turns = LoadTurns.shared
        let views = (0..<4).map { _ in PageView(frame: .zero, configuration: WKWebViewConfiguration()) }
        var ran: [Int] = []
        // Says it asked for a page, and never loads one.
        turns.start(views[0], .asked, wanted: false) { ran.append(0); return true }
        // No longer wanted by the time its turn comes.
        turns.start(views[1], .asked, wanted: false) { ran.append(1); return false }
        // A view nobody keeps: gone by the time its turn comes.
        autoreleasepool {
            let gone = PageView(frame: .zero, configuration: WKWebViewConfiguration())
            turns.start(gone, .asked, wanted: false) { ran.append(9); return true }
        }
        turns.start(views[2], .asked, wanted: false) { ran.append(2); return true }
        XCTAssertEqual(ran, [0])
        XCTAssertEqual(turns.waitingCount, 2, "The view already gone is no longer waited for")
        spin(for: 0.2) { false }
        XCTAssertEqual(ran, [0], "The turn is kept a moment for a page that hasn't begun")
        spin(for: 10) { ran.count == 3 }
        XCTAssertEqual(ran, [0, 1, 2], "Given back; the one not wanted passes it on at once; the view gone is passed over")
        spin(for: 10) { turns.loadingCount == 0 }
        XCTAssertEqual(turns.loadingCount, 0)
        XCTAssertEqual(turns.waitingCount, 0)
    }

    // MARK: - what never waits

    /// A tab picked while it waits loads as its view lands in the window,
    /// not after the pages ahead of it, and without taking a turn.
    func testATabPickedWhileItWaitsLoadsAtOnce() {
        LoadTurns.most = 2
        LoadTurns.longest = 60
        server.reply = { path in .init(body: Self.page(path), stalls: path != "/page/5") }
        let tabs = (0..<6).map { browser.open(server.url("/page/\($0)"), foreground: false) }
        spin(for: 0.3) { false }
        XCTAssertEqual(server.requests("/page/5"), 0, "Waiting behind the others")
        XCTAssertEqual(LoadTurns.shared.waitingCount, 4)

        browser.select(tabs[5])
        attach(tabs[5])
        spin(for: 5) { tabs[5].title == "Page 5" && !tabs[5].loading }
        XCTAssertEqual(tabs[5].title, "Page 5")
        XCTAssertEqual(server.requests("/page/5"), 1)
        XCTAssertEqual(LoadTurns.shared.waitingCount, 3, "The others wait on")
        XCTAssertEqual(LoadTurns.shared.loadingCount, 2, "and it took nobody's turn")
    }

    /// Picked with no stage to put its view in a window (a window out of
    /// sight): it loads all the same, a second on at most.
    func testATabPickedWithNoWindowStillLoads() {
        LoadTurns.most = 1
        LoadTurns.longest = 60
        server.reply = { path in .init(body: Self.page(path), stalls: path == "/page/0") }
        let tabs = (0..<3).map { browser.open(server.url("/page/\($0)"), foreground: false) }
        browser.select(tabs[2])
        spin(for: 8) { tabs[2].title == "Page 2" && !tabs[2].loading }
        XCTAssertEqual(tabs[2].title, "Page 2")
    }

    /// A link opened in front while every turn is taken (Browser.open sends
    /// the tab to its page, then brings it to the front): it loads at once,
    /// with no stage to put its view in a window either.
    func testALinkOpenedInFrontNeverWaits() {
        LoadTurns.most = 1
        LoadTurns.longest = 60
        server.reply = { path in .init(body: Self.page(path), stalls: path.hasPrefix("/slow/")) }
        _ = (0..<3).map { browser.open(server.url("/slow/\($0)"), foreground: false) }
        XCTAssertEqual(LoadTurns.shared.waitingCount, 2)
        let front = browser.open(server.url("/page/front"), foreground: true)
        XCTAssertEqual(browser.activeID, front.id)
        XCTAssertFalse(LoadTurns.shared.waits(for: front.web), "In front, it is out of the line")
        attach(front)
        spin(for: 5) { front.title == "Page front" && !front.loading }
        XCTAssertEqual(front.title, "Page front")
        XCTAssertEqual(LoadTurns.shared.waitingCount, 2, "The pages out of sight wait on")
    }

    /// A view put in a window any other way (a split's other page, a small
    /// window, a peek) with its load still waiting: it starts then.
    func testAViewThatComesIntoSightStartsItsLoad() {
        LoadTurns.most = 1
        LoadTurns.longest = 60
        server.reply = { path in .init(body: Self.page(path), stalls: path == "/page/0") }
        let tabs = (0..<3).map { browser.open(server.url("/page/\($0)"), foreground: false) }
        XCTAssertTrue(LoadTurns.shared.waits(for: tabs[1].web))
        attach(tabs[1])
        spin(for: 5) { tabs[1].title == "Page 1" && !tabs[1].loading }
        XCTAssertEqual(tabs[1].title, "Page 1")
        XCTAssertTrue(LoadTurns.shared.waits(for: tabs[2].web), "The one still out of sight waits on")
    }

    /// The tab on screen goes where it is sent, and reloads, at once, with
    /// every turn taken by pages out of sight.
    func testTheTabOnScreenNeverWaits() throws {
        LoadTurns.most = 2
        LoadTurns.longest = 60
        server.reply = { path in .init(body: Self.page(path), stalls: path.hasPrefix("/slow/")) }
        _ = (0..<5).map { browser.open(server.url("/slow/\($0)"), foreground: false) }
        XCTAssertEqual(LoadTurns.shared.waitingCount, 3)

        let front = try XCTUnwrap(browser.active)
        attach(front)
        front.go(to: server.url("/page/front"))
        XCTAssertTrue(front.web.isLoading, "Asked for in the same step")
        spin(for: 5) { front.title == "Page front" && !front.loading }
        XCTAssertEqual(front.title, "Page front")

        front.reload()
        XCTAssertTrue(front.web.isLoading, "Reloaded in the same step")
        spin(for: 5) { server.requests("/page/front") == 2 && !front.loading }
        XCTAssertEqual(server.requests("/page/front"), 2)
        XCTAssertEqual(LoadTurns.shared.waitingCount, 3, "The pages out of sight wait on")
    }

    /// A row of tabs reloading out of sight, more than there are turns, and
    /// a link opened behind the page being read just then: it loads before
    /// the tabs still waiting to reload.
    func testALinkJustOpenedGoesAheadOfPagesComingBack() {
        LoadTurns.most = 2
        let slow = Flag()
        server.reply = { path in .init(body: Self.page(path), after: slow.on && path != "/page/link" ? 1.5 : 0) }
        let tabs = (0..<6).map { browser.open(server.url("/page/\($0)"), foreground: false) }
        spin(for: 60) { tabs.allSatisfy { !$0.loading && $0.title.hasPrefix("Page ") } }
        XCTAssertTrue(tabs.allSatisfy { $0.title.hasPrefix("Page ") })

        slow.on = true
        server.forget()
        tabs.forEach { $0.reload() }
        XCTAssertEqual(LoadTurns.shared.waitingCount, 4, "Four of the six wait to reload")
        let link = browser.open(server.url("/page/link"), foreground: false)
        XCTAssertTrue(LoadTurns.shared.waits(for: link.web))
        // The first turn given back is the link's: the four reloads wait on.
        spin(for: 30) { !LoadTurns.shared.waits(for: link.web) }
        XCTAssertFalse(LoadTurns.shared.waits(for: link.web))
        XCTAssertGreaterThanOrEqual(LoadTurns.shared.waitingCount, 3, "It went ahead of the tabs waiting to reload")
        XCTAssertTrue(tabs[3...].allSatisfy { LoadTurns.shared.waits(for: $0.web) })

        spin(for: 60) { !link.loading && link.title == "Page link" && tabs.allSatisfy { !$0.loading } }
        XCTAssertEqual(link.title, "Page link")
        XCTAssertEqual(server.order.count, 7, "Each of the six reloaded, and the link loaded: \(server.order)")
    }

    /// A folder of bookmarks opened behind the page (Browser.open with
    /// `mayWait`), more than there are turns, and then one link opened on
    /// its own: the link is next, ahead of the bookmarks still waiting.
    func testALinkOpenedOnItsOwnGoesAheadOfManyOpenedTogether() {
        let lazy = browser.prefs.lazyTabs
        browser.prefs.lazyTabs = false
        defer { browser.prefs.lazyTabs = lazy }
        LoadTurns.most = 2
        server.reply = { path in .init(body: Self.page(path), after: path == "/page/link" ? 0 : 1.2) }
        let many = (0..<8).map { browser.open(server.url("/page/\($0)"), foreground: false, atEnd: true, mayWait: true) }
        XCTAssertEqual(LoadTurns.shared.waitingCount, 6)
        let link = browser.open(server.url("/page/link"), foreground: false)
        spin(for: 30) { !LoadTurns.shared.waits(for: link.web) }
        XCTAssertFalse(LoadTurns.shared.waits(for: link.web))
        XCTAssertTrue(many[3...].allSatisfy { LoadTurns.shared.waits(for: $0.web) }, "The bookmarks behind it wait on")

        spin(for: 60) { (many + [link]).allSatisfy { !$0.loading && $0.title.hasPrefix("Page ") } }
        XCTAssertEqual(link.title, "Page link")
        for (n, tab) in many.enumerated() { XCTAssertEqual(tab.title, "Page \(n)", "And every bookmark loads") }
    }

    // MARK: - a tab that waits is still a tab

    /// Stopped while it waits, a tab stops saying it is loading; picked
    /// afterwards it loads its page, not left empty.
    func testATabStoppedWhileItWaitsLoadsWhenPicked() {
        LoadTurns.most = 1
        LoadTurns.longest = 60
        server.reply = { path in .init(body: Self.page(path), stalls: path == "/page/0") }
        let tabs = (0..<3).map { browser.open(server.url("/page/\($0)"), foreground: false) }
        XCTAssertTrue(tabs[2].loading)
        tabs[2].stop()
        XCTAssertFalse(tabs[2].loading, "Stopped, it no longer says it is loading")
        browser.select(tabs[2])
        attach(tabs[2])
        spin(for: 5) { tabs[2].title == "Page 2" && !tabs[2].loading }
        XCTAssertEqual(tabs[2].title, "Page 2")
    }

    /// Put to sleep before its turn came, a tab wakes to its page: its empty
    /// view's state is not taken for a history to bring back.
    func testATabPutToSleepBeforeItsTurnWakesToItsPage() {
        LoadTurns.most = 1
        LoadTurns.longest = 60
        server.reply = { path in .init(body: Self.page(path), stalls: path == "/page/0") }
        let tabs = (0..<3).map { browser.open(server.url("/page/\($0)"), foreground: false) }
        XCTAssertEqual(browser.awake(because: tabs[2]), "still loading", "A tab waiting its turn is not one to put to sleep")
        tabs[2].sleep(picture: nil)
        XCTAssertTrue(tabs[2].asleep)
        XCTAssertFalse(tabs[2].loading)
        XCTAssertEqual(server.requests("/page/2"), 0)

        browser.select(tabs[2])
        attach(tabs[2])
        spin(for: 8) { tabs[2].title == "Page 2" && !tabs[2].loading }
        XCTAssertEqual(tabs[2].title, "Page 2")
        XCTAssertEqual(tabs[2].built?.url, server.url("/page/2"))
    }

    /// Closed while they wait, tabs are forgotten: the ones behind them
    /// load, and nothing is left waiting.
    func testTabsClosedWhileTheyWaitAreForgotten() {
        LoadTurns.most = 1
        server.reply = { path in .init(body: Self.page(path), after: 0.4) }
        let tabs = (0..<6).map { browser.open(server.url("/page/\($0)"), foreground: false) }
        for n in [1, 2, 3] { browser.close(tabs[n]) }
        spin(for: 30) { [0, 4, 5].allSatisfy { !tabs[$0].loading && tabs[$0].title.hasPrefix("Page ") } }
        for n in [0, 4, 5] { XCTAssertEqual(tabs[n].title, "Page \(n)") }
        for n in [1, 2, 3] { XCTAssertEqual(server.requests("/page/\(n)"), 0, "A closed tab's page is not asked for") }
        XCTAssertEqual(LoadTurns.shared.waitingCount, 0)
    }

    // MARK: - helpers

    nonisolated private static func page(_ path: String) -> String {
        let name = path.split(separator: "/").last.map(String.init) ?? ""
        return "<!doctype html><title>Page \(name)</title><p>Page \(name)</p>"
    }

    /// The stage's part, done by hand: the view in the window at the window's size.
    private func attach(_ tab: Tab) {
        let page = tab.web
        // A window far off every screen counts as hidden to WebKit, which
        // then lays nothing out; the page is to see itself shown.
        let occlusion = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        if page.responds(to: occlusion) {
            typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(page.method(for: occlusion), to: Setter.self)(page, occlusion, false)
        }
        page.frame = window.contentView?.bounds ?? .zero
        window.contentView?.addSubview(page)
    }

    /// The run loop turned over by hand, at least once, until `done` or the
    /// time is up. Not `await`ed: a test's async body runs on the main
    /// queue, and the blocks this waits for would queue behind it.
    private func spin(for seconds: TimeInterval, until done: () -> Bool) {
        let end = Date().addingTimeInterval(seconds)
        repeat {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.002))
        } while !done() && Date() < end
    }
}

/// A switch a server's reply reads from its own threads.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var on: Bool {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}

/// A loopback origin for pages that take their time: each reply can come
/// after a wait, or send its page and never finish, as a site still sending
/// does. It keeps the order pages were asked for in, and how many it was
/// answering at once.
final class TurnsServer: @unchecked Sendable {
    struct Reply {
        var body: String
        /// Seconds before anything is sent.
        var after: TimeInterval = 0
        /// The page sent, and the connection held open for good.
        var stalls = false
    }

    private let socket: Int32
    private let lock = NSLock()
    private var asked: [String] = []
    private var answering = 0
    private var most = 0
    private var stopped = false
    private var answer: @Sendable (String) -> Reply = { _ in Reply(body: "") }
    let port: UInt16

    init() throws {
        let server = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard server >= 0 else { throw Self.failure("socket") }
        socket = server
        var reuse: Int32 = 1
        _ = setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(server, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(server, 64) == 0 else {
            Darwin.close(server)
            throw Self.failure("bind/listen")
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(server, $0, &length) }
        }
        guard named == 0 else {
            Darwin.close(server)
            throw Self.failure("getsockname")
        }
        port = UInt16(bigEndian: actual.sin_port)
        Thread.detachNewThread { [weak self] in
            while let self, !self.isStopped {
                let client = Darwin.accept(self.socket, nil, nil)
                guard client >= 0 else { return }
                Thread.detachNewThread { [weak self] in self?.serve(client) }
            }
        }
    }

    deinit { stop() }

    /// What each path is answered with; called on the server's threads.
    var reply: @Sendable (String) -> Reply {
        get { lock.lock(); defer { lock.unlock() }; return answer }
        set { lock.lock(); answer = newValue; lock.unlock() }
    }

    func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }

    /// Every path asked for, in the order the requests arrived.
    var order: [String] { lock.lock(); defer { lock.unlock() }; return asked }

    func requests(_ path: String) -> Int { order.filter { $0 == path }.count }

    /// The most requests it was answering at the same time.
    var mostAtOnce: Int { lock.lock(); defer { lock.unlock() }; return most }

    /// The order and the count start again.
    func forget() {
        lock.lock()
        asked = []
        most = answering
        lock.unlock()
    }

    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    func stop() {
        lock.lock()
        let first = !stopped
        stopped = true
        lock.unlock()
        guard first else { return }
        shutdown(socket, SHUT_RDWR)
        Darwin.close(socket)
    }

    private func serve(_ client: Int32) {
        defer { Darwin.close(client) }
        var noSignal: Int32 = 1
        _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < 64 * 1024, data.range(of: Data("\r\n\r\n".utf8)) == nil {
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0 else { return }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard let header = String(data: data, encoding: .utf8),
              let target = header.components(separatedBy: "\r\n").first?.split(separator: " ").dropFirst().first
        else { return }
        let path = URLComponents(string: "http://fixture\(target)")?.path ?? String(target)
        // A page's icon is asked for beside it: no part of what is counted.
        guard path != "/favicon.ico" else {
            _ = send(client, Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8))
            return
        }
        lock.lock()
        asked.append(path)
        answering += 1
        most = max(most, answering)
        let reply = answer
        lock.unlock()
        defer { lock.lock(); answering -= 1; lock.unlock() }

        let made = reply(path)
        if made.after > 0 { usleep(UInt32(made.after * 1_000_000)) }
        let body = Data(made.body.utf8)
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nCache-Control: no-store\r\n"
            + "\(made.stalls ? "" : "Content-Length: \(body.count)\r\n")Connection: close\r\n\r\n"
        guard send(client, Data(head.utf8) + body), made.stalls else { return }
        while !isStopped { usleep(50_000) }
    }

    private func send(_ client: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return true }
            var sent = 0
            while sent < raw.count {
                let count = Darwin.send(client, base.advanced(by: sent), raw.count - sent, 0)
                guard count > 0 else { return false }
                sent += count
            }
            return true
        }
    }

    private static func failure(_ operation: String) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "\(operation) failed"])
    }
}
