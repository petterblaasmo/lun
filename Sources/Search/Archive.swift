import Foundation
import SwiftUI

// The tabs Search closed by itself, as Arc's archive keeps them.
//
// With Settings › Tabs › Close tabs left alone on, a tab nobody has looked
// at for its time closes (Closing.swift). ⇧⌘T and Recently Closed hold a
// dozen closes, and every close counts, ⌘W's too: a week's worth of tabs
// closed overnight went past them, and History has each page among
// everything else. Here they stay together, newest first, for thirty days
// or the last five hundred: History › Archived Tabs… lists them, with a
// search, and a click opens one again in the space on screen.
//
// Only what Search closed: a tab you closed yourself is one you meant to.
// Never a private tab, which nothing keeps. Each profile has its own, as it
// has its own history: a window lists only its profile's, and deleting a
// profile, or clearing its history, empties it. With tabs never closing,
// nothing is added and the menu doesn't offer it.

/// One tab Search closed, as the archive keeps it.
struct Archived: Codable, Identifiable, Equatable {
    var id = UUID()
    let url: URL
    let title: String
    /// When it was closed.
    let closed: Date

    var label: String { title.isEmpty ? Address.withoutWWW(Address.editable(url)) : title }
    var site: String { Address.withoutWWW(url.host() ?? Address.editable(url)) }
}

@MainActor
final class Archive: ObservableObject {
    /// Newest first.
    @Published private(set) var tabs: [Archived] = []

    /// Kept at most: far more than anybody scrolls back through, and a small file.
    nonisolated static let cap = 500
    /// Kept for a month: past that, History has it.
    nonisolated static let lasts: TimeInterval = 30 * 86_400

    let file: URL
    /// Its profile deleted: nothing more is written.
    private var retired = false

    init(file name: String) {
        file = Store.file(name)
        let saved = (try? Data(contentsOf: file)).flatMap { try? Archive.decoder.decode([Archived].self, from: $0) }
        tabs = Archive.trimmed(saved ?? [], now: Date())
    }

    // MARK: - each profile's

    private static var made: [UUID: Archive] = [:]

    /// archive.json for Personal, one of its own for each other profile, as
    /// history is (see Profiles.history).
    static func fileName(of profile: UUID) -> String {
        profile == Profile.personalID ? "archive.json" : "archive-\(profile.uuidString).json"
    }

    static func of(_ profile: UUID) -> Archive {
        if let archive = made[profile] { return archive }
        let archive = Archive(file: fileName(of: profile))
        made[profile] = archive
        return archive
    }

    /// A profile deleted: its archive emptied and its file gone, opened
    /// this run or not.
    static func forget(profile: UUID) {
        made.removeValue(forKey: profile)?.retired = true
        Disk.remove(Store.file(fileName(of: profile)))
    }

    // MARK: - changing it

    /// A tab Search just closed. A page already here moves to the top.
    func add(_ url: URL, title: String, at closed: Date = Date()) {
        guard !retired, let url = History.kept(url) else { return }
        var list = tabs.filter { $0.url != url }
        list.insert(Archived(url: url, title: title, closed: closed), at: 0)
        tabs = Archive.trimmed(list, now: Date())
        save()
    }

    func remove(_ id: Archived.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        tabs.removeAll { $0.id == id }
        save()
    }

    func clear() {
        guard !tabs.isEmpty else { return }
        tabs = []
        save()
    }

    /// What the list shows: past the month, nothing, even before anything
    /// is next added; and, with words typed, what has all of them in its
    /// title or address.
    func listed(matching hunt: String = "", now: Date = Date()) -> [Archived] {
        let words = hunt.lowercased().split(whereSeparator: \.isWhitespace)
        return Archive.trimmed(tabs, now: now).filter { tab in
            let text = (tab.title + " " + tab.url.absoluteString).lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    /// Newest first, a month at most, and no more than the cap.
    nonisolated static func trimmed(_ list: [Archived], now: Date) -> [Archived] {
        let since = now.addingTimeInterval(-lasts)
        return Array(list.filter { $0.closed >= since }.sorted { $0.closed > $1.closed }.prefix(cap))
    }

    private func save() {
        guard !retired else { return }
        let snapshot = tabs
        Disk.write(file) { try? Archive.encoder.encode(snapshot) }
    }

    nonisolated private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    nonisolated private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension Browser {
    /// This window's profile's.
    var archive: Archive { Archive.of(profileID) }

    /// Closing one by itself (Closing.swift): into the archive first. Its
    /// address as the tab knows it, asleep or not; Search's own pages are
    /// one click away already.
    func archive(_ tab: Tab) {
        guard !tab.shy, let url = tab.address ?? tab.page?.url, InternalPage(url: url) == nil,
              ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") else { return }
        archive.add(url, title: tab.title)
    }

    /// From the list: a tab of its own in the space on screen, in front,
    /// and out of the archive.
    func reopen(_ archived: Archived) {
        archive.remove(archived.id)
        _ = open(archived.url, foreground: true)
    }

    /// History › Archived Tabs…, in a tab.
    var archiving: Bool {
        get { pageTab(.archive) != nil }
        set { if newValue { show(InternalPage(.archive)) } else { putAway(.archive) } }
    }
}

/// History › Archived Tabs…: History's look, its days and its rows, for the
/// tabs Search closed by itself.
struct ArchivePanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var archive: Archive

    @FocusState private var hunting: Bool
    @State private var hunt = ""

    private var listed: [Archived] { archive.listed(matching: hunt) }

    var body: some View {
        let listed = self.listed
        Plate("Archived Tabs", line: "Tabs Lun put away because you left them alone. Each stays here for 30 days.", width: 600,
              tools: AnyView(tools), close: { browser.archiving = false }) {
            if listed.isEmpty {
                Card { Nothing(hunt.isEmpty ? empty : "Nothing matches.") }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(days(listed)) { day in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(day.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                                    Text(day.tabs.count == 1 ? "1 tab" : "\(day.tabs.count) tabs").font(.system(size: 12)).foregroundStyle(Palette.muted)
                                    Spacer()
                                    Pill("Reopen All") { day.tabs.forEach { browser.reopen($0) } }
                                }
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], alignment: .leading, spacing: 12) {
                                    ForEach(day.tabs) { tab in
                                        Tile(tab: tab, go: { browser.reopen(tab) }, remove: { archive.remove(tab.id) })
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
                Text(listed.count == 1 ? "1 tab" : "\(listed.count) tabs")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                Spacer()
                if !archive.tabs.isEmpty {
                    Pill("Clear") { archive.clear() }
                }
            }
        }
        .onAppear { hunting = true }
    }

    private var tools: some View {
        HStack(spacing: 8) {
            PopUp("Put tabs away", shows: browser.prefs.tabLife.title,
                    selection: Binding(get: { browser.prefs.tabLife }, set: { browser.prefs.tabLife = $0 })) {
                ForEach(TabLife.allCases) { Text($0.title).tag($0) }
            }
            Hunt(text: $hunt, prompt: "Search", focus: $hunting).frame(width: 180)
        }
    }

    private var empty: String {
        browser.prefs.tabLife.interval == nil
            ? "Tabs never close by themselves (Settings › Tabs & Spaces)."
            : "Nothing yet. Tabs Lun closes for you land here."
    }

    private struct Day: Identifiable {
        let id: Date
        let title: String
        let tabs: [Archived]
    }

    /// Each day and the tabs put away on it, newest first.
    private func days(_ listed: [Archived]) -> [Day] {
        let calendar = Calendar.current
        return Dictionary(grouping: listed) { calendar.startOfDay(for: $0.closed) }
            .sorted { $0.key > $1.key }
            .map { Day(id: $0.key, title: When.day($0.key), tabs: $0.value) }
    }

    /// A tab put away: its icon, its title, its site, and how long it stays.
    private struct Tile: View {
        let tab: Archived
        let go: () -> Void
        let remove: () -> Void

        @State private var hovering = false

        private var left: String {
            let days = max(0, Int((Archive.lasts - Date().timeIntervalSince(tab.closed)) / 86_400))
            return days == 1 ? "1 day left" : "\(days) days left"
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Mark(icon: Favicons.shared.cached(for: tab.url), letter: "", size: 24, globe: true)
                    Spacer()
                    if hovering {
                        Button(action: remove) {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted)
                                .frame(width: 22, height: 22).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                }
                FadingLine(text: tab.label).font(.system(size: 13)).foregroundStyle(Palette.ink)
                HStack(spacing: 4) {
                    Text("\(tab.site) · \(When.clock(tab.closed))").lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(left).fixedSize()
                }
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
            }
            .padding(12)
            .background(hovering ? Palette.fillHover : Palette.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onTapGesture(perform: go)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
            .help("Open again in this space")
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
    }
}
