import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// AccountService against a stubbed Supabase: sessions, tokens, sign-in flows, the profile and the modes.
@MainActor
final class SyncAccountServiceTests: XCTestCase {
    func testFirstTokenCreatesOneAnonymousSessionForConcurrentCallers() async throws {
        let server = StubServer()
        server.on("POST", "/auth/v1/signup") { _ in .json(BackendTest.sessionJSON(), delay: 0.25) }
        let store = InMemorySessionStore()
        let app = BackendTest.app(server: server, store: store)

        async let first = app.account.accessToken()
        async let second = app.account.accessToken()
        let tokens = try await [first, second]

        XCTAssertEqual(tokens, ["access-1", "access-1"])
        let signups = server.requests("POST", "/auth/v1/signup")
        XCTAssertEqual(signups.count, 1)
        XCTAssertEqual(signups.first?.header("apikey"), "anon-key")
        XCTAssertEqual(store.load()?.accessToken, "access-1")
        XCTAssertTrue(app.account.isAnonymous)
        XCTAssertFalse(app.account.isSignedIn)
        XCTAssertEqual(app.account.userID, BackendTest.userID)

        // Cached afterwards: no more auth traffic.
        _ = try await app.account.accessToken()
        XCTAssertEqual(server.requests.count, 1)
    }

    func testStoredSessionIsRefreshedNearExpiry() async throws {
        let server = StubServer()
        server.on("POST", "/auth/v1/token") { _ in
            .json(BackendTest.sessionJSON(token: "access-2", refresh: "refresh-2", anonymous: false,
                                          email: "maya@example.com"))
        }
        let store = InMemorySessionStore(BackendTest.session(expiresIn: 30))
        let app = BackendTest.app(server: server, store: store)
        app.account.restoreSession()
        XCTAssertTrue(app.account.isSignedIn)

        let token = try await app.account.accessToken()

        XCTAssertEqual(token, "access-2")
        let refresh = try XCTUnwrap(server.requests("POST", "/auth/v1/token").first)
        XCTAssertEqual(refresh.query("grant_type"), "refresh_token")
        XCTAssertEqual(refresh.object?["refresh_token"] as? String, "refresh-1")
        XCTAssertEqual(store.load()?.refreshToken, "refresh-2")
        XCTAssertTrue(server.requests("POST", "/auth/v1/signup").isEmpty)
    }

    func testValidStoredSessionNeedsNoNetwork() async throws {
        let server = StubServer()
        let app = BackendTest.app(server: server, store: InMemorySessionStore(BackendTest.session()))
        app.account.restoreSession()
        let token = try await app.account.accessToken()
        XCTAssertEqual(token, "access-1")
        XCTAssertTrue(server.requests.isEmpty)
    }

    func testRejectedRefreshDropsTheSessionAndStartsAnonymous() async throws {
        let server = StubServer()
        server.on("POST", "/auth/v1/token") { _ in
            .json(["code": 400, "error_code": "refresh_token_not_found", "msg": "Invalid Refresh Token"], status: 400)
        }
        server.on("POST", "/auth/v1/signup") { _ in
            .json(BackendTest.sessionJSON(userID: BackendTest.otherUserID, token: "anon-token"))
        }
        let store = InMemorySessionStore(BackendTest.session(expiresIn: 10))
        let app = BackendTest.app(server: server, store: store)
        app.account.restoreSession()

        let token = try await app.account.accessToken()

        XCTAssertEqual(token, "anon-token")
        XCTAssertTrue(app.account.isAnonymous)
        XCTAssertFalse(app.account.isSignedIn)
        XCTAssertEqual(store.load()?.userID, BackendTest.otherUserID)
    }

    func testRejectedRefreshWithoutCreatingIsUnauthorized() async throws {
        let server = StubServer()
        server.on("POST", "/auth/v1/token") { _ in .json(["msg": "Invalid Refresh Token"], status: 400) }
        let store = InMemorySessionStore(BackendTest.session(expiresIn: 10))
        let app = BackendTest.app(server: server, store: store)
        app.account.restoreSession()

        do {
            _ = try await app.account.currentAccessToken()
            XCTFail("expected unauthorized")
        } catch let error as RelayError {
            XCTAssertEqual(error, .unauthorized)
        }
        XCTAssertNil(store.load())
        XCTAssertFalse(app.account.isSignedIn)
        XCTAssertTrue(server.requests("POST", "/auth/v1/signup").isEmpty)
    }

    func testOfflineRefreshKeepsTheSession() async throws {
        let server = StubServer()
        server.on("POST", "/auth/v1/token") { _ in .failure(.notConnectedToInternet) }
        let store = InMemorySessionStore(BackendTest.session(expiresIn: 10))
        let app = BackendTest.app(server: server, store: store)
        app.account.restoreSession()

        do {
            _ = try await app.account.accessToken()
            XCTFail("expected offline")
        } catch let error as RelayError {
            XCTAssertEqual(error, .offline)
        }
        XCTAssertNotNil(store.load())
        XCTAssertTrue(app.account.isSignedIn)
    }

    func testSignInWithAppleSendsTheIdTokenAndRawNonce() async throws {
        let server = StubServer()
        server.on("POST", "/auth/v1/token") { _ in
            .json(BackendTest.sessionJSON(token: "apple-token", anonymous: false, email: "maya@privaterelay.appleid.com"))
        }
        let app = BackendTest.app(server: server)
        let nonce = AppleSignInNonce.make()
        XCTAssertEqual(nonce.raw.count, 32)
        XCTAssertEqual(nonce.hashed, AppleSignInNonce.sha256(nonce.raw))
        XCTAssertEqual(nonce.hashed.count, 64)

        var name = PersonNameComponents()
        name.givenName = "Maya"
        try await app.signInWithApple(idToken: "apple-id-token", rawNonce: nonce.raw, fullName: name)

        let request = try XCTUnwrap(server.requests("POST", "/auth/v1/token").first)
        XCTAssertEqual(request.query("grant_type"), "id_token")
        XCTAssertEqual(request.object?["provider"] as? String, "apple")
        XCTAssertEqual(request.object?["id_token"] as? String, "apple-id-token")
        XCTAssertEqual(request.object?["nonce"] as? String, nonce.raw)
        XCTAssertTrue(app.account.isSignedIn)
        XCTAssertFalse(app.account.isAnonymous)
        XCTAssertEqual(app.account.email, "maya@privaterelay.appleid.com")
        XCTAssertEqual(app.settings.firstName, "Maya")
        // The profile carries the name and the time zone.
        let profile = try XCTUnwrap(server.requests("POST", "/rest/v1/profiles").last)
        XCTAssertEqual(profile.query("on_conflict"), "id")
        XCTAssertEqual(profile.header("Authorization"), "Bearer apple-token")
        XCTAssertEqual(profile.rows.first?["display_name"] as? String, "Maya")
        XCTAssertEqual(profile.rows.first?["timezone"] as? String, TimeZone.current.identifier)
        XCTAssertEqual(profile.rows.first?["id"] as? String, BackendTest.userID)
    }

    func testEmailCodeSendAndVerify() async throws {
        let server = StubServer()
        server.on("POST", "/auth/v1/otp") { _ in .json([String: Any]()) }
        server.on("POST", "/auth/v1/verify") { _ in
            .json(BackendTest.sessionJSON(token: "email-token", anonymous: false, email: "maya@example.com"))
        }
        let app = BackendTest.app(server: server)

        try await app.sendEmailCode("  Maya@Example.com ")
        let otp = try XCTUnwrap(server.requests("POST", "/auth/v1/otp").first)
        XCTAssertEqual(otp.object?["email"] as? String, "maya@example.com")
        XCTAssertEqual(otp.object?["create_user"] as? Bool, true)

        try await app.verifyEmailCode(email: "maya@example.com", code: "123 456")
        let verify = try XCTUnwrap(server.requests("POST", "/auth/v1/verify").first)
        XCTAssertEqual(verify.object?["type"] as? String, "email")
        XCTAssertEqual(verify.object?["email"] as? String, "maya@example.com")
        XCTAssertEqual(verify.object?["token"] as? String, "123456")
        XCTAssertTrue(app.account.isSignedIn)
        XCTAssertEqual(app.account.email, "maya@example.com")
    }

    func testBadCodeAndBadAddressAreRejectedLocally() async throws {
        let server = StubServer()
        let app = BackendTest.app(server: server)
        await XCTAssertThrowsRelayError(try await app.sendEmailCode("not-an-address")) {
            if case .badRequest = $0 { true } else { false }
        }
        await XCTAssertThrowsRelayError(try await app.verifyEmailCode(email: "maya@example.com", code: "12")) {
            if case .badRequest = $0 { true } else { false }
        }
        XCTAssertTrue(server.requests.isEmpty)
    }

    func testWrongEmailCodeIsABadRequest() async throws {
        let server = StubServer()
        server.on("POST", "/auth/v1/verify") { _ in
            .json(["code": 403, "error_code": "otp_expired", "msg": "Token has expired or is invalid"], status: 403)
        }
        let app = BackendTest.app(server: server)
        await XCTAssertThrowsRelayError(try await app.verifyEmailCode(email: "maya@example.com", code: "000000")) {
            if case .badRequest = $0 { true } else { false }
        }
        XCTAssertFalse(app.account.isSignedIn)
    }

    func testSignOutClearsTheSessionAndTellsTheServer() async throws {
        let server = StubServer()
        server.on("POST", "/auth/v1/logout") { _ in .empty(204) }
        let store = InMemorySessionStore(BackendTest.session())
        let app = BackendTest.app(server: server, store: store)
        app.account.restoreSession()
        XCTAssertTrue(app.account.isSignedIn)

        await app.signOut()

        XCTAssertFalse(app.account.isSignedIn)
        XCTAssertNil(app.account.userID)
        XCTAssertNil(store.load())
        let logout = try XCTUnwrap(server.requests("POST", "/auth/v1/logout").first)
        XCTAssertEqual(logout.header("Authorization"), "Bearer access-1")
    }

    func testProfileIsPushedOnlyWhenItChanges() async throws {
        let server = StubServer()
        let app = BackendTest.app(server: server, store: InMemorySessionStore(BackendTest.session(anonymous: true)))
        app.account.restoreSession()
        app.settings.firstName = "Maya"

        await app.account.pushProfileIfNeeded()
        await app.account.pushProfileIfNeeded()
        XCTAssertEqual(server.requests("POST", "/rest/v1/profiles").count, 1)

        app.settings.firstName = "Maya R"
        await app.account.pushProfileIfNeeded()
        let pushes = server.requests("POST", "/rest/v1/profiles")
        XCTAssertEqual(pushes.count, 2)
        XCTAssertEqual(pushes.last?.rows.first?["display_name"] as? String, "Maya R")
        XCTAssertEqual(pushes.last?.header("Prefer"), "resolution=merge-duplicates,return=minimal")
    }

    func testProfileNeedsASessionButNeverCreatesOne() async throws {
        let server = StubServer()
        let app = BackendTest.app(server: server)
        await app.account.pushProfileIfNeeded()
        XCTAssertTrue(server.requests.isEmpty)
    }

    func testSyncEntitlementsPostsTheTransactionsAndKeepsTheAnswer() async throws {
        let server = StubServer()
        server.on("POST", "/functions/v1/account/entitlements") { _ in .json(BackendTest.fixture("entitlement")) }
        let app = BackendTest.app(server: server, store: InMemorySessionStore(BackendTest.session()))
        app.account.restoreSession()

        await app.account.syncEntitlements(["jws-1", "jws-2"])

        let request = try XCTUnwrap(server.requests("POST", "/functions/v1/account/entitlements").first)
        XCTAssertEqual(request.object?["signedTransactions"] as? [String], ["jws-1", "jws-2"])
        XCTAssertEqual(request.header("Authorization"), "Bearer access-1")
        XCTAssertEqual(app.account.entitlement?.plan, .pro)
        XCTAssertEqual(app.account.entitlement?.quota.meter(.grades)?.limit, nil)
    }

    func testSyncEntitlementsNeverThrows() async throws {
        let server = StubServer()
        server.on("POST", "/functions/v1/account/entitlements") { _ in .failure(.notConnectedToInternet) }
        let app = BackendTest.app(server: server, store: InMemorySessionStore(BackendTest.session()))
        app.account.restoreSession()
        await app.account.syncEntitlements(["jws"])
        XCTAssertNil(app.account.entitlement)
    }

    // MARK: Modes

    func testLocalModeIsNotConfiguredAndSilent() async throws {
        let app = BackendTest.app(.local)
        await XCTAssertThrowsRelayError(try await app.account.accessToken()) { $0 == .notConfigured }
        await XCTAssertThrowsRelayError(try await app.squadMembers()) { $0 == .notConfigured }
        await XCTAssertThrowsRelayError(try await app.signInWithApple(idToken: "t", rawNonce: "n", fullName: nil)) {
            $0 == .notConfigured
        }
        await app.account.start()
        await app.account.syncEntitlements(["jws"])
        XCTAssertNil(app.account.entitlement)
        XCTAssertFalse(app.account.isSignedIn)
    }

    func testMockModeSimulatesSignInWithoutNetwork() async throws {
        let app = BackendTest.app(.mock)
        await XCTAssertThrowsRelayError(try await app.account.accessToken()) { $0 == .notConfigured }
        try await app.sendEmailCode("maya@example.com")
        try await app.verifyEmailCode(email: "maya@example.com", code: "123456")
        XCTAssertTrue(app.account.isSignedIn)
        XCTAssertEqual(app.account.email, "maya@example.com")
        XCTAssertFalse(app.sync.isEnabled)
        await app.signOut()
        XCTAssertFalse(app.account.isSignedIn)
    }

    func testHarnessAccountHookShowsASignedInAccount() async throws {
        let app = BackendTest.app(.mock, environment: ["CRAMLESS_ACCOUNT": "apple"], isHarness: true)
        await app.account.start()
        XCTAssertTrue(app.account.isSignedIn)
        XCTAssertEqual(app.account.email, "maya@example.com")
        await XCTAssertThrowsRelayError(try await app.account.accessToken()) { $0 == .notConfigured }
    }

    // MARK: Wipe

    func testWipeLocalDataRemovesEverythingAndSignsOut() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "wipe-\(UUID().uuidString)")
        FileStore.rootOverride = root
        defer { FileStore.rootOverride = nil; try? FileManager.default.removeItem(at: root) }
        let store = InMemorySessionStore(BackendTest.session())
        let app = BackendTest.app(server: StubServer(), store: store)
        app.account.restoreSession()
        let course = Course(name: "Bio 101")
        app.context.insert(course)
        app.context.insert(StudyItem(course: course, kind: .flashcard, origin: .person, prompt: "Q", answer: "A"))
        app.context.insert(ReviewLog(itemID: UUID(), courseID: course.id, sessionID: nil, reviewedAt: Date(),
                                     rating: .good, gradedBy: "person", durationMs: 1000, before: .new, after: .new,
                                     elapsedDays: 0, scheduledDays: 1))
        app.settings.firstName = "Maya"
        app.settings.onboardingCompleted = true
        app.save()
        try FileStore.write(Data("x".utf8), folder: "pages", name: "p.jpg")
        SyncLedger(userID: BackendTest.userID).save(to: app.defaults)

        app.wipeLocalData()

        XCTAssertTrue(app.fetch(FetchDescriptor<Course>()).isEmpty)
        XCTAssertTrue(app.fetch(FetchDescriptor<StudyItem>()).isEmpty)
        XCTAssertTrue(app.fetch(FetchDescriptor<ReviewLog>()).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "pages/p.jpg").path))
        XCTAssertEqual(app.settings.firstName, "")
        XCTAssertFalse(app.settings.onboardingCompleted)
        XCTAssertFalse(app.account.isSignedIn)
        XCTAssertNil(store.load())
        XCTAssertNil(SyncLedger.load(from: app.defaults).userID)
    }

    func testDeleteAccountCallsTheServerThenWipes() async throws {
        let server = StubServer()
        server.on("POST", "/functions/v1/account/delete") { _ in .json(BackendTest.fixture("account-delete")) }
        let app = BackendTest.app(server: server, store: InMemorySessionStore(BackendTest.session()))
        app.account.restoreSession()
        app.context.insert(Course(name: "Chem"))
        app.save()

        try await app.deleteAccount()

        XCTAssertEqual(server.requests("POST", "/functions/v1/account/delete").count, 1)
        XCTAssertTrue(app.fetch(FetchDescriptor<Course>()).isEmpty)
        XCTAssertFalse(app.account.isSignedIn)
    }

    func testFailedServerDeleteKeepsLocalData() async throws {
        let server = StubServer()
        server.on("POST", "/functions/v1/account/delete") { _ in .failure(.notConnectedToInternet) }
        let app = BackendTest.app(server: server, store: InMemorySessionStore(BackendTest.session()))
        app.account.restoreSession()
        app.context.insert(Course(name: "Chem"))
        app.save()

        await XCTAssertThrowsRelayError(try await app.deleteAccount()) { $0 == .offline }
        XCTAssertEqual(app.fetch(FetchDescriptor<Course>()).count, 1)
        XCTAssertTrue(app.account.isSignedIn)
    }

    /// A signed-in session that can't be refreshed must not become a fresh anonymous one that gets deleted instead:
    /// that would leave the real account on the server and wipe the phone. Deleting stops and asks to sign in again.
    func testDeleteAccountNeverDeletesAFreshAnonymousAccount() async throws {
        let server = StubServer()
        server.on("POST", "/auth/v1/token") { _ in .json(["msg": "Invalid Refresh Token"], status: 400) }
        server.on("POST", "/auth/v1/signup") { _ in .json(BackendTest.sessionJSON(userID: BackendTest.otherUserID)) }
        server.on("POST", "/functions/v1/account/delete") { _ in .json(BackendTest.fixture("account-delete")) }
        let app = BackendTest.app(server: server, store: InMemorySessionStore(BackendTest.session(expiresIn: 10)))
        app.account.restoreSession()
        app.context.insert(Course(name: "Chem"))
        app.save()

        await XCTAssertThrowsRelayError(try await app.deleteAccount()) { $0 == .unauthorized }

        XCTAssertTrue(server.requests("POST", "/auth/v1/signup").isEmpty)
        XCTAssertTrue(server.requests("POST", "/functions/v1/account/delete").isEmpty)
        XCTAssertEqual(app.fetch(FetchDescriptor<Course>()).count, 1)
    }

    /// No session on this device means no server account of its own: deleting wipes the phone without a request.
    func testDeleteWithoutASessionOnlyWipesTheDevice() async throws {
        let server = StubServer()
        let app = BackendTest.app(server: server, store: InMemorySessionStore())
        app.context.insert(Course(name: "Chem"))
        app.save()

        try await app.deleteAIData()
        try await app.deleteAccount()

        XCTAssertTrue(server.requests.isEmpty)
        XCTAssertTrue(app.fetch(FetchDescriptor<Course>()).isEmpty)
    }
}

/// Asserts that `expression` throws a RelayError matching `matches`.
@MainActor
func XCTAssertThrowsRelayError<T>(_ expression: @autoclosure () async throws -> T,
                                  file: StaticString = #filePath, line: UInt = #line,
                                  _ matches: (RelayError) -> Bool) async {
    do {
        _ = try await expression()
        XCTFail("expected a RelayError", file: file, line: line)
    } catch let error as RelayError {
        XCTAssertTrue(matches(error), "unexpected \(error)", file: file, line: line)
    } catch {
        XCTFail("unexpected \(error)", file: file, line: line)
    }
}
