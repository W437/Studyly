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
    /// An in-memory AppModel with its own defaults, a fixed calendar and a settable clock.
    static func make(clock: TestClock, calendar: Calendar) throws -> AppModel {
        let defaults = UserDefaults(suiteName: "capling.tests.\(UUID().uuidString)")!
        let app = AppModel(container: try Persistence.makeContainer(inMemory: true), defaults: defaults)
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

    func testInsightsOnAnEmptyStore() {
        XCTAssertEqual(app.todaySummary().sessionReady, false)
        XCTAssertEqual(app.streak(), StreakState())
        XCTAssertEqual(app.heatmap().count, 84)
        XCTAssertEqual(app.weeklyStats().days.count, 7)
        XCTAssertEqual(app.dueForecast().count, 7)
        XCTAssertNil(app.retentionRate())
        XCTAssertTrue(app.confusionCandidates().isEmpty)
    }
}
