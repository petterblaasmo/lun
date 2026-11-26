import SwiftUI

// The pieces every panel is made of, so that Settings, History, Downloads,
// Passwords and Bookmarks read as one kind of thing: the same plate, the
// same title with the cross beside it, the same hairline cards with a rule
// between lines, the same field for searching. Built once here; each panel
// only says what goes in it.

/// The plate: a rounded card with a title, a cross, whatever the panel is
/// about, and — when there is one — a foot below a hairline.
struct Plate<Content: View, Foot: View>: View {
    let title: String
    /// A line under the title, in a tab of its own.
    var line: String? = nil
    var width: CGFloat = 560
    /// How wide it is in a tab of its own: as wide as a list wants to be.
    var across: CGFloat = 960
    /// What is done with all of it, beside its title.
    var tools: AnyView? = nil
    let close: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let foot: () -> Foot

    init(
        _ title: String,
        line: String? = nil,
        width: CGFloat = 560,
        across: CGFloat = 960,
        tools: AnyView? = nil,
        close: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder foot: @escaping () -> Foot
    ) {
        self.title = title
        self.line = line
        self.width = width
        self.across = across
        self.tools = tools
        self.close = close
        self.content = content
        self.foot = foot
    }

    @Environment(\.asTab) private var asTab

    var body: some View {
        if asTab { page } else { card }
    }

    /// In a tab of its own (see InternalPages.swift): the title with what is
    /// done with all of it beside it, then the content, the page's width. No
    /// card, no shadow, no cross — the tab is what closes.
    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let line {
                        Text(line)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                    }
                }
                Spacer(minLength: 16)
                if let tools { tools }
            }
            .frame(minHeight: 32)
            .padding(.top, 28)
            .padding(.bottom, 20)

            content()

            if Foot.self != EmptyView.self {
                foot()
                    .padding(.vertical, 14)
            }
            Color.clear.frame(height: 12)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: across + 64, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                if let tools { tools }
                Door(icon: "xmark", help: "Done   esc", act: close)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 14)

            content()
                .padding(.horizontal, 22)

            if Foot.self != EmptyView.self {
                Rectangle().fill(Palette.hairline).frame(height: 1)
                    .padding(.top, 18)
                foot()
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
            } else {
                Color.clear.frame(height: 20)
            }
        }
        .frame(width: width, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .elevated(.overlay, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), fill: Palette.ground)
    }
}

extension Plate where Foot == EmptyView {
    init(
        _ title: String,
        line: String? = nil,
        width: CGFloat = 560,
        across: CGFloat = 960,
        tools: AnyView? = nil,
        close: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title, line: line, width: width, across: across, tools: tools, close: close, content: content, foot: { EmptyView() })
    }
}

/// A group of lines in one hairline box.
struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(Palette.fill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// The hairline between two lines of a card, inset like the text unless
/// the card says otherwise (see EnvironmentValues.ruleInset).
struct Rule: View {
    var inset: CGFloat? = nil
    @Environment(\.ruleInset) private var standard
    var body: some View {
        Rectangle().fill(Palette.rule).frame(height: 1).padding(.leading, inset ?? standard).padding(.trailing, max(0, inset ?? standard))
    }
}

private struct RuleInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 16
}

extension EnvironmentValues {
    /// Where a Rule without an inset of its own starts and ends: under the
    /// text, as far from the card's edges as it is.
    var ruleInset: CGFloat {
        get { self[RuleInsetKey.self] }
        set { self[RuleInsetKey.self] = newValue }
    }
}

/// One thing to set or do: what it is on the left, the control on the right.
struct Line<Control: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let control: () -> Control

    init(_ title: String, _ detail: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .turnsItsSwitch(title)
    }
}

/// A tick box in Lun's own drawing: a small square, ink with a tick when
/// it is on, an outline when it is not.
struct Tick: View {
    let on: Bool
    /// Under the pointer: its edge goes to ink, and its ink eases off as a
    /// filled pill's does.
    var lit = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
            .fill(on ? Palette.ink.opacity(lit ? 0.86 : 1) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(on ? Color.clear : lit ? Palette.ink : Palette.muted.opacity(0.7), lineWidth: 1.2)
            )
            .overlay {
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Palette.ground)
                }
            }
            .frame(width: 16, height: 16)
    }
}

/// A tick box with its words beside it: one of a few things side by side
/// (Ticks), or a line of its own under a form. The words are part of the
/// button, and it is a little taller to land on than it looks.
struct Ticked: View {
    let title: String
    @Binding var on: Bool
    @State private var hovering = false

    init(_ title: String, on: Binding<Bool>) {
        self.title = title
        self._on = on
    }

    var body: some View {
        Button { on.toggle() } label: {
            HStack(spacing: 7) {
                Tick(on: on, lit: hovering)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .padding(.vertical, -4)
        }
        .buttonStyle(Gives(to: 0.96))
        .hovers($hovering)
        .accessibilityLabel(title)
        .accessibilityValue(on ? "Ticked" : "Not ticked")
        .accessibilityAddTraits(.isToggle)
    }
}

/// One thing a checklist offers: its tick, what it is, what will happen to
/// it, and how many there are. The whole row is the button, so it is as
/// easy to land on as it is wide; one with nothing to bring is dimmed and
/// can't be ticked.
struct Checked: View {
    let title: String
    let detail: String?
    /// How many there are, at the row's end.
    var count: String? = nil
    @Binding var on: Bool
    /// Nothing of this kind to choose.
    var none = false

    @State private var hovering = false

    init(_ title: String, _ detail: String? = nil, count: String? = nil, on: Binding<Bool>, none: Bool = false) {
        self.title = title
        self.detail = detail
        self.count = count
        self._on = on
        self.none = none
    }

    var body: some View {
        Button { on.toggle() } label: {
            HStack(alignment: .center, spacing: 12) {
                Tick(on: on && !none)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let count {
                    Text(count)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(hovering && !none ? Palette.fillHover : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(Gives(to: 0.995))
        .disabled(none)
        .hovers($hovering)
        .accessibilityLabel(title)
        .accessibilityValue(none ? "None" : (on ? "Ticked" : "Not ticked") + (count.map { ", \($0)" } ?? ""))
        .accessibilityAddTraits(.isToggle)
    }
}

/// One row of a list in a card, pressed to do the one thing the row is for:
/// a real button, so the keyboard and VoiceOver can press it. Under the
/// pointer it lies on a darker band, rounded and in from the card's edges;
/// under the press the whole row gives. What else the row does (Remove,
/// Show in Finder) goes in `trailing`, beside the button and not in it, so
/// each takes its own click. The label brings its own height and its
/// leading inset; the trailing end its own.
struct RowButton<Label: View, Trailing: View>: View {
    /// How far in from the card's sides the band under the pointer stops.
    static var inset: CGFloat { 4 }

    /// The row under the pointer, for one that shows something only then.
    /// Where it is given, it is what the row draws from.
    var hovering: Binding<Bool>?
    var selected = false
    /// False where there is nothing to open (a file that has gone): no
    /// band, no press, and what is beside the button still answers.
    var works = true
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @ViewBuilder let trailing: () -> Trailing

    @State private var inside = false
    @State private var pressed = false

    init(hovering: Binding<Bool>? = nil, selected: Bool = false, works: Bool = true, action: @escaping () -> Void,
         @ViewBuilder label: @escaping () -> Label, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.hovering = hovering
        self.selected = selected
        self.works = works
        self.action = action
        self.label = label
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                label()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(Tells(pressed: $pressed))
            .disabled(!works)
            .accessibilityAddTraits(selected ? .isSelected : [])
            trailing()
        }
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(lit && works ? Palette.fillHover : Color.clear)
                .padding(.horizontal, Self.inset)
                .padding(.vertical, 2)
        }
        .modifier(Give(pressed: pressed, to: 0.99))
        .onHover {
            inside = $0
            hovering?.wrappedValue = $0
        }
        .animation(Motion.quick, value: lit)
    }

    private var lit: Bool { hovering?.wrappedValue ?? inside }

    /// Draws nothing of its own and says when it is down: the row gives as
    /// one, what is beside the button with it.
    private struct Tells: ButtonStyle {
        @Binding var pressed: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .onChange(of: configuration.isPressed) { _, down in pressed = down }
        }
    }
}

extension RowButton where Trailing == EmptyView {
    init(hovering: Binding<Bool>? = nil, selected: Bool = false, works: Bool = true, action: @escaping () -> Void,
         @ViewBuilder label: @escaping () -> Label) {
        self.init(hovering: hovering, selected: selected, works: works, action: action, label: label, trailing: { EmptyView() })
    }
}

/// A symbol that is a button, anywhere but in the column (Door is the
/// column's): a cross, a step, a knob. It can't be made without saying what
/// it does, which is its name to VoiceOver and its tooltip; it goes to ink
/// under the pointer, gives under the press, dims where it can't be
/// pressed, and is never smaller to land on than `hit`, however small it
/// is drawn.
struct IconButton: View {
    let symbol: String
    let label: String
    /// The symbol's own size.
    var glyph: CGFloat = 11
    var weight: Font.Weight = .medium
    /// The side of what is drawn behind it under the pointer.
    var size: CGFloat = 24
    /// The least there is to press, with nothing moved to make the room.
    var hit: CGFloat = 24
    /// A disc behind it, not a rounded square.
    var round = false
    /// At rest; under the pointer, and while `on`, it is ink.
    var tint: Color = Palette.muted
    /// What it lies on under the pointer. Nil for one that only darkens.
    var wash: Color? = Palette.fillHover
    var on = false
    /// The tooltip, where it says more than the name. Empty for one whose
    /// caller puts its own on (with the key that does the same).
    var tip: String?
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    init(_ symbol: String, label: String, glyph: CGFloat = 11, weight: Font.Weight = .medium, size: CGFloat = 24,
         hit: CGFloat = 24, round: Bool = false, tint: Color = Palette.muted, wash: Color? = Palette.fillHover,
         on: Bool = false, tip: String? = nil, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.glyph = glyph
        self.weight = weight
        self.size = size
        self.hit = hit
        self.round = round
        self.tint = tint
        self.wash = wash
        self.on = on
        self.tip = tip
        self.action = action
    }

    /// How much is added on every side to make the hit area.
    var grown: CGFloat { max(0, (hit - size) / 2) }

    var body: some View {
        let lit = hovering && enabled
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: weight))
                .foregroundStyle(on || lit ? Palette.ink : tint)
                .frame(width: size, height: size)
                .background((lit ? wash : nil) ?? Color.clear,
                            in: round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: min(8, size / 3), style: .continuous)))
                .padding(grown)
                .contentShape(Rectangle())
        }
        .buttonStyle(Gives(to: 0.88))
        .hovers($hovering)
        .accessibilityLabel(label)
        .modifier(Tip(text: tip ?? label))
        // The button itself is the larger; taken back out here, around
        // it, so nothing beside it moves. Taken back inside its label, the
        // press still stopped at what was drawn (PressTests).
        .padding(-grown)
    }

    private struct Tip: ViewModifier {
        let text: String

        func body(content: Content) -> some View {
            if text.isEmpty { content } else { content.help(text) }
        }
    }
}

/// Words that go somewhere, or do one quiet thing: ink and underlined under
/// the pointer, with the pointing hand, and they give under the press. As
/// tall to press as a line of a list, though it is drawn no taller than its
/// text.
struct TextLink: View {
    let title: String
    /// At rest.
    var tint: Color = Palette.muted
    /// After the words: an arrow where it leads on.
    var symbol: String?
    /// Underlined at rest too: one in the middle of a sentence, where only
    /// the line says it can be pressed.
    var underlined = false
    /// As large as the words it stands among, and never under twelve.
    var size: CGFloat = 12
    let action: () -> Void

    @State private var hovering = false

    init(_ title: String, tint: Color = Palette.muted, symbol: String? = nil, underlined: Bool = false, size: CGFloat = 12,
         action: @escaping () -> Void) {
        self.title = title
        self.tint = tint
        self.symbol = symbol
        self.underlined = underlined
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).underline(underlined || hovering)
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                }
            }
            .font(.system(size: max(12, size)))
            .foregroundStyle(hovering ? Palette.ink : tint)
            .lineLimit(1)
            .padding(.vertical, Self.grown)
            .contentShape(Rectangle())
        }
        .buttonStyle(Gives(to: 0.97))
        .hovers($hovering)
        .pointingHand()
        // Taller to press than its words, with the line it is in no taller
        // for it (see IconButton).
        .padding(.vertical, -Self.grown)
    }

    /// What is added over and under the words to press.
    static var grown: CGFloat { 4 }
}

/// A heading that opens what is under it and closes it again: one arrow
/// that turns, where some swapped one glyph for another. Ink under the
/// pointer, and it says to VoiceOver whether it is open.
struct Disclosure<Extra: View>: View {
    let title: String
    @Binding var open: Bool
    var weight: Font.Weight = .regular
    /// After the words: a sign that something in it is chosen.
    @ViewBuilder let extra: () -> Extra

    @State private var hovering = false

    init(_ title: String, open: Binding<Bool>, weight: Font.Weight = .regular, @ViewBuilder extra: @escaping () -> Extra) {
        self.title = title
        self._open = open
        self.weight = weight
        self.extra = extra
    }

    var body: some View {
        Button { withAnimation(Motion.quick) { open.toggle() } } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                Text(title).font(.system(size: 12, weight: weight))
                extra()
            }
            .foregroundStyle(hovering ? Palette.ink : Palette.muted)
            .padding(.vertical, TextLink.grown)
            .contentShape(Rectangle())
        }
        .buttonStyle(Gives(to: 0.97))
        .hovers($hovering)
        .accessibilityLabel(title)
        .accessibilityValue(open ? "Expanded" : "Collapsed")
        .padding(.vertical, -TextLink.grown)
    }
}

extension Disclosure where Extra == EmptyView {
    init(_ title: String, open: Binding<Bool>, weight: Font.Weight = .regular) {
        self.init(title, open: open, weight: weight, extra: { EmptyView() })
    }
}

extension View {
    /// The pointing hand over what leads somewhere, as a link on a page has.
    func pointingHand() -> some View { modifier(PointingHand()) }

    /// A row with a switch in it turns the switch wherever it is clicked,
    /// and lies on a darker wash under the pointer to say so. `title` is
    /// what the switch is called to VoiceOver, which had "switch" alone.
    func turnsItsSwitch(_ title: String? = nil, lit: Bool = false) -> some View {
        modifier(TurnsItsSwitch(title: title, lit: lit))
    }
}

private struct PointingHand: ViewModifier {
    @State private var pushed = false

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(.link)
        } else {
            // Before the Mac had a pointer style to ask for: put on over
            // it and taken off again, also when it goes from under the
            // pointer by being pressed.
            content
                .onHover { inside in
                    guard inside != pushed else { return }
                    pushed = inside
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .onDisappear {
                    if pushed { NSCursor.pop() }
                    pushed = false
                }
        }
    }
}

/// What a row and the switch in it say to each other: the switch leaves
/// how it is turned here, and a click anywhere on the row uses it. A row
/// whose control is anything else has nothing left here and stays as it
/// was. Passed down rather than asked of each call site, so every row
/// with a switch answers and none had to be rewritten.
@MainActor
final class RowSwitch {
    /// Turns the switch, as a click on it does. Nil while there is none in
    /// the row, or it can't be turned.
    var turn: (() -> Void)?
    /// Whose `turn` it is: a switch leaving the row clears only its own.
    var owner: UUID?
}

private struct RowSwitchKey: EnvironmentKey {
    static let defaultValue: RowSwitch? = nil
}

private struct RowTitleKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The row a switch is in, where its row answers for it (turnsItsSwitch).
    var rowSwitch: RowSwitch? {
        get { self[RowSwitchKey.self] }
        set { self[RowSwitchKey.self] = newValue }
    }

    /// What that row is called, for the switch to be called too.
    var rowTitle: String? {
        get { self[RowTitleKey.self] }
        set { self[RowTitleKey.self] = newValue }
    }
}

private struct TurnsItsSwitch: ViewModifier {
    let title: String?
    let lit: Bool
    @State private var held = RowSwitch()
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .environment(\.rowSwitch, held)
            .environment(\.rowTitle, title)
            // Read when the pointer comes: the switch has left its turn by
            // then, having been drawn.
            .background(lit || (hovering && held.turn != nil) ? Palette.fillHover : Color.clear)
            .contentShape(Rectangle())
            // The switch, the (i) and any other button in the row take
            // their own clicks; this has the rest of it.
            .onTapGesture { held.turn?() }
            .hovers($hovering)
    }
}

/// A small heading over a card, for when a panel has more than one.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Palette.muted)
            .padding(.leading, 16)
    }
}

/// The field for narrowing a list. The wash, the glass, the caret.
struct Hunt: View {
    @Binding var text: String
    var prompt = "Search"
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(prompt).foregroundStyle(Palette.muted)
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Palette.ink)
                    .focused(focus)
            }
            .font(.system(size: 13))
            if !text.isEmpty {
                IconButton("xmark.circle.fill", label: "Clear", glyph: 11, weight: .regular, size: 16, wash: nil) { text = "" }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A list's narrower choices, down the side of a page: what each one is
/// called and how many there are.
struct SideChoice: View {
    let title: String
    var icon: NSImage?
    var globe = false
    /// A sign in front of the words, where there is no icon: a warning's.
    var symbol: String?
    var symbolTint: Color = Palette.muted
    let count: Int?
    let on: Bool
    let act: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            HStack(spacing: 8) {
                if globe || icon != nil { Mark(icon: icon, letter: "", size: 16, globe: true) }
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(symbolTint)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.system(size: 13, weight: on ? .medium : .regular))
                    .foregroundStyle(on || hovering ? Palette.ink : Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let count {
                    Text(count.formatted())
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(on ? Palette.fill : hovering ? Palette.hover : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(Gives(to: 0.98))
        .hovers($hovering)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// What a panel says when its list is empty.
struct Nothing: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
    }
}

/// A small text action inside a row — Show, Copy, Remove.
struct Quick: View {
    let title: String
    var tint: Color = Palette.ink
    let act: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    init(_ title: String, tint: Color = Palette.ink, act: @escaping () -> Void) {
        self.title = title
        self.tint = tint
        self.act = act
    }

    var body: some View {
        Button(action: act) {
            // On one line, whatever room is left: in the narrow downloads
            // card, Resume, Retry and Remove broke in the middle of a word.
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 22)
                // Not lit where it can't be pressed (Pausing…): dimmed
                // and lit, it still looked ready.
                .background(hovering && enabled ? Palette.fillHover : Palette.fill, in: Capsule())
                // A point over and under to land on: 22 drawn, 24 pressed.
                .padding(.vertical, 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(Gives(to: 0.95))
        .hovers($hovering)
        .padding(.vertical, -1)
    }
}
