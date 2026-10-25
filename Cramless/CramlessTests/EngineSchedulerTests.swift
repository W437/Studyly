import Foundation
import XCTest
@testable import Cramless

final class EngineSchedulerTests: XCTestCase {
    let cal = EngineTest.calendar()
    lazy var now = EngineTest.date(2026, 10, 22, 9, in: cal)
    lazy var today = cal.dayNumber(for: now)

    /// A review item due now whose Good answer lands on `days`-ish days.
    func reviewItem(stability: Double = 20, course: UUID? = nil, topic: UUID? = nil, id: UUID = UUID()) -> ItemSnapshot {
        let last = cal.adding(days: -Int(stability), to: now)
        let memory = MemoryState(state: .review, stability: stability, difficulty: 5, due: now, lastReview: last,
                                 reps: 4, lapses: 0, step: 0)
        return ItemSnapshot(id: id, kind: .flashcard, topicID: topic, courseID: course, memory: memory)
    }

    func testFuzzOffIsPlainFSRS() {
        let scheduler = StudyScheduler(calendar: cal, fuzz: false)
        let item = reviewItem()
        let result = scheduler.schedule(item, rating: .good, at: now)
        let plain = FSRS().review(item.memory, rating: .good, at: now)
        XCTAssertEqual(result.memory.stability, plain.memory.stability)
        XCTAssertEqual(result.memory.difficulty, plain.memory.difficulty)
        XCTAssertEqual(result.fsrsIntervalDays, plain.intervalDays)
        XCTAssertEqual(cal.dayNumber(for: result.memory.due!) - today, plain.intervalDays)
        XCTAssertEqual(result.adjustment, ScheduleAdjustment.none)
    }

    func testLearningStepsAreNotFuzzed() {
        let scheduler = StudyScheduler(calendar: cal)
        let result = scheduler.schedule(ItemSnapshot(memory: .new), rating: .good, at: now)
        XCTAssertEqual(result.memory.state, .learning)
        XCTAssertEqual(result.memory.due, now.addingTimeInterval(600))
        XCTAssertEqual(result.adjustment, ScheduleAdjustment.none)
    }

    func testFuzzIsDeterministicAndInRange() {
        let scheduler = StudyScheduler(calendar: cal, fuzz: true, loadBalance: false)
        let fsrs = FSRS()
        var seen = Set<Int>()
        for _ in 0..<60 {
            let item = reviewItem()
            let a = scheduler.schedule(item, rating: .good, at: now)
            let b = scheduler.schedule(item, rating: .good, at: now)
            XCTAssertEqual(a.memory.due, b.memory.due, "same item, same day, same fuzz")
            let range = fsrs.fuzzRange(intervalDays: a.fsrsIntervalDays!)
            let days = cal.dayNumber(for: a.memory.due!) - today
            XCTAssertTrue(range.contains(days), "\(days) in \(range)")
            seen.insert(days)
        }
        XCTAssertGreaterThan(seen.count, 2, "different items spread over the fuzz range")
    }

    func testLoadBalancingPicksTheLeastLoadedDay() {
        let scheduler = StudyScheduler(calendar: cal)
        let item = reviewItem()
        let base = scheduler.schedule(item, rating: .good, at: now)
        let ivl = base.fsrsIntervalDays!
        let range = FSRS().fuzzRange(intervalDays: ivl)
        XCTAssertGreaterThan(range.count, 2)
        // Every day in range is busy except one at the edge.
        var load = DueLoad()
        for d in range { load.counts[today + d] = 30 }
        load.counts[today + range.upperBound] = 2
        let balanced = scheduler.schedule(item, rating: .good, at: now, load: load)
        XCTAssertEqual(cal.dayNumber(for: balanced.memory.due!) - today, range.upperBound)
        XCTAssertEqual(balanced.adjustment, .balanced)
    }

    func testLoadBalancingSpreadsASameDayBatch() {
        // Twenty identical cards learned together: with the load updated after each, they don't all land on one day.
        let scheduler = StudyScheduler(calendar: cal)
        var load = DueLoad()
        var days: [Int] = []
        for _ in 0..<20 {
            let r = scheduler.schedule(reviewItem(), rating: .good, at: now, load: load)
            let d = cal.dayNumber(for: r.memory.due!)
            load.move(from: nil, to: d)
            days.append(d)
        }
        let perDay = Dictionary(grouping: days, by: { $0 }).mapValues(\.count)
        XCTAssertGreaterThan(perDay.count, 3)
        XCTAssertLessThanOrEqual(perDay.values.max()!, 6)
    }

    func testEasyDaysTakeLessLoad() {
        let item = reviewItem()
        let ivl = StudyScheduler(calendar: cal).schedule(item, rating: .good, at: now).fsrsIntervalDays!
        let range = FSRS().fuzzRange(intervalDays: ivl)
        // Make the FSRS day itself an easy day; with equal loads the balancer moves off it.
        let target = today + ivl
        let easy = StudyScheduler(calendar: cal, easyDays: [Calendar.weekday(dayNumber: target)])
        var load = DueLoad()
        for d in range { load.counts[today + d] = 4 }
        let r = easy.schedule(item, rating: .good, at: now, load: load)
        let landed = cal.dayNumber(for: r.memory.due!)
        XCTAssertNotEqual(Calendar.weekday(dayNumber: landed), Calendar.weekday(dayNumber: target))
        // An easy day still wins when it is much emptier than the rest.
        for d in range { load.counts[today + d] = 20 }
        load.counts[target] = 1
        XCTAssertEqual(cal.dayNumber(for: easy.schedule(item, rating: .good, at: now, load: load).memory.due!), target)
    }

    func testExamCapping() {
        let course = UUID(), topic = UUID(), other = UUID()
        let exam = ExamSnapshot(courseID: course, date: cal.adding(days: 6, to: now), scope: [topic], target: 0.97)
        let scheduler = StudyScheduler(calendar: cal, fuzz: false)
        let examDay = cal.dayNumber(for: exam.date)

        // In scope, would be due after the exam (S 3 → about 11 days), and under 97% on exam day: pulled to 1–3
        // days before.
        let inScope = reviewItem(stability: 3, course: course, topic: topic)
        let capped = scheduler.schedule(inScope, rating: .good, at: now, exams: [exam])
        XCTAssertGreaterThan(capped.fsrsIntervalDays!, 6)
        XCTAssertEqual(capped.adjustment, .examCapped)
        XCTAssertEqual(capped.examID, exam.id)
        let landed = cal.dayNumber(for: capped.memory.due!)
        XCTAssertTrue((examDay - 3)...(examDay - 1) ~= landed, "landed \(landed - today) days out")

        // Another topic: not capped.
        let outside = scheduler.schedule(reviewItem(stability: 3, course: course, topic: other), rating: .good,
                                         at: now, exams: [exam])
        XCTAssertEqual(outside.adjustment, ScheduleAdjustment.none)

        // A target its exam-day recall already meets: not capped.
        let easyExam = ExamSnapshot(courseID: course, date: exam.date, scope: [topic], target: 0.5)
        XCTAssertEqual(scheduler.schedule(inScope, rating: .good, at: now, exams: [easyExam]).adjustment,
                       ScheduleAdjustment.none)

        // Least loaded of the three days wins.
        var load = DueLoad()
        load.counts[examDay - 1] = 9
        load.counts[examDay - 2] = 1
        load.counts[examDay - 3] = 9
        let balanced = scheduler.schedule(inScope, rating: .good, at: now, load: load, exams: [exam])
        XCTAssertEqual(cal.dayNumber(for: balanced.memory.due!), examDay - 2)
    }

    func testDueLoadCountsReviewItemsByDay() {
        let grid = DayGrid(calendar: cal, from: now, count: 30)
        let items = [reviewItem(stability: 3), reviewItem(stability: 3), ItemSnapshot(memory: .new)]
        let load = DueLoad(items: items, grid: grid)
        XCTAssertEqual(load.count(onDay: today), 2)
        var moved = load
        moved.move(from: today, to: today + 4)
        XCTAssertEqual(moved.count(onDay: today), 1)
        XCTAssertEqual(moved.count(onDay: today + 4), 1)
    }

    func testDayMathAcrossDaylightSaving() {
        // US daylight saving ends on Sunday, Nov 1, 2026: that day has 25 hours.
        let before = EngineTest.date(2026, 10, 31, 23, 30, in: cal)
        let after = EngineTest.date(2026, 11, 2, 0, 30, in: cal)
        XCTAssertEqual(cal.dayNumber(for: after) - cal.dayNumber(for: before), 2)
        XCTAssertEqual(cal.dayDistance(from: before, to: after), 2)
        let grid = DayGrid(calendar: cal, from: before, count: 5)
        XCTAssertEqual(grid.dayNumber(for: after), cal.dayNumber(for: after))
        XCTAssertEqual(grid.end(ofDay: grid.firstDay + 1).timeIntervalSince(grid.start(ofDay: grid.firstDay + 1)), 25 * 3600)
        XCTAssertEqual(cal.dayNumber(forKey: cal.dayKey(for: after)), cal.dayNumber(for: after))
        // Spring forward (Mar 8, 2026): a 1-day interval from late evening is still tomorrow.
        let sat = EngineTest.date(2026, 3, 7, 23, 30, in: cal)
        XCTAssertEqual(cal.dayNumber(for: cal.adding(days: 1, to: sat)) - cal.dayNumber(for: sat), 1)
        // Weekday arithmetic agrees with the calendar.
        for offset in 0..<14 {
            let d = cal.adding(days: offset, to: now)
            XCTAssertEqual(Calendar.weekday(dayNumber: cal.dayNumber(for: d)), cal.component(.weekday, from: d))
        }
    }

    func testDayNumbersHoldForOtherCalendarSystems() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        for c in [buddhist, hebrew] {
            // Across the Gregorian leap day and month ends.
            let a = c.startOfDay(for: EngineTest.iso("2028-02-20T05:00:00Z")).addingTimeInterval(10 * 3600)
            for k in 0..<20 {
                let b = c.adding(days: k, to: a)
                XCTAssertEqual(c.dayNumber(for: b) - c.dayNumber(for: a), k, "\(c.identifier) +\(k)")
                XCTAssertEqual(c.dayNumber(forKey: c.dayKey(for: b)), c.dayNumber(for: b))
                XCTAssertEqual(c.startOfDay(dayNumber: c.dayNumber(for: b)), c.startOfDay(for: b))
            }
        }
    }
}
