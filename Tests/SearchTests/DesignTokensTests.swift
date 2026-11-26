import AppKit
import SwiftUI
import XCTest
@testable import Search

/// A shadow, a corner and a colour are said once, in Design.swift
/// (Elevation, Radius, Palette), and the views name them. These hold the
/// ones that were moved there to it, so the next card over the page takes
/// an elevation and not a shadow of its own.
@MainActor
final class DesignTokensTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    /// Every line of the app's source that matches, as "File.swift:12",
    /// leaving out comments and the files named.
    private func lines(matching pattern: String, except: Set<String> = []) throws -> [String] {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Search", isDirectory: true)
        let wanted = try NSRegularExpression(pattern: pattern)
        var found: [String] = []
        for file in try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        where file.pathExtension == "swift" && file.lastPathComponent != "Design.swift" && !except.contains(file.lastPathComponent) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                if wanted.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    found.append("\(file.lastPathComponent):\(number + 1)")
                }
            }
        }
        return found.sorted()
    }

    /// How many lines match in each file that has any, comments left out.
    private func counts(matching pattern: String) throws -> [String: Int] {
        Dictionary(try lines(matching: pattern).map { (String($0.split(separator: ":")[0]), 1) }, uniquingKeysWith: +)
    }

    /// What floats takes an elevation. The shadows left are each named
    /// here with why, and how many its file has: one more in any of them
    /// fails as one in a new file does. The three a window is too small
    /// for, or too small themselves, say so where they are drawn.
    func testAShadowIsAnElevation() throws {
        let own: [String: (shadows: Int, why: String)] = [
            "Fold.swift": (2, "the column slid out over the page: a side's shadow, not a card's, cast one way"),
            "HomeStickers.swift": (1, "a sticker's die-cut edge, a filter inside its own drawing"),
            "UnreadBadge.swift": (1, "the unread badge: a point of shadow to lift it off an icon"),
            "Settings.swift": (1, "the switch's knob: an elevation's hairline is a pale rim round it in the dark"),
            "DownloadsFloat.swift": (1, "the downloads card: its window is 24 points larger, less than .float needs"),
            "TabOffers.swift": (1, "the tab offers: their window is 8 points larger, less than .float needs"),
        ]
        let found = try counts(matching: #"\.shadow\("#)
        for (file, count) in found.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(count, own[file]?.shadows ?? 0, "\(file): use .elevated(…) or .carriedShadow(…), or name it here with why")
        }
        for (file, kept) in own where found[file] == nil {
            XCTFail("\(file) has no shadow of its own any more (\(kept.why)): take it off this list")
        }
    }

    func testRedIsThePalettes() throws {
        XCTAssertEqual(try lines(matching: #"Color\.red\b|[(: ]\.red\b|Color\(nsColor: \.systemRed\)"#, except: ["Bench.swift"]), [],
                       "Palette.danger, .dangerRing or .recording")
    }

    func testTheRingAndTheButtonsGreyAreThePalettes() throws {
        XCTAssertEqual(try lines(matching: #"Palette\.ink\.opacity\(0\.35\)|Palette\.ink\.opacity\(0\.07\)|Palette\.ink\.opacity\(0\.16\)"#), [],
                       "Palette.ring, Palette.fill or Palette.drop")
    }

    /// Ink a step back is Palette.soft, and under the pointer a title is
    /// ink itself: neither is ink at 0.7 or 0.75 typed by hand. Two are
    /// still typed, in files that other pull requests were rewriting when
    /// the name was given; each is one word to change once they are in.
    func testInkAStepBackIsThePalettes() throws {
        let waiting: Set<String> = ["SplitView.swift", "BookmarksBar.swift"]
        XCTAssertEqual(try lines(matching: #"Palette\.ink\.opacity\(0\.75?\)"#, except: waiting), [], "Palette.soft, or Palette.ink under the pointer")
        let left = try counts(matching: #"Palette\.ink\.opacity\(0\.75?\)"#)
        for file in waiting {
            XCTAssertLessThanOrEqual(left[file] ?? 0, 1, "\(file): no more than the one that was there")
        }
    }

    /// The Mac's accent colour says one of a few things, and nothing else
    /// wears it: these are the places, each a state and not a decoration.
    /// A new use is a decision; it goes here with what it says.
    func testTheAccentColourSaysAState() throws {
        let says: [String: (uses: Int, what: String)] = [
            "AddressLine.swift": (1, "the address field has the keys"),
            "SpaceSwipe.swift": (1, "a space's name field has the keys"),
            "PinFolderViews.swift": (1, "where a carried pin would land"),
            "Fold.swift": (1, "a page is loading, with the column folded away"),
            "AgentBanner.swift": (2, "a coding agent is working: on its card, and on its tab"),
            "Snap.swift": (1, "the part of a page being captured"),
            "MeCard.swift": (1, "a box just filled in from your card"),
            "SiteCard.swift": (1, "the line of a menu under the pointer, as the Mac's own menus have it"),
        ]
        let found = try counts(matching: #"accentColor|controlAccentColor"#)
        XCTAssertEqual(found, says.mapValues(\.uses), "The accent colour is for a state: see what each of these says")
    }

    /// 7 and 11 were nobody's corner: a control's is 6, a row's 8, a
    /// card's or a field's 10.
    func testNoCornerIsBetweenTheHouses() throws {
        XCTAssertEqual(try lines(matching: #"cornerRadius: (7|11)\b"#), [])
    }

    /// The corners that were typed and are named now: what floats from a
    /// field has the float's 14 (the launcher, the space chooser, the tab
    /// offers), the field in the middle of the window its own 20, and a
    /// ring three points out from a field is the field's corner and three.
    func testTheLargerCornersAreNamed() throws {
        XCTAssertEqual(try lines(matching: #"cornerRadius: (13|14|18|20)\b"#), [], "Radius.float, Radius.middle, or Radius.card + 3 for a ring")
    }

    func testTheCornersGrowWithWhatTheyRound() {
        XCTAssertLessThan(Radius.control, Radius.row)
        XCTAssertLessThan(Radius.row, Radius.card)
        XCTAssertLessThan(Radius.card, Radius.float)
        XCTAssertLessThan(Radius.float, Radius.panel)
        XCTAssertLessThan(Radius.panel, Radius.middle)
        XCTAssertEqual(Radius.card, Metrics.cardRadius, "A card of rows and the page's card are one corner")
    }

    // MARK: drawn

    private func picture(_ view: some View, dark: Bool, name: String? = nil) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if let name, let folder = ProcessInfo.processInfo.environment["LUN_PICTURES"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
        return rep
    }

    private func grey(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> CGFloat {
        let scale = CGFloat(rep.pixelsWide) / rep.size.width
        return rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB)?.redComponent ?? -1
    }

    /// A panel is over everything, and still on the ground's own colour:
    /// what lies in it (a card of rows, a switch's knob) was drawn for that
    /// ground, in the dark too, where a floating card is a step lighter.
    func testAPanelIsOnTheGround() throws {
        for dark in [false, true] {
            let plate = Plate("History", width: 300, close: {}) { Color.clear.frame(height: 60) }
                .padding(60).background(Color.gray)
            let rep = try picture(plate, dark: dark, name: "plate")
            XCTAssertEqual(grey(rep, 60 + 150, 60 + 80), dark ? 0.11 : 1.0, accuracy: 0.02, dark ? "dark" : "light")
            // Beside it, its shadow: darker than the grey it lies on. Above
            // or below: a picture drawn off screen lays a shadow upward.
            let bare = grey(rep, 4, rep.size.height / 2)
            let beside = min(grey(rep, 60 + 150, 60 - 10), grey(rep, 60 + 150, rep.size.height - 60 + 10))
            XCTAssertLessThan(beside, bare - 0.02, dark ? "dark" : "light")
        }
    }

    /// What the hand carries casts one shadow, deeper in the dark, and
    /// none once it is put down.
    func testWhatIsCarriedCastsAShadowOnlyWhileHeld() throws {
        func under(held: Bool, dark: Bool) throws -> CGFloat {
            let view = Color.white.frame(width: 60, height: 30).carriedShadow(held)
                .padding(30).background(Color(white: 0.5))
            let rep = try picture(view, dark: dark, name: held ? "carried" : nil)
            // Four points off its foot or its head, in the middle (a
            // picture drawn off screen lays a shadow upward).
            return min(grey(rep, 60, 30 + 30 + 4), grey(rep, 60, 30 - 4))
        }
        let ground = try under(held: false, dark: false)
        XCTAssertEqual(try under(held: false, dark: true), ground, accuracy: 0.01)
        let light = try under(held: true, dark: false), dark = try under(held: true, dark: true)
        XCTAssertLessThan(light, ground - 0.02)
        XCTAssertLessThan(dark, light - 0.02, "Deeper in a dark window")
    }

    /// A key waiting to be pressed is not the key under the pointer: it is
    /// filled in darker and its edge is ink.
    func testAKeyWaitingIsNotAKeyPointedAt() throws {
        for dark in [false, true] {
            let keys = HStack(spacing: 8) {
                KeyFace(label: "⌘K")
                KeyFace(label: "⌘K", hovering: true)
                KeyFace(label: "Type a shortcut", listening: true)
                KeyFace(label: "None", set: false)
            }
            .padding(12).background(Palette.ground)
            _ = try picture(keys, dark: dark, name: "keys")
            func inside(_ face: KeyFace) throws -> CGFloat {
                // Just inside its top edge, clear of its words.
                let rep = try picture(face.padding(4).background(Palette.ground), dark: dark)
                return grey(rep, 4 + 10, 4 + 3)
            }
            let rest = try inside(KeyFace(label: "⌘K"))
            let pointed = try inside(KeyFace(label: "⌘K", hovering: true))
            let waiting = try inside(KeyFace(label: "⌘K", listening: true))
            XCTAssertNotEqual(rest, pointed, accuracy: 0.01)
            XCTAssertGreaterThan(abs(waiting - rest), abs(pointed - rest) + 0.01, dark ? "dark" : "light")
        }
    }
}

/// Settings › Privacy asks before it takes something away for good: each
/// of the four has a question of its own and a button named for what it
/// does, never a bare OK.
final class WipingTests: XCTestCase {
    func testEachAsksInItsOwnWords() {
        let all = SettingsPanel.Wiping.allCases
        XCTAssertEqual(all.count, 4)
        XCTAssertEqual(Set(all.map(\.question)).count, all.count, "A question each")
        XCTAssertEqual(Set(all.map(\.detail)).count, all.count, "What goes, each in its own words")
        for wiping in all {
            XCTAssertTrue(wiping.question.hasSuffix("?"), wiping.question)
            XCTAssertFalse(wiping.detail.isEmpty)
            XCTAssertFalse(["OK", "Yes", "Cancel", ""].contains(wiping.yes), "The button says what it does")
            XCTAssertFalse(wiping.yes.hasSuffix("…"), "The last step asks nothing more")
        }
    }
}
