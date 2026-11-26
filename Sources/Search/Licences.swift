import AppKit
import SwiftUI

// Settings › About › Licences: the licences of the code in the app, read from
// the two files build.sh puts beside it. They have to come with every copy.

@MainActor
enum LicencesWindow {
    private static var window: NSWindow?

    /// Shown, or brought forward if it is already up. Never in a test run:
    /// a probe stays off every screen.
    static func show() {
        guard !Store.testing else { return }
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Licences"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 420, height: 300)
        window.contentView = NSHostingView(rootView: LicencesView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

struct LicencesView: View {
    /// The app's own licence, then everyone else's.
    static let texts: [String] = ["LICENSE", "THIRD_PARTY_NOTICES.md"].compactMap { name in
        Bundle.main.url(forResource: name, withExtension: nil).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(Array(LicencesView.texts.enumerated()), id: \.offset) { _, text in
                    Text(verbatim: text)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if LicencesView.texts.isEmpty {
                    Text("The licences are missing from this copy of Lun.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(24)
        }
        .background(Palette.ground)
    }
}
