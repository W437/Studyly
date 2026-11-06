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
                isEasyDay: false, offset: offset, seconds: Double(session * 60))
    }

    /// An exam `days` away: study days up to its eve, then the eve and the day.
    private func plan(_ title: String, examIn days: Int, session: Int = 15, eve: Int = 10) -> TodayPlanStrip.ExamPlan {
        var list: [PlanDay] = []
        for offset in 0..<days {
            list.append(planDay(offset, offset == days - 1 ? .examEve : .study, session: offset == days - 1 ? eve : session))
        }
        list.append(planDay(days, .exam))
        return TodayPlanStrip.ExamPlan(title: title, days: list)
    }

    private func make(_ plans: [TodayPlanStrip.ExamPlan], past: [DaySnapshot] = [], todayMinutes: Int = 15, done: Bool = false,
                      goal: Int = 15, easy: [Int] = [], tonight: Int? = nil, tomorrowEve: Int? = nil) -> [TodayPlanDay] {
        TodayPlanStrip.make(today: now, plans: plans, past: past, todayMinutes: todayMinutes, todayDone: done, goal: goal,
                            easyDays: easy, tonightMinutes: tonight, tomorrowEveMinutes: tomorrowEve, calendar: cal)
    }

    /// One number: an eve tomorrow reads the session its button will start, like tonight's; later eves can only be the plan's estimate.
    func testAnEveTomorrowSaysWhatItsButtonWillSay() {
        let quiz = plan("Chem 110 Quiz", examIn: 2, eve: 1)
        XCTAssertEqual(make([quiz], tomorrowEve: 2)[3].mark, .eve(minutes: 2))
        XCTAssertEqual(make([quiz], tomorrowEve: 0)[3].mark, .eve(minutes: 0), "nothing to review")
        XCTAssertEqual(make([quiz])[3].mark, .eve(minutes: 1), "none built: the plan's")
        XCTAssertEqual(make([plan("Chem 110 Quiz", examIn: 3, eve: 1)], tomorrowEve: 2)[4].mark, .eve(minutes: 1), "that eve isn't tomorrow")
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

    /// The strip says what the exam page's plan says about an eve: its minutes, at least 1, never a constant.
    func testAnEveAheadShowsThePlansMinutes() {
        XCTAssertEqual(make([plan("Chem 110 Quiz", examIn: 2, eve: 4)])[3].mark, .eve(minutes: 4))
        XCTAssertEqual(make([plan("Chem 110 Quiz", examIn: 2, eve: 0)])[3].mark, .eve(minutes: 1), "at least 1")
        var seconds = plan("Chem 110 Quiz", examIn: 2)
        seconds.days[1].seconds = 70
        XCTAssertEqual(make([seconds])[3].mark, .eve(minutes: seconds.days[1].shownMinutes))
        XCTAssertEqual(make([seconds])[3].mark, .eve(minutes: 1), "as the plan's stop rounds it")
        XCTAssertEqual(make([plan("A", examIn: 3, eve: 4), plan("B", examIn: 3, eve: 7)])[4].mark, .eve(minutes: 11), "two exams share one evening")
    }

    /// Tonight, the session that is really built says the minutes (the card's button and the plan's "Tonight" say the same).
    func testTonightShowsTheBuiltSessionsMinutes() {
        let tonight = plan("Chem 110 Quiz", examIn: 1, eve: 9)
        XCTAssertEqual(make([tonight], tonight: 4)[2].mark, .eve(minutes: 4))
        XCTAssertEqual(make([tonight])[2].mark, .eve(minutes: 9), "no session passed: the plan's")
        let nothing = make([tonight], tonight: 0)[2]
        XCTAssertEqual(nothing.mark, .eve(minutes: 0))
        XCTAssertEqual(TodayCopy.stripCaption(nothing), "", "nothing to review tonight: no minutes to show")
        XCTAssertEqual(TodayCopy.stripDay(nothing, calendar: cal), "Today: the night before Chem 110 Quiz")
        let saturday = make([plan("Chem 110 Quiz", examIn: 2, eve: 1)])[3]
        XCTAssertEqual(TodayCopy.stripCaption(saturday), "1m")
        XCTAssertTrue(TodayCopy.stripDay(saturday, calendar: cal).hasSuffix("the night before Chem 110 Quiz, 1 minute"),
                      TodayCopy.stripDay(saturday, calendar: cal))
    }

    func testTwoExamsOnOneDayShowTwo() {
        let week = make([plan("Chem 110 Quiz", examIn: 3), plan("Bio 101 Quiz", examIn: 3)])
        XCTAssertEqual(week[5].mark, .exam(count: 2))
        XCTAssertEqual(week[5].examTitles, ["Chem 110 Quiz", "Bio 101 Quiz"])
        XCTAssertEqual(week[4].mark, .eve(minutes: 20), "each with its own 10")
        XCTAssertEqual(week[4].examTitles, ["Chem 110 Quiz", "Bio 101 Quiz"])
    }

    /// Today says the session really planned, whatever yesterday's strip said of it; the days ahead keep the goal as a floor.
    func testTodayIsTheRealSessionAndTheDaysAheadKeepTheGoalAsAFloor() {
        let week = make([plan("Final", examIn: 10, session: 6)], todayMinutes: 11, goal: 25)
        XCTAssertEqual(week[2].mark, .minutes(11))
        XCTAssertEqual(week[3].mark, .minutes(25))
        let nothing = make([], todayMinutes: 0)[2]
        XCTAssertEqual(TodayCopy.stripCaption(nothing), "", "no session yet: no minutes")
        XCTAssertEqual(TodayCopy.stripDay(nothing, calendar: cal), "Today: nothing planned")
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

    // MARK: Minutes moved

    func testALongDaysMinutesShowOnTheDaysAroundIt() {
        let moved = TodayPlanStrip.make(today: now, plans: [plan("Midterm", examIn: 9)], past: [], todayMinutes: 15, todayDone: false, goal: 15,
                                        easyDays: [], boosts: [1: 5, 2: -10, 3: 5], calendar: cal)
        func minutes(_ offset: Int) -> TodayPlanDay.Mark? { moved.first { $0.offset == offset }?.mark }
        XCTAssertEqual(minutes(2), .minutes(15), "the plan day's own session still says what it was built with")
        XCTAssertEqual(minutes(1), .minutes(20))
        XCTAssertEqual(minutes(3), .minutes(20))
        // A plan built with the move has the shorter day in it.
        let shorter = plan("Midterm", examIn: 9)
        var days = shorter.days
        days[2] = planDay(2, .study, session: 5)
        let built = TodayPlanStrip.make(today: now, plans: [TodayPlanStrip.ExamPlan(title: "Midterm", days: days)], past: [], todayMinutes: 15, todayDone: false,
                                        goal: 15, easyDays: [], boosts: [2: -10], calendar: cal)
        XCTAssertEqual(built.first { $0.offset == 2 }?.mark, .minutes(5))
    }

    func testWithNoExamPlanTheGoalMovesToo() {
        let week = TodayPlanStrip.make(today: now, plans: [], past: [], todayMinutes: 15, todayDone: false, goal: 15, easyDays: [], boosts: [2: -10],
                                       calendar: cal)
        XCTAssertEqual(week.first { $0.offset == 2 }?.mark, .minutes(5))
        XCTAssertEqual(week.first { $0.offset == 1 }?.mark, .minutes(15))
    }
}
