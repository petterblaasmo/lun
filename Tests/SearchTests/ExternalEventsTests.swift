import XCTest
@testable import Search

/// The window's scene leaves events from outside to Links: a page handed
/// off from an iPhone, a file opened from the Finder. Routed by SwiftUI
/// they closed the window first, and a close with other windows open takes
/// the window's tabs. What the line does is shown by Tests/handoff_scene.py,
/// which needs no build; this holds the line in place.
final class ExternalEventsTests: XCTestCase {
    func testTheWindowsSceneHandlesNoExternalEvents() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Search/App.swift")
        let app = try String(contentsOf: file, encoding: .utf8)
        let start = try XCTUnwrap(app.range(of: "id: Browsers.sceneID)"))
        let end = try XCTUnwrap(app.range(of: ".commands {", range: start.upperBound..<app.endIndex))
        let scene = app[start.upperBound..<end.lowerBound]
        let code = scene.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        XCTAssertTrue(code.contains { $0.contains(".handlesExternalEvents(matching: [])") })
    }
}
