import SwiftUI

/// Every password kept, by site. The same white-and-hairline panel as the
/// rest, and the same rule: a password is never shown until you have proved
/// you are you, and never for longer than it takes to read it.
struct PasswordsPanel: View {
    @ObservedObject var browser: Browser
    /// A picture's: made-up accounts where the keychain's list would be.
    private let made: [Kept]?
    /// Which passwords are worth a look, once that has been asked for and
    /// the Mac has said who is asking (see PasswordCheck). Nothing is known
    /// about any password before then.
    @StateObject private var check: PasswordCheck

    @FocusState private var hunting: Bool
    /// The account on show.
    @State private var picked: Kept.ID?
    @State private var adding = false
    @State private var width: CGFloat = 900
    /// Which accounts the list is asked to show. A warning's only while
    /// there is something found to show by: see `filter`.
    @State private var asked: PasswordFilter = .all

    init(browser: Browser, check: PasswordCheck? = nil, made: [Kept]? = nil, showing: PasswordFilter = .all) {
        self.browser = browser
        self.made = made
        _check = StateObject(wrappedValue: check ?? PasswordCheck())
        _asked = State(initialValue: showing)
    }

    /// The narrower choices have a column of their own from this width.
    static let sidesFrom: CGFloat = 760
    private static let sidesWidth: CGFloat = 168
    private static let gap: CGFloat = 24

    var body: some View {
        let all = made ?? browser.saved
        // What the search leaves, then what the choice at the side leaves.
        let searched = made ?? browser.shownSites.flatMap(\.logins)
        let found = check.warnings
        let filter = found == nil ? .all : asked
        let accounts = filter.of(searched, found)
        let shown = accounts.first { $0.id == picked } ?? accounts.first
        let wide = width >= Self.sidesFrom
        Plate("Passwords", width: 620, tools: AnyView(Pill(adding ? "Cancel" : "Add…") { adding.toggle() }), close: { browser.managing = false }) {
            VStack(alignment: .leading, spacing: 14) {
                if adding {
                    Card { AddForm(browser: browser) { adding = false } }
                        .transition(.opacity)
                }
                HStack(alignment: .top, spacing: Self.gap) {
                    if wide {
                        sides(all: all, searched: searched, found: found, filter: filter)
                            .frame(width: Self.sidesWidth)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Hunt(text: $browser.hunting, prompt: searched.count == 1 ? "Search 1 account" : "Search \(all.count) accounts", focus: $hunting)
                        if !wide, !all.isEmpty { narrowed(all: all, searched: searched, found: found, filter: filter) }
                        if accounts.isEmpty {
                            Card {
                                Nothing(all.isEmpty
                                        ? "Nothing kept yet. Sign in somewhere and say yes, or bring yours in below."
                                        : searched.isEmpty ? "Nothing matches." : filter.nothing)
                            }
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 2) {
                                    ForEach(accounts) { login in
                                        AccountRow(login: login, on: login.id == shown?.id, warned: found?.says(of: login)) { picked = login.id }
                                    }
                                }
                                .padding(.bottom, 2)
                            }
                            .listHeight(400)
                        }
                    }
                    .frame(width: min(280, max(180, (wide ? width - Self.sidesWidth - Self.gap : width) * 0.36)))
                    if let shown {
                        Account(login: shown, reused: found?.others(of: shown) ?? [], guessable: found?.whyGuessable(shown) ?? [],
                                copy: { browser.copy(shown) }, forget: { browser.forget(shown) })
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
                    // It goes by the search alone, so with the list narrowed
                    // to a warning's there is no Remove All… at all.
                    if !searched.isEmpty, filter == .all {
                        Pill(browser.hunting.trimmingCharacters(in: .whitespaces).isEmpty ? "Remove All…" : "Remove \(searched.count)…") {
                            browser.forgetShown()
                        }
                        .disabled(browser.forgetting)
                    }
                    Text(all.count == 1 ? "1 password" : "\(all.count) passwords")
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
        // Every time the list is read again, also when it reads the same:
        // a password saved over an old one changes no row of it.
        .onReceive(browser.$saved.dropFirst()) { check.listed($0) }
        // What was found is the page's, for as long as it is open.
        .onDisappear { check.forget() }
    }

    /// The narrower choices, down the side: all of them, then what is worth
    /// a look, which is nothing until it has been asked for.
    private func sides(all: [Kept], searched: [Kept], found: PasswordWarnings?, filter: PasswordFilter) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SideChoice(title: PasswordFilter.all.title, count: searched.count, on: filter == .all) { asked = .all }
            Text("Worth a look")
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
                .padding(.leading, 10)
                .padding(.top, 16)
                .padding(.bottom, 4)
            if let found {
                ForEach([PasswordFilter.reused, .guessable], id: \.self) { one in
                    SideChoice(title: one.title, symbol: "exclamationmark.triangle", symbolTint: Palette.unsafe,
                               count: one.of(searched, found).count, on: filter == one) { asked = one }
                }
                note(found.unread == 0 ? PasswordWarnings.after : PasswordWarnings.after + " " + PasswordWarnings.unread(found.unread))
                    .padding(.top, 8)
            } else {
                note(PasswordWarnings.before)
                asking(all).padding(.leading, 10).padding(.top, 8)
            }
        }
    }

    /// The same choices over the list, where there is no room beside it.
    private func narrowed(all: [Kept], searched: [Kept], found: PasswordWarnings?, filter: PasswordFilter) -> some View {
        HStack(spacing: 8) {
            if let found {
                PopUp("Show", shows: filter.title, selection: $asked) {
                    Text(PasswordFilter.all.title).tag(PasswordFilter.all)
                    Divider()
                    ForEach([PasswordFilter.reused, .guessable], id: \.self) { one in
                        Text("\(one.title) (\(one.of(searched, found).count))").tag(one)
                    }
                }
                Spacer(minLength: 0)
            } else {
                Text("Reused or easy to guess?")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(PasswordWarnings.before)
                Spacer(minLength: 0)
                asking(all)
            }
        }
    }

    /// Asked for, never done on opening the page: the Mac asks who it is.
    private func asking(_ all: [Kept]) -> some View {
        Pill(check.checking ? "Checking…" : "Check…") { check.run(all) }
            .disabled(check.checking || all.isEmpty)
    }

    private func note(_ words: String) -> some View {
        Text(words)
            .font(.system(size: 12))
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
    }

    /// One account in the list: its site, and whose it is.
    private struct AccountRow: View {
        let login: Kept
        let on: Bool
        /// What a look found about its password, in words; nil for nothing.
        var warned: String?
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
                    if let warned {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.unsafe)
                            .help(warned)
                            .accessibilityLabel(warned)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(on ? Palette.fill : hovering ? Palette.hover : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .hovers($hovering)
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }

    /// One account: the name, the password as dots, and the things to do with
    /// it. Show asks the Mac who you are first.
    private struct Account: View {
        let login: Kept
        /// The other sites with this password, and why it is easy to guess:
        /// both empty until a look has been taken (see PasswordCheck).
        var reused: [String] = []
        var guessable: [Guessable] = []
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
                if !reused.isEmpty || !guessable.isEmpty {
                    Card {
                        if !reused.isEmpty {
                            warning(PasswordWarnings.reusedTitle(reused.count), PasswordWarnings.reusedDetail(reused))
                        }
                        if !reused.isEmpty, !guessable.isEmpty { Rule() }
                        if !guessable.isEmpty {
                            warning(PasswordFilter.guessable.title, guessable.map(\.says).joined(separator: " "))
                        }
                    }
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
                    Pill("Remove…", tint: Palette.danger, action: forget)
                }
            }
            .onDisappear { conceal() }
        }

        /// What a look found, over the account it found it about: said, and
        /// left to you. Changing a password is the site's to do.
        private func warning(_ title: String, _ detail: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.unsafe)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
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
