import XCTest
@testable import Search

/// A swipe past the last space brings the card for a new one, with only
/// one space as with several.
@MainActor
final class SwipeToNewSpaceTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    func testTheCardIsInReachWithOneSpace() {
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        browser.prefs.usesSpaces = true
        // One past the last space, however many there are: the test world
        // may hold more than one. It was the last space itself with one.
        XCTAssertEqual(SpaceSwipe.shared.furthest(browser), browser.spaces.count, "the card for a new space is in reach")
    }

    /// Carried to the card, the rows end a page to the left and are drawn
    /// there, not parked off to the right, where the animation took them.
    func testTheRowsAreNotParkedWhereTheCarryEnds() {
        let width: CGFloat = 248
        XCTAssertFalse(SwipeShift.parks(offset: -width, by: 0, park: width), "a page off: still the rows' own place")
        XCTAssertFalse(SwipeShift.parks(offset: -120, by: 0, park: width), "on their way")
        XCTAssertTrue(SwipeShift.parks(offset: 0, by: 0, park: width), "nothing moving: out of the way")
        XCTAssertTrue(SwipeShift.parks(offset: -120, by: 2 * width, park: width), "a space two along: out of the way")
    }
}
