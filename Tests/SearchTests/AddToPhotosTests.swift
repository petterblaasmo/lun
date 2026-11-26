import AppKit
import Photos
import WebKit
import XCTest
@testable import Search

/// "Add Image to Photos" in a picture's menu: where the item is, what it
/// hands to Photos, and that the library is only ever asked for leave to
/// add. The Mac's own library asks on screen, so a stand-in is used here.
@MainActor
final class AddToPhotosTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    /// What the stand-in library was asked and given.
    private final class Seen: @unchecked Sendable {
        var asked = 0
        var added: [Data] = []
    }

    private func door(_ status: PHAuthorizationStatus, seen: Seen, canAsk: Bool = true, fails: Bool = false) -> PhotosDoor {
        PhotosDoor(canAsk: { canAsk },
                   access: { seen.asked += 1; return status },
                   add: { data in
                       if fails { throw CocoaError(.fileWriteUnknown) }
                       seen.added.append(data)
                   })
    }

    /// A small PNG, as a site would serve one.
    private func png() throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    func testThePictureIsAddedAsTheBytesItCameIn() async throws {
        let seen = Seen()
        let data = try png()
        for status in [PHAuthorizationStatus.authorized, .limited] {
            let said = await Browser.addToPhotos(data, through: door(status, seen: seen))
            XCTAssertEqual(said, "Added to Photos")
        }
        XCTAssertEqual(seen.added, [data, data], "not encoded again")
        XCTAssertEqual(seen.asked, 2)
    }

    func testRefusedItSaysWhereToAllowIt() async throws {
        let seen = Seen()
        let data = try png()
        for status in [PHAuthorizationStatus.denied, .restricted] {
            let said = await Browser.addToPhotos(data, through: door(status, seen: seen))
            XCTAssertEqual(said, Browser.photosRefused)
            XCTAssertTrue(said.contains("System Settings"))
        }
        // The question put away unanswered: nothing added, and no blame.
        let unanswered = await Browser.addToPhotos(data, through: door(.notDetermined, seen: seen))
        XCTAssertEqual(unanswered, "Couldn't add that image")
        XCTAssertTrue(seen.added.isEmpty)
    }

    func testNothingIsAskedForWhatIsNoPicture() async throws {
        let seen = Seen()
        let open = door(.authorized, seen: seen)
        let missing = await Browser.addToPhotos(nil, through: open)
        let words = await Browser.addToPhotos(Data("<html>not a picture</html>".utf8), through: open)
        XCTAssertEqual(missing, "Couldn't add that image")
        XCTAssertEqual(words, "Couldn't add that image")
        XCTAssertEqual(seen.asked, 0, "Photos is not asked about a picture that never arrived")

        // A build with no sentence for the question never touches the
        // library: macOS would end the app for it.
        let data = try png()
        let bare = await Browser.addToPhotos(data, through: door(.authorized, seen: seen, canAsk: false))
        XCTAssertEqual(bare, "Couldn't add that image")
        XCTAssertEqual(seen.asked, 0)

        // Photos itself refusing the picture is said, not hidden.
        let refused = await Browser.addToPhotos(data, through: door(.authorized, seen: seen, fails: true))
        XCTAssertEqual(refused, "Couldn't add that image")
        XCTAssertTrue(seen.added.isEmpty)
    }

    private func makeTab() -> (Browser, Tab) {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        browser.welcoming = false
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let tab = Tab(configuration: configuration)
        tab.setAddressOptimistically(URL(string: "https://pictures.example/")!)
        browser.prepare(tab)
        browser.insert(tab, at: browser.tabs.count)
        _ = tab.web
        return (browser, tab)
    }

    func testThePictureMenuHasItUnderDownloadImage() throws {
        let (browser, tab) = makeTab()
        defer { browser.closeAll() }
        let url = try XCTUnwrap(URL(string: "https://pictures.example/cat.jpg"))
        let menu = try XCTUnwrap(browser.imageMenu(for: tab, at: url))
        let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        let download = try XCTUnwrap(titles.firstIndex(of: "Download Image"))
        XCTAssertEqual(titles[download + 1], "Add Image to Photos")
        XCTAssertEqual(titles.first, "Open Image in New Tab")
        XCTAssertEqual(titles.last, "Copy Image Address")
        XCTAssertEqual(titles.filter { $0 == "Add Image to Photos" }.count, 1)
    }

    /// WebKit's own menu, kept over a picture that is also a link: the item
    /// is put under its Download Image and names the picture; a menu with
    /// no Download Image (a plain link's) gets none.
    func testWebKitsMenuOverAPictureGetsItToo() throws {
        let (browser, tab) = makeTab()
        defer { browser.closeAll() }
        let page = try XCTUnwrap(tab.built)
        let url = try XCTUnwrap(URL(string: "https://pictures.example/cat.jpg"))
        var chosen: [(URL, ImageAction)] = []
        page.onImage = { chosen.append(($0, $1)) }

        func item(_ title: String, _ id: String) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier(id)
            return item
        }
        let menu = NSMenu()
        menu.addItem(item("Open Link in New Window", "WKMenuItemIdentifierOpenLinkInNewWindow"))
        menu.addItem(item("Download Image", "WKMenuItemIdentifierDownloadImage"))
        menu.addItem(item("Copy Image", "WKMenuItemIdentifierCopyImage"))
        PageView.dress(menu, for: url, target: page)
        XCTAssertEqual(menu.items.map(\.title), ["Open Link in New Window", "Download Image", "Add Image to Photos", "Copy Image"])

        let photos = menu.items[2]
        XCTAssertEqual(photos.representedObject as? URL, url)
        XCTAssertTrue(photos.target === page)
        for at in [1, 2, 3] { menu.performActionForItem(at: at) }
        XCTAssertEqual(chosen.map(\.0), [url, url, url])
        XCTAssertEqual(chosen.map(\.1), [.download, .photos, .copy])

        let link = NSMenu()
        link.addItem(item("Open Link in New Window", "WKMenuItemIdentifierOpenLinkInNewWindow"))
        link.addItem(item("Copy Link", "WKMenuItemIdentifierCopyLink"))
        PageView.dress(link, for: url, target: page)
        XCTAssertEqual(link.items.map(\.title), ["Open Link in New Window", "Copy Link"])
    }

    /// The app that is built can put the question, and only that one: a
    /// sentence for adding, none for reading, and the hardened runtime's
    /// leave in every set of entitlements build.sh signs with.
    func testTheBuiltAppAsksToAddAndNothingMore() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func read(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }

        let build = try read("build.sh")
        XCTAssertTrue(build.contains("<key>NSPhotoLibraryAddUsageDescription</key>"))
        XCTAssertFalse(build.contains("NSPhotoLibraryUsageDescription"), "no sentence for reading the library")

        for file in ["Search.entitlements", "Search.passkeys.entitlements", "Search.icloud.entitlements"] {
            let data = try Data(contentsOf: root.appendingPathComponent(file))
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            XCTAssertEqual(plist["com.apple.security.personal-information.photos-library"] as? Bool, true, file)
        }

        let source = try read("Sources/Search/AddToPhotos.swift")
        XCTAssertTrue(source.contains("requestAuthorization(for: .addOnly)"))
        XCTAssertFalse(source.contains(".readWrite"))
        // Nowhere else in the app is the library touched.
        let sources = root.appendingPathComponent("Sources/Search")
        for file in try FileManager.default.contentsOfDirectory(atPath: sources.path) where file.hasSuffix(".swift") && file != "AddToPhotos.swift" {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            XCTAssertFalse(text.contains("PHPhotoLibrary"), file)
        }
    }
}
