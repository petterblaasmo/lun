import CoreServices
import XCTest
@testable import Search

final class MarkDownloadedTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("mark-downloaded-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func written(_ name: String) throws -> URL {
        let file = folder.appendingPathComponent(name)
        try Data("%PDF-1.4".utf8).write(to: file)
        return file
    }

    private func properties(_ file: URL) throws -> [String: Any] {
        try XCTUnwrap(try file.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties)
    }

    /// Get Info's "Where from", as it is on the file.
    static func whereFrom(_ file: URL) -> [String]? {
        let size = getxattr(file.path, Browser.whereFrom, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(file.path, Browser.whereFrom, $0.baseAddress, size, 0, 0) }
        guard read == size else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String]
    }

    /// The mark itself, field by field: flags, time, the app's name, and
    /// macOS's number for it.
    static func mark(_ file: URL) -> [String]? {
        var bytes = [UInt8](repeating: 0, count: 512)
        let size = getxattr(file.path, Browser.quarantine, &bytes, bytes.count, 0, 0)
        return size > 0 ? String(decoding: bytes[..<size], as: UTF8.self).components(separatedBy: ";") : nil
    }

    /// What macOS goes by when the file is first opened.
    static func flags(_ file: URL) -> Int? {
        mark(file)?.first.flatMap { Int($0, radix: 16) }
    }

    func testASavedFileIsMarkedAsDownloaded() throws {
        let file = try written("a.pdf")

        Browser.markDownloaded(file)

        let properties = try properties(file)
        XCTAssertEqual(properties[kLSQuarantineTypeKey as String] as? String, kLSQuarantineTypeWebDownload as String)
        XCTAssertEqual(properties[kLSQuarantineAgentNameKey as String] as? String, "Lun")
        XCTAssertEqual(properties[kLSQuarantineAgentBundleIdentifierKey as String] as? String, Bundle.main.bundleIdentifier)
        XCTAssertEqual(Self.mark(file)?.dropFirst(2).first, "Lun", "`xattr -p com.apple.quarantine` named no app")
        XCTAssertNil(Self.whereFrom(file), "a file given no address said where it was from")
    }

    func testAFileSaysWhereItCameFrom() throws {
        let file = try written("b.pdf")
        let source = try XCTUnwrap(URL(string: "https://files.example.test/b.pdf?v=2"))
        let page = try XCTUnwrap(URL(string: "https://example.test/papers"))

        Browser.markDownloaded(file, from: source, on: page)

        XCTAssertEqual(try properties(file)[kLSQuarantineAgentNameKey as String] as? String, "Lun")
        XCTAssertEqual(Self.whereFrom(file), [source.absoluteString, page.absoluteString])
    }

    /// A password in an address, a blob: or a data: one is kept out, as it is
    /// out of the downloads list.
    func testOnlyAnAddressAnotherAppCanFetchIsWritten() throws {
        let file = try written("c.pdf")

        Browser.markDownloaded(file, from: URL(string: "blob:https://example.test/1b2c"),
                               on: URL(string: "https://me:secret@example.test/inbox"))

        XCTAssertEqual(Self.whereFrom(file), ["https://example.test/inbox"])
    }

    /// The addresses in the mark can't be read back on a macOS that drops
    /// them, so what is handed to it is looked at instead.
    func testTheMarkHasTheAddressesItIsGivenAndNoOthers() throws {
        let named = Browser.downloadMark(from: "https://files.example.test/b.pdf", on: "https://example.test/papers")
        XCTAssertEqual(named[kLSQuarantineDataURLKey as String] as? URL, URL(string: "https://files.example.test/b.pdf"))
        XCTAssertEqual(named[kLSQuarantineOriginURLKey as String] as? URL, URL(string: "https://example.test/papers"))
        XCTAssertEqual(named[kLSQuarantineTypeKey as String] as? String, kLSQuarantineTypeWebDownload as String)

        let unnamed = Browser.downloadMark(from: nil, on: nil)
        XCTAssertNil(unnamed[kLSQuarantineDataURLKey as String])
        XCTAssertNil(unnamed[kLSQuarantineOriginURLKey as String])
        XCTAssertEqual(unnamed[kLSQuarantineAgentNameKey as String] as? String, "Lun")
    }

    /// What WebKit leaves on a download: made by a sandboxed process, with
    /// no name. Lun's goes over it, and the file is still one macOS checks
    /// when it is first opened.
    func testAMarkAlreadyThereIsAddedToNotTakenOff() throws {
        let file = try written("d.pdf")
        let webKits = Array("0283;6b0af0fc;;".utf8)
        XCTAssertEqual(setxattr(file.path, Browser.quarantine, webKits, webKits.count, 0, 0), 0)

        Browser.markDownloaded(file)

        let properties = try properties(file)
        XCTAssertEqual(properties[kLSQuarantineAgentNameKey as String] as? String, "Lun")
        XCTAssertEqual(properties[kLSQuarantineTypeKey as String] as? String, kLSQuarantineTypeWebDownload as String)
        let flags = try XCTUnwrap(Self.flags(file))
        XCTAssertEqual(flags & 0x1, 0x1, "no longer marked as a download: \(String(flags, radix: 16))")
        XCTAssertEqual(Self.mark(file)?.dropFirst(2).first, "Lun")
    }
}
