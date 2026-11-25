import SwiftUI

// A blank tab's grid: the sites of the bookmark folder called Home, each a
// tile with its saved title. Off unless Settings › Tabs turns it on; nothing
// is drawn without such a folder.
struct HomeGrid: View {
    let browser: Browser
    @ObservedObject private var typing: FieldState
    @ObservedObject private var prefs: Preferences

    init(browser: Browser) {
        self.browser = browser
        typing = browser.typing
        prefs = browser.prefs
    }

    /// How tall the grid stands under the field, nought when it isn't
    /// drawn: the open tabs an empty side of a Split View offers go under
    /// it, where they lay over its tiles (#1381).
    static func height(_ browser: Browser) -> CGFloat {
        guard browser.prefs.homeGrid, browser.active?.isBlank == true, browser.typing.typed.isEmpty else { return 0 }
        let count = browser.bookmarks.homeSites.count
        guard count > 0 else { return 0 }
        let rows = CGFloat((count + 3) / 4)
        return rows * 50 + (rows - 1) * 8
    }

    var body: some View {
        // The switch first: off, the bookmarks aren't walked at each key.
        if prefs.homeGrid, browser.active?.isBlank == true, typing.typed.isEmpty,
           case let sites = browser.bookmarks.homeSites, !sites.isEmpty {
            // As wide as the field, hung just under it (Omnibox.under).
            GeometryReader { page in
                let width = Omnibox.width(in: page.size)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(sites) { site in
                        Button { site.address.map(browser.openBookmark) } label: {
                            Text(site.label)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                                .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.hairline))
                                .contentShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: width)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, Omnibox.under(in: page.size) + 12)
            }
        }
    }
}
