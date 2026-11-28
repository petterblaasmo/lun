import AppKit
import ObjectiveC
import WebKit

// A video's full screen without leaving the desktop (issue 240).
//
// WebKit lends a page that asks for the screen to a window of its own and
// sends that window into macOS full screen: a Space of its own, reached by
// the desktop-switching animation each way. With Settings › Browsing ›
// Video › Full screen stays on this desktop on (off unless turned on), the
// window stays where it is instead. WebKit has already laid it over the
// whole screen, in the Space in view, before it asks macOS for a Space;
// only that last step is answered here.
//
// Everything about the page is still WebKit's: the Fullscreen API and the
// click or key it needs, `:fullscreen`, a player inside a frame, Escape,
// the page's own button, and the page coming home. Three upstream attempts
// (upstream PRs 1269, 1425 and 1487) answered the API from a script in the
// page instead, and none landed: a page can tell an imitation from the
// real thing, and only the top page was sure to be answered.
//
// How: WebKit's window asks macOS for full screen with enterFullScreenMode:
// and leaves with exitFullScreenMode:, and hears how it went through the
// NSWindowDelegate methods AppKit calls around a custom full-screen
// animation. The two calls are answered for that window's class alone, and
// the delegate is told what AppKit would have told it: start your
// animation, and then that it is over. Neither call is in AppKit's headers.
// Should WebKit stop making them, or rename its window, nothing here runs
// and full screen is WebKit's again, as with the switch off.
//
// Measured in a bare WKWebView on macOS 26.6 (28 Nov 2026): the page and a
// player in a frame from another site both go in and come back, by Escape
// and by the page's own exitFullscreen, and a page closed while in it
// closes the window. Not for a window that is itself in macOS full screen:
// a second window can't join its Space this way, so WebKit's own is kept.
@MainActor
enum FullScreenInPlace {
    /// Settings › Browsing › Video › Full screen stays on this desktop, as
    /// Preferences has it.
    static var on = false

    private static let enter = NSSelectorFromString("enterFullScreenMode:")
    private static let exit = NSSelectorFromString("exitFullScreenMode:")

    enum Stage {
        /// Asked for by its page, not yet on screen.
        case waiting
        /// Over the screen, on the desktop it was asked from.
        case filling
        /// Put away, or sent to a Space as WebKit would.
        case home
    }

    /// One of WebKit's full-screen windows. Each page has its own, made the
    /// first time it asks and kept for as long as the page is.
    @MainActor private final class Held {
        weak var window: NSWindow?
        /// The style WebKit gave it, for a Space of its own.
        let style: NSWindow.StyleMask
        var stage = Stage.home
        var strip: NSWindow?
        var closes: NSObjectProtocol?

        init(_ window: NSWindow) {
            self.window = window
            style = window.styleMask
        }
    }

    private static var holds: [ObjectIdentifier: Held] = [:]
    private static var hooked: Set<ObjectIdentifier> = []
    /// What the app asked of the menu bar and the Dock before a video took
    /// the screen.
    private static var barsBefore: NSApplication.PresentationOptions?

    /// A page on its way into full screen (Tab's fullscreenState watch):
    /// WebKit has moved it into its window by now, and has yet to show that
    /// window or ask macOS for the Space.
    static func entering(_ page: WKWebView) {
        guard let window = page.window, NSStringFromClass(type(of: window)) == "WebCoreFullScreenWindow" else { return }
        // Already on screen: the order this leans on isn't the one WebKit
        // kept, and the window is left alone.
        wait(for: window, inPlace: on && !window.isVisible && !besideFullScreenWindow)
    }

    /// One of the app's windows is in macOS full screen, in the Space in view.
    private static var besideFullScreenWindow: Bool {
        NSApp.windows.contains { $0.styleMask.contains(.fullScreen) && $0.isOnActiveSpace }
    }

    /// `window`, about to be asked into full screen: to stay in place, or
    /// to go as WebKit sends it.
    static func wait(for window: NSWindow, inPlace: Bool) {
        let key = ObjectIdentifier(window)
        let known = holds[key].flatMap { $0.window === window ? $0 : nil }
        guard known?.stage != .filling else { return }
        guard inPlace, answers(window.delegate), hook(type(of: window)) else {
            // Decided here, not by what an earlier time left behind: to a
            // Space of its own, as WebKit made it.
            if let known { asMade(known, window) }
            return
        }
        let held = known ?? hold(window)
        held.stage = .waiting
        // No title bar: outside macOS full screen it would lie over the top
        // of the video, take the clicks there and round the screen's corners.
        if window.styleMask != [.borderless] { window.styleMask = [.borderless] }
    }

    private static func asMade(_ held: Held, _ window: NSWindow) {
        held.stage = .home
        if window.styleMask != held.style { window.styleMask = held.style }
    }

    private static func hold(_ window: NSWindow) -> Held {
        let held = Held(window)
        holds[ObjectIdentifier(window)] = held
        // The page closed while in it, its tab or its process gone: WebKit
        // closes the window without asking to leave.
        held.closes = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: nil) { note in
            MainActor.assumeIsolated {
                guard let window = note.object as? NSWindow, let held = holds[ObjectIdentifier(window)] else { return }
                over(held)
                if let closes = held.closes { NotificationCenter.default.removeObserver(closes) }
                holds[ObjectIdentifier(window)] = nil
            }
        }
        return held
    }

    /// Whether a window of WebKit's is over the screen in place.
    static var filling: Bool { holds.values.contains { $0.stage == .filling } }

    /// Where `window` is, for the tests.
    static func stage(of window: NSWindow) -> Stage? {
        holds[ObjectIdentifier(window)].flatMap { $0.window === window ? $0.stage : nil }
    }

    // MARK: - the two calls

    /// The delegate hears what AppKit would have told it, or nothing is tried.
    private static func answers(_ delegate: NSWindowDelegate?) -> Bool {
        guard let delegate else { return false }
        return [#selector(NSWindowDelegate.window(_:startCustomAnimationToEnterFullScreenWithDuration:)),
                #selector(NSWindowDelegate.windowDidEnterFullScreen(_:)),
                #selector(NSWindowDelegate.window(_:startCustomAnimationToExitFullScreenWithDuration:)),
                #selector(NSWindowDelegate.windowDidExitFullScreen(_:))].allSatisfy(delegate.responds(to:))
    }

    /// The two calls answered for `cls`, once: here first, and by AppKit as
    /// before whenever this says no.
    private static func hook(_ cls: AnyClass) -> Bool {
        if hooked.contains(ObjectIdentifier(cls)) { return true }
        guard let goes = class_getInstanceMethod(cls, enter), let leaves = class_getInstanceMethod(cls, exit) else { return false }
        typealias Call = @convention(c) (NSWindow, Selector, AnyObject?) -> Void
        for (selector, method, entering) in [(enter, goes, true), (exit, leaves, false)] {
            let original = unsafeBitCast(method_getImplementation(method), to: Call.self)
            let block: @convention(block) (NSWindow, AnyObject?) -> Void = { window, sender in
                let taken = MainActor.assumeIsolated { entering ? fill(window) : leave(window) }
                if !taken { original(window, selector, sender) }
            }
            class_replaceMethod(cls, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method))
        }
        hooked.insert(ObjectIdentifier(cls))
        return true
    }

    /// WebKit's window asking macOS for full screen. True when it stays in
    /// place: its animation is started here and, once over, said to be.
    private static func fill(_ window: NSWindow) -> Bool {
        guard let held = holds[ObjectIdentifier(window)], held.window === window else { return false }
        guard held.stage == .waiting, let delegate = window.delegate else {
            asMade(held, window)
            return false
        }
        held.stage = .filling
        hideBars()
        cover(above: window, for: held)
        let length = Motion.duration(.settle)
        delegate.window?(window, startCustomAnimationToEnterFullScreenWithDuration: max(length, 0.01))
        after(length) { [weak window] in
            // Closed on the way in: nothing is left to tell.
            guard let window, held.stage == .filling else { return }
            window.delegate?.windowDidEnterFullScreen?(Notification(name: NSWindow.didEnterFullScreenNotification, object: window))
        }
        return true
    }

    /// WebKit's window asking to leave macOS full screen. True when it was
    /// never there: the way back is animated and ended here.
    private static func leave(_ window: NSWindow) -> Bool {
        guard let held = holds[ObjectIdentifier(window)], held.window === window, held.stage == .filling else { return false }
        // With its window on another Space, WebKit has brought the page
        // home already and waits for nothing.
        guard window.isOnActiveSpace, let delegate = window.delegate else {
            over(held)
            return true
        }
        let length = Motion.duration(.settle)
        delegate.window?(window, startCustomAnimationToExitFullScreenWithDuration: max(length, 0.01))
        Motion.run(.settle) { held.strip?.animator().alphaValue = 0 }
        after(length) { [weak window] in
            guard held.stage == .filling else { return }
            over(held)
            guard let window else { return }
            window.delegate?.windowDidExitFullScreen?(Notification(name: NSWindow.didExitFullScreenNotification, object: window))
        }
        return true
    }

    private static func after(_ length: TimeInterval, _ then: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + length) { MainActor.assumeIsolated(then) }
    }

    /// No longer over the screen: the menu bar and the Dock as they were,
    /// once no other video has them away.
    private static func over(_ held: Held) {
        held.stage = .home
        held.strip?.orderOut(nil)
        held.strip = nil
        guard !filling, let before = barsBefore else { return }
        barsBefore = nil
        NSApp.presentationOptions = before
    }

    // MARK: - the screen's edges

    /// The menu bar and the Dock out of the way, back at the screen's edge
    /// under the pointer, as in macOS full screen.
    private static func hideBars() {
        guard barsBefore == nil else { return }
        barsBefore = NSApp.presentationOptions
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
    }

    /// Beside a camera housing WebKit keeps its window below the menu bar's
    /// strip, which macOS paints black in a Space of its own. Here the
    /// desktop would show through it: a black strip of our own, until the
    /// video leaves.
    private static func cover(above window: NSWindow, for held: Held) {
        guard let screen = window.screen else { return }
        let housing = screen.safeAreaInsets.top
        guard housing > 0, abs(screen.frame.maxY - window.frame.maxY - housing) < 1 else { return }
        let frame = NSRect(x: screen.frame.minX, y: window.frame.maxY, width: screen.frame.width, height: housing)
        let strip = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
        strip.isReleasedWhenClosed = false
        strip.backgroundColor = .black
        strip.hasShadow = false
        strip.animationBehavior = .none
        strip.collectionBehavior = [.stationary, .ignoresCycle]
        strip.alphaValue = 0
        strip.order(.below, relativeTo: window.windowNumber)
        Motion.run(.settle) { strip.animator().alphaValue = 1 }
        held.strip = strip
    }
}
