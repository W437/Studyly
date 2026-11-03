import XCTest
@testable import Cramless

/// The filter every on-device and offline question passes before it is shown: the junk the 14-day test found (a "Term"
/// card, "Describe j.) in your own words.", "What happens during the", a blank that is "Next") goes; the questions around
/// it stay.
@MainActor
final class QuestionQualityTests: XCTestCase {

    private func item(_ kind: ItemKind, _ prompt: String, _ answer: String, cloze: String? = nil) -> GeneratedItem {
        GeneratedItem(id: "x", kind: kind, topic: "T", prompt: prompt, answer: answer, cloze: cloze.map { ClozeSpec(text: $0) }, anchors: ["a"])
    }

    // MARK: What goes

    func testACardWhoseFrontIsABareGenericWordGoes() {
        XCTAssertNotNil(QuestionQuality.problem(with: item(.flashcard, "Term", "negligence")))
        XCTAssertNotNil(QuestionQuality.problem(with: item(.flashcard, "Definition", "something")))
        XCTAssertNotNil(QuestionQuality.problem(with: item(.flashcard, " key  terms ", "something")))
        XCTAssertNil(QuestionQuality.problem(with: item(.flashcard, "Due care", "A duty imposed on each one of us to protect society.")))
        XCTAssertNil(QuestionQuality.problem(with: item(.flashcard, "Cardiac cycle", "The activity of the heart from one beat to the next.")))
    }

    func testDescribeAHeadingThatIsNotATopicGoes() {
        let junk = [
            "Describe j.) in your own words.",
            "Describe 60.) in your own words.",
            "Describe 0:32 in your own words.",
            "Describe description in your own words.",
            "Describe nor do I comment on the word \"unreasonable.\" in your own words.",
            "Describe glycolysis is the metabolic pathway that converts glucose in your own words.",
            "Describe charges are balanced by the difference between in your own words.",
            "Describe the glycolysis pathway can be separated into two in your own words.",
            "Describe Embden-Meyerhof-Parnas pathway.(4) in your own words.",
            "Describe for the in your own words.",
            "Describe of the in your own words.",
            "Describe Q1 in your own words.",
        ]
        for prompt in junk {
            XCTAssertNotNil(QuestionQuality.problem(with: item(.recall, prompt, "Something the page says about it, in a sentence.")), prompt)
        }
        let fine = [
            "Describe the chain rule in your own words.",
            "Describe atrial systole in your own words.",
            "Describe higher derivatives in your own words.",
            "Describe composites of more than two functions in your own words.",
            "Describe prophase in your own words.",
        ]
        for prompt in fine {
            XCTAssertNil(QuestionQuality.problem(with: item(.recall, prompt, "Something the page says about it, in a sentence.")), prompt)
        }
    }

    func testShortRealTermsAndTermsThatStartLikeAFragmentAreStillHeadings() {
        // The offline generator lowercases the heading's first word ("Describe for loops ..."), so a rule that took "for", "if", "in",
        // "on", "to", "as", "by" or "it" for the start of a wrapped sentence dropped these, and one that wanted four letters dropped the
        // acronyms.
        let terms = ["DNA", "ATP", "GDP", "RNA", "pH", "Mg", "AI", "IT", "H2O", "AND gate", "for loops", "if statements", "in vitro fertilization",
                     "in vivo", "on the origin of species", "by-products", "as a service", "the chain rule", "a cell"]
        for term in terms {
            XCTAssertFalse(QuestionQuality.isWeakHeading(term), term)
            XCTAssertNil(QuestionQuality.problem(with: item(.recall, "Describe \(term) in your own words.", "Something the page says about it, in a sentence.")), term)
        }
        // Real fragments and markers are still out: only small words, a list marker, a time, a sentence's second half or a clause.
        let junk = ["for the", "of the", "in", "the", "to", "if", "on", "and so on", "j.)", "60.)", "0:32", "A", "Q1", "(b)", "IV", "iv.", "12.",
                    "nor do I comment on the word \"unreasonable.\"", "glycolysis is the metabolic pathway that converts glucose",
                    "These notes cover chapters one to three", "For present purposes it sufficiently describes the thing"]
        for heading in junk { XCTAssertTrue(QuestionQuality.isWeakHeading(heading), heading) }
        // A heading the next line carries on in lower case is the first half of a sentence; one that starts a new line is a heading.
        XCTAssertTrue(QuestionQuality.isWeakHeading("Nor do I comment", next: "the word unreasonable in this context."))
        XCTAssertTrue(QuestionQuality.isWeakHeading("In vitro fertilization", next: "joins an egg and a sperm outside the body."))
        XCTAssertFalse(QuestionQuality.isWeakHeading("In vitro fertilization", next: "Joins an egg and a sperm outside the body."))
        XCTAssertFalse(QuestionQuality.isWeakHeading("Prophase", next: "Chromosomes condense."))
    }

    func testTheOfflineRulesAskAboutAShortHeadingAndNotAboutAFragmentOrAMarker() {
        func page(_ title: String, _ heading: String) -> [PageText] {
            let lines = [title, heading, "• Describes the thing that is happening here in detail.", "• Is used when natural conception fails to happen.",
                         "• Places the embryo in the womb afterwards."]
            return [PageText(index: 0, label: "1", lines: lines.enumerated().map { TextLine(id: "p0.l\($0.offset)", text: $0.element, box: nil) })]
        }
        func prompts(_ heading: String) -> [String] {
            LocalGenerator.generate(pages: page("Notes", heading), sourceTitle: "T", maxItems: 30).items.filter { $0.kind == .recall }.map(\.prompt)
        }
        for (heading, prompt) in [("DNA", "Describe DNA in your own words."), ("ATP", "Describe ATP in your own words."),
                                  ("GDP", "Describe GDP in your own words."), ("For loops", "Describe for loops in your own words."),
                                  ("If statements", "Describe if statements in your own words."),
                                  ("In vitro fertilization", "Describe in vitro fertilization in your own words.")] {
            XCTAssertEqual(prompts(heading), [prompt], heading)
        }
        for heading in ["for the", "j.)", "60.)", "Q1"] { XCTAssertEqual(prompts(heading), [], heading) }
    }

    func testAPromptWithAnUnmatchedBracketGoes() {
        XCTAssertEqual(QuestionQuality.problem(with: item(.recall, "What is the role of the nucleus (in mitosis?", "It holds the DNA.")), "unmatched bracket")
        XCTAssertEqual(QuestionQuality.problem(with: item(.recall, "Describe j.) in your own words.", "x y z")), "unmatched bracket")
        XCTAssertNotNil(QuestionQuality.problem(with: item(.flashcard, "PFK (phosphofructokinase", "An enzyme.")))
        XCTAssertNil(QuestionQuality.problem(with: item(.flashcard, "PFK (phosphofructokinase)", "An enzyme of glycolysis.")))
        XCTAssertNil(QuestionQuality.problem(with: item(.recall, "What does the term (in genetics) mean for a cell?", "It is a thing.")))
        // A fill-in's own blanks are not brackets.
        XCTAssertNil(QuestionQuality.problem(with: item(.cloze, "Fill in the word.", "telophase", cloze: "During {{telophase}}, the envelopes re-form.")))
    }

    func testAPromptThatStopsMidSentenceOrIsTooShortGoes() {
        XCTAssertEqual(QuestionQuality.problem(with: item(.recall, "What happens during the", "Something happens.")), "ends mid-sentence")
        XCTAssertNotNil(QuestionQuality.problem(with: item(.recall, "What is the purpose of the?", "Something.")))
        XCTAssertNotNil(QuestionQuality.problem(with: item(.recall, "Which of these shows the", "Something.")))
        XCTAssertNotNil(QuestionQuality.problem(with: item(.recall, "What is the difference between a cell and", "Something.")))
        XCTAssertEqual(QuestionQuality.problem(with: item(.recall, "Why?", "In fairness he should make good every injury.")), "too short")
        XCTAssertEqual(QuestionQuality.problem(with: item(.recall, "Explain it.", "Because.")), "too short")
        // A plain question word and a question mark may be three words; a bare statement may not.
        XCTAssertNil(QuestionQuality.problem(with: item(.recall, "What is DNA?", "The molecule that carries genetic information.")))
        XCTAssertNotNil(QuestionQuality.problem(with: item(.recall, "Describe DNA.", "The molecule that carries genetic information.")))
        XCTAssertNil(QuestionQuality.problem(with: item(.recall, "What happens in prophase?", "Chromosomes condense and the envelope breaks down.")))
        XCTAssertNil(QuestionQuality.problem(with: item(.recall, "What do the cells do with it?", "They store it.")))
        // A question may end on a stranded preposition, a demonstrative or a main verb.
        for prompt in ["What is it made of?", "What does ATP stand for?", "Which phase is the cell in?", "What is the ruling in this case about?",
                       "What do they do?", "What is this?", "What happens to the cell before?"] {
            XCTAssertNil(QuestionQuality.problem(with: item(.recall, prompt, "Something the page says about it.")), prompt)
        }
        // A card's front is a term, however short.
        XCTAssertNil(QuestionQuality.problem(with: item(.flashcard, "Mitosis", "Cell division that makes two identical cells.")))
    }

    func testABlankThatIsNotAContentWordGoes() {
        func blank(_ answer: String, _ sentence: String) -> GeneratedItem {
            item(.cloze, "Fill in the word.", answer, cloze: sentence)
        }
        XCTAssertNotNil(QuestionQuality.problem(with: blank("Next", "Click {{Next}} to continue.")))
        XCTAssertNotNil(QuestionQuality.problem(with: blank("The", "{{The}} cell divides in two.")))
        XCTAssertNotNil(QuestionQuality.problem(with: blank("4", "Mitosis has {{4}} phases.")), "a number alone")
        XCTAssertNotNil(QuestionQuality.problem(with: blank("of", "The role {{of}} the nucleus.")))
        XCTAssertNil(QuestionQuality.problem(with: blank("1789", "The revolution began in {{1789}}.")), "a year is a fact worth recalling")
        XCTAssertNil(QuestionQuality.problem(with: blank("Cytokinesis", "{{Cytokinesis}} is the division of the cytoplasm.")))
        XCTAssertNil(QuestionQuality.problem(with: blank("nuclear envelope", "In prophase the {{nuclear envelope}} breaks down.")))
    }

    func testAnAnswerThatIsACitationTailOrStartsMidSentenceGoes() {
        XCTAssertEqual(QuestionQuality.problem(with: item(.recall, "Describe court of Appeals of New York in your own words.",
                                                          "248 N.Y. 339; 162 N.E. 99; 59 A.L.R.")) != nil, true)
        XCTAssertEqual(QuestionQuality.problem(with: item(.recall, "What is the ruling in this case about?", "248 N.Y. 339; 162 N.E. 99; 59 A.L.R. 1253")), "citation tail")
        XCTAssertEqual(QuestionQuality.problem(with: item(.recall, "Describe the ventricular diastole in your own words.",
                                                          ", or relaxation, begins with isovolumic relaxation")), "answer starts mid-sentence")
        XCTAssertNil(QuestionQuality.problem(with: item(.recall, "When did the revolution begin and end?", "It began in 1789 and ended in 1799.")))
    }

    func testTwoDatesAreNotTwoCitationsButTwoReportersAre() {
        for dates in ["From 1 September 1939 to 2 September 1945.", "He was born on 3 March 1950 and died on 14 July 2020.",
                      "1 Sept. 1939 and 2 Sept. 1945", "The war ran from 1 Jan. 1914 to 11 Nov. 1918, and the peace from 28 June 1919."] {
            XCTAssertFalse(QuestionQuality.looksLikeCitation(dates), dates)
            XCTAssertNil(QuestionQuality.problem(with: item(.recall, "When was the war fought?", dates)), dates)
        }
        for citations in ["260 N.Y. 99; 9 Ex. 341", "248 N.Y. 339; 162 N.E. 99; 59 A.L.R. 1253", "Hadley v Baxendale (1854) 9 Exch 341; 156 ER 145",
                          "56 L. Ed. 2d 200 and 93 S. Ct. 705"] {
            XCTAssertTrue(QuestionQuality.looksLikeCitation(citations), citations)
            XCTAssertEqual(QuestionQuality.problem(with: item(.recall, "What is the ruling in this case about?", citations)), "citation tail", citations)
        }
        // One citation is a reference in a sentence, not a tail; a street address is not one.
        XCTAssertFalse(QuestionQuality.looksLikeCitation("248 N.Y. 339"))
        XCTAssertFalse(QuestionQuality.looksLikeCitation("100 East 42 Street and 12 East 14 Street"))
        // Text that is mostly numbers still is.
        XCTAssertTrue(QuestionQuality.looksLikeCitation("12 14 18 22 30 41 52 60 71 80"))
    }

    // MARK: What a printout leaves in the text

    private func cloze(_ sentence: String, blank: String? = nil) -> GeneratedItem {
        let answer = blank ?? (sentence.firstMatch(of: #/\{\{(?<x>.+?)\}\}/#).map { String($0.x) } ?? "")
        return item(.cloze, "Fill in the word.", answer, cloze: sentence)
    }

    func testMarkdownMarkersAWebAddressAndAFootnoteNumberGo() {
        XCTAssertEqual(QuestionQuality.problem(with: cloze("NIH: National Heart ## Statins ## What is {{cholesterol}}?")), "markup left in the text")
        XCTAssertEqual(QuestionQuality.problem(with: cloze("## Dijkstra's algorithm Dijkstra's algorithm is an algorithm for finding {{shortest}} paths.")), "markup left in the text")
        XCTAssertEqual(QuestionQuality.problem(with: item(.recall, "Describe the principle in your own words.", "A principle used to predict the effect of a change.[2] Other names exist.")),
                       "footnote marker in the text")
        XCTAssertEqual(QuestionQuality.problem(with: cloze("\"Le {{Chatelier's}} Principle Definition\" (https://www.thoughtco.com/definition).")), "web address in the text")
        XCTAssertNotNil(QuestionQuality.problem(with: item(.flashcard, "Open textbook", "See www.opentextbc.ca for the full book of chemistry notes.")))
        // C# is a language, an array index is not a footnote, a sentence about "node.js" has no address.
        XCTAssertNil(QuestionQuality.problem(with: item(.flashcard, "C# programming", "A language from Microsoft that compiles to bytecode.")))
        XCTAssertNil(QuestionQuality.problem(with: item(.flashcard, "Node.js", "A runtime that lets JavaScript run outside a browser.")))
        XCTAssertFalse(TextArtifacts.hasFootnoteMarker("The array holds dist[u] for every node."))
    }

    func testAReferenceEntryOrASentenceCutAtAnAbbreviationGoes() {
        let junk = [
            "679, 688; 1 Beven, {{Negligence}} [4th ed.], 7; Paul v.",
            "94; 1 Shearman & Redfield on {{Negligence}}, § 8, and cases cited; Cooley on Torts [3d ed.], p.",
            "{{Chemistry}}: 1st Canadian edition.",
            "{{Open Systems}}: Narratives and the Second Law of Thermodynamics, 2000, p.",
            "{{New York}}: McGraw-Hill, 2011. p.",
            "{{Thermodynamics}} is An Engineering Approach. 7th ed.",
            "Bailyn, M. (1994). A Survey of {{Thermodynamics}}, American Institute of Physics Press.",
            "In Painter, supra, the Court found that a segregated law school could not provide equal educational {{opportunities}}.",
        ]
        for sentence in junk { XCTAssertNotNil(QuestionQuality.problem(with: cloze(sentence)), sentence) }
        XCTAssertEqual(QuestionQuality.problem(with: item(.flashcard, "Brown v.", "Board of Education was decided in 1954.")), "cut off at an abbreviation")
        XCTAssertTrue(TextArtifacts.endsOnAbbreviation("It was conceived by computer scientist Edsger W. Dijkstra, trans."))
        // A chemical symbol is not "Co.", a page number is not a citation, and a sentence may end on a real word.
        XCTAssertFalse(TextArtifacts.endsOnAbbreviation("The methanol concentration rises as the extra CO."))
        XCTAssertFalse(TextArtifacts.endsOnAbbreviation("The result is a vitamin C."))
        XCTAssertTrue(TextArtifacts.endsOnAbbreviation("He worked for Ford Motor Co."))
        XCTAssertNil(QuestionQuality.problem(with: cloze("The first printed {{edition}} of the book appeared in 1859.")))
        XCTAssertNil(QuestionQuality.problem(with: cloze("Two dates are not two citations: the war ran from 1 September 1939 to 2 September 1945, and its {{aftermath}} lasted years.")))
    }

    func testAQuestionAboutAFigureOrAnEquationTheTextLostGoes() {
        for prompt in ["Which statement is true about the given graph?", "What does Figure 4 show about the cycle?", "What is Equation 3?",
                       "What is shown in the table above?", "Describe pressure–volume graph in your own words.", "Describe network diagram in your own words."] {
            XCTAssertNotNil(QuestionQuality.problem(with: item(.recall, prompt, "Something the page says about it, in a sentence.")), prompt)
        }
        XCTAssertEqual(QuestionQuality.problem(with: cloze("{{Red lines}} are the shortest path covering, i.e., connecting u and prev[u].")), "blank is the key to a picture")
        XCTAssertNotNil(QuestionQuality.problem(with: cloze("See Figure 4: the cycle is drawn on a pressure–volume {{diagram}} with four arrows.")))
        // The word "graph" in a graph theory text is a topic, not a picture.
        XCTAssertNil(QuestionQuality.problem(with: cloze("If the nodes of the graph represent cities, then Dijkstra's algorithm finds the shortest {{route}} between two of them.")))
        XCTAssertNil(QuestionQuality.problem(with: item(.recall, "What is a graph in computer science?", "A set of nodes joined by edges, used to model networks of relations.")))
    }

    func testCodeAFormulaAndANameWithInitialsAreNotTopics() {
        for heading in ["17 prev[v] ← u", "2 u ← target", "CO + 2 H2 ⇌ CH3OH", "the reversible reaction 2NO2(g) ⇌", "alt ← dist[u] + Graph.Distance(u,v)",
                        "t. K. Abbott", "T. K. Abbott", "le Chatelier's principle - Wikipedia", "pressure–volume graph", "other statements", "as a macroscopic construct"] {
            XCTAssertTrue(QuestionQuality.isWeakHeading(heading), heading)
        }
        for heading in ["U.S. history", "Dijkstra's algorithm", "C++ programming", "Newton's second law", "Running time", "Equilibrium constant", "as a service"] {
            XCTAssertFalse(QuestionQuality.isWeakHeading(heading), heading)
        }
        XCTAssertNotNil(QuestionQuality.problem(with: item(.flashcard, "dist[v] ← alt", "Updates the distance of v when a shorter path is found.")))
    }

    func testATermThatIsAPieceOfASentenceGoes() {
        let junk = ["Since it", "Today it", "As to B it", "If the only concern", "The presence of such cycles", "Wrongdoer as to them",
                    "Behind the cloud of words", "Carnot heat-engine cycle described", "Key feature", "Main idea", "Now sequence S",
                    "To secure one's own happiness", "Red lines", "Filled nodes", "Open question about the"]
        for term in junk {
            XCTAssertNotNil(TextArtifacts.termProblem(term), term)
            XCTAssertNotNil(QuestionQuality.problem(with: item(.flashcard, term, "A fact about it that the page states in a full sentence.")), term)
            XCTAssertNotNil(QuestionQuality.problem(with: cloze("A sentence that explains something about the topic, and {{\(term)}} sits in its middle somewhere.", blank: term)), term)
        }
        let terms = ["If statements", "In vitro fertilization", "On the Origin of Species", "Carnot cycle", "Red blood cells", "Le Chatelier's principle",
                     "Main memory", "Invariant hypothesis", "Bidirectional Dijkstra", "Equal protection of the laws", "First Amendment", "Only child",
                     "Min-priority queue", "Statins", "OSPF", "Entropy"]
        for term in terms { XCTAssertNil(TextArtifacts.termProblem(term), term) }
    }

    func testACardWhoseAnswerSaysNothingGoes() {
        XCTAssertEqual(QuestionQuality.problem(with: item(.flashcard, "OSPF and IS-IS", "The most common.")), "nothing to learn in the answer")
        XCTAssertNil(QuestionQuality.problem(with: item(.flashcard, "Misology", "Hatred of reason.")))
        XCTAssertNil(QuestionQuality.problem(with: item(.flashcard, "Statins", "A type of cholesterol medicine.")))
        XCTAssertNil(QuestionQuality.problem(with: item(.flashcard, "Cytokinesis", "The division of the cytoplasm.")))
        // A question card may have a short answer.
        XCTAssertNil(QuestionQuality.problem(with: item(.flashcard, "Which clause of the Fourteenth Amendment is violated by segregation?", "The Equal Protection Clause.")))
    }

    // MARK: Fill-ins

    func testABlankThePageGivesAwayOrThatTestsNothingGoes() {
        // The rest of the sentence uses the word; a possessive; an adverb; a generic word; a connective.
        XCTAssertEqual(QuestionQuality.problem(with: cloze("For the will stands between its a priori {{principle}}, which is formal, and the formal principle of volition.")), "the sentence gives the blank away")
        XCTAssertEqual(QuestionQuality.problem(with: cloze("If the guard threw it down willfully, he would not have threatened the {{plaintiff's}} safety, so far as appearances could warn him.")), "blank is only a possessive")
        XCTAssertEqual(QuestionQuality.problem(with: cloze("Before more advanced queues were found, {{Dijkstra's}} original algorithm ran in quadratic time on dense graphs.")), "blank is only a possessive")
        XCTAssertEqual(QuestionQuality.problem(with: cloze("A chauffeur {{negligently}} collides with another car which is filled with dynamite, although he could not know it.")), "blank is an adverb")
        XCTAssertNotNil(QuestionQuality.problem(with: cloze("Negligence, like risk, is thus a {{term}} of relation between the actor and the person who is hurt.")))
        XCTAssertEqual(QuestionQuality.problem(with: cloze("The court heard the appeal and decided that the lower court had made a legal {{example}} of the rule.")), "blank is too generic")
        XCTAssertNotNil(QuestionQuality.problem(with: cloze("But even in this case, if the desire for happiness did not influence his will, and {{supposing}} that health was not a necessary element.")))
        XCTAssertNotNil(QuestionQuality.problem(with: cloze("{{OSPF and IS-IS}} are the most common.")))
        // Blanks worth recalling stay: a noun the sentence doesn't use, a year, an acronym, a key phrase.
        XCTAssertNil(QuestionQuality.problem(with: cloze("{{Bleeding}} is the most common side effect of blood thinners.")))
        XCTAssertNil(QuestionQuality.problem(with: cloze("The revolution began in {{1789}} and reshaped the political order of Europe.")))
        XCTAssertNil(QuestionQuality.problem(with: cloze("Statins lower {{LDL}} cholesterol by slowing down how much cholesterol the liver makes.")))
        XCTAssertNil(QuestionQuality.problem(with: cloze("The algorithm uses a {{min-priority queue}} data structure for selecting the shortest paths known so far.")))
    }

    func testASentenceThatDoesNotStandAloneIsNotAFillIn() {
        // A page number or list marker at its start, a quoted title, a sentence that carries on, an unmatched quotation mark.
        for sentence in ["492-493. (c) Where a State has undertaken to provide an {{opportunity}} for an education, it must be made available to all.",
                         "\"Application of the Second Law of Thermodynamics to the Developing {{Ecosystem}}\".",
                         "But not merely a {{relationship}} between man and those whom he might reasonably expect his act would injure.",
                         "Rather, a {{relationship}} between him and those whom he does in fact injure is what the law requires.",
                         "He wrote that \"the experiment was a {{failure}} and nothing more could be said about it."] {
            XCTAssertNotNil(QuestionQuality.problem(with: cloze(sentence)), sentence)
        }
        // A formula that is most of the sentence goes; one in passing stays.
        XCTAssertNotNil(QuestionQuality.problem(with: cloze("The running time is: Θ(|E| ⋅ T_dk + |V| ⋅ T_em), where T_dk and T_em are the {{complexities}} of the operations.")))
        XCTAssertNotNil(QuestionQuality.problem(with: cloze("alt ← dist[u] + Graph.Distance(u,v) updates the {{distance}} of the neighbour.")))
        XCTAssertNil(QuestionQuality.problem(with: cloze("Before more advanced queues were found, the {{original}} algorithm ran in Θ(|V|^2) time, where |V| is the number of nodes.")))
        XCTAssertNil(QuestionQuality.problem(with: cloze("The Dial algorithm uses a {{bucket queue}} to obtain a running time of O(|E| + |V|C).")))
        // Short but whole.
        XCTAssertNil(QuestionQuality.problem(with: cloze("Separate educational facilities are {{inherently unequal}}.")))
    }

    // MARK: What the model wrote

    func testAQuestionWithNothingToChooseFromOrALabelOrAboutTheAuthorGoes() {
        XCTAssertEqual(QuestionQuality.problem(with: item(.flashcard, "Which of the following statements is true about the Carnot cycle?", "The Carnot cycle is a reversible thermodynamic cycle.")),
                       "asks to choose from options it doesn't show")
        XCTAssertNotNil(QuestionQuality.problem(with: item(.recall, "Which one of these is not a phase of mitosis, and why is that?", "Interphase is not part of mitosis itself.")))
        XCTAssertEqual(QuestionQuality.problem(with: item(.flashcard, "Flashcard: What is the Carnot cycle?", "A reversible cycle between two reservoirs.")), "a label in front of the question")
        XCTAssertNotNil(QuestionQuality.problem(with: item(.flashcard, "Term: Efficiency", "An upper limit on the efficiency of a heat engine.")))
        XCTAssertEqual(QuestionQuality.problem(with: item(.flashcard, "What does the author think of reason?", "Reason is weak and delusive.")), "asks what the author thinks")
        XCTAssertEqual(QuestionQuality.problem(with: item(.recall, "What is the key idea of the text?", "A good will is good in itself.")), "asks what the author thinks")
        // A question with a claim in it is concrete enough, and a real multiple-choice question has its options.
        XCTAssertNil(QuestionQuality.problem(with: item(.flashcard, "What does the author say about the plaintiff's claim being original and primary?", "It is a claim for breach of a duty to herself, not one derived from another person's wrong.")))
        var mcq = item(.mcq, "Which phase is this: chromosomes line up at the equator?", "Metaphase")
        mcq.choices = [Choice(text: "Prophase", correct: false), Choice(text: "Metaphase", correct: true), Choice(text: "Anaphase", correct: false)]
        XCTAssertNil(QuestionQuality.problem(with: mcq))
        mcq.choices = [Choice(text: "Prophase", correct: false), Choice(text: "Metaphase", correct: true)]
        XCTAssertEqual(QuestionQuality.problem(with: mcq), "choices that don't make a question")
    }

    func testAnAnswerThatIsAlreadyInTheQuestionGoes() {
        XCTAssertEqual(QuestionQuality.problem(with: item(.flashcard, "What is an indirect inclination?", "An inclination that is not direct.")), "the answer is in the question")
        XCTAssertNotNil(QuestionQuality.problem(with: item(.flashcard, "What is a good will?", "A good will.")))
        // An answer that adds the one word asked for stays.
        XCTAssertNil(QuestionQuality.problem(with: item(.flashcard, "What are the most common side effects of blood thinners?", "Bleeding is the most common side effect of blood thinners.")))
        XCTAssertNil(QuestionQuality.problem(with: item(.flashcard, "What is negligence?", "Negligence is the absence of care, according to the circumstances.")))
    }

    // MARK: Questions that ask the same thing

    func testTheSameFactInAnotherFormatOrOtherWordsIsAskedOnce() {
        let kept = QuestionQuality.filter([
            item(.cloze, "Fill in the key word.", "Cholesterol", cloze: "{{Cholesterol}} is a waxy, fat-like substance that's found in all the cells in your body."),
            item(.flashcard, "Cholesterol", "A waxy, fat-like substance that's found in all the cells in your body."),
            item(.cloze, "Fill in the word.", "liver", cloze: "Cholesterol is made by your {{liver}} and travels through the blood on proteins called lipoproteins."),
            item(.flashcard, "Statins", "A type of cholesterol medicine used to lower LDL cholesterol."),
            item(.flashcard, "What are statins?", "A type of cholesterol medicine used to lower the LDL cholesterol."),
        ])
        XCTAssertEqual(kept.map(\.prompt), ["Fill in the key word.", "Fill in the word.", "Statins"])
        // Different facts about the same subject are different questions; a short card is never a duplicate by overlap.
        XCTAssertFalse(QuestionQuality.isNearDuplicate(item(.flashcard, "Statins", "A type of cholesterol medicine."),
                                                        item(.flashcard, "Bleeding", "The most common side effect of blood thinners.")))
        XCTAssertFalse(QuestionQuality.isNearDuplicate(item(.flashcard, "DNA", "Genetic material."), item(.flashcard, "RNA", "Genetic material.")))
        // A choice question and a card about one fact are both kept.
        var mcq = item(.mcq, "Which phase is this: sister chromatids are pulled to opposite poles?", "Anaphase")
        mcq.choices = [Choice(text: "Prophase", correct: false), Choice(text: "Anaphase", correct: true), Choice(text: "Telophase", correct: false)]
        XCTAssertFalse(QuestionQuality.isNearDuplicate(mcq, item(.flashcard, "Anaphase", "Sister chromatids are pulled to opposite poles of the cell.")))
    }

    func testGoodQuestionsOfEveryFormatSurviveTheFilter() {
        let good: [GeneratedItem] = [
            item(.flashcard, "What is the Carnot cycle?", "An ideal thermodynamic cycle between a hot and a cold reservoir, made of two isothermal and two adiabatic steps."),
            item(.flashcard, "Which clause of the Fourteenth Amendment does segregation violate?", "The Equal Protection Clause."),
            item(.flashcard, "Entropy", "A thermodynamic state variable that measures the number of accessible microstates of a system."),
            item(.recall, "Why does a catalyst not change the position of an equilibrium?", "It speeds up the forward and the backward reaction by the same factor."),
            item(.recall, "Describe the base case of the proof in your own words.", "There is just one visited node, the source, and its distance is zero, the shortest possible."),
            cloze("Unlike Dijkstra's algorithm, the Bellman–Ford algorithm can be used on graphs with negative edge weights, as long as the graph contains no negative {{cycle}}."),
            cloze("To prove the correctness of Dijkstra's algorithm, mathematical {{induction}} can be used on the number of visited nodes."),
            cloze("{{Hypertension}}, also called high blood pressure, is when blood puts too much pressure against the walls of your arteries."),
        ]
        for q in good { XCTAssertNil(QuestionQuality.problem(with: q), q.prompt + " " + (q.cloze?.text ?? q.answer)) }
        XCTAssertEqual(QuestionQuality.filter(good).count, good.count)
    }

    // MARK: Repeats

    func testARepeatedQuestionIsKeptOnceNormalised() {
        let kept = QuestionQuality.filter([
            item(.flashcard, "Cardiac cycle", "The activity of the heart."),
            item(.flashcard, "cardiac  cycle!", "The performance of the heart."),
            item(.recall, "What happens in prophase?", "Chromosomes condense and the envelope breaks down."),
            item(.recall, "What happens in Prophase", "A second answer for the same question here."),
            item(.cloze, "Fill in the word.", "telophase", cloze: "During {{telophase}}, the envelopes re-form."),
            item(.cloze, "Fill in the word.", "anaphase", cloze: "During {{anaphase}}, the chromatids separate."),
        ])
        XCTAssertEqual(kept.map(\.prompt), ["Cardiac cycle", "What happens in prophase?", "Fill in the word.", "Fill in the word."])
    }

    // MARK: Where it applies

    func testTheOfflineRulesNeverWriteWhatTheFilterWouldDrop() {
        let pages: [[TextLine]] = [
            AITestSupport.sampleLines,
            [
                "Torts", "Court of Appeals of New York", "248 N.Y. 339; 162 N.E. 99; 59 A.L.R. 1253", "j.)",
                "Plaintiff was standing on a platform of defendant's railroad after buying a ticket to go to Rockaway Beach.",
                "60.)", "As was said by Mr. Justice Holmes many years ago, the law should be able to predict liability.",
                "Term", "Negligence: the failure to use reasonable care.",
                "Description", "The conduct of the defendant's guard was not a wrong in its relation to the plaintiff.",
            ].enumerated().map { TextLine(id: "p0.l\($0.offset)", text: $0.element, box: nil) },
        ]
        for lines in pages {
            let r = LocalGenerator.generate(pages: [PageText(index: 0, label: "1", lines: lines)], sourceTitle: "T", maxItems: 30)
            for item in r.items { XCTAssertNil(QuestionQuality.problem(with: item), item.prompt) }
            XCTAssertEqual(Set(r.items.map { QuestionQuality.duplicateKey($0) }).count, r.items.count, "no repeats")
        }
    }

    func testTheOnDeviceModelsJunkIsNotShown() async {
        let app = AITestSupport.makeApp(mode: .local)
        app.ai.probe = FixedOnDeviceProbe(.ready)
        let junk = #"""
        {"topics": ["Mitosis"],
         "questions": [
           {"kind": "flashcard", "topic": "Mitosis", "prompt": "Term", "answer": "Cytokinesis", "keyIdeas": [], "wrongChoices": [], "clozeSentence": "", "lines": ["L40"]},
           {"kind": "recall", "topic": "Mitosis", "prompt": "What happens during the", "answer": "Chromosomes condense and the envelope breaks down.",
            "keyIdeas": [{"label": "Chromosomes condense", "terms": ["condense"]}], "wrongChoices": [], "clozeSentence": "", "lines": ["L9"]},
           {"kind": "fillIn", "topic": "Mitosis", "prompt": "Fill in the blank.", "answer": "Next", "keyIdeas": [], "wrongChoices": [],
            "clozeSentence": "Click ____ to continue.", "lines": ["L40"]},
           {"kind": "flashcard", "topic": "Mitosis", "prompt": "Cytokinesis", "answer": "The division of the cytoplasm.", "keyIdeas": [], "wrongChoices": [],
            "clozeSentence": "", "lines": ["L40"]}
         ]}
        """#
        app.ai.onDevice = ScriptedOnDeviceBackend([.json(junk)])
        let outcome = await app.ai.generateSet(AITestSupport.sampleInput)
        XCTAssertEqual(outcome.origin, .onDevice)
        let modelPrompts = outcome.items.filter { $0.id.hasPrefix("d") }.map(\.prompt)
        XCTAssertEqual(modelPrompts, ["Cytokinesis"], "the model's other three were junk")
        for item in outcome.items { XCTAssertNil(QuestionQuality.problem(with: item), item.prompt) }
    }

    func testTheOnDeviceModelsFootnotesGoAndItsOptionlessChoiceAndRepeatedFactAreNotShown() async {
        let app = AITestSupport.makeApp(mode: .local)
        app.ai.probe = FixedOnDeviceProbe(.ready)
        let output = #"""
        {"topics": ["Mitosis"],
         "questions": [
           {"kind": "flashcard", "topic": "Mitosis", "prompt": "Cytokinesis", "answer": "The division of the cytoplasm.[1]", "keyIdeas": [], "wrongChoices": [], "clozeSentence": "", "lines": ["L40"]},
           {"kind": "flashcard", "topic": "Mitosis", "prompt": "Which of the following statements is true about cytokinesis?", "answer": "The cytoplasm divides.", "keyIdeas": [], "wrongChoices": [], "clozeSentence": "", "lines": ["L40"]},
           {"kind": "fillIn", "topic": "Mitosis", "prompt": "Fill in the blank.", "answer": "Cytokinesis", "keyIdeas": [], "wrongChoices": [],
            "clozeSentence": "____ is the division of the cytoplasm.", "lines": ["L40"]}
         ]}
        """#
        app.ai.onDevice = ScriptedOnDeviceBackend([.json(output)])
        let outcome = await app.ai.generateSet(AITestSupport.sampleInput)
        XCTAssertEqual(outcome.origin, .onDevice)
        let model = outcome.items.filter { $0.id.hasPrefix("d") }
        XCTAssertEqual(model.map(\.prompt), ["Cytokinesis"], "the options-less question and the same fact asked again are left out")
        XCTAssertEqual(model.first?.answer, "The division of the cytoplasm.", "the footnote number is taken out")
        for item in outcome.items { XCTAssertNil(QuestionQuality.problem(with: item), item.prompt) }
    }

    func testTheSmallTestsOnTheirOwn() {
        // A formula the text lost leaves its frame behind; an ordinary colon does not.
        XCTAssertTrue(TextArtifacts.hasLostSymbols("For a reversible cyclic process: which means the line integral entropy: is path-independent."))
        XCTAssertTrue(TextArtifacts.hasLostSymbols("The quantity ( ) is conserved."))
        XCTAssertTrue(TextArtifacts.hasLostSymbols("The rate is denoted, and it depends on pressure."))
        XCTAssertFalse(TextArtifacts.hasLostSymbols("There are two kinds of cell: animal cells and plant cells."))
        // Two sentences run together; two sentences with a full stop between them.
        XCTAssertTrue(TextArtifacts.hasFusedSentences("The 'index' response of interest The two ways of statement differ."))
        XCTAssertFalse(TextArtifacts.hasFusedSentences("The cell divides. The next stage is anaphase."))
        // A sentence that leans on a line, a step, a listing or the text around it.
        for sentence in ["The search terminates after line 10 if u = target.", "Otherwise the algorithm skips to step 6.", "In the following pseudocode, dist is an array.",
                         "It is implemented separately in pseudocode:", "In the former case, let w be the first unvisited node.", "As mentioned earlier, a queue helps."] {
            XCTAssertTrue(TextArtifacts.leansOnItsSurroundings(sentence), sentence)
        }
        XCTAssertFalse(TextArtifacts.leansOnItsSurroundings("The algorithm uses a min-priority queue data structure for selecting the shortest paths known so far."))
        // Code symbols are for lines, code syntax for headings; a sentence may mention dist[v].
        XCTAssertTrue(TextArtifacts.hasCodeSymbols("alt ← dist[u] + Graph.Distance(u,v)"))
        XCTAssertFalse(TextArtifacts.hasCodeSymbols("For each visited node v, dist[v] is the shortest distance from source to v."))
        XCTAssertTrue(TextArtifacts.hasCodeSyntax("dist[v]"))
        XCTAssertFalse(TextArtifacts.hasCodeSyntax("principle[1] is a principle"))
        // Markers: a footnote number and a pronunciation guide go, a name from a program (dist[u]) stays.
        XCTAssertEqual(TextArtifacts.withoutMarkers("Dijkstra's algorithm (/ˈdaɪk.strəz/, DYKE-strəz) finds paths.[1] It is fast.[citation needed]"), "Dijkstra's algorithm finds paths. It is fast.")
        XCTAssertEqual(TextArtifacts.withoutMarkers("The array holds dist[u] for every node, so dist[u] is a code name."), "The array holds dist[u] for every node, so dist[u] is a code name.")
        XCTAssertEqual(TextArtifacts.modelLabel(in: "Flashcard: What is Equation 3?"), "What is Equation 3?")
        XCTAssertEqual(TextArtifacts.modelLabel(in: "Q2. Why does the pressure rise?"), "Why does the pressure rise?")
        XCTAssertNil(TextArtifacts.modelLabel(in: "Terms of service"))
        XCTAssertNil(TextArtifacts.modelLabel(in: "Q-learning: what is it used for?"), "a hyphen is part of a name, a colon is a label")
        // "Equation 3" points at a lost equation, "the equation 2x + 3 = 7" is the problem itself.
        XCTAssertTrue(TextArtifacts.refersToMissingFigure("What does Equation 3 say about the efficiency?"))
        XCTAssertTrue(TextArtifacts.refersToMissingFigure("Using eq. (4.2), find the work done."))
        XCTAssertFalse(TextArtifacts.refersToMissingFigure("Solve the equation 2x + 3 = 7 for x."))
    }

    func testTheRulesDoNotRepeatAFactTheModelAskedWhenTheSetsAreMerged() {
        var card = item(.flashcard, "Cholesterol", "A waxy, fat-like substance that's found in all the cells in your body.")
        card.anchors = ["p0.l1"]
        var sameFact = item(.cloze, "Fill in the key word.", "Cholesterol", cloze: "{{Cholesterol}} is a waxy, fat-like substance that's found in all the cells in your body.")
        sameFact.anchors = ["p0.l2"]
        var other = item(.cloze, "Fill in the word.", "liver", cloze: "Cholesterol is made by your {{liver}} and travels through the blood on proteins called lipoproteins.")
        other.anchors = ["p0.l3"]
        let merged = AIRouter.merge([card], with: [sameFact, other], limit: 5)
        XCTAssertEqual(merged.map(\.prompt), ["Cholesterol", "Fill in the word."], "the fill-in of the card's fact is not added")
    }

    // MARK: Second round: what the blind reviewers still found

    func testABlankThatSharesARootWithAWordOfItsSentenceIsGivenAway() {
        XCTAssertEqual(QuestionQuality.problem(with: cloze("Is the result too remote from the cause, and here we consider {{remoteness}} in time and space.")), "the sentence gives the blank away")
        XCTAssertEqual(QuestionQuality.problem(with: cloze("Under that doctrine, {{equality}} of treatment is accorded when the races are provided substantially equal facilities.")), "the sentence gives the blank away")
        XCTAssertNotNil(QuestionQuality.problem(with: cloze("A feeling of {{inferiority}} follows when a group is treated as inferior by the law.")))
        for (a, b) in [("remote", "remoteness"), ("equal", "equality"), ("segregated", "segregation"), ("inferior", "inferiority")] { XCTAssertTrue(TextArtifacts.sharesRoot(a, b), a) }
        for (a, b) in [("energy", "entropy"), ("heat", "engine"), ("act", "action"), ("pressure", "pressing")] { XCTAssertFalse(TextArtifacts.sharesRoot(a, b), a) }
        XCTAssertNil(QuestionQuality.problem(with: cloze("{{Bleeding}} is the most common side effect of blood thinners.")))
        XCTAssertNil(QuestionQuality.problem(with: cloze("The court must ask itself whether there was a natural and continuous {{sequence}} between cause and effect.")))
    }

    func testWhatALostFormulaLeavesInTheWordsAroundItGoes() {
        let garbled = "The principle analyzes a system when one of its state variables, say changes by an amount the 'driving change', causing a change the 'response' in another variable of the same system."
        XCTAssertTrue(TextArtifacts.hasDebris(garbled))
        XCTAssertEqual(QuestionQuality.problem(with: item(.recall, "Describe the thermodynamic principle in your own words.", garbled)), "what a lost formula leaves")
        for debris in ["The rate is given by the law , and it depends on pressure.", "The cycle is described by and the work done on it.", "It is applied.[.", "The value of the constant ( , ) is fixed."] {
            XCTAssertTrue(TextArtifacts.hasDebris(debris), debris)
        }
        // One word in single quotes is a term; apostrophes are not quotes.
        for fine in ["The doctrine of 'separate but equal' has no place in public education.", "The plaintiff's injuries and the defendant's duty are different questions.",
                     "He wrote 'Hello' and left, by and large without a word."] {
            XCTAssertFalse(TextArtifacts.hasDebris(fine), fine)
        }
    }

    func testDescribeAHeadingNeedsAnAnswerThatTalksAboutIt() {
        let unrelated = "Nothing can possibly be conceived in the world, or even out of it, which can be called good, without qualification, except a good will. Intelligence, wit, judgement, and the other talents of the mind are undoubtedly good."
        XCTAssertEqual(QuestionQuality.problem(with: item(.recall, "Describe transition from the common rational knowledge of morality to the philosophical in your own words.", unrelated)),
                       "the answer doesn't talk about the heading")
        let about = "Changing the concentration of a chemical will shift the equilibrium to the side that would counter that change in concentration. The chemical system will attempt to partly oppose the change."
        XCTAssertNil(QuestionQuality.problem(with: item(.recall, "Describe effect of change in concentration in your own words.", about)))
        // A list is not prose, and a summary is not about the word "summary".
        XCTAssertNil(QuestionQuality.problem(with: item(.recall, "Describe symptoms in your own words.", "Fever. Cough. A sore throat and a runny nose.")))
        XCTAssertNil(QuestionQuality.problem(with: item(.recall, "Describe syllabus (the Reporter's summary) in your own words.", unrelated)))
        // A question heading is the question: its answer needn't repeat it.
        XCTAssertNil(QuestionQuality.problem(with: item(.recall, "What lifestyle changes can help lower high blood pressure?", "Losing weight. Being physically active. Managing stress.")))
    }

    func testAPartOfTheDocumentIsNotATopic() {
        for heading in ["Opinion of the Court (Warren, C.J.)", "Dissenting opinion (Andrews, J.)", "Concurring opinion", "Foreword", "Reporter's headnote and statement of the case"] {
            XCTAssertTrue(QuestionQuality.isWeakHeading(heading), heading)
        }
        for heading in ["Public opinion", "Opinion polls", "Dissent in animals", "Syllabus (the Reporter's summary)"] { XCTAssertFalse(QuestionQuality.isWeakHeading(heading), heading) }
    }

    func testACardThatIsASentenceOfAnOwnWordsAnswerIsThatAnswerAgain() {
        let answer = "Bidirectional Dijkstra is a variant of Dijkstra's algorithm designed to efficiently compute the shortest path between a source vertex and a target vertex. The key idea is to run two simultaneous searches."
        let recall = item(.recall, "Describe bidirectional Dijkstra in your own words.", answer)
        let card = item(.flashcard, "Bidirectional Dijkstra", "A variant of Dijkstra's algorithm designed to efficiently compute the shortest path between a source vertex and a target vertex.")
        XCTAssertTrue(QuestionQuality.isNearDuplicate(recall, card))
        // A fill-in of one of those sentences asks for a word of it and stays; so does a card about something else.
        XCTAssertFalse(QuestionQuality.isNearDuplicate(recall, cloze("Bidirectional Dijkstra is a variant of Dijkstra's algorithm designed to efficiently compute the shortest {{path}} between a source vertex and a target vertex.")))
        XCTAssertFalse(QuestionQuality.isNearDuplicate(recall, item(.flashcard, "Priority queue", "A structure that returns the item with the smallest key first and supports decrease-key operations.")))
    }
}
