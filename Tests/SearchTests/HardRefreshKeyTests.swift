import XCTest
@testable import Search

/// ⇧⌘R reloads the page from the network (a hard refresh), as in Chrome and
/// Arc; Reading Mode is on ⌥⌘R.
@MainActor
final class HardRefreshKeyTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    func testTheTwoKeys() throws {
        let hard = try XCTUnwrap(Command.named("view.reloadOrigin"))
        let reader = try XCTUnwrap(Command.named("view.reader"))
        XCTAssertEqual(hard.baseKey, KeyCombo("r", shift: true))
        XCTAssertEqual(reader.baseKey, KeyCombo("r", option: true))
        XCTAssertEqual(try XCTUnwrap(Command.named("view.reload")).baseKey, KeyCombo("r"))
    }

    func testNoTwoCommandsShareAKeyOnR() {
        let onR = Command.all.compactMap(\.baseKey).filter { $0 == KeyCombo("r") || $0 == KeyCombo("r", shift: true) || $0 == KeyCombo("r", option: true) }
        XCTAssertEqual(onR.count, 3)
    }
}
