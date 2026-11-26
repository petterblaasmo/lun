import AppKit
import Foundation
import WebKit
import XCTest
@testable import Search

/// The list behind the puzzle has a line for every installed extension: one
/// switched off, or one that couldn't start, had none and could only be
/// found in Settings.
@available(macOS 15.4, *)
@MainActor
final class ExtensionListTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    func testHowAnExtensionStands() {
        typealias Standing = Extensions.Standing
        XCTAssertEqual(Standing.of(enabled: true, running: true, hasButton: true, reason: nil), .button)
        XCTAssertEqual(Standing.of(enabled: true, running: true, hasButton: false, reason: nil), .silent)
        XCTAssertEqual(Standing.of(enabled: true, running: false, hasButton: false, reason: nil), .stopped(nil))
        XCTAssertEqual(Standing.of(enabled: true, running: false, hasButton: false, reason: "no manifest"), .stopped("no manifest"))
        // Off is off, whatever was last known of it.
        XCTAssertEqual(Standing.of(enabled: false, running: false, hasButton: false, reason: "no manifest"), .off)
        XCTAssertEqual(Standing.of(enabled: false, running: true, hasButton: true, reason: nil), .off)
    }

    func testWhatALineSaysOfItself() {
        XCTAssertEqual(Extensions.Standing.off.says("Quiet"), "Quiet is off")
        XCTAssertEqual(Extensions.Standing.stopped(nil).says("Quiet"), "Quiet is starting")
        XCTAssertEqual(Extensions.Standing.stopped("no manifest").says("Quiet"), "Quiet couldn’t start: no manifest")
        XCTAssertTrue(Extensions.Standing.silent.says("Quiet").contains("no button"))
    }

    private func folder(_ manifest: String) throws -> URL {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("puzzle-list-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: source.appendingPathComponent("manifest.json"))
        try Data("".utf8).write(to: source.appendingPathComponent("content.js"))
        return source
    }

    private func wait(_ seconds: TimeInterval = 15, until met: () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end, !met() { try await Task.sleep(for: .milliseconds(20)) }
    }

    /// One whose manifest names a button and one whose doesn't, on and off:
    /// each has its line throughout.
    func testEveryInstalledExtensionHasALine() async throws {
        _ = NSApplication.shared
        let extensions = Extensions.shared
        let pressed = try folder(#"{"manifest_version": 3, "name": "Pressed", "version": "1.0", "action": {"default_title": "Press"}}"#)
        let quiet = try folder(#"{"manifest_version": 3, "name": "Quiet", "version": "1.0", "content_scripts": [{"matches": ["https://quiet.invalid/*"], "js": ["content.js"]}]}"#)
        defer { [pressed, quiet].forEach { try? FileManager.default.removeItem(at: $0) } }
        let ids = [pressed, quiet].map { Crx.unpackedID(for: URL(fileURLWithPath: Crx.realPath(of: $0), isDirectory: true)) }
        defer { ids.forEach(extensions.remove) }

        extensions.installFolder(at: pressed, confirm: false)
        try await wait { extensions.contexts[ids[0]] != nil }
        extensions.installFolder(at: quiet, confirm: false)
        try await wait { extensions.contexts[ids[1]] != nil }
        XCTAssertNotNil(extensions.contexts[ids[0]], "the one with a button didn't load")
        XCTAssertNotNil(extensions.contexts[ids[1]], "the one without didn't load")

        func line(_ id: String) -> Extensions.Listed? { extensions.listed.first { $0.id == id } }
        XCTAssertEqual(line(ids[0])?.standing, .button)
        XCTAssertEqual(line(ids[0])?.button.enabled, true)
        // WebKit gives one with no action in its manifest a button too, so
        // running it was in the list already, and still is.
        XCTAssertEqual(line(ids[1])?.standing, .button)
        XCTAssertEqual(line(ids[1])?.button.name, "Quiet")
        // In install order, as the buttons are.
        XCTAssertEqual(extensions.listed.map(\.id).filter(ids.contains), ids)
        XCTAssertEqual(extensions.buttons.map(\.id).filter(ids.contains), ids)

        // Switched off, both keep their lines, dimmed, and say so. Neither
        // has a button for the row.
        ids.forEach { extensions.setEnabled($0, false) }
        for id in ids {
            XCTAssertEqual(line(id)?.standing, .off)
            XCTAssertEqual(line(id)?.button.enabled, false)
        }
        XCTAssertEqual(line(ids[1])?.button.name, "Quiet")
        XCTAssertEqual(extensions.listed.map(\.id).filter(ids.contains), ids, "… in the same places")
        XCTAssertFalse(extensions.buttons.contains { ids.contains($0.id) })

        // On again, as the line's switch does it: starting, then back.
        extensions.setEnabled(ids[0], true)
        XCTAssertEqual(line(ids[0])?.standing, .stopped(nil), "on and not yet running: starting")
        XCTAssertEqual(line(ids[1])?.standing, .off)
        try await wait { extensions.contexts[ids[0]] != nil }
        XCTAssertEqual(line(ids[0])?.standing, .button)
    }
}
