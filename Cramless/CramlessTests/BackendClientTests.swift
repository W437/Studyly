import Foundation
import XCTest
@testable import Cramless

/// The `account` function's calls: paths, methods, bodies, the error envelope, and the mock and local modes.
@MainActor
final class BackendClientTests: XCTestCase {
    private func signedInApp(_ server: StubServer) -> AppModel {
        let app = BackendTest.app(server: server, store: InMemorySessionStore(BackendTest.session()))
        app.account.restoreSession()
        return app
    }

    func testEveryCallUsesItsPathMethodAndBody() async throws {
        let server = StubServer()
        server.on("POST", "/functions/v1/account/entitlements") { _ in .json(BackendTest.fixture("entitlement")) }
        server.on("GET", "/functions/v1/account/entitlements") { _ in .json(BackendTest.fixture("entitlement")) }
        server.on("POST", "/functions/v1/account/squad/invite") { _ in .json(BackendTest.fixture("squad-invite")) }
        server.on("POST", "/functions/v1/account/squad/redeem") { _ in .json(BackendTest.fixture("squad-redeem")) }
        server.on("GET", "/functions/v1/account/squad/members") { _ in .json(BackendTest.fixture("squad-members")) }
        server.on("POST", "/functions/v1/account/squad/remove") { _ in .json(BackendTest.fixture("squad-members")) }
        server.on("POST", "/functions/v1/account/delete-ai-data") { _ in .json(BackendTest.fixture("account-delete")) }
        server.on("POST", "/functions/v1/account/delete") { _ in .json(BackendTest.fixture("account-delete")) }
        let app = signedInApp(server)
        let backend = app.account.backend

        let entitlement = try await backend.entitlements(["jws"])
        XCTAssertEqual(entitlement.plan, .pro)
        XCTAssertEqual(entitlement.expiresAt, ISO8601DateFormatter().date(from: "2027-10-29T00:00:00Z"))
        _ = try await backend.currentEntitlement()
        let invite = try await backend.createSquadInvite()
        XCTAssertEqual(invite.code, "CAP-7Q4K")
        let redeemed = try await backend.redeemSquadInvite(code: "CAP-7Q4K")
        XCTAssertEqual(redeemed.plan, .squad)
        XCTAssertEqual(redeemed.ownerName, "Maya")
        let members = try await backend.squadMembers()
        XCTAssertEqual(members.seats, 4)
        XCTAssertEqual(members.members.first?.isOwner, true)
        _ = try await backend.removeSquadMember(id: "u-priya")
        let aiDeleted = try await backend.deleteAIData()
        XCTAssertTrue(aiDeleted.deleted)
        let accountDeleted = try await backend.deleteAccount()
        XCTAssertTrue(accountDeleted.deleted)

        let calls = server.requests.map { "\($0.method) \($0.path)" }
        XCTAssertEqual(calls, [
            "POST /functions/v1/account/entitlements",
            "GET /functions/v1/account/entitlements",
            "POST /functions/v1/account/squad/invite",
            "POST /functions/v1/account/squad/redeem",
            "GET /functions/v1/account/squad/members",
            "POST /functions/v1/account/squad/remove",
            "POST /functions/v1/account/delete-ai-data",
            "POST /functions/v1/account/delete",
        ])
        for request in server.requests {
            XCTAssertEqual(request.header("Authorization"), "Bearer access-1", request.path)
            XCTAssertEqual(request.header("apikey"), "anon-key", request.path)
            if request.method == "GET" { XCTAssertNil(request.body, request.path) }
        }
        let bodies = server.requests.map(\.object)
        XCTAssertEqual(bodies[0]?["signedTransactions"] as? [String], ["jws"])
        XCTAssertEqual(bodies[2]?.isEmpty, true)
        XCTAssertEqual(bodies[3]?["code"] as? String, "CAP-7Q4K")
        XCTAssertEqual(bodies[5]?["memberId"] as? String, "u-priya")
        XCTAssertEqual(bodies[6]?.isEmpty, true)
        XCTAssertEqual(bodies[7]?.isEmpty, true)
    }

    func testTheErrorEnvelopeMapsToRelayErrors() async throws {
        let server = StubServer()
        let app = signedInApp(server)
        let backend = app.account.backend

        server.on("GET", "/functions/v1/account/squad/members") { _ in .json(BackendTest.fixture("error-quota"), status: 429) }
        do {
            _ = try await backend.squadMembers()
            XCTFail("expected quota")
        } catch RelayError.quotaExceeded(let quota, let message) {
            XCTAssertEqual(quota?.plan, .free)
            XCTAssertEqual(quota?.meter(.grades)?.used, 20)
            XCTAssertTrue(message.contains("20 graded answers"))
        }

        let envelope: (String, String) -> Data = { code, message in
            try! JSONSerialization.data(withJSONObject: ["error": ["code": code, "message": message]])
        }
        server.on("GET", "/functions/v1/account/squad/members") { _ in .json(envelope("unauthorized", "no"), status: 401) }
        await XCTAssertThrowsRelayError(try await backend.squadMembers()) { $0 == .unauthorized }

        server.on("GET", "/functions/v1/account/squad/members") { _ in
            .json(envelope("entitlement_required", "Squad owners only"), status: 403)
        }
        await XCTAssertThrowsRelayError(try await backend.squadMembers()) { $0 == .entitlementRequired }

        server.on("GET", "/functions/v1/account/squad/members") { _ in .json(envelope("bad_request", "That code expired"), status: 400) }
        await XCTAssertThrowsRelayError(try await backend.squadMembers()) { $0 == .badRequest("That code expired") }

        server.on("GET", "/functions/v1/account/squad/members") { _ in .json(envelope("upstream", "down"), status: 502) }
        await XCTAssertThrowsRelayError(try await backend.squadMembers()) { $0 == .upstream("down") }

        // The gateway's own 401 has no envelope.
        server.on("GET", "/functions/v1/account/squad/members") { _ in .json(["msg": "Invalid JWT"], status: 401) }
        await XCTAssertThrowsRelayError(try await backend.squadMembers()) { $0 == .unauthorized }

        server.on("GET", "/functions/v1/account/squad/members") { _ in .failure(.notConnectedToInternet) }
        await XCTAssertThrowsRelayError(try await backend.squadMembers()) { $0 == .offline }

        server.on("GET", "/functions/v1/account/squad/members") { _ in .json(Data("{\"nope\":1}".utf8)) }
        await XCTAssertThrowsRelayError(try await backend.squadMembers()) {
            if case .decoding = $0 { true } else { false }
        }
    }

    func testMockModeAnswersFromTheFixturesWithoutNetwork() async throws {
        let app = BackendTest.app(.mock)
        let backend = BackendClient(mode: .mock, client: nil, tokens: TokenSource(), mockLatency: .milliseconds(5))
        let invite = try await backend.createSquadInvite()
        XCTAssertEqual(invite, try RelayFixtures.load(SquadInvite.self, "squad-invite"))
        let members = try await backend.squadMembers()
        XCTAssertEqual(members, try RelayFixtures.load(SquadMembers.self, "squad-members"))
        let redeemed = try await backend.redeemSquadInvite(code: "CAP-7Q4K")
        XCTAssertEqual(redeemed.ownerName, "Maya")
        let afterRemoval = try await backend.removeSquadMember(id: "u-priya")
        XCTAssertEqual(afterRemoval.members.map(\.id), ["u-owner"])
        let paid = try await backend.entitlements(["jws"])
        XCTAssertEqual(paid.plan, .pro)
        let free = try await backend.entitlements([])
        XCTAssertEqual(free.plan, .free)
        let current = try await backend.currentEntitlement()
        XCTAssertEqual(current.quota.meter(.scans)?.limit, 3)
        let aiDeleted = try await backend.deleteAIData()
        XCTAssertTrue(aiDeleted.deleted)
        let accountDeleted = try await backend.deleteAccount()
        XCTAssertTrue(accountDeleted.deleted)
        // The app's own client in mock mode behaves the same.
        let appInvite = try await app.createSquadInvite()
        XCTAssertEqual(appInvite.code, "CAP-7Q4K")
        XCTAssertNil(app.account.client)
    }

    func testLocalModeThrowsNotConfigured() async throws {
        let backend = BackendClient(mode: .local, client: nil, tokens: TokenSource())
        await XCTAssertThrowsRelayError(try await backend.createSquadInvite()) { $0 == .notConfigured }
        await XCTAssertThrowsRelayError(try await backend.deleteAccount()) { $0 == .notConfigured }
    }

    func testAFirstCallWithoutASessionStartsAnAnonymousOne() async throws {
        let server = StubServer()
        server.on("POST", "/auth/v1/signup") { _ in .json(BackendTest.sessionJSON(token: "anon-1")) }
        server.on("GET", "/functions/v1/account/entitlements") { _ in .json(BackendTest.fixture("entitlement")) }
        let app = BackendTest.app(server: server)
        _ = try await app.account.backend.currentEntitlement()
        XCTAssertEqual(server.requests.map(\.path), ["/auth/v1/signup", "/functions/v1/account/entitlements"])
        XCTAssertEqual(server.requests.last?.header("Authorization"), "Bearer anon-1")
    }

    func testSessionJSONParsing() throws {
        let session = try XCTUnwrap(SupabaseClient.parseSession(BackendTest.sessionJSON(anonymous: false,
                                                                                        email: "a@b.co")))
        XCTAssertEqual(session.userID, BackendTest.userID)
        XCTAssertEqual(session.email, "a@b.co")
        XCTAssertFalse(session.isAnonymous)
        XCTAssertGreaterThan(session.expiresAt.timeIntervalSinceNow, 3500)
        XCTAssertNil(SupabaseClient.parseSession(Data("{\"access_token\":\"x\"}".utf8)))
    }
}
