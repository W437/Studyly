import Foundation
import XCTest
@testable import Cramless

/// How the exam screen arranges the engine's values: the path chart, the week strip, the exam's phase, the Exam
/// Pass offer and the grade comparison.
final class ExamPresentationTests: XCTestCase {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    lazy var now = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 18))!

    private func day(_ offset: Int, hour: Int = 0) -> Date {
        cal.adding(days: offset, to: cal.startOfDay(for: now)).addingTimeInterval(Double(hour) * 3600)
    }

    private func plan(days: [PlanDay], curve: [ReadinessPoint], target: Double = 0.9, reached: Date? = nil) -> StudyPlan {
        StudyPlan(examID: UUID(), target: target, daysLeft: days.count - 1, dailyMinutes: 15, itemsInScope: 10, newItems: 0,
                  reviewsPlanned: 0, days: days, lastIntroDay: nil, examEve: nil, curve: curve,
                  projectedReadiness: curve.last?.value ?? 0, targetReachedOn: reached, suggestedMinutes: nil)
    }

    private func planDay(_ offset: Int, _ kind: PlanDay.Kind, minutes: Int = 10) -> PlanDay {
        PlanDay(date: day(offset), dayNumber: cal.dayNumber(for: day(offset)), kind: kind, minutes: minutes,
                sessionMinutes: max(minutes, 15), newItems: 0, reviews: 0, isToday: offset == 0, isEasyDay: false)
    }

    // MARK: Path

    func testPathJoinsHistoryAndProjectionAtNow() {
        let history = (0..<14).map { ReadinessPoint(date: day($0 - 13), value: 0.4 + Double($0) * 0.01, isProjection: false) }
        let curve = [ReadinessPoint(date: now, value: 0.53, isProjection: false)]
            + (1...5).map { ReadinessPoint(date: day($0), value: 0.53 + Double($0) * 0.05, isProjection: true) }
        let path = ExamPresentation.path(history: history, plan: plan(days: [], curve: curve), examDate: day(5, hour: 9),
                                         now: now, calendar: cal)
        XCTAssertEqual(path.history.last?.date, now)
        XCTAssertEqual(path.history.last?.value, 0.53, "the history ends on the plan's own now")
        XCTAssertEqual(path.history.count, 14, "today's end-of-day point gives way to now")
        XCTAssertEqual(path.projection.first?.date, now)
        XCTAssertEqual(path.projection.count, 6)
        XCTAssertTrue(path.projection.allSatisfy(\.isProjection))
        XCTAssertFalse(path.isCut)
        XCTAssertEqual(path.end, day(5, hour: 9))
        XCTAssertEqual(path.start, day(-12), "each past day is drawn where it ended")
        XCTAssertEqual(path.nearest(to: day(2).addingTimeInterval(3600))?.date, day(2))
    }

    func testAFarExamIsCutSoTheHistoryStaysReadable() {
        let curve = [ReadinessPoint(date: now, value: 0.16, isProjection: false)]
            + (1...196).map { ReadinessPoint(date: day($0), value: 0.16 + Double($0) * 0.003, isProjection: true) }
        let path = ExamPresentation.path(history: [], plan: plan(days: [], curve: curve), examDate: day(196, hour: 8),
                                         now: now, calendar: cal, maxDays: 56)
        XCTAssertTrue(path.isCut)
        XCTAssertEqual(path.end, cal.adding(days: 56, to: now))
        XCTAssertTrue(path.projection.allSatisfy { $0.date <= path.end })
        XCTAssertEqual(path.projectedAtExam, curve.last!.value, accuracy: 1e-9, "the exam-day projection is still the plan's")
    }

    // MARK: Week strip

    func testAMissedYesterdayLeadsTheStripAndTodayAbsorbsIt() {
        let days = [planDay(0, .study, minutes: 22), planDay(1, .study), planDay(2, .rest, minutes: 0), planDay(3, .study),
                    planDay(4, .study), planDay(5, .study), planDay(6, .examEve, minutes: 8), planDay(7, .exam, minutes: 0)]
        let p = plan(days: days, curve: [])
        let missed = DaySnapshot(dayKey: cal.dayKey(for: day(-1, hour: 12)), day: day(-1), sessions: 0)
        let strip = ExamPresentation.weekStrip(plan: p, yesterday: missed, examCreatedAt: day(-20), now: now, calendar: cal)
        XCTAssertEqual(strip.count, 7)
        XCTAssertEqual(strip.first?.kind, .missed)
        XCTAssertEqual(strip.first?.date, day(-1))
        XCTAssertTrue(strip[1].isToday)
        XCTAssertTrue(strip[1].absorbsMissedDay)
        XCTAssertFalse(strip[2].absorbsMissedDay)
        XCTAssertEqual(strip.map(\.kind), [.missed, .study, .study, .rest, .study, .study, .study])

        let frozen = DaySnapshot(dayKey: missed.dayKey, day: day(-1), sessions: 0, frozen: true)
        XCTAssertEqual(ExamPresentation.weekStrip(plan: p, yesterday: frozen, examCreatedAt: day(-20), now: now, calendar: cal).first?.kind,
                       .frozen)
    }

    func testNoMissedDayWhenYesterdayWasStudiedOrTheExamIsNew() {
        let days = [planDay(0, .study), planDay(1, .examEve, minutes: 6), planDay(2, .exam, minutes: 0)]
        let p = plan(days: days, curve: [])
        let studied = DaySnapshot(dayKey: "k", day: day(-1), studySeconds: 600, sessions: 1)
        let strip = ExamPresentation.weekStrip(plan: p, yesterday: studied, examCreatedAt: day(-20), now: now, calendar: cal)
        XCTAssertEqual(strip.map(\.kind), [.study, .eve, .exam])
        XCTAssertFalse(strip.contains { $0.absorbsMissedDay })
        let fresh = ExamPresentation.weekStrip(plan: p, yesterday: nil, examCreatedAt: now, now: now, calendar: cal)
        XCTAssertEqual(fresh.map(\.kind), [.study, .eve, .exam], "an exam set today has no yesterday to miss")
    }

    // MARK: Phase, pass and grade

    func testPhase() {
        XCTAssertEqual(ExamPresentation.phase(examDate: day(23, hour: 9), now: now, calendar: cal), .ahead(days: 23))
        XCTAssertEqual(ExamPresentation.phase(examDate: day(1, hour: 9), now: now, calendar: cal), .eve)
        XCTAssertEqual(ExamPresentation.phase(examDate: day(0, hour: 21), now: now, calendar: cal), .today)
        XCTAssertEqual(ExamPresentation.phase(examDate: day(0, hour: 9), now: now, calendar: cal), .past(days: 0))
        XCTAssertEqual(ExamPresentation.phase(examDate: day(-3, hour: 9), now: now, calendar: cal), .past(days: 3))
    }

    func testExamPassOnlyForFreeUsersEightToTwentyOneDaysOut() {
        func offers(_ days: Int, plan: Plan = .free, others: [Int] = []) -> Bool {
            ExamPresentation.offersExamPass(plan: plan, examDate: day(days, hour: 9),
                                            examDates: others.map { day($0, hour: 9) }, now: now, calendar: cal)
        }
        XCTAssertTrue(offers(21))
        XCTAssertTrue(offers(8))
        XCTAssertFalse(offers(22), "too early")
        XCTAssertFalse(offers(7), "exam week")
        XCTAssertFalse(offers(1), "the eve")
        XCTAssertFalse(offers(0), "the day")
        XCTAssertFalse(offers(-2), "past")
        XCTAssertFalse(offers(15, plan: .pro))
        XCTAssertFalse(offers(15, plan: .pass))
        XCTAssertFalse(offers(15, others: [3]), "another exam in 3 days keeps it quiet")
        XCTAssertTrue(offers(15, others: [40]))
        XCTAssertFalse(offers(30, others: [10]), "this exam is past the window, though another is in it")
    }

    // MARK: What the questions cover

    private func covering(_ title: String, words: Int, covered: Int) -> Coverage.SourceCoverage {
        Coverage.SourceCoverage(sourceID: UUID(), title: title, words: words, coveredWords: covered, sections: 10, uncovered: [])
    }

    func testTheCoverageNoteSaysHowMuchOfTheMaterialTheQuestionsReach() throws {
        // 1,850 of 6,000 words: 31%, with the long reading (17%) holding all that is left.
        let summary = try XCTUnwrap(Coverage.summary([covering("Palsgraf", words: 5000, covered: 850),
                                                       covering("Reading 2", words: 1000, covered: 1000)]))
        let note = ExamPresentation.coverageNote(summary, canAddMore: true)
        XCTAssertEqual(note.sentence, "Your questions cover 31% of your material.")
        XCTAssertEqual(note.mainGap, "Palsgraf: 17%")
        XCTAssertTrue(note.isThin, "under half is amber")
        XCTAssertTrue(note.offersMore)

        // One source says it in the sentence alone.
        let single = try XCTUnwrap(Coverage.summary([covering("Palsgraf", words: 5800, covered: 986)]))
        XCTAssertEqual(ExamPresentation.coverageNote(single, canAddMore: true).sentence, "Your questions cover 17% of your material.")
        XCTAssertNil(ExamPresentation.coverageNote(single, canAddMore: true).mainGap)
        // Nothing to write questions from (only a lecture is left): no button.
        XCTAssertFalse(ExamPresentation.coverageNote(summary, canAddMore: false).offersMore)
    }

    func testTheNoteTurnsAmberBelowHalfAndStopsOfferingWhenNearlyAllIsCovered() throws {
        func note(_ covered: Int) throws -> ExamPresentation.CoverageNote {
            ExamPresentation.coverageNote(try XCTUnwrap(Coverage.summary([covering("Reading", words: 1000, covered: covered)])), canAddMore: true)
        }
        XCTAssertTrue(try note(494).isThin)
        XCTAssertFalse(try note(495).isThin, "it reads 50%, which is not amber")
        XCTAssertTrue(try note(500).offersMore)
        XCTAssertTrue(try note(894).offersMore)
        XCTAssertFalse(try note(895).offersMore, "90% needs no nudge")
        XCTAssertEqual(try note(1000).sentence, "Your questions cover 100% of your material.")
        XCTAssertFalse(try note(1000).offersMore)
    }

    func testTheSourceScreensLine() {
        XCTAssertEqual(LibraryFormat.coverageLine(share: 0.17, kind: .pdf), "Questions cover 17% of this reading")
        XCTAssertEqual(LibraryFormat.coverageLine(share: 0.5, kind: .text), "Questions cover 50% of this reading")
        XCTAssertEqual(LibraryFormat.coverageLine(share: 1, kind: .lecture), "Questions cover 100% of this lecture")
    }

    /// After the exam, the grade sits beside readiness on the day (never beside a projection the student was never shown).
    func testPastExamComparesReadinessOnTheDay() {
        let lines = ExamPresentation.gradeComparison(onTheDay: 0.74, got: 0.81, calibratingExams: 1)
        XCTAssertEqual(lines.headline, "You got 81%, at 74% ready on the day.")
        XCTAssertEqual(lines.note, "Log one more grade and Capling can project yours.")
        XCTAssertEqual(ExamPresentation.gradeComparison(onTheDay: 0.8, got: 0.7, calibratingExams: 2).note,
                       "Capling now projects your grades from your readiness.")
        XCTAssertEqual(ExamPresentation.gradeComparison(onTheDay: nil, got: 0.7, calibratingExams: 0).headline, "You got 70%.")
        XCTAssertEqual(ExamPresentation.logGradeInvite(onTheDay: 0.74),
                       "You were 74% ready on the day. Log your grade and Capling learns how your readiness turns into grades.")
        XCTAssertEqual(ExamPresentation.logGradeInvite(onTheDay: nil),
                       "Log your grade and Capling learns how your readiness turns into grades.")
    }
}
