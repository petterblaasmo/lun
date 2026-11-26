import SwiftUI

/// Find on Page's words, its two switches and what the page last answered
/// (`Browser.seeking`): the find bar watches it, and nothing else has to.
@MainActor
final class FindState: ObservableObject {
    @Published var needle = ""
    @Published var matchCase = false
    @Published var wholeWords = false
    @Published var missed = false
    @Published var focus = 0
    @Published var result: PageFind.Result?
}

/// Looking for a word on the page. A pill in the top corner, the same white and
/// hairline as everything else that floats, and gone the moment it isn't wanted.
struct FindBar: View {
    @ObservedObject var browser: Browser
    var availableWidth: CGFloat? = nil
    var onPillFrame: ((CGRect) -> Void)? = nil
    /// The words and the page's answer, which `browser` doesn't announce.
    @ObservedObject private var seeking: FindState

    init(browser: Browser) {
        self.browser = browser
        seeking = browser.seeking
    }

    @FocusState private var focused: Bool
    /// The button under the pointer, by its symbol.

    private var narrow: Bool { availableWidth.map { $0 < 330 } ?? false }
    private var fieldWidth: CGFloat {
        guard let availableWidth else { return 140 }
        return max(40, min(140, availableWidth - (narrow ? 80 : 270)))
    }

    var body: some View {
        HStack(spacing: 6) {
            if !narrow {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .padding(.trailing, 2)
                    .accessibilityHidden(true)
            }
            ZStack(alignment: .leading) {
                if browser.needle.isEmpty {
                    Text("Find on page")
                        .foregroundStyle(Palette.muted)
                }
                TextField("", text: $browser.needle)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Palette.ink)
                    .accessibilityLabel("Find on page")
                    .accessibilityHint("Type text to search this page. Press Return to find the next match.")
                    .focused($focused)
                    .onSubmit { browser.look(forward: true) }
            }
            .font(.system(size: 13))
            .frame(width: fieldWidth)

            // "3 of 17", as the page counted it.
            if let status = browser.findStatus {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(browser.missed ? Palette.danger : Palette.muted)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel(status)
                    .accessibilityIdentifier("Find result status")
            }

            if !narrow {
                Rectangle().fill(Palette.rule).frame(width: 1, height: 18).padding(.horizontal, 2)
            }

            // A pane too narrow for them keeps Return and ⇧Return instead.
            if !narrow {
                step("chevron.up", label: "Previous match", help: "Previous Match", shortcut: "edit.findPrevious") {
                    browser.look(forward: false)
                }
                step("chevron.down", label: "Next match", help: "Next Match", shortcut: "edit.findNext") {
                    browser.look(forward: true)
                }
            }

            Menu {
                Toggle("Match case", isOn: $browser.matchCase)
                    .help("Match uppercase and lowercase letters exactly.")
                Toggle("Whole words", isOn: $browser.wholeWords)
                    .disabled(browser.findResult?.nativeFallback == true && !browser.wholeWords)
                    .help("Match complete words. This option is unavailable for PDF pages.")
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(browser.matchCase || browser.wholeWords ? Palette.ink : Palette.muted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Search options")
            .accessibilityHint("Choose whether to match case or whole words.")
            .help("Search options")

            step("xmark", label: "Close Find on Page", help: "Close the find field and clear its selection.") {
                browser.closeFind()
            }
        }
        .padding(.leading, narrow ? 10 : 14)
        .padding(.trailing, 6)
        .frame(height: 40)
        .elevated(.float, in: Capsule())
        .overlay {
            if browser.missed { Capsule().strokeBorder(Palette.dangerRing, lineWidth: 1) }
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("find")) }) {
            onPillFrame?($0)
        }
        .padding(.top, 12)
        .padding(.trailing, 12)
        .frame(maxWidth: availableWidth == nil ? nil : .infinity,
               maxHeight: availableWidth == nil ? nil : .infinity, alignment: .topTrailing)
        .coordinateSpace(name: "find")
        .animation(Motion.quick, value: browser.missed)
        .onAppear(perform: focus)
        .onChange(of: browser.findFocus) { _, _ in focus() }
    }

    /// Into the field, and once more a moment later if it didn't take: as
    /// the bar comes in, the field may not be in the window yet, and with
    /// the Mac's keyboard navigation on, the keyboard went to the first
    /// button instead — the back button — until ⌘F was pressed again (#172).
    private func focus() {
        focused = true
        DispatchQueue.main.async {
            if !focused { focused = true }
        }
    }

    private func step(
        _ icon: String,
        label: String,
        help: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        IconButton(icon, label: label, size: 28, hit: 28, round: true, tint: Palette.ink, wash: Palette.fill, tip: "", action: action)
            .accessibilityHint(help)
            .shortcutHelp(help, shortcut)
    }
}
