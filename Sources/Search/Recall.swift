import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Everywhere you have been, and everything you have kept. Two lists in the
/// same white-and-hairline panel as the rest, and in both cases the point is
/// as much being able to remove a line as to read one.

enum When {
    private static let ago: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func said(_ date: Date) -> String {
        ago.localizedString(for: date, relativeTo: Date())
    }

    private static let hour: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let plain: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        return formatter
    }()

    /// The time of day. Once a list is grouped by day, that is all a row needs.
    static func clock(_ date: Date) -> String { hour.string(from: date) }

    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return plain.string(from: date)
    }
}

struct HistoryPanel: View {
    @ObservedObject var browser: Browser

    @FocusState private var hunting: Bool
    @State private var traces: [History.Trace] = []
    /// The list as drawn: each day's name, then its pages. Worked out when
    /// the history or the search changes, not each time the panel is drawn.
    @State private var lines: [Listed] = []
    /// Which history Clear takes: nil for every space's, as Safari's All
    /// Profiles; shown only when a signed-out space keeps one of its own.
    @State private var clearsIn: UUID?
    private var clearing: Bool { browser.recallMode == .clearing }

    /// Which days the list is of.
    private enum Span: CaseIterable, Identifiable {
        case all, today, yesterday, week, earlier
        var id: Self { self }
        var title: String {
            switch self {
            case .all: return "Everything"
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .week: return "This Week"
            case .earlier: return "Earlier"
            }
        }

        func holds(_ date: Date) -> Bool {
            let calendar = Calendar.current
            switch self {
            case .all: return true
            case .today: return calendar.isDateInToday(date)
            case .yesterday: return calendar.isDateInYesterday(date)
            case .week: return calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
            case .earlier: return !calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
            }
        }
    }
    @State private var span: Span = .all
    /// One site alone.
    @State private var site: String?
    /// How many there are of each, before one is picked.
    @State private var counts: [Span: Int] = [:]
    /// The sites been to most, by how often.
    @State private var most: [(host: String, visits: Int)] = []
    @State private var width: CGFloat = 900

    var body: some View {
        Plate("History", width: 600, tools: AnyView(tools), close: { browser.recalling = false }) {
            HStack(alignment: .top, spacing: 32) {
                if width > 620, !clearing { sides.frame(width: 200) }
                VStack(alignment: .leading, spacing: 14) {
                    if clearing {
                        sweeps
                    } else if lines.isEmpty {
                        Card { Nothing(browser.recallHunt.isEmpty ? "Nothing yet." : "Nothing matches.") }
                    } else {
                        list
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
        .animation(Motion.settle, value: clearing)
        .onAppear {
            hunting = true
            refresh()
        }
        .onChange(of: browser.recallHunt) { _, _ in refresh() }
        .onChange(of: span) { _, _ in refresh() }
        .onChange(of: site) { _, _ in refresh() }
        // Another space may keep a history of its own (Spaces.history).
        .onChange(of: browser.spaceID) { _, _ in refresh() }
    }

    private var tools: some View {
        HStack(spacing: 8) {
            if clearing {
                Pill("Back") { withAnimation(Motion.settle) { browser.recallMode = .history } }
            } else {
                Hunt(text: $browser.recallHunt, prompt: "Search titles and addresses", focus: $hunting)
                    .frame(width: 300)
                Pill("Clear…") { withAnimation(Motion.settle) { browser.recallMode = .clearing } }
            }
        }
    }

    private var sides: some View {
        VStack(alignment: .leading, spacing: 2) {
            heading("When")
            ForEach(Span.allCases) { choice in
                SideChoice(title: choice.title, count: counts[choice] ?? 0, on: span == choice && site == nil) {
                    span = choice
                    site = nil
                }
            }
            if !most.isEmpty {
                heading("Most visited").padding(.top, 16)
                ForEach(most, id: \.host) { one in
                    SideChoice(title: Address.withoutWWW(one.host), icon: Favicons.shared.cached(one.host), globe: true, count: one.visits, on: site == one.host) {
                        site = site == one.host ? nil : one.host
                    }
                }
            }
        }
    }

    private func heading(_ words: String) -> some View {
        Text(words)
            .font(.system(size: 12))
            .foregroundStyle(Palette.muted)
            .padding(.leading, 10)
            .padding(.bottom, 4)
    }

    private var list: some View {
        // Lazy: only the lines in view are made. Two thousand of
        // them, each with its icon, took the panel a third of a
        // second to open, and scrolling redrew them all.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    switch line.kind {
                    case .day(let day, let date):
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(day).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                            if !date.isEmpty { Text(date).font(.system(size: 12)).foregroundStyle(Palette.muted) }
                        }
                        .padding(.leading, 4)
                        .padding(.top, line.id == lines.first?.id ? 0 : 20)
                        .padding(.bottom, 8)
                    case .trace(let trace, let first, let last):
                        Row(
                            trace: trace,
                            go: {
                                // In this tab, as Chrome's
                                // history does: Back returns here.
                                (browser.pageTab(.history) ?? browser.active)?.go(to: trace.url)
                            },
                            forget: {
                                browser.history.forget(trace.key)
                                refresh()
                            }
                        )
                        // A day's card, drawn a line at a time.
                        .background(Palette.fill)
                        .clipShape(Slice(first: first, last: last))
                    }
                }
            }
            .padding(.bottom, 2)
        }
        .listHeight(420)
    }

    /// Three separate things, worded so nobody has to guess which one signs
    /// them out of their bank.
    private var sweeps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Card {
                Line("History", historyDetail) {
                    let scopes = browser.historyScopes
                    if !scopes.isEmpty {
                        Picker("", selection: $clearsIn) {
                            Text("All Spaces").tag(UUID?.none)
                            ForEach(scopes, id: \.space) { Text($0.name).tag(UUID?.some($0.space)) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    Pill("Clear") {
                        browser.clearHistory(in: scopes.contains { $0.space == clearsIn } ? clearsIn : nil)
                        clearsIn = nil
                        refresh()
                        withAnimation(Motion.settle) { browser.recallMode = .history }
                    }
                }
                Rule()
                Line("Cookies and sign-ins", "Signs you out of every site") {
                    Pill("Sign out of everything") { browser.clearSites() }
                }
                Rule()
                Line("Cache", "Only what was fetched to draw pages") {
                    Pill("Clear") { browser.clearCache() }
                }
            }
        }
        .transition(.opacity)
    }

    private var historyDetail: String {
        guard let clearsIn, let scope = browser.historyScopes.first(where: { $0.space == clearsIn }) else {
            return "Everywhere you have been"
        }
        return "Where you have been in \(scope.name)"
    }

    private func refresh() {
        let all = browser.history.everything(matching: browser.recallHunt)
        counts = Dictionary(uniqueKeysWithValues: Span.allCases.map { span in (span, all.lazy.filter { span.holds($0.last) }.count) })
        var visits: [String: Int] = [:]
        for trace in all { if let host = trace.url.host() { visits[host, default: 0] += trace.count } }
        most = visits.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
        traces = all.filter { span.holds($0.last) && (site == nil || $0.url.host() == site) }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: traces) { calendar.startOfDay(for: $0.last) }
        var made: [Listed] = []
        for day in grouped.keys.sorted(by: >) {
            let rows = grouped[day]!.sorted { $0.last > $1.last }
            let named = calendar.isDateInToday(day) || calendar.isDateInYesterday(day)
            // In English, as the words around it are.
            let long = day.formatted(Date.FormatStyle(locale: Locale(identifier: "en_GB")).weekday(.wide).day().month(.wide))
            made.append(Listed(id: "day " + day.description, kind: .day(named ? When.day(day) : long, named ? long : "")))
            for (index, trace) in rows.enumerated() {
                made.append(Listed(id: trace.id, kind: .trace(trace, first: index == 0, last: index == rows.count - 1)))
            }
        }
        lines = made
    }

    /// One line of the list: a day's name, or a page under it.
    struct Listed: Identifiable {
        enum Kind {
            case day(String, String)
            case trace(History.Trace, first: Bool, last: Bool)
        }
        let id: String
        let kind: Kind
    }

    /// A slice of a card: rounded at the top on its first line and at the
    /// bottom on its last, as the whole card would be.
    struct Slice: InsettableShape {
        let first: Bool
        let last: Bool
        var inset: CGFloat = 0

        func path(in rect: CGRect) -> Path {
            let radius: CGFloat = 10 - inset
            let top = first ? radius : 0, bottom = last ? radius : 0
            return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
                .path(in: rect.insetBy(dx: inset, dy: inset))
        }

        func inset(by amount: CGFloat) -> Slice {
            var copy = self
            copy.inset += amount
            return copy
        }
    }

    /// One line. A title, where it came from, and when — the three things you
    /// scan for, in the order you scan them.
    private struct Row: View {
        let trace: History.Trace
        let go: () -> Void
        let forget: () -> Void

        @State private var hovering = false

        var body: some View {
            HStack(spacing: 10) {
                Mark(icon: Favicons.shared.cached(for: trace.url), letter: "", size: 16, globe: true)
                Text(trace.title.isEmpty ? Address.withoutWWW(trace.address) : trace.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(Address.withoutWWW(trace.address))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if hovering {
                    Quick("Remove", tint: .red.opacity(0.75), act: forget)
                } else {
                    if trace.count > 1 {
                        Text("\(trace.count) visits")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .padding(.horizontal, 8)
                            .frame(height: 18)
                            .background(Palette.fill, in: Capsule())
                            .fixedSize()
                    }
                    Text(When.clock(trace.last))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .monospacedDigit()
                        .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(hovering ? Palette.fillHover : .clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: go)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }
}

struct DownloadsPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var loot: Loot
    @ObservedObject var fetches: Fetches
    /// Under the downloads button or in the side panel (Settings ›
    /// Downloads › Open Downloads): the same list in a narrower place, with
    /// its own title line and cross instead of the plate's.
    let compact: Bool
    let close: (() -> Void)?

    init(browser: Browser, loot: Loot, compact: Bool = false, close: (() -> Void)? = nil) {
        self.browser = browser
        self.loot = loot
        self.fetches = browser.fetches
        self.compact = compact
        self.close = close
    }

    var body: some View {
        if compact { small } else { plate }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Downloads")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                // The whole list, sorted by kind, in a tab: the card is
                // where Downloads opens, so this is the way to the rest.
                Door(icon: "arrow.up.forward.square", help: "Show All in a Tab") {
                    close?()
                    browser.hoarding = true
                }
                Door(icon: "folder", help: "Open the Downloads Folder") {
                    NSWorkspace.shared.open(browser.downloadsFolder)
                }
                if let close { Door(icon: "xmark", help: "Close", act: close) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Rectangle().fill(Palette.hairline).frame(height: 1)
            list
                .padding(12)
            if !loot.kept.isEmpty {
                Spacer(minLength: 0)
                Rectangle().fill(Palette.hairline).frame(height: 1)
                HStack {
                    Spacer()
                    Pill("Clear list") { loot.forgetAll() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// What kind of file the page is of.
    private enum Sort: String, CaseIterable, Identifiable {
        case all = "All", documents = "Documents", images = "Images", apps = "Apps"
        var id: Self { self }

        func holds(_ keep: Keep) -> Bool {
            guard self != .all else { return true }
            guard let type = UTType(filenameExtension: (keep.name as NSString).pathExtension) else { return false }
            switch self {
            case .all: return true
            case .images: return type.conforms(to: .image)
            case .apps: return type.conforms(to: .diskImage) || type.conforms(to: .application) || type.conforms(to: .package)
                || ["pkg", "dmg"].contains(type.preferredFilenameExtension ?? "")
            case .documents: return !Sort.images.holds(keep) && !Sort.apps.holds(keep)
            }
        }
    }
    @State private var sort: Sort = .all
    @State private var hunt = ""
    @FocusState private var hunting: Bool

    private var shown: [Keep] {
        let words = hunt.trimmingCharacters(in: .whitespaces).lowercased()
        return loot.kept.filter { keep in
            sort.holds(keep) && (words.isEmpty || keep.name.lowercased().contains(words) || keep.from.lowercased().contains(words))
        }
    }

    private var plate: some View {
        let shown = self.shown
        let pictures = Array(shown.filter { Sort.images.holds($0) && $0.stillThere }.prefix(8))
        return Plate("Downloads", width: 560, tools: AnyView(HStack(spacing: 8) {
            Segmented(options: Sort.allCases.map { ($0, $0.rawValue) }, selection: $sort)
            Hunt(text: $hunt, prompt: "Search", focus: $hunting).frame(width: 200)
        }), close: close ?? { browser.hoarding = false }) {
            if fetches.entries.isEmpty && loot.kept.isEmpty {
                Card { Nothing("Nothing downloaded yet.") }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if !fetches.entries.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                heading("Coming in")
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                                    ForEach(fetches.entries) { entry in
                                        Card {
                                            FetchRow(
                                                entry: entry,
                                                pause: { browser.pauseDownload(entry) },
                                                resume: { browser.resumeDownload(entry) },
                                                retry: { browser.retryDownload(entry) },
                                                cancel: { browser.cancelDownload(entry) }
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        if !pictures.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                heading("Pictures")
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(alignment: .top, spacing: 12) {
                                        ForEach(pictures) { keep in Picture(keep: keep) { loot.open(keep) } }
                                    }
                                }
                            }
                        }
                        if shown.isEmpty {
                            Card { Nothing("Nothing matches.") }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    heading("Completed")
                                    Spacer()
                                    Text(shown.count == 1 ? "1 file" : "\(shown.count) files")
                                        .font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.trailing, 4)
                                }
                                Card {
                                    HStack(spacing: 12) {
                                        Text("Name").padding(.leading, 44)
                                        Spacer(minLength: 8)
                                        Text("From").frame(width: KeptRow.from, alignment: .leading)
                                        Text("Size").frame(width: KeptRow.size, alignment: .trailing)
                                        Text("Added").frame(width: KeptRow.added, alignment: .trailing)
                                    }
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.muted)
                                    .padding(.horizontal, 14)
                                    .frame(height: 34)
                                    ForEach(shown) { keep in
                                        KeptRow(
                                            keep: keep,
                                            wide: true,
                                            open: { loot.open(keep) },
                                            reveal: { loot.reveal(keep) },
                                            forget: { loot.forget(keep) }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 2)
                }
                .listHeight(420)
            }
        } foot: {
            HStack {
                Text(loot.kept.isEmpty ? "Files land in \(browser.downloadsFolder.lastPathComponent)"
                     : "Clearing the list leaves the files where they are")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                Spacer()
                if !loot.kept.isEmpty {
                    Pill("Clear List") { loot.forgetAll() }
                }
            }
        }
    }

    private func heading(_ words: String) -> some View {
        Text(words).font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.leading, 4)
    }

    /// A downloaded picture, small: read off the main thread at the size it
    /// is drawn.
    private struct Picture: View {
        let keep: Keep
        let open: () -> Void
        @State private var image: NSImage?

        var body: some View {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 4) {
                    ZStack {
                        Palette.fill
                        if let image {
                            Image(nsImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo").font(.system(size: 18)).foregroundStyle(Palette.muted)
                        }
                    }
                    .frame(width: 150, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    FadingLine(text: keep.name).font(.system(size: 12)).foregroundStyle(Palette.ink)
                    Text(When.day(keep.date)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                .frame(width: 150, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(DragOut(keep: keep))
            .task(id: keep.path) {
                let url = keep.url
                let made: CGImage? = await Task.detached(priority: .utility) {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 400,
                    ] as CFDictionary)
                }.value
                image = made.map { NSImage(cgImage: $0, size: .zero) }
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if fetches.entries.isEmpty && loot.kept.isEmpty {
            Card { Nothing("Nothing downloaded yet.") }
        } else {
            FadingScroll {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if !fetches.entries.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Caption("Current downloads")
                            Card {
                                ForEach(Array(fetches.entries.enumerated()), id: \.element.id) { index, entry in
                                    if index > 0 { Rule() }
                                    FetchRow(
                                        entry: entry,
                                        pause: { browser.pauseDownload(entry) },
                                        resume: { browser.resumeDownload(entry) },
                                        retry: { browser.retryDownload(entry) },
                                        cancel: { browser.cancelDownload(entry) }
                                    )
                                }
                            }
                        }
                    }

                    if !loot.kept.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Caption("Completed")
                            Card {
                                ForEach(Array(loot.kept.enumerated()), id: \.element.id) { index, keep in
                                    if index > 0 { Rule() }
                                    KeptRow(
                                        keep: keep,
                                        open: { loot.open(keep) },
                                        reveal: { loot.reveal(keep) },
                                        forget: { loot.forget(keep) }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 2)
            }
            // Hairlines from edge to edge, as Settings' are: the cards hold
            // icons, not text, at the inset a rule would start from.
            .environment(\.ruleInset, 0)
            .listHeight(420)
        }
    }

    /// The list's scroll, fading out at its foot while more lies below
    /// rather than cutting a line in half; less as the end comes up, and
    /// not at all once it is in view. Its head does the same once scrolled,
    /// so a caption going under the title line isn't sliced across. A mask,
    /// so it is the same in light and dark and over whatever the list is
    /// drawn on.
    private struct FadingScroll<Content: View>: View {
        @ViewBuilder let content: () -> Content
        /// Where the list ends, and how tall the scroll is: the end lies
        /// below the foot by the difference.
        @State private var end: CGFloat = 0
        /// Where the list starts: above the scroll's top by as much as it
        /// has been scrolled.
        @State private var start: CGFloat = 0
        @State private var height: CGFloat = 0
        private let fade: CGFloat = 24
        private static var space: String { "downloads.list" }

        var body: some View {
            ScrollView {
                content()
                    // Read where it is rather than sent up as a preference:
                    // one from inside the scroll never came out of it here.
                    .background(GeometryReader { list in
                        let frame = list.frame(in: .named(Self.space))
                        Color.clear
                            .onAppear { end = frame.maxY; start = frame.minY }
                            .onChange(of: frame.maxY) { _, new in end = new }
                            .onChange(of: frame.minY) { _, new in start = new }
                    })
            }
            .coordinateSpace(name: Self.space)
            // Measured beside the scroll, not around it, so it sizes itself
            // as it always has.
            .background(GeometryReader { view in
                Color.clear
                    .onAppear { height = view.size.height }
                    .onChange(of: view.size.height) { _, new in height = new }
            })
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(1 - min(1, max(0, -start) / fade)), .black],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: fade)
                    Rectangle()
                    LinearGradient(colors: [.black, .black.opacity(1 - min(1, max(0, end - height) / fade))],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: fade)
                }
            }
        }
    }

    private struct FetchRow: View {
        @ObservedObject var entry: FetchEntry
        let pause: () -> Void
        let resume: () -> Void
        let retry: () -> Void
        let cancel: () -> Void

        private var received: String {
            ByteCountFormatter.string(fromByteCount: entry.completedBytes, countStyle: .file)
        }

        private var bytes: String {
            guard entry.totalBytes > 0 else { return received + " downloaded" }
            let total = ByteCountFormatter.string(fromByteCount: entry.totalBytes, countStyle: .file)
            return "\(received) of \(total)"
        }

        private var stateLabel: String {
            switch entry.state {
            case .downloading: return entry.stalled ? "Stalled" : "Downloading"
            case .pausing: return entry.stopping
            case .paused: return "Paused"
            case .resuming: return "Resuming…"
            case .failed: return "Failed"
            }
        }

        private func status(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
                .monospacedDigit()
                .lineLimit(1)
        }

        private var icon: String {
            switch entry.state {
            case .downloading, .pausing, .resuming: return "arrow.down.circle"
            case .paused: return "pause.circle"
            case .failed: return "exclamationmark.circle"
            }
        }

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 18)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 7) {
                        if let fraction = entry.fraction {
                            // Grey, as the ring in the chrome is.
                            Capsule()
                                .fill(Palette.hairline)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(Palette.ink.opacity(0.6))
                                        .frame(width: 68 * min(1, max(0, fraction)))
                                }
                                .frame(width: 68, height: 3)
                        }
                        // A row with three buttons has little room left: say
                        // less rather than cut the amount out of the middle.
                        ViewThatFits(in: .horizontal) {
                            status("\(stateLabel) · \(bytes)")
                            status("\(stateLabel) · \(received)")
                            status(stateLabel)
                        }
                    }
                    if case .failed = entry.state {
                        Text(entry.errorDescription ?? "The download failed.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    // Beside the text, the buttons left it a few letters
                    // wide; under it, the name and status read whole.
                    controls
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .contextMenu { if let address = entry.address { CopyAddress(address: address) } }
        }

        @ViewBuilder
        private var controls: some View {
            switch entry.state {
            case .downloading:
                HStack(spacing: 4) {
                    if entry.canPause { Quick("Pause", act: pause) }
                    Quick("Cancel", act: cancel)
                }
            case .pausing:
                HStack(spacing: 4) {
                    Quick(entry.stopping, act: {})
                        .disabled(true)
                    Quick("Cancel", act: cancel)
                }
            case .paused:
                HStack(spacing: 4) {
                    if entry.canResume {
                        Quick("Resume", act: resume)
                    } else if entry.canRetry {
                        Quick("Retry", act: retry)
                            .help("Start the download again from the beginning")
                    }
                    Quick("Remove", act: cancel)
                }
            case .resuming:
                HStack(spacing: 4) {
                    Quick("Resuming…", act: {})
                        .disabled(true)
                    Quick("Cancel", act: cancel)
                }
            case .failed:
                HStack(spacing: 4) {
                    if entry.canResume { Quick("Resume", act: resume) }
                    if entry.canRetry {
                        Quick("Retry", act: retry)
                            .help("Start the download again from the beginning")
                    }
                    Quick("Remove", act: cancel)
                }
            }
        }
    }

    private struct KeptRow: View {
        static let from: CGFloat = 170
        static let size: CGFloat = 70
        static let added: CGFloat = 90

        let keep: Keep
        /// On the page, in columns, rather than in a panel's few words.
        var wide = false
        let open: () -> Void
        let reveal: () -> Void
        let forget: () -> Void

        @State private var hovering = false

        private var bytes: String {
            guard let size = try? keep.url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "" }
            return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }

        var body: some View {
            HStack(spacing: 12) {
                Text((keep.name as NSString).pathExtension.prefix(4).uppercased())
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 26, height: 32)
                    .elevated(.lift, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .opacity(keep.stillThere ? 1 : 0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(keep.name)
                        .font(.system(size: 13))
                        .foregroundStyle(keep.stillThere ? Palette.ink : Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !keep.stillThere {
                        Text("Moved or deleted").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    } else if !wide {
                        Text(keep.from.isEmpty ? When.said(keep.date) : "\(keep.from) · \(When.said(keep.date))")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if hovering {
                    if keep.stillThere { Quick("Show in Finder", act: reveal) }
                    Quick("Remove", tint: .red.opacity(0.75), act: forget)
                } else if wide {
                    HStack(spacing: 8) {
                        if !keep.from.isEmpty { SiteMark(host: keep.from, size: 14) }
                        Text(keep.from).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .frame(width: Self.from)
                    Text(bytes).monospacedDigit().frame(width: Self.size, alignment: .trailing)
                    Text(Calendar.current.isDateInToday(keep.date) ? When.clock(keep.date) : When.day(keep.date))
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: Self.added, alignment: .trailing)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(hovering ? Palette.fillHover : .clear)
            .contentShape(Rectangle())
            .contextMenu { if let address = keep.address { CopyAddress(address: address) } }
            .modifier(DragOut(keep: keep))
            .onTapGesture { if keep.stillThere { open() } }
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }

    /// A finished download dragged out of the list as its file, onto a page
    /// or into another app, with the file's own icon under the pointer. A
    /// row whose file has gone has nothing to drag. The drag starts only
    /// once the pointer moves, so a click still opens the file.
    private struct DragOut: ViewModifier {
        let keep: Keep

        func body(content: Content) -> some View {
            if keep.stillThere {
                content.onDrag {
                    keep.dragged ?? NSItemProvider()
                } preview: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: keep.path))
                        .resizable()
                        .frame(width: 32, height: 32)
                }
            } else {
                content
            }
        }
    }

    /// A row's right-click, for handing the download to another app.
    private struct CopyAddress: View {
        let address: String

        var body: some View {
            Button("Copy Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(address, forType: .string)
            }
        }
    }
}
