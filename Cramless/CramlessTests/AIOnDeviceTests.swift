import FoundationModels
import XCTest
@testable import Cramless

/// The on-device tier with a scripted model: the mapping re-checks everything the model says, the runner never
/// throws, the budget and the language gate keep prompts the model can't read away from it, and the schemas build.
/// No test here reaches the real model (the simulator has none).
@MainActor
final class AIOnDeviceTests: XCTestCase {

    private func app(_ steps: [ScriptedOnDeviceBackend.Step]) -> (AppModel, ScriptedOnDeviceBackend) {
        let app = AITestSupport.makeApp(mode: .local)
        let backend = ScriptedOnDeviceBackend(steps)
        app.ai.probe = FixedOnDeviceProbe(.ready)
        app.ai.onDevice = backend
        app.ai.resetUsage()
        return (app, backend)
    }

    private let pageAnswer = #"""
    {"topics": ["Phases of mitosis", "Cytokinesis"],
     "questions": [
       {"kind": "multipleChoice", "topic": "Phases of mitosis", "prompt": "In which phase do chromosomes line up at the equator?",
        "answer": "Metaphase", "keyIdeas": [], "wrongChoices": ["Prophase", "Anaphase", "Telophase"], "clozeSentence": "", "lines": ["L10", "L14", "L18"]},
       {"kind": "fillIn", "topic": "Cytokinesis", "prompt": "Fill in the key term.", "answer": "Cytokinesis",
        "keyIdeas": [], "wrongChoices": [], "clozeSentence": "____ is the division of the cytoplasm.", "lines": ["L40"]},
       {"kind": "recall", "topic": "Phases of mitosis", "prompt": "What happens in prophase?",
        "answer": "Chromosomes condense and become visible, and the nuclear envelope breaks down.",
        "keyIdeas": [{"label": "Chromosomes condense", "terms": ["condense", "become visible"]}, {"label": "Envelope breaks down", "terms": ["breaks down"]}],
        "wrongChoices": [], "clozeSentence": "", "lines": ["9", "L13", "L17", "L21", "L25"]},
       {"kind": "flashcard", "topic": "Cytokinesis", "prompt": "Cytokinesis", "answer": "The division of the cytoplasm.",
        "keyIdeas": [], "wrongChoices": [], "clozeSentence": "", "lines": ["L40"]},
       {"kind": "multipleChoice", "topic": "Phases of mitosis", "prompt": "Bad question with one wrong option", "answer": "Metaphase",
        "keyIdeas": [], "wrongChoices": ["Prophase"], "clozeSentence": "", "lines": ["L10"]},
       {"kind": "flashcard", "topic": "Mitosis", "prompt": "Meiosis", "answer": "Makes four sex cells.",
        "keyIdeas": [], "wrongChoices": [], "clozeSentence": "", "lines": ["L99"]}
     ]}
    """#

    // MARK: Generation

    func testOnDeviceGenerationMapsAndChecksTheModelsQuestions() async throws {
        let (app, backend) = app([.json(pageAnswer)])
        let outcome = await app.ai.generateSet(AITestSupport.sampleInput)
        XCTAssertEqual(outcome.origin, .onDevice)
        XCTAssertEqual(outcome.checkedBy, .onDevice)
        XCTAssertEqual(backend.callCount, 1)
        // The model's choice questions are never kept as choices (measured on the real model: its wrong options
        // can be true per the page); a short one stays as a flashcard, with the page's line ids as references.
        let converted = try XCTUnwrap(outcome.items.first { $0.prompt == "In which phase do chromosomes line up at the equator?" })
        XCTAssertEqual(converted.kind, .flashcard)
        XCTAssertEqual(converted.answer, "Metaphase")
        XCTAssertEqual(converted.anchors, ["p0.l9", "p0.l13", "p0.l17"])
        // Multiple choice comes from the rules, merged after the model's questions.
        let mcq = try XCTUnwrap(outcome.items.first { $0.kind == .mcq })
        XCTAssertTrue(mcq.id.hasPrefix("r"), "the rules' question, not the model's")
        let cloze = try XCTUnwrap(outcome.items.first { $0.kind == .cloze })
        XCTAssertEqual(cloze.cloze?.text, "{{Cytokinesis}} is the division of the cytoplasm.")
        let recall = try XCTUnwrap(outcome.items.first { $0.kind == .recall })
        XCTAssertEqual(recall.anchors.first, "p0.l8", "a bare number is read as a line reference")
        // No choice question from the model survives as one; a made-up line is dropped with a reason.
        XCTAssertFalse(outcome.items.contains { $0.kind == .mcq && !$0.id.hasPrefix("r") })
        XCTAssertTrue(outcome.dropped.contains { $0.item.prompt == "Meiosis" && $0.reason.contains("isn't on your page") })
        XCTAssertEqual(app.ai.usage.used(.scans), 1)
        // The model was told the page's lines and nothing else.
        let prompt = try XCTUnwrap(backend.requests.first?.prompt)
        XCTAssertTrue(prompt.contains("L4: Mitosis is the process by which a single eukaryotic cell divides to produce two"))
    }

    func testFewModelQuestionsAreToppedUpByTheRules() async {
        let one = #"{"topics": [], "questions": [{"kind": "flashcard", "topic": "", "prompt": "Cytokinesis", "answer": "The division of the cytoplasm.", "keyIdeas": [], "wrongChoices": [], "clozeSentence": "", "lines": ["L40"]}]}"#
        let (app, _) = app([.json(one)])
        let outcome = await app.ai.generateSet(AITestSupport.sampleInput)
        XCTAssertEqual(outcome.origin, .onDevice)
        XCTAssertFalse(outcome.fellBack)
        XCTAssertEqual(outcome.items.first?.prompt, "Cytokinesis", "the model's question comes first")
        XCTAssertGreaterThan(outcome.items.count, 1, "the rules add what they do reliably")
        XCTAssertEqual(Set(outcome.items.map { Lexicon.normalizedAnswer($0.prompt) }).count, outcome.items.count, "no repeats")
        XCTAssertEqual(app.ai.usage.used(.scans), 1)
    }

    func testNothingUsableFromTheModelFallsBackToTheRules() async {
        let madeUp = #"{"topics": [], "questions": [{"kind": "flashcard", "topic": "", "prompt": "Meiosis", "answer": "Makes four sex cells.", "keyIdeas": [], "wrongChoices": [], "clozeSentence": "", "lines": ["L99"]}]}"#
        let (app, _) = app([.json(madeUp)])
        let outcome = await app.ai.generateSet(AITestSupport.sampleInput)
        XCTAssertEqual(outcome.origin, .rules)
        XCTAssertTrue(outcome.fellBack)
        XCTAssertEqual(outcome.note, "Your iPhone's AI couldn't write these, so they're basic questions from the offline rules.")
        XCTAssertEqual(app.ai.usage.used(.scans), 0, "a run that gave nothing usable isn't counted")
    }

    func testModelOutputFiltersFromTheRealModelRuns() {
        // Patterns measured with scripts/fm_live/run.sh on the system model.
        XCTAssertTrue(OnDeviceGeneration.hasNegativeStem("Which of the following is NOT a phase of mitosis?"))
        XCTAssertFalse(OnDeviceGeneration.hasNegativeStem("Which phase comes right before cytokinesis?"))
        XCTAssertEqual(OnDeviceGeneration.blankWord(sentence: "During prophase, chromosomes ____.",
                                                    answer: "Chromosomes condense during prophase."), "condense")
        XCTAssertNil(OnDeviceGeneration.clozeText(sentence: "Chromosomes line up at the equator of the cell.",
                                                  answer: "Chromosomes line up at the equator of the cell."),
                     "a blank that is the whole sentence tests nothing")
        let restated = OnDeviceGeneration.groundedIdeas([KeyIdea(id: "k1", label: "The four main phases of mitosis", terms: [])],
                                                        answer: "The four main phases of mitosis are prophase, metaphase, anaphase, and telophase.",
                                                        prompt: "What are the four main phases of mitosis?")
        XCTAssertEqual(restated.map(\.label), ["prophase", "metaphase", "anaphase", "telophase"])
        let vague = OnDeviceGeneration.groundedIdeas([KeyIdea(id: "k1", label: "Role", terms: ["role"])],
                                                     answer: "Sister chromatids are pulled to opposite poles.",
                                                     prompt: "What is the role of sister chromatids?")
        XCTAssertFalse(vague.isEmpty)
        XCTAssertFalse(vague.contains { $0.label == "Role" })
    }

    func testNotEnglishNeverReachesTheModel() async {
        let (app, backend) = app([.json(pageAnswer)])
        let lines = ["La mitosis es el proceso por el cual una célula se divide en dos células hijas idénticas.",
                     "Durante la mitosis el material genético se copia y se reparte por igual entre los dos núcleos."]
            .enumerated().map { TextLine(id: "p0.l\($0.offset)", text: $0.element, box: nil) }
        let input = GenerationInput(course: "Bio", sourceTitle: "Apuntes", pages: [PageText(index: 0, label: "1", lines: lines)])
        _ = await app.ai.generateSet(input)
        XCTAssertEqual(backend.callCount, 0)
    }

    // MARK: The runner

    struct SlowCall: OnDeviceCall {
        typealias Output = FMCards
        static let kind = OnDeviceCallKind.cards
        static let instructions = "Test."
        static let schemaTokens = 10
        static let responseTokens = 10
        static let timeout = Duration.milliseconds(200)
        var prompt: String
    }

    func testRunnerNeverThrows() async {
        let budget = OnDeviceBudget()
        let ok = await OnDeviceRunner.run(SlowCall(prompt: "x"), on: ScriptedOnDeviceBackend([.json(#"{"cards":[]}"#)]), budget: budget)
        XCTAssertEqual(ok, FMCards(cards: []))
        let failed = await OnDeviceRunner.run(SlowCall(prompt: "x"), on: ScriptedOnDeviceBackend([.failure(URLError(.badServerResponse))]), budget: budget)
        XCTAssertNil(failed)
        let garbage = await OnDeviceRunner.run(SlowCall(prompt: "x"), on: ScriptedOnDeviceBackend([.json("not json")]), budget: budget)
        XCTAssertNil(garbage)
        let start = Date()
        let hung = await OnDeviceRunner.run(SlowCall(prompt: "x"), on: ScriptedOnDeviceBackend([.hang]), budget: budget)
        XCTAssertNil(hung)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3, "the timeout ends a call that never answers")
    }

    func testPromptTooLongIsNeverSent() async {
        let backend = ScriptedOnDeviceBackend([.json(#"{"cards":[]}"#)])
        let long = String(repeating: "chromosome ", count: 5000)
        let result = await OnDeviceRunner.run(SlowCall(prompt: long), on: backend, budget: OnDeviceBudget())
        XCTAssertNil(result)
        XCTAssertEqual(backend.callCount, 0)
    }

    // MARK: Budget and language

    func testBudgetChunksKeepLinesWholeAndInOrder() {
        let budget = OnDeviceBudget(contextSize: 4096)
        let lines = (0..<400).map { TextLine(id: "p0.l\($0)", text: "Line \($0): the spindle fibres attach to the centromeres in metaphase.", box: nil) }
        let chunks = budget.chunks(lines, limit: 600, render: OnDevicePageCall.render)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.flatMap { $0 }.map(\.id), lines.map(\.id))
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.reduce(0) { $0 + OnDeviceBudget.estimateTokens(OnDevicePageCall.render($1)) + 1 }, 600)
        }
        XCTAssertEqual(OnDeviceBudget(contextSize: 0).contextSize, 4096, "a size that can't be right reads as the default")
        XCTAssertEqual(budget.chunks([TextLine(id: "x", text: String(repeating: "a", count: 9000), box: nil)], limit: 100,
                                     render: OnDevicePageCall.render).count, 0, "a line too long alone is skipped")
    }

    func testLanguageGate() {
        func verdict(_ text: String) -> OnDeviceLanguageGate.Verdict {
            OnDeviceLanguageGate.verdict(for: text, supportsLocale: { $0.language.languageCode?.identifier == "en" })
        }
        XCTAssertEqual(verdict("During mitosis the chromosomes condense and the nuclear envelope breaks down."), .supported)
        XCTAssertEqual(verdict("The Δv of the rocket depends on the exhaust speed and the mass ratio of the stages."), .supported)
        XCTAssertEqual(verdict("12"), .tooShort)
        XCTAssertEqual(verdict("מיטוזה היא חלוקת תא שבה נוצרים שני תאים זהים"), .foreignScript)
        XCTAssertEqual(verdict("Митоз — это деление клетки на две одинаковые дочерние клетки."), .foreignScript)
        XCTAssertEqual(verdict("La mitosis es el proceso por el cual una célula se divide en dos células hijas idénticas."), .notEnglish("es"))
        XCTAssertEqual(OnDeviceLanguageGate.verdict(for: "During mitosis the chromosomes condense and become visible.",
                                                    supportsLocale: { _ in false }), .unsupportedByModel)
    }

    // MARK: Mapping the other jobs

    func testGradeMappingMarksOnlyVerbatimQuotes() {
        let subject = GradeSubject(item: AITestSupport.fixtureItem("i1"))
        let answer = "So the body can grow and repair tissue, making two identical cells."
        let local = LocalGrader.grade(subject, answer: .text(answer))
        let output = FMGrade(ideas: [FMIdeaCheck(id: "K1", present: true, quote: "grow and repair tissue"),
                                     FMIdeaCheck(id: "K2", present: true, quote: "cells that are the same"),
                                     FMIdeaCheck(id: "K3", present: false, quote: "")],
                             feedback: "Good: growth, repair and identical cells.", fix: "Add the chromosome number.")
        let outcome = OnDeviceGrading.outcome(from: output, subject: subject, answer: answer, local: local)!
        XCTAssertEqual(outcome.gradedBy, .onDevice)
        XCTAssertEqual(outcome.hitIdeaIDs, ["k1", "k2"])
        // K2's quote isn't in the answer: the offline grader's own mark for it stands in.
        XCTAssertEqual(AITestSupport.marked(outcome, in: answer), ["grow and repair tissue", "identical"])
        XCTAssertGreaterThan(outcome.confidence, 0.8, "the model and the rules agree")

        let disagree = FMGrade(ideas: [FMIdeaCheck(id: "K1", present: false, quote: ""), FMIdeaCheck(id: "K2", present: false, quote: ""),
                                       FMIdeaCheck(id: "K3", present: true, quote: "the same chromosomes")], feedback: "", fix: "")
        let unsure = OnDeviceGrading.outcome(from: disagree, subject: subject, answer: answer, local: local)!
        XCTAssertLessThan(unsure.confidence, 0.6)
        // K3's quote isn't in the answer, and the rules didn't find it: it isn't counted and never marked. The
        // rules' own evidence for K1 and K2 still stands.
        XCTAssertFalse(unsure.hitIdeaIDs.contains("k3"))
        XCTAssertFalse(unsure.marks.contains { $0.ideaID == "k3" }, "a quote that isn't in the answer is never marked")
        XCTAssertEqual(unsure.hitIdeaIDs, local.hitIdeaIDs)
        XCTAssertEqual(unsure.feedback, local.feedback, "the words come from the hits, the same as the rules'")
        XCTAssertFalse(outcome.feedback.contains("K1"), "the model's prose (with its internal numbers) is never shown")
    }

    func testTutorMappingNeedsAQuoteFromThePassages() {
        let passages = [TutorSource(id: "s1", title: "Biology textbook", label: "Textbook p. 87",
                                    text: "After mitosis, cytokinesis takes place. This is the division of the cytoplasm.")]
        let good = FMTutorReply(covered: true, reply: "Cytokinesis splits the cytoplasm after mitosis.", passages: [1],
                                quotes: ["This is the division of the cytoplasm."])
        XCTAssertEqual(OnDeviceTutoring.reply(from: good, passages: passages)?.quotes.first?.quote, "This is the division of the cytoplasm.")
        let invented = FMTutorReply(covered: true, reply: "It happens in plants.", passages: [1], quotes: ["Cytokinesis only happens in plants."])
        XCTAssertNil(OnDeviceTutoring.reply(from: invented, passages: passages))
        let uncovered = FMTutorReply(covered: false, reply: "Not covered.", passages: [], quotes: [])
        XCTAssertNil(OnDeviceTutoring.reply(from: uncovered, passages: passages))
    }

    func testOnDeviceTutorAnswersShortQuestionsWithCheckedCitations() async throws {
        let reply = #"{"covered": true, "reply": "In anaphase the sister chromatids are pulled to opposite poles. What do they become?", "passages": [1], "quotes": ["Anaphase: Sister chromatids are pulled to opposite poles of the cell."]}"#
        let (app, backend) = app([.json(reply)])
        let input = TutorInput(messages: [TutorMessage(role: .user, text: "What happens in anaphase?")], course: nil,
                               material: AITestSupport.material)
        let answered = await app.ai.tutorReply(input)
        let outcome = try XCTUnwrap(answered)
        XCTAssertEqual(outcome.origin, .onDevice)
        XCTAssertEqual(outcome.citations.first?.label, "Textbook p. 87")
        XCTAssertEqual(backend.requests.first?.kind, .tutor)
        XCTAssertTrue(backend.requests.first?.prompt.contains("Mode: hints first") ?? false)
        XCTAssertEqual(app.ai.usage.used(.tutor), 1)
    }

    func testLectureSectionsCanBeRewrittenOnDeviceButKeepTheirTimes() async throws {
        let section = #"{"title": "Prophase", "bullets": ["The chromatin condenses and chromosomes become visible under the microscope."]}"#
        let (app, _) = app(Array(repeating: .json(section), count: 1) + Array(repeating: .failure(OnDeviceError.unusable), count: 10))
        let outcome = await app.ai.lectureNotes(LectureInput(course: "Bio 101", title: "Lecture 6: Cell division",
                                                             segments: AITestSupport.lectureSegments, flags: []))
        XCTAssertEqual(outcome.origin, .onDevice)
        XCTAssertEqual(outcome.notes.origin, "onDevice")
        let local = LocalLectureNotes.make(title: "Lecture 6: Cell division", segments: AITestSupport.lectureSegments, flags: [])
        XCTAssertEqual(outcome.notes.sections.map(\.start), local.sections.map(\.start))
        XCTAssertEqual(outcome.notes.sections.first?.bullets, ["The chromatin condenses and chromosomes become visible under the microscope."])
    }

    // MARK: The device and the schemas

    func testTheRealProbeNeverClaimsTheSimulatorsModel() {
        XCTAssertEqual(SystemOnDeviceProbe(allowed: false).capability().availability, .unavailable(.notChecked))
        #if targetEnvironment(simulator)
        XCTAssertEqual(SystemOnDeviceProbe(allowed: true).capability().availability, .unavailable(.simulator))
        #endif
        XCTAssertFalse(AIBuild.privateCloudEnabled, "Private Cloud Compute stays dormant without the entitlement")
    }

    func testSchemasBuild() {
        // Building each schema is where a duplicated type name would throw on a device.
        let schemas: [GenerationSchema] = [FMPageQuestions.generationSchema, FMGrade.generationSchema, FMTutorReply.generationSchema,
                                           FMLectureSection.generationSchema, FMCards.generationSchema]
        for schema in schemas { XCTAssertFalse(String(describing: schema).isEmpty) }
    }
}
