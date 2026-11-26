import SwiftUI

/// Every password kept, by site. The same white-and-hairline panel as the
/// rest, and the same rule: a password is never shown until you have proved
/// you are you, and never for longer than it takes to read it.
struct PasswordsPanel: View {
    @ObservedObject var browser: Browser

    @FocusState private var hunting: Bool
    /// The account on show.
    @State private var picked: Kept.ID?
    @State private var adding = false
    @State private var width: CGFloat = 900

    private var accounts: [Kept] { browser.shownSites.flatMap(\.logins) }

    var body: some View {
        let accounts = self.accounts
        let shown = accounts.first { $0.id == picked } ?? accounts.first
        Plate("Passwords", width: 620, tools: AnyView(Pill(adding ? "Cancel" : "Add…") { adding.toggle() }), close: { browser.managing = false }) {
            VStack(alignment: .leading, spacing: 14) {
                if adding {
                    Card { AddForm(browser: browser) { adding = false } }
                        .transition(.opacity)
                }
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Hunt(text: $browser.hunting, prompt: accounts.count == 1 ? "Search 1 account" : "Search \(browser.saved.count) accounts", focus: $hunting)
                        if accounts.isEmpty {
                            Card {
                                Nothing(browser.saved.isEmpty
                                        ? "Nothing kept yet. Sign in somewhere and say yes, or bring yours in below."
                                        : "Nothing matches.")
                            }
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 2) {
                                    ForEach(accounts) { login in
                                        AccountRow(login: login, on: login.id == shown?.id) { picked = login.id }
                                    }
                                }
                                .padding(.bottom, 2)
                            }
                            .listHeight(400)
                        }
                    }
                    .frame(width: min(280, max(180, width * 0.36)))
                    if let shown {
                        Account(login: shown, copy: { browser.copy(shown) }, forget: { browser.forget(shown) })
                            .id(shown.id)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    } else {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        } foot: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Bring in from")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                    // Which browser, which profile and what of it: the sheet.
                    Pill("Bring in…") { browser.lead(to: InternalPage(.importing)) }
                    Pill("File…") { browser.importFile() }
                    Spacer(minLength: 0)
                    // What the list shows, all of it or what the search
                    // leaves: never more than can be seen (Browser.forgetShown).
                    let shown = browser.shownSites.reduce(0) { $0 + $1.logins.count }
                    if shown > 0 {
                        Pill(browser.hunting.trimmingCharacters(in: .whitespaces).isEmpty ? "Remove All…" : "Remove \(shown)…") {
                            browser.forgetShown()
                        }
                        .disabled(browser.forgetting)
                    }
                    Text(browser.saved.count == 1 ? "1 password" : "\(browser.saved.count) passwords")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }
                Text("macOS asks once for that browser's keychain key. Nothing is changed there; everything lands in your own keychain, under Lun.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(Motion.settle, value: adding)
        .onAppear { hunting = true }
    }

    /// One account in the list: its site, and whose it is.
    private struct AccountRow: View {
        let login: Kept
        let on: Bool
        let act: () -> Void

        @State private var hovering = false

        var body: some View {
            Button(action: act) {
                HStack(spacing: 10) {
                    SiteMark(host: login.host, size: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(login.host)
                            .font(.system(size: 13, weight: on ? .medium : .regular))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text(login.user.isEmpty ? "No username" : login.user)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(on ? Palette.fill : hovering ? Palette.hover : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }

    /// One account: the name, the password as dots, and the things to do with
    /// it. Show asks the Mac who you are first.
    private struct Account: View {
        let login: Kept
        let copy: () -> Void
        let forget: () -> Void

        @State private var shown = false
        /// The secret, from the moment it is shown to the moment it is hidden
        /// again. Read on that click rather than with the list: see `Kept`.
        @State private var secret: String?
        @State private var hide: DispatchWorkItem?

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    SiteMark(host: login.host, size: 32)
                    Text(login.host)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Card {
                    line("Username") {
                        Text(login.user.isEmpty ? "No username" : login.user)
                            .foregroundStyle(login.user.isEmpty ? Palette.muted : Palette.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            // Selectable, as the password is: a username is
                            // not a secret, and it is the half of a sign-in you are
                            // most often asked to type somewhere else.
                            .textSelection(.enabled)
                    } control: { EmptyView() }
                    Rule()
                    line("Password") {
                        // Ten dots whatever it is: the row does not know the length
                        // until the secret is read, and a count that changed with it
                        // told anyone looking over a shoulder how long it was.
                        Text(shown ? (secret ?? "") : String(repeating: "•", count: 10))
                            .font(.system(size: 13, design: shown ? .monospaced : .default))
                            .foregroundStyle(shown ? Palette.ink : Palette.muted)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    } control: {
                        Pill(shown ? "Hide" : "Show") { shown ? conceal() : reveal() }
                        Pill("Copy", action: copy)
                    }
                }
                HStack {
                    Spacer()
                    Pill("Remove…", tint: .red.opacity(0.8), action: forget)
                }
            }
            .onDisappear { conceal() }
        }

        private func line<Value: View, Control: View>(_ name: String, @ViewBuilder value: () -> Value, @ViewBuilder control: () -> Control) -> some View {
            HStack(spacing: 8) {
                Text(name).foregroundStyle(Palette.muted).frame(width: 90, alignment: .leading)
                value()
                Spacer(minLength: 8)
                control()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 16)
            .frame(height: 44)
        }

        private func reveal() {
            Vault.prove("show the password for \(login.host)") { ok in
                // Read after the Mac has said who this is, not before: the
                // secret is asked for here and let go with the row.
                guard ok, let password = Vault.secret(of: login) else { return }
                secret = password
                shown = true
                // Long enough to read or type across, and not a minute more.
                let work = DispatchWorkItem { conceal() }
                hide?.cancel()
                hide = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
            }
        }

        /// Hidden again, and the secret with it: this is the only place it is
        /// held, and only while it is on screen.
        private func conceal() {
            hide?.cancel()
            shown = false
            secret = nil
        }
    }

    /// Typing one in by hand. The site, the name, the password, and Save.
    private struct AddForm: View {
        @ObservedObject var browser: Browser
        let done: () -> Void

        @State private var site = ""
        @State private var user = ""
        @State private var password = ""
        @FocusState private var focus: Int?

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    field("Site", text: $site, tag: 0)
                    field("Username", text: $user, tag: 1)
                }
                HStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        if password.isEmpty {
                            Text("Password").foregroundStyle(Palette.muted)
                                .padding(.leading, 10)
                        }
                        SecureField("", text: $password)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(Palette.ink)
                            .focused($focus, equals: 2)
                            .onSubmit(keep)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                    }
                    .background(Palette.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Pill("Save", filled: true, action: keep)
                        .disabled(Vault.host(of: site).isEmpty || password.isEmpty)
                }
            }
            .padding(14)
            .onAppear { focus = 0 }
        }

        private func field(_ name: String, text: Binding<String>, tag: Int) -> some View {
            ZStack(alignment: .leading) {
                if text.wrappedValue.isEmpty {
                    Text(name).foregroundStyle(Palette.muted).padding(.leading, 10)
                }
                TextField("", text: text)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Palette.ink)
                    .focused($focus, equals: tag)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            .font(.system(size: 12.5))
            .background(Palette.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }

        private func keep() {
            let host = Vault.host(of: site)
            guard !host.isEmpty, !password.isEmpty else { return }
            browser.keep(host: host, user: user.trimmingCharacters(in: .whitespaces), password: password)
            done()
        }
    }
}
