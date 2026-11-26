import Foundation
import XCTest
@testable import Search

/// What a save handed to Disk can be counted on for, whichever thread asks
/// and whichever queue writes: the newest asked for is the one left on disk,
/// one overtaken is never encoded, the file is whole at every moment (a
/// process killed halfway through a write leaves the old one), and a read
/// after `settle` finds the last save. The session, the user's open tabs, is
/// written this way off the main thread (Session.write).
final class DiskTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("disk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        Disk.drain()
        try? FileManager.default.removeItem(at: folder)
    }

    private final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        @discardableResult func add() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
        var now: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// The queue held up by a write of another file, until the returned
    /// semaphore is signalled: whatever is asked for meanwhile waits.
    private func hold(brisk: Bool) -> DispatchSemaphore {
        let hold = DispatchSemaphore(value: 0)
        let began = DispatchSemaphore(value: 0)
        Disk.write(folder.appendingPathComponent("other-\(brisk).json"), brisk: brisk) {
            began.signal()
            hold.wait()
            return Data()
        }
        began.wait()
        return hold
    }

    private func text(_ file: URL) throws -> String { try String(contentsOf: file, encoding: .utf8) }

    // MARK: - the newest wins

    func testASaveOvertakenBeforeItsTurnIsNeitherEncodedNorWritten() throws {
        for brisk in [false, true] {
            let file = folder.appendingPathComponent("row-\(brisk).json")
            let held = hold(brisk: brisk)
            let older = Count(), newer = Count()
            Disk.write(file, brisk: brisk) { older.add(); return Data("older".utf8) }
            Disk.write(file, brisk: brisk) { older.add(); return Data("old".utf8) }
            Disk.write(file, brisk: brisk) { newer.add(); return Data("newer".utf8) }
            held.signal()
            Disk.drain()
            XCTAssertEqual(older.now, 0, "A save overtaken before it began is not encoded")
            XCTAssertEqual(newer.now, 1)
            XCTAssertEqual(try text(file), "newer")
        }
    }

    /// Quitting: the save on the calling thread is on disk when it returns,
    /// with the queue still holding older ones, and none of those lands
    /// over it afterwards.
    func testASaveAtOnceIsOnDiskWhenItReturnsAndStaysTheNewest() throws {
        for brisk in [false, true] {
            let file = folder.appendingPathComponent("quit-\(brisk).json")
            let held = hold(brisk: brisk)
            let older = Count()
            Disk.write(file, brisk: brisk) { older.add(); return Data("a moment ago".utf8) }
            Disk.write(file, now: true, brisk: brisk) { Data("on the way out".utf8) }
            XCTAssertEqual(try text(file), "on the way out", "Written before returning, the queue still held up")
            held.signal()
            Disk.drain()
            XCTAssertEqual(try text(file), "on the way out", "The older save, still waiting, never lands over it")
            XCTAssertEqual(older.now, 0)
        }
    }

    /// A save at once arrives while a queued one is being encoded: the
    /// queued one, older, is not put in place when it is done.
    func testASaveOvertakenWhileEncodingIsNotPutInPlace() throws {
        for brisk in [false, true] {
            let file = folder.appendingPathComponent("mid-\(brisk).json")
            let encoding = DispatchSemaphore(value: 0)
            let resume = DispatchSemaphore(value: 0)
            Disk.write(file, brisk: brisk) {
                encoding.signal()
                resume.wait()
                return Data("older".utf8)
            }
            encoding.wait()
            Disk.write(file, now: true, brisk: brisk) { Data("newer".utf8) }
            resume.signal()
            Disk.drain()
            XCTAssertEqual(try text(file), "newer")
        }
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".writing") }
        XCTAssertEqual(left, [], "And what it had written beside the file is taken away")
    }

    /// Saves asked for from eight threads at once, some at once and some
    /// queued, on either queue: the last one asked for is the one on disk.
    func testTheLastSaveAskedForFromManyThreadsIsTheOneOnDisk() throws {
        let file = folder.appendingPathComponent("many.json")
        let asking = NSLock()
        nonisolated(unsafe) var last = 0
        for _ in 0..<5 {
            DispatchQueue.concurrentPerform(iterations: 400) { i in
                // The order of asking is the order the lock was taken in.
                asking.lock()
                last += 1
                let n = last
                Disk.write(file, now: i % 5 == 0, brisk: i % 2 == 0) { Data("save \(n)".utf8) }
                asking.unlock()
            }
            Disk.drain()
            XCTAssertEqual(try text(file), "save \(last)")
        }
    }

    // MARK: - read as saved

    func testAReadAfterSettleFindsTheSaveJustAskedFor() throws {
        let file = folder.appendingPathComponent("settle.json")
        for n in 0..<300 {
            Disk.write(file, brisk: n % 2 == 0) { Data("save \(n)".utf8) }
            Disk.settle(file)
            XCTAssertEqual(try text(file), "save \(n)")
        }
        // Nothing waiting: nothing to wait for, the queue held up or not.
        let held = hold(brisk: true)
        Disk.settle(file)
        held.signal()
    }

    /// A file read from inside a write (an encoder that reads another file)
    /// waits for nothing: waiting for its own queue would never end.
    func testSettleFromInsideAWriteDoesNotWait() throws {
        let first = folder.appendingPathComponent("first.json")
        let second = folder.appendingPathComponent("second.json")
        let done = expectation(description: "the write that reads")
        Disk.write(first, brisk: true) {
            // `second` is behind this one on the same queue.
            Disk.settle(second)
            done.fulfill()
            return Data("first".utf8)
        }
        Disk.write(second, brisk: true) { Data("second".utf8) }
        wait(for: [done], timeout: 10)
        Disk.drain()
        XCTAssertEqual(try text(second), "second")
    }

    /// A file removed at once stays gone: a save of it still on the queue
    /// does not bring it back.
    func testAFileRemovedAtOnceIsNotBroughtBackByAnOlderSave() throws {
        let file = folder.appendingPathComponent("gone.json")
        Disk.write(file, now: true) { Data("there".utf8) }
        let held = hold(brisk: true)
        Disk.write(file, brisk: true) { Data("back again".utf8) }
        Disk.remove(file, now: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        held.signal()
        Disk.drain()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "The save asked for before it was removed")
        // And one asked for after it is written.
        Disk.write(file, brisk: true) { Data("new".utf8) }
        Disk.settle(file)
        XCTAssertEqual(try text(file), "new")
    }

    // MARK: - whole at every moment

    /// A save of `n`: its number, then a megabyte that only that number
    /// writes, so a file that is part of one save, or parts of two, shows.
    private static func payload(_ n: Int) -> Data {
        var data = Data("\(n)\n".utf8)
        data.append(Data(repeating: UInt8(97 + n % 26), count: 1 << 20))
        return data
    }

    /// The number of the save `data` is, or nil when it is not one whole save.
    private static func whole(_ data: Data) -> Int? {
        guard let line = data.firstIndex(of: 10), let n = Int(String(decoding: data[..<line], as: UTF8.self)) else { return nil }
        return data == payload(n) ? n : nil
    }

    /// Read over and over while saves land: every reading is one whole save,
    /// never part of one, and never an older one after a newer.
    func testEveryReadingWhileSavesLandIsOneWholeSave() throws {
        let file = folder.appendingPathComponent("whole.json")
        Disk.write(file, now: true) { Self.payload(0) }
        let stop = Count()
        let readings = Count()
        nonisolated(unsafe) var trouble: String?
        let reader = Thread {
            var seen = 0
            while stop.now == 0 {
                guard let data = try? Data(contentsOf: file) else { trouble = "no file at all"; return }
                guard let n = Self.whole(data) else { trouble = "\(data.count) bytes that are no whole save"; return }
                guard n >= seen else { trouble = "save \(n) after save \(seen)"; return }
                seen = n
                readings.add()
            }
        }
        reader.start()
        // A second and a half of saves, at once and queued, on either queue.
        var n = 0
        let end = Date().addingTimeInterval(1.5)
        while Date() < end, !reader.isFinished {
            n += 1
            let save = n
            Disk.write(file, now: n % 7 == 0, brisk: n % 2 == 0) { Self.payload(save) }
            if n % 10 == 0 { Disk.drain() }
        }
        Disk.drain()
        stop.add()
        while !reader.isFinished { usleep(1000) }
        XCTAssertNil(trouble)
        XCTAssertGreaterThan(readings.now, 50, "The file was read while it was being saved")
        XCTAssertGreaterThan(n, 50)
        XCTAssertEqual(Self.whole(try Data(contentsOf: file)), n)
    }

    /// Not a test of its own: the writer the test below starts and kills.
    /// It saves the file named by DISK_TEST_VICTIM over and over, at once
    /// and queued, until it is killed.
    func testSavesUntilKilled() throws {
        guard let path = ProcessInfo.processInfo.environment["DISK_TEST_VICTIM"] else {
            throw XCTSkip("Only as the process testAProcessKilledMidSaveLeavesAWholeFile kills")
        }
        let file = URL(fileURLWithPath: path)
        FileManager.default.createFile(atPath: path + ".started", contents: nil)
        var n = 0
        while true {
            n += 1
            let save = n
            Disk.write(file, now: n % 3 == 0, brisk: n % 2 == 0) { Self.payload(save) }
            if n % 8 == 0 { Disk.drain() }
        }
    }

    /// A crash halfway through a save: a process saving a megabyte over and
    /// over is killed outright (SIGKILL, no way out to run), eight times, a
    /// different moment into its saves each time. What is on disk afterwards
    /// is one whole save every time: the old file, or the new one.
    func testAProcessKilledMidSaveLeavesAWholeFile() throws {
        let runner = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        try XCTSkipUnless(runner.lastPathComponent == "xctest", "Needs the xctest runner to start a second process")
        let bundle = Bundle(for: DiskTests.self).bundlePath
        let file = folder.appendingPathComponent("victim.json")
        let started = file.path + ".started"
        // A save from before any of them: the old file a first kill leaves.
        Disk.write(file, now: true) { Self.payload(0) }
        var changed = 0
        var last = try Data(contentsOf: file)
        for round in 0..<8 {
            try? FileManager.default.removeItem(atPath: started)
            let child = Process()
            child.executableURL = runner
            child.arguments = ["-XCTest", "SearchTests.DiskTests/testSavesUntilKilled", bundle]
            child.environment = ProcessInfo.processInfo.environment.merging(["DISK_TEST_VICTIM": file.path]) { $1 }
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            try child.run()
            let limit = Date().addingTimeInterval(120)
            while !FileManager.default.fileExists(atPath: started), child.isRunning, Date() < limit { usleep(2000) }
            guard FileManager.default.fileExists(atPath: started) else {
                child.terminate()
                return XCTFail("The writing process never began (round \(round))")
            }
            // Somewhere into its saves, a different place each round.
            usleep(UInt32(3000 + round * 9000 + Int.random(in: 0..<4000)))
            kill(child.processIdentifier, SIGKILL)
            child.waitUntilExit()
            XCTAssertEqual(child.terminationReason, .uncaughtSignal, "It was killed, it did not finish")
            let data = try Data(contentsOf: file)
            XCTAssertNotNil(Self.whole(data), "Round \(round): \(data.count) bytes that are no whole save")
            if data != last { changed += 1 }
            last = data
        }
        XCTAssertGreaterThan(changed, 0, "The process did save before it was killed")
    }
}
