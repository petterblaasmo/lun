import Foundation
@testable import Search

/// Every setting as it was when the run began, put back before each test.
///
/// The settings are one object for the whole run (`Shared.prefs`), and a
/// test that turns the column on, or the address line, or spaces, turned it
/// on for every test after it: each kept a list of the few it changed and
/// put those back, and whatever a list missed made a later test fail only
/// in some orders (issue 98). Here the whole of it is kept once and put back
/// by TestWorld, so a test sets what it needs and owes nothing afterwards.
///
/// A setting is put back through its own setter, and only where it differs,
/// so nothing happens for the ones a test left alone.
/// TestWorldTests holds this list to the settings there are.
@MainActor
enum KeptSettings {
    private static var kept: [(name: String, putBack: () -> Bool)] = []

    /// The names kept, for the test that holds the list complete.
    static var names: Set<String> { Set(kept.map(\.name)) }

    /// The setters nobody outside Preferences has: read from the store only.
    static let readOnly: Set<String> = ["aiModels"]

    private static func keep<Value: Equatable>(_ name: String, _ path: ReferenceWritableKeyPath<Preferences, Value>) {
        let prefs = Shared.prefs
        let value = prefs[keyPath: path]
        kept.append((name, {
            guard prefs[keyPath: path] != value else { return false }
            prefs[keyPath: path] = value
            return true
        }))
    }

    /// Put back, and which had been changed. Twice over, since one setter
    /// may move another (the tabs' layout sets three).
    @discardableResult
    static func putBack() -> [String] {
        var changed: [String] = []
        for _ in 0..<2 {
            for setting in kept where setting.putBack() { changed.append(setting.name) }
        }
        return changed
    }

    static func take() {
        guard kept.isEmpty else { return }
        keep("copiesCapturesOnly", \.copiesCapturesOnly)
        keep("homeTiles", \.homeTiles)
        keep("animatesDownloads", \.animatesDownloads)
        keep("tabClickRenames", \.tabClickRenames)
        keep("screenshotsInDownloads", \.screenshotsInDownloads)
        keep("splitControls", \.splitControls)
        keep("meetPiP", \.meetPiP)
        keep("pinPreviews", \.pinPreviews)
        keep("hidingShapes", \.hidingShapes)
        keep("developerLocal", \.developerLocal)
        keep("navigationLeft", \.navigationLeft)
        keep("compactStrip", \.compactStrip)
        keep("bench", \.bench)
        keep("agents", \.agents)
        keep("look", \.look)
        keep("homeTheme", \.homeTheme)
        keep("homeTuning", \.homeTuning)
        keep("homeShuffle", \.homeShuffle)
        keep("homeThemeImage", \.homeThemeImage)
        keep("sidebar", \.sidebar)
        keep("sidePanelWidth", \.sidePanelWidth)
        keep("sidePosition", \.sidePosition)
        keep("sideHides", \.sideHides)
        keep("slidesColumn", \.slidesColumn)
        keep("roomyTabs", \.roomyTabs)
        keep("doorsUp", \.doorsUp)
        keep("foldButton", \.foldButton)
        keep("sideIcons", \.sideIcons)
        keep("foldsToIcons", \.foldsToIcons)
        keep("narrowsToIcons", \.narrowsToIcons)
        keep("narrowed", \.narrowed)
        keep("showsPlayer", \.showsPlayer)
        keep("sideWidth", \.sideWidth)
        keep("cards", \.cards)
        keep("cardsInFullScreen", \.cardsInFullScreen)
        keep("addressLine", \.addressLine)
        keep("scrollbarsFade", \.scrollbarsFade)
        keep("addressWidth", \.addressWidth)
        keep("addressPlace", \.addressPlace)
        keep("glass", \.glass)
        keep("glassGrain", \.glassGrain)
        keep("glassClear", \.glassClear)
        keep("liquidTabs", \.liquidTabs)
        keep("glassStyle", \.glassStyle)
        keep("glyph", \.glyph)
        keep("engine", \.engine)
        keep("customEngine", \.customEngine)
        keep("customSuggest", \.customSuggest)
        keep("shiftEngine", \.shiftEngine)
        keep("shiftCustom", \.shiftCustom)
        keep("keywords", \.keywords)
        keep("keepsSitesAwake", \.keepsSitesAwake)
        keep("tabsGive", \.tabsGive)
        keep("awakeSites", \.awakeSites)
        keep("popupWindows", \.popupWindows)
        keep("popupSites", \.popupSites)
        keep("sleepsTabs", \.sleepsTabs)
        keep("dimsSleepingTabs", \.dimsSleepingTabs)
        keep("hidesBack", \.hidesBack)
        keep("hidesForward", \.hidesForward)
        keep("hidesReload", \.hidesReload)
        keep("hidesExtensionsDoor", \.hidesExtensionsDoor)
        keep("hidesBookmarksDoor", \.hidesBookmarksDoor)
        keep("hidesProfileDoor", \.hidesProfileDoor)
        keep("tabLife", \.tabLife)
        keep("sleepPace", \.sleepPace)
        keep("siteNotifications", \.siteNotifications)
        keep("lazyTabs", \.lazyTabs)
        keep("newTabAfterLast", \.newTabAfterLast)
        keep("keepWindowAfterLast", \.keepWindowAfterLast)
        keep("closeGoesBack", \.closeGoesBack)
        keep("homeGrid", \.homeGrid)
        keep("undoReopensTab", \.undoReopensTab)
        keep("switcherBehindFirst", \.switcherBehindFirst)
        keep("switcherLeavesOutPins", \.switcherLeavesOutPins)
        keep("newTabPlace", \.newTabPlace)
        keep("frontLinksBeside", \.frontLinksBeside)
        keep("swipeBackCloses", \.swipeBackCloses)
        keep("mirrorsTabs", \.mirrorsTabs)
        keep("startsFresh", \.startsFresh)
        keep("confirmsQuit", \.confirmsQuit)
        keep("searchesSites", \.searchesSites)
        keep("engineSuggests", \.engineSuggests)
        keep("showsTabShortcuts", \.showsTabShortcuts)
        keep("showsReading", \.showsReading)
        keep("showsPinCounts", \.showsPinCounts)
        keep("highContrastText", \.highContrastText)
        keep("showsAddress", \.showsAddress)
        keep("tabClickAddressOnly", \.tabClickAddressOnly)
        keep("tabClickKeepsName", \.tabClickKeepsName)
        keep("shielded", \.shielded)
        keep("keepsSignIns", \.keepsSignIns)
        keep("sendsPrivacySignal", \.sendsPrivacySignal)
        keep("triesHTTPSFirst", \.triesHTTPSFirst)
        keep("removesClickIDs", \.removesClickIDs)
        keep("passkeys", \.passkeys)
        keep("downloads", \.downloads)
        keep("asksWhereToSave", \.asksWhereToSave)
        keep("savesPasswords", \.savesPasswords)
        keep("fillsPasswords", \.fillsPasswords)
        keep("asksBeforeFilling", \.asksBeforeFilling)
        keep("fillsContacts", \.fillsContacts)
        keep("applePasswords", \.applePasswords)
        keep("welcomed", \.welcomed)
        keep("autocorrect", \.autocorrect)
        keep("inlinePredictions", \.inlinePredictions)
        keep("pageZoom", \.pageZoom)
        keep("darkensPages", \.darkensPages)
        keep("capturesPages", \.capturesPages)
        keep("sitesStyles", \.sitesStyles)
        keep("inspectorChrome", \.inspectorChrome)
        keep("inspectorDark", \.inspectorDark)
        keep("autoScroll", \.autoScroll)
        keep("videoKeys", \.videoKeys)
        keep("wheelGlides", \.wheelGlides)
        keep("bounces", \.bounces)
        keep("fastPages", \.fastPages)
        keep("lightMotion", \.lightMotion)
        keep("instantMotion", \.instantMotion)
        keep("peekClick", \.peekClick)
        keep("peeksLinks", \.peeksLinks)
        keep("peekStays", \.peekStays)
        keep("optionClickSplits", \.optionClickSplits)
        keep("backspaceGoesBack", \.backspaceGoesBack)
        keep("pinsPeek", \.pinsPeek)
        keep("readsTwins", \.readsTwins)
        keep("readerFollowsLook", \.readerFollowsLook)
        keep("littleLinks", \.littleLinks)
        keep("webmail", \.webmail)
        keep("linksFindTabs", \.linksFindTabs)
        keep("sendsLinksToSpaces", \.sendsLinksToSpaces)
        keep("spaceButtons", \.spaceButtons)
        keep("spaceRoutes", \.spaceRoutes)
        keep("spaceForOtherLinks", \.spaceForOtherLinks)
        keep("asksSpaceForLinks", \.asksSpaceForLinks)
        keep("linkChoices", \.linkChoices)
        keep("alwaysShowsDownloads", \.alwaysShowsDownloads)
        keep("downloadsOpening", \.downloadsOpening)
        keep("bookmarksBar", \.bookmarksBar)
        keep("bookmarksInSidebar", \.bookmarksInSidebar)
        keep("bookmarksNewTabOnly", \.bookmarksNewTabOnly)
        keep("bookmarksIconsOnly", \.bookmarksIconsOnly)
        keep("showsLinks", \.showsLinks)
        keep("holdsHistory", \.holdsHistory)
        keep("floatFlicks", \.floatFlicks)
        keep("floatMinimizes", \.floatMinimizes)
        keep("floatsAway", \.floatsAway)
        keep("waitsForPlay", \.waitsForPlay)
        keep("translateTarget", \.translateTarget)
        keep("translateAlways", \.translateAlways)
        keep("floatsOnLeave", \.floatsOnLeave)
        keep("sitesInPanel", \.sitesInPanel)
        keep("panelSite", \.panelSite)
        keep("floatStyle", \.floatStyle)
        keep("escapeTwice", \.escapeTwice)
        keep("keepsWindow", \.keepsWindow)
        keep("installsUpdates", \.installsUpdates)
        keep("showsUpdateReady", \.showsUpdateReady)
        keep("updateHiddenBuild", \.updateHiddenBuild)
        keep("usesSpaces", \.usesSpaces)
        keep("spacesOnCommand", \.spacesOnCommand)
        keep("profilesInOneWindow", \.profilesInOneWindow)
        keep("usesTabGroups", \.usesTabGroups)
        keep("listsPins", \.listsPins)
        keep("pinFolders", \.pinFolders)
        keep("pinsGoHome", \.pinsGoHome)
        keep("pinCommandOpensTab", \.pinCommandOpensTab)
        keep("pinLinksOpenTabs", \.pinLinksOpenTabs)
        keep("pinNumberGoesBack", \.pinNumberGoesBack)
        keep("sharesPins", \.sharesPins)
        keep("ai", \.ai)
        keep("aiProvider", \.aiProvider)
        keep("showsLoadingLine", \.showsLoadingLine)
        keep("splitView", \.splitView)
        keep("switcherKeys", \.switcherKeys)
        keep("handoff", \.handoff)
        keep("commandBar", \.commandBar)
        keep("floatingNewTab", \.floatingNewTab)
        keep("fieldOnWindow", \.fieldOnWindow)
        keep("fieldHidesPage", \.fieldHidesPage)
        keep("launcher", \.launcher)
        keep("launcherLittle", \.launcherLittle)
        keep("launcherKey", \.launcherKey)
        keep("recentInNewTab", \.recentInNewTab)
        keep("arcTabPopup", \.arcTabPopup)
        keep("returnTakesTop", \.returnTakesTop)
    }
}
