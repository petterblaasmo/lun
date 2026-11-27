import Foundation
import WebKit

// Where everything this browser keeps is kept.
//
// One place, and one rule: a run started for testing never touches the folder
// or the settings of the browser somebody is actually using. Sharing them once
// cost a person their pinned tabs, which is not a mistake worth being able to
// make twice.

enum Store {
    /// A run is a test run if it says so, or if it is being run straight out
    /// of the build folder rather than from an installed app. The second half
    /// is not belt and braces: a development build launched from a terminal
    /// once wrote over somebody's real session, and asking a person to
    /// remember a flag is not a safeguard.
    ///
    /// Asked a hundred thousand times in a launch's first seconds with
    /// hundreds of tabs: read with getenv, not ProcessInfo's environment,
    /// which is a fresh dictionary of every variable at each call (13 MB
    /// allocated and freed again in ten seconds at 400 tabs), and still
    /// read each time, as a unit test sets SEARCH_PROBE before its world.
    static var testing: Bool { getenv("SEARCH_PROBE") != nil || fromBuildFolder }
    private static let fromBuildFolder = Bundle.main.executablePath?.contains("/.build/") == true

    /// Which test world a test run lives in. SEARCH_PROBE=1, or a run from
    /// the build folder, is the test world, "Lun (test)". SEARCH_PROBE=
    /// <name> is a world of its own, "Lun (<name>)", with settings and
    /// WebKit stores of its own: two sessions testing at once, or a
    /// measurement that needs a browser nobody has installed anything in,
    /// never borrow each other's. Nil for the browser somebody is using.
    static let world: String? = {
        guard testing else { return nil }
        let asked = (ProcessInfo.processInfo.environment["SEARCH_PROBE"] ?? "").lowercased()
            .filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" }
        return asked.isEmpty || asked == "1" || asked == "test" ? "test" : asked
    }()

    /// A test run there to be weighed and timed rather than driven
    /// (SEARCH_MEASURE beside SEARCH_PROBE). It keeps what the shipped
    /// browser does where test runs otherwise differ — hidden pages slowed
    /// the way WebKit slows them, App Nap left to macOS — so what gets
    /// measured is what people get.
    static var measuring: Bool {
        testing && getenv("SEARCH_MEASURE") != nil
    }

    /// Cookies, sign-ins, caches. WebKit keeps its default store per bundle,
    /// not per folder, so a test run got every site already signed in — and
    /// "sign out of everything" in a test run signed the real browser out.
    /// A test run gets a store of its own, under a fixed name so it persists
    /// between probes the way the real one does. Wiping the test store is
    /// then as safe as wiping its folder.
    static var websites: WKWebsiteDataStore {
        guard testing, !ownContainer else { return .default() }
        return WKWebsiteDataStore(forIdentifier: probeStore(1))
    }

    /// Settings › Privacy › Prevent cross-site tracking, turned off. WebKit's
    /// tracking prevention, as in Safari, clears what a site it has seen
    /// redirect you — a sign-in through Google or Apple, say — left in local
    /// storage once you haven't opened it for a week or a month of use, and a
    /// site it counts as a tracker loses its cookies too: you are signed out.
    /// Turned off, that stops, and so does the rest of it: a site framed in
    /// another gets its cookies again, so trackers can follow you across
    /// sites, as in Chrome. On unless turned off; until then its flag is not
    /// touched.
    @MainActor static var keepsSignIns = false {
        didSet {
            guard keepsSignIns != oldValue else { return }
            Spaces.everyStore.forEach(followSignIns)
        }
    }

    /// The switch through a name outside the public framework — Safari's
    /// "Prevent cross-site tracking" is the same one.
    @MainActor static func followSignIns(_ store: WKWebsiteDataStore) {
        followCookies(store)
        let set = NSSelectorFromString("_setResourceLoadStatisticsEnabled:")
        guard store.responds(to: set) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(store.method(for: set), to: Setter.self)(store, set, !keepsSignIns)
    }

    /// Something done to a page through Search's own controls on its behalf
    /// — the floating video's play, pause and skip, the player at the foot
    /// of the sidebar, ⇧⌘M — counted as using the site, as a click on the
    /// page is. Tracking prevention (above) wipes a site it counts as a
    /// tracker once nobody has used it for 30 days, and youtube.com, framed
    /// on every other site, is one: someone who only ever watched, pausing
    /// from the floating video, was signed out every few weeks. A script
    /// run in the page never counts, even with the gesture WebKit lends it
    /// (measured), so it is told so through a name outside the public
    /// framework, the one Safari's own testing uses. Only for a site's own
    /// http(s) page, and only while tracking prevention is on.
    @MainActor static func interacted(with web: WKWebView) {
        guard !keepsSignIns, let url = web.url else { return }
        interacted(with: url, in: web.configuration.websiteDataStore)
    }

    @MainActor static func interacted(with url: URL, in store: WKWebsiteDataStore, done: @escaping () -> Void = {}) {
        let log = NSSelectorFromString("_logUserInteraction:completionHandler:")
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host() != nil,
              store.responds(to: log) else { return done() }
        typealias Log = @convention(c) (AnyObject, Selector, NSURL, @escaping @convention(block) () -> Void) -> Void
        unsafeBitCast(store.method(for: log), to: Log.self)(store, log, url as NSURL, done)
    }

    /// Off, the store's cookie policy is Always too: left as it was, it took
    /// cookies only from the page's own site, and a site framed in another —
    /// a Kaltura video in a Brightspace course — still got none. WebKit keeps
    /// the policy with the store, so it is set back when the switch is on, and
    /// at launch for every store, which an earlier run may have left at Always.
    @MainActor static func followCookies(_ store: WKWebsiteDataStore) {
        let jar = store.httpCookieStore
        let policy = NSSelectorFromString("_setCookieAcceptPolicy:completionHandler:")
        guard jar.responds(to: policy) else { return }
        typealias Policy = @convention(c) (AnyObject, Selector, UInt, @escaping @convention(block) () -> Void) -> Void
        let accept: HTTPCookie.AcceptPolicy = keepsSignIns ? .always : .onlyFromMainDocumentDomain
        unsafeBitCast(jar.method(for: policy), to: Policy.self)(jar, policy, accept.rawValue) {}
    }

    /// A test copy of the app under a bundle id of its own has a WebKit
    /// container of its own too, so it can use WebKit's default store and
    /// extension configuration — the ones the real browser uses, which
    /// differ from stores made by identifier in how long extension workers
    /// are let live.
    static var ownContainer: Bool {
        (Bundle.main.bundleIdentifier ?? "") != "com.lunbrowser.lun"
    }

    /// The fixed identifiers of a test world's WebKit stores: 1 for websites,
    /// 2 for extensions. The test world's are 5E4C0000-0000-4000-8000-00000000000k,
    /// the ones fresh.sh wipes; a named world puts a hash of its name (FNV-1a,
    /// 32 bits) in place of the second and third groups of zeros, so each
    /// keeps its own from one run to the next.
    static func probeStore(_ kind: UInt32) -> UUID {
        var hash: UInt32 = 0
        if let world, world != "test" {
            hash = 2_166_136_261
            for byte in world.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        }
        let text = String(format: "5E4C%04X-%04X-4000-8000-%012X", hash >> 16, hash & 0xFFFF, kind)
        return UUID(uuidString: text)!
    }

    /// Lun's own, never Search's: the two run beside each other, so nothing
    /// is moved or copied here from the browser it came from.
    static let folder: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent(world.map { "Lun (\($0))" } ?? "Lun", isDirectory: true)
    }()

    static func file(_ name: String) -> URL {
        folder.appendingPathComponent(name)
    }

    /// A file that didn't decode is set aside rather than overwritten the
    /// next time something is saved over it — bookmarks, history and a
    /// session are the kind of thing nobody wants to lose to a bad read with
    /// no trace of what was there. Failing to move it is fine: the read
    /// already came back empty either way, and there's nothing further to
    /// do about a folder that won't take a rename.
    static func quarantine(_ file: URL) {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = file.deletingLastPathComponent()
            .appendingPathComponent("\(file.deletingPathExtension().lastPathComponent).unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: file, to: aside)
    }

    /// Settings live apart too: a test that changes what the tabs wear or
    /// where the tabs go must not change yours.
    static let settings: UserDefaults = {
        guard testing else { return .standard }
        let suite = world == "test" ? "com.lunbrowser.lun.test" : "com.lunbrowser.lun.test.\(world ?? "")"
        return UserDefaults(suiteName: suite) ?? .standard
    }()
}

/// Files written in the background, one at a time and the newest last.
///
/// Each save used to go to a concurrent queue on its own: two saves of the
/// same file a moment apart could land in either order, and the session
/// written at quit could be overwritten by an older one still on its way —
/// yesterday's tabs coming back instead of today's. Here every write joins
/// a serial queue, and a write that a newer one of the same file has
/// overtaken is dropped, including when the newer one was written at once
/// on the way out.
///
/// What holds, whichever thread asks and whichever queue writes
/// (DiskTests):
/// - the newest write asked for of a file is the one left on disk;
/// - a write overtaken before its turn is never encoded;
/// - the file is whole at every moment, the old one or the new: each write
///   is made beside it and renamed into its place, so a crash halfway
///   through leaves the old file as it was;
/// - a read after `settle` finds the write this thread last asked for.
enum Disk {
    private static let queue = DispatchQueue(label: "search.disk", qos: .utility)
    /// The rows of tabs and the windows: small, asked for at every tab
    /// closed or moved, and wanted on disk within the moment. A queue of
    /// their own, so they are never behind the history or the bookmarks,
    /// which can take a good part of a second.
    private static let brisk = DispatchQueue(label: "search.disk.brisk", qos: .userInitiated)
    private static let lock = NSLock()
    /// The newest write asked for, by file.
    nonisolated(unsafe) private static var newest: [URL: Int] = [:]
    nonisolated(unsafe) private static var count = 0
    /// The newest write of a file, or its removal, while it is still on a
    /// queue: which one, and on which queue (see settle).
    nonisolated(unsafe) private static var unwritten: [URL: (turn: Int, brisk: Bool)] = [:]
    /// Set on both queues: a read from inside a write has nothing to wait for.
    private static let onQueue: DispatchSpecificKey<Bool> = {
        let key = DispatchSpecificKey<Bool>()
        queue.setSpecific(key: key, value: true)
        brisk.setSpecific(key: key, value: true)
        return key
    }()

    /// `encode` runs where the write does. `now` writes on the calling
    /// thread: quitting doesn't wait for a queue. `brisk`, for a small file
    /// wanted on disk within the moment (see the queue).
    static func write(_ file: URL, now: Bool = false, brisk: Bool = false, _ encode: @escaping @Sendable () -> Data?) {
        lock.lock()
        count += 1
        let turn = count
        newest[file] = turn
        unwritten[file] = now ? nil : (turn, brisk)
        lock.unlock()
        // Overtaken: something newer of this file was asked for since.
        let current: @Sendable () -> Bool = {
            lock.lock()
            defer { lock.unlock() }
            return newest[file] == turn
        }
        let put: @Sendable () -> Void = {
            guard current(), let data = encode() else { return }
            // Written beside it with no lock held, and only put in its place
            // under the lock: held for the whole write, a write at once on the
            // main thread waited for whatever was being written in the
            // background — the whole history, say.
            let folder = file.deletingLastPathComponent()
            let aside = folder.appendingPathComponent(".\(file.lastPathComponent).\(turn).writing")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard (try? data.write(to: aside)) != nil else { return }
            lock.lock()
            defer { lock.unlock() }
            if newest[file] == turn, rename(aside.path, file.path) == 0 { return }
            try? FileManager.default.removeItem(at: aside)
        }
        if now {
            put()
        } else {
            (brisk ? Disk.brisk : queue).async {
                put()
                lock.lock()
                if unwritten[file]?.turn == turn { unwritten[file] = nil }
                lock.unlock()
            }
        }
    }

    /// Before a file is read: the newest write of it, if that one is still
    /// on a queue, lands first, so what is read is what was last saved (or
    /// nothing, after `remove`). With nothing of it waiting, which is nearly
    /// always, this returns at once.
    static func settle(_ file: URL) {
        _ = onQueue
        guard DispatchQueue.getSpecific(key: onQueue) == nil else { return }
        lock.lock()
        let waiting = unwritten[file]
        lock.unlock()
        guard let waiting else { return }
        (waiting.brisk ? brisk : queue).sync {}
    }

    /// The file gone, after any write of it already asked for — and none
    /// asked for before this lands it again. `now`, on the calling thread.
    static func remove(_ file: URL, now: Bool = false) {
        lock.lock()
        count += 1
        let turn = count
        newest[file] = turn
        unwritten[file] = now ? nil : (turn, false)
        lock.unlock()
        let take: @Sendable () -> Void = {
            lock.lock()
            defer { lock.unlock() }
            if unwritten[file]?.turn == turn { unwritten[file] = nil }
            guard newest[file] == turn else { return }
            try? FileManager.default.removeItem(at: file)
        }
        if now { take() } else { queue.async(execute: take) }
    }

    /// Everything asked for so far, written — for the way out.
    static func drain() {
        queue.sync {}
        brisk.sync {}
    }

    /// The rows of tabs and the windows asked for so far, written: for the
    /// bench, whose scripts read those files themselves.
    static func drainRows() {
        brisk.sync {}
    }
}
