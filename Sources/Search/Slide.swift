import SwiftUI

/// An amount pulled along a track: Lun's slider.
///
/// The Mac's own was the last control in Settings in the accent's blue. This
/// one is the switch's drawing laid out long: its track the switch's grey,
/// filled in ink as far as the amount goes, with an ink knob at the end that
/// grows a little under the pointer and while it is held. A press anywhere
/// on the track takes the knob there, as the Mac's does.
struct Slide: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    /// Told when a pull starts and when it is let go, as the Mac's slider
    /// tells: for an amount that is only applied once the knob is dropped.
    var editing: (Bool) -> Void = { _ in }

    @State private var hovering = false
    @State private var held = false
    @Environment(\.isEnabled) private var enabled

    /// The room the knob takes, at its largest.
    static let knob: CGFloat = 14
    static let track: CGFloat = 4
    /// How far VoiceOver's and the arrow keys' one step goes.
    static let step = 0.05

    var body: some View {
        GeometryReader { box in
            let run = max(1, box.size.width - Self.knob)
            let at = Self.fraction(of: value, in: range)
            let lit = hovering || held
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.faint).frame(height: Self.track)
                Capsule().fill(Palette.ink).frame(width: Self.knob / 2 + run * at, height: Self.track)
                Circle().fill(Palette.ink)
                    .frame(width: lit ? Self.knob : Self.knob - 2, height: lit ? Self.knob : Self.knob - 2)
                    .frame(width: Self.knob, height: Self.knob)
                    .offset(x: run * at)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { pull in
                    if !held {
                        held = true
                        editing(true)
                    }
                    value = Self.value(at: pull.location.x, width: box.size.width, in: range)
                }
                .onEnded { _ in
                    held = false
                    editing(false)
                })
        }
        .frame(height: 18)
        .opacity(enabled ? 1 : 0.4)
        .hovers($hovering)
        .animation(Motion.quick, value: held)
        .accessibilityElement()
        .accessibilityValue("\(Int((Self.fraction(of: value, in: range) * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let span = range.upperBound - range.lowerBound
            let moved = value + (direction == .increment ? 1 : -1) * span * Self.step
            editing(true)
            value = min(range.upperBound, max(range.lowerBound, moved))
            editing(false)
        }
    }

    /// How far along its range a value is, from 0 to 1; one outside the
    /// range is at the end it is past.
    static func fraction(of value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    /// The value under the pointer at `x` on a track `width` wide. The
    /// knob's middle runs from half a knob in to half a knob short of the
    /// end, so the knob never hangs over either: a press before or past
    /// that is the range's end.
    static func value(at x: CGFloat, width: CGFloat, in range: ClosedRange<Double>) -> Double {
        let run = width - knob
        guard run > 0 else { return range.lowerBound }
        let along = min(1, max(0, (x - knob / 2) / run))
        return range.lowerBound + Double(along) * (range.upperBound - range.lowerBound)
    }
}
