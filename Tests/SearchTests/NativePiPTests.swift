import WebKit
import XCTest
@testable import Search

/// Settings › General › The floating video: Search's window unless picture
/// in picture is chosen, and the choice kept (idea 376). Entering picture
/// in picture puts a system window on screen, so that part is by eye.
@MainActor
final class NativePiPTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    func testSearchsWindowUnlessChosen() {
        let saved = Store.settings.object(forKey: "float.style")
        defer { Store.settings.set(saved, forKey: "float.style") }
        Store.settings.removeObject(forKey: "float.style")
        XCTAssertEqual(Preferences().floatStyle, .search)
        let prefs = Preferences()
        prefs.floatStyle = .system
        XCTAssertEqual(Preferences().floatStyle, .system)
        Store.settings.set("nonsense", forKey: "float.style")
        XCTAssertEqual(Preferences().floatStyle, .search)
    }

    func testScriptsAskOnlyForPictureInPicture() {
        let on = NativePiP.script(toggle: false)
        XCTAssertTrue(on.contains("var toggle = false"))
        XCTAssertTrue(NativePiP.script(toggle: true).contains("var toggle = true"))
        XCTAssertTrue(on.contains("webkitSetPresentationMode('picture-in-picture')"))
        XCTAssertFalse(on.contains("fullscreen"))
        XCTAssertTrue(NativePiP.off.contains("webkitSetPresentationMode('inline')"))
    }

    /// Only what is playing with a picture is offered to picture in
    /// picture: a song played through a video with none (YouTube Music's,
    /// nought by nought) has nothing to show there, playing or paused.
    func testAVideoWithNoPictureIsNotOffered() async throws {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        // A video that says it is playing and can go into picture in
        // picture, and notes it when sent there: no window is opened.
        let stand = """
        window.stand = function (wide, high, css) {
          var v = document.createElement('video');
          Object.defineProperties(v, {
            paused: { value: false }, ended: { value: false }, readyState: { value: 4 },
            videoWidth: { value: wide }, videoHeight: { value: high },
            webkitPresentationMode: { value: 'inline', writable: true },
            webkitSupportsPresentationMode: { value: function () { return true; } },
            webkitSetPresentationMode: { value: function (mode) { this.webkitPresentationMode = mode; } }
          });
          v.style.cssText = css;
          (document.body || document.documentElement).appendChild(v);
          return v;
        };
        window.song = window.stand(0, 0, 'width:300px;height:200px;display:block');
        true;
        """
        _ = try await web.evaluateJavaScript(stand)
        for toggle in [false, true] {
            let said = try await web.evaluateJavaScript(NativePiP.script(toggle: toggle)) as? String
            XCTAssertEqual(said, "none", "a sound alone is nothing to show (toggle: \(toggle))")
        }
        // Beside a film, the film goes, small as it is on the page.
        _ = try await web.evaluateJavaScript("window.film = window.stand(320, 180, 'width:10px;height:10px;display:block'); true;")
        let said = try await web.evaluateJavaScript(NativePiP.script(toggle: true)) as? String
        XCTAssertEqual(said, "in")
        let modes = try await web.evaluateJavaScript("[window.song.webkitPresentationMode, window.film.webkitPresentationMode]") as? [String]
        XCTAssertEqual(modes, ["inline", "picture-in-picture"], "the film goes, not the larger video with no picture")
    }
}
