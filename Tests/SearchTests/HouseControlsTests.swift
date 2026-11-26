import AppKit
import SwiftUI
import XCTest
@testable import Search

/// The controls that took the place of the Mac's own in Settings and the
/// space's look: the tick boxes, the slider, and the track of symbols. Drawn
/// off screen in an NSHostingView that is never put in a window, and read
/// back by the pixel: they are in Lun's ink, never the accent's blue.
@MainActor
final class HouseControlsTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    private func picture(_ view: some View, dark: Bool, name: String? = nil) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.padding(12).background(Palette.ground))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        // Kept for the eye where a folder is named: LUN_PICTURES=/some/dir.
        if let name, let folder = ProcessInfo.processInfo.environment["LUN_PICTURES"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
        return rep
    }

    private func colour(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> NSColor {
        let scale = CGFloat(rep.pixelsWide) / rep.size.width
        return rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB) ?? .clear
    }

    /// Whether any pixel is a colour and not a grey: the accent's blue, in
    /// a control that should be ink on grey.
    private func coloured(_ rep: NSBitmapImageRep) -> Bool {
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.5 else { continue }
                let most = max(c.redComponent, c.greenComponent, c.blueComponent)
                let least = min(c.redComponent, c.greenComponent, c.blueComponent)
                if most - least > 0.12 { return true }
            }
        }
        return false
    }

    private func ink(dark: Bool) -> CGFloat { dark ? 0.93 : 0.09 }

    // MARK: the slider's arithmetic

    func testAValueIsWhereItLiesInItsRange() {
        XCTAssertEqual(Slide.fraction(of: 0.25, in: 0...1), 0.25, accuracy: 0.0001)
        XCTAssertEqual(Slide.fraction(of: 90, in: 0...360), 0.25, accuracy: 0.0001)
        XCTAssertEqual(Slide.fraction(of: -4, in: 0...1), 0)
        XCTAssertEqual(Slide.fraction(of: 9, in: 0...1), 1)
        XCTAssertEqual(Slide.fraction(of: 3, in: 3...3), 0, "A range of no length has nowhere to be")
    }

    func testAPressOnTheTrackIsTheValueUnderIt() {
        let width: CGFloat = 160
        let half = Slide.knob / 2
        // The knob's middle runs between half a knob in from either end.
        XCTAssertEqual(Slide.value(at: half, width: width, in: 0...1), 0, accuracy: 0.0001)
        XCTAssertEqual(Slide.value(at: width - half, width: width, in: 0...1), 1, accuracy: 0.0001)
        XCTAssertEqual(Slide.value(at: width / 2, width: width, in: 0...1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(Slide.value(at: width / 2, width: width, in: 0...360), 180, accuracy: 0.0001)
        // Past either end is that end, not past it.
        XCTAssertEqual(Slide.value(at: -40, width: width, in: 0...1), 0)
        XCTAssertEqual(Slide.value(at: width + 40, width: width, in: 0...100), 100)
        XCTAssertEqual(Slide.value(at: 10, width: Slide.knob, in: 2...5), 2, "No room to run in: the range's start")
    }

    /// There and back: the knob drawn for a value is where a press gives
    /// that value.
    func testTheKnobIsDrawnWhereAPressWouldPutIt() {
        let width: CGFloat = 200
        for value in stride(from: 0.0, through: 1.0, by: 0.125) {
            let middle = Slide.knob / 2 + (width - Slide.knob) * Slide.fraction(of: value, in: 0...1)
            XCTAssertEqual(Slide.value(at: middle, width: width, in: 0...1), value, accuracy: 0.0001)
        }
    }

    // MARK: drawn

    func testTheSliderIsInkAsFarAsItsValue() throws {
        for dark in [false, true] {
            let rep = try picture(Slide(value: .constant(0.5)).frame(width: 160), dark: dark, name: "slide")
            XCTAssertFalse(coloured(rep), "No accent colour in the slider")
            // 12 of padding, then the track: a quarter along is filled,
            // three quarters along is the bare track.
            let filled = colour(rep, 12 + 40, 12 + 9), bare = colour(rep, 12 + 130, 12 + 9)
            XCTAssertEqual(filled.redComponent, ink(dark: dark), accuracy: 0.03)
            XCTAssertGreaterThan(abs(bare.redComponent - ink(dark: dark)), 0.3)
        }
    }

    func testTheTicksAreTheHouseTick() throws {
        for dark in [false, true] {
            var back = true, forward = false
            let ticks = Ticks(items: [("Back", Binding(get: { back }, set: { back = $0 })),
                                      ("Forward", Binding(get: { forward }, set: { forward = $0 }))])
            let rep = try picture(ticks, dark: dark, name: "ticks")
            XCTAssertFalse(coloured(rep), "A tick is ink, not the accent's blue")
            // The first box is ticked: ink at its corner, inside the edge.
            let box = colour(rep, 12 + 3, CGFloat(rep.size.height) / 2 - 5)
            XCTAssertEqual(box.redComponent, ink(dark: dark), accuracy: 0.03)
        }
    }

    func testATickedBoxTogglesWhatItIsBoundTo() {
        var on = false
        let ticked = Ticked("Shuffle", on: Binding(get: { on }, set: { on = $0 }))
        XCTAssertEqual(ticked.title, "Shuffle")
        ticked.on.toggle()
        XCTAssertTrue(on)
    }

    func testTheTrackOfSymbolsIsDrawnWithoutColour() throws {
        for dark in [false, true] {
            let words = try picture(Segmented(options: [(0, "Subtle"), (1, "Rich"), (2, "Vivid")], selection: .constant(1), wide: true)
                .frame(width: 256), dark: dark, name: "segmented-words")
            XCTAssertFalse(coloured(words))
            let arrows = try picture(Segmented(options: SpaceLookPicker.directions.map { (Int($0.angle), $0.symbol) },
                                               selection: .constant(90), wide: true, symbols: { "\($0)" })
                .frame(width: 256), dark: dark, name: "segmented-symbols")
            XCTAssertFalse(coloured(arrows))
            XCTAssertEqual(arrows.size.height, words.size.height, "Words and symbols make the same track")
        }
    }

    func testThePopUpsFaceIsThePill() throws {
        for dark in [false, true] {
            let rep = try picture(HStack(spacing: 8) { PopUpFace(shows: "Ask"); Pill("Reset") {} }, dark: dark, name: "popup-face")
            XCTAssertFalse(coloured(rep))
            XCTAssertEqual(rep.size.height, 24 + 24, "The pop-up is as tall as the pill beside it")
        }
    }
}
