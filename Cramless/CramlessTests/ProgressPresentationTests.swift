import Foundation
import XCTest
@testable import Cramless

/// How Progress and Streak arrange the engine's habit values: the streak's row, the run a repair joins, a month's calendar, the topics
/// to review soon and the pairs often confused.
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

    /// One row for the streak and the week, with no comparison with last week (a week in progress against a whole one reads as a loss).
    func testTheStreakRowSaysTheRunAndTheWeek() {
        XCTAssertEqual(ProgressPresentation.weekRowParts(streak: 12, onHold: false, minutes: 185), ["12-day streak", "3 h 5 min this week"])
        XCTAssertEqual(ProgressPresentation.weekRowParts(streak: 0, onHold: false, minutes: 0), ["Start a streak today", "0 min this week"])
        XCTAssertEqual(ProgressPresentation.weekRowParts(streak: 8, onHold: true, minutes: 40), ["8-day streak on hold", "40 min this week"])
        XCTAssertEqual(ProgressPresentation.weekRowParts(streak: nil, onHold: false, minutes: 40), ["40 min this week"], "Quiet mode: no streak")
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

    private func light(_ name: String, dim: Int, examDays: Int? = nil) -> ProgressPresentation.TopicLight {
        ProgressPresentation.TopicLight(id: UUID(), name: name, courseID: UUID(), courseName: "Bio", color: .sky, index: 0,
                                        dimCount: dim, examDays: examDays)
    }

    /// "Review soon" is the sky's dim line (questions under 0.7 recall), for the nearest exam first, then the most to review; topics on no
    /// exam after. The rows show counts, never a percentage.
    func testReviewSoonPutsTheNearestExamFirstThenTheMostToReview() {
        let topics = [light("Off exam, 5 dim", dim: 5), light("Far", dim: 9, examDays: 30), light("Soon, 1 dim", dim: 1, examDays: 2),
                      light("Soon, 3 dim", dim: 3, examDays: 2), light("Nothing fading", dim: 0, examDays: 1),
                      light("Off exam, 2 dim", dim: 2)]
        XCTAssertEqual(ProgressPresentation.fading(topics, count: 3).map(\.name), ["Soon, 3 dim", "Soon, 1 dim", "Far"])
        XCTAssertEqual(ProgressPresentation.fading(topics, count: 10).map(\.name),
                       ["Soon, 3 dim", "Soon, 1 dim", "Far", "Off exam, 5 dim", "Off exam, 2 dim"], "a topic with nothing fading never shows")
        XCTAssertTrue(ProgressPresentation.fading([], count: 3).isEmpty)
        XCTAssertEqual(ProgressPresentation.reviewLine(2), "2 to review")
        XCTAssertEqual(ProgressPresentation.reviewLine(1), "1 to review")
    }

    /// An exam's region says which constellations it covers: a topic takes the nearest exam that covers it, and an exam gone by counts for none.
    func testATopicsExamIsTheNearestThatCoversIt() {
        let cal = calendar()
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 14))!
        let soon = UUID(), later = UUID(), past = UUID(), course = UUID()
        func region(_ id: UUID, _ covers: [Int]) -> SkyLayout.Region {
            SkyLayout.Region(examID: id, courseID: course, title: "", center: SkyPoint(x: 0, y: 0), radius: 1, covers: covers)
        }
        let days = ProgressPresentation.daysToNearestExam(
            regions: [region(later, [0, 1]), region(soon, [1]), region(past, [2])],
            examDates: [soon: cal.date(byAdding: .day, value: 2, to: now)!, later: cal.date(byAdding: .day, value: 20, to: now)!,
                        past: cal.date(byAdding: .day, value: -2, to: now)!],
            now: now, calendar: cal)
        XCTAssertEqual(days[0], 20)
        XCTAssertEqual(days[1], 2)
        XCTAssertNil(days[2])
    }

    func testTheExamRowAndTheTilesInWords() {
        XCTAssertEqual(ProgressPresentation.examLine(days: 2, delta: 0.15), "in 2 days · +15% this week")
        XCTAssertEqual(ProgressPresentation.examLine(days: 1, delta: 0), "tomorrow · ±0% this week")
        XCTAssertEqual(ProgressPresentation.examLine(days: 0, delta: -0.03), "today · −3% this week")
        XCTAssertEqual(ProgressPresentation.skyLine(stars: 63, dim: 17), "63 stars · 17 to review")
    }

    /// A pair's row counts its misses as they are now.
    func testOftenConfusedRows() {
        XCTAssertEqual(ProgressPresentation.confusedLine(misses: 3, courseName: "Bio 101"), "Missed 3 times · Bio 101")
        XCTAssertEqual(ProgressPresentation.confusedLine(misses: 1, courseName: "Bio 101"), "Missed 1 time · Bio 101")
        XCTAssertEqual(ProgressPresentation.confusedLine(misses: 0, courseName: "Bio 101"), "Not missed yet · Bio 101")
    }
}
