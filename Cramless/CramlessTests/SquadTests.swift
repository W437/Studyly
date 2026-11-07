import Foundation
import os
import XCTest
@testable import Cramless

/// Squad: who sees what (owner, member, none), codes typed or pasted from a link, and the calls the screens make
/// in the demo build (mock mode answers from the fixtures; a build without accounts says so).
@MainActor
final class SquadTests: AskTestCase {

    func testRoles() {
        XCTAssertEqual(SquadView.role(allowsSeats: true, plan: .squad), .owner)
        XCTAssertEqual(SquadView.role(allowsSeats: false, plan: .squad), .member, "a seat on a friend's Squad")
        XCTAssertEqual(SquadView.role(allowsSeats: false, plan: .pro), SquadView.Role.none)
        XCTAssertEqual(SquadView.role(allowsSeats: false, plan: .free), SquadView.Role.none)
    }

    func testCodesFromLinksAndTyping() {
        XCTAssertEqual(SquadRedeemView.normalize("https://capling.app/squad/cap-7q4k"), "CAP-7Q4K")
        XCTAssertEqual(SquadRedeemView.normalize("  cap 7q4k \n"), "CAP7Q4K")
        XCTAssertEqual(SquadRedeemView.normalize("capling.app/squad/CAP-7Q4K?ref=share"), "CAP-7Q4K")
        XCTAssertEqual(SquadRedeemView.normalize("CAP-7Q4K"), "CAP-7Q4K")
    }

    func testTheDemoBuildAnswersFromTheFixtures() async throws {
        let app = makeApp(mode: .mock)
        let members = try await app.squadMembers()
        XCTAssertEqual(members.seats, 4)
        XCTAssertEqual(members.members.first(where: \.isOwner)?.name, "Maya")
        let invite = try await app.createSquadInvite()
        XCTAssertEqual(invite.code, "CAP-7Q4K")
        XCTAssertEqual(URL(string: invite.url)?.lastPathComponent, invite.code)
        let joined = try await app.redeemSquadInvite("CAP-7Q4K")
        XCTAssertEqual(joined.ownerName, "Maya")
        let afterRemoval = try await app.removeSquadMember("u-priya")
        XCTAssertFalse(afterRemoval.members.contains { $0.id == "u-priya" })
    }

    func testABuildWithoutAccountsSaysSo() async {
        let app = makeApp(mode: .local)
        do {
            _ = try await app.createSquadInvite()
            XCTFail("a build without accounts can't make invites")
        } catch {
            XCTAssertEqual(error as? RelayError, .notConfigured)
            XCTAssertTrue(RelayError.message(for: error)?.hasPrefix("Accounts aren't set up") ?? false)
        }
    }

    // MARK: Studied today

    private func friend(_ name: String, _ studied: Bool?) -> SquadToday.Friend { .init(id: "u-\(name)", name: name, studied: studied) }

    func testTheLineSaysOnlyWhatPeopleChoseToShare() {
        func line(_ friends: [SquadToday.Friend]) -> String { SquadToday(day: "2026-11-06", readAt: .now, friends: friends).line }
        XCTAssertEqual(line([friend("Priya", true)]), "Priya studied today")
        XCTAssertEqual(line([friend("Priya", true), friend("Sam", true)]), "Priya and Sam studied today")
        XCTAssertEqual(line([friend("Priya", true), friend("Sam", true), friend("Lee", true)]), "Priya, Sam, and Lee studied today")
        XCTAssertEqual(line([friend("Priya", true), friend("Sam", false), friend("Lee", nil)]), "Priya studied today", "only who has")
        XCTAssertEqual(line([friend("Priya", false), friend("Sam", nil)]), "No one in your Squad has studied yet today")
        XCTAssertEqual(line([friend("Priya", nil), friend("Sam", nil)]), "Who's in your Squad", "nobody shares: only the way to the Squad")
    }

    /// An app on a friend's Squad, or on its own: the mock answers from the fixture, where Priya has studied.
    private func squadApp(plan: Plan = .squad, mode: AppConfig.AIMode = .mock) -> AppModel {
        let app = makeApp(mode: mode)
        if plan != .free { app.purchases.applyServerGrant(plan, until: nil) }
        return app
    }

    func testSharingIsOffUntilSwitchedOnAndOldSettingsSayOff() throws {
        let old = try JSONDecoder.cramless.decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(old.shareSquadDay)
        XCTAssertFalse(AppSettings().shareSquadDay)
    }

    func testTodaysLineComesFromTheMembersWithoutThePerson() async throws {
        let app = squadApp()
        XCTAssertNil(app.squadTodayLine, "nothing read yet")
        await app.refreshSquadToday()
        let line = try XCTUnwrap(app.squadTodayLine)
        XCTAssertEqual(line.friends.map(\.name), ["Maya", "Priya"], "a member's list holds the owner")
        XCTAssertEqual(line.friends.map(\.studied), [nil, true])
        XCTAssertEqual(line.line, "Priya studied today")
        XCTAssertFalse(app.settings.shareSquadDay, "the fixture's person doesn't share")
    }

    func testThePersonIsNotInTheirOwnLine() throws {
        let members = try RelayFixtures.load(SquadMembers.self, "squad-members")
        XCTAssertEqual(SquadToday.friends(in: members, me: nil, owner: true).map(\.name), ["Priya"], "the owner's seat")
        XCTAssertEqual(SquadToday.friends(in: members, me: "u-priya", owner: false).map(\.name), ["Maya"], "a member's own")
        XCTAssertEqual(SquadToday.friends(in: members, me: "u-owner", owner: true).map(\.name), ["Priya"])
    }

    func testNoSquadNoLineAndNothingAsked() async {
        let app = squadApp(plan: .pro)
        await app.refreshSquadToday()
        XCTAssertNil(app.squadToday)
        XCTAssertNil(app.squadTodayLine)
    }

    func testTheLineGoesAtMidnightAndWhenTheSquadGoes() async throws {
        let app = squadApp()
        await app.refreshSquadToday()
        XCTAssertNotNil(app.squadTodayLine)
        let later = app.now.addingTimeInterval(86_400)
        app.clock = { later }
        XCTAssertNil(app.squadTodayLine, "yesterday's dots aren't today's")
        await app.refreshSquadToday()
        XCTAssertNotNil(app.squadTodayLine, "read again")
        app.clearSquadToday()
        XCTAssertNil(app.squadTodayLine)
    }

    func testAFreshLookIsNotReadAgain() async throws {
        let server = StubServer()
        let app = signedIn(server: server, sharing: false, studied: false)
        func reads() -> Int { server.requests.filter { $0.path.hasSuffix("/squad/members") }.count }
        await app.refreshSquadToday()
        await app.refreshSquadToday()
        XCTAssertEqual(reads(), 1, "still fresh")
        let later = app.now.addingTimeInterval(16 * 60)
        app.clock = { later }
        await app.refreshSquadToday()
        XCTAssertEqual(reads(), 2)
    }

    /// An account on the stub, signed in, on a friend's Squad, with a session finished today or not.
    private func signedIn(server: StubServer, sharing: Bool, studied: Bool = true) -> AppModel {
        // Like the real one: the members say whether the person shares, as the switch last left it.
        let shares = OSAllocatedUnfairLock(initialState: sharing)
        let list: @Sendable () -> StubServer.Response = {
            var members = (try? JSONDecoder.cramless.decode(SquadMembers.self, from: BackendTest.fixture("squad-members")))!
            members.sharing = shares.withLock { $0 }
            return .json((try? JSONEncoder.cramless.encode(members)) ?? Data())
        }
        server.on("POST", "/functions/v1/account/squad/studied") { _ in .json(BackendTest.fixture("squad-studied")) }
        server.on("POST", "/functions/v1/account/squad/share") { request in
            shares.withLock { $0 = request.object?["on"] as? Bool ?? false }
            return list()
        }
        server.on("GET", "/functions/v1/account/squad/members") { _ in list() }
        let app = BackendTest.app(server: server, store: InMemorySessionStore(BackendTest.session()))
        app.account.restoreSession()
        app.purchases.applyServerGrant(.squad, until: nil)
        app.settings.shareSquadDay = sharing
        if studied {
            let session = StudySession(kind: .daily, startedAt: app.now, plannedSeconds: 600)
            session.endedAt = app.now
            session.itemCount = 5
            app.context.insert(session)
            app.save()
        }
        return app
    }

    func testStudiedIsSentOnceADayForSomeoneWhoShares() async throws {
        let server = StubServer()
        let app = signedIn(server: server, sharing: true)
        let key = app.calendar.dayKey(for: app.now)
        let sent = await app.sendSquadStudiedIfDue()
        XCTAssertTrue(sent)
        let posts = server.requests.filter { $0.path.hasSuffix("/squad/studied") }
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts[0].method, "POST")
        XCTAssertEqual(posts[0].object?["dayKey"] as? String, key)
        XCTAssertEqual(posts[0].object?.count, 1, "the day and nothing else")
        let again = await app.sendSquadStudiedIfDue()
        XCTAssertFalse(again)
        XCTAssertEqual(server.requests.filter { $0.path.hasSuffix("/squad/studied") }.count, 1)
    }

    func testNothingIsSentWithoutSharingASquadOrAFinishedSession() async {
        let off = StubServer()
        let notSharing = signedIn(server: off, sharing: false)
        let first = await notSharing.sendSquadStudiedIfDue()
        XCTAssertFalse(first)
        XCTAssertTrue(off.requests.filter { $0.path.hasSuffix("/squad/studied") }.isEmpty)

        let idle = StubServer()
        let notYet = signedIn(server: idle, sharing: true, studied: false)
        let second = await notYet.sendSquadStudiedIfDue()
        XCTAssertFalse(second)
        XCTAssertTrue(idle.requests.filter { $0.path.hasSuffix("/squad/studied") }.isEmpty)

        let gone = StubServer()
        let noSquad = signedIn(server: gone, sharing: true)
        noSquad.purchases.applyServerGrant(nil, until: nil)
        let third = await noSquad.sendSquadStudiedIfDue()
        XCTAssertFalse(third)
        XCTAssertTrue(gone.requests.filter { $0.path.hasSuffix("/squad/studied") }.isEmpty)
    }

    func testAFailedSendIsTriedAgain() async {
        let server = StubServer()
        let online = OSAllocatedUnfairLock(initialState: false)
        let app = signedIn(server: server, sharing: true)
        server.on("POST", "/functions/v1/account/squad/studied") { _ in
            online.withLock { $0 } ? .json(BackendTest.fixture("squad-studied")) : .failure(.notConnectedToInternet)
        }
        let offline = await app.sendSquadStudiedIfDue()
        XCTAssertFalse(offline)
        online.withLock { $0 = true }
        let back = await app.sendSquadStudiedIfDue()
        XCTAssertTrue(back)
    }

    func testTheSwitchTellsTheServerAndSaysStudiedIfASessionIsDone() async throws {
        let server = StubServer()
        let app = signedIn(server: server, sharing: false)
        let on = try await app.setSquadSharing(true)
        XCTAssertEqual(on.members.count, 2)
        XCTAssertTrue(app.settings.shareSquadDay)
        let paths = server.requests.map(\.path)
        XCTAssertEqual(server.requests.first { $0.path.hasSuffix("/squad/share") }?.object?["on"] as? Bool, true)
        XCTAssertTrue(paths.contains { $0.hasSuffix("/squad/studied") }, "today's session counts at once")
        _ = try await app.setSquadSharing(false)
        XCTAssertFalse(app.settings.shareSquadDay)
        XCTAssertEqual(server.requests.last { $0.path.hasSuffix("/squad/share") }?.object?["on"] as? Bool, false)
        // Switched on again the same day: the server deleted it, so it's said again.
        _ = try await app.setSquadSharing(true)
        XCTAssertEqual(server.requests.filter { $0.path.hasSuffix("/squad/studied") }.count, 2)
    }

    func testTheServersWordOnTheSwitchWins() async throws {
        let app = squadApp()
        app.settings.shareSquadDay = true
        await app.refreshSquadToday()
        XCTAssertFalse(app.settings.shareSquadDay, "the fixture says it isn't sharing")
    }

    func testTheFixtureDecodes() throws {
        let members = try RelayFixtures.load(SquadMembers.self, "squad-members")
        XCTAssertEqual(members.sharing, false)
        XCTAssertNil(members.members[0].studiedToday, "not shared: not there")
        XCTAssertEqual(members.members[1].studiedToday, true)
        XCTAssertTrue(try RelayFixtures.load(SquadStudiedResponse.self, "squad-studied").recorded)
    }

    func testServerWordsNeverReachTheScreen() {
        XCTAssertEqual(RelayError.badRequest("There's no such endpoint.").friendlyMessage, RelayError.couldNotDoIt, "a build newer than its server")
        XCTAssertEqual(RelayError.badRequest("That method isn't supported here.").friendlyMessage, RelayError.couldNotDoIt)
        XCTAssertEqual(RelayError.badRequest("That Squad is full.").friendlyMessage, "That Squad is full.", "words meant for the person stay")
        XCTAssertEqual(String(localized: SquadCopy.switchOnFailed), "Couldn't turn this on. Try again in a while.")
        XCTAssertEqual(String(localized: SquadCopy.switchOffFailed), "Couldn't turn this off. Try again in a while.")
    }
}
