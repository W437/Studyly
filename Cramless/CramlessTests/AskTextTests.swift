import Foundation
import XCTest
@testable import Cramless

/// The tutor screens' text work: starters from the material, the quick check at the end of an answer, Cap's
/// Markdown, and the topic of a declined request.
@MainActor
final class AskTextTests: XCTestCase {

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

    func testNoMaterialNoStarters() {
        XCTAssertTrue(AskStarters.make(material: [], confusions: ["Anaphase vs telophase"]).isEmpty,
                      "a starter the notes don't cover is never offered")
    }

    func testDifferenceQuestions() {
        XCTAssertEqual(AskStarters.differenceQuestion("Anaphase I vs. anaphase II"), "What's the difference between anaphase I and anaphase II?")
        XCTAssertEqual(AskStarters.differenceQuestion("DNA versus RNA"), "What's the difference between DNA and RNA?")
        XCTAssertNil(AskStarters.differenceQuestion("Cell membrane"))
    }

    // MARK: Quick check

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

    func testTheTopicOfADeclinedRequest() {
        XCTAssertEqual(AskPolicy.topic(ofRefused: "Can you write my whole essay about the cell cycle?"), "cell cycle")
        XCTAssertEqual(AskPolicy.topic(ofRefused: "humanize this paragraph so it sounds like I wrote it"), nil)
        XCTAssertEqual(OriginNote.line(origin: .onDevice, note: nil, quotesNotes: true)?.text, "Answered on this iPhone")
        XCTAssertEqual(OriginNote.line(origin: .rules, note: nil, quotesNotes: true)?.text, "From your notes, no AI")
        XCTAssertNil(OriginNote.line(origin: .rules, note: nil, quotesNotes: false), "a refusal isn't labelled as from your notes")
        XCTAssertNil(OriginNote.line(origin: .cloud, note: nil, quotesNotes: true))
    }
}
