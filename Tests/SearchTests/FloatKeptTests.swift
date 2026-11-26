import AppKit
import WebKit
import XCTest
@testable import Search

/// The floating video's page keeps the size it had in its tab, a part of it
/// shown at the window's size (Float.kept): which part, when a page can, and
/// that its view is then never resized. Arithmetic, and a window off every
/// screen: the page drawn in it, video and all, is Tests/float_kept.py's.
@MainActor
final class FloatKeptTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    func testThePartShownIsTheWindowsShapeAroundThePicture() throws {
        let shape = NSSize(width: 440, height: 247)
        // Sixteen by nine, in a page a little taller: all but the window's
        // shape already, a hair of black each side.
        let film = NSRect(x: 0, y: 12.5, width: 1200, height: 675)
        let part = try XCTUnwrap(Float.crop(around: film, shape: shape))
        XCTAssertEqual(part.height, 675, accuracy: 0.001)
        XCTAssertEqual(part.width, 675 * 440 / 247, accuracy: 0.001)
        XCTAssertEqual(part.midX, film.midX, accuracy: 0.001)
        XCTAssertEqual(part.midY, film.midY, accuracy: 0.001)

        // Whatever the picture's shape, the part is the window's, holds the
        // picture whole, is about its middle, and is no larger than it has
        // to be: one way they are the same size.
        let pictures = [
            NSRect(x: 150, y: 0, width: 900, height: 675),      // four by three
            NSRect(x: 410, y: 0, width: 380, height: 675),      // upright
            NSRect(x: 0, y: 85.7, width: 1200, height: 514.3),  // wide
            NSRect(x: 0, y: 0, width: 300, height: 168.75),     // a small page
        ]
        for picture in pictures {
            let part = try XCTUnwrap(Float.crop(around: picture, shape: shape))
            XCTAssertEqual(part.width / part.height, shape.width / shape.height, accuracy: 0.0001)
            XCTAssertTrue(part.insetBy(dx: -0.001, dy: -0.001).contains(picture), "\(picture) whole in \(part)")
            XCTAssertEqual(part.midX, picture.midX, accuracy: 0.001)
            XCTAssertEqual(part.midY, picture.midY, accuracy: 0.001)
            XCTAssertTrue(abs(part.width - picture.width) < 0.001 || abs(part.height - picture.height) < 0.001)
        }
        XCTAssertNil(Float.crop(around: NSRect(x: 0, y: 0, width: 0, height: 100), shape: shape))
        XCTAssertNil(Float.crop(around: film, shape: .zero))
    }

    func testAPageKeepsItsSizeOnlyAsItSaidItIs() {
        let view = NSSize(width: 1200, height: 700)
        let picture: [Double] = [0, 12.5, 1200, 675]
        XCTAssertEqual(Float.kept(picture: picture, page: [1200, 700], zoom: 1, magnification: 1, view: view),
                       NSRect(x: 0, y: 12.5, width: 1200, height: 675))
        // Zoomed with ⌘+: the page's own pixels are larger than points.
        XCTAssertEqual(Float.kept(picture: [0, 10, 960, 540], page: [960, 560], zoom: 1.25, magnification: 1, view: view),
                       NSRect(x: 0, y: 12.5, width: 1200, height: 675))
        XCTAssertNil(Float.kept(picture: picture, page: [1200, 700], zoom: 1, magnification: 1.4, view: view),
                     "pinched larger, the view shows a part of the page")
        XCTAssertNil(Float.kept(picture: picture, page: [1000, 700], zoom: 1, magnification: 1, view: view),
                     "an answer from before the view was resized")
        XCTAssertNil(Float.kept(picture: [0, 12.5, 1200], page: [1200, 700], zoom: 1, magnification: 1, view: view))
        XCTAssertNil(Float.kept(picture: [0, 12.5, 1200, .nan], page: [1200, 700], zoom: 1, magnification: 1, view: view))
        XCTAssertNil(Float.kept(picture: [0, 12.5, 0, 0], page: [1200, 700], zoom: 1, magnification: 1, view: view))
        XCTAssertNil(Float.kept(picture: [0, 400, 1200, 675], page: [1200, 700], zoom: 1, magnification: 1, view: view),
                     "a picture that runs off the page is not all there to show")
        XCTAssertNil(Float.kept(picture: picture, page: [1200, 700], zoom: 1, magnification: 1, view: .zero))
    }

    func testAPageThatKeepsItsSizeIsShownScaledAndNeverResized() async throws {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 700))
        web.autoresizingMask = [.height]
        let picture = NSRect(x: 0, y: 12.5, width: 1200, height: 675)
        try await withFloatUp(page: web, picture: picture) { floater, panel in
            XCTAssertTrue(floater.keeps)
            XCTAssertFalse(floater.covered, "nothing is laid out again: no still over it")
            XCTAssertTrue(floater.unseen, "unseen until the page is drawn in it")
            XCTAssertEqual(web.frame.size, NSSize(width: 1200, height: 700))

            // Where the picture is in the window: all of its height, in the middle.
            @MainActor func shown() throws -> NSRect {
                let shows = try XCTUnwrap(floater.benchShows())
                XCTAssertEqual(shows.views.minX, shows.layers.minX, accuracy: 0.01, "the layers drawn are where the views say")
                XCTAssertEqual(shows.views.minY, shows.layers.minY, accuracy: 0.01)
                XCTAssertEqual(shows.views.width, shows.layers.width, accuracy: 0.01)
                XCTAssertEqual(shows.views.height, shows.layers.height, accuracy: 0.01)
                let by = shows.views.width / shows.page.width
                return NSRect(x: shows.views.minX + picture.minX * by, y: shows.views.minY + picture.minY * by,
                              width: picture.width * by, height: picture.height * by)
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            var seen = try shown()
            XCTAssertEqual(seen.minY, 0, accuracy: 0.01)
            XCTAssertEqual(seen.height, 247, accuracy: 0.01)
            XCTAssertEqual(seen.midX, 220, accuracy: 0.01)
            XCTAssertEqual(seen.width, 247 * 1200 / 675, accuracy: 0.01)

            // The window made twice as large: the same part, twice as large,
            // and the page the size it was.
            let f = panel.frame
            panel.setFrame(NSRect(x: f.minX, y: f.minY, width: 880, height: 494), display: false)
            XCTAssertEqual(web.frame.size, NSSize(width: 1200, height: 700))
            try await Task.sleep(nanoseconds: 100_000_000)
            seen = try shown()
            XCTAssertEqual(seen.minY, 0, accuracy: 0.01)
            XCTAssertEqual(seen.height, 494, accuracy: 0.01)
            XCTAssertEqual(seen.midX, 440, accuracy: 0.01)

            // A page with nothing in it never says it is drawn: the window
            // is shown at its limit all the same.
            try await Task.sleep(nanoseconds: 900_000_000)
            XCTAssertFalse(floater.unseen)

            floater.drop()
            XCTAssertEqual(web.frame.size, NSSize(width: 1200, height: 700), "home at the size it left at")
            XCTAssertEqual(web.autoresizingMask, [.height], "and sized by its own again")
            XCTAssertFalse(floater.keeps)
        }
    }

    func testAPageLaidOutAtTheWindowsSizeIsCoveredAsBefore() async throws {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 700))
        try await withFloatUp(page: web, picture: nil) { floater, panel in
            XCTAssertFalse(floater.keeps)
            XCTAssertTrue(floater.covered)
            XCTAssertFalse(floater.unseen)
            XCTAssertEqual(web.frame.size, panel.frame.size)
        }
    }

    /// The floating window up, off every screen, holding `page`.
    private func withFloatUp(page: NSView, picture: NSRect?, _ body: (Float, NSWindow) async throws -> Void) async throws {
        _ = NSApplication.shared
        let was = (Float.benchAway, Store.settings.object(forKey: "float.frame"))
        Store.settings.removeObject(forKey: "float.frame")
        Float.benchAway = NSPoint(x: -30000, y: -30000)
        let floater = Float()
        defer {
            floater.drop()
            Float.benchAway = was.0
            Store.settings.set(was.1, forKey: "float.frame")
        }
        floater.lift(page, picture: picture)
        try await body(floater, try XCTUnwrap(floater.benchWindow))
    }
}
