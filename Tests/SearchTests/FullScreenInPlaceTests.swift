import AppKit
import ObjectiveC
import XCTest
@testable import Search

/// A video's full screen kept on the desktop it was asked from
/// (FullScreenInPlace): WebKit's window asks macOS for a Space and is
/// answered here instead, its delegate told what AppKit would have told it.
/// A window and a delegate of the tests' own stand in for WebKit's; no
/// window is ever ordered in. What WebKit and the screen do with it is
/// Tests/fullscreen_in_place.py's and an eye's.
@MainActor
final class FullScreenInPlaceTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    private static let enter = NSSelectorFromString("enterFullScreenMode:")
    private static let exit = NSSelectorFromString("exitFullScreenMode:")

    /// WebKit's full-screen window: the two calls it makes, counted when
    /// they get as far as macOS.
    private class Lent: NSWindow {
        var sent = 0, fetched = 0
        var onSpace = true
        override var isOnActiveSpace: Bool { onSpace }
        @objc(enterFullScreenMode:) dynamic func enterFullScreenMode(_ sender: Any?) { sent += 1 }
        @objc(exitFullScreenMode:) dynamic func exitFullScreenMode(_ sender: Any?) { fetched += 1 }
    }

    /// One that is never asked to stay in place.
    private final class Untouched: Lent {
        @objc(enterFullScreenMode:) dynamic override func enterFullScreenMode(_ sender: Any?) { sent += 1 }
        @objc(exitFullScreenMode:) dynamic override func exitFullScreenMode(_ sender: Any?) { fetched += 1 }
    }

    /// One whose delegate says nothing about full screen.
    private final class Mute: Lent {
        @objc(enterFullScreenMode:) dynamic override func enterFullScreenMode(_ sender: Any?) { sent += 1 }
        @objc(exitFullScreenMode:) dynamic override func exitFullScreenMode(_ sender: Any?) { fetched += 1 }
    }

    /// WebKit's controller, as the window's delegate.
    private final class Told: NSObject, NSWindowDelegate {
        var heard: [String] = []
        func window(_ window: NSWindow, startCustomAnimationToEnterFullScreenWithDuration duration: TimeInterval) { heard.append("in") }
        func windowDidEnterFullScreen(_ notification: Notification) { heard.append("entered") }
        func window(_ window: NSWindow, startCustomAnimationToExitFullScreenWithDuration duration: TimeInterval) { heard.append("out") }
        func windowDidExitFullScreen(_ notification: Notification) { heard.append("exited") }
    }

    private final class Silent: NSObject, NSWindowDelegate {}

    private final class Watcher: NSObject {
        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {}
    }

    private static let made: NSWindow.StyleMask = [.titled, .closable, .resizable, .fullSizeContentView]
    private var told = Told()
    private var bars = NSApplication.PresentationOptions()

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        // Nothing moves: what follows an animation follows at once.
        Motion.testReduceMotion = true
        told = Told()
        bars = NSApp.presentationOptions
    }

    override func tearDown() {
        Motion.testReduceMotion = nil
        super.tearDown()
    }

    private static let rect = NSRect(x: 0, y: 0, width: 200, height: 100)

    private func ready<Window: Lent>(_ window: Window) -> Window {
        window.isReleasedWhenClosed = false
        window.delegate = told
        return window
    }

    private func lent() -> Lent {
        ready(Lent(contentRect: Self.rect, styleMask: Self.made, backing: .buffered, defer: true))
    }

    private func ask(_ window: NSWindow, _ selector: Selector) { window.perform(selector, with: nil) }

    /// What waits for an animation to end has run.
    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

    func testInAndBackOnTheSameDesktop() {
        let window = lent()
        FullScreenInPlace.wait(for: window, inPlace: true)
        XCTAssertEqual(FullScreenInPlace.stage(of: window), .waiting)
        XCTAssertEqual(window.styleMask, [.borderless], "no title bar over the video")

        ask(window, Self.enter)
        XCTAssertEqual(window.sent, 0, "macOS is never asked for a Space")
        XCTAssertEqual(told.heard, ["in"])
        XCTAssertEqual(FullScreenInPlace.stage(of: window), .filling)
        XCTAssertTrue(FullScreenInPlace.filling)
        XCTAssertEqual(NSApp.presentationOptions, [.autoHideMenuBar, .autoHideDock])
        settle()
        XCTAssertEqual(told.heard, ["in", "entered"])

        ask(window, Self.exit)
        XCTAssertEqual(told.heard, ["in", "entered", "out"])
        XCTAssertTrue(FullScreenInPlace.filling, "until the page is back")
        settle()
        XCTAssertEqual(told.heard, ["in", "entered", "out", "exited"])
        XCTAssertEqual(window.fetched, 0)
        XCTAssertEqual(FullScreenInPlace.stage(of: window), .home)
        XCTAssertFalse(FullScreenInPlace.filling)
        XCTAssertEqual(NSApp.presentationOptions, bars, "the menu bar and the Dock as they were")
        window.close()
    }

    func testSwitchOffIsWebKitsOwn() throws {
        let window = ready(Untouched(contentRect: Self.rect, styleMask: Self.made, backing: .buffered, defer: true))
        let before = try XCTUnwrap(class_getInstanceMethod(Untouched.self, Self.enter).map(method_getImplementation))
        FullScreenInPlace.wait(for: window, inPlace: false)
        ask(window, Self.enter)
        ask(window, Self.exit)
        XCTAssertEqual([window.sent, window.fetched], [1, 1])
        XCTAssertEqual(told.heard, [])
        XCTAssertEqual(window.styleMask, Self.made)
        XCTAssertNil(FullScreenInPlace.stage(of: window))
        XCTAssertEqual(NSApp.presentationOptions, bars)
        // Nothing of the window's class is touched until the switch is on.
        XCTAssertEqual(class_getInstanceMethod(Untouched.self, Self.enter).map(method_getImplementation), before)
    }

    func testSwitchTurnedOffGoesBackToWebKitsOwn() {
        let window = lent()
        FullScreenInPlace.wait(for: window, inPlace: true)
        ask(window, Self.enter); settle()
        // Turned off while a video is in place: that one still leaves in place.
        ask(window, Self.exit); settle()
        XCTAssertEqual(told.heard, ["in", "entered", "out", "exited"])
        XCTAssertEqual(window.styleMask, [.borderless])

        FullScreenInPlace.wait(for: window, inPlace: false)
        XCTAssertEqual(window.styleMask, Self.made, "as WebKit made it, for a Space of its own")
        ask(window, Self.enter)
        ask(window, Self.exit)
        XCTAssertEqual([window.sent, window.fetched], [1, 1])
        XCTAssertEqual(told.heard, ["in", "entered", "out", "exited"], "told nothing more")
        XCTAssertEqual(NSApp.presentationOptions, bars)
        window.close()
    }

    func testAskedForAndThenNot() {
        let window = lent()
        FullScreenInPlace.wait(for: window, inPlace: true)
        FullScreenInPlace.wait(for: window, inPlace: false)
        XCTAssertEqual(FullScreenInPlace.stage(of: window), .home)
        XCTAssertEqual(window.styleMask, Self.made)
        ask(window, Self.enter)
        XCTAssertEqual(window.sent, 1)
        window.close()
    }

    func testTabClosedWhileInIt() {
        let window = lent()
        FullScreenInPlace.wait(for: window, inPlace: true)
        ask(window, Self.enter); settle()
        XCTAssertEqual(NSApp.presentationOptions, [.autoHideMenuBar, .autoHideDock])
        // WebKit closes its window with the page, asking nothing.
        window.close()
        XCTAssertNil(FullScreenInPlace.stage(of: window))
        XCTAssertFalse(FullScreenInPlace.filling)
        XCTAssertEqual(NSApp.presentationOptions, bars)
        settle()
        XCTAssertEqual(told.heard, ["in", "entered"])
    }

    func testClosedOnTheWayIn() {
        let window = lent()
        FullScreenInPlace.wait(for: window, inPlace: true)
        ask(window, Self.enter)
        window.close()
        settle()
        XCTAssertEqual(told.heard, ["in"], "a closed window is told nothing")
        XCTAssertEqual(NSApp.presentationOptions, bars)
    }

    func testClosedOnTheWayBack() {
        let window = lent()
        FullScreenInPlace.wait(for: window, inPlace: true)
        ask(window, Self.enter); settle()
        ask(window, Self.exit)
        window.close()
        settle()
        XCTAssertEqual(told.heard, ["in", "entered", "out"])
        XCTAssertEqual(NSApp.presentationOptions, bars)
    }

    func testLeftFromAnotherDesktop() {
        let window = lent()
        FullScreenInPlace.wait(for: window, inPlace: true)
        ask(window, Self.enter); settle()
        // WebKit brings the page home itself when its window isn't in view.
        window.onSpace = false
        ask(window, Self.exit); settle()
        XCTAssertEqual(told.heard, ["in", "entered"])
        XCTAssertEqual(window.fetched, 0)
        XCTAssertEqual(FullScreenInPlace.stage(of: window), .home)
        XCTAssertEqual(NSApp.presentationOptions, bars)
        window.close()
    }

    /// AppKit takes the menu bar and the Dock going as a change of screen,
    /// and pulls a window that hangs over the screen's edge whole onto it
    /// (and one far off back to where it last was). Every window of the
    /// app's is where it was, in and out.
    func testOtherWindowsStayWhereTheyWere() throws {
        let screen = try XCTUnwrap(NSScreen.main).frame
        let window = lent()
        let over = NSWindow(contentRect: NSRect(x: screen.midX, y: screen.midY, width: 400, height: 300),
                            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        over.isReleasedWhenClosed = false
        // On screen as far as AppKit knows, and clear (Tests/NoWindows);
        // then dragged half off it, as a person parks a window.
        over.orderBack(nil)
        defer { over.close() }
        over.setFrame(NSRect(x: screen.maxX - 150, y: screen.minY - 120, width: 400, height: 300), display: false)
        let was = over.frame
        XCTAssertGreaterThan(was.maxX, screen.maxX, "it hangs over the edge to begin with")

        FullScreenInPlace.wait(for: window, inPlace: true)
        ask(window, Self.enter); settle()
        XCTAssertEqual(NSApp.presentationOptions, [.autoHideMenuBar, .autoHideDock])
        XCTAssertEqual(over.frame, was)
        ask(window, Self.exit); settle()
        XCTAssertEqual(over.frame, was)
        window.close()
    }

    func testTwoVideosShareTheBars() {
        let one = lent(), two = lent()
        for window in [one, two] {
            FullScreenInPlace.wait(for: window, inPlace: true)
            ask(window, Self.enter)
        }
        settle()
        ask(one, Self.exit); settle()
        XCTAssertEqual(NSApp.presentationOptions, [.autoHideMenuBar, .autoHideDock], "the other still fills the screen")
        ask(two, Self.exit); settle()
        XCTAssertEqual(NSApp.presentationOptions, bars)
        one.close(); two.close()
    }

    func testADelegateThatSaysNothingIsLeftToWebKit() {
        let window = ready(Mute(contentRect: Self.rect, styleMask: Self.made, backing: .buffered, defer: true))
        let silent = Silent()
        window.delegate = silent
        FullScreenInPlace.wait(for: window, inPlace: true)
        XCTAssertNil(FullScreenInPlace.stage(of: window))
        XCTAssertEqual(window.styleMask, Self.made)
        ask(window, Self.enter)
        XCTAssertEqual(window.sent, 1)
    }

    /// WebKit watches its window by key-value observing, which gives the
    /// window a class of its own: the calls are answered for the class
    /// WebKit made, so for every such window, watched or not.
    func testAWatchedWindowIsAnsweredByItsOwnClass() {
        let watched = lent(), other = lent()
        let watcher = Watcher()
        watched.addObserver(watcher, forKeyPath: "contentLayoutRect", options: [], context: nil)
        defer { watched.removeObserver(watcher, forKeyPath: "contentLayoutRect") }
        XCTAssertFalse(object_getClass(watched) === Lent.self)
        for window in [watched, other] {
            FullScreenInPlace.wait(for: window, inPlace: true)
            ask(window, Self.enter)
            XCTAssertEqual(window.sent, 0)
        }
        settle()
        XCTAssertEqual(told.heard, ["in", "in", "entered", "entered"])
        watched.close(); other.close()
    }

    func testTheSwitch() throws {
        let item = try XCTUnwrap(SettingsIndex.item("fullscreen.inPlace"))
        XCTAssertEqual(item.group, "video")
        XCTAssertEqual(item.keys, ["fullscreen.inPlace"])
        XCTAssertTrue(SettingsIndex.find("full screen").contains { $0.id == "fullscreen.inPlace" })
        XCTAssertFalse(RetiredSettings.rows.contains("fullscreen.inPlace"))
        XCTAssertTrue(WhatsNew.toggles.contains { $0.title == item.title })

        let name = "inplace-\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        XCTAssertFalse(store.bool(forKey: "fullscreen.inPlace"), "off unless turned on")

        let prefs = Shared.prefs
        XCTAssertFalse(prefs.fullScreenInPlace)
        prefs.fullScreenInPlace = true
        XCTAssertTrue(FullScreenInPlace.on)
        prefs.fullScreenInPlace = false
        XCTAssertFalse(FullScreenInPlace.on)
    }
}
