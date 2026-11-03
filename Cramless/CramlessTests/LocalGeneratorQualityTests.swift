import XCTest
@testable import Cramless

/// What the offline question writer chooses to ask about: pasted pages with Markdown and citations, names the line splitter cut in two,
/// definitions that define nothing, blanks that give nothing away, and a set that is short rather than padded.
@MainActor
final class LocalGeneratorQualityTests: XCTestCase {

    private func pasted(_ text: String) -> [PageText] {
        TextPaginator.pages(from: text).map { PageText(index: $0.pageIndex, label: $0.label, lines: $0.lines) }
    }

    private let statins = """
    ## Statins

    ## What is cholesterol?

    Cholesterol is a waxy, fat-like substance that's found in all the cells in your body. Your body needs some cholesterol to work properly. But if you have too much of it in your blood, it can stick to the walls of your arteries and narrow or even block them.

    ## What are statins?

    Statins are a type of cholesterol medicine. Your health care provider may prescribe them if you have high cholesterol and making lifestyle changes does not lower your cholesterol enough.

    ## How do statins lower cholesterol?

    Statins lower LDL cholesterol by slowing down how much cholesterol the liver makes. They also increase your liver's ability to remove LDL cholesterol that is already in the blood.

    NIH: National Heart, Lung, and Blood Institute

    ## References

    1. Smith, J. (2020). Statins and the liver. Journal of Medicine 3 (2): 146-155. doi:10.1000/xyz
    2. Jones, A.; Brown, K. (2019). Cholesterol. Oxford University Press, New York. ISBN 0-123-45678-9.
    """

    func testMarkdownHeadingsAreHeadingsAndQuestionHeadingsBecomeQuestions() throws {
        let lines = try XCTUnwrap(SourceHygiene.prepare(pasted(statins)).first?.lines)
        let s = PageStructure.read(lines)
        XCTAssertEqual(s.sections.compactMap(\.heading?.text), ["What is cholesterol?", "What are statins?", "How do statins lower cholesterol?"])
        XCTAssertTrue(s.sections.allSatisfy { $0.heading?.text.contains("#") == false })
        let r = LocalGenerator.generate(pages: pasted(statins), sourceTitle: "Notes", maxItems: 20)
        let recall = r.items.filter { $0.kind == .recall }.map(\.prompt)
        XCTAssertEqual(recall, ["What is cholesterol?", "What are statins?", "How do statins lower cholesterol?"])
        XCTAssertTrue(r.items.contains { ($0.kind == .cloze && $0.answer == "Cholesterol") || ($0.kind == .flashcard && $0.prompt == "Cholesterol") },
                      "the definition is asked once, as a fill-in or a card")
        for item in r.items {
            let shown = [item.prompt, item.answer, item.cloze?.text ?? ""].joined(separator: " ")
            for junk in ["#", "NIH", "Smith", "Jones", "doi", "ISBN", "Oxford"] { XCTAssertFalse(shown.contains(junk), "\(junk) in \(shown)") }
        }
    }

    func testAnAbbreviationTheLineSplitterCutAtIsOneSentenceAgain() throws {
        // "Brown v." / "Board of Education of Topeka" and "… Edsger W." / "Dijkstra in 1956 …" are one name and one sentence.
        let lines = ["Brown v.", "Board of Education of Topeka", "Segregation of children in public schools solely on the basis of race denies them the equal protection of the laws.",
                     "The algorithm was conceived by the computer scientist Edsger W.", "Dijkstra in 1956 and published three years later."]
            .enumerated().map { TextLine(id: "p0.l\($0.offset)", text: $0.element, box: nil) }
        let s = PageStructure.read(lines)
        XCTAssertFalse(s.sections.contains { $0.heading?.text == "Board of Education of Topeka" })
        let sentences = s.sections.flatMap(\.sentences)
        let dijkstra = try XCTUnwrap(sentences.first { $0.text.hasPrefix("The algorithm was conceived") })
        XCTAssertEqual(dijkstra.text, "The algorithm was conceived by the computer scientist Edsger W. Dijkstra in 1956 and published three years later.")
        XCTAssertEqual(dijkstra.lineIDs, ["p0.l3", "p0.l4"], "both lines are its anchors")
        // A sentence that really ends on an initial-like word is not glued to the next one.
        let plain = ["Vitamin C is found in citrus fruit.", "The next vitamin to know about is vitamin B."].enumerated().map { TextLine(id: "p0.l\($0.offset)", text: $0.element, box: nil) }
        XCTAssertEqual(PageStructure.read(plain).sections.flatMap(\.sentences).count, 2)
    }

    // MARK: What is worth asking

    func testNothingIsAskedAboutADefinitionThatDoesNotDefine() {
        let text = """
        Entropy is a thermodynamic state variable that measures the number of accessible microstates of a system.
        Since it is a reversible cycle, the entropy of the engine and its surroundings does not change over one full turn.
        If the only concern is the path to a target node, the algorithm terminates once the current node is the target node.
        OSPF and IS-IS are the most common.
        The presence of such cycles means that no shortest path can be found, since the label becomes lower each time.
        Red lines are the shortest path covering, i.e., connecting u and prev[u].
        Key feature: the stopping condition is checked before every relaxation of an edge in the graph.
        """
        let items = LocalGenerator.generate(pages: pasted(text), sourceTitle: "Notes", maxItems: 30).items
        let cards = items.filter { $0.kind == .flashcard }.map(\.prompt)
        XCTAssertTrue(items.contains { ($0.kind == .cloze && $0.answer == "Entropy") || ($0.kind == .flashcard && $0.prompt == "Entropy") }, "the real definition is asked")
        for junk in ["Since it", "If the only concern", "OSPF and IS-IS", "The presence of such cycles", "Red lines", "Key feature"] {
            XCTAssertFalse(cards.contains(junk), junk)
            XCTAssertFalse(items.contains { $0.kind == .cloze && $0.answer == junk }, junk)
        }
    }

    func testATermLineIsAskedAsACardAndASentenceThatDefinesAsAFillIn() {
        let lines = ["Cell transport", "Diffusion: particles move from high to low concentration.",
                     "Osmosis: water moves across a membrane from a dilute to a concentrated solution.",
                     "Mitosis is the process by which a single eukaryotic cell divides to produce two identical daughter cells."]
            .enumerated().map { TextLine(id: "p0.l\($0.offset)", text: $0.element, box: nil) }
        let items = LocalGenerator.generate(pages: [PageText(index: 0, label: "1", lines: lines)], sourceTitle: "Slides", maxItems: 20).items
        XCTAssertTrue(items.contains { $0.kind == .flashcard && $0.prompt == "Diffusion" })
        XCTAssertTrue(items.contains { $0.kind == .flashcard && $0.prompt == "Osmosis" })
        XCTAssertFalse(items.contains { $0.kind == .cloze && $0.answer == "Diffusion" }, "the fill-in would only repeat the card")
        XCTAssertTrue(items.contains { $0.kind == .cloze && $0.answer == "Mitosis" }, "a sentence keeps its context in the fill-in")
        XCTAssertFalse(items.contains { $0.kind == .flashcard && $0.prompt == "Mitosis" }, "…and is asked once")
    }

    func testAFillInBlanksAnIdeaNotTheWordTheWholeTextIsAbout() {
        // "segregation" is in nine of these ten sentences; "inferiority" and "doctrine" are in one or two.
        let sentences = [
            "Segregation of children in public schools deprives them of the equal protection of the laws.",
            "To separate them from others solely because of their race generates a feeling of inferiority as to their status in the community.",
            "The impact of segregation is greater when it has the sanction of the law, because it is usually interpreted as denoting inferiority.",
            "Segregation in public education has a detrimental effect upon children who attend the separate schools.",
            "The doctrine of separate but equal was adopted in the case of Plessy, and it has no place in public education.",
            "Segregation with the sanction of law has a tendency to retard the educational and mental development of the children.",
            "The history of the Fourteenth Amendment is inconclusive as to its intended effect on segregation in public education.",
            "Segregation in the schools of the District is also held to violate the due process of law, for the same reasons.",
            "Because segregation is a denial of equal protection, the plaintiffs are entitled to admission to the schools.",
            "Segregation of white and Negro children has a harmful effect upon the motivation of a child to learn.",
        ]
        let blanks = LocalGenerator.generate(pages: pasted(sentences.joined(separator: " ")), sourceTitle: "Brown", maxItems: 20).items
            .filter { $0.kind == .cloze }.map { $0.answer.lowercased() }
        XCTAssertFalse(blanks.contains("segregation"), "\(blanks)")
        XCTAssertEqual(blanks.count, Set(blanks).count, "no word is blanked twice: \(blanks)")
    }

    func testSelectionTakesStrongQuestionsFirstAndAddsTheRestOnlyUpToTheMinimum() {
        func cloze(_ word: String, score: Double, strong: Bool, order: Int) -> LocalGenerator.Candidate {
            .init(item: GeneratedItem(id: "", kind: .cloze, topic: "T", prompt: "Fill in the word.", answer: word,
                                      cloze: ClozeSpec(text: "The {{\(word)}} of a thing is not the same as its other properties \(order)."), anchors: ["a\(order)"]),
                  score: score, order: order, strong: strong)
        }
        func recall(_ topic: String, _ answer: String, order: Int) -> LocalGenerator.Candidate {
            .init(item: GeneratedItem(id: "", kind: .recall, topic: topic, prompt: "Describe \(topic) in your own words.", answer: answer, anchors: ["r\(order)"]),
                  score: 2.5, order: order)
        }
        let strong = [recall("mitosis", "The nucleus divides into two identical nuclei during the stages of mitosis.", order: 0),
                      recall("meiosis", "Sex cells form when a diploid cell halves its chromosome number in two rounds.", order: 1),
                      recall("osmosis", "Water crosses a membrane towards the side where dissolved particles are more concentrated.", order: 2)]
        let weak = (0..<6).map { cloze("weak\($0)xyz", score: 1.5, strong: false, order: 10 + $0) }
        let all = strong + weak
        XCTAssertEqual(LocalGenerator.select(all, limit: 20).count, 3, "weak ones are not used when nobody needs them")
        XCTAssertEqual(LocalGenerator.select(all, limit: 20, minimum: 5).count, 5, "…but fill a short set up to the minimum")
        XCTAssertEqual(LocalGenerator.select(all, limit: 4, minimum: 8).count, 4, "the limit still wins")
        XCTAssertEqual(LocalGenerator.minimumQuestions(words: 3000), 7)
        XCTAssertEqual(LocalGenerator.minimumQuestions(words: 300), 3)
    }

    func testSelectionBlanksAWordOnceAndSpreadsOverTheSections() {
        func cloze(_ word: String, topic: String, score: Double, order: Int) -> LocalGenerator.Candidate {
            .init(item: GeneratedItem(id: "", kind: .cloze, topic: topic, prompt: "Fill in the word.", answer: word,
                                      cloze: ClozeSpec(text: "In section \(topic) the {{\(word)}} matters a great deal for the result number \(order)."), anchors: ["a\(order)"]),
                  score: score, order: order)
        }
        // Three sentences blank "inferiority"; section A has many good sentences, section B two a little worse.
        var all = [cloze("inferiority", topic: "A", score: 2.4, order: 1), cloze("inferiority", topic: "A", score: 2.3, order: 2), cloze("inferiority", topic: "B", score: 2.2, order: 3)]
        all += ["alpha", "bravo", "charlie", "delta", "echo"].enumerated().map { cloze($0.element + "xyz", topic: "A", score: 2.1 - Double($0.offset) * 0.01, order: 10 + $0.offset) }
        all += [cloze("foxtrot", topic: "B", score: 1.9, order: 20), cloze("golfxx", topic: "B", score: 1.8, order: 21)]
        let chosen = LocalGenerator.select(all, limit: 4)
        XCTAssertEqual(chosen.filter { $0.item.answer == "inferiority" }.count, 1)
        XCTAssertGreaterThanOrEqual(chosen.filter { $0.item.topic == "B" }.count, 2, "the second section gets its share: \(chosen.map { $0.item.answer })")
    }

    func testNoFillInShowsAWordFromTheRootOfItsBlank() {
        let sentences = [
            "Is the result too remote from the cause, and here we consider remoteness in time and space as the measure of the injury.",
            "Under that doctrine, equality of treatment is accorded when the races are provided substantially equal facilities, even though separate.",
            "The impact of segregation is greater when it has the sanction of the law, because it is usually interpreted as denoting inferiority of the group.",
            "To separate children from others solely because of their race generates a feeling of inferiority as to their status in the community.",
            "The court must ask itself whether there was a natural and continuous sequence between cause and effect in the chain of events.",
            "Where a railroad is required to fence its tracks against cattle, no man's rights are injured should he wander upon the road.",
        ]
        let items = LocalGenerator.generate(pages: pasted(sentences.joined(separator: " ") + "\n\n" + statins), sourceTitle: "Mixed", maxItems: 30).items
        for item in items where item.kind == .cloze {
            let visible = QuestionQuality.visibleText(of: item)
            let words = Lexicon.tokens(visible).filter(\.isContent).map(\.word)
            XCTAssertFalse(words.contains { TextArtifacts.sharesRoot($0, item.answer) }, "\(item.answer) in \(visible)")
        }
        XCTAssertFalse(items.contains { $0.kind == .cloze && $0.answer.lowercased() == "remoteness" })
    }

    func testASetIsNotMostlyFillIns() {
        func recall(_ topic: String, _ answer: String, order: Int) -> LocalGenerator.Candidate {
            .init(item: GeneratedItem(id: "", kind: .recall, topic: topic, prompt: "Describe \(topic) in your own words.", answer: answer, anchors: ["r\(order)"]), score: 2.5, order: order)
        }
        let sentences = ["Glycolysis splits glucose into pyruvate inside the cytoplasm of the cell.", "Ribosomes assemble proteins from amino acids carried by transfer molecules.",
                         "Chloroplasts capture sunlight and convert carbon dioxide into sugar.", "Lysosomes digest worn organelles using powerful enzymes.",
                         "Neurons transmit electrical signals along long fibres called axons.", "Hormones travel through the bloodstream to reach distant target tissues.",
                         "Antibodies recognise foreign molecules and mark pathogens for destruction.", "Enzymes lower the activation energy needed for chemical reactions.",
                         "Membranes control which substances enter and leave the cell.", "Mitochondria release usable energy by oxidising nutrient molecules."]
        let blanks = ["pyruvate", "proteins", "sunlight", "enzymes", "axons", "bloodstream", "pathogens", "activation", "membranes", "oxidising"]
        let clozes: [LocalGenerator.Candidate] = sentences.indices.map { n in
            let text = sentences[n].replacingOccurrences(of: blanks[n], with: "{{\(blanks[n])}}")
            return .init(item: GeneratedItem(id: "", kind: .cloze, topic: "T\(n % 3)", prompt: "Fill in the word.", answer: blanks[n], cloze: ClozeSpec(text: text), anchors: ["c\(n)"]),
                         score: 2 - Double(n) * 0.01, order: 100 + n)
        }
        let all = [recall("mitosis", "The nucleus divides into two identical nuclei during the stages of mitosis.", order: 1),
                   recall("evolution", "Populations change over generations through natural selection acting on heritable variation.", order: 2)] + clozes
        let chosen = LocalGenerator.select(all, limit: 20)
        XCTAssertEqual(chosen.filter { $0.item.kind == .recall }.count, 2)
        XCTAssertEqual(chosen.filter { $0.item.kind == .cloze }.count, 4, "two other questions allow four fill-ins, not ten: the weakest go")
        // The minimum a long text deserves keeps more of them, half of it at most.
        XCTAssertEqual(LocalGenerator.select(all, limit: 20, minimum: 12).filter { $0.item.kind == .cloze }.count, 6)
    }

    func testAPartOfTheDocumentIsNotDescribedAndALoneWordHeadingNamesItsSubject() {
        let text = """
        ## Le Chatelier's principle

        Le Chatelier's principle is a principle used to predict the effect of a change in conditions on chemical equilibrium. It was named after Henry Louis Le Chatelier.

        ## Dissenting opinion (Andrews, J.)

        Assisting a passenger to board a train, the defendant's servant negligently knocked a package from his arms. It fell between the platform and the cars. It contained fireworks which exploded.

        ## Economics

        In economics, a similar concept also named after Le Chatelier was introduced by Paul Samuelson in 1947. There the generalized Le Chatelier principle is for a maximum condition of economic equilibrium.

        ## Catalysts

        A catalyst increases the rate of a reaction without being consumed in the reaction. The use of a catalyst does not affect the position of the equilibrium.
        """
        let prompts = LocalGenerator.generate(pages: pasted(text), sourceTitle: "Chem", maxItems: 20).items.filter { $0.kind == .recall }.map(\.prompt)
        XCTAssertFalse(prompts.contains { $0.localizedCaseInsensitiveContains("dissenting") || $0.localizedCaseInsensitiveContains("opinion") }, "\(prompts)")
        XCTAssertTrue(prompts.contains("Describe economics (Le Chatelier's principle) in your own words."), "\(prompts)")
        XCTAssertTrue(prompts.contains("Describe catalysts in your own words."), "a section that isn't about the subject by name keeps its heading as it is: \(prompts)")
    }

    /// Four plain sentences pasted in: what makes a blank worth asking (a word the text keeps coming back to, a term it defines) has
    /// nothing to go on in so little text, and the iOS Simulator's tagger calls every word "other word". The set is small, not empty.
    func testAFewPastedSentencesStillGetFillIns() {
        let notes = "Mitosis makes two daughter cells that are genetically identical to the parent cell. "
            + "In prophase the chromosomes condense and the nuclear envelope breaks down. "
            + "In metaphase the chromosomes line up at the equator of the cell. "
            + "After mitosis, cytokinesis divides the cytoplasm into two cells."
        let result = LocalGenerator.generate(pages: pasted(notes), sourceTitle: "Cell division", maxItems: 16)
        XCTAssertGreaterThanOrEqual(result.items.count, 2, "\(result.items.map(\.prompt))")
        XCTAssertTrue(result.items.allSatisfy { $0.kind == .cloze }, "\(result.items.map(\.kind))")
        for item in result.items { XCTAssertNil(QuestionQuality.problem(with: item), item.cloze?.text ?? item.prompt) }
    }
}
