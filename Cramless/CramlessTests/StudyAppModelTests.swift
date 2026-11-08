import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// A settable clock for an AppModel under test.
final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
enum StudyTestApp {
    /// An in-memory AppModel with its own defaults, a fixed calendar and a settable clock. `defaults` and `container`: another launch
    /// over the same ones.
    static func make(clock: TestClock, calendar: Calendar, defaults: UserDefaults? = nil, container: ModelContainer? = nil) throws -> AppModel {
        let defaults = defaults ?? UserDefaults(suiteName: "capling.tests.\(UUID().uuidString)")!
        let app = AppModel(container: try container ?? Persistence.makeContainer(inMemory: true), defaults: defaults)
        app.calendar = calendar
        app.clock = { clock.now }
        return app
    }
}

@MainActor
final class StudyAppModelTests: XCTestCase {
    let cal = EngineTest.calendar()
    var clock: TestClock!
    var app: AppModel!
    var previousLive: AppModel?

    override func setUp() async throws {
        previousLive = AppModel.live
        clock = TestClock(EngineTest.date(2026, 10, 22, 18, in: cal))
        app = try StudyTestApp.make(clock: clock, calendar: cal)
        AppModel.schedulerFuzz = false
    }

    override func tearDown() async throws {
        AppModel.schedulerFuzz = true
        AppModel.live = previousLive
        app = nil
    }

    @discardableResult
    func makeCourse(_ name: String = "Bio 101") -> Course {
        let course = Course(name: name, now: clock.now)
        app.context.insert(course)
        return course
    }

    @discardableResult
    func makeItem(in course: Course, kind: ItemKind = .flashcard, status: ItemStatus = .active,
                  answer: String = "Answer", memory: MemoryState? = nil) -> StudyItem {
        let item = StudyItem(course: course, kind: kind, status: status, origin: .person, prompt: "Question?",
                             answer: answer, now: clock.now)
        if let memory { item.memory = memory }
        app.context.insert(item)
        course.items.append(item)
        return item
    }

    func addDays(_ pattern: String, endingDaysAgo: Int = 1) {
        let chars = Array(pattern)
        for (i, ch) in chars.enumerated() where ch != "-" {
            let back = endingDaysAgo + (chars.count - 1 - i)
            let at = cal.adding(days: -back, to: clock.now)
            let record = DayRecord(dayKey: cal.dayKey(for: at), day: cal.startOfDay(for: at),
                                   studySeconds: ch == "s" ? 600 : 0, itemsReviewed: ch == "s" ? 12 : 0,
                                   sessions: ch == "s" ? 1 : 0, frozen: ch == "f")
            app.context.insert(record)
        }
    }

    func testASessionFromStartToSummary() throws {
        let course = makeCourse()
        let item = makeItem(in: course)
        app.save()

        let built = app.buildSession(SessionRequest(kind: .daily))
        XCTAssertEqual(built.newCount, 1)
        let session = app.startSession(built)

        let first = try XCTUnwrap(app.recordReview(itemID: item.id, rating: .good, durationMs: 8000, sessionID: session.id))
        XCTAssertEqual(first.before.state, .new)
        XCTAssertEqual(first.after.state, .learning)
        XCTAssertTrue(first.stillLearning)
        XCTAssertEqual(first.after.stability, FSRS().initialStability(.good))

        let record = try XCTUnwrap(app.dayRecord(key: cal.dayKey(for: clock.now)))
        XCTAssertEqual(record.sessions, 1)
        XCTAssertEqual(record.itemsReviewed, 1)
        XCTAssertEqual(record.studySeconds, 8, accuracy: 1e-9)
        XCTAssertEqual(session.itemCount, 1)
        XCTAssertEqual(session.correctCount, 1)

        clock.advance(600)
        let second = try XCTUnwrap(app.recordReview(itemID: item.id, rating: .good, durationMs: 5000, sessionID: session.id))
        XCTAssertEqual(second.after.state, .review)
        XCTAssertEqual(item.memory, second.after)
        XCTAssertEqual(record.sessions, 1, "one session, however many answers")

        let logs = app.fetch(FetchDescriptor<ReviewLog>(sortBy: [SortDescriptor(\.reviewedAt)]))
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs[0].stateBeforeRaw, CardState.new.rawValue)
        XCTAssertEqual(logs[0].stabilityAfter, FSRS().initialStability(.good))
        XCTAssertEqual(logs[1].stateBeforeRaw, CardState.learning.rawValue)
        XCTAssertEqual(logs[1].stabilityBefore, logs[0].stabilityAfter)
        XCTAssertEqual(logs[1].sessionID, session.id)
        XCTAssertGreaterThanOrEqual(logs[1].scheduledDays, 1)

        let summary = app.finishSession(session)
        XCTAssertEqual(summary.answers, 2)
        XCTAssertEqual(summary.itemsReviewed, 1)
        XCTAssertEqual(summary.correctFirstTry, 1)
        XCTAssertEqual(summary.accuracy, 1)
        XCTAssertEqual(summary.newLearned, 1)
        XCTAssertEqual(summary.streak.current, 1)
        XCTAssertTrue(summary.streak.studiedToday)
        XCTAssertTrue(summary.streakExtended)
        XCTAssertFalse(summary.stopNow)
        XCTAssertNotNil(session.endedAt)
        // The day's minutes are topped up from the 13 s of answering toward the session's 10 minutes of wall
        // time, capped at twice the plan (18 s here) with a one-minute floor, so a session left open doesn't count.
        XCTAssertEqual(record.studySeconds, 60, accuracy: 1e-6)
        XCTAssertEqual(summary.minutes, 1)
        // Finishing twice changes nothing.
        let again = app.finishSession(session)
        XCTAssertEqual(record.studySeconds, 60, accuracy: 1e-6)
        XCTAssertEqual(again.answers, summary.answers)
        XCTAssertEqual(again.correctFirstTry, summary.correctFirstTry)
    }

    func testWallTimeCountsForARealSession() throws {
        let course = makeCourse()
        for _ in 0..<20 { makeItem(in: course, kind: .recall) }
        app.save()
        let built = app.buildSession(SessionRequest(kind: .daily))
        XCTAssertEqual(built.newCount, 5, "the default new quota for 15 minutes")
        XCTAssertEqual(built.plannedSeconds, 500, accuracy: 1e-9)
        let session = app.startSession(built)
        for entry in built.entries {
            clock.advance(90)
            app.recordReview(itemID: entry.itemID, rating: .good, durationMs: 40_000, sessionID: session.id)
        }
        let summary = app.finishSession(session)
        XCTAssertEqual(app.dayRecord(key: cal.dayKey(for: clock.now))?.studySeconds ?? 0, 450, accuracy: 1e-6)
        XCTAssertEqual(summary.minutes, 8)
    }

    func testSummaryReportsReadinessForTheNextExam() throws {
        let course = makeCourse()
        for _ in 0..<4 { makeItem(in: course) }
        let exam = Exam(course: course, title: "Midterm", date: cal.adding(days: 10, to: clock.now), now: clock.now)
        app.context.insert(exam)
        app.save()
        let built = app.buildSession(SessionRequest(kind: .daily))
        let session = app.startSession(built)
        XCTAssertEqual(session.examID, exam.id)
        XCTAssertEqual(session.readinessBefore, 0)
        for entry in built.entries {
            app.recordReview(itemID: entry.itemID, rating: .easy, durationMs: 4000, sessionID: session.id)
        }
        let summary = app.finishSession(session)
        XCTAssertEqual(summary.examTitle, "Midterm")
        XCTAssertGreaterThan(try XCTUnwrap(summary.readinessDelta), 0.5)
    }

    /// The delta beside "53% → 67%" is the difference of the two numbers on screen, not a rounding of the raw gap (13.2 points).
    func testTheSummarysDeltaIsTheDifferenceOfTheRoundedNumbers() throws {
        var summary = SessionSummary(sessionID: UUID(), kind: .daily, answers: 1, itemsReviewed: 1, correctFirstTry: 1, accuracy: 1, newLearned: 0,
                                     minutes: 1, examID: nil, examTitle: nil, readinessBefore: 0.534, readinessAfter: 0.666,
                                     streak: StreakState(), streakExtended: false, repairedDay: nil, stopNow: false)
        XCTAssertEqual(CLFormat.percent(0.534), "53%")
        XCTAssertEqual(CLFormat.percent(0.666), "67%")
        XCTAssertEqual(CLFormat.delta(try XCTUnwrap(summary.readinessDelta)), "+14%")
        summary.readinessBefore = 0.671
        summary.readinessAfter = 0.666
        XCTAssertEqual(CLFormat.delta(try XCTUnwrap(summary.readinessDelta)), "±0%")
        summary.readinessAfter = nil
        XCTAssertNil(summary.readinessDelta)
    }

    func testRolloverFreezesASingleMissedDay() throws {
        makeCourse()
        addDays("sssssss", endingDaysAgo: 2)
        app.save()
        XCTAssertEqual(app.streak().current, 8, "the read model applies the freeze before the rollover writes it")
        app.applyDailyRollover()
        let yesterday = try XCTUnwrap(app.dayRecord(key: cal.dayKey(for: cal.adding(days: -1, to: clock.now))))
        XCTAssertTrue(yesterday.frozen)
        XCTAssertEqual(app.streak().current, 8)
        XCTAssertEqual(app.streak().freezesAvailable, 0)
        app.applyDailyRollover()
        XCTAssertEqual(app.fetch(FetchDescriptor<DayRecord>()).filter(\.frozen).count, 1, "idempotent")
    }

    func testRefreshingTodayRollsTheDayOverAndWaitsForNothingWithoutSync() async throws {
        makeCourse()
        addDays("sssssss", endingDaysAgo: 2)
        app.save()
        let began = Date()
        let reached = await app.refreshToday()
        XCTAssertTrue(reached, "with no account to reach there is nothing that can fail")
        XCTAssertLessThan(Date().timeIntervalSince(began), 1)
        let yesterday = try XCTUnwrap(app.dayRecord(key: cal.dayKey(for: cal.adding(days: -1, to: clock.now))))
        XCTAssertTrue(yesterday.frozen, "the same rollover as on launch")
        let again = await app.refreshToday()
        XCTAssertTrue(again)
        XCTAssertEqual(app.fetch(FetchDescriptor<DayRecord>()).filter(\.frozen).count, 1, "idempotent")
    }

    func testRolloverKeepsReadinessOnExamMorning() throws {
        let course = makeCourse()
        makeItem(in: course, memory: MemoryState(state: .review, stability: 30, difficulty: 5,
                                                 due: cal.adding(days: 20, to: clock.now),
                                                 lastReview: cal.adding(days: -2, to: clock.now), reps: 3))
        let exam = Exam(course: course, title: "Quiz", date: cal.adding(days: 1, to: clock.now), now: clock.now)
        app.context.insert(exam)
        app.save()
        app.applyDailyRollover()
        XCTAssertNil(exam.readinessAtExam, "not yet")
        clock.advance(26 * 3600)
        app.applyDailyRollover()
        let kept = try XCTUnwrap(exam.readinessAtExam)
        XCTAssertGreaterThan(kept, 0.8)
    }

    func testADoubleSessionRepairsAMissedDay() throws {
        let course = makeCourse()
        let items = (0..<3).map { _ in makeItem(in: course) }
        addDays("sssss-s")
        app.save()
        let missed = cal.startOfDay(for: cal.adding(days: -2, to: clock.now))
        XCTAssertEqual(app.streak().repairableDay, missed)
        let built = app.buildSession(SessionRequest(kind: .daily))
        let session = app.startSession(built)
        // 31 minutes of answering today: twice the 15-minute goal.
        for (i, item) in items.enumerated() {
            app.recordReview(itemID: item.id, rating: .good, durationMs: i == 0 ? 31 * 60 * 1000 : 1000, sessionID: session.id)
        }
        let summary = app.finishSession(session)
        XCTAssertEqual(summary.repairedDay, missed)
        XCTAssertEqual(try XCTUnwrap(app.dayRecord(key: cal.dayKey(for: missed.addingTimeInterval(43_200)))).repaired, true)
        XCTAssertEqual(summary.streak.current, 8)
        XCTAssertNil(summary.streak.repairableDay)
    }

    func testAnAgainOnAConfusedItemCountsTheMiss() throws {
        let course = makeCourse()
        let a = makeItem(in: course, memory: MemoryState(state: .review, stability: 5, difficulty: 6, due: clock.now,
                                                          lastReview: cal.adding(days: -5, to: clock.now), reps: 3))
        let confusion = Confusion(course: course, name: "Anaphase vs telophase", explanation: "", itemIDs: [a.id],
                                  missCount: 3, now: clock.now)
        app.context.insert(confusion)
        app.save()
        let outcome = try XCTUnwrap(app.recordReview(itemID: a.id, rating: .again, answer: "Telophase"))
        XCTAssertFalse(outcome.wasCorrect)
        XCTAssertEqual(outcome.after.state, .relearning)
        XCTAssertEqual(outcome.after.lapses, 1)
        XCTAssertEqual(confusion.missCount, 4)
        // A review without a session still makes the day count.
        XCTAssertEqual(app.dayRecord(key: cal.dayKey(for: clock.now))?.sessions, 1)
    }

    func testSuspendedItemsStayOutOfSessions() {
        let course = makeCourse()
        let item = makeItem(in: course)
        app.save()
        XCTAssertEqual(app.buildSession(SessionRequest(kind: .daily)).entries.count, 1)
        app.suspend(item)
        XCTAssertEqual(item.status, .suspended)
        XCTAssertTrue(app.buildSession(SessionRequest(kind: .daily)).isEmpty)
        app.unsuspend(item)
        XCTAssertEqual(item.status, .active)
        XCTAssertFalse(app.buildSession(SessionRequest(kind: .daily)).isEmpty)
    }

    func testQuickCheckRunsOnDraftItems() {
        let course = makeCourse()
        let draft = makeItem(in: course, status: .draft)
        app.save()
        let built = app.buildSession(SessionRequest(kind: .quickCheck, itemIDs: [draft.id]))
        XCTAssertEqual(built.entries.map(\.itemID), [draft.id])
    }

    func testTopicPractice() {
        let course = makeCourse()
        let topic = Topic(course: course, name: "Meiosis", now: clock.now)
        app.context.insert(topic)
        let inTopic = makeItem(in: course)
        inTopic.topicID = topic.id
        makeItem(in: course)
        app.save()
        let built = app.buildSession(SessionRequest(kind: .practice, courseID: course.id, topicID: topic.id))
        XCTAssertEqual(built.entries.map(\.itemID), [inTopic.id])
    }

    func testScoreToRatingThresholds() {
        XCTAssertEqual(AppModel.rating(forScore: 0), .again)
        XCTAssertEqual(AppModel.rating(forScore: 0.59), .again)
        XCTAssertEqual(AppModel.rating(forScore: 0.6), .hard)
        XCTAssertEqual(AppModel.rating(forScore: 0.67), .hard, "the grade-partial fixture")
        XCTAssertEqual(AppModel.rating(forScore: 0.8), .good)
        XCTAssertEqual(AppModel.rating(forScore: 1), .good)
        XCTAssertEqual(AppModel.rating(forScore: 1, kind: .recall, durationMs: 20_000), .easy)
        XCTAssertEqual(AppModel.rating(forScore: 1, kind: .recall, durationMs: 45_000), .good)
        // Consistent with ReviewLog.wasCorrect.
        for score in stride(from: 0.0, through: 1.0, by: 0.05) {
            let rating = AppModel.rating(forScore: score)
            let snap = ReviewSnapshot(itemID: UUID(), reviewedAt: .now, rating: rating, score: score, stabilityAfter: 1)
            XCTAssertEqual(snap.wasCorrect, score >= 0.6 - 1e-9, "\(score)")
        }
    }

    func testTodaySummaryCountsAndExamEve() {
        let course = makeCourse()
        for _ in 0..<3 { makeItem(in: course) }
        let exam = Exam(course: course, title: "Quiz", date: cal.adding(days: 1, to: clock.now), now: clock.now)
        app.context.insert(exam)
        app.save()
        let today = app.todaySummary()
        XCTAssertEqual(today.minutesGoal, 15)
        XCTAssertEqual(today.newItems, 3)
        XCTAssertTrue(today.sessionReady)
        XCTAssertFalse(today.studiedToday)
        XCTAssertEqual(today.examEveExamID, exam.id)
        XCTAssertGreaterThan(today.plannedMinutes, 0)
    }

    /// Two exams share one daily goal: the sooner exam takes what it needs first and the later one gets what's left; on the
    /// sooner exam's eve, the eve keeps its 10 minutes and the later exam waits.
    func testTwoExamsShareTheDailyGoal() throws {
        let bio = makeCourse("Bio 101"), chem = makeCourse("Chem 110")
        let overdue = MemoryState(state: .review, stability: 1, difficulty: 6, due: cal.adding(days: -2, to: clock.now),
                                  lastReview: cal.adding(days: -3, to: clock.now), reps: 3)
        for _ in 0..<80 { makeItem(in: bio, kind: .mcq, memory: overdue) }
        for _ in 0..<80 { makeItem(in: chem, kind: .mcq, memory: overdue) }
        let quiz = Exam(course: chem, title: "Quiz", date: cal.adding(days: 3, to: clock.now), now: clock.now)
        let midterm = Exam(course: bio, title: "Midterm", date: cal.adding(days: 12, to: clock.now), now: clock.now)
        app.context.insert(quiz)
        app.context.insert(midterm)
        app.save()

        let plans = app.examPlans()
        XCTAssertEqual(plans.map(\.examID), [quiz.id, midterm.id], "soonest first")
        let goal = Double(app.settings.dailyMinutes * 60)
        let first = plans[0], second = plans[1]
        XCTAssertGreaterThan(first.days[0].seconds, 0)
        for day in second.days where day.kind != .exam {
            let other = first.days.first { $0.offset == day.offset }
            if other?.kind == .examEve {
                XCTAssertEqual(day.seconds, 0, "the quiz's eve: the midterm waits")
                XCTAssertLessThanOrEqual(other?.seconds ?? 0, PlanBuilder.examEveSeconds + 1e-9)
            } else {
                XCTAssertLessThanOrEqual(day.seconds + (other?.seconds ?? 0), goal + 1e-9, "day \(day.offset)")
            }
        }
        // Alone, the midterm would have claimed more of today.
        let alone = app.planBuilder().plan(for: ExamSnapshot(midterm), items: app.itemSnapshots(in: bio))
        XCTAssertGreaterThan(alone.days[0].seconds, second.days[0].seconds)
        // Every screen reads the shared plan.
        XCTAssertEqual(app.plan(for: midterm), second)
        let (readiness, plan) = app.readinessAndPlan(for: midterm)
        XCTAssertEqual(plan, second)
        XCTAssertEqual(readiness.projected, second.projectedReadiness)
        XCTAssertEqual(app.readiness(for: midterm), readiness)
        // What if: a day off has no work; with every day off, the projection is the ring now; the shared plan stays as it was.
        let skip = app.plan(for: midterm, skipping: [3])
        XCTAssertTrue(skip.days[3].isSkipped)
        XCTAssertEqual(skip.days[3].seconds, 0)
        XCTAssertEqual(skip.days[3].sessionMinutes, 0)
        let none = app.plan(for: midterm, skipping: Set(0..<12))
        XCTAssertEqual(none.reviewsPlanned, 0)
        XCTAssertEqual(none.projectedReadiness, readiness.value, accuracy: 1e-9)
        XCTAssertLessThan(none.projectedReadiness, second.projectedReadiness)
        XCTAssertEqual(app.plan(for: midterm), second)
    }

    /// The summary's ring follows the exam the session serves (the one Today's card names), not the sooner exam among its courses.
    func testTheTrackedExamIsTheExamTheSessionServes() throws {
        let bio = makeCourse("Bio 101"), chem = makeCourse("Chem 110")
        let due = MemoryState(state: .review, stability: 3, difficulty: 5, due: cal.adding(days: -1, to: clock.now),
                              lastReview: cal.adding(days: -4, to: clock.now), reps: 3)
        makeItem(in: bio, memory: due)
        for _ in 0..<6 { makeItem(in: chem, kind: .mcq, memory: due) }
        let midterm = Exam(course: bio, title: "Midterm", date: cal.adding(days: 4, to: clock.now), now: clock.now)
        let quiz = Exam(course: chem, title: "Quiz", date: cal.adding(days: 6, to: clock.now), now: clock.now)
        app.context.insert(midterm)
        app.context.insert(quiz)
        app.save()
        let built = app.buildSession(SessionRequest(kind: .daily))
        XCTAssertEqual(built.entries.count, 7)
        XCTAssertEqual(app.sessionFocus(built).examID, quiz.id)
        XCTAssertEqual(app.trackedExam(for: built)?.id, quiz.id, "the old rule picked the sooner midterm")
        XCTAssertEqual(app.startSession(built).examID, quiz.id)
        // A session for one exam keeps it.
        let eve = app.buildSession(SessionRequest(kind: .examEve, examID: midterm.id))
        XCTAssertEqual(app.trackedExam(for: eve)?.id, midterm.id)
    }

    /// Follow-through moves a little each day with the record: no day where it jumps from a default to the student's own figure.
    func testHabitsMoveWithTheRecordWithoutASuddenJump() throws {
        makeCourse()
        XCTAssertEqual(app.studyHabits().adherence, StudyHabits.followThroughPrior, accuracy: 1e-9, "no record, no mark against them")
        XCTAssertEqual(app.studyHabits().newItemSuccess, StudyHabits.firstLookPrior, accuracy: 1e-9)
        var previous = app.studyHabits().adherence
        var pattern = Array("ssxsxsssxssxss").makeIterator()
        for _ in 0..<14 {
            let today = app.dayRecord(for: clock.now)
            if pattern.next() == "s" { today.sessions = 1 }
            app.save()
            clock.advance(86_400)
            let now = app.studyHabits().adherence
            XCTAssertLessThan(abs(now - previous), 0.125, "a step of \(now - previous)")
            previous = now
        }
        XCTAssertLessThan(previous, 0.95, "a student who skips comes down")
    }

    func testNextExamIsTheSoonestStillToCome() throws {
        let course = makeCourse()
        let other = makeCourse("Chem 110")
        let past = Exam(course: course, title: "Quiz 1", date: clock.now.addingTimeInterval(-3600), now: clock.now)
        let final = Exam(course: course, title: "Final", date: cal.adding(days: 30, to: clock.now), now: clock.now)
        let midterm = Exam(course: course, title: "Midterm", date: cal.adding(days: 9, to: clock.now), now: clock.now)
        let elsewhere = Exam(course: other, title: "Quiz", date: cal.adding(days: 2, to: clock.now), now: clock.now)
        for exam in [past, final, midterm, elsewhere] { app.context.insert(exam) }
        app.save()
        XCTAssertEqual(app.nextExam(of: course.id)?.id, midterm.id)
        midterm.deletedAt = clock.now
        app.save()
        XCTAssertEqual(app.nextExam(of: course.id)?.id, final.id)
        XCTAssertNil(app.nextExam(of: UUID()))
        clock.advance(31 * 86_400)
        XCTAssertNil(app.nextExam(of: course.id), "only past exams")
    }

    func testInsightsOnAnEmptyStore() {
        XCTAssertEqual(app.todaySummary().sessionReady, false)
        XCTAssertEqual(app.streak(), StreakState())
        XCTAssertEqual(app.heatmap().count, 84)
        XCTAssertEqual(app.weeklyStats().days.count, 7)
        XCTAssertEqual(app.dueForecast().count, 7)
        XCTAssertNil(app.retentionRate())
        XCTAssertTrue(app.confusionCandidates().isEmpty)
    }

    // MARK: Look-alikes

    /// Metaphase and Telophase on a midterm 9 days out, one studied, the other's wrong option naming it.
    private func lookAlikeWorld() throws -> (course: Course, draft: LookAlikeDraft, a: StudyItem, b: StudyItem, pair: LookAlikePair) {
        let course = makeCourse()
        let memory = MemoryState(state: .review, stability: 1, difficulty: 5, due: cal.adding(days: 3, to: clock.now), lastReview: cal.adding(days: -2, to: clock.now), reps: 2)
        func add(_ prompt: String, _ answer: String, wrong: String) -> StudyItem {
            let item = StudyItem(course: course, kind: .mcq, status: .active, origin: .person, prompt: prompt, answer: answer,
                                 choices: [Choice(text: answer, correct: true), Choice(text: wrong, correct: false)], now: clock.now)
            item.memory = memory
            app.context.insert(item)
            course.items.append(item)
            return item
        }
        let a = add("In which phase do chromosomes line up?", "Metaphase", wrong: "Telophase")
        let b = add("Which phase comes before cytokinesis?", "Telophase", wrong: "Metaphase")
        let exam = Exam(course: course, title: "Bio 101 Midterm", date: cal.adding(days: 9, to: clock.now), now: clock.now)
        app.context.insert(exam)
        course.exams.append(exam)
        app.save()
        let card = try XCTUnwrap(app.noticeDeck().first { $0.kind == .lookAlike })
        guard case .lookAlike(let pair) = card.evidence else { throw XCTSkip("not a pair") }
        return (course, try XCTUnwrap(app.lookAlikeDraft(a: pair.a, b: pair.b)), a, b, pair)
    }

    /// An exam `days` out, with `count` multiple-choice questions a mock can use.
    private func mockWorld(examIn days: Int, questions count: Int = 10) -> Exam {
        let course = makeCourse()
        for index in 0..<count {
            let item = StudyItem(course: course, kind: .mcq, status: .active, origin: .person, prompt: "A question that has number \(index) in it", answer: "A long answer that names nothing \(index)",
                                 choices: [Choice(text: "Right \(index)", correct: true), Choice(text: "Wrong \(index)", correct: false)], now: clock.now)
            app.context.insert(item)
            course.items.append(item)
        }
        let exam = Exam(course: course, title: "Bio 101 Midterm", date: cal.adding(days: days, to: clock.now), now: clock.now)
        app.context.insert(exam)
        course.exams.append(exam)
        app.save()
        // A quarter or more studied, or Today doesn't offer it.
        for item in course.items.prefix(max(1, count / 3)) { app.recordReview(itemID: item.id, rating: .good, score: 1, answer: "Right", gradedBy: "rules") }
        return exam
    }

    func testNoMockCardWithNothingStudied() {
        let course = makeCourse()
        for index in 0..<12 {
            let item = StudyItem(course: course, kind: .mcq, status: .active, origin: .person, prompt: "A question that has number \(index) in it", answer: "A long answer",
                                 choices: [Choice(text: "Right \(index)", correct: true), Choice(text: "Wrong \(index)", correct: false)], now: clock.now)
            app.context.insert(item)
            course.items.append(item)
        }
        let exam = Exam(course: course, title: "Bio 101 Midterm", date: cal.adding(days: 5, to: clock.now), now: clock.now)
        app.context.insert(exam)
        course.exams.append(exam)
        app.save()
        XCTAssertFalse(app.noticeDeck().contains { $0.kind == .mockOffer })
    }

    func testTakeItOpensTheMockAndTheCardStaysAway() throws {
        let exam = mockWorld(examIn: 5)
        let notice = try XCTUnwrap(app.noticeDeck().first { $0.kind == .mockOffer })
        let card = NoticeContent.card(notice, firstName: "", now: clock.now, calendar: cal)
        XCTAssertEqual(card.title, "A mock exam for your Bio 101 Midterm")
        XCTAssertEqual(card.detail, "10 questions like the real one · 10 min")
        XCTAssertNil(app.perform(try XCTUnwrap(card.action)), "the mock is its own screen, not a session")
        XCTAssertEqual(app.router.cover, .mockExam(examID: exam.id))
        XCTAssertFalse(app.noticeDeck().contains { $0.kind == .mockOffer })
    }

    func testNoMockCardWithTooFewQuestions() {
        _ = mockWorld(examIn: 5, questions: 5)
        XCTAssertFalse(app.noticeDeck().contains { $0.kind == .mockOffer })
    }

    func testNoMockCardAWeekAndADayOut() {
        _ = mockWorld(examIn: 8)
        XCTAssertFalse(app.noticeDeck().contains { $0.kind == .mockOffer })
    }

    func testQuietModeTakesTheStreakOutOfWelcomeBack() throws {
        let course = makeCourse()
        let item = StudyItem(course: course, kind: .flashcard, status: .active, origin: .person, prompt: "Mitosis", answer: "Cell division", now: clock.now)
        app.context.insert(item)
        course.items.append(item)
        for offset in 9..<20 {
            let date = cal.adding(days: -offset, to: clock.now)
            let record = app.dayRecord(key: cal.dayKey(for: date), date: date)
            record.sessions = 1
            record.studySeconds = 15 * 60
            record.itemsReviewed = 18
        }
        app.save()
        func welcome() throws -> CapNotice {
            let notice = try XCTUnwrap(app.noticeDeck().first { $0.kind == .welcomeBack })
            return NoticeContent.card(notice, firstName: "Maya", now: clock.now, calendar: cal)
        }
        XCTAssertTrue(try welcome().detail.contains("best streak"))

        app.settings.quietMode = true
        let quiet = try welcome()
        XCTAssertEqual(quiet.detail, "Your stars waited for you.")
        XCTAssertEqual(quiet.title, "Welcome back, Maya", "the card itself stays: it is about coming back to the plan")
    }

    func testShowMeAddsNothing() throws {
        let (course, draft, _, _, pair) = try lookAlikeWorld()
        let card = NoticeContent.card(try XCTUnwrap(app.noticeDeck().first), firstName: "", now: clock.now, calendar: cal)
        XCTAssertEqual(card.title, "Metaphase vs telophase")
        XCTAssertNil(app.perform(try XCTUnwrap(card.action)), "it opens the sheet, not a session")
        XCTAssertEqual(app.router.sheet, .lookAlike(a: pair.a, b: pair.b, examID: pair.examID))
        XCTAssertTrue(course.confusions.isEmpty, "nothing saved")
        XCTAssertEqual(course.items.count, 2)
        XCTAssertEqual(draft.rules.questions.count, 2)
        // Having seen to it, the card stays away.
        XCTAssertFalse(app.noticeDeck().contains { $0.id == pair.id })
    }

    func testTryingALookAlikeAdoptsItWithNoMisses() throws {
        let (course, draft, a, b, _) = try lookAlikeWorld()
        let request = try XCTUnwrap(app.tryLookAlike(draft, lesson: draft.rules, origin: .rules))
        XCTAssertEqual(request.kind, .fix)
        XCTAssertEqual(app.router.cover, .session(request))
        let confusion = try XCTUnwrap(course.confusions.first)
        XCTAssertEqual(confusion.status, .open)
        XCTAssertEqual(confusion.missCount, 0)
        XCTAssertEqual(Set(confusion.itemIDs), [a.id, b.id])
        XCTAssertEqual(confusion.name, "Metaphase vs telophase")
        XCTAssertEqual(confusion.fix?.itemIDs.count, 2, "its two questions are the fix")
        XCTAssertEqual(course.items.count, 4)
        // The Today card now reads as what it is.
        let note = try XCTUnwrap(app.todayConfusionNote())
        XCTAssertEqual(NoticeContent.card(for: note).title, "Metaphase vs telophase")
    }

    func testNotALookAlikeIsRememberedAndSkippedByBothFinders() throws {
        let (course, draft, a, b, pair) = try lookAlikeWorld()
        app.rejectLookAlike(draft)
        let confusion = try XCTUnwrap(course.confusions.first)
        XCTAssertEqual(confusion.status, .dismissed, "dismissed, and it syncs like any mix-up")
        XCTAssertNil(confusion.syncedAt)
        XCTAssertFalse(app.noticeDeck().contains { $0.id == pair.id })
        clock.advance(86_400)
        XCTAssertFalse(app.noticeDeck().contains { $0.kind == .lookAlike }, "tomorrow too")
        // Swapping them for real doesn't bring it back: the mix-up finder skips what was dismissed.
        let (session, _) = app.startSession(SessionRequest(kind: .daily))
        for _ in 0..<2 {
            app.recordReview(itemID: a.id, rating: .again, score: 0, answer: "Telophase", gradedBy: "rules", sessionID: session.id)
            app.recordReview(itemID: b.id, rating: .again, score: 0, answer: "Metaphase", gradedBy: "rules", sessionID: session.id)
        }
        XCTAssertTrue(app.confusionCandidates().isEmpty)
    }

    func testAFixedLookAlikeIsNoMixUpFixedForTheBadges() throws {
        let (course, draft, _, _, _) = try lookAlikeWorld()
        app.tryLookAlike(draft, lesson: draft.rules, origin: .rules)
        let confusion = try XCTUnwrap(course.confusions.first)
        confusion.status = .fixed
        app.save()
        XCTAssertEqual(app.achievementFacts().mixUpsFixed, 0)
        confusion.missCount = 2
        app.save()
        XCTAssertEqual(app.achievementFacts().mixUpsFixed, 1)
    }

    func testTheLookAlikeLessonAsksTheCloudOnlyIfAllowedAndFallsBackQuietly() async throws {
        let (_, draft, _, _, _) = try lookAlikeWorld()
        // No relay in tests' default mode, or no consent: the rules.
        let plain = await app.lookAlikeLesson(draft)
        XCTAssertEqual(plain.origin, .rules)
        XCTAssertEqual(plain.lesson, draft.rules)
    }
}
