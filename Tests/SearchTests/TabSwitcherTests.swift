import AppKit
import XCTest
@testable import Search

@MainActor
final class TabSwitcherTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    func testResetCancelsDelayedRevealAndDiscardsPictures() async throws {
        let switcher = TabSwitcher()
        let first = UUID(), second = UUID()
        let address = try XCTUnwrap(URL(string: "https://example.test"))
        switcher.step(row: [first, second], current: first, backwards: false)
        switcher.step(row: [first, second], current: first, backwards: false)
        switcher.cachePreview(NSImage(size: NSSize(width: 1, height: 1)), for: first, address: address)
        XCTAssertNotNil(switcher.preview(for: first, address: address))

        switcher.reset()
        XCTAssertNil(switcher.preview(for: first, address: address))
        // A result arriving after reset cannot repopulate the cache.
        switcher.cachePreview(NSImage(size: NSSize(width: 1, height: 1)), for: first, address: address)
        XCTAssertNil(switcher.preview(for: first, address: address))

        switcher.step(row: [first, second], current: first, backwards: false)
        switcher.reset()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(switcher.visible)
        XCTAssertFalse(switcher.active)
        XCTAssertNil(switcher.selectedID)
    }

    // MARK: the press

    /// A switcher up over three cards in a row, each where the window's
    /// monitor would find it. Two steps: the first only arms the reveal.
    private func up() -> (switcher: TabSwitcher, ids: [Tab.ID]) {
        let switcher = TabSwitcher()
        let ids = [UUID(), UUID(), UUID()]
        switcher.step(row: ids, current: ids[0], backwards: false)
        switcher.step(row: ids, current: ids[0], backwards: false)
        switcher.panelFrame = CGRect(x: 100, y: 100, width: 320, height: 120)
        for (index, id) in ids.enumerated() {
            switcher.cardFrames[id] = CGRect(x: 110 + CGFloat(index) * 100, y: 110, width: 90, height: 100)
        }
        return (switcher, ids)
    }

    private func middle(_ switcher: TabSwitcher, _ id: Tab.ID) -> CGPoint {
        let frame = switcher.cardFrames[id] ?? .zero
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// The button going down on a card picks it and holds it pressed, the
    /// switcher still up; the tab is taken when the button comes up on it.
    func testACardGivesUnderThePressAndIsTakenWhenLetGo() {
        let (switcher, ids) = up()
        XCTAssertTrue(switcher.visible)
        XCTAssertEqual(switcher.selectedID, ids[2])
        var taken: [Tab.ID] = []

        XCTAssertTrue(switcher.press(at: middle(switcher, ids[1])), "The switcher's press")
        XCTAssertEqual(switcher.pressedID, ids[1])
        XCTAssertEqual(switcher.selectedID, ids[1], "The card pressed is the pick")
        XCTAssertTrue(switcher.visible, "Still up while the button is down")
        XCTAssertTrue(taken.isEmpty)

        XCTAssertTrue(switcher.lift(at: middle(switcher, ids[1])) { taken.append($0) })
        XCTAssertEqual(taken, [ids[1]], "Taken once, on the way up")
        XCTAssertNil(switcher.pressedID)
    }

    /// Let go beside the card, the press is called off, as a button's is.
    func testLettingGoBesideTheCardTakesNothing() {
        let (switcher, ids) = up()
        var taken: [Tab.ID] = []
        XCTAssertTrue(switcher.press(at: middle(switcher, ids[0])))
        XCTAssertTrue(switcher.lift(at: middle(switcher, ids[2])) { taken.append($0) }, "The press's own end")
        XCTAssertTrue(taken.isEmpty)
        XCTAssertNil(switcher.pressedID)
        XCTAssertTrue(switcher.visible, "The switcher stays for another go")
        // Outside the window altogether (the monitor's -1, -1).
        XCTAssertTrue(switcher.press(at: middle(switcher, ids[0])))
        XCTAssertTrue(switcher.lift(at: CGPoint(x: -1, y: -1)) { taken.append($0) })
        XCTAssertTrue(taken.isEmpty)
    }

    func testAPressBesideThePanelPutsTheSwitcherAway() {
        let (switcher, _) = up()
        var taken: [Tab.ID] = []
        XCTAssertTrue(switcher.press(at: CGPoint(x: 5, y: 5)))
        XCTAssertFalse(switcher.visible)
        XCTAssertNil(switcher.pressedID)
        XCTAssertFalse(switcher.lift(at: CGPoint(x: 5, y: 5)) { taken.append($0) }, "No press of the switcher's to end")
        XCTAssertFalse(switcher.press(at: CGPoint(x: 5, y: 5)), "Not up: the click is the window's")
        XCTAssertTrue(taken.isEmpty)
    }

    /// Between two cards the press is the switcher's and nothing gives, and
    /// the button coming up after it is nobody's.
    func testAPressBetweenTwoCardsPressesNothing() {
        let (switcher, ids) = up()
        var taken: [Tab.ID] = []
        XCTAssertTrue(switcher.press(at: CGPoint(x: 205, y: 150)))
        XCTAssertNil(switcher.pressedID)
        XCTAssertEqual(switcher.selectedID, ids[2], "The pick is where the keys left it")
        XCTAssertFalse(switcher.lift(at: CGPoint(x: 205, y: 150)) { taken.append($0) })
        XCTAssertTrue(taken.isEmpty)
        XCTAssertTrue(switcher.visible)
    }

    /// ⌃ let go with the button still down: the card pressed is the pick,
    /// so it is the one taken, and the button coming up finds nothing left.
    func testLettingGoOfTheKeysWhilePressedTakesThePressedCard() {
        let (switcher, ids) = up()
        var taken: [Tab.ID] = []
        XCTAssertTrue(switcher.press(at: middle(switcher, ids[0])))
        XCTAssertEqual(switcher.finish(), ids[0])
        XCTAssertNil(switcher.pressedID)
        XCTAssertFalse(switcher.visible)
        XCTAssertFalse(switcher.lift(at: middle(switcher, ids[0])) { taken.append($0) })
        XCTAssertTrue(taken.isEmpty)
    }

    /// A card closed from the keys while it is held (⌃W) is no longer held.
    func testACardClosedWhilePressedIsNotTakenWhenLetGo() {
        let (switcher, ids) = up()
        var taken: [Tab.ID] = []
        let spot = middle(switcher, ids[1])
        XCTAssertTrue(switcher.press(at: spot))
        switcher.remove(ids[1])
        XCTAssertNil(switcher.pressedID)
        XCTAssertFalse(switcher.lift(at: spot) { taken.append($0) })
        XCTAssertTrue(taken.isEmpty)
    }
}
