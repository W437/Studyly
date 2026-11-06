import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// The Study lane's glue: the session runner over the engine (recording, re-queueing, finishing), rating previews,
/// the confusion workflow and onboarding's exam and quick check.
@MainActor
final class SessionTests: XCTestCase {
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
    private func makeCourse(_ name: String = "Bio 101") -> Course {
        let course = Course(name: name, now: clock.now)
        app.context.insert(course)
        return course
    }

    @discardableResult
    private func makeSource(in course: Course, title: String = "Scan", daysAgo: Int = 0) -> Source {
        let source = Source(course: course, kind: .scan, title: title, status: .ready,
                            now: cal.adding(days: -daysAgo, to: clock.now))
        app.context.insert(source)
        course.sources.append(source)
        return source
    }

    @discardableResult
    private func makeItem(in course: Course, kind: ItemKind = .flashcard, prompt: String = "Question?",
                          answer: String = "Answer", status: ItemStatus = .active, difficulty: Double = 0.5,
                          choices: [Choice] = [], keyIdeas: [KeyIdea] = [], source: Source? = nil) -> StudyItem {
        let ref = source.map { SourceRef(sourceID: $0.id, pageIndex: 0, anchorIDs: [], label: "p. 1") }
        let item = StudyItem(course: course, kind: kind, status: status, origin: .person, prompt: prompt, answer: answer,
                             keyIdeas: keyIdeas, choices: choices, sourceRef: ref, difficultyHint: difficulty, now: clock.now)
        app.context.insert(item)
        course.items.append(item)
        return item
    }

    private func answerAll(_ runner: SessionRunner, rating: Rating = .good) {
        var guardCount = 0
        while runner.phase == .question, guardCount < 100 {
            runner.record(rating: rating, score: -1, answer: nil, gradedBy: "person", durationMs: 5000,
                          outcome: SessionRunner.Outcome(rating: rating))
            runner.advance()
            guardCount += 1
        }
    }

    // MARK: The runner

    func testAnAgainComesBackLaterInTheSessionAndTheSegmentsFollow() throws {
        let course = makeCourse()
        for i in 0..<3 { makeItem(in: course, prompt: "Card \(i)") }
        app.save()

        let runner = SessionRunner(app: app, request: SessionRequest(kind: .daily))
        XCTAssertEqual(runner.phase, .ready)
        runner.start()
        XCTAssertEqual(runner.phase, .question)
        XCTAssertNotNil(runner.sessionID)
        let first = try XCTUnwrap(runner.current)
        XCTAssertEqual(runner.segment(0), .current)

        runner.setProvisional(.wrong)
        XCTAssertTrue(runner.hasUnsavedAnswer)
        XCTAssertEqual(runner.segment(0), .done(.wrong), "a graded answer colours its segment before it's committed")

        runner.record(rating: .again, score: -1, answer: nil, gradedBy: "person", durationMs: 4000, outcome: .wrong)
        XCTAssertFalse(runner.hasUnsavedAnswer)
        runner.advance()
        XCTAssertEqual(runner.queue.count, 4, "the Again is back in the queue")
        XCTAssertTrue(runner.queue.entries.dropFirst().contains { $0.itemID == first.itemID && $0.attempt == 1 })
        XCTAssertEqual(runner.segment(0), .done(.wrong))
        XCTAssertEqual(runner.segment(1), .current)

        answerAll(runner)
        XCTAssertEqual(runner.phase, .finished)
        let summary = try XCTUnwrap(runner.summary)
        XCTAssertEqual(summary.itemsReviewed, 3)
        XCTAssertEqual(summary.correctFirstTry, 2)
        XCTAssertEqual(runner.rightFirstTime, 2)
        XCTAssertEqual(runner.distinctAnswered, 3)
        XCTAssertNotNil(app.studySession(try XCTUnwrap(runner.sessionID))?.endedAt)
    }

    func testRecordingTheSameQuestionTwiceKeepsOneReview() throws {
        let course = makeCourse()
        makeItem(in: course)
        makeItem(in: course)
        app.save()
        let runner = SessionRunner(app: app, request: SessionRequest(kind: .daily))
        runner.start()
        runner.record(rating: .good, score: -1, answer: nil, gradedBy: "person", durationMs: 3000, outcome: .right)
        runner.record(rating: .again, score: -1, answer: nil, gradedBy: "person", durationMs: 3000, outcome: .wrong)
        XCTAssertEqual(app.fetch(FetchDescriptor<ReviewLog>()).count, 1)
        XCTAssertEqual(runner.answers.count, 1)
        XCTAssertEqual(runner.answers.first?.review.rating, .good)
    }

    func testTheQuickCheckIsExactlyTheQuestionsItWasGiven() throws {
        let course = makeCourse()
        let a = makeItem(in: course, prompt: "A")
        let b = makeItem(in: course, prompt: "B")
        makeItem(in: course, prompt: "Not in the check")
        app.save()
        let runner = SessionRunner(app: app, request: SessionRequest(kind: .quickCheck, itemIDs: [a.id, b.id]),
                                   options: .init(liveActivity: false, requeues: false))
        runner.start()
        XCTAssertEqual(runner.queue.entries.map(\.itemID), [a.id, b.id])
        answerAll(runner)
        XCTAssertEqual(runner.phase, .finished)
        XCTAssertEqual(runner.answers.count, 2, "new items in a learning step don't come back in the two-question check")
    }

    func testClosingEarlyKeepsTheAnswersAndFinishesOnce() throws {
        let course = makeCourse()
        for i in 0..<4 { makeItem(in: course, prompt: "Card \(i)") }
        app.save()
        let runner = SessionRunner(app: app, request: SessionRequest(kind: .daily))
        runner.start()
        runner.record(rating: .good, score: -1, answer: nil, gradedBy: "person", durationMs: 3000, outcome: .right)
        runner.advance()
        runner.close()
        runner.close()
        XCTAssertEqual(runner.phase, .finished)
        XCTAssertEqual(runner.summary?.itemsReviewed, 1)
        XCTAssertEqual(app.fetch(FetchDescriptor<ReviewLog>()).count, 1)
        XCTAssertEqual(app.answersToday(), 1)
    }

    func testAnEmptySessionSaysSo() {
        makeCourse()
        app.save()
        let runner = SessionRunner(app: app, request: SessionRequest(kind: .daily))
        XCTAssertEqual(runner.phase, .empty)
        runner.start()
        XCTAssertEqual(runner.phase, .empty, "nothing to start")
        runner.close()
        XCTAssertNil(runner.summary)
    }

    func testOutcomesFromVerdictsAndRatings() {
        XCTAssertEqual(SessionRunner.Outcome(.correct), .right)
        XCTAssertEqual(SessionRunner.Outcome(.partial), .partial)
        XCTAssertEqual(SessionRunner.Outcome(.incorrect), .wrong)
        XCTAssertEqual(SessionRunner.Outcome(rating: .again), .wrong)
        XCTAssertEqual(SessionRunner.Outcome(rating: .hard), .partial)
        XCTAssertEqual(SessionRunner.Outcome(rating: .easy), .right)
    }

    /// The views take the rating from the grade: a partial own-words answer is Hard, a full one quickly given is
    /// Easy, a right multiple choice in normal time is Good.
    func testRatingsTheViewsUseForGrades() {
        XCTAssertEqual(AppModel.rating(forScore: 0.67, kind: .recall, durationMs: 40_000), .hard)
        XCTAssertEqual(AppModel.rating(forScore: 1, kind: .recall, durationMs: 20_000), .easy)
        XCTAssertEqual(AppModel.rating(forScore: 1, kind: .mcq, durationMs: 14_000), .good)
        XCTAssertEqual(AppModel.rating(forScore: 0, kind: .mcq, durationMs: 3000), .again)
        XCTAssertEqual(AppModel.rating(forScore: 0.75, kind: .diagram, durationMs: 20_000), .hard)
    }

    /// An own-words answer the person marked themselves (no model graded it) is logged as "self" and counts in a run like any other
    /// answer, by the rating it ended with: the run on the screen and the one the quests read from the log are the same.
    func testASelfMarkedAnswerCountsInTheRunLikeAnyOtherAndTheQuestsSeeTheSameRun() throws {
        let course = makeCourse()
        let ideas = [KeyIdea(id: "k1", label: "One", terms: ["one"]), KeyIdea(id: "k2", label: "Two", terms: ["two"])]
        for i in 0..<5 { makeItem(in: course, kind: .recall, prompt: "Question \(i)?", answer: "One and two.", keyIdeas: ideas) }
        app.save()
        let runner = SessionRunner(app: app, request: SessionRequest(kind: .daily), options: .init(liveActivity: false, requeues: false))
        runner.start()
        func record(_ rating: Rating, score: Double, by who: String) {
            runner.record(rating: rating, score: score, answer: "an answer", gradedBy: who, durationMs: 9000,
                          outcome: SessionRunner.Outcome(rating: rating))
            runner.advance()
        }
        // Right, right, a self-marked wrong answer, a self-marked right one, right: the run is broken in the middle (the screen used to
        // go on counting through it, four against the quests' two).
        record(.good, score: 1, by: "rules")
        record(.good, score: 1, by: "cloud")
        XCTAssertEqual(runner.combo(), 2)
        record(.again, score: 0, by: "self")
        XCTAssertEqual(runner.combo(), 0, "marking it wrong yourself breaks the run, as a wrong answer does")
        record(.good, score: 0.9, by: "self")
        XCTAssertEqual(runner.combo(), 1, "and marking one right builds it, by its rating")
        record(.good, score: 1, by: "rules")
        XCTAssertEqual(runner.combo(), 2)
        XCTAssertEqual(runner.answers.map(\.outcome), [.right, .right, .wrong, .right, .right])
        runner.finish()
        // The quests read the same run from the log.
        XCTAssertEqual(app.questFacts(forDay: cal.dayKey(for: clock.now)).bestRun, 2, "the screen and the quests agree")

        let logs = app.fetch(FetchDescriptor<ReviewLog>(sortBy: [SortDescriptor(\.reviewedAt)]))
        XCTAssertEqual(logs.count, 5)
        XCTAssertEqual(Set(logs.map(\.gradedBy)), ["rules", "cloud", "self"])
        XCTAssertEqual(logs.filter { $0.gradedBy == "self" }.map(\.score).sorted(), [0, 0.9])
    }

    /// 0 or 1 of 3 ticked, then "Counts as Good": the log used to say Good over the ticks' score, and `wasCorrect` (which needs 0.6)
    /// then called it a miss: the session's correct count, a mix-up's miss count and the "right first time" tally all disagreed with
    /// the rating FSRS was given. The view logs `Grading.score(standingFor:near:)` of the rating the person ended with.
    func testAMarkTheyOverrodeIsLoggedWithAScoreThatAgreesWithItsRating() throws {
        let course = makeCourse()
        let ideas = (1...3).map { KeyIdea(id: "k\($0)", label: "Idea \($0)", terms: ["idea\($0)"]) }
        let first = makeItem(in: course, kind: .recall, prompt: "First?", answer: "All three.", keyIdeas: ideas)
        let second = makeItem(in: course, kind: .recall, prompt: "Second?", answer: "All three.", keyIdeas: ideas)
        let confusion = Confusion(course: course, name: "Idea 1 vs Idea 2", explanation: "", itemIDs: [first.id, second.id], missCount: 0,
                                  now: clock.now)
        app.context.insert(confusion)
        app.save()
        let runner = SessionRunner(app: app, request: SessionRequest(kind: .daily), options: .init(liveActivity: false, requeues: false))
        runner.start()
        // One of three ticked (a score of 0.33), and the person says it counts as Good.
        let ticks = SelfCheck.score(ticked: ["k1"], of: ideas)
        XCTAssertEqual(AppModel.rating(forScore: ticks, kind: .recall, durationMs: 40_000), .again, "what the ticks alone would say")
        let rating = Rating.good
        let score = Grading.score(standingFor: rating, near: ticks)
        let review = try XCTUnwrap(runner.record(rating: rating, score: score, answer: "an answer", gradedBy: "self", durationMs: 40_000,
                                                 outcome: SessionRunner.Outcome(rating: rating)))
        runner.advance()
        XCTAssertTrue(review.wasCorrect, "Good by the rating and right by the score")
        XCTAssertEqual(runner.rightFirstTime, 1)
        XCTAssertEqual(app.studySession(try XCTUnwrap(runner.sessionID))?.correctCount, 1)
        XCTAssertEqual(confusion.missCount, 0, "not a miss")
        let log = try XCTUnwrap(app.fetch(FetchDescriptor<ReviewLog>()).first)
        XCTAssertEqual(log.rating, .good)
        XCTAssertTrue(log.wasCorrect)
        XCTAssertEqual(log.gradedBy, "self")

        // The contradiction this replaces: the same mark with the ticks' own score logged over it.
        let stale = try XCTUnwrap(runner.record(rating: .good, score: ticks, answer: "an answer", gradedBy: "person", durationMs: 40_000,
                                                outcome: SessionRunner.Outcome(rating: .good)))
        XCTAssertFalse(stale.wasCorrect, "the old log said Good and counted a miss (it is here, a second entry for the next question)")
    }

    // MARK: Rating previews

    func testIntervalPreviewOrdersTheRatingsAndWritesNothing() throws {
        let course = makeCourse()
        let item = makeItem(in: course)
        app.save()
        let before = item.memory
        let preview = app.intervalPreview(itemID: item.id)
        let again = try XCTUnwrap(preview[.again]), hard = try XCTUnwrap(preview[.hard])
        let good = try XCTUnwrap(preview[.good]), easy = try XCTUnwrap(preview[.easy])
        XCTAssertLessThanOrEqual(again, hard)
        XCTAssertLessThanOrEqual(hard, good)
        XCTAssertLessThan(good, easy)
        XCTAssertLessThan(again, 1.0 / 24, "a new card's Again is minutes away")
        XCTAssertEqual(item.memory, before)
        XCTAssertTrue(app.fetch(FetchDescriptor<ReviewLog>()).isEmpty)
        XCTAssertTrue(app.intervalPreview(itemID: UUID()).isEmpty)
    }

    // MARK: Onboarding

    func testOnboardingMakesTheExamFromTheQuizDateOnce() throws {
        let course = makeCourse()
        app.save()
        XCTAssertNil(app.ensureOnboardingExam(courseID: course.id), "no date, no exam")

        var s = app.settings
        s.nextExamDate = cal.adding(days: 23, to: clock.now)
        app.settings = s
        let exam = try XCTUnwrap(app.ensureOnboardingExam(courseID: course.id))
        XCTAssertEqual(exam.title, "Bio 101 exam")
        XCTAssertEqual(exam.course?.id, course.id)
        XCTAssertEqual(app.ensureOnboardingExam(courseID: course.id)?.id, exam.id)
        XCTAssertEqual(app.upcomingExams().count, 1)
    }

    func testOnboardingUsesAnExamThatAlreadyExists() throws {
        let course = makeCourse()
        let other = makeCourse("Chem 110")
        let date = cal.adding(days: 10, to: clock.now)
        let existing = Exam(course: other, title: "Chem final", date: date, now: clock.now)
        app.context.insert(existing)
        other.exams.append(existing)
        app.save()
        var s = app.settings
        s.nextExamDate = date
        app.settings = s
        XCTAssertEqual(app.ensureOnboardingExam(courseID: course.id)?.id, existing.id,
                       "the person's exam on that day is never doubled")

        let own = Exam(course: course, title: "Bio midterm", date: cal.adding(days: 5, to: clock.now), now: clock.now)
        app.context.insert(own)
        course.exams.append(own)
        app.save()
        XCTAssertEqual(app.ensureOnboardingExam(courseID: course.id)?.id, own.id)
    }

    func testAPastExamDateMakesNoExam() {
        let course = makeCourse()
        app.save()
        var s = app.settings
        s.nextExamDate = cal.adding(days: -2, to: clock.now)
        app.settings = s
        XCTAssertNil(app.ensureOnboardingExam(courseID: course.id))
    }

    func testTheQuickCheckPicksTheEasiestChoiceAndOwnWordsFromTheNewestSet() {
        let course = makeCourse()
        let old = makeSource(in: course, title: "Old", daysAgo: 5)
        let new = makeSource(in: course, title: "New", daysAgo: 0)
        makeItem(in: course, kind: .mcq, difficulty: 0.1, source: old)
        makeItem(in: course, kind: .mcq, difficulty: 0.5, source: new)
        let easyChoice = makeItem(in: course, kind: .mcq, difficulty: 0.3, source: new)
        makeItem(in: course, kind: .recall, difficulty: 0.1, source: new)
        let words = makeItem(in: course, kind: .recall, difficulty: 0.6,
                             keyIdeas: [KeyIdea(id: "k1", label: "Idea", terms: ["idea"])], source: new)
        makeItem(in: course, kind: .mcq, status: .rejected, difficulty: 0, source: new)
        app.save()
        XCTAssertEqual(app.quickCheckItemIDs(courseID: course.id), [easyChoice.id, words.id])
    }

    func testTheQuickCheckFallsBackToOtherFormats() {
        let course = makeCourse()
        let card = makeItem(in: course, kind: .flashcard, difficulty: 0.2)
        let cloze = makeItem(in: course, kind: .cloze, difficulty: 0.4)
        app.save()
        XCTAssertEqual(app.quickCheckItemIDs(courseID: course.id), [cloze.id, card.id])
        XCTAssertEqual(app.quickCheckItemIDs(courseID: UUID()), [cloze.id, card.id], "an unknown course means the first")
    }

    // MARK: Confusions

    private func swappedPair() -> (StudyItem, StudyItem, UUID) {
        let course = makeCourse()
        let a = makeItem(in: course, kind: .mcq, prompt: "What does anaphase I separate?", answer: "Homologous pairs",
                         choices: [Choice(text: "Homologous pairs", correct: true), Choice(text: "Sister chromatids", correct: false)])
        let b = makeItem(in: course, kind: .mcq, prompt: "What does anaphase II separate?", answer: "Sister chromatids",
                         choices: [Choice(text: "Homologous pairs", correct: false), Choice(text: "Sister chromatids", correct: true)])
        app.save()
        let (session, _) = app.startSession(SessionRequest(kind: .daily))
        app.recordReview(itemID: a.id, rating: .again, score: 0, answer: "Sister chromatids", gradedBy: "rules",
                         sessionID: session.id)
        app.recordReview(itemID: b.id, rating: .again, score: 0, answer: "Homologous pairs", gradedBy: "rules",
                         sessionID: session.id)
        return (a, b, session.id)
    }

    func testASwapInASessionBecomesAnOpenConfusionOnce() throws {
        let (a, b, sessionID) = swappedPair()
        let candidate = try XCTUnwrap(app.confusionCandidate(forSession: sessionID))
        XCTAssertEqual(Set(candidate.itemIDs), [a.id, b.id])
        XCTAssertEqual(app.mistakeInputs(for: candidate).count, 2)

        let confusion = app.adoptConfusion(candidate, explained: nil, withFixQuestions: false)
        XCTAssertEqual(confusion.status, .open)
        XCTAssertEqual(Set(confusion.itemIDs), [a.id, b.id])
        XCTAssertEqual(confusion.fix?.itemIDs, [])
        XCTAssertEqual(app.adoptConfusion(candidate, explained: nil, withFixQuestions: false).id, confusion.id)
        XCTAssertNil(app.confusionCandidate(forSession: sessionID), "its items are in an open confusion now")
        XCTAssertEqual(app.todayConfusionNote()?.id, confusion.id)
    }

    /// Two swapped answers that are sentences give no name to make of them: the mix-up is stored as what it is, with how many misses on
    /// how many questions, and Cap's line doesn't pretend it has a name.
    func testASwapOfSentencesIsStoredWithoutAMadeUpName() throws {
        let course = makeCourse()
        let first = "The sister chromatids are pulled to opposite poles of the cell"
        let second = "The nuclear envelope re-forms around each new set of chromosomes"
        let a = makeItem(in: course, kind: .recall, prompt: "What happens in anaphase?", answer: first)
        let b = makeItem(in: course, kind: .recall, prompt: "What happens in telophase?", answer: second)
        app.save()
        let (session, _) = app.startSession(SessionRequest(kind: .daily))
        app.recordReview(itemID: a.id, rating: .again, score: 0, answer: second, gradedBy: "rules", sessionID: session.id)
        app.recordReview(itemID: b.id, rating: .again, score: 0, answer: first, gradedBy: "rules", sessionID: session.id)

        let candidate = try XCTUnwrap(app.confusionCandidate(forSession: session.id))
        XCTAssertEqual(candidate.name, ConfusionCandidate.unnamed)
        XCTAssertEqual(candidate.defaultExplanation, "2 misses on these 2 questions")
        let confusion = app.adoptConfusion(candidate, explained: nil, withFixQuestions: false)
        XCTAssertEqual(confusion.name, "Questions you keep missing")
        XCTAssertEqual(confusion.explanation, "2 misses on these 2 questions")
        let note = try XCTUnwrap(app.todayConfusionNote())
        XCTAssertEqual(SessionCopy.mixUpLine(note.name), "These questions keep tripping you up.")
    }

    func testFixItNowTurnsTheExplanationsQuestionsIntoTheFix() throws {
        let (a, b, sessionID) = swappedPair()
        let candidate = try XCTUnwrap(app.confusionCandidate(forSession: sessionID))
        let explained = ConfusionOut(
            name: "Homologous pairs vs sister chromatids", explanation: "Anaphase I splits pairs; II splits chromatids.",
            itemIds: [a.id.uuidString, b.id.uuidString], lesson: "I: pairs. II: chromatids.",
            questions: [GeneratedItem(id: "q1", kind: .mcq, topic: "Meiosis", prompt: "Which division splits pairs?",
                                      answer: "Meiosis I",
                                      choices: [Choice(text: "Meiosis I", correct: true), Choice(text: "Meiosis II", correct: false)])])
        let confusion = app.adoptConfusion(candidate, explained: explained, origin: .rules, withFixQuestions: true)
        XCTAssertEqual(confusion.name, "Homologous pairs vs sister chromatids")
        XCTAssertEqual(confusion.fix?.lesson, "I: pairs. II: chromatids.")
        let fixID = try XCTUnwrap(confusion.fix?.itemIDs.first)
        XCTAssertEqual(app.item(fixID)?.status, .active)

        let request = try XCTUnwrap(app.prepareFix(confusion.id))
        XCTAssertEqual(request.kind, .fix)
        let built = app.buildSession(request)
        XCTAssertEqual(built.entries.first?.itemID, fixID, "the fix's own questions come first")
        XCTAssertEqual(Set(built.entries.map(\.itemID)), [fixID, a.id, b.id])
    }

    func testPrepareFixActivatesDraftQuestionsAndResolveFixNeedsMostRight() throws {
        let course = makeCourse()
        let item = makeItem(in: course)
        let draft = makeItem(in: course, status: .draft)
        let confusion = Confusion(course: course, name: "A vs b", explanation: "", itemIDs: [item.id],
                                  fix: ConfusionFix(lesson: "", itemIDs: [draft.id]), missCount: 3, now: clock.now)
        app.context.insert(confusion)
        course.confusions.append(confusion)
        app.save()
        _ = app.prepareFix(confusion.id)
        XCTAssertEqual(draft.status, .active)

        func summary(_ right: Int, of n: Int) -> SessionSummary {
            SessionSummary(sessionID: UUID(), kind: .fix, answers: n, itemsReviewed: n, correctFirstTry: right,
                           accuracy: Double(right) / Double(n), newLearned: 0, minutes: 2, examID: nil, examTitle: nil,
                           readinessBefore: nil, readinessAfter: nil, streak: StreakState(), streakExtended: false,
                           repairedDay: nil, stopNow: false)
        }
        XCTAssertFalse(app.resolveFix(confusionID: confusion.id, summary: summary(2, of: 4)))
        XCTAssertEqual(confusion.status, .open)
        XCTAssertTrue(app.resolveFix(confusionID: confusion.id, summary: summary(3, of: 4)))
        XCTAssertEqual(confusion.status, .fixed)
    }

    func testLaterHidesTheNoteUntilTomorrowAndDismissEndsIt() throws {
        let (_, _, sessionID) = swappedPair()
        let candidate = try XCTUnwrap(app.confusionCandidate(forSession: sessionID))
        let confusion = app.adoptConfusion(candidate, explained: nil, withFixQuestions: false)
        let note = try XCTUnwrap(app.todayConfusionNote())
        XCTAssertEqual(note.recentAnswers, 2)
        XCTAssertEqual(note.recentMisses, 2)

        app.snoozeConfusion(confusion.id)
        XCTAssertTrue(app.isConfusionSnoozed(confusion.id))
        XCTAssertNil(app.todayConfusionNote())
        clock.advance(24 * 3600)
        XCTAssertFalse(app.isConfusionSnoozed(confusion.id))
        XCTAssertEqual(app.todayConfusionNote()?.id, confusion.id)

        app.dismissConfusion(confusion.id)
        XCTAssertEqual(confusion.status, .dismissed)
        XCTAssertNil(app.todayConfusionNote())
    }

    func testTheLastWrongAnswerIsWhatThePersonGave() {
        let (a, _, _) = swappedPair()
        XCTAssertEqual(app.lastWrongAnswer(itemID: a.id), "Sister chromatids")
    }

    // MARK: Pure pieces

    func testClozeTokensKeepPunctuationWithTheBlank() {
        let tokens = ClozeToken.parse("During {{telophase}}, new envelopes form {{again}}.")
        XCTAssertEqual(tokens.map(\.kind), [.word("During"), .blank(0, trailing: ","), .word("new"), .word("envelopes"),
                                            .word("form"), .blank(1, trailing: ".")])
        XCTAssertEqual(ClozeToken.parse("{{Cytokinesis}} is the division.").first?.kind, .blank(0, trailing: ""))
    }

    func testTheDiagramCropStopsBetweenLinesAndLeavesRoomForTheSlots() {
        let targets = [
            DiagramTarget(anchorID: "l8", label: "Prophase", box: NormRect(x: 0.13, y: 0.267, w: 0.09, h: 0.017)),
            DiagramTarget(anchorID: "l9", label: "Metaphase", box: NormRect(x: 0.34, y: 0.269, w: 0.1, h: 0.017)),
        ]
        let lines = [
            TextLine(id: "above", text: "Mitosis occurs in four main phases:", box: NormRect(x: 0.08, y: 0.229, w: 0.3, h: 0.021)),
            TextLine(id: "below", text: "• Chromosomes condense", box: NormRect(x: 0.08, y: 0.43, w: 0.2, h: 0.03)),
        ] + targets.map { TextLine(id: $0.anchorID, text: $0.label, box: $0.box) }
        let region = DiagramQuestionView.region(for: targets, pageAspect: 2.0 / 3.0, lines: lines)
        for line in lines where !targets.contains(where: { $0.anchorID == line.id }) {
            let box = line.box!
            XCTAssertFalse(box.y < region.minY && box.y + box.h > region.minY, "the top edge cuts \(line.id)")
            XCTAssertFalse(box.y < region.maxY && box.y + box.h > region.maxY, "the bottom edge cuts \(line.id)")
        }
        XCTAssertLessThanOrEqual(region.minY, 0.267 - 0.035, "room above the labels for their slots")
        XCTAssertGreaterThanOrEqual(region.width, 0.5)
        let room = DiagramQuestionView.slotRoom(for: targets)
        XCTAssertEqual(room["l8"] ?? 0, 0.215, accuracy: 0.001)
    }

    func testTheSweepsTicksLandInOrderWithinTheSweep() {
        let n = 3
        let times = (0..<n).map { SweepTiming.landing(of: $0, count: n) }
        XCTAssertEqual(times, times.sorted())
        XCTAssertLessThanOrEqual(times.last ?? 0, SweepTiming.duration(marks: n))
        XCTAssertGreaterThan(times.first ?? 0, 0)
        XCTAssertEqual(SweepTiming.time(toReach: 1), 1, accuracy: 0.001)
        XCTAssertEqual(SweepTiming.time(toReach: 0), 0, accuracy: 0.001)
    }

    func testChoiceOrderIsStableForADayAndKeepsNoneOfTheAboveLast() {
        let texts = ["Growth", "Repair", "None of the above", "Making sex cells"]
        let id = UUID()
        let today = ChoiceOrder.order(texts: texts, itemID: id, day: 100)
        XCTAssertEqual(today, ChoiceOrder.order(texts: texts, itemID: id, day: 100))
        XCTAssertEqual(Set(today), Set(texts.indices))
        XCTAssertEqual(today.last, 2)
    }

    // MARK: Nothing lost mid-answer

    func testDraftsAreKeptAWeekAtMostThirtyAndBlankRemovesOne() {
        let t0 = clock.now
        var drafts = AnswerDrafts()
        let a = UUID()
        drafts.keep("Mitosis makes two", for: a, now: t0)
        XCTAssertEqual(drafts.draft(for: a, now: t0.addingTimeInterval(6 * 86_400))?.text, "Mitosis makes two")
        XCTAssertNil(drafts.draft(for: a, now: t0.addingTimeInterval(7 * 86_400 + 1)), "a week old: gone")
        drafts.keep("  ", for: a, now: t0)
        XCTAssertNil(drafts.draft(for: a, now: t0), "blank text removes the draft")
        let ids = (0..<35).map { _ in UUID() }
        for (i, id) in ids.enumerated() { drafts.keep("answer \(i)", for: id, now: t0.addingTimeInterval(Double(i))) }
        XCTAssertEqual(drafts.drafts.count, AnswerDrafts.limit)
        XCTAssertNil(drafts.draft(for: ids[0], now: t0.addingTimeInterval(40)), "the oldest go first")
        XCTAssertNotNil(drafts.draft(for: ids[34], now: t0.addingTimeInterval(40)))
        drafts.keep("late", for: UUID(), now: t0.addingTimeInterval(8 * 86_400))
        XCTAssertEqual(drafts.drafts.count, 1, "expired drafts go when another is kept")
    }

    func testADraftComesBackUntilTheAnswerIsRecorded() throws {
        let course = makeCourse()
        for i in 0..<3 { makeItem(in: course, kind: .recall, prompt: "Why \(i)?") }
        app.save()
        let runner = SessionRunner(app: app, request: SessionRequest(kind: .daily))
        runner.start()
        let entry = try XCTUnwrap(runner.current)
        app.keepAnswerDraft("Because the cell", for: entry.itemID)
        XCTAssertEqual(app.answerDraft(for: entry.itemID), "Because the cell")
        XCTAssertEqual(app.defaults.data(forKey: AnswerDrafts.defaultsKey).map { _ in true }, true, "kept in \(AnswerDrafts.defaultsKey)")
        clock.advance(3 * 86_400)
        XCTAssertEqual(app.answerDraft(for: entry.itemID), "Because the cell", "still there three days on")
        runner.record(rating: .good, score: 1, answer: "Because the cell grows", gradedBy: "rules", durationMs: 9000, outcome: .right)
        XCTAssertNil(app.answerDraft(for: entry.itemID), "recorded: the draft is gone")
        app.keepAnswerDraft("Another", for: entry.itemID)
        clock.advance(7 * 86_400 + 60)
        XCTAssertNil(app.answerDraft(for: entry.itemID), "a week later it has expired")
    }

    func testASessionIOSClosedPicksUpTheSameDayWithoutCountingTheGap() throws {
        let course = makeCourse()
        for i in 0..<12 { makeItem(in: course, prompt: "Card \(i)") }
        app.save()
        let first = SessionRunner(app: app, request: SessionRequest(kind: .daily), options: .init(liveActivity: false))
        first.start()
        for _ in 0..<2 {
            first.record(rating: .good, score: -1, answer: nil, gradedBy: "person", durationMs: 5000, outcome: .right)
            clock.advance(30)
            first.advance()
        }
        let sessionID = try XCTUnwrap(first.sessionID)
        let onScreen = try XCTUnwrap(first.current?.itemID)
        app.keepAnswerDraft("half typed", for: onScreen)
        let saved = try XCTUnwrap(app.sessionCheckpoint())
        XCTAssertEqual(saved.sessionID, sessionID)
        XCTAssertEqual(saved.currentItemID, onScreen)
        XCTAssertEqual(saved.wallSeconds, 60, accuracy: 0.001)
        // iOS closes the app here: nothing finishes. Three hours later, the same evening, Study again.
        clock.advance(3 * 3600)

        XCTAssertNil(app.resumableCheckpoint(for: SessionRequest(kind: .practice)), "a practice round starts again")
        let checkpoint = try XCTUnwrap(app.resumableCheckpoint(for: SessionRequest(kind: .daily)))
        let second = SessionRunner(app: app, request: SessionRequest(kind: .daily), options: .init(liveActivity: false),
                                   resuming: checkpoint)
        XCTAssertTrue(second.resumed)
        XCTAssertEqual(second.current?.itemID, onScreen, "the question that was on screen comes first")
        second.start()
        XCTAssertEqual(second.sessionID, sessionID, "the same StudySession goes on")
        // The clock goes on from the 60 s already spent (the 3 hours between aren't in it), and the bar counts the two earlier answers.
        XCTAssertEqual(Date().timeIntervalSince(second.startedAt), 60, accuracy: 10)
        XCTAssertEqual(second.earlier, [.right, .right])
        XCTAssertEqual(second.segmentCount, second.queue.count + 2)
        XCTAssertEqual(second.segmentPosition, 2)
        XCTAssertEqual(second.segment(0), .done(.right))
        XCTAssertEqual(second.segment(1), .done(.right))
        XCTAssertEqual(second.segment(2), .current, "the question on screen")
        XCTAssertEqual(second.segment(3), .pending)
        XCTAssertEqual(second.rightSoFar, 2)
        second.record(rating: .good, score: -1, answer: nil, gradedBy: "person", durationMs: 5000, outcome: .right)
        clock.advance(30)
        second.close()

        let summary = try XCTUnwrap(second.summary)
        XCTAssertEqual(summary.sessionID, sessionID)
        XCTAssertEqual(summary.answers, 3, "the answers from before the close count in the same session")
        XCTAssertEqual(app.fetch(FetchDescriptor<StudySession>()).count, 1)
        let session = try XCTUnwrap(app.studySession(sessionID))
        XCTAssertEqual(session.activeSeconds, 90, accuracy: 0.5, "60 s before the close and 30 s after; the 3 hours between don't count")
        XCTAssertEqual(app.dayRecordSnapshot(for: clock.now)?.studySeconds ?? 0, 90, accuracy: 0.5)
        XCTAssertNil(app.sessionCheckpoint(), "finished: nothing left to pick up")
        XCTAssertNil(app.answerDraft(for: onScreen), "its answer was recorded")
    }

    /// A session that isn't picked up has no earlier answers and a clock from zero.
    func testAFreshSessionStartsTheClockAndTheBarAtZero() throws {
        let course = makeCourse()
        for i in 0..<4 { makeItem(in: course, prompt: "Card \(i)") }
        app.save()
        let runner = SessionRunner(app: app, request: SessionRequest(kind: .daily), options: .init(liveActivity: false))
        runner.start()
        XCTAssertEqual(Date().timeIntervalSince(runner.startedAt), 0, accuracy: 5)
        XCTAssertTrue(runner.earlier.isEmpty)
        XCTAssertEqual(runner.segmentCount, runner.queue.count)
        XCTAssertEqual(runner.segment(0), .current)
    }

    func testOnlyTodaysOpenSessionIsPickedUp() throws {
        let course = makeCourse()
        for i in 0..<8 { makeItem(in: course, prompt: "Card \(i)") }
        app.save()
        let left = SessionRunner(app: app, request: SessionRequest(kind: .daily), options: .init(liveActivity: false))
        left.start()
        left.record(rating: .good, score: -1, answer: nil, gradedBy: "person", durationMs: 5000, outcome: .right)
        left.advance()
        XCTAssertNotNil(app.sessionCheckpoint())
        left.close()
        XCTAssertNil(app.sessionCheckpoint(), "leaving clears it")
        XCTAssertNil(app.resumableCheckpoint(for: SessionRequest(kind: .daily)))

        let closed = SessionRunner(app: app, request: SessionRequest(kind: .daily), options: .init(liveActivity: false))
        closed.start()
        closed.record(rating: .good, score: -1, answer: nil, gradedBy: "person", durationMs: 5000, outcome: .right)
        closed.advance()
        clock.advance(86_400)
        XCTAssertNil(app.resumableCheckpoint(for: SessionRequest(kind: .daily)), "yesterday's session isn't picked up")
        XCTAssertNil(app.sessionCheckpoint(), "and its checkpoint is cleared")

        let practice = SessionRunner(app: app, request: SessionRequest(kind: .practice), options: .init(liveActivity: false))
        practice.start()
        XCTAssertNil(app.sessionCheckpoint(), "a practice round keeps none")
    }

    func testASessionPickedUpWithNothingLeftEndsTheOneThatWasCutOff() throws {
        let course = makeCourse()
        let only = makeItem(in: course, kind: .recall, prompt: "Why?")
        app.save()
        let first = SessionRunner(app: app, request: SessionRequest(kind: .daily), options: .init(liveActivity: false))
        first.start()
        let sessionID = try XCTUnwrap(first.sessionID)
        app.keepAnswerDraft("half", for: only.id)
        let checkpoint = try XCTUnwrap(app.resumableCheckpoint(for: SessionRequest(kind: .daily)))
        // The question went away meanwhile (deleted on another device): nothing is left to pick up.
        app.setSuspended([only.id], true)
        let second = SessionRunner(app: app, request: SessionRequest(kind: .daily), options: .init(liveActivity: false),
                                   resuming: checkpoint)
        XCTAssertEqual(second.phase, .empty)
        XCTAssertFalse(second.resumed)
        second.close()
        XCTAssertNil(app.sessionCheckpoint())
        XCTAssertNotNil(app.studySession(sessionID)?.endedAt, "the cut-off session is finished, not offered again")
        XCTAssertNil(app.resumableCheckpoint(for: SessionRequest(kind: .daily)))
    }
}

