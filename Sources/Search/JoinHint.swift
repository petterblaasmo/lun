import SwiftUI

/// Over a tab in the column while another is held lying across it (see
/// Carried.across, TabJoin): the split letting go would make, said on the
/// row itself. The row wears the ring a picked tab wears, on the grey a
/// pressed control has, with the mark of two pages side by side at its end;
/// the tab carried goes faint over it (Carried), so both are read at once.
/// A split's item wears it whole: the carried tab would join it. A tile of
/// the icon column has no room for the mark beside its own.
struct JoinHint: View {
    let browser: Browser
    let tab: Tab
    var marked = true
    @ObservedObject private var join = TabJoin.shared

    private var shown: Bool {
        guard let shown = join.shown, shown.browserID == ObjectIdentifier(browser) else { return false }
        return shown.targetID == tab.id || browser.split(for: tab)?.contains(shown.targetID) == true
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ZStack(alignment: .trailing) {
            if shown {
                shape.fill(Palette.fill)
                shape.strokeBorder(Palette.ring, lineWidth: 1)
                if marked {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 24, height: 20)
                        .background(Palette.ground, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .padding(.trailing, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.quick, value: shown)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
