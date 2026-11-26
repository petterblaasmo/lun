import XCTest
@testable import Search

/// The test world puts every setting back before each test (KeptSettings):
/// a setting missing from its list would be one a test can leave changed.
@MainActor
final class TestWorldTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    func testEverySettingIsKept() {
        let published = Mirror(reflecting: Shared.prefs).children
            .compactMap(\.label).filter { $0.hasPrefix("_") }.map { String($0.dropFirst()) }
        XCTAssertGreaterThan(published.count, 100, "the settings are read off Preferences")
        let missing = Set(published).subtracting(KeptSettings.names).subtracting(KeptSettings.readOnly)
        XCTAssertEqual(missing.sorted(), [], "add these to KeptSettings.take()")
        let gone = KeptSettings.names.subtracting(published)
        XCTAssertEqual(gone.sorted(), [], "no longer settings: take these out of KeptSettings.take()")
    }

    func testASettingLeftChangedIsPutBack() {
        let prefs = Shared.prefs
        let was = (prefs.addressLine, prefs.sideWidth)
        prefs.addressLine.toggle()
        prefs.sideWidth = was.1 == Metrics.sideMin ? Metrics.sideMax : Metrics.sideMin
        XCTAssertEqual(Set(KeptSettings.putBack()), ["addressLine", "sideWidth"])
        XCTAssertEqual(prefs.addressLine, was.0)
        XCTAssertEqual(prefs.sideWidth, was.1)
        XCTAssertEqual(KeptSettings.putBack(), [], "nothing left to put back")
    }
}
