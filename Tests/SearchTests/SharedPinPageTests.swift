import AppKit
import WebKit
import XCTest
@testable import Search

/// A pin kept in every space keeps one page in a window (Browser.pinPages):
/// which spaces it goes between and which keep a page of their own, what
/// each space has in front and in a pair afterwards, and where the page
/// goes when the space that has it is deleted. Without a window on screen.
@MainActor
final class SharedPinPageTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    private let home = URL(string: "about:blank#shared")!

    // MARK: - which spaces share the page

    func testThePageGoesWithYouBetweenSpacesSignedInTogether() throws {
        try withSharedPin { browser, pin in
            let first = browser.spaceID
            let second = addSpace("Second", to: browser)
            let web = pin.web

            browser.switchSpace(to: second.id)
            XCTAssertTrue(try tab(for: pin, in: browser) === pin, "The second space shows the first one's page")
            XCTAssertTrue(pin.built === web, "…the very same view, not one made again")
            let left = try XCTUnwrap(browser.parked[first]?.tabs.first { $0.pinID == pin.pinID })
            XCTAssertFalse(left === pin, "The first space keeps a tab for the pin")
            XCTAssertNil(left.built, "…with no page of its own")
            XCTAssertEqual(browser.sharedPinOwner, second.id)
            assertOneRowEach(browser)

            browser.switchSpace(to: first)
            XCTAssertTrue(try tab(for: pin, in: browser) === pin)
            XCTAssertTrue(pin.built === web)
            XCTAssertTrue(browser.parked[second.id]?.tabs.first { $0.pinID == pin.pinID } === left,
                          "The second space has its own tab back")
            XCTAssertEqual(browser.sharedPinOwner, first)
            assertOneRowEach(browser)
        }
    }

    func testASpaceWithItsOwnSignInsKeepsAPageOfItsOwn() throws {
        try withSharedPin { browser, pin in
            let first = browser.spaceID
            let apart = addSpace("Apart", to: browser, sharesSignIns: false)
            let second = addSpace("Second", to: browser)
            let web = pin.web
            XCTAssertTrue(browser.sharesPinPages(in: first))
            XCTAssertTrue(browser.sharesPinPages(in: second.id))
            XCTAssertFalse(browser.sharesPinPages(in: apart.id))

            browser.switchSpace(to: apart.id)
            let theirs = try tab(for: pin, in: browser)
            XCTAssertFalse(theirs === pin, "Its own tab for the pin")
            XCTAssertFalse(theirs.store === pin.store, "…in its own store")
            XCTAssertTrue(browser.parked[first]?.tabs.contains { $0 === pin } == true, "The page stayed where it was")
            XCTAssertTrue(pin.built === web, "…and runs on there")
            XCTAssertEqual(browser.sharedPinOwner, first)

            // On from there to a space signed in with the first: the page
            // comes from the first, past the one that keeps its own.
            browser.switchSpace(to: second.id)
            XCTAssertTrue(try tab(for: pin, in: browser) === pin)
            XCTAssertTrue(pin.built === web)
            XCTAssertTrue(browser.parked[apart.id]?.tabs.contains { $0 === theirs } == true)
            XCTAssertEqual(browser.sharedPinOwner, second.id)

            browser.switchSpace(to: apart.id)
            XCTAssertTrue(try tab(for: pin, in: browser) === theirs, "Back to its own, untouched")
            XCTAssertTrue(theirs.store === Spaces.store(for: apart.id))
            assertOneRowEach(browser)
        }
    }

    func testASpaceOfAnotherProfileNeverSharesThePage() throws {
        try withSharedPin { browser, _ in
            let other = Space(id: UUID(), name: "Work", colour: 1, sharesSignIns: true, profile: UUID())
            Spaces.known[other.id] = other
            defer { Spaces.known[other.id] = nil }
            XCTAssertFalse(browser.sharesPinPages(in: other.id), "Signed in with its own profile, not this window's")
            XCTAssertFalse(browser.sharesPinPages(in: UUID()), "Nor a space nobody knows")
        }
    }

    /// The spaces' say is not taken alone: a tab only takes the place of one
    /// in the same store, and a space with its own sign-ins keeps its tab
    /// even if that tab were found in the profile's store.
    func testThePageOnlyReplacesATabInItsOwnStore() throws {
        try withSharedPin { browser, pin in
            let first = browser.spaceID
            let second = addSpace("Second", to: browser)
            let apart = addSpace("Apart", to: browser, sharesSignIns: false)
            _ = pin.web

            // Signed in together by the list, but its tab is in another store.
            let stray = stand(in: Web.configuration(store: .nonPersistent()), for: pin, in: browser)
            browser.parked[second.id] = Parked(tabs: [stray], active: stray.id)
            browser.showAhead(second.id)
            XCTAssertTrue(browser.pageAhead === stray)
            browser.pageAhead = nil
            browser.switchSpace(to: second.id)
            XCTAssertTrue(browser.active === stray, "A tab in another store keeps its place")
            browser.switchSpace(to: first)
            XCTAssertTrue(browser.active === pin)

            // Apart by the list, but its tab is in the profile's store.
            let same = stand(in: Web.configuration(store: pin.store), for: pin, in: browser)
            XCTAssertTrue(same.store === pin.store)
            browser.parked[apart.id] = Parked(tabs: [same], active: same.id)
            browser.showAhead(apart.id)
            XCTAssertTrue(browser.pageAhead === same)
            browser.pageAhead = nil
            browser.switchSpace(to: apart.id)
            XCTAssertTrue(browser.active === same, "A space with its own sign-ins keeps its tab whatever its store")
            browser.switchSpace(to: first)
            XCTAssertTrue(browser.active === pin)
            assertOneRowEach(browser)
        }
    }

    // MARK: - what each space has in front

    func testEachSpaceKeepsWhatItHadInFront() throws {
        try withSharedPin { browser, pin in
            let first = browser.spaceID
            let second = addSpace("Second", to: browser)
            let third = addSpace("Third", to: browser)
            let web = pin.web
            XCTAssertTrue(browser.active === pin)

            // A space never gone to, with nothing of its own: an empty tab
            // in front, as before, and the page beside it.
            browser.switchSpace(to: second.id)
            XCTAssertEqual(browser.active?.isBlank, true)
            XCTAssertTrue(try tab(for: pin, in: browser) === pin)
            XCTAssertEqual(browser.parked[first]?.active, browser.parked[first]?.tabs.first { $0.pinID == pin.pinID }?.id,
                           "The first space still has the pin in front, under its own tab for it")

            // One read ahead of the visit opens on its first pin, as before:
            // that is the page now.
            browser.parked[third.id] = browser.loadRow(third.id)
            browser.showAhead(third.id)
            XCTAssertTrue(browser.pageAhead === pin, "The page that comes along is the one shown ahead")
            browser.pageAhead = nil
            browser.switchSpace(to: third.id)
            XCTAssertTrue(browser.active === pin)
            XCTAssertTrue(pin.built === web)

            browser.switchSpace(to: second.id)
            XCTAssertEqual(browser.active?.isBlank, true, "The second space is back on its empty tab")
            XCTAssertTrue(try tab(for: pin, in: browser) === pin)
            browser.switchSpace(to: first)
            XCTAssertTrue(browser.active === pin, "The first space is back on the pin")
            XCTAssertTrue(pin.built === web)
            assertOneRowEach(browser)
        }
    }

    func testReplacingARowsTabKeepsItInFrontAndInItsPair() {
        let (pin, loose, page) = (Tab(), Tab(), Tab())
        defer { [pin, loose, page].forEach { $0.close() } }

        var row = Parked(tabs: [pin, loose], active: pin.id, splits: [TabSplit(left: pin.id, right: loose.id)])
        row.replaceTab(at: 0, with: page)
        XCTAssertTrue(row.tabs[0] === page)
        XCTAssertTrue(row.tabs[1] === loose)
        XCTAssertEqual(row.active, page.id)
        XCTAssertEqual(row.splits.first?.tabs, [page.id, loose.id])

        var behind = Parked(tabs: [pin, loose], active: loose.id)
        behind.replaceTab(at: 0, with: page)
        XCTAssertEqual(behind.active, loose.id, "Another tab in front stays in front")
        XCTAssertTrue(behind.splits.isEmpty)
    }

    func testAPairWithThePinHoldsInEachSpace() throws {
        try withSharedPin { browser, pin in
            let first = browser.spaceID
            let second = addSpace("Second", to: browser)
            browser.newTab()
            let beside = try XCTUnwrap(browser.active)
            XCTAssertFalse(beside === pin)
            browser.showRow(browser.tabs, active: pin.id, splits: [TabSplit(left: pin.id, right: beside.id)])

            browser.switchSpace(to: second.id)
            XCTAssertTrue(browser.splits.isEmpty, "The second space has no pair of its own")
            let left = try XCTUnwrap(browser.parked[first]?.tabs.first { $0.pinID == pin.pinID })
            XCTAssertEqual(browser.parked[first]?.splits.first?.tabs, [left.id, beside.id],
                           "The first space's pair holds its own tab for the pin meanwhile")

            browser.switchSpace(to: first)
            XCTAssertEqual(browser.splits.first?.tabs, [pin.id, beside.id], "…and the page again once back")
        }
    }

    /// Float a video when you leave its tab: the page in front here and in
    /// front there too never leaves the screen, so nothing is asked of it;
    /// with another tab in front there, its video is asked for as before.
    func testAVideoStaysInAPageThatStaysInFront() throws {
        try withSharedPin { browser, pin in
            let second = addSpace("Second", to: browser)
            let third = addSpace("Third", to: browser)
            let floats = browser.prefs.floatsOnLeave
            defer {
                if let pending = browser.spaceFloat.pending { browser.spaceFloat.finish(pending) }
                browser.prefs.floatsOnLeave = floats
            }
            browser.prefs.floatsOnLeave = true
            _ = pin.web
            pin.playingVideo = true

            // Read ahead of the visit, it opens on its first pin.
            browser.parked[second.id] = browser.loadRow(second.id)
            browser.switchSpace(to: second.id)
            XCTAssertTrue(browser.active === pin)
            XCTAssertNil(browser.spaceFloat.pending, "In front in both: its video isn't asked to float")

            browser.switchSpace(to: third.id)
            XCTAssertEqual(browser.active?.isBlank, true)
            XCTAssertNotNil(browser.spaceFloat.pending, "Behind another tab there: asked, as on leaving any space")
        }
    }

    // MARK: - asleep and awake

    func testAPageAsleepGoesAlongAsleep() throws {
        try withSharedPin { browser, pin in
            let second = addSpace("Second", to: browser)
            browser.newTab()
            pin.rest()
            XCTAssertNil(pin.built)

            browser.parked[second.id] = browser.loadRow(second.id)
            browser.parked[second.id]?.active = nil
            browser.switchSpace(to: second.id)
            XCTAssertTrue(try tab(for: pin, in: browser) === pin)
            XCTAssertNil(pin.built, "Nothing wakes a pin that isn't in front")
            XCTAssertTrue(pin.asleep)
        }
    }

    /// A page of the pin opened in a parked row while the space that has
    /// the pin has it asleep (an extension's tabs.update, a script) is the
    /// one kept: the page that is running isn't put down for one that isn't.
    func testAnOpenPageIsNotGivenUpForOneAsleep() throws {
        try withSharedPin { browser, pin in
            let first = browser.spaceID
            let second = addSpace("Second", to: browser)
            pin.rest()
            XCTAssertNil(pin.built)

            browser.parked[second.id] = browser.loadRow(second.id)
            let theirs = try XCTUnwrap(browser.parked[second.id]?.tabs.first { $0.pinID == pin.pinID })
            XCTAssertFalse(theirs === pin)
            theirs.wake()
            XCTAssertNotNil(theirs.built)

            browser.switchSpace(to: second.id)
            XCTAssertTrue(try tab(for: pin, in: browser) === theirs, "The second space keeps the page it has open")
            XCTAssertNotNil(theirs.built)
            XCTAssertNil(pin.built)

            // That page is the pin's from here on, and goes back with you.
            browser.switchSpace(to: first)
            XCTAssertTrue(try tab(for: pin, in: browser) === theirs)
            XCTAssertNotNil(theirs.built)
            assertOneRowEach(browser)
        }
    }

    /// Two pages open for the pin: the one that comes along is kept, and
    /// the one it replaces is put to sleep rather than left running in a
    /// row it never comes on screen from.
    func testASecondOpenPageIsPutToSleep() throws {
        try withSharedPin { browser, pin in
            let first = browser.spaceID
            let second = addSpace("Second", to: browser)
            let web = pin.web

            browser.parked[second.id] = browser.loadRow(second.id)
            let theirs = try XCTUnwrap(browser.parked[second.id]?.tabs.first { $0.pinID == pin.pinID })
            theirs.wake()
            XCTAssertNotNil(theirs.built)

            browser.switchSpace(to: second.id)
            XCTAssertTrue(try tab(for: pin, in: browser) === pin)
            XCTAssertTrue(pin.built === web)
            XCTAssertNil(theirs.built, "The other page is asleep")
            XCTAssertTrue(theirs.asleep, "…not closed: it has its address")
            XCTAssertTrue(browser.parked[first]?.tabs.contains { $0 === theirs } == true)
        }
    }

    // MARK: - a space deleted

    /// With a space of its own sign-ins on screen, the page is in the row of
    /// the last space that shared it. That row gone, the page goes to a
    /// space that stays, still open.
    func testDeletingTheSpaceThatHasThePageHandsItOn() throws {
        try withSharedPin { browser, pin in
            let first = browser.spaceID
            let second = addSpace("Second", to: browser)
            let apart = addSpace("Apart", to: browser, sharesSignIns: false)
            let web = pin.web
            browser.switchSpace(to: second.id)
            browser.switchSpace(to: apart.id)
            XCTAssertEqual(browser.sharedPinOwner, second.id)
            XCTAssertTrue(browser.parked[second.id]?.tabs.contains { $0 === pin } == true)
            let left = try XCTUnwrap(browser.parked[first]?.tabs.first { $0.pinID == pin.pinID })

            browser.forget(space: second.id)
            XCTAssertNil(browser.parked[second.id])
            XCTAssertEqual(browser.sharedPinOwner, first)
            XCTAssertTrue(browser.parked[first]?.tabs.contains { $0 === pin } == true, "The page is the first space's now")
            XCTAssertTrue(pin.built === web, "…and was never closed")
            XCTAssertFalse(browser.parkedTabs.contains { $0 === left }, "The tab it replaced went with the deleted row")
            assertOneRowEach(browser)

            browser.switchSpace(to: first)
            XCTAssertTrue(try tab(for: pin, in: browser) === pin)
            XCTAssertTrue(pin.built === web)
        }
    }

    func testDeletingTheLastSpaceThatSharedThePageLeavesNobodyHoldingIt() throws {
        try withSharedPin { browser, pin in
            let first = browser.spaceID
            let apart = addSpace("Apart", to: browser, sharesSignIns: false)
            _ = pin.web
            browser.switchSpace(to: apart.id)
            XCTAssertEqual(browser.sharedPinOwner, first)
            let theirs = try tab(for: pin, in: browser)

            browser.forget(space: first)
            XCTAssertNil(browser.sharedPinOwner)
            XCTAssertNil(browser.parked[first])
            XCTAssertTrue(try tab(for: pin, in: browser) === theirs, "The space on screen is as it was")
        }
    }

    /// Deleted in another window while this one shows it: the space is in
    /// no list by the time this window leaves it, and its page goes along
    /// all the same, by its tabs' store.
    func testAPageLeavesASpaceDeletedElsewhere() throws {
        try withSharedPin { browser, pin in
            let first = browser.spaceID
            let second = addSpace("Second", to: browser)
            let web = pin.web
            browser.switchSpace(to: second.id)
            XCTAssertTrue(try tab(for: pin, in: browser) === pin)

            Spaces.known[second.id] = nil
            browser.spaces.removeAll { $0.id == second.id }
            browser.enter(first)
            XCTAssertTrue(try tab(for: pin, in: browser) === pin)
            browser.forget(space: second.id)
            XCTAssertTrue(pin.built === web, "Its row gone, the page is still open in the first space")
            XCTAssertEqual(browser.sharedPinOwner, first)
        }
    }

    // MARK: - the pin changed

    func testOnlyInThisSpaceKeepsThePageWhereYouAre() throws {
        try withSharedPin { browser, pin in
            let first = browser.spaceID
            let second = addSpace("Second", to: browser)
            let web = pin.web
            browser.switchSpace(to: second.id)

            browser.keepHere(pin)
            XCTAssertFalse(pin.everywhere)
            XCTAssertTrue(browser.tabs.contains { $0 === pin })
            XCTAssertTrue(pin.built === web, "The page stays, this space's own pin")
            XCTAssertFalse(browser.parked[first]?.tabs.contains { $0.pinID == pin.pinID } == true,
                           "The first space let its tab for the pin go")

            browser.switchSpace(to: first)
            XCTAssertFalse(browser.tabs.contains { $0 === pin }, "A pin of one space goes nowhere")
            browser.switchSpace(to: second.id)
            XCTAssertTrue(browser.tabs.contains { $0 === pin })
            XCTAssertTrue(pin.built === web)
        }
    }

    func testASecondPinAndTheirOrderGoAlong() throws {
        try withSharedPin { browser, pin in
            let first = browser.spaceID
            let second = addSpace("Second", to: browser)
            browser.newTab()
            let other = try XCTUnwrap(browser.active)
            other.setAddressOptimistically(URL(string: "about:blank#other")!)
            browser.pin(other)
            browser.shareEverywhere(other)
            XCTAssertEqual(browser.tabs.filter(\.everywhere).map(\.id), [pin.id, other.id])

            browser.switchSpace(to: second.id)
            XCTAssertEqual(browser.tabs.filter(\.everywhere).map(\.id), [pin.id, other.id], "Both pages came, in their order")

            // Moved among the pins here: every row follows by the pin, and
            // the pages are still the ones that go back.
            browser.move(other, to: 0)
            browser.writeSession(now: true)
            XCTAssertEqual(browser.tabs.filter(\.everywhere).map(\.id), [other.id, pin.id])
            XCTAssertEqual(browser.parked[first]?.tabs.filter(\.everywhere).map(\.pinID), [other.pinID, pin.pinID])
            browser.switchSpace(to: first)
            XCTAssertEqual(browser.tabs.filter(\.everywhere).map(\.id), [other.id, pin.id])
            assertOneRowEach(browser)
        }
    }

    // MARK: - the session

    /// Nothing new is written: each space's row has one tab for the pin,
    /// as a build from before has it and expects it, and a window opened
    /// from those rows starts with the space on screen holding the page.
    func testEachRowIsWrittenWithItsOneTabForThePin() throws {
        let page = URL(string: "https://shared-pin-page.invalid/")!
        try withSharedPin(at: page) { browser, pin in
            let first = browser.spaceID
            let second = addSpace("Second", to: browser)
            browser.newTab()
            browser.parked[second.id] = browser.loadRow(second.id)
            browser.parked[second.id]?.active = nil
            browser.switchSpace(to: second.id)
            XCTAssertTrue(try tab(for: pin, in: browser) === pin)

            let rows = browser.allRows()
            for space in [first, second.id] {
                let entries = try XCTUnwrap(rows[space.uuidString]).tabs.filter { $0.pinID == pin.pinID }
                XCTAssertEqual(entries.count, 1, "One tab for the pin in each row")
                XCTAssertEqual(entries.first?.url, page.absoluteString)
            }
            let record = Browsers.record(of: browser, rows: true)
            let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]).keys
            XCTAssertTrue(Set(keys).isSubset(of: ["id", "space", "frame", "rows", "merge", "tucked", "folded"]),
                          "The window's line has nothing a build from before doesn't know: \(keys.sorted())")

            // Opened from those rows (its spaces are the file's: the first
            // alone), the space on screen is the one that has the page.
            let again = Browser(record: record)
            defer { again.closeAll() }
            XCTAssertEqual(again.spaceID, first)
            XCTAssertEqual(again.sharedPinOwner, first)
            XCTAssertEqual(again.tabs.filter { $0.pinID == pin.pinID }.count, 1)
        }
    }

    // MARK: - the scene

    /// A window with Spaces on and, in front in its first space, a pin every
    /// space shows, for `body`. Its rows are written to no file, and its pin
    /// and the spaces added to it are gone afterwards.
    private func withSharedPin(at address: URL? = nil, _ body: (Browser, Tab) throws -> Void) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        browser.leaveFiles()
        let prefs = browser.prefs
        let saved = prefs.usesSpaces
        prefs.usesSpaces = true
        let first = browser.spaceID
        let spaces = Set(browser.spaces.map(\.id))
        let pin = try XCTUnwrap(browser.active)
        pin.setAddressOptimistically(address ?? home)
        browser.pin(pin)
        browser.shareEverywhere(pin)
        XCTAssertTrue(pin.everywhere)
        defer {
            if browser.spaces.contains(where: { $0.id == first }) { browser.switchSpace(to: first) }
            for tab in browser.tabs where tab.pin != nil { browser.unpin(tab) }
            browser.closeAll()
            for space in browser.spaces where !spaces.contains(space.id) { Spaces.known[space.id] = nil }
            prefs.usesSpaces = saved
        }
        try body(browser, pin)
    }

    /// One more space for the window, signed in with its first unless told
    /// otherwise (withSharedPin forgets it again).
    private func addSpace(_ name: String, to browser: Browser, sharesSignIns: Bool = true) -> Space {
        let space = Space(id: UUID(), name: name, colour: 1, sharesSignIns: sharesSignIns)
        Spaces.known[space.id] = space
        browser.spaces.append(space)
        return space
    }

    /// A tab for `pin` as another row would have it, made with `configuration`.
    private func stand(in configuration: WKWebViewConfiguration, for pin: Tab, in browser: Browser) -> Tab {
        let tab = Tab(configuration: configuration)
        browser.prepare(tab)
        tab.setAddressOptimistically(home)
        tab.pin = pin.pin
        tab.pinID = pin.pinID
        tab.home = home
        tab.everywhere = true
        return tab
    }

    /// The tab the row on screen has for `pin`.
    private func tab(for pin: Tab, in browser: Browser) throws -> Tab {
        try XCTUnwrap(browser.tabs.first { $0.pinID == pin.pinID })
    }

    /// Every tab in one row only, and one tab for each shared pin in a row.
    private func assertOneRowEach(_ browser: Browser, file: StaticString = #filePath, line: UInt = #line) {
        let all = browser.tabs + browser.parkedTabs
        XCTAssertEqual(Set(all.map(ObjectIdentifier.init)).count, all.count, "A tab is in two rows", file: file, line: line)
        for row in [browser.tabs] + browser.parked.values.map(\.tabs) {
            let pins = row.filter(\.everywhere).compactMap(\.pinID)
            XCTAssertEqual(Set(pins).count, pins.count, "A row has two tabs for one pin", file: file, line: line)
        }
    }
}
