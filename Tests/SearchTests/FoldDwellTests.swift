import AppKit
import XCTest
@testable import Search

/// With the tabs across the top and hidden, the strip waited 0.15 s on its
/// edge where a column hidden for good waits 0.05 s, and was felt as slow
/// (idea 1253). Both wait the same now; the strip's edge, which is also the
/// way to the menu bar, starts its wait again while the pointer still rises.
final class FoldDwellTests: XCTestCase {
    func testOnlyTheColumnInFrontTrustsThePointersPosition() {
        XCTAssertTrue(Fold.frontColumn(sidebar: true, key: true, main: false))
        XCTAssertTrue(Fold.frontColumn(sidebar: true, key: false, main: true))
        XCTAssertFalse(Fold.frontColumn(sidebar: true, key: false, main: false))
        XCTAssertFalse(Fold.frontColumn(sidebar: false, key: true, main: true))
    }

    func testTheStripWaitsNoLongerThanTheColumn() {
        XCTAssertEqual(Fold.dwell, 0.05, accuracy: 0.0001)
    }

    func testAPointerStillRisingIsOnItsWayToTheMenuBar() {
        // Window coordinates, y up: from 2 points under the top to 1.
        XCTAssertTrue(Fold.rising(from: NSPoint(x: 400, y: 797), to: NSPoint(x: 402, y: 799)))
    }

    func testAPointerAtRestOrAlongTheEdgeWaitsOutTheDwell() {
        // Pinned against the screen's top, it can't rise any further.
        XCTAssertFalse(Fold.rising(from: NSPoint(x: 400, y: 799), to: NSPoint(x: 400, y: 799)))
        // Along the edge, or settling back down onto it.
        XCTAssertFalse(Fold.rising(from: NSPoint(x: 400, y: 798), to: NSPoint(x: 460, y: 798)))
        XCTAssertFalse(Fold.rising(from: NSPoint(x: 400, y: 799), to: NSPoint(x: 400, y: 797)))
        // The first sample has nothing before it.
        XCTAssertFalse(Fold.rising(from: nil, to: NSPoint(x: 400, y: 799)))
    }

    /// Out over the page, the column went the moment the pointer was past
    /// its width: a few points too far, aiming at a row's close button, and
    /// it slid away. Once the pointer has been on it, a little past its
    /// edge still is; coming from the page, only the column itself is.
    func testAColumnThePointerWasOnForgivesASmallOvershoot() {
        let reach: CGFloat = 248
        XCTAssertEqual(Metrics.columnSlack, 24)
        XCTAssertTrue(Fold.onColumn(distance: reach - 1, reach: reach, was: false), "on it")
        XCTAssertTrue(Fold.onColumn(distance: reach - 1, reach: reach, was: true))
        XCTAssertTrue(Fold.onColumn(distance: reach + 10, reach: reach, was: true), "a few points past its edge, once on it")
        XCTAssertFalse(Fold.onColumn(distance: reach + 30, reach: reach, was: true), "well past it: it goes")
        XCTAssertFalse(Fold.onColumn(distance: reach + 10, reach: reach, was: false), "never brought or kept from the page")
        // The slack ends where it says.
        XCTAssertTrue(Fold.onColumn(distance: reach + Metrics.columnSlack - 0.5, reach: reach, was: true))
        XCTAssertFalse(Fold.onColumn(distance: reach + Metrics.columnSlack, reach: reach, was: true))
        XCTAssertFalse(Fold.onColumn(distance: reach, reach: reach, was: false), "at its width exactly, as before")
    }

    /// The edge is watched on drags too: a drag in the page that reached it
    /// (a selection, Airtable's own sidebar edge 6 points in) brought the
    /// column out over the page mid-drag. Not with the left button held.
    func testTheEdgeWaitsForTheButtonToBeLetGo() {
        XCTAssertTrue(Fold.edgeBrings(pressed: 0))
        XCTAssertFalse(Fold.edgeBrings(pressed: 1))
        XCTAssertFalse(Fold.edgeBrings(pressed: 1 | 4))
        // The right or middle button alone is no drag in the page.
        XCTAssertTrue(Fold.edgeBrings(pressed: 2))
        XCTAssertTrue(Fold.edgeBrings(pressed: 4))
    }

    /// Airtable's collapsed sidebar has its button 6–12 points in, inside
    /// the hidden column's 28-point band: resting there brought the column
    /// out over it and the click went to the column (idea 1308). Off the
    /// very edge, over something of the page's, only the edge itself does.
    func testTheBandIsThePagesWhereItHasSomethingToPress() {
        XCTAssertEqual(Fold.trueEdge, 4)
        XCTAssertLessThan(Fold.trueEdge, Fold.hiddenEdge)
        // The very edge always.
        XCTAssertEqual(Fold.edgeComes(distance: 0, pageHas: true), true)
        XCTAssertEqual(Fold.edgeComes(distance: 3.9, pageHas: nil), true)
        // Off it: over a button, never; over plain page, yes; not yet
        // answered, wait.
        XCTAssertEqual(Fold.edgeComes(distance: 8, pageHas: true), false)
        XCTAssertEqual(Fold.edgeComes(distance: 8, pageHas: false), true)
        XCTAssertNil(Fold.edgeComes(distance: 8, pageHas: nil))
        XCTAssertEqual(Fold.edgeComes(distance: 27, pageHas: false), true)
    }
}
