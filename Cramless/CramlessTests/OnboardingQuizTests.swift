import XCTest
@testable import Cramless

/// Onboarding's one question (the exam's date), the plan screen's words, and the settings they leave behind.
final class OnboardingQuizTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    func testTheDateQuestionNamesTheCourse() {
        XCTAssertEqual(QuizContent.examQuestion(courseName: "Bio 101"), "When's your Bio 101 exam?")
        XCTAssertEqual(QuizContent.examQuestion(courseName: "  "), "When's your next exam?")
        XCTAssertEqual(QuizContent.examQuestion(courseName: nil), "When's your next exam?")
    }

    /// The minutes are plain numbers: no labels like "Serious" or "All in".
    func testTheMinutesArePlain() {
        XCTAssertEqual(QuizContent.minuteOptions, [5, 10, 15, 20, 30])
    }

    func testTheExamDateSurvivesSavingAndOldSettingsStillLoad() throws {
        var s = AppSettings()
        let exam = ISO8601DateFormatter().date(from: "2026-11-14T14:00:00Z")!
        s.nextExamDate = exam
        let data = try JSONEncoder.cramless.encode(s)
        XCTAssertEqual(try JSONDecoder.cramless.decode(AppSettings.self, from: data).nextExamDate, exam)
        // Settings saved before the goal and "where do your notes live" questions were removed still load.
        let old = Data(#"{"dailyMinutes": 10, "goal": "aceExams", "notesLocations": ["paper", "slides"]}"#.utf8)
        let decoded = try JSONDecoder.cramless.decode(AppSettings.self, from: old)
        XCTAssertNil(decoded.nextExamDate)
        XCTAssertEqual(decoded.dailyMinutes, 10)
        let saved = try XCTUnwrap(String(data: JSONEncoder.cramless.encode(decoded), encoding: .utf8))
        XCTAssertFalse(saved.contains("notesLocations") || saved.contains("\"goal\""), "nothing stores them any more")
    }

    func testExamSummary() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 9))!
        let in23 = calendar.date(byAdding: .day, value: 23, to: now)!
        XCTAssertTrue(QuizContent.examSummary(in23, now: now, calendar: calendar).hasSuffix("23 days away"))
        XCTAssertTrue(QuizContent.examSummary(calendar.date(byAdding: .day, value: 1, to: now)!, now: now,
                                              calendar: calendar).hasSuffix("tomorrow"))
        XCTAssertTrue(QuizContent.examSummary(now, now: now, calendar: calendar).hasSuffix("today"))
    }

    func testThePlanSaysItInOneLine() {
        XCTAssertEqual(QuizContent.examLine(title: "Bio 101 exam", days: 23), "Bio 101 exam · 23 days")
        XCTAssertEqual(QuizContent.examLine(title: "Bio 101 exam", days: 0), "Bio 101 exam · today")

        let reached = calendar.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: 12))!
        let line = QuizContent.planLine(minutes: 15, target: 0.9, reachedOn: reached, projected: 0.94)
        XCTAssertTrue(line.hasPrefix("15 minutes a day gets you to 90% by "), line)
        XCTAssertFalse(line.contains("94%"), "the date the target is reached, not the projection")
        let short = QuizContent.planLine(minutes: 10, target: 0.9, reachedOn: nil, projected: 0.72)
        XCTAssertEqual(short, "10 minutes a day gets you to 72% by exam day.")
        let none = QuizContent.noExamLine(minutes: 15)
        XCTAssertTrue(none.hasPrefix("15 minutes a day"))
        XCTAssertFalse(none.contains("%"), "with no exam there is no readiness to promise")
    }

    /// The demos left onboarding; they stay (DEBUG) for films and store art.
    func testTheDemosAreKeptForFilms() {
        XCTAssertEqual(IntroPage.all.map(\.scene), [.snap, .flashcards, .ownWords, .readiness, .plan, .askCap])
        XCTAssertEqual(IntroPage.all.map(\.id), Array(0..<6))
        XCTAssertTrue(IntroPage.all.allSatisfy { $0.sceneDescription.hasPrefix("Demo: ") })
        XCTAssertFalse(IntroPage.all[2].body.contains("flip-and-guess"), "it came right after the flashcards page")
    }
}
