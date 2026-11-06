import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// Undo after a self-given rating: held, written nowhere, then recorded through the idempotent path (`SessionRunner.PendingGrade`).
@MainActor
final class SessionUndoTests: XCTestCase {
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

    // MARK: Builders

    @discardableResult
    private func items(_ count: Int, kind: ItemKind = .flashcard, memory: MemoryState? = nil) -> [StudyItem] {
        let course = Course(name: "Bio 101", now: clock.now)
        app.context.insert(course)
        let made = (0..<count).map { n -> StudyItem in
            let item = StudyItem(course: course, kind: kind, status: .active, origin: .person, prompt: "Question \(n)?",
                                 answer: "Answer", now: clock.now)
            if let memory { item.memory = memory }
            app.context.insert(item)
            course.items.append(item)
            return item
        }
        app.save()
        return made
    }

    private func runner(_ made: [StudyItem], window: Duration? = .seconds(600), kind: SessionKind = .practice,
                        requeues: Bool = true) -> SessionRunner {
        let runner = SessionRunner(app: app, request: SessionRequest(kind: kind, itemIDs: made.map(\.id)),
                                   options: .init(liveActivity: false, requeues: requeues, undoWindow: window))
        runner.start()
        return runner
    }

    private var logs: [ReviewLog] { app.fetch(FetchDescriptor<ReviewLog>()) }

    /// A self-rating, as a flashcard gives it: held when the runner has a window.
    @discardableResult
    private func rate(_ runner: SessionRunner, _ rating: Rating, advancing: Bool = true) -> ReviewOutcome? {
        let review = runner.record(rating: rating, score: -1, answer: nil, gradedBy: "person", durationMs: 4000,
                                   outcome: .init(rating: rating), undo: .flashcard(flippedAtMs: 4000))
        if advancing { runner.advance() }
        return review
    }

    /// Studied a while ago and fading: a right answer now is a save.
    private func fading() -> MemoryState {
        let last = cal.adding(days: -30, to: clock.now)
        return MemoryState(state: .review, stability: 2, difficulty: 5, due: last.addingTimeInterval(2 * 86_400),
                           lastReview: last, reps: 3, lapses: 0, step: 0)
    }

    // MARK: Holding

    func testAHeldRatingWritesNothing() throws {
        let made = items(3)
        let runner = runner(made)
        let first = try XCTUnwrap(runner.current)
        let item = try XCTUnwrap(app.item(first.itemID))
        let memory = item.memory
        let updated = item.updatedAt
        let revision = app.revision
        let today = app.dayRecordSnapshot(for: clock.now)?.itemsReviewed

        let review = try XCTUnwrap(rate(runner, .good))

        XCTAssertTrue(logs.isEmpty, "no review log")
        XCTAssertEqual(item.memory, memory, "the memory is unchanged")
        XCTAssertEqual(item.updatedAt, updated, "not marked for sync")
        XCTAssertEqual(app.revision, revision, "nothing saved, so nothing downstream refreshes")
        XCTAssertEqual(app.dayRecordSnapshot(for: clock.now)?.itemsReviewed, today, "the day's record is unchanged")
        let session = try XCTUnwrap(app.studySession(try XCTUnwrap(runner.sessionID)))
        XCTAssertEqual(session.itemCount, 0)
        // The session itself has moved on, from the preview.
        XCTAssertEqual(runner.pending?.preview, review)
        XCTAssertEqual(runner.answers.map(\.isPending), [true])
        XCTAssertEqual(runner.segment(0), .done(.right))
        XCTAssertNotEqual(runner.current?.id, first.id)
    }

    func testWithoutAWindowARatingIsRecordedAtOnce() throws {
        let made = items(2)
        let runner = runner(made, window: nil)
        rate(runner, .good)
        XCTAssertNil(runner.pending)
        XCTAssertEqual(logs.count, 1, "tests, onboarding and the quick check see no difference")
    }

    func testAGradedAnswerIsRecordedAtOnceAndAnOlderHeldRatingGoesFirst() throws {
        let made = items(3)
        let runner = runner(made)
        rate(runner, .good)
        XCTAssertTrue(logs.isEmpty)
        // A grade as it stands has no restore: Continue was its moment.
        let graded = runner.record(rating: .good, score: 1, answer: "x", gradedBy: "rules", durationMs: 2000, outcome: .right)
        XCTAssertNotNil(graded)
        XCTAssertNil(runner.pending)
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs.sorted { $0.gradedBy < $1.gradedBy }.map(\.gradedBy), ["person", "rules"])
        XCTAssertEqual(runner.answers.map(\.isPending), [false, false])
    }

    func testRecordingTheHeldQuestionAgainChangesNothing() throws {
        let made = items(2)
        let runner = runner(made)
        let held = try XCTUnwrap(rate(runner, .easy, advancing: false))
        let again = try XCTUnwrap(rate(runner, .again, advancing: false))
        XCTAssertEqual(again, held)
        XCTAssertEqual(runner.answers.count, 1)
    }

    // MARK: Preview and commit

    func testThePreviewIsWhatRecordingDoes() throws {
        for fuzz in [false, true] {
            AppModel.schedulerFuzz = fuzz
            for rating in Rating.allCases {
                let made = items(2, memory: fading())
                let runner = runner(made)
                let entry = try XCTUnwrap(runner.current)
                let preview = try XCTUnwrap(rate(runner, rating))
                // The clock moves on; what the rating does stays what it was when it was given.
                clock.now = clock.now.addingTimeInterval(4)
                runner.commitPending()
                let answer = try XCTUnwrap(runner.answers.first { $0.entry.id == entry.id })
                XCTAssertEqual(answer.review, preview, "\(rating) with fuzz \(fuzz)")
                XCTAssertEqual(app.item(entry.itemID)?.memory, preview.after)
                XCTAssertEqual(answer.review.isSave, preview.isSave)
                let log = try XCTUnwrap(logs.first { $0.id == preview.logID })
                XCTAssertEqual(log.scheduledDays, preview.scheduledDays)
                XCTAssertEqual(log.wasCorrect, preview.wasCorrect)
                runner.finish()
            }
        }
        XCTAssertTrue(try XCTUnwrap(previewOfASave()).isSave, "the flare can play from a preview")
    }

    private func previewOfASave() -> ReviewOutcome? {
        let made = items(1, memory: fading())
        return app.previewReview(itemID: made[0].id, rating: .good, reviewID: UUID())
    }

    func testAScoreBelowTheLineIsNotCorrectInThePreviewEither() throws {
        let made = items(1)
        let preview = try XCTUnwrap(app.previewReview(itemID: made[0].id, rating: .hard, score: 0.2, reviewID: UUID()))
        XCTAssertFalse(preview.wasCorrect)
        let recorded = try XCTUnwrap(app.recordReview(itemID: made[0].id, rating: .hard, score: 0.2))
        XCTAssertEqual(recorded.wasCorrect, preview.wasCorrect)
    }

    func testARatingHeldOverMidnightCountsForTheDayItWasGiven() throws {
        clock.now = EngineTest.date(2026, 10, 22, 23, in: cal).addingTimeInterval(59 * 60 + 58)
        let made = items(2)
        let runner = runner(made)
        let ratedAt = clock.now
        let key = app.calendar.dayKey(for: ratedAt)
        rate(runner, .good)
        clock.now = ratedAt.addingTimeInterval(5)
        XCTAssertNotEqual(app.calendar.dayKey(for: clock.now), key)
        runner.commitPending()
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.reviewedAt, ratedAt)
        XCTAssertEqual(app.dayRecord(key: key)?.itemsReviewed, 1)
        XCTAssertNil(app.dayRecord(key: app.calendar.dayKey(for: clock.now)), "tomorrow has nothing from it")
    }

    // MARK: What commits

    func testTheNextRatingCommitsTheOneBefore() throws {
        let made = items(3)
        let runner = runner(made)
        rate(runner, .good)
        XCTAssertEqual(logs.count, 0)
        rate(runner, .hard)
        XCTAssertEqual(logs.count, 1, "the first is written; the second is held")
        XCTAssertEqual(runner.pending?.rating, .hard)
    }

    func testClosingCommits() throws {
        let made = items(3)
        let runner = runner(made)
        rate(runner, .good)
        runner.close()
        XCTAssertEqual(logs.count, 1)
        XCTAssertNil(runner.pending)
        XCTAssertEqual(runner.summary?.answers, 1, "the summary sees it")
    }

    func testFinishingCommits() throws {
        let made = items(3)
        let runner = runner(made)
        rate(runner, .good)
        runner.finish()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(runner.phase, .finished)
        XCTAssertEqual(runner.summary?.itemsReviewed, 1)
    }

    func testTheWindowEndsByItself() async throws {
        let made = items(2)
        let runner = runner(made, window: .milliseconds(40))
        rate(runner, .good)
        XCTAssertEqual(logs.count, 0)
        for _ in 0..<100 where runner.pending != nil { try await nap(20) }
        XCTAssertNil(runner.pending)
        XCTAssertEqual(logs.count, 1)
    }

    func testLeavingAQuestionWithoutAnAnswerCommitsTheHeldRating() throws {
        let made = items(3)
        let runner = runner(made)
        rate(runner, .good)
        runner.advance()
        XCTAssertNil(runner.pending, "an item deleted elsewhere moves past: the held one can't come back over it")
        XCTAssertEqual(logs.count, 1)
    }

    // MARK: Undo

    func testUndoBringsTheQuestionBackAndAnAgainsCopyGoesWithIt() throws {
        let made = items(5)
        let runner = runner(made)
        let first = try XCTUnwrap(runner.current)
        let count = runner.queue.count
        rate(runner, .again)
        XCTAssertEqual(runner.queue.count, count + 1, "the Again is back in the queue")

        runner.undoPending()

        XCTAssertEqual(runner.current?.id, first.id)
        XCTAssertEqual(runner.queue.count, count, "its copy has gone")
        XCTAssertFalse(runner.queue.entries.contains { $0.attempt > 0 })
        XCTAssertTrue(runner.answers.isEmpty)
        XCTAssertNil(runner.pending)
        XCTAssertEqual(runner.segment(0), .current)
        XCTAssertFalse(runner.hasRecorded(first.id))
        XCTAssertTrue(logs.isEmpty)
        guard case .flashcard(let ms)? = runner.takeRestore(for: first.id) else { return XCTFail("a flashcard comes back flipped") }
        XCTAssertEqual(ms, 4000)
        XCTAssertNil(runner.takeRestore(for: first.id), "once")

        // Rated again, it goes through as if nothing had happened.
        rate(runner, .good)
        runner.commitPending()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.ratingRaw, Rating.good.rawValue)
    }

    func testAnUndoneRatingLeavesTheStoreAsItWas() throws {
        let made = items(2)
        let runner = runner(made)
        let item = try XCTUnwrap(app.item(try XCTUnwrap(runner.current).itemID))
        let memory = item.memory
        rate(runner, .good)
        runner.undoPending()
        runner.finish()
        XCTAssertTrue(logs.isEmpty)
        XCTAssertEqual(item.memory, memory)
        XCTAssertEqual(app.dayRecordSnapshot(for: clock.now)?.itemsReviewed ?? 0, 0)
    }

    func testTheRestoreOfAnotherQuestionIsNotTaken() throws {
        let made = items(3)
        let runner = runner(made)
        let first = try XCTUnwrap(runner.current)
        rate(runner, .good)
        let second = try XCTUnwrap(runner.current)
        runner.undoPending()
        XCTAssertNil(runner.takeRestore(for: second.id))
        XCTAssertNotNil(runner.takeRestore(for: first.id))
    }

    // MARK: The last question

    func testTheLastQuestionWaitsAndTheSummaryStartsOnCommit() throws {
        let made = items(1)
        let runner = runner(made, requeues: false)
        rate(runner, .good)
        XCTAssertEqual(runner.phase, .wrapping)
        XCTAssertNil(runner.summary)
        XCTAssertTrue(logs.isEmpty)
        XCTAssertNil(runner.current)
        runner.commitPending()
        XCTAssertEqual(runner.phase, .finished)
        XCTAssertEqual(runner.summary?.answers, 1)
        XCTAssertEqual(logs.count, 1)
    }

    func testUndoFromTheLastQuestionGoesBackToIt() throws {
        let made = items(1)
        let runner = runner(made, requeues: false)
        let first = try XCTUnwrap(runner.current)
        rate(runner, .good)
        XCTAssertEqual(runner.phase, .wrapping)
        runner.undoPending()
        XCTAssertEqual(runner.phase, .question)
        XCTAssertEqual(runner.current?.id, first.id)
    }

    func testClosingOnTheLastOneCommits() throws {
        let made = items(1)
        let runner = runner(made, requeues: false)
        rate(runner, .good)
        runner.close()
        XCTAssertEqual(runner.phase, .finished)
        XCTAssertEqual(logs.count, 1)
    }

    // MARK: Drafts and picking up

    func testADraftStaysUntilTheRatingIsRecorded() throws {
        let made = items(2, kind: .recall)
        let runner = runner(made)
        let entry = try XCTUnwrap(runner.current)
        app.keepAnswerDraft("So the body can grow", for: entry.itemID)
        rate(runner, .good)
        XCTAssertEqual(app.answerDraft(for: entry.itemID), "So the body can grow", "Undo still has it")
        runner.undoPending()
        XCTAssertEqual(app.answerDraft(for: entry.itemID), "So the body can grow")
        rate(runner, .good)
        runner.commitPending()
        XCTAssertNil(app.answerDraft(for: entry.itemID), "recorded: it is no longer a draft")
    }

    func testAGradedAnswerStillClearsItsDraftWhenItIsRecorded() throws {
        let made = items(2, kind: .recall)
        let runner = runner(made)
        let entry = try XCTUnwrap(runner.current)
        app.keepAnswerDraft("Words", for: entry.itemID)
        runner.record(rating: .good, score: 1, answer: "Words", gradedBy: "rules", durationMs: 1000, outcome: .right)
        XCTAssertNil(app.answerDraft(for: entry.itemID))
    }

    func testTheCheckpointFollowsTheQuestionOnScreenThroughAnUndo() throws {
        let made = items(3)
        let runner = runner(made, kind: .daily)
        let first = try XCTUnwrap(runner.current)
        XCTAssertEqual(app.sessionCheckpoint()?.currentItemID, first.itemID)
        rate(runner, .good)
        let second = try XCTUnwrap(runner.current)
        XCTAssertEqual(app.sessionCheckpoint()?.currentItemID, second.itemID)
        runner.undoPending()
        XCTAssertEqual(app.sessionCheckpoint()?.currentItemID, first.itemID, "the question it picks up is the one on screen")
    }

    func testAHeldRatingLostToACrashComesBackInThePickedUpSession() throws {
        let made = items(4)
        let first = try XCTUnwrap(SessionRunner(app: app, request: SessionRequest(kind: .daily)).built.entries.first)
        let runner = runner(made, kind: .daily)
        XCTAssertEqual(runner.current?.itemID, first.itemID)
        app.keepAnswerDraft("Half an answer", for: first.itemID)
        rate(runner, .good)
        // iOS kills the app inside the window: nothing was written, the checkpoint and the draft are still there.
        XCTAssertTrue(logs.isEmpty)
        let checkpoint = try XCTUnwrap(app.resumableCheckpoint(for: SessionRequest(kind: .daily)))
        let picked = SessionRunner(app: app, request: SessionRequest(kind: .daily), resuming: checkpoint)
        XCTAssertTrue(picked.resumed)
        XCTAssertTrue(picked.queue.entries.contains { $0.itemID == first.itemID }, "the rating that was lost is asked again")
        XCTAssertEqual(app.answerDraft(for: first.itemID), "Half an answer")
    }

    func testAResumedSessionHoldsAndCommitsLikeAnyOther() throws {
        let made = items(4)
        let opening = runner(made, kind: .daily)
        opening.record(rating: .good, score: 1, answer: nil, gradedBy: "rules", durationMs: 1000, outcome: .right)
        opening.advance()
        let checkpoint = try XCTUnwrap(app.resumableCheckpoint(for: SessionRequest(kind: .daily)))
        let picked = SessionRunner(app: app, request: SessionRequest(kind: .daily),
                                   options: .init(liveActivity: false, undoWindow: .seconds(600)), resuming: checkpoint)
        picked.start()
        XCTAssertEqual(picked.sessionID, opening.sessionID)
        rate(picked, .good)
        XCTAssertEqual(logs.count, 1)
        picked.commitPending()
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs.compactMap(\.sessionID).filter { $0 == opening.sessionID }.count, 2)
    }

    // MARK: Words

    func testThePillSaysWhatWasMarkedAndWhenItComesBack() {
        XCTAssertEqual(String(localized: SessionCopy.undoLine(rating: .easy, days: 28)), "Easy · back in 4 weeks")
        XCTAssertEqual(String(localized: SessionCopy.undoLine(rating: .again, days: 10.0 / 1440)), "Again · back in 10 min")
        XCTAssertEqual(String(localized: SessionCopy.undoAnnouncement(rating: .easy)), "Marked Easy. Undo is at the bottom.")
    }
}
