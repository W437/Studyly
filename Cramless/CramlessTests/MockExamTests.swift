import Foundation
import XCTest
@testable import Cramless

/// The mock exam's engine: what it asks, in what order, how long it runs, and the fair score it is compared with.
final class MockExamTests: XCTestCase {
    let cal = EngineTest.calendar()
    lazy var now = EngineTest.date(2026, 10, 22, 18, in: cal)
    let course = UUID()

    private var builder: MockExamBuilder { MockExamBuilder(fsrs: FSRS(), calendar: cal, now: now) }

    private func exam(format: ExamFormat = ExamFormat(), scope: Set<UUID> = []) -> ExamSnapshot {
        ExamSnapshot(courseID: course, title: "Midterm", date: cal.adding(days: 10, to: now), scope: scope, format: format)
    }

    private func item(_ kind: ItemKind, topic: UUID? = nil, memory: MemoryState = .new, status: ItemStatus = .active, course other: UUID? = nil) -> ItemSnapshot {
        ItemSnapshot(kind: kind, topicID: topic, courseID: other ?? course, memory: memory, status: status)
    }

    private func items(_ count: Int, _ kind: ItemKind, topic: UUID? = nil) -> [ItemSnapshot] {
        (0..<count).map { _ in item(kind, topic: topic) }
    }

    private func studied(stability: Double, daysAgo: Int) -> MemoryState {
        MemoryState(state: .review, stability: stability, difficulty: 5, due: cal.adding(days: 3, to: now),
                    lastReview: cal.adding(days: -daysAgo, to: now), reps: 3)
    }

    // MARK: What it asks

    func testAMockTakesOnlyTheExamsScope() throws {
        let inside = UUID(), outside = UUID()
        let pool = items(12, .mcq, topic: inside) + items(12, .mcq, topic: outside) + [item(.mcq, topic: inside, course: UUID())]
        let plan = try XCTUnwrap(builder.build(exam: exam(scope: [inside]), items: pool, seed: 1))
        XCTAssertEqual(plan.entries.count, 12)
        XCTAssertTrue(plan.entries.allSatisfy { $0.topicID == inside })
    }

    func testTheKindsFollowTheFormat() {
        XCTAssertEqual(MockExamBuilder.kinds(for: ExamFormat(multipleChoice: true, shortAnswer: false)), [.mcq])
        XCTAssertEqual(MockExamBuilder.kinds(for: ExamFormat(multipleChoice: false, shortAnswer: true)), [.recall, .cloze])
        XCTAssertEqual(MockExamBuilder.kinds(for: ExamFormat(multipleChoice: false, shortAnswer: false, essay: true)), [.apply])
        XCTAssertEqual(MockExamBuilder.kinds(for: ExamFormat(multipleChoice: false, shortAnswer: false)), [.mcq, .recall, .cloze, .apply],
                       "nothing ticked asks all four")
    }

    func testFlashcardsDiagramsAndSuspendedQuestionsStayOut() throws {
        let pool = items(10, .mcq) + items(10, .flashcard) + items(5, .diagram) + [item(.mcq, status: .suspended)]
        let plan = try XCTUnwrap(builder.build(exam: exam(), items: pool, seed: 1))
        XCTAssertEqual(plan.entries.count, 10)
        XCTAssertTrue(plan.entries.allSatisfy { $0.kind == .mcq })
    }

    func testBelowEightQuestionsThereIsNoMock() {
        XCTAssertNil(builder.build(exam: exam(), items: items(7, .mcq), seed: 1))
        XCTAssertNotNil(builder.build(exam: exam(), items: items(8, .mcq), seed: 1))
    }

    func testTheSizeComesFromTheExamWithinWhatASittingTakes() throws {
        let pool = items(60, .mcq)
        XCTAssertEqual(try XCTUnwrap(builder.build(exam: exam(), items: pool, seed: 1)).entries.count, MockExamBuilder.defaultSize)
        var format = ExamFormat(multipleChoice: true, shortAnswer: false)
        format.questionCount = 30
        XCTAssertEqual(try XCTUnwrap(builder.build(exam: exam(format: format), items: pool, seed: 1)).entries.count, 30)
        format.questionCount = 200
        XCTAssertEqual(try XCTUnwrap(builder.build(exam: exam(format: format), items: pool, seed: 1)).entries.count, MockExamBuilder.maximumSize)
        format.questionCount = 3
        XCTAssertEqual(try XCTUnwrap(builder.build(exam: exam(format: format), items: pool, seed: 1)).entries.count, MockExamBuilder.minimumQuestions)
        XCTAssertEqual(try XCTUnwrap(builder.build(exam: exam(), items: pool, seed: 1, size: 12)).entries.count, 12, "a request's size wins")
    }

    func testTopicsAreSharedBySizeAndNoneIsLeftOut() throws {
        let big = UUID(), middle = UUID(), small = UUID()
        let pool = items(40, .mcq, topic: big) + items(20, .mcq, topic: middle) + items(1, .mcq, topic: small)
        let plan = try XCTUnwrap(builder.build(exam: exam(), items: pool, seed: 3, size: 20))
        let counts = Dictionary(grouping: plan.entries, by: \.topicID).mapValues(\.count)
        XCTAssertEqual(counts[big], 13)
        XCTAssertEqual(counts[middle], 6)
        XCTAssertEqual(counts[small], 1, "even a small topic gets one")
    }

    func testQuotasAddUpAndFitTheirBuckets() {
        XCTAssertEqual(MockExamBuilder.quotas(counts: [10, 10], total: 5).reduce(0, +), 5)
        XCTAssertEqual(MockExamBuilder.quotas(counts: [3, 3, 3], total: 9), [3, 3, 3])
        XCTAssertEqual(MockExamBuilder.quotas(counts: [50, 1, 1, 1], total: 8), [5, 1, 1, 1])
        XCTAssertEqual(MockExamBuilder.quotas(counts: [1, 1, 1], total: 2), [1, 1, 0], "too many topics: the first in order")
        XCTAssertEqual(MockExamBuilder.quotas(counts: [], total: 5), [])
    }

    func testMultipleChoiceTakesThreeInFourAndComesFirst() throws {
        let a = UUID(), b = UUID()
        let pool = items(20, .mcq, topic: a) + items(10, .recall, topic: a) + items(20, .mcq, topic: b) + items(10, .cloze, topic: b)
        let plan = try XCTUnwrap(builder.build(exam: exam(), items: pool, seed: 5, size: 20))
        XCTAssertEqual(plan.multipleChoiceCount, 15)
        XCTAssertEqual(plan.shortCount + plan.fillInCount, 5)
        XCTAssertTrue(plan.entries.prefix(15).allSatisfy { $0.kind == .mcq }, "multiple choice first")
        XCTAssertTrue(plan.entries.dropFirst(15).allSatisfy { $0.kind != .mcq })
        for pair in zip(plan.entries.prefix(15), plan.entries.prefix(15).dropFirst()) {
            XCTAssertNotEqual(pair.0.topicID, pair.1.topicID, "the topics are interleaved")
        }
    }

    func testTheMixIsSharedOverTheTopics() {
        XCTAssertEqual(MockExamBuilder.split(15, of: [10, 10], available: [20, 20], others: [10, 10]), [8, 7])
        XCTAssertEqual(MockExamBuilder.split(6, of: [4, 4], available: [1, 8], others: [8, 0]), [1, 4],
                       "a topic can't give what it doesn't have, and one with only multiple choice takes it all")
        XCTAssertEqual(MockExamBuilder.split(0, of: [4, 4], available: [0, 0], others: [4, 4]), [0, 0])
        XCTAssertEqual(MockExamBuilder.split(8, of: [4, 4], available: [4, 4], others: [0, 0]), [4, 4])
        XCTAssertEqual(MockExamBuilder.split(5, of: [0, 0], available: [0, 0], others: [0, 0]), [0, 0])
    }

    func testAShortKindIsToppedUpFromTheOther() throws {
        let few = try XCTUnwrap(builder.build(exam: exam(), items: items(3, .mcq) + items(30, .recall), seed: 2, size: 20))
        XCTAssertEqual(few.multipleChoiceCount, 3)
        XCTAssertEqual(few.entries.count, 20)
        let onlyWritten = try XCTUnwrap(builder.build(exam: exam(), items: items(9, .recall), seed: 2))
        XCTAssertEqual(onlyWritten.entries.count, 9)
        XCTAssertEqual(onlyWritten.multipleChoiceCount, 0)
    }

    func testUnseenQuestionsAreInThereAndAskedOnce() throws {
        let seen = (0..<10).map { _ in item(.mcq, memory: studied(stability: 30, daysAgo: 3)) }
        let plan = try XCTUnwrap(builder.build(exam: exam(), items: seen + items(10, .mcq), seed: 4, size: 20))
        XCTAssertEqual(plan.entries.filter { $0.reason == .new }.count, 10)
        XCTAssertEqual(Set(plan.entries.map(\.itemID)).count, plan.entries.count)
    }

    func testTheSameSeedGivesTheSameMockAndAnotherSeedAnother() throws {
        let pool = items(50, .mcq, topic: UUID()) + items(50, .mcq, topic: UUID())
        let midterm = exam()
        let one = try XCTUnwrap(builder.build(exam: midterm, items: pool, seed: 11))
        XCTAssertEqual(one, try XCTUnwrap(builder.build(exam: midterm, items: pool, seed: 11)))
        XCTAssertEqual(one, try XCTUnwrap(builder.build(exam: midterm, items: pool.reversed(), seed: 11)), "whatever order the store gave them")
        XCTAssertNotEqual(one.entries, try XCTUnwrap(builder.build(exam: midterm, items: pool, seed: 12)).entries)
    }

    // MARK: Time

    func testTimeFollowsTheRealExamsPaceWhenItIsKnown() {
        let entries = items(20, .mcq).map { SessionEntry(itemID: $0.id, reason: .new, kind: .mcq, estimatedSeconds: 60) }
        var format = ExamFormat()
        format.minutes = 90
        format.questionCount = 60
        XCTAssertEqual(MockExamBuilder.minutes(for: entries, format: format), 30, "20 of 60 questions at the real pace")
        format.questionCount = nil
        XCTAssertEqual(MockExamBuilder.minutes(for: entries, format: format), 20, "by the kinds, within the real length")
        format.minutes = 12
        XCTAssertEqual(MockExamBuilder.minutes(for: entries, format: format), 15, "rounded up to 5")
    }

    func testTimeByKindRoundsUpToFiveMinutes() {
        func entry(_ kind: ItemKind) -> SessionEntry { SessionEntry(itemID: UUID(), reason: .new, kind: kind, estimatedSeconds: 1) }
        // 60 + 45 + 120 + 180 = 405 s, 6.75 minutes.
        XCTAssertEqual(MockExamBuilder.minutes(for: [entry(.mcq), entry(.cloze), entry(.recall), entry(.apply)], format: ExamFormat()), 10)
        XCTAssertEqual(MockExamBuilder.minutes(for: [entry(.mcq)], format: ExamFormat()), 5)
    }

    // MARK: The fair score

    func testExpectedIsRecallNowPlusTheGuessingFloor() throws {
        XCTAssertEqual(MockExamBuilder.expectedCredit(recall: 0, guess: 0.25), 0.25, accuracy: 1e-9)
        XCTAssertEqual(MockExamBuilder.expectedCredit(recall: 0.8, guess: 0.25), 0.85, accuracy: 1e-9)
        XCTAssertEqual(MockExamBuilder.expectedCredit(recall: 0.8, guess: 0), 0.8, accuracy: 1e-9)

        let memory = studied(stability: 10, daysAgo: 10)
        let known = (0..<4).map { _ in item(.recall, memory: memory) }
        let unseen = items(4, .mcq)
        var choices: [UUID: Int] = [:]
        for question in unseen { choices[question.id] = 2 }
        let plan = try XCTUnwrap(builder.build(exam: exam(), items: known + unseen, choices: choices, seed: 1))
        let recall = FSRS().retrievability(elapsedDays: 10, stability: 10)
        for question in known { XCTAssertEqual(plan.expectedByItem[question.id] ?? -1, recall, accuracy: 1e-6) }
        for question in unseen { XCTAssertEqual(plan.expectedByItem[question.id] ?? -1, 0.5, accuracy: 1e-9, "a blind guess, nothing more") }
        XCTAssertEqual(plan.expected, (recall * 4 + 0.5 * 4) / 8, accuracy: 1e-6)
    }

    func testAnUnseenWrittenQuestionIsExpectedToEarnNothing() throws {
        let plan = try XCTUnwrap(builder.build(exam: exam(), items: items(8, .recall), seed: 1))
        XCTAssertEqual(plan.expected, 0)
    }

    // MARK: Scoring

    private func line(_ credit: Double?, expected: Double = 0.5, topic: UUID? = nil) -> MockLine {
        MockLine(itemID: UUID(), topicID: topic, expected: expected, credit: credit)
    }

    func testPartialCreditAndBlanksScoreOnlyWhatHasAMark() throws {
        let result = MockScorer.score([line(1, expected: 0.8), line(0.5, expected: 0.6), line(0, expected: 0.4), line(nil, expected: 0.1)], topicNames: [:])
        XCTAssertEqual(result.total, 4)
        XCTAssertEqual(result.counted, 3)
        XCTAssertEqual(try XCTUnwrap(result.score), 0.5, accuracy: 1e-9)
        XCTAssertEqual(result.expected, 0.6, accuracy: 1e-9, "a question with no mark leaves the prediction too")
    }

    func testNothingMarkedHasNoScore() {
        let result = MockScorer.score([line(nil), line(nil)], topicNames: [:])
        XCTAssertNil(result.score)
        XCTAssertNil(result.verdict)
        XCTAssertEqual(result.counted, 0)
    }

    func testTopicsAreWeakestFirstAndThreeAtMostAreCalledWeak() {
        let names = (0..<5).map { _ in UUID() }
        let topicNames = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.element, "Topic \($0.offset)") })
        let lines = [line(0.2, topic: names[0]), line(0.9, topic: names[1]), line(0.4, topic: names[2]), line(0.1, topic: names[3]),
                     line(0.6, topic: names[4]), line(1, topic: nil)]
        let result = MockScorer.score(lines, topicNames: topicNames)
        XCTAssertEqual(result.topics.map(\.name), ["Topic 3", "Topic 0", "Topic 2", "Topic 4", "Topic 1"])
        XCTAssertEqual(result.weakest.map(\.name), ["Topic 3", "Topic 0", "Topic 2"], "three, under 70%")
    }

    func testAStrongTopicIsNotCalledWeak() {
        let topic = UUID()
        let result = MockScorer.score([line(0.7, topic: topic), line(0.7, topic: topic)], topicNames: [topic: "Moles"])
        XCTAssertEqual(result.topics.count, 1)
        XCTAssertTrue(result.weakest.isEmpty, "exactly 70% isn't under it")
    }

    func testTheVerdictIsFivePointsEitherWay() {
        XCTAssertEqual(MockScorer.verdict(score: 0.70, expected: 0.70), .asExpected)
        XCTAssertEqual(MockScorer.verdict(score: 0.75, expected: 0.70), .asExpected)
        XCTAssertEqual(MockScorer.verdict(score: 0.65, expected: 0.70), .asExpected)
        XCTAssertEqual(MockScorer.verdict(score: 0.76, expected: 0.70), .better)
        XCTAssertEqual(MockScorer.verdict(score: 0.64, expected: 0.70), .below)
    }

    // MARK: Today's offer

    func testTodayOffersAMockTwoToSevenDaysOutWithEnoughQuestionsAndNoneLately() {
        func due(_ days: Int, eligible: Int = 12, last: Int? = nil) -> Bool {
            MockSuggestion.isDue(daysLeft: days, eligible: eligible, lastMockAt: last.map { cal.adding(days: -$0, to: now) }, now: now, calendar: cal)
        }
        XCTAssertTrue(due(2))
        XCTAssertTrue(due(7))
        XCTAssertFalse(due(1), "not on the eve")
        XCTAssertFalse(due(0), "not on the day")
        XCTAssertFalse(due(8))
        XCTAssertFalse(due(5, eligible: 7))
        XCTAssertFalse(due(5, last: 3))
        XCTAssertTrue(due(5, last: 4))
    }

    // MARK: Words

    func testTheWordsReadRight() {
        XCTAssertEqual(MockCopy.cardLine(questions: 20, minutes: 25), "20 questions like the real one · 25 min")
        XCTAssertEqual(MockCopy.tooFew(have: 2, format: ExamFormat(multipleChoice: true, shortAnswer: false)),
                       "This exam is multiple choice. A mock needs 8 of those, and you have 2.")
        XCTAssertEqual(MockCopy.tooFew(have: 3, format: ExamFormat(multipleChoice: false, shortAnswer: true)),
                       "This exam is short answer. A mock needs 8 of those, and you have 3.")
        XCTAssertEqual(MockCopy.tooFew(have: 0, format: ExamFormat(multipleChoice: false, shortAnswer: false, essay: true)),
                       "This exam is essay questions. A mock needs 8 of those, and you have 0.")
        XCTAssertEqual(MockCopy.tooFew(have: 5, format: ExamFormat(multipleChoice: true, shortAnswer: true)),
                       "This exam is multiple choice and short answer. A mock needs 8 of those, and you have 5.")
        XCTAssertEqual(MockCopy.tooFew(have: 1, format: ExamFormat(multipleChoice: false, shortAnswer: false)),
                       "A mock needs 8 multiple-choice or written questions, and you have 1.")
        XCTAssertEqual(MockCopy.verdictLine(.asExpected), "Right where Cap expected.")
        XCTAssertEqual(MockCopy.verdictLine(.better), "Better than Cap expected.")
        XCTAssertEqual(MockCopy.scored(0.72), "You scored 72%.")
        XCTAssertEqual(MockCopy.predicted(0.68), "Cap predicted 68%.")
        XCTAssertEqual(MockCopy.timeUpLine(answered: 17, total: 20), "You answered 17 of 20. Finish the rest without the clock, or see your score now.")
        XCTAssertEqual(MockCopy.scopeLine(counted: 17, total: 20, inTime: 17), "You answered 17 of 20 in time.")
        XCTAssertEqual(MockCopy.scopeLine(counted: 12, total: 20, inTime: nil), "Scored on the 12 of 20 you answered.")
        XCTAssertNil(MockCopy.scopeLine(counted: 20, total: 20, inTime: nil))
        XCTAssertTrue(MockCopy.mixLine(multiple: 15, short: 5, essay: 0).contains("15 multiple choice"))
        XCTAssertTrue(MockCopy.mixLine(multiple: 15, short: 5, essay: 0).contains("5 short answers"))
        XCTAssertFalse(MockCopy.mixLine(multiple: 15, short: 0, essay: 0).contains("short"))
    }

    /// The intro's short answers are what marking counts: fill-ins are marked at once and have their own word.
    func testTheMixAndTheMarkingCountTheSameAnswers() throws {
        let pool = items(4, .cloze, topic: UUID()) + items(8, .recall, topic: UUID())
        let plan = try XCTUnwrap(builder.build(exam: exam(format: ExamFormat(multipleChoice: false, shortAnswer: true)), items: pool, seed: 5, size: 12))
        XCTAssertEqual(plan.fillInCount, 4)
        XCTAssertEqual(plan.shortCount, 8)
        XCTAssertEqual(MockCopy.mixLine(multiple: plan.multipleChoiceCount, fillIns: plan.fillInCount, short: plan.shortCount, essay: plan.essayCount),
                       "Matches your exam: 4 fill-ins and 8 short answers. Only this exam's topics.")
        XCTAssertEqual(MockCopy.markingLine(done: 8, total: plan.shortCount), "8 of 8 short answers marked")
        XCTAssertEqual(MockCopy.markingLine(done: 1, total: 1), "1 of 1 short answer marked")
        XCTAssertEqual(MockCopy.markingLine(done: 2, total: 3, hasEssays: true), "2 of 3 written answers marked")
        XCTAssertEqual(MockCopy.mixLine(multiple: 1, fillIns: 1, short: 1, essay: 1),
                       "Matches your exam: 1 multiple choice, 1 fill-in, 1 short answer, and 1 essay question. Only this exam's topics.")
    }

    /// The prediction sits beside the exam page's readiness, a different number on purpose: the summary says why, with no number of its own.
    func testThePredictionExplainsItselfWithoutANewPercentage() {
        XCTAssertEqual(MockCopy.predictionNote, "Cap's prediction is for this mock, today. Readiness is what you'd remember on exam day.")
        XCTAssertFalse(MockCopy.predictionNote.contains("%"))
    }

    func testPluralsReadInTheSingular() {
        XCTAssertEqual(MockCopy.markYourself(1), "Mark 1 answer yourself")
        XCTAssertEqual(MockCopy.markYourself(3), "Mark 3 answers yourself")
        XCTAssertEqual(MockCopy.blanksLine(1), "1 left blank. It stays out of your score.")
        XCTAssertNil(MockCopy.blanksLine(0))
    }
}
