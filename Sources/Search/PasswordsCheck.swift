import AppKit
import Foundation

// Which kept passwords are worth a look: the same one on two sites or more,
// and ones that are easy to guess. Worked out on this Mac and nowhere else:
// no request is made, nothing is looked up, nothing is compared with a list
// of leaks. Only asked for, never on opening the page, and only once the Mac
// has said who is asking, as showing one password is.
//
// The passwords are read for the length of one pass and let go. What is kept
// afterwards is which accounts were found and why, in memory, until the page
// is put away or the Mac locks: never a password, nor anything made from
// one, and none of it is written or logged. Nothing here writes to the
// keychain.

/// Why a password is easy to guess. A handful of rules a person can check
/// by eye, and no score: each says what it saw.
enum Guessable: String, CaseIterable {
    case short, repeated, run, common, userName, siteName

    var says: String {
        switch self {
        case .short: return "Shorter than \(PasswordRules.least) characters."
        case .repeated: return "One character, repeated."
        case .run: return "A run of neighbouring characters or keys."
        case .common: return "One of the most common passwords."
        case .userName: return "The same as the user name."
        case .siteName: return "The same as the site's name."
        }
    }
}

enum PasswordRules {
    /// Fewer than this is short.
    static let least = 8

    /// Every reason `password` is easy to guess; none for one that isn't.
    /// `site` is the host's registrable domain (tide.example for
    /// calendar.tide.example).
    static func guessable(_ password: String, user: String, host: String, site: String) -> [Guessable] {
        let plain = password.lowercased()
        var why: [Guessable] = []
        if password.count < least { why.append(.short) }
        if isRepeat(password) { why.append(.repeated) }
        if isRun(plain) { why.append(.run) }
        if common.contains(plain) { why.append(.common) }
        if names(ofUser: user).contains(plain) { why.append(.userName) }
        if names(ofHost: host, site: site).contains(plain) { why.append(.siteName) }
        return why
    }

    /// One character and nothing else: aaaaaaaa, 00000000.
    static func isRepeat(_ password: String) -> Bool {
        guard password.count > 1, let first = password.first else { return false }
        return password.allSatisfy { $0 == first }
    }

    /// The rows of a keyboard, for a run along one: qwerty, asdfgh.
    private static let rows = ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"]

    /// The whole of it one run, up or down: 12345678, hgfedcba, or along a
    /// row of the keyboard. `password` in lower case.
    static func isRun(_ password: String) -> Bool {
        guard password.count >= 4 else { return false }
        if rows.contains(where: { $0.contains(password) || $0.contains(String(password.reversed())) }) { return true }
        let points = password.unicodeScalars.map(\.value)
        guard points.allSatisfy({ $0 < 128 }) else { return false }
        let steps = zip(points, points.dropFirst()).map { Int($1) - Int($0) }
        return steps.allSatisfy { $0 == 1 } || steps.allSatisfy { $0 == -1 }
    }

    /// What a user name is, written as a password: all of it, and what is
    /// before the @ of an address. Nothing for an account without a name.
    private static func names(ofUser user: String) -> Set<String> {
        let name = user.lowercased().trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return [] }
        var names: Set<String> = [name]
        if let at = name.firstIndex(of: "@"), at > name.startIndex { names.insert(String(name[..<at])) }
        return names
    }

    /// What a site is called: its host, its domain, and the name in front of
    /// the domain's ending (tide, of tide.example).
    private static func names(ofHost host: String, site: String) -> Set<String> {
        var names: Set<String> = [host.lowercased(), site.lowercased()]
        if let name = site.lowercased().split(separator: ".").first { names.insert(String(name)) }
        names.remove("")
        return names
    }

    /// The passwords most often found in use, as every yearly list of them
    /// has it, give or take: a short list, kept here, in lower case. Not a
    /// list of leaks, and nothing is fetched to add to it.
    static let common: Set<String> = [
        "123456", "1234567", "12345678", "123456789", "1234567890", "12345", "1234", "123", "12345678910",
        "987654321", "654321", "000000", "111111", "1111111", "11111111", "121212", "112233", "123123", "123321",
        "555555", "666666", "696969", "7777777", "88888888", "159753", "147258369",
        "password", "password1", "password12", "password123", "passw0rd", "p@ssw0rd", "p@ssword", "pass", "pass123",
        "passord", "passord1", "passord123",
        "qwerty", "qwerty1", "qwerty123", "qwertyuiop", "qwertz", "azerty", "asdfgh", "asdfghjkl", "zxcvbn", "zxcvbnm",
        "qazwsx", "1qaz2wsx", "zaq12wsx", "1q2w3e", "1q2w3e4r", "1q2w3e4r5t", "q1w2e3r4", "123qwe", "qwe123",
        "abc123", "abc12345", "abcd1234", "1234abcd", "a123456", "aa123456", "123456a", "abcdef", "abcdefgh",
        "admin", "admin1", "admin123", "admin1234", "administrator", "root", "toor", "guest", "user", "login",
        "test", "test123", "default", "changeme", "secret", "access", "master", "letmein", "letmein1",
        "welcome", "welcome1", "welcome123", "hello", "hello123", "iloveyou", "iloveyou1", "trustno1", "whatever",
        "monkey", "dragon", "shadow", "sunshine", "princess", "superman", "batman", "starwars", "pokemon",
        "football", "baseball", "soccer", "hockey", "liverpool", "chelsea", "arsenal", "mustang", "killer",
        "freedom", "flower", "cheese", "cookie", "banana", "chocolate", "ginger", "pepper", "summer", "winter",
        "computer", "internet", "google", "samsung", "hunter", "hunter2", "lovely",
        "michael", "jordan", "charlie", "donald", "ashley", "jessica", "daniel", "andrew", "thomas", "robert",
        "george", "jennifer", "michelle", "nicole",
    ]
}

/// What one look through the kept passwords found. It holds accounts and
/// reasons: no password, and nothing made from one.
struct PasswordWarnings: Equatable {
    /// Accounts with one password between them, on two sites or more: one
    /// group for each such password.
    private(set) var shared: [[Kept]] = []
    private(set) var guessable: [Kept.ID: [Guessable]] = [:]
    /// Every account there was when it was looked through.
    private(set) var seen: Set<Kept.ID> = []
    /// How many the keychain didn't hand over: those are not judged.
    private(set) var unread = 0
    /// The site each host belongs to, as it was worked out for the look.
    private var sites: [String: String] = [:]

    private func site(_ host: String) -> String { sites[host] ?? host }

    /// The hosts on other sites that have this account's password, one for
    /// each site (its shortest), in order. None for a password used on this
    /// site alone: one sign-in on two hosts of a site is not a password
    /// used twice.
    func others(of kept: Kept) -> [String] {
        guard let group = shared.first(where: { $0.contains { $0.id == kept.id } }) else { return [] }
        let mine = site(kept.host)
        var named: [String: String] = [:]
        for other in group where site(other.host) != mine {
            let its = site(other.host)
            guard let now = named[its] else {
                named[its] = other.host
                continue
            }
            if (other.host.count, other.host) < (now.count, now) { named[its] = other.host }
        }
        return named.values.sorted()
    }

    func isReused(_ kept: Kept) -> Bool { shared.contains { $0.contains { $0.id == kept.id } } }
    func whyGuessable(_ kept: Kept) -> [Guessable] { guessable[kept.id] ?? [] }
    func isGuessable(_ kept: Kept) -> Bool { guessable[kept.id] != nil }
    func flags(_ kept: Kept) -> Bool { isReused(kept) || isGuessable(kept) }

    /// Reads each account's password with `read`, judges them, and lets
    /// them go: nothing read leaves this call. Three refusals in a row end
    /// it, so that a keychain which asks about every item isn't answered
    /// four hundred times; what wasn't read is counted and not judged.
    static func reading(_ accounts: [Kept], sites: [String: String], read: (Kept) -> String?) -> PasswordWarnings {
        var held: [(kept: Kept, password: String)] = []
        var refused = 0, unread = 0
        for (index, account) in accounts.enumerated() {
            guard let password = read(account) else {
                unread += 1
                refused += 1
                if refused == 3 {
                    unread += accounts.count - index - 1
                    break
                }
                continue
            }
            refused = 0
            held.append((account, password))
        }
        var found = of(held, sites: sites)
        found.seen = Set(accounts.map(\.id))
        found.unread = unread
        return found
    }

    /// The judging alone, of passwords already in hand.
    static func of(_ held: [(kept: Kept, password: String)], sites: [String: String]) -> PasswordWarnings {
        var found = PasswordWarnings()
        found.sites = sites
        found.seen = Set(held.map(\.kept.id))
        // By the password itself, for the length of this call.
        var same: [String: [Kept]] = [:]
        for (kept, password) in held {
            same[password, default: []].append(kept)
            let why = PasswordRules.guessable(password, user: kept.user, host: kept.host, site: found.site(kept.host))
            if !why.isEmpty { found.guessable[kept.id] = why }
        }
        found.shared = same.values.map { $0.sorted { $0.id < $1.id } }.sorted { ($0.first?.id ?? "") < ($1.first?.id ?? "") }
        found.settle()
        return found
    }

    /// A group is a warning only while it spans two sites.
    private mutating func settle() {
        let sites = self.sites
        shared.removeAll { Set($0.map { sites[$0.host] ?? $0.host }).count < 2 }
    }

    /// What is still true once accounts have been removed: `left` is what
    /// the list holds now. Nil when it holds anything this never saw, or
    /// may hold a password changed since: then it is all out of date.
    func pruned(to left: [Kept]) -> PasswordWarnings? {
        let ids = Set(left.map(\.id))
        guard ids.isSubset(of: seen), ids != seen else { return nil }
        var now = self
        now.seen = ids
        now.shared = shared.map { $0.filter { ids.contains($0.id) } }
        now.guessable = guessable.filter { ids.contains($0.key) }
        now.settle()
        return now
    }
}

extension PasswordWarnings {
    /// What the page says before a look is asked for, and after one.
    static let before = "Passwords used on more than one site, and ones that are easy to guess. Worked out on this Mac: nothing is sent."
    static let after = "Worked out on this Mac. Nothing was sent."

    static func unread(_ count: Int) -> String {
        count == 1 ? "The keychain kept 1 back: it isn't judged." : "The keychain kept \(count) back: they aren't judged."
    }

    /// What was found about one account, for its row; nil for nothing.
    func says(of kept: Kept) -> String? {
        let words = [isReused(kept) ? PasswordFilter.reused.title : nil, isGuessable(kept) ? PasswordFilter.guessable.title : nil]
            .compactMap { $0 }
        guard let first = words.first else { return nil }
        return ([first] + words.dropFirst().map { $0.lowercased() }).joined(separator: ", ")
    }

    static func reusedTitle(_ sites: Int) -> String {
        sites == 1 ? "Reused on 1 other site" : "Reused on \(sites) other sites"
    }

    /// The first two by name, the rest counted.
    static func reusedDetail(_ hosts: [String]) -> String {
        switch hosts.count {
        case 0: return ""
        case 1: return "\(hosts[0]) has the same password."
        case 2: return "\(hosts[0]) and \(hosts[1]) have the same password."
        default: return "\(hosts[0]), \(hosts[1]) and \(hosts.count - 2) more have the same password."
        }
    }
}

/// Which of the accounts the list shows.
enum PasswordFilter: Hashable, CaseIterable {
    case all, reused, guessable

    var title: String {
        switch self {
        case .all: return "All"
        case .reused: return "Reused"
        case .guessable: return "Easy to guess"
        }
    }

    /// What the list says when this leaves nothing.
    var nothing: String {
        switch self {
        case .all: return "Nothing matches."
        case .reused: return "No password is used on more than one site."
        case .guessable: return "None that are easy to guess."
        }
    }

    /// Without a look having been taken, the two warnings hold nothing:
    /// nothing is known about any password before that.
    func holds(_ kept: Kept, _ warnings: PasswordWarnings?) -> Bool {
        switch self {
        case .all: return true
        case .reused: return warnings?.isReused(kept) ?? false
        case .guessable: return warnings?.isGuessable(kept) ?? false
        }
    }

    func of(_ accounts: [Kept], _ warnings: PasswordWarnings?) -> [Kept] {
        self == .all ? accounts : accounts.filter { holds($0, warnings) }
    }
}

/// The look itself, for the Passwords page: asked for there, proved the way
/// showing a password is, and forgotten when the page is put away, when the
/// list may have changed under it, and when the Mac sleeps or locks.
@MainActor
final class PasswordCheck: ObservableObject {
    /// What the last look found; nil before one, and once it is forgotten.
    @Published private(set) var warnings: PasswordWarnings?
    /// Asking who this is, or reading.
    @Published private(set) var checking = false

    private let prove: @MainActor (String, @escaping (Bool) -> Void) -> Void
    private let read: (Kept) -> String?
    private let site: (String) -> String
    /// A look that was forgotten while it was still reading says nothing.
    private var round = 0
    private var watch: Watch?

    /// The Mac's own question and the keychain, unless a test brings its
    /// own of each: a test's never reach either.
    init(prove: @escaping @MainActor (String, @escaping (Bool) -> Void) -> Void = { Vault.prove($0, $1) },
         read: @escaping (Kept) -> String? = { Vault.secret(of: $0) },
         site: @escaping (String) -> String = { Vault.registrable($0) }) {
        self.prove = prove
        self.read = read
        self.site = site
        watch = Watch { [weak self] in MainActor.assumeIsolated { self?.forget() } }
    }

    /// Asks the Mac who this is, and only then reads: a no, or a cancel,
    /// reads nothing and finds nothing.
    func run(_ accounts: [Kept]) {
        guard !checking, !accounts.isEmpty else { return }
        checking = true
        round += 1
        let mine = round
        prove("look for reused and easy-to-guess passwords") { [weak self] ok in
            guard let self, self.round == mine else { return }
            guard ok else {
                self.checking = false
                return
            }
            let read = self.read
            let sites = Dictionary(accounts.map { ($0.host, self.site($0.host)) }, uniquingKeysWith: { first, _ in first })
            // A keychain read is a few milliseconds, a few hundred of them
            // a second: off the main thread, as Remove All… is.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let found = PasswordWarnings.reading(accounts, sites: sites, read: read)
                DispatchQueue.main.async {
                    guard let self, self.round == mine else { return }
                    self.checking = false
                    self.warnings = found
                }
            }
        }
    }

    /// Gone, and a look still under way with it.
    func forget() {
        round += 1
        checking = false
        if warnings != nil { warnings = nil }
    }

    /// The list was read again. Accounts only removed: what was found
    /// about the rest still holds. Anything else, a password saved or
    /// brought in, and what was found may no longer be true: forgotten,
    /// to be asked for again.
    func listed(_ accounts: [Kept]) {
        guard let found = warnings else {
            if checking { forget() }
            return
        }
        if let left = found.pruned(to: accounts) { warnings = left } else { forget() }
    }

    /// The Mac going to sleep, locking, or handed to someone else.
    private final class Watch {
        private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

        init(_ spend: @escaping () -> Void) {
            let workspace = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification,
                         NSWorkspace.sessionDidResignActiveNotification] {
                tokens.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { _ in spend() }))
            }
            let everywhere = DistributedNotificationCenter.default()
            tokens.append((everywhere, everywhere.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in spend() }))
        }

        deinit { tokens.forEach { $0.0.removeObserver($0.1) } }
    }
}
