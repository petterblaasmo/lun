import SwiftUI

/// The first time. Four short pages over the window, in the app's own
/// language: what this is, what to bring over, how to hold it, and whether
/// links from other apps should come here — and a fifth, until an email has
/// been given once, offering the iPhone beta and news by email (OptIn.swift).
/// Nothing is asked twice, and every page can be skipped.
///
/// Each page is one thing, down the middle: a heading, a line under it, what
/// there is to choose, and one button that does it. Where that button does
/// something (brings things over, asks macOS for the default), "Not now"
/// under it goes on without. Nothing is written smaller than can be read, or
/// in the grey kept for rules and switches.
///
/// The first page also holds Sync with iCloud and Handoff, on for a new
/// install (SyncDefault.swift): there, before Skip or Get Started, so nobody
/// leaves without having seen them. They take effect when the welcome is
/// left, however it is; nothing goes anywhere while it is up.
struct WelcomePanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    @State private var page = 0
    // Sync with iCloud and Handoff, as they will be once the welcome is
    // left (SyncDefault.starts).
    @State private var syncs = SyncDefault.startsNow().sync
    @State private var handsOff = SyncDefault.startsNow().handoff
    @State private var forward = true

    // Bringing things over. The browsers are looked for when their page is
    // first reached: finding them goes through each one's folders, and as an
    // initial value that ran every time the panel was made, the first
    // window's included, for a page that isn't showing yet.
    @State private var sources: [ImportSource] = []
    @State private var unreadable: [String] = []
    @State private var looked = false
    /// The ones to bring from, by id: any number of them. Nil until one is
    /// pressed, which means the first.
    @State private var chosen: Set<String>?
    /// The ones already brought from, which aren't brought twice.
    @State private var done: Set<String> = []
    @State private var wantsPasswords = true
    @State private var wantsHistory = true
    @State private var wantsBookmarks = true
    @State private var bringing = false
    @State private var brought: String?

    // The default browser.
    @State private var isDefault = Links.isDefault
    @State private var asked = false

    private var picks: [ImportSource] {
        let ids = chosen ?? Set(sources.first.map { [$0.id] } ?? [])
        return sources.filter { ids.contains($0.id) && !done.contains($0.id) }
    }
    private var importsPasswords: Bool { picks.contains(where: \.importsPasswords) }
    /// The first page's words, in after its mark has been written.
    @State private var said = false
    private var bringsSomething: Bool { (importsPasswords && wantsPasswords) || wantsHistory || wantsBookmarks }

    /// Read once: the email page stays to the end once it is there, for
    /// its thanks.
    @State private var offersEmail = OptIn.offered()
    /// For pictures: the page to open at, the browsers picked there, and
    /// the email page's state.
    var startPage = 0
    var startChosen: Set<String>?
    var optInStart: OptInForm.Phase = .idle
    var optInEmail = ""
    @State private var began = false

    /// Set Up Like Arc from the welcome: what it turned on, for its line
    /// and Undo. Nothing changes unless it is pressed.
    @State private var arcSaid: String?
    @ObservedObject private var likeArc = LikeArc.shared

    private var pages: Int { offersEmail ? 5 : 4 }

    /// How wide a page is: a line of the text under a heading is read at a
    /// glance at this width, and two window drawings fit side by side.
    private static let column: CGFloat = 460

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                // A short window scrolls the page rather than pushing the
                // button off its bottom edge.
                ViewThatFits(in: .vertical) {
                    current
                    ScrollView(showsIndicators: false) { current.padding(.vertical, 12) }
                }
                .frame(maxWidth: WelcomePanel.column, maxHeight: .infinity)
                .id(page)
                .transition(.page(forward: forward))
                foot
            }
            // Clear of the window's own buttons, which stay over this.
            .padding(.top, 44)
            .padding(.horizontal, 32)
            .padding(.bottom, 26)
        }
        .animation(Motion.glide, value: page)
        .transition(.opacity)
        .onAppear {
            guard !began else { return }
            began = true
            if let startChosen { chosen = startChosen }
            go(to: min(startPage, pages - 1))
        }
    }

    @ViewBuilder
    private var current: some View {
        switch page {
        case 0: welcome
        case 1: bring
        case 2: hold
        case 3: links
        default: early
        }
    }

    // MARK: - the pages

    private var welcome: some View {
        VStack(spacing: 0) {
            Wordmark(height: 88)
                .accessibilityElement()
                .accessibilityLabel("Lun")
            Group {
                Text("A small, fast, quiet browser for the Mac.")
                    .font(.system(size: 19, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 28)
                devices
                    .padding(.top, 40)
            }
            .opacity(said ? 1 : 0)
            .offset(y: said ? 0 : 8)
        }
        .onAppear {
            // After the mark, which takes about a second to write.
            withAnimation(Motion.slow?.delay(0.85)) { said = true }
        }
    }

    /// Sync with iCloud and Handoff, in sight before anything starts.
    private var devices: some View {
        VStack(spacing: 12) {
            Box {
                Choice("Sync with iCloud", "Open tabs, pins, spaces, bookmarks and a few settings, on your iPhone and other Macs. End-to-end encrypted, in your own iCloud.", on: $syncs)
                Rule(inset: 0)
                Choice("Handoff", "The page in front shows up on your iPhone and iPad.", on: $handsOff)
            }
            Text("Nothing starts until you leave this welcome. Both are in Settings › General.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bring: some View {
        VStack(spacing: 24) {
            heading("Bring your things over.",
                    sources.isEmpty ? "Passwords, bookmarks and history from the browser you're coming from."
                                    : sources.count > 1 ? "Pick the browsers you're coming from. Nothing in them changes."
                                                        : "From the browser you're coming from. Nothing in it changes.")

            if sources.isEmpty {
                if unreadable.isEmpty {
                    Box {
                        Text("No other browser found on this Mac, so there is nothing to bring.")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                browsers

                Box {
                    if importsPasswords || picks.isEmpty {
                        Choice("Passwords", passwordsLine, on: $wantsPasswords)
                    } else {
                        Said("Passwords", passwordsLine)
                    }
                    Rule(inset: 0)
                    Choice("Bookmarks", "Folders and all, behind the bookmark button.", on: $wantsBookmarks)
                    Rule(inset: 0)
                    Choice("History", "The last few thousand places, for finishing addresses.", on: $wantsHistory)
                }
                .disabled(bringing || picks.isEmpty)
                .opacity(picks.isEmpty ? 0.5 : 1)

                if let brought {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text(brought)
                            .font(.system(size: 13.5))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Palette.ink)
                    .transition(.opacity)
                }
            }

            if !unreadable.isEmpty {
                Text(unreadable.joined(separator: "\n"))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Safari, a browser on another Mac, one Lun can't read: what it
            // exported, bookmarks, passwords or Safari's own ZIP.
            Quiet(sources.isEmpty ? "Bring in a file another browser exported…" : "Or bring in a file another browser exported…") {
                browser.importFile()
            }
        }
        .animation(Motion.settle, value: brought)
    }

    /// What the passwords row says of the browsers picked: where they go,
    /// what macOS will ask, and which of them can't give theirs.
    private var passwordsLine: String {
        let without = picks.filter { !$0.importsPasswords }
        guard importsPasswords else {
            if without.count == 1, let one = without.first {
                return one.passwordsInPasswordsApp
                    ? "\(one.name) keeps them in the Passwords app: export them there, then bring in the file."
                    : "Not from \(one.name) yet."
            }
            return without.isEmpty ? "Into your Mac's keychain." : "Not from these yet."
        }
        let with = picks.filter(\.importsPasswords)
        let key = with.count == 1 ? "\(with[0].name)'s key" : "each browser's key"
        let rest = without.isEmpty ? "" : " Not from \(ImportSource.listed(without.map(\.name))) yet."
        return "Into your Mac's keychain. macOS asks once for \(key).\(rest)"
    }

    /// The browsers found on this Mac, each under its own icon: any number
    /// of them can be picked, and are brought from one after another.
    /// Spaces, open tabs and which profile are in the full page
    /// (File › Bring Things Over…).
    private var browsers: some View {
        let picked = Set(picks.map(\.id))
        let row = HStack(spacing: 10) {
            ForEach(sources) { one in
                Source(name: one.name, icon: one.appIcon, chosen: picked.contains(one.id), done: done.contains(one.id)) {
                    guard !bringing else { return }
                    var now = chosen ?? Set(sources.first.map { [$0.id] } ?? [])
                    if now.contains(one.id) { now.remove(one.id) } else { now.insert(one.id) }
                    chosen = now
                }
            }
        }
        // The chosen one's shadow, which a scroll view would cut.
        .padding(.vertical, 4)
        return ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal, showsIndicators: false) { row.padding(.horizontal, 2) }
        }
    }

    private var hold: some View {
        VStack(spacing: 24) {
            heading("Tabs on the side, or on top.", "Change your mind any time with ⇧⌘S.")
            HStack(spacing: 12) {
                Way(title: "Sidebar", sidebar: true, glyph: prefs.glyph, chosen: prefs.sidebar) {
                    withAnimation(Motion.glide) { prefs.sidebar = true }
                }
                Way(title: "Tab strip", sidebar: false, glyph: prefs.glyph, chosen: !prefs.sidebar) {
                    withAnimation(Motion.glide) { prefs.sidebar = false }
                }
            }
            Box {
                HStack(spacing: 12) {
                    Said("Tabs wear", "A site's own icon, or its first letter.")
                    Segmented(options: Glyph.allCases.map { ($0, $0.title) }, selection: $prefs.glyph)
                        .fixedSize()
                }
                Rule(inset: 0)
                arc
            }
        }
    }

    /// Coming from Arc? One button for Arc's way (LikeArc), optional like
    /// everything here: Continue goes on without it.
    private var arc: some View {
        HStack(spacing: 12) {
            Said("Coming from Arc?", arcSaid ?? "Tabs on the left, spaces, pinned rows, and Arc's habits: tabs that close after 12 hours, peek, the floating video.")
            if arcSaid != nil, likeArc.undoable(prefs) {
                Pill("Undo", large: true) {
                    withAnimation(Motion.glide) { likeArc.undo(prefs) }
                    arcSaid = nil
                }
            } else if prefs.looksLikeArc {
                if arcSaid == nil {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                        Text("Set up like Arc").font(.system(size: 12.5))
                    }
                    .foregroundStyle(Palette.muted)
                    .fixedSize()
                }
            } else {
                Pill("Set Up Like Arc", large: true) {
                    arcSaid = LikeArc.said(withAnimation(Motion.glide) { likeArc.setUp(prefs) })
                }
            }
        }
        .animation(Motion.settle, value: arcSaid)
    }

    private var links: some View {
        VStack(spacing: 24) {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 84, height: 84)
                    .accessibilityHidden(true)
            }
            heading(isDefault ? "Lun is your default browser." : "Make Lun your default browser.",
                    "Links you click in Mail, Slack and other apps open here.")
            if asked, !isDefault {
                Text("macOS asks in its own dialog.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Worth knowing")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.leading, 4)
                Box(spacing: 11) {
                    Key("⌘T", "A new tab. Type a place, or words to search.")
                    Key("⌘K", "Every open tab, by name.")
                    Key("⌥⌘N", "Two pages side by side.")
                    Key("⌘,", "Settings. ⌘F there finds any of them.")
                }
            }
            .padding(.top, 6)
        }
        .animation(Motion.settle, value: isDefault)
        .animation(Motion.settle, value: asked)
    }

    /// Light, and skippable like every page: Start Browsing goes on
    /// without it (OptIn.swift).
    private var early: some View {
        OptInWelcomePage(start: optInStart, startEmail: optInEmail) { url in
            finish()
            _ = browser.open(url, foreground: true)
        }
    }

    // MARK: - the bottom edge

    /// What the page's one button says and does.
    private var main: (title: String, act: () -> Void) {
        switch page {
        case 0:
            return ("Get Started", next)
        case 1 where bringing:
            return ("Bringing…", {})
        case 1 where !picks.isEmpty:
            let from = picks.count > 2 ? "\(picks.count) Browsers" : ImportSource.listed(picks.map(\.name))
            return ("Bring Over from \(from)", bringAll)
        case 3 where !isDefault:
            return ("Make Lun the Default", {
                asked = true
                Links.becomeDefault { _ in isDefault = Links.isDefault }
            })
        default:
            return (page < pages - 1 ? "Continue" : "Start Browsing", next)
        }
    }

    /// The way on without the page's button, where that button does
    /// something; on the first page, the way out of all of it.
    private var second: (title: String, act: () -> Void)? {
        switch page {
        case 0: return ("Skip", finish)
        case 1 where !picks.isEmpty && !bringing: return ("Not now", next)
        case 3 where !isDefault: return ("Not now", next)
        default: return nil
        }
    }

    private var foot: some View {
        VStack(spacing: 0) {
            Big(main.title, busy: bringing, act: main.act)
                .disabled(bringing || (page == 1 && !picks.isEmpty && !bringsSomething))
                .keyboardShortcut(.defaultAction)
            // Its room is kept where there is none, so the button stays put
            // from page to page.
            Quiet(second?.title ?? " ") { second?.act() }
                .opacity(second == nil ? 0 : 1)
                .disabled(second == nil)
                .accessibilityHidden(second == nil)
                .padding(.top, 12)
            ZStack {
                HStack(spacing: 7) {
                    ForEach(0..<pages, id: \.self) { i in
                        Circle()
                            .fill(i == page ? Palette.ink : Palette.faint)
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Page \(page + 1) of \(pages)")
                if page > 0 {
                    HStack {
                        Quiet("Back", glyph: "chevron.left") { forward = false; go(to: page - 1) }
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
        }
        .padding(.top, 20)
    }

    // MARK: - doing

    private func next() {
        if page < pages - 1 { forward = true; go(to: page + 1) } else { finish() }
    }

    private func go(to target: Int) {
        if target == 1, !looked {
            looked = true
            sources = ImportSource.installed()
            unreadable = Chromium.unreadable().map(\.message)
        }
        page = target
    }

    /// From each browser picked, one after another: macOS asks for one
    /// keychain key at a time. What came is added up; what went wrong is
    /// said under it, by browser.
    private func bringAll() {
        let queue = picks
        guard !queue.isEmpty else { return }
        bringing = true
        var passwords = 0
        var undecrypted = 0
        var bookmarks = 0
        var places = 0
        var asked = false
        var troubles: [String] = []

        func bring(_ index: Int) {
            guard index < queue.count else {
                var lines: [String] = []
                if asked { lines.append("\(passwords) passwords" + (undecrypted > 0 ? " (\(undecrypted) couldn't be decrypted)" : "")) }
                if wantsBookmarks { lines.append("\(bookmarks) bookmarks") }
                if wantsHistory { lines.append("\(places) places") }
                bringing = false
                brought = ([lines.joined(separator: " · ")] + troubles).joined(separator: "\n")
                browser.relist()
                return
            }
            let source = queue[index]
            // The profile used most recently, without asking: the page in
            // File › Bring Things Over… is where another is chosen.
            let profile = source.usual
            let group = DispatchGroup()
            if wantsPasswords && source.importsPasswords {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let outcome = Result { try source.read(profile: profile) }
                    DispatchQueue.main.async {
                        switch outcome {
                        case .success(let found):
                            let kept = browser.keep(found)
                            ImportRecords.note(source.name, passwords: kept)
                            asked = true
                            passwords += kept
                            undecrypted += found.undecrypted
                        case .failure(Chromium.Trouble.noPassphrase):
                            troubles.append("\(source.name)'s passwords: macOS didn't hand over the key. Allow it and try again.")
                        case .failure(Mozilla.Trouble.primaryPassword):
                            troubles.append("\(source.name) has a primary password: export its passwords and bring in the CSV.")
                        case .failure:
                            troubles.append("\(source.name)'s passwords: nothing readable.")
                        }
                        group.leave()
                    }
                }
            }
            if wantsBookmarks {
                bookmarks += browser.takeBookmarks(from: source, profile: profile).added
            }
            if wantsHistory {
                group.enter()
                browser.takePlaces(from: source, profile: profile) { count in
                    places += count
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                done.insert(source.id)
                bring(index + 1)
            }
        }
        bring(0)
    }

    private func finish() {
        SyncDefault.welcomeLeft(sync: syncs, handoff: handsOff, prefs: prefs, icloud: ICloudSync.shared)
        prefs.welcomed = true
        withAnimation(Motion.settle) { browser.welcoming = false }
    }

    private func heading(_ title: String, _ line: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(line)
                .font(.system(size: 15))
                .foregroundStyle(Palette.muted)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - pieces

    /// The mark alone, at whatever height the page wants — no plate behind
    /// it, the same as everywhere else it's drawn. Here it is written as
    /// the page comes, l then u then n, unless motion is reduced.
    private struct Wordmark: View {
        let height: CGFloat
        @State private var drawn: CGFloat = Motion.reduced ? 1 : 0

        var body: some View {
            LogomarkWritten(drawn: drawn)
                .frame(height: height)
                .onAppear {
                    guard drawn < 1 else { return }
                    withAnimation(Motion.drawn?.delay(0.1)) { drawn = 1 }
                }
        }
    }

    /// The page's one button: wide, and the same place on every page.
    private struct Big: View {
        let title: String
        var busy = false
        let act: () -> Void
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        init(_ title: String, busy: Bool = false, act: @escaping () -> Void) {
            self.title = title
            self.busy = busy
            self.act = act
        }

        var body: some View {
            Button(action: act) {
                HStack(spacing: 9) {
                    if busy { Ring(size: 11) }
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(Palette.ground)
                .padding(.horizontal, 28)
                .frame(minWidth: 240)
                .frame(height: 42)
                .background(Palette.ink.opacity(enabled || busy ? (hovering ? 0.86 : 1) : 0.35), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }

    /// Words to press, with no ground of their own: the way on without, the
    /// way back, a file instead.
    private struct Quiet: View {
        let title: String
        var glyph: String?
        let act: () -> Void
        @State private var hovering = false

        init(_ title: String, glyph: String? = nil, act: @escaping () -> Void) {
            self.title = title
            self.glyph = glyph
            self.act = act
        }

        var body: some View {
            Button(action: act) {
                HStack(spacing: 5) {
                    if let glyph {
                        Image(systemName: glyph).font(.system(size: 10.5, weight: .semibold))
                    }
                    Text(title).font(.system(size: 13.5))
                }
                .foregroundStyle(hovering ? Palette.ink : Palette.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }

    /// A box of rows, as Settings groups its own.
    private struct Box<Content: View>: View {
        var spacing: CGFloat = 13
        @ViewBuilder let content: () -> Content

        var body: some View {
            VStack(alignment: .leading, spacing: spacing) { content() }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// A row's two lines: what it is, and what it means for you.
    private struct Said: View {
        let title: String
        let detail: String
        init(_ title: String, _ detail: String) { self.title = title; self.detail = detail }

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct Choice: View {
        let title: String
        let detail: String
        @Binding var on: Bool

        init(_ title: String, _ detail: String, on: Binding<Bool>) {
            self.title = title
            self.detail = detail
            _on = on
        }

        var body: some View {
            HStack(spacing: 14) {
                Said(title, detail)
                Switch(on: $on)
                    .accessibilityLabel(title)
            }
        }
    }

    /// The ground of something chosen among others, and of the others: the
    /// chosen one lifted off the page as the tab you're on is, ringed and
    /// ticked so it is the one in the dark as well.
    private struct Pick: ViewModifier {
        let chosen: Bool
        let hovering: Bool
        /// Already brought from: ticked still, and no longer to press.
        var done = false
        var radius: CGFloat = 14

        func body(content: Content) -> some View {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            content
                .background {
                    if chosen {
                        Color.clear.elevated(.lift, in: shape)
                    } else {
                        shape.fill(hovering ? Palette.fillHover : Palette.fill)
                    }
                }
                .overlay { if chosen { shape.strokeBorder(Palette.ink, lineWidth: 1.5) } }
                .overlay(alignment: .topTrailing) {
                    if chosen || done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Palette.ground)
                            .frame(width: 17, height: 17)
                            .background(done ? Palette.muted : Palette.ink, in: Circle())
                            .padding(7)
                            .transition(.pop)
                    }
                }
                .contentShape(shape)
        }
    }

    /// One browser to come from, under its own icon.
    private struct Source: View {
        let name: String
        let icon: NSImage?
        let chosen: Bool
        var done = false
        let pick: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: pick) {
                VStack(spacing: 9) {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 44, height: 44)
                    } else {
                        // Its data is here and its app isn't: its letter, as
                        // a tab with no icon wears one.
                        Text(name.prefix(1).uppercased())
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 40, height: 40)
                            .background(Palette.fillHover, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(2)
                    }
                    Text(name)
                        .font(.system(size: 13, weight: chosen ? .medium : .regular))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
                .opacity(done ? 0.55 : 1)
                .frame(width: 104, height: 100)
                .modifier(Pick(chosen: chosen, hovering: hovering && !done, done: done))
            }
            .buttonStyle(.plain)
            .disabled(done)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
            .animation(Motion.settle, value: chosen)
            .animation(Motion.settle, value: done)
            .accessibilityLabel(done ? "\(name), brought over" : name)
            .accessibilityAddTraits(chosen ? .isSelected : [])
        }
    }

    /// One of the two ways, as a small drawing of the window.
    private struct Way: View {
        let title: String
        let sidebar: Bool
        let glyph: Glyph
        let chosen: Bool
        let pick: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: pick) {
                VStack(spacing: 10) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.ground)
                        if sidebar {
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Palette.faint).frame(width: 5, height: 5) } }
                                        .padding(.bottom, 4)
                                    ForEach(0..<4, id: \.self) { i in
                                        HStack(spacing: 3) {
                                            Wear(glyph: glyph, tab: i)
                                            RoundedRectangle(cornerRadius: 3).fill(i == 0 ? Palette.fillHover : Palette.fill).frame(height: 8)
                                        }
                                    }
                                }
                                .padding(8)
                                .frame(width: 66)
                                Rectangle().fill(Palette.hairline).frame(width: 1)
                                Spacer()
                            }
                        } else {
                            HStack(spacing: 3) {
                                HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Palette.faint).frame(width: 5, height: 5) } }
                                    .padding(.trailing, 6)
                                ForEach(0..<4, id: \.self) { i in
                                    HStack(spacing: 3) {
                                        Wear(glyph: glyph, tab: i)
                                        RoundedRectangle(cornerRadius: 3).fill(i == 0 ? Palette.fillHover : Palette.fill).frame(width: 24, height: 8)
                                    }
                                    .padding(.trailing, 3)
                                }
                            }
                            .padding(8)
                        }
                    }
                    .frame(height: 112)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                    Text(title)
                        .font(.system(size: 13.5, weight: chosen ? .medium : .regular))
                        .foregroundStyle(Palette.ink)
                }
                .padding(10)
                .modifier(Pick(chosen: chosen, hovering: hovering))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
            .animation(Motion.settle, value: chosen)
            .accessibilityLabel(title)
            .accessibilityAddTraits(chosen ? .isSelected : [])
        }
    }

    /// What a tab wears in the two small pictures, as Tabs wear has it: a
    /// letter in a faint square, as Mark draws one, or a patch of colour
    /// where a site's own icon would be. Seen before it is chosen: letters
    /// were taken for icons that hadn't loaded (#1271).
    private struct Wear: View {
        let glyph: Glyph
        let tab: Int

        private static let letters = ["G", "M", "Y", "W"]
        private static let tints: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange]

        var body: some View {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(glyph == .icons ? Color(nsColor: Wear.tints[tab]).opacity(0.7) : Palette.ink.opacity(0.06))
                .frame(width: 10, height: 10)
                .overlay {
                    if glyph == .letters {
                        Text(Wear.letters[tab])
                            .font(.system(size: 6.5, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    }
                }
                .animation(Motion.quick, value: glyph)
        }
    }

    private struct Key: View {
        let keys: String
        let what: String
        init(_ keys: String, _ what: String) { self.keys = keys; self.what = what }
        var body: some View {
            HStack(spacing: 12) {
                Text(keys)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .frame(minWidth: 34)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Palette.fillHover, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(what)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension ImportSource {
    /// The other browser's own icon, where its app is on this Mac: one is
    /// known by it sooner than by its name.
    var appIcon: NSImage? {
        let names: [String]
        switch self {
        case .chromium(let source): names = [source.app]
        case .mozilla(let source): names = ["\(source.name).app", "\(source.name) Browser.app"]
        case .webkit(let source): names = ["\(source.name).app"]
        }
        let folders = ["/Applications", NSHomeDirectory() + "/Applications"]
        for folder in folders {
            for name in names {
                let path = folder + "/" + name
                if FileManager.default.fileExists(atPath: path) { return NSWorkspace.shared.icon(forFile: path) }
            }
        }
        return nil
    }
}
