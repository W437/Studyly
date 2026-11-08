import Foundation
import SwiftData
import SwiftUI
import XCTest
@testable import Cramless

/// Shared setup for the Ask, Settings and Squad tests: a private file store (the sample page copies its photo), an
/// app wired for tests (`AITestSupport.makeApp`), and Bio 101 with the sample textbook page and Lecture 6.
@MainActor
class AskTestCase: XCTestCase {
    var fileRoot: URL!
    private var previousLive: AppModel?

    override func setUp() async throws {
        try await super.setUp()
        previousLive = AppModel.live
        fileRoot = FileManager.default.temporaryDirectory.appending(path: "cramless-ask-\(UUID().uuidString)", directoryHint: .isDirectory)
        FileStore.rootOverride = fileRoot
    }

    override func tearDown() async throws {
        FileStore.rootOverride = nil
        try? FileManager.default.removeItem(at: fileRoot)
        AppModel.live = previousLive
        try await super.tearDown()
    }

    func makeApp(mode: AppConfig.AIMode = .local, consent: Bool = false, age: AppSettings.AgeBand = .adult,
                 level: AppSettings.Level? = .college) -> AppModel {
        let app = AITestSupport.makeApp(mode: mode, consent: consent, age: age, level: level)
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        app.clock = { now }
        return app
    }

    struct Bio {
        var course: Course
        var textbook: Source
        var lecture: Source
    }

    /// Bio 101: the sample textbook page (p. 87) and Lecture 6's transcript.
    @discardableResult
    func makeBio(_ app: AppModel) -> Bio {
        let course = Course(name: "Bio 101", now: app.now)
        app.context.insert(course)
        let textbook = SamplePage.makeSource(in: course, context: app.context, now: app.now)
        textbook.status = .ready
        let lecture = Source(course: course, kind: .lecture, title: "Lecture 6: Cell division", status: .ready, now: app.now)
        app.context.insert(lecture)
        course.sources.append(lecture)
        lecture.segments = AITestSupport.lectureSegments
        app.save()
        return Bio(course: course, textbook: textbook, lecture: lecture)
    }

    /// Waits (briefly) for a condition the main actor will make true.
    func eventually(_ timeout: TimeInterval = 3, _ condition: @escaping () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { try? await Task.sleep(for: .milliseconds(20)) }
    }
}

/// `AppModel+Ask`: threads, messages and saved citations, the stream through the tutor (mock, offline, refused,
/// stopped), cards from a chat becoming items, citations placed on their lines, and deleting.
@MainActor
final class AskAppModelTests: AskTestCase {

    // MARK: Threads and messages

    func testThreadsAreNewestFirstAndNamedByTheirFirstQuestion() {
        let app = makeApp()
        var clock = app.now
        app.clock = { clock }
        let first = app.startChat(courseID: nil)
        app.addQuestion("What is diffusion?", to: first)
        clock = clock.addingTimeInterval(60)
        let second = app.startChat(courseID: nil)
        app.addQuestion("What's the difference between mitosis and cytokinesis?", to: second)
        XCTAssertEqual(app.chatThreads().map(\.id), [second.id, first.id])
        XCTAssertEqual(first.title, "What is diffusion?")
        XCTAssertEqual(second.title, "Mitosis vs cytokinesis")
        // A later question doesn't rename the chat.
        app.addQuestion("And what about osmosis?", to: first)
        XCTAssertEqual(first.title, "What is diffusion?")
        XCTAssertNil(app.addQuestion("   ", to: first), "an empty question isn't added")
    }

    func testChatTitles() {
        XCTAssertEqual(AppModel.chatTitle(for: "what's the difference between anaphase I and anaphase II?"), "Anaphase I vs anaphase II")
        let long = AppModel.chatTitle(for: "Can you walk me through every single step of how the cell membrane controls what enters and leaves?")
        XCTAssertTrue(long.hasSuffix("…"), long)
        XCTAssertLessThanOrEqual(long.count, 46)
        XCTAssertEqual(AppModel.mistakeQuestion(given: " sex cells "), "I answered “sex cells”. What did I miss?")
        XCTAssertEqual(AppModel.mistakeQuestion(given: ""), "I didn't know this one. What's the answer?")
    }

    func testAnswersKeepTheirCitationsOriginAndOrderWithAFrozenClock() throws {
        let app = makeApp()
        let bio = makeBio(app)
        let thread = app.startChat(courseID: bio.course.id)
        app.addQuestion("What happens after mitosis?", to: thread)
        let citation = Citation(id: "c1", sourceID: bio.textbook.id, pageIndex: 0, start: nil,
                                quote: "After mitosis, cytokinesis takes place.", label: "Textbook p. 87")
        let outcome = TutorOutcome(text: "  Cytokinesis divides the cytoplasm.  ", citations: [citation], origin: .onDevice,
                                   model: "on-device", mode: .explain, grounded: true)
        let saved = try XCTUnwrap(app.saveAnswer(outcome, to: thread))
        XCTAssertEqual(saved.text, "Cytokinesis divides the cytoplasm.")
        XCTAssertEqual(saved.citations, [citation])
        XCTAssertEqual(saved.origin, "onDevice")
        app.addQuestion("Thanks!", to: thread)
        // The clock is frozen, yet the order holds.
        XCTAssertEqual(thread.sortedMessages.map(\.role), [.user, .assistant, .user])
        XCTAssertEqual(ChatEntry.entries(of: thread).map(\.origin), [nil, .onDevice, nil])
        XCTAssertNil(app.saveAnswer(TutorOutcome(text: " ", citations: [], origin: .rules, model: "", mode: .hints, grounded: false), to: thread))
    }

    func testTutorInputSendsTheChatAndCanRewordTheLastQuestion() {
        let app = makeApp()
        let bio = makeBio(app)
        let thread = app.startChat(courseID: bio.course.id)
        app.addQuestion("How many cells does meiosis make?", to: thread)
        app.saveAnswer(TutorOutcome(text: "Quick check: 2, 4 or 8?", citations: [], origin: .cloud, model: "m", mode: .explain, grounded: true), to: thread)
        app.addQuestion("4", to: thread)
        let plain = app.tutorInput(for: thread)
        XCTAssertEqual(plain.messages.map(\.text), ["How many cells does meiosis make?", "Quick check: 2, 4 or 8?", "4"])
        XCTAssertEqual(plain.course, "Bio 101")
        XCTAssertEqual(Set(plain.material.map(\.sourceID)), [bio.textbook.id, bio.lecture.id])
        let reworded = app.tutorInput(for: thread, lastQuestionAs: "Quick check: how many cells? My answer: 4")
        XCTAssertEqual(reworded.messages.last?.text, "Quick check: how many cells? My answer: 4")
        XCTAssertEqual(thread.sortedMessages.last?.text, "4", "the chat keeps what the person wrote")
    }

    // MARK: Streaming

    func testTheMockTutorStreamsAndTheAnswerIsSavedWithCheckedCitations() async throws {
        let app = makeApp(mode: .mock, consent: true)
        // The tutor's own path: Ask tries the assistant first, so this is the relay having no assistant (it falls back to the tutor).
        app.ai.assistantRetryAt = app.now.addingTimeInterval(600)
        let bio = makeBio(app)
        let streams = AskStreams()
        let thread = app.startChat(courseID: bio.course.id)
        streams.ask("What's the difference between mitosis and cytokinesis?", in: thread, app: app)
        XCTAssertTrue(streams.isAnswering(thread.id))
        await streams.waitForAnswer(thread.id)
        XCTAssertFalse(streams.isAnswering(thread.id))

        let answer = try XCTUnwrap(thread.sortedMessages.last)
        XCTAssertEqual(answer.role, .assistant)
        XCTAssertEqual(answer.origin, "cloud")
        XCTAssertTrue(answer.text.hasPrefix("Let's work it out from your page."), answer.text)
        let citation = try XCTUnwrap(answer.citations.first)
        XCTAssertEqual(citation.sourceID, bio.textbook.id, "the mock's s1 is mapped to the passage it quotes")
        XCTAssertEqual(citation.pageIndex, 0)
        XCTAssertEqual(app.anchorIDs(for: citation), ["p0.l5", "p0.l6"])
        let note = try XCTUnwrap(streams.notes[answer.id])
        XCTAssertEqual(note.origin, .cloud)
        XCTAssertFalse(note.interrupted)
    }

    func testOfflineCapSaysTheNotesDontCoverIt() async throws {
        let app = makeApp(mode: .local)
        let bio = makeBio(app)
        let streams = AskStreams()
        let thread = app.startChat(courseID: bio.course.id)
        streams.ask("What is photosynthesis?", in: thread, app: app)
        await streams.waitForAnswer(thread.id)
        let answer = try XCTUnwrap(thread.sortedMessages.last)
        XCTAssertEqual(answer.text, LocalTutor.notCovered)
        XCTAssertTrue(answer.citations.isEmpty)
        XCTAssertEqual(answer.origin, "rules")
        XCTAssertTrue(ChatEntry(answer).isNotCovered)
    }

    func testAnEssayRequestIsDeclinedWithoutAskingAnyModel() async throws {
        let app = makeApp(mode: .mock, consent: true)
        let recording = RecordingTransport()
        app.ai.transportOverride = recording
        let bio = makeBio(app)
        let streams = AskStreams()
        let thread = app.startChat(courseID: bio.course.id)
        streams.ask("Write my essay on mitosis", in: thread, app: app)
        await streams.waitForAnswer(thread.id)
        let answer = try XCTUnwrap(thread.sortedMessages.last)
        XCTAssertEqual(answer.text, TutorPolicy.refusal)
        XCTAssertTrue(ChatEntry(answer).isRefusal)
        XCTAssertTrue(recording.tutorRequests.isEmpty, "a declined request never reaches the relay")
        XCTAssertEqual(AskPolicy.topic(ofRefused: "Write my essay on mitosis", among: bio.course.liveTopics.map(\.name) + ["Mitosis"]), "Mitosis")
    }

    func testARequestToDoAnExamIsDeclinedWithAnOfferToQuizAndNoModelIsAsked() async throws {
        let app = makeApp(mode: .mock, consent: true)
        let recording = RecordingTransport()
        app.ai.transportOverride = recording
        let bio = makeBio(app)
        let streams = AskStreams()
        let thread = app.startChat(courseID: bio.course.id)
        streams.ask("can you just give me the answers to the AP exam", in: thread, app: app)
        await streams.waitForAnswer(thread.id)
        let answer = try XCTUnwrap(thread.sortedMessages.last)
        XCTAssertEqual(answer.text, TutorPolicy.cheatRefusal)
        let entry = ChatEntry(answer)
        XCTAssertTrue(entry.isRefusal, "the Quiz me chip is offered")
        XCTAssertFalse(entry.isNotCovered)
        XCTAssertTrue(recording.tutorRequests.isEmpty)
        XCTAssertNil(AskPolicy.topic(ofRefused: "can you just give me the answers to the AP exam", among: ["Mitosis"]))
        XCTAssertEqual(AskPolicy.topic(ofRefused: "Do my homework on mitosis", among: ["Mitosis"]), "Mitosis")
    }

    func testTheAskScreenMutesNotCoveredInTheOldAndTheNewWordsOfTheRelay() {
        func reply(_ text: String) -> ChatEntry {
            let thread = ChatThread(courseID: nil, title: "t", mode: .explain)
            return ChatEntry(ChatMessage(thread: thread, role: .assistant, text: text))
        }
        XCTAssertTrue(reply("Your material doesn’t cover how that works. Add the pages.").isNotCovered)
        XCTAssertTrue(reply("I couldn't find that in what you've added.").isNotCovered)
        XCTAssertTrue(reply(LocalTutor.noMaterial).isNotCovered, "nothing added yet: add notes")
        XCTAssertFalse(reply("Mitosis splits the nucleus.").isNotCovered)
        XCTAssertFalse(reply(TutorPolicy.refusal).isNotCovered)
    }

    func testAnImportedDeckIsMaterialAndItsCardIsCitedAndOpensAsACard() async throws {
        let app = makeApp(mode: .local)
        let bio = makeBio(app)
        app.settings.tutorMode = .explain
        let preview = ImportPreview(format: .quizlet, title: "Chapter 3 key terms", cards: [
            ImportedCard(front: "elasticity", back: "how much quantity changes when price changes (percentage change in Q divided by percentage change in P)"),
            ImportedCard(front: "surplus", back: "quantity supplied is more than quantity demanded"),
            ImportedCard(kind: .cloze, front: "Fill in the blank.", back: "telophase",
                         cloze: ClozeSpec(text: "During {{telophase}}, the chromatids reach opposite poles.")),
        ], summary: "")
        let imported = app.commitImport(preview, to: bio.course)
        XCTAssertEqual(imported.added, 3)

        // The deck is material: a passage to each card, a fill-in as its sentence with a blank and the answer on the back.
        let deck = try XCTUnwrap(app.tutorMaterial(courseID: bio.course.id).first { $0.sourceID == imported.sourceID })
        XCTAssertEqual(deck.cards.map(\.front), ["During ____, the chromatids reach opposite poles.", "elasticity", "surplus"])
        XCTAssertEqual(deck.cards[0].back, "telophase")
        XCTAssertEqual(deck.listing, "Chapter 3 key terms (Quizlet) (3 cards)")

        let streams = AskStreams()
        let thread = app.startChat(courseID: bio.course.id)
        streams.ask("How do I calculate elasticity?", in: thread, app: app)
        await streams.waitForAnswer(thread.id)
        let answer = try XCTUnwrap(thread.sortedMessages.last)
        XCTAssertTrue(answer.text.contains("percentage change in Q divided by percentage change in P"), answer.text)
        let citation = try XCTUnwrap(answer.citations.first)
        XCTAssertEqual(citation.sourceID, imported.sourceID)
        XCTAssertNil(citation.pageIndex)
        XCTAssertEqual(citation.label, "Deck: Chapter 3 key terms · card 2")

        // Opening it shows the card; it never points at a page the deck doesn't have.
        let group = try XCTUnwrap(CitationGroup.groups(answer.citations).first)
        XCTAssertFalse(group.isLecture)
        CitationOpener.open(group, app: app)
        guard case .deckCard(let sourceID, let quote, let label) = app.router.sheet else { return XCTFail("\(String(describing: app.router.sheet))") }
        XCTAssertEqual(sourceID, imported.sourceID)
        XCTAssertEqual(label, "Deck: Chapter 3 key terms · card 2")
        let found = try XCTUnwrap(app.deckCard(quoting: quote, in: sourceID, label: label))
        XCTAssertEqual(found.number, 2)
        XCTAssertEqual(found.card.front, "elasticity")
        XCTAssertEqual(app.anchorIDs(for: citation), [], "no lines to mark: a deck has none")
        // A card that has gone says so.
        app.router.dismissSheet()
        if let item = bio.course.items.first(where: { $0.prompt == "elasticity" }) { app.deleteItems([item.id]) }
        XCTAssertNil(app.deckCard(quoting: quote, in: sourceID))
    }

    func testTheCardScreenDrawsTheCardAndAGoneCardWithoutTrapping() throws {
        let app = makeApp(mode: .local)
        let bio = makeBio(app)
        let imported = app.commitImport(ImportPreview(format: .quizlet, title: "Chapter 3 key terms", cards: [
            ImportedCard(front: "elasticity", back: "percentage change in Q divided by percentage change in P", explanation: "Use the midpoint formula."),
        ], summary: ""), to: bio.course)
        // Drawn without a window: this only shows that the screen's body runs for a card that is there and for one that is not.
        func draw(_ quote: String) {
            let host = UIHostingController(rootView: NavigationStack { DeckCardView(sourceID: imported.sourceID, quote: quote) }.environment(app))
            host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
            host.loadViewIfNeeded()
            host.view.layoutIfNeeded()
            XCTAssertEqual(host.view.frame.width, 390)
        }
        draw("percentage change in Q divided by percentage change in P")
        draw("a quote of a card that was never there")
        let found = try XCTUnwrap(app.deckCard(quoting: "Use the midpoint formula.", in: imported.sourceID))
        XCTAssertEqual(found.card.note, "Use the midpoint formula.")
        XCTAssertEqual(found.card.text, "Front: elasticity Back: percentage change in Q divided by percentage change in P Note: Use the midpoint formula.")
    }

    func testTwoCardsWithTheSameWordsOpenTheCardTheCitationNames() throws {
        let app = makeApp(mode: .local)
        let bio = makeBio(app)
        // Cards are numbered in the order the Library lists them (cards imported together are listed by their fronts).
        let preview = ImportPreview(format: .quizlet, title: "Terms", cards: [
            ImportedCard(front: "Alpha cycle", back: "happens in the mitochondrial matrix"),
            ImportedCard(front: "Beta cycle", back: "happens in the mitochondrial matrix"),
        ], summary: "")
        let imported = app.commitImport(preview, to: bio.course)
        let quote = "happens in the mitochondrial matrix"
        XCTAssertEqual(app.deckCard(quoting: quote, in: imported.sourceID)?.number, 1, "by the words alone, the first")
        let second = try XCTUnwrap(app.deckCard(quoting: quote, in: imported.sourceID, label: "Deck: Terms · card 2"))
        XCTAssertEqual(second.number, 2, "the card the label numbers")
        XCTAssertEqual(second.card.front, "Beta cycle")
        // A label that numbers a card which doesn't hold the quote (the deck changed) falls back to the words.
        XCTAssertEqual(app.deckCard(quoting: "Alpha cycle", in: imported.sourceID, label: "Deck: Terms · card 2")?.number, 1)
        XCTAssertNil(app.deckCard(quoting: "a quote of a card that was never there", in: imported.sourceID, label: "Deck: Terms · card 1"))
    }

    // MARK: A course with only a deck

    func testACourseWithOnlyAnImportedDeckHasNotesCapCanRead() async throws {
        let app = makeApp(mode: .local)
        let econ = Course(name: "Econ 101", sortOrder: 0, now: app.now)
        app.context.insert(econ)
        let chem = Course(name: "Chem 110", sortOrder: 1, now: app.now)
        app.context.insert(chem)
        // Chem's exam is sooner, but it has nothing Cap can read; Econ has a deck.
        let quiz = Exam(course: chem, title: "Chem quiz", date: app.now.addingTimeInterval(2 * 86_400), now: app.now)
        app.context.insert(quiz)
        chem.exams.append(quiz)
        app.save()
        XCTAssertTrue(app.readableSources(courseID: econ.id).isEmpty)

        let imported = app.commitImport(ImportPreview(format: .quizlet, title: "Chapter 3 key terms", cards: [
            ImportedCard(front: "elasticity", back: "how much quantity changes when price changes"),
            ImportedCard(front: "surplus", back: "quantity supplied is more than quantity demanded"),
            ImportedCard(front: "law of demand", back: "when price goes up, quantity demanded goes down"),
        ], summary: ""), to: econ)
        XCTAssertEqual(app.readableSources(courseID: econ.id).map(\.id), [imported.sourceID], "the deck counts: not 'no notes yet'")
        XCTAssertEqual(app.readableSources(courseID: nil).map(\.id), [imported.sourceID])
        XCTAssertEqual(app.defaultChatCourseID, econ.id, "a new chat starts where Cap has something to read")

        // Starters from its cards, each one covered by them.
        let starters = await app.chatStarters(courseID: econ.id)
        XCTAssertFalse(starters.isEmpty, "\(starters)")
        XCTAssertTrue(starters.contains("What is elasticity?"), "\(starters)")
        let retriever = LocalRetriever(material: app.tutorMaterial(courseID: econ.id))
        for starter in starters { XCTAssertTrue(AskStarters.isCovered(starter, by: retriever), starter) }

        // With every card deleted the deck has nothing to read again.
        app.deleteItems(econ.liveItems.map(\.id))
        XCTAssertTrue(app.readableSources(courseID: econ.id).isEmpty)
    }

    func testStoppingKeepsWhatArrived() async throws {
        let app = makeApp(mode: .mock, consent: true)
        app.ai.transportOverride = HangingTutorTransport()
        let bio = makeBio(app)
        let streams = AskStreams()
        let thread = app.startChat(courseID: bio.course.id)
        streams.ask("What's the difference between mitosis and cytokinesis?", in: thread, app: app)
        await eventually { streams.live[thread.id]?.text.contains("nucleus") == true }
        XCTAssertEqual(streams.live[thread.id]?.origin, .cloud)
        streams.stop(thread.id, app: app)
        XCTAssertFalse(streams.isAnswering(thread.id))
        let answer = try XCTUnwrap(thread.sortedMessages.last)
        XCTAssertEqual(answer.role, .assistant)
        XCTAssertEqual(answer.text, "Mitosis splits the nucleus.")
        XCTAssertEqual(streams.notes[answer.id]?.interrupted, true)
        // A new question can be asked straight away, and the stopped stream never clears it.
        streams.ask("What happens after mitosis?", in: thread, app: app)
        XCTAssertTrue(streams.isAnswering(thread.id))
        streams.discard(thread.id)
    }

    // MARK: Cards from a chat

    func testCardsFromAChatBecomeItemsLinkedToTheCitedPage() throws {
        let app = makeApp()
        let bio = makeBio(app)
        let thread = app.startChat(courseID: bio.course.id)
        app.addQuestion("What's the difference between mitosis and cytokinesis?", to: thread)
        let quotes = ["During mitosis, the genetic material (DNA) is copied and equally separated into two new nuclei.",
                      "After mitosis, cytokinesis takes place. This is the division of the cytoplasm, producing two separate daughter cells."]
        app.saveAnswer(TutorOutcome(text: "Mitosis splits the nucleus; cytokinesis splits the rest of the cell.",
                                    citations: quotes.enumerated().map {
                                        Citation(id: "c\($0.offset)", sourceID: bio.textbook.id, pageIndex: 0, start: nil, quote: $0.element, label: "Textbook p. 87")
                                    },
                                    origin: .cloud, model: "mock", mode: .explain, grounded: true), to: thread)
        var cards = try RelayFixtures.load(CardsFromChatResponse.self, "cards-from-chat").items
        cards.append(GeneratedItem(id: "x1", kind: .flashcard, topic: "", prompt: "Photosynthesis", answer: "Plants make sugar from light."))
        cards.append(GeneratedItem(id: "x2", kind: .flashcard, topic: "", prompt: "   ", answer: "Nothing to ask"))
        let before = bio.course.items.count

        let made = app.addCardsFromChat(cards, origin: .cloud, to: bio.course.id, from: thread)
        XCTAssertEqual(made.count, 3, "an empty card is skipped")
        XCTAssertEqual(bio.course.items.count, before + 3)
        XCTAssertTrue(made.allSatisfy { $0.status == .active && $0.origin == .cloud }, "approved in Make cards, so active")

        let flashcard = try XCTUnwrap(made.first { $0.prompt == "Mitosis vs cytokinesis" })
        let ref = try XCTUnwrap(flashcard.sourceRef)
        XCTAssertEqual(ref.sourceID, bio.textbook.id)
        XCTAssertEqual(ref.pageIndex, 0)
        XCTAssertTrue(ref.label.hasPrefix("p. 87"), ref.label)
        XCTAssertTrue(Set(ref.anchorIDs).isSuperset(of: ["p0.l5", "p0.l6", "p0.l32"]), "\(ref.anchorIDs)")
        XCTAssertEqual(bio.course.liveTopics.first { $0.id == flashcard.topicID }?.name, "Cytokinesis")

        let mcq = try XCTUnwrap(made.first { $0.kind == .mcq })
        XCTAssertEqual(mcq.choices.filter(\.correct).map(\.text), ["Mitosis"])
        let unrelated = try XCTUnwrap(made.first { $0.prompt == "Photosynthesis" })
        XCTAssertNil(unrelated.sourceRef, "a card the chat's quotes don't support isn't linked to them")
        XCTAssertNil(unrelated.topicID)
    }

    func testMakeThisACardGoesToTheQuestionsTopicLinkedToTheCitedPage() throws {
        let app = makeApp()
        let bio = makeBio(app)
        let topic = Topic(course: bio.course, name: "Cell division", now: app.now)
        app.context.insert(topic)
        bio.course.topics.append(topic)
        let question = StudyItem(course: bio.course, topicID: topic.id, kind: .flashcard, status: .active, origin: .cloud,
                                 prompt: "What does mitosis make?", answer: "Two identical cells", now: app.now)
        app.context.insert(question)
        bio.course.items.append(question)
        app.save()
        let thread = app.startChat(courseID: bio.course.id)
        app.addQuestion(AppModel.mistakeQuestion(given: "Sex cells"), to: thread, contextItemID: question.id)
        let quote = "Mitosis is the process by which a single eukaryotic cell divides to produce two identical daughter cells."
        app.saveAnswer(TutorOutcome(text: "It makes two identical cells.",
                                    citations: [Citation(id: "c1", sourceID: bio.textbook.id, pageIndex: 0, start: nil, quote: quote, label: "Textbook p. 87")],
                                    origin: .cloud, model: "mock", mode: .explain, grounded: true), to: thread, contextItemID: question.id)
        let before = bio.course.items.count

        let card = GeneratedItem(id: "m1", kind: .flashcard, topic: "Somewhere else", prompt: "How many cells does mitosis make?", answer: "Two identical ones")
        let made = try XCTUnwrap(app.addMistakeCard(card, origin: .cloud, itemID: question.id, from: thread))
        XCTAssertEqual(bio.course.items.count, before + 1)
        XCTAssertEqual(made.prompt, "How many cells does mitosis make?")
        XCTAssertEqual(made.topicID, topic.id, "the question's own topic")
        XCTAssertEqual(made.status, .active, "the student pressed Add")
        XCTAssertEqual(made.origin, .cloud)
        XCTAssertEqual(made.sourceRef?.sourceID, bio.textbook.id)
        XCTAssertEqual(made.sourceRef?.pageIndex, 0)
        XCTAssertFalse(made.sourceRef?.anchorIDs.isEmpty ?? true)

        // The question has gone: nothing to file it under.
        app.context.delete(question)
        app.save()
        XCTAssertNil(app.addMistakeCard(card, origin: .cloud, itemID: question.id, from: thread))
    }

    func testExplainMyMistakeIsAnExplanationForAnAdultAndHintsUnderEighteen() async throws {
        for (age, mode) in [(AppSettings.AgeBand.adult, TutorMode.explain), (.teen, .hints)] {
            let app = makeApp(mode: .relay, consent: true, age: age)
            let transport = RecordingTransport()
            app.ai.transportOverride = transport
            app.settings.tutorMode = .hints
            let bio = makeBio(app)
            let streams = AskStreams()
            let thread = app.startChat(courseID: bio.course.id)
            let context = TutorContext(itemPrompt: "What does mitosis make?", expected: "Two identical cells", given: "Sex cells")
            streams.ask("What did I miss?", in: thread, app: app, context: context, contextItemID: UUID())
            await streams.waitForAnswer(thread.id)
            let request = try XCTUnwrap(transport.tutorRequests.first)
            XCTAssertEqual(request.mode, mode)
            XCTAssertEqual(request.context, context)
            // The mock's reply comes in the three parts: two that explain, then the check.
            let reply = MistakeReply.split(thread.sortedMessages.last?.text ?? "")
            XCTAssertEqual(MistakeReply.paragraphs(reply.explanation).count, 2)
            XCTAssertNotNil(reply.check)
        }
    }

    func testACardFromALectureCitationPointsAtItsMoment() throws {
        let app = makeApp()
        let bio = makeBio(app)
        let thread = app.startChat(courseID: bio.course.id)
        app.addQuestion("When does the nuclear envelope break down?", to: thread)
        let quote = "Then the nuclear envelope breaks down and the spindle starts forming from the centrosomes."
        app.saveAnswer(TutorOutcome(text: "In prophase.", citations: [Citation(id: "l1", sourceID: bio.lecture.id, pageIndex: nil, start: 340, quote: quote, label: "Lecture 6 · 05:40")],
                                    origin: .cloud, model: "mock", mode: .explain, grounded: true), to: thread)
        let card = GeneratedItem(id: "l", kind: .flashcard, topic: "Phases of mitosis", prompt: "Nuclear envelope in prophase",
                                 answer: "It breaks down, and the spindle starts forming from the centrosomes.")
        let item = try XCTUnwrap(app.addCardsFromChat([card], origin: .cloud, to: bio.course.id, from: thread).first)
        XCTAssertEqual(item.sourceRef?.sourceID, bio.lecture.id)
        XCTAssertEqual(item.sourceRef?.anchorIDs, ["s3"])
        XCTAssertEqual(item.sourceRef?.label, "Lecture 6 · 05:40")
    }

    // MARK: Citations on the page

    func testAQuoteIsPlacedOnItsLinesInReadingOrderAndInColumns() throws {
        let lines = AITestSupport.sampleLines
        XCTAssertEqual(AppModel.lineIDs(quoting: "After mitosis, cytokinesis takes place.", in: lines), ["p0.l32"])
        // The phases are printed in columns, so the quote's words are found line by line.
        let columns = AppModel.lineIDs(quoting: "Sister chromatids are pulled to opposite poles of the cell.", in: lines)
        XCTAssertTrue(columns.contains("p0.l14") && columns.contains("p0.l18"), "\(columns)")
        XCTAssertFalse(columns.contains("p0.l17"), "“the equator of the cell.” isn't part of it")
        XCTAssertTrue(AppModel.lineIDs(quoting: "Photosynthesis happens in chloroplasts.", in: lines).isEmpty)
    }

    func testAMissingSourceHasNoAnchors() {
        let app = makeApp()
        let citation = Citation(id: "x", sourceID: UUID(), pageIndex: 0, start: nil, quote: "Anything", label: "Gone p. 1")
        XCTAssertTrue(app.anchorIDs(for: citation).isEmpty)
    }

    // MARK: Settings the chat uses

    func testTheDefaultCourseHasNotesCapCanRead() {
        let app = makeApp()
        let bio = makeBio(app)
        let chem = Course(name: "Chem 110", sortOrder: 0, now: app.now)
        app.context.insert(chem)
        let quiz = Exam(course: chem, title: "Chem quiz", date: app.now.addingTimeInterval(2 * 86_400), now: app.now)
        app.context.insert(quiz)
        chem.exams.append(quiz)
        app.save()
        XCTAssertTrue(app.readableSources(courseID: chem.id).isEmpty)
        XCTAssertEqual(app.readableSources(courseID: bio.course.id).count, 2)
        XCTAssertEqual(app.defaultChatCourseID, bio.course.id, "the nearer exam's course has nothing to quote")
    }

    func testJustExplainIsLockedForUnder18() {
        let adult = makeApp()
        adult.setTutorMode(.explain)
        XCTAssertEqual(adult.settings.effectiveTutorMode, .explain)
        let teen = makeApp(age: .teen)
        teen.setTutorMode(.explain)
        XCTAssertEqual(teen.settings.tutorMode, .hints)
        XCTAssertEqual(teen.settings.effectiveTutorMode, .hints)
    }

    // MARK: Deleting

    func testDeletingAChatRemovesItsMessagesAndKeepsItsCards() throws {
        let app = makeApp()
        let bio = makeBio(app)
        let keep = app.startChat(courseID: bio.course.id)
        app.addQuestion("What is diffusion?", to: keep)
        let gone = app.startChat(courseID: bio.course.id)
        app.addQuestion("What happens after mitosis?", to: gone)
        app.saveAnswer(TutorOutcome(text: "Cytokinesis.", citations: [], origin: .rules, model: "rules", mode: .explain, grounded: true), to: gone)
        let card = GeneratedItem(id: "c", kind: .flashcard, topic: "", prompt: "After mitosis", answer: "Cytokinesis")
        let made = app.addCardsFromChat([card], origin: .rules, to: bio.course.id, from: gone)

        app.deleteChat(gone)
        XCTAssertEqual(app.chatThreads().map(\.id), [keep.id])
        XCTAssertEqual(app.fetch(FetchDescriptor<ChatMessage>()).count, 1)
        XCTAssertNotNil(app.item(made.first?.id), "cards made from a chat stay")

        app.deleteAllChats()
        XCTAssertTrue(app.chatThreads().isEmpty)
        XCTAssertTrue(app.fetch(FetchDescriptor<ChatMessage>()).isEmpty)
    }
}

/// A relay whose tutor sends a start and two pieces, then goes quiet until cancelled (the person presses stop).
private struct HangingTutorTransport: RelayTransport {
    func tutor(_ request: TutorRequest) -> AsyncThrowingStream<TutorEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.start(model: "test"))
                continuation.yield(.delta("Mitosis splits "))
                continuation.yield(.delta("the nucleus. "))
                try? await Task.sleep(for: .seconds(3600))
                continuation.finish(throwing: RelayError.cancelled)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func generate(_ request: GenerateRequest) async throws -> GenerateResponse { throw RelayError.upstream("unused") }
    func check(_ request: CheckRequest) async throws -> CheckResponse { throw RelayError.upstream("unused") }
    func grade(_ request: GradeRequest) async throws -> GradeResponse { throw RelayError.upstream("unused") }
    func confusions(_ request: ConfusionsRequest) async throws -> ConfusionsResponse { throw RelayError.upstream("unused") }
    func lecture(_ request: LectureRequest) async throws -> LectureResponse { throw RelayError.upstream("unused") }
    func cardsFromChat(_ request: CardsFromChatRequest) async throws -> CardsFromChatResponse { throw RelayError.upstream("unused") }
    func transcribeImage(_ request: TranscribeImageRequest) async throws -> TranscribeImageResponse { throw RelayError.upstream("unused") }
    func quota() async throws -> QuotaStatus { throw RelayError.upstream("unused") }
}
