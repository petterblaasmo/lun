import SwiftUI

/// The Themes page: pick a family, then its preset, then tune it. Every
/// preview is the same renderer as the blank tab, drawn once small and kept.
struct ThemesPage: View {
    @ObservedObject var prefs: Preferences
    /// The family on show. A family with nothing chosen yet (an image not
    /// picked) can be on show without being on the wall.
    @State private var family: HomeTheme.Family
    /// How wide the preview is, as wide as the page allows, for the
    /// families' picker and the cards. Not measured around the picker,
    /// whose segments would hold it wide.
    @State private var width: CGFloat = 0

    init(prefs: Preferences) {
        self.prefs = prefs
        _family = State(initialValue: prefs.homeTheme.family)
    }

    private let thumb = CGSize(width: 160, height: 100)
    private let columns = Array(repeating: GridItem(.fixed(160 + 6), spacing: 14, alignment: .top), count: 3)
    /// Where the page is too narrow for three, as many as fit.
    private let fewer = [GridItem(.adaptive(minimum: 160 + 6, maximum: 160 + 6), spacing: 14, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            mock

            // The families side by side, in Lun's own track; a pop-up
            // where the six would run off the card.
            ViewThatFits(in: .horizontal) {
                Segmented(options: HomeTheme.Family.allCases.map { ($0, $0.title) }, selection: chosenFamily)
                PopUp("Theme", shows: family.title, selection: chosenFamily) {
                    ForEach(HomeTheme.Family.allCases) { Text($0.title).tag($0) }
                }
            }

            switch family {
            case .off:
                Text("The blank tab stays plain.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            case .wall:
                grid(HomeTheme.walls.map { theme in
                    card(theme.title, on: prefs.homeTheme == theme, preview: preview(theme)) { prefs.homeTheme = theme }
                })
            case .stickers:
                grid(StickerPack.allCases.map { pack in
                    var t = prefs.homeTuning
                    t.pack = pack
                    return card(pack.title, on: prefs.homeTheme == .stickers && prefs.homeTuning.pack == pack,
                                preview: preview(.stickers, t)) {
                        prefs.homeTuning.pack = pack
                        prefs.homeTheme = .stickers
                    }
                })
            case .solid:
                solid
            case .gradient:
                gradient
            case .image:
                image
            }

            if family == .wall || family == .stickers {
                Ticked("Shuffle: a different one each day", on: $prefs.homeShuffle)
            }

            if family != .off && (family != .image || HomeBackground.load(prefs.homeThemeImage) != nil) {
                sliders
            }
        }
    }

    /// The family on show, chosen at once: the page under the track
    /// changes as it did under the Mac's picker, and only the track's own
    /// white slides.
    private var chosenFamily: Binding<HomeTheme.Family> {
        Binding(get: { family }, set: { next in atOnce { choose(next) } })
    }

    // MARK: - the live preview

    /// The window in small: the tabs where yours are, the address field in
    /// the middle, and the chosen theme behind it. It is the blank tab's own
    /// renderer, so it changes when a theme is picked or a slider let go.
    private var mock: some View {
        let size = CGSize(width: 480, height: 300)
        let side = prefs.sidebar
        let right = prefs.sidePosition == .right
        return ZStack {
            Palette.ground
            if prefs.homeTheme != .off {
                HomeBackground(theme: prefs.homeTheme, tuning: prefs.homeTuning, image: prefs.homeThemeImage,
                               shuffle: prefs.homeShuffle)
            }
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.ground)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                .overlay(Text("Search or enter address")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted))
                .frame(width: 220, height: 30)
            tabs(side: side, right: right)
        }
        .frame(maxWidth: size.width) // Narrower where the page is
        .frame(height: size.height)
        .background(GeometryReader { box in
            Color.clear
                .onAppear { width = box.size.width }
                .onChange(of: box.size.width) { _, now in width = now }
        })
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tabs(side: Bool, right: Bool) -> some View {
        let bar = RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Palette.muted.opacity(0.35))
        if side {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<4, id: \.self) { _ in bar.frame(height: 8) }
                Spacer()
            }
            .padding(10)
            .frame(width: 70)
            .frame(maxHeight: .infinity)
            .background(Palette.ground.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: right ? .trailing : .leading)
        } else {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { _ in bar.frame(width: 56, height: 10) }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .frame(maxWidth: .infinity)
            .background(Palette.ground.opacity(0.55))
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - choosing

    private func choose(_ next: HomeTheme.Family) {
        family = next
        switch next {
        case .off: prefs.homeTheme = .off
        case .image:
            // On the wall only once there is a picture to put there.
            if HomeBackground.load(prefs.homeThemeImage) != nil { prefs.homeTheme = .custom }
        default:
            if prefs.homeTheme.family != next { prefs.homeTheme = next.first }
        }
    }

    private func preview(_ theme: HomeTheme, _ tuning: HomeTuning? = nil) -> some View {
        HomeBackground(theme: theme, tuning: tuning ?? prefs.homeTuning, image: prefs.homeThemeImage, thumbnail: true)
    }

    private func grid(_ cards: [some View]) -> some View {
        LazyVGrid(columns: width >= 470 ? columns : fewer, // Wraps when narrow
                   alignment: .leading, spacing: 14) {
            ForEach(cards.indices, id: \.self) { cards[$0] }
        }
    }

    private func card(_ title: String, on: Bool, preview: some View, action: @escaping () -> Void) -> some View {
        // Under the pointer its edge and its name go to ink, and it gives
        // under the press, a little: it is large.
        Hovered { hovering in
            Button(action: action) {
                VStack(spacing: 6) {
                    preview
                        .frame(width: thumb.width, height: thumb.height)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(hovering && !on ? Palette.ring : Palette.hairline, lineWidth: 1))
                        .padding(3)
                        .overlay(RoundedRectangle(cornerRadius: Radius.card + 3, style: .continuous)
                            .strokeBorder(on ? Palette.ink : .clear, lineWidth: 2.5))
                    Text(title)
                        .font(.system(size: 12, weight: on ? .medium : .regular))
                        .foregroundStyle(on || hovering ? Palette.ink : Palette.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Gives(to: 0.98))
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - families

    private var solid: some View {
        let swatches = ["#E8DFD0", "#F3D9CF", "#D9E4D3", "#D3DFEA", "#E4D8EC", "#2B2B2E"]
        return HStack(spacing: 10) {
            ForEach(swatches, id: \.self) { hex in
                Hovered { hovering in
                    Button {
                        prefs.homeTuning.solid = hex
                        prefs.homeTheme = .solid
                    } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 24, height: 24)
                            .overlay(Circle().strokeBorder(prefs.homeTuning.solid == hex && prefs.homeTheme == .solid
                                                           ? Palette.ink : hovering ? Palette.ring : Palette.hairline, lineWidth: 1.5))
                    }
                    .buttonStyle(Gives(to: 0.92))
                }
                .accessibilityLabel("Colour \(hex)")
            }
            ColorPicker("Colour", selection: Binding(
                get: { Color(hex: prefs.homeTuning.solid) },
                set: { prefs.homeTuning.solid = $0.hex; prefs.homeTheme = .solid }), supportsOpacity: false)
        }
    }

    private var gradient: some View {
        VStack(alignment: .leading, spacing: 12) {
            grid(GradientPreset.allCases.map { preset in
                var t = prefs.homeTuning
                (t.gradientA, t.gradientB, t.angle) = preset.colours
                return card(preset.title,
                            on: prefs.homeTheme == .gradient && prefs.homeTuning.gradientA == preset.colours.a
                                && prefs.homeTuning.gradientB == preset.colours.b,
                            preview: preview(.gradient, t)) {
                    (prefs.homeTuning.gradientA, prefs.homeTuning.gradientB, prefs.homeTuning.angle) = preset.colours
                    prefs.homeTheme = .gradient
                }
            })
            HStack(spacing: 16) {
                ColorPicker("From", selection: Binding(
                    get: { Color(hex: prefs.homeTuning.gradientA) },
                    set: { prefs.homeTuning.gradientA = $0.hex; prefs.homeTheme = .gradient }), supportsOpacity: false)
                ColorPicker("To", selection: Binding(
                    get: { Color(hex: prefs.homeTuning.gradientB) },
                    set: { prefs.homeTuning.gradientB = $0.hex; prefs.homeTheme = .gradient }), supportsOpacity: false)
            }
            ThemeSlider(title: "Angle", value: prefs.homeTuning.angle, range: 0...360, unit: "°") {
                prefs.homeTuning.angle = $0
                prefs.homeTheme = .gradient
            }
        }
    }

    private var image: some View {
        HStack(alignment: .top, spacing: 16) {
            Group {
                if HomeBackground.load(prefs.homeThemeImage) != nil {
                    HomeBackground(theme: .custom, tuning: prefs.homeTuning, image: prefs.homeThemeImage, thumbnail: true)
                } else {
                    Palette.wash.overlay(Image(systemName: "photo").foregroundStyle(Palette.muted))
                }
            }
            .frame(width: 176, height: 114)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            VStack(alignment: .leading, spacing: 8) {
                Pill("Choose Image…") {
                    // Cancelled, or not copied: what was there stays.
                    guard let kept = HomeTheme.choose() else { return }
                    let old = prefs.homeThemeImage
                    prefs.homeThemeImage = kept
                    if old != kept { HomeTheme.forget(old) }
                    prefs.homeTheme = .custom
                }
                if prefs.homeThemeImage != nil {
                    Pill("Remove") {
                        HomeTheme.forget(prefs.homeThemeImage)
                        prefs.homeThemeImage = nil
                        if prefs.homeTheme == .custom { prefs.homeTheme = .off }
                    }
                }
                Text("A copy is kept inside Lun.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
        }
    }

    // MARK: - tuning

    @ViewBuilder
    private var sliders: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThemeSlider(title: "Intensity", value: prefs.homeTuning.intensity * 100, range: 0...100, unit: "%") {
                prefs.homeTuning.intensity = $0 / 100
            }
            if prefs.homeTheme == .stickers {
                ThemeSlider(title: "Density", value: prefs.homeTuning.density * 100, range: 0...100, unit: "%") {
                    prefs.homeTuning.density = $0 / 100
                }
            }
            if prefs.homeTheme == .stickers {
                ThemeSlider(title: "Scale", value: prefs.homeTuning.scale * 100, range: 0...100, unit: "%") {
                    prefs.homeTuning.scale = $0 / 100
                }
            }
        }
    }
}

/// A slider that is let go before it is applied: dragging it would draw the
/// whole background again at every step, and one drawing is enough.
private struct ThemeSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let unit: String
    let commit: (Double) -> Void
    @State private var held: Double?

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                .frame(width: 64, alignment: .leading)
            Slide(value: Binding(get: { held ?? value }, set: { held = $0 }), range: range) { editing in
                if !editing, let done = held {
                    commit(done)
                    held = nil
                }
            }
            .accessibilityLabel(title)
            Text("\(Int((held ?? value).rounded()))\(unit)")
                .font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.muted)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
