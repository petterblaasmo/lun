import AppKit
import XCTest
@testable import Search

/// The row of tabs saved off the main thread (Browser.writeSession, Disk):
/// an everyday save doesn't hold the window until the file is on disk, the
/// newest row is the one kept, a row read is read as last saved, and
/// quitting writes at once on the thread that asks. In a space of its own,
/// so no other test's window writes the same file.
@MainActor
final class SessionSaveTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    private var browser: Browser!
    private var space: UUID!
    private var oldUsesSpaces = false
    private var file: URL { Store.file("session-\(space.uuidString).json") }

    override func setUp() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        browser = Browser(record: nil)
        oldUsesSpaces = browser.prefs.usesSpaces
        browser.prefs.usesSpaces = true
        let made = UUID()
        space = made
        browser.spaces = [Space(id: browser.spaceID, name: "First", colour: 0), Space(id: made, name: "Saves", colour: 1)]
        browser.switchSpace(to: made)
        XCTAssertEqual(browser.spaceID, made)
        XCTAssertTrue(browser.usesFiles, "The window whose rows are the session files")
        Disk.drain()
    }

    override func tearDown() async throws {
        browser.closeAll()
        browser.prefs.usesSpaces = oldUsesSpaces
        Disk.drain()
        try? FileManager.default.removeItem(at: file)
        browser = nil
    }

    private func open(_ name: String) {
        if browser.tabs.last?.isBlank == false { browser.newTab() }
        browser.tabs.last?.restore(url: URL(string: "https://\(name).example/")!, title: name)
    }

    /// The row as the file has it this instant, read past Session.read: no
    /// waiting for a save still on its way.
    private func onDisk() -> [String] {
        guard let data = try? Data(contentsOf: file),
              let shape = try? JSONDecoder().decode(Session.Shape.self, from: data) else { return [] }
        return shape.tabs.map(\.title)
    }

    /// The queue the rows are written on held up, until the returned
    /// semaphore is signalled.
    private func holdTheQueue() -> DispatchSemaphore {
        let hold = DispatchSemaphore(value: 0)
        let began = DispatchSemaphore(value: 0)
        let other = FileManager.default.temporaryDirectory.appendingPathComponent("held-\(UUID().uuidString).json")
        Disk.write(other, brisk: true) {
            began.signal()
            hold.wait()
            try? FileManager.default.removeItem(at: other)
            return nil
        }
        began.wait()
        return hold
    }

    /// Closing a tab, moving one, pinning one (writeSession(now: true)): the
    /// call comes back with the file still to write, and a read of the row
    /// is the row just saved all the same.
    func testAnEverydaySaveIsWrittenOffTheMainThreadAndReadBackAsSaved() {
        open("one")
        browser.flushSession()
        XCTAssertEqual(onDisk(), ["one"])

        let held = holdTheQueue()
        open("two")
        browser.writeSession(now: true)
        XCTAssertEqual(onDisk(), ["one"], "Back from the save with the file not yet written: nothing was written on this thread")
        held.signal()
        XCTAssertEqual(Session.read(space: space).tabs.map(\.title), ["one", "two"], "A read waits for the save on its way")
        XCTAssertEqual(onDisk(), ["one", "two"])
    }

    /// Quitting (flushSession): on disk when it returns, with nothing left
    /// for a queue to finish, and a save from a moment before, still
    /// waiting, never lands over it.
    func testQuittingWritesTheRowBeforeItReturns() {
        open("one")
        let held = holdTheQueue()
        browser.writeSession(now: true)
        open("two")
        browser.writeSession(now: true)
        open("three")
        browser.flushSession()
        XCTAssertEqual(onDisk(), ["one", "two", "three"], "Written on the thread that asked, the queue still held up")
        held.signal()
        Disk.drain()
        XCTAssertEqual(onDisk(), ["one", "two", "three"], "The older saves, still waiting, did not land over it")
    }

    /// Fifty changes, each saved as it is made, in every way a save is asked
    /// for: after each, the row read is that row, and the last is the file.
    func testTheNewestRowIsTheOneKept() {
        var names: [String] = []
        for n in 0..<50 {
            names.append("tab\(n)")
            open("tab\(n)")
            switch n % 4 {
            case 0: browser.writeSession()
            case 1, 2: browser.writeSession(now: true)
            default: browser.flushSession()
            }
            XCTAssertEqual(Session.read(space: space).tabs.map(\.title), names)
        }
        // And taken away again, one save each, none read in between.
        for _ in 0..<30 {
            names.removeLast()
            browser.close(browser.tabs[browser.tabs.count - 1])
            browser.writeSession(now: true)
        }
        Disk.drain()
        XCTAssertEqual(onDisk(), names)
    }

    /// A space deleted just after its row was saved: the save, still on its
    /// way, doesn't bring the file back.
    func testARowErasedIsNotBroughtBackByASaveStillOnItsWay() {
        let gone = UUID()
        let its = Store.file("session-\(gone.uuidString).json")
        defer { try? FileManager.default.removeItem(at: its) }
        Session.write(now: true, space: gone, Session.Shape(tabs: [], active: 0))
        XCTAssertTrue(FileManager.default.fileExists(atPath: its.path))
        let held = holdTheQueue()
        Session.write(space: gone, Session.Shape(tabs: [Session.Entry(url: "https://left.example/", title: "left")], active: 0))
        Session.erase(space: gone)
        held.signal()
        Disk.drain()
        XCTAssertFalse(FileManager.default.fileExists(atPath: its.path))
        XCTAssertTrue(Session.read(space: gone).tabs.isEmpty)
    }
}
