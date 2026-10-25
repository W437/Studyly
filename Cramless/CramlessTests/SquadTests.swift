import Foundation
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
}
