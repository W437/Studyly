import XCTest
@testable import Cramless

/// The free AI allowance said before the work (the + sheet, the scanner, the recorder), and nothing sold in the middle of studying.
@MainActor
final class AllowanceCopyTests: XCTestCase {
    private func text(_ resource: LocalizedStringResource?) -> String? { resource.map { String(localized: $0) } }

    func testScansLeftThisWeek() {
        XCTAssertEqual(text(AllowanceCopy.scans(left: 2)), "2 free AI scans left this week")
        XCTAssertEqual(text(AllowanceCopy.scans(left: 1)), "1 free AI scan left this week")
        XCTAssertEqual(text(AllowanceCopy.scans(left: 0)),
                       "Free AI scans are used up until Monday. Cap still writes questions on your iPhone.")
        XCTAssertNil(AllowanceCopy.scans(left: nil), "nothing to say on a paid plan, without consent, or for a child")
    }

    func testLectureNotesLeftThisWeek() {
        XCTAssertEqual(text(AllowanceCopy.lectures(left: 1)), "AI notes for 1 lecture left this week")
        XCTAssertEqual(text(AllowanceCopy.lectures(left: 2)), "AI notes for 2 lectures left this week")
        XCTAssertEqual(text(AllowanceCopy.lectures(left: 0)), "This week's AI lecture notes are used. Transcripts still work.")
        XCTAssertNil(AllowanceCopy.lectures(left: nil))
    }

    func testTheRecordersMakingNotesLineSaysWhoWritesThem() {
        XCTAssertTrue(text(AllowanceCopy.makingNotes(cloud: true, lecturesLeft: nil))!.hasSuffix("with Cloud AI."))
        XCTAssertTrue(text(AllowanceCopy.makingNotes(cloud: true, lecturesLeft: 1))!.hasSuffix("using this week's free AI notes."))
        let used = text(AllowanceCopy.makingNotes(cloud: true, lecturesLeft: 0))!
        XCTAssertTrue(used.contains("on your iPhone."))
        XCTAssertTrue(used.hasSuffix("This week's AI lecture notes are used. Transcripts still work."))
        XCTAssertTrue(text(AllowanceCopy.makingNotes(cloud: false, lecturesLeft: nil))!.hasSuffix("on your iPhone."))
        XCTAssertFalse(text(AllowanceCopy.makingNotes(cloud: false, lecturesLeft: 0))!.contains("used"),
                       "without Cloud AI there is no allowance to talk about")
    }

    func testTheFooterSaysWhatIsAlwaysFree() {
        XCTAssertEqual(String(localized: AllowanceCopy.alwaysFree), "Reviews, cards you make and imports are always free.")
    }

    /// The counts the lines are made from: nil on a paid plan, without consent, for a child; the meter's count otherwise.
    func testTheCountsComeFromTheRouter() throws {
        let app = try StudyTestApp.make(clock: TestClock(EngineTest.date(2026, 11, 6, 10, in: EngineTest.calendar())),
                                        calendar: EngineTest.calendar())
        app.ai.modeOverride = .mock
        app.settings.cloudConsentVersion = AIConsent.currentVersion
        XCTAssertEqual(app.ai.freeCloudUsesLeft(for: .generate), AIFreeLimits.limit(.scans))
        app.ai.setServerQuota(TestHarness.quota("scans:2,lectures:0"))
        XCTAssertEqual(app.ai.freeCloudUsesLeft(for: .generate), 2)
        XCTAssertEqual(app.ai.freeCloudUsesLeft(for: .lecture), 0)
        XCTAssertEqual(app.ai.freeCloudUsesLeft(for: .grade), AIFreeLimits.limit(.grades), "a meter not named is untouched")
        app.settings.ageBand = .under13
        XCTAssertNil(app.ai.freeCloudUsesLeft(for: .generate), "a child's account never uses Cloud AI")
    }

    func testTheQuotaHookReadsUsesLeft() {
        let status = TestHarness.quota("scans:2, lectures:1 ,grades:20,bogus:4")
        XCTAssertEqual(status.plan, .free)
        XCTAssertEqual(status.meter(.scans)?.remaining, 2)
        XCTAssertEqual(status.meter(.lectures)?.remaining, 1)
        XCTAssertEqual(status.meter(.grades)?.remaining, 20)
        XCTAssertEqual(status.meter(.tutor)?.remaining, AIFreeLimits.limit(.tutor))
        XCTAssertEqual(TestHarness.quota("scans:0").meter(.scans)?.remaining, 0)
    }

    // MARK: Never sold mid-session

    func testASessionShowsAFreeLimitAsALineWithNoButton() {
        let limit = AISuggestion.upgrade(.grades, message: AIFreeLimits.cardLine(for: .grades, deviceKeepsWorking: false))
        XCTAssertNil(SuggestionBanner.actionTitle(for: limit, inSession: true), "no See Pro in a session")
        XCTAssertNotNil(SuggestionBanner.actionTitle(for: limit, inSession: false))
        // Consent is not a sale: its button stays.
        XCTAssertNotNil(SuggestionBanner.actionTitle(for: .allowCloud(feature: "Grade"), inSession: true))
        XCTAssertNotNil(SuggestionBanner.actionTitle(for: .allowPhotos, inSession: true))
    }

    /// The question view hands the banner `inSession: true` (read from its source, the one place it is made).
    func testTheOwnWordsQuestionSaysItIsInASession() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Cramless/Features/Session/Questions/OwnWordsQuestionView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("SuggestionBanner(suggestion: suggestion, selfMarked: selfCheck, inSession: true)"))
    }
}
