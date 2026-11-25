import AppKit
import SwiftUI

// The address of the page in front, always in sight, for whoever wants it
// (Settings › Appearance › Window › Always show the address bar, #1227,
// #1240), with the site card's button at its end. Off unless asked for:
// Search shows the address when you go to change it, with ⌘L. On, it sits
// at the top of the column, as tall as a tab and in line with them, or
// before the tabs across the top, Small or Medium.
//
// At rest it says where the page is from, as the tab at rest does
// (AtRestLine): the site in ink, not the whole address in grey, which read
// as a text box nobody meant you to touch. It answers the pointer as a
// button does: a little brighter under it, and lifted off the column once
// clicked.
//
// A click there is ⌘L's editing, in place: the same field, the address in
// it to type over, and the same suggestions hanging under the line rather
// than in the middle of the page (Browser.inlineEdit). The line lifts off
// the column while it is typed in. ⌘L itself still raises its field over
// the page. A click anywhere else puts it away, as Escape does. Search's own
// pages show their own address, and a tab with nothing in it what to type.

enum AddressWidth: String, CaseIterable, Identifiable {
    case small, medium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        }
    }

    var width: CGFloat {
        switch self {
        case .small: return 220
        case .medium: return 340
        }
    }
}

struct AddressLine: View {
    @ObservedObject var browser: Browser
    /// A tab's height in the column; the row's across the top.
    var height: CGFloat = 28
    /// In the column, which cuts off whatever passes its edge: typed in, the
    /// card is drawn by the column instead (AddressCard.Place), out over the
    /// page.
    var inColumn = false

    /// The room after it, before the tabs across the top.
    static let after: CGFloat = 8

    /// The bench pictures the line as it is under the pointer.
    @MainActor static var benchHovering = false

    var body: some View {
        // The tab says when its address changes; the browser only which tab.
        // A tab with nothing in it has the field in the middle of the window:
        // a second empty one up here would only ask the same again.
        if let tab = browser.active, !tab.isBlank {
            Shown(browser: browser, tab: tab, height: height, inColumn: inColumn).id(tab.id)
        }
    }

    private struct Shown: View {
        @ObservedObject var browser: Browser
        @ObservedObject var tab: Tab
        let height: CGFloat
        let inColumn: Bool
        @Environment(\.greys) private var greys
        /// The line and its site button, for the site card to hang under.
        @State private var line = ViewAnchor.Box()
        @State private var options = ViewAnchor.Box()
        @State private var hovering = false
        @State private var width: CGFloat = 0

        private var url: URL? { tab.page?.url ?? tab.address }
        private var rest: AtRest? { AtRest.of(url) }
        /// What follows the site, said under the pointer: the page's own path.
        private var path: String? {
            guard let url, url.scheme == "http" || url.scheme == "https" else { return nil }
            let path = url.path() + (url.query().map { "?" + $0 } ?? "")
            return path.isEmpty || path == "/" ? nil : path.removingPercentEncoding ?? path
        }
        private var lit: Bool { hovering || AddressLine.benchHovering }
        private var editing: Bool { browser.editingInline }

        var body: some View {
            HStack(spacing: 6) {
                if let rest {
                    if rest.kind == .notSecure {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.unsafe)
                            .help("Not secure")
                            .accessibilityLabel("Not secure")
                    }
                    HStack(spacing: 0) {
                        AtRestLine(rest: rest, size: 13, ink: Palette.ink, dim: Palette.muted, says: false, weight: .regular)
                            .layoutPriority(1)
                        if lit, let path {
                            Text(path)
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                                .fixedSize()
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                .clipped()
                                .mask {
                                    HStack(spacing: 0) {
                                        Rectangle()
                                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 16)
                                    }
                                }
                        }
                    }
                } else if tab.isBlank == false, let title = tab.page?.title {
                    Text(title).foregroundStyle(Palette.ink).lineLimit(1)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.muted)
                    Text("Search or enter address")
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if tab.isWeb, lit {
                    // The site card (#1240), for a page on the web, under
                    // the pointer.
                    button("slider.horizontal.3", help: "Site Settings") {
                        siteCard()
                    }
                    .background(ViewAnchor(box: options))
                }
            }
            .font(.system(size: 13))
            .padding(.leading, 12)
            .padding(.trailing, tab.isWeb && lit ? 4 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .background(lit ? greys.pinLive : greys.tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            // Under the card while it is open, which takes its place.
            .opacity(editing ? 0 : 1)
            .animation(.easeOut(duration: 0.12), value: lit)
            .background(ViewAnchor(box: line))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { if !browser.editing { browser.edit(); browser.inlineEdit = true } }
            .shortcutHelp("Type an address or a search", "file.openAddress")
            // The button is only there under the pointer.
            .contextMenu { if tab.isWeb { Button("Site Settings") { siteCard() } } }
            // Where the column is to draw the card.
            .anchorPreference(key: AddressCard.Place.self, value: .bounds) { editing && inColumn ? $0 : nil }
            // Across the top nothing cuts it off: it opens where it is.
            .overlay(alignment: .topLeading) {
                if editing && !inColumn {
                    AddressCard(browser: browser, height: height, width: AddressCard.width(for: width), line: width)
                }
            }
            .animation(.easeOut(duration: 0.15), value: editing)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }

        private func siteCard() {
            guard let under = line.view else { return }
            SiteCardPanel.toggle(for: tab, in: browser, under: under, button: options.view ?? under)
        }

        private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
        }
    }
}

/// The address bar typed in: the field and its suggestions in one card, as
/// a command bar is, as wide as the field in the middle of the window and so
/// out over the page.
struct AddressCard: View {
    @ObservedObject var browser: Browser
    /// What is typed and what answers it, which the browser doesn't publish.
    @ObservedObject private var typing: FieldState
    /// The line's height, which the card's field row is a little taller than.
    let height: CGFloat
    let width: CGFloat
    /// The line's own width, which the card keeps until something is typed.
    let line: CGFloat

    init(browser: Browser, height: CGFloat, width: CGFloat, line: CGFloat) {
        self.browser = browser
        self.typing = browser.typing
        self.height = height
        self.width = width
        self.line = line
    }

    /// The card's width for a line this wide, in a window this wide.
    static func width(for line: CGFloat, window: CGFloat? = nil) -> CGFloat {
        max(line, min(Metrics.fieldWidth, (window ?? .infinity) - 2 * Metrics.sideInset))
    }

    /// The icon of the place Return would go to, or the glass.
    private var lead: NSImage? {
        guard let picked = browser.picked ?? (browser.ending != nil ? 0 : nil), browser.offers.indices.contains(picked) else { return nil }
        let offer = browser.offers[picked]
        switch offer.kind {
        case .search, .suggested, .searched, .command: return nil
        default: return Favicons.shared.cached(for: offer.url)
        }
    }

    /// Opened and not typed in yet: the address selected, the ring round it.
    private var untouched: Bool { browser.offers.isEmpty && browser.siteOffer == nil && browser.switcherNote == nil }

    @State private var frame: CGRect = .zero
    @State private var clicks: Any?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if !untouched {
                    if let lead {
                        Mark(icon: lead, letter: "", size: 16)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 16)
                    }
                }
                AddressField(browser: browser, size: untouched ? 13 : 15)
            }
            .padding(.horizontal, untouched ? 12 : 16)
            .frame(height: untouched ? max(height, 32) : 48)
            Omnibox(browser: browser, over: false, listOnly: width)
        }
        .frame(width: untouched ? line : width, alignment: .top)
        .elevated(.float, in: RoundedRectangle(cornerRadius: untouched ? 10 : 16, style: .continuous))
        .overlay {
            if untouched {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color(nsColor: .controlAccentColor), lineWidth: 2)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .transition(.scale(scale: 0.98, anchor: .topLeading).combined(with: .opacity))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onAppear { watch(true) }
        .onDisappear { watch(false) }
    }

    /// While it is open, a click anywhere but the card puts it away, as
    /// Escape does; the click goes on to whatever it was for.
    private func watch(_ on: Bool) {
        if let clicks { NSEvent.removeMonitor(clicks) }
        clicks = nil
        guard on else { return }
        clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            MainActor.assumeIsolated {
                guard browser.editingInline, let view = event.window?.contentView else { return }
                let at = event.locationInWindow
                let point = CGPoint(x: at.x, y: view.bounds.height - at.y)
                guard !frame.contains(point) else { return }
                browser.dismiss()
            }
            return event
        }
    }

    /// Where the line is in the column, for the column to draw the card over
    /// it past its own edge (see SideBar).
    struct Place: PreferenceKey {
        static let defaultValue: Anchor<CGRect>? = nil
        static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
            value = value ?? nextValue()
        }
    }
}

/// The AppKit view under a SwiftUI one, for a window to hang beside it.
private struct ViewAnchor: NSViewRepresentable {
    final class Box { weak var view: NSView? }
    let box: Box

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { box.view = view }
}
