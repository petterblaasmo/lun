import SwiftUI

// "Update ready" in the window, not only in the Search menu: while a newer
// build is in place and runs at the next launch (Updater.Stage.ready), a
// quiet card at the foot of the column, just above its doors, with Restart;
// with the tabs across the top, a small pill at the far end of the strip.
// Installing on its own switched off, the same card says "Update available"
// with Install. Nothing while the feed is read or the build fetched, and
// nothing for a disk image offered instead: that stays in the menu.
//
// On by default, unlike Search's other additions, because it is only ever
// there when an update really is (Settings › About › Show when an update is
// ready). Its × or Hide puts it away until a newer build is ready: the build
// put away is kept in the settings. Chrome only: never over a page, a sheet
// or anything private, and it never takes the keys.
//
// The quiet card alone was easy to miss. So a newer build first comes as a
// small bubble in its place (UpdateBubble): raised, with the version, a
// filled Restart and ×, once a build. × puts the bubble away and the quiet
// card stays. With no column of words to hold it (tabs across the top, the
// column hidden or in icons), the bubble sits in the page's bottom corner on
// the column's side instead (UpdatePopup).

enum UpdateNotice {
    static let key = "update.notice"
    static let hiddenKey = "update.notice.hidden"

    enum Kind: Equatable {
        /// Swapped in: Restart.
        case ready
        /// Found, waiting for Install (installing on its own is off).
        case waiting
    }

    /// What there is to show for a stage, if anything.
    static func shown(_ stage: Updater.Stage, on: Bool, hidden: Int) -> (kind: Kind, build: Int)? {
        guard on else { return nil }
        switch stage {
        case .ready(let release) where release.build != hidden: return (.ready, release.build)
        case .waiting(let release) where release.build != hidden: return (.waiting, release.build)
        default: return nil
        }
    }

    @MainActor
    static func shown(_ updater: Updater, _ prefs: Preferences) -> (kind: Kind, build: Int)? {
        shown(updater.stage, on: prefs.showsUpdateReady, hidden: prefs.updateHiddenBuild)
    }

    /// The popup over the window: what the card would show, with its
    /// release, while its build hasn't been answered.
    static func popup(_ stage: Updater.Stage, on: Bool, hidden: Int, answered: Int) -> (kind: Kind, release: Updater.Release)? {
        guard let shown = shown(stage, on: on, hidden: hidden), shown.build != answered else { return nil }
        switch stage {
        case .ready(let release), .waiting(let release): return (shown.kind, release)
        default: return nil
        }
    }

    @MainActor
    static func popup(_ updater: Updater, _ prefs: Preferences) -> (kind: Kind, release: Updater.Release)? {
        popup(updater.stage, on: prefs.showsUpdateReady, hidden: prefs.updateHiddenBuild, answered: updater.poppedBuild)
    }

    static func popupTitle(_ kind: Kind, version: String) -> String {
        kind == .ready ? "Lun \(version) is ready" : "Lun \(version) is out"
    }

    static func title(_ kind: Kind) -> String { kind == .ready ? "Update ready" : "Update available" }
    static func button(_ kind: Kind) -> String { kind == .ready ? "Restart" : "Install" }

    @MainActor
    static func act(_ kind: Kind) {
        switch kind {
        case .ready: Updater.shared.relaunch()
        case .waiting: Updater.shared.install()
        }
    }
}

/// The card at the foot of the column: drawn as the player's row is, a
/// hairline round the column's own ground, so it sits on the glass or the
/// solid ground alike and never reads as one more tab.
struct UpdateNoticeRow: View {
    @Environment(\.greys) private var greys
    @ObservedObject var prefs: Preferences
    @ObservedObject private var updater = Updater.shared

    @State private var hovering = false

    var body: some View {
        if let fresh = UpdateNotice.popup(updater, prefs) {
            UpdateBubble(kind: fresh.kind, release: fresh.release, row: prefs.sideRow, title: prefs.sideTitle)
                .transition(.card(from: .bottom))
        } else if let shown = UpdateNotice.shown(updater, prefs) {
            HStack(spacing: 8) {
                // The icon goes first in a narrow column, as on the agent's
                // card: the words are what must be read whole.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                        title(shown.kind)
                    }
                    title(shown.kind)
                    // Narrowest of all: the button says the rest.
                    title("Update")
                }
                Spacer(minLength: 0)
                if hovering {
                    UpdateNoticeCross { prefs.updateHiddenBuild = shown.build }
                        .transition(.opacity)
                }
                CardButton(title: UpdateNotice.button(shown.kind)) { UpdateNotice.act(shown.kind) }
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(height: prefs.sideRow)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? greys.hover : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .hovers($hovering)
            .contextMenu {
                Button(UpdateNotice.button(shown.kind)) { UpdateNotice.act(shown.kind) }
                Button("Hide") { prefs.updateHiddenBuild = shown.build }
            }
            .help(shown.kind == .ready
                  ? "A new version of Lun is ready. Restart to use it, or it starts the next time you open Lun."
                  : "A new version of Lun is out. Install fetches it; it starts at the next launch.")
            .animation(Motion.quick, value: hovering)
        }
    }

    private func title(_ kind: UpdateNotice.Kind) -> some View { title(UpdateNotice.title(kind)) }

    private func title(_ words: String) -> some View {
        Text(words)
            .font(.system(size: prefs.sideTitle))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(hovering ? Palette.ink : Palette.muted)
    }
}

/// With the tabs across the top: a small pill at the far end of the strip,
/// the click Restart (or Install), Hide on a right-click.
struct UpdateNoticePill: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject private var updater = Updater.shared

    @State private var hovering = false

    var body: some View {
        if let shown = UpdateNotice.shown(updater, prefs) {
            Button { UpdateNotice.act(shown.kind) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10, weight: .medium))
                    Text(UpdateNotice.title(shown.kind))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(hovering ? Palette.ink : Palette.soft)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Palette.ground.opacity(hovering ? 1 : 0.6), in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                .contentShape(Capsule())
                .fixedSize()
            }
            .buttonStyle(.plain)
            .focusable(false)
            .hovers($hovering)
            .contextMenu {
                Button(UpdateNotice.button(shown.kind)) { UpdateNotice.act(shown.kind) }
                Button("Hide") { prefs.updateHiddenBuild = shown.build }
            }
            .help(shown.kind == .ready
                  ? "A new version of Lun is ready. Click to restart and use it."
                  : "A new version of Lun is out. Click to install it.")
            .animation(Motion.quick, value: hovering)
        }
    }
}

/// A newer build, the first time: one raised line with the version, a
/// filled Restart (or Install) and ×. In the column in place of the quiet
/// card, or in the page's bottom corner where there is no column of words.
struct UpdateBubble: View {
    let kind: UpdateNotice.Kind
    let release: Updater.Release
    let row: CGFloat
    let title: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink)
                    words(UpdateNotice.popupTitle(kind, version: release.version))
                }
                words(UpdateNotice.popupTitle(kind, version: release.version))
                words(UpdateNotice.title(kind))
                // Narrowest of all: the button says the rest.
                words("Update")
            }
            Spacer(minLength: 0)
            CardButton(title: UpdateNotice.button(kind), filled: true) {
                Updater.shared.answerPopup(release.build)
                UpdateNotice.act(kind)
            }
            UpdateNoticeCross(help: "Hide; Update ready stays in the column") {
                Updater.shared.answerPopup(release.build)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevated(.float, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .contextMenu {
            Button(UpdateNotice.button(kind)) {
                Updater.shared.answerPopup(release.build)
                UpdateNotice.act(kind)
            }
            Button("Hide") { Updater.shared.answerPopup(release.build) }
        }
        .help(kind == .ready
              ? "A new version of Lun is downloaded. Restart to use it, or it starts the next time you open Lun."
              : "A new version of Lun is out. Install fetches it; it starts at the next launch.")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(UpdateNotice.popupTitle(kind, version: release.version))
    }

    private func words(_ text: String) -> some View {
        Text(text)
            .font(.system(size: title, weight: .medium))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// The bubble where no column of words holds it: tabs across the top, the
/// column hidden, or the column of icons. In the page's bottom corner on the
/// column's side, clear of the page's middle and its top.
struct UpdatePopup: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject private var updater = Updater.shared

    static let margin: CGFloat = 12

    var body: some View {
        let fresh = browser.welcoming || inColumn ? nil : UpdateNotice.popup(updater, prefs)
        ZStack(alignment: corner) {
            if let fresh {
                UpdateBubble(kind: fresh.kind, release: fresh.release, row: 30, title: 12)
                    .fixedSize()
                    .padding(Self.margin)
                    .transition(.card(from: right ? .bottomTrailing : .bottomLeading))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner)
        .padding(.leading, prefs.sidebar && !right && !browser.folded ? prefs.columnWidth : 0)
        .padding(.trailing, prefs.sidebar && right && !browser.folded ? prefs.columnWidth : 0)
        .animation(Motion.settle, value: fresh?.release.build)
    }

    /// The column of words, on screen: the bubble is in it (UpdateNoticeRow).
    private var inColumn: Bool { prefs.sidebar && !prefs.iconColumn && !browser.folded }
    private var right: Bool { prefs.sidebar && prefs.sidePosition == .right }
    private var corner: Alignment { right ? .bottomTrailing : .bottomLeading }
}

/// Restart or Install, and the coding agent's Stop on its card
/// (AgentBanner): a small capsule on the ground, under a hairline. `spot`
/// is drawn behind the label, for a control that has to know where it is.
struct CardButton<Spot: View>: View {
    let title: String
    /// In ink, for the one thing to press (UpdateBubble's Restart).
    var filled = false
    let act: () -> Void
    let spot: Spot
    @State private var hovering = false

    init(title: String, filled: Bool = false, act: @escaping () -> Void, @ViewBuilder spot: () -> Spot) {
        self.title = title
        self.filled = filled
        self.act = act
        self.spot = spot()
    }

    var body: some View {
        Button(action: act) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(filled ? Palette.ground : hovering ? Palette.ink : Palette.soft)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(filled ? Palette.ink.opacity(hovering ? 0.86 : 1) : Palette.ground, in: Capsule())
                .overlay(Capsule().strokeBorder(filled ? .clear : Palette.hairline, lineWidth: 1))
                .contentShape(Capsule())
                .background(spot)
                .fixedSize()
        }
        // Gives under the press, as Quick does: Stop and Restart did
        // their thing with nothing to say they had been pressed.
        .buttonStyle(Gives(to: 0.95))
        .focusable(false)
        .hovers($hovering)
    }
}

extension CardButton where Spot == EmptyView {
    init(title: String, filled: Bool = false, act: @escaping () -> Void) {
        self.init(title: title, filled: filled, act: act) { EmptyView() }
    }
}

/// Put away, until a newer build is ready: the player row's cross.
private struct UpdateNoticeCross: View {
    var help = "Hide until the next version"
    let act: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .frame(width: 15, height: 15)
                .background(Palette.ink.opacity(hovering ? 0.07 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .hovers($hovering)
        .help(help)
    }
}
