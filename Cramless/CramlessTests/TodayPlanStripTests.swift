import XCTest
@testable import Cramless

/// "Your plan": the seven days of the strip across every exam (`TodayPlanStrip.make`): the past as it was (never red), today, each
/// exam's eve and day, two exams on one day, easy days, and with no exams the goal every day.
final class TodayPlanStripTests: XCTestCase {
    private let cal = EngineTest.calendar()
    /// Friday 6 Nov 2026, 14:00.
    private lazy var now = EngineTest.date(2026, 11, 6, 14, in: cal)
    private lazy var today = cal.dayNumber(for: now)

    private func record(_ offset: Int, sessions: Int = 0, frozen: Bool = false, repaired: Bool = false) -> DaySnapshot {
        let day = cal.startOfDay(dayNumber: today + offset)
        return DaySnapshot(dayKey: cal.dayKey(for: day), day: day, studySeconds: sessions > 0 ? 600 : 0,
                           itemsReviewed: sessions > 0 ? 12 : 0, sessions: sessions, frozen: frozen, repaired: repaired)
    }

    private func planDay(_ offset: Int, _ kind: PlanDay.Kind, session: Int = 15) -> PlanDay {
        PlanDay(date: cal.startOfDay(dayNumber: today + offset), dayNumber: today + offset, kind: kind, minutes: session,
                sessionMinutes: kind == .exam ? 0 : session, newItems: 0, reviews: 0, isToday: offset == 0,
                isEasyDay: false, offset: offset)
    }

    /// An exam `days` away: study days up to its eve, then the eve and the day.
    private func plan(_ title: String, examIn days: Int, session: Int = 15) -> TodayPlanStrip.ExamPlan {
        var list: [PlanDay] = []
        for offset in 0..<days {
            list.append(planDay(offset, offset == days - 1 ? .examEve : .study, session: offset == days - 1 ? 10 : session))
        }
        list.append(planDay(days, .exam))
        return TodayPlanStrip.ExamPlan(title: title, days: list)
    }

    private func make(_ plans: [TodayPlanStrip.ExamPlan], past: [DaySnapshot] = [], todayMinutes: Int = 15, done: Bool = false,
                      goal: Int = 15, easy: [Int] = []) -> [TodayPlanDay] {
        TodayPlanStrip.make(today: now, plans: plans, past: past, todayMinutes: todayMinutes, todayDone: done, goal: goal,
                            easyDays: easy, calendar: cal)
    }

    func testSevenDaysTwoBackTodayAndFourAhead() {
        let week = make([])
        XCTAssertEqual(week.map(\.offset), [-2, -1, 0, 1, 2, 3, 4])
        XCTAssertEqual(week.filter(\.isToday).count, 1)
        XCTAssertEqual(week[2].date, cal.startOfDay(for: now))
    }

    func testThePastIsACheckASnowflakeOrAHollowCircleNeverRed() {
        let week = make([], past: [record(-2, sessions: 1), record(-1, frozen: true)])
        XCTAssertEqual(week[0].mark, .studied)
        XCTAssertEqual(week[1].mark, .frozen)
        XCTAssertEqual(make([], past: [record(-1, repaired: true)])[1].mark, .studied, "a repair counts as studied")
        XCTAssertEqual(make([])[0].mark, .missed, "nothing that day: a hollow circle")
    }

    func testTodayIsItsMinutesOrACheckOnceTheGoalIsMet() {
        XCTAssertEqual(make([], todayMinutes: 9)[2].mark, .minutes(9))
        XCTAssertEqual(make([], done: true)[2].mark, .done)
    }

    func testAnExamInsideTheWindowHasItsEveAndItsDay() {
        let week = make([plan("Chem 110 Quiz", examIn: 2)])
        XCTAssertEqual(week[3].mark, .eve(minutes: 10))
        XCTAssertEqual(week[3].examTitles, ["Chem 110 Quiz"])
        XCTAssertEqual(week[4].mark, .exam(count: 1))
        XCTAssertEqual(week[4].examTitles, ["Chem 110 Quiz"])
        XCTAssertEqual(week[5].mark, .minutes(15), "after the exam: the goal")
    }

    func testTheEveIsTodayWhenTheExamIsTomorrow() {
        let week = make([plan("Chem 110 Quiz", examIn: 1)])
        XCTAssertEqual(week[2].mark, .eve(minutes: 10))
        XCTAssertEqual(make([plan("Chem 110 Quiz", examIn: 1)], done: true)[2].mark, .done)
        XCTAssertEqual(week[3].mark, .exam(count: 1))
    }

    func testTwoExamsOnOneDayShowTwo() {
        let week = make([plan("Chem 110 Quiz", examIn: 3), plan("Bio 101 Quiz", examIn: 3)])
        XCTAssertEqual(week[5].mark, .exam(count: 2))
        XCTAssertEqual(week[5].examTitles, ["Chem 110 Quiz", "Bio 101 Quiz"])
        XCTAssertEqual(week[4].mark, .eve(minutes: 10))
    }

    func testAnEasyDayPlansHalfTheGoalUnlessAnExamNeedsMore() {
        let tomorrow = Calendar.weekday(dayNumber: today + 1)
        XCTAssertEqual(make([], easy: [tomorrow])[3].mark, .minutes(8), "half of 15, rounded")
        XCTAssertEqual(make([], easy: [tomorrow])[3].isEasy, true)
        XCTAssertEqual(make([plan("Final", examIn: 10, session: 22)], easy: [tomorrow])[3].mark, .minutes(22),
                       "the busiest exam's session when it needs more")
    }

    func testWithNoExamsEveryDayAheadIsTheGoal() {
        let week = make([], goal: 20)
        for day in week where day.offset > 0 { XCTAssertEqual(day.mark, .minutes(20)) }
    }
}
