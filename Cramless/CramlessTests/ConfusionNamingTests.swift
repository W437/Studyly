import XCTest
@testable import Cramless

/// What the offline rules call a mix-up: a name only where they have an honest one (two swapped terms, a topic's own name), else a
/// plain description of how many misses on how many questions. Cloud AI names a mix-up in plain words, and that path is untouched.
final class ConfusionNamingTests: XCTestCase {
    let cal = EngineTest.calendar()
    lazy var now = EngineTest.date(2026, 10, 22, 9, in: cal)
    let course = UUID(), topic = UUID()

    private func info(_ answer: String, topicID: UUID? = nil) -> ItemAnswerInfo {
        ItemAnswerInfo(id: UUID(), courseID: course, topicID: topicID, prompt: "Which one?", expected: answer, accepted: [answer])
    }

    private func miss(_ item: ItemAnswerInfo, given: String?, daysAgo: Int) -> ReviewSnapshot {
        ReviewSnapshot(itemID: item.id, courseID: course, reviewedAt: cal.adding(days: -daysAgo, to: now), rating: .again, answer: given,
                       stabilityAfter: 1)
    }

    private func candidates(_ items: [ItemAnswerInfo], _ logs: [ReviewSnapshot], topics: [UUID: String] = [:]) -> [ConfusionCandidate] {
        ConfusionFinder(calendar: cal, now: now).candidates(items: items, logs: logs, topicNames: topics)
    }

    // MARK: The finder

    func testTwoSwappedTermsAreNamedAsBefore() throws {
        let a = info("Anaphase"), b = info("Telophase")
        let found = candidates([a, b], [miss(a, given: "telophase", daysAgo: 3), miss(b, given: "anaphase", daysAgo: 2)])
        let candidate = try XCTUnwrap(found.first)
        XCTAssertEqual(candidate.name, "Anaphase vs telophase")
        XCTAssertTrue(candidate.isNamed)
        XCTAssertEqual(candidate.defaultExplanation, "You've missed these 2 times in the last two weeks.")
    }

    func testTwoSwappedSentencesAreNotGivenANameMadeOfTheirText() throws {
        let a = info("The sister chromatids are pulled to opposite poles of the cell")
        let b = info("The nuclear envelope re-forms around each new set of chromosomes")
        let found = candidates([a, b], [miss(a, given: b.expected, daysAgo: 3), miss(b, given: a.expected, daysAgo: 2)])
        let candidate = try XCTUnwrap(found.first)
        XCTAssertEqual(candidate.reason, .swappedAnswers)
        XCTAssertEqual(candidate.name, ConfusionCandidate.unnamed)
        XCTAssertFalse(candidate.isNamed)
        XCTAssertEqual(candidate.defaultExplanation, "2 misses on these 2 questions")
        for text in [candidate.name, candidate.defaultExplanation] {
            XCTAssertFalse(text.contains("chromatids") || text.contains("envelope") || text.contains("…"), text)
        }
    }

    func testRepeatedMissesWithoutATopicAreDescribedNotNamedFromAnAnswer() throws {
        let a = info("Homologous pairs line up at the equator in metaphase one")
        let logs = (1...3).map { miss(a, given: nil, daysAgo: $0) }
        let candidate = try XCTUnwrap(candidates([a], logs).first)
        XCTAssertEqual(candidate.reason, .repeatedMisses)
        XCTAssertEqual(candidate.name, "Questions you keep missing", "not \"Homologous pairs line up at…\"")
        XCTAssertEqual(candidate.defaultExplanation, "3 misses on this question")

        // The topic's own name is the person's, and stays.
        let t = info("Homologous pairs", topicID: topic), u = info("Sister chromatids", topicID: topic)
        let topicLogs = (1...3).map { miss(t, given: nil, daysAgo: $0) } + (1...4).map { miss(u, given: nil, daysAgo: $0) }
        let named = try XCTUnwrap(candidates([t, u], topicLogs, topics: [topic: "Meiosis"]).first)
        XCTAssertEqual(named.name, "Meiosis")
        XCTAssertTrue(named.isNamed)
        XCTAssertEqual(named.defaultExplanation, "You've missed these 7 times in the last two weeks.")
    }

    func testWhatAShortAnswerIsAndHowMissesAreCounted() {
        for term in ["Anaphase", "sister chromatids", "DNA polymerase.", "  The Krebs cycle "] { XCTAssertTrue(ConfusionFinder.isTerm(term), term) }
        for sentence in ["The sister chromatids are…", "The sister chromatids are pulled apart", "", "   ", "A very long answer indeed"] {
            XCTAssertFalse(ConfusionFinder.isTerm(sentence), sentence)
        }
        XCTAssertEqual(ConfusionFinder.shortName("The sister chromatids are pulled apart"), "The sister chromatids are…")
        XCTAssertEqual(ConfusionFinder.description(misses: 3, questions: 2), "3 misses on these 2 questions")
        XCTAssertEqual(ConfusionFinder.description(misses: 1, questions: 1), "1 miss on this question")
        XCTAssertEqual(ConfusionFinder.description(misses: 2, questions: 1), "2 misses on this question")
        XCTAssertEqual(ConfusionFinder.description(misses: 1, questions: 3), "1 miss on these 3 questions")
    }

    // MARK: The offline explanation

    func testTheOfflineRulesNameTwoTermsAndDescribeTwoSentences() throws {
        func mistake(_ id: String, _ prompt: String, expected: String, given: String, misses: Int) -> MistakeInput {
            MistakeInput(itemId: id, topic: "", prompt: prompt, expected: expected, given: given, misses: misses)
        }
        let terms = LocalConfusions.find([
            mistake("a", "Which phase pulls the chromatids apart?", expected: "Anaphase", given: "Telophase", misses: 2),
            mistake("b", "Which phase re-forms the envelopes?", expected: "Telophase", given: "Anaphase", misses: 1),
        ])
        let named = try XCTUnwrap(terms.first)
        XCTAssertEqual(named.name, "Telophase vs anaphase")
        XCTAssertEqual(named.explanation, "You've answered telophase where it was anaphase, and the other way round.")

        let first = "The sister chromatids are pulled to opposite poles of the cell"
        let second = "The nuclear envelope re-forms around each new set of chromosomes"
        let sentences = LocalConfusions.find([
            mistake("a", "What happens in anaphase?", expected: first, given: second, misses: 2),
            mistake("b", "What happens in telophase?", expected: second, given: first, misses: 1),
        ])
        let plain = try XCTUnwrap(sentences.first)
        XCTAssertEqual(plain.name, ConfusionCandidate.unnamed)
        XCTAssertEqual(plain.explanation, "3 misses on these 2 questions", "no sentence of the answers is quoted back as a name")
        XCTAssertFalse(plain.lesson.isEmpty, "the lesson still teaches the two answers")
        XCTAssertEqual(plain.questions.count, 2)
        XCTAssertEqual(Set(plain.itemIds), ["a", "b"])
    }

    // MARK: The words

    func testCapsLineDoesNotPretendTheMixUpHasAName() {
        XCTAssertEqual(SessionCopy.mixUpLine(ConfusionCandidate.unnamed), "These questions keep tripping you up.")
        XCTAssertEqual(SessionCopy.mixUpPair(ConfusionCandidate.unnamed), "them")
        // A mix-up with a name reads as it always did, Cloud AI's or the rules'.
        XCTAssertEqual(SessionCopy.mixUpLine("Anaphase vs telophase"), "You keep mixing up anaphase and telophase.")
        XCTAssertEqual(SessionCopy.mixUpLine("Mendelian genetics"), "Mendelian genetics keeps tripping you up.")
        XCTAssertEqual(SessionCopy.mixUpPair("Anaphase vs telophase"), "anaphase and telophase")
    }
}
