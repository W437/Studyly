import Foundation

/// Supabase auth for the app: the anonymous session the relay needs (created on first need), Sign in with Apple
/// and email codes for a real account (which turns on sync), and the token every backend call carries. The
/// session lives in the Keychain; the observable state is what Settings shows.
///
/// Modes: `local` (no project configured) throws `RelayError.notConfigured` and starts nothing; `mock` never
/// touches the network (sign-in flows succeed after a short pause, for demos); `relay` talks to Supabase.
///
/// DEBUG harness hook: `CRAMLESS_ACCOUNT=apple|email` with `CRAMLESS_UITEST=1` shows a signed-in account
/// (`maya@example.com`) without any network, for screenshots of Settings and Squad.
@MainActor
@Observable
final class AccountService: AccessTokenProvider {
    @ObservationIgnored weak var app: AppModel?

    /// A non-anonymous (Apple or email) session: sync is on.
    private(set) var isSignedIn = false
    /// The current session is anonymous (AI and purchases work; nothing syncs).
    private(set) var isAnonymous = false
    private(set) var email: String?
    private(set) var userID: String?
    /// The last answer from the backend's entitlement check. A Squad member's plan arrives only here.
    private(set) var entitlement: EntitlementResponse?

    let backend: BackendClient

    @ObservationIgnored let mode: AppConfig.AIMode
    @ObservationIgnored let client: SupabaseClient?
    @ObservationIgnored let store: SessionStore
    @ObservationIgnored let tokens: TokenSource
    @ObservationIgnored var now: () -> Date = { Date() }
    /// Sign-in flows in `mock` mode pause this long before succeeding.
    @ObservationIgnored var mockLatency: Duration = .milliseconds(600)

    @ObservationIgnored private var session: AuthSession?
    @ObservationIgnored private var inFlight: Task<AuthSession, Error>?
    /// Bumped by every explicit sign-in or sign-out, so a slower in-flight token request can't overwrite it.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var started = false
    /// A signed-in state without a session (mock mode and the harness hook): no token, no network.
    @ObservationIgnored private(set) var isSimulatedAccount = false

    static let profileDefaultsKey = "capling.sync.profile"

    convenience init(app: AppModel) {
        let config = app.config
        self.init(app: app, config: config, urlSession: .shared,
                  store: config.inMemoryStore ? InMemorySessionStore() : KeychainSessionStore())
    }

    /// The test seam: a URLSession (a URLProtocol stub in tests) and a session store.
    init(app: AppModel?, config: AppConfig, urlSession: URLSession, store: SessionStore) {
        self.app = app
        self.mode = config.aiMode
        var client: SupabaseClient?
        if config.aiMode == .relay, let url = config.supabaseURL, let key = config.supabaseAnonKey, !key.isEmpty {
            client = SupabaseClient(baseURL: url, anonKey: key, session: urlSession)
        }
        self.client = client
        self.store = store
        let tokens = TokenSource()
        self.tokens = tokens
        self.backend = BackendClient(mode: config.aiMode, client: client, tokens: tokens)
        tokens.provider = self
    }

    // MARK: Launch

    /// Loads the stored session; refreshing it, pushing the profile and the first sync run in the background.
    func start() async {
        guard !started else { return }
        started = true
        #if DEBUG
        if let app, app.config.isHarness, let kind = app.config.environment["CRAMLESS_ACCOUNT"],
           kind == "apple" || kind == "email" {
            simulateSignedIn(email: "maya@example.com")
            return
        }
        #endif
        guard mode == .relay, client != nil else { return }
        restoreSession()
        guard session != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.validSession(createIfNeeded: false)
            await self.pushProfileIfNeeded()
            if self.isSignedIn { await self.app?.sync.syncNow() }
        }
    }

    /// Loads the session kept from the last launch (no network).
    func restoreSession() {
        guard mode == .relay, session == nil, let stored = store.load() else { return }
        apply(stored, persist: false)
    }

    // MARK: Tokens

    /// A Supabase access token, creating an anonymous session on first need.
    func accessToken() async throws -> String {
        guard mode == .relay, client != nil, !isSimulatedAccount else { throw RelayError.notConfigured }
        return try await validSession(createIfNeeded: true).accessToken
    }

    /// The current session's token, refreshed if needed, never creating one (sync and profile use this).
    func currentAccessToken() async throws -> String {
        guard mode == .relay, client != nil, !isSimulatedAccount else { throw RelayError.notConfigured }
        return try await validSession(createIfNeeded: false).accessToken
    }

    /// A session valid for at least another minute. Concurrent callers share one in-flight request.
    func validSession(createIfNeeded: Bool) async throws -> AuthSession {
        if let session, session.expiresAt.timeIntervalSince(now()) > 60 { return session }
        if let inFlight { return try await inFlight.value }
        guard let client else { throw RelayError.notConfigured }
        let current = session
        if current == nil, !createIfNeeded { throw RelayError.unauthorized }
        let ticket = generation
        let task = Task { try await self.obtainSession(from: current, createIfNeeded: createIfNeeded, client: client) }
        inFlight = task
        do {
            let fresh = try await task.value
            if inFlight == task { inFlight = nil }
            guard ticket == generation else { return session ?? fresh }
            apply(fresh)
            return fresh
        } catch {
            if inFlight == task { inFlight = nil }
            throw error
        }
    }

    private func obtainSession(from current: AuthSession?, createIfNeeded: Bool,
                               client: SupabaseClient) async throws -> AuthSession {
        if let current {
            do {
                return try await client.refresh(refreshToken: current.refreshToken)
            } catch let error as RelayError where error.rejectsSession {
                // The refresh token was revoked or already used: that session is gone for good.
                if session?.refreshToken == current.refreshToken { apply(nil) }
                guard createIfNeeded else { throw RelayError.unauthorized }
            }
        }
        return try await client.signUpAnonymously()
    }

    // MARK: Signing in and out

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        if mode == .mock {
            try await pause()
            simulateSignedIn(email: nil)
            return
        }
        guard mode == .relay, let client else { throw RelayError.notConfigured }
        let fresh = try await client.signInWithIdToken(provider: "apple", idToken: idToken, nonce: rawNonce)
        signedIn(fresh)
        await pushProfileIfNeeded()
    }

    /// Emails a 6-digit code to sign in (or sign up) with.
    func sendEmailCode(to email: String) async throws {
        let address = Self.normalized(email)
        guard address.contains("@"), address.count >= 3 else {
            throw RelayError.badRequest("That doesn't look like an email address.")
        }
        if mode == .mock { try await pause(); return }
        guard mode == .relay, let client else { throw RelayError.notConfigured }
        try await client.sendEmailOTP(email: address)
    }

    func verifyEmailCode(email: String, code: String) async throws {
        let address = Self.normalized(email)
        let digits = code.filter { !$0.isWhitespace }
        guard digits.count >= 6, digits.allSatisfy(\.isNumber) else {
            throw RelayError.badRequest("Enter the 6-digit code from the email.")
        }
        if mode == .mock {
            try await pause()
            simulateSignedIn(email: address)
            return
        }
        guard mode == .relay, let client else { throw RelayError.notConfigured }
        let fresh: AuthSession
        do {
            fresh = try await client.verifyEmailOTP(email: address, code: digits)
        } catch let error as RelayError where error.rejectsSession {
            // GoTrue answers a wrong or expired code with 401/403: that's the person's typo, not a lost session.
            throw RelayError.badRequest("That code didn't work. Check the latest email, or send a new code.")
        }
        signedIn(fresh)
        await pushProfileIfNeeded()
    }

    /// Signs out here and on the server. Local study data stays; the next AI request starts an anonymous session.
    func signOut() async {
        let token = session?.accessToken
        clearLocalSession()
        if let token, let client { try? await client.signOut(accessToken: token) }
    }

    /// Forgets the session on this device without a network call (sign-out, account deletion).
    func clearLocalSession() {
        generation += 1
        inFlight?.cancel()
        inFlight = nil
        isSimulatedAccount = false
        apply(nil)
        setEntitlement(nil)
        app?.defaults.removeObject(forKey: Self.profileDefaultsKey)
    }

    // MARK: Entitlements and profile

    /// Sends the current StoreKit transactions (`jwsRepresentation`) to the backend so the relay knows the plan.
    func syncEntitlements(_ signedTransactions: [String]) async {
        guard mode != .local else { return }
        do {
            setEntitlement(try await backend.entitlements(signedTransactions))
        } catch {
            AppConfig.log.error("entitlement sync failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Asks the backend for the plan it sees now (after redeeming a Squad code, for instance).
    func refreshEntitlement() async {
        guard mode != .local else { return }
        if let fresh = try? await backend.currentEntitlement() { setEntitlement(fresh) }
    }

    /// Keeps the server's profile (the name Squad members see, the time zone quotas reset in) in step with the
    /// settings. Needs a session but never creates one; sends only when something changed.
    func pushProfileIfNeeded() async {
        guard mode == .relay, let client, let app, let session else { return }
        let name = String(app.settings.firstName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let zone = TimeZone.current.identifier
        let key = "\(session.userID)|\(name)|\(zone)"
        guard app.defaults.string(forKey: Self.profileDefaultsKey) != key else { return }
        do {
            let token = try await currentAccessToken()
            let row: SyncRow = ["id": .string(session.userID), "display_name": .string(name),
                                "timezone": .string(zone), "updated_at": .date(now())]
            try await client.upsert(table: "profiles", rows: [row], onConflict: "id", token: token)
            app.defaults.set(key, forKey: Self.profileDefaultsKey)
        } catch {
            AppConfig.log.error("profile push failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: State

    /// The server's plan reaches the purchase store too: a seat on a friend's Squad exists only on the server.
    private func setEntitlement(_ value: EntitlementResponse?) {
        entitlement = value
        let plan = value?.plan
        app?.purchases.applyServerGrant(plan == .free ? nil : plan, until: value?.expiresAt)
    }

    private func signedIn(_ fresh: AuthSession) {
        generation += 1
        inFlight?.cancel()
        inFlight = nil
        isSimulatedAccount = false
        apply(fresh)
    }

    private func apply(_ value: AuthSession?, persist: Bool = true) {
        session = value
        if persist { store.save(value) }
        isSignedIn = value.map { !$0.isAnonymous } ?? false
        isAnonymous = value?.isAnonymous ?? false
        email = value?.email
        userID = value?.userID
        // Purchases carry the account id as their appAccountToken (PurchaseStore uses it only when signed in).
        app?.purchases.accountToken = value.flatMap { UUID(uuidString: $0.userID) }
    }

    private func simulateSignedIn(email: String?) {
        generation += 1
        isSimulatedAccount = true
        session = nil
        isSignedIn = true
        isAnonymous = false
        self.email = email
        userID = "simulated"
    }

    private func pause() async throws {
        do { try await Task.sleep(for: mockLatency) } catch { throw RelayError.cancelled }
    }

    private static func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension RelayError {
    /// GoTrue said no to the token itself (as opposed to the network failing).
    var rejectsSession: Bool {
        switch self {
        case .unauthorized, .badRequest: true
        default: false
        }
    }
}
