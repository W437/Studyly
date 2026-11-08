import SwiftData
import XCTest
@testable import Cramless

/// What a topic's plan holds and when Cap offers it. Pure.
final class TeachPlannerTests: XCTestCase {
    private let topic = UUID()
    private let cal = EngineTest.calendar()
    private lazy var now = EngineTest.date(2026, 10, 22, 18, in: cal)

    private func item(_ answer: String, recall: Double? = 0.9, ideas: [KeyIdea] = []) -> TeachItem {
        TeachItem(id: UUID(), kind: ideas.isEmpty ? .flashcard : .recall, prompt: ideas.isEmpty ? "What's this one about?" : "Tell me about it.", answer: answer, ideas: ideas, recall: recall)
    }

    private func idea(_ id: String, _ label: String) -> KeyIdea { KeyIdea(id: id, label: label, terms: [label.lowercased()]) }

    private func plan(_ items: [TeachItem]) -> TeachPlan? {
        TeachPlanner.plan(topicID: topic, topicName: "Anaphase", courseID: nil, items: items)
    }

    func testWeakestFirstAndNeverStudiedLast() throws {
        let strong = item("strong", recall: 0.95)
        let weak = item("weak", recall: 0.4)
        let middle = item("middle", recall: 0.7)
        let unseen = item("unseen", recall: nil)
        let plan = try XCTUnwrap(plan([strong, unseen, middle, weak]))
        XCTAssertEqual(plan.ideas.map(\.label), ["What's this one about? Weak.", "What's this one about? Middle.", "What's this one about? Strong.", "What's this one about? Unseen."])
        XCTAssertEqual(plan.ideas.map(\.itemID), [weak.id, middle.id, strong.id, unseen.id])
    }

    func testAtMostSixIdeasOneFromEachQuestionFirst() throws {
        let a = item("a", recall: 0.1, ideas: [idea("k1", "A one"), idea("k2", "A two"), idea("k3", "A three")])
        let b = item("b", recall: 0.2, ideas: [idea("k1", "B one"), idea("k2", "B two"), idea("k3", "B three")])
        let c = item("c", recall: 0.3, ideas: [idea("k1", "C one"), idea("k2", "C two")])
        let plan = try XCTUnwrap(plan([a, b, c]))
        XCTAssertEqual(plan.ideas.map(\.label), ["A one", "B one", "C one", "A two", "B two", "C two"])
    }

    func testIdeasGetTheirOwnIDsAndDuplicatesGo() throws {
        let a = item("a", recall: 0.1, ideas: [idea("k1", "Spindle fibres pull")])
        let b = item("b", recall: 0.2, ideas: [idea("k1", "spindle fibres pull."), idea("k2", "Chromatids separate")])
        let plan = try XCTUnwrap(plan([a, b]))
        XCTAssertEqual(plan.ideas.map(\.id), ["t1", "t2"], "two questions can both have a k1; the grader needs one id per idea")
        XCTAssertEqual(plan.ideas.map(\.label), ["Spindle fibres pull", "Chromatids separate"])
    }

    func testTooLittleToAsk() {
        XCTAssertNil(plan([]))
        XCTAssertNil(plan([item("only")]))
        XCTAssertNil(plan([item("same"), item("same")]))
    }

    func testAQuestionWithNoIdeasBecomesAWholeStatement() {
        func said(_ prompt: String, _ answer: String, kind: ItemKind = .flashcard, cloze: ClozeSpec? = nil, explanation: String = "") -> String? {
            TeachPlanner.ideas(of: TeachItem(id: UUID(), kind: kind, prompt: prompt, answer: answer, cloze: cloze, explanation: explanation)).first?.label
        }
        XCTAssertEqual(said("S phase", "The part of interphase when DNA is replicated."), "S phase: the part of interphase when DNA is replicated.", "a term and what it means")
        XCTAssertEqual(said("What do spindle fibres do in anaphase?", "They pull the chromatids apart", kind: .mcq), "They pull the chromatids apart", "a whole answer stands alone")
        XCTAssertEqual(said("Which phase lines the chromosomes up?", "Metaphase", kind: .mcq), "Which phase lines the chromosomes up? Metaphase.", "never a lone word")
        XCTAssertEqual(said("What holds the chromatids together?", "The centromeres", kind: .mcq), "What holds the chromatids together? The centromeres.")
        XCTAssertEqual(said("Which phase lines the chromosomes up?", "Metaphase", kind: .mcq, explanation: "In metaphase the chromosomes line up at the middle. Then they part."),
                       "In metaphase the chromosomes line up at the middle.", "its explanation says it better")
        XCTAssertEqual(said("Fill in the word.", "osmosis", kind: .cloze, cloze: ClozeSpec(text: "In {{osmosis}}, water moves across a membrane.")), "In osmosis, water moves across a membrane.")
        XCTAssertEqual(said("Mitosis", "Cell division"), "Mitosis: cell division.")
        XCTAssertNil(said("What is 2 + 2?", "4"), "a sum has nothing to explain")
        XCTAssertEqual(said("How many chromosomes do humans have?", "46"), "How many chromosomes do humans have? 46.")
        XCTAssertNil(said("Explain metaphase", "Metaphase"), "an answer that only repeats its question")
        XCTAssertEqual(TeachPlanner.terms(of: "Anaphase"), ["anaphase"])
        let long = TeachPlanner.terms(of: "The sister chromatids get pulled towards opposite poles")
        XCTAssertEqual(long.first, "the sister chromatids get pulled towards opposite poles")
        XCTAssertTrue(long.contains("chromatids"), "\(long)")
        XCTAssertTrue(TeachPlanner.ideas(of: item("   ")).isEmpty)
    }

    func testTheSubjectIsOneTheRelayTakesAsItIs() throws {
        let items = (0..<8).map { item("Idea \($0)", recall: Double($0) / 10) }
        let subject = try XCTUnwrap(plan(items)).subject(level: "college")
        XCTAssertEqual(subject.kind, .recall)
        XCTAssertEqual(subject.prompt, "Explain Anaphase")
        XCTAssertEqual(subject.keyIdeas.count, 6)
        XCTAssertLessThanOrEqual(subject.keyIdeas.count, RelayLimits.keyIdeas)
        XCTAssertEqual(subject.level, "college")
        XCTAssertFalse(subject.modelAnswer.isEmpty)
    }

    func testTheRulesGradeThePlanLikeAnyAnswer() throws {
        let plan = try XCTUnwrap(plan([item("Sister chromatids"), item("Spindle fibres"), item("Opposite poles")]))
        let subject = plan.subject(level: nil)
        XCTAssertEqual(subject.wholeIdeas, Set(plan.ideas.map(\.id)))
        let all = LocalGrader.grade(subject, answer: .text("The sister chromatids are pulled by spindle fibres to opposite poles."))
        XCTAssertEqual(Set(all.hitIdeaIDs), Set(plan.ideas.map(\.id)))
        XCTAssertEqual(all.verdict, .correct)
        let thin = LocalGrader.grade(subject, answer: .text("Something about spindle fibres."))
        XCTAssertEqual(thin.hitIdeaIDs.count, 1)
        XCTAssertEqual(thin.verdict, .partial)
        XCTAssertEqual(thin.missing.count, 2)
    }

    func testTheFirstMissingIsTheWeakest() throws {
        let weak = item("weak", recall: 0.3)
        let strong = item("strong", recall: 0.9)
        let plan = try XCTUnwrap(plan([strong, weak]))
        XCTAssertEqual(plan.firstMissing(covered: [])?.itemID, weak.id)
        XCTAssertEqual(plan.firstMissing(covered: ["t1"])?.itemID, strong.id)
        XCTAssertNil(plan.firstMissing(covered: ["t1", "t2"]))
    }

    func testAFollowUpIsAskedInOwnWordsWhateverItsKind() {
        let choice = TeachItem(id: UUID(), kind: .mcq, prompt: "Which phase?", answer: "Anaphase")
        let subject = TeachPlanner.followUpSubject(choice, level: nil)
        XCTAssertEqual(subject.kind, .recall)
        XCTAssertEqual(subject.prompt, "Which phase?")
        XCTAssertEqual(subject.keyIdeas.first?.label, "Which phase? Anaphase.")
        let right = LocalGrader.grade(subject, answer: .text("Anaphase"))
        XCTAssertEqual(right.verdict, .correct, "asked the question, its one new word is the answer")
    }

    func testAShortKeyIdeaReadsWithItsQuestion() throws {
        let ideas = [KeyIdea(id: "k1", label: "Anaphase is blocked", terms: ["anaphase is blocked"]), KeyIdea(id: "k2", label: "Chromosomes wait for the spindle", terms: ["wait"])]
        let item = TeachItem(id: UUID(), kind: .recall, prompt: "What does the checkpoint do?", answer: "It holds the cell until every chromosome is attached.", ideas: ideas)
        XCTAssertEqual(TeachPlanner.ideas(of: item).map(\.label), ["What does the checkpoint do? Anaphase is blocked.", "Chromosomes wait for the spindle"])
        XCTAssertEqual(TeachPlanner.ideas(of: item).first?.terms, ["anaphase is blocked"], "its terms stay what was chosen")
        let short = TeachIdea(idea: TeachPlanner.ideas(of: item)[0], itemID: item.id)
        let added = try XCTUnwrap(TeachPlanner.addedQuestion(for: short, from: item))
        XCTAssertEqual(added.prompt, "What does the checkpoint do?")
        XCTAssertEqual(added.idea.label, "Anaphase is blocked.")
        let long = TeachIdea(idea: TeachPlanner.ideas(of: item)[1], itemID: item.id)
        XCTAssertEqual(TeachPlanner.addedQuestion(for: long, from: item)?.prompt, "Explain in your own words: Chromosomes wait for the spindle.")
    }

    func testAFollowUpIsAQuestion() {
        let card = TeachItem(id: UUID(), kind: .flashcard, prompt: "Interphase", answer: "The longest part of the cell cycle.")
        XCTAssertEqual(TeachPlanner.followUpPrompt(of: card), "Explain interphase in your own words.")
        XCTAssertEqual(TeachPlanner.followUpPrompt(of: TeachItem(id: UUID(), kind: .flashcard, prompt: "DNA", answer: "Holds the genes.")), "Explain DNA in your own words.")
        let fill = TeachItem(id: UUID(), kind: .cloze, prompt: "Fill in the word.", answer: "osmosis", cloze: ClozeSpec(text: "In {{osmosis}}, water moves."))
        XCTAssertEqual(TeachPlanner.followUpPrompt(of: fill), "In ____, water moves.")
        let question = TeachItem(id: UUID(), kind: .mcq, prompt: "Which phase?", answer: "Anaphase")
        XCTAssertEqual(TeachPlanner.followUpPrompt(of: question), "Which phase?")
    }

    // MARK: What counts as saying an idea

    /// Cell cycle's three cards, as the plan has them.
    private func cellCycle() throws -> TeachPlan {
        let cards = [("G1 phase", "The first growth phase of interphase."), ("S phase", "The part of interphase when DNA is replicated."),
                     ("Interphase", "The longest part of the cell cycle, when the cell grows and copies its DNA.")]
        let items = cards.enumerated().map { TeachItem(id: UUID(), kind: .flashcard, prompt: $1.0, answer: $1.1, recall: 0.1 * Double($0 + 1)) }
        return try XCTUnwrap(TeachPlanner.plan(topicID: topic, topicName: "Cell cycle", courseID: nil, items: items))
    }

    private func hits(_ words: String, _ plan: TeachPlan) -> [String] {
        let found = Set(LocalGrader.gradeOwnWords(plan.subject(level: nil), words).hitIdeaIDs)
        return plan.ideas.filter { found.contains($0.id) }.map(\.label)
    }

    func testOneSharedWordIsNotSayingAnIdea() throws {
        let plan = try cellCycle()
        XCTAssertEqual(hits("first growth phase of interphase", plan), ["G1 phase: the first growth phase of interphase."],
                       "sharing \"interphase\" isn't saying when DNA is replicated")
        XCTAssertEqual(hits("It has something to do with interphase I think", plan), [], "one word says nothing yet")
    }

    func testATrueParaphraseCounts() throws {
        let plan = try cellCycle()
        XCTAssertEqual(hits("DNA gets replicated during interphase", plan), ["S phase: the part of interphase when DNA is replicated."])
        XCTAssertEqual(hits("the cell grows and copies its DNA", plan), ["Interphase: the longest part of the cell cycle, when the cell grows and copies its DNA."])
    }

    func testANegatedStatementDoesNotCount() throws {
        let plan = try cellCycle()
        XCTAssertEqual(hits("DNA is not replicated in interphase", plan), [])
    }

    func testAKeyIdeaAnyoneChoseStillCountsOnItsTerm() throws {
        let plan = try XCTUnwrap(TeachPlanner.plan(topicID: topic, topicName: "Anaphase", courseID: nil, items: [
            TeachItem(id: UUID(), kind: .recall, prompt: "What happens?", answer: "They separate.", ideas: [KeyIdea(id: "k1", label: "Chromatids separate", terms: ["separate"])]),
            TeachItem(id: UUID(), kind: .recall, prompt: "What pulls?", answer: "Fibres.", ideas: [KeyIdea(id: "k1", label: "Spindle fibres pull", terms: ["spindle fibres"])]),
        ]))
        XCTAssertTrue(plan.subject(level: nil).wholeIdeas.isEmpty)
        XCTAssertEqual(LocalGrader.gradeOwnWords(plan.subject(level: nil), "They separate").hitIdeaIDs.count, 1)
    }

    func testHowManyWordsAStatementWants() {
        XCTAssertEqual((1...10).map(LocalGrader.statementWordsNeeded), [1, 2, 2, 2, 3, 3, 4, 4, 4, 4])
    }

    func testTheIdeaOfATopicsOwnNameIsNotAnIdea() {
        let same = [TeachItem(id: UUID(), kind: .flashcard, prompt: "What is this?", answer: "Cell cycle"), TeachItem(id: UUID(), kind: .flashcard, prompt: "What's it called?", answer: "The cell cycle")]
        XCTAssertNil(TeachPlanner.plan(topicID: topic, topicName: "Cell cycle", courseID: nil, items: same))
    }

    func testAMissedIdeaBecomesARealQuestionOrNone() throws {
        let card = TeachItem(id: UUID(), kind: .flashcard, prompt: "S phase", answer: "The part of interphase when DNA is replicated.")
        let statement = TeachIdea(idea: KeyIdea(id: "t1", label: "S phase: the part of interphase when DNA is replicated.", terms: []), itemID: card.id, isStatement: true)
        let added = try XCTUnwrap(TeachPlanner.addedQuestion(for: statement, from: card))
        XCTAssertEqual(added.prompt, "Explain S phase in your own words.")
        XCTAssertEqual(added.answer, "The part of interphase when DNA is replicated.")
        XCTAssertEqual(added.idea.label, "The part of interphase when DNA is replicated.")

        let bare = TeachItem(id: UUID(), kind: .recall, prompt: "Which?", answer: "Metaphase", ideas: [KeyIdea(id: "k1", label: "Metaphase", terms: ["metaphase"])])
        let own = TeachIdea(idea: bare.ideas[0], itemID: bare.id)
        XCTAssertNil(TeachPlanner.addedQuestion(for: own, from: bare), "\"Explain in your own words: Metaphase.\" answered \"Metaphase\" is no question")
    }

    // MARK: The offer

    private func snapshots(studied: Int, new: Int = 0, recall: Double = 0.95, course: UUID) -> [ItemSnapshot] {
        (0..<studied).map { _ in EngineTest.studied(kind: .flashcard, topic: topic, course: course, recall: recall, daysAgo: 1, now: now, cal: cal) }
            + (0..<new).map { _ in EngineTest.fresh(kind: .flashcard, topic: topic, course: course, createdAt: now) }
    }

    private func offers(value: Double? = 0.9, items: [ItemSnapshot], examDays: Int? = 20, course: UUID, taught: [String: Date] = [:]) -> [NoticeTeachBack] {
        let mastery = [TopicReadiness(id: topic, name: "Anaphase", value: value, itemCount: items.count)]
        let exams = examDays.map { [ExamSnapshot(id: UUID(), courseID: course, title: "Midterm", date: cal.adding(days: $0, to: now), scope: [], target: 0.8,
                                                 format: ExamFormat())] } ?? []
        return TeachPlanner.offers(mastery: mastery, courseOf: [topic: course], items: items, exams: exams, taught: taught, now: now, calendar: cal)
    }

    func testNotOnTheExamsOwnDayOrJustAfter() {
        let course = UUID()
        let items = snapshots(studied: 4, course: course)
        let mastery = [TopicReadiness(id: topic, name: "Meiosis", value: 0.9, itemCount: items.count)]
        func offered(examHoursAgo hours: Double) -> [NoticeTeachBack] {
            let sat = ExamSnapshot(id: UUID(), courseID: course, title: "Midterm", date: now.addingTimeInterval(-hours * 3600), scope: [], target: 0.8, format: ExamFormat())
            return TeachPlanner.offers(mastery: mastery, courseOf: [topic: course], items: items, exams: [sat], taught: [:], now: now, calendar: cal)
        }
        XCTAssertTrue(offered(examHoursAgo: 8).isEmpty, "that evening")
        XCTAssertTrue(offered(examHoursAgo: 24).isEmpty, "the next day")
        XCTAssertFalse(offered(examHoursAgo: 24 * 4).isEmpty, "a few days later")
    }

    func testANameThatDoesntReadAsATopicIsNotOffered() {
        for name in ["First", "Dear", "What does he say", "In cracks and pores in rock.", "Why it matters?"] {
            XCTAssertFalse(TeachPlanner.readsAsATopic(name), name)
        }
        for name in ["Meiosis", "The Gettysburg Address", "TCP segment structure", "First impressions", "Causes of inflation", "明治維新"] {
            XCTAssertTrue(TeachPlanner.readsAsATopic(name), name)
        }
    }

    func testAStrongTopicIsOffered() {
        let course = UUID()
        XCTAssertEqual(offers(items: snapshots(studied: 4, course: course), course: course).map(\.topicID), [topic])
    }

    func testNotWhenItIsNotStrong() {
        let course = UUID()
        XCTAssertTrue(offers(value: 0.84, items: snapshots(studied: 4, course: course), course: course).isEmpty)
        XCTAssertTrue(offers(value: nil, items: snapshots(studied: 4, course: course), course: course).isEmpty)
    }

    func testNotWhenTooLittleOfItIsStudied() {
        let course = UUID()
        XCTAssertTrue(offers(items: snapshots(studied: 2, course: course), course: course).isEmpty)
        XCTAssertTrue(offers(items: snapshots(studied: 3, new: 3, course: course), course: course).isEmpty, "half of it unseen isn't \"you know it\"")
        XCTAssertEqual(offers(items: snapshots(studied: 3, new: 2, course: course), course: course).count, 1)
    }

    func testNotInTheWeekBeforeTheExam() {
        let course = UUID()
        let items = snapshots(studied: 4, course: course)
        XCTAssertTrue(offers(items: items, examDays: 6, course: course).isEmpty)
        XCTAssertEqual(offers(items: items, examDays: 7, course: course).count, 1)
        XCTAssertEqual(offers(items: items, examDays: nil, course: course).count, 1, "with no exam, there's no hurry")
    }

    func testNotAgainForTwoWeeks() {
        let course = UUID()
        let items = snapshots(studied: 4, course: course)
        let recently = [topic.uuidString: cal.adding(days: -13, to: now)]
        XCTAssertTrue(offers(items: items, course: course, taught: recently).isEmpty)
        let long = [topic.uuidString: cal.adding(days: -14, to: now)]
        XCTAssertEqual(offers(items: items, course: course, taught: long).count, 1)
    }

    func testTheCopy() {
        XCTAssertEqual(TeachCopy.noticeTitle("Anaphase"), "You know anaphase. Can you teach it?")
        XCTAssertEqual(TeachCopy.noticeTitle("DNA replication"), "You know DNA replication. Can you teach it?")
        XCTAssertEqual(String(localized: TeachCopy.ask("Cell cycle")), "Explain cell cycle to me like I missed the class.")
        XCTAssertEqual(String(localized: TeachCopy.added), "Question added")
        XCTAssertEqual(TeachCopy.explainTerm("S phase"), "Explain S phase in your own words.")
        XCTAssertEqual(String(localized: TeachCopy.ideasCount(4, of: 6)), "4 of 6 ideas")
        XCTAssertEqual(String(localized: TeachCopy.ideasCount(1, of: 1)), "1 of 1 idea")
        XCTAssertFalse(String(localized: TeachCopy.addMissing).contains("card"), "questions, not cards")
    }
}

/// Teach Cap against the store: a topic's plan, the check, the follow-up's one review, the missing idea, and the card on Today.
@MainActor
final class TeachAppModelTests: XCTestCase {
    let cal = EngineTest.calendar()
    var clock: TestClock!
    var app: AppModel!
    var course: Course!
    var topic: Topic!
    var previousLive: AppModel?

    override func setUp() async throws {
        previousLive = AppModel.live
        clock = TestClock(EngineTest.date(2026, 10, 22, 18, in: cal))
        app = try StudyTestApp.make(clock: clock, calendar: cal)
        AppModel.schedulerFuzz = false
        course = Course(name: "Bio 101", now: clock.now)
        app.context.insert(course)
        topic = Topic(course: course, name: "Anaphase", sortOrder: 0, now: clock.now)
        app.context.insert(topic)
        course.topics.append(topic)
        app.save()
    }

    override func tearDown() async throws {
        AppModel.schedulerFuzz = true
        AppModel.live = previousLive
        app = nil
    }

    @discardableResult
    private func add(_ kind: ItemKind = .flashcard, prompt: String, answer: String, studiedDaysAgo: Double? = 1, stability: Double = 60,
                     keyIdeas: [KeyIdea] = [], choices: [Choice] = [], source: Source? = nil, in topic: Topic? = nil) -> StudyItem {
        let ref = source.map { SourceRef(sourceID: $0.id, pageIndex: 0, anchorIDs: ["p0.l1"], start: nil, end: nil, label: "p. 87") }
        let item = StudyItem(course: course, topicID: (topic ?? self.topic).id, kind: kind, status: .active, origin: .rules, prompt: prompt, answer: answer,
                             keyIdeas: keyIdeas, choices: choices, sourceRef: ref, now: clock.now)
        if let studiedDaysAgo {
            var memory = MemoryState()
            memory.state = .review
            memory.stability = stability
            memory.difficulty = 5
            memory.lastReview = clock.now.addingTimeInterval(-studiedDaysAgo * 86_400)
            memory.due = clock.now.addingTimeInterval(40 * 86_400)
            memory.reps = 3
            item.memory = memory
        }
        app.context.insert(item)
        course.items.append(item)
        app.save()
        return item
    }

    private func threeIdeas() {
        add(prompt: "What are pulled apart?", answer: "Sister chromatids", stability: 3)
        add(prompt: "What pulls them?", answer: "Spindle fibres", stability: 30)
        add(prompt: "Where do they go?", answer: "Opposite poles", stability: 90)
    }

    private func session(_ lines: [String] = []) throws -> (TeachSession, FakeListener) {
        let listener = FakeListener(lines)
        let plan = try XCTUnwrap(app.teachPlan(topicID: topic.id))
        return (TeachSession(app: app, plan: plan, ports: TeachPorts(makeListener: { listener })), listener)
    }

    private func until(_ what: String = "condition", _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            if ContinuousClock.now >= deadline { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func logs() -> [ReviewLog] { app.fetch(FetchDescriptor<ReviewLog>()) }

    func testThePlanReadsAnOptionsWordsAndLeavesOutDiagrams() throws {
        add(.mcq, prompt: "Which phase splits them?", answer: "x", choices: [Choice(text: "Anaphase", correct: true), Choice(text: "Prophase", correct: false)])
        add(.diagram, prompt: "Label it", answer: "Spindle")
        add(prompt: "What pulls them?", answer: "Spindle fibres")
        let plan = try XCTUnwrap(app.teachPlan(topicID: topic.id))
        XCTAssertEqual(Set(plan.ideas.map(\.label)), ["Which phase splits them? Anaphase.", "What pulls them? Spindle fibres."])
        XCTAssertEqual(plan.topicName, "Anaphase")
        XCTAssertEqual(plan.courseID, course.id)
    }

    func testTooLittleHasNoPlan() {
        add(prompt: "What pulls them?", answer: "Spindle fibres")
        XCTAssertNil(app.teachPlan(topicID: topic.id))
        XCTAssertNil(app.teachPlan(topicID: UUID()))
    }

    func testSayingItFillsTheNotesAndDoneChecksIt() async throws {
        threeIdeas()
        let (session, listener) = try session([FakeListener.wait])
        XCTAssertEqual(session.phase, .prompt)
        session.sayIt()
        try await until("listening") { session.phase == .listening }
        XCTAssertEqual(listener.turns.first?.endpoint, .teaching, "until Done, or two minutes")
        session.done()
        // Nothing was said: back to Cap's question, and the microphone goes off.
        try await until("the way back") { session.phase == .prompt }
        XCTAssertNotNil(session.note)
        XCTAssertTrue(listener.closed)
    }

    func testTheWordsAreCheckedAndCoverWhatTheyCover() async throws {
        threeIdeas()
        let (session, _) = try session(["The sister chromatids are pulled by the spindle fibres to opposite poles"])
        session.sayIt()
        try await until("the check") { session.phase == .check && !session.isRefining }
        XCTAssertEqual(session.coveredCount, 3)
        XCTAssertNil(session.firstMissing)
        XCTAssertEqual(session.liveHits.count, 3, "the notes, from the rules")
        XCTAssertNotNil(app.noticeLedger.taught[topic.id.uuidString], "he won't offer it again for a while")
        XCTAssertTrue(logs().isEmpty, "explaining records nothing by itself")
    }

    func testNothingSaidIsKept() async throws {
        threeIdeas()
        let words = "Something about the spindle fibres"
        let (session, _) = try session([words, "the words of the follow-up"])
        session.sayIt()
        try await until("the check") { session.phase == .check && !session.isRefining }
        session.askFollowUp()
        session.sayFollowUp()
        try await until("the follow-up's grade") { session.phase == .followUpDone && !session.followUpRefining }
        session.markFollowUp(hadIt: true)
        for log in logs() { XCTAssertNil(log.answer) }
        let data = app.defaults.dictionaryRepresentation().description
        XCTAssertFalse(data.contains(words))
    }

    func testAThinExplanationIsThePersonsToMarkWithoutAModel() async throws {
        threeIdeas()
        let (session, _) = try session(["Something about the spindle fibres, I think, and how the whole thing moves along"])
        session.sayIt()
        try await until("the check") { session.phase == .check && !session.isRefining }
        XCTAssertTrue(session.isSelfCheck)
        XCTAssertEqual(session.coveredCount, 1, "starts from what the rules found")
        let missing = try XCTUnwrap(session.firstMissing)
        session.toggle(missing)
        XCTAssertEqual(session.coveredCount, 2)
        session.toggle(missing)
        XCTAssertEqual(session.coveredCount, 1)
    }

    func testTheFollowUpIsTheWeakestMissedAndRecordsOneReview() async throws {
        threeIdeas()
        let weakest = try XCTUnwrap(app.teachPlan(topicID: topic.id)?.ideas.first)
        XCTAssertEqual(weakest.label, "What are pulled apart? Sister chromatids.", "the least stable, so the least remembered")
        let (session, _) = try session(["Something about the spindle fibres", "I'm not sure", "x"])
        session.sayIt()
        try await until("the check") { session.phase == .check && !session.isRefining }
        session.askFollowUp()
        XCTAssertEqual(session.phase, .followUp)
        XCTAssertEqual(session.followUp?.itemID, weakest.itemID)
        XCTAssertEqual(session.followUp?.prompt, "What are pulled apart?")
        session.typeFollowUp()
        XCTAssertEqual(session.phase, .followUpTyping)
        session.typedFollowUp("sister chromatids")
        session.doneFollowUp()
        try await until("the grade") { session.followUpRating != nil }
        XCTAssertEqual(session.followUpGrade?.verdict, .correct)
        XCTAssertEqual(logs().count, 1)
        XCTAssertEqual(logs().first?.itemID, weakest.itemID)
        XCTAssertNil(logs().first?.answer)
        XCTAssertNil(logs().first?.sessionID)
    }

    func testAFollowUpTheRulesCantJudgeIsThePersonsToSayOnce() async throws {
        threeIdeas()
        let (session, _) = try session(["Something about the spindle fibres"])
        session.sayIt()
        try await until("the check") { session.phase == .check && !session.isRefining }
        session.askFollowUp()
        session.typeFollowUp()
        session.typedFollowUp("the chromatids that got copied, I think")
        session.doneFollowUp()
        try await until("the grade") { session.phase == .followUpDone && !session.followUpRefining }
        XCTAssertEqual(session.followUpGrade?.mode, .selfCheck)
        XCTAssertTrue(logs().isEmpty, "nothing until the person says")
        session.markFollowUp(hadIt: true)
        session.markFollowUp(hadIt: false)
        XCTAssertEqual(logs().count, 1)
        XCTAssertEqual(logs().first?.rating, .good)
        XCTAssertEqual(logs().first?.gradedBy, "self")
    }

    func testTypingWhenThereIsNoMicrophone() async throws {
        threeIdeas()
        let listener = FakeListener()
        listener.failure = .microphoneDenied
        let plan = try XCTUnwrap(app.teachPlan(topicID: topic.id))
        let session = TeachSession(app: app, plan: plan, ports: TeachPorts(makeListener: { listener }))
        session.sayIt()
        try await until("typing") { session.phase == .typing }
        XCTAssertNotNil(session.note)
        session.typed("The sister chromatids and the spindle fibres and opposite poles")
        try await until("the notes") { session.liveHits.count == 3 }
        session.done()
        try await until("the check") { session.phase == .check && !session.isRefining }
        XCTAssertEqual(session.coveredCount, 3)
    }

    func testDoneWithNothingTypedStays() throws {
        threeIdeas()
        let (session, _) = try session()
        session.typeIt()
        session.typed("   ")
        session.done()
        XCTAssertEqual(session.phase, .typing)
    }

    func testAMissingIdeaBecomesAQuestionLinkedToItsSource() throws {
        let source = Source(course: course, kind: .scan, title: "Textbook", status: .ready, now: clock.now)
        app.context.insert(source)
        course.sources.append(source)
        let lines = [TextLine(id: "p0.l1", text: "Sister chromatids separate in anaphase.", box: nil)]
        app.context.insert(SourcePage(source: source, pageIndex: 0, label: "87", text: "", lines: lines))
        let parent = add(prompt: "What are pulled apart?", answer: "Sister chromatids", source: source)
        add(prompt: "What pulls them?", answer: "Spindle fibres")
        let idea = try XCTUnwrap(app.teachPlan(topicID: topic.id)?.ideas.first { $0.itemID == parent.id })
        let made = try XCTUnwrap(app.addMissingIdea(idea, topicID: topic.id))
        XCTAssertEqual(made.kind, .recall)
        XCTAssertEqual(made.status, .active)
        XCTAssertEqual(made.topicID, topic.id)
        XCTAssertEqual(made.prompt, "What are pulled apart?", "it asks what its question asked")
        XCTAssertEqual(made.answer, "Sister chromatids")
        XCTAssertEqual(made.keyIdeas.map(\.label), ["Sister chromatids"])
        XCTAssertEqual(made.sourceRef?.sourceID, source.id)
        XCTAssertEqual(made.sourceRef?.anchorIDs, ["p0.l1"])
        XCTAssertEqual(made.memory, .new)
    }

    func testAddingTheMissingIdeaHappensOnce() async throws {
        threeIdeas()
        let (session, _) = try session(["Something about the spindle fibres"])
        session.sayIt()
        try await until("the check") { session.phase == .check && !session.isRefining }
        session.askFollowUp()
        let before = course.liveItems.count
        session.addMissingIdea()
        session.addMissingIdea()
        XCTAssertEqual(course.liveItems.count, before + 1)
        XCTAssertEqual(session.addedIdea, "What are pulled apart?")
    }

    func testClosingTurnsTheMicrophoneOff() async throws {
        threeIdeas()
        let (session, listener) = try session([FakeListener.wait])
        session.sayIt()
        try await until("listening") { session.phase == .listening }
        session.close()
        XCTAssertTrue(listener.closed)
    }

    func testTheHarnessMockAnswersWithThePlansOwnIdeas() async throws {
        threeIdeas()
        let plan = try XCTUnwrap(app.teachPlan(topicID: topic.id))
        let subject = plan.subject(level: nil)
        let request = GradeRequest(kind: subject.kind, level: nil, prompt: subject.prompt, modelAnswer: subject.modelAnswer, keyIdeas: subject.keyIdeas,
                                   response: "It's the spindle fibres", sourceExcerpt: nil)
        let response = try await MockRelayTransport(latencyScale: 0).grade(request)
        XCTAssertEqual(response.hits.map(\.ideaId), plan.ideas.filter { $0.label.contains("Spindle fibres") }.map(\.id))
        XCTAssertEqual(response.missing.count, 2)
        let outcome = AIRouter.outcome(from: response, subject: subject, answer: "It's the spindle fibres",
                                       local: LocalGrader.grade(subject, answer: .text("It's the spindle fibres")))
        XCTAssertEqual(outcome.hitIdeaIDs.count, 1, "the ideas survive the router")
    }

    // MARK: The card on Today

    private func strongTopic() {
        add(prompt: "One?", answer: "Sister chromatids")
        add(prompt: "Two?", answer: "Spindle fibres")
        add(prompt: "Three?", answer: "Opposite poles")
    }

    func testTheOfferReachesTheCardAndLeadsToTheCover() throws {
        strongTopic()
        let inputs = app.noticeInputs()
        XCTAssertEqual(inputs.teachOffers.map(\.topicID), [topic.id])
        let notices = NoticeEngine(inputs).candidates().filter { $0.kind == .teachBack }
        XCTAssertEqual(notices.map(\.id), [NoticeEngine.teachID(topic.id)])
        XCTAssertFalse(try XCTUnwrap(notices.first).notifiable, "an extra: never a notification")
        let card = NoticeContent.card(try XCTUnwrap(notices.first), firstName: "", now: clock.now, calendar: cal)
        XCTAssertEqual(card.title, "You know anaphase well", "no question over \"Teach Cap\"")
        XCTAssertNil(card.cost)
        XCTAssertFalse(card.title.contains("%") || card.detail.contains("%"), "no percentage")
        let action = try XCTUnwrap(card.action)
        XCTAssertEqual(action.title, "Teach Cap")
        app.perform(action)
        XCTAssertEqual(app.router.cover, .teach(topicID: topic.id))
        XCTAssertNotNil(app.noticeLedger.acted[NoticeEngine.teachID(topic.id)])
    }

    func testAKindSwitchedOffDealsNoCard() {
        strongTopic()
        app.setNoticeKind(.teachBack, on: false)
        XCTAssertFalse(NoticeEngine(app.noticeInputs()).candidates().contains { $0.kind == .teachBack })
    }

    func testAfterTeachingItIsNotOffered() {
        strongTopic()
        XCTAssertFalse(app.noticeInputs().teachOffers.isEmpty)
        app.noteTopicTaught(topic.id)
        XCTAssertTrue(app.noticeInputs().teachOffers.isEmpty)
        clock.now = cal.adding(days: 15, to: clock.now)
        // Fifteen days on, it's been long enough, though these questions have faded a little.
        XCTAssertNil(app.noticeLedger.taught[topic.id.uuidString].flatMap { cal.dayDistance(from: $0, to: clock.now) < TeachPlanner.offerQuietDays ? $0 : nil })
    }

    func testWhatLastsInTheLedgerIsAMonth() {
        var ledger = NoticeLedger()
        ledger.day = "2026-10-01"
        ledger.taught = ["a": EngineTest.date(2026, 10, 1, 9, in: cal), "b": EngineTest.date(2026, 8, 1, 9, in: cal)]
        let rolled = ledger.rolled(to: cal.dayKey(for: EngineTest.date(2026, 10, 2, 9, in: cal)), now: EngineTest.date(2026, 10, 2, 9, in: cal), calendar: cal)
        XCTAssertEqual(Array(rolled.taught.keys), ["a"])
        let data = try! JSONEncoder.cramless.encode(rolled)
        XCTAssertEqual(try! JSONDecoder.cramless.decode(NoticeLedger.self, from: data).taught.keys.first, "a")
    }
}
