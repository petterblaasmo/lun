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

    /// The stroke that brings the card (#246): the rows take 0.45 of it
    /// where they took 0.6, and the card comes where they stand as far from
    /// their place as before, so the fingers go a third further.
    func testTheCardTakesAStrokeAThirdLonger() {
        let enough: CGFloat = 50  // the column's
        XCTAssertEqual(SpaceSwipe.cardWeight, 0.45)
        XCTAssertEqual(SpaceSwipe.cardReach(enough), 60, "where the rows stood at twice enough, at 0.6")
        XCTAssertEqual(SpaceSwipe.cardProgress(travel: 0, enough: enough), 0)
        XCTAssertEqual(SpaceSwipe.cardProgress(travel: -100, enough: enough), 0.75, accuracy: 0.0001,
                       "the stroke that brought the card before is three quarters of the way")
        XCTAssertLessThan(SpaceSwipe.cardProgress(travel: -133, enough: enough), 1)
        XCTAssertEqual(SpaceSwipe.cardProgress(travel: -134, enough: enough), 1, "133 and a third points of the fingers'")
        XCTAssertEqual(SpaceSwipe.cardProgress(travel: -400, enough: enough), 1, "and no further than closed")
        // In the bar across the top the same share of its shorter stroke.
        XCTAssertEqual(SpaceSwipe.cardProgress(travel: -2 * 26.4, enough: 26.4), 0.75, accuracy: 0.0001)
        XCTAssertEqual(SpaceSwipe.cardProgress(travel: -50, enough: 0), 0)
    }

    /// One tap each time the ring closes: none while it stays closed, and
    /// one more once the fingers have turned back and closed it again.
    func testTheTapComesOncePerArming() {
        var arming = CardArming()
        let strokes: [CGFloat] = [0, 0.3, 0.99, 1, 1, 1, 0.8, 0.99, 1, 1, 0, 1]
        let taps = strokes.map { arming.closes(at: $0) }
        XCTAssertEqual(taps, [false, false, false, true, false, false, false, false, true, false, false, true])
        XCTAssertTrue(arming.armed)
        XCTAssertFalse(arming.closes(at: 0.5))
        XCTAssertFalse(arming.armed)
    }

    /// The gesture itself, from the last space: what the disc is told, when
    /// the tap comes, and what letting go does on each side of the point.
    func testAStrokePastTheLastSpaceArmsTapsAndBringsTheCard() throws {
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        browser.prefs.usesSpaces = true
        browser.prefs.sidebar = true
        while browser.spaces.count < 2 { browser.addSpace(named: "Other") }
        browser.switchSpace(to: try XCTUnwrap(browser.spaces.last).id)
        // Nothing glides: what letting go does is done at once.
        Motion.testReduceMotion = true
        defer { Motion.testReduceMotion = nil }
        let swipe = SpaceSwipe.shared
        swipe.start(for: browser)
        var taps = 0
        let tap = swipe.tap
        swipe.tap = { taps += 1 }
        defer {
            swipe.tap = tap
            browser.cancelSpaceCreation()
            browser.makingSpace = false
            browser.spaceSwipe = 0
        }
        let pull = browser.cardPull

        // 120 points toward the card, which brought it before: not now.
        swipe.began()
        for _ in 0..<12 { swipe.moved(along: -10) }
        XCTAssertEqual(pull.progress, 0.9, accuracy: 0.0001)
        XCTAssertEqual(browser.spaceSwipe, -120 * SpaceSwipe.cardWeight, accuracy: 0.0001, "the rows go heavily")
        XCTAssertEqual(taps, 0)
        swipe.ended()
        XCTAssertFalse(browser.makingSpace, "let go short of the point: no card")
        XCTAssertEqual(pull.progress, 0, "and the disc goes with the fingers")

        // Back toward the space before: as it was, and no disc.
        swipe.began()
        for _ in 0..<4 { swipe.moved(along: 10) }
        XCTAssertEqual(browser.spaceSwipe, 40, "between spaces the rows follow the fingers whole")
        XCTAssertEqual(pull.progress, 0)
        swipe.ended(cancelled: true)

        // To the point: a tap as the ring closes, none while it stays so,
        // one more for closing it again, and letting go brings the card.
        swipe.began()
        for _ in 0..<13 { swipe.moved(along: -10) }
        XCTAssertLessThan(pull.progress, 1)
        XCTAssertEqual(taps, 0)
        swipe.moved(along: -10)
        XCTAssertEqual(pull.progress, 1)
        XCTAssertEqual(taps, 1)
        swipe.moved(along: -10)
        XCTAssertEqual(taps, 1)
        swipe.moved(along: 40)
        XCTAssertLessThan(pull.progress, 1, "turned back: the ring unwinds")
        XCTAssertEqual(taps, 1)
        swipe.moved(along: -40)
        XCTAssertEqual(taps, 2)
        swipe.ended()
        XCTAssertTrue(browser.makingSpace, "let go closed: the card")
        XCTAssertEqual(pull.progress, 0)
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
