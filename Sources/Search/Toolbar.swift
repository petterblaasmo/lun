import SwiftUI

// The address above the page, with the tabs down a side (#235): the row the
// tabs across the top have under them (AddressRow), back, forward and reload
// before the address and the page's own buttons after it, and the
// extensions at its end. Off unless asked for (Settings › Appearance ›
// Window › Address bar above the page). The column gives up its address,
// its three buttons and the extensions while the row has them, so each is
// in one place only: an extension's popup hangs from the one button there
// is (ExtensionSlot).
//
// With the page as a card, the row is the card's first row, as it is under
// the tabs across the top: the card starts above it and the page's own edge
// is the line between the two (ContentView.rowsInCard). Its middle is on
// the lights' line, so it reads as one title bar with the column's top row.
// Edge to edge it has its own ground and is as tall as the column's top
// row. It stays when the column folds away (⌘S), which is what it is for:
// the page's address and the way back with no column in the window, where
// the card from the top edge came down for them before (EdgeBar, which
// keeps away while this row is up). A page filling the screen takes it away.

struct Toolbar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    /// The first row of the page's card, which draws the ground and the
    /// edge; otherwise on its own ground, a hairline under it.
    var inCard = false

    /// The column's top row's height (Metrics.strip).
    @MainActor static var height: CGFloat { Metrics.strip }
    /// Inside the card, from the card's top down, centred on the lights'
    /// line as the column's top row is.
    @MainActor static var inCard: CGFloat { 2 * (Metrics.strip / 2 - Metrics.cardGap) }

    var body: some View {
        HStack(spacing: 2) {
            AddressRow(browser: browser)
                // Its suggestions hang over the page below.
                .zIndex(1)
            ExtensionSlot(browser: browser, edge: .bottom, puzzle: !prefs.hidesExtensionsDoor)
        }
        .padding(.horizontal, 8)
        .frame(height: inCard ? Toolbar.inCard : Toolbar.height)
        .frame(maxWidth: .infinity)
        // Title bar above and below the row's controls, as the column's top
        // row is: a press there moves the window and a double-click does
        // what the title bar's does. The band the controls sit in is theirs.
        .background(DragStrip(reserved: .greatestFiniteMagnitude, band: 30))
        .background {
            if !inCard {
                ZStack(alignment: .bottom) {
                    // On glass the window's ground shows through (Glass.swift).
                    if !browser.glassy {
                        Palette.ground
                        // The space's wash carried on under it, as under the
                        // bookmarks bar.
                        SpaceWash(look: browser.wash)
                    }
                    // Under the row, not over it: the suggestions hang
                    // across this line and on down over the page.
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }
            }
        }
        .environment(\.greys, .white)
    }
}
