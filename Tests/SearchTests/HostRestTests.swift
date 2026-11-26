import Foundation
import XCTest
@testable import Search

/// A host that keeps turning the browser away is given a rest (#134), and a
/// host that works is never held back.
@available(macOS 15.4, *)
final class HostRestTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    func testThreeQuickSilentEndsInARowStartARest() {
        var rest = HostRest()
        XCTAssertFalse(rest.ended(after: 0.03, said: false, at: start))
        XCTAssertFalse(rest.ended(after: 0.03, said: false, at: start))
        XCTAssertTrue(rest.open(at: start), "two noes: still started")
        XCTAssertTrue(rest.ended(after: 0.03, said: false, at: start), "the third starts a rest")
        XCTAssertFalse(rest.open(at: start))
        XCTAssertEqual(rest.left(at: start), HostRest.first)
        XCTAssertFalse(rest.open(at: start.addingTimeInterval(29)))
        XCTAssertTrue(rest.open(at: start.addingTimeInterval(30)), "and after half a minute it may start again")
    }

    func testEachRestIsTwiceTheLastUpToTenMinutes() {
        var rest = HostRest()
        var now = start
        var lengths: [TimeInterval] = []
        for _ in 0..<7 {
            for _ in 0..<HostRest.tries { _ = rest.ended(after: 0.1, said: false, at: now) }
            let left = rest.left(at: now) ?? 0
            lengths.append(left)
            now = now.addingTimeInterval(left)
        }
        XCTAssertEqual(lengths, [30, 60, 120, 240, 480, 600, 600])
    }

    func testAHostThatAnswersOrRunsAWhileIsLeftAlone() {
        var rest = HostRest()
        _ = rest.ended(after: 0.1, said: false, at: start)
        _ = rest.ended(after: 0.1, said: false, at: start)
        XCTAssertFalse(rest.ended(after: 0.1, said: true, at: start), "a host that said something is working")
        XCTAssertEqual(rest, HostRest(), "and the count starts over")
        _ = rest.ended(after: 0.1, said: false, at: start)
        _ = rest.ended(after: 0.1, said: false, at: start)
        XCTAssertFalse(rest.ended(after: 45, said: false, at: start), "nor one that ran for a while, silent or not")
        XCTAssertTrue(rest.open(at: start))
    }

    func testAWorkingHostAfterARestStartsFromTheShortestAgain() {
        var rest = HostRest()
        for _ in 0..<HostRest.tries { _ = rest.ended(after: 0.1, said: false, at: start) }
        let later = start.addingTimeInterval(HostRest.first)
        _ = rest.ended(after: 0.1, said: true, at: later)
        for _ in 0..<HostRest.tries { _ = rest.ended(after: 0.1, said: false, at: later) }
        XCTAssertEqual(rest.left(at: later), HostRest.first, "the rests double only while it keeps saying no")
    }

    /// A one-shot message (`sendNativeMessage`) is a host that answers and
    /// ends: never counted, however quick.
    func testAQuickAnswerIsNotANo() {
        var rest = HostRest()
        for _ in 0..<10 { XCTAssertFalse(rest.ended(after: 0.05, said: true, at: start)) }
        XCTAssertTrue(rest.open(at: start))
    }
}
