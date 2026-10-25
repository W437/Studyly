import XCTest
@testable import Cramless

/// The tutor: retrieval over the person's material, the offline tutor, and the router's stream with citations
/// mapped through the passages sent.
@MainActor
final class TutorTests: XCTestCase {

    private let retriever = LocalRetriever(material: AITestSupport.material)

    // MARK: Retrieval

    func testRetrieverFindsThePassageAndLabelsIt() throws {
        let hit = try XCTUnwrap(retriever.search("What happens in anaphase?").first)
        XCTAssertTrue(hit.passage.text.contains("Sister chromatids are pulled to opposite poles"), hit.passage.text)
        XCTAssertEqual(hit.passage.label, "Textbook p. 87")
        XCTAssertEqual(hit.passage.sourceID, AITestSupport.textbookID)
        XCTAssertEqual(hit.passage.pageIndex, 0)
        let lecture = try XCTUnwrap(retriever.search("metaphase plate").first)
        XCTAssertEqual(lecture.passage.label, "Lecture 6 · 07:40")
        XCTAssertEqual(lecture.passage.start, 460)
    }

    func testRetrieverForgivesATypoAndIgnoresQuestionWords() throws {
        XCTAssertEqual(retriever.queryTerms("what does cytokenesis divide?"), ["cytokinesis", "divid"])
        XCTAssertEqual(retriever.queryTerms("What's the difference between mitosis and cytokinesis?"), ["mitosis", "cytokinesis"])
        XCTAssertTrue(retriever.search("What is photosynthesis?").isEmpty)
        XCTAssertEqual(LocalRetriever.pageLabel(title: "Week 5 slides", kind: .pdf, page: "11"), "Slides p. 11")
        XCTAssertEqual(LocalRetriever.pageLabel(title: "Chem notes: unit 2", kind: .text, page: "3"), "Chem notes p. 3")
    }

    // MARK: The offline tutor

    private func reply(_ question: String, _ mode: TutorMode, context: TutorContext? = nil) -> LocalTutor.Reply {
        let asked = context.map { "\($0.itemPrompt) \($0.expected) \(question)" } ?? question
        return LocalTutor.reply(question: question, mode: mode, hits: retriever.search(asked), context: context,
                                terms: retriever.weightedTerms(asked))
    }

    func testExplainQuotesTheNotesVerbatim() {
        let r = reply("What's the difference between mitosis and cytokinesis?", .explain)
        XCTAssertTrue(r.grounded)
        XCTAssertTrue(r.text.contains("After mitosis, cytokinesis takes place. This is the division of the cytoplasm"), r.text)
        let all = retriever.passages.map(\.text)
        for quote in r.quotes { XCTAssertTrue(all.contains { $0.contains(quote.text) }, quote.text) }
    }

    func testHintsAskInsteadOfTelling() {
        let r = reply("What's the difference between mitosis and cytokinesis?", .hints)
        XCTAssertTrue(r.grounded)
        XCTAssertTrue(r.text.contains("____"), r.text)
        XCTAssertTrue(r.text.hasSuffix("What goes in the gap?"))
        XCTAssertFalse(r.text.contains("division of the cytoplasm"), "the hint must leave the key word out")
    }

    func testGroundedOrSilent() {
        let r = reply("What is photosynthesis?", .explain)
        XCTAssertFalse(r.grounded)
        XCTAssertEqual(r.text, LocalTutor.notCovered)
        XCTAssertTrue(r.quotes.isEmpty)
        XCTAssertEqual(reply("thanks!", .explain).text, LocalTutor.smallTalk)
    }

    func testNoEssaysNoHumanizing() {
        for request in ["Write my essay on mitosis", "can you humanize this paragraph", "make it sound like I wrote it",
                        "help me bypass the AI detector"] {
            XCTAssertTrue(TutorPolicy.isRefused(request), request)
            XCTAssertEqual(reply(request, .explain).text, TutorPolicy.refusal)
        }
        XCTAssertFalse(TutorPolicy.isRefused("How do I plan an essay about mitosis?"))
    }

    func testExplainMyMistake() {
        let context = TutorContext(itemPrompt: "Describe what happens in anaphase.", expected: "The sister chromatids are pulled to opposite poles",
                                   given: "The nuclear envelope forms again")
        let r = reply("", .explain, context: context)
        XCTAssertTrue(r.grounded)
        XCTAssertTrue(r.text.hasPrefix("You wrote “The nuclear envelope forms again”"), r.text)
        XCTAssertTrue(r.text.contains("Sister chromatids are pulled to opposite poles of the cell"), r.text)
    }

    // MARK: The router

    private func collect(_ app: AppModel, _ input: TutorInput) async -> (updates: [TutorUpdate], outcome: TutorOutcome?) {
        var updates: [TutorUpdate] = []
        var outcome: TutorOutcome?
        for await update in app.ai.tutor(input) {
            updates.append(update)
            if case .finished(let o) = update { outcome = o }
        }
        return (updates, outcome)
    }

    private func input(_ question: String, context: TutorContext? = nil) -> TutorInput {
        TutorInput(messages: [TutorMessage(role: .user, text: question)], course: "Bio 101", material: AITestSupport.material,
                   context: context)
    }

    func testLocalModeAnswersFromTheRulesWithCitations() async throws {
        let app = AITestSupport.makeApp(mode: .local)
        app.settings.tutorMode = .explain
        let (updates, outcome) = await collect(app, input("What happens in anaphase?"))
        XCTAssertEqual(updates.first, .started(origin: .rules))
        let o = try XCTUnwrap(outcome)
        XCTAssertEqual(o.origin, .rules)
        XCTAssertTrue(o.grounded)
        XCTAssertEqual(updates.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(), o.text)
        let citation = try XCTUnwrap(o.citations.first)
        XCTAssertEqual(citation.sourceID, AITestSupport.textbookID)
        XCTAssertEqual(citation.pageIndex, 0)
        XCTAssertEqual(citation.label, "Textbook p. 87")
        // Local mode has no cloud: nothing to suggest.
        XCTAssertNil(o.suggestion)
    }

    func testMockCloudStreamsTheScriptAndMapsCitations() async throws {
        let app = AITestSupport.makeApp(mode: .mock)
        app.settings.tutorMode = .explain
        let (updates, outcome) = await collect(app, input("What's the difference between mitosis and cytokinesis?"))
        let o = try XCTUnwrap(outcome)
        XCTAssertEqual(o.origin, .cloud)
        XCTAssertEqual(updates.first, .started(origin: .cloud))
        XCTAssertTrue(o.text.hasPrefix("Short version: mitosis splits the nucleus"), o.text)
        // Both of the script's quotes are in the person's material, so both become citations to the textbook.
        XCTAssertEqual(o.citations.count, 2)
        XCTAssertTrue(o.citations.allSatisfy { $0.sourceID == AITestSupport.textbookID && $0.label == "Textbook p. 87" })
        XCTAssertTrue(o.grounded)
    }

    func testCitationsNotInTheNotesAreDropped() {
        let passage = retriever.passages[0]
        XCTAssertNil(AIRouter.citation(sourceID: "s1", label: "Textbook p. 87", quote: "Mitosis happens only in plants.",
                                       sent: ["s1": passage], retriever: retriever, index: 0))
        XCTAssertNotNil(AIRouter.citation(sourceID: "s9", label: "?", quote: "Spindle fibres attach to the centromeres.",
                                          sent: ["s1": passage], retriever: retriever, index: 0))
    }

    func testMinorsGetHintsAndTheMinorFlag() async throws {
        let app = AITestSupport.makeApp(mode: .relay, consent: true, age: .teen)
        let transport = RecordingTransport()
        app.ai.transportOverride = transport
        app.settings.tutorMode = .explain
        let (_, outcome) = await collect(app, input("What's the difference between mitosis and cytokinesis?"))
        let request = try XCTUnwrap(transport.tutorRequests.first)
        XCTAssertTrue(request.minor)
        XCTAssertEqual(request.mode, .hints)
        XCTAssertEqual(outcome?.mode, .hints)
        XCTAssertFalse(request.sources.isEmpty)
        XCTAssertTrue(request.sources.allSatisfy { $0.label == "Textbook p. 87" || $0.label.hasPrefix("Lecture 6") })
    }

    func testCloudFailureBeforeAnyTextFallsBackQuietly() async throws {
        let app = AITestSupport.makeApp(mode: .mock)
        let (updates, outcome) = await collect(app, input("What happens in anaphase? #fail"))
        let o = try XCTUnwrap(outcome)
        XCTAssertEqual(o.origin, .rules)
        XCTAssertTrue(o.fellBack)
        XCTAssertEqual(updates.filter { if case .started = $0 { true } else { false } }.count, 1)
    }

    func testTheFallbackNoteOnlyBlamesTheCloudWhenItWasTried() async throws {
        // No consent: the cloud is never tried; this iPhone's model fails; the offline tutor answers, quietly.
        let app = AITestSupport.makeApp(mode: .relay, consent: false)
        app.ai.transportOverride = RecordingTransport()
        app.ai.probe = FixedOnDeviceProbe(.ready)
        app.ai.onDevice = ScriptedOnDeviceBackend([.failure(OnDeviceError.unusable)])
        let (_, outcome) = await collect(app, input("What happens in anaphase?"))
        let o = try XCTUnwrap(outcome)
        XCTAssertEqual(o.origin, .rules)
        XCTAssertTrue(o.fellBack)
        XCTAssertNil(o.note)
    }

    func testUncoveredQuestionsNeverReachAModel() async throws {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let transport = RecordingTransport()
        app.ai.transportOverride = transport
        let (_, outcome) = await collect(app, input("What is photosynthesis?"))
        XCTAssertEqual(outcome?.grounded, false)
        XCTAssertEqual(outcome?.text, LocalTutor.notCovered)
        XCTAssertTrue(transport.calls.isEmpty)
    }

    func testTutorQuotaReachedFallsBackAndFlags() async throws {
        let app = AITestSupport.makeApp(mode: .mock)
        let (_, outcome) = await collect(app, input("What happens in anaphase? #quota"))
        let o = try XCTUnwrap(outcome)
        XCTAssertEqual(o.origin, .rules)
        XCTAssertEqual(o.limitReached, .tutor)
        guard case .upgrade(.tutor, _) = o.suggestion else { return XCTFail("\(String(describing: o.suggestion))") }
    }
}
