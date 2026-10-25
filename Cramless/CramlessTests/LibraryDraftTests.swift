import Foundation
import XCTest
@testable import Cramless

/// The editors' drafts: what stops a question or an exam from being saved, and what gets stored.
final class LibraryDraftTests: XCTestCase {
    // MARK: Questions

    func testEachFormatSaysWhatIsMissing() {
        var card = ItemDraft.blank(kind: .flashcard)
        XCTAssertEqual(card.problem, "Write the front of the card.")
        card.prompt = "Osmosis"
        XCTAssertEqual(card.problem, "Write the back of the card.")
        card.answer = "Water moves across a membrane"
        XCTAssertNil(card.problem)

        var recall = ItemDraft.blank(kind: .recall)
        XCTAssertEqual(recall.ideas.count, 1, "an own-words question starts with one key idea to fill in")
        recall.prompt = "Why do cells divide?"
        recall.answer = "To grow and repair."
        XCTAssertEqual(recall.problem, "Add a key idea, so answers in your own words can be graded.")
        recall.ideas[0].label = "Growth and repair"
        XCTAssertNil(recall.problem)

        var choice = ItemDraft.blank(kind: .mcq)
        XCTAssertEqual(choice.options.count, 2)
        choice.prompt = "Which phase?"
        choice.options[0].text = "Metaphase"
        XCTAssertEqual(choice.problem, "Add at least two choices.")
        choice.options[1].text = "Anaphase"
        XCTAssertNil(choice.problem, "the first choice starts as the right one")
        choice.options[0].correct = false
        XCTAssertEqual(choice.problem, "Mark the one right answer.")
        choice.markCorrect(choice.options[1].id)
        XCTAssertEqual(choice.options.map(\.correct), [false, true])
        XCTAssertNil(choice.problem)

        var cloze = ItemDraft.blank(kind: .cloze)
        cloze.clozeText = "During telophase the envelopes re-form."
        XCTAssertEqual(cloze.problem, "Put {{double braces}} around the words to hide.")
        cloze.clozeText = "During {{ }} the envelopes re-form."
        XCTAssertEqual(cloze.problem, "One of the blanks is empty.")
        cloze.clozeText = "During {{telophase}} the envelopes re-form."
        XCTAssertNil(cloze.problem, "a fill-in needs no instruction")
    }

    func testNormalizedChoicesDropEmptyRowsAndAnswerWithTheRightOne() {
        var draft = ItemDraft.blank(kind: .mcq)
        draft.prompt = "  Which phase comes right before cytokinesis? "
        draft.options = [ItemDraft.Option(text: "Prophase", correct: false, why: "  "),
                         ItemDraft.Option(text: " Telophase ", correct: true, why: " Envelopes re-form, then the cell splits. "),
                         ItemDraft.Option(text: "", correct: false)]
        let n = draft.normalized
        XCTAssertEqual(n.prompt, "Which phase comes right before cytokinesis?")
        XCTAssertEqual(n.answer, "Telophase")
        XCTAssertEqual(n.choices, [Choice(text: "Prophase", correct: false, why: nil),
                                   Choice(text: "Telophase", correct: true, why: "Envelopes re-form, then the cell splits.")])
        XCTAssertTrue(n.keyIdeas.isEmpty)
        XCTAssertNil(n.cloze)
    }

    func testNormalizedKeyIdeasCarryTheirPhrasingsInLowercaseWithoutRepeats() {
        var draft = ItemDraft.blank(kind: .apply)
        draft.prompt = "A drug stops spindle fibres. What can't happen?"
        draft.answer = "Anaphase: chromatids can't be pulled apart."
        draft.ideas = [ItemDraft.Idea(id: "k1", label: "Anaphase is blocked", phrasings: "anaphase, ANAPHASE; no anaphase\n"),
                       ItemDraft.Idea(id: "k1", label: "Chromatids stay together", phrasings: ""),
                       ItemDraft.Idea(id: "k3", label: "   ", phrasings: "ignored")]
        let ideas = draft.normalized.keyIdeas
        XCTAssertEqual(ideas.count, 2)
        XCTAssertEqual(ideas[0].terms, ["anaphase is blocked", "anaphase", "no anaphase"])
        XCTAssertEqual(ideas[1].terms, ["chromatids stay together"])
        XCTAssertNotEqual(ideas[0].id, ideas[1].id, "ids stay unique")
    }

    func testNormalizedClozeDerivesItsAnswerAndKeepsOnlyRealAlternates() {
        var draft = ItemDraft.blank(kind: .cloze)
        draft.clozeText = " In {{osmosis}}, water moves from {{dilute}} to concentrated. "
        draft.clozeAlternates = ["Osmosis, osmotic flow", ""]
        let n = draft.normalized
        XCTAssertEqual(n.prompt, ItemDraft.defaultClozePrompt)
        XCTAssertEqual(n.answer, "osmosis, dilute")
        XCTAssertEqual(n.cloze?.text, "In {{osmosis}}, water moves from {{dilute}} to concentrated.")
        XCTAssertEqual(n.cloze?.alternates, [["osmotic flow"], []])

        draft.clozeAlternates = []
        XCTAssertEqual(draft.normalized.cloze?.alternates, [], "no alternates at all stores none")
    }

    func testDraftFromAnItemRoundTrips() {
        let item = StudyItem(course: nil, kind: .recall, status: .suspended, origin: .cloud, prompt: "What is diffusion?",
                             answer: "Particles spread from high to low concentration.", explanation: "Down the gradient.",
                             keyIdeas: [KeyIdea(id: "k1", label: "High to low", terms: ["high to low", "down the gradient"])])
        let draft = ItemDraft(item: item)
        XCTAssertEqual(draft.kind, .recall)
        XCTAssertTrue(draft.suspended)
        XCTAssertEqual(draft.ideas, [ItemDraft.Idea(id: "k1", label: "High to low", phrasings: "down the gradient")])
        XCTAssertEqual(draft.normalized.keyIdeas, [KeyIdea(id: "k1", label: "High to low", terms: ["high to low", "down the gradient"])])

        let cloze = StudyItem(course: nil, kind: .cloze, origin: .person, prompt: ItemDraft.defaultClozePrompt, answer: "osmosis",
                              cloze: ClozeSpec(text: "In {{osmosis}}, water moves.", alternates: [["osmotic flow"]]))
        let clozeDraft = ItemDraft(item: cloze)
        XCTAssertEqual(clozeDraft.prompt, "", "the default instruction isn't shown as typed text")
        XCTAssertEqual(clozeDraft.clozeAlternates, ["osmotic flow"])
        XCTAssertEqual(clozeDraft.blanks, ["osmosis"])
    }

    func testRowsAndIDs() {
        var draft = ItemDraft.blank(kind: .recall)
        draft.addIdea()
        XCTAssertEqual(draft.ideas.map(\.id), ["k1", "k2"])
        draft.ideas.remove(at: 0)
        draft.addIdea()
        XCTAssertEqual(Set(draft.ideas.map(\.id)).count, 2)
        var choices = ItemDraft.blank(kind: .mcq)
        choices.options[0].correct = false
        choices.addOption()
        XCTAssertEqual(choices.options.filter(\.correct).count, 1, "a new option is the right one only when none is")
        XCTAssertEqual(ItemDraft.split("a, b;c\n , "), ["a", "b", "c"])
        XCTAssertEqual(ItemDraft.terms(label: "Same", phrasings: "same, SAME, other"), ["same", "other"])
    }

    // MARK: Exams

    func testExamDraft() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 18))!
        let course = UUID()
        var draft = ExamDraft.new(courseID: course, now: now, calendar: cal)
        XCTAssertEqual(cal.dayDistance(from: now, to: draft.date), 14)
        XCTAssertEqual(cal.component(.hour, from: draft.date), 9)
        XCTAssertNil(draft.problem)
        XCTAssertEqual(draft.scopeIDs, [])
        XCTAssertEqual(draft.resolvedTitle(courseName: "Bio 101"), "Bio 101 exam")
        draft.title = "  Midterm "
        XCTAssertEqual(draft.resolvedTitle(courseName: "Bio 101"), "Midterm")

        draft.wholeCourse = false
        XCTAssertEqual(draft.problem, "Pick at least one topic, or the whole course.")
        let topic = UUID()
        draft.scope = [topic]
        XCTAssertNil(draft.problem)
        XCTAssertEqual(draft.scopeIDs, [topic])

        draft.target = 0.5
        XCTAssertEqual(draft.clampedTarget, 0.7, accuracy: 1e-9)
        draft.target = 0.87
        XCTAssertEqual(draft.clampedTarget, 0.85, accuracy: 1e-9)
        draft.target = 0.99
        XCTAssertEqual(draft.clampedTarget, 0.95, accuracy: 1e-9)

        draft.courseID = nil
        XCTAssertEqual(draft.problem, "Pick the course this exam is for.")
        draft.format.notes = "  open book \n"
        XCTAssertEqual(draft.cleanFormat.notes, "open book")
    }
}
