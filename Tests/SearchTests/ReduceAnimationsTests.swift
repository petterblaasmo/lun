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
        Motion.instant = true
        XCTAssertNil(Motion.dissolve)
        XCTAssertEqual(Motion.duration(.reveal), 0)
    }

    /// No view writes a curve of its own: an Animation literal belongs in
    /// `enum Motion` (Design.swift), so one switch quiets them all.
    func testNoAnimationIsWrittenOutsideTheVocabulary() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Search", isDirectory: true)
        let literal = try NSRegularExpression(pattern: #"\.(easeOut|easeIn|easeInOut|linear|spring|timingCurve|interactiveSpring|bouncy|smooth|snappy)\("#)
        var found: [String] = []
        for file in try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        where file.pathExtension == "swift" && file.lastPathComponent != "Design.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                if literal.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    found.append("\(file.lastPathComponent):\(number + 1)")
                }
            }
        }
        XCTAssertEqual(found, [], "Use a member of Motion, or add one")
    }
}
