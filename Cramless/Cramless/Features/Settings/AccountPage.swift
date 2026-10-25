import AuthenticationServices
import SwiftUI

/// Settings ▸ Account: your name, signing in (Apple or an emailed code), sync, signing out and deleting the account.
/// In a build without accounts (no Supabase project) it says so plainly and keeps everything on this iPhone.
///
/// Harness: `CRAMLESS_ACCOUNT=apple` shows a signed-in account (AccountService). `CRAMLESS_SYNC=ok|error|syncing`
/// shows that sync state (the demo build has no server to sync with).
struct AccountPage: View {
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @State private var confirmingSignOut = false
    @State private var confirmingDelete = false
    @State private var working = false
    @State private var errorText: String?

    private var account: AccountService { app.account }
    private var hasAccounts: Bool { app.config.aiMode != .local }

    var body: some View {
        SettingsScroll(title: "Account") {
            nameGroup
            if !hasAccounts {
                CLSectionHeader(title: "Account")
                SettingsInfoCard(icon: "iphone", tint: .sky, title: "Accounts aren't set up in this build",
                                 text: "Everything you study stays on this iPhone. With an account, a copy is kept in it, so a new iPhone picks up where you left off.")
                    .clCard(padding: 0)
            } else if account.isSignedIn {
                signedIn
            } else {
                CLSectionHeader(title: "Sign in")
                VStack(alignment: .leading, spacing: 14) {
                    Text("Sign in to keep a copy of your courses, cards and progress in your account. Sync turns on when you do.")
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    SignInPanel()
                }
                .clCard()
            }
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.circle.fill")
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.roseInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            if hasAccounts && (account.isSignedIn || account.isAnonymous) {
                SettingsGroup(title: "Delete account",
                              footer: "Deletes your account on our server, then everything on this iPhone.") {
                    SettingsActionRow(icon: "trash", title: "Delete account", destructive: true, busy: working) {
                        confirmingDelete = true
                    }
                }
            }
        }
        .onAppear { name = app.settings.firstName }
        .onDisappear(perform: saveName)
        .confirmationDialog("Sign out?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out") {
                Task {
                    await app.signOut()
                    CLHaptics.commit()
                    app.router.toast("Signed out. Everything stays on this iPhone.", systemImage: "rectangle.portrait.and.arrow.right", tone: .neutral)
                }
            }
        } message: {
            Text("Everything you've studied stays on this iPhone. Sync stops until you sign in again.")
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account and data", role: .destructive, action: deleteAccount)
        } message: {
            Text(Self.deleteMessage)
        }
    }

    static let deleteMessage = """
    On our server: your account and sign-in, every course, card, review, exam and lecture synced to it, the page \
    photos you sent, and your Squad seat. Then everything on this iPhone, and onboarding starts again. This can't \
    be undone. A subscription is billed by Apple: cancel it in Subscription, or it keeps renewing.
    """

    // MARK: Parts

    private var nameGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            CLSectionHeader(title: "Your name")
            HStack(spacing: 12) {
                InitialsAvatar(name: name, size: 44)
                TextField("First name", text: $name)
                    .clFont(.body)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .onSubmit(saveName)
                    .padding(.horizontal, 12)
                    .frame(minHeight: CLMetrics.minHitTarget)
                    .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: CLRadius.field, style: .continuous))
            }
            .clCard(padding: 14)
            Text("Cap uses it to say hi. Your Squad sees it too.")
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink2)
                .padding(.horizontal, 6)
                .padding(.top, 10)
        }
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 0) {
            CLSectionHeader(title: "Signed in")
            CLList {
                HStack(spacing: 12) {
                    CLIconBadge(systemImage: account.email == nil ? "apple.logo" : "envelope.fill", tint: .sky)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.email ?? "Signed in with Apple").clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text("Sync is on").clFont(.footnote).foregroundStyle(CLColor.mintInk)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: CLMetrics.rowMinHeight)
                .accessibilityElement(children: .combine)
                SyncStatusRow()
                SettingsActionRow(icon: "rectangle.portrait.and.arrow.right", tint: .capy, title: "Sign out",
                                  subtitle: "Everything stays on this iPhone") {
                    confirmingSignOut = true
                }
            }
        }
    }

    // MARK: Actions

    private func saveName() {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard clean != app.settings.firstName else { return }
        app.settings.firstName = clean
        Task { await app.account.pushProfileIfNeeded() }
    }

    private func deleteAccount() {
        working = true
        errorText = nil
        Task {
            do {
                try await app.deleteAccount()
                CLHaptics.commit()
            } catch {
                errorText = RelayError.message(for: error)
            }
            working = false
        }
    }
}

/// "Synced 2 minutes ago", "Syncing…", or what went wrong, with Sync now.
struct SyncStatusRow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let state = status
        HStack(spacing: 12) {
            CLIconBadge(systemImage: state.icon, tint: state.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title).clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                Text(state.detail)
                    .clFont(.footnote)
                    .foregroundStyle(state.isError ? CLColor.roseInk : CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if state.isSyncing {
                ProgressView()
            } else {
                Button("Sync now") {
                    CLHaptics.tap()
                    Task { await app.syncNow() }
                }
                .buttonStyle(.cl(.soft, size: .small, fullWidth: false))
                .disabled(!app.sync.isEnabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: CLMetrics.rowMinHeight)
    }

    private struct State {
        var title: String
        var detail: String
        var icon: String
        var tint: CourseColor
        var isError = false
        var isSyncing = false
    }

    private var status: State {
        #if DEBUG
        if let hook = TestHarness.value("CRAMLESS_SYNC") {
            switch hook {
            case "syncing": return State(title: "Syncing", detail: "Sending your latest changes", icon: "arrow.triangle.2.circlepath", tint: .sky, isSyncing: true)
            case "error": return State(title: "Couldn't sync", detail: RelayError.offline.friendlyMessage ?? "", icon: "exclamationmark.icloud", tint: .rose, isError: true)
            default: return State(title: "Up to date", detail: "Synced 2 minutes ago", icon: "checkmark.icloud", tint: .mint)
            }
        }
        #endif
        let sync = app.sync
        if sync.isSyncing {
            return State(title: "Syncing", detail: "Sending your latest changes", icon: "arrow.triangle.2.circlepath", tint: .sky, isSyncing: true)
        }
        if let error = sync.lastError {
            return State(title: "Couldn't sync", detail: error.friendlyMessage ?? "It will try again soon.",
                         icon: "exclamationmark.icloud", tint: .rose, isError: true)
        }
        if let last = sync.lastSyncedAt {
            return State(title: "Up to date", detail: "Synced " + last.formatted(.relative(presentation: .named)),
                         icon: "checkmark.icloud", tint: .mint)
        }
        if !sync.isEnabled {
            return State(title: "Sync", detail: "Starts when this build is connected to Capling's server.", icon: "icloud", tint: .sky)
        }
        return State(title: "Sync", detail: "Not synced yet on this iPhone", icon: "icloud", tint: .sky)
    }
}

/// Sign in with Apple, or with a 6-digit code sent by email. Used by Account and by joining a Squad.
struct SignInPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme
    @State private var nonce = AppleSignInNonce.make()
    @State private var usingEmail = false
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var errorText: String?
    @FocusState private var focus: Field?

    private enum Field { case email, code }

    var body: some View {
        if app.config.aiMode == .local {
            Text("Accounts aren't set up in this build. Everything you study stays on this iPhone.")
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    let fresh = AppleSignInNonce.make()
                    nonce = fresh
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = fresh.hashed
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(Capsule())
                .disabled(busy)
                .accessibilityHint("Signs in with your Apple Account. Capling gets a private address if you choose to hide yours.")

                if usingEmail { emailForm } else {
                    Button("Use an email code instead") {
                        withAnimation(CLMotion.settle) { usingEmail = true }
                        focus = .email
                    }
                    .buttonStyle(.cl(.ghost, size: .small))
                }
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.circle.fill")
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.roseInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var emailForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Email address", text: $email)
                .clFont(.body)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .submitLabel(.send)
                .onSubmit(sendCode)
                .disabled(codeSent)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: CLRadius.field, style: .continuous))
            if codeSent {
                Text("We sent a 6-digit code to \(email). It works for 10 minutes.")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("6-digit code", text: $code)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .code)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: CLRadius.field, style: .continuous))
                    .accessibilityLabel("Code from the email")
                HStack {
                    Button(action: verify) { busyLabel("Sign in") }
                        .buttonStyle(.cl(.primary, size: .medium))
                        .disabled(busy || code.filter(\.isNumber).count < 6)
                }
                Button("Use another address or send a new code") {
                    codeSent = false
                    code = ""
                    focus = .email
                }
                .buttonStyle(.cl(.ghost, size: .small))
            } else {
                Button(action: sendCode) { busyLabel("Email me a code") }
                    .buttonStyle(.cl(.dark, size: .medium))
                    .disabled(busy || !email.contains("@"))
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func busyLabel(_ title: String) -> some View {
        ZStack {
            Text(title).opacity(busy ? 0 : 1)
            if busy { ProgressView() }
        }
    }

    // MARK: Actions

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
                errorText = "Apple didn't send a sign-in token. Try again."
                return
            }
            let raw = nonce.raw
            run {
                try await app.signInWithApple(idToken: token, rawNonce: raw, fullName: credential.fullName)
                signedIn()
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorText = "Sign in with Apple didn't finish. Try again, or use an email code."
        }
    }

    private func sendCode() {
        guard !busy else { return }
        run {
            try await app.sendEmailCode(email)
            withAnimation(CLMotion.settle) { codeSent = true }
            focus = .code
        }
    }

    private func verify() {
        run {
            try await app.verifyEmailCode(email: email, code: code)
            signedIn()
        }
    }

    private func signedIn() {
        CLHaptics.success()
        app.router.toast("Signed in. Sync is on.", systemImage: "checkmark.icloud")
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        busy = true
        errorText = nil
        Task {
            do { try await work() } catch { errorText = RelayError.message(for: error) }
            busy = false
        }
    }
}
