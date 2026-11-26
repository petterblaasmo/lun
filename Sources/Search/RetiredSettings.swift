import Foundation

// The switches Lun took out of Settings.
//
// Settings had 154 rows, most of them a fair answer to one person's
// request and off unless asked for. Lun keeps the ones worth choosing and
// fixes the rest (26 Nov 2026): no row, nothing in the find field. Most
// are fixed at what they already did by default, their stored choice put
// aside so the default is what is read. Twenty-five that were off unless
// asked for are fixed on instead (`fixed`): each was a better browser than
// the one without it, and none was worth a switch.
//
// Retired, not deleted: the code behind each switch, its property on
// Preferences and its tests are left as they were, so what comes from
// upstream still fits. Lun's difference is this one file, and the few
// lines that read it (SettingsIndex.offered, Preferences.init, WhatsNew).

enum RetiredSettings {
    /// Rows of SettingsIndex that are no longer drawn or found.
    static let rows: Set<String> = [
        // Fixed at their default.
        "downloads.button", "sidebar.foldIcons", "layout.cardsFullScreen", "toolbar.left", "tabs.compact",
        "window.glass.style", "tabs.liquid", "sidebar.doorsUp", "helm.shown", "foot.shown", "sidebar.foldButton",
        "tabs.reading", "bookmarks.iconsOnly", "bookmarks.newTabOnly", "tabs.newAfterLast", "tabs.keepWindow",
        "tabs.closeGoesBack", "tabs.switcherBehindFirst", "tabs.switcherLeavesOutPins", "tabs.lazy",
        "tabs.sleep.dim", "tabs.shortcuts", "tabs.address", "tabs.clickAddressOnly", "tabs.clickKeepsName",
        "search.shift", "field.top", "reader.twins", "float.style", "float.minimize",
        "fullscreen.escapeTwice", "fullscreen.keepsWindow", "pages.120", "spaces.buttons", "pins.keep",
        "pins.commandNewTab", "field.hidesPage", "newtab.recent", "passkeys", "privacy.clickIDs", "privacy.gpc",
        "keys.backspaceBack", "swipe.history", "updates.notice",
        // Said twice: the Mac's own setting, or another row, decides.
        "scrollbars.fade", "tabs.highContrast", "motion.instant", "pins.linksNewTab", "launcher.little",
        // Drawn inside another row now (Show the bookmarks bar, Bring
        // things over, Open the address field from any app).
        "bookmarks.side", "arc.import", "launcher.key",
        // From before.
        "address.width", "glyph", "news.updates", "news.iphone",
        // Always on (see `fixed`).
        "downloads.open", "sidebar.slides", "fold.loadingLine", "sidebar.narrowIcons", "sidebar.player",
        "tabs.pinCounts", "tabs.give", "motion.light", "tabs.frontBeside", "tabs.swipeBackCloses",
        "tabs.undoReopens", "tabs.popupWindows", "links.little.tabs", "reader.follows", "video.keys",
        "pages.capture", "pins.folders", "field.window", "newtab.arc", "commandbar", "privacy.httpsFirst",
        "links.peek.stays", "links.optionSplit", "wheel.smooth", "pages.bounce",
    ]

    /// The switches fixed at something other than their default, with what
    /// each is fixed at: on, and for Downloads the card floating by its
    /// button. Written at launch, since some are read straight from the
    /// store (Motion), not only by Preferences.
    static let fixed: [(key: String, value: Any)] = [
        ("downloads.open", DownloadsOpening.popover.rawValue),
        ("sidebar.slides", true), ("fold.loadingLine", true), ("sidebar.narrowIcons", true),
        ("sidebar.player", true), ("tabs.pinCounts", true), ("tabs.give", true), ("motion.light", true),
        ("tabs.frontBeside", true), ("tabs.swipeBackCloses", true), ("tabs.undoReopens", true),
        ("tabs.popupWindows", true), ("links.little.tabs", true), ("reader.follows", true),
        ("video.keys", true), ("pages.capture", true), ("pins.folders", true), ("field.window", true),
        ("newtab.arc", true), ("commandbar", true), ("privacy.httpsFirst", true),
        ("links.peek.stays", true), ("links.optionSplit", true), ("wheel.smooth", true), ("pages.bounce", true),
    ]

    /// The defaults keys those switches wrote. Put aside at launch, so each
    /// reads as its default. "glyph" is not among them: its being there at
    /// all says this install is one from before the welcome (Preferences),
    /// so it is left and only its value is no longer read.
    static let keys: [String] = [
        "downloads.button", "sidebar.foldIcons", "layout.cardsFullScreen", "toolbar.left", "tabs.compact",
        "window.glass.style", "tabs.liquid", "sidebar.doorsUp",
        "helm.back.hidden", "helm.forward.hidden", "helm.reload.hidden",
        "foot.extensions.hidden", "foot.bookmarks.hidden", "foot.profile.hidden",
        "sidebar.foldButton", "tabs.reading", "bookmarks.iconsOnly", "bookmarks.newTabOnly",
        "tabs.newAfterLast", "tabs.keepWindow", "tabs.closeGoesBack", "tabs.switcherBehindFirst",
        "tabs.switcherLeavesOutPins", "tabs.lazy", "tabs.sleep.dim", "tabs.shortcuts", "tabs.address",
        "tabs.clickAddressOnly", "tabs.clickKeepsName", "search.shift", "search.shiftCustom", "field.top",
        "reader.twins", "float.style", "float.minimize", "fullscreen.escapeTwice", "fullscreen.keepsWindow",
        "pages.120", "pages.120.mode", "spaces.buttons", "pins.home", "pins.peek", "pins.commandNewTab",
        "field.hidesPage", "newtab.recent", "passkeys", "privacy.clickIDs", "privacy.gpc",
        "keys.backspaceBack", "swipe.history", "update.notice",
        "scrollbars.fade", "tabs.highContrast", "motion.instant", "pins.linksNewTab", "launcher.little",
        "address.width",
    ]

    /// What's New's switches for the same things, by the title its card
    /// gives them: not offered there either.
    static let offers: Set<String> = [
        "Links from pins open in a new tab", "Keep the window when its last tab closes",
        "Clicking the tab you're on keeps its name", "Fade scroll bars", "Update ready, in the window",
        "Bookmarks bar only on new tabs",
        "Click the tab you're on to edit its address", "Icons only on the bookmarks bar", "Sidebar button",
        "One button per space", "Buttons at the top", "Dim sleeping tabs", "High contrast tab text",
        "Keep the card in full screen", "⌘-click on a pin opens a new tab", "Close goes back",
        "Tab numbers while ⌘ is held", "Escape twice to leave full screen", "Pins keep their site",
        "Always show the downloads button", "Pages at 120 Hz",
        // Always on.
        "Space and arrow keys control videos", "The field in the middle of the window",
        "Smooth scrolling with a mouse wheel", "A loading line with the tabs hidden",
        "Unread counts on pinned tabs", "Narrow to icons", "Swipe back closes a link's tab",
        "⌘T finds your open tabs", "Try HTTPS first", "⌥-click a link opens it in Split View",
        "Bounce at the top and bottom", "Slide the column in and out", "Commands in the address field",
        "Capture", "Folders in pinned rows",
    ]

    /// Where a put-aside choice is kept, should its switch ever come back.
    static func aside(_ key: String) -> String { "retired." + key }

    /// Puts every stored choice of a retired switch aside, so the default
    /// is read, and writes what the fixed ones are fixed at. Before anything
    /// in Preferences reads the store.
    static func settle(_ store: UserDefaults) {
        for key in keys {
            guard let was = store.object(forKey: key) else { continue }
            store.set(was, forKey: aside(key))
            store.removeObject(forKey: key)
        }
        for (key, value) in fixed {
            let was = store.object(forKey: key) as? NSObject
            guard was?.isEqual(value) != true else { continue }
            if let was { store.set(was, forKey: aside(key)) }
            store.set(value, forKey: key)
        }
    }

    /// Not in a test run: the tests of what these switches do set them
    /// first, and were written against the defaults. LUN_SETTLE=1 runs the
    /// tests as the app is, to see what the fixed ones change.
    static var applies: Bool {
        !Store.testing || ProcessInfo.processInfo.environment["LUN_SETTLE"] != nil
    }
}
