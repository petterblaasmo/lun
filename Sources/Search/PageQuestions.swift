import SwiftUI

/// The same site permission question in a browser or a small popup window.
struct CaptureQuestion: View {
    @ObservedObject var browser: Browser
    let ask: Browser.CaptureAsk

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SiteMark(host: ask.host, size: 16)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                Text(ask.wants == "location" ? "\(ask.host) wants your location"
                     : ask.wants == "notifications" ? "\(ask.host) wants to send you notifications"
                     // Safari's question, in fewer words: a yes lets the framed
                     // site know you were on this one.
                     : ask.wants == "cookies" ? "\(ask.host) wants to use its cookies and website data on \(ask.under), which also lets it see you were there"
                     : "\(ask.host) wants to use your \(ask.wants)")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { Spacer(minLength: 0); buttons }
                VStack(alignment: .trailing, spacing: 6) { buttons }.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(14)
        .frame(width: ask.once && ask.keeps ? 360 : 280)
        .elevated(.float, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var buttons: some View {
        Pill("Don't allow", large: true) { browser.denyCapture() }
        if ask.once, ask.keeps {
            Pill("Always allow", large: true) { browser.allowCapture() }
        }
        Pill(ask.once ? "Allow once" : "Allow", filled: true, large: true) { ask.once ? browser.allowCaptureOnce() : browser.allowCapture() }
    }
}

/// A site by its icon, or a globe until there is one.
struct SiteMark: View {
    let host: String
    var size: CGFloat = 16

    var body: some View {
        Mark(icon: Favicons.shared.cached(host) ?? Favicons.shared.cached("www." + host), letter: "", size: size, globe: true)
    }
}

/// A page asking to share the screen (Browser.askedToShareScreen): nothing
/// is shared until a screen or a window is picked in macOS's own picker,
/// which only these two answers open.
struct ScreenQuestion: View {
    @ObservedObject var browser: Browser
    let ask: Browser.CaptureAsk

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 2)
                Text(ask.sound ? "\(ask.host) wants to share your screen and your Mac's sound"
                               : "\(ask.host) wants to share your screen")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The buttons every other question has: these three were words
            // with nothing under the pointer or the press.
            HStack(spacing: 8) {
                Pill("Don't Allow", large: true) { browser.denyShare() }
                Spacer(minLength: 8)
                // A window gives away less than a whole screen: it is the
                // one drawn as the answer.
                Pill("Share a Screen", large: true) { browser.shareScreen() }
                Pill("Share a Window", filled: true, large: true) { browser.shareWindow() }
            }
        }
        .frame(maxWidth: 400, alignment: .leading)
        .padding(18)
        .elevated(.float, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }
}

/// A password offer remains readable in the popup that submitted the form.
struct PasswordOffer: View {
    @ObservedObject var browser: Browser
    let offer: Browser.Offer
    /// The pointer is over Never here.
    @State private var never = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SiteMark(host: offer.login.host, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(offer.changed ? "Update your password?" : "Save your password?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("For \(offer.login.host), in your Mac’s keychain")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 0) {
                if !offer.login.user.isEmpty {
                    line("Username", offer.login.user)
                    Rectangle().fill(Palette.rule).frame(height: 1).padding(.horizontal, 12)
                }
                line("Password", String(repeating: "•", count: max(8, min(16, offer.login.password.count))))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Password, hidden")
            }
            .background(Palette.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack(spacing: 6) {
                if !offer.changed {
                    Button("Never here") { browser.neverOffer() }
                        .buttonStyle(Gives())
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(never ? Palette.ink : Palette.muted)
                        .padding(.horizontal, 12)
                        .hovers($never)
                }
                Spacer(minLength: 0)
                Pill("Not now", large: true) { browser.dropOffer() }
                Pill(offer.changed ? "Update" : "Save", filled: true, large: true) { browser.keepOffer() }
            }
        }
        .padding(18)
        .frame(width: 340)
        .elevated(.float, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func line(_ name: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(name).foregroundStyle(Palette.muted).frame(width: 76, alignment: .leading)
            Text(value).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
