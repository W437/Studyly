import Foundation

/// Hands the backend clients the current access token without a reference cycle back to `AccountService`.
final class TokenSource: @unchecked Sendable {
    private let lock = NSLock()
    private weak var _provider: (AnyObject & AccessTokenProvider)?

    var provider: (AnyObject & AccessTokenProvider)? {
        get { lock.lock(); defer { lock.unlock() }; return _provider }
        set { lock.lock(); _provider = newValue; lock.unlock() }
    }

    func token() async throws -> String {
        guard let provider else { throw RelayError.notConfigured }
        return try await provider.accessToken()
    }

    /// The token of the session this device already has, refreshed if needed, never a new anonymous one.
    /// Deletion uses it: a fresh anonymous session would delete an empty account and leave the real one.
    func existingToken() async throws -> String {
        guard let provider else { throw RelayError.notConfigured }
        if let account = provider as? AccountService { return try await account.currentAccessToken() }
        return try await provider.accessToken()
    }
}

/// The `account` Edge Function: entitlements, Squad and deletion, in the contract's types (RelayContract.swift).
/// In `mock` mode it answers from the bundled fixtures after a short pause and never touches the network; in
/// `local` mode (no project configured) every call throws `RelayError.notConfigured`.
final class BackendClient: Sendable {
    let mode: AppConfig.AIMode
    let client: SupabaseClient?
    let tokens: TokenSource
    let mockLatency: Duration

    init(mode: AppConfig.AIMode, client: SupabaseClient?, tokens: TokenSource,
         mockLatency: Duration = .milliseconds(600)) {
        self.mode = mode
        self.client = client
        self.tokens = tokens
        self.mockLatency = mockLatency
    }

    /// Sends the current StoreKit transactions (`jwsRepresentation`); the answer is the plan the relay now uses.
    func entitlements(_ signedTransactions: [String]) async throws -> EntitlementResponse {
        try await call("account/entitlements", method: "POST",
                       body: EntitlementRequest(signedTransactions: signedTransactions)) {
            signedTransactions.isEmpty ? try Self.freeEntitlement()
                : try RelayFixtures.load(EntitlementResponse.self, "entitlement")
        }
    }

    /// The plan the relay sees now (a Squad member's plan comes only from here: they have no StoreKit purchase).
    func currentEntitlement() async throws -> EntitlementResponse {
        try await call("account/entitlements", method: "GET", body: nil) { try Self.freeEntitlement() }
    }

    func createSquadInvite() async throws -> SquadInvite {
        try await call("account/squad/invite", method: "POST", body: EmptyBody()) {
            try RelayFixtures.load(SquadInvite.self, "squad-invite")
        }
    }

    func redeemSquadInvite(code: String) async throws -> SquadRedeemResponse {
        try await call("account/squad/redeem", method: "POST", body: SquadRedeemRequest(code: code)) {
            try RelayFixtures.load(SquadRedeemResponse.self, "squad-redeem")
        }
    }

    func squadMembers() async throws -> SquadMembers {
        try await call("account/squad/members", method: "GET", body: nil) {
            try RelayFixtures.load(SquadMembers.self, "squad-members")
        }
    }

    func removeSquadMember(id: String) async throws -> SquadMembers {
        try await call("account/squad/remove", method: "POST", body: SquadRemoveRequest(memberId: id)) {
            var members = try RelayFixtures.load(SquadMembers.self, "squad-members")
            members.members.removeAll { $0.id == id && !$0.isOwner }
            return members
        }
    }

    /// Shares, or stops sharing, that the person studied today. Off deletes what was shared.
    func setSquadSharing(on: Bool) async throws -> SquadMembers {
        try await call("account/squad/share", method: "POST", body: SquadShareRequest(on: on)) {
            var members = try RelayFixtures.load(SquadMembers.self, "squad-members")
            members.sharing = on
            return members
        }
    }

    /// The day's first finished session, for someone who shares. It works without sync: only the day goes.
    func markSquadStudied(dayKey: String) async throws -> SquadStudiedResponse {
        try await call("account/squad/studied", method: "POST", body: SquadStudiedRequest(dayKey: dayKey)) {
            try RelayFixtures.load(SquadStudiedResponse.self, "squad-studied")
        }
    }

    /// Deletes what the relay keeps about the person's AI use (the request log; it never stores content).
    /// Uses the session this device has; `.unauthorized` when it can't be refreshed.
    func deleteAIData() async throws -> AccountDeleteResponse {
        try await call("account/delete-ai-data", method: "POST", body: EmptyBody(), existingSessionOnly: true) {
            try RelayFixtures.load(AccountDeleteResponse.self, "account-delete")
        }
    }

    /// Deletes the account: every synced row, uploaded file, entitlement and the auth user. Uses the session this
    /// device has, never a new one; `.unauthorized` when it can't be refreshed (sign in again, then delete).
    func deleteAccount() async throws -> AccountDeleteResponse {
        try await call("account/delete", method: "POST", body: EmptyBody(), existingSessionOnly: true) {
            try RelayFixtures.load(AccountDeleteResponse.self, "account-delete")
        }
    }

    // MARK: Plumbing

    private struct EmptyBody: Encodable {}

    private func call<Response: Decodable>(_ path: String, method: String, body: (any Encodable)?,
                                           existingSessionOnly: Bool = false,
                                           mock: () throws -> Response) async throws -> Response {
        switch mode {
        case .local:
            throw RelayError.notConfigured
        case .mock:
            do { try await Task.sleep(for: mockLatency) } catch { throw RelayError.cancelled }
            return try mock()
        case .relay:
            break
        }
        guard let client else { throw RelayError.notConfigured }
        let data: Data?
        if let body {
            do { data = try JSONEncoder.cramless.encode(body) } catch { throw RelayError.badRequest("unencodable body") }
        } else {
            data = nil
        }
        let token = existingSessionOnly ? try await tokens.existingToken() : try await tokens.token()
        let response = try await client.invoke(path, method: method, body: data, token: token)
        do {
            return try JSONDecoder.cramless.decode(Response.self, from: response)
        } catch {
            throw RelayError.decoding("\(path): \(error)")
        }
    }

    static func freeEntitlement() throws -> EntitlementResponse {
        EntitlementResponse(plan: .free, expiresAt: nil, quota: try RelayFixtures.load(QuotaStatus.self, "quota-free"))
    }
}
