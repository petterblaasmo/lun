import Foundation
import WebKit
import XCTest
@testable import Search

/// What an extension's own script refused by a page's policy may be
/// (ExtensionPageScript): which path, for which page, and what runs.
@available(macOS 15.4, *)
final class ExtensionPageScriptTests: XCTestCase {
    private let page = URL(string: "https://www.youtube.com/watch?v=1")!
    private let manifest: [String: Any] = [
        "web_accessible_resources": [
            ["resources": ["page.js", "scripts/*.js"], "matches": ["https://www.youtube.com/*"]],
            ["resources": ["other.js"], "matches": ["https://example.com/*"]],
        ],
        "content_scripts": [["matches": ["https://www.youtube.com/*"], "exclude_matches": ["https://www.youtube.com/embed/*"], "js": ["c.js"]]],
    ]

    func testPathsAreDecodedAndPlain() {
        XCTAssertEqual(ExtensionPageScript.normalized("/page.js"), "page.js")
        XCTAssertEqual(ExtensionPageScript.normalized("/%70age.js"), "page.js", "matched as decoded")
        XCTAssertEqual(ExtensionPageScript.normalized("/scripts/a.js"), "scripts/a.js")
        for bad in ["/../page.js", "/scripts/../page.js", "/./page.js", "/scripts//a.js", "/%2e%2e/page.js", "/a%00.js", "/a\\b.js", "/"] {
            XCTAssertNil(ExtensionPageScript.normalized(bad), bad)
        }
    }

    func testWebAccessibleForThatPage() {
        let ok = { (path: String) in ExtensionPageScript.normalized(path).map { ExtensionPageScript.accessible($0, to: self.page, manifest: self.manifest) } ?? false }
        XCTAssertTrue(ok("/page.js"))
        XCTAssertTrue(ok("/%70age.js"))
        XCTAssertTrue(ok("/scripts/x.js"))
        XCTAssertFalse(ok("/other.js"), "web-accessible to another site only")
        XCTAssertFalse(ok("/hidden.js"))
        XCTAssertFalse(ok("/scripts/../hidden.js"))
    }

    func testMayScriptThatPage() {
        XCTAssertTrue(ExtensionPageScript.mayScript(page, manifest: manifest, hasScripting: false), "a content script for the page")
        XCTAssertFalse(ExtensionPageScript.mayScript(URL(string: "https://www.youtube.com/embed/1")!, manifest: manifest, hasScripting: false), "excluded")
        XCTAssertFalse(ExtensionPageScript.mayScript(URL(string: "https://example.com/")!, manifest: manifest, hasScripting: false))
        XCTAssertTrue(ExtensionPageScript.mayScript(URL(string: "https://example.com/")!, manifest: manifest, hasScripting: true))
    }

    /// One evaluation: the check on the document first, then the element,
    /// then the file; a strict file stays strict.
    func testEvaluation() {
        let token = String(repeating: "a", count: 32)
        let plain = ExtensionPageScript.evaluation(source: "var x = 1;", expected: "https://www.youtube.com/watch?v=1", token: token)
        XCTAssertTrue(plain.hasPrefix("(() => {\n  if (location.origin + location.pathname + location.search !== \"https://www.youtube.com/watch?v=1\") throw \""), plain)
        XCTAssertTrue(plain.contains("queueMicrotask"))
        XCTAssertTrue(plain.hasSuffix("var x = 1;\n;void 0"))
        let strict = ExtensionPageScript.evaluation(source: "/* hi */\n'use strict'; var y;", expected: "https://a.b/", token: token)
        XCTAssertTrue(strict.hasPrefix("\"use strict\";(() => {"), strict)
        let quoted = ExtensionPageScript.evaluation(source: "", expected: "https://a.b/?q=\"</script>\\", token: token)
        XCTAssertTrue(quoted.contains(#"!== "https://a.b/?q=\"</script>\\")"#), quoted)
        let from = ExtensionPageScript.evaluation(source: "", expected: "https://a.b/", token: token, address: "chrome-extension://abc/web/a.js")
        XCTAssertTrue(from.contains(#"get: () => "chrome-extension://abc/web/a.js""#), "the element's src while the file runs")
    }

    /// What tells a script in the page its address (addresses), in a page:
    /// said from another world on the element, the element's src reads as
    /// the address while it is the script running and as WebKit gives it
    /// otherwise; the page's own listeners hear nothing, and can't have the
    /// page's currentScript taken for WebKit's.
    @MainActor
    func testAScriptIsToldItsAddressOnlyWhileItRuns() async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addUserScript(
            WKUserScript(source: ExtensionPageScript.addresses, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 200, height: 200), configuration: config)
        web.loadHTMLString("""
            <!doctype html><script>
            for (const where of [window, document]) where.addEventListener("search-script-address", (e) => { window.heard = e.detail; }, true);
            </script><p>page</p><script>window.ready = true</script>
            """, baseURL: URL(string: "https://example.com/"))
        for _ in 0..<200 {
            if (try? await web.evaluateJavaScript("window.ready")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        // As a content script's shim does it, in a world of its own.
        let world = WKContentWorld.world(name: "a-content-script")
        _ = try await web.evaluateJavaScript("""
            (() => {
              const s = document.createElement("script");
              s.id = "theirs";
              s.src = "data:text/javascript,window.read = document.currentScript.src; window.ran = true";
              document.head.appendChild(s);
              s.dispatchEvent(new CustomEvent("search-script-address", { detail: "chrome-extension://abc/web/a.js?_=1" }));
              s.dispatchEvent(new CustomEvent("search-script-address", { detail: "chrome-extension://abc/second.js" }));
            })(); 1
            """, in: nil, contentWorld: world)
        for _ in 0..<200 {
            if (try? await web.evaluateJavaScript("window.ran")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let read = try await web.evaluateJavaScript("window.read") as? String
        XCTAssertEqual(read, "chrome-extension://abc/web/a.js?_=1", "the first address said, to the script itself")
        let after = try await web.evaluateJavaScript("document.getElementById('theirs').src") as? String
        XCTAssertEqual(after?.hasPrefix("data:text/javascript"), true, "the page reads what WebKit gives")
        let heard = try await web.evaluateJavaScript("String(window.heard)") as? String
        XCTAssertEqual(heard, "undefined", "no listener of the page's hears it")
        let posed = try await web.evaluateJavaScript("""
            (() => {
              const s = document.getElementById("theirs");
              Object.defineProperty(document, "currentScript", { configurable: true, get: () => s });
              return s.src;
            })()
            """) as? String
        XCTAssertEqual(posed?.hasPrefix("data:text/javascript"), true, "a currentScript the page puts there isn't WebKit's")
    }

    /// The address the evaluation checks, as location reads it.
    func testPageAddress() {
        let a = { (s: String) in ExtensionPageScript.pageAddress(URL(string: s)!) }
        XCTAssertEqual(a("https://www.youtube.com/watch?v=1#t=3"), "https://www.youtube.com/watch?v=1")
        XCTAssertEqual(a("HTTPS://WWW.Example.com"), "https://www.example.com/")
        XCTAssertEqual(a("http://127.0.0.1:8080/a%20b?x=%41"), "http://127.0.0.1:8080/a%20b?x=%41")
        XCTAssertEqual(a("https://a.example:443/p?"), "https://a.example/p")
        XCTAssertNil(a("file:///etc/hosts"))
    }
}
