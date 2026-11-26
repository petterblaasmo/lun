import AppKit
import SwiftUI
import XCTest
@testable import Search

/// Settings › Appearance › Reduce animations (Motion.instant): off unless
/// turned on, kept, and with it on nothing in Search's interface moves.
@MainActor
final class ReduceAnimationsTests: XCTestCase {
    private var saved: Any?

    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func setUp() {
        super.setUp()
        saved = Store.settings.object(forKey: Motion.instantKey)
        Store.settings.removeObject(forKey: Motion.instantKey)
        Motion.instant = false
        // Whatever the Mac running the tests has chosen.
        Motion.testReduceMotion = false
    }

    override func tearDown() {
        Store.settings.set(saved, forKey: Motion.instantKey)
        Motion.instant = false
        Motion.testReduceMotion = nil
        Motion.testLowPower = nil
        super.tearDown()
    }

    func testOffUnlessTurnedOn() {
        XCTAssertFalse(Preferences().instantMotion)
        XCTAssertFalse(Motion.instant)
    }

    func testTheSwitchIsKeptAndReadAgainAtLaunch() {
        Preferences().instantMotion = true
        XCTAssertTrue(Motion.instant)
        XCTAssertTrue(Store.settings.bool(forKey: Motion.instantKey))
        Motion.instant = false
        XCTAssertTrue(Preferences().instantMotion)
        XCTAssertTrue(Motion.instant)
        Preferences().instantMotion = false
        XCTAssertFalse(Motion.instant)
    }

    /// ⌘1–⌘9's highlight moves on glide and quick, a space on its own
    /// ease-out behind Motion.reduced, a page's first frame on seconds.
    func testOnEveryTransitionIsImmediate() {
        Motion.instant = true
        XCTAssertTrue(Motion.reduced)
        XCTAssertNil(Motion.glide)
        XCTAssertNil(Motion.settle)
        XCTAssertNil(Motion.quick)
        XCTAssertNil(Motion.folding(out: true))
        XCTAssertNil(Motion.folding(out: false))
        XCTAssertNil(Motion.dissolve)
        XCTAssertNil(Motion.slow)
        XCTAssertNil(Motion.drawn)
        XCTAssertNil(Motion.shake)
        XCTAssertNil(Motion.carry)
        XCTAssertEqual(Motion.duration(.reveal), 0)
        XCTAssertEqual(Motion.duration(.dissolve), 0)
        XCTAssertEqual(Motion.duration(.glide), 0)
        for length in ownLengths { XCTAssertEqual(length, 0) }
        XCTAssertFalse(Motion.popovers)
        // Low Power Mode's short ease-out is still a movement.
        Motion.testLowPower = true
        Store.settings.set(true, forKey: Motion.lightKey)
        defer { Store.settings.removeObject(forKey: Motion.lightKey) }
        XCTAssertNil(Motion.glide)
        XCTAssertNil(Motion.settle)
    }

    func testOffEverythingMovesAsBefore() {
        XCTAssertFalse(Motion.reduced)
        XCTAssertNotNil(Motion.glide)
        XCTAssertNotNil(Motion.settle)
        XCTAssertNotNil(Motion.quick)
        XCTAssertNotNil(Motion.folding(out: true))
        XCTAssertNotNil(Motion.dissolve)
        XCTAssertNotNil(Motion.slow)
        XCTAssertNotNil(Motion.shake)
        XCTAssertEqual(Motion.duration(.reveal), 0.12)
        XCTAssertEqual(Motion.duration(.quick), 0.14)
        XCTAssertEqual(Motion.duration(.settle), 0.30)
        // What was tuned where it is used moves as long as it did.
        XCTAssertEqual(ownLengths, [0.15, 0.2, 0.2, 0.3, 0.15, 0.32, 0.22, 0.18])
        XCTAssertTrue(Motion.popovers)
    }

    /// The lengths that are one surface's own (the hint over a page, the
    /// loading line, a space's page, the Split View, the downloads card's
    /// window, the floating video).
    private var ownLengths: [TimeInterval] {
        [Motion.hint(shown: true), Motion.hint(shown: false), Motion.lineRuns, Motion.lineFades,
         Motion.spaceFade, Motion.panes, Motion.resize, Motion.tuck]
    }

    /// Reduce Motion alone keeps its fades; Reduce animations takes those too.
    func testReduceMotionAloneKeepsItsFades() {
        Motion.testReduceMotion = true
        XCTAssertTrue(Motion.reduced)
        XCTAssertNil(Motion.glide)
        XCTAssertNil(Motion.slow)
        XCTAssertEqual(Motion.duration(.settle), 0)
        XCTAssertNotNil(Motion.dissolve)
        XCTAssertEqual(Motion.duration(.reveal), 0.12)
        XCTAssertEqual(Motion.duration(.dissolve), 0.2)
        // The loading line stops running and still fades out.
        XCTAssertEqual(Motion.lineRuns, 0)
        XCTAssertEqual(Motion.lineFades, 0.3)
        XCTAssertEqual(Motion.hint(shown: true), 0)
        XCTAssertEqual(Motion.tuck, 0)
        // A popover is the system's, which answers Reduce Motion itself.
        XCTAssertTrue(Motion.popovers)
        Motion.instant = true
        XCTAssertNil(Motion.dissolve)
        XCTAssertEqual(Motion.duration(.reveal), 0)
        XCTAssertEqual(Motion.lineFades, 0)
    }

    /// The ring in a loading tab turns whatever is asked, since a ring
    /// standing still says the page has stopped; the light over a peeked
    /// page and the glow under the field hold still.
    func testOnlyTheLoadingRingStillGoesRound() throws {
        let spin = try XCTUnwrap(Motion.loop(.spin, CABasicAnimation(keyPath: "transform.rotation.z")))
        XCTAssertEqual(spin.duration, 0.85)
        XCTAssertEqual(spin.repeatCount, .infinity)
        XCTAssertNil(spin.timingFunction)
        let sweep = try XCTUnwrap(Motion.loop(.sweep, CABasicAnimation(keyPath: "position.x")))
        XCTAssertEqual(sweep.duration, 1.3)
        XCTAssertFalse(sweep.autoreverses)
        let breath = try XCTUnwrap(Motion.loop(.breathe, CAAnimationGroup()))
        XCTAssertEqual(breath.duration, 2.6)
        XCTAssertTrue(breath.autoreverses)
        XCTAssertEqual(breath.repeatCount, .infinity)

        for stilled in [{ Motion.testReduceMotion = true }, { Motion.testReduceMotion = false; Motion.instant = true }] {
            stilled()
            XCTAssertNotNil(Motion.loop(.spin, CABasicAnimation()))
            XCTAssertNil(Motion.loop(.sweep, CABasicAnimation()))
            XCTAssertNil(Motion.loop(.breathe, CAAnimationGroup()))
            XCTAssertEqual(Motion.pulse().peak, 1)
        }
    }

    /// The window's buttons go with the column on the column's own numbers.
    func testTheWindowsButtonsMoveOnTheColumnsSpring() throws {
        let slides = Store.settings.object(forKey: Motion.slidesKey)
        defer { Store.settings.set(slides, forKey: Motion.slidesKey) }
        Store.settings.set(false, forKey: Motion.slidesKey)
        for out in [true, false] {
            let fold = Motion.fold(out: out)
            let spring = try XCTUnwrap(Motion.folding(out: out, keyPath: "transform.translation.x") as? CASpringAnimation)
            XCTAssertEqual(spring.keyPath, "transform.translation.x")
            XCTAssertEqual(spring.stiffness, pow(2 * .pi / fold.response, 2), accuracy: 0.001)
            XCTAssertEqual(spring.damping, 4 * .pi * fold.damping / fold.response, accuracy: 0.001)
        }
        Store.settings.set(true, forKey: Motion.slidesKey)
        let eased = Motion.folding(out: false, keyPath: "transform.translation.x")
        XCTAssertFalse(eased is CASpringAnimation)
        XCTAssertEqual(eased.duration, 0.22)
    }

    /// A developer tools package is told the two switches, so its panels
    /// hold still when the rest of the window does.
    func testADeveloperToolsPackageIsToldTheSame() {
        let host = DevToolsHostBridge(id: "motion")
        XCTAssertFalse(host.reducesMotion)
        XCTAssertFalse(host.stillsMotion)
        Motion.testReduceMotion = true
        XCTAssertTrue(host.reducesMotion)
        XCTAssertFalse(host.stillsMotion)
        Motion.instant = true
        XCTAssertTrue(host.stillsMotion)
    }

    /// No view writes a curve of its own: an Animation literal belongs in
    /// `enum Motion` (Design.swift), so one switch quiets them all.
    /// The developer tools are a package of their own and can't reach
    /// Motion: theirs is the Motion in their Shims.swift, held the same way.
    func testNoAnimationIsWrittenOutsideTheVocabulary() throws {
        let literal = #"\.(easeOut|easeIn|easeInOut|linear|spring|timingCurve|interactiveSpring|bouncy|smooth|snappy)\("#
        XCTAssertEqual(try lines(matching: literal, in: "Search", except: "Design.swift"), [],
                       "Use a member of Motion, or add one")
        for package in ["DevToolsFull", "DevToolsShared", "DevToolsLite"] {
            XCTAssertEqual(try lines(matching: literal, in: package, except: "Shims.swift"), [],
                           "Use a member of the package's Motion (Shims.swift), or add one")
        }
    }

    /// Nor a length: what AppKit and Core Animation are given comes from
    /// Motion, so Reduce Motion and Reduce animations reach it.
    func testNoLengthIsSetOutsideTheVocabulary() throws {
        let set = #"(\.duration\s*=[^=]|setAnimationDuration\()"#
        let found = try lines(matching: set, in: "Search", except: "Design.swift") { !$0.contains("Motion.") }
        XCTAssertEqual(found, [], "Use a length of Motion's, or add one")
    }

    /// Where `pattern` is written in a target's sources, comments aside:
    /// "File.swift:12".
    private func lines(matching pattern: String, in target: String, except vocabulary: String,
                       where counts: (String) -> Bool = { _ in true }) throws -> [String] {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/\(target)", isDirectory: true)
        let wanted = try NSRegularExpression(pattern: pattern)
        var found: [String] = []
        for file in try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        where file.pathExtension == "swift" && file.lastPathComponent != vocabulary {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), counts(line) else { continue }
                if wanted.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    found.append("\(file.lastPathComponent):\(number + 1)")
                }
            }
        }
        return found.sorted()
    }
}
