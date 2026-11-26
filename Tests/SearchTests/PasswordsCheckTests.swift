import AppKit
import SwiftUI
import XCTest
@testable import Search

/// Reused and easy-to-guess passwords on the Passwords page, and the list
/// narrowed to them. Nothing here touches the keychain or asks the Mac who
/// anyone is: every account and password is made up, the passwords are read
/// out of a dictionary, and the Mac's question is a closure that says yes or
/// no. The page is drawn off screen, in no window.
@MainActor
final class PasswordsCheckTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func setUp() { _ = NSApplication.shared }

    // MARK: made up

    private static let long = "plum-Harbour-41-kettle"
    private static let other = "nine-Lanterns-ferry-08"

    private let tide = Kept(host: "tide.example", user: "ingrid.vik")
    private let calendar = Kept(host: "calendar.tide.example", user: "ingrid.vik")
    private let orbit = Kept(host: "orbit.example", user: "ingrid.vik")
    private let ledger = Kept(host: "ledger.example", user: "ingrid@vik.example")
    private let atlas = Kept(host: "atlas.example", user: "ingrid@vik.example")
    private let kart = Kept(host: "kart.example", user: "ingrid@vik.example")
    private let shop = Kept(host: "shop.kart.example", user: "ingrid@vik.example")
    private let kettle = Kept(host: "kettle.example", user: "ingrid@vik.example")

    private var accounts: [Kept] { [atlas, calendar, kart, kettle, ledger, orbit, shop, tide] }

    /// One password on three sites (and twice on one of them), one on two
    /// hosts of a single site, one that is easy to guess, one that is fine.
    private var passwords: [Kept.ID: String] {
        [tide.id: Self.long, calendar.id: Self.long, orbit.id: Self.long, ledger.id: Self.long,
         kart.id: Self.other, shop.id: Self.other,
         kettle.id: "qwerty123", atlas.id: "saffron-Gable-62-otter"]
    }

    /// The last two labels: every host here ends in .example.
    private static func site(_ host: String) -> String {
        host.split(separator: ".").suffix(2).joined(separator: ".")
    }

    private var sites: [String: String] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.host, Self.site($0.host)) })
    }

    private func found() -> PasswordWarnings {
        let passwords = self.passwords
        return PasswordWarnings.reading(accounts, sites: sites) { passwords[$0.id] }
    }

    private func why(_ password: String, user: String = "ingrid.vik", host: String = "tide.example") -> [Guessable] {
        PasswordRules.guessable(password, user: user, host: host, site: Self.site(host))
    }

    /// A look with made-up answers: whether the Mac says yes, and how many
    /// passwords were read.
    private final class Reads: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var read: Int { lock.withLock { count } }
        func one() { lock.withLock { count += 1 } }
    }

    private func check(says yes: Bool?, reads: Reads, read: (@Sendable (Kept) -> String?)? = nil) -> PasswordCheck {
        let passwords = self.passwords
        return PasswordCheck(
            prove: { _, done in if let yes { done(yes) } },
            read: { kept in
                reads.one()
                return read.map { $0(kept) } ?? passwords[kept.id]
            },
            site: Self.site)
    }

    private func settle(_ check: PasswordCheck) {
        let end = Date().addingTimeInterval(5)
        while check.checking, Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    // MARK: the rules

    func testAPasswordThatIsFineHasNothingSaidOfIt() {
        XCTAssertEqual(why(Self.long), [])
        XCTAssertEqual(why("saffron-Gable-62-otter", user: ""), [], "an account without a name is no one's name")
    }

    func testShort() {
        XCTAssertEqual(why("kv4!pz"), [.short])
        XCTAssertEqual(why("kv4!pzq"), [.short], "seven is short")
        XCTAssertEqual(why("kv4!pzqm"), [], "eight is not")
    }

    func testOneCharacterRepeated() {
        XCTAssertEqual(why("zzzzzzzzzz"), [.repeated])
        XCTAssertTrue(why("0000").contains(.repeated))
        XCTAssertFalse(why("zzzzzzzzzy").contains(.repeated))
    }

    func testARun() {
        XCTAssertEqual(why("hgfedcba"), [.run], "down as well as up")
        XCTAssertTrue(why("12345678").contains(.run))
        XCTAssertEqual(why("ertyuiop"), [.run], "along a row of the keyboard")
        XCTAssertEqual(why("lkjhgfds"), [.run], "and back along it")
        XCTAssertEqual(why("FGHIJKLM"), [.run], "in capitals too")
        XCTAssertEqual(why("abcdefgx"), [], "all of it, or it is no run")
    }

    func testOneOfTheMostCommon() {
        XCTAssertEqual(why("Password123"), [.common], "however it is capitalised")
        XCTAssertEqual(why("iloveyou"), [.common])
        XCTAssertEqual(Set(PasswordRules.common.map { $0.lowercased() }), PasswordRules.common, "kept in lower case")
        XCTAssertLessThan(PasswordRules.common.count, 250, "a short list")
    }

    func testTheSameAsTheUserNameOrTheSite() {
        XCTAssertEqual(why("ingrid.vik"), [.userName])
        XCTAssertEqual(why("Ingrid@Vik.example", user: "ingrid@vik.example"), [.userName])
        XCTAssertEqual(why("ingridvik", user: "ingridvik@vik.example"), [.userName], "the name before the @")
        XCTAssertEqual(why("tide.example", host: "calendar.tide.example"), [.siteName])
        XCTAssertEqual(why("calendar.tide.example", host: "calendar.tide.example"), [.siteName])
        XCTAssertEqual(why("lanternquay", host: "www.lanternquay.example"), [.siteName], "the name alone")
        XCTAssertEqual(why("tide"), [.short, .siteName], "every reason is given")
    }

    // MARK: reused

    func testOnePasswordOnTwoSitesOrMoreIsReused() {
        let found = found()
        XCTAssertEqual(found.others(of: tide), ["ledger.example", "orbit.example"])
        XCTAssertEqual(found.others(of: orbit), ["ledger.example", "tide.example"], "a site by its shortest host")
        XCTAssertEqual(found.others(of: calendar), ["ledger.example", "orbit.example"], "its own site is not another")
        XCTAssertTrue([tide, calendar, orbit, ledger].allSatisfy(found.isReused))
        XCTAssertFalse(found.isReused(atlas))
    }

    func testOneSignInOnTwoHostsOfASiteIsNotReused() {
        let found = found()
        XCTAssertFalse(found.isReused(kart))
        XCTAssertFalse(found.isReused(shop))
        XCTAssertEqual(found.others(of: kart), [])
    }

    func testEasyToGuessIsFoundBesideReused() {
        let found = found()
        XCTAssertEqual(found.whyGuessable(kettle), [.common])
        XCTAssertFalse(found.isGuessable(tide))
        XCTAssertEqual(found.says(of: kettle), "Easy to guess")
        XCTAssertEqual(found.says(of: tide), "Reused")
        XCTAssertNil(found.says(of: atlas))
        var both = passwords
        both[atlas.id] = "password"
        both[kettle.id] = "password"
        let again = PasswordWarnings.reading(accounts, sites: sites) { both[$0.id] }
        XCTAssertEqual(again.says(of: atlas), "Reused, easy to guess")
    }

    /// What is kept once the passwords are let go names accounts and
    /// reasons, and holds no password.
    func testWhatIsKeptHoldsNoPassword() {
        var written = ""
        dump(found(), to: &written)
        for password in Set(passwords.values) {
            XCTAssertFalse(written.contains(password))
        }
        XCTAssertTrue(written.contains("tide.example"), "the dump does show what is in it")
    }

    func testThreeRefusalsInARowEndIt() {
        var asked = 0
        let none = PasswordWarnings.reading(accounts, sites: sites) { _ in asked += 1; return nil }
        XCTAssertEqual(asked, 3, "a keychain that refuses isn't asked about every one")
        XCTAssertEqual(none.unread, accounts.count, "and what wasn't read is counted")
        XCTAssertTrue(accounts.allSatisfy { !none.flags($0) })

        let passwords = self.passwords
        asked = 0
        let some = PasswordWarnings.reading(accounts, sites: sites) { kept in
            asked += 1
            return asked % 3 == 0 ? nil : passwords[kept.id]
        }
        XCTAssertEqual(asked, accounts.count, "one refusal here and there doesn't")
        XCTAssertEqual(some.unread, accounts.count / 3)
    }

    // MARK: the list narrowed

    func testTheListNarrowedToAWarning() {
        let found = found()
        XCTAssertEqual(PasswordFilter.all.of(accounts, found), accounts)
        XCTAssertEqual(PasswordFilter.reused.of(accounts, found), [calendar, ledger, orbit, tide])
        XCTAssertEqual(PasswordFilter.guessable.of(accounts, found), [kettle])
    }

    func testNothingIsAWarningBeforeALook() {
        XCTAssertEqual(PasswordFilter.all.of(accounts, nil), accounts)
        XCTAssertEqual(PasswordFilter.reused.of(accounts, nil), [])
        XCTAssertEqual(PasswordFilter.guessable.of(accounts, nil), [])
    }

    func testTheWords() {
        XCTAssertEqual(PasswordWarnings.reusedTitle(1), "Reused on 1 other site")
        XCTAssertEqual(PasswordWarnings.reusedTitle(3), "Reused on 3 other sites")
        XCTAssertEqual(PasswordWarnings.reusedDetail(["a.example"]), "a.example has the same password.")
        XCTAssertEqual(PasswordWarnings.reusedDetail(["a.example", "b.example"]), "a.example and b.example have the same password.")
        XCTAssertEqual(PasswordWarnings.reusedDetail(["a.example", "b.example", "c.example", "d.example"]),
                       "a.example, b.example and 2 more have the same password.")
    }

    // MARK: asked for, and proved first

    func testNothingIsReadUntilTheMacSaysYes() {
        let reads = Reads()
        let waiting = check(says: nil, reads: reads)
        waiting.run(accounts)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(waiting.checking, "the question is still up")
        XCTAssertEqual(reads.read, 0)
        XCTAssertNil(waiting.warnings)

        let refused = check(says: false, reads: reads)
        refused.run(accounts)
        settle(refused)
        XCTAssertFalse(refused.checking)
        XCTAssertEqual(reads.read, 0, "a no reads nothing")
        XCTAssertNil(refused.warnings)
    }

    func testALookFindsThemOnceProved() {
        let reads = Reads()
        let check = check(says: true, reads: reads)
        XCTAssertNil(check.warnings)
        check.run(accounts)
        settle(check)
        XCTAssertEqual(reads.read, accounts.count, "each read once")
        XCTAssertEqual(check.warnings, found())
        check.forget()
        XCTAssertNil(check.warnings)
    }

    func testALookForgottenWhileReadingSaysNothing() {
        let reads = Reads()
        let long = Self.long
        let check = check(says: true, reads: reads) { _ in
            Thread.sleep(forTimeInterval: 0.02)
            return long
        }
        check.run(accounts)
        check.forget()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertNil(check.warnings)
        XCTAssertFalse(check.checking)
    }

    func testRemovingAccountsKeepsWhatStillHolds() {
        let check = check(says: true, reads: Reads())
        check.run(accounts)
        settle(check)
        // Orbit's gone: tide's password is still on ledger.
        check.listed(accounts.filter { $0 != orbit })
        XCTAssertEqual(check.warnings?.others(of: tide), ["ledger.example"])
        // Ledger's too: it is now on tide's own hosts alone, and no warning.
        check.listed(accounts.filter { $0 != orbit && $0 != ledger })
        XCTAssertNotNil(check.warnings)
        XCTAssertEqual(check.warnings?.isReused(tide), false)
        XCTAssertEqual(check.warnings?.isReused(calendar), false)
        check.listed(accounts.filter { ![orbit, ledger, kettle].contains($0) })
        XCTAssertEqual(check.warnings?.isGuessable(kettle), false)
    }

    func testAnythingElseReadAgainForgetsIt() {
        let saved = check(says: true, reads: Reads())
        saved.run(accounts)
        settle(saved)
        saved.listed(accounts)
        XCTAssertNil(saved.warnings, "the same accounts: one of their passwords may have been saved over")

        let added = check(says: true, reads: Reads())
        added.run(accounts)
        settle(added)
        added.listed(accounts + [Kept(host: "ord.example", user: "ingrid.vik")])
        XCTAssertNil(added.warnings, "one it never saw")

        let swapped = check(says: true, reads: Reads())
        swapped.run(accounts)
        settle(swapped)
        swapped.listed(accounts.dropLast() + [Kept(host: "ord.example", user: "ingrid.vik")])
        XCTAssertNil(swapped.warnings, "one gone and one new")
    }

    // MARK: the page

    /// The page as a tab draws it, with made-up accounts in place of the
    /// keychain's. Kept for the eye where a folder is named:
    /// LUN_PICTURES=/some/dir.
    private func picture(_ name: String, check: PasswordCheck, showing: PasswordFilter = .all, width: CGFloat = 1040, dark: Bool) throws -> NSBitmapImageRep {
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let page = PasswordsPanel(browser: browser, check: check, made: accounts, showing: showing)
            .environment(\.asTab, true)
            .frame(width: width, height: 620)
            .background(Palette.ground)
        let host = NSHostingView(rootView: page)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 620)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if let folder = ProcessInfo.processInfo.environment["LUN_PICTURES"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
        return rep
    }

    /// How many pixels are the warning's amber: red well over green, green
    /// well over blue, which Remove…'s red is not. Read from the bytes:
    /// asking for a colour a pixel at a time took most of a minute.
    private func amber(_ rep: NSBitmapImageRep) -> Int {
        guard let bytes = rep.bitmapData, rep.bitsPerSample == 8, rep.samplesPerPixel >= 3 else { return -1 }
        let first = rep.bitmapFormat.contains(.alphaFirst) ? 1 : 0
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let at = y * rep.bytesPerRow + x * rep.samplesPerPixel + first
                let red = Int(bytes[at]), green = Int(bytes[at + 1]), blue = Int(bytes[at + 2])
                if red - green > 30, green - blue > 30 { count += 1 }
            }
        }
        return count
    }

    func testThePageShowsNoWarningBeforeALookAndShowsThemAfter() throws {
        for dark in [false, true] {
            let before = check(says: true, reads: Reads())
            XCTAssertEqual(amber(try picture("passwords-before", check: before, dark: dark)), 0,
                           "nothing is said of any password until it is asked for")

            let after = check(says: true, reads: Reads())
            after.run(accounts)
            settle(after)
            XCTAssertGreaterThan(amber(try picture("passwords-after", check: after, dark: dark)), 40, "the signs are drawn")
            XCTAssertGreaterThan(amber(try picture("passwords-reused", check: after, showing: .reused, dark: dark)), 40)
            XCTAssertGreaterThan(amber(try picture("passwords-guessable", check: after, showing: .guessable, dark: dark)), 20)
            XCTAssertGreaterThan(amber(try picture("passwords-narrow", check: after, showing: .reused, width: 620, dark: dark)), 20)
            XCTAssertEqual(amber(try picture("passwords-narrow-before", check: before, width: 620, dark: dark)), 0)
        }
    }
}
