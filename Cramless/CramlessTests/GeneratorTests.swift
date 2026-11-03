import XCTest
@testable import Cramless

/// The offline generator on the sample page's real recognised lines, the page reader underneath it, and the
/// grounding check every on-device and offline item passes.
@MainActor
final class GeneratorTests: XCTestCase {

    private var result: LocalGenerator.Result {
        LocalGenerator.generate(pages: [AITestSupport.samplePage], sourceTitle: "Biology textbook", maxItems: 16)
    }

    func testSamplePageGivesAGroundedMixedSet() throws {
        let r = result
        XCTAssertGreaterThanOrEqual(r.items.count, 8)
        XCTAssertEqual(r.quality, .basic)
        XCTAssertEqual(r.language, "en")
        let lineIDs = Set(AITestSupport.sampleLines.map(\.id))
        for item in r.items {
            XCTAssertFalse(item.anchors.isEmpty, item.prompt)
            for anchor in item.anchors { XCTAssertTrue(lineIDs.contains(anchor), "\(item.prompt) → \(anchor)") }
            XCTAssertEqual(item.anchors.count, Set(item.anchors).count, "no repeated anchors")
        }
        let kinds = Set(r.items.map(\.kind))
        XCTAssertTrue(kinds.isSuperset(of: [.recall, .mcq, .cloze, .flashcard]), "\(kinds)")
        XCTAssertEqual(Set(r.items.map(\.id)).count, r.items.count)
        XCTAssertTrue(r.topics.map(\.name).contains("Phases of mitosis"))
    }

    func testPhasesBecomeAFourOptionQuestion() throws {
        let mcqs = result.items.filter { $0.kind == .mcq }
        let phases = try XCTUnwrap(mcqs.first { $0.choices.map(\.text) == ["Prophase", "Metaphase", "Anaphase", "Telophase"] })
        XCTAssertEqual(phases.choices.filter(\.correct).count, 1)
        XCTAssertTrue(phases.prompt.hasPrefix("Which phase is this:"), phases.prompt)
        let right = try XCTUnwrap(phases.choices.first(where: \.correct))
        XCTAssertEqual(right.text, phases.answer)
        XCTAssertTrue(phases.choices.allSatisfy { $0.why != nil })
    }

    func testPhaseRecallItemsHaveAKeyIdeaPerBullet() throws {
        // Which of the four phases a 16-question set asks as a recall (the others come out as cards or choices) depends on what else competes for
        // its places, so every phase that is asked as one is checked.
        let phases = result.items.filter { $0.kind == .recall && $0.prompt.hasPrefix("What happens in ") }
        XCTAssertGreaterThanOrEqual(phases.count, 2, "\(result.items.map(\.prompt))")
        let expected: [String: (terms: [String], anchors: Set<String>)] = [
            "prophase": (["condense", "breaks down"], ["p0.l8", "p0.l12", "p0.l16", "p0.l20", "p0.l24"]),
            "metaphase": (["line up", "spindle"], ["p0.l9", "p0.l13", "p0.l17", "p0.l21", "p0.l25"]),
            "telophase": (["nuclear", "unwind"], ["p0.l11", "p0.l15", "p0.l19", "p0.l23", "p0.l27", "p0.l29", "p0.l30"]),
        ]
        for item in phases {
            XCTAssertEqual(item.keyIdeas.count, 2, item.prompt)
            // Page-wide words never stand alone as a term: "chromosomes" would let any answer through.
            for idea in item.keyIdeas { XCTAssertFalse(idea.terms.contains("chromosomes"), idea.label) }
            let phase = String(item.prompt.dropFirst("What happens in ".count).dropLast())
            guard let want = expected[phase] else { continue }
            for (n, term) in want.terms.enumerated() { XCTAssertTrue(item.keyIdeas[n].terms.contains(term), "\(phase): \(item.keyIdeas[n].terms)") }
            XCTAssertEqual(Set(item.anchors), want.anchors, phase)
        }
    }

    func testGeneratedKeyIdeasAcceptTheirOwnModelAnswers() {
        for item in result.items where item.kind.isOwnWords {
            let g = LocalGrader.grade(GradeSubject(item: item), answer: .text(item.answer))
            XCTAssertEqual(g.verdict, .correct, "\(item.prompt): \(g.missing.map(\.label))")
        }
    }

    func testDiagramUsesThePhaseLabelLines() throws {
        let diagram = try XCTUnwrap(LocalGenerator.generate(pages: [AITestSupport.samplePage], sourceTitle: "Biology textbook",
                                                           maxItems: 30).items.first { $0.kind == .diagram })
        XCTAssertEqual(diagram.diagramLabels, ["p0.l8", "p0.l9", "p0.l10", "p0.l11"])
        XCTAssertEqual(diagram.prompt, "Label the four phases of mitosis.")
    }

    func testDeterministic() {
        XCTAssertEqual(result, result)
    }

    func testFormatsAndLimit() {
        let onlyCards = LocalGenerator.generate(pages: [AITestSupport.samplePage], sourceTitle: "x", maxItems: 5, formats: [.flashcard])
        XCTAssertFalse(onlyCards.items.isEmpty)
        XCTAssertLessThanOrEqual(onlyCards.items.count, 5)
        XCTAssertTrue(onlyCards.items.allSatisfy { $0.kind == .flashcard })
    }

    // MARK: Reading the page

    func testPageStructureRebuildsTheColumns() throws {
        let s = PageStructure.read(AITestSupport.sampleLines)
        XCTAssertEqual(s.title?.text, "Mitosis: How Cells Divide")
        XCTAssertEqual(s.subject, "Mitosis")
        let group = try XCTUnwrap(s.groups.first)
        XCTAssertEqual(group.name, "Phases of mitosis")
        XCTAssertEqual(group.noun, "phase")
        XCTAssertTrue(group.isRow && group.isSequence)
        let anaphase = try XCTUnwrap(group.siblings.first { $0.name.text == "Anaphase" })
        XCTAssertEqual(anaphase.bullets.map(\.text), ["Sister chromatids are pulled to opposite poles of the cell.",
                                                     "Each chromatid becomes a separate chromosome."])
        XCTAssertEqual(anaphase.bullets[0].lineIDs, ["p0.l14", "p0.l18", "p0.l22"])
        XCTAssertEqual(s.sections.compactMap(\.heading?.text),
                       ["Mitosis: How Cells Divide", "What happens after mitosis?", "Why is mitosis important?"])
        // The running header and the page number are not content.
        XCTAssertFalse(s.sections.contains { $0.heading?.text == "Unit 3 Cell Biology" })
        XCTAssertEqual(Set(s.definitions.map(\.term)), ["Cytokinesis", "Mitosis"])
    }

    func testStackedHeadingsAndTermLinesWithoutBoxes() {
        let text = """
        Cell transport
        Diffusion: particles move from high to low concentration.
        Osmosis: water moves across a membrane from dilute to concentrated solution.
        Glycolysis
        • Splits glucose into pyruvate
        Krebs cycle
        • Releases carbon dioxide
        Electron transport
        • Makes most of the ATP
        """
        let lines = text.split(separator: "\n").enumerated().map { TextLine(id: "p0.l\($0.offset)", text: String($0.element), box: nil) }
        let s = PageStructure.read(lines)
        XCTAssertEqual(s.groups.first?.siblings.map(\.name.text), ["Glycolysis", "Krebs cycle", "Electron transport"])
        XCTAssertEqual(s.definitions.map(\.term), ["Diffusion", "Osmosis"])
        let r = LocalGenerator.generate(pages: [PageText(index: 0, label: "1", lines: lines)], sourceTitle: "Slides")
        XCTAssertTrue(r.items.contains { $0.kind == .flashcard && $0.prompt == "Diffusion" })
        XCTAssertTrue(r.items.contains { $0.kind == .mcq && $0.choices.count == 3 })
    }

    func testOtherLanguagesAreAdmittedNotFaked() {
        let text = ["La mitosis es el proceso por el cual una célula se divide en dos células hijas idénticas.",
                    "Citocinesis: la división del citoplasma que sigue a la mitosis.",
                    "Durante la mitosis el material genético se copia y se reparte por igual entre los dos núcleos nuevos."]
        let lines = text.enumerated().map { TextLine(id: "p0.l\($0.offset)", text: $0.element, box: nil) }
        let r = LocalGenerator.generate(pages: [PageText(index: 0, label: "1", lines: lines)], sourceTitle: "Apuntes")
        XCTAssertEqual(r.quality, .unsupportedLanguage)
        XCTAssertEqual(r.language, "es")
        XCTAssertTrue(r.items.allSatisfy { $0.kind == .flashcard })
    }

    // MARK: The grounding check

    private var texts: [String: String] { GroundingCheck.texts(of: [AITestSupport.samplePage]) }

    func testGroundingDropsAFakeAnchor() {
        var item = AITestSupport.fixtureItem("i3")
        XCTAssertNil(GroundingCheck.problem(with: item, texts: texts))
        item.anchors.append("p0.l99")
        let (kept, dropped) = GroundingCheck.apply([item, AITestSupport.fixtureItem("i7")], texts: texts)
        XCTAssertEqual(kept.map(\.id), ["i7"])
        XCTAssertEqual(dropped.first?.item.id, "i3")
        XCTAssertTrue(dropped.first?.reason.contains("p0.l99") ?? false)
    }

    func testGroundingDropsAnswersTheirLinesDontBack() {
        var recall = AITestSupport.fixtureItem("i3")
        recall.answer = "Photosynthesis turns sunlight into sugar in the chloroplasts."
        XCTAssertNotNil(GroundingCheck.problem(with: recall, texts: texts))

        var mcq = AITestSupport.fixtureItem("i7")
        mcq.choices = [Choice(text: "Interphase", correct: true), Choice(text: "Metaphase", correct: false)]
        mcq.answer = "Interphase"
        XCTAssertNotNil(GroundingCheck.problem(with: mcq, texts: texts))

        var cloze = AITestSupport.fixtureItem("i13")
        cloze.cloze = ClozeSpec(text: "{{Photosynthesis}} is the division of the cytoplasm.")
        XCTAssertNotNil(GroundingCheck.problem(with: cloze, texts: texts))

        var noAnchors = AITestSupport.fixtureItem("i15")
        noAnchors.anchors = []
        XCTAssertNotNil(GroundingCheck.problem(with: noAnchors, texts: texts))

        var twoRight = AITestSupport.fixtureItem("i9")
        twoRight.choices[1].correct = true
        XCTAssertNotNil(GroundingCheck.problem(with: twoRight, texts: texts))
    }

    func testCuratedItemsPassTheAnchorCheck() {
        let (kept, dropped) = GroundingCheck.apply(AITestSupport.fixture.items, texts: texts, anchorsOnly: true)
        XCTAssertEqual(kept.count, 16)
        XCTAssertTrue(dropped.isEmpty)
    }

    func testEveryGeneratedItemPassesTheFullCheck() {
        let r = result
        let (kept, dropped) = GroundingCheck.apply(r.items, texts: texts)
        XCTAssertEqual(kept.count, r.items.count, "\(dropped.map(\.reason))")
    }
}
