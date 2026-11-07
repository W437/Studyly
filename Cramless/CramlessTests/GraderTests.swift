import XCTest
@testable import Cramless

/// The offline grader on the sample's curated items: key ideas hit and missed, exact marks, negation, typos,
/// confidence, and the exact checks for fill-ins, choices and labels.
@MainActor
final class GraderTests: XCTestCase {

    private func grade(_ id: String, _ answer: String) -> GradeOutcome {
        LocalGrader.grade(GradeSubject(item: AITestSupport.fixtureItem(id)), answer: .text(answer))
    }

    private func assertMarksAreVerbatim(_ outcome: GradeOutcome, _ answer: String, file: StaticString = #filePath, line: UInt = #line) {
        let count = answer.count
        for mark in outcome.marks {
            XCTAssertTrue(mark.range.lowerBound >= 0 && mark.range.upperBound <= count && !mark.range.isEmpty,
                          "mark \(mark.range) outside the answer", file: file, line: line)
        }
    }

    // MARK: The brief's table

    func testSampleAnswerHitsGrowthAndIdenticalMissesChromosomeNumber() {
        let answer = "So the body can grow and repair tissue, making two identical cells."
        let g = grade("i1", answer)
        XCTAssertEqual(g.verdict, .partial)
        XCTAssertEqual(g.hitIdeaIDs, ["k1", "k2"])
        XCTAssertEqual(g.missing.map(\.label), ["Same number of chromosomes"])
        XCTAssertEqual(AITestSupport.marked(g, in: answer), ["grow and repair", "identical"])
        XCTAssertEqual(g.score, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(g.confidence, 0.8)
        XCTAssertEqual(g.gradedBy, .rules)
        XCTAssertFalse(g.fix.isEmpty)
        assertMarksAreVerbatim(g, answer)
    }

    func testTable() {
        struct Row { var id: String; var answer: String; var hits: [String]; var verdict: GradeResponse.Verdict }
        let rows: [Row] = [
            Row(id: "i1", answer: "To grow and heal, making genetically identical cells with the same number of chromosomes.", hits: ["k1", "k2", "k3"], verdict: .correct),
            Row(id: "i1", answer: "growth and repairs, and the cells are identicle with the same chromosome number", hits: ["k1", "k2", "k3"], verdict: .correct),
            Row(id: "i1", answer: "Cells divide so they can make sex cells.", hits: [], verdict: .incorrect),
            Row(id: "i1", answer: "It doesn't help the body grow. The cells are not identical.", hits: [], verdict: .incorrect),
            Row(id: "i1", answer: "Not only growth but also repair.", hits: ["k1"], verdict: .partial),
            Row(id: "i3", answer: "The nuclear envelope broke down and the chromosomes became visible.", hits: ["k1", "k2"], verdict: .correct),
            Row(id: "i3", answer: "It dissolves while the chromosomes condense.", hits: ["k1", "k2"], verdict: .correct),
            Row(id: "i3", answer: "It forms around the chromosomes.", hits: [], verdict: .incorrect),
            Row(id: "i4", answer: "The sister chromatids get pulled apart to opposite poles and each one becomes its own chromosome.", hits: ["k1", "k2", "k3"], verdict: .correct),
            Row(id: "i4", answer: "The chromatids are not pulled apart.", hits: [], verdict: .incorrect),
            Row(id: "i5", answer: "Mitosis splits the nucleus and DNA, cytokinesis divides the cytoplasm so you get two separate cells.", hits: ["k1", "k2", "k3"], verdict: .correct),
            Row(id: "i6", answer: "Anaphase, because without spindle fibres the chromatids can't be pulled apart.", hits: ["k1", "k2"], verdict: .correct),
            Row(id: "i6", answer: "Metaphase can't happen.", hits: [], verdict: .incorrect),
        ]
        for row in rows {
            let g = grade(row.id, row.answer)
            XCTAssertEqual(g.hitIdeaIDs, row.hits, "\(row.id): \(row.answer)")
            XCTAssertEqual(g.verdict, row.verdict, "\(row.id): \(row.answer)")
            assertMarksAreVerbatim(g, row.answer)
            XCTAssertEqual(Set(g.marks.map(\.ideaID)), Set(row.hits), "every hit is marked: \(row.answer)")
        }
    }

    func testNegationGuard() {
        // Before the words, and inside them.
        XCTAssertTrue(grade("i1", "Mitosis does not make identical cells.").hitIdeaIDs.isEmpty)
        XCTAssertTrue(grade("i4", "They aren't pulled apart at all.").hitIdeaIDs.isEmpty)
        // A clause break ends the negation's reach.
        XCTAssertEqual(grade("i1", "No, it's so the body can grow.").hitIdeaIDs, ["k1"])
        let negated = grade("i1", "Cells don't divide to grow or repair, they just make two cells.")
        XCTAssertEqual(negated.verdict, .incorrect)
        XCTAssertTrue(negated.feedback.contains("opposite"))
    }

    func testNegativeTermNeedsTheNegationAndMarksIt() {
        let answer = "Anaphase, because without spindle fibres the chromatids can't be pulled apart."
        let g = grade("i6", answer)
        XCTAssertTrue(AITestSupport.marked(g, in: answer).contains("can't be pulled"))
    }

    func testTyposLowerConfidence() {
        let exact = grade("i1", "To grow and heal, making identical cells with the same number of chromosomes.")
        let typo = grade("i1", "To grow and heal, making identicle cells with the same number of chromosones.")
        XCTAssertEqual(typo.hitIdeaIDs, ["k1", "k2", "k3"])
        XCTAssertLessThan(typo.confidence, exact.confidence)
        // Short words get no typo allowance ("polls" is not "poles").
        XCTAssertFalse(grade("i4", "They go to opposite polls.").hitIdeaIDs.contains("k2"))
    }

    func testHonestUncertainty() {
        // Right in other words the rules don't know: no hits, low confidence, so the UI offers "Grade again".
        let paraphrase = grade("i1", "So that organisms can get bigger and fix wounds, and both cells have matching genes.")
        XCTAssertEqual(paraphrase.verdict, .incorrect)
        XCTAssertTrue(paraphrase.needsSecondLook)
        // A long answer is less certain than a short one with the same hits.
        let short = grade("i3", "The envelope breaks down and the chromosomes condense.")
        let long = grade("i3", String(repeating: "In this phase lots of things happen inside the cell and the student writes a great deal more. ", count: 6)
                         + "The envelope breaks down and the chromosomes condense.")
        XCTAssertEqual(long.hitIdeaIDs, short.hitIdeaIDs)
        XCTAssertLessThan(long.confidence, short.confidence)
        // Hedging costs a little.
        XCTAssertLessThan(grade("i3", "Maybe the envelope breaks down and the chromosomes condense?").confidence, short.confidence)
    }

    func testEmptyAnswer() {
        let g = grade("i1", "   ")
        XCTAssertEqual(g.verdict, .incorrect)
        XCTAssertTrue(g.marks.isEmpty)
        XCTAssertEqual(g.feedback, "No answer yet.")
    }

    func testATermThatOnlyRepeatsTheQuestionDoesNotCount() {
        let subject = GradeSubject(kind: .recall, prompt: "Why is mitosis important?", modelAnswer: "It lets organisms grow.",
                                   keyIdeas: [KeyIdea(id: "k1", label: "Mitosis", terms: ["mitosis"]),
                                              KeyIdea(id: "k2", label: "Growth", terms: ["grow", "growth"])])
        let g = LocalGrader.grade(subject, answer: .text("Mitosis is important for growth."))
        XCTAssertEqual(g.hitIdeaIDs, ["k2"])
    }

    func testWithoutKeyIdeasComparesWithTheModelAnswer() {
        let subject = GradeSubject(kind: .recall, prompt: "What is diffusion?",
                                   modelAnswer: "Particles moving from high to low concentration.")
        let good = LocalGrader.grade(subject, answer: .text("particles move from a high concentration to a low one"))
        XCTAssertEqual(good.verdict, .correct)
        XCTAssertEqual(good.confidence, 0.5)
        XCTAssertEqual(LocalGrader.grade(subject, answer: .text("Water moves into cells.")).verdict, .incorrect)
    }

    // MARK: Exact answers

    func testClozeExactAlternatesAndTypos() {
        let i11 = GradeSubject(item: AITestSupport.fixtureItem("i11"))
        XCTAssertEqual(LocalGrader.grade(i11, answer: .blanks(["telophase"])).verdict, .correct)
        XCTAssertEqual(LocalGrader.grade(i11, answer: .blanks(["Telophase."])).verdict, .correct)
        let typo = LocalGrader.grade(i11, answer: .blanks(["telophse"]))
        XCTAssertEqual(typo.verdict, .correct)
        XCTAssertEqual(typo.spellingNote, "Check the spelling: telophase")
        XCTAssertEqual(LocalGrader.grade(i11, answer: .blanks(["anaphase"])).verdict, .incorrect)
        XCTAssertEqual(LocalGrader.grade(i11, answer: .blanks([""])).blankResults, [false])

        let i12 = GradeSubject(item: AITestSupport.fixtureItem("i12"))
        XCTAssertEqual(LocalGrader.grade(i12, answer: .blanks(["the same"])).verdict, .correct)
        XCTAssertEqual(LocalGrader.grade(i12, answer: .blanks(["similar"])).verdict, .incorrect)

        let two = GradeSubject(kind: .cloze, prompt: "Fill in.", modelAnswer: "",
                               cloze: ClozeSpec(text: "{{Prophase}} comes before {{metaphase}}."))
        let half = LocalGrader.grade(two, answer: .blanks(["prophase", "anaphase"]))
        XCTAssertEqual(half.verdict, .partial)
        XCTAssertEqual(half.blankResults, [true, false])
    }

    func testChoicesAndLabels() {
        let i7 = GradeSubject(item: AITestSupport.fixtureItem("i7"))
        let right = LocalGrader.grade(i7, answer: .choice(1))
        XCTAssertEqual(right.verdict, .correct)
        XCTAssertEqual(right.feedback, "Chromosomes line up at the equator in metaphase.")
        let wrong = LocalGrader.grade(i7, answer: .choice(0))
        XCTAssertEqual(wrong.verdict, .incorrect)
        XCTAssertEqual(wrong.fix, "The answer: Metaphase.")
        XCTAssertEqual(LocalGrader.grade(i7, answer: .text("metaphase")).verdict, .correct)
        XCTAssertEqual(LocalGrader.grade(GradeSubject(item: AITestSupport.fixtureItem("i9")), answer: .text("centromeres")).verdict, .correct)

        let i14 = GradeSubject(item: AITestSupport.fixtureItem("i14"))
        let labels = LocalGrader.grade(i14, answer: .labels(["Prophase", "Metaphase", "Anaphse", "Prophase"]))
        XCTAssertEqual(labels.blankResults, [true, true, true, false])
        XCTAssertEqual(labels.verdict, .partial)
        XCTAssertEqual(labels.spellingNote, "Check the spelling: Anaphase")
    }

    // MARK: The text layer

    func testStemmingKeepsWordFamiliesTogether() {
        let families = [["divides", "divided", "dividing", "divide"], ["chromosomes", "chromosome"], ["broke", "breaks", "broken", "break"],
                        ["strings", "string"], ["bleeding", "bleed"], ["fibres", "fibers", "fibre"], ["copies", "copied", "copy"],
                        ["nuclei", "nucleus"], ["splitting", "split"], ["grew", "grown", "grows", "grow"]]
        for family in families {
            XCTAssertEqual(Set(family.map(Lexicon.stem)).count, 1, "\(family) → \(family.map(Lexicon.stem))")
        }
        XCTAssertNotEqual(Lexicon.stem("mitosis"), Lexicon.stem("meiosis"))
    }

    func testTokensCarryCharacterRanges() {
        let text = "Café: the cells’ DNA isn't split."
        let tokens = Lexicon.tokens(text)
        let chars = Array(text)
        XCTAssertEqual(tokens.map { String(chars[$0.range]) }, ["Café", "the", "cells", "DNA", "isn't", "split"])
        XCTAssertTrue(tokens[4].isNegation)
        XCTAssertTrue(tokens[0].endsClause)
    }

    // MARK: The stored answer itself

    /// Stored answers like the ones real decks hold, key ideas included: typed back, in any case and with the outer punctuation gone or kept, they are right.
    func testAStoredAnswerTypedBackIsRightInEveryLanguage() {
        let rows: [(answer: String, ideas: [KeyIdea])] = [
            ("12 bytes of options.", [KeyIdea(id: "a", label: "Option length", terms: ["option length", "options field"]), KeyIdea(id: "b", label: "Twelve", terms: ["twelve"])]),
            ("It was the end of the war.", [KeyIdea(id: "a", label: "Peace", terms: ["peace"])]),
            ("La inflación sube porque hay más dinero.", [KeyIdea(id: "a", label: "Oferta monetaria", terms: ["oferta monetaria"])]),
            ("Die Verdunstung nimmt im Sommer zu.", [KeyIdea(id: "a", label: "Temperatur", terms: ["temperatur"])]),
            ("明治維新は1868年に始まった。", [KeyIdea(id: "a", label: "王政復古", terms: ["王政復古"])]),
            ("Elle a dit non.", [KeyIdea(id: "a", label: "Refus", terms: ["refus"])]),
            ("It isn't a bond, not at all.", [KeyIdea(id: "a", label: "Bond", terms: ["bond"])]),
            ("≈ 5 %", [KeyIdea(id: "a", label: "About five", terms: ["about five"])]),
        ]
        for row in rows {
            let subject = GradeSubject(kind: .recall, prompt: "What?", modelAnswer: row.answer, keyIdeas: row.ideas)
            for typed in [row.answer, row.answer.uppercased(), row.answer.lowercased(), "  \(row.answer) ", row.answer.trimmingCharacters(in: .punctuationCharacters),
                          row.answer.folding(options: .diacriticInsensitive, locale: nil), row.answer.folding(options: .widthInsensitive, locale: nil)] {
                let result = LocalGrader.grade(subject, answer: .text(typed))
                XCTAssertEqual(result.verdict, .correct, "\(row.answer) typed as \(typed)")
                XCTAssertEqual(result.score, 1)
                XCTAssertEqual(Grading.rating(forScore: result.score), .good)
                XCTAssertTrue(result.missing.isEmpty)
            }
            XCTAssertNil(AIRouter.refinableText(subject, .text(row.answer)), "no model is asked to second-guess it")
        }
    }

    func testOnlyTheWholeStoredAnswerIsRightByThatRule() {
        let ideas = [KeyIdea(id: "a", label: "Bytes", terms: ["bytes"]), KeyIdea(id: "b", label: "Options", terms: ["option length"])]
        let subject = GradeSubject(kind: .recall, prompt: "How long?", modelAnswer: "12 bytes of options.", keyIdeas: ideas)
        XCTAssertEqual(LocalGrader.grade(subject, answer: .text("12 bytes")).verdict, .partial, "part of it is still part of it")
        XCTAssertNotNil(AIRouter.refinableText(subject, .text("12 bytes")))
        XCTAssertFalse(Lexicon.isSameAnswer("", as: ""))
        XCTAssertFalse(Lexicon.isSameAnswer("  ", as: "12"))
        XCTAssertFalse(Lexicon.isSameAnswer("≠", as: "≈"))
        XCTAssertFalse(Lexicon.isSameAnswer("13 bytes", as: "12 bytes"))
        XCTAssertTrue(Lexicon.isSameAnswer("１２ bytes", as: "12 bytes"), "full-width digits")
    }

}
