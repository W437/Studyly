import XCTest
@testable import Cramless

/// The four questions and where their answers land.
final class OnboardingQuizTests: XCTestCase {
    func testFourQuestionsWithTheirChoices() {
        XCTAssertEqual(QuizQuestion.allCases.count, OnboardingMachine.quizQuestions)
        XCTAssertEqual(QuizContent.goals.map(\.value), AppSettings.Goal.allCases)
        XCTAssertEqual(QuizContent.minutes.map(\.value), [5, 10, 15, 20, 30])
        XCTAssertEqual(QuizContent.notes.map(\.value), AppSettings.NotesLocation.allCases)
        XCTAssertEqual(QuizQuestion.allCases.filter(\.isMultiSelect), [.notes])
    }

    func testNotesToggleKeepsTheQuestionsOrder() {
        var s = AppSettings()
        s.toggleNotesLocation(.flashcardApps)
        s.toggleNotesLocation(.paper)
        XCTAssertEqual(s.notesLocations, [.paper, .flashcardApps])
        s.toggleNotesLocation(.paper)
        XCTAssertEqual(s.notesLocations, [.flashcardApps])
    }

    func testTheExamDateSurvivesSavingAndOldSettingsStillLoad() throws {
        var s = AppSettings()
        let exam = ISO8601DateFormatter().date(from: "2026-11-14T14:00:00Z")!
        s.nextExamDate = exam
        let data = try JSONEncoder.cramless.encode(s)
        XCTAssertEqual(try JSONDecoder.cramless.decode(AppSettings.self, from: data).nextExamDate, exam)
        let old = Data(#"{"dailyMinutes": 10}"#.utf8)
        let decoded = try JSONDecoder.cramless.decode(AppSettings.self, from: old)
        XCTAssertNil(decoded.nextExamDate)
        XCTAssertEqual(decoded.dailyMinutes, 10)
    }

    func testExamSummary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 9))!
        let in23 = calendar.date(byAdding: .day, value: 23, to: now)!
        XCTAssertTrue(QuizContent.examSummary(in23, now: now, calendar: calendar).hasSuffix("23 days away"))
        XCTAssertTrue(QuizContent.examSummary(calendar.date(byAdding: .day, value: 1, to: now)!, now: now,
                                              calendar: calendar).hasSuffix("tomorrow"))
        XCTAssertTrue(QuizContent.examSummary(now, now: now, calendar: calendar).hasSuffix("today"))
    }

    func testTheReminderMomentSaysWhenAndWhy() {
        let body = QuizContent.reminderBody(minutes: 15, time: "7:00 PM")
        XCTAssertTrue(body.contains("7:00 PM"))
        XCTAssertTrue(body.contains("15 minutes"))
        XCTAssertTrue(body.contains("quiet hours"))
    }

    func testIntroPagesMatchTheMachine() {
        XCTAssertEqual(IntroPage.all.count, OnboardingMachine.introPages)
        XCTAssertEqual(IntroPage.all.map(\.id), Array(0..<OnboardingMachine.introPages))
        XCTAssertTrue(IntroPage.all.allSatisfy { $0.sceneDescription.hasPrefix("Demo: ") })
    }

    /// What people search a study app for is on the first pages: the scan that makes cards, then the flashcards themselves
    /// (the owner noticed the intro never showed them).
    func testTheIntroShowsFlashcardsEarly() {
        XCTAssertEqual(IntroPage.all.map(\.scene), [.snap, .flashcards, .ownWords, .readiness, .plan, .askCap])
        XCTAssertTrue(IntroPage.all[0].body.contains("Flashcards"), "the scan page says what the scan makes")
        let flashcards = IntroPage.all[1]
        XCTAssertTrue(flashcards.title.contains("Flashcards"))
        XCTAssertTrue(flashcards.body.contains("Anki") && flashcards.body.contains("Quizlet"), "and that existing decks come along")
        XCTAssertTrue(flashcards.sceneDescription.contains("Got it") && flashcards.sceneDescription.contains("5 days"))
    }
}
