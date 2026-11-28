import Foundation
import SQLite3
import CryptoKit

// Where another browser is signed in.
//
// A Chromium browser keeps its cookies as it keeps its passwords: a SQLite
// file, "Cookies", each value wrapped with the key in "<Name> Safe Storage".
// Brought over, the sites you are signed in to there are signed in here.
// Only when asked for: Chromium keeps them behind that key and WebKit keeps
// its cookies without one, which is where they would land anyway the moment
// you signed in here yourself.
//
// The same rules as the passwords: the key is asked for once, the file is
// read from a copy, and nothing leaves this Mac. A cookie's name and value
// are never written anywhere but WebKit's store.

extension Chromium {
    struct SignIns {
        var cookies: [HTTPCookie] = []
        /// Left behind: ones that end when the other browser quits. Here
        /// they would only last until Lun did.
        var session = 0
        /// Left behind: ones kept for one site's pages alone (CHIPS). There
        /// is no making one of those in WebKit from outside, and one made
        /// without its partition would be sent where it never was.
        var partitioned = 0
        /// Ones that were there but didn't open with the key the keychain
        /// handed over, or weren't their host's: said, so an import that
        /// brought nothing says why.
        var unread = 0
    }

    /// The cookies of one profile, or of all of them when `profile` is nil:
    /// then a cookie two profiles both hold comes from the first. The key
    /// is the passwords', kept a minute, so both are one question.
    static func signIns(in source: Source, profile: String? = nil, now: Date = Date()) throws -> SignIns {
        guard source.importsPasswords else { throw Trouble.unreadable }
        // Newer profiles keep them under Network/, older ones beside Login Data.
        let files = source.profiles(only: profile).compactMap { folder in
            ["Network/Cookies", "Cookies"].compactMap { source.file($0, in: folder) }
                .first { FileManager.default.fileExists(atPath: $0.path) }
        }
        // No file, no keychain question.
        guard !files.isEmpty else { throw Trouble.unreadable }
        guard let key = storageKey(source) else { throw Trouble.noPassphrase }

        var out = SignIns()
        var seen = Set<String>()
        var readAny = false
        for file in files {
            guard let found = try? signIns(in: file, key: key, now: now) else { continue }
            readAny = true
            out.session += found.session
            out.partitioned += found.partitioned
            out.unread += found.unread
            for cookie in found.cookies where seen.insert("\(cookie.domain)\u{0}\(cookie.name)\u{0}\(cookie.path)").inserted {
                out.cookies.append(cookie)
            }
        }
        guard readAny else { throw Trouble.unreadable }
        return out
    }

    /// One "Cookies" file, with the key already stretched. Expired cookies
    /// are passed over without a word.
    static func signIns(in file: URL, key: [UInt8], now: Date = Date()) throws -> SignIns {
        // A copy, next to nothing the other browser is watching.
        let copy = try Snapshot(of: file)
        // Kept to the end: the copy goes with it, and SQLite is reading it.
        defer { withExtendedLifetime(copy) {} }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.file.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw Trouble.unreadable
        }
        defer { sqlite3_close(db) }

        // From version 24 of the file (August 2024) each value starts with
        // the SHA-256 of its host, so a value can't be moved to another
        // site's row.
        var version = 0
        var meta: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = 'version'", -1, &meta, nil) == SQLITE_OK,
           sqlite3_step(meta) == SQLITE_ROW {
            version = Int(sqlite3_column_int(meta, 0))
        }
        sqlite3_finalize(meta)

        let sql = """
        SELECT host_key, name, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite,
               top_frame_site_key, is_persistent
        FROM cookies
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw Trouble.unreadable
        }
        defer { sqlite3_finalize(statement) }

        var out = SignIns()
        while true {
            let status = sqlite3_step(statement)
            guard status != SQLITE_DONE else { break }
            guard status == SQLITE_ROW else { throw Trouble.unreadable }
            func text(_ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }

            guard text(8).isEmpty else {
                out.partitioned += 1
                continue
            }
            // Microseconds since 1601, Chromium's idea of a date.
            let stamp = sqlite3_column_int64(statement, 4)
            guard sqlite3_column_int(statement, 9) != 0, stamp > 0 else {
                out.session += 1
                continue
            }
            let expires = Date(timeIntervalSince1970: Double(stamp) / 1_000_000 - 11_644_473_600)
            guard expires > now else { continue }

            // The leading dot and all: it says the cookie is its domain's,
            // every name under it too, and without one its host's alone.
            let host = text(0)
            var blob = Data()
            if let bytes = sqlite3_column_blob(statement, 2) {
                blob = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 2)))
            }
            // Encrypted or not taken, as the passwords are: one lying in the
            // "value" column in the clear is not one the browser wrote.
            guard var plain = opened(blob, key: key) else {
                out.unread += 1
                continue
            }
            if version >= 24 {
                let hash = Data(SHA256.hash(data: Data(host.utf8)))
                guard plain.prefix(hash.count) == hash else {
                    out.unread += 1
                    continue
                }
                plain.removeFirst(hash.count)
            }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: host, .name: text(1), .path: text(3).isEmpty ? "/" : text(3), .expires: expires,
            ]
            if sqlite3_column_int(statement, 5) != 0 { properties[.secure] = "TRUE" }
            if sqlite3_column_int(statement, 6) != 0 { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            // 1 is Lax and 2 Strict. None (0) and no word at all (-1) are
            // both left unsaid, which is how WebKit keeps a cookie that came
            // either way.
            switch sqlite3_column_int(statement, 7) {
            case 1: properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax.rawValue
            case 2: properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict.rawValue
            default: break
            }
            guard let value = String(data: plain, encoding: .utf8) else {
                out.unread += 1
                continue
            }
            properties[.value] = value
            guard let cookie = HTTPCookie(properties: properties) else {
                out.unread += 1
                continue
            }
            out.cookies.append(cookie)
        }
        return out
    }
}

extension ImportSource {
    /// Whether its sign-ins can come over: a Chromium browser whose key
    /// Lun can ask for.
    var bringsSignIns: Bool {
        if case .chromium(let source) = self { return source.importsPasswords }
        return false
    }

    func signIns(profile: String? = nil) throws -> Chromium.SignIns {
        guard case .chromium(let source) = self else { throw Chromium.Trouble.unreadable }
        return try Chromium.signIns(in: source, profile: profile)
    }
}
