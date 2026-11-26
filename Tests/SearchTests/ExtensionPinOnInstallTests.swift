import AppKit
import Foundation
import WebKit
import XCTest
@testable import Search

@available(macOS 15.4, *)
@MainActor
final class ExtensionPinOnInstallTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    /// A new extension's button is in the row at once, not behind the puzzle.
    func testANewExtensionIsPinned() async throws {
        _ = NSApplication.shared
        let extensions = Extensions.shared
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("pin-on-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        try Data(#"{"manifest_version": 3, "name": "Pinned at once", "version": "1.0", "action": {"default_title": "Press"}}"#.utf8)
            .write(to: source.appendingPathComponent("manifest.json"))
        let id = Crx.unpackedID(for: URL(fileURLWithPath: Crx.realPath(of: source), isDirectory: true))
        defer { extensions.remove(id) }

        extensions.installFolder(at: source, confirm: false)
        let end = Date().addingTimeInterval(10)
        while Date() < end, extensions.contexts[id] == nil { try await Task.sleep(for: .milliseconds(20)) }

        XCTAssertEqual(extensions.installed.first { $0.id == id }?.pinned, true)
        XCTAssertEqual(extensions.buttons.first { $0.id == id }?.pinned, true, "its button is not in the row")

        // Unpinning it is still the person's to do, and it stays unpinned.
        extensions.setPinned(id, false)
        XCTAssertEqual(extensions.buttons.first { $0.id == id }?.pinned, false)
    }
}
