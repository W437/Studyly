import SwiftUI

/// Joining a friend's Squad with their code (typed, or from a `capling.app/squad/<code>` link). It needs an account,
/// and says why: the seat belongs to the account, so it follows the person to a new iPhone. On success a toast says
/// whose Squad it is and the plan refreshes.
///
/// Harness: `CRAMLESS_ROUTE=squadRedeem:CAP-7Q4K` (a code from a link), with `CRAMLESS_ACCOUNT=apple` to be signed in.
struct SquadRedeemView: View {
    let code: String?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var entered = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var joined = false
    @FocusState private var focused: Bool

    private var hasAccounts: Bool { app.config.aiMode != .local }
    private var normalized: String { Self.normalize(entered) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    CLIconBadge(systemImage: "person.3.fill", tint: .mint, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Join a Squad").clFont(.title2).foregroundStyle(CLColor.ink).accessibilityAddTraits(.isHeader)
                        Text("A friend's Squad gives you every Pro feature, on their plan.")
                            .clFont(.subheadline).foregroundStyle(CLColor.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    CLIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(code == nil ? "Their code" : "The code from your link")
                        .clFont(.footnoteEmphasis).foregroundStyle(CLColor.ink2)
                    TextField("CAP-7Q4K", text: $entered)
                        .font(.system(size: 30, weight: .heavy, design: .rounded).monospaced())
                        .foregroundStyle(CLColor.ink)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.join)
                        .onSubmit(join)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 64)
                        .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .accessibilityLabel("Squad code")
                }
                .clCard()

                if !hasAccounts {
                    SettingsInfoCard(icon: "iphone", title: "Accounts aren't set up in this build",
                                     text: "A Squad seat belongs to an account, so codes can't be used here.")
                        .clCard(padding: 0)
                } else if !app.account.isSignedIn {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sign in first").clFont(.headline).foregroundStyle(CLColor.ink)
                        Text("Your seat belongs to your account, so it follows you to a new iPhone, and your friend can see who joined.")
                            .clFont(.subheadline).foregroundStyle(CLColor.ink2).fixedSize(horizontal: false, vertical: true)
                        SignInPanel()
                    }
                    .clCard()
                }

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.circle.fill")
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.roseInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 22)
            .padding(.bottom, 12)
            .frame(maxWidth: CLMetrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(action: join) {
                ZStack {
                    Text("Join Squad").opacity(busy || joined ? 0 : 1)
                    if busy { ProgressView().tint(CLColor.onFill) }
                    Label("Joined", systemImage: "checkmark").opacity(joined ? 1 : 0).scaleEffect(joined ? 1 : 0.7)
                }
                .animation(CLMotion.pop, value: joined)
            }
            .buttonStyle(.cl(.primary))
            .disabled(!canJoin)
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(alignment: .top) {
                CLColor.background.ignoresSafeArea(edges: .bottom)
            }
        }
        .clScreenBackground()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Sheets don't inherit the root's font choice (RootView sets it inside the modifier that presents them).
        .environment(\.clDyslexicFont, app.settings.dyslexicFont)
        .onAppear {
            if entered.isEmpty, let code { entered = Self.normalize(code) }
        }
    }

    private var canJoin: Bool {
        hasAccounts && app.account.isSignedIn && normalized.count >= 4 && !busy && !joined
    }

    /// "capling.app/squad/cap-7q4k" or " cap 7q4k " → "CAP-7Q4K".
    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = text.lastIndex(of: "/") { text = String(text[text.index(after: slash)...]) }
        if let query = text.firstIndex(where: { $0 == "?" || $0 == "#" }) { text = String(text[..<query]) }
        let kept = text.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return String(kept.prefix(24))
    }

    private func join() {
        guard canJoin else { return }
        busy = true
        errorText = nil
        focused = false
        Task {
            do {
                let response = try await app.redeemSquadInvite(normalized)
                busy = false
                CLHaptics.success()
                joined = true
                try? await nap(600)
                dismiss()
                let message = "You joined \(response.ownerName)'s Squad." + (response.plan.isPaid ? " Every Pro feature is on." : "")
                app.router.toast(.verbatim(message), systemImage: "person.3.fill")
            } catch {
                busy = false
                errorText = RelayError.message(for: error)
            }
        }
    }
}
