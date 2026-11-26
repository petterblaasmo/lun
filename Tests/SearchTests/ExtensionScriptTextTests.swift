import XCTest
@testable import Search

/// WebKit shares an extension's script and stylesheet text between sites and
/// tabs only for an app that says it takes every current WebKit behaviour.
/// Lun says so only where that changes nothing else: on a macOS no newer
/// than the SDK it was built with (Web.shareScriptText). What the sharing
/// saves is measured in a running app by Tests/extension_memory.py.
final class ExtensionScriptTextTests: XCTestCase {
    func testOnlyOnAMacOSNoNewerThanTheSDK() {
        XCTAssertTrue(Web.takesCurrentBehaviours(macOS: (26, 6), sdk: (27, 2)))
        XCTAssertTrue(Web.takesCurrentBehaviours(macOS: (27, 2), sdk: (27, 2)), "the same, to the minor")
        XCTAssertTrue(Web.takesCurrentBehaviours(macOS: (14, 7), sdk: (27, 2)))
        XCTAssertFalse(Web.takesCurrentBehaviours(macOS: (27, 3), sdk: (27, 2)), "a later minor has behaviours of its own")
        XCTAssertFalse(Web.takesCurrentBehaviours(macOS: (28, 0), sdk: (27, 2)))
        XCTAssertFalse(Web.takesCurrentBehaviours(macOS: (26, 6), sdk: nil), "not knowing is a no")
    }

    /// Read from the running program's own header: here the test runner's,
    /// built with a macOS SDK this package can be built with at all.
    func testTheSDKIsReadFromTheHeader() throws {
        let sdk = try XCTUnwrap(Web.builtWith)
        XCTAssertGreaterThanOrEqual(sdk.major, 14)
        XCTAssertLessThan(sdk.major, 100)
        XCTAssertTrue((0..<100).contains(sdk.minor))
    }
}
