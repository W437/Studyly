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

    /// What the sample page gives with Cloud AI off, and the review notes rely on: 8 questions, 6 of them of a mock's kinds. That's two short, and the words say what to do
    /// next. A mock of six, with a score to hold against Cap's prediction, wouldn't say much, so the minimum stays.
    func testASampleOnlyStudentIsTwoShortAndToldWhatToDoNext() {
        let pool = items(3, .mcq) + items(2, .recall) + items(1, .cloze) + items(2, .flashcard)
        XCTAssertEqual(MockExamBuilder.eligible(pool, exam: exam()).count, 6)
        XCTAssertNil(builder.build(exam: exam(), items: pool, seed: 1))
        XCTAssertEqual(MockCopy.tooFew(have: 6, format: ExamFormat()),
                       "This exam is multiple choice and short answer. A mock needs 8 of those, and you have 6. Add a page or paste your notes, and Cap writes more.")
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

    // MARK: The exam's stated mix

    private func stated(_ multiple: Int?, _ short: Int?, _ essay: Int? = nil, questions: Int? = 40, minutes: Int? = 90) -> ExamFormat {
        ExamFormat(multipleChoice: multiple != nil, shortAnswer: short != nil, essay: essay != nil, questionCount: questions, minutes: minutes,
                   multipleChoiceCount: multiple, shortAnswerCount: short, essayCount: essay)
    }

    func testAStatedMixIsFollowedWhereTheQuestionsAreThere() throws {
        let topic = UUID()
        let plan = try XCTUnwrap(builder.build(exam: exam(format: stated(30, 10)), items: items(40, .mcq, topic: topic) + items(20, .recall, topic: topic), seed: 3))
        XCTAssertEqual(plan.entries.count, 40)
        XCTAssertEqual(plan.multipleChoiceCount, 30)
        XCTAssertEqual(plan.shortCount, 10)
        XCTAssertEqual(plan.minutes, 90)
        XCTAssertTrue(plan.holdsMix(of: stated(30, 10)))
    }

    /// The same mix at a smaller size: 3 in 4, not whatever the questions happen to be.
    func testAMixScalesDownWithTheMock() throws {
        let format = stated(10, 30)
        let plan = try XCTUnwrap(builder.build(exam: exam(format: format), items: items(20, .mcq) + items(40, .recall), seed: 3, size: 20))
        XCTAssertEqual(plan.multipleChoiceCount, 5, "a stated 1 in 4, where the default would be 3 in 4")
        XCTAssertEqual(plan.shortCount, 15)
    }

    func testShortOfOneKindTheOtherFillsAndTheWordsSaySo() throws {
        let format = stated(30, 10)
        let plan = try XCTUnwrap(builder.build(exam: exam(format: format), items: items(6, .mcq) + items(7, .recall), seed: 3))
        XCTAssertEqual(plan.entries.count, 13)
        XCTAssertEqual(plan.multipleChoiceCount, 6)
        XCTAssertEqual(plan.shortCount, 7)
        XCTAssertFalse(plan.holdsMix(of: format))
        XCTAssertEqual(plan.minutes, 30, "the real exam's pace: 13 of 40 at 90 minutes")
        let words = MockCopy.offer(plan, format: format)
        XCTAssertEqual(words.line, "13 of the real 40 questions · 30 min")
        XCTAssertEqual(words.mix, "That's every question you have for it so far, with the time scaled to match. 6 multiple choice and 7 short answers: the real one's mix, as far as your questions go. Only this exam's topics.")
    }

    func testFillInsOnlyStandInForShortAnswersAndSaySo() throws {
        let format = stated(30, 10)
        // Enough short answers: no fill-in, though there are plenty.
        let plenty = try XCTUnwrap(builder.build(exam: exam(format: format), items: items(30, .mcq) + items(10, .recall) + items(10, .cloze), seed: 1))
        XCTAssertEqual(plenty.fillInCount, 0)
        XCTAssertEqual(plenty.shortCount, 10)
        XCTAssertFalse(MockCopy.offer(plenty, format: format).mix.contains("fill-in"))
        XCTAssertTrue(MockCopy.offer(plenty, format: format).mix.hasPrefix("Matches your exam: 30 multiple choice and 10 short answers."))
        // Too few: fill-ins take the short answers' places, before more multiple choice does.
        let few = try XCTUnwrap(builder.build(exam: exam(format: format), items: items(40, .mcq) + items(2, .recall) + items(5, .cloze), seed: 1))
        XCTAssertEqual(few.multipleChoiceCount, 33)
        XCTAssertEqual(few.shortCount, 2)
        XCTAssertEqual(few.fillInCount, 5)
        XCTAssertEqual(MockCopy.offer(few, format: format).mix,
                       "33 multiple choice and 2 short answers, with 5 fill-ins standing in for short answers you don't have yet. Only this exam's topics.")
    }

    /// The page's numbers are only a mix for the kinds still ticked, and a kind with no number takes what the exam's size leaves.
    func testTheStatedMixReadsTheFormatAsItStands() {
        XCTAssertEqual(stated(30, 10).statedMix?.multiple, 30)
        XCTAssertEqual(stated(30, nil).statedMix?.short, 0)
        var unnamed = ExamFormat(multipleChoice: true, shortAnswer: true, questionCount: 40, multipleChoiceCount: 30)
        XCTAssertEqual(unnamed.statedMix?.short, 10, "what the size leaves")
        unnamed.questionCount = nil
        XCTAssertNil(unnamed.statedMix, "the numbers can't say how the places divide")
        var unticked = stated(30, 10)
        unticked.multipleChoice = false
        XCTAssertEqual(unticked.statedMix?.multiple, 0)
        XCTAssertEqual(unticked.statedMix?.short, 10)
        XCTAssertNil(ExamFormat().statedMix)
    }

    func testTheNumbersInASyllabusLine() {
        let line = StatedCounts("40 questions: 30 multiple choice and 10 short answers, 90 minutes.")
        XCTAssertEqual(line.multipleChoice, 30)
        XCTAssertEqual(line.shortAnswer, 10)
        XCTAssertNil(line.essay)
        XCTAssertEqual(StatedCounts("30 MCQs, 10 short, 2 essays").essay, 2)
        XCTAssertEqual(StatedCounts("30 MCQs, 10 short, 2 essays").multipleChoice, 30)
        XCTAssertNil(StatedCounts("Multiple choice and short answer").multipleChoice)
    }

    func testAMockShorterThanTheRealOneSaysWhy() {
        XCTAssertEqual(MockCopy.cardLine(questions: 13, minutes: 30, realQuestions: 40), "13 of the real 40 questions · 30 min")
        XCTAssertEqual(MockCopy.cardLine(questions: 40, minutes: 90, realQuestions: 40), "40 questions like the real one · 90 min")
        XCTAssertEqual(MockCopy.cardLine(questions: 8, minutes: 15, realQuestions: 3), "8 questions · 15 min", "a real one smaller than a mock can be")
        XCTAssertEqual(MockCopy.whyShorter(questions: 40, format: stated(70, 30, questions: 100)), "A mock stops at 40 questions, with the time scaled to match.")
        XCTAssertEqual(MockCopy.whyShorter(questions: 13, format: stated(30, 10, minutes: nil)), "That's every question you have for it so far.")
        XCTAssertNil(MockCopy.whyShorter(questions: 40, format: stated(30, 10)))
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

    // MARK: An essay exam

    private var essays: ExamFormat {
        var format = ExamFormat()
        format.multipleChoice = false
        format.shortAnswer = false
        format.essay = true
        return format
    }

    func testAnEssayExamNeedsOnlyAFewEssaysAndGivesThemTime() throws {
        let builder = MockExamBuilder(fsrs: FSRS(), calendar: cal, now: now)
        XCTAssertNil(builder.build(exam: exam(format: essays), items: items(1, .apply), seed: 1), "one essay is no mock")
        let two = try XCTUnwrap(builder.build(exam: exam(format: essays), items: items(2, .apply), seed: 1))
        XCTAssertEqual(two.entries.count, 2)
        XCTAssertEqual(two.minutes, 30, "fifteen minutes each")
        let many = try XCTUnwrap(builder.build(exam: exam(format: essays), items: items(9, .apply) + items(40, .mcq), seed: 1))
        XCTAssertEqual(many.entries.count, MockExamBuilder.defaultEssays, "a real essay exam is a few long answers")
        XCTAssertTrue(many.entries.allSatisfy { $0.kind == .apply })
        XCTAssertEqual(many.minutes, 45)
    }

    func testAnEssayMockKeepsTheRealOnesPaceAndCount() throws {
        var format = essays
        format.essayCount = 4
        format.minutes = 120
        let builder = MockExamBuilder(fsrs: FSRS(), calendar: cal, now: now)
        let plan = try XCTUnwrap(builder.build(exam: exam(format: format), items: items(9, .apply), seed: 1))
        XCTAssertEqual(plan.entries.count, 4)
        XCTAssertEqual(plan.minutes, 120)
        let short = try XCTUnwrap(builder.build(exam: exam(format: format), items: items(2, .apply), seed: 1))
        XCTAssertEqual(short.minutes, 60, "the same pace for the two there are")
    }

    func testTheMinimumFollowsTheFormatInItsWordsAndItsOffer() {
        XCTAssertEqual(MockExamBuilder.minimum(for: essays), 2)
        XCTAssertEqual(MockExamBuilder.minimum(for: ExamFormat()), MockExamBuilder.minimumQuestions)
        var both = essays
        both.multipleChoice = true
        XCTAssertEqual(MockExamBuilder.minimum(for: both), MockExamBuilder.minimumQuestions, "a mixed exam isn't essay-only")
        XCTAssertEqual(MockCopy.tooFew(have: 1, format: essays), "This exam is essay questions. A mock needs 2 of those, and you have 1. Add a page or paste your notes, and Cap writes more.")
        XCTAssertTrue(MockSuggestion.isDue(daysLeft: 5, eligible: 2, studied: 1, minimum: MockExamBuilder.minimum(for: essays), lastMockAt: nil, now: now, calendar: cal))
    }

    // MARK: Today's offer

    func testTodayOffersAMockTwoToSevenDaysOutWithEnoughQuestionsAndNoneLately() {
        func due(_ days: Int, eligible: Int = 12, studied: Int = 6, last: Int? = nil) -> Bool {
            MockSuggestion.isDue(daysLeft: days, eligible: eligible, studied: studied, lastMockAt: last.map { cal.adding(days: -$0, to: now) }, now: now, calendar: cal)
        }
        XCTAssertFalse(due(5, studied: 0), "nothing studied yet: a mock would only show that")
        XCTAssertFalse(due(5, studied: 2), "too little of it")
        XCTAssertTrue(due(5, studied: 3), "a quarter of it")
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
                       "This exam is multiple choice. A mock needs 8 of those, and you have 2. Add a page or paste your notes, and Cap writes more.")
        XCTAssertEqual(MockCopy.tooFew(have: 3, format: ExamFormat(multipleChoice: false, shortAnswer: true)),
                       "This exam is short answer. A mock needs 8 of those, and you have 3. Add a page or paste your notes, and Cap writes more.")
        XCTAssertEqual(MockCopy.tooFew(have: 0, format: ExamFormat(multipleChoice: false, shortAnswer: false, essay: true)),
                       "This exam is essay questions. A mock needs 2 of those, and you have 0. Add a page or paste your notes, and Cap writes more.")
        XCTAssertEqual(MockCopy.tooFew(have: 5, format: ExamFormat(multipleChoice: true, shortAnswer: true)),
                       "This exam is multiple choice and short answer. A mock needs 8 of those, and you have 5. Add a page or paste your notes, and Cap writes more.")
        XCTAssertEqual(MockCopy.tooFew(have: 1, format: ExamFormat(multipleChoice: false, shortAnswer: false)),
                       "A mock needs 8 multiple-choice or written questions, and you have 1. Add a page or paste your notes, and Cap writes more.")
        XCTAssertEqual(MockCopy.scored(0.72), "You scored 72%.")
        XCTAssertEqual(MockCopy.expected(0.68), "Cap expected 68%.")
        XCTAssertEqual(MockCopy.startLine, "From this exam's topics. Marked at the end.")
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

    func testPluralsReadInTheSingular() {
        XCTAssertEqual(MockCopy.markYourself(1), "Mark 1 answer yourself")
        XCTAssertEqual(MockCopy.markYourself(3), "Mark 3 answers yourself")
        XCTAssertEqual(MockCopy.blanksLine(1), "1 left blank. It stays out of your score.")
        XCTAssertNil(MockCopy.blanksLine(0))
    }
}
