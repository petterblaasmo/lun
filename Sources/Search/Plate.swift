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
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 34, y: 12)
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
    }
}

/// A tick box in Lun's own drawing: a small square, ink with a tick when
/// it is on, an outline when it is not.
struct Tick: View {
    let on: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
            .fill(on ? Palette.ink : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(on ? Color.clear : Palette.muted.opacity(0.7), lineWidth: 1.2)
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
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
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
    let count: Int?
    let on: Bool
    let act: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            HStack(spacing: 8) {
                if globe || icon != nil { Mark(icon: icon, letter: "", size: 16, globe: true) }
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
                .background(hovering ? Palette.fillHover : Palette.fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(Gives(to: 0.95))
        .hovers($hovering)
    }
}
