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
    /// What a group of rows lies on, and a button or a field in one: the ink
    /// itself, a little of it, so a button on a group is a step darker.
    static let fill = Color(nsColor: NS.fill)
    static let fillHover = Color(nsColor: NS.fillHover)
    static let rule = Color(nsColor: NS.rule)
    /// What a chosen part of a picker lies on.
    static let knob = Color(nsColor: NS.knob)
    /// The only two that aren't grey: a connection nobody can read on the
    /// way, and one anybody can (see SiteCard.swift).
    static let safe = Color(nsColor: NS.safe)           // green-700 · green-400
    static let unsafe = Color(nsColor: NS.unsafe)       // amber-700 · amber-400

    // MARK: said once here, where each was written out by hand
    //
    // Each of these was a colour typed at several places, a shade apart
    // from one to the next.

    /// What takes something away for good, in its own words (Remove,
    /// Delete…), and the words of a refusal: the Mac's red, eased to sit
    /// with the greys.
    static let danger = Color.red.opacity(0.8)
    /// Round a field that refused what was typed: the address field, the
    /// launcher, Find with nothing found.
    static let dangerRing = Color.red.opacity(0.35)
    /// Ink a step back, between ink and muted: a title at rest that goes
    /// to ink under the pointer or once it is picked (the update's and the
    /// agent's pill, a live folder's item, a page a long swipe offers), and
    /// a small sign drawn in a row's ink (a page of Lun's own by its
    /// symbol, a download's ring).
    static let soft = ink.opacity(0.75)
    /// Round a tab or a pin chosen along with others.
    static let ring = ink.opacity(0.35)
    /// The outline of where what is being dragged would land.
    static let drop = ink.opacity(0.16)
    /// What dims the window under a panel, and under a peek, which is a
    /// page over the page and wants the one behind further back.
    static let scrim = Color.black.opacity(0.10)
    static let scrimDeep = Color.black.opacity(0.22)
    /// A hint over a page in full screen, most often over a video: black
    /// let through and white on it, whatever the window's appearance.
    static let overPage = Color.black.opacity(0.72)
    static let overPageEdge = Color.white.opacity(0.6)
    /// A count that wants looking at: the unread badge on a pin.
    static let badge = Color(red: 0.93, green: 0.24, blue: 0.21)
    /// Something is recording: the Mac's own red, as its menu bar's dot.
    static let recording = Color(nsColor: .systemRed)

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
        static let fill = shade(0.07, 0.08)
        static let fillHover = shade(0.11, 0.13)
        static let rule = shade(0.10, 0.10)
        static let knob = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.16) : .white
        }

        private static func shade(_ light: CGFloat, _ dark: CGFloat) -> NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(white: 0.93, alpha: dark) : NSColor(white: 0.09, alpha: light)
            }
        }
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
        Shared.prefs.sidebar ? 48 : Shared.prefs.compactStrip ? 36 : 44
    }
    /// The row under the tabs across the top, with back, forward, reload and
    /// the page's address in it (AddressRow).
    @MainActor static var addressRow: CGFloat { Shared.prefs.compactStrip ? 36 : 44 }
    /// A tab across the top as it stands on the page's card: down to the
    /// strip's foot, and this tall.
    @MainActor static var standingTab: CGFloat { Shared.prefs.compactStrip ? 30 : 36 }
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
    static let pinWidth: CGFloat = 36
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

/// The house's corners, all continuous: a control inside a control (a
/// track's knob, a step, a chip), a row's wash or a door or a key, a card
/// of rows or a field, what floats over the page from a field (the
/// launcher, a list under it), and a panel or a question. A shape inside
/// another takes the outer's less the gap between them, so their curves run
/// alongside: a theme's ring is 13 round a 10 picture, 3 away.
enum Radius {
    static let control: CGFloat = 6
    static let row: CGFloat = 8
    static let card: CGFloat = 10
    static let float: CGFloat = 14
    static let panel: CGFloat = 16
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

extension View {
    /// The shadow under what the hand has lifted out of its row and is
    /// carrying: a tab across the top, a pin, a tab's picture between
    /// windows. One lift for the three, which each had their own; deeper
    /// in a dark window, as the elevations are. Nothing while not `held`.
    func carriedShadow(_ held: Bool = true) -> some View {
        modifier(CarriedShadow(held: held))
    }
}

private struct CarriedShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let held: Bool

    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(held ? (scheme == .dark ? 0.4 : 0.16) : 0), radius: 12, y: 4)
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

/// A tab standing on the page's card: round at the top, and at the foot two
/// small curves out to either side, so the two are one piece.
struct StandingTab: Shape {
    var radius: CGFloat = 10
    /// The curves at the foot: the tab you're on; a tab under the pointer
    /// stops at its own edges.
    var flares = true

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - (flares ? r : 0), y: rect.maxY))
        if flares {
            path.addArc(center: CGPoint(x: rect.minX - r, y: rect.maxY - r), radius: r,
                        startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        if flares {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX + r, y: rect.maxY - r), radius: r,
                        startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
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

    // MARK: the rest of the vocabulary
    //
    // quick, settle and glide move things. These four are for what they
    // don't cover, so that no view has to write a curve of its own: an
    // Animation literal belongs in this enum and nowhere else, and a
    // transition is one of the named ones under it (AnyTransition.card and
    // the rest). Each is nil when nothing should move.

    /// One thing fading into another with nothing moving: a page's cover,
    /// the line a tab says at rest, a hint. A fade is what Reduce Motion
    /// asks for in place of movement, so the Mac's setting leaves it; only
    /// Reduce animations in Settings takes it away.
    static var dissolve: Animation? {
        instant ? nil : .easeOut(duration: 0.2)
    }

    /// Something meant to be watched arrive, not just to be there: the
    /// welcome's words under its mark, the column's buttons changing ends.
    static var slow: Animation? {
        reduced ? nil : light ? .easeOut(duration: 0.16) : .easeInOut(duration: 0.45)
    }

    /// The wordmark being written, l then u then n (LogomarkWritten).
    static var drawn: Animation? {
        reduced ? nil : .easeInOut(duration: 0.9)
    }

    /// What a swipe between spaces lets go of, carried the rest of the way:
    /// the rows, and the space's sign with them. A length of its own, and
    /// no spring, since something is waiting for it to finish.
    static var carry: Animation? {
        reduced ? nil : .easeOut(duration: 0.22)
    }

    /// The column fading in place where it doesn't slide (fadesColumn).
    static var columnFade: Animation? {
        fadesColumn ? .easeInOut(duration: fade) : nil
    }

    /// A refusal: the field shivers and stops (Shake, whose travel this
    /// takes from 0 to 1).
    static var shake: Animation? {
        reduced ? nil : .easeOut(duration: 0.5)
    }

    /// The kinds by name, for AppKit and Core Animation, which take a
    /// length and a curve rather than an Animation.
    enum Kind {
        case quick, settle, glide, dissolve, slow
        /// A page or what covered it fading: shorter than a dissolve, so
        /// the page is there sooner. Kept under Reduce Motion, as a fade is.
        case reveal
    }

    /// How long a kind takes, nought when nothing should move: for an
    /// NSAnimationContext, a CAAnimation, or whatever has to wait one out.
    static func duration(_ kind: Kind) -> TimeInterval {
        switch kind {
        case .quick: return reduced ? 0 : 0.14
        case .settle: return reduced ? 0 : light ? 0.16 : 0.30
        case .glide: return reduced ? 0 : light ? 0.16 : 0.34
        case .dissolve: return instant ? 0 : 0.2
        case .slow: return reduced ? 0 : light ? 0.16 : 0.45
        case .reveal: return instant ? 0 : 0.12
        }
    }

    /// The curve AppKit runs a kind on. A spring has no bezier; the one the
    /// two springs get was fitted by eye to glide for the Split View's
    /// panes (PaneStage), and reads the same.
    static func timing(_ kind: Kind) -> CAMediaTimingFunction {
        switch kind {
        case .quick, .dissolve, .reveal: return CAMediaTimingFunction(name: .easeOut)
        case .settle, .glide: return CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        case .slow: return CAMediaTimingFunction(name: .easeInEaseOut)
        }
    }

    /// AppKit's animator proxies moved in a kind's time, at once when
    /// nothing should move: `changes` sets `view.animator()` values.
    @MainActor static func run(_ kind: Kind, _ changes: () -> Void, then done: (@MainActor () -> Void)? = nil) {
        let length = duration(kind)
        guard length > 0 else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                changes()
            }
            done?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = length
            context.timingFunction = timing(kind)
            context.allowsImplicitAnimation = true
            changes()
        }, completionHandler: done.map { done in { MainActor.assumeIsolated { done() } } })
    }

    /// A panel of AppKit's coming on, once it is placed and in order: faded
    /// in, as a card SwiftUI draws arrives, where it was simply there. A
    /// fade, so the Mac's Reduce Motion keeps it. Not on a test run, which
    /// reads what a window shows the moment it is up.
    @MainActor static func arrive(_ window: NSWindow) {
        guard duration(.reveal) > 0, !Store.testing else { return }
        window.alphaValue = 0
        run(.reveal) { window.animator().alphaValue = 1 }
    }

    /// The same panel going: faded out, then `gone` (which takes it out of
    /// order). At once where nothing should move.
    @MainActor static func leave(_ window: NSWindow, then gone: @escaping @MainActor () -> Void) {
        guard duration(.reveal) > 0, !Store.testing, window.isVisible else { return gone() }
        run(.reveal, { window.animator().alphaValue = 0 }, then: gone)
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

    /// Motion.folding in Core Animation's terms, for the window's buttons,
    /// which a layer carries along with the column (Fold.slide): the eased
    /// slide where Settings asks for one, else the same spring.
    static func folding(out: Bool, keyPath: String) -> CABasicAnimation {
        if let slide = slide(out: out) {
            let eased = CABasicAnimation(keyPath: keyPath)
            eased.timingFunction = CAMediaTimingFunction(name: out ? .easeOut : .easeIn)
            eased.duration = slide
            return eased
        }
        let fold = fold(out: out)
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = 1
        spring.stiffness = pow(2 * .pi / fold.response, 2)
        spring.damping = 4 * .pi * fold.damping / fold.response
        spring.duration = spring.settlingDuration
        return spring
    }

    // MARK: lengths that are one surface's own
    //
    // Each was tuned where it is used and keeps its number. They are here
    // so that no file sets a length of its own, and so the two switches
    // reach them: nought where nothing should move.

    /// A hint over the page that is read and never pressed (the pointer's
    /// lock, "esc again" in full screen): there a little sooner than it
    /// is gone.
    static func hint(shown: Bool) -> TimeInterval {
        reduced ? 0 : shown ? 0.15 : 0.2
    }

    /// The line under the address while a page loads, running on to where
    /// the load has got to.
    static var lineRuns: TimeInterval {
        reduced ? 0 : 0.2
    }

    /// That line fading once the page is in. A fade, so the Mac's Reduce
    /// Motion keeps it.
    static var lineFades: TimeInterval {
        instant ? 0 : 0.3
    }

    /// One space's page fading into the next while the rows slide
    /// (PaneStage.show), on timing(.dissolve).
    static var spaceFade: TimeInterval {
        reduced ? 0 : 0.15
    }

    /// The Split View's pages moving to their new places, on timing(.glide):
    /// the curve was fitted to glide's spring at this length.
    static var panes: TimeInterval {
        reduced ? 0 : 0.32
    }

    /// A window's frame following what it holds (the downloads card as its
    /// list grows): tuned for a frame, which AppKit moves, not SwiftUI.
    static var resize: TimeInterval {
        reduced ? 0 : light ? 0.16 : 0.22
    }

    /// The floating video tucked down to a corner, and back to its size.
    static var tuck: TimeInterval {
        reduced ? 0 : 0.18
    }

    // MARK: what waits for a move
    //
    // A spring is on its place to the eye before it is at rest, and says
    // neither. What has to follow one waits these out.

    /// A glide as good as there: the page takes the room the column left
    /// (ContentView).
    static let glideLanded: TimeInterval = 0.42

    /// A glide at rest, about half a second and a little over: what would
    /// have cost it frames is done now (Browser.columnTurning).
    static let glideRested: TimeInterval = 0.6

    /// How long the back and forward swipe's disc is seen going with its
    /// page before it leaves (PageView.go).
    static let swipeGone: TimeInterval = 0.32

    // MARK: what goes round, and what bumps once

    /// What repeats for as long as it is there. Core Animation's, since a
    /// SwiftUI animation that never ends lays the window out every frame.
    enum Loop {
        /// The ring in a tab while its page loads.
        case spin
        /// The light passing over a peeked page's bones.
        case sweep
        /// The glow under the address field.
        case breathe
    }

    /// `animation` made to go round as `loop` does (how long, at what pace,
    /// and for the breath its way back), or nil where it should hold still.
    /// The ring turns whatever is asked: it says a page is still coming,
    /// and a ring standing still says the page has stopped. The light and
    /// the breath are only there to be looked at, and stop with the rest.
    static func loop<Turn: CAAnimation>(_ loop: Loop, _ animation: Turn) -> Turn? {
        switch loop {
        case .spin:
            animation.duration = 0.85
        case .sweep:
            guard !reduced else { return nil }
            animation.duration = 1.3
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        case .breathe:
            guard !reduced else { return nil }
            animation.duration = 2.6
            animation.autoreverses = true
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        animation.repeatCount = .infinity
        return animation
    }

    /// "Something just arrived here": how far a sign swells and how long it
    /// takes each way (the downloads door as a download starts). Under
    /// Reduce Motion it goes nowhere, for the same length: a keyframe of no
    /// length comes out as not a number, and AppKit stops the whole app
    /// over a transform like that.
    static func pulse(reduced: Bool = Motion.reduced, light: Bool = Motion.light) -> (peak: CGFloat, up: Double, down: Double) {
        let seconds = light ? 0.16 : 0.3
        return (reduced ? 1 : 1.35, seconds * 0.4, seconds * 0.6)
    }

    // MARK: what follows the fingers
    //
    // Three things are moved a frame at a time off the display, not by an
    // Animation: each sets off at the fingers' own speed or is caught again
    // halfway, which an Animation can't be. The arithmetic stays with each;
    // how hard its spring pulls is here with the rest. Under Reduce Motion
    // each is simply in its place, asked where it would start.

    /// The rows carried into place when a swipe between spaces is let go
    /// (SwipeGlide): how quickly the spring pulls, a second, critically
    /// damped. Most of the way in a tenth of a second, within a point of
    /// its place in a fifth. At 20, a slide took 0.4 s, and at 26 a third
    /// of a second: it felt slow, and the next stroke often had to wait
    /// for it.
    static let spacePull: Double = 34

    /// The Liquid Glass pane going from tab to tab (LensMotion): how hard
    /// it is pulled, and how much of its speed it loses. Three quarters of
    /// what would stop it without overshooting, so it overshoots a touch
    /// and settles at once. Less, and the wobble was the thing to watch
    /// rather than the tab.
    static let lens: (pull: Double, damping: Double) = (320, 27)

    /// The floating video flung to a corner: critically damped, quick away
    /// and into the corner without going past it, there within `within`.
    static let fling: (pull: CGFloat, within: CGFloat) = (15, 0.6)

    /// The same let back out from a side: underdamped (`damping` is the
    /// ratio), a little past its place and back to it.
    static let flingBack: (pull: CGFloat, damping: CGFloat, within: CGFloat) = (16, 0.5, 0.9)

    // MARK: what the system moves

    /// Whether a popover comes and goes on the system's own animation:
    /// `popover.animates = Motion.popovers` wherever an NSPopover is made.
    /// A popover is the system's to move, and under the Mac's Reduce Motion
    /// the system changes it itself; only Reduce animations is Lun's to
    /// apply. One made by SwiftUI's `.popover` (PopoverSide) can't be told
    /// either way and keeps the system's: the one exception to `instant`,
    /// with menus, alerts and standard windows.
    static var popovers: Bool {
        !instant
    }
}

/// Lun's wordmark: three letters from one round-ended stroke, drawn for Lun
/// with no typeface inside it, so it is ours to use anywhere. The logo is
/// always "lun"; in sentences the name stays "Lun". Filled with the non-zero
/// rule: the u's and the n's bowls cross their stems, and even-odd would cut
/// holes where they do. The same stroke is in Icon/icon.swift.
struct Logomark: Shape {
    /// The ink's own size, nothing outside it.
    static let canvas = CGSize(width: 143, height: 77)
    static let pen: CGFloat = 13

    /// Where the pen goes, in the canvas's own points: l, u, n, in the
    /// order a hand writes them.
    static let line: Path = {
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
        return line
    }()

    /// How much larger than its canvas it is drawn in `rect`.
    static func scale(in rect: CGRect) -> CGFloat {
        min(rect.width / Logomark.canvas.width, rect.height / Logomark.canvas.height)
    }

    /// Into whatever frame this is given, centred, at the larger scale that
    /// still keeps it inside: an SVG viewBox's "meet".
    static func fit(_ rect: CGRect) -> CGAffineTransform {
        let scale = scale(in: rect)
        let x = rect.midX - Logomark.canvas.width * scale / 2
        let y = rect.midY - Logomark.canvas.height * scale / 2
        return CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale)
    }

    func path(in rect: CGRect) -> Path {
        Logomark.line
            .strokedPath(StrokeStyle(lineWidth: Logomark.pen, lineCap: .round, lineJoin: .round))
            .applying(Logomark.fit(rect))
    }
}

/// The wordmark as the pen writes it, from nothing (`drawn` 0) to all three
/// letters (1): the welcome's first page. Drawn whole, it is Logomark.
struct LogomarkWritten: View {
    var drawn: CGFloat

    var body: some View {
        GeometryReader { box in
            let rect = CGRect(origin: .zero, size: box.size)
            Logomark.line.applying(Logomark.fit(rect))
                .trim(from: 0, to: drawn)
                .stroke(Palette.ink, style: StrokeStyle(lineWidth: Logomark.pen * Logomark.scale(in: rect), lineCap: .round, lineJoin: .round))
        }
        .aspectRatio(Logomark.canvas.width / Logomark.canvas.height, contentMode: .fit)
    }
}

// MARK: - how things arrive and leave
//
// Every surface comes and goes one of these ways, so a card is a card
// wherever it is. The animation that carries one goes on the container
// outside the `if`, `.animation(Motion.settle, value:)`: on the thing
// inserted it never runs.

extension AnyTransition {
    /// A card, a sheet, a question, a panel, a list under a field: up from
    /// a little smaller, from `anchor`, and back.
    static func card(from anchor: UnitPoint = .center) -> AnyTransition {
        .scale(scale: 0.97, anchor: anchor).combined(with: .opacity)
    }

    /// The same from its middle.
    static var card: AnyTransition { card() }

    /// What comes in along an edge and leaves by it: a toast at the foot,
    /// the find bar at the top.
    static func bar(_ edge: Edge) -> AnyTransition {
        .move(edge: edge).combined(with: .opacity)
    }

    /// One page of several replacing another: in from where it is going,
    /// out the other way.
    static func page(forward: Bool) -> AnyTransition {
        .asymmetric(insertion: .offset(x: forward ? 40 : -40).combined(with: .opacity),
                    removal: .offset(x: forward ? -40 : 40).combined(with: .opacity))
    }

    /// A row joining a list or leaving it, a sub-list opening under its
    /// heading.
    static func row(from anchor: UnitPoint = .top) -> AnyTransition {
        .scale(scale: 0.94, anchor: anchor).combined(with: .opacity)
    }

    /// A card's other face: the one a step in comes from the trailing side
    /// and goes back to it, the one it came from waits on the leading side.
    /// A short way, and faded: the card stays where it is.
    static func face(_ edge: HorizontalEdge) -> AnyTransition {
        .offset(x: edge == .leading ? -24 : 24).combined(with: .opacity)
    }

    /// The pages a long swipe back or forward offers, in the disc's place:
    /// grown from the edge the swipe came from, and less far going than
    /// coming, since the page is already on its way.
    static func swiped(from anchor: UnitPoint) -> AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: anchor)),
                    removal: .opacity.combined(with: .scale(scale: 0.96, anchor: anchor)))
    }

    /// A small sign: a badge, a tick, a count.
    static var pop: AnyTransition {
        .scale(scale: 0.6).combined(with: .opacity)
    }
}

// MARK: - how things answer

/// Gives a little under a press and comes back when it is let go, as a tab
/// does (Give): a press is answered before what it does is seen. Dimmed
/// when it can't be pressed.
struct Gives: ButtonStyle {
    /// How far it gives; a large thing less, or it looks to jump.
    var to: CGFloat = Motion.give
    /// Whether it dims itself where it can't be pressed; not for one that
    /// already says so its own way.
    var dims = true

    func makeBody(configuration: Configuration) -> some View {
        Pressed(configuration: configuration, to: to, dims: dims)
    }

    private struct Pressed: View {
        let configuration: Configuration
        let to: CGFloat
        let dims: Bool
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .opacity(enabled || !dims ? 1 : 0.4)
                .modifier(Give(pressed: configuration.isPressed, to: to))
        }
    }
}

extension View {
    /// Tracks the pointer over it into `hovering`, the change eased as
    /// every hover is.
    func hovers(_ hovering: Binding<Bool>) -> some View {
        onHover { hovering.wrappedValue = $0 }
            .animation(Motion.quick, value: hovering.wrappedValue)
    }

    /// A symbol bumped once when `value` changes, "something just arrived
    /// here", as the downloads door pulses (Motion.pulse). The bounce is
    /// the system's; where nothing should move the value it watches never
    /// changes, and the symbol holds still.
    func bumps<Value: Equatable>(on value: Value) -> some View {
        symbolEffect(.bounce, value: Motion.reduced ? nil : value)
    }
}

extension View {
    /// A row pressed as a whole that can't be a Button, since it holds
    /// buttons of its own or lies under other clicks: it gives under the
    /// press as a button does (Gives, by a tab's means: Pressing and Give)
    /// and does `act` on the click. A tap on a stack did the thing with
    /// nothing to say it had been pressed. After the row's contentShape.
    func pressed(to: CGFloat = 0.98, _ act: @escaping () -> Void) -> some View {
        modifier(PressedRow(to: to, act: act))
    }
}

private struct PressedRow: ViewModifier {
    let to: CGFloat
    let act: () -> Void
    @State private var down = false

    func body(content: Content) -> some View {
        content
            .modifier(Give(pressed: down, to: to))
            .modifier(Pressing(down: $down))
            .onTapGesture(perform: act)
    }
}

/// Hands what it draws whether the pointer is over it, eased as every
/// hover is: for one of many built in a loop (a swatch, a tile, a cell of
/// a grid), which has nowhere of its own to keep that.
struct Hovered<Label: View>: View {
    @ViewBuilder let label: (Bool) -> Label
    @State private var hovering = false

    var body: some View {
        label(hovering).hovers($hovering)
    }
}

/// A change made at once, from inside a control that slides a knob of its
/// own (Segmented, Switch): the knob still moves, on its own animation, and
/// what it sets in the window doesn't ride along on it. For what was set by
/// one of the Mac's controls, which carried no animation with it.
func atOnce(_ change: () -> Void) {
    withTransaction(Transaction(animation: nil), change)
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
    /// Round at the foot alone: the address row is the card's own top.
    var squareTop = false
    /// The card in the page's middle across (⌘S), or from its leading edge
    /// (the column's edge held): where the page is carried decides.
    var centred = true

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
        return content.background(Rider(across: on ? across : nil, corner: on ? max(0, corner) : 0, squareTop: squareTop,
                                        centred: centred))
    }

    /// The card, measured in the window: the room it leaves across and
    /// down, inside this view's own size. Read as the stage lays itself
    /// out, so the two are always of the same moment: handed a size worked
    /// out before the stage had grown, the card was cut short for a frame.
    private struct Rider: NSViewRepresentable {
        let across: CGSize?
        let corner: CGFloat
        let squareTop: Bool
        let centred: Bool

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
            case let panes as PaneStage: panes.clip(card: card, corner: corner, squareTop: squareTop, centred: centred)
            case let one as StageView: one.clip(card: card, corner: corner, squareTop: squareTop, centred: centred)
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
