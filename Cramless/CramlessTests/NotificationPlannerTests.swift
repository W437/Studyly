import XCTest
@testable import Cramless

/// The notification plan: what goes out, when, and in what words.
final class NotificationPlannerTests: XCTestCase {
    private let cal = WidgetTestSupport.calendar
    private let now = WidgetTestSupport.now   // Thu Oct 22, 2026, 09:00
    private let chemID = UUID()
    private let bioID = UUID()

    /// The demo world: 15 minutes planned, 18 due, 6 new, 2 weak; a 12-day streak not yet extended today; the Chem
    /// quiz on Saturday at 10:00 and the Bio midterm in 23 days; reminder at 19:00, quiet hours 22:00–07:00.
    private func input(_ change: (inout NotificationPlanner.Input) -> Void = { _ in }) -> NotificationPlanner.Input {
        var today = TodaySummary(minutesGoal: 15)
        today.plannedMinutes = 15
        today.reviews = 18
        today.newItems = 6
        today.weakSpots = 2
        today.sessionReady = true
        var i = NotificationPlanner.Input(
            now: now, reminderMinutes: 19 * 60, quietStart: 22 * 60, quietEnd: 7 * 60, goalMinutes: 15, today: today,
            streak: StreakState(current: 12, best: 12, studiedToday: false, freezesAvailable: 1),
            exams: [
                .init(id: bioID, title: "Bio 101 Midterm", courseName: "Bio 101", date: WidgetTestSupport.date(2026, 11, 14, 9)),
                .init(id: chemID, title: "Chem 110 Quiz", courseName: "Chem 110", date: WidgetTestSupport.date(2026, 10, 24, 10)),
            ])
        change(&i)
        return i
    }

    private func plan(_ change: (inout NotificationPlanner.Input) -> Void = { _ in }) -> [NotificationPlanner.Planned] {
        NotificationPlanner.plan(input(change), calendar: cal)
    }

    private func hm(_ date: Date) -> String {
        let c = cal.dateComponents([.month, .day, .hour, .minute], from: date)
        return String(format: "%02d-%02d %02d:%02d", c.month!, c.day!, c.hour!, c.minute!)
    }

    // MARK: The week

    func testTheDemoWeek() {
        let p = plan()
        XCTAssertEqual(p.map { "\(hm($0.date)) \($0.kind.rawValue)" }, [
            "10-22 19:00 daily",
            "10-22 20:30 streak",
            "10-23 20:00 examEve",
            "10-24 19:00 daily",
            "10-25 19:00 daily",
            "10-26 19:00 daily",
            "10-27 19:00 daily",
            "10-28 19:00 daily",
        ])
        XCTAssertEqual(p[0].body, "15 minutes keeps Chem 110 on track. 18 cards are due.")
        XCTAssertEqual(p[0].url, CramlessLink.session)
        XCTAssertEqual(p[1].body, "15 minutes tonight and your 12-day streak is safe.")
        XCTAssertEqual(p[2].body, "Chem 110 tomorrow. 10 minutes of weak spots, then sleep.")
        XCTAssertEqual(DeepLinks.parse(p[2].url),
                       .session(kind: .examEve, examID: chemID, confusionID: nil, courseID: nil))
        XCTAssertEqual(p[3].body, "15 minutes keeps Bio 101 on track. Bio 101 Midterm is in 21 days.",
                       "the quiz is over by 19:00 on Saturday, so the reminder is about Bio")
        XCTAssertTrue(p.allSatisfy { $0.id.hasPrefix("capling.") })
        XCTAssertEqual(Set(p.map(\.id)).count, p.count, "identifiers are unique")
    }

    func testAWeekBeforeReplacesThatDaysReminder() {
        let p = plan { $0.exams = [.init(id: self.bioID, title: "Bio 101 Midterm", courseName: "Bio 101",
                                        date: WidgetTestSupport.date(2026, 10, 30, 9))] }
        let thursday = p.filter { cal.isDate($0.date, inSameDayAs: WidgetTestSupport.date(2026, 10, 23)) }
        XCTAssertEqual(thursday.map(\.kind), [.examWeek])
        XCTAssertEqual(thursday.first.map { hm($0.date) }, "10-23 19:00")
        XCTAssertEqual(thursday.first?.body, "Bio 101 Midterm is a week away. Your plan: 15 minutes a day, weak spots first.")
        XCTAssertEqual(thursday.first?.url, CramlessLink.exam(bioID))
        XCTAssertEqual(thursday.first?.id, "capling.week.\(bioID.uuidString)")
    }

    func testExamsOnTheSameDayShareOneEveningNote() {
        let p = plan {
            $0.exams = [
                .init(id: UUID(), title: "Chem 110 Quiz", courseName: "Chem 110", date: WidgetTestSupport.date(2026, 10, 24, 10)),
                .init(id: UUID(), title: "Bio 101 Lab Practical", courseName: "Bio 101", date: WidgetTestSupport.date(2026, 10, 24, 14)),
            ]
        }
        let eves = p.filter { $0.kind == .examEve }
        XCTAssertEqual(eves.count, 1)
        XCTAssertEqual(eves.first?.body, "Chem 110 and Bio 101 tomorrow. 10 minutes of weak spots, then sleep.")
        XCTAssertEqual(eves.first?.url, CramlessLink.session(kind: "examEve"))
    }

    // MARK: Today

    func testNothingTodayOnceTodayIsDone() {
        let p = plan {
            $0.today.studiedToday = true
            $0.streak.studiedToday = true
            $0.streak.current = 13
        }
        XCTAssertFalse(p.contains { cal.isDate($0.date, inSameDayAs: self.now) }, "no reminder or nudge today")
        let friday = p.filter { cal.isDate($0.date, inSameDayAs: WidgetTestSupport.date(2026, 10, 23)) }
        XCTAssertEqual(friday.map(\.kind), [.examEve], "the eve note replaces the reminder; the nudge is too close to it")
        let p2 = plan {
            $0.today.studiedToday = true
            $0.streak.current = 13
            $0.exams = []
        }
        let tomorrow = p2.filter { cal.isDate($0.date, inSameDayAs: WidgetTestSupport.date(2026, 10, 23)) }
        XCTAssertEqual(tomorrow.map(\.kind), [.daily, .streak])
        XCTAssertEqual(tomorrow.last?.body, "15 minutes tonight and your 13-day streak is safe.")
    }

    func testNoStreakNudgeBelowThreeDaysOrWithRemindersOff() {
        XCTAssertFalse(plan { $0.streak.current = 2 }.contains { $0.kind == .streak })
        let off = plan { $0.reminderMinutes = nil }
        XCTAssertFalse(off.contains { $0.kind == .streak || $0.kind == .daily })
        XCTAssertEqual(off.map { "\(hm($0.date)) \($0.kind.rawValue)" }, ["10-23 20:00 examEve"],
                       "exam notes still come: they're about a date the person set")
    }

    func testNothingToStudyMeansNoReminderToday() {
        let p = plan {
            $0.today = TodaySummary(minutesGoal: 15)
            $0.exams = []
            $0.streak = StreakState()
        }
        XCTAssertTrue(p.isEmpty, "no material, no exams, no history: nothing to remind about")
        let caughtUp = plan {
            $0.today = TodaySummary(minutesGoal: 15)
            $0.exams = []
        }
        XCTAssertFalse(caughtUp.contains { cal.isDate($0.date, inSameDayAs: self.now) },
                       "nothing to study today: no reminder and no streak nudge about it")
        XCTAssertEqual(caughtUp.first { $0.kind == .daily }?.body, "Your 15-minute session is ready when you are.")
    }

    func testGenericCopyWhenTheDataIsThin() {
        let p = plan {
            $0.exams = []
            $0.today.reviews = 0
            $0.today.newItems = 0
        }
        XCTAssertEqual(p.first?.body, "Your 15-minute session is ready when you are.")
        let newOnly = plan {
            $0.exams = []
            $0.today.reviews = 0
        }
        XCTAssertEqual(newOnly.first?.body, "Your 15-minute session has 6 new questions.")
        let dueOnly = plan {
            $0.exams = []
            $0.today.reviews = 1
        }
        XCTAssertEqual(dueOnly.first?.body, "1 card is due. Your 15-minute session is ready.")
    }

    // MARK: Time

    func testRemindersMoveOutOfQuietHours() {
        XCTAssertEqual(NotificationPlanner.movedOutOfQuietHours(23 * 60, start: 22 * 60, end: 7 * 60), 21 * 60 + 30)
        XCTAssertEqual(NotificationPlanner.movedOutOfQuietHours(6 * 60, start: 22 * 60, end: 7 * 60), 7 * 60)
        XCTAssertEqual(NotificationPlanner.movedOutOfQuietHours(19 * 60, start: 22 * 60, end: 7 * 60), 19 * 60)
        XCTAssertEqual(NotificationPlanner.movedOutOfQuietHours(14 * 60, start: 13 * 60, end: 15 * 60), 15 * 60,
                       "the end is closer than half an hour before the start")
        XCTAssertEqual(NotificationPlanner.movedOutOfQuietHours(13 * 60 + 10, start: 13 * 60, end: 15 * 60), 12 * 60 + 30)
        XCTAssertEqual(NotificationPlanner.movedOutOfQuietHours(10, start: 0, end: 6 * 60), 6 * 60,
                       "never before midnight")
        XCTAssertEqual(NotificationPlanner.movedOutOfQuietHours(19 * 60, start: 22 * 60, end: 22 * 60), 19 * 60,
                       "equal start and end means no quiet hours")
        let late = plan { $0.reminderMinutes = 23 * 60 }
        XCTAssertEqual(late.first.map { "\(hm($0.date)) \($0.kind.rawValue)" }, "10-22 21:30 daily",
                       "moved before quiet hours; no streak nudge an hour before the reminder")
        XCTAssertTrue(late.allSatisfy { !NotificationPlanner.isQuiet(cal.component(.hour, from: $0.date) * 60
                                                                         + cal.component(.minute, from: $0.date),
                                                                     start: 22 * 60, end: 7 * 60) })
    }

    func testNothingInThePastAndAtMostTwoADayAnHourApart() {
        let evening = plan { $0.now = WidgetTestSupport.date(2026, 10, 22, 20, 0) }
        XCTAssertEqual(evening.first.map { hm($0.date) }, "10-22 20:30", "19:00 has passed; the nudge hasn't")
        let busy = plan {
            $0.reminderMinutes = 19 * 60 + 45
            $0.exams = [
                .init(id: UUID(), title: "Chem 110 Quiz", courseName: "Chem 110", date: WidgetTestSupport.date(2026, 10, 24, 10)),
                .init(id: UUID(), title: "Bio 101 Midterm", courseName: "Bio 101", date: WidgetTestSupport.date(2026, 10, 30, 9)),
            ]
        }
        let byDay = Dictionary(grouping: busy) { cal.startOfDay(for: $0.date) }
        XCTAssertTrue(byDay.values.allSatisfy { $0.count <= 2 })
        for list in byDay.values where list.count == 2 {
            XCTAssertGreaterThanOrEqual(abs(list[0].date.timeIntervalSince(list[1].date)), 3600)
        }
        let friday = byDay[cal.startOfDay(for: WidgetTestSupport.date(2026, 10, 23))]?.map(\.kind)
        XCTAssertEqual(friday, [.examEve], "the eve of Chem wins over Bio's week note 15 minutes earlier; no reminder")
        XCTAssertFalse(busy.contains { $0.kind == .streak }, "the 19:45 reminder is within an hour of 20:30")
    }

    func testOnlyEveryWeekAhead() {
        let p = plan { $0.exams = [] }
        XCTAssertEqual(p.filter { $0.kind == .daily }.count, 7)
        XCTAssertLessThan(p.last!.date, WidgetTestSupport.date(2026, 10, 29), "nothing beyond a week")
    }

    // MARK: Ownership

    func testOnlyOurOwnRequestsAreEverRemoved() {
        let p = plan()
        let pending = ["trial.reminder", "trial.day5", "capling.daily.2026-10-01", p[0].id, "someone.else"]
        XCTAssertEqual(NotificationPlanner.staleIdentifiers(pending: pending, planned: p), ["capling.daily.2026-10-01"])
        XCTAssertEqual(NotificationPlanner.staleIdentifiers(pending: pending, planned: []),
                       ["capling.daily.2026-10-01", p[0].id], "even with notifications off, trial requests stay")
    }

    // MARK: One session from a milestone

    func testTheDayOneSessionMakesAMilestoneSaysSo() {
        // 29 days, today not done: today's reminder and nudge name the 30th day. Later days go on as ever.
        let p = plan {
            $0.streak = StreakState(current: 29, best: 29, studiedToday: false, freezesAvailable: 1)
            $0.exams = []
        }
        let today = p.filter { cal.isDate($0.date, inSameDayAs: now) }
        XCTAssertEqual(today.map(\.kind), [.daily, .streak])
        XCTAssertEqual(today[0].body, "One session today makes it 30 days.")
        XCTAssertEqual(today[1].body, "15 minutes tonight makes it 30 days.")
        let tomorrow = p.first { cal.isDate($0.date, inSameDayAs: WidgetTestSupport.date(2026, 10, 23)) }
        XCTAssertEqual(tomorrow?.body, "Your 15-minute session is ready when you are.", "not a promise about a day that hasn't come")
    }

    func testOnceTodayIsDoneItIsTomorrowsReminderThatSaysIt() {
        // 6 days and today done: tomorrow's session makes the 7th.
        let p = plan {
            $0.streak = StreakState(current: 6, best: 6, studiedToday: true, freezesAvailable: 0)
            $0.today.studiedToday = true
            $0.exams = []
        }
        XCTAssertTrue(p.filter { cal.isDate($0.date, inSameDayAs: now) }.isEmpty, "nothing more today")
        let tomorrow = p.filter { cal.isDate($0.date, inSameDayAs: WidgetTestSupport.date(2026, 10, 23)) }
        XCTAssertEqual(tomorrow.map(\.kind), [.daily, .streak])
        XCTAssertEqual(tomorrow[0].body, "One session today makes it 7 days.")
        XCTAssertEqual(tomorrow[1].body, "15 minutes tonight makes it 7 days.")
    }

    func testAnOrdinaryStreakKeepsItsOrdinaryWords() {
        for current in [0, 1, 2 + 1, 4, 12, 28, 30, 98, 365] {
            let p = plan {
                $0.streak = StreakState(current: current, best: current, studiedToday: false, freezesAvailable: 0)
                $0.exams = []
            }
            XCTAssertFalse(p.contains { $0.body.contains("makes it") && !StreakStage.milestones.contains(current + 1) },
                           "a streak of \(current) is not one session from a milestone")
        }
        // Every milestone has its day: a streak one short of it.
        for milestone in StreakStage.milestones where milestone > 3 {
            let p = plan {
                $0.streak = StreakState(current: milestone - 1, best: milestone - 1, studiedToday: false, freezesAvailable: 0)
                $0.exams = []
            }
            XCTAssertEqual(p.first?.body, "One session today makes it \(milestone) days.")
        }
        XCTAssertEqual(NotificationPlanner.milestoneNext(StreakState(current: 2), studiedToday: false)?.days, 3)
        XCTAssertNil(NotificationPlanner.milestoneNext(StreakState(current: 0), studiedToday: false))
        XCTAssertEqual(NotificationPlanner.milestoneNext(StreakState(current: 6), studiedToday: true)?.offset, 1)
    }
}
