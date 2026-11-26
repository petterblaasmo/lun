import XCTest
@testable import Search

@MainActor
final class SiteSearchTests: XCTestCase {
    func testKeywordSiteShortcutCanBeOfferedByItsKeyword() throws {
        let keyword = Keyword(keyword: "grk", template: "https://grok.com/?q=%s")

        let site = try XCTUnwrap(SiteSearch.match("gr", learnedToo: false, keywords: [keyword]))

        XCTAssertEqual(site.name, "Grok")
        XCTAssertEqual(site.host, "grok.com")
        XCTAssertEqual(site.template, keyword.template)
        XCTAssertEqual(site.aliases, ["grk"])
    }

    private let inPath = SearchSite(name: "Music", host: "music.example", template: "https://music.example/search/%s")

    func testWordsAtTheEndOfThePathKeepASlashOfTheirOwn() throws {
        let url = try XCTUnwrap(URL(string: "https://music.example/search/AC%2FDC"))
        XCTAssertEqual(SiteSearch.words(in: url, searchedOn: inPath), "AC/DC")
    }

    func testWordsAtTheEndOfThePathAreReadDecoded() throws {
        let url = try XCTUnwrap(URL(string: "https://music.example/search/daft%20punk"))
        XCTAssertEqual(SiteSearch.words(in: url, searchedOn: inPath), "daft punk")
    }

    func testAPageUnderTheSearchPageIsNotASearch() throws {
        let url = try XCTUnwrap(URL(string: "https://music.example/search/a/b"))
        XCTAssertNil(SiteSearch.words(in: url, searchedOn: inPath))
    }
}
