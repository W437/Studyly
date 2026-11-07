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

    /// The store's clock. The midterm's exam-day number is what the plan and the exam page show, so it has to be one number however the store
    /// happens to hand over the course's questions.
    func testTheMidtermsProjectionIsOneNumberInAnyOrder() throws {
        let cal = EngineTest.calendar("America/New_York")
        let clock = TestClock(try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-06T14:00:00-05:00")))
        let app = try StudyTestApp.make(clock: clock, calendar: cal)
        SampleData.seed(into: app)
        let bio = try XCTUnwrap(app.upcomingExams().first { $0.title == "Bio 101 Midterm" })
        let shared = app.sharedPlans()
        let plan = try XCTUnwrap(shared.plans.first { $0.examID == bio.id })

        var builder = app.planBuilder()
        builder.capacity = shared.capacity[bio.id]
        for other in shared.plans.prefix(while: { $0.examID != bio.id }) {
            for day in other.days where day.kind != .exam { builder.newElsewhere[day.offset, default: 0] += day.newItems }
        }
        let items = app.itemSnapshots(in: bio.course)
        XCTAssertEqual(builder.plan(for: ExamSnapshot(bio), items: items), plan, "the shared plan, rebuilt")

        var rng = SeededGenerator(seed: 2026)
        var seen = Set<Int>()
        for _ in 0..<60 {
            let again = builder.plan(for: ExamSnapshot(bio), items: items.shuffled(using: &rng))
            seen.insert(Int((again.projectedReadiness * 100).rounded()))
            XCTAssertEqual(again, plan)
        }
        print("Bio midterm projection, 60 orders: \(seen.sorted()), unrounded \(plan.projectedReadiness)")
        XCTAssertEqual(seen.count, 1)
    }

    /// Each launch's world reads the same, whatever order this one's store hands things over in.
    func testEveryLaunchPlansTheSameWorldTheSameWay() throws {
        let cal = EngineTest.calendar("America/New_York")
        let clock = TestClock(try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-06T14:00:00-05:00")))
        var first: [StudyPlan]?
        for launch in 0..<8 {
            let app = try StudyTestApp.make(clock: clock, calendar: cal)
            SampleData.seed(into: app)
            let plans = app.examPlans()
            XCTAssertEqual(plans.count, 3)
            if let first { XCTAssertEqual(plans, first, "launch \(launch)") } else { first = plans }
        }
    }

    /// A course's questions come out in one order, the one `itemSnapshots()` uses, not the store's.
    func testACoursesQuestionsComeOutInOneOrder() throws {
        let cal = EngineTest.calendar("America/New_York")
        let clock = TestClock(EngineTest.date(2026, 11, 6, 14, in: cal))
        let app = try StudyTestApp.make(clock: clock, calendar: cal)
        SampleData.seed(into: app)
        for course in app.courses {
            let ids = app.itemSnapshots(in: course).map(\.id)
            XCTAssertEqual(ids, ids.sorted(), course.name)
            XCTAssertEqual(ids, app.itemSnapshots().filter { $0.courseID == course.id }.map(\.id), course.name)
        }
    }

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
            let next = app.courseReadiness(course)
            lines.append("Library \(course.name): \(next.map { "\(pct($0.value)) ready for \($0.exam.title)" } ?? "Add a date")")
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

    /// The demo world on Friday 6 Nov 2026, 14:00 New York (`CRAMLESS_NOW=2026-11-06T14:00:00-05:00`): the Chem quiz is on Sunday
    /// at 10:00. Prints the numbers the exam page and Today show.
    func testFridayNumbers() throws {
        let cal = EngineTest.calendar("America/New_York")
        let clock = TestClock(EngineTest.iso("2026-11-06T19:00:00Z"))
        let app = try StudyTestApp.make(clock: clock, calendar: cal)
        SampleData.seed(into: app)
        let exams = app.upcomingExams()
        let chem = try XCTUnwrap(exams.first { $0.title == "Chem 110 Quiz" })
        var lines: [String] = []
        for exam in exams {
            let r = app.readiness(for: exam)
            lines.append("\(exam.title): ring \(pct(r.value)) · projected \(pct(r.projected)) · \(r.projectedGrade.letter) \(pct(r.projectedGrade.percent)) · \(r.daysLeft) days")
        }
        let plan = app.plan(for: chem)
        lines.append("Chem plan: " + plan.days.map { "\(cal.dayKey(for: $0.date.addingTimeInterval(43_200)).suffix(5)) \($0.kind.rawValue) \($0.minutes)m +\($0.newItems)n \($0.reviews)r" }.joined(separator: " | "))
        lines.append("Chem curve: " + plan.curve.map { pct($0.value) }.joined(separator: " → "))
        let today = app.todaySummary()
        lines.append("Today: \(today.plannedMinutes) min · \(today.reviews) reviews · \(today.newItems) new · weak \(today.weakChips)")

        // Saturday is the quiz's eve.
        let rChem = app.readiness(for: chem)
        let saturday = try XCTUnwrap(plan.days.first { $0.offset == 1 })
        XCTAssertEqual(saturday.kind, .examEve)
        let skipped = app.plan(for: chem, skipping: [saturday.offset])
        lines.append("Chem if Saturday is skipped: \(pct(skipped.projectedReadiness)) (costs \(Int(((rChem.projected - skipped.projectedReadiness) * 100).rounded())) points)")
        // Today's session, the exam it serves, and where that exam is after it.
        let session = app.todayBuiltSession()
        let focus = app.sessionFocus(session)
        let focusExam = try XCTUnwrap(exams.first { $0.id == focus.examID }, "today's session serves an exam")
        let rFocus = app.readiness(for: focusExam)
        let after = app.readinessAfter(session, for: ExamSnapshot(focusExam))
        let names = app.topicNames()
        lines.append("Focus: \(focusExam.title) · \(Int((focus.focusSeconds / 60).rounded())) of \(session.plannedMinutes) min · topics \(focus.topicIDs.compactMap { names[$0] }) · \(focus.dueCount) due, \(focus.newCount) new, \(focus.weakCount) weak · others \(focus.otherExamIDs.compactMap { id in exams.first { $0.id == id }?.title })")
        lines.append("\(focusExam.title): \(pct(rFocus.value)) ready now · about \(pct(after)) after today")
        lines.append("Chem 110 Quiz after today's session: about \(pct(app.readinessAfter(session, for: ExamSnapshot(chem)))) (now \(pct(rChem.value)), \(Int(((focus.secondsByExam[chem.id] ?? 0) / 60).rounded())) min of it)")
        lines.append("Shared plans: " + app.examPlans().map { p in "\(exams.first { $0.id == p.examID }?.title ?? "?") " + p.days.prefix(4).map { "\($0.offset):\(Int($0.seconds))s/\(Int($0.neededSeconds))s" }.joined(separator: " ") }.joined(separator: " | "))
        // The exam page and the Library read the same numbers.
        let phase = ExamPresentation.phase(examDate: chem.date, now: app.now, calendar: cal)
        let topics = ExamPresentation.topicsWeakestFirst(rChem.topics, target: rChem.target)
        let projection = try XCTUnwrap(ExamPresentation.projection(
            phase: phase, plan: plan, questionCount: rChem.itemsInScope, weakestTopic: topics.first { $0.isWeakest }?.name,
            grade: rChem.projectedGrade, examDate: chem.date, now: app.now, calendar: cal))
        let work = ExamPresentation.todayWork(entries: session.entries, sessionMinutes: session.plannedMinutes, exam: ExamSnapshot(chem),
                                              topicNames: names, studiedToday: false, missedYesterday: false)
        let stops = ExamPresentation.stops(plan: plan, phase: phase, examTitle: chem.title, examDate: chem.date, today: work,
                                           skipped: nil, now: app.now, calendar: cal)
        lines.append("Chem page: \(projection.sentence) \(projection.nudge ?? "") · letter \(projection.letter ?? "none")")
        lines.append("Chem stops: " + stops.map { "\($0.title) [\($0.detail ?? "")]" }.joined(separator: " → "))
        lines.append("Chem topics: " + topics.map { "\($0.name) \($0.value.map(pct) ?? "gap")\($0.isWeakest ? " (weakest)" : "")" }.joined(separator: ", "))
        for course in app.courses {
            lines.append("Library \(course.name): \(app.courseReadiness(course).map { "\(pct($0.value)) for \($0.exam.title)" } ?? "Add a date")")
        }
        print("\n===== DEMO FRIDAY =====\n" + lines.joined(separator: "\n") + "\n=======================\n")

        let chemCourse = try XCTUnwrap(chem.course)
        XCTAssertEqual(app.courseReadiness(chemCourse)?.value ?? -1, rChem.value, accuracy: 1e-12, "the Library ring is the exam ring")
        XCTAssertNil(projection.letter, "one logged grade or none: no letter")
        XCTAssertTrue(projection.sentence.contains("ready by Sunday"), projection.sentence)
        XCTAssertNil(app.courseReadiness(try XCTUnwrap(app.courses.first { $0.name == "Spanish II" })), "Spanish II has no exam")

        XCTAssertLessThan(rChem.projected, 0.8, "hours counted, right and wrong answers both in the forecast")
        XCTAssertLessThan(skipped.projectedReadiness, rChem.projected, "skipping the eve costs readiness")
        XCTAssertGreaterThanOrEqual(after, rFocus.value)
        XCTAssertLessThanOrEqual(after, 1)

        // The day card: the quiz in two days, though Bio has more of the session.
        XCTAssertEqual(focus.examID, chem.id)
        let snapshot = TodaySnapshot.make(app: app)
        let names2 = snapshot.focus?.topics ?? []
        XCTAssertEqual(snapshot.focus?.exam.title, "Chem 110 Quiz")
        let input = app.todayReasonsInput()
        XCTAssertEqual(names2.first, input.weakestName, "the title and \"Why these?\" agree on the weakest")
        let saturdayStrip = try XCTUnwrap(snapshot.strip.first { $0.offset == 1 })
        // Saturday's eve is tomorrow: its button, the strip and the exam page's plan say one number.
        let builtEve = app.builtEveMinutes(examID: chem.id)
        XCTAssertEqual(saturdayStrip.mark, .eve(minutes: builtEve))
        let stopsWithEve = ExamPresentation.stops(plan: plan, phase: phase, examTitle: chem.title, examDate: chem.date, today: work,
                                                  skipped: nil, tonightMinutes: builtEve, now: app.now, calendar: cal)
        XCTAssertTrue(stopsWithEve.contains { $0.kind == .eve && $0.title.hasSuffix("about \(builtEve) min") }, "\(stopsWithEve.map(\.title))")
        // The card and "Why these?" are true of the session the button starts.
        XCTAssertEqual(snapshot.summary.plannedQuestions, session.entries.count)
        XCTAssertEqual(input.sessionTotal, session.entries.count)
        XCTAssertLessThan(input.examQuestions, input.sessionTotal, "the demo's session holds other exams too")
        XCTAssertTrue(TodayHeroContent.make(snapshot).reason.hasSuffix("About \(session.entries.count) questions fit in today's session."),
                      TodayHeroContent.make(snapshot).reason)
        print("\n===== DEMO CARD =====\n\(TodayHeroContent.make(snapshot).chip?.text ?? "") · \(TodayHeroContent.make(snapshot).when ?? "") · \(TodayHeroContent.make(snapshot).title) · \(pct(snapshot.focus?.exam.readiness ?? 0)) → \(pct(snapshot.focus?.forecast ?? 0)) · strip Sat \(saturdayStrip.mark)\nWhy: " + TodayReasons.make(input).map { "\($0.title) [\($0.detail ?? "")]" }.joined(separator: " | ") + "\n=====================\n")
    }
}
