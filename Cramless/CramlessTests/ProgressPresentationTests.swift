import Foundation
import XCTest
@testable import Cramless

/// How Progress and Streak arrange the engine's habit values: heatmap weeks and month labels, last week beside this
/// one, the run a repair joins, a month's calendar, and the strongest and weakest topics.
final class ProgressPresentationTests: XCTestCase {
    private func calendar(firstWeekday: Int = 1) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US")
        c.firstWeekday = firstWeekday
        return c
    }

    /// The engine's own heatmap for a pattern of days ending yesterday ("s" studied, "f" frozen, "-" missed).
    private func cells(_ pattern: String, cal: Calendar, now: Date, weeks: Int = 12, minutes: Int = 15) -> [HeatmapCell] {
        var records: [DaySnapshot] = []
        for (i, ch) in pattern.enumerated() where ch != "-" {
            let back = pattern.count - i
            let date = cal.adding(days: -back, to: now)
            records.append(DaySnapshot(dayKey: cal.dayKey(for: date), day: cal.startOfDay(for: date),
                                       studySeconds: ch == "s" ? Double(minutes * 60) : 0, itemsReviewed: 0,
                                       sessions: ch == "s" ? 1 : 0, frozen: ch == "f"))
        }
        return StreakEngine(calendar: cal, now: now, dailyMinutes: 15).heatmap(records, weeks: weeks)
    }

    func testHeatmapWeeksAndMonthLabels() {
        let cal = calendar()
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 18))!
        let heat = cells("sss", cal: cal, now: now)
        let weeks = ProgressPresentation.weeks(heat)
        XCTAssertEqual(weeks.count, 12)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(cal.component(.weekday, from: weeks[0][0].date), 1, "columns start on the calendar's first weekday")
        let labels = ProgressPresentation.monthLabels(weeks, calendar: cal)
        XCTAssertEqual(labels.map(\.label), ["Aug", "Sep", "Oct"])
        XCTAssertTrue(zip(labels, labels.dropFirst()).allSatisfy { $1.column - $0.column >= 2 }, "labels never crowd")
        XCTAssertEqual(ProgressPresentation.style(weeks[11][4]), .empty, "today, not studied yet")
        XCTAssertEqual(ProgressPresentation.style(weeks[11][5]), .future)
        XCTAssertEqual(ProgressPresentation.style(weeks[11][3]), .level(3), "15 minutes against a 15-minute goal")
    }

    func testCellWords() {
        let cal = calendar()
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 18))!
        let heat = cells("sf-", cal: cal, now: now)
        let byDay = Dictionary(uniqueKeysWithValues: heat.map { (cal.dayNumber(for: $0.date), $0) })
        let today = cal.dayNumber(for: now)
        XCTAssertEqual(ProgressPresentation.accessibility(byDay[today - 3]!, calendar: cal).value, "15 minutes")
        XCTAssertEqual(ProgressPresentation.accessibility(byDay[today - 2]!, calendar: cal).value, "Covered by a streak freeze")
        XCTAssertEqual(ProgressPresentation.accessibility(byDay[today - 1]!, calendar: cal).value, "Not studied")
        XCTAssertEqual(ProgressPresentation.accessibility(byDay[today]!, calendar: cal).value, "Today, not studied yet")
        XCTAssertEqual(ProgressPresentation.accessibility(byDay[today + 1]!, calendar: cal).value, "Later this week")
        XCTAssertEqual(ProgressPresentation.accessibility(byDay[today - 3]!, calendar: cal).label, "Mon, Oct 19")
        XCTAssertEqual(ProgressPresentation.style(byDay[today - 2]!), .frozen)
    }

    func testLastWeekLinesUpWithThisWeeksDays() {
        let cal = calendar()
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 18))!
        // Last week Sun…Sat: 10, 0, 20, 0, 5, 0, 30; this week so far nothing.
        var records: [DaySnapshot] = []
        for (offset, minutes) in [(-11, 10), (-9, 20), (-7, 5), (-5, 30)] {
            let date = cal.adding(days: offset, to: now)
            records.append(DaySnapshot(dayKey: cal.dayKey(for: date), day: cal.startOfDay(for: date),
                                       studySeconds: Double(minutes * 60), sessions: 1))
        }
        let engine = StreakEngine(calendar: cal, now: now, dailyMinutes: 15)
        let week = engine.weekly(records)
        let last = ProgressPresentation.lastWeekMinutes(cells: engine.heatmap(records, weeks: 12), week: week, calendar: cal)
        XCTAssertEqual(last, [10, 0, 20, 0, 5, 0, 30])
        XCTAssertEqual(last.reduce(0, +), week.previousWeekMinutes)
        XCTAssertEqual(ProgressPresentation.weekComparison(this: 64, last: 73), "−9 min vs last week")
        XCTAssertEqual(ProgressPresentation.weekComparison(this: 90, last: 20), "+1 h 10 min vs last week")
        XCTAssertEqual(ProgressPresentation.weekComparison(this: 5, last: 5), "Same as last week")
    }

    func testRunBeforeAMissedDay() {
        let cal = calendar()
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 18))!
        let heat = cells("-ssfss-", cal: cal, now: now)
        let yesterday = cal.startOfDay(for: cal.adding(days: -1, to: now))
        XCTAssertEqual(ProgressPresentation.runBefore(yesterday, cells: heat, calendar: cal), 5, "a frozen day keeps the run")
        XCTAssertEqual(ProgressPresentation.runBefore(cal.startOfDay(for: cal.adding(days: -7, to: now)), cells: heat, calendar: cal), 0)
    }

    func testMonthGridFollowsTheCalendarsWeek() {
        let october = calendar().date(from: DateComponents(year: 2026, month: 10, day: 15))!
        let sundayFirst = ProgressPresentation.monthGrid(for: october, calendar: calendar())
        XCTAssertEqual(sundayFirst.count, 5)
        XCTAssertEqual(sundayFirst[0].prefix(4).compactMap { $0 }.count, 0, "Oct 1, 2026 is a Thursday")
        XCTAssertEqual(sundayFirst[0][4].map { calendar().component(.day, from: $0) }, 1)
        XCTAssertEqual(sundayFirst.flatMap { $0 }.compactMap { $0 }.count, 31)
        XCTAssertTrue(sundayFirst.allSatisfy { $0.count == 7 })

        let mondayFirst = ProgressPresentation.monthGrid(for: october, calendar: calendar(firstWeekday: 2))
        XCTAssertEqual(mondayFirst[0].prefix(3).compactMap { $0 }.count, 0)
        XCTAssertNotNil(mondayFirst[0][3])
        XCTAssertEqual(ProgressPresentation.weekdaySymbols(calendar: calendar(firstWeekday: 2)), ["M", "T", "W", "T", "F", "S", "S"])
        XCTAssertEqual(ProgressPresentation.weekdaySymbols(calendar: calendar()), ["S", "M", "T", "W", "T", "F", "S"])
    }

    func testStrongestAndWeakestNeverOverlapAndSkipUnstudiedTopics() {
        func topic(_ name: String, _ value: Double, items: Int = 4) -> ProgressPresentation.TopicEntry {
            ProgressPresentation.TopicEntry(id: UUID(), name: name, courseID: UUID(), courseName: "Bio", color: .sky,
                                            value: value, itemCount: items)
        }
        let all = [topic("A", 0.95), topic("B", 0.42), topic("C", 0.81), topic("D", 0), topic("E", 0.66), topic("F", 0.3),
                   topic("G", 0.9), topic("H", 0.55, items: 0)]
        let (strongest, weakest) = ProgressPresentation.topicExtremes(all, count: 3)
        XCTAssertEqual(strongest.map(\.name), ["A", "G", "C"])
        XCTAssertEqual(weakest.map(\.name), ["F", "B", "E"], "weakest first, never one of the strongest, never unstudied")

        let few = ProgressPresentation.topicExtremes([topic("X", 0.7), topic("Y", 0.4), topic("Z", 0.9)], count: 3)
        XCTAssertEqual(few.strongest.map(\.name), ["Z", "X"])
        XCTAssertEqual(few.weakest.map(\.name), ["Y"])
        XCTAssertTrue(ProgressPresentation.topicExtremes([], count: 3).strongest.isEmpty)
    }
}
