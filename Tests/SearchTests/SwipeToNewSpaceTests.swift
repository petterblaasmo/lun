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
}
