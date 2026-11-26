import SwiftUI
import AppKit

/// What is typed in a window's field and what answers it (`Browser.typing`):
/// the field and its list watch it, and nothing else has to.
@MainActor
final class FieldState: ObservableObject {
    @Published var typed = ""
    @Published var offers: [Suggestion] = []
    @Published var ending: String?
    @Published var picked: Int?
    /// The row was picked by what was typed (Arc-style tab popup), not by
    /// the arrow keys: Return takes it, and the field keeps what was typed.
    @Published var pickedByTyping = false
    @Published var siteOffer: SearchSite?
}

/// One field, in the middle, and the few places it thinks you mean. It takes
/// addresses and only addresses: type something that isn't a place and it
/// shivers and says so, rather than quietly handing your keystrokes to a
/// search engine.
///
/// The field and its list are one card, as a command bar is: large type, a
/// rule under it, and the places under that, the last few you went before
/// anything is typed (Browser.recentPlaces). Its top edge stays where it is
/// and the card grows down, so a list that arrives never moves the field out
/// from under what is being typed.
struct Omnibox: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var typing: FieldState
    /// Raised over a page by ⌘L, rather than standing on an empty tab.
    let over: Bool

    /// The field's own height: the 28 of text and 16 of air above and below
    /// it that `field` lays out.
    static let fieldHeight: CGFloat = 28 + 16 * 2
    /// As wide as it gets: wider than the address bar's card, which opens
    /// from a line in the column.
    static let width: CGFloat = 640

    /// How wide it is on a page this size.
    static func width(in page: CGSize) -> CGFloat { min(width, max(0, page.width - 28)) }
    /// How far down a page this size its top edge is: in the upper part, as
    /// Spotlight's, with room under it for the list.
    static func top(in page: CGSize) -> CGFloat { max(20, page.height * 0.24) }
    /// Where the field ends, for what hangs under it on an empty tab
    /// (HomeGrid, a pair's open tabs).
    static func under(in page: CGSize) -> CGFloat { top(in: page) + fieldHeight }

    @State private var shake: CGFloat = 0
    @State private var refused = false

    /// Sized to a pane of a split rather than to the window.
    var fitted = false
    /// The page whose pane this field stands on, with Split View on.
    var tab: Tab.ID?
    /// Only the list, as wide as this, for the address line's field
    /// (AddressLine.swift), which stands where the line is.
    var listOnly: CGFloat?

    /// Drawn by the window, centred on all of it, for Settings › The field
    /// in the middle of the window (idea 753).
    var high = false

    init(browser: Browser, over: Bool, fitted: Bool = false, tab: Tab.ID? = nil, listOnly: CGFloat? = nil, high: Bool = false) {
        self.high = high
        self.browser = browser
        self.typing = browser.typing
        self.over = over
        self.fitted = fitted
        self.tab = tab
        self.listOnly = listOnly
    }

    var body: some View {
        Group {
            if let width = listOnly {
                if browser.fieldShowing, !browser.offers.isEmpty || browser.siteOffer != nil || browser.switcherNote != nil {
                    rows()
                        .padding(6)
                        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, 16) }
                        .frame(width: width)
                }
            } else {
                GeometryReader { geometry in
                    content(width: Omnibox.width(in: geometry.size), top: Omnibox.top(in: geometry.size))
                }
            }
        }
        .allowsHitTesting(browser.fieldShowing)
    }

    private var listed: Bool { !browser.offers.isEmpty || browser.siteOffer != nil || browser.switcherNote != nil }

    /// `top`: the card that far down from the top.
    private func content(width: CGFloat, top: CGFloat) -> some View {
        ZStack(alignment: .top) {
            // Keep the container mounted: only the field scales, while the
            // page's cover fades without pulling its edges into view. Not
            // while the address line has the field (AddressLine.swift), nor
            // over a pane while the window has it (Settings › The field in
            // the middle of the window): the pane's, made a moment after the
            // window's, took the keys and went, leaving them to nothing, so
            // ⌘T's and ⌘L's field had no caret (idea 1033).
            if browser.fieldShowing, !browser.editingInline, high || !browser.fieldOnWindow {
                if over {
                    // The page is still there, just out of the way.
                    // Or out of sight, for whoever asked (Settings › Hide
                    // the page behind the field).
                    Rectangle()
                        .fill(Palette.ground.opacity(browser.prefs.fieldHidesPage ? 1 : 0.74))
                        .ignoresSafeArea(.all, edges: fitted ? [] : .all)
                        .onTapGesture { browser.dismiss() }
                        .transition(.opacity)
                }

                card
                    .frame(width: width)
                    .padding(.top, top)
                    .transition(.card(from: .top))
                    // The list's arrival and its leaving are animated from here,
                    // briefly: nothing that changes the suggestions does it inside
                    // an animation of its own. Its rows follow what was typed or
                    // pasted at once — sliding into place on a spring between
                    // keystrokes, they trailed behind the field.
                    .animation(Motion.quick, value: listed)
                    .animation(Motion.settle, value: refused)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The field, and under a rule the places it thinks you mean, on one
    /// ground.
    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return VStack(spacing: 0) {
            field
            // Present or gone, not always-on-and-hidden: the rows keep the
            // appear and disappear they had.
            if listed {
                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, 20)
                rows(large: true)
                    .padding(8)
                    .transition(.opacity)
            }
        }
            .background {
                ZStack {
                    // A slow, almost invisible breath under the field. It is
                    // the only thing on an empty tab, and a thing that never
                    // moves at all reads as a picture of an app rather than
                    // an app. Not over a theme (Settings › Themes): the wall
                    // moves the eye already, and the ink's haze lay over a
                    // picture as a white or dark smudge (idea 952).
                    UnlessThemed(over: over) { Breath() }

                    Color.clear.elevated(.float, in: shape)
                }
            }
            .overlay {
                if refused {
                    shape
                        .strokeBorder(Palette.dangerRing, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .modifier(Shake(travel: shake))
            .onAppear {
                shake = 0
                refused = false
            }
            .onChange(of: browser.refusals) { _, _ in
                shake = 0
                refused = true
                withAnimation(Motion.shake) { shake = 1 }
            }
            .onChange(of: browser.typed) { _, _ in
                withAnimation(Motion.quick) { refused = false }
            }
    }

    private var field: some View {
        HStack(spacing: 12) {
            if let site = browser.siteChip {
                SiteChip(site: site)
                    .transition(.row(from: .leading))
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            AddressField(browser: browser, tab: tab, size: 19)
        }
        .animation(Motion.quick, value: browser.siteChip)
        .frame(height: 28)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    /// What it thinks you mean: the rows alone. Places you have been come
    /// with their titles; the handful of well-known addresses it starts life
    /// knowing come without the weight of one. Under the address bar
    /// (AddressLine.swift) they are the lower part of the card the bar opens
    /// into, so the bar draws the card; in the middle of the window they are
    /// `large`, as the field over them is.
    private func rows(large: Bool = false) -> some View {
        VStack(spacing: 0) {
            if let site = browser.siteOffer {
                SiteOfferRow(site: site)
                    .contentShape(Rectangle())
                    .onTapGesture { _ = browser.lockSiteOffer() }
            }
            ForEach(Array(browser.offers.enumerated()), id: \.element.id) { index, offer in
                // A line between the places and the words to search for.
                if index > 0, offer.kind.isWords != browser.offers[index - 1].kind.isWords {
                    Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, large ? 12 : 10).padding(.vertical, 6)
                }
                Row(offer: offer, picked: browser.picked == index, typed: browser.typed, large: large)
                    .contentShape(Rectangle())
                    .onTapGesture { browser.take(offer) }
            }
            if let note = browser.switcherNote {
                Text(note)
                    .font(.system(size: large ? 14 : 13))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, large ? 14 : 12)
                    .padding(.vertical, large ? 11 : 9)
            }
        }
        // The arrow over the rows: from the field's caret the pointer kept
        // its text cursor down the list, nothing under it saying otherwise.
        .background(CursorGround())
    }

    /// One row of a list of places, here and under the field in the tab.
    struct Row: View {
        let offer: Suggestion
        /// Where the arrow keys have walked to. The pointer gets its own,
        /// quieter mark, and changes nothing but the look of the row.
        let picked: Bool
        /// What is in the field, for the words an engine suggested.
        var typed = ""
        /// In the middle of the window, under its larger field.
        var large = false

        @State private var hovering = false

        var body: some View {
            lineBody
        }

        private var isSearch: Bool { offer.kind == .search || offer.kind == .suggested || offer.kind == .searched }

        /// The words the row leads with: a page's title, or the words to search.
        private var headline: String {
            if isSearch || offer.kind.isCommand || offer.title.isEmpty { return isSearch ? offer.key : Address.withoutWWW(offer.key) }
            return offer.title
        }

        /// Under them: the site, or where the words are sent.
        private var subline: String? {
            if isSearch { return offer.kind == .search && !offer.title.isEmpty ? offer.title : nil }
            if offer.kind.isCommand || offer.title.isEmpty { return nil }
            return Address.withoutWWW(offer.kind == .open ? Address.editable(offer.url) : offer.key)
        }

        /// What stands before the words: the site's icon, or what kind of row.
        @ViewBuilder private var icon: some View {
            switch offer.kind {
            case .search, .suggested:
                if let icon = Favicons.shared.cached(for: offer.url) {
                    Mark(icon: icon, letter: "", size: mark)
                } else {
                    symbol("magnifyingglass")
                }
            case .command:
                symbol("command")
            case .searched:
                symbol("clock.arrow.circlepath")
            default:
                Mark(icon: Favicons.shared.cached(for: offer.url), letter: letter, size: mark)
            }
        }

        private var mark: CGFloat { large ? 18 : 16 }

        /// Kept, on another device, or pinned.
        @ViewBuilder private var marks: some View {
            if case .command(let command) = offer.kind, let key = command.key {
                Text(key)
                    .font(.system(size: large ? 13 : 12))
                    .foregroundStyle(Palette.muted)
            }
            if offer.kind == .elsewhere {
                symbol("laptopcomputer.and.iphone")
            } else if offer.pinned {
                symbol("pin")
            }
        }

        private var lineBody: some View {
            HStack(spacing: large ? 12 : 10) {
                // Every row has the same column before its words, so the
                // words line up whatever stands in it.
                icon.frame(width: large ? 20 : 16, height: large ? 20 : 16)
                words
                    .font(.system(size: large ? 15 : 13))
                    .lineLimit(1)
                    .layoutPriority(1)
                if let subline {
                    Text(subline)
                        .font(.system(size: large ? 13 : 11))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                marks
                if let says {
                    Text(says)
                        .font(.system(size: large ? 13 : 12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, large ? 12 : 10)
            .frame(height: large ? 44 : 36)
            .background {
                if picked {
                    RoundedRectangle(cornerRadius: large ? 12 : 10, style: .continuous)
                        .fill(Palette.wash)
                } else if hovering {
                    RoundedRectangle(cornerRadius: large ? 12 : 10, style: .continuous)
                        .fill(Palette.hover)
                }
            }
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
            .accessibilityElement(children: .combine)
        }

        /// The headline, and for words an engine suggested, what it adds to
        /// what was typed in the quieter ink.
        private var words: Text {
            let typed = typed.trimmingCharacters(in: .whitespaces)
            if offer.kind == .suggested, !typed.isEmpty, headline.lowercased().hasPrefix(typed.lowercased()) {
                return Text(headline.prefix(typed.count)).foregroundStyle(Palette.ink)
                    + Text(headline.dropFirst(typed.count)).foregroundStyle(Palette.muted)
            }
            return Text(headline).foregroundStyle(Palette.ink)
        }

        /// What Return does with it, where that isn't simply going there.
        private var says: String? {
            switch offer.kind {
            case .open: return "Switch to Tab"
            case .bookmark: return "Bookmark"
            case .search: return "Search the Web"
            case .searched: return "Searched Before"
            default: return nil
            }
        }

        private func symbol(_ name: String) -> some View {
            Image(systemName: name)
                .font(.system(size: large ? 12 : 10, weight: .medium))
                .foregroundStyle(Palette.muted)
        }

        /// The site's first letter, as History's lines wear it: an open
        /// tab's row leads with its title, so the address is asked instead.
        private var letter: String {
            let host = offer.url.host().map(Address.withoutWWW) ?? ""
            return host.first.map { String($0).uppercased() } ?? "•"
        }
    }
}

/// A site's icon when this Mac has it, or a glass.
private struct SiteIcon: View {
    let site: SearchSite
    var body: some View {
        let host = site.host.split(separator: "/").first.map(String.init) ?? site.host
        // By where its search goes first, as the rows below it are, so the
        // chip and its rows wear one mark: Wikipedia's icon is kept under
        // en.wikipedia.org, not the wikipedia.org the site is named by.
        if let icon = Favicons.shared.cached(for: site.url(for: "x"))
            ?? Favicons.shared.cached(host) ?? Favicons.shared.cached("www." + host) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 14, height: 14)
        }
    }
}

/// The site Tab put in the field: its icon and name, in the field's grey,
/// before what is typed.
private struct SiteChip: View {
    let site: SearchSite
    var body: some View {
        HStack(spacing: 6) {
            SiteIcon(site: site)
            Text(site.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Searching \(site.name)")
    }
}

/// "Search Reddit", first in the list, with the key that takes it.
private struct SiteOfferRow: View {
    let site: SearchSite
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 10) {
            SiteIcon(site: site)
            Text("Search \(site.name)")
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("Tab")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background {
            if hovering { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.hover) }
        }
        .hovers($hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Search \(site.name), press Tab")
    }
}

/// Its content only where no theme is behind the field: over a page (⌘L) or
/// on a plain blank tab. A view of its own, so only it watches the settings.
private struct UnlessThemed<Content: View>: View {
    let over: Bool
    @ViewBuilder let content: () -> Content
    @ObservedObject private var prefs = Shared.prefs

    var body: some View {
        if over || !themed { content() }
    }

    /// A chosen picture that can't be read shows as Off (HomeBackground).
    private var themed: Bool {
        switch prefs.homeTheme {
        case .off: return false
        case .custom: return HomeBackground.load(prefs.homeThemeImage) != nil
        default: return true
        }
    }
}

/// The breath under the field: a soft shape of ink, blurred, moved by Core
/// Animation. Animated by SwiftUI, it was drawn again on the main thread
/// every frame for as long as an empty tab was showing — 18% of a core with
/// the window doing nothing (24 Sep 2026). As a layer's shadow, breathed by
/// Core Animation, it is played in the render server and costs the app
/// nothing; and it is a layer, not a second SwiftUI view to build before
/// the first frame.
private struct Breath: NSViewRepresentable {
    /// As dark as the shape it replaces, 5% ink blurred by 26: a shadow of
    /// the same radius comes out at 0.7 of the darkness at equal strength,
    /// measured on pictures of both (24 Sep 2026), so 7%.
    static let strength: Swift.Float = 0.07

    func makeNSView(context: Context) -> NSView { Lung() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Lung: NSView {
        private let glow = CALayer()
        private var breathed: CGSize = .zero

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            glow.shadowOpacity = Breath.strength
            glow.shadowOffset = .zero
            glow.shadowRadius = 26
            layer?.addSublayer(glow)
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(breathe),
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// The ink is the look's: light on a dark window, dark on a light one.
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            effectiveAppearance.performAsCurrentDrawingAppearance { glow.shadowColor = Palette.NS.ink.cgColor }
        }

        override func layout() {
            super.layout()
            guard bounds.size != breathed, bounds.width > 0 else { return }
            breathed = bounds.size
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            glow.bounds = bounds
            glow.position = CGPoint(x: bounds.midX, y: bounds.midY)
            glow.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 26, cornerHeight: 26, transform: nil)
            effectiveAppearance.performAsCurrentDrawingAppearance { glow.shadowColor = Palette.NS.ink.cgColor }
            CATransaction.commit()
            breathe()
        }

        /// From 0.97 to 1.03, from 0.65 to full, 2.6 s each way, for as
        /// long as the field is there. It never stops on its own, so with
        /// Reduce Motion on it doesn't start: the glow holds still, at its
        /// full strength. Asked again when that setting changes, so turning
        /// it on stills a breath already going.
        @objc private func breathe() {
            glow.removeAnimation(forKey: "breath")
            guard !Motion.reduced else { return }
            let size = CABasicAnimation(keyPath: "transform.scale")
            size.fromValue = 0.97
            size.toValue = 1.03
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.65
            fade.toValue = 1.0
            let both = CAAnimationGroup()
            both.animations = [size, fade]
            both.duration = 2.6
            both.autoreverses = true
            both.repeatCount = .infinity
            both.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glow.add(both, forKey: "breath")
        }
    }
}

/// The field itself, in AppKit.
///
/// SwiftUI's TextField can hold a string and nothing else, and the whole point
/// here is the part you didn't type: the rest of the address, already there and
/// selected, so carrying on typing replaces it and Return accepts it. That
/// needs a real text field and its delegate.
struct AddressField: NSViewRepresentable {
    @ObservedObject var browser: Browser
    @ObservedObject private var typing: FieldState
    /// The pane's page, for a field standing on one (see Coordinator.focus).
    var tab: Tab.ID?
    /// Its type, smaller in the address line (AddressLine.swift).
    var size: CGFloat = 15.5

    init(browser: Browser, tab: Tab.ID? = nil, size: CGFloat = 15.5) {
        self.browser = browser
        self.typing = browser.typing
        self.tab = tab
        self.size = size
    }

    func makeCoordinator() -> Coordinator { Coordinator(browser: browser) }

    /// The field each window made last: the one on show. SwiftUI can make a
    /// new one while the one before is still fading out, in the window and
    /// still told of every request for the keys (from the second ⌘T on a
    /// page, since #718). That one answered after the new one, took the keys
    /// back, and left the window with them: nothing had them.
    private static let shown = NSMapTable<Browser, Field>.weakToWeakObjects()

    func makeNSView(context: Context) -> Field {
        let field = Field()
        Self.shown.setObject(field, forKey: browser)
        field.delegate = context.coordinator
        field.wanted = { [weak coordinator = context.coordinator, weak field] in
            guard let coordinator, let field else { return false }
            return coordinator.wantsKeys(field)
        }
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: size)
        field.textColor = Palette.NS.ink
        field.lineBreakMode = .byClipping
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        // Scrolls with the caret, so a long address can be read and edited
        // all the way along rather than cut off at the field's edge.
        field.cell?.isScrollable = true
        // SwiftUI picks its own colour for a placeholder, and on a pale ground
        // that colour was near-white.
        let words = Self.placeholderWords(for: browser)
        field.placeholderAttributedString = Self.placeholder(words, size: size)
        field.setAccessibilityLabel(Self.accessibilityName(for: browser))
        context.coordinator.placeheld = words
        return field
    }

    /// What the empty field asks for: with a site put in it with Tab, the
    /// words to search that site for; otherwise an address, and where it
    /// will open, since the field looks the same whichever key raised it.
    /// In the address bar there is no doubt where: it is the tab's own.
    private static func placeholderWords(for browser: Browser) -> String {
        if let site = browser.siteChip { return "Search \(site.name)" }
        if browser.editingInline { return "Search or enter address" }
        switch browser.fieldMode {
        case .blank: return "Search or enter address"
        case .newTab: return "New tab: search or enter address"
        case .thisTab: return "This tab: search or enter address"
        case .switcher: return "Switch to an open tab"
        }
    }

    /// The field's name for VoiceOver, which reads it beside what is typed,
    /// after the placeholder has gone.
    private static func accessibilityName(for browser: Browser) -> String {
        switch browser.fieldMode {
        case .blank: return "Address"
        case .newTab: return "Address, new tab"
        case .thisTab: return "Address, this tab"
        case .switcher: return "Switch to an open tab"
        }
    }

    private static func placeholder(_ words: String, size: CGFloat) -> NSAttributedString {
        NSAttributedString(
            string: words,
            attributes: [
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: Palette.NS.muted,
            ]
        )
    }

    func updateNSView(_ field: Field, context: Context) {
        let coordinator = context.coordinator
        coordinator.browser = browser
        coordinator.tab = tab
        // The address bar's card, larger once something is typed.
        if field.font?.pointSize != size {
            field.font = .systemFont(ofSize: size)
            if let editor = field.currentEditor() as? NSTextView { editor.font = field.font }
        }

        // Only when something other than typing changed it — ⌘L arriving with
        // an address, a walk through the list, a submit clearing it.
        //
        // Comparing against the field's own text instead would undo every
        // backspace: deleting leaves the field shorter than what the browser
        // still considers complete, and the next update would helpfully type
        // it back in. That is a field you cannot shorten, and it reads exactly
        // like one that has stopped responding.
        let want = browser.completed
        if want != coordinator.synced {
            coordinator.synced = want
            field.stringValue = want
            coordinator.select(from: browser.typed.count, in: field)
        }

        let words = Self.placeholderWords(for: browser)
        if coordinator.placeheld != words {
            coordinator.placeheld = words
            field.placeholderAttributedString = Self.placeholder(words, size: size)
            field.setAccessibilityLabel(Self.accessibilityName(for: browser))
            DispatchQueue.main.async { coordinator.showPlaceholder(in: field) }
        }

        if coordinator.answered != browser.focusRequest {
            coordinator.answered = browser.focusRequest
            DispatchQueue.main.async { coordinator.focus(field) }
        }
    }

    /// Whether the field on show had the keys a moment ago and is still up,
    /// with what was typed: if so they go back to it, in the next turn of
    /// the run loop, with the caret where it was. For a page that asked for
    /// them by itself (PageView.becomeFirstResponder, idea 495), in the
    /// field's own window.
    @MainActor static func keepsKeys(for browser: Browser, in pageWindow: NSWindow) -> Bool {
        // Only the page beside the field: one gone to WebKit's own full
        // screen window takes the keys there.
        guard browser.fieldShowing, let field = shown.object(forKey: browser), let window = field.window, window === pageWindow,
              let leftAt = field.leftAt, field.currentEditor() == nil else { return false }
        DispatchQueue.main.async { [weak field] in
            guard let field, browser.editing, field.window === window, field.currentEditor() == nil else { return }
            let attributes = (window.fieldEditor(false, for: field) as? NSTextView)?.selectedTextAttributes
            window.makeFirstResponder(field)
            guard let editor = field.currentEditor() as? NSTextView else { return }
            if let attributes { editor.selectedTextAttributes = attributes }
            let length = (editor.string as NSString).length
            let start = min(leftAt.location, length)
            editor.selectedRange = NSRange(location: start, length: min(leftAt.length, length - start))
        }
        return true
    }

    /// The field, told when it lands in a window.
    ///
    /// SwiftUI makes the view and updates it before it is in one, and with
    /// Split View on it comes only once the stage has said where the page is,
    /// a turn of the run loop later. Asked for the keys before then, the
    /// field had no window to ask: the request went nowhere and nothing asked
    /// again, so ⌘T left a field with no caret and typing that went nowhere
    /// until it was clicked. Now the request waits for the window.
    final class Field: RoomyField {
        var arrived: (() -> Void)?
        /// Where the caret was as the field last let go of the keys.
        var leftAt: NSRange?
        /// How the selection looked then, for the keys given back.
        private var leftLook: [NSAttributedString.Key: Any]?
        /// Whether this is still the field that should have the keys: the
        /// one on show, over the page in front. Set by its coordinator.
        var wanted: (() -> Bool)?
        /// The field is being moved, in its own window, with the keys.
        private var movingWithKeys = false

        override func textDidEndEditing(_ note: Notification) {
            if let editor = note.object as? NSTextView {
                leftAt = editor.selectedRange()
                leftLook = editor.selectedTextAttributes
            }
            super.textDidEndEditing(note)
            DispatchQueue.main.async { [weak self] in self?.takeKeysBack() }
        }

        // SwiftUI draws the field inside a view of its own while the field's
        // open animation runs, and when it ends it moves the field out of it,
        // within the same window (DisplayList.ViewUpdater, addSubview). On
        // macOS 27 that move ends the field's editing and leaves the keys
        // with the window, about 0.35 s after ⌘T or ⌘L, with the open
        // animation: what was typed from then on went nowhere until a click
        // in the field (idea 1099). Moved with the keys, or let go of them
        // with nobody taking them, the field takes them back, the caret
        // where it was. A click, Tab or a page that takes the keys leaves
        // them with what took them, and a field put away is not wanted.
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            movingWithKeys = newWindow != nil && newWindow === window && currentEditor() != nil
            // A test run can have the move drop the keys, as macOS 27 does,
            // on a Mac whose macOS keeps them (Tests/field_keeps_keys.py).
            if movingWithKeys, Self.dropsKeysOnMove { window?.makeFirstResponder(nil) }
            super.viewWillMove(toWindow: newWindow)
        }

        static var dropsKeysOnMove: Bool {
            Store.testing && Store.settings.bool(forKey: "test.fieldDropsKeysOnMove")
        }

        /// The keys back, if the field lost them to nobody: the window holds
        /// them itself, and the field is still the one wanted.
        func takeKeysBack() {
            guard let window, currentEditor() == nil, window.firstResponder === window,
                  !isHiddenOrHasHiddenAncestor, let leftAt, wanted?() == true else { return }
            window.makeFirstResponder(self)
            guard let editor = currentEditor() as? NSTextView else { return }
            if let leftLook { editor.selectedTextAttributes = leftLook }
            let length = (editor.string as NSString).length
            let start = min(leftAt.location, length)
            editor.selectedRange = NSRange(location: start, length: min(leftAt.length, length - start))
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if movingWithKeys {
                movingWithKeys = false
                takeKeysBack()
            }
            guard window != nil, let arrived else { return }
            self.arrived = nil
            arrived()
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var browser: Browser
        var tab: Tab.ID?
        var answered = -1
        /// The placeholder last given, so it is set again only when a site
        /// goes in or comes out, or another key raises the field.
        var placeheld: String?
        /// The last value pushed in from the browser side, so an update can
        /// tell a change worth applying from one it made itself.
        var synced = ""

        /// A backspace has to be allowed to actually take a letter off. Without
        /// this the field puts the same letter straight back as a completion
        /// and the address can never be shortened.
        private var deleting = false

        init(browser: Browser) {
            self.browser = browser
        }

        /// Whether `field` should have the keys: the one on show, over the
        /// page in front, with no tab being renamed.
        @MainActor func wantsKeys(_ field: Field) -> Bool {
            (tab == nil || tab == browser.activeID) && browser.fieldShowing && browser.editingTab == nil
                && AddressField.shown.object(forKey: browser) === field
        }

        /// The keys to the field, now if it is in a window, or the moment it is.
        @MainActor func focus(_ field: Field) {
            // Only the field of the page in front. With Split View on, ⌘T's
            // request reaches the field over the page just left too, in the
            // moment before it goes: answered there, the keys went with it
            // and were left to the window, which beeps at every key.
            guard tab == nil || tab == browser.activeID else { return }
            // One on its way out has no keys to take.
            guard AddressField.shown.object(forKey: browser) === field else { return }
            guard let window = field.window else {
                field.arrived = { [weak self, weak field] in
                    DispatchQueue.main.async {
                        guard let self, let field, self.browser.fieldShowing else { return }
                        self.focus(field)
                    }
                }
                return
            }
            field.arrived = nil
            window.makeFirstResponder(field)
            guard let editor = field.currentEditor() as? NSTextView else { return }
            defer { browser.fieldFocused(in: window) }
            // The system paints selected text as a block of accent colour,
            // which over this pale field is the loudest thing in the
            // window. A tenth of the ink says "selected" quietly enough.
            editor.selectedTextAttributes = [
                .backgroundColor: NSColor(Palette.ink.opacity(0.12)),
                .foregroundColor: Palette.NS.ink,
            ]
            // A draft come back to its blank tab is carried on, not typed
            // over: the caret after it. An address ⌘L raises is selected whole.
            if browser.active?.isBlank == true, !browser.typed.isEmpty {
                select(from: browser.typed.count, in: field)
            } else {
                editor.selectAll(nil)
            }
        }

        /// A field being typed in shows the placeholder its editor was given
        /// when the typing began, and AppKit has no way to hand that editor
        /// a new one: the field begins editing again, with the caret and
        /// whatever was selected put back where they were.
        @MainActor func showPlaceholder(in field: Field) {
            guard let window = field.window, let editor = field.currentEditor() as? NSTextView,
                  window.firstResponder === editor else { return }
            let selected = editor.selectedRange()
            window.makeFirstResponder(field)
            guard let again = field.currentEditor() as? NSTextView else { return }
            again.selectedTextAttributes = editor.selectedTextAttributes
            let length = (again.string as NSString).length
            let start = min(selected.location, length)
            again.selectedRange = NSRange(location: start, length: min(selected.length, length - start))
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            let text = field.stringValue

            browser.typed = text
            guard !deleting, let ending = browser.ending else {
                if deleting { browser.stopCompleting() }
                deleting = false
                synced = browser.completed
                return
            }
            deleting = false

            field.stringValue = text + ending
            synced = field.stringValue
            select(from: text.count, in: field)
        }

        /// The part after the caret, shown as selected, so the next keystroke
        /// replaces it and Return takes it.
        func select(from start: Int, in field: NSTextField) {
            guard let editor = field.currentEditor() as? NSTextView else { return }
            editor.selectedTextAttributes = [
                .backgroundColor: NSColor(Palette.ink.opacity(0.12)),
                .foregroundColor: Palette.NS.ink,
            ]
            let length = field.stringValue.count
            guard start <= length else { return }
            editor.selectedRange = NSRange(location: start, length: length - start)
            // The start in view, not the end: selecting a long completion
            // scrolled the field to its last characters, hiding what was
            // typed and the site it goes to (#1055). The ending stays
            // selected, so the next key still replaces it.
            editor.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy command: Selector
        ) -> Bool {
            switch command {
            case #selector(NSResponder.insertNewline(_:)):
                browser.submit()
                return true
            case #selector(NSResponder.moveDown(_:)):
                browser.walk(1)
                return true
            case #selector(NSResponder.moveUp(_:)):
                browser.walk(-1)
                return true
            case #selector(NSResponder.deleteWordBackward(_:)):
                // ⌥⌫ over an offered ending lets go of it and takes the last
                // word typed, as it does with no ending there. Left to the
                // text view it would only take the selected ending.
                deleting = true
                let selected = textView.selectedRange()
                guard browser.ending != nil, selected.length > 0,
                      NSMaxRange(selected) == (textView.string as NSString).length
                else { return false }
                textView.delete(nil)
                deleting = true
                textView.deleteWordBackward(nil)
                return true
            case #selector(NSResponder.deleteBackward(_:)) where textView.string.isEmpty && browser.siteChip != nil:
                // ⌫ on an empty field takes the site out of it.
                browser.siteChip = nil
                return true
            case #selector(NSResponder.deleteBackward(_:)),
                 #selector(NSResponder.deleteForward(_:)),
                 #selector(NSResponder.deleteWordForward(_:)):
                deleting = true
                return false
            default:
                return false
            }
        }
    }
}

/// A one-line field whose text stops a little short of its trailing edge.
///
/// Scrolled to the end of a long query, the field editor put the caret and
/// the last letter right against the field's edge, a fraction of a point in
/// (0.2 to 1 measured), where anything that clips the field there — the row
/// or the pill around it, a wider caret — hid the caret and part of the last
/// letter (idea 736). The text is now laid out, drawn and edited in a rect
/// `margin` short of that edge, so the editor scrolls the caret that far in.
class RoomyField: NSTextField {
    override class var cellClass: AnyClass? {
        get { RoomyFieldCell.self }
        set {}
    }
}

final class RoomyFieldCell: NSTextFieldCell {
    /// What is kept clear past the caret at the end of the text.
    static let margin: CGFloat = 4

    private static func short(_ rect: NSRect) -> NSRect {
        var inner = rect
        inner.size.width = max(0, inner.width - margin)
        return inner
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        Self.short(super.drawingRect(forBounds: rect))
    }

    // The field editor is laid in the frame it is handed here, not in the
    // drawing rect above.
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                       delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: Self.short(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                         delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: Self.short(rect), in: controlView, editor: textObj, delegate: delegate,
                     start: selStart, length: selLength)
    }
}
