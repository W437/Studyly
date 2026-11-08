import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// A transport that records the assistant's requests and answers from the fixtures (no waiting), with a switch to make web
/// research fail the way the relay would.
final class AssistantSpyTransport: RelayTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let base = MockRelayTransport(latencyScale: 0)
    private var _requests: [AssistantRequest] = []
    private var _research: [ResearchRequest] = []
    var researchError: RelayError?
    var assistantError: RelayError?

    var requests: [AssistantRequest] { lock.withLock { _requests } }
    var researchRequests: [ResearchRequest] { lock.withLock { _research } }

    func generate(_ request: GenerateRequest) async throws -> GenerateResponse { try await base.generate(request) }
    func check(_ request: CheckRequest) async throws -> CheckResponse { try await base.check(request) }
    func grade(_ request: GradeRequest) async throws -> GradeResponse { try await base.grade(request) }
    func tutor(_ request: TutorRequest) -> AsyncThrowingStream<TutorEvent, Error> { base.tutor(request) }
    func confusions(_ request: ConfusionsRequest) async throws -> ConfusionsResponse { try await base.confusions(request) }
    func lecture(_ request: LectureRequest) async throws -> LectureResponse { try await base.lecture(request) }
    func cardsFromChat(_ request: CardsFromChatRequest) async throws -> CardsFromChatResponse { try await base.cardsFromChat(request) }
    func transcribeImage(_ request: TranscribeImageRequest) async throws -> TranscribeImageResponse { try await base.transcribeImage(request) }
    func quota() async throws -> QuotaStatus { try await base.quota() }

    func assistant(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
        lock.withLock { _requests.append(request) }
        if let assistantError { return AsyncThrowingStream { $0.finish(throwing: assistantError) } }
        return base.assistant(request)
    }

    func research(_ request: ResearchRequest) -> AsyncThrowingStream<ResearchEvent, Error> {
        lock.withLock { _research.append(request) }
        if let researchError { return AsyncThrowingStream { $0.finish(throwing: researchError) } }
        return base.research(request)
    }
}

/// A relay from before the limit was raised: it takes 24 passages in an assistant request and turns a longer list down as a bad
/// request, in any round. Round one looks something up in the notes; the round after answers.
final class LegacyAssistantTransport: RelayTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [Int] = []
    private var _lookedUp = false
    private let query: String

    init(lookingUp query: String) { self.query = query }

    var sourceCounts: [Int] { lock.withLock { counts } }
    var lookedUp: Bool { lock.withLock { _lookedUp } }

    func assistant(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
        lock.withLock { counts.append(request.sources.count) }
        if request.sources.count > 24 {
            return AsyncThrowingStream { $0.finish(throwing: RelayError.badRequest("The request isn't valid: /sources has more than 24 items.")) }
        }
        let first = request.turns.isEmpty
        if first { lock.withLock { _lookedUp = true } }
        let query = self.query
        return AsyncThrowingStream { continuation in
            continuation.yield(.start(model: "legacy"))
            if first {
                continuation.yield(.toolStart(callID: "c1", name: "search_notes"))
                continuation.yield(.toolCall(callID: "c1", name: "search_notes", arguments: .object(["query": .string(query)])))
                let call: AnyJSON = .object(["type": .string("function_call"), "name": .string("search_notes"), "call_id": .string("c1")])
                continuation.yield(.done(model: "legacy", stop: "tool_calls", continuation: [call], limit: nil))
            } else {
                continuation.yield(.delta("Here is what the notes say."))
                continuation.yield(.done(model: "legacy", stop: "end_turn", continuation: [], limit: nil))
            }
            continuation.finish()
        }
    }

    func tutor(_ request: TutorRequest) -> AsyncThrowingStream<TutorEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: RelayError.upstream("unused")) }
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

/// Ask Cap's assistant: the mock relay's scripted rounds run through the real tools, and what changes in the library is
/// what is asserted (not the transcript). The Deno suite checks the same scripts against the real tool schemas.
@MainActor
final class AssistantTests: AskTestCase {

    private func world(auto: Set<AssistantAutoKind> = [], age: AppSettings.AgeBand = .adult) -> (AppModel, Bio, AssistantSpyTransport) {
        let app = makeApp(mode: .mock, consent: true, age: age)
        app.ai.assistantBeat = .zero
        let spy = AssistantSpyTransport()
        app.ai.transportOverride = spy
        if !auto.isEmpty { app.settings.assistant.auto = auto }
        let bio = makeBio(app)
        // Something to practise (not a card the scripts draft: a card the course already has is left out of a draft).
        let item = StudyItem(course: bio.course, kind: .flashcard, status: .active, origin: .person, prompt: "What is osmosis?",
                             answer: "Water moving across a membrane", now: app.now)
        app.context.insert(item)
        bio.course.items.append(item)
        app.save()
        return (app, bio, spy)
    }

    /// Asks Cap in a new chat and saves the reply, as the Ask tab does.
    private func ask(_ say: String, app: AppModel, bio: Bio) async -> (thread: ChatThread, outcome: AssistantOutcome, message: ChatMessage)? {
        let thread = app.startChat(courseID: bio.course.id)
        app.addQuestion(say, to: thread)
        guard let outcome = await app.ai.assistantReply(app.assistantInput(for: thread)),
              let message = app.saveAssistantAnswer(outcome, to: thread) else { return nil }
        return (thread, outcome, message)
    }

    private func cards(_ step: AssistantStep) -> [CardDraft] {
        if case .cards(let c) = step.payload { return c }
        return []
    }

    // MARK: Drafting, checking, adding

    func testFlashcardsAreDraftedAndCheckedAgainstTheNotesNotAddedBehindTheBack() async throws {
        let (app, bio, _) = world()
        let reply = try await XCTUnwrapAsync(await ask("Make me flashcards on mitosis", app: app, bio: bio))
        let step = try XCTUnwrap(reply.outcome.steps.first)
        XCTAssertEqual(reply.outcome.steps.count, 1)
        XCTAssertEqual(step.tool, .createFlashcards)
        XCTAssertEqual(step.status, .proposed, "Cap proposes; the student decides")
        XCTAssertEqual(step.courseID, bio.course.id)
        let drafts = cards(step)
        XCTAssertEqual(drafts.count, 6)
        // The quotes that are on the page are checked and named; the one that isn't is Cap's own words.
        XCTAssertEqual(drafts.filter { $0.basis.isFromNotes }.count, 5)
        XCTAssertEqual(drafts.last?.basis, .own)
        XCTAssertEqual(drafts.first?.basis.evidence?.label, "Textbook p. 87")
        XCTAssertEqual(drafts.first?.basis.evidence?.sourceID, bio.textbook.id)
        XCTAssertTrue(reply.outcome.text.hasPrefix("I drafted 6 flashcards on mitosis"), reply.outcome.text)
        // Nothing was added.
        XCTAssertEqual(bio.course.liveItems.count, 1, "only the card the student already had")
    }

    func testAddingMakesCheckedItemsLinkedToTheirPageAndUndoTakesThemBack() async throws {
        let (app, bio, _) = world()
        let reply = try await XCTUnwrapAsync(await ask("Make me flashcards on mitosis", app: app, bio: bio))
        let stepID = try XCTUnwrap(reply.outcome.steps.first).id

        let applied = try XCTUnwrap(app.approveAssistantStep(messageID: reply.message.id, stepID: stepID))
        XCTAssertEqual(applied.status, .applied)
        XCTAssertFalse(applied.auto)
        XCTAssertEqual(applied.createdIDs.count, 6)
        let made = bio.course.liveItems.filter { applied.createdIDs.contains($0.id) }
        XCTAssertEqual(made.count, 6)
        XCTAssertTrue(made.allSatisfy { $0.origin == .cloud && $0.status == .active && $0.kind == .flashcard })
        // Five rest on the textbook page and say so; the sixth is not marked as checked.
        XCTAssertEqual(made.filter { $0.checkedAt != nil }.count, 5)
        XCTAssertEqual(made.filter { $0.sourceRef?.sourceID == bio.textbook.id }.count, 5)
        XCTAssertFalse(made.filter { $0.sourceRef?.sourceID == bio.textbook.id }.contains { ($0.sourceRef?.anchorIDs ?? []).isEmpty },
                       "a card rests on the lines that hold its quote")
        let unchecked = try XCTUnwrap(made.first { $0.checkedAt == nil })
        XCTAssertNil(unchecked.sourceRef)
        XCTAssertEqual(bio.course.liveTopics.map(\.name), ["Mitosis"], "the topic is made when the cards are added")
        XCTAssertNil(app.approveAssistantStep(messageID: reply.message.id, stepID: stepID), "adding twice does nothing")
        XCTAssertEqual(bio.course.liveItems.count, 7)

        // The reply keeps what was done, so the list in Settings can find it.
        XCTAssertEqual(app.assistantAdditions().map(\.step.id), [stepID])
        let undone = try XCTUnwrap(app.undoAssistantStep(messageID: reply.message.id, stepID: stepID))
        XCTAssertEqual(undone.status, .undone)
        XCTAssertEqual(bio.course.liveItems.count, 1)
        XCTAssertTrue(app.assistantAdditions().isEmpty)
    }

    func testSkippingAddsNothingAndCanBeTakenBack() async throws {
        let (app, bio, _) = world()
        let reply = try await XCTUnwrapAsync(await ask("Make me flashcards on mitosis", app: app, bio: bio))
        let stepID = try XCTUnwrap(reply.outcome.steps.first).id
        app.skipAssistantStep(messageID: reply.message.id, stepID: stepID)
        XCTAssertEqual(app.assistantStep(messageID: reply.message.id, stepID: stepID)?.status, .skipped)
        XCTAssertEqual(bio.course.liveItems.count, 1)
        app.reopenAssistantStep(messageID: reply.message.id, stepID: stepID)
        XCTAssertEqual(app.assistantStep(messageID: reply.message.id, stepID: stepID)?.status, .proposed)
        XCTAssertNotNil(app.approveAssistantStep(messageID: reply.message.id, stepID: stepID))
    }

    func testUntickedAndEditedCardsAreWhatIsAdded() async throws {
        let (app, bio, _) = world()
        let reply = try await XCTUnwrapAsync(await ask("Make me flashcards on mitosis", app: app, bio: bio))
        let step = try XCTUnwrap(reply.outcome.steps.first)
        let drafts = cards(step)
        app.updateAssistantStep(messageID: reply.message.id, stepID: step.id) { s in
            guard case .cards(var c) = s.payload else { return }
            c[0].kept = false
            c[1].front = "What follows mitosis?"
            s.payload = .cards(c)
        }
        let applied = try XCTUnwrap(app.approveAssistantStep(messageID: reply.message.id, stepID: step.id))
        XCTAssertEqual(applied.createdIDs.count, 5)
        let prompts = bio.course.liveItems.filter { applied.createdIDs.contains($0.id) }.map(\.prompt)
        XCTAssertFalse(prompts.contains(drafts[0].front))
        XCTAssertTrue(prompts.contains("What follows mitosis?"))
    }

    func testACardTheCourseAlreadyHasIsLeftOutAndTheModelIsToldSo() async throws {
        let (app, bio, spy) = world()
        let have = StudyItem(course: bio.course, kind: .flashcard, status: .active, origin: .person, prompt: "What is mitosis?",
                             answer: "Cell division", now: app.now)
        app.context.insert(have)
        bio.course.items.append(have)
        app.save()
        let before = bio.course.liveItems.count

        let reply = try await XCTUnwrapAsync(await ask("Make me flashcards on mitosis", app: app, bio: bio))
        let step = try XCTUnwrap(reply.outcome.steps.first)
        let drafts = cards(step)
        XCTAssertEqual(drafts.count, 6, "the card is still shown")
        XCTAssertTrue(drafts.first?.isDuplicate ?? false)
        XCTAssertFalse(drafts.first?.kept ?? true, "but unticked, so it isn't added twice")
        XCTAssertEqual(step.title, "5 flashcards on Mitosis")
        let told = try XCTUnwrap(spy.requests.last?.turns.first?.results.first?.output)
        XCTAssertTrue(told.contains("\"already_in_course\":1") || told.contains("\"already_in_course\" : 1"), told)
        XCTAssertTrue(told.contains("\"count\":5") || told.contains("\"count\" : 5"), told)

        let applied = try XCTUnwrap(app.approveAssistantStep(messageID: reply.message.id, stepID: step.id))
        XCTAssertEqual(applied.createdIDs.count, 5)
        XCTAssertEqual(bio.course.liveItems.count, before + 5)
        // The student can still tick it if they want the twin.
        let again = try await XCTUnwrapAsync(await ask("Make me flashcards on mitosis", app: app, bio: bio))
        let second = try XCTUnwrap(again.outcome.steps.first)
        XCTAssertTrue(cards(second).allSatisfy(\.isDuplicate), "every one of them is in the course now")
        XCTAssertEqual(second.title, "Already in Bio 101", "not \"0 flashcards\"")
        app.updateAssistantStep(messageID: again.message.id, stepID: second.id) { s in
            guard case .cards(var c) = s.payload else { return }
            for i in c.indices { c[i].kept = (i == 0) }
            s.payload = .cards(c)
        }
        let one = try XCTUnwrap(app.approveAssistantStep(messageID: again.message.id, stepID: second.id))
        XCTAssertEqual(one.createdIDs.count, 1)
    }

    // MARK: Let Cap do it

    func testLetCapDoItAddsAtOnceTellsTheModelSoAndCanBeUndone() async throws {
        let (app, bio, spy) = world(auto: [.cards])
        let reply = try await XCTUnwrapAsync(await ask("Make me flashcards on mitosis", app: app, bio: bio))
        let step = try XCTUnwrap(reply.outcome.steps.first)
        XCTAssertEqual(step.status, .applied)
        XCTAssertTrue(step.auto)
        XCTAssertEqual(bio.course.liveItems.count, 7)
        // The model was told what really happened, so its note doesn't say "for you to look over".
        let result = try XCTUnwrap(spy.requests.last?.turns.first?.results.first)
        XCTAssertTrue(result.output.contains("\"added\""), result.output)
        XCTAssertNotNil(app.undoAssistantStep(messageID: reply.message.id, stepID: step.id))
        XCTAssertEqual(bio.course.liveItems.count, 1)
    }

    func testTheOtherKindsStayAskFirstWhenOnlyCardsAreHandedOver() async throws {
        let (app, bio, _) = world(auto: [.cards])
        let reply = try await XCTUnwrapAsync(await ask("Write me a note summarising mitosis", app: app, bio: bio))
        XCTAssertEqual(reply.outcome.steps.first?.status, .proposed)
    }

    /// Settings has one switch for every kind ("Let Cap add cards, notes and exams without asking").
    func testOneSwitchHandsOverEveryKindAndTakesThemAllBack() {
        let (app, _, _) = world()
        app.setAssistantAutoAll(true)
        XCTAssertEqual(app.settings.assistantAuto, Set(AssistantAutoKind.allCases))
        app.setAssistantAutoAll(false)
        XCTAssertTrue(app.settings.assistantAuto.isEmpty)
    }

    func testAnAccountUnder18AlwaysAsksFirstAndHasNoWeb() async throws {
        let (app, bio, spy) = world(age: .teen)
        app.settings.assistant.auto = [.cards, .notes, .exams]   // however it got there
        XCTAssertTrue(app.settings.assistantAuto.isEmpty)
        XCTAssertFalse(app.assistantTools.contains(.researchWeb))
        app.setAssistantAutoAll(true)                            // the switch is locked too
        let reply = try await XCTUnwrapAsync(await ask("Make me flashcards on mitosis", app: app, bio: bio))
        XCTAssertEqual(reply.outcome.steps.first?.status, .proposed)
        XCTAssertEqual(spy.requests.first?.minor, true)
        XCTAssertFalse(spy.requests.first?.tools.contains(.researchWeb) ?? true)
    }

    // MARK: Questions, notes, exams

    func testQuestionsAreWellFormedAndTheRightOptionIsNotAlwaysFirst() async throws {
        let (app, bio, _) = world()
        let reply = try await XCTUnwrapAsync(await ask("Quiz me on mitosis", app: app, bio: bio))
        let step = try XCTUnwrap(reply.outcome.steps.first)
        guard case .questions(let questions) = step.payload else { return XCTFail("not questions") }
        XCTAssertEqual(questions.map(\.kind), [.multipleChoice, .shortAnswer, .fillBlank])
        let mc = questions[0]
        XCTAssertEqual(mc.choices.count, 4)
        XCTAssertEqual(mc.choices[try XCTUnwrap(mc.correctIndex)], "The cytoplasm")
        XCTAssertEqual(Set(mc.choices), ["The nucleus", "The cytoplasm", "The DNA", "The chromosomes"])

        let applied = try XCTUnwrap(app.approveAssistantStep(messageID: reply.message.id, stepID: step.id))
        let items = bio.course.liveItems.filter { applied.createdIDs.contains($0.id) }.sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(items.map(\.kind), [.mcq, .recall, .cloze])
        XCTAssertEqual(items[0].choices.filter(\.correct).map(\.text), ["The cytoplasm"])
        XCTAssertEqual(items[1].keyIdeas.count, 4)
        XCTAssertEqual(items[2].cloze?.answers, ["identical"])
        XCTAssertTrue(items.allSatisfy { $0.checkedAt != nil })
    }

    func testANoteBecomesASourceInTheCourseAndGoesAgainOnUndo() async throws {
        let (app, bio, _) = world()
        let reply = try await XCTUnwrapAsync(await ask("Write me a note summarising mitosis", app: app, bio: bio))
        let step = try XCTUnwrap(reply.outcome.steps.first)
        guard case .note(let note) = step.payload else { return XCTFail("not a note") }
        XCTAssertEqual(note.title, "Mitosis in short")
        XCTAssertTrue(note.body.contains("Prophase"))
        let before = bio.course.liveSources.count
        let applied = try XCTUnwrap(app.approveAssistantStep(messageID: reply.message.id, stepID: step.id))
        XCTAssertEqual(bio.course.liveSources.count, before + 1)
        let made = try XCTUnwrap(app.source(applied.createdIDs.first))
        XCTAssertEqual(made.title, "Mitosis in short")
        XCTAssertEqual(made.kind, .text)
        XCTAssertTrue(made.sortedPages.map(\.text).joined().contains("Telophase"))
        app.undoAssistantStep(messageID: reply.message.id, stepID: step.id)
        XCTAssertEqual(bio.course.liveSources.count, before)
    }

    func testAnExamHasARealDateAndOnlyCountsOnceAdded() async throws {
        let (app, bio, _) = world()
        let reply = try await XCTUnwrapAsync(await ask("Plan my midterm for 12 November", app: app, bio: bio))
        let step = try XCTUnwrap(reply.outcome.steps.first)
        guard case .exam(let plan) = step.payload else { return XCTFail("not an exam") }
        let c = app.calendar.dateComponents([.year, .month, .day, .hour], from: plan.date)
        XCTAssertEqual([c.year, c.month, c.day, c.hour], [2026, 11, 12, 9])
        XCTAssertEqual(plan.title, "Bio 101 midterm")
        XCTAssertTrue(bio.course.liveExams.isEmpty)
        let applied = try XCTUnwrap(app.approveAssistantStep(messageID: reply.message.id, stepID: step.id))
        XCTAssertEqual(bio.course.liveExams.map(\.title), ["Bio 101 midterm"])
        XCTAssertEqual(applied.createdIDs, bio.course.liveExams.map(\.id))
        app.undoAssistantStep(messageID: reply.message.id, stepID: step.id)
        XCTAssertTrue(bio.course.liveExams.isEmpty)
    }

    // MARK: Buttons, lookups, more than one step

    func testPracticeIsOfferedAndNothingOpensUntilTheStudentTaps() async throws {
        let (app, bio, _) = world()
        let reply = try await XCTUnwrapAsync(await ask("Start a practice session", app: app, bio: bio))
        let step = try XCTUnwrap(reply.outcome.steps.first)
        XCTAssertEqual(step.status, .offered)
        guard case .practice(let offer) = step.payload else { return XCTFail("not an offer") }
        XCTAssertEqual(offer.minutes, 10)
        XCTAssertEqual(offer.courseID, bio.course.id)
        XCTAssertNil(app.router.cover)
        app.perform(step.payload)
        guard case .session(let request) = app.router.cover else { return XCTFail("the session didn't open on tap") }
        XCTAssertEqual(request.kind, .practice)
        XCTAssertEqual(request.minutes, 10)
    }

    func testALookupThenCardsIsTwoStepsInThreeRoundsAndAQuoteNotInTheNotesIsMarkedAsCapsOwn() async throws {
        let (app, bio, spy) = world()
        let reply = try await XCTUnwrapAsync(await ask("Look through my notes and make cards on anaphase", app: app, bio: bio))
        XCTAssertEqual(reply.outcome.steps.map(\.tool), [.searchNotes, .createFlashcards])
        let lookup = reply.outcome.steps[0]
        XCTAssertEqual(lookup.status, .done)
        guard case .lookup(let found) = lookup.payload else { return XCTFail("not a lookup") }
        XCTAssertFalse(found.hits.isEmpty)
        XCTAssertEqual(spy.requests.count, 3)
        XCTAssertTrue(spy.requests[1].turns[0].results[0].output.contains("passages"))
        XCTAssertEqual(spy.requests[2].turns.count, 2, "each round is sent back with the one before")
        // This world has the textbook and Lecture 6 but not the slides two of the quotes come from.
        let drafts = cards(reply.outcome.steps[1])
        XCTAssertEqual(drafts.count, 3)
        XCTAssertEqual(drafts.filter { $0.basis == .own }.count, 2, "a quote that is not in the student's material does not count")
        XCTAssertEqual(drafts.last?.basis.evidence?.label.hasPrefix("Lecture 6"), true)
    }

    func testTheFirstRequestCarriesTheNotesNotSixHits() async throws {
        let (app, bio, spy) = world()
        _ = await ask("Make me flashcards on mitosis", app: app, bio: bio)
        let all = LocalRetriever(material: app.tutorMaterial(courseID: bio.course.id)).passages
        let asked = try XCTUnwrap(spy.requests.first)
        XCTAssertGreaterThan(all.count, 6, "more than the six the first round used to start from")
        XCTAssertEqual(asked.sources.map(\.text), all.map(\.text), "everything, in reading order, with ids that stay the same from round to round")
        XCTAssertEqual(asked.sources.map(\.id), (1...all.count).map { "s\($0)" })
        if spy.requests.count > 1 {
            XCTAssertEqual(Array(spy.requests[1].sources.prefix(all.count)), asked.sources, "the start of every round is the same")
        }
    }

    func testAnOldRelayThatTakes24PassagesIsKeptWithinThemInEveryRound() async throws {
        let app = makeApp(mode: .mock, consent: true)
        app.ai.assistantBeat = .zero
        let legacy = LegacyAssistantTransport(lookingUp: "matter55")
        app.ai.transportOverride = legacy
        let bio = makeBio(app)
        // About 4,000 words on pages of ten: far more than 24 passages, so the whole of it goes at first.
        _ = try app.createSource(fromText: (0..<60).map { TutorFixtures.paragraph($0) }.joined(separator: "\n"), title: "Reading A", course: bio.course)
        let thread = app.startChat(courseID: bio.course.id)
        app.addQuestion("What do my notes say about matter3?", to: thread)
        let reply = await app.ai.assistantReply(app.assistantInput(for: thread))
        let outcome = try XCTUnwrap(reply)

        let counts = legacy.sourceCounts
        XCTAssertEqual(counts.count, 3, "refused, then the first round again, then the one after the lookup: \(counts)")
        XCTAssertGreaterThan(counts[0], 24, "the first try carried the notes")
        XCTAssertEqual(counts[1], 24, "asked again with the best 24")
        XCTAssertLessThanOrEqual(counts[2], 24, "the lookup added passages, and the next round still holds only 24")
        XCTAssertEqual(outcome.text, "Here is what the notes say.")
        XCTAssertFalse(outcome.interrupted, "not 'lost the connection part way'")
        XCTAssertNil(outcome.note)
        XCTAssertTrue(legacy.lookedUp, "the reply did look something up")
    }

    func testASessionKeepsToItsLimitInEveryRound() throws {
        let (app, bio, _) = world()
        let retriever = LocalRetriever(material: [TutorFixtures.source("Reading A", paragraphs: 50)])
        func session() -> AssistantSession {
            AssistantSession(index: app.studyIndex(currentCourseID: bio.course.id), retriever: retriever, currentCourseID: bio.course.id)
        }
        let all = retriever.passages
        XCTAssertGreaterThanOrEqual(all.count, 50)
        // The new relay takes a hundred.
        let plain = session()
        plain.send(Array(all.prefix(30)))
        plain.send(Array(all.dropFirst(30)))
        XCTAssertEqual(plain.sources.count, all.count)
        XCTAssertEqual(AssistantSession.maxSources, 100)
        // An old one takes 24: after `restart`, whatever the lookups add, a request holds the first six and the newest.
        let old = session()
        old.restart(with: Array(all.prefix(24)), limit: 24)
        XCTAssertEqual(old.sources.map(\.id), (1...24).map { "s\($0)" })
        old.send(Array(all.dropFirst(24).prefix(14)))
        XCTAssertEqual(old.sent.count, 38)
        let ids = old.sources.map(\.id)
        XCTAssertEqual(ids.count, 24)
        XCTAssertEqual(Array(ids.prefix(6)), (1...6).map { "s\($0)" })
        XCTAssertEqual(ids.last, "s38")
        // A passage inside a joined one keeps the joined one's id.
        let joined = TutorSelection.joined(Array(all.prefix(3)))
        let third = session()
        third.send([joined])
        XCTAssertEqual(third.send([all[1]]).map(\.id), ["s1"])
        XCTAssertEqual(third.send([all[5]]).map(\.id), ["s2"])
    }

    func testPassagesKeepTheirIdsFromRoundToRound() throws {
        let (app, bio, _) = world()
        let retriever = LocalRetriever(material: app.tutorMaterial(courseID: bio.course.id))
        XCTAssertGreaterThanOrEqual(retriever.passages.count, 4)
        let session = AssistantSession(index: app.studyIndex(currentCourseID: bio.course.id), retriever: retriever,
                                       currentCourseID: bio.course.id)
        XCTAssertEqual(session.send(Array(retriever.passages.prefix(2))).map(\.id), ["s1", "s2"])
        XCTAssertEqual(session.send([retriever.passages[0]]).map(\.id), ["s1"], "a passage keeps its id")
        XCTAssertEqual(session.send([retriever.passages[3]]).map(\.id), ["s3"])
        XCTAssertEqual(session.sources.map(\.id), ["s1", "s2", "s3"])
    }

    func testLookupsNeverPushTheRequestOverWhatTheRelayTakesInAll() throws {
        let (app, bio, _) = world()
        // 20 passages of 12,000 characters: three tokens of 4,000 letters each, so a few words and a lot of text.
        let pages = (0..<20).map { n in
            PageText(index: n, label: "\(n + 1)", lines: [TextLine(id: "p\(n).l0", text: [String(repeating: "a", count: 4_000),
                                                                                           String(repeating: "b", count: 4_000),
                                                                                           String(repeating: "c", count: 4_000)].joined(separator: " ") + ".",
                                                                    box: nil)])
        }
        let retriever = LocalRetriever(material: [TutorMaterial(sourceID: UUID(), title: "Kanji reader", kind: .text, pages: pages)])
        XCTAssertEqual(retriever.passages.count, 20)
        let session = AssistantSession(index: app.studyIndex(currentCourseID: bio.course.id), retriever: retriever, currentCourseID: bio.course.id)
        session.send(Array(retriever.passages.prefix(10)))
        session.send(Array(retriever.passages.suffix(10)))
        let ids = session.sources.map(\.id)
        let total = session.sources.reduce(0) { $0 + $1.text.utf16.count }
        XCTAssertLessThanOrEqual(total, AssistantSession.maxCharacters)
        XCTAssertLessThanOrEqual(AssistantSession.maxCharacters, 200_000)
        XCTAssertEqual(Array(ids.prefix(6)), ["s1", "s2", "s3", "s4", "s5", "s6"], "the start of the request stays as it was")
        XCTAssertEqual(ids.last, "s20", "the newest lookup stays")
        XCTAssertLessThan(ids.count, 20, "the oldest lookups went")
        // Ordinary passages are all there.
        let ordinary = AssistantSession(index: app.studyIndex(currentCourseID: bio.course.id),
                                        retriever: LocalRetriever(material: app.tutorMaterial(courseID: bio.course.id)),
                                        currentCourseID: bio.course.id)
        ordinary.send(Array(ordinary.retriever.passages.prefix(4)))
        XCTAssertEqual(ordinary.sources.count, 4)
    }

    // MARK: The web

    func testResearchShowsItsSearchSourcesSummaryAndCitationsAndCanBeSavedAsANote() async throws {
        let (app, bio, spy) = world()
        let reply = try await XCTUnwrapAsync(await ask("Research mitosis vs meiosis online", app: app, bio: bio))
        let step = try XCTUnwrap(reply.outcome.steps.first)
        XCTAssertEqual(step.tool, .researchWeb)
        XCTAssertEqual(step.status, .proposed)
        guard case .research(let result) = step.payload else { return XCTFail("not research") }
        XCTAssertEqual(result.phase, .done)
        XCTAssertEqual(result.queries, ["mitosis meiosis differences two divisions chromosomes"])
        XCTAssertEqual(result.sources.count, 5)
        XCTAssertEqual(result.cited.map(\.domain), ["openstax.org", "britannica.com", "khanacademy.org"])
        XCTAssertEqual(result.cited.first?.title, "11.1 The Process of Meiosis - Biology | OpenStax")
        XCTAssertTrue(result.text.contains("Meiosis"))
        XCTAssertEqual(spy.researchRequests.first?.minor, false)
        // The model is told it was shown, not what it said, and that it is the student's to save.
        let told = try XCTUnwrap(spy.requests.last?.turns.first?.results.first?.output)
        XCTAssertTrue(told.contains("researched"), told)
        XCTAssertFalse(told.contains("Meiosis involves"), "the summary stays between the web and the student")
        // Nothing is saved until the student says so.
        let before = bio.course.liveSources.count
        let saved = try XCTUnwrap(app.approveAssistantStep(messageID: reply.message.id, stepID: step.id))
        XCTAssertEqual(bio.course.liveSources.count, before + 1)
        let note = try XCTUnwrap(app.source(saved.createdIDs.first))
        XCTAssertTrue(note.title.hasPrefix("From the web:"))
        let text = note.sortedPages.map(\.text).joined(separator: " ")
        XCTAssertTrue(text.contains("openstax.org"), "the note names where it came from")
    }

    func testResearchIsNeverSavedOnItsOwnEvenWhenNotesAreHandedToCap() async throws {
        let (app, bio, spy) = world(auto: [.cards, .notes, .exams])
        let before = bio.course.liveSources.count
        let reply = try await XCTUnwrapAsync(await ask("Research mitosis vs meiosis online", app: app, bio: bio))
        let step = try XCTUnwrap(reply.outcome.steps.first)
        XCTAssertEqual(step.tool, .researchWeb)
        XCTAssertEqual(step.status, .proposed, "a page's words are not the student's, so the student decides")
        XCTAssertFalse(step.auto)
        XCTAssertEqual(bio.course.liveSources.count, before, "nothing was saved")
        let told = try XCTUnwrap(spy.requests.last?.turns.first?.results.first?.output)
        XCTAssertTrue(told.contains("researched"), told)
        XCTAssertFalse(told.contains("saved"), "the model is not told it was saved: \(told)")
    }

    func testResearchThatNeedsProSaysSoAndOffersTheUpgrade() async throws {
        let (app, bio, spy) = world()
        spy.researchError = .entitlementRequired
        let reply = try await XCTUnwrapAsync(await ask("Research mitosis vs meiosis online", app: app, bio: bio))
        let step = try XCTUnwrap(reply.outcome.steps.first)
        XCTAssertEqual(step.status, .failed)
        XCTAssertTrue(step.needsPro)
        XCTAssertEqual(step.detail, "Web research is part of Capling Pro.")
        let told = try XCTUnwrap(spy.requests.last?.turns.first?.results.first?.output)
        XCTAssertTrue(told.contains("Capling Pro"), told)
    }

    func testResearchSwitchedOffInSettingsIsNotOffered() {
        let (app, _, _) = world()
        XCTAssertTrue(app.assistantTools.contains(.researchWeb))
        app.setAssistantWeb(false)
        XCTAssertFalse(app.assistantTools.contains(.researchWeb))
    }

    // MARK: When it can't

    func testAFailureBeforeAnythingIsShownLeavesTheAnswerToTheTutor() async throws {
        let (app, bio, _) = world()
        let thread = app.startChat(courseID: bio.course.id)
        app.addQuestion("make a flashcard #fail", to: thread)
        var declined = false
        var finished = false
        for await update in app.ai.assistant(app.assistantInput(for: thread)) {
            if case .declined = update { declined = true }
            if case .finished = update { finished = true }
        }
        XCTAssertTrue(declined)
        XCTAssertFalse(finished)
    }

    func testTheDaysCostCapLeavesTheAnswerToTheTutorWhichSaysSo() async throws {
        let (app, bio, spy) = world()
        spy.assistantError = .quotaExceeded(QuotaStatus(plan: .pro, meters: []),
                                            message: "That's all the cloud AI for today. It starts again at midnight.")
        let thread = app.startChat(courseID: bio.course.id)
        app.addQuestion("Make me flashcards on mitosis", to: thread)
        var declined = false
        var finished = false
        for await update in app.ai.assistant(app.assistantInput(for: thread)) {
            if case .declined = update { declined = true }
            if case .finished = update { finished = true }
        }
        XCTAssertTrue(declined, "nothing reached the student, so the tutor answers")
        XCTAssertFalse(finished)
        XCTAssertTrue(app.ai.cloudRefused, "and it knows why")
        XCTAssertTrue(app.ai.assistantAvailable(question: "Make me flashcards on mitosis", hasContext: false),
                      "the cap is the relay's to enforce; it is not a relay without an assistant")
    }

    func testARelayWithoutAnAssistantIsNotAskedAgainForAWhile() async throws {
        let (app, bio, spy) = world()
        spy.assistantError = .upstream("Cap's assistant isn't set up on this server.")
        let thread = app.startChat(courseID: bio.course.id)
        app.addQuestion("Make me flashcards on mitosis", to: thread)
        XCTAssertTrue(app.ai.assistantAvailable(question: "Make me flashcards on mitosis", hasContext: false))
        _ = await app.ai.assistantReply(app.assistantInput(for: thread))
        XCTAssertFalse(app.ai.assistantAvailable(question: "Make me flashcards on mitosis", hasContext: false))
        let later = app.now.addingTimeInterval(601)
        app.clock = { later }
        XCTAssertTrue(app.ai.assistantAvailable(question: "Make me flashcards on mitosis", hasContext: false))
    }

    func testTheTutorKeepsWhatItAlwaysDid() {
        let (app, _, _) = world()
        XCTAssertTrue(app.ai.assistantAvailable(question: "What is mitosis?", hasContext: false))
        XCTAssertFalse(app.ai.assistantAvailable(question: "What is mitosis?", hasContext: true), "Explain my mistake stays on the tutor")
        XCTAssertFalse(app.ai.assistantAvailable(question: "Write my essay on mitosis", hasContext: false), "a refused request reaches no model")
        XCTAssertFalse(app.ai.assistantAvailable(question: "thanks", hasContext: false), "small talk reaches no model")
        // (Mock mode counts consent as granted, since nothing leaves the device; a real relay needs it.)
        let off = makeApp(mode: .relay, consent: false)
        off.ai.transportOverride = AssistantSpyTransport()
        XCTAssertFalse(off.ai.assistantAvailable(question: "Make flashcards on mitosis", hasContext: false), "no consent, no cloud")
        let on = makeApp(mode: .relay, consent: true)
        on.ai.transportOverride = AssistantSpyTransport()
        XCTAssertTrue(on.ai.assistantAvailable(question: "Make flashcards on mitosis", hasContext: false), "consent given, a relay: yes")
        let local = makeApp(mode: .local, consent: true)
        XCTAssertFalse(local.ai.assistantAvailable(question: "Make flashcards on mitosis", hasContext: false), "no relay, no assistant")
        let child = makeApp(mode: .mock, consent: true, age: .under13)
        XCTAssertFalse(child.ai.assistantAvailable(question: "Make flashcards on mitosis", hasContext: false), "nothing leaves a child's iPhone")
    }

    func testTheMakeSomethingChipsAreOfferedOnlyWhenCapCanDoThemAndTheWebOnlyWhenItIsOn() {
        let (app, _, _) = world()
        XCTAssertTrue(app.ai.assistantReady)
        XCTAssertEqual(AssistantQuickStart.available(app).count, 5)
        app.setAssistantWeb(false)
        XCTAssertEqual(AssistantQuickStart.available(app).count, 4)
        XCTAssertFalse(AssistantQuickStart.available(app).contains { $0.icon == "globe" }, "no web chip when the web is off")
        let (teen, _, _) = world(age: .teen)
        XCTAssertFalse(AssistantQuickStart.available(teen).contains { $0.icon == "globe" }, "none for an account under 18")

        // No consent, no relay, or a child's account: the empty chat has no chips to lead nowhere.
        let off = makeApp(mode: .relay, consent: false)
        off.ai.transportOverride = AssistantSpyTransport()
        XCTAssertFalse(off.ai.assistantReady)
        XCTAssertFalse(makeApp(mode: .local, consent: true).ai.assistantReady)
        let child = makeApp(mode: .relay, consent: true, age: .under13)
        child.ai.transportOverride = AssistantSpyTransport()
        XCTAssertFalse(child.ai.assistantReady)
    }

    // MARK: What the model is shown

    func testTheModelSeesTheStudentsStudyWithShortIdsAndNothingElse() async throws {
        let (app, bio, spy) = world()
        let exam = Exam(course: bio.course, title: "Bio 101 midterm", date: app.now.addingTimeInterval(86_400 * 12), now: app.now)
        app.context.insert(exam)
        bio.course.exams.append(exam)
        _ = ItemFactory.topic(named: "Mitosis", in: bio.course, now: app.now)
        app.save()
        _ = await ask("hi there", app: app, bio: bio)
        let study = try XCTUnwrap(spy.requests.first?.study)
        XCTAssertEqual(study.currentCourseId, "c1")
        XCTAssertEqual(study.courses.map(\.name), ["Bio 101"])
        XCTAssertEqual(study.courses[0].sources, 2)
        XCTAssertEqual(study.courses[0].topics.map(\.id), ["t1"])
        XCTAssertEqual(study.exams.map(\.id), ["e1"])
        XCTAssertEqual(study.exams[0].courseId, "c1")
        let json = String(decoding: try JSONEncoder.cramless.encode(spy.requests[0]), as: UTF8.self)
        XCTAssertFalse(json.contains(bio.course.id.uuidString), "the model is never given a uuid")
        // The request carries the passages the app found, ids and all.
        let asked = try XCTUnwrap(spy.requests.first)
        XCTAssertEqual(asked.mode, .hints, "the person's setting, hints first by default")
        XCTAssertEqual(asked.tools, AssistantToolName.allCases)
    }

    func testTheTutorModeIsThePersonsChoiceAndAlwaysHintsForAMinor() async throws {
        let (adult, bioA, spyA) = world()
        adult.settings.tutorMode = .explain
        _ = await ask("hi there", app: adult, bio: bioA)
        XCTAssertEqual(spyA.requests.first?.mode, .explain)
        XCTAssertEqual(spyA.requests.first?.minor, false)

        let (teen, bioT, spyT) = world(age: .teen)
        teen.settings.tutorMode = .explain
        _ = await ask("hi there", app: teen, bio: bioT)
        XCTAssertEqual(spyT.requests.first?.mode, .hints, "an account under 18 is always on hints first")
        XCTAssertEqual(spyT.requests.first?.minor, true)
        XCTAssertFalse(spyT.requests.first?.tools.contains(.researchWeb) ?? true, "and is never offered the web")
    }

    func testWhenTheDaysDraftsAreUsedUpCapSaysSoInItsOwnWordsAndTheStepsOfThatReplyGoWithIt() async throws {
        let (app, bio, _) = world()
        let reply = try await XCTUnwrapAsync(await ask("Make a card #limit", app: app, bio: bio))
        XCTAssertEqual(reply.outcome.limit, "drafts", "the relay ended the reply there")
        XCTAssertEqual(reply.outcome.text, "I can't make anything new today.", "the words are the app's, not a fallback to the tutor")
        XCTAssertTrue(reply.outcome.steps.isEmpty)
        XCTAssertEqual(reply.message.text, reply.outcome.text, "and they are what the chat keeps")
        XCTAssertEqual(bio.course.liveItems.count, 1, "nothing was made")

        // On a paid plan it is the fair-use day, with no offer of Pro.
        app.ai.setServerQuota(QuotaStatus(plan: .pro, meters: []))
        let paid = try await XCTUnwrapAsync(await ask("Make a card #limit", app: app, bio: bio))
        XCTAssertEqual(paid.outcome.text, "That's all the drafts for today. They start again at midnight.")
    }

    func testTheChecksArePlayedOutOneByOneAndMarkedAsTheCheckingPhase() {
        let drafts = (0..<4).map { CardDraft(id: UUID(), front: "Front \($0)", back: "Back", basis: .own) }
        let step = AssistantStep(id: "c", tool: .createFlashcards, status: .proposed, title: "4 flashcards", payload: .cards(drafts))
        XCTAssertNil(step.checking, "a settled step is not in the checking phase")

        let frames = AIRouter.reveal(step)
        XCTAssertEqual(frames.count, 4)
        XCTAssertTrue(frames.allSatisfy { $0.status == .working && $0.checking == true })
        // Nothing is checked in the first frame, one more is in each next, so the card's growth only ever rises.
        let checked = frames.map { frame -> Int in
            guard case .cards(let c) = frame.payload else { return -1 }
            return c.filter { $0.basis != .checking }.count
        }
        XCTAssertEqual(checked, [0, 1, 2, 3])
        XCTAssertTrue(zip(frames, frames.dropFirst()).allSatisfy { $0.growth < $1.growth })
        // The last words of the writing phase and the first frame of the checking phase differ, so the chat follows both.
        var writing = frames[0]
        writing.checking = nil
        XCTAssertNotEqual(writing.growth, frames[0].growth)
        XCTAssertTrue(AIRouter.reveal(AssistantStep(id: "n", tool: .createNote, status: .proposed, title: "n",
                                                    payload: .note(NoteDraft(title: "t", body: "b")))).isEmpty,
                      "only decks are checked one by one")
    }

    func testAStoppedReplyKeepsWhatWasAddedAndMarksWhatWasNeverCheckedAsCapsOwn() async throws {
        let (app, bio, _) = world()
        let thread = app.startChat(courseID: bio.course.id)
        let unchecked = (0..<2).map { CardDraft(id: UUID(), front: "Front \($0)", back: "Back", basis: .checking) }
        // Added by "Let Cap do it", and the checks were still playing out when the student pressed stop.
        var added = AssistantStep(id: "a", tool: .createFlashcards, status: .working, courseID: bio.course.id, courseName: "Bio 101",
                                  title: "2 flashcards", payload: .cards(unchecked))
        added.createdIDs = [UUID(), UUID()]
        added.checking = true
        // Cut off while the model was still writing it.
        var cut = AssistantStep(id: "b", tool: .createFlashcards, status: .working, courseID: bio.course.id, courseName: "Bio 101",
                                title: "2 flashcards so far", payload: .cards(unchecked))
        cut.checking = nil
        let outcome = AssistantOutcome(text: "", citations: [], steps: [added, cut], model: "", interrupted: true)

        let message = try XCTUnwrap(app.saveAssistantAnswer(outcome, to: thread))
        let saved = message.steps
        XCTAssertEqual(saved.map(\.status), [.applied, .skipped], "what is in the library stays in the chat, and can be taken back")
        XCTAssertEqual(saved[0].createdIDs, added.createdIDs)
        XCTAssertNil(saved[0].checking)
        XCTAssertEqual(saved[1].detail, "Cap stopped before it finished this.")
        guard case .cards(let kept) = saved[1].payload else { return XCTFail("not cards") }
        XCTAssertTrue(kept.allSatisfy { $0.basis == .own }, "drafts that never met a check are not shown as checked")
    }

    func testWhatARepyDraftedIsWrittenIntoTheChatTheModelReadsNextTime() async throws {
        let (app, bio, _) = world()
        let reply = try await XCTUnwrapAsync(await ask("Make me flashcards on mitosis", app: app, bio: bio))
        let said = reply.message.textForModel
        XCTAssertTrue(said.contains("I drafted 6 flashcards"))
        XCTAssertTrue(said.contains("[Drafted 6 flashcards on Mitosis: What is mitosis?"), said)
        // A plain message is its words.
        let plain = ChatMessage(thread: reply.thread, role: .assistant, text: "Just words", now: app.now)
        XCTAssertEqual(plain.textForModel, "Just words")
    }

    func testStepsSurviveTheTripThroughTheStore() async throws {
        let (app, bio, _) = world()
        let reply = try await XCTUnwrapAsync(await ask("Quiz me on mitosis", app: app, bio: bio))
        let again = try XCTUnwrap(app.chatMessage(reply.message.id))
        XCTAssertEqual(again.steps, reply.outcome.steps)
        XCTAssertEqual(ChatEntry(again).steps.count, 1)
    }

    func testAStepStillWorkingWhenTheReplyEndsIsNotLeftWorking() {
        let (app, bio, _) = world()
        let thread = app.startChat(courseID: bio.course.id)
        let step = AssistantStep(id: "x", tool: .createFlashcards, status: .working, title: "Writing flashcards", payload: .cards([]))
        let outcome = AssistantOutcome(text: "", citations: [], steps: [step], model: "", interrupted: true)
        let message = app.saveAssistantAnswer(outcome, to: thread)
        XCTAssertEqual(message?.steps.first?.status, .skipped)
    }

    // MARK: The work, as it is shown

    func testTheChecksPlayOutOneAtATimeAndAStepWithOneCardNeedsNoStaging() {
        let drafts = (0..<4).map { CardDraft(id: UUID(), front: "Front \($0)", back: "Back", basis: .own) }
        let step = AssistantStep(id: "c", tool: .createFlashcards, status: .proposed, title: "4 flashcards", payload: .cards(drafts))
        let frames = AIRouter.reveal(step)
        XCTAssertEqual(frames.count, 4)
        XCTAssertTrue(frames.allSatisfy { $0.status == .working }, "while the checks play the step is still working")
        let checked = frames.map { frame -> Int in
            if case .cards(let c) = frame.payload { return c.filter { $0.basis != .checking }.count }
            return -1
        }
        XCTAssertEqual(checked, [0, 1, 2, 3], "one more card is checked in each frame")
        var one = step
        one.payload = .cards([drafts[0]])
        XCTAssertTrue(AIRouter.reveal(one).isEmpty)
        var lookup = step
        lookup.payload = .lookup(NotesLookup(query: "x", hits: []))
        XCTAssertTrue(AIRouter.reveal(lookup).isEmpty)
    }

    func testCardsAndNoteWordsFlowIntoTheirStepAsTheyAreWritten() throws {
        let (app, bio, _) = world()
        let session = AssistantSession(index: app.studyIndex(currentCourseID: bio.course.id),
                                       retriever: LocalRetriever(material: []), currentCourseID: bio.course.id)
        var cards = AIRouter.workingStep(id: "a", tool: .createFlashcards, session: session, app: app)
        XCTAssertEqual(cards.status, .working)
        XCTAssertEqual(cards.courseName, "Bio 101")
        for n in 1...3 {
            AIRouter.stream(try JSONDecoder.cramless.decode(AnyJSON.self, from: Data(#"{"front":"Q\#(n)","back":"A\#(n)","evidence":null}"#.utf8)),
                            into: &cards)
        }
        guard case .cards(let written) = cards.payload else { return XCTFail("not cards") }
        XCTAssertEqual(written.map(\.front), ["Q1", "Q2", "Q3"])
        XCTAssertTrue(written.allSatisfy { $0.basis == .checking }, "a card just written is not checked yet")
        XCTAssertEqual(cards.title, "3 flashcards so far")

        var note = AIRouter.workingStep(id: "n", tool: .createNote, session: session, app: app)
        AIRouter.stream(text: "Mitosis makes ", into: &note)
        AIRouter.stream(text: "two cells.", into: &note)
        guard case .note(let draft) = note.payload else { return XCTFail("not a note") }
        XCTAssertEqual(draft.body, "Mitosis makes two cells.")
        // Cards written into a note's step (a mix-up between calls) change nothing.
        AIRouter.stream(try JSONDecoder.cramless.decode(AnyJSON.self, from: Data(#"{"front":"x","back":"y"}"#.utf8)), into: &note)
        guard case .note(let same) = note.payload else { return XCTFail("not a note") }
        XCTAssertEqual(same.body, "Mitosis makes two cells.")
    }

    // MARK: Settings

    func testSettingsKeepWhatTheStudentHandedOverAndDefaultToAskingFirst() throws {
        var s = AppSettings()
        XCTAssertTrue(s.assistant.auto.isEmpty)
        XCTAssertTrue(s.assistant.webResearch)
        s.assistant.auto = [.cards, .exams]
        s.assistant.webResearch = false
        let data = try JSONEncoder.cramless.encode(s)
        let back = try JSONDecoder.cramless.decode(AppSettings.self, from: data)
        XCTAssertEqual(back.assistant.auto, [.cards, .exams])
        XCTAssertFalse(back.assistant.webResearch)
        // Settings saved before the assistant existed, and a kind from a later version, both read.
        let old = try JSONDecoder.cramless.decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(old.assistant.auto.isEmpty)
        let later = try JSONDecoder.cramless.decode(AppSettings.self, from: Data(#"{"assistant":{"auto":["cards","tarot"],"webResearch":true}}"#.utf8))
        XCTAssertEqual(later.assistant.auto, [.cards])
    }

    func testTheConsentThatNamesCapsToolsIsVersionThree() {
        XCTAssertEqual(AIConsent.currentVersion, 3)
        var old = AppSettings()
        old.cloudConsentVersion = 2
        XCTAssertFalse(AIConsent.isGranted(old), "someone who agreed to version 2 is asked again")
    }
}

// MARK: - The mock and the contract

/// The mock transport and the relay's MOCK mode choose scripts the same way; the Deno suite holds the same table.
final class AssistantMockTests: XCTestCase {

    private func request(_ say: String, tool: String? = nil) -> AssistantRequest {
        var turns: [AssistantTurn] = []
        if let tool {
            turns = [AssistantTurn(continuation: [.object(["type": .string("function_call"), "name": .string(tool)])], results: [])]
        }
        return AssistantRequest(mode: .explain, minor: false, course: nil, messages: [TutorMessage(role: .user, text: say)], sources: [],
                                context: nil, study: StudyState(today: "2026-10-22", currentCourseId: nil, courses: [], exams: []),
                                tools: AssistantToolName.allCases, turns: turns)
    }

    func testWhatTheStudentAsksPicksTheScript() {
        let table: [(String, String)] = [
            ("Make me flashcards on mitosis", "assistant-cards"),
            ("make some cards about the cell cycle", "assistant-cards"),
            ("Quiz me on mitosis", "assistant-quiz"),
            ("Write 5 practice questions", "assistant-quiz"),
            ("Add a note summarising chapter 3", "assistant-note"),
            ("Make me a study sheet for meiosis", "assistant-note"),
            ("Plan my midterm for 12 November", "assistant-exam"),
            ("Start a practice session", "assistant-practice"),
            ("Research meiosis online", "assistant-research"),
            ("Look through my notes and make cards on anaphase", "assistant-multi-1"),
            ("Show me my progress", "assistant-open"),
            ("What is the difference between mitosis and meiosis?", "assistant-answer"),
            ("hi", "assistant-answer"),
            ("Make a card #fail", "assistant-error"),
            ("Make a card #limit", "assistant-limit"),
        ]
        for (say, expected) in table { XCTAssertEqual(request(say).mockScript, expected, say) }
        XCTAssertEqual(request("x", tool: "search_notes").mockScript, "assistant-multi-2")
        XCTAssertEqual(request("x", tool: "create_flashcards").mockScript, "assistant-cards-final")
        XCTAssertEqual(request("x", tool: "create_quiz_questions").mockScript, "assistant-quiz-final")
        XCTAssertEqual(request("x", tool: "create_note").mockScript, "assistant-note-final")
        XCTAssertEqual(request("x", tool: "create_exam").mockScript, "assistant-exam-final")
        XCTAssertEqual(request("x", tool: "start_practice").mockScript, "assistant-practice-final")
        XCTAssertEqual(request("x", tool: "research_web").mockScript, "assistant-research-final")

        // A call that failed gets its own wrap-up, whichever tool it was; cards made after a lookup, theirs.
        var failed = request("x", tool: "research_web")
        failed.turns[0].results = [AssistantResult(callId: "c", output: #"{"error":"Web research is part of Capling Pro."}"#)]
        XCTAssertEqual(failed.mockScript, "assistant-failed-final")
        func call(_ name: String, output: String) -> AssistantTurn {
            AssistantTurn(continuation: [.object(["type": .string("function_call"), "name": .string(name)])],
                          results: [AssistantResult(callId: "c", output: output)])
        }
        var lookedUp = request("x")
        lookedUp.turns = [call("search_notes", output: #"{"passages":[]}"#), call("create_flashcards", output: "{}")]
        XCTAssertEqual(lookedUp.mockScript, "assistant-multi-final")
        lookedUp.turns[0] = call("search_notes", output: #"{"passages":[{"text":"the word \"error\": in a note"}]}"#)
        XCTAssertEqual(lookedUp.mockScript, "assistant-multi-final", "an \"error\" inside a note is not a failed call")
    }

    func testEveryScriptAndRequestFixtureDecodesAndEveryEventIsOneTheAppKnows() throws {
        let scripts = ["assistant-answer", "assistant-cards", "assistant-cards-final", "assistant-error", "assistant-exam",
                       "assistant-exam-final", "assistant-limit", "assistant-multi-1", "assistant-multi-2", "assistant-note",
                       "assistant-note-final", "assistant-open", "assistant-open-final", "assistant-practice",
                       "assistant-practice-final", "assistant-quiz", "assistant-quiz-final", "assistant-research",
                       "assistant-research-final", "assistant-multi-final", "assistant-failed-final"]
        for name in scripts {
            let script = try RelayFixtures.load(AssistantScript.self, name)
            XCTAssertFalse(script.events.isEmpty, name)
            for event in script.events { XCTAssertNotNil(event.assistantEvent, "\(name): \(event.event)") }
        }
        for name in ["research-mitosis", "research-error"] {
            let script = try RelayFixtures.load(ResearchScript.self, name)
            for event in script.events { XCTAssertNotNil(event.researchEvent, "\(name): \(event.event)") }
        }
        let cards = try RelayFixtures.load(AssistantScript.self, "assistant-cards")
        if case .done(_, let stop, let continuation, _)? = cards.events.last?.assistantEvent {
            XCTAssertEqual(stop, "tool_calls")
            XCTAssertEqual(continuation.first?["name"]?.string, "create_flashcards")
        } else {
            XCTFail("a round of calls ends in done")
        }
        XCTAssertNoThrow(try fixtureRequest(AssistantRequest.self, "assistant"))
        XCTAssertNoThrow(try fixtureRequest(ResearchRequest.self, "research"))
    }

    func testTheRequestIsSentInTheWireShapeTheRelayValidates() throws {
        let sample = try fixtureRequest(AssistantRequest.self, "assistant")
        let data = try JSONEncoder.cramless.encode(sample)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["mode", "minor", "course", "messages", "sources", "study", "tools", "turns"])
        XCTAssertEqual((object["tools"] as? [String])?.first, "search_notes")
        let study = try XCTUnwrap(object["study"] as? [String: Any])
        XCTAssertNotNil(study["currentCourseId"])
        XCTAssertEqual((study["courses"] as? [[String: Any]])?.first?["id"] as? String, "c1")
    }
}

// MARK: - Reading what the model wrote

/// `AssistantDrafts`: the rules that make the model's word checkable.
final class AssistantDraftsTests: XCTestCase {
    private func json(_ text: String) -> AnyJSON {
        try! JSONDecoder.cramless.decode(AnyJSON.self, from: Data(text.utf8))
    }

    private let found: AssistantDrafts.EvidenceChecker = { _, quote in
        quote.contains("real") ? Evidence(quote: quote, sourceID: nil, pageIndex: 0, start: nil, label: "Textbook p. 87", anchorIDs: ["p0.l1"]) : nil
    }

    func testAQuoteCountsOnlyIfTheCheckerFindsIt() {
        let made = AssistantDrafts.cards(from: json("""
        {"cards":[{"front":"A thing","back":"Its meaning","evidence":{"source_id":"s1","quote":"a real quote from the notes"}},
                  {"front":"Another","back":"Meaning","evidence":{"source_id":"s1","quote":"made up by the model"}},
                  {"front":"Third","back":"Meaning","evidence":null}]}
        """), check: found, existing: [])
        XCTAssertEqual(made.drafts.map(\.basis.isFromNotes), [true, false, false])
        XCTAssertEqual(made.drafts.map(\.basis), [.notes(Evidence(quote: "a real quote from the notes", sourceID: nil, pageIndex: 0, start: nil,
                                                                  label: "Textbook p. 87", anchorIDs: ["p0.l1"])), .own, .own])
    }

    func testDuplicatesEmptyAndOverlongCardsAndTooManyAreDealtWith() {
        let many = (1...15).map { #"{"front":"Card number \#($0)","back":"Back \#($0)","evidence":null}"# }.joined(separator: ",")
        let made = AssistantDrafts.cards(from: json("""
        {"cards":[{"front":"What is mitosis?","back":"Cell division","evidence":null},
                  {"front":"what is  MITOSIS","back":"again","evidence":null},
                  {"front":"","back":"no front","evidence":null},
                  {"front":"Already there","back":"yes","evidence":null},
                  \(many)]}
        """), check: found, existing: [AssistantDrafts.key("Already there")])
        XCTAssertEqual(made.drafts.count, 12, "never more than a deck of twelve")
        XCTAssertEqual(made.drafts[0].front, "What is mitosis?")
        XCTAssertFalse(made.drafts.contains { $0.front == "what is  MITOSIS" })
        let there = made.drafts.first { $0.front == "Already there" }
        XCTAssertEqual(there?.isDuplicate, true)
        XCTAssertEqual(there?.kept, false, "a card the course already has is left out unless the student ticks it")
        XCTAssertGreaterThan(made.dropped, 0)
    }

    func testAChoiceQuestionNeedsItsRightOptionAndIsShuffledTheSameWayEveryTime() {
        let text = """
        {"questions":[{"type":"multiple_choice","question":"What does cytokinesis divide?","options":["The nucleus","The cytoplasm","The DNA"],
                       "correct_index":1,"answer":"The cytoplasm","key_ideas":null,"explanation":"x","evidence":null},
                      {"type":"multiple_choice","question":"Wrong index, right answer","options":["a","b","c"],"correct_index":0,
                       "answer":"c","key_ideas":null,"explanation":"x","evidence":null},
                      {"type":"multiple_choice","question":"No right option at all","options":["a","b","c"],"correct_index":null,
                       "answer":"zzz","key_ideas":null,"explanation":"x","evidence":null}]}
        """
        let first = AssistantDrafts.questions(from: json(text), check: found, existing: [])
        let second = AssistantDrafts.questions(from: json(text), check: found, existing: [])
        XCTAssertEqual(first.drafts.count, 2)
        XCTAssertEqual(first.dropped, 1)
        XCTAssertEqual(first.drafts.map(\.choices), second.drafts.map(\.choices), "the same question shuffles the same way")
        for q in first.drafts { XCTAssertEqual(q.choices[q.correctIndex!], q.answer) }
        XCTAssertEqual(first.drafts[1].answer, "c", "the answer's own text decides when the index disagrees")
    }

    func testTheRightOptionLandsInEveryPosition() {
        var seen = Set<Int>()
        for n in 0..<60 {
            let (options, correct) = AssistantDrafts.shuffled(["a", "b", "c", "d"], correct: 0, seed: "question \(n)")
            XCTAssertEqual(Set(options), ["a", "b", "c", "d"])
            XCTAssertEqual(options[correct], "a")
            seen.insert(correct)
        }
        XCTAssertEqual(seen, [0, 1, 2, 3])
    }

    func testFillBlankAndShortAnswerRules() {
        let made = AssistantDrafts.questions(from: json("""
        {"questions":[{"type":"fill_blank","question":"The {{nucleus}} holds the DNA.","options":null,"correct_index":null,"answer":"nucleus","key_ideas":null,"explanation":"","evidence":null},
                      {"type":"fill_blank","question":"Mitochondria make energy.","options":null,"correct_index":null,"answer":"energy","key_ideas":null,"explanation":"","evidence":null},
                      {"type":"fill_blank","question":"No blank here at all.","options":null,"correct_index":null,"answer":"giraffe","key_ideas":null,"explanation":"","evidence":null},
                      {"type":"short_answer","question":"Why do cells divide?","options":null,"correct_index":null,"answer":"To grow and heal.","key_ideas":[],"explanation":"","evidence":null},
                      {"type":"essay","question":"Write an essay","options":null,"correct_index":null,"answer":"x","key_ideas":null,"explanation":"","evidence":null}]}
        """), check: found, existing: [])
        XCTAssertEqual(made.drafts.map(\.kind), [.fillBlank, .fillBlank, .shortAnswer])
        XCTAssertEqual(made.drafts[0].answer, "nucleus")
        XCTAssertEqual(made.drafts[1].prompt, "Mitochondria make {{energy}}.", "a forgotten blank is put where the answer stands")
        XCTAssertEqual(made.drafts[2].keyIdeas, ["To grow and heal."], "a short answer with no key ideas is graded on its answer")
        XCTAssertEqual(made.dropped, 2)
    }

    func testQuotesAreComparedByLettersNotCaseQuotesOrSpacing() {
        XCTAssertTrue(AssistantDrafts.contains("it’s  the DIVISION of the cytoplasm", in: "Note: It's the division\nof the cytoplasm."))
        XCTAssertTrue(AssistantDrafts.contains("café au lait is brewed", in: "A cafe au lait is brewed daily."))
        XCTAssertFalse(AssistantDrafts.contains("short", in: "short"), "a few letters prove nothing")
        XCTAssertFalse(AssistantDrafts.contains("division of the nucleus", in: "division of the cytoplasm"))
    }

    func testAnExamNeedsARealDayThatHasNotPassed() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_792_000_000)   // mid October 2026
        let ok = try AssistantDrafts.examDate(day: "2026-11-12", time: nil, calendar: cal, now: now)
        XCTAssertFalse(ok.hasTime)
        XCTAssertEqual(cal.component(.hour, from: ok.date), 9)
        let timed = try AssistantDrafts.examDate(day: "2026-11-12", time: "14:30", calendar: cal, now: now)
        XCTAssertTrue(timed.hasTime)
        XCTAssertEqual([cal.component(.hour, from: timed.date), cal.component(.minute, from: timed.date)], [14, 30])
        XCTAssertThrowsError(try AssistantDrafts.examDate(day: "2020-01-05", time: nil, calendar: cal, now: now)) {
            XCTAssertEqual($0 as? AssistantDrafts.ExamProblem, .pastDate)
        }
        for bad in ["next Friday", "2026-13-40", "2026-02-30", "", nil] {
            XCTAssertThrowsError(try AssistantDrafts.examDate(day: bad, time: nil, calendar: cal, now: now), "\(bad ?? "nil")") {
                XCTAssertEqual($0 as? AssistantDrafts.ExamProblem, .noDate)
            }
        }
    }

    func testANoteNeedsWordsAndGetsATitle() {
        XCTAssertNil(AssistantDrafts.note(from: json(#"{"title":"x","body":"  "}"#)))
        XCTAssertEqual(AssistantDrafts.note(from: json(#"{"title":"Mitosis","body":"The cell divides in four phases."}"#))?.title, "Mitosis")
        XCTAssertEqual(AssistantDrafts.note(from: json(#"{"title":"","body":"First line\nsecond line is longer"}"#))?.title, "First line")
    }

    func testWebTilesKnowTheirSitesAndSubdomains() {
        XCTAssertEqual(WebSourceBrand.brand(for: "en.wikipedia.org").name, "Wikipedia")
        XCTAssertEqual(WebSourceBrand.brand(for: "www.britannica.com").name, "Britannica")
        XCTAssertEqual(WebSourceBrand.brand(for: "ocw.mit.edu").name, "MIT")
        XCTAssertEqual(WebSourceBrand.brand(for: "pubmed.ncbi.nlm.nih.gov").name, "NIH")
        let unknown = WebSourceBrand.brand(for: "example-school.edu")
        XCTAssertEqual(unknown.name, "example-school.edu")
        XCTAssertEqual(unknown.glyph, .letters("E", serif: false))
        XCTAssertEqual(WebSourceBrand.brand(for: "example-school.edu"), unknown, "a site always looks the same")
    }
}

/// `XCTUnwrap` for an async expression.
@MainActor
func XCTUnwrapAsync<T>(_ expression: @autoclosure () async throws -> T?, _ message: String = "", file: StaticString = #filePath,
                       line: UInt = #line) async throws -> T {
    let value = try await expression()
    return try XCTUnwrap(value, message, file: file, line: line)
}
