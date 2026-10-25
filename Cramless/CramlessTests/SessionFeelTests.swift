import SwiftData
import XCTest
@testable import Cramless

/// Runs of right answers, saves, the cues a verdict plays, and the autoplay answers the films depend on.
final class ComboRunTests: XCTestCase {
    private func steps(_ pattern: String) -> [ComboRun.Step] {
        pattern.map { c in
            switch c {
            case "r": ComboRun.Step(counts: true, right: true)
            case "f": ComboRun.Step(counts: false, right: false)   // a flashcard rated anything
            case "F": ComboRun.Step(counts: false, right: true)
            default: ComboRun.Step(counts: true, right: false)
            }
        }
    }

    func testARunCountsRightAnswersBackToTheLastMiss() {
        XCTAssertEqual(ComboRun.length(steps("")), 0)
        XCTAssertEqual(ComboRun.length(steps("rrr")), 3)
        XCTAssertEqual(ComboRun.length(steps("rrwrr")), 2)
        XCTAssertEqual(ComboRun.length(steps("rrrw")), 0, "almost, not yet and I don't know all end it")
    }

    func testFlashcardRatingsNeitherBuildNorBreakARun() {
        XCTAssertEqual(ComboRun.length(steps("rrfr")), 3, "an Again on a flashcard doesn't break it")
        XCTAssertEqual(ComboRun.length(steps("rFFr")), 2, "a Good on a flashcard doesn't build it")
        XCTAssertEqual(ComboRun.length(steps("ffff")), 0)
    }

    func testEveryFifthStepIsAMilestone() {
        XCTAssertEqual((1...16).filter(ComboRun.isMilestone), [5, 10, 15])
        XCTAssertFalse(ComboRun.isMilestone(0))
    }
}

@MainActor
final class SessionFeelTests: XCTestCase {
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

    private func items(_ count: Int, kind: ItemKind = .mcq, memory: MemoryState? = nil) -> [StudyItem] {
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

    private func fading() -> MemoryState {
        let last = cal.adding(days: -30, to: clock.now)
        return MemoryState(state: .review, stability: 2, difficulty: 5, due: last.addingTimeInterval(2 * 86_400),
                           lastReview: last, reps: 3, lapses: 0, step: 0)
    }

    /// Records the runner's current question with `outcome` and moves on.
    private func answer(_ runner: SessionRunner, _ outcome: SessionRunner.Outcome) {
        let rating: Rating = outcome == .right ? .good : outcome == .partial ? .hard : .again
        runner.record(rating: rating, score: outcome == .right ? 1 : 0, answer: nil, gradedBy: "rules", durationMs: 4000,
                      outcome: outcome)
        runner.advance()
    }

    /// Learned and due today (a review, not a save: recall is about 0.9).
    private func due() -> MemoryState {
        let last = cal.adding(days: -3, to: clock.now)
        return MemoryState(state: .review, stability: 3, difficulty: 5, due: clock.now, lastReview: last, reps: 3,
                           lapses: 0, step: 0)
    }

    func testTheCuesClimbTheScaleAndFlourishAtFive() throws {
        let made = items(8, memory: due())
        let runner = SessionRunner(app: app, request: SessionRequest(kind: .practice, itemIDs: made.map(\.id)),
                                   options: .init(liveActivity: false, requeues: false))
        runner.start()
        var played: [[CLCue]] = []
        for _ in 0..<5 {
            let item = try XCTUnwrap(runner.current.flatMap(runner.item(for:)))
            played.append(runner.cues(for: .right, item: item, answered: true))
            answer(runner, .right)
        }
        XCTAssertEqual(played, [[.right(combo: 1)], [.right(combo: 2)], [.right(combo: 3)], [.right(combo: 4)],
                                [.right(combo: 5), .flourish]])
        XCTAssertEqual(runner.combo(), 5)
        let next = try XCTUnwrap(runner.current.flatMap(runner.item(for:)))
        XCTAssertEqual(runner.cues(for: .partial, item: next, answered: true), [.almost])
        XCTAssertEqual(runner.cues(for: .wrong, item: next, answered: true), [.notYet])
        XCTAssertEqual(runner.cues(for: .wrong, item: next, answered: false), [.revealed])
        answer(runner, .partial)
        XCTAssertEqual(runner.combo(), 0, "an almost ends the run")
    }

    func testRightOnAFadingMemorySavesIt() throws {
        let made = items(1, memory: fading())
        let runner = SessionRunner(app: app, request: SessionRequest(kind: .practice, itemIDs: made.map(\.id)),
                                   options: .init(liveActivity: false, requeues: false))
        runner.start()
        let item = try XCTUnwrap(runner.current.flatMap(runner.item(for:)))
        XCTAssertTrue(runner.wouldSave(item))
        XCTAssertEqual(runner.cues(for: .right, item: item, answered: true), [.saved])
        let review = try XCTUnwrap(runner.record(rating: .good, score: 1, answer: nil, gradedBy: "rules", durationMs: 4000,
                                                 outcome: .right))
        XCTAssertTrue(review.isSave, "the preview and the recorded outcome agree")
    }

    func testTheSkysFlareIsPublishedWhenTheViewsAskForItNotWhenAnAnswerIsRecorded() throws {
        let made = items(2, memory: fading())
        let runner = SessionRunner(app: app, request: SessionRequest(kind: .practice, itemIDs: made.map(\.id)),
                                   options: .init(liveActivity: false, requeues: false))
        runner.start()
        XCTAssertNil(runner.saveFlare, "nothing has happened yet")
        let first = try XCTUnwrap(runner.current.flatMap(runner.item(for:)))
        // Recording happens when the person commits; the flare belongs to the moment "Saved it." comes up.
        runner.record(rating: .good, score: 1, answer: nil, gradedBy: "rules", durationMs: 3000, outcome: .right)
        XCTAssertNil(runner.saveFlare, "recording alone shows nothing")
        let before = Date()
        runner.flareSave(of: first)
        let one = try XCTUnwrap(runner.saveFlare)
        XCTAssertEqual(one.id, 1)
        XCTAssertGreaterThanOrEqual(one.at, before, "stamped when it happened")
        XCTAssertLessThanOrEqual(one.at, Date())
        runner.advance()
        let second = try XCTUnwrap(runner.current.flatMap(runner.item(for:)))
        runner.flareSave(of: second)
        XCTAssertEqual(runner.saveFlare?.id, 2, "each save has its own, so two in a row both play")
    }

    func testOnlyARightAnswerIsASaveAnAlmostIsNot() throws {
        // Hard is "Almost.": the person partly had it, and the screen doesn't say "Saved it.", so the count doesn't either.
        let made = items(4, memory: fading())
        let runner = SessionRunner(app: app, request: SessionRequest(kind: .practice, itemIDs: made.map(\.id)),
                                   options: .init(liveActivity: false, requeues: false))
        runner.start()
        var saves: [Bool] = []
        for rating in [Rating.easy, .good, .hard, .again] {
            let review = try XCTUnwrap(runner.record(rating: rating, score: -1, answer: nil, gradedBy: "person", durationMs: 3000,
                                                     outcome: SessionRunner.Outcome(rating: rating)))
            saves.append(review.isSave)
            runner.advance()
        }
        XCTAssertEqual(saves, [true, true, false, false])
    }

    func testANewItemIsNeverASave() throws {
        let made = items(1)
        let runner = SessionRunner(app: app, request: SessionRequest(kind: .practice, itemIDs: made.map(\.id)),
                                   options: .init(liveActivity: false, requeues: false))
        runner.start()
        let item = try XCTUnwrap(runner.current.flatMap(runner.item(for:)))
        XCTAssertFalse(runner.wouldSave(item))
    }

    func testTheLiveRunCountsTheCheckedQuestionOnScreen() {
        let made = items(4)
        let runner = SessionRunner(app: app, request: SessionRequest(kind: .practice, itemIDs: made.map(\.id)),
                                   options: .init(liveActivity: false, requeues: false))
        runner.start()
        answer(runner, .right)
        answer(runner, .right)
        XCTAssertEqual(runner.liveCombo, 2)
        runner.setProvisional(.right)
        XCTAssertEqual(runner.liveCombo, 3, "the third right answer shows the run before Continue")
        runner.setProvisional(.wrong)
        XCTAssertEqual(runner.liveCombo, 0)
    }

    func testAutoplaysRightAnswersGradeRightOffline() throws {
        SampleData.seed(into: app)
        let ownWords = app.fetch(FetchDescriptor<StudyItem>()).filter {
            $0.deletedAt == nil && $0.status == .active && $0.kind.isOwnWords && !$0.keyIdeas.isEmpty
        }
        XCTAssertFalse(ownWords.isEmpty)
        for item in ownWords {
            let subject = app.gradeSubject(for: item)
            let answer = SessionQuestionHost.rightAnswer(to: item, subject: subject)
            XCTAssertEqual(LocalGrader.grade(subject, answer: .text(answer)).verdict, .correct,
                           "autoplay's 'r' must grade right: \(item.prompt)")
        }
    }
}
