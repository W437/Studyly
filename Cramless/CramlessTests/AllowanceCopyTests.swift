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

    /// A long reading says what it takes before the work, once its pages are known.
    func testALongReadingSaysWhatItTakes() {
        XCTAssertEqual(text(AllowanceCopy.reading(pages: 21, needed: 3, readable: 21, left: 3)),
                       "This is 21 pages, so it takes 3 of your free AI scans.")
        XCTAssertEqual(text(AllowanceCopy.reading(pages: 12, needed: 2, readable: 10, left: 1)),
                       "You have 1 free AI scan left, so Cap reads the first 10 of 12 pages.")
        XCTAssertEqual(text(AllowanceCopy.reading(pages: 25, needed: 3, readable: 20, left: 2)),
                       "You have 2 free AI scans left, so Cap reads the first 20 of 25 pages.")
        XCTAssertNil(AllowanceCopy.reading(pages: 8, needed: 1, readable: 8, left: 3), "one scan: nothing to warn of")
        XCTAssertNil(AllowanceCopy.reading(pages: 21, needed: 3, readable: 21, left: nil), "a paid plan")
        XCTAssertEqual(text(AllowanceCopy.reading(pages: 21, needed: 3, readable: 0, left: 0)),
                       "Free AI scans are used up until Monday. Cap still writes questions on your iPhone.")
    }

    /// The line agrees with how the reading is really cut.
    func testTheRouterCutsTheReadingTheWayTheRunWill() throws {
        let app = try StudyTestApp.make(clock: TestClock(EngineTest.date(2026, 11, 6, 10, in: EngineTest.calendar())),
                                        calendar: EngineTest.calendar())
        app.ai.modeOverride = .mock
        app.settings.cloudConsentVersion = AIConsent.currentVersion
        let pages = { (n: Int) in Array(repeating: 500, count: n) }
        app.ai.setServerQuota(TestHarness.quota("scans:3"))
        XCTAssertEqual(text(app.ai.readingAllowance(pageWords: pages(21))), "This is 21 pages, so it takes 3 of your free AI scans.")
        XCTAssertNil(app.ai.readingAllowance(pageWords: pages(9)))
        app.ai.setServerQuota(TestHarness.quota("scans:1"))
        XCTAssertEqual(text(app.ai.readingAllowance(pageWords: pages(12))), "You have 1 free AI scan left, so Cap reads the first 10 of 12 pages.")
        app.settings.ageBand = .under13
        XCTAssertNil(app.ai.readingAllowance(pageWords: pages(21)), "a child's account has no allowance to talk about")
    }

    /// The + sheet says the week's allowance once, under its list.
    func testThePlusSheetSaysTheWeekInOneLine() {
        XCTAssertEqual(text(AllowanceCopy.week(scans: 3, lectures: 1)), "This week: 3 free AI scans, 1 lecture.")
        XCTAssertEqual(text(AllowanceCopy.week(scans: 1, lectures: 2)), "This week: 1 free AI scan, 2 lectures.")
        XCTAssertEqual(text(AllowanceCopy.week(scans: 2, lectures: 0)), "This week: 2 free AI scans.")
        XCTAssertEqual(text(AllowanceCopy.week(scans: 0, lectures: 1)),
                       "Free AI scans are used up until Monday. Cap still writes questions on your iPhone.")
        XCTAssertNil(AllowanceCopy.week(scans: nil, lectures: nil), "nothing to say on a paid plan, without consent, or for a child")
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
