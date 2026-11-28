import AppKit
import SwiftUI
import XCTest
@testable import Search

/// The disc a back or forward swipe brings in grows from its own edge
/// (AnyTransition.pop(from:)). It stands at one side of a frame as wide as
/// the window, and grown from that frame's middle it faded in well inside
/// the page and slid out to the edge.
@MainActor
final class SwipeDiscEdgeTests: XCTestCase {
    override class func setUp() { TestWorld.enter(); super.setUp() }

    /// The furthest from its edge anything of the disc is drawn, in points,
    /// over the frames of its coming in: nil if nothing was seen.
    private func reach(back: Bool) async throws -> CGFloat? {
        _ = NSApplication.shared
        let pulling = Pulling()
        let size = NSSize(width: 800, height: 300)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: Swiping(pulling: pulling).frame(width: size.width, height: size.height).background(Color.white))
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(300))
        let view = try XCTUnwrap(window.contentView)
        pulling.pull = Pull(back: back, travel: 12, armed: false, going: false)
        var furthest: CGFloat?
        // Its coming in takes a fifth of a second (Motion.dissolve).
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(16))
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / size.width
            let row = rep.pixelsHigh / 2
            for x in 0..<rep.pixelsWide {
                guard let colour = rep.colorAt(x: x, y: row)?.usingColorSpace(.sRGB),
                      colour.redComponent < 0.97 || colour.greenComponent < 0.97 || colour.blueComponent < 0.97 else { continue }
                let from = (back ? CGFloat(x) : CGFloat(rep.pixelsWide - 1 - x)) / scale
                furthest = max(furthest ?? 0, from)
            }
        }
        return furthest
    }

    func testTheDiscComesInAtItsOwnEdge() async throws {
        for back in [true, false] {
            let reach = try await reach(back: back)
            let seen = try XCTUnwrap(reach, "the disc was drawn")
            // At rest it ends about 66 points in (10 in, 52 across, its
            // shadow). From the frame's middle it began some 160 in.
            XCTAssertLessThan(seen, 100, back ? "back" : "forward")
        }
    }
}
