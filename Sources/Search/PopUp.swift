import SwiftUI

/// One value out of a few, behind a pill that says which: Lun's pop-up.
///
/// The Mac's own pop-up button was the one control in Settings that was not
/// Lun's: bordered, in its own type, and blind to the pointer. This is the
/// pill the buttons beside it are, with the pair of chevrons that says more
/// is behind it, and it answers the pointer as they do. What opens is still
/// the Mac's menu, ticked at the value chosen, so arrow keys, typing to
/// pick and VoiceOver work as everywhere else.
///
/// The choices are written as a picker's are: `Text("…").tag(value)`, with
/// a `Divider()` where one is wanted.
struct PopUp<Value: Hashable, Content: View>: View {
    /// What it chooses, for VoiceOver: no words of it are drawn.
    let label: String
    /// The chosen value, in words.
    let shows: String
    @Binding var selection: Value
    @ViewBuilder let content: () -> Content

    @State private var hovering = false

    init(_ label: String, shows: String, selection: Binding<Value>, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.shows = shows
        self._selection = selection
        self.content = content
    }

    var body: some View {
        Menu {
            Picker(label, selection: $selection, content: content)
                .pickerStyle(.inline)
                .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Text(shows)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.leading, 12)
            .padding(.trailing, 9)
            .frame(height: 24)
            .background(hovering ? Palette.fillHover : Palette.fill, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .hovers($hovering)
        .accessibilityLabel(label)
        .accessibilityValue(shows)
    }
}
