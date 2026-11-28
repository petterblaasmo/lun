import Foundation
import WebKit

// Cookie banners, answered No.
//
// With Settings › Privacy › Refuse cookie banners on, a site's consent pop-up
// is answered No (reject all, or only what is needed) and closed, usually
// before it has been seen. The work is DuckDuckGo's autoconsent, the one
// their own Mac and iPhone browsers run in a WKWebView like this one. It
// knows the consent platforms most sites use (OneTrust, Cookiebot, Didomi,
// Sourcepoint, Usercentrics and a few hundred more, some site by site) by
// their own markup, and what to press, in what order, to say no.
//
// Its script and its rules are in the app (Autoconsent/ in the repository,
// MPL-2.0, as published on npm and unchanged; Autoconsent/VERSION says
// which release). Nothing is fetched: they change with a release of Lun,
// by hand, with scripts/autoconsent.sh.
//
// Only No, and only pop-ups it knows:
// - its heuristic mode, which guesses at a banner from the words on its
//   buttons, stays off: a wrong guess there is a press on Accept;
// - its generated rules, which find a button by its place in the page
//   rather than its name, stay off for the same reason;
// - its cosmetic rules, which only hide a banner that has no way to say
//   no, stay off: such a banner is left as it is, for ⇧⌘H.
//
// It runs in every frame, since Sourcepoint and TrustArc show theirs in a
// frame of their own, and in a world of its own, so the page sees none of
// it and it sees none of Lun's own handlers. What it can't do from there,
// calling a platform's own JavaScript (Didomi's setUserDisagreeToAll()), it
// hands to Lun, which runs it in that frame's page world and answers
// whether it worked. That code is always the script's own: a rule only
// names one of the script's snippets.
//
// Off, which it is unless turned on, none of this is read from disk and no
// page gets a line of it (Tab.arm).

final class Autoconsent: NSObject, WKScriptMessageHandlerWithReply {
    static let shared = Autoconsent()
    static let name = "consent"
    @MainActor static let world = WKContentWorld.world(name: "Lun Consent")

    /// Settings' switch. Off unless turned on.
    @MainActor static var on = false

    /// The vendored files: in the app, where build.sh puts them. A debug
    /// build run out of the build folder (swift test) has no bundle around
    /// it and reads the checkout's own.
    static let folder: URL? = {
        var places = [Bundle.main.resourceURL?.appendingPathComponent("Autoconsent")]
        #if DEBUG
        places.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Autoconsent"))
        #endif
        return places.compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("autoconsent.js").path)
        }
    }()

    /// For each page and frame: a few lines of Lun's, then DuckDuckGo's
    /// script as it comes. Read the first time a page needs it; nil in a
    /// copy of Lun without Autoconsent/, which then goes without.
    @MainActor static let script: WKUserScript? = {
        guard let file = folder?.appendingPathComponent("autoconsent.js"),
              let library = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return WKUserScript(source: glue + library, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world)
    }()

    /// The rules, read the first time a page asks for them, off the main
    /// thread (see `init` below).
    static let book: Rulebook? = folder.flatMap { try? Data(contentsOf: $0.appendingPathComponent("rules.json")) }
        .flatMap(Rulebook.init)

    /// What the script says to Lun. Only its two questions are passed on,
    /// the rules for this frame and a snippet to run; an answer goes
    /// straight back to it. The rest is a running report of every step, a
    /// few dozen messages a page, which nothing here reads. In a view with
    /// no one to ask (an extension's page, once a tab beside it closed)
    /// nothing is said, and the script waits for good.
    static let glue = """
    window.autoconsentSendMessage = function (message) {
      if (message.type !== "init" && message.type !== "eval") return;
      var lun = window.webkit && window.webkit.messageHandlers.\(name);
      if (!lun) return;
      lun.postMessage(message).then(function (reply) {
        if (reply) window.autoconsentReceiveMessage(reply);
      }, function () {});
    };

    """

    /// Where Lun differs from the script's defaults, or rests on one:
    /// refuse without asking, and nothing guessed, generated or merely
    /// hidden (see the top of this file). Its errors stay out of the
    /// page's console.
    static let config: [String: Any] = [
        "autoAction": "optOut",
        "heuristicMode": "off",
        "enableHeuristicDetection": false,
        "enableGeneratedRules": false,
        "enableCosmeticRules": false,
        "logs": ["errors": false],
    ]

    /// One snippet, `(() => …)()`, as a question: did it work? One that
    /// throws, or that the page's own policy refuses, didn't.
    static func asked(_ code: String) -> String {
        "(() => { try { return !!(\(code)); } catch (e) { return false; } })();"
    }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        MainActor.assumeIsolated {
            // Switched off while a page was up: its script asks, and is told nothing.
            guard Autoconsent.on, let body = message.body as? [String: Any], let type = body["type"] as? String
            else { return replyHandler(nil, nil) }
            switch type {
            case "init":
                // Only the web's pages: a file, or a page of Lun's own, has
                // no banner to answer. Unanswered, the script does nothing.
                guard let url = body["url"] as? String, url.hasPrefix("http://") || url.hasPrefix("https://")
                else { return replyHandler(nil, nil) }
                let main = message.frameInfo.isMainFrame
                // Off the main thread: the first page waits here for the
                // rules to be read, and each one for the 900 site patterns.
                DispatchQueue.global(qos: .userInitiated).async {
                    let rules = Autoconsent.book?.rules(for: url, mainFrame: main)
                    DispatchQueue.main.async {
                        guard let rules else { return replyHandler(nil, nil) }
                        replyHandler(["type": "initResp", "config": Autoconsent.config, "rules": ["compact": rules]], nil)
                    }
                }
            case "eval":
                guard let id = body["id"] as? String, let code = body["code"] as? String, let web = message.webView
                else { return replyHandler(nil, nil) }
                web.evaluateJavaScript(Autoconsent.asked(code), in: message.frameInfo, in: .page) { result in
                    let worked = (try? result.get()) as? Bool ?? false
                    replyHandler(["type": "evalResp", "id": id, "result": worked], nil)
                }
            default:
                replyHandler(nil, nil)
            }
        }
    }
}

/// DuckDuckGo's rules in their compact form (Autoconsent/rules.json): the
/// strings every rule points into, the rules, and where each kind starts:
/// those for any site, those for a frame, those for one site. For each
/// frame they are cut down to what can apply there, as autoconsent's own
/// filterCompactRules does, so an ad's frame is handed nothing and a page
/// only the sites' rules that are its own.
final class Rulebook: @unchecked Sendable {
    /// The compact format the script reads (its decodeRules refuses
    /// anything newer).
    static let format = 1

    private let version: Int
    private let strings: [Any]
    private let rules: [[Any]]
    private let generic: Range<Int>
    private let frame: Range<Int>
    private let specific: Range<Int>
    /// The strings each rule points at.
    private let uses: [Set<Int>]
    /// Each rule's address pattern, made once. One ICU can't read isn't
    /// here and its rule goes along: the script checks the address again
    /// itself, so this only ever saves work.
    private let patterns: [Int: NSRegularExpression]
    /// What a page with no rule of its own gets, the same for every one.
    private let common: [String: Any]
    /// Where the strings of the rules for any site end.
    private let commonEnd: Int

    init?(_ data: Data) {
        guard let all = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = all["v"] as? Int, version <= Rulebook.format,
              let strings = all["s"] as? [Any],
              let rules = all["r"] as? [[Any]], !rules.isEmpty,
              let index = all["index"] as? [String: Any]
        else { return nil }
        func range(_ key: String) -> Range<Int>? {
            guard let ends = index[key] as? [Int], ends.count == 2,
                  0 <= ends[0], ends[0] <= ends[1], ends[1] <= rules.count else { return nil }
            return ends[0]..<ends[1]
        }
        guard let generic = range("genericRuleRange"), let frame = range("frameRuleRange"),
              let specific = range("specificRuleRange")
        else { return nil }
        let uses = rules.map(Rulebook.strings(of:))
        // A rule pointing past the strings isn't one the script can read.
        guard uses.allSatisfy({ $0.allSatisfy(strings.indices.contains) }) else { return nil }
        self.version = version
        self.strings = strings
        self.rules = rules
        self.generic = generic
        self.frame = frame
        self.specific = specific
        self.uses = uses
        var patterns: [Int: NSRegularExpression] = [:]
        for (i, rule) in rules.enumerated() {
            guard rule.count > 3, let pattern = rule[3] as? String, !pattern.isEmpty,
                  let made = try? NSRegularExpression(pattern: pattern) else { continue }
            patterns[i] = made
        }
        self.patterns = patterns
        commonEnd = (generic.compactMap { uses[$0].max() }.max() ?? -1) + 1
        common = ["v": version, "s": Array(strings[..<commonEnd]), "r": Array(rules[generic])]
    }

    /// The strings a rule points at: its selectors to hide early, and those
    /// its steps name by their short keys (autoconsent's clearUnusedStrings).
    private static func strings(of rule: [Any]) -> Set<Int> {
        var ids = Set<Int>()
        func walk(_ steps: Any?) {
            for case let step as [String: Any] in steps as? [Any] ?? [] {
                for key in ["e", "v", "c", "k", "w", "wv", "h", "cc"] {
                    if let id = step[key] as? Int { ids.insert(id) }
                }
                if let condition = step["if"] { walk([condition]) }
                walk(step["then"])
                walk(step["else"])
                walk(step["any"])
            }
        }
        guard rule.count > 9 else { return ids }
        ids.formUnion(rule[5] as? [Int] ?? [])
        rule[6...9].forEach(walk)
        return ids
    }

    /// The first `whole` strings as they are, then only the ones these
    /// rules point at, each at its own place and the rest left empty.
    private func strings(whole: Int, and kept: [Int]) -> [Any] {
        let used = kept.reduce(into: Set<Int>()) { $0.formUnion(uses[$1]) }
        let end = max(whole, (used.max() ?? -1) + 1)
        return Array(strings[..<whole]) + (whole..<end).map { used.contains($0) ? strings[$0] : "" }
    }

    /// The rules for one frame, in the shape the script takes as `compact`.
    func rules(for url: String, mainFrame: Bool) -> [String: Any] {
        let whole = NSRange(url.startIndex..., in: url)
        func runs(_ i: Int) -> Bool {
            let rule = rules[i]
            // Where a rule runs: 1 frames only; 10, 12, 20 and 22 the top
            // page only (autoconsent's shouldRunRuleInContext).
            let context = rule.count > 4 ? rule[4] as? Int ?? 0 : 0
            if mainFrame, context == 1 { return false }
            if !mainFrame, [10, 12, 20, 22].contains(context) { return false }
            if let pattern = patterns[i], pattern.firstMatch(in: url, range: whole) == nil { return false }
            return true
        }
        guard mainFrame else {
            let kept = frame.filter(runs)
            return ["v": version, "s": strings(whole: 0, and: kept), "r": kept.map { rules[$0] }]
        }
        let own = specific.filter(runs)
        guard !own.isEmpty else { return common }
        return ["v": version, "s": strings(whole: commonEnd, and: own), "r": Array(rules[generic]) + own.map { rules[$0] }]
    }
}
