import WebKit
import XCTest
@testable import Search

/// How far up a page opened from disk may read (#1342): two folders, never
/// the home folder or a folder directly in it, however the path is spelled.
/// A folder of the temporary directory stands in for the home folder.
final class FileReadRootTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("readroot-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Docs/site/a/b"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Docs/link"), withDestinationURL: home)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testTwoFoldersUpWithinAFolderOfHome() {
        let folder = home.appendingPathComponent("Docs/site/a/b")
        XCTAssertEqual(WKWebView.readRoot(folder, home: home).path, home.appendingPathComponent("Docs/site").path)
    }

    func testNeverAFolderDirectlyInHome() {
        let folder = home.appendingPathComponent("Docs/site/a")
        XCTAssertEqual(WKWebView.readRoot(folder, home: home).path, home.appendingPathComponent("Docs/site").path)
    }

    /// A link to the home folder is the home folder: Docs/link/Docs/site
    /// is Docs/site, and Docs/link/Docs is Docs, a folder directly in home.
    func testALinkToHomeIsHome() {
        let folder = home.appendingPathComponent("Docs/link/Docs/site/a")
        XCTAssertEqual(WKWebView.readRoot(folder, home: home).path,
                       home.appendingPathComponent("Docs/link/Docs/site").path)
    }

    /// The home folder in another case is the home folder (APFS ignores case).
    func testAnotherCaseIsHome() throws {
        let upper = URL(fileURLWithPath: home.path.uppercased())
        try XCTSkipUnless(FileManager.default.fileExists(atPath: upper.path), "case-sensitive volume")
        let folder = upper.appendingPathComponent("DOCS/SITE/A")
        XCTAssertEqual(WKWebView.readRoot(folder, home: home).path, upper.appendingPathComponent("DOCS/SITE").path)
    }

    func testSameItemFollowsLinks() {
        XCTAssertTrue(WKWebView.sameItem(home.appendingPathComponent("Docs/link"), home))
        XCTAssertFalse(WKWebView.sameItem(home.appendingPathComponent("Docs"), home))
        XCTAssertFalse(WKWebView.sameItem(home.appendingPathComponent("missing"), home))
    }

    /// The folder is handed to WebKit as the file's address spells it: with
    /// /private in front, a folder that also answers without it was
    /// standardized to the shorter spelling, and the page stayed blank.
    func testTheFolderIsSpelledAsTheFileIs() throws {
        let short = try XCTUnwrap(shortSpelling(of: home))
        let long = URL(fileURLWithPath: "/private" + short.path)
        XCTAssertEqual(long.appendingPathComponent("Docs/site").standardizedFileURL.path,
                       short.appendingPathComponent("Docs/site").path, "standardizing drops /private here")
        for spelling in [long, short] {
            let file = spelling.appendingPathComponent("Docs/site/a/b/page.html")
            let access = WKWebView.readAccess(for: file, home: home)
            XCTAssertEqual(access.path, spelling.appendingPathComponent("Docs/site").path)
            XCTAssertTrue(file.path.hasPrefix(access.path + "/"), "the file is under the folder it may read")
        }
        // Dots in the address are taken out, not counted as folders.
        let dotted = long.appendingPathComponent("Docs/site/a/b/../b/page.html")
        XCTAssertEqual(WKWebView.readAccess(for: dotted, home: home).path, long.appendingPathComponent("Docs/site").path)
    }

    /// A file in the home folder itself reads only itself, as before.
    func testAFileInAWideFolderReadsOnlyItself() {
        let file = home.appendingPathComponent("page.html")
        XCTAssertEqual(WKWebView.readAccess(for: file, home: home), file)
        let top = URL(fileURLWithPath: "/page.html")
        XCTAssertEqual(WKWebView.readAccess(for: top, home: home), top)
    }

    /// The page itself, in a web view: file:///private/…/page.html loads,
    /// where it stayed blank and loading for ever.
    @MainActor
    func testAPageSpelledWithPrivateLoads() async throws {
        let short = try XCTUnwrap(shortSpelling(of: home))
        let file = URL(fileURLWithPath: "/private" + short.path).appendingPathComponent("Docs/site/page.html")
        try Data("<!doctype html><title>read</title><p>here".utf8).write(to: file)
        _ = NSApplication.shared
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        web.open(file)
        for _ in 0..<100 where web.title != "read" { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(web.title, "read")
    }

    /// `folder` without the /private in front of it, when it is spelled
    /// with it and answers without it too (the temporary directory does).
    private func shortSpelling(of folder: URL) -> URL? {
        let path = folder.path.hasPrefix("/private/") ? String(folder.path.dropFirst(8)) : folder.path
        guard FileManager.default.fileExists(atPath: path), FileManager.default.fileExists(atPath: "/private" + path)
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    func testTheDataVolumeIsAVolume() {
        XCTAssertTrue(WKWebView.isVolume(URL(fileURLWithPath: "/")))
        XCTAssertFalse(WKWebView.isVolume(home))
    }
}
