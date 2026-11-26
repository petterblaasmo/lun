import XCTest
@testable import Search

/// Replace, answered in the save panel: the download is written where the
/// old file was. WebKit writes over nothing, so the old file has to be out
/// of the way first.
final class DownloadReplaceTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("replace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testANameNothingHasIsKeptAndNothingIsRemoved() {
        let file = folder.appendingPathComponent("Photo 1.jpg")
        var removed: [URL] = []

        XCTAssertEqual(Browser.makingWay(for: file, remove: { removed.append($0) }), file)

        XCTAssertEqual(removed, [])
    }

    func testTheFileBeingReplacedGoesAndItsNameIsKept() throws {
        let file = folder.appendingPathComponent("Photo 1.jpg")
        try Data("old".utf8).write(to: file)

        let place = Browser.makingWay(for: file, remove: { try FileManager.default.removeItem(at: $0) })

        XCTAssertEqual(place, file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testAFileThatWillNotGoIsLeftAndTheDownloadTakesAFreeName() throws {
        let file = folder.appendingPathComponent("Photo 1.jpg")
        try Data("old".utf8).write(to: file)

        let place = Browser.makingWay(for: file, remove: { _ in throw CocoaError(.fileWriteNoPermission) })

        XCTAssertEqual(place.lastPathComponent, "Photo 1 2.jpg")
        XCTAssertEqual(try Data(contentsOf: file), Data("old".utf8))
    }

    /// A remover that says it worked while the file is still there is not
    /// taken at its word: WebKit would fail on the name all the same.
    func testAFileStillThereAfterRemovingTakesAFreeNameToo() throws {
        let file = folder.appendingPathComponent("Photo 1.jpg")
        try Data("old".utf8).write(to: file)

        let place = Browser.makingWay(for: file, remove: { _ in })

        XCTAssertEqual(place.lastPathComponent, "Photo 1 2.jpg")
    }
}
