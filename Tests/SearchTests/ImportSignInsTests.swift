import CommonCrypto
import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import Search

/// Another Chromium browser's cookies (ImportSignIns.swift), read from a
/// "Cookies" file made here with a key made here: never a real browser's,
/// never the keychain.
final class ImportSignInsTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        TestWorld.enter()
    }

    private let key = Chromium.stretchedKey("search-test-secret")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var later: Date { now.addingTimeInterval(86_400 * 30) }

    func testVersion24CookiesComeAsTheyWere() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Cookies")
        try Self.write([
            Row(host: ".example.com", name: "sid", value: "s3cret", expires: later, secure: true, httpOnly: true, sameSite: 1),
            Row(host: "app.example.com", name: "seat", value: "", path: "/account", expires: later, sameSite: 2),
            Row(host: "none.example.com", name: "open", value: "a=b", expires: later, secure: true, sameSite: 0),
            Row(host: "unsaid.example.com", name: "plain", value: "ø", expires: later, sameSite: -1),
            Row(host: "old.example.com", name: "gone", value: "x", expires: now.addingTimeInterval(-60)),
            Row(host: "tab.example.com", name: "visit", value: "x", expires: nil),
            Row(host: "widget.example.com", name: "chips", value: "x", expires: later, partition: "https://shop.example"),
            Row(host: "bank.example.com", name: "moved", value: "x", expires: later, hashedFor: "evil.example.com"),
            Row(host: "clear.example.com", name: "planted", value: "x", expires: later, inTheClear: true),
        ], to: file, version: 24, key: key)

        let found = try Chromium.signIns(in: file, key: key, now: now)
        XCTAssertEqual(found.cookies.map(\.name), ["sid", "seat", "open", "plain"])
        XCTAssertEqual(found.session, 1, "one that ends with the session is left behind, and counted")
        XCTAssertEqual(found.partitioned, 1, "a partitioned one is left behind, and counted")
        XCTAssertEqual(found.unread, 2, "a value under another host's hash, and one never encrypted")

        let sid = found.cookies[0]
        XCTAssertEqual(sid.domain, ".example.com", "its domain's, and every name under it")
        XCTAssertEqual(sid.value, "s3cret", "the host's hash is checked and gone")
        XCTAssertEqual(sid.path, "/")
        XCTAssertTrue(sid.isSecure)
        XCTAssertTrue(sid.isHTTPOnly)
        XCTAssertEqual(sid.sameSitePolicy, .sameSiteLax)
        XCTAssertEqual(try XCTUnwrap(sid.expiresDate).timeIntervalSince1970, later.timeIntervalSince1970, accuracy: 1)
        XCTAssertFalse(sid.isSessionOnly)

        let seat = found.cookies[1]
        XCTAssertEqual(seat.domain, "app.example.com", "its host's alone")
        XCTAssertEqual(seat.value, "")
        XCTAssertEqual(seat.path, "/account")
        XCTAssertFalse(seat.isSecure)
        XCTAssertFalse(seat.isHTTPOnly)
        XCTAssertEqual(seat.sameSitePolicy, .sameSiteStrict)

        XCTAssertNil(found.cookies[2].sameSitePolicy, "SameSite=None is kept as WebKit keeps it: unsaid")
        XCTAssertTrue(found.cookies[2].isSecure)
        XCTAssertNil(found.cookies[3].sameSitePolicy)
        XCTAssertEqual(found.cookies[3].value, "ø")
    }

    func testBeforeVersion24ThereIsNoHashToStrip() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Cookies")
        try Self.write([Row(host: ".example.com", name: "sid", value: String(repeating: "v", count: 40), expires: later)],
                       to: file, version: 23, key: key)

        let found = try Chromium.signIns(in: file, key: key, now: now)
        XCTAssertEqual(found.cookies.map(\.value), [String(repeating: "v", count: 40)])
        XCTAssertEqual(found.unread, 0)
    }

    func testWrongKeyBringsNothingAndSaysSo() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Cookies")
        // Enough of them that one in 256 opens by luck, its padding right:
        // the host's hash is what turns that one away.
        let rows = (0..<600).map { Row(host: "site\($0).example.com", name: "sid", value: "value-\($0)", expires: later) }
        try Self.write(rows, to: file, version: 24, key: key)

        let found = try Chromium.signIns(in: file, key: Chromium.stretchedKey("another-secret"), now: now)
        XCTAssertTrue(found.cookies.isEmpty)
        XCTAssertEqual(found.unread, 600)
    }

    func testNotACookieFileIsUnreadable() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Cookies")
        try Data("not a database".utf8).write(to: file)
        XCTAssertThrowsError(try Chromium.signIns(in: file, key: key, now: now))
    }

    func testProfilesAreReadWithTheBrowsersKeyAskedForOnce() throws {
        let root = try Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        // A test run's browser keeps its key beside its profiles.
        try Data("search-test-secret".utf8).write(to: root.appendingPathComponent("Safe Storage"))
        for (profile, inside, value) in [("Default", "Network", "first"), ("Profile 1", "", "second")] {
            let folder = root.appendingPathComponent(profile).appendingPathComponent(inside)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: root.appendingPathComponent(profile).appendingPathComponent("Bookmarks"))
            try Self.write([
                Row(host: ".example.com", name: "sid", value: value, expires: later),
                Row(host: "\(value).example.com", name: "own", value: value, expires: later),
            ], to: folder.appendingPathComponent("Cookies"), version: 24, key: key)
        }
        // A name of its own: the key is kept a minute under it.
        let name = "Fixture \(UUID().uuidString)"
        let source = Chromium.Source(name: "Fixture", folder: "", service: name, account: "Fixture", app: "", rootOverride: root)

        let asked = Chromium.keyAsks
        let one = try Chromium.signIns(in: source, profile: "Profile 1", now: now)
        XCTAssertEqual(one.cookies.map(\.value), ["second", "second"], "beside Login Data, where older profiles keep them")
        let all = try ImportSource.chromium(source).signIns()
        XCTAssertEqual(all.cookies.count, 3, "a cookie two profiles hold comes once")
        XCTAssertEqual(Set(all.cookies.filter { $0.name == "own" }.map(\.value)), ["first", "second"])
        XCTAssertEqual(Chromium.keyAsks - asked, 1, "the key is asked for once")

        XCTAssertTrue(ImportSource.chromium(source).bringsSignIns)
    }

    func testNoCookieFileAsksForNoKey() throws {
        let root = try Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = root.appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: profile.appendingPathComponent("Bookmarks"))
        try Data("search-test-secret".utf8).write(to: root.appendingPathComponent("Safe Storage"))
        let source = Chromium.Source(name: "Fixture", folder: "", service: "Fixture \(UUID().uuidString)", account: "Fixture", app: "",
                                     rootOverride: root)

        let asked = Chromium.keyAsks
        XCTAssertThrowsError(try Chromium.signIns(in: source, now: now)) { error in
            guard case Chromium.Trouble.unreadable = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(Chromium.keyAsks, asked)

        // And a browser whose key Lun can't ask for isn't offered at all.
        var keyless = source
        keyless.importsPasswords = false
        XCTAssertFalse(ImportSource.chromium(keyless).bringsSignIns)
        XCTAssertThrowsError(try Chromium.signIns(in: keyless, now: now))
    }

    func testKeyNotHandedOverSaysSo() throws {
        let root = try Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = root.appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: profile.appendingPathComponent("Bookmarks"))
        try Self.write([Row(host: ".example.com", name: "sid", value: "x", expires: later)],
                       to: profile.appendingPathComponent("Cookies"), version: 24, key: key)
        // No "Safe Storage" beside the profiles: the key isn't handed over.
        let source = Chromium.Source(name: "Fixture", folder: "", service: "Fixture \(UUID().uuidString)", account: "Fixture", app: "",
                                     rootOverride: root)
        XCTAssertThrowsError(try Chromium.signIns(in: source, now: now)) { error in
            guard case Chromium.Trouble.noPassphrase = error else { return XCTFail("\(error)") }
        }
    }

    /// Into the store of the space on screen, a signed-out space's own and
    /// not its profile's, and out of WebKit again as Chromium had them.
    @MainActor
    func testCookiesLandInTheSpacesOwnStoreAsTheyWere() async throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Cookies")
        try Self.write([
            Row(host: ".sign-ins.example", name: "sid", value: "s3cret", expires: later, secure: true, httpOnly: true, sameSite: 1),
            Row(host: "app.sign-ins.example", name: "seat", value: "7", path: "/account", expires: later, sameSite: 2),
            Row(host: "app.sign-ins.example", name: "open", value: "1", expires: later, secure: true, sameSite: 0),
        ], to: file, version: 24, key: key)
        let found = try Chromium.signIns(in: file, key: key, now: now)

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        let oldUsesSpaces = browser.prefs.usesSpaces
        browser.prefs.usesSpaces = true
        browser.addSpace(named: "Signed out", sharesSignIns: false)
        let own = browser.spaceID
        defer {
            browser.deleteSpace(own)
            browser.closeAll()
            browser.prefs.usesSpaces = oldUsesSpaces
        }
        XCTAssertTrue(Spaces.ownsStore(own))

        await withCheckedContinuation { done in browser.takeSignIns(found) { done.resume() } }

        func ours(_ cookies: [HTTPCookie]) -> [HTTPCookie] {
            cookies.filter { $0.domain.hasSuffix("sign-ins.example") }.sorted { $0.name > $1.name }
        }
        let shared = ours(await Profiles.store(browser.profileID).httpCookieStore.allCookies())
        XCTAssertTrue(shared.isEmpty, "the profile's other spaces are not signed in by it")
        let landed = ours(await Spaces.store(for: own).httpCookieStore.allCookies())
        XCTAssertEqual(landed.map(\.name), ["sid", "seat", "open"])
        guard landed.count == 3 else { return }

        XCTAssertEqual(landed[0].domain, ".sign-ins.example")
        XCTAssertEqual(landed[0].value, "s3cret")
        XCTAssertTrue(landed[0].isSecure)
        XCTAssertTrue(landed[0].isHTTPOnly)
        XCTAssertEqual(landed[0].sameSitePolicy, .sameSiteLax)
        XCTAssertEqual(try XCTUnwrap(landed[0].expiresDate).timeIntervalSince1970, later.timeIntervalSince1970, accuracy: 1)

        XCTAssertEqual(landed[1].domain, "app.sign-ins.example", "host-only stays host-only")
        XCTAssertEqual(landed[1].path, "/account")
        XCTAssertFalse(landed[1].isSecure)
        XCTAssertFalse(landed[1].isHTTPOnly)
        XCTAssertEqual(landed[1].sameSitePolicy, .sameSiteStrict)

        XCTAssertNil(landed[2].sameSitePolicy)
        XCTAssertTrue(landed[2].isSecure)
    }

    // MARK: - a Cookies file, as Chromium writes it

    struct Row {
        var host: String
        var name: String
        var value: String
        var path = "/"
        /// Nil for one that ends with the session.
        var expires: Date?
        var secure = false
        var httpOnly = false
        var sameSite: Int32 = -1
        var partition = ""
        /// The host whose hash goes before the value, when not its own.
        var hashedFor: String?
        /// In the "value" column, with nothing encrypted.
        var inTheClear = false
    }

    private static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("search-sign-ins-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// "v10", then AES-128-CBC under sixteen spaces; from version 24 the
    /// SHA-256 of the host goes before the value.
    private static func wrap(_ value: String, host: String?, key: [UInt8]) -> Data {
        var plain = Data()
        if let host { plain += Data(SHA256.hash(data: Data(host.utf8))) }
        plain += Data(value.utf8)
        let body = [UInt8](plain)
        let iv = [UInt8](repeating: 0x20, count: 16)
        var out = [UInt8](repeating: 0, count: body.count + kCCBlockSizeAES128)
        var moved = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding),
                             key, key.count, iv, body, body.count, &out, out.count, &moved)
        XCTAssertEqual(status, CCCryptorStatus(kCCSuccess))
        return Data("v10".utf8) + Data(out.prefix(moved))
    }

    /// Chromium's own table (net/extras/sqlite/sqlite_persistent_cookie_store.cc,
    /// CreateV24Schema), and its "meta" beside it.
    private static func write(_ rows: [Row], to file: URL, version: Int, key: [UInt8]) throws {
        var db: OpaquePointer?
        guard sqlite3_open(file.path, &db) == SQLITE_OK, let db else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_close(db) }
        let schema = """
        CREATE TABLE meta(key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR);
        INSERT INTO meta VALUES ('version', '\(version)'), ('last_compatible_version', '\(version)');
        CREATE TABLE cookies(creation_utc INTEGER NOT NULL, host_key TEXT NOT NULL, top_frame_site_key TEXT NOT NULL,
          name TEXT NOT NULL, value TEXT NOT NULL, encrypted_value BLOB NOT NULL, path TEXT NOT NULL,
          expires_utc INTEGER NOT NULL, is_secure INTEGER NOT NULL, is_httponly INTEGER NOT NULL,
          last_access_utc INTEGER NOT NULL, has_expires INTEGER NOT NULL, is_persistent INTEGER NOT NULL,
          priority INTEGER NOT NULL, samesite INTEGER NOT NULL, source_scheme INTEGER NOT NULL,
          source_port INTEGER NOT NULL, last_update_utc INTEGER NOT NULL, source_type INTEGER NOT NULL,
          has_cross_site_ancestor INTEGER NOT NULL);
        """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        var statement: OpaquePointer?
        let sql = """
        INSERT INTO cookies VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 0, ?11, ?11, 1, ?12, 2, 443, 0, 1, 0)
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, row) in rows.enumerated() {
            sqlite3_reset(statement)
            sqlite3_bind_int64(statement, 1, Int64(index + 1))
            sqlite3_bind_text(statement, 2, row.host, -1, transient)
            sqlite3_bind_text(statement, 3, row.partition, -1, transient)
            sqlite3_bind_text(statement, 4, row.name, -1, transient)
            sqlite3_bind_text(statement, 5, row.inTheClear ? row.value : "", -1, transient)
            let blob = row.inTheClear ? Data() : wrap(row.value, host: version >= 24 ? row.hashedFor ?? row.host : nil, key: key)
            _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, 6, $0.baseAddress, Int32(blob.count), transient) }
            sqlite3_bind_text(statement, 7, row.path, -1, transient)
            // Microseconds since 1601.
            sqlite3_bind_int64(statement, 8, row.expires.map { Int64(($0.timeIntervalSince1970 + 11_644_473_600) * 1_000_000) } ?? 0)
            sqlite3_bind_int(statement, 9, row.secure ? 1 : 0)
            sqlite3_bind_int(statement, 10, row.httpOnly ? 1 : 0)
            sqlite3_bind_int(statement, 11, row.expires == nil ? 0 : 1)
            sqlite3_bind_int(statement, 12, row.sameSite)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw CocoaError(.fileWriteUnknown) }
        }
    }
}
