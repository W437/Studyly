import Foundation
import SwiftData

// Account, sync, Squad and deletion: what Settings and the Squad screens call. Each throws `RelayError` (the app's
// one backend error vocabulary): `.notConfigured` when this build has no Supabase project, `.offline`,
// `.unauthorized`, `.entitlementRequired` (inviting without a Squad subscription), `.badRequest(message)` for a
// wrong code or address. In `mock` mode they answer from the bundled fixtures without any network.
extension AppModel {
    // MARK: Signing in

    /// Sign in with Apple. Put `AppleSignInNonce.make().hashed` in the Apple request and pass the raw nonce here.
    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        try await account.signInWithApple(idToken: idToken, rawNonce: rawNonce, fullName: fullName)
        if settings.firstName.trimmingCharacters(in: .whitespaces).isEmpty,
           let given = fullName?.givenName?.trimmingCharacters(in: .whitespaces), !given.isEmpty {
            settings.firstName = given
        }
        await account.pushProfileIfNeeded()
        startSyncAfterSignIn()
    }

    /// Emails a 6-digit sign-in code.
    func sendEmailCode(_ email: String) async throws {
        try await account.sendEmailCode(to: email)
    }

    func verifyEmailCode(email: String, code: String) async throws {
        try await account.verifyEmailCode(email: email, code: code)
        startSyncAfterSignIn()
    }

    /// Signs out. Everything studied stays on this iPhone; sync stops until the next sign-in.
    func signOut() async {
        await account.signOut()
        // The purchases went to the signed-in account; the next session (anonymous) needs them too, or a subscriber
        // is metered as free until the next launch (the same gap the sign-in path closes).
        await purchases.resyncEntitlements()
    }

    private func startSyncAfterSignIn() {
        Task { [weak self] in
            guard let self else { return }
            // Purchases already sent this launch went to the previous (anonymous) session: send them for this
            // account, or the relay meters a subscriber as free until the next launch.
            await self.purchases.resyncEntitlements()
            await self.account.refreshEntitlement()
            await self.sync.syncNow()
        }
    }

    // MARK: Sync

    /// Pull, then push (the Settings button; launch does this on its own).
    func syncNow() async {
        await sync.syncNow()
    }

    // MARK: Deleting

    /// Deletes what the relay keeps about this person's AI use. Study data is untouched. Without a session on this
    /// device the relay holds nothing that is this device's: there is nothing to delete.
    func deleteAIData() async throws {
        if config.aiMode == .relay {
            account.restoreSession()
            guard account.userID != nil else { return }
        }
        let response = try await account.backend.deleteAIData()
        guard response.deleted else { throw RelayError.upstream("The AI data wasn't deleted.") }
    }

    /// Deletes the account on the server (every synced row, file, entitlement and the sign-in), then everything on
    /// this iPhone. Only the session this device already has can do it: when it can't be refreshed this throws
    /// `.unauthorized` (sign in again, then delete) and keeps local data, rather than deleting a fresh anonymous
    /// account. With no session at all, or no configured project, only the local wipe happens.
    func deleteAccount() async throws {
        if config.aiMode == .relay {
            account.restoreSession()
            if account.userID != nil {
                let response = try await account.backend.deleteAccount()
                guard response.deleted else { throw RelayError.upstream("The account wasn't deleted.") }
            }
        } else if config.aiMode == .mock {
            _ = try await account.backend.deleteAccount()
        }
        wipeLocalData()
    }

    /// Removes every study model, the files beside the store, the settings (onboarding runs again), the session,
    /// the half-typed answers and the sync ledger.
    func wipeLocalData() {
        for m in fetch(FetchDescriptor<ChatMessage>()) { context.delete(m) }
        for m in fetch(FetchDescriptor<ChatThread>()) { context.delete(m) }
        for m in fetch(FetchDescriptor<ReviewLog>()) { context.delete(m) }
        for m in fetch(FetchDescriptor<StudySession>()) { context.delete(m) }
        for m in fetch(FetchDescriptor<DayRecord>()) { context.delete(m) }
        for m in fetch(FetchDescriptor<Confusion>()) { context.delete(m) }
        for m in fetch(FetchDescriptor<Exam>()) { context.delete(m) }
        for m in fetch(FetchDescriptor<StudyItem>()) { context.delete(m) }
        for m in fetch(FetchDescriptor<Topic>()) { context.delete(m) }
        for m in fetch(FetchDescriptor<SourcePage>()) { context.delete(m) }
        for m in fetch(FetchDescriptor<Source>()) { context.delete(m) }
        for m in fetch(FetchDescriptor<Course>()) { context.delete(m) }
        try? FileManager.default.removeItem(at: FileStore.root)
        account.clearLocalSession()
        sync.resetLedger()
        clearSessionKeep()
        defaults.removeObject(forKey: AgeCheck.defaultsKey)
        var fresh = AppSettings()
        fresh.installedAt = Date()
        settings = fresh
        save()
    }

    // MARK: Squad

    /// A single-use invite for a friend (Squad owners only; four seats in all).
    func createSquadInvite() async throws -> SquadInvite {
        try await account.backend.createSquadInvite()
    }

    /// Joins a friend's Squad; the plan the relay sees changes at once.
    func redeemSquadInvite(_ code: String) async throws -> SquadRedeemResponse {
        let response = try await account.backend.redeemSquadInvite(code: code)
        await account.refreshEntitlement()
        // The seat counts at once, also in mock mode, where the canned entitlement doesn't know about it.
        if response.plan.isPaid, !purchases.isPro { purchases.applyServerGrant(response.plan, until: nil) }
        return response
    }

    func squadMembers() async throws -> SquadMembers {
        try await account.backend.squadMembers()
    }

    /// The owner removes a member, or a member leaves (pass your own id).
    func removeSquadMember(_ id: String) async throws -> SquadMembers {
        let members = try await account.backend.removeSquadMember(id: id)
        if id == account.userID { await account.refreshEntitlement() }
        return members
    }
}
