import Foundation
import XCTest
@testable import Search

/// A user script's `file` is the extension's to name, and what is read is
/// written back into the extension's own folder, where it can fetch it. So
/// only a file of its own package is read: never one reached with `..`, and
/// never one a symbolic link points to elsewhere on the Mac.
@available(macOS 15.4, *)
@MainActor
final class ExtensionUserScriptFileTests: XCTestCase {
    private var root: URL!
    private var package: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("user-script-\(UUID().uuidString)", isDirectory: true)
        package = root.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: package.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try "window.own = 1".write(to: package.appendingPathComponent("scripts/own.js"), atomically: true, encoding: .utf8)
        try "OUTSIDE-THE-PACKAGE".write(to: root.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: package.appendingPathComponent("link.js"),
                                                   withDestinationURL: root.appendingPathComponent("secret.txt"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testOnlyAPathThatStaysInThePackageIsOneOfItsFiles() {
        XCTAssertNotNil(ExtensionShims.inside("scripts/own.js", of: package))
        XCTAssertNotNil(ExtensionShims.inside("/scripts/own.js", of: package))
        XCTAssertNotNil(ExtensionShims.inside("scripts/../scripts/own.js", of: package))
        XCTAssertNil(ExtensionShims.inside("../secret.txt", of: package))
        XCTAssertNil(ExtensionShims.inside("scripts/../../secret.txt", of: package))
        XCTAssertNil(ExtensionShims.inside("link.js", of: package))
    }

    func testAUserScriptIsMadeFromThePackagesOwnFilesOnly() throws {
        let script: [String: Any] = ["js": [["file": "scripts/own.js"], ["file": "../secret.txt"],
                                            ["file": "scripts/../../secret.txt"], ["file": "link.js"]]]

        let written = try ExtensionShims.userScriptFile(script, in: package)

        let text = try String(contentsOf: package.appendingPathComponent(written), encoding: .utf8)
        XCTAssertTrue(text.contains("window.own = 1"))
        XCTAssertFalse(text.contains("OUTSIDE-THE-PACKAGE"))
    }
}
