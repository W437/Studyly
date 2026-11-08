import Foundation
import XCTest
@testable import Cramless

/// The tutor screens' text work: starters from the material, the quick check at the end of an answer, Cap's
/// Markdown, and the topic of a declined request.
@MainActor
final class AskTextTests: XCTestCase {

    // MARK: The mistake, explained on one page

    private let threeParts = """
    You're right that the cell divides. The one thing off: mitosis doesn't make sex cells.

    During mitosis the DNA is copied and separated, so each new cell matches the parent.

    Quick check: how many daughter cells does one round of mitosis make: 2, 4 or 8?
    """

    func testThreePartsAreAnExplanationAndACheck() throws {
        let reply = MistakeReply.split(threeParts)
        XCTAssertEqual(reply.explanation, """
        You're right that the cell divides. The one thing off: mitosis doesn't make sex cells.

        During mitosis the DNA is copied and separated, so each new cell matches the parent.
        """)
        let check = try XCTUnwrap(reply.check)
        XCTAssertEqual(check.question, "How many daughter cells does one round of mitosis make?")
        XCTAssertEqual(check.options, ["2", "4", "8"])
        XCTAssertEqual(check.lead, "", "the card shows only the question")
    }

    func testTheRelaysOwnScriptHasItsCheckSplitOff() throws {
        let script = try RelayFixtures.load(TutorScript.self, "tutor-mistake")
        let text = script.events.compactMap { $0.data.text }.joined()
        let reply = MistakeReply.split(text)
        XCTAssertEqual(MistakeReply.paragraphs(reply.explanation).count, 2)
        XCTAssertEqual(reply.check?.options, ["2", "4", "8"])
    }

    func testTheCheckArrivesUnderTheExplanationAsTheStreamReachesIt() {
        XCTAssertEqual(MistakeReply.split("", streaming: true), MistakeReply())
        let first = MistakeReply.split("You're right that", streaming: true)
        XCTAssertEqual(first.explanation, "You're right that")
        XCTAssertFalse(first.reachedCheck)
        let second = MistakeReply.split("One.\n\nDuring mito", streaming: true)
        XCTAssertEqual(second.explanation, "One.\n\nDuring mito", "two parts are both the explanation while they come")
        XCTAssertFalse(second.reachedCheck)
        let third = MistakeReply.split("One.\n\nTwo.\n\nQuick check: how many", streaming: true)
        XCTAssertEqual(third.explanation, "One.\n\nTwo.")
        XCTAssertNil(third.check, "not a question yet")
        XCTAssertEqual(third.checkDraft, "Quick check: how many")
        XCTAssertTrue(third.reachedCheck, "the explanation above it is whole")
        let done = MistakeReply.split("One.\n\nTwo.\n\nQuick check: how many?", streaming: true)
        XCTAssertEqual(done.check?.question, "How many?")
    }

    func testTwoPartsAndAMissingCheckAsksThemToSayItBack() throws {
        let noCheck = MistakeReply.split("You had the first half.\n\nThe notes add the second half.")
        XCTAssertEqual(noCheck.explanation, "You had the first half.\n\nThe notes add the second half.")
        XCTAssertEqual(noCheck.check, MistakeReply.sayItBack)

        let noWhy = MistakeReply.split("You had the first half.\n\nWhat does the page add?")
        XCTAssertEqual(noWhy.explanation, "You had the first half.")
        XCTAssertEqual(noWhy.check?.question, "What does the page add?")
    }

    func testOneParagraphKeepsItsQuestionApart() {
        let reply = MistakeReply.split("You had the first half. The second half is the division of the cytoplasm. Which comes first?")
        XCTAssertEqual(reply.explanation, "You had the first half. The second half is the division of the cytoplasm.")
        XCTAssertEqual(reply.check?.question, "Which comes first?")
    }

    func testAListStaysWhole() {
        let list = "These are the phases:\n- Prophase\n- Metaphase"
        let reply = MistakeReply.split(list)
        XCTAssertEqual(reply.explanation, list)
        XCTAssertEqual(reply.check, MistakeReply.sayItBack)
    }

    func testAHintThatIsOnlyAQuestionHasOnlyTheCheck() {
        let reply = MistakeReply.split("Which line of your page talks about the cytoplasm?")
        XCTAssertEqual(reply.explanation, "")
        XCTAssertEqual(reply.check?.question, "Which line of your page talks about the cytoplasm?")
    }

    func testTheOfflineExplanationAndHintFit() {
        let explain = MistakeReply.split("You wrote “Sex cells”, but the answer is “Two cells”. Your notes say:\n\nMitosis makes two identical cells.")
        XCTAssertEqual(explain.explanation, "You wrote “Sex cells”, but the answer is “Two cells”. Your notes say:\n\nMitosis makes two identical cells.")
        XCTAssertEqual(explain.check, MistakeReply.sayItBack)

        let hint = MistakeReply.split("You wrote “Sex cells. Or not”. Have another look: Textbook p. 87 says: “Mitosis makes two ____ cells.” What goes in the gap?")
        XCTAssertEqual(hint.explanation, "You wrote “Sex cells. Or not”.")
        XCTAssertEqual(hint.check?.question, "Textbook p. 87 says: “Mitosis makes two ____ cells.” What goes in the gap?")
    }

    func testNotCoveredAndADeclineHaveNoCheck() {
        for text in [LocalTutor.notCovered, "I couldn't find that in what you've added.", TutorPolicy.cheatRefusal] {
            let reply = MistakeReply.split(text)
            XCTAssertEqual(reply.explanation, text)
            XCTAssertNil(reply.check)
            XCTAssertFalse(reply.reachedCheck)
        }
    }

    // MARK: Starters

    func testStartersComeFromTheMaterialAndAreCovered() {
        let starters = AskStarters.make(material: AITestSupport.material, confusions: ["Anaphase vs telophase"], limit: 3)
        XCTAssertEqual(starters.count, 3, "\(starters)")
        XCTAssertEqual(starters.first, "What's the difference between anaphase and telophase?")
        XCTAssertTrue(starters.contains("What happens after mitosis?") || starters.contains("Why is mitosis important?"), "\(starters)")
        let retriever = LocalRetriever(material: AITestSupport.material)
        for starter in starters { XCTAssertTrue(AskStarters.isCovered(starter, by: retriever), starter) }
        XCTAssertEqual(Set(starters).count, starters.count, "no repeats")
    }

    func testStartersFromTheCardsOfAnImportedDeck() {
        let deck = TutorMaterial.deck(sourceID: UUID(), title: "Chapter 3 key terms (Quizlet)", kind: .quizlet, cards: [
            TutorCard(id: "a", front: "elasticity", back: "how much quantity changes when price changes"),
            TutorCard(id: "b", front: "During ____, the chromatids reach opposite poles.", back: "telophase"),
            TutorCard(id: "c", front: "Why does a price ceiling cause a shortage?", back: "because the price is held below where the market clears"),
            TutorCard(id: "d", front: "law of demand", back: "when price goes up, quantity demanded goes down"),
            TutorCard(id: "e", front: "Total ATP per glucose", back: "about 30-32"),
        ])
        let starters = AskStarters.make(material: [deck], confusions: [], limit: 3)
        XCTAssertEqual(starters.count, 3, "\(starters)")
        XCTAssertEqual(starters.first, "What is elasticity?")
        XCTAssertFalse(starters.contains { $0.contains("____") }, "a fill-in is not a term to ask about: \(starters)")
        let retriever = LocalRetriever(material: [deck])
        for starter in starters { XCTAssertTrue(AskStarters.isCovered(starter, by: retriever), starter) }
        XCTAssertEqual(AskStarters.cardQuestion(deck.cards[2]), "Why does a price ceiling cause a shortage?")
        XCTAssertNil(AskStarters.cardQuestion(deck.cards[1]))
        XCTAssertNil(AskStarters.cardQuestion(TutorCard(id: "z", front: "$$ \\frac{a}{b} $$.", back: "x")))
    }

    func testNoMaterialNoStarters() {
        XCTAssertTrue(AskStarters.make(material: [], confusions: ["Anaphase vs telophase"]).isEmpty,
                      "a starter the notes don't cover is never offered")
    }

    func testAStarterAsAChip() {
        XCTAssertEqual(AskStarters.chipLabel("What's the difference between anaphase and telophase?"), "Anaphase vs telophase?")
        XCTAssertEqual(AskStarters.chipLabel("What's the difference between DNA and RNA?"), "DNA vs RNA?")
        XCTAssertEqual(AskStarters.chipLabel("What is the Krebs cycle?"), "What is the Krebs cycle?")
    }

    private let starts: [AssistantQuickStart.Start] = [
        .init(title: "Make cards", icon: "rectangle.stack", prefix: "Make cards on ", kind: .cards),
        .init(title: "Quiz me", icon: "checklist", prefix: "Quiz me on ", kind: .quiz),
        .init(title: "Write a note", icon: "doc.text", prefix: "Write me a note on ", kind: .note),
        .init(title: "Add exam", icon: "calendar", prefix: "Add my exam on ", kind: .exam),
    ]

    func testTheDockChipsPutTheStartersBetweenWhatCapCanMake() {
        let chips = AskDockChips.make(quickStarts: starts, starters: ["What's the difference between mitosis and meiosis?", "What is DNA?", "What is RNA?"])
        XCTAssertEqual(chips.map(\.title), ["Quiz me", "Make cards", "Mitosis vs meiosis?", "What is DNA?", "Write a note", "Add exam"])
        XCTAssertEqual(chips[0].action, .compose("Quiz me on "))
        XCTAssertEqual(chips[2].action, .ask("What's the difference between mitosis and meiosis?"), "the chip is short; the question stays whole")
        XCTAssertTrue(chips[2].isQuestion)
        XCTAssertFalse(chips[0].isQuestion)
    }

    func testTheDockChipsOfferResearchOnlyWhenItIsThere() {
        XCTAssertFalse(AskDockChips.make(quickStarts: starts, starters: []).contains { $0.title == "Research online" })
        let web = starts + [.init(title: "Research online", icon: "globe", prefix: "Research online: ", kind: .research)]
        XCTAssertEqual(AskDockChips.make(quickStarts: web, starters: []).last?.title, "Research online")
    }

    func testWithoutTheAssistantTheDockIsAQuizAndTheQuestions() {
        let chips = AskDockChips.make(quickStarts: [], starters: ["What is DNA?", "What is RNA?"])
        XCTAssertEqual(chips.map(\.title), ["Quiz me", "What is DNA?", "What is RNA?"])
        XCTAssertEqual(chips[0].action, .quiz)
    }

    func testDifferenceQuestions() {
        XCTAssertEqual(AskStarters.differenceQuestion("Anaphase I vs. anaphase II"), "What's the difference between anaphase I and anaphase II?")
        XCTAssertEqual(AskStarters.differenceQuestion("DNA versus RNA"), "What's the difference between DNA and RNA?")
        XCTAssertNil(AskStarters.differenceQuestion("Cell membrane"))
    }

    // MARK: Quick check

    private func entry(_ role: ChatRole, _ text: String) -> ChatEntry {
        let message = ChatMessage(thread: nil, role: role, text: text, now: Date(timeIntervalSince1970: 0))
        return ChatEntry(message)
    }

    func testWhileCapsQuestionWaitsTheComposerTakesTheAnswer() throws {
        let asked = entry(.user, "What's the difference between mitosis and cytokinesis?")
        let hint = entry(.assistant, "Let's work it out from your page. What does the page say is divided in cytokinesis?")
        let waiting = try XCTUnwrap(ChatPane.waitingCheck([asked, hint]))
        XCTAssertEqual(waiting.question, "What does the page say is divided in cytokinesis?")
        XCTAssertNil(ChatPane.waitingCheck([asked, hint, entry(.user, "The cytoplasm")]), "answered: the chips come back")
        XCTAssertNil(ChatPane.waitingCheck([asked, entry(.assistant, "Cytokinesis divides the cytoplasm.")]), "no question, nothing waits")
        XCTAssertNil(ChatPane.waitingCheck([asked, entry(.assistant, LocalTutor.notCovered)]))
        XCTAssertNil(ChatPane.waitingCheck([asked, entry(.assistant, TutorPolicy.cheatRefusal)]))
        XCTAssertNil(ChatPane.waitingCheck([]))
    }

    func testALabelledQuickCheckWithOptions() throws {
        let check = try XCTUnwrap(QuickCheck.split("Meiosis makes four cells.\n\nQuick check before we go on: how many cells does meiosis end with: 2, 4 or 8?"))
        XCTAssertTrue(check.isLabelled)
        XCTAssertEqual(check.lead, "Meiosis makes four cells.")
        XCTAssertEqual(check.question, "How many cells does meiosis end with?")
        XCTAssertEqual(check.options, ["2", "4", "8"])
    }

    func testOptionsAfterAComma() throws {
        let check = try XCTUnwrap(QuickCheck.split("Quick check: which happens first, mitosis or cytokinesis?"))
        XCTAssertEqual(check.question, "Which happens first?")
        XCTAssertEqual(check.options, ["Mitosis", "Cytokinesis"])
        XCTAssertEqual(check.lead, "")
    }

    func testAWhichQuestionTakesItsOptionsFromTheChat() throws {
        let check = try XCTUnwrap(QuickCheck.split("Short version: mitosis splits the nucleus. Quick check: which one happens first?",
                                                   chatContext: "What's the difference between mitosis and cytokinesis?"))
        XCTAssertEqual(check.lead, "Short version: mitosis splits the nucleus.")
        XCTAssertEqual(check.question, "Which one happens first?")
        XCTAssertEqual(check.options, ["Mitosis", "Cytokinesis"])
    }

    func testAHintEndsWithAQuestionToAnswerInWords() throws {
        let check = try XCTUnwrap(QuickCheck.split("Let's work it out from your page. Then something else happens to the rest of the cell. What does the page say is divided in cytokinesis?"))
        XCTAssertFalse(check.isLabelled)
        XCTAssertEqual(check.question, "What does the page say is divided in cytokinesis?")
        XCTAssertTrue(check.options.isEmpty)
        XCTAssertEqual(check.lead, "Let's work it out from your page. Then something else happens to the rest of the cell.")
    }

    func testNoQuestionNoQuickCheck() {
        XCTAssertNil(QuickCheck.split("Mitosis splits the nucleus."))
        XCTAssertNil(QuickCheck.split("| Divisions | 1 | 2? |"), "a table row isn't a quick check")
        XCTAssertTrue(QuickCheck.listedOptions(in: "What does a balanced equation tell you about the reaction?") == nil)
        XCTAssertTrue(QuickCheck.listedOptions(in: "Is it the one that lines up the chromosomes along the middle or the other?") == nil,
                      "long options aren't buttons")
    }

    // MARK: Markdown

    func testMarkdownBlocks() {
        let text = """
        Short version: **mitosis copies a cell**.

        | | Mitosis | Meiosis |
        |---|---|---|
        | Divisions | 1 | 2 |
        | New cells | 2, identical | 4 |

        - Prophase
        - Metaphase
        1. Copy the DNA
        2. Split the cell
        """
        let blocks = CapMarkdown.blocks(text)
        XCTAssertEqual(blocks.count, 4, "\(blocks)")
        XCTAssertEqual(blocks[0], .paragraph("Short version: **mitosis copies a cell**."))
        XCTAssertEqual(blocks[1], .table(header: ["", "Mitosis", "Meiosis"], rows: [["Divisions", "1", "2"], ["New cells", "2, identical", "4"]]))
        XCTAssertEqual(blocks[2], .bullets(["Prophase", "Metaphase"]))
        XCTAssertEqual(blocks[3], .numbered(["Copy the DNA", "Split the cell"]))
    }

    func testAHalfArrivedAnswerStillParses() {
        let blocks = CapMarkdown.blocks("Short version: **mitosis cop\n\n| | Mitosis |\n|---|---|\n| Divisions | 1")
        XCTAssertEqual(blocks.last, .table(header: ["", "Mitosis"], rows: [["Divisions", "1"]]))
        // The unpaired ** is left out rather than shown.
        XCTAssertEqual(String(CapMarkdown.inline("Short version: **mitosis cop").characters), "Short version: mitosis cop")
        XCTAssertEqual(String(CapMarkdown.inline("**Bold** and *soft*").characters), "Bold and soft")
    }

    func testPlainTextReadsTablesRowByRow() {
        let plain = CapMarkdown.plain("**Short** version.\n\n| | Mitosis | Meiosis |\n|---|---|---|\n| Divisions | 1 | 2 |")
        XCTAssertEqual(plain, "Short version.\nDivisions, Mitosis: 1, Meiosis: 2")
        XCTAssertEqual(CapMessageView.spoken("**Yes**: four cells.", groups: [CitationGroup(label: "Slides p. 12", citations: [])]),
                       "Cap: Yes: four cells. Sources: Slides p. 12.")
    }

    // MARK: Citations and declined requests

    func testCitationsWithOneLabelShareAChip() {
        let a = Citation(id: "1", sourceID: UUID(), pageIndex: 0, start: nil, quote: "A", label: "Textbook p. 87")
        let b = Citation(id: "2", sourceID: a.sourceID, pageIndex: 0, start: nil, quote: "B", label: "Textbook p. 87")
        let c = Citation(id: "3", sourceID: UUID(), pageIndex: nil, start: 192, quote: "C", label: "Lecture 6 · 03:12")
        let groups = CitationGroup.groups([a, c, b])
        XCTAssertEqual(groups.map(\.label), ["Textbook p. 87", "Lecture 6 · 03:12"])
        XCTAssertEqual(groups[0].citations.map(\.id), ["1", "2"])
        XCTAssertFalse(groups[0].isLecture)
        XCTAssertTrue(groups[1].isLecture)
    }

    func testTheTopicOfADeclinedRequestIsOneTheStudentsOwnMaterialHas() {
        let names = ["Cell cycle", "Mitosis", "Cytokinesis", "Chapter 3 key terms"]
        XCTAssertEqual(AskPolicy.topic(ofRefused: "Can you write my whole essay about the cell cycle?", among: names), "Cell cycle")
        XCTAssertEqual(AskPolicy.topic(ofRefused: "Write my essay on mitosis", among: names), "Mitosis")
        XCTAssertEqual(AskPolicy.topic(ofRefused: "Do my homework on mitosis", among: names), "Mitosis")
        // A request that names none of them gets no topic, never words picked out of the sentence ("Quiz me on take online").
        XCTAssertNil(AskPolicy.topic(ofRefused: "take my online quiz for me", among: names))
        XCTAssertNil(AskPolicy.topic(ofRefused: "can you just give me the answers to the AP exam", among: names))
        XCTAssertNil(AskPolicy.topic(ofRefused: "humanize this paragraph so it sounds like I wrote it", among: names))
        XCTAssertNil(AskPolicy.topic(ofRefused: "How do I ace the midterm?", among: names))
        XCTAssertNil(AskPolicy.topic(ofRefused: "write my essay", among: []))
        // Words that are the request are not a match, even in a source's name.
        XCTAssertNil(AskPolicy.topic(ofRefused: "do my homework", among: ["Homework 3", "Exam review"]))
        XCTAssertEqual(AskPolicy.names(inTitle: "Lecture 6: Cell division"), ["Cell division", "Lecture 6"])
        XCTAssertEqual(AskPolicy.names(inTitle: "Chapter 3 key terms (Quizlet)"), ["Chapter 3 key terms"])
        XCTAssertEqual(AskPolicy.names(inTitle: "Federalist No. 10 (Madison, 1787)"), ["Federalist No. 10 (Madison, 1787)"])
        XCTAssertEqual(AskPolicy.names(inTitle: "  "), [])
        XCTAssertEqual(OriginNote.line(origin: .onDevice, note: nil, quotesNotes: true)?.text, "Answered on this iPhone")
        XCTAssertEqual(OriginNote.line(origin: .rules, note: nil, quotesNotes: true)?.text, "From your notes, no AI")
        XCTAssertNil(OriginNote.line(origin: .rules, note: nil, quotesNotes: false), "a refusal isn't labelled as from your notes")
        XCTAssertNil(OriginNote.line(origin: .cloud, note: nil, quotesNotes: true))
    }

    // MARK: Nothing sold mid-session

    func testExplainMyMistakeShowsNoUpgradeButton() {
        XCTAssertFalse(ExplainMistakeView.allowsUpgrade, "only sessions open it")
        let limit = AISuggestion.upgrade(.tutor, message: AIFreeLimits.message(for: .tutor))
        XCTAssertNil(AISuggestionCard.buttonTitle(for: limit, allowsUpgrade: ExplainMistakeView.allowsUpgrade))
        XCTAssertEqual(AISuggestionCard.buttonTitle(for: limit, allowsUpgrade: true).map { String(localized: $0) }, "See Pro",
                       "in Ask itself the offer stays")
        XCTAssertNotNil(AISuggestionCard.buttonTitle(for: .allowCloud(feature: "Explain"), allowsUpgrade: false),
                        "consent isn't a sale")
    }

    func testTheCostCapNotesAreKnownSoAHelpLinkCanSitBesideThem() {
        XCTAssertTrue(AIFreeLimits.isCostCapNote(AIFreeLimits.costCapTutorNote))
        XCTAssertTrue(AIFreeLimits.isCostCapNote(AIFreeLimits.costCapAssistantNote))
        XCTAssertFalse(AIFreeLimits.isCostCapNote("Cloud AI couldn't be reached, so Cap answered from your notes on this iPhone."))
        XCTAssertFalse(AIFreeLimits.isCostCapNote(nil))
    }
}

