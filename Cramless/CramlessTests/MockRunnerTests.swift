import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// A sitting from start to finish over the real store: nothing recorded until hand-in, then one review per answer with a mark.
@MainActor
final class MockRunnerTests: XCTestCase {
    let cal = EngineTest.calendar()
    var clock: TestClock!
    var wall: TestClock!
    var app: AppModel!
    var previousLive: AppModel?
    var course: Course!
    var exam: Exam!

    override func setUp() async throws {
        previousLive = AppModel.live
        clock = TestClock(EngineTest.date(2026, 10, 22, 18, in: cal))
        wall = TestClock(clock.now)
        app = try StudyTestApp.make(clock: clock, calendar: cal)
        AppModel.schedulerFuzz = false
        course = Course(name: "Bio 101", now: clock.now)
        app.context.insert(course)
        exam = Exam(course: course, title: "Midterm", date: cal.adding(days: 10, to: clock.now), now: clock.now)
        app.context.insert(exam)
        course.exams.append(exam)
    }

    override func tearDown() async throws {
        AppModel.schedulerFuzz = true
        AppModel.live = previousLive
        app = nil
    }

    // MARK: Builders

    @discardableResult
    private func addMCQ(_ count: Int, checked: Bool = true, reported: Bool = false) -> [StudyItem] {
        (0..<count).map { index in
            let item = StudyItem(course: course, kind: .mcq, status: .active, origin: .cloud, prompt: "MC \(index)?", answer: "Right",
                                 choices: [Choice(text: "Right", correct: true), Choice(text: "Wrong", correct: false)], now: clock.now)
            item.checkedAt = checked ? clock.now : nil
            item.reported = reported
            app.context.insert(item)
            course.items.append(item)
            return item
        }
    }

    @discardableResult
    private func addRecall(_ count: Int = 1) -> [StudyItem] {
        (0..<count).map { index in
            let item = StudyItem(course: course, kind: .recall, status: .active, origin: .cloud, prompt: "Why do cells divide \(index)?",
                                 answer: "So the body can grow and repair tissue.",
                                 keyIdeas: [KeyIdea(id: "k1", label: "Growth", terms: ["grow", "growth"]),
                                            KeyIdea(id: "k2", label: "Repair", terms: ["repair"])], now: clock.now)
            item.checkedAt = clock.now
            app.context.insert(item)
            course.items.append(item)
            return item
        }
    }

    private func runner() throws -> MockRunner {
        try XCTUnwrap(MockRunner(app: app, examID: exam.id, seed: 7, clock: { [wall] in wall!.now }))
    }

    private func logs() -> [ReviewLog] { app.fetch(FetchDescriptor<ReviewLog>(sortBy: [SortDescriptor(\.reviewedAt)])) }

    private func pickRight(_ runner: MockRunner, _ entry: SessionEntry) {
        runner.setChoice(runner.item(entry)?.choices.firstIndex(where: \.correct), for: entry.itemID)
    }

    private func pickWrong(_ runner: MockRunner, _ entry: SessionEntry) {
        runner.setChoice(runner.item(entry)?.choices.firstIndex { !$0.correct }, for: entry.itemID)
    }

    // MARK: Who is asked

    func testEligibilityLeavesOutReportedAndUncheckedQuestions() throws {
        addMCQ(4)
        addMCQ(3, checked: false)
        addMCQ(3, reported: true)
        let own = StudyItem(course: course, kind: .mcq, status: .active, origin: .person, prompt: "Mine?", answer: "Right",
                            choices: [Choice(text: "Right", correct: true), Choice(text: "Wrong", correct: false)], now: clock.now)
        app.context.insert(own)
        course.items.append(own)
        XCTAssertEqual(app.mockEligibleItems(for: exam).count, 5, "checked, or the student's own")
        XCTAssertEqual(app.mockOffer(for: exam), .tooFew(have: 5))
    }

    func testTheOfferIsHiddenOnTheEveAndTheDay() throws {
        addMCQ(10)
        if case .ready = app.mockOffer(for: exam) {} else { XCTFail("ten days out, ten questions") }
        exam.date = cal.adding(days: 2, to: clock.now)
        if case .ready = app.mockOffer(for: exam) {} else { XCTFail("two days out is still fine") }
        exam.date = cal.adding(days: 1, to: clock.now)
        XCTAssertEqual(app.mockOffer(for: exam), .hidden, "the eve")
        exam.date = clock.now.addingTimeInterval(3600)
        XCTAssertEqual(app.mockOffer(for: exam), .hidden, "the day")
        exam.date = cal.adding(days: -2, to: clock.now)
        XCTAssertEqual(app.mockOffer(for: exam), .hidden, "after")
    }

    // MARK: Sitting

    func testNothingIsRecordedBeforeHandIn() throws {
        addMCQ(8)
        let runner = try runner()
        runner.start(timed: true)
        for entry in runner.plan.entries { pickRight(runner, entry) }
        XCTAssertEqual(runner.answeredCount, 8)
        XCTAssertTrue(logs().isEmpty)
        XCTAssertEqual(app.fetch(FetchDescriptor<StudySession>()).first?.itemCount, 0)
    }

    func testHandInRecordsOneReviewPerAnswerInTheMockSession() async throws {
        addMCQ(8)
        let runner = try runner()
        runner.start(timed: true)
        let started = clock.now
        for (index, entry) in runner.plan.entries.enumerated() {
            clock.advance(60)
            if index % 2 == 0 { pickRight(runner, entry) } else { pickWrong(runner, entry) }
        }
        await runner.handIn()

        XCTAssertEqual(runner.phase, .summary)
        let session = try XCTUnwrap(app.fetch(FetchDescriptor<StudySession>()).first)
        XCTAssertEqual(session.kind, .mock)
        XCTAssertEqual(session.examID, exam.id)
        XCTAssertNotNil(session.readinessBefore)
        XCTAssertNotNil(session.endedAt)
        XCTAssertEqual(session.itemCount, 8)
        let logs = logs()
        XCTAssertEqual(logs.count, 8)
        XCTAssertTrue(logs.allSatisfy { $0.sessionID == session.id })
        XCTAssertTrue(logs.allSatisfy { $0.gradedBy == "rules" })
        XCTAssertEqual(logs.first?.reviewedAt, started.addingTimeInterval(60), "dated when it was answered")
        XCTAssertEqual(logs.last?.reviewedAt, started.addingTimeInterval(480))
        XCTAssertEqual(logs.filter(\.wasCorrect).count, 4)
        XCTAssertEqual(try XCTUnwrap(runner.result?.score), 0.5, accuracy: 1e-9)
    }

    func testAChangedAnswerCountsAsItsLastOne() async throws {
        addMCQ(8)
        let runner = try runner()
        runner.start(timed: false)
        let entry = runner.plan.entries[0]
        pickWrong(runner, entry)
        runner.next()
        runner.back()
        pickRight(runner, entry)
        await runner.handIn()
        XCTAssertEqual(logs().count, 1)
        XCTAssertEqual(logs().first?.wasCorrect, true)
    }

    func testAClearedAnswerIsLeftBlank() async throws {
        addMCQ(8)
        let runner = try runner()
        runner.start(timed: false)
        let entry = runner.plan.entries[0]
        pickRight(runner, entry)
        XCTAssertEqual(runner.answeredCount, 1)
        runner.setChoice(nil, for: entry.itemID)
        XCTAssertEqual(runner.answeredCount, 0)
        XCTAssertEqual(runner.blankCount, 8)
    }

    func testAMockHasNoRequeues() async throws {
        addMCQ(8)
        let runner = try runner()
        runner.start(timed: false)
        for entry in runner.plan.entries { pickWrong(runner, entry) }
        await runner.handIn()
        XCTAssertEqual(logs().count, 8, "every miss once; it comes back in tomorrow's session")
        XCTAssertEqual(Set(logs().map(\.itemID)).count, 8)
    }

    func testBackAndFlagWork() throws {
        addMCQ(8)
        let runner = try runner()
        runner.start(timed: false)
        XCTAssertTrue(runner.isFirst)
        runner.back()
        XCTAssertEqual(runner.position, 0, "nothing before the first")
        runner.next()
        XCTAssertEqual(runner.position, 1)
        runner.toggleFlag()
        XCTAssertTrue(runner.isFlagged)
        XCTAssertEqual(runner.flaggedCount, 1)
        runner.back()
        XCTAssertFalse(runner.isFlagged)
        runner.next()
        runner.toggleFlag()
        XCTAssertEqual(runner.flaggedCount, 0)
        runner.openReview()
        XCTAssertEqual(runner.phase, .review)
        runner.go(to: 5)
        XCTAssertEqual(runner.phase, .answering)
        XCTAssertEqual(runner.position, 5)
    }

    func testTimeOnAQuestionGoesIntoItsReview() async throws {
        addMCQ(8)
        let runner = try runner()
        runner.start(timed: false)
        let entry = runner.plan.entries[0]
        wall.advance(30)
        pickRight(runner, entry)
        runner.next()
        wall.advance(600)
        runner.back()
        wall.advance(10)
        await runner.handIn()
        XCTAssertEqual(logs().first?.durationMs, 40_000, "only while it was on screen")
    }

    // MARK: The clock

    func testTheClockRunsOutAndUntimedFinishesTheRest() async throws {
        addMCQ(8)
        let runner = try runner()
        runner.start(timed: true)
        XCTAssertEqual(runner.deadline, wall.now.addingTimeInterval(Double(runner.plan.minutes) * 60))
        pickRight(runner, runner.plan.entries[0])
        runner.checkTime()
        XCTAssertEqual(runner.phase, .answering, "time left")
        wall.advance(Double(runner.plan.minutes) * 60 + 1)
        runner.checkTime()
        XCTAssertEqual(runner.phase, .timeUp)
        XCTAssertEqual(runner.answeredInTime, 1)

        runner.finishUntimed()
        XCTAssertEqual(runner.phase, .answering)
        XCTAssertNil(runner.deadline)
        XCTAssertEqual(runner.position, 1, "on to the first blank")
        pickRight(runner, runner.plan.entries[1])
        await runner.handIn()
        XCTAssertEqual(runner.answeredInTime, 1, "the summary says how many were in time")
        XCTAssertEqual(logs().count, 2)
    }

    func testSeeMyScoreAtTimeUpCountsWhatIsAnswered() async throws {
        addMCQ(8)
        let runner = try runner()
        runner.start(timed: true)
        for entry in runner.plan.entries.prefix(5) { pickRight(runner, entry) }
        wall.advance(Double(runner.plan.minutes) * 60 + 1)
        runner.checkTime()
        await runner.handIn()
        XCTAssertEqual(runner.phase, .summary)
        XCTAssertEqual(logs().count, 5)
        XCTAssertEqual(runner.result?.counted, 5)
        XCTAssertEqual(runner.result?.total, 8)
        XCTAssertEqual(runner.result?.score, 1)
    }

    func testUntimedHasNoClock() throws {
        addMCQ(8)
        let runner = try runner()
        runner.start(timed: false)
        XCTAssertNil(runner.deadline)
        wall.advance(1_000_000)
        runner.checkTime()
        XCTAssertEqual(runner.phase, .answering)
    }

    // MARK: Leaving

    func testClosingEarlyKeepsTheAnswersAndLeavesTheRestOut() async throws {
        addMCQ(8)
        let runner = try runner()
        runner.start(timed: true)
        pickRight(runner, runner.plan.entries[0])
        pickRight(runner, runner.plan.entries[1])
        await runner.handIn()
        XCTAssertEqual(logs().count, 2)
        XCTAssertEqual(runner.result?.total, 8)
        XCTAssertEqual(runner.result?.counted, 2)
        let session = try XCTUnwrap(app.fetch(FetchDescriptor<StudySession>()).first)
        XCTAssertNotNil(session.endedAt)
    }

    func testLeavingWithNothingAnsweredRecordsNothing() throws {
        addMCQ(8)
        let runner = try runner()
        runner.start(timed: true)
        runner.abandon()
        XCTAssertTrue(logs().isEmpty)
        XCTAssertNil(app.lastMock(for: exam.id), "an empty sitting isn't a mock")
        XCTAssertNotNil(app.fetch(FetchDescriptor<StudySession>()).first?.endedAt)
    }

    func testHandingInTwiceRecordsOnce() async throws {
        addMCQ(8)
        let runner = try runner()
        runner.start(timed: false)
        pickRight(runner, runner.plan.entries[0])
        await runner.handIn()
        await runner.handIn()
        XCTAssertEqual(logs().count, 1)
    }

    // MARK: Marking it yourself

    func testAnAnswerNoModelGradesWaitsForTheStudentsMark() async throws {
        // With no consent and no model on this route, an attempt the rules can't vouch for is the person's to mark.
        addMCQ(7)
        let written = addRecall()[0]
        app.settings.cloudConsentVersion = 0
        let runner = try runner()
        runner.start(timed: false)
        for entry in runner.plan.entries where entry.kind == .mcq { pickRight(runner, entry) }
        // Words about the subject that name no key idea: not correct, and not off the subject either.
        runner.setText("Cells divide because of the body", for: written.id)
        await runner.handIn()

        XCTAssertEqual(logs().count, 7, "not recorded before it is marked")
        XCTAssertEqual(runner.toMark.map(\.itemID), [written.id])
        XCTAssertEqual(runner.result?.counted, 7)

        runner.mark(written.id, ticked: ["k1"])
        XCTAssertTrue(runner.toMark.isEmpty)
        let log = try XCTUnwrap(logs().first { $0.itemID == written.id })
        XCTAssertEqual(log.gradedBy, "self")
        XCTAssertEqual(log.sessionID, app.fetch(FetchDescriptor<StudySession>()).first?.id)
        XCTAssertEqual(runner.result?.counted, 8)
        XCTAssertEqual(try XCTUnwrap(runner.result?.score), (7 + log.score) / 8, accuracy: 1e-9)
    }

    func testABlankWrittenAnswerIsNotRecorded() async throws {
        addMCQ(7)
        let written = addRecall()[0]
        let runner = try runner()
        runner.start(timed: false)
        for entry in runner.plan.entries where entry.kind == .mcq { pickRight(runner, entry) }
        runner.setText("   ", for: written.id)
        await runner.handIn()
        XCTAssertFalse(logs().contains { $0.itemID == written.id })
        XCTAssertEqual(runner.marks[written.id], .blank)
        XCTAssertTrue(runner.toMark.isEmpty)
    }

    // MARK: Afterwards

    func testTheLastMockIsReadBackFromTheLog() async throws {
        addMCQ(8)
        XCTAssertNil(app.lastMock(for: exam.id))
        let runner = try runner()
        runner.start(timed: false)
        for (index, entry) in runner.plan.entries.enumerated() {
            if index < 6 { pickRight(runner, entry) } else { pickWrong(runner, entry) }
        }
        await runner.handIn()
        let last = try XCTUnwrap(app.lastMock(for: exam.id))
        XCTAssertEqual(last.score, 0.75, accuracy: 1e-9)
        XCTAssertEqual(last.date, clock.now)
        XCTAssertFalse(app.mockIsDue(for: exam), "not again so soon")
    }

    func testAMissComesBackAsAReview() async throws {
        let items = addMCQ(8)
        let runner = try runner()
        runner.start(timed: false)
        for entry in runner.plan.entries { pickWrong(runner, entry) }
        await runner.handIn()
        XCTAssertTrue(items.allSatisfy { $0.memory.state != .new }, "the mock's answers count")
        XCTAssertTrue(items.allSatisfy { $0.lapses >= 0 && $0.memory.lastReview == clock.now })
    }

    func testTheStreakCounts() async throws {
        addMCQ(8)
        let runner = try runner()
        runner.start(timed: false)
        pickRight(runner, runner.plan.entries[0])
        await runner.handIn()
        XCTAssertTrue(app.streak().studiedToday)
    }

    func testARequestForAMockBuildsOne() throws {
        addMCQ(10)
        let built = app.buildSession(SessionRequest(kind: .mock, examID: exam.id, questionCount: 8))
        XCTAssertEqual(built.kind, .mock)
        XCTAssertEqual(built.entries.count, 8)
        XCTAssertEqual(built.examID, exam.id)
        XCTAssertGreaterThan(built.budgetSeconds, 0)
    }
}
