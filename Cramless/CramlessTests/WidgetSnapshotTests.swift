import XCTest
@testable import Cramless

/// The snapshot the widgets read: storage, rolling forward across midnight, the builder, the timeline and the copy.
final class WidgetSnapshotTests: XCTestCase {
    private let cal = WidgetTestSupport.calendar
    private let now = WidgetTestSupport.now
    private var sample: WidgetSnapshot { .sample(now: now, calendar: cal) }

    // MARK: Quiet mode

    func testQuietModeTakesTheFlameOffTheTodayWidgetOnly() {
        var quiet = sample
        XCTAssertGreaterThan(quiet.streak.current, 0)
        XCTAssertEqual(quiet.forTodayWidget, quiet, "nothing changes with Quiet mode off")
        quiet.quiet = true
        XCTAssertEqual(quiet.forTodayWidget.streak.current, 0, "the Today widget has no streak to show")
        XCTAssertEqual(quiet.streak.current, sample.streak.current, "a placed Streak widget reads the snapshot as it is")
    }

    func testASnapshotFromBeforeQuietModeStillReads() throws {
        let encoded = try JSONEncoder().encode(sample)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["quiet"] = nil
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(try JSONDecoder().decode(WidgetSnapshot.self, from: data).quiet)
    }

    func testTheBuilderWritesQuietModeOnlyWhenItIsOn() {
        let summary = TodaySummary(minutesGoal: 15)
        let off = WidgetSnapshotBuilder.make(now: now, summary: summary, streak: StreakState(current: 4), exams: [], courses: [])
        XCTAssertNil(off.quiet)
        let on = WidgetSnapshotBuilder.make(now: now, summary: summary, streak: StreakState(current: 4), exams: [], courses: [], quiet: true)
        XCTAssertEqual(on.quiet, true)
    }

    // MARK: Storage

    func testRoundTripsThroughTheStore() throws {
        let folder = try WidgetTestSupport.temporaryFolder()
        let store = WidgetSnapshotStore(directory: folder)
        XCTAssertNil(store.read(), "nothing written yet")
        XCTAssertTrue(store.write(sample))
        XCTAssertEqual(store.read(), sample)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "widget-snapshot.json").path))

        var changed = sample
        changed.streak.current = 13
        XCTAssertTrue(store.write(changed))
        XCTAssertEqual(store.read()?.streak.current, 13, "a second write replaces the first")
        store.remove()
        XCTAssertNil(store.read())
    }

    func testWithoutAnAppGroupNothingHappens() {
        let store = WidgetSnapshotStore(directory: nil)
        XCTAssertFalse(store.isAvailable)
        XCTAssertFalse(store.write(sample))
        XCTAssertNil(store.read())
        store.remove()
    }

    func testUnreadableOrNewerFilesReadAsNothing() throws {
        let folder = try WidgetTestSupport.temporaryFolder()
        let store = WidgetSnapshotStore(directory: folder)
        try Data("not json".utf8).write(to: XCTUnwrap(store.fileURL))
        XCTAssertNil(store.read())
        var future = sample
        future.version = WidgetSnapshot.currentVersion + 1
        XCTAssertTrue(store.write(future))
        XCTAssertNil(store.read(), "a snapshot from a newer build is ignored, not misread")
    }

    func testCarriedOverIsNeverStored() throws {
        var s = sample
        s.today.carriedOver = true
        let data = try WidgetSnapshotStore.encoder.encode(s)
        let back = try WidgetSnapshotStore.decoder.decode(WidgetSnapshot.self, from: data)
        XCTAssertFalse(back.today.carriedOver)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("carriedOver"))
    }

    // MARK: Rolling forward

    func testSameDayReadsAsWritten() {
        let later = cal.date(byAdding: .hour, value: 10, to: now)!
        XCTAssertEqual(sample.rolled(to: later, calendar: cal), sample)
    }

    func testNextDayAfterStudyingKeepsTheStreakAndEmptiesToday() {
        var s = sample
        s.streak.studiedToday = true
        s.streak.current = 13
        s.today.doneMinutes = 16
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let r = s.rolled(to: tomorrow, calendar: cal)
        XCTAssertEqual(r.streak.current, 13)
        XCTAssertFalse(r.streak.studiedToday)
        XCTAssertEqual(r.streak.freezes, 1, "no freeze used")
        XCTAssertEqual(r.today.doneMinutes, 0)
        XCTAssertTrue(r.today.carriedOver)
        XCTAssertTrue(r.today.ready)
        XCTAssertNil(WidgetCopy.sessionCounts(r.today), "yesterday's counts aren't shown as today's")
        XCTAssertEqual(r.today.sessionMinutes, 15, "the goal stands in for today's plan")
    }

    func testAMissedDayUsesAFreeze() {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let r = sample.rolled(to: tomorrow, calendar: cal)   // not studied on the snapshot's day, one freeze
        XCTAssertEqual(r.streak.current, 12)
        XCTAssertEqual(r.streak.freezes, 0)
    }

    func testMoreMissedDaysThanFreezesEndTheStreak() {
        let later = cal.date(byAdding: .day, value: 2, to: now)!
        XCTAssertEqual(sample.rolled(to: later, calendar: cal).streak.current, 0)
    }

    func testExamsDropOffAfterTheyEnd() {
        var s = sample
        s.exams.insert(.init(id: UUID(), title: "Chem 110 Quiz", courseName: "Chem 110", color: .tangerine,
                             date: WidgetTestSupport.date(2026, 10, 23, 10), readiness: 0.4, delta: 0), at: 0)
        XCTAssertEqual(s.rolled(to: WidgetTestSupport.date(2026, 10, 23, 12), calendar: cal).nextExam?.title,
                       "Chem 110 Quiz", "still on during the exam")
        XCTAssertEqual(s.rolled(to: WidgetTestSupport.date(2026, 10, 23, 13, 1), calendar: cal).nextExam?.title,
                       "Bio 101 Midterm", "gone three hours after it starts")
    }

    func testDaysLeftCountsCalendarDaysAcrossDaylightSaving() {
        let exam = WidgetSnapshot.Exam(id: UUID(), title: "Bio 101 Midterm", courseName: "Bio 101", color: .sky,
                                       date: WidgetTestSupport.date(2026, 11, 2, 9), readiness: 0.6, delta: 0)
        // Oct 31 23:30 → Nov 2 09:00 crosses the Nov 1 change: still 2 days.
        XCTAssertEqual(sample.daysLeft(to: exam, from: WidgetTestSupport.date(2026, 10, 31, 23, 30), calendar: cal), 2)
        XCTAssertEqual(sample.daysLeft(to: exam, from: WidgetTestSupport.date(2026, 11, 2, 0, 5), calendar: cal), 0)
    }

    // MARK: Builder

    func testBuilderSortsCapsAndClamps() {
        var summary = TodaySummary(minutesGoal: 15)
        summary.plannedMinutes = 22
        summary.reviews = 18
        summary.newItems = 6
        summary.weakSpots = 2
        summary.weakChips = ["Meiosis I vs II", "Chromosome number", "Cytokinesis", "Mitosis"]
        summary.sessionReady = true
        summary.studiedToday = true
        let streak = StreakState(current: 12, best: 20, studiedToday: false, freezesAvailable: 2)
        func exam(_ title: String, _ days: Int, _ r: Double) -> WidgetSnapshotBuilder.ExamInput {
            .init(id: UUID(), title: title, courseName: title, color: .sky,
                  date: cal.date(byAdding: .day, value: days, to: now)!, readiness: r, delta: 2)
        }
        let s = WidgetSnapshotBuilder.make(now: now, summary: summary, streak: streak,
                                           exams: [exam("D", 40, 0.5), exam("A", 2, 1.4), exam("C", 30, -0.2), exam("B", 9, 0.6)],
                                           courses: [])
        XCTAssertEqual(s.exams.map(\.title), ["A", "B", "C"], "soonest first, at most three")
        XCTAssertEqual(s.exams.map(\.readiness), [1, 0.6, 0])
        XCTAssertEqual(WidgetSnapshotBuilder.rounded(0.64444), 0.644, "hair-width drift doesn't rewrite the snapshot")
        XCTAssertEqual(s.exams.first?.delta, 1)
        XCTAssertTrue(s.streak.studiedToday, "studied today from either source")
        XCTAssertEqual(s.streak.freezes, 2)
        XCTAssertEqual(s.today.weakChips.count, 3)
        XCTAssertEqual(s.today.sessionMinutes, 22)
        XCTAssertEqual(s.generatedAt, now)
    }

    @MainActor
    func testTheAppBuildsItsSnapshotFromTheDemoWorld() throws {
        let previous = AppModel.live
        defer { AppModel.live = previous }
        let app = WidgetTestSupport.makeApp(seed: true)
        let s = app.makeWidgetSnapshot()
        XCTAssertEqual(s.exams.map(\.title), ["Chem 110 Quiz", "Bio 101 Midterm", "AP Psych Exam"])
        XCTAssertEqual(s.exams.map(\.courseName), ["Chem 110", "Bio 101", "AP Psychology"])
        XCTAssertEqual(s.exams.map(\.color), [.tangerine, .sky, .mint])
        XCTAssertEqual(s.daysLeft(to: try XCTUnwrap(s.nextExam), from: app.now, calendar: app.calendar), 2)
        XCTAssertEqual(s.courses.map(\.name), ["Bio 101", "Chem 110", "AP Psychology", "Spanish II"])
        XCTAssertEqual(s.today.goalMinutes, 15)
    }

    // MARK: Timeline

    func testTimelineRedrawsAtMidnightAndWhenAnExamEnds() {
        var s = sample
        s.exams.insert(.init(id: UUID(), title: "Chem 110 Quiz", courseName: "Chem 110", color: .tangerine,
                             date: WidgetTestSupport.date(2026, 10, 23, 10), readiness: 0.4, delta: 0), at: 0)
        let dates = WidgetTimeline.dates(from: now, snapshot: s, calendar: cal)
        XCTAssertEqual(dates, [now, WidgetTestSupport.date(2026, 10, 23), WidgetTestSupport.date(2026, 10, 23, 13),
                               WidgetTestSupport.date(2026, 10, 24)])
        let entries = WidgetTimeline.entries(from: now, stored: s, calendar: cal)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[1].snapshot?.today.carriedOver, true)
        XCTAssertEqual(entries[2].snapshot?.nextExam?.title, "Bio 101 Midterm")
        XCTAssertNil(WidgetTimeline.entries(from: now, stored: nil, calendar: cal).first?.snapshot)
    }

    func testRelevanceRisesBeforeAnExam() {
        var s = sample
        XCTAssertEqual(WidgetTimeline.relevance(of: s, at: now, calendar: cal)?.score, 40)
        s.exams[0].date = WidgetTestSupport.date(2026, 10, 23, 9)
        XCTAssertEqual(WidgetTimeline.relevance(of: s, at: now, calendar: cal)?.score, 80)
        s.streak.studiedToday = true
        s.exams = []
        XCTAssertNil(WidgetTimeline.relevance(of: s, at: now, calendar: cal))
    }

    // MARK: Copy

    func testInlineLine() {
        var s = sample
        XCTAssertEqual(WidgetCopy.inline(s), "12-day streak · 15 min today")
        s.today.doneMinutes = 6
        XCTAssertEqual(WidgetCopy.inline(s), "12-day streak · 6 of 15 min")
        s.streak.studiedToday = true
        s.streak.current = 13
        XCTAssertEqual(WidgetCopy.inline(s), "13-day streak · done today")
        s.streak.current = 0
        XCTAssertEqual(WidgetCopy.inline(s), "Done for today")
        s.streak.studiedToday = false
        s.today.doneMinutes = 0
        XCTAssertEqual(WidgetCopy.inline(s), "15 min today")
        XCTAssertEqual(WidgetCopy.inline(nil), "Open Capling to start")
    }

    func testTodayGlance() {
        var s = sample
        XCTAssertEqual(WidgetCopy.todayGlance(s).headline, "18 due")
        XCTAssertEqual(WidgetCopy.todayGlance(s).detail, "15 min keeps your streak")
        s.streak.current = 1
        XCTAssertEqual(WidgetCopy.todayGlance(s).detail, "15 min today")
        s.today.reviews = 0
        XCTAssertEqual(WidgetCopy.todayGlance(s).headline, "6 new")
        s.streak.studiedToday = true
        XCTAssertEqual(WidgetCopy.todayGlance(s).headline, "Done")
        XCTAssertEqual(WidgetCopy.todayGlance(nil).headline, "Get started")
    }

    func testCountsKeepEachPartTogether() {
        var today = sample.today
        XCTAssertEqual(WidgetCopy.sessionCounts(today), "18\u{00A0}reviews · 6\u{00A0}new · 2\u{00A0}weak\u{00A0}spots")
        today.reviews = 1
        today.newItems = 0
        today.weakSpots = 1
        XCTAssertEqual(WidgetCopy.sessionCounts(today), "1\u{00A0}review · 1\u{00A0}weak\u{00A0}spot")
        XCTAssertEqual(WidgetCopy.weakSpotsLine(sample.today), "Weak spots: Meiosis I vs II, Chromosome number")
        XCTAssertEqual(WidgetCopy.weakSpotsLine(sample.today, maxNames: 1), "Weak spots: Meiosis I vs II +1")
    }

    func testDaysAndDelta() {
        XCTAssertEqual(WidgetCopy.days(0), "Today")
        XCTAssertEqual(WidgetCopy.days(1), "Tomorrow")
        XCTAssertEqual(WidgetCopy.days(23), "23 days")
        XCTAssertEqual(WidgetCopy.daysShort(6), "6d")
        XCTAssertEqual(WidgetCopy.delta(0.05), "+5% this week")
        XCTAssertEqual(WidgetCopy.delta(-0.031), "−3% this week")
        XCTAssertNil(WidgetCopy.delta(0.004))
        XCTAssertEqual(WidgetCopy.percent(0.645), 65)
        XCTAssertEqual(WidgetCopy.percent(1.3), 100)
    }

    func testSiriAnswer() {
        XCTAssertEqual(WidgetCopy.readinessAnswer(sample, now: now, calendar: cal),
                       "64% ready for Bio 101 Midterm, 23 days to go. Up 5 points this week.")
        var s = sample
        s.exams.insert(.init(id: UUID(), title: "Chem 110 Quiz", courseName: "Chem 110", color: .tangerine,
                             date: WidgetTestSupport.date(2026, 10, 23, 10), readiness: 0.41, delta: 0), at: 0)
        XCTAssertEqual(WidgetCopy.readinessAnswer(s, now: now, calendar: cal),
                       "41% ready for Chem 110 Quiz. It's tomorrow. Next: Bio 101 Midterm in 23 days, 64% ready.")
        s.exams[0].readiness = 0.02
        XCTAssertTrue(WidgetCopy.readinessAnswer(s, now: now, calendar: cal)
            .hasPrefix("You're just getting started on Chem 110 Quiz, and it's tomorrow."))
        s.exams = []
        XCTAssertEqual(WidgetCopy.readinessAnswer(s, now: now, calendar: cal),
                       "You haven't added an exam yet. Add one in Capling and it will track how ready you are.")
        XCTAssertEqual(WidgetCopy.readinessAnswer(nil, now: now, calendar: cal),
                       "Open Capling once and I can tell you how ready you are.")
    }

    func testExamAccessibility() {
        XCTAssertEqual(WidgetCopy.examAccessibility(sample.exams[0], daysLeft: 23),
                       "Bio 101 Midterm, 64 percent ready, 23 days left, +5 percent this week")
    }
}
