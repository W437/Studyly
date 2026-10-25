import Foundation
import XCTest
@testable import Cramless

final class EngineReadinessTests: XCTestCase {
    let cal = EngineTest.calendar()
    lazy var now = EngineTest.date(2026, 10, 22, 9, in: cal)
    let course = UUID()
    let topicA = UUID(), topicB = UUID(), topicGap = UUID()
    lazy var engine = ReadinessEngine(fsrs: FSRS(), calendar: cal, now: now)
    lazy var topics = [TopicSnapshot(id: topicA, courseID: course, name: "A", sortOrder: 0),
                       TopicSnapshot(id: topicB, courseID: course, name: "B", sortOrder: 1),
                       TopicSnapshot(id: topicGap, courseID: course, name: "No material", sortOrder: 2)]

    func testNeverStudiedItemsCountZero() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 10, to: now))
        let studied = EngineTest.studied(topic: topicA, course: course, recall: 0.9, daysAgo: 5, now: now, cal: cal)
        let fresh = EngineTest.fresh(topic: topicB, course: course)
        let r = engine.examRecall(studied.memory, on: exam.date)
        XCTAssertLessThan(r, 0.9, "recall falls by exam day")
        XCTAssertEqual(engine.value(of: exam, items: [studied, fresh]), r / 2, accuracy: 1e-12)
        // Suspended items and other courses are out of scope.
        var suspended = studied
        suspended.id = UUID()
        suspended.status = .suspended
        let other = EngineTest.studied(course: UUID(), recall: 0.2, daysAgo: 5, now: now, cal: cal)
        XCTAssertEqual(engine.value(of: exam, items: [studied, fresh, suspended, other]), r / 2, accuracy: 1e-12)
    }

    func testTopicsAndCoverageGaps() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 10, to: now))
        let items = [EngineTest.studied(topic: topicA, course: course, recall: 0.9, daysAgo: 5, now: now, cal: cal),
                     EngineTest.fresh(topic: topicB, course: course)]
        let list = engine.topicReadiness(for: exam, items: items, topics: topics)
        XCTAssertEqual(list.map(\.name), ["A", "B", "No material"])
        XCTAssertGreaterThan(list[0].value!, 0.5)
        XCTAssertEqual(list[1].value, 0)
        XCTAssertNil(list[2].value, "a topic with no items is a coverage gap")
        // A scoped exam lists only its topics.
        let scoped = ExamSnapshot(courseID: course, date: exam.date, scope: [topicB])
        XCTAssertEqual(engine.topicReadiness(for: scoped, items: items, topics: topics).map(\.name), ["B"])
    }

    func testMasteryIsCurrentRecallOfStudiedItems() {
        let items = [EngineTest.studied(course: course, recall: 0.8, daysAgo: 3, now: now, cal: cal),
                     EngineTest.studied(course: course, recall: 0.6, daysAgo: 3, now: now, cal: cal),
                     EngineTest.fresh(course: course)]
        XCTAssertEqual(engine.mastery(of: items), 0.7, accuracy: 1e-9)
        XCTAssertEqual(engine.mastery(of: [EngineTest.fresh(course: course)]), 0)
        let byTopic = engine.topicMastery(courseID: course, items: [EngineTest.fresh(topic: topicB, course: course)],
                                          topics: topics)
        XCTAssertEqual(byTopic.map(\.value), [nil, 0, nil])
    }

    func testDeltaThisWeekComesFromTheReviewLog() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 14, to: now))
        let id = UUID()
        let tenDaysAgo = cal.adding(days: -10, to: now)
        let twoDaysAgo = cal.adding(days: -2, to: now)
        let memory = MemoryState(state: .review, stability: 20, difficulty: 5, due: cal.adding(days: 18, to: twoDaysAgo),
                                 lastReview: twoDaysAgo, reps: 2)
        let item = ItemSnapshot(id: id, topicID: topicA, courseID: course, memory: memory)
        let logs = [ReviewSnapshot(itemID: id, reviewedAt: tenDaysAgo, rating: .good, stabilityAfter: 4),
                    ReviewSnapshot(itemID: id, reviewedAt: twoDaysAgo, rating: .good, stabilityAfter: 20)]
        let fresh = EngineTest.fresh(topic: topicB, course: course)
        let plan = PlanBuilder(fsrs: FSRS(), calendar: cal, now: now, dailyMinutes: 15).plan(for: exam, items: [item, fresh])
        let r = engine.readiness(for: exam, items: [item, fresh], topics: topics, logs: logs, plan: plan,
                                 grade: .uncalibrated(for: exam.format))
        let nowValue = engine.recall(stability: 20, last: twoDaysAgo, on: exam.date) / 2
        let weekAgo = engine.recall(stability: 4, last: tenDaysAgo, on: exam.date) / 2
        XCTAssertEqual(r.value, nowValue, accuracy: 1e-12)
        XCTAssertEqual(r.deltaThisWeek, nowValue - weekAgo, accuracy: 1e-12)
        XCTAssertGreaterThan(r.deltaThisWeek, 0)
        XCTAssertEqual(r.daysLeft, 14)
        XCTAssertEqual(r.itemsInScope, 2)
        XCTAssertEqual(r.unseenItems, 1)
        XCTAssertEqual(r.coverageGaps, 1)
        XCTAssertGreaterThan(r.projected, r.value, "following the plan beats stopping now")
        XCTAssertEqual(r.projectedGrade, GradeModel.uncalibrated(for: exam.format).grade(r.projected))
    }

    func testHistoryIsOldestFirstAndEndsNow() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 14, to: now))
        let id = UUID()
        let fiveDaysAgo = cal.adding(days: -5, to: now)
        let item = ItemSnapshot(id: id, courseID: course, memory: MemoryState(state: .review, stability: 10, difficulty: 5,
                                                                              due: cal.adding(days: 10, to: fiveDaysAgo),
                                                                              lastReview: fiveDaysAgo, reps: 1))
        let logs = [ReviewSnapshot(itemID: id, reviewedAt: fiveDaysAgo, rating: .good, stabilityAfter: 10)]
        let points = engine.history(of: exam, items: [item], logs: logs, days: 14)
        XCTAssertEqual(points.count, 14)
        XCTAssertEqual(points.last!.value, engine.value(of: exam, items: [item]), accuracy: 1e-12)
        XCTAssertEqual(points.first!.value, 0, "nothing studied two weeks ago")
        XCTAssertTrue(zip(points, points.dropFirst()).allSatisfy { $0.date < $1.date })
        XCTAssertEqual(points.firstIndex { $0.value > 0 }, 14 - 6, "studied five days ago")
    }

    func testImportedMemoryWithoutLogsCountsOnceReviewed() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 14, to: now))
        let item = EngineTest.studied(course: course, recall: 0.9, daysAgo: 3, now: now, cal: cal)
        XCTAssertGreaterThan(engine.value(of: exam, items: [item], at: cal.adding(days: -1, to: now), logsByItem: [:]), 0)
        XCTAssertEqual(engine.value(of: exam, items: [item], at: cal.adding(days: -5, to: now), logsByItem: [:]), 0)
    }

    // MARK: Grades

    func testDefaultGradeMapping() {
        let mixed = GradeModel.uncalibrated(for: ExamFormat(multipleChoice: true, shortAnswer: true, essay: false))
        XCTAssertEqual(mixed.percent(0.8), 0.125 + 0.875 * 0.8, accuracy: 1e-12)
        XCTAssertFalse(mixed.isCalibrated)
        XCTAssertEqual(GradeModel.uncalibrated(for: ExamFormat(multipleChoice: true, shortAnswer: false)).percent(0), 0.25)
        XCTAssertEqual(GradeModel.uncalibrated(for: ExamFormat(multipleChoice: false, shortAnswer: true)).percent(0.7), 0.7,
                       accuracy: 1e-12)
        XCTAssertEqual(GradeModel.letter(0.87), "B+")
        XCTAssertEqual(GradeModel.letter(0.905), "A−")
        XCTAssertEqual(GradeModel.letter(0.5), "F")
        XCTAssertEqual(GradeModel.letter(1), "A+")
    }

    func testCalibrationFitsLoggedGrades() {
        let format = ExamFormat()
        XCTAssertFalse(GradeModel.make(format: format, history: [(0.7, 0.8)]).isCalibrated, "one exam isn't enough")
        let fit = GradeModel.make(format: format, history: [(0.6, 0.7), (0.8, 0.86)])
        XCTAssertTrue(fit.isCalibrated)
        XCTAssertEqual(fit.slope, 0.8, accuracy: 1e-9)
        XCTAssertEqual(fit.intercept, 0.22, accuracy: 1e-9)
        XCTAssertEqual(fit.percent(0.7), 0.78, accuracy: 1e-9)
        // No spread in readiness: the default slope, shifted.
        let flat = GradeModel.make(format: format, history: [(0.7, 0.8), (0.7, 0.9)])
        XCTAssertEqual(flat.slope, GradeModel.uncalibrated(for: format).slope)
        XCTAssertEqual(flat.percent(0.7), 0.85, accuracy: 1e-9)
    }
}

final class EnginePlanTests: XCTestCase {
    let cal = EngineTest.calendar()
    lazy var now = EngineTest.date(2026, 10, 22, 9, in: cal)
    let course = UUID()

    func builder(at date: Date? = nil, minutes: Int = 15, easyDays: [Int] = []) -> PlanBuilder {
        PlanBuilder(fsrs: FSRS(), calendar: cal, now: date ?? now, dailyMinutes: minutes, easyDays: easyDays)
    }

    func world(new: Int = 30, studied: Int = 20) -> [ItemSnapshot] {
        (0..<new).map { i in EngineTest.fresh(course: course, createdAt: cal.adding(days: -5, to: now), hint: Double(i) / 100) }
            + (0..<studied).map { i in
                EngineTest.studied(course: course, recall: 0.7 + Double(i % 5) * 0.05, daysAgo: 2 + i % 6, now: now, cal: cal)
            }
    }

    func testNewMaterialIsInByThreeDaysBeforeTheExam() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 20, to: now))
        let plan = builder().plan(for: exam, items: world())
        let today = cal.dayNumber(for: now), examDay = cal.dayNumber(for: exam.date)
        XCTAssertEqual(plan.daysLeft, 20)
        XCTAssertEqual(plan.days.count, 21, "today through exam day")
        XCTAssertEqual(plan.days.reduce(0) { $0 + $1.newItems }, 30)
        XCTAssertTrue(plan.days.filter { $0.dayNumber > examDay - 3 }.allSatisfy { $0.newItems == 0 })
        XCTAssertEqual(plan.lastIntroDay, cal.startOfDay(dayNumber: examDay - 3))
        XCTAssertEqual(plan.days.first?.isToday, true)
        XCTAssertEqual(plan.days.first?.dayNumber, today)
        XCTAssertEqual(plan.days.last?.kind, .exam)
    }

    func testTheLastEveningIsTheExamEve() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 10, to: now))
        let plan = builder().plan(for: exam, items: world())
        let eve = plan.days[plan.days.count - 2]
        XCTAssertEqual(eve.kind, .examEve)
        XCTAssertEqual(eve.newItems, 0)
        XCTAssertEqual(plan.examEve, eve.date)
        XCTAssertEqual(plan.days.filter { $0.kind == .examEve }.count, 1)
    }

    func testEasyDaysGetNoNewMaterialAndALighterSession() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 14, to: now))
        let saturday = 7
        let plan = builder(easyDays: [saturday]).plan(for: exam, items: world())
        let easy = plan.days.filter(\.isEasyDay)
        XCTAssertFalse(easy.isEmpty)
        for day in easy where day.kind != .examEve && day.kind != .exam {
            XCTAssertEqual(day.newItems, 0)
            XCTAssertTrue(day.kind == .light || day.kind == .rest)
        }
        XCTAssertEqual(plan.days.reduce(0) { $0 + $1.newItems }, 30)
        let normal = plan.days.first { !$0.isEasyDay && $0.kind == .study }!
        XCTAssertGreaterThanOrEqual(normal.sessionMinutes, 15)
    }

    func testTheCurveRisesToTheProjection() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 23, to: now), target: 0.9)
        let plan = builder().plan(for: exam, items: world())
        XCTAssertEqual(plan.curve.count, 24, "now, then each morning to exam day")
        XCTAssertFalse(plan.curve[0].isProjection)
        XCTAssertTrue(plan.curve.dropFirst().allSatisfy(\.isProjection))
        XCTAssertEqual(plan.projectedReadiness, plan.curve.last!.value)
        XCTAssertGreaterThan(plan.projectedReadiness, plan.currentReadiness + 0.3)
        XCTAssertGreaterThan(plan.projectedReadiness, 0.8)
        if let reached = plan.targetReachedOn {
            XCTAssertGreaterThanOrEqual(plan.curve.first { $0.date == reached }!.value, 0.9)
        }
        XCTAssertEqual(plan.curve.last!.date, cal.startOfDay(for: exam.date))
    }

    /// Miss a day: the following days absorb it (the new material still goes in by three days before, and the
    /// overdue reviews spread instead of piling onto one day).
    func testThePlanBendsAfterAMissedDay() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 12, to: now))
        let items = world(new: 40, studied: 150)
        let planned = builder().plan(for: exam, items: items)
        let tomorrow = cal.adding(days: 1, to: now)
        let bent = builder(at: tomorrow).plan(for: exam, items: items) // nothing was studied today
        let examDay = cal.dayNumber(for: exam.date)
        XCTAssertEqual(bent.days.reduce(0) { $0 + $1.newItems }, 40)
        XCTAssertTrue(bent.days.filter { $0.dayNumber > examDay - 3 }.allSatisfy { $0.newItems == 0 })
        // The new items planned for the missed day are spread over the days left, not dumped on tomorrow.
        let firstPlanned = planned.days.first!.newItems
        XCTAssertGreaterThan(bent.days.first!.newItems, planned.days[1].newItems)
        XCTAssertLessThan(bent.days.first!.newItems, planned.days[1].newItems + firstPlanned)
        // 150 overdue reviews (more than a day's 15 minutes) spread over the next three days.
        XCTAssertLessThan(bent.days[0].reviews, 120)
        XCTAssertGreaterThan(bent.days[1].reviews, 30)
        XCTAssertGreaterThan(bent.days[2].reviews, 30)
    }

    func testAPlanAcrossTheDaylightSavingChangeCountsCalendarDays() {
        // Oct 22 → Nov 14 crosses the end of US daylight saving (Nov 1): still 23 days, one entry per day.
        let exam = ExamSnapshot(courseID: course, date: EngineTest.date(2026, 11, 14, 9, in: cal))
        let plan = builder().plan(for: exam, items: world())
        XCTAssertEqual(plan.daysLeft, 23)
        XCTAssertEqual(plan.days.count, 24)
        let keys = plan.days.map { cal.dayKey(for: $0.date.addingTimeInterval(12 * 3600)) }
        XCTAssertEqual(Set(keys).count, 24)
        XCTAssertEqual(keys.first, "2026-10-22")
        XCTAssertEqual(keys.last, "2026-11-14")
        XCTAssertTrue(plan.days.allSatisfy { cal.component(.hour, from: $0.date) == 0 })
    }

    func testAnExamTomorrowIsAllEve() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 1, to: now))
        let plan = builder().plan(for: exam, items: world(new: 3, studied: 5))
        XCTAssertEqual(plan.days.map(\.kind), [.examEve, .exam])
        XCTAssertEqual(plan.days[0].newItems, 3, "with one day left the new material goes in today")
    }

    func testSuggestsMoreMinutesWhenTheGoalIsTooSmall() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 4, to: now))
        let items = (0..<120).map { _ in EngineTest.fresh(kind: .recall, course: course) }
        let plan = builder(minutes: 10).plan(for: exam, items: items)
        XCTAssertNotNil(plan.suggestedMinutes)
        XCTAssertEqual(plan.suggestedMinutes! % 5, 0)
        XCTAssertGreaterThan(plan.suggestedMinutes!, 10)
    }

    func testNoItemsNoPlan() {
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 9, to: now))
        let plan = builder().plan(for: exam, items: [])
        XCTAssertEqual(plan.projectedReadiness, 0)
        XCTAssertEqual(plan.itemsInScope, 0)
    }
}
