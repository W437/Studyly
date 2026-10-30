import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// Ask Cap's assistant over the wire: the app's real `HTTPRelayTransport` against the relay's real code in MOCK mode
/// (`cd supabase/functions && deno run -A tools/serve_mock_relay.ts`), so what the in-app mock can't show is shown here: the
/// request the app encodes passes the relay's validation, every server-sent event decodes, a round's `continuation` comes back
/// with the results, and the library ends up as it does with the in-app mock.
///
/// Opt-in, skipped unless the relay's address is given:
///   TEST_RUNNER_CRAMLESS_ASSISTANT_RELAY_URL=http://127.0.0.1:54990 SIM_ID=<udid> scripts/xcq.sh test -only-testing:CramlessTests/AssistantWireTests
@MainActor
final class AssistantWireTests: AskTestCase {

    private struct FixedToken: AccessTokenProvider {
        func accessToken() async throws -> String { "token-user-1" }
    }

    private func relayWorld(age: AppSettings.AgeBand = .adult) throws -> (app: AppModel, bio: Bio, transport: HTTPRelayTransport) {
        guard let raw = ProcessInfo.processInfo.environment["CRAMLESS_ASSISTANT_RELAY_URL"], let url = URL(string: raw) else {
            throw XCTSkip("Set TEST_RUNNER_CRAMLESS_ASSISTANT_RELAY_URL to the mock relay (supabase/functions: deno run -A tools/serve_mock_relay.ts).")
        }
        let app = makeApp(mode: .relay, consent: true, age: age)
        app.ai.assistantBeat = .zero
        let transport = HTTPRelayTransport(baseURL: url, anonKey: "anon-key", tokens: FixedToken())
        app.ai.transportOverride = transport
        return (app, makeBio(app), transport)
    }

    private func ask(_ say: String, app: AppModel, bio: Bio) async -> (thread: ChatThread, outcome: AssistantOutcome, message: ChatMessage)? {
        let thread = app.startChat(courseID: bio.course.id)
        app.addQuestion(say, to: thread)
        guard let outcome = await app.ai.assistantReply(app.assistantInput(for: thread)),
              let message = app.saveAssistantAnswer(outcome, to: thread) else { return nil }
        return (thread, outcome, message)
    }

    func testFlashcardsArriveCheckedAndAreAddedLinkedToTheirPage() async throws {
        let (app, bio, _) = try relayWorld()
        let reply = try await XCTUnwrapAsync(await ask("Make me flashcards on mitosis", app: app, bio: bio))
        XCTAssertFalse(reply.outcome.interrupted, reply.outcome.note ?? "")
        let step = try XCTUnwrap(reply.outcome.steps.first)
        XCTAssertEqual(reply.outcome.steps.count, 1)
        XCTAssertEqual(step.tool, .createFlashcards)
        XCTAssertEqual(step.status, .proposed)
        guard case .cards(let drafts) = step.payload else { return XCTFail("not cards") }
        XCTAssertEqual(drafts.count, 6)
        XCTAssertEqual(drafts.filter { $0.basis.isFromNotes }.count, 5)
        XCTAssertEqual(drafts.last?.basis, .own)
        XCTAssertTrue(reply.outcome.text.hasPrefix("I drafted 6 flashcards on mitosis"), reply.outcome.text)

        let applied = try XCTUnwrap(app.approveAssistantStep(messageID: reply.message.id, stepID: step.id))
        XCTAssertEqual(applied.createdIDs.count, 6)
        let made = bio.course.liveItems.filter { applied.createdIDs.contains($0.id) }
        XCTAssertEqual(made.filter { $0.sourceRef?.sourceID == bio.textbook.id }.count, 5)
    }

    func testALookupThenADeckIsTwoRoundsAndTheContinuationComesBack() async throws {
        let (app, bio, _) = try relayWorld()
        let reply = try await XCTUnwrapAsync(await ask("Look through my notes and make cards on anaphase", app: app, bio: bio))
        XCTAssertFalse(reply.outcome.interrupted, "the second round was refused or unreadable: \(reply.outcome.note ?? "")")
        XCTAssertEqual(reply.outcome.steps.map(\.tool), [.searchNotes, .createFlashcards])
        XCTAssertEqual(reply.outcome.steps.first?.status, .done)
        XCTAssertEqual(reply.outcome.steps.last?.status, .proposed)
        XCTAssertFalse(reply.outcome.text.isEmpty, "the last round writes Cap's note")
    }

    func testQuestionsANoteAndAnExamEachDecodeAndAdd() async throws {
        let (app, bio, _) = try relayWorld()
        let quiz = try await XCTUnwrapAsync(await ask("Quiz me on mitosis", app: app, bio: bio))
        guard case .questions(let questions) = try XCTUnwrap(quiz.outcome.steps.first).payload else { return XCTFail("not questions") }
        XCTAssertEqual(questions.map(\.kind), [.multipleChoice, .shortAnswer, .fillBlank])

        let note = try await XCTUnwrapAsync(await ask("Write me a note summarising mitosis", app: app, bio: bio))
        guard case .note(let draft) = try XCTUnwrap(note.outcome.steps.first).payload else { return XCTFail("not a note") }
        XCTAssertEqual(draft.title, "Mitosis in short")
        XCTAssertTrue(draft.body.contains("Prophase"))

        let exam = try await XCTUnwrapAsync(await ask("Plan my midterm for 12 November", app: app, bio: bio))
        guard case .exam(let plan) = try XCTUnwrap(exam.outcome.steps.first).payload else { return XCTFail("not an exam") }
        XCTAssertEqual(plan.title, "Bio 101 midterm")
    }

    func testWebResearchOverTheWireShowsItsSearchSourcesAndCitations() async throws {
        let (app, bio, _) = try relayWorld()
        let reply = try await XCTUnwrapAsync(await ask("Research mitosis vs meiosis online", app: app, bio: bio))
        XCTAssertFalse(reply.outcome.interrupted, reply.outcome.note ?? "")
        let step = try XCTUnwrap(reply.outcome.steps.first)
        XCTAssertEqual(step.tool, .researchWeb)
        XCTAssertEqual(step.status, .proposed, "the relay's account is on Pro; the app asks the student before saving")
        guard case .research(let result) = step.payload else { return XCTFail("not research") }
        XCTAssertEqual(result.phase, .done)
        XCTAssertFalse(result.queries.isEmpty)
        XCTAssertGreaterThanOrEqual(result.sources.count, 3)
        XCTAssertFalse(result.cited.isEmpty)
        XCTAssertTrue(result.text.contains("Meiosis"))
        XCTAssertTrue(result.cited.allSatisfy { URL(string: $0.url)?.scheme == "https" })
        XCTAssertEqual(bio.course.liveSources.count, 2, "nothing was saved")
    }

    func testTheFreeLimitIsToldOnceAndAFailureLeavesTheAnswerToTheTutor() async throws {
        let (app, bio, _) = try relayWorld()
        let limited = try await XCTUnwrapAsync(await ask("Make a card #limit", app: app, bio: bio))
        XCTAssertEqual(limited.outcome.limit, "drafts")
        XCTAssertEqual(limited.outcome.text, "I can't make anything new today.", "the relay ends the reply; the words are the app's")

        let thread = app.startChat(courseID: bio.course.id)
        app.addQuestion("Make a card #fail", to: thread)
        var declined = false
        var finished = false
        for await update in app.ai.assistant(app.assistantInput(for: thread)) {
            if case .declined = update { declined = true }
            if case .finished = update { finished = true }
        }
        XCTAssertTrue(declined, "an error before anything is shown falls back quietly")
        XCTAssertFalse(finished)
    }

    func testTheRelayRefusesWebResearchForAnAccountUnder18EvenIfAskedDirectly() async throws {
        let (_, _, transport) = try relayWorld()
        let request = ResearchRequest(minor: true, topic: "mitosis", focus: nil, course: "Bio 101")
        do {
            for try await _ in transport.research(request) {}
            XCTFail("the relay answered a minor's research request")
        } catch {
            // Refused, as it should be.
        }
    }
}
