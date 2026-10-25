import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// The demo world (`SampleData`) through the real engines, with a frozen clock: the numbers the harness
/// screenshots will show. Prints them and checks they are plausible.
@MainActor
final class StudyDemoWorldTests: XCTestCase {
    var previousLive: AppModel?
    var fileRoot: URL!

    override func setUp() async throws {
        previousLive = AppModel.live
        fileRoot = FileManager.default.temporaryDirectory.appending(path: "cramless-demo-\(UUID().uuidString)")
        FileStore.rootOverride = fileRoot
    }

    override func tearDown() async throws {
        FileStore.rootOverride = nil
        try? FileManager.default.removeItem(at: fileRoot)
        AppModel.live = previousLive
    }

    func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    func testDemoWorldNumbers() throws {
        let cal = EngineTest.calendar("America/New_York")
        let clock = TestClock(EngineTest.date(2026, 10, 22, 9, in: cal)) // Thursday morning
        let app = try StudyTestApp.make(clock: clock, calendar: cal)
        SampleData.seed(into: app)

        let today = app.todaySummary()
        let streak = app.streak()
        let exams = app.upcomingExams()
        let bio = try XCTUnwrap(exams.first { $0.title == "Bio 101 Midterm" })
        let chem = try XCTUnwrap(exams.first { $0.title == "Chem 110 Quiz" })
        let psych = try XCTUnwrap(exams.first { $0.title == "AP Psych Exam" })
        let rBio = app.readiness(for: bio), rChem = app.readiness(for: chem), rPsych = app.readiness(for: psych)
        let plan = app.plan(for: bio)

        var lines: [String] = []
        lines.append("Today: \(today.plannedMinutes) min · \(today.reviews) reviews · \(today.newItems) new · \(today.weakSpots) weak spots \(today.weakChips) · due \(today.dueTotal) · catch-up \(today.catchUp) · eve \(today.examEveExamID != nil)")
        lines.append("Streak: \(streak.current) days · best \(streak.best) · freezes \(streak.freezesAvailable) · frozen \(streak.frozenDays.map { cal.dayKey(for: $0.addingTimeInterval(43_200)) }) · studied today \(streak.studiedToday) · repairable \(streak.repairableDay.map { cal.dayKey(for: $0) } ?? "none")")
        for (name, r) in [("Bio 101 Midterm", rBio), ("Chem 110 Quiz", rChem), ("AP Psych Exam", rPsych)] {
            lines.append("\(name): ready \(pct(r.value)) · \(r.deltaThisWeek >= 0 ? "+" : "")\(pct(r.deltaThisWeek)) this week · projected \(pct(r.projected)) \(r.projectedGrade.letter) (\(pct(r.projectedGrade.percent))\(r.projectedGrade.isCalibrated ? ", calibrated" : ", projection")) · \(r.daysLeft) days · \(r.itemsInScope) items, \(r.unseenItems) unseen · gaps \(r.coverageGaps) · target by \(r.targetReachedOn.map { cal.dayKey(for: $0) } ?? "–")")
            lines.append("  topics: " + r.topics.map { "\($0.name) \($0.value.map(pct) ?? "no material")" }.joined(separator: ", "))
        }
        for course in app.courses {
            lines.append("Mastery \(course.name): \(pct(app.mastery(of: course)))")
        }
        lines.append("Bio plan: " + plan.days.prefix(8).map { "\(cal.dayKey(for: $0.date.addingTimeInterval(43_200)).suffix(5)) \($0.kind.rawValue) \($0.minutes)m/\($0.sessionMinutes)m +\($0.newItems)n \($0.reviews)r" }.joined(separator: " | "))
        lines.append("Bio curve: " + plan.curve.enumerated().filter { $0.offset % 4 == 0 || $0.offset == plan.curve.count - 1 }.map { pct($0.element.value) }.joined(separator: " → ") + " · suggested \(plan.suggestedMinutes.map(String.init) ?? "–")")
        lines.append("Bio history (14 d): " + app.readinessHistory(for: bio).map { pct($0.value) }.joined(separator: " "))
        let week = app.weeklyStats()
        lines.append("Week: \(week.totalMinutes) min (last week \(week.previousWeekMinutes)) · active \(week.activeDays) · heatmap cells \(app.heatmap().count)")
        lines.append("Due next 7 days: \(app.dueForecast().map(\.count)) · retention \(app.retentionRate().map(pct) ?? "–") · confusion candidates \(app.confusionCandidates().map(\.name))")
        let built = app.buildSession(SessionRequest(kind: .daily))
        lines.append("Session order: " + built.entries.prefix(12).map { "\($0.kind.rawValue)/\($0.reason.rawValue)" }.joined(separator: ", "))
        print("\n===== DEMO WORLD =====\n" + lines.joined(separator: "\n") + "\n======================\n")

        // A 12-day streak with one frozen day, up to yesterday.
        XCTAssertEqual(streak.current, 12)
        XCTAssertEqual(streak.frozenDays.count, 1)
        XCTAssertFalse(streak.studiedToday)
        XCTAssertGreaterThanOrEqual(streak.best, 12)
        // Readiness: Bio middling, Chem lower, AP Psych low.
        XCTAssertTrue((0.40...0.75).contains(rBio.value), "Bio \(rBio.value)")
        XCTAssertLessThan(rChem.value, rBio.value)
        XCTAssertLessThan(rPsych.value, 0.4)
        XCTAssertGreaterThan(rBio.projected, rBio.value)
        XCTAssertEqual(rBio.daysLeft, 23)
        XCTAssertTrue(rBio.topics.contains { $0.name == "DNA replication" && $0.value == nil }, "a coverage gap")
        XCTAssertTrue(today.sessionReady)
        XCTAssertGreaterThan(today.reviews, 0)
        XCTAssertFalse(today.weakChips.isEmpty)
        XCTAssertLessThanOrEqual(today.plannedMinutes, 16)
    }
}
