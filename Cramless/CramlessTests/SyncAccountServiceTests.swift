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

    // MARK: The first account is made in the background

    /// Records the pauses the background try asks for, and takes no time.
    private final class PauseLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [Double] = []
        var values: [Double] { lock.withLock { _values } }
        func add(_ duration: Duration) { lock.withLock { _values.append(Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18) } }
    }

    /// GoTrue's answer when one address signs up too often.
    private let rateLimited = Data(#"{"code": 429, "error_code": "over_request_rate_limit", "msg": "Request rate limit reached"}"#.utf8)

    private func waitUntil(_ seconds: TimeInterval = 5, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition(), "timed out waiting")
    }

    func testARateLimitedSignUpIsRetriedInTheBackgroundUntilItWorks() async throws {
        let server = StubServer()
        let counter = StubCounter()
        let refusal = rateLimited
        server.on("POST", "/auth/v1/signup") { _ in
            counter.next() <= 2 ? .json(refusal, status: 429) : .json(BackendTest.sessionJSON())
        }
        let app = BackendTest.app(server: server)
        let log = PauseLog()
        app.account.sleep = { log.add($0) }
        app.account.jitter = { 0.5 }

        app.account.prepare()
        XCTAssertEqual(app.account.readiness, .gettingReady, "it returns at once and works in the background")
        try await waitUntil { app.account.readiness == .ready }

        XCTAssertEqual(server.requests("POST", "/auth/v1/signup").count, 3, "429, 429, then 200")
        XCTAssertEqual(log.values, [2, 4], "exponential: 2 s, then 4 s")
        XCTAssertTrue(app.account.isAnonymous)
        let token = try await app.account.accessToken()
        XCTAssertEqual(token, "access-1")
        XCTAssertEqual(server.requests.count, 3, "the account is cached: no more traffic")
    }

    func testAFailedSignUpOffTheNetworkIsRetriedToo() async throws {
        let server = StubServer()
        let counter = StubCounter()
        server.on("POST", "/auth/v1/signup") { _ in
            counter.next() == 1 ? .failure(.notConnectedToInternet) : .json(BackendTest.sessionJSON())
        }
        let app = BackendTest.app(server: server)
        app.account.sleep = { _ in }
        app.account.prepare()
        try await waitUntil { app.account.readiness == .ready }
        XCTAssertEqual(server.requests("POST", "/auth/v1/signup").count, 2)
    }

    func testTheFirstCloudCallWaitsForTheAccountInsteadOfFailing() async throws {
        let server = StubServer()
        let counter = StubCounter()
        let refusal = rateLimited
        server.on("POST", "/auth/v1/signup") { _ in
            counter.next() <= 2 ? .json(refusal, status: 429) : .json(BackendTest.sessionJSON())
        }
        let app = BackendTest.app(server: server)
        app.account.sleep = { _ in }

        let token = try await app.account.accessToken()

        XCTAssertEqual(token, "access-1")
        XCTAssertEqual(server.requests("POST", "/auth/v1/signup").count, 3)
    }

    func testACloudCallThatFindsNoAccountInTimeSaysCloudAIIsGettingReady() async throws {
        let server = StubServer()
        let refusal = rateLimited
        server.on("POST", "/auth/v1/signup") { _ in .json(refusal, status: 429) }
        let app = BackendTest.app(server: server)
        app.account.sleep = { _ in try await Task.sleep(for: .seconds(30)) }
        app.account.firstCallWait = .milliseconds(80)

        await XCTAssertThrowsRelayError(try await app.account.accessToken()) { $0 == .accountPending }
        XCTAssertEqual(app.account.readiness, .gettingReady, "it keeps trying in the background")
        XCTAssertFalse(app.account.isAnonymous)

        // Signing out (or deleting the account) stops the try.
        app.account.clearLocalSession()
        XCTAssertEqual(app.account.readiness, .idle)
        XCTAssertEqual(server.requests("POST", "/auth/v1/signup").count, 1)
    }

    func testTheRouterFallsBackFromACloudJobWithNoAccountAndSaysCloudAIIsGettingReady() async throws {
        let server = StubServer()
        let refusal = rateLimited
        server.on("POST", "/auth/v1/signup") { _ in .json(refusal, status: 429) }
        let app = BackendTest.app(server: server)
        app.account.sleep = { _ in try await Task.sleep(for: .seconds(30)) }
        app.account.firstCallWait = .milliseconds(50)
        app.settings.cloudConsentVersion = AIConsent.currentVersion
        app.ai.probe = FixedOnDeviceProbe(.unavailable(.notChecked))
        app.ai.transportOverride = HTTPRelayTransport(baseURL: server.baseURL, anonKey: "anon-key", tokens: app.account,
                                                      session: server.makeSession())

        let outcome = await app.ai.generateSet(AITestSupport.sampleInput)

        XCTAssertEqual(outcome.origin, .rules)
        XCTAssertTrue(outcome.fellBack)
        XCTAssertEqual(outcome.note, "Cloud AI is getting ready, so these are basic questions from the offline rules. Try again in a minute.")
        XCTAssertFalse(outcome.items.isEmpty, "the app works offline meanwhile")
        XCTAssertTrue(server.requests("POST", "/functions/v1/ai/generate").isEmpty, "no request without an account")
        app.account.clearLocalSession()
    }

    func testASignUpThatIsRefusedForGoodStopsTryingAndSaysWhy() async throws {
        let server = StubServer()
        server.on("POST", "/auth/v1/signup") { _ in .json(["code": 422, "msg": "Anonymous sign-ins are disabled"], status: 422) }
        let app = BackendTest.app(server: server)
        app.account.sleep = { _ in XCTFail("nothing to wait for") }

        await XCTAssertThrowsRelayError(try await app.account.accessToken()) { $0 == .badRequest("Anonymous sign-ins are disabled") }
        XCTAssertEqual(app.account.readiness, .idle)
        XCTAssertEqual(server.requests("POST", "/auth/v1/signup").count, 1)
    }

    func testPreparingTwiceIsOneSignUpAndNeedsNoAccountWhenOneExists() async throws {
        let server = StubServer()
        server.on("POST", "/auth/v1/signup") { _ in .json(BackendTest.sessionJSON(), delay: 0.1) }
        let app = BackendTest.app(server: server)
        app.account.prepare()
        app.account.prepare()
        try await waitUntil { app.account.readiness == .ready }
        XCTAssertEqual(server.requests("POST", "/auth/v1/signup").count, 1)
        app.account.prepare()
        XCTAssertEqual(app.account.readiness, .ready, "an account exists: nothing to prepare")

        let stored = BackendTest.app(server: StubServer(), store: InMemorySessionStore(BackendTest.session()))
        stored.account.restoreSession()
        stored.account.prepare()
        XCTAssertEqual(stored.account.readiness, .idle)
    }

    func testAllowingCloudAIOrLaunchingWithItAllowedMakesTheAccountInTheBackground() async throws {
        // Allowing Cloud AI starts it.
        let server = StubServer()
        server.on("POST", "/auth/v1/signup") { _ in .json(BackendTest.sessionJSON()) }
        let app = BackendTest.app(server: server)
        XCTAssertTrue(server.requests.isEmpty, "nothing is made before the person allows Cloud AI")
        app.allowCloudAI()
        try await waitUntil { app.account.readiness == .ready }
        XCTAssertEqual(server.requests("POST", "/auth/v1/signup").count, 1)

        // A launch with it allowed and no account starts it; a launch without consent does not.
        let again = StubServer()
        again.on("POST", "/auth/v1/signup") { _ in .json(BackendTest.sessionJSON()) }
        let launched = BackendTest.app(server: again)
        launched.settings.cloudConsentVersion = AIConsent.currentVersion
        await launched.account.start()
        try await waitUntil { launched.account.readiness == .ready }

        let quiet = StubServer()
        let undecided = BackendTest.app(server: quiet)
        await undecided.account.start()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(quiet.requests.isEmpty)
        XCTAssertEqual(undecided.account.readiness, .idle)
    }

    func testTheBackoffScheduleIsExponentialWithJitterAndStopsAfterAboutFiveMinutes() {
        // No jitter in the middle of the range (0.5 is x1): 2, 4, 8, 16, 32, then a minute.
        let steady = (1...6).map { AccountBackoff.delay(afterFailures: $0, waited: 0, jitter: 0.5) }
        XCTAssertEqual(steady, [2, 4, 8, 16, 32, 60])
        XCTAssertEqual(AccountBackoff.delay(afterFailures: 9, waited: 0, jitter: 0.5), 60, "a minute at most")
        XCTAssertEqual(AccountBackoff.delay(afterFailures: 40, waited: 0, jitter: 0.5), 60)
        // A quarter either way.
        XCTAssertEqual(AccountBackoff.delay(afterFailures: 1, waited: 0, jitter: 0), 1.5)
        XCTAssertEqual(AccountBackoff.delay(afterFailures: 1, waited: 0, jitter: 1), 2.5)
        XCTAssertEqual(AccountBackoff.delay(afterFailures: 4, waited: 0, jitter: 0), 12)
        XCTAssertEqual(AccountBackoff.delay(afterFailures: 4, waited: 0, jitter: 7), 20, "jitter is kept in 0...1")
        XCTAssertNil(AccountBackoff.delay(afterFailures: 0, waited: 0, jitter: 0.5))
        // Run it: eight retries over four minutes, then it gives up.
        var waited = 0.0
        var pauses: [Double] = []
        var failures = 1
        while let pause = AccountBackoff.delay(afterFailures: failures, waited: waited, jitter: 0.5) {
            pauses.append(pause)
            waited += pause
            failures += 1
        }
        XCTAssertEqual(pauses, [2, 4, 8, 16, 32, 60, 60, 60])
        XCTAssertEqual(waited, 242)
        XCTAssertLessThanOrEqual(waited, AccountBackoff.giveUpAfter)
        // Every variation of the jitter stays inside the five minutes.
        for jitter in stride(from: 0.0, through: 1.0, by: 0.25) {
            var total = 0.0, n = 1
            while let pause = AccountBackoff.delay(afterFailures: n, waited: total, jitter: jitter) { total += pause; n += 1 }
            XCTAssertLessThanOrEqual(total, 300)
            XCTAssertGreaterThan(total, 200)
        }
    }

    func testARefusedSignUpIsNotAMistakeInTheEmailFlow() {
        // Only the anonymous sign-up treats a 429 as a wait; the email code flow still shows GoTrue's own words.
        let body = Data(#"{"code":429,"msg":"For security purposes, you can only request this after 56 seconds."}"#.utf8)
        XCTAssertEqual(SupabaseClient.error(status: 429, data: body, kind: .auth),
                       .badRequest("For security purposes, you can only request this after 56 seconds."))
        XCTAssertEqual(SupabaseClient.error(status: 429, data: body, kind: .signUp),
                       .upstream("For security purposes, you can only request this after 56 seconds."))
        XCTAssertEqual(SupabaseClient.error(status: 422, data: body, kind: .signUp),
                       .badRequest("For security purposes, you can only request this after 56 seconds."))
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
