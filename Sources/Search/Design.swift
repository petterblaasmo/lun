import SwiftUI
import AppKit

// Lifted from Office Inspiration, with the ground turned white: there the work
// floats on an off-white canvas, here the page *is* the ground and everything
// the browser draws has to get out of its way.
//
// Every colour is a pair — one for a light window, one for a dark — and
// resolves itself against whatever appearance the window has. The window
// takes its appearance from the app, and the app from Settings › Appearance:
// light, dark, or whatever the Mac is doing. Nothing else in the code knows
// which it is.
enum Palette {
    static let ground = Color(nsColor: NS.ground)
    static let ink = Color(nsColor: NS.ink)             // neutral-900 · neutral-100
    static let muted = Color(nsColor: NS.muted)         // #5A5A5A · #A3A3A3
    static let faint = Color(nsColor: NS.faint)         // neutral-300 · neutral-700
    static let hairline = Color(nsColor: NS.hairline)   // neutral-200 · neutral-800
    static let wash = Color(nsColor: NS.wash)           // the live tab
    static let hover = Color(nsColor: NS.hover)         // the one under the pointer
    /// Around the page's card, with the tabs down the side: the column, the
    /// bookmarks bar and the gaps share it, a touch off the page's white, so
    /// the card reads as one (see CardEdge).
    static let frame = Color(nsColor: NS.frame)
    /// What floats over the page: a card, a list, the address field. The
    /// ground's white in a light window, a step off it in a dark one.
    static let raised = Color(nsColor: NS.raised)
    /// The only two that aren't grey: a connection nobody can read on the
    /// way, and one anybody can (see SiteCard.swift).
    static let safe = Color(nsColor: NS.safe)           // green-700 · green-400
    static let unsafe = Color(nsColor: NS.unsafe)       // amber-700 · amber-400

    /// The same colours for the AppKit corners of the app — a text field's
    /// ink, a window's background — which want an NSColor and keep it.
    enum NS {
        static let ground = pair(1.0, 0.11)
        static let ink = pair(0.09, 0.93)
        static let muted = pair(0.353, 0.64)
        static let faint = pair(0.83, 0.32)
        static let hairline = pair(0.91, 0.20)
        static let wash = pair(0.937, 0.175)
        static let hover = pair(0.965, 0.15)
        static let frame = pair(0.955, 0.075)
        static let raised = pair(1.0, 0.13)
        /// The resting traffic lights, drawn by hand when the app is behind.
        static let resting = pair(0.80, 0.30)
        static let safe = tint(light: (0.08, 0.50, 0.24), dark: (0.29, 0.87, 0.50))
        static let unsafe = tint(light: (0.71, 0.33, 0.04), dark: (0.98, 0.75, 0.14))

        private static func tint(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
            NSColor(name: nil) { appearance in
                let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
                return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
            }
        }

        private static func pair(_ light: CGFloat, _ dark: CGFloat) -> NSColor {
            NSColor(name: nil) { appearance in
                let dim = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(white: dim ? dark : light, alpha: 1)
            }
        }
    }
}

/// The greys of the column's rows, pins and buttons, for the ground they lie
/// on: the white's (the strip, a panel, the column with the page edge to
/// edge) or the window's beside the page's card, set by the column for
/// what is in it (see SideBar.onFrame). Read through the environment, so a
/// row, a pin or a door is the same view on either ground.
struct Greys {
    let wash: Color
    let hover: Color
    let tile: Color
    let pinLive: Color
    /// The live and hovered greys for a row lying on a tile (a Split View
    /// tab's panes), so the two together land where the plain ones do.
    let washOnTile: Color
    let hoverOnTile: Color
    /// What the tab you're on lies on: beside the page's card a card of its
    /// own, lifted off the column (see Elevated); on the white, the wash, as
    /// white on white would be a shadow alone.
    let raised: Color
    let lifts: Bool
    /// The quiet ink of a tab's title that isn't live, the same way: on
    /// the plain ground Palette.muted exactly, on a space's Rich or Vivid
    /// colour as far from it as Palette.muted is from the plain ground,
    /// where the opaque grey lost a third of its contrast.
    let muted: Color
    /// The faintest ink, New tab's, the same way: on Vivid the opaque grey
    /// all but vanished into the colour.
    let faint: Color

    // Black in a light window, white in a dark one, at the strength that
    // lands on the same grey as Palette's over the ground they lie on (the
    // white, or the frame beside the card). On that ground nothing changes;
    // on a space's colour or gradient they take its tint, where an opaque
    // grey sat on it as a grey patch (Drice, 18 Nov 2026).
    static let white = Greys(wash: shade(0.07, 0.08), hover: shade(0.04, 0.05),
                             tile: shade(0.055, 0.06), pinLive: shade(0.11, 0.14),
                             washOnTile: shade(0.0294, 0.0342), hoverOnTile: shade(0.02, 0.025),
                             raised: shade(0.07, 0.08), lifts: false,
                             muted: shade(0.647, 0.5955), faint: shade(0.17, 0.236))
    static let frame = Greys(wash: shade(0.07, 0.08), hover: shade(0.04, 0.05),
                             tile: shade(0.065, 0.08), pinLive: shade(0.11, 0.14),
                             washOnTile: shade(0.0324, 0.0452), hoverOnTile: shade(0.02, 0.025),
                             raised: paper, lifts: true,
                             muted: shade(0.631, 0.611), faint: shade(0.1309, 0.2649))

    /// White in a light window, in a dark one what 14% of white does to the
    /// column under it.
    private static let paper = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.14) : .white
    })

    private static func shade(_ light: CGFloat, _ dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 1, alpha: dark) : NSColor(white: 0, alpha: light)
        })
    }
}

private struct GreysKey: EnvironmentKey {
    static let defaultValue = Greys.white
}

extension EnvironmentValues {
    var greys: Greys {
        get { self[GreysKey.self] }
        set { self[GreysKey.self] = newValue }
    }
}

/// Light, dark, or the Mac's own — the one choice that colours everything.
enum Look: String, CaseIterable, Identifiable {
    case light, dark, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    /// What the app is told to be. Nothing, for "system": the app then
    /// follows the Mac, and changes with it.
    var appearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }

    /// Set on the app rather than on the window, so every panel, alert and
    /// sheet — and every page, which follows the window it is in — agrees.
    ///
    /// Never from inside whatever is happening when it is asked for: the
    /// switch in Settings changes it from within an animation, over a panel
    /// in transition, and re-skinning every window in the middle of that is
    /// how a window ends up with a layer that takes clicks and shows
    /// nothing. The next turn of the run loop is soon enough.
    func apply() {
        let wanted = appearance
        DispatchQueue.main.async {
            guard NSApp.appearance !== wanted, NSApp.appearance?.name != wanted?.name else { return }
            NSApp.appearance = wanted
        }
    }
}

enum Metrics {
    /// The tab strip. The window's title bar is grown to match it so the
    /// traffic lights come down with the tabs — otherwise giving the row room
    /// to breathe just leaves it sitting below three buttons it used to line
    /// up with. Shorter tab bar, with the tabs across the top, takes it down
    /// to a few points above and below the 28-point tabs: a strip, not a
    /// toolbar. The column keeps the full band, as its first row shares it.
    @MainActor static var strip: CGFloat {
        Shared.prefs.sidebar ? 48 : Shared.prefs.compactStrip ? 36 : 52
    }
    /// With the tabs down the side the page is a card: this far from the
    /// window's edges (and from the column, folded away), and its corners
    /// this round.
    static let cardGap: CGFloat = 8
    static let cardRadius: CGFloat = 10
    /// Where the first tab starts. The traffic lights run from 19 to 79 —
    /// measured, not guessed — so this leaves them the same air on their right
    /// that the window gives them on their left.
    static let lights: CGFloat = 100
    /// Back, forward and reload, at the far end of the row beside the
    /// bookmarks: three doors and the air before the next one.
    static let helm: CGFloat = 3 * 26 + 2 * 2 + 8
    /// The same three doors again, in the sidebar, where they sit right of
    /// the lights instead. The column already has 10 of horizontal padding
    /// of its own before this even starts. 72 put the back door's box 3
    /// points from the zoom button and its chevron 12, "a little tight"
    /// (feedback, 22 Oct 2026): at 80 the chevron is 20 points clear of the
    /// lights, about the 19 the window leaves on their left, as a toolbar's
    /// first item sits in Safari. A column too narrow for that gives back
    /// what it must (SideBar.lights), down to where it was.
    static let sideLights: CGFloat = 80
    /// The least of it the fold door may have: its box 3 points clear of
    /// the zoom button (SideBar.folds).
    static let sideLightsLeast: CGFloat = 72
    /// The three doors' own width, without the air after them.
    static let helmDoors: CGFloat = 3 * 26 + 2 * 4
    /// The same two, for the doors Settings leaves shown (idea 815): all
    /// three unless some are hidden, nothing when none is.
    @MainActor static func helm(_ prefs: Preferences) -> CGFloat {
        let n = CGFloat(prefs.helmDoors)
        return n == 0 ? 0 : n * 26 + (n - 1) * 2 + 8
    }
    @MainActor static func helmDoors(_ prefs: Preferences) -> CGFloat {
        let n = CGFloat(prefs.helmDoors)
        return n == 0 ? 0 : n * 26 + (n - 1) * 4
    }
    /// Tabs are a fixed width rather than the width of their titles, so the
    /// cross always lands in the same place and the row never rearranges
    /// itself while you read it. They give way when there are too many:
    /// narrower than tabTitled they show their site's mark alone, and they
    /// stop at tabMinWidth, the mark and its air. Past that the row scrolls,
    /// inside its own edges.
    static let tabWidth: CGFloat = 186
    /// A titled tab's own parts, end to end (TabPill.titled): its air at
    /// the left, the mark, a gap, the title, a gap, the spring at its
    /// least, a gap, the slot the cross and the ring take (kept while
    /// empty, so the title doesn't move under the pointer), its air at the
    /// right. Everything but the title.
    static let tabLead: CGFloat = 11
    static let tabTrail: CGFloat = 7
    static let tabMark: CGFloat = 15
    static let tabSpacing: CGFloat = 6
    static let tabSpring: CGFloat = 2
    static let tabCloseSlot: CGFloat = 15
    static let tabFixed: CGFloat = tabLead + tabMark + tabSpacing + tabSpacing + tabSpring + tabSpacing + tabCloseSlot + tabTrail
    /// The least a title is given: three letters and the "…", as most
    /// titles' letters run at 12.5 points ("Rec…" is 32, "Wea…" 35). Less
    /// than that and a tab showed its mark and a lone "…", or a letter or
    /// two, which says nothing a mark alone doesn't; it shows the mark
    /// alone instead.
    static let tabTitleRoom: CGFloat = 36
    /// A sign before the title (a blocked window, a translation), framed
    /// this wide; the bare ones (a script's flask, a private eye, the
    /// recording dot) are a symbol of 9 or 10 points, about tabGlyph.
    static let tabSign: CGFloat = 17
    static let tabGlyph: CGFloat = 12
    /// 104: narrower than this a tab is its mark alone.
    static let tabTitled: CGFloat = tabFixed + tabTitleRoom
    static let tabMinWidth: CGFloat = 36
    static let tabGap: CGFloat = 2
    /// A pinned tab is a square the height of the row, holding one letter.
    static let pinWidth: CGFloat = 30
    /// The square at the end of the row that opens a new page.
    static let plusWidth: CGFloat = 30
    /// What a full row of tabs still leaves past the plus to take the window
    /// by, as Chrome's does: the tabs give way before it. Without it they ran
    /// up to the buttons at the far end, and the corner the lights sit in was
    /// all of the row that moved the window.
    static let tabRowHold: CGFloat = 40
    /// The address field, in both the places it shows up.
    static let fieldWidth: CGFloat = 560
    /// The column of titles down the left, in the way that has one.
    /// 232 of it rows, and sideInset on either side of them.
    static let side: CGFloat = 248
    /// The air between the column's edges and its rows: the page's card
    /// stands as far from the column as from the window (cardGap).
    static let sideInset: CGFloat = 8
    static let sideMin: CGFloat = 176
    /// Narrower than this, with Narrow to icons on, the column is the strip
    /// of icons (Preferences.narrowStrip).
    static let narrowLine: CGFloat = 200
    static let sideMax: CGFloat = 440
}

/// Three heights over the ground, one shadow each: a card lying on the column
/// (the tab you're on), one floating over the page (the address list, a
/// question), one over everything (the tab switcher). A hairline round each
/// keeps its edge where the shadow is too soft to; in the dark it is light.
enum Elevation {
    case lift, float, overlay
}

struct Elevated<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let height: Elevation
    let shape: S
    let fill: Color

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        content
            .background {
                switch height {
                case .lift:
                    shape.fill(fill).shadow(color: .black.opacity(dark ? 0.3 : 0.07), radius: 1.5, y: 1)
                case .float:
                    shape.fill(fill)
                        .shadow(color: .black.opacity(dark ? 0.3 : 0.04), radius: 3, y: 2)
                        .shadow(color: .black.opacity(dark ? 0.5 : 0.12), radius: 18, y: 12)
                case .overlay:
                    shape.fill(fill)
                        .shadow(color: .black.opacity(dark ? 0.3 : 0.06), radius: 6, y: 4)
                        .shadow(color: .black.opacity(dark ? 0.6 : 0.18), radius: 40, y: 28)
                }
            }
            .overlay {
                shape.strokeBorder(dark ? Color.white.opacity(height == .lift ? 0.08 : 0.10)
                                        : Color.black.opacity(height == .lift ? 0.05 : 0.08),
                                   lineWidth: dark ? 1 : 0.5)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// On a card at `height` over what it lies on (see Elevated).
    func elevated<S: InsettableShape>(_ height: Elevation, in shape: S, fill: Color = Palette.raised) -> some View {
        modifier(Elevated(height: height, shape: shape, fill: fill))
    }
}

/// The ground of the tab you're on: a card lifted off the column, or on the
/// white the wash (Greys.raised).
struct LiveGround: View {
    @Environment(\.greys) private var greys
    var radius: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if greys.lifts {
            Color.clear.elevated(.lift, in: shape, fill: greys.raised)
        } else {
            shape.fill(greys.raised)
        }
    }
}

/// A title on one line that fades out at its end where it doesn't fit, rather
/// than being cut at three dots. One that fits is drawn as it is.
struct FadingLine: View {
    let text: String
    var fade: CGFloat = 16
    /// In a list whose rows are drawn often, measured once for a text at a
    /// width; the layout only decides which of the two to show.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text).lineLimit(1).fixedSize()
            Text(text).lineLimit(1).fixedSize()
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .clipped()
                .mask {
                    HStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: fade)
                    }
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// The handle on an edge that pulls: the column's, the side panel's and the
/// one between two pages in Split View. Not a line the edge's whole height —
/// a short pill in the middle of it, as macOS and iPadOS draw theirs, that
/// grows a little and darkens under the pointer and while it is held. What
/// takes the pointer is still the whole edge; only the drawing is small.
enum Grip {
    static let width: CGFloat = 4
    /// Its length at rest, and under the pointer or held.
    static let rest: CGFloat = 28
    static let lit: CGFloat = 40
}

/// The pill itself (see Grip). `resting`: drawn, faint, before the pointer
/// comes; otherwise it is only there once the pointer is on the edge.
struct EdgeGrip: View {
    let lit: Bool
    var resting = false

    var body: some View {
        Capsule(style: .continuous)
            .fill(lit ? Palette.muted : Palette.faint)
            .frame(width: Grip.width, height: lit ? Grip.lit : Grip.rest)
            .opacity(lit || resting ? 1 : 0)
            .animation(Motion.quick, value: lit)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// One spring for anything that moves between two places, one for anything that
// arrives or leaves. Using the same two everywhere is most of why a thing feels
// like a single piece of software rather than a pile of views.
// When macOS Reduce Motion is on in System Settings, or Reduce animations in
// Search's own, transitions become immediate so the interface does not jump
// or slide.
enum Motion {
    /// Whether interface transitions should be immediate, following the
    /// Mac's own accessibility setting or Search's Reduce animations.
    static var reduced: Bool {
        instant || (testReduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// A test run's stand-in for the Mac's Reduce Motion, so what Reduce
    /// animations does alone can be seen on a Mac that has it on.
    nonisolated(unsafe) static var testReduceMotion: Bool?

    /// Settings › Appearance › Reduce animations, for Search alone: every
    /// transition is immediate, as under Reduce Motion, and so are the fades
    /// Reduce Motion keeps. The tab ⌘1–⌘9 picks is lit at once, the page
    /// shows at once, a panel is there or gone. Kept here rather than read
    /// from the settings each time, since quick is asked for in nearly every
    /// row's body; Preferences sets it as it reads and writes the switch.
    nonisolated(unsafe) static var instant = false

    nonisolated static let instantKey = "motion.instant"

    /// `seconds`, or none with Reduce animations on: for the fades that run
    /// on a length of their own rather than on the animations below.
    static func seconds(_ seconds: TimeInterval) -> TimeInterval {
        instant ? 0 : seconds
    }

    /// `animation`, or none with Reduce animations on, the same way.
    static func timed(_ animation: Animation) -> Animation? {
        instant ? nil : animation
    }

    /// Whether the Mac is short of power: Low Power Mode is on, or it is hot
    /// enough that macOS is holding its processors back. Then the two springs
    /// below become a short ease-out. A spring keeps moving long after it
    /// looks done: glide takes about 0.5 s to settle, 30 frames that SwiftUI
    /// works out one by one on the main thread, which is the thread a busy or
    /// slowed Mac takes time from first, and every frame it misses shows as a
    /// stutter. 0.16 s is 10 frames, and is over before a missed one shows.
    /// Read at the moment something moves, so it follows the switch at once.
    /// Only once it is turned on in Settings › General (Preferences.lightMotion).
    static var light: Bool {
        guard Store.settings.bool(forKey: lightKey) else { return false }
        return lowPowerMode || ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }

    /// The same switch, with Low Power Mode on and nothing else: idle tabs
    /// sleep sooner then (see Browser.sleepAfter). Heat alone doesn't count,
    /// since what a sleeping tab gives back is mostly memory, and a hot Mac
    /// has enough of that.
    static var savingPower: Bool {
        Store.settings.bool(forKey: lightKey) && lowPowerMode
    }

    nonisolated static let lightKey = "motion.light"

    /// Low Power Mode, from Battery in System Settings, or a test run's stand-in
    /// for it: only an admin can turn the real one on.
    nonisolated(unsafe) static var testLowPower: Bool?

    private static var lowPowerMode: Bool {
        testLowPower ?? ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    static var glide: Animation? {
        reduced ? nil : light ? .easeOut(duration: 0.16) : .spring(response: 0.34, dampingFraction: 0.82)
    }

    static var settle: Animation? {
        reduced ? nil : light ? .easeOut(duration: 0.16) : .spring(response: 0.30, dampingFraction: 0.86)
    }

    static var quick: Animation? {
        reduced ? nil : .easeOut(duration: 0.14)
    }

    /// How far a tab gives while it is pressed (see Give): enough to feel
    /// under the pointer, about 3 points on a pill and 7 on a column row.
    static let give: CGFloat = 0.97

    /// The folded column or strip coming out over the page, and going back.
    /// On glide it was slow both ways, next to Arc and Dia timed frame by
    /// frame on the same Mac: each slides its sidebar 90% of the way out in
    /// about 95ms and back in about 70ms, where glide took over 200ms. These
    /// match them. Going in is damped all the way, since nothing is arriving
    /// to settle. Fold.slide moves the window's buttons on the same numbers,
    /// in Core Animation's terms.
    static func fold(out: Bool) -> (response: Double, damping: Double) {
        out ? (0.14, 0.86) : (0.13, 1)
    }

    /// How long the folded column takes to slide back in, or fade, and
    /// is still over the page: the spring's response (Motion.fold) runs a
    /// little past it.
    static var columnAway: TimeInterval {
        if reduced { return 0 }
        if fadesColumn { return fade }
        return slide(out: false) ?? 0.2
    }

    static func folding(out: Bool) -> Animation? {
        if reduced { return nil }
        if let slide = slide(out: out) {
            return out ? .easeOut(duration: slide) : .easeIn(duration: slide)
        }
        let spring = fold(out: out)
        return .spring(response: spring.response, dampingFraction: spring.damping)
    }

    /// Settings › Appearance › Slide the column in and out: the column comes
    /// out on an ease-out and goes back on an ease-in, over this long, as
    /// Arc's does, rather than on the short springs above. Nil when off.
    /// Read at the moment it moves, as `light` is.
    static func slide(out: Bool) -> TimeInterval? {
        guard Store.settings.bool(forKey: slidesKey) else { return nil }
        return out ? 0.26 : 0.22
    }

    nonisolated static let slidesKey = "sidebar.slides"

    /// Slide the column in and out with the Mac's Reduce Motion on: the
    /// column fades in place where it would slide, as Apple's own sidebars
    /// do under Reduce Motion, rather than doing nothing at all, which read
    /// as a switch that does nothing. Search's own Reduce animations still
    /// means at once (see `instant`).
    static var fadesColumn: Bool {
        !instant && slide(out: true) != nil
            && (testReduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// That fade's length.
    static let fade: TimeInterval = 0.2
}

/// Lun's wordmark: three letters from one round-ended stroke, drawn for Lun
/// with no typeface inside it, so it is ours to use anywhere. The logo is
/// always "lun"; in sentences the name stays "Lun". Filled with the non-zero
/// rule: the u's and the n's bowls cross their stems, and even-odd would cut
/// holes where they do. The same stroke is in Icon/icon.swift.
struct Logomark: Shape {
    /// The ink's own size, nothing outside it.
    static let canvas = CGSize(width: 143, height: 77)
    private static let pen: CGFloat = 13

    func path(in rect: CGRect) -> Path {
        let half = Logomark.pen / 2
        var line = Path()
        // l
        line.move(to: CGPoint(x: half, y: half))
        line.addLine(to: CGPoint(x: half, y: 64 + half))
        // u
        line.move(to: CGPoint(x: 26 + half, y: 24 + half))
        line.addLine(to: CGPoint(x: 26 + half, y: 44 + half))
        line.addArc(center: CGPoint(x: 46 + half, y: 44 + half), radius: 20,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        line.addLine(to: CGPoint(x: 66 + half, y: 24 + half))
        line.move(to: CGPoint(x: 66 + half, y: 24 + half))
        line.addLine(to: CGPoint(x: 66 + half, y: 64 + half))
        // n
        line.move(to: CGPoint(x: 90 + half, y: 24 + half))
        line.addLine(to: CGPoint(x: 90 + half, y: 64 + half))
        line.move(to: CGPoint(x: 90 + half, y: 44 + half))
        line.addArc(center: CGPoint(x: 110 + half, y: 44 + half), radius: 20,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        line.addLine(to: CGPoint(x: 130 + half, y: 64 + half))
        let outline = line.strokedPath(StrokeStyle(lineWidth: Logomark.pen, lineCap: .round, lineJoin: .round))

        // Fit into whatever frame this is given, centred, at the larger
        // scale that still keeps it inside: an SVG viewBox's "meet".
        let scale = min(rect.width / Logomark.canvas.width, rect.height / Logomark.canvas.height)
        let x = rect.midX - Logomark.canvas.width * scale / 2
        let y = rect.midY - Logomark.canvas.height * scale / 2
        return outline.applying(CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale))
    }
}

/// Wrong address, said without a dialog: the field shivers and stops.
struct Shake: GeometryEffect {
    var travel: CGFloat

    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard !Motion.reduced else { return ProjectionTransform(.identity) }
        // Three there-and-backs, tapering to nothing, so it settles rather than
        // stopping mid-swing.
        let decay = 1 - travel
        return ProjectionTransform(
            CGAffineTransform(translationX: sin(travel * .pi * 6) * 7 * decay, y: 0)
        )
    }
}

extension View {
    /// What a popover holds, on the ground colour. From macOS 26 a popover
    /// clips what it holds to its own rounded glass, and the background
    /// fills its arrow too; before, an opaque background was drawn out to the
    /// content's square edges, past the popover's rounded corners (macOS 15,
    /// by email). There the popover is handed the colour and fills its own
    /// shape with it, arrow included. The bookmarks list and card were drawn
    /// as a rounded card of their own inside the popover, which left the
    /// arrow in the popover's lighter glass beside the darker card; they're
    /// on the ground as the rest are now.
    func popoverGround() -> some View {
        modifier(PopoverGround())
    }
}

private struct PopoverGround: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.background(Palette.ground)
        } else {
            content.presentationBackground(Palette.ground)
        }
    }
}

/// The page as a card in the window, with the tabs down the side: round
/// corners, a hairline edge and a soft shadow under it. The shadow is drawn
/// by a shape behind the page, never by the page's own layers, which would
/// make WebKit's drawing go through it; the page's view is rounded by its own
/// layer as well (see StageView), since a web view is AppKit's and a clip of
/// SwiftUI's is not always carried down to it. Two pages side by side are a
/// card each, drawn by the stage that holds them (see PaneStage).
struct CardEdge: ViewModifier {
    let on: Bool
    /// Where the card lies in the view, for a card drawn over a page laid
    /// out larger than it (the window's page as ⌘S moves the column): the
    /// clip, ground and edge follow these, animated, and the page doesn't.
    var insets = EdgeInsets()
    var corner: CGFloat = Metrics.cardRadius
    /// The screen's scale, for the window's page: its edges on whole
    /// pixels, a hairline one pixel wide and no soft shadow around it, so
    /// the white of the page meets the window's grey on a sharp line. Zero
    /// keeps the soft card other cards are (the side panel, downloads).
    var scale: CGFloat = 0

    // One shape of view, on or off: a page whose view were rebuilt as the
    // card comes and goes (the tabs across the top, a video taking the
    // screen) would be handed to a new stage just as WebKit takes it to its
    // full screen window. Off, the clip reaches far past the page and cuts
    // nothing, and the edge and shadow are clear.
    func body(content: Content) -> some View {
        let shape = CardShape(on: on, insets: insets, corner: corner, scale: scale)
        let crisp = scale > 0
        content
            .clipShape(shape)
            .background {
                if crisp {
                    shape.fill(on ? Palette.ground : .clear)
                } else {
                    shape
                        .fill(on ? Palette.ground : .clear)
                        .shadow(color: .black.opacity(on ? CardEdge.shadow : 0), radius: 6, y: 1)
                }
            }
            .overlay {
                shape
                    .strokeBorder(Color.primary.opacity(on && corner > 0 ? CardEdge.edge : 0),
                                  lineWidth: crisp ? 1 / scale : 1)
                    .allowsHitTesting(false)
            }
    }

    /// How dark the shadow and the edge are, for the stage's own cards too.
    static let shadow: Double = 0.07
    static let edge: Double = 0.08
}

/// The card's outline: round at its corners, or, off, a rectangle reaching
/// far past the page on every side.
private struct CardShape: InsettableShape {
    let on: Bool
    var insets = EdgeInsets()
    var corner: CGFloat = Metrics.cardRadius
    var scale: CGFloat = 0
    var inset: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get { .init(.init(insets.top, insets.leading), .init(.init(insets.bottom, insets.trailing), corner)) }
        set {
            insets = EdgeInsets(top: newValue.first.first, leading: newValue.first.second,
                                bottom: newValue.second.first.first, trailing: newValue.second.first.second)
            corner = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        guard on else { return Path(rect.insetBy(dx: -10_000, dy: -10_000)) }
        func pixel(_ x: CGFloat) -> CGFloat { scale > 0 ? (x * scale).rounded() / scale : x }
        let card = CGRect(x: pixel(rect.minX + insets.leading), y: pixel(rect.minY + insets.top),
                          width: pixel(rect.width - insets.leading - insets.trailing),
                          height: pixel(rect.height - insets.top - insets.bottom))
        return RoundedRectangle(cornerRadius: max(0, corner), style: .continuous)
            .path(in: card.insetBy(dx: inset, dy: inset))
    }

    func inset(by amount: CGFloat) -> CardShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}

/// An offset kept to the screen's pixels while it animates, so what it
/// moves is never drawn between two of them, resampled and soft.
struct PixelOffset: GeometryEffect {
    var offset: CGSize
    var scale: CGFloat

    var animatableData: CGSize.AnimatableData {
        get { offset.animatableData }
        set { offset.animatableData = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        func pixel(_ x: CGFloat) -> CGFloat { scale > 0 ? (x * scale).rounded() / scale : x }
        return ProjectionTransform(CGAffineTransform(translationX: pixel(offset.width), y: pixel(offset.height)))
    }
}

/// The window's page cut to its card on every frame the card moves (see
/// StageView.clip): what the card is short of the page laid out under it,
/// across and down, and its corners, handed on as SwiftUI works each frame
/// out, so the page's edge and the card's are one.
struct CardClip: ViewModifier, Animatable {
    var card: EdgeInsets
    var corner: CGFloat
    let scale: CGFloat
    let on: Bool

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get { .init(.init(card.top, card.leading), .init(.init(card.bottom, card.trailing), corner)) }
        set {
            card = EdgeInsets(top: newValue.first.first, leading: newValue.first.second,
                              bottom: newValue.second.first.first, trailing: newValue.second.first.second)
            corner = newValue.second.second
        }
    }

    func body(content: Content) -> some View {
        func pixel(_ x: CGFloat) -> CGFloat { scale > 0 ? (x * scale).rounded() / scale : x }
        let across = CGSize(width: pixel(card.leading + card.trailing), height: pixel(card.top + card.bottom))
        return content.background(Rider(across: on ? across : nil, corner: on ? max(0, corner) : 0))
    }

    /// The card, measured in the window: the room it leaves across and
    /// down, inside this view's own size. Read as the stage lays itself
    /// out, so the two are always of the same moment: handed a size worked
    /// out before the stage had grown, the card was cut short for a frame.
    private struct Rider: NSViewRepresentable {
        let across: CGSize?
        let corner: CGFloat

        func makeNSView(context: Context) -> NSView { Unseen() }

        func updateNSView(_ view: NSView, context: Context) {
            guard let unseen = view as? Unseen, let window = view.window else { return }
            // The window's stage: two pages' (PaneStage), or the one page's.
            if unseen.stage?.window !== window {
                unseen.stage = Self.find(in: window.contentView)
            }
            let card: (() -> CGSize)? = across.map { across in
                { [weak unseen] in
                    guard let unseen else { return .zero }
                    return CGSize(width: unseen.bounds.width - across.width, height: unseen.bounds.height - across.height)
                }
            }
            switch unseen.stage {
            case let panes as PaneStage: panes.clip(card: card, corner: corner)
            case let one as StageView: one.clip(card: card, corner: corner)
            default: break
            }
        }

        private static func find(in view: NSView?) -> NSView? {
            guard let view else { return nil }
            if view is PaneStage || view is StageView { return view }
            for sub in view.subviews { if let found = find(in: sub) { return found } }
            return nil
        }

        private final class Unseen: NSView {
            weak var stage: NSView?
            override func hitTest(_ point: NSPoint) -> NSView? { nil }
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                // The first frame's update may come before the window does.
                needsLayout = true
            }
        }
    }
}
