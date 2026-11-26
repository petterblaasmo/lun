import JavaScriptCore
import XCTest
@testable import Search

/// The page's word on a sideways swipe (Swipe.watch): "taken" when the page
/// keeps it, "free" when it may go back or forward. Here, what the root's
/// overscroll-behavior says about it, and a page's own wheel handler.
@MainActor
final class SwipeWatchTests: XCTestCase {
    /// A page that scrolls nowhere sideways, with the root's
    /// overscroll-behavior as given, swiped once: what the watch said.
    /// `pagePansItself` is a handler of the page's calling preventDefault.
    private func said(overscrollX: String, overscrollY: String, pagePansItself: Bool = false) throws -> [String] {
        let context = try XCTUnwrap(JSContext())
        var trouble: String?
        context.exceptionHandler = { _, error in trouble = error?.toString() }
        context.evaluateScript("""
        var heard = [], listeners = {}, timers = [];
        var root = { nodeType: 1, parentElement: null, scrollWidth: 800, clientWidth: 800, scrollLeft: 0 };
        var style = { overflowX: 'visible', overscrollBehaviorX: '\(overscrollX)', overscrollBehaviorY: '\(overscrollY)' };
        var document = { documentElement: root, body: null };
        var window = this;
        window.innerWidth = 800;
        window.scrollX = 0;
        window.addEventListener = function (name, listener) { (listeners[name] = listeners[name] || []).push(listener); };
        window.webkit = { messageHandlers: { officeScroll: { postMessage: function (message) { heard.push(message.side); } } } };
        function getComputedStyle() { return style; }
        function setTimeout(run) { timers.push(run); }
        """)
        context.evaluateScript(Swipe.watch)
        context.evaluateScript("""
        var swipe = { deltaX: 40, deltaY: 0, target: root, defaultPrevented: false };
        listeners.wheel.forEach(function (listener) { listener(swipe); });
        // The page's own handler runs after the watch's, which is first.
        swipe.defaultPrevented = \(pagePansItself);
        timers.forEach(function (run) { run(); });
        """)
        XCTAssertNil(trouble)
        return try XCTUnwrap(context.evaluateScript("heard")?.toArray() as? [String])
    }

    func testAnOrdinaryPageLeavesTheSwipeFree() throws {
        XCTAssertEqual(try said(overscrollX: "auto", overscrollY: "auto"), ["free"])
    }

    /// A whiteboard or a map pans under two fingers with a wheel handler
    /// of its own and nothing that scrolls: its preventDefault is its claim.
    func testAPageThatTakesTheWheelItselfKeepsTheSwipe() throws {
        XCTAssertEqual(try said(overscrollX: "auto", overscrollY: "auto", pagePansItself: true), ["taken"])
    }

    /// A spreadsheet's word: sideways held, up and down left alone.
    func testARootHoldingSidewaysOnlyKeepsTheSwipe() throws {
        XCTAssertEqual(try said(overscrollX: "none", overscrollY: "auto"), ["taken"])
        XCTAssertEqual(try said(overscrollX: "contain", overscrollY: "auto"), ["taken"])
    }

    /// `html { overscroll-behavior: none }` is a page that doesn't want to
    /// bounce: it still swipes back, as it does in Safari.
    func testARootThatOnlyWantsNoBounceLeavesTheSwipeFree() throws {
        XCTAssertEqual(try said(overscrollX: "none", overscrollY: "none"), ["free"])
        XCTAssertEqual(try said(overscrollX: "contain", overscrollY: "contain"), ["free"])
        XCTAssertEqual(try said(overscrollX: "none", overscrollY: "contain"), ["free"])
    }
}
