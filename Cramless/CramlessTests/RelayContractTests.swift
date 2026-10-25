import XCTest
@testable import Cramless

/// Every canned reply decodes with the app's contract types. A renamed or retyped field fails here, not in a
/// session. The relay's tests validate the same files against its schemas.
final class RelayContractTests: XCTestCase {
    func testEveryFixtureDecodes() throws {
        XCTAssertNoThrow(try RelayFixtures.load(GenerateResponse.self, "generate"))
        XCTAssertNoThrow(try RelayFixtures.load(CheckResponse.self, "check"))
        for name in ["grade-partial", "grade-correct", "grade-incorrect"] {
            XCTAssertNoThrow(try RelayFixtures.load(GradeResponse.self, name), name)
        }
        for name in ["tutor-hints", "tutor-explain", "tutor-error"] {
            let script = try RelayFixtures.load(TutorScript.self, name)
            XCTAssertFalse(script.events.isEmpty, name)
            XCTAssertTrue(script.events.allSatisfy { $0.tutorEvent != nil }, name)
        }
        XCTAssertNoThrow(try RelayFixtures.load(ConfusionsResponse.self, "confusions"))
        XCTAssertNoThrow(try RelayFixtures.load(LectureResponse.self, "lecture"))
        XCTAssertNoThrow(try RelayFixtures.load(CardsFromChatResponse.self, "cards-from-chat"))
        XCTAssertNoThrow(try RelayFixtures.load(TranscribeImageResponse.self, "transcribe-image"))
        XCTAssertNoThrow(try RelayFixtures.load(QuotaStatus.self, "quota-free"))
        XCTAssertNoThrow(try RelayFixtures.load(QuotaStatus.self, "quota-pro"))
        XCTAssertNoThrow(try RelayFixtures.load(EntitlementResponse.self, "entitlement"))
        XCTAssertNoThrow(try RelayFixtures.load(SquadInvite.self, "squad-invite"))
        XCTAssertNoThrow(try RelayFixtures.load(SquadMembers.self, "squad-members"))
        XCTAssertNoThrow(try RelayFixtures.load(SquadRedeemResponse.self, "squad-redeem"))
        XCTAssertNoThrow(try RelayFixtures.load(AccountDeleteResponse.self, "account-delete"))
        XCTAssertNoThrow(try RelayFixtures.load(RelayErrorBody.self, "error-quota"))
    }

    func testSampleItemsAnchorToRealLines() throws {
        let lines = Set(try XCTUnwrap(SamplePage.ocr()).lines.map(\.id))
        let generated = try RelayFixtures.load(GenerateResponse.self, "generate")
        for item in generated.items {
            XCTAssertFalse(item.anchors.isEmpty, item.id)
            for anchor in item.anchors { XCTAssertTrue(lines.contains(anchor), "\(item.id) → \(anchor)") }
        }
        let checked = SamplePage.checkedItems()
        XCTAssertEqual(checked.dropped.map(\.id), ["i8"])
        XCTAssertEqual(checked.items.first { $0.id == "i2" }?.answer.contains("same number of chromosomes"), true)
    }
}
