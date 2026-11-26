import XCTest
@testable import Search

/// The Bookmarks page (BookmarksPage.swift): where something carried lands,
/// worked out apart from the views, and that it reaches the list through
/// `Bookmarks.move` alone. The page shows a folder's folders apart from its
/// bookmarks, while the file keeps them in one list, so a place among the
/// bookmarks has to become a place among everything; and a folder must
/// never land inside itself. In the test world's own files, never the
/// bookmarks of whoever runs the tests.
@MainActor
final class BookmarksPageTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    private func site(_ name: String) -> Bookmark {
        .site(name, URL(string: "https://\(name).example/")!)
    }

    /// Norway as the page's board draws it, with a folder between two
    /// bookmarks in the file:
    ///
    ///     Travel
    ///       Norway
    ///         Lofoten        (folder, holds "deep" and the folder Reine)
    ///         a
    ///         Ferries        (folder)
    ///         b
    ///         c
    ///       Food             (folder)
    ///     top
    private struct Tree {
        var roots: [Bookmark]
        let travel, norway, lofoten, reine, ferries, food: Bookmark.ID
        let a, b, c, deep, top: Bookmark.ID
    }

    private func tree() -> Tree {
        let a = site("a"), b = site("b"), c = site("c"), deep = site("deep"), top = site("top")
        let reine = Bookmark.folder("Reine", [])
        let lofoten = Bookmark.folder("Lofoten", [deep, reine])
        let ferries = Bookmark.folder("Ferries", [])
        let norway = Bookmark.folder("Norway", [lofoten, a, ferries, b, c])
        let food = Bookmark.folder("Food", [])
        let travel = Bookmark.folder("Travel", [norway, food])
        return Tree(roots: [travel, top], travel: travel.id, norway: norway.id, lofoten: lofoten.id, reine: reine.id,
                    ferries: ferries.id, food: food.id, a: a.id, b: b.id, c: c.id, deep: deep.id, top: top.id)
    }

    private func landing(_ dragged: Bookmark.ID, _ target: Bookmark.ID?, _ zone: BookmarkDrop.Zone, _ t: Tree) -> BookmarkDrop.Landing? {
        BookmarkDrop.landing(of: dragged, over: target, zone, in: t.roots)?.landing
    }

    // MARK: - which part of a row

    func testARowHasTwoHalvesAndAFolderAMiddle() {
        XCTAssertEqual(BookmarkDrop.zone(at: 0.1, folder: false), .before)
        XCTAssertEqual(BookmarkDrop.zone(at: 0.49, folder: false), .before)
        XCTAssertEqual(BookmarkDrop.zone(at: 0.5, folder: false), .after)
        XCTAssertEqual(BookmarkDrop.zone(at: 0.9, folder: false), .after)
        XCTAssertEqual(BookmarkDrop.zone(at: 0.1, folder: true), .before)
        XCTAssertEqual(BookmarkDrop.zone(at: 0.25, folder: true), .into)
        XCTAssertEqual(BookmarkDrop.zone(at: 0.5, folder: true), .into)
        XCTAssertEqual(BookmarkDrop.zone(at: 0.75, folder: true), .into)
        XCTAssertEqual(BookmarkDrop.zone(at: 0.9, folder: true), .after)
    }

    // MARK: - the place among everything

    /// Norway holds Lofoten, a, Ferries, b, c: the table shows a, b, c.
    func testAPlaceAmongTheBookmarksIsAPlaceAmongEverything() {
        let t = tree()
        // c before a: a is second in the file, behind the folder Lofoten.
        XCTAssertEqual(landing(t.c, t.a, .before, t), .init(parent: t.norway, index: 1))
        // c after a: straight after it, ahead of the folder that follows.
        XCTAssertEqual(landing(t.c, t.a, .after, t), .init(parent: t.norway, index: 2))
        // a after c: the end.
        XCTAssertEqual(landing(t.a, t.c, .after, t), .init(parent: t.norway, index: 5))
        // a before c.
        XCTAssertEqual(landing(t.a, t.c, .before, t), .init(parent: t.norway, index: 4))
        // One from another folder, beside one here.
        XCTAssertEqual(landing(t.top, t.b, .before, t), .init(parent: t.norway, index: 3))
        XCTAssertEqual(landing(t.deep, t.top, .after, t), .init(parent: nil, index: 2))
    }

    func testAFolderGoesBesideAFolder() {
        let t = tree()
        XCTAssertEqual(landing(t.ferries, t.lofoten, .before, t), .init(parent: t.norway, index: 0))
        XCTAssertEqual(landing(t.lofoten, t.ferries, .after, t), .init(parent: t.norway, index: 3))
        XCTAssertEqual(landing(t.food, t.lofoten, .after, t), .init(parent: t.norway, index: 1))
    }

    /// Beside the neighbour it already stands beside nothing moves, though
    /// a folder lies between the two in the file: a and b are neighbours in
    /// the table, with Ferries between them.
    func testBesideItsOwnNeighbourIsNothingToDo() {
        let t = tree()
        XCTAssertNil(landing(t.a, t.b, .before, t))
        XCTAssertNil(landing(t.b, t.a, .after, t))
        XCTAssertNil(landing(t.b, t.c, .before, t))
        XCTAssertNil(landing(t.lofoten, t.ferries, .before, t))
        XCTAssertNil(landing(t.ferries, t.lofoten, .after, t))
        XCTAssertNil(landing(t.a, t.a, .before, t), "over itself")
        // The other side of its neighbour is a move.
        XCTAssertNotNil(landing(t.a, t.b, .after, t))
        XCTAssertNotNil(landing(t.b, t.a, .before, t))
    }

    // MARK: - onto a folder

    func testOntoAFolderGoesIntoIt() {
        let t = tree()
        XCTAssertEqual(landing(t.a, t.ferries, .into, t), .init(parent: t.ferries, index: nil))
        XCTAssertEqual(landing(t.top, t.norway, .into, t), .init(parent: t.norway, index: nil))
        XCTAssertEqual(landing(t.food, t.norway, .into, t), .init(parent: t.norway, index: nil))
        // The top level, which has no id.
        XCTAssertEqual(landing(t.a, nil, .into, t), .init(parent: nil, index: nil))
        XCTAssertEqual(landing(t.norway, nil, .before, t), .init(parent: nil, index: nil))
    }

    func testIntoTheFolderItIsInIsNothingToDo() {
        let t = tree()
        XCTAssertNil(landing(t.a, t.norway, .into, t))
        XCTAssertNil(landing(t.norway, t.travel, .into, t))
        XCTAssertNil(landing(t.top, nil, .into, t))
        XCTAssertNil(landing(t.travel, nil, .into, t))
    }

    /// The folders are shown apart from the bookmarks, so each goes beside
    /// its own kind: a bookmark over a folder's edge still goes into it.
    func testABookmarkOverAnyPartOfAFolderGoesIn() {
        let t = tree()
        for zone in [BookmarkDrop.Zone.before, .into, .after] {
            let found = BookmarkDrop.landing(of: t.a, over: t.ferries, zone, in: t.roots)
            XCTAssertEqual(found?.zone, .into)
            XCTAssertEqual(found?.landing, .init(parent: t.ferries, index: nil))
        }
        XCTAssertNil(landing(t.lofoten, t.b, .before, t), "a folder has no place among the bookmarks")
        XCTAssertNil(landing(t.lofoten, t.b, .after, t))
        XCTAssertNil(landing(t.a, t.b, .into, t), "a bookmark holds nothing")
    }

    // MARK: - the cycle guard

    func testAFolderNeverGoesIntoItselfOrWhatIsInsideIt() {
        let t = tree()
        XCTAssertNil(landing(t.norway, t.norway, .into, t), "itself")
        XCTAssertNil(landing(t.travel, t.norway, .into, t), "its child")
        XCTAssertNil(landing(t.travel, t.reine, .into, t), "three down")
        XCTAssertNil(landing(t.norway, t.lofoten, .into, t))
        // Beside something inside it would put it inside itself too.
        XCTAssertNil(landing(t.travel, t.food, .before, t))
        XCTAssertNil(landing(t.norway, t.ferries, .after, t))
        XCTAssertNil(landing(t.lofoten, t.reine, .before, t))
        // Out of a folder, and into one beside it, is fine.
        XCTAssertNotNil(landing(t.lofoten, t.food, .into, t))
        XCTAssertNotNil(landing(t.reine, t.norway, .into, t))
        XCTAssertNil(landing(UUID(), t.norway, .into, t), "not in the list at all")
        XCTAssertNil(landing(t.a, UUID(), .into, t))
    }

    // MARK: - through the list itself

    private func titles(_ nodes: [Bookmark]) -> [String] { nodes.map(\.title) }

    private func kids(_ id: Bookmark.ID, in list: Bookmarks) -> [String] {
        titles(list.bookmark(id)?.children ?? [])
    }

    /// The list in the test world, filled with the tree.
    private func list(_ t: Tree) -> Bookmarks {
        let list = Bookmarks(file: "bookmarks-page-\(UUID().uuidString).json")
        list.adopt(t.roots)
        return list
    }

    /// What a drop does on the page: the landing, then `move`.
    @discardableResult
    private func drop(_ dragged: Bookmark.ID, _ target: Bookmark.ID?, _ zone: BookmarkDrop.Zone, in list: Bookmarks) -> Bool {
        guard let found = BookmarkDrop.landing(of: dragged, over: target, zone, in: list.roots) else { return false }
        list.move(dragged, into: found.landing.parent, at: found.landing.index)
        return true
    }

    func testADropReordersThroughMove() {
        let t = tree()
        let list = list(t)
        defer { list.retire() }
        // Down: the place is counted before it leaves its own.
        drop(t.a, t.c, .before, in: list)
        XCTAssertEqual(kids(t.norway, in: list), ["Lofoten", "Ferries", "b", "a", "c"])
        drop(t.a, t.c, .after, in: list)
        XCTAssertEqual(kids(t.norway, in: list), ["Lofoten", "Ferries", "b", "c", "a"])
        // Up.
        drop(t.a, t.b, .before, in: list)
        XCTAssertEqual(kids(t.norway, in: list), ["Lofoten", "Ferries", "a", "b", "c"])
        // The folders among themselves, the bookmarks left as they are.
        drop(t.ferries, t.lofoten, .before, in: list)
        XCTAssertEqual(kids(t.norway, in: list), ["Ferries", "Lofoten", "a", "b", "c"])
        // Into a folder, and out to the top level.
        drop(t.b, t.ferries, .after, in: list)
        XCTAssertEqual(kids(t.norway, in: list), ["Ferries", "Lofoten", "a", "c"])
        XCTAssertEqual(kids(t.ferries, in: list), ["b"])
        drop(t.b, nil, .into, in: list)
        XCTAssertEqual(titles(list.roots), ["Travel", "top", "b"])
        drop(t.b, t.top, .before, in: list)
        XCTAssertEqual(titles(list.roots), ["Travel", "b", "top"])
        XCTAssertEqual(list.count, 5, "nothing lost, nothing made")
    }

    func testARefusedDropLeavesTheListAsItWas() {
        let t = tree()
        let list = list(t)
        defer { list.retire() }
        let before = list.roots
        XCTAssertFalse(drop(t.travel, t.reine, .into, in: list))
        XCTAssertFalse(drop(t.norway, t.norway, .into, in: list))
        XCTAssertFalse(drop(t.travel, t.food, .after, in: list))
        XCTAssertFalse(drop(t.a, t.b, .before, in: list))
        XCTAssertFalse(drop(t.lofoten, t.c, .after, in: list))
        XCTAssertEqual(list.roots, before)
        // And should a view ask anyway, the list itself refuses the loop.
        list.move(t.travel, into: t.reine)
        XCTAssertEqual(list.roots, before)
    }

    // MARK: - what the page draws from

    func testTheTreeIsTheFoldersAlone() {
        let t = tree()
        func shown(_ open: Set<Bookmark.ID>) -> [BookmarksPanel.Branch] {
            var out: [BookmarksPanel.Branch] = []
            BookmarksPanel.branches(t.roots, expanded: open, into: &out)
            return out
        }
        XCTAssertEqual(shown([]).map(\.node.title), ["Travel"])
        XCTAssertEqual(shown([]).first?.isOpen, false)
        let open = shown([t.travel, t.norway, t.food])
        XCTAssertEqual(open.map(\.node.title), ["Travel", "Norway", "Lofoten", "Ferries", "Food"])
        XCTAssertEqual(open.map(\.depth), [0, 1, 2, 2, 1])
        // An arrow only where there is a folder inside to open.
        XCTAssertEqual(open.map(\.isOpen), [true, true, false, nil, nil])
        // A folder inside a closed one doesn't show, open or not.
        XCTAssertEqual(shown([t.norway]).map(\.node.title), ["Travel"])
    }

    func testWhatAFolderHoldsInWords() {
        XCTAssertEqual(BookmarksPanel.summary(folders: 2, sites: 7), "2 folders, 7 bookmarks")
        XCTAssertEqual(BookmarksPanel.summary(folders: 1, sites: 1), "1 folder, 1 bookmark")
        XCTAssertEqual(BookmarksPanel.summary(folders: 0, sites: 3), "3 bookmarks")
        XCTAssertEqual(BookmarksPanel.summary(folders: 4, sites: 0), "4 folders")
        XCTAssertEqual(BookmarksPanel.summary(folders: 0, sites: 0), "Empty")
    }

    /// List or grid is a plain key in the test world's settings, a list
    /// until it is chosen otherwise.
    func testListOrGridIsRemembered() {
        let saved = Store.settings.object(forKey: BookmarksLayout.key)
        defer { Store.settings.set(saved, forKey: BookmarksLayout.key) }
        Store.settings.removeObject(forKey: BookmarksLayout.key)
        XCTAssertEqual(BookmarksLayout.kept, .list)
        BookmarksLayout.kept = .grid
        XCTAssertEqual(Store.settings.string(forKey: BookmarksLayout.key), "grid")
        XCTAssertEqual(BookmarksLayout.kept, .grid)
        Store.settings.set("columns", forKey: BookmarksLayout.key)
        XCTAssertEqual(BookmarksLayout.kept, .list, "a word it doesn't know is the list")
    }

    /// The page keeps nothing new about a bookmark: the file has the four
    /// things it had, and reads back the same.
    func testTheFileKeepsItsShape() throws {
        let t = tree()
        let data = try JSONEncoder().encode(t.roots)
        var keys = Set<String>()
        func walk(_ value: Any) {
            if let list = value as? [Any] { list.forEach(walk) }
            if let node = value as? [String: Any] {
                keys.formUnion(node.keys)
                node.values.forEach(walk)
            }
        }
        walk(try JSONSerialization.jsonObject(with: data))
        XCTAssertEqual(keys, ["id", "title", "url", "children"])
        XCTAssertEqual(try JSONDecoder().decode([Bookmark].self, from: data), t.roots)
    }
}
