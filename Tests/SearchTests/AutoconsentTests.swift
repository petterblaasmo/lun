import WebKit
import XCTest
@testable import Search

/// Refuse cookie banners (Autoconsent.swift): nothing in a page with the
/// switch off, DuckDuckGo's script in every frame with it on, a banner it
/// knows answered No on stand-ins for two consent platforms, and its rules
/// cut down for one frame as autoconsent's own filterCompactRules does.
/// The script and the rules are the ones in the app (Autoconsent/), so
/// nothing here fetches anything.
@MainActor
final class AutoconsentTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    // Each page says what it was told: window.__choice, in the page's world.
    private static let complianz = """
        <!doctype html><title>complianz</title><p>A shop.</p>
        <div id="cmplz-cookiebanner-container"><div class="cmplz-cookiebanner" style="position:fixed;bottom:0;left:0;right:0;height:120px;background:#eee">
        We use cookies. <button class="cmplz-accept" onclick="answer('accept')">Accept</button>
        <button class="cmplz-deny" onclick="answer('deny')">Deny</button></div></div>
        <script>function answer(a) { window.__choice = a; document.querySelector('.cmplz-cookiebanner').style.display = 'none'; }</script>
        """

    /// No button to say no: only Didomi's own setUserDisagreeToAll(), which
    /// the script asks Lun to call in the page's world.
    private static let didomi = """
        <!doctype html><title>didomi</title><p>A newspaper.</p>
        <div id="didomi-host"><div id="didomi-notice" style="position:fixed;bottom:0;left:0;right:0;height:120px;background:#eee">
        We and our partners use cookies. <button id="didomi-notice-agree-button" onclick="answer('accept')">Agree</button></div></div>
        <script>
        function answer(a) { window.__choice = a; document.getElementById('didomi-notice').remove(); }
        window.Didomi = {
          setUserDisagreeToAll: function () { answer('deny'); },
          getCurrentUserStatus: function () { return { purposes: { ads: { enabled: window.__choice !== 'deny' } } }; }
        };
        </script>
        """

    private static let unknown = """
        <!doctype html><title>unknown</title><p>A blog.</p>
        <div class="my-own-banner" style="position:fixed;bottom:0;left:0;right:0;height:120px;background:#eee">
        This site uses cookies. <button onclick="window.__choice='accept'">Accept all</button>
        <button onclick="window.__choice='deny'">Reject all</button></div>
        """

    /// A tab made with the switch as given, on `html`.
    private func open(_ html: String, on: Bool, shy: Bool = false) async throws -> Tab {
        _ = NSApplication.shared
        Shared.prefs.refusesCookieBanners = on
        let tab = Tab(shy: shy, bench: true)
        addTeardownBlock { @MainActor in tab.close() }
        tab.web.loadHTMLString(html + "<script>window.fixtureReady = true</script>", baseURL: URL(string: "https://consent.invalid/"))
        for _ in 0..<200 {
            if (try? await tab.web.evaluateJavaScript("window.fixtureReady")) as? Bool == true { return tab }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out loading the page")
        throw CancellationError()
    }

    /// What the page was told, once it was told something, or nil.
    private func choice(_ tab: Tab, within seconds: Double) async throws -> String? {
        for _ in 0..<Int(seconds * 10) {
            if let told = (try? await tab.web.evaluateJavaScript("window.__choice || null")) as? String { return told }
            try await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// Whether DuckDuckGo's script is in the page, asked in its own world.
    private func hasScript(_ tab: Tab) async throws -> Bool {
        try await tab.web.evaluateJavaScript("typeof window.autoconsentReceiveMessage === 'function'",
                                             contentWorld: Autoconsent.world) as? Bool == true
    }

    // MARK: - the switch

    func testOffUnlessTurnedOnAndAChoiceStands() {
        let key = "privacy.cookieBanners"
        let saved = Store.settings.object(forKey: key)
        defer {
            Store.settings.set(saved, forKey: key)
            _ = Preferences()
        }
        Store.settings.removeObject(forKey: key)
        XCTAssertFalse(Preferences().refusesCookieBanners)
        XCTAssertFalse(Autoconsent.on)
        XCTAssertNil(Store.settings.object(forKey: key), "nothing written just for reading it")
        Store.settings.set(true, forKey: key)
        XCTAssertTrue(Preferences().refusesCookieBanners)
        XCTAssertTrue(Autoconsent.on, "read by the tabs from the first one on")
    }

    func testTheRowIsOnPrivacyAndFoundByItsWords() throws {
        let row = try XCTUnwrap(SettingsIndex.item("privacy.cookieBanners"))
        XCTAssertEqual(row.page, .privacy)
        XCTAssertEqual(row.group, "blocking")
        XCTAssertEqual(row.keys, ["privacy.cookieBanners"])
        XCTAssertFalse(row.findOnly)
        XCTAssertFalse(SettingsIndex.essential.contains(row.id), "under More options, not what the page opens on")
        for word in ["cookie", "cookie banner", "consent", "gdpr", "reject"] {
            XCTAssertTrue(SettingsIndex.find(word).contains { $0.id == row.id }, word)
        }
    }

    func testWhatsNewOffersItUnderTheRowsName() throws {
        let row = try XCTUnwrap(SettingsIndex.item("privacy.cookieBanners"))
        let offer = try XCTUnwrap(WhatsNew.toggles.first { $0.title == row.title })
        let prefs = Shared.prefs
        prefs.refusesCookieBanners = false
        XCTAssertFalse(offer.get(prefs))
        offer.set(prefs, true)
        XCTAssertTrue(prefs.refusesCookieBanners)
        XCTAssertTrue(Autoconsent.on)
        XCTAssertEqual(Store.settings.object(forKey: "privacy.cookieBanners") as? Bool, true)
    }

    // MARK: - what a page gets

    func testOffNothingIsPutInAPage() async throws {
        let tab = try await open(Self.complianz, on: false)
        let scripts = try XCTUnwrap(tab.contentController).userScripts
        XCTAssertFalse(scripts.isEmpty, "the tab's other scripts are there")
        XCTAssertFalse(scripts.contains { $0.source.contains("autoconsent") })
        let scripted = try await hasScript(tab)
        XCTAssertFalse(scripted)
        let told = try await choice(tab, within: 2)
        XCTAssertNil(told, "the banner is left for you")
    }

    func testOnEveryFrameGetsTheScriptInAWorldOfItsOwn() async throws {
        let script = try XCTUnwrap(Autoconsent.script, "Autoconsent/autoconsent.js")
        XCTAssertFalse(script.isForMainFrameOnly, "Sourcepoint and TrustArc show theirs in a frame")
        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        for shy in [false, true] {
            let tab = try await open(Self.unknown, on: true, shy: shy)
            let scripts = try XCTUnwrap(tab.contentController).userScripts
            XCTAssertEqual(scripts.filter { $0 === script }.count, 1, shy ? "a private tab" : "a tab")
            let scripted = try await hasScript(tab)
            XCTAssertTrue(scripted)
            let page = try await tab.web.evaluateJavaScript(
                "typeof window.autoconsentReceiveMessage + typeof window.autoconsentSendMessage") as? String
            XCTAssertEqual(page, "undefinedundefined", "the page sees none of it")
        }
    }

    func testTurnedOffTheNextPageGetsNothing() async throws {
        let tab = try await open(Self.unknown, on: true)
        Shared.prefs.refusesCookieBanners = false
        tab.rearm()
        XCTAssertFalse(try XCTUnwrap(tab.contentController).userScripts.contains { $0.source.contains("autoconsent") })
    }

    // MARK: - banners

    func testABannerItKnowsGetsItsDenyButton() async throws {
        let tab = try await open(Self.complianz, on: true)
        let told = try await choice(tab, within: 15)
        XCTAssertEqual(told, "deny")
    }

    func testABannerWithNoButtonToSayNoIsRefusedThroughItsOwnCall() async throws {
        let tab = try await open(Self.didomi, on: true)
        let told = try await choice(tab, within: 15)
        XCTAssertEqual(told, "deny")
    }

    func testABannerNoRuleKnowsIsLeftAlone() async throws {
        let tab = try await open(Self.unknown, on: true)
        let told = try await choice(tab, within: 4)
        XCTAssertNil(told, "never guessed at, Reject all or not")
    }

    func testOnlyNoAndNothingGuessed() {
        XCTAssertEqual(Autoconsent.config["autoAction"] as? String, "optOut")
        XCTAssertEqual(Autoconsent.config["heuristicMode"] as? String, "off")
        XCTAssertEqual(Autoconsent.config["enableHeuristicDetection"] as? Bool, false)
        XCTAssertEqual(Autoconsent.config["enableGeneratedRules"] as? Bool, false)
        XCTAssertEqual(Autoconsent.config["enableCosmeticRules"] as? Bool, false)
    }

    func testOnlyItsTwoQuestionsReachLun() {
        XCTAssertTrue(Autoconsent.glue.contains(#"message.type !== "init" && message.type !== "eval""#))
        XCTAssertTrue(Autoconsent.glue.contains("messageHandlers.\(Autoconsent.name);"))
    }

    // MARK: - the files in the app

    func testTheNoticesNameTheReleaseInTheApp() throws {
        let version = try String(contentsOf: Self.root.appendingPathComponent("Autoconsent/VERSION"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notices = try String(contentsOf: Self.root.appendingPathComponent("THIRD_PARTY_NOTICES.md"), encoding: .utf8)
        XCTAssertTrue(notices.contains("Version \(version),"), "say autoconsent \(version) in THIRD_PARTY_NOTICES.md")
        XCTAssertTrue(notices.contains("Mozilla Public License Version 2.0"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: Self.root.appendingPathComponent("Autoconsent/LICENSE").path))
        // build.sh puts all three in the app.
        let build = try String(contentsOf: Self.root.appendingPathComponent("build.sh"), encoding: .utf8)
        XCTAssertTrue(build.contains(#"cp Autoconsent/autoconsent.js Autoconsent/rules.json Autoconsent/LICENSE "$APP/Contents/Resources/Autoconsent/""#))
    }

    func testNothingInItIsFetched() throws {
        let swift = try String(contentsOf: Self.root.appendingPathComponent("Sources/Search/Autoconsent.swift"), encoding: .utf8)
        for word in ["URLSession", "URLRequest", "NSURLConnection", "jsdelivr"] {
            XCTAssertFalse(swift.contains(word), word)
        }
    }

    // MARK: - the rules, cut for one frame

    private struct Whole {
        let strings: [String]
        let rules: [[Any]]
        func named(_ name: String) -> [Any]? { rules.first { $0[1] as? String == name } }
    }

    private func published() throws -> Whole {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("Autoconsent/rules.json"))
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Whole(strings: try XCTUnwrap(all["s"] as? [String]), rules: try XCTUnwrap(all["r"] as? [[Any]]))
    }

    private func names(_ cut: [String: Any]) -> [String] { (cut["r"] as? [[Any]] ?? []).compactMap { $0[1] as? String } }

    /// Every number a rule holds under a key that points into the strings.
    private func pointers(_ value: Any, into found: inout Set<Int>) {
        if let list = value as? [Any] {
            list.forEach { pointers($0, into: &found) }
        } else if let step = value as? [String: Any] {
            for (key, inner) in step {
                if ["e", "v", "c", "k", "w", "wv", "h", "cc"].contains(key), let id = inner as? Int { found.insert(id) } else { pointers(inner, into: &found) }
            }
        }
    }

    /// What the script would read: each string a kept rule points at is in
    /// the cut, at its own place.
    private func assertWhole(_ cut: [String: Any], against whole: Whole, _ what: String) {
        let strings = cut["s"] as? [String] ?? []
        for rule in cut["r"] as? [[Any]] ?? [] {
            var ids = Set(rule[5] as? [Int] ?? [])
            pointers(Array(rule[6...9]), into: &ids)
            for id in ids {
                XCTAssertTrue(id < strings.count && strings[id] == whole.strings[id], "\(what): \(rule[1]) string \(id)")
            }
        }
    }

    func testTheRulesInTheAppAreOnesTheScriptReads() throws {
        let book = try XCTUnwrap(Autoconsent.book, "Autoconsent/rules.json")
        let cut = book.rules(for: "https://nothing-of-its-own.example/", mainFrame: true)
        XCTAssertEqual(cut["v"] as? Int, Rulebook.format)
        XCTAssertGreaterThan(names(cut).count, 500)
    }

    func testASiteWithNoRuleOfItsOwnGetsOnlyThoseForAnySite() throws {
        let book = try XCTUnwrap(Autoconsent.book)
        let whole = try published()
        let cut = book.rules(for: "https://nothing-of-its-own.example/", mainFrame: true)
        XCTAssertTrue(names(cut).contains("Complianz banner") && names(cut).contains("didomi"))
        XCTAssertTrue((cut["r"] as? [[Any]] ?? []).allSatisfy { $0[3] as? String == "" }, "none of one site's")
        XCTAssertLessThan((cut["s"] as? [Any])?.count ?? .max, whole.strings.count, "nor one site's strings")
        assertWhole(cut, against: whole, "any site")
    }

    func testASiteWithARuleOfItsOwnGetsItTooWithItsStrings() throws {
        let book = try XCTUnwrap(Autoconsent.book)
        let whole = try published()
        let plain = Set(names(book.rules(for: "https://nothing-of-its-own.example/", mainFrame: true)))
        for (name, address) in [("airbnb", "https://www.airbnb.com/rooms"), ("tumblr-com", "https://www.tumblr.com/explore"),
                                ("figma", "https://www.figma.com/files")] {
            XCTAssertNotNil(whole.named(name), "\(name) is no longer a rule: pick another for this test")
            let cut = book.rules(for: address, mainFrame: true)
            XCTAssertEqual(names(cut).filter { !plain.contains($0) }, [name])
            XCTAssertEqual(names(cut).count, plain.count + 1)
            assertWhole(cut, against: whole, name)
        }
    }

    func testAnotherSitesFrameGetsNothing() throws {
        let book = try XCTUnwrap(Autoconsent.book)
        let cut = book.rules(for: "https://ads.example/frame", mainFrame: false)
        XCTAssertEqual(names(cut), [])
        XCTAssertEqual((cut["s"] as? [Any])?.count, 0, "its own platforms' banners are in the script, not the rules")
    }

    func testAFrameGetsItsOwnFrameRuleAndATopPageDoesNot() throws {
        let book = try XCTUnwrap(Autoconsent.book)
        let whole = try published()
        XCTAssertEqual(whole.named("dropbox")?[4] as? Int, 1, "dropbox is no longer a frame's rule: pick another for this test")
        let frame = book.rules(for: "https://www.dropbox.com/consent", mainFrame: false)
        XCTAssertEqual(names(frame), ["dropbox"])
        assertWhole(frame, against: whole, "a frame")
        XCTAssertFalse(names(book.rules(for: "https://www.dropbox.com/", mainFrame: true)).contains("dropbox"))
        // And a top page's rule stays out of its frames.
        XCTAssertFalse(names(book.rules(for: "https://www.airbnb.com/rooms", mainFrame: false)).contains("airbnb"))
    }

    func testWhatIsntRulesTheScriptReadsIsntABook() throws {
        XCTAssertNil(Rulebook(Data("{}".utf8)))
        XCTAssertNil(Rulebook(Data("<html>Not found</html>".utf8)))
        XCTAssertNil(Rulebook(Data(#"{"v":1,"s":[],"r":[[1]],"index":{"genericRuleRange":[0,9]}}"#.utf8)))
        let small = #"{"v":V,"s":[".a"],"r":[[1,"one",2,"",22,[P],[{"e":0}],[{"v":0}],[{"c":0}],[],{}]],"#
            + #""index":{"genericRuleRange":[0,1],"frameRuleRange":[1,1],"specificRuleRange":[1,1]}}"#
        func book(format: Int, pointing: Int) -> Rulebook? {
            Rulebook(Data(small.replacingOccurrences(of: "V", with: "\(format)").replacingOccurrences(of: "P", with: "\(pointing)").utf8))
        }
        XCTAssertNotNil(book(format: Rulebook.format, pointing: 0))
        XCTAssertNil(book(format: Rulebook.format + 1, pointing: 0), "a newer format than the script's")
        XCTAssertNil(book(format: Rulebook.format, pointing: 1), "a rule pointing past the strings")
    }
}
