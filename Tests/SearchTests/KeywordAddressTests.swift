import XCTest
@testable import Search

/// A site shortcut's address typed without https://, as the field's own
/// example is written, is taken as https and saved that way.
final class KeywordAddressTests: XCTestCase {
    func testAnAddressTypedWithoutItsSchemeIsTakenAsHTTPS() {
        let typed = "youtube.com/results?search_query=%s"

        XCTAssertEqual(Keyword.address(typed), "https://youtube.com/results?search_query=%s")
        XCTAssertNil(Keyword.problem(word: "yt", template: typed, among: []))
        XCTAssertEqual(Keyword(keyword: "yt", template: typed).name, "youtube.com")
    }

    func testAnAddressWithASchemeIsOnlyTrimmed() {
        XCTAssertEqual(Keyword.address(" http://example.com/?q=%s "), "http://example.com/?q=%s")
        XCTAssertEqual(Keyword.address("https://example.com/?q=%s"), "https://example.com/?q=%s")
        XCTAssertEqual(Keyword.address("  "), "")
    }

    /// What was refused with a scheme is refused without one: the words
    /// still have to go into the path, query or fragment of one site.
    func testNothingElseGetsThroughForLackingAScheme() {
        XCTAssertNotNil(Keyword.problem(word: "yt", template: "youtube.com/results?search_query=", among: []))
        XCTAssertNotNil(Keyword.problem(word: "yt", template: "%s.example.com", among: []))
        XCTAssertNotNil(Keyword.problem(word: "yt", template: "javascript:alert(%s)", among: []))
        XCTAssertNotNil(Keyword.problem(word: "yt", template: "user@%s/path", among: []))
    }
}
