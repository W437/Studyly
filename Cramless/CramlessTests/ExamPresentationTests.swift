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

    func testPathSummary() {
        var path = ExamPresentation.path(history: [], plan: plan(days: [], curve: [ReadinessPoint(date: now, value: 0.5, isProjection: false),
                                                                                ReadinessPoint(date: day(9), value: 0.84, isProjection: true)]),
                                         examDate: day(9, hour: 9), now: now, calendar: cal)
        XCTAssertEqual(ExamPresentation.pathSummary(path, suggestedMinutes: 25, calendar: cal),
                       "The plan gets you to 84% by exam day. About 25 minutes on the busy days would get you closer to 90%.")
        path.targetReachedOn = day(6)
        XCTAssertTrue(ExamPresentation.pathSummary(path, suggestedMinutes: nil, calendar: cal).hasPrefix("On track for 90% by "))
        path.targetReachedOn = now
        XCTAssertEqual(ExamPresentation.pathSummary(path, suggestedMinutes: nil, calendar: cal),
                       "You're at your 90% target. The plan keeps you there.")
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

    func testExamPassOnlyForFreeUsersWithinThreeWeeks() {
        XCTAssertTrue(ExamPresentation.offersExamPass(plan: .free, phase: .ahead(days: 21)))
        XCTAssertTrue(ExamPresentation.offersExamPass(plan: .free, phase: .eve))
        XCTAssertFalse(ExamPresentation.offersExamPass(plan: .free, phase: .ahead(days: 22)))
        XCTAssertFalse(ExamPresentation.offersExamPass(plan: .pro, phase: .ahead(days: 3)))
        XCTAssertFalse(ExamPresentation.offersExamPass(plan: .pass, phase: .ahead(days: 3)))
        XCTAssertFalse(ExamPresentation.offersExamPass(plan: .free, phase: .past(days: 2)))
    }

    func testGradeComparisonCopy() {
        let lines = ExamPresentation.gradeComparison(projected: 0.87, got: 0.91, calibratedNow: false)
        XCTAssertEqual(lines.headline, "Capling projected 87%, you got 91%.")
        XCTAssertEqual(lines.note, "Projections will calibrate as you log more grades.")
        XCTAssertEqual(ExamPresentation.gradeComparison(projected: 0.8, got: 0.7, calibratedNow: true).note,
                       "Projections are now calibrated to your grades.")
    }
}
