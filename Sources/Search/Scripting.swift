import AppKit

// AppleScript, in Safari's words (#232): a window's `tabs` and its
// `current tab`, and each tab's `URL` and `name`; and the names of the
// window's `space` and `profile` (#836). Search.sdef says so, and build.sh
// puts it in the app. All of it is to read, but for one thing: a script may
// say which of a window's tabs is the one in front (`set current tab of
// window 1 to tab 2 of window 1`), as it may in Safari. Nothing here runs
// anything in a page, or opens, closes or moves a tab.
//
// Only an app allowed in System Settings › Privacy & Security › Automation
// gets this far. Private tabs are never shown to it: they are left out of
// the list, and a window whose tab in front is private has no current tab,
// space or profile (missing value). Not being in the list, a private tab
// can't be gone to by a script either.

/// A tab as a script sees it: where its page is and what it's called.
@MainActor
@objc(ScriptTab)
final class ScriptTab: NSObject {
    fileprivate let tab: Tab
    /// Its place among the tabs a script sees, private ones left out, which
    /// is what `tab N of window …` counts.
    private let index: Int
    private weak var window: NSWindow?

    init(_ tab: Tab, index: Int, in window: NSWindow) {
        self.tab = tab
        self.index = index
        self.window = window
    }

    /// The page that is on screen, not an address typed, loading or held.
    /// Never a name or password written into the address (user:password@).
    @objc var url: String {
        guard let page = tab.pageAddress else { return "" }
        guard var parts = URLComponents(url: page, resolvingAgainstBaseURL: false), parts.user != nil || parts.password != nil
        else { return page.absoluteString }
        parts.user = nil
        parts.password = nil
        return parts.url?.absoluteString ?? ""
    }
    /// That page's title. The tab's own is emptied as soon as a load starts;
    /// the page's stays until the next one has arrived, as the address does.
    @objc var name: String {
        if tab.committed != nil, let page = tab.built { return page.title ?? "" }
        return tab.title
    }

    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let window, let container = window.objectSpecifier,
              let description = container.keyClassDescription
        else { return nil }
        return NSIndexSpecifier(
            containerClassDescription: description,
            containerSpecifier: container, key: "scriptTabs", index: index
        )
    }
}

extension NSWindow {
    /// Its own browser's tabs, private ones left out. A window that isn't a
    /// browser's — Settings, a panel — has none.
    @MainActor @objc var scriptTabs: [ScriptTab] {
        Scripting.shown(in: self).enumerated().map { ScriptTab($0.element, index: $0.offset, in: self) }
    }

    /// The tab in front, unless it is private. Set, that tab comes to the
    /// front of this window (see Scripting.go).
    @MainActor @objc var scriptCurrentTab: ScriptTab? {
        get { Scripting.front(of: self).map { ScriptTab($0.tab, index: $0.index, in: self) } }
        set { Scripting.go(to: newValue, in: self) }
    }

    /// The name of the space the window shows. With spaces off, that is its
    /// profile's first space, whose tabs and sign-ins the window has. Read
    /// from `Spaces.known`: a popup window never refreshes its own list, so
    /// it would keep a space's old name after a rename.
    @MainActor @objc var scriptSpace: String? {
        Scripting.front(of: self).map { Spaces.known[$0.browser.spaceID]?.name ?? $0.browser.space.name }
    }

    /// The name of the profile the window is in: Personal's, while it is the
    /// only one.
    @MainActor @objc var scriptProfile: String? {
        Scripting.front(of: self).map { Profiles.shared.profile($0.browser.profileID).name }
    }
}

@MainActor
enum Scripting {
    /// The tabs a script may see in a window: its browser's, without the
    /// private ones.
    static func shown(in window: NSWindow) -> [Tab] {
        Browsers.browser(for: window)?.tabs.filter { !$0.shy } ?? []
    }

    /// A window's browser and its tab in front, with that tab's place among
    /// the ones shown; nil for a window that isn't a browser's, or whose tab
    /// in front is private, so `space` and `profile` never reveal one (#836).
    static func front(of window: NSWindow) -> (browser: Browser, tab: Tab, index: Int)? {
        guard let browser = Browsers.browser(for: window), let active = browser.active, !active.shy,
              let index = shown(in: window).firstIndex(where: { $0 === active })
        else { return nil }
        return (browser, active, index)
    }

    /// `set current tab of window … to tab …`: that tab in front, in the
    /// window it is in. Only one of the tabs the script was shown in this
    /// same window; any other, or none, is refused and nothing changes. The
    /// window stays where it is among the others: a script switching tabs
    /// is no reason to take the screen from what you are doing.
    @discardableResult
    static func go(to picked: ScriptTab?, in window: NSWindow) -> Bool {
        guard let picked, let browser = Browsers.browser(for: window),
              shown(in: window).contains(where: { $0 === picked.tab })
        else {
            refuse("The current tab of a window can only be set to one of that window's tabs.")
            return false
        }
        if browser.activeID != picked.tab.id { browser.select(picked.tab) }
        return true
    }

    /// What the script is told when what it asked for isn't done.
    private static func refuse(_ words: String) {
        guard let command = NSScriptCommand.current() else { return }
        command.scriptErrorNumber = errAEEventNotPermitted
        command.scriptErrorString = words
    }
}
