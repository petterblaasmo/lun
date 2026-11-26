import AppKit
import Combine
import SwiftUI

// The Bookmarks page: the folders as a tree down the side, and beside it
// what the folder picked holds: its folders as tiles, its bookmarks as a
// table or a grid. A bookmark or a folder is carried to another place among
// its own kind, or onto a folder, in the tree or beside it.
//
// It draws the list and changes it through what Bookmarks already does
// (move, rename, new folder, remove). Nothing new is kept in the file: a
// bookmark has a name and an address and nothing else, so there is no
// column for when it was added.

/// Where something carried on the Bookmarks page lands, worked out apart
/// from the views that take the drop.
@MainActor
enum BookmarkDrop {
    /// Which part of a row or a tile the pointer is over.
    enum Zone: String { case before, into, after }

    /// What is asked of `Bookmarks.move`: the folder (the top level for
    /// nil), and the place among what it holds, counted before the move;
    /// the end for nil.
    struct Landing: Equatable {
        var parent: Bookmark.ID?
        var index: Int?
    }

    /// How far along a row or a tile, from 0 to 1, is which part of it. A
    /// folder's middle half is the folder itself; anything else has only a
    /// first half and a second.
    static func zone(at part: CGFloat, folder: Bool) -> Zone {
        guard folder else { return part < 0.5 ? .before : .after }
        return part < 0.25 ? .before : part > 0.75 ? .after : .into
    }

    /// Where `dragged` goes when it is let go over `target` (the top level
    /// for nil) at `zone`, and the zone it is taken as. Nil where it can't
    /// go, or would stay where it is:
    ///
    /// - a folder never goes into itself or anything inside it, nor beside
    ///   anything inside it, which would loop it out of the list;
    /// - the page shows a folder's folders apart from its bookmarks, so one
    ///   goes beside its own kind only. A bookmark over any part of a
    ///   folder goes into it; a folder over a bookmark goes nowhere;
    /// - beside the neighbour it already stands beside, or into the folder
    ///   it is already in, there is nothing to do. The place is counted
    ///   among its own kind, as the page shows them: a folder standing
    ///   between two bookmarks in the file doesn't make them less beside
    ///   each other.
    static func landing(of dragged: Bookmark.ID, over target: Bookmark.ID?, _ zone: Zone,
                        in roots: [Bookmark]) -> (zone: Zone, landing: Landing)? {
        guard let carried = find(dragged, in: roots) else { return nil }
        guard let target else {
            return carried.parent == nil ? nil : (.into, Landing(parent: nil, index: nil))
        }
        guard target != dragged, !Bookmarks.holds(target, carried.node), let aimed = find(target, in: roots) else { return nil }
        var zone = zone
        if zone != .into, carried.node.isFolder != aimed.node.isFolder {
            guard aimed.node.isFolder else { return nil }
            zone = .into
        }
        if zone == .into {
            guard aimed.node.isFolder, carried.parent != target else { return nil }
            return (.into, Landing(parent: target, index: nil))
        }
        if carried.parent == aimed.parent {
            let kind = aimed.siblings.filter { $0.isFolder == carried.node.isFolder }
            if let from = kind.firstIndex(where: { $0.id == dragged }), let to = kind.firstIndex(where: { $0.id == target }),
               to == (zone == .before ? from + 1 : from - 1) {
                return nil
            }
        }
        return (zone, Landing(parent: aimed.parent, index: zone == .before ? aimed.index : aimed.index + 1))
    }

    /// A bookmark or a folder with where it stands: the folder it is in
    /// (nil at the top level), what else is there, and its place among it.
    private static func find(_ id: Bookmark.ID, in nodes: [Bookmark], parent: Bookmark.ID? = nil)
        -> (node: Bookmark, parent: Bookmark.ID?, siblings: [Bookmark], index: Int)? {
        for (index, node) in nodes.enumerated() {
            if node.id == id { return (node, parent, nodes, index) }
            if let kids = node.children, let found = find(id, in: kids, parent: node.id) { return found }
        }
        return nil
    }
}

/// How the page lays a folder's bookmarks out. Remembered as a plain key,
/// not a setting: it is chosen on the page itself.
enum BookmarksLayout: String {
    case list, grid

    static let key = "bookmarks.view"

    static var kept: BookmarksLayout {
        get { Store.settings.string(forKey: key).flatMap(BookmarksLayout.init) ?? .list }
        set { Store.settings.set(newValue.rawValue, forKey: key) }
    }
}

/// The full list, for putting it in order, finding one, or bringing more in.
struct BookmarksPanel: View {
    @ObservedObject var browser: Browser
    let bookmarks: Bookmarks

    /// The folder shown beside the tree; nil for the top level, which is
    /// also what shows once that folder is gone.
    @State private var picked: Bookmark.ID?
    /// The folders open in the tree.
    @State private var expanded: Set<Bookmark.ID>
    @State private var layout = BookmarksLayout.kept
    @State private var query = ""
    @FocusState private var hunting: Bool
    /// The row just shown from a search, washed for a moment so the eye
    /// lands on it.
    @State private var shown: Bookmark.ID?
    @State private var dragging: Bookmark.ID?
    /// Where the drag under way would land, drawn as a line or a wash.
    @State private var aimed: Aim?
    /// A closed folder of the tree held over opens after a moment, so a
    /// bookmark can go deep without being dropped on the way.
    @State private var spring: DispatchWorkItem?
    @State private var width: CGFloat = 900

    init(browser: Browser, bookmarks: Bookmarks) {
        self.browser = browser
        self.bookmarks = bookmarks
        _expanded = State(initialValue: BookmarksDropdown.opening(bookmarks.roots))
    }

    /// A row or a tile and where on it; the top level for no id. The tree's
    /// rows and the tiles beside it may be the same folder, and only the
    /// one under the pointer is lit.
    struct Aim: Equatable {
        let id: Bookmark.ID?
        let zone: BookmarkDrop.Zone
        let tree: Bool
    }

    /// One folder of the tree as it shows.
    struct Branch: Identifiable {
        let node: Bookmark
        let depth: Int
        /// Nil where it holds no folder: nothing to open.
        let isOpen: Bool?
        var id: Bookmark.ID { node.id }
    }

    /// The folders that show, those in `expanded` open, in order. Only
    /// folders: the bookmarks are beside the tree, not in it.
    static func branches(_ nodes: [Bookmark], expanded: Set<Bookmark.ID>, depth: Int = 0, into out: inout [Branch]) {
        for node in nodes where node.isFolder {
            let kids = node.children ?? []
            let inside = kids.contains(where: \.isFolder)
            let isOpen = inside && expanded.contains(node.id)
            out.append(Branch(node: node, depth: depth, isOpen: inside ? isOpen : nil))
            if isOpen { branches(kids, expanded: expanded, depth: depth + 1, into: &out) }
        }
    }

    /// What a folder holds, in words: "2 folders, 7 bookmarks".
    static func summary(folders: Int, sites: Int) -> String {
        let parts = [
            folders == 0 ? nil : folders == 1 ? "1 folder" : "\(folders.formatted()) folders",
            sites == 0 ? nil : sites == 1 ? "1 bookmark" : "\(sites.formatted()) bookmarks",
        ].compactMap { $0 }
        return parts.isEmpty ? "Empty" : parts.joined(separator: ", ")
    }

    /// With less room than this the tree gives way to the list, as
    /// History's side does: a narrow pane of a pair.
    private var wide: Bool { width > 620 }

    /// The folder shown, nil at the top level.
    private var folder: Bookmark? {
        picked.flatMap { bookmarks.bookmark($0) }.flatMap { $0.isFolder ? $0 : nil }
    }

    var body: some View {
        Plate("Bookmarks", width: 600, tools: AnyView(tools), close: { browser.bookmarking = false }) {
            VStack(alignment: .leading, spacing: 14) {
                if bookmarks.isEmpty {
                    Card { Nothing("Nothing kept yet. Add this page with ⇧⌘B, or bring yours in below.") }
                } else if !query.isEmpty {
                    found
                } else {
                    HStack(alignment: .top, spacing: 32) {
                        if wide { tree.frame(width: 200) }
                        pane.frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        } foot: {
            HStack(spacing: 8) {
                Text("Bring in from")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                Pill("Bring in…") { browser.lead(to: InternalPage(.importing)) }
                Pill("File…") { browser.importFile() }
                Spacer()
                Text(bookmarks.count == 1 ? "1 bookmark" : "\(bookmarks.count) bookmarks")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
            }
        }
        .animation(Motion.settle, value: query.isEmpty)
        .onAppear { hunting = true }
        .onChange(of: layout) { _, now in BookmarksLayout.kept = now }
        .onReceive(Self.bench) { answer($0) }
    }

    private var tools: some View {
        HStack(spacing: 8) {
            Hunt(text: $query, prompt: bookmarks.count == 1 ? "Search 1 bookmark" : "Search \(bookmarks.count) bookmarks", focus: $hunting)
                .onSubmit(openFirst)
                // The field gives way in a narrow pane, not the buttons.
                .frame(minWidth: 120, maxWidth: 240)
            Segmented(options: [(BookmarksLayout.list, "list.bullet"), (BookmarksLayout.grid, "square.grid.2x2")],
                      selection: $layout, symbols: { $0 == .list ? "List" : "Grid" })
            // In the folder shown, as a new folder in a Finder window is.
            Pill("New Folder…") { bookmarks.askNewFolder(in: folder?.id) }
                .fixedSize()
        }
    }

    // MARK: - the tree

    private var tree: some View {
        var showing: [Branch] = []
        Self.branches(bookmarks.roots, expanded: expanded, into: &showing)
        let folders = Bookmarks.folders(bookmarks.roots)
        let here = folder?.id
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                TreeRow(title: "Top Level", symbol: "book", depth: 0, count: bookmarks.count, isOpen: nil, on: here == nil,
                        aimed: aimed == Aim(id: nil, zone: .into, tree: true), dragging: false,
                        toggle: {}, pick: { pick(nil) })
                    .contextMenu { Button("New Folder…") { bookmarks.askNewFolder(in: nil) } }
                    .modifier(landing(over: nil, tree: true, edges: false))
                ForEach(showing) { branch in
                    let node = branch.node
                    TreeRow(title: node.title, symbol: "folder", depth: branch.depth, count: Bookmarks.count(node.children ?? []),
                            isOpen: branch.isOpen, on: here == node.id,
                            aimed: aimed == Aim(id: node.id, zone: .into, tree: true), dragging: dragging == node.id,
                            toggle: { withAnimation(Motion.quick) { toggle(node.id) } }, pick: { pick(node.id) })
                        .contextMenu { menu(for: node, folders: folders) }
                        .onDrag { carry(node) }
                        .modifier(landing(over: node.id, tree: true, edges: false))
                }
            }
            .padding(.bottom, 2)
        }
        .listHeight(440)
    }

    /// One folder of the tree: its arrow, which opens it, and the rest of
    /// the row, which shows what it holds beside the tree.
    private struct TreeRow: View {
        let title: String
        let symbol: String
        let depth: Int
        let count: Int
        let isOpen: Bool?
        let on: Bool
        /// A drag is over it, and would go in.
        let aimed: Bool
        let dragging: Bool
        let toggle: () -> Void
        let pick: () -> Void

        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            HStack(spacing: 4) {
                Group {
                    if let isOpen {
                        IconButton("chevron.right", label: isOpen ? "Close \(title)" : "Open \(title)", glyph: 9, weight: .semibold,
                                   size: 16, wash: nil, tip: "", action: toggle)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 16, height: 16)
                Button(action: pick) {
                    HStack(spacing: 8) {
                        Image(systemName: symbol)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.soft)
                            .frame(width: 18)
                        Text(title)
                            .font(.system(size: 13, weight: on ? .medium : .regular))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(count.formatted())
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(Palette.muted)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(Gives(to: 0.98))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            .padding(.leading, CGFloat(depth) * 16 + 6)
            .padding(.trailing, 10)
            .frame(height: 30)
            .background(aimed ? Palette.fillHover : on ? Palette.fill : hovering ? Palette.hover : .clear, in: shape)
            .overlay { if aimed { shape.strokeBorder(Palette.drop, lineWidth: 1) } }
            .contentShape(shape)
            .opacity(dragging ? 0.35 : 1)
            .hovers($hovering)
            .animation(Motion.quick, value: aimed)
            .animation(Motion.quick, value: dragging)
        }
    }

    // MARK: - what the folder holds

    private var pane: some View {
        let here = folder
        let kids = here.map { $0.children ?? [] } ?? bookmarks.roots
        let inside = kids.filter(\.isFolder), sites = kids.filter { !$0.isFolder }
        let folders = Bookmarks.folders(bookmarks.roots)
        let above = here.flatMap { bookmarks.path(to: $0.id) } ?? []
        let summary = Self.summary(folders: inside.count, sites: sites.count)
        if Store.testing {
            Self.benchShows = [
                "path": above.map(\.title) + (here.map { [$0.title] } ?? []), "summary": summary, "layout": layout.rawValue,
                "folders": inside.map(\.title), "bookmarks": sites.map(\.label), "tree": wide,
            ]
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // With no tree beside it, the way back up is here.
                if !wide, here != nil { crumb("Top Level", to: nil) }
                ForEach(above) { crumb($0.title, to: $0.id) }
                Text(here?.title ?? "Top Level")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .layoutPriority(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .frame(minHeight: 24)
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !inside.isEmpty { tiles(inside, folders: folders) }
                        if sites.isEmpty {
                            if inside.isEmpty { Card { Nothing("Nothing in this folder yet.") } }
                        } else if layout == .list {
                            table(sites, folders: folders)
                        } else {
                            grid(sites, folders: folders)
                        }
                    }
                    .padding(.bottom, 2)
                }
                .listHeight(440)
                // A bookmark found is shown where it lives, which may be
                // below what shows. This list is only made as the search is
                // cleared for it, with the row to show already set, so it is
                // read as it appears too.
                .onChange(of: shown, initial: true) { _, id in
                    guard let id else { return }
                    DispatchQueue.main.async {
                        withAnimation(Motion.settle) { scroller.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }

    /// A folder above the one shown, and the arrow after it.
    @ViewBuilder
    private func crumb(_ title: String, to id: Bookmark.ID?) -> some View {
        TextLink(title, size: 15) { pick(id) }
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Palette.muted)
            .accessibilityHidden(true)
    }

    private func tiles(_ inside: [Bookmark], folders: [(node: Bookmark, depth: Int)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(inside) { node in
                FolderTile(node: node, dragging: dragging == node.id, aim: aim(on: node.id)) { pick(node.id) }
                    .contextMenu { menu(for: node, folders: folders) }
                    .onDrag { carry(node) }
                    .modifier(landing(over: node.id, tree: false, across: true, folder: true))
            }
        }
    }

    private func table(_ sites: [Bookmark], folders: [(node: Bookmark, depth: Int)]) -> some View {
        // The address has a column of its own where there is room for one.
        let room = width - (wide ? 232 : 0)
        let address: CGFloat? = room >= 520 ? min(280, room * 0.36) : nil
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Over the names, past the icons.
                Text("Name").padding(.leading, 28)
                Spacer(minLength: 12)
                if let address { Text("Address").frame(width: address, alignment: .leading) }
            }
            .font(.system(size: 12))
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 16)
            .frame(height: 34)
            // Lazy: only the rows in sight are made, as in History. A
            // folder of thousands comes in from another browser.
            LazyVStack(spacing: 0) {
                ForEach(sites) { node in
                    BookmarkLine(node: node, address: address, dragging: dragging == node.id, aim: aim(on: node.id),
                                 shown: shown == node.id, open: { open(node) })
                        .id(node.id)
                        .modifier(carried(node, folders: folders, across: false))
                }
            }
        }
        .padding(.bottom, 4)
        .background(Palette.fill)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func grid(_ sites: [Bookmark], folders: [(node: Bookmark, depth: Int)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(sites) { node in
                BookmarkTile(node: node, dragging: dragging == node.id, aim: aim(on: node.id), shown: shown == node.id,
                             open: { open(node) })
                    .id(node.id)
                    .modifier(carried(node, folders: folders, across: true))
            }
        }
    }

    /// What every bookmark has, as a row or as a tile: the middle button
    /// for a new tab, its menu, and that it is carried and takes a drop.
    private func carried(_ node: Bookmark, folders: [(node: Bookmark, depth: Int)], across: Bool) -> Carried {
        Carried(newTab: node.address.map { url in { browser.pickBookmark(url, inNewTab: true) } },
                menu: AnyView(menu(for: node, folders: folders)),
                carry: { carry(node) },
                landing: landing(over: node.id, tree: false, across: across, folder: false))
    }

    private struct Carried: ViewModifier {
        let newTab: (() -> Void)?
        let menu: AnyView
        let carry: () -> NSItemProvider
        let landing: TakesDrop

        func body(content: Content) -> some View {
            content
                .overlay { if let newTab { MiddleClick(act: newTab) } }
                .contextMenu { menu }
                .onDrag(carry)
                .modifier(landing)
        }
    }

    /// The same things the button's list offers on a right-click. Remove
    /// asks first for a folder with anything in it (Bookmarks.askRemove),
    /// and is here only, never a button on the row.
    @ViewBuilder
    private func menu(for node: Bookmark, folders: [(node: Bookmark, depth: Int)]) -> some View {
        if !node.isFolder {
            Button("Open") { open(node) }
            Divider()
        }
        Button("Rename…") { bookmarks.askRename(node) }
        if node.isFolder {
            Button("New Folder Inside…") {
                bookmarks.askNewFolder(in: node.id) { _ in expanded.insert(node.id) }
            }
        }
        Menu("Move to") {
            Button("Top Level") { bookmarks.move(node.id, into: nil) }
            // A folder is kept out of itself and what is inside it.
            let targets = node.isFolder ? folders.filter { !Bookmarks.holds($0.node.id, node) } : folders
            if !targets.isEmpty {
                Divider()
                ForEach(targets, id: \.node.id) { target in
                    Button(String(repeating: "   ", count: target.depth) + target.node.title) {
                        bookmarks.move(node.id, into: target.node.id)
                    }
                }
            }
        }
        Divider()
        Button("Remove", role: .destructive) { bookmarks.askRemove(node) }
    }

    /// An extension can write an address that does not parse.
    private func open(_ node: Bookmark) {
        if let url = node.address { browser.pickBookmark(url) }
    }

    /// Where the drag under way would land on this row or tile beside the
    /// tree, if it is the one aimed at.
    private func aim(on id: Bookmark.ID) -> BookmarkDrop.Zone? {
        guard let aimed, !aimed.tree, aimed.id == id else { return nil }
        return aimed.zone
    }

    /// The folder shown beside the tree, and the tree open down to it and
    /// at it, so the folders its tiles show are under it there too.
    private func pick(_ id: Bookmark.ID?) {
        picked = id
        if let id { expanded.formUnion((bookmarks.path(to: id) ?? []).map(\.id) + [id]) }
    }

    private func toggle(_ id: Bookmark.ID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    // MARK: - carrying

    private func carry(_ node: Bookmark) -> NSItemProvider {
        dragging = node.id
        settleWhenLetGo()
        return NSItemProvider(object: node.id.uuidString as NSString)
    }

    private func landing(over target: Bookmark.ID?, tree: Bool, across: Bool = false, folder: Bool = true, edges: Bool = true) -> TakesDrop {
        TakesDrop(across: across, folder: folder, edges: edges,
                settle: { settle($0, over: target) },
                aim: { aim($0.map { Aim(id: target, zone: $0, tree: tree) }) },
                land: { land($0, over: target, $1) })
    }

    /// What the drag under way would be taken as over `target`, nil where
    /// it can't go. One that didn't start here (the button's list) is only
    /// known as it lands.
    private func settle(_ zone: BookmarkDrop.Zone, over target: Bookmark.ID?) -> BookmarkDrop.Zone? {
        guard let dragging else { return zone }
        return BookmarkDrop.landing(of: dragging, over: target, zone, in: bookmarks.roots)?.zone
    }

    private func aim(_ target: Aim?) {
        guard target != aimed else { return }
        aimed = target
        spring?.cancel()
        spring = nil
        guard let target, target.tree, let id = target.id, !expanded.contains(id) else { return }
        let expanded = $expanded
        let work = DispatchWorkItem { withAnimation(Motion.settle) { _ = expanded.wrappedValue.insert(id) } }
        spring = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    /// SwiftUI says when something lands here, not when it is let go
    /// anywhere else or the drag is called off, which would leave the line
    /// where it was last aimed and the row faded. The button coming up says
    /// it, as in the button's list (BookmarkOutline.settleWhenLetGo).
    private func settleWhenLetGo() {
        let aimed = $aimed, dragging = $dragging, spring = $spring
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            timer.invalidate()
            MainActor.assumeIsolated {
                spring.wrappedValue?.cancel()
                spring.wrappedValue = nil
                aimed.wrappedValue = nil
                dragging.wrappedValue = nil
            }
        }
    }

    private func land(_ zone: BookmarkDrop.Zone, over target: Bookmark.ID?, _ providers: [NSItemProvider]) -> Bool {
        aim(nil)
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: String.self) }) else { return false }
        _ = provider.loadObject(ofClass: String.self) { text, _ in
            guard let text, let id = UUID(uuidString: text) else { return }
            DispatchQueue.main.async {
                self.put(id, over: target, zone)
                self.dragging = nil
            }
        }
        return true
    }

    /// The move a drop asks for, if it is one (BookmarkDrop.landing).
    private func put(_ id: Bookmark.ID, over target: Bookmark.ID?, _ zone: BookmarkDrop.Zone) {
        guard let found = BookmarkDrop.landing(of: id, over: target, zone, in: bookmarks.roots) else { return }
        withAnimation(Motion.settle) { bookmarks.move(id, into: found.landing.parent, at: found.landing.index) }
    }

    /// Takes a drop on a row or a tile: which part of it the pointer is
    /// over says where, and that is only known against its size, so it is
    /// measured.
    private struct TakesDrop: ViewModifier {
        /// Side by side, as tiles are: before is to the left. Rows are one
        /// over the other.
        let across: Bool
        let folder: Bool
        /// False for a row of the tree, which only takes things in.
        let edges: Bool
        let settle: (BookmarkDrop.Zone) -> BookmarkDrop.Zone?
        let aim: (BookmarkDrop.Zone?) -> Void
        let land: (BookmarkDrop.Zone, [NSItemProvider]) -> Bool

        @State private var size = CGSize(width: 1, height: 1)

        func body(content: Content) -> some View {
            content
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { size = CGSize(width: max($0.width, 1), height: max($0.height, 1)) }
                .onDrop(of: [.text], delegate: Spot(landing: self))
        }

        func zone(at point: CGPoint) -> BookmarkDrop.Zone {
            guard edges else { return .into }
            return BookmarkDrop.zone(at: across ? point.x / size.width : point.y / size.height, folder: folder)
        }

        private struct Spot: DropDelegate {
            let landing: TakesDrop

            func dropUpdated(info: DropInfo) -> DropProposal? {
                guard let zone = landing.settle(landing.zone(at: info.location)) else {
                    landing.aim(nil)
                    return DropProposal(operation: .forbidden)
                }
                landing.aim(zone)
                return DropProposal(operation: .move)
            }

            func dropExited(info: DropInfo) { landing.aim(nil) }

            func performDrop(info: DropInfo) -> Bool {
                let zone = landing.zone(at: info.location)
                guard landing.settle(zone) != nil else { return false }
                return landing.land(zone, info.itemProviders(for: [.text]))
            }
        }
    }

    /// Where what is carried would go: a thin line in the Mac's accent, as
    /// a pin's is (PinFolderMark), lying between two rows or standing
    /// between two tiles.
    private struct DropLine: View {
        var upright = false

        var body: some View {
            Capsule()
                .fill(Color.accentColor)
                .frame(width: upright ? 2 : nil, height: upright ? nil : 2)
                .allowsHitTesting(false)
        }
    }

    /// The line for `aim` on a tile, in the gap beside it.
    private struct TileLine: ViewModifier {
        let aim: BookmarkDrop.Zone?

        func body(content: Content) -> some View {
            content.overlay(alignment: aim == .before ? .leading : .trailing) {
                if aim == .before || aim == .after {
                    DropLine(upright: true)
                        .padding(.vertical, 4)
                        .offset(x: aim == .before ? -6 : 6)
                }
            }
        }
    }

    /// A folder inside the one shown: pressed, it is the one shown.
    private struct FolderTile: View {
        let node: Bookmark
        let dragging: Bool
        let aim: BookmarkDrop.Zone?
        let open: () -> Void

        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            Button(action: open) {
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.soft)
                        .frame(width: 18)
                    Text(node.title)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Bookmarks.count(node.children ?? []).formatted())
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(hovering || aim == .into ? Palette.fillHover : Palette.fill, in: shape)
                .overlay { if aim == .into { shape.strokeBorder(Palette.drop, lineWidth: 1) } }
                .contentShape(shape)
            }
            .buttonStyle(Gives(to: 0.98))
            .hovers($hovering)
            .opacity(dragging ? 0.35 : 1)
            .modifier(TileLine(aim: aim))
            .accessibilityLabel("\(node.title), folder")
            .animation(Motion.quick, value: aim)
            .animation(Motion.quick, value: dragging)
        }
    }

    /// One bookmark in the table: what it is called, then where it goes.
    private struct BookmarkLine: View {
        let node: Bookmark
        /// How wide the address's column is; nil with no room for one.
        let address: CGFloat?
        let dragging: Bool
        let aim: BookmarkDrop.Zone?
        let shown: Bool
        let open: () -> Void

        var body: some View {
            if Store.testing { Bench.bodies["bookmarkLine", default: 0] += 1 }
            return RowButton(action: open) {
                HStack(spacing: 12) {
                    Mark(icon: Favicons.shared.cached(for: node.address), letter: "", size: 16, globe: true)
                    // One without a name reads as its address, a shade lighter.
                    Text(node.label)
                        .font(.system(size: 13))
                        .foregroundStyle(node.unnamed ? Palette.muted : Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    if let address {
                        Text(node.address.map(Address.pretty) ?? node.url ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: address, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 40)
            }
            .background {
                if shown {
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .fill(Palette.fillHover)
                        .padding(.horizontal, RowButton<EmptyView, EmptyView>.inset)
                        .padding(.vertical, 2)
                }
            }
            .overlay(alignment: aim == .before ? .top : .bottom) {
                if aim == .before || aim == .after {
                    DropLine()
                        .padding(.horizontal, 16)
                        .offset(y: aim == .before ? -1 : 1)
                }
            }
            .opacity(dragging ? 0.35 : 1)
            .animation(Motion.quick, value: aim)
            .animation(Motion.quick, value: dragging)
            .animation(Motion.settle, value: shown)
        }
    }

    /// One bookmark in the grid: its icon over its name and its site.
    private struct BookmarkTile: View {
        let node: Bookmark
        let dragging: Bool
        let aim: BookmarkDrop.Zone?
        let shown: Bool
        let open: () -> Void

        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            Button(action: open) {
                VStack(alignment: .leading, spacing: 12) {
                    Mark(icon: Favicons.shared.cached(for: node.address), letter: "", size: 24, globe: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(node.label)
                            .font(.system(size: 13))
                            .foregroundStyle(node.unnamed ? Palette.muted : Palette.ink)
                            .lineLimit(1)
                        Text(node.host.map(Address.withoutWWW) ?? node.url ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hovering || shown ? Palette.fillHover : Palette.fill, in: shape)
                .contentShape(shape)
            }
            .buttonStyle(Gives(to: 0.98))
            .hovers($hovering)
            .opacity(dragging ? 0.35 : 1)
            .modifier(TileLine(aim: aim))
            .animation(Motion.quick, value: aim)
            .animation(Motion.quick, value: dragging)
            .animation(Motion.settle, value: shown)
        }
    }

    // MARK: - searching

    /// What the search finds, flat, each with the folders it is in. Nothing
    /// here is dragged: it is put in order in its folder.
    @ViewBuilder
    private var found: some View {
        let hits = bookmarks.matches(query)
        if hits.isEmpty {
            Card { Nothing("Nothing matches.") }
        } else {
            ScrollView {
                Card {
                    ForEach(Array(hits.enumerated()), id: \.element.node.id) { index, hit in
                        if index > 0 { Rule(inset: 40) }
                        Found(
                            node: hit.node,
                            path: hit.path,
                            open: hit.node.url.flatMap(URL.init(string:)).map { url in { browser.pickBookmark(url) } },
                            show: { show(hit.node) }
                        )
                    }
                }
                .padding(.bottom, 2)
            }
            .listHeight(440)
        }
    }

    /// Return in the field: the first site found.
    private func openFirst() {
        guard let url = bookmarks.matches(query).lazy.compactMap({ $0.node.url.flatMap(URL.init(string:)) }).first
        else { return }
        browser.pickBookmark(url)
    }

    /// Back to the folders, at the one it is in, and it washed a moment. A
    /// folder is shown itself.
    private func show(_ node: Bookmark) {
        query = ""
        guard !node.isFolder else { return pick(node.id) }
        pick(bookmarks.parent(of: node.id))
        shown = node.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if shown == node.id { withAnimation(Motion.settle) { shown = nil } }
        }
    }

    /// One line of what was found: its title, then where it is.
    private struct Found: View {
        let node: Bookmark
        let path: [String]
        /// Nil for a folder, which is shown beside the tree instead.
        let open: (() -> Void)?
        let show: () -> Void

        @State private var hovering = false

        var body: some View {
            RowButton(hovering: $hovering, action: { open?() ?? show() }) {
                HStack(spacing: 10) {
                    if node.isFolder {
                        Mark(icon: nil, letter: "", size: 16)
                            .overlay(Image(systemName: "folder.fill").font(.system(size: 9.5)).foregroundStyle(Palette.muted))
                    } else {
                        Mark(icon: Favicons.shared.cached(for: node.address), letter: "", size: 16, globe: true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.label)
                            .font(.system(size: 13))
                            .foregroundStyle(node.unnamed ? Palette.muted : Palette.ink)
                            .lineLimit(1)
                        Text(whereabouts)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.leading, 14)
                .padding(.trailing, hovering ? 0 : 14)
                .padding(.vertical, 9)
            } trailing: {
                if hovering {
                    Quick("Show in Folder", act: show)
                        .padding(.leading, 10)
                        .padding(.trailing, 14)
                }
            }
            .contextMenu {
                if let open { Button("Open", action: open) }
                Button("Show in Folder", action: show)
            }
        }

        /// The folders it is in, then the site.
        private var whereabouts: String {
            let folders = path.isEmpty ? "Top level" : path.joined(separator: " \u{203A} ")
            guard let host = node.host else { return folders }
            return folders + "  \u{00B7}  " + host
        }
    }

    // MARK: - for the bench

    /// What a hand does on the page, asked for by the bench in its place
    /// (Tests/bookmarks_page.py): a folder picked, the layout chosen, words
    /// typed in the search box, and something let go over a row or a tile.
    /// `held` is a drag stopped on its way, for a picture of where it would
    /// land: nil lets go of it. Only a test run sends one.
    enum Asked {
        case pick(Bookmark.ID?)
        case layout(BookmarksLayout)
        case find(String)
        case drop(Bookmark.ID, over: Bookmark.ID?, BookmarkDrop.Zone)
        case show(Bookmark.ID)
        case held(Bookmark.ID?, over: Bookmark.ID?, BookmarkDrop.Zone, tree: Bool)
    }

    static let bench = PassthroughSubject<Asked, Never>()

    /// What the page beside the tree last drew, for the bench to read.
    static var benchShows: [String: Any] = [:]

    private func answer(_ asked: Asked) {
        switch asked {
        case .pick(let id): pick(id)
        case .layout(let now): layout = now
        case .find(let words):
            query = words
            Self.benchShows["found"] = bookmarks.matches(words).map(\.node.label)
        case .drop(let id, let target, let zone): put(id, over: target, zone)
        case .show(let id): if let node = bookmarks.bookmark(id) { show(node) }
        case .held(let id, let target, let zone, let tree):
            dragging = id
            aimed = id.flatMap { _ in settle(zone, over: target) }.map { Aim(id: target, zone: $0, tree: tree) }
        }
    }
}
