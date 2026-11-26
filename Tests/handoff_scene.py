#!/usr/bin/env python3
"""A page handed off from an iPhone, or a file opened from the Finder, keeps
the window's tabs.

`python3 Tests/handoff_scene.py` (no build of Lun needed).

SwiftUI's own app delegate takes such an event to a scene before the app's
delegate hears of it, and for a `Window` scene that means closing the open
window and opening it again. Lun reads a close as yours (Browsers.closing):
with another window open, the closed one's tabs all go. The scene says
`.handlesExternalEvents(matching: [])`, which keeps SwiftUI out of it.

The app itself can't be handed an event headless: SwiftUI brings its window
forward for one. So a small SwiftUI app with the same kind of scene is built
here twice, without the line and with it, and each is handed the two events
through SwiftUI's delegate while it counts the windows that close. Its
windows are transparent from the moment they are made and it is never the
active app, so nothing reaches the screen. The script also checks that Lun's
own scene still carries the line.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

APP = r'''
import SwiftUI
import AppKit
import ObjectiveC

/// Every window transparent from birth, whatever it is told later.
func keepWindowsUnseen() {
    typealias SetAlpha = @convention(c) (NSWindow, Selector, CGFloat) -> Void
    let setAlpha = #selector(setter: NSWindow.alphaValue)
    let alphaMethod = class_getInstanceMethod(NSWindow.self, setAlpha)!
    let plainAlpha = unsafeBitCast(method_getImplementation(alphaMethod), to: SetAlpha.self)
    let never: @convention(block) (NSWindow, CGFloat) -> Void = { window, _ in plainAlpha(window, setAlpha, 0) }
    method_setImplementation(alphaMethod, imp_implementationWithBlock(never))

    typealias Make = @convention(c) (NSWindow, Selector, NSRect, UInt, UInt, Bool) -> NSWindow
    let make = #selector(NSWindow.init(contentRect:styleMask:backing:defer:))
    let makeMethod = class_getInstanceMethod(NSWindow.self, make)!
    let plainMake = unsafeBitCast(method_getImplementation(makeMethod), to: Make.self)
    let unseen: @convention(block) (NSWindow, NSRect, UInt, UInt, Bool) -> NSWindow = { window, rect, style, backing, later in
        let made = plainMake(window, make, rect, style, backing, later)
        plainAlpha(made, setAlpha, 0)
        return made
    }
    method_setImplementation(makeMethod, imp_implementationWithBlock(unseen))
}

func say(_ line: String) { print(line); fflush(stdout) }

/// This process's windows the window server draws with any alpha at all.
func onScreen() -> Int {
    let all = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return all.filter {
        ($0[kCGWindowOwnerPID as String] as? Int32) == getpid() && (($0[kCGWindowAlpha as String] as? Double) ?? 0) > 0
    }.count
}

final class Delegate: NSObject, NSApplicationDelegate {
    var second: NSWindow?
    var closed = 0

    func applicationDidFinishLaunching(_ note: Notification) {
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            self.closed += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            // A second window, AppKit's own, as Lun's other windows are.
            let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 300, height: 200),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSView()
            window.orderBack(nil)
            self.second = window

            let swiftUI = NSApp.delegate!
            let handed = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
            handed.webpageURL = URL(string: "https://example.com/handed")
            _ = swiftUI.application?(NSApp, continue: handed, restorationHandler: { _ in })
            say("handoff closed=\(self.closed)")
            self.closed = 0
            swiftUI.application?(NSApp, open: [URL(fileURLWithPath: "/tmp/page.html")])
            say("file closed=\(self.closed)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                say("onscreen=\(onScreen())")
                exit(0)
            }
        }
    }

    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        say("heard handoff")
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        say("heard file")
    }
}

@main
struct ProbeApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate

    init() {
        keepWindowsUnseen()
        NSApplication.shared.setActivationPolicy(.prohibited)
    }

    var body: some Scene {
        #if KEPT_OUT
        Window("Probe", id: "probe") { Color.clear }
            .windowStyle(.hiddenTitleBar)
            .handlesExternalEvents(matching: [])
        #else
        Window("Probe", id: "probe") { Color.clear }
            .windowStyle(.hiddenTitleBar)
        #endif
    }
}
'''

failed = 0


def ok(name, passed, detail=""):
    global failed
    print(("ok   " if passed else "FAIL ") + name + ("" if passed else f"  {detail}"))
    if not passed:
        failed += 1


def run(kept_out, folder):
    source = folder / "main.swift"
    source.write_text(APP)
    binary = folder / ("kept-out" if kept_out else "plain")
    flags = ["-DKEPT_OUT"] if kept_out else []
    subprocess.run(["swiftc", "-parse-as-library", *flags, str(source), "-o", str(binary)], check=True)
    out = subprocess.run([str(binary)], capture_output=True, text=True, timeout=60).stdout
    return out, {name: int(count) for name, count in re.findall(r"^(handoff|file) closed=(\d+)", out, re.M)}


def main():
    app = (ROOT / "Sources/Search/App.swift").read_text()
    scene = app[app.index("id: Browsers.sceneID)"):app.index(".commands {")]
    ok("Lun's scene keeps SwiftUI out of events from outside", ".handlesExternalEvents(matching: [])" in scene)

    with tempfile.TemporaryDirectory(prefix="handoff-scene-") as temporary:
        folder = Path(temporary)
        out, plain = run(False, folder)
        ok("without the line: SwiftUI closes the window for a handed-off page", plain.get("handoff", 0) >= 1, out)
        ok("without the line: and for a file opened", plain.get("file", 0) >= 1, out)
        ok("without the line: the app's delegate still hears both", "heard handoff" in out and "heard file" in out, out)
        ok("nothing on screen", "onscreen=0" in out, out)

        out, kept = run(True, folder)
        ok("with it: no window closes for a handed-off page", kept.get("handoff") == 0, out)
        ok("with it: nor for a file opened", kept.get("file") == 0, out)
        ok("with it: the app's delegate hears both", "heard handoff" in out and "heard file" in out, out)
        ok("nothing on screen", "onscreen=0" in out, out)

    print(f"\n{failed} failed" if failed else "\nall passed")
    return 1 if failed else 0


if __name__ == "__main__":
    if sys.platform != "darwin":
        sys.exit("Tests/handoff_scene.py needs macOS")
    sys.exit(main())
