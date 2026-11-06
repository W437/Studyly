import UIKit
import XCTest
@testable import Cramless

/// A relay that plays a tutor script of the test's own (each turn its own events), and records the requests.
final class ScriptedTutorTransport: RelayTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [TutorRequest] = []
    /// One script a request, the last repeating. An error ends the stream with it.
    var scripts: [(events: [TutorEvent], error: Error?)]
    /// Waits for the test to look at what has reached the student so far, before the last event.
    var gate: AsyncStream<Void>?

    init(_ events: [TutorEvent], error: Error? = nil) { scripts = [(events, error)] }

    var requests: [TutorRequest] { lock.withLock { _requests } }

    func tutor(_ request: TutorRequest) -> AsyncThrowingStream<TutorEvent, Error> {
        let script: (events: [TutorEvent], error: Error?) = lock.withLock {
            _requests.append(request)
            return scripts[min(_requests.count - 1, scripts.count - 1)]
        }
        let gate = self.gate
        return AsyncThrowingStream { continuation in
            Task {
                for (index, event) in script.events.enumerated() {
                    if index == script.events.count - 1, let gate { for await _ in gate { break } }
                    continuation.yield(event)
                }
                continuation.finish(throwing: script.error)
            }
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

/// "Snap a problem": the words read on this iPhone, hints first for everyone, and a cloud answer shown only with a citation that is really in the notes.
@MainActor
final class AskSnapTests: AskTestCase {
    private let realQuote = "Each daughter cell is genetically identical to the parent cell, with the same number of chromosomes."

    private func reply(_ text: String, quote: String?) -> [TutorEvent] {
        var events: [TutorEvent] = [.start(model: "test"), .delta(text)]
        if let quote { events.append(.citation(sourceID: "s1", label: "Textbook p. 87", quote: quote)) }
        return events + [.done(model: "test")]
    }

    private func world(_ transport: (any RelayTransport)? = nil, consent: Bool = true, age: AppSettings.AgeBand = .adult, mode: AppConfig.AIMode = .relay) -> (AppModel, Bio) {
        let app = makeApp(mode: mode, consent: consent, age: age)
        if let transport { app.ai.transportOverride = transport }
        return (app, makeBio(app))
    }

    private func asked(_ app: AppModel, _ bio: Bio, _ text: String = "How many chromosomes does each daughter cell have?") async -> (AskStreams, ChatThread) {
        let streams = AskStreams()
        let thread = app.startChat(courseID: bio.course.id)
        streams.ask(text, in: thread, app: app, fromPhoto: true)
        await streams.waitForAnswer(thread.id)
        return (streams, thread)
    }

    // MARK: The message and the chat

    func testTheQuestionRemembersItsPhotoAndAPlainChatStaysPlain() throws {
        let (app, bio) = world()
        let plain = app.startChat(courseID: bio.course.id)
        let typed = try XCTUnwrap(app.addQuestion("What is mitosis?", to: plain))
        XCTAssertFalse(typed.fromPhoto)
        XCTAssertFalse(plain.isFromPhoto)
        XCTAssertFalse(app.tutorInput(for: plain).fromPhoto)

        let snapped = app.startChat(courseID: bio.course.id)
        XCTAssertTrue(try XCTUnwrap(app.addQuestion("Homework 3. Solve it.", to: snapped, fromPhoto: true)).fromPhoto)
        XCTAssertTrue(snapped.isFromPhoto)
        XCTAssertEqual(snapped.title, "Homework 3. Solve it.")
        let first = app.tutorInput(for: snapped)
        XCTAssertTrue(first.fromPhoto)
        XCTAssertTrue(first.lastIsPhotoText)
        // A question typed after it: the chat is still from a photo, and this one is the student's own words.
        app.addQuestion("is it 46?", to: snapped)
        let later = app.tutorInput(for: snapped)
        XCTAssertTrue(later.fromPhoto)
        XCTAssertFalse(later.lastIsPhotoText)
        XCTAssertTrue(ChatEntry(try XCTUnwrap(snapped.sortedMessages.first)).fromPhoto)
    }

    // MARK: Hints first, whoever asks

    func testAnAdultOnJustExplainStillGetsHintsAndTheRequestSaysSo() async throws {
        let transport = ScriptedTutorTransport(reply("Which line of your notes says what each daughter cell gets?", quote: realQuote))
        let (app, bio) = world(transport)
        app.setTutorMode(.explain)
        let (_, thread) = await asked(app, bio)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.fromPhoto, true)
        XCTAssertEqual(request.mode, .hints)
        XCTAssertEqual(app.settings.tutorMode, .explain, "the student's own choice stays for their other chats")
        XCTAssertEqual(thread.sortedMessages.last?.origin, "cloud")
    }

    func testAFollowUpStaysOnHintsAndAnOrdinaryChatDoesNotSayFromPhoto() async throws {
        let transport = ScriptedTutorTransport(reply("What does that line say?", quote: realQuote))
        let (app, bio) = world(transport)
        app.setTutorMode(.explain)
        let (streams, thread) = await asked(app, bio)
        streams.ask("the same number?", in: thread, app: app)
        await streams.waitForAnswer(thread.id)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[1].fromPhoto, true)
        XCTAssertEqual(transport.requests[1].mode, .hints)

        let plain = app.startChat(courseID: bio.course.id)
        streams.ask("What is mitosis?", in: plain, app: app)
        await streams.waitForAnswer(plain.id)
        XCTAssertNil(transport.requests[2].fromPhoto)
        XCTAssertEqual(transport.requests[2].mode, .explain)
    }

    func testAPhotoChatNeverGoesToTheAssistant() async throws {
        let transport = ScriptedTutorTransport(reply("Which line says it?", quote: realQuote))
        let (app, bio) = world(transport)
        XCTAssertTrue(app.ai.assistantAvailable(question: "How many chromosomes?", hasContext: false), "the assistant would be asked otherwise")
        let (streams, thread) = await asked(app, bio)
        XCTAssertEqual(transport.requests.count, 1, "the tutor's route, at once")
        // Nor its follow-ups, which would otherwise look like a request to make something.
        streams.ask("Make flashcards on this", in: thread, app: app)
        await streams.waitForAnswer(thread.id)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testTheWordsOfAPhotoAreNotARequestToDecline() async throws {
        let transport = ScriptedTutorTransport(reply("What does your page say about it?", quote: realQuote))
        let (app, bio) = world(transport)
        let header = "Do my homework: problems 1 to 10. Mitosis chromosomes."
        XCTAssertNotNil(TutorPolicy.decline(for: header), "typed, Cap would decline it")
        let (_, thread) = await asked(app, bio, header)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertFalse(TutorPolicy.isDecline(thread.sortedMessages.last?.text ?? ""))
        XCTAssertEqual(thread.sortedMessages.last?.origin, "cloud")

        // A student who then types it is another matter.
        let streams = AskStreams()
        streams.ask(header, in: thread, app: app)
        await streams.waitForAnswer(thread.id)
        XCTAssertEqual(transport.requests.count, 1, "no model is asked")
        XCTAssertEqual(thread.sortedMessages.last?.text, TutorPolicy.cheatRefusal)
    }

    // MARK: The citation rule

    func testAnAnswerIsHeldUntilCompleteAndShownWithAVerifiedCitation() async throws {
        let transport = ScriptedTutorTransport(reply("Your page has the line. What does it say?", quote: realQuote))
        let (gate, open) = AsyncStream<Void>.makeStream()
        transport.gate = gate
        let (app, bio) = world(transport)
        let streams = AskStreams()
        let thread = app.startChat(courseID: bio.course.id)
        streams.ask("How many chromosomes does each daughter cell have?", in: thread, app: app, fromPhoto: true)
        await eventually { !transport.requests.isEmpty }
        try? await Task.sleep(for: .milliseconds(120))
        // The words and the quote have arrived from the relay, and none of it has reached the student.
        XCTAssertEqual(streams.live[thread.id]?.text, "")
        XCTAssertNil(streams.live[thread.id]?.origin)
        open.yield()
        await streams.waitForAnswer(thread.id)
        let answer = try XCTUnwrap(thread.sortedMessages.last)
        XCTAssertEqual(answer.text, "Your page has the line. What does it say?")
        XCTAssertEqual(answer.citations.map(\.quote), [realQuote])
        XCTAssertEqual(answer.citations.first?.sourceID, bio.textbook.id)
    }

    func testAQuoteThatIsNotInTheNotesMeansTheAppSaysSoInstead() async throws {
        let transport = ScriptedTutorTransport(reply("The answer is 46, as your page says.", quote: "Every cell in the body has 46 chromosomes."))
        let (app, bio) = world(transport)
        let (_, thread) = await asked(app, bio)
        let answer = try XCTUnwrap(thread.sortedMessages.last)
        XCTAssertEqual(answer.text, LocalTutor.snapNotCovered)
        XCTAssertTrue(answer.citations.isEmpty)
        XCTAssertFalse(answer.text.contains("46"), "what it wrote is never shown")
        XCTAssertTrue(ChatEntry(answer).isNotCovered, "muted, with Add notes on this")
    }

    func testNoCitationAtAllAndTheModelsOwnNotCoveredAreTheAppsLine() async throws {
        for (text, quote) in [("Use the power rule: the answer is 9.", nil as String?),
                              ("I couldn't find this topic in what you've added.", nil),
                              ("I couldn't find this topic in what you've added.", realQuote)] {
            let (app, bio) = world(ScriptedTutorTransport(reply(text, quote: quote)))
            let (_, thread) = await asked(app, bio, "Find the integral of x squared from 0 to 3.")
            let answer = try XCTUnwrap(thread.sortedMessages.last)
            XCTAssertEqual(answer.text, LocalTutor.snapNotCovered, text)
            XCTAssertEqual(LocalTutor.snapNotCovered, "I couldn't find this topic in your notes, so I won't guess. Add the chapter it's from and snap it again.")
            XCTAssertTrue(answer.citations.isEmpty)
        }
    }

    func testLaterInTheChatAReplyWithNoQuoteAsksWhichStepNotForTheChapter() async throws {
        let transport = ScriptedTutorTransport(reply("Which line says it?", quote: realQuote))
        transport.scripts.append((reply("The answer is 46.", quote: nil), nil))
        let (app, bio) = world(transport)
        let (streams, thread) = await asked(app, bio)
        streams.ask("just tell me", in: thread, app: app)
        await streams.waitForAnswer(thread.id)
        let answer = try XCTUnwrap(thread.sortedMessages.last)
        XCTAssertEqual(answer.text, LocalTutor.snapUnverified)
        XCTAssertFalse(ChatEntry(answer).isNotCovered, "the topic is in the notes: this one reply couldn't be pointed to")
    }

    func testTheMocksTwoRepliesTellTheStory() async throws {
        let (app, bio) = world(mode: .mock)
        let (_, covered) = await asked(app, bio)
        XCTAssertFalse(try XCTUnwrap(covered.sortedMessages.last).citations.isEmpty)
        let (_, beyond) = await asked(app, bio, "Find the integral of x squared. #uncovered")
        XCTAssertEqual(beyond.sortedMessages.last?.text, LocalTutor.snapNotCovered)
    }

    func testAFailureBeforeTheAnswerIsCompleteFallsBackToTheOfflineHint() async throws {
        // Words arrived, then the connection went: a held answer has shown nothing, so nothing is half-shown.
        let transport = ScriptedTutorTransport([.start(model: "test"), .delta("The answer is")], error: URLError(.networkConnectionLost))
        let (app, bio) = world(transport)
        let (streams, thread) = await asked(app, bio)
        let answer = try XCTUnwrap(thread.sortedMessages.last)
        XCTAssertEqual(answer.origin, "rules")
        XCTAssertFalse(answer.text.contains("The answer is"))
        let note = try XCTUnwrap(streams.notes[answer.id])
        XCTAssertEqual(note.note, "You're offline, so Cap answered from your notes on this iPhone.")
        XCTAssertTrue(note.offersLater)
    }

    func testAPhotoProblemThatSharesNoWordWithALongMaterialIsStillTheModelsToJudge() async throws {
        // Too much to send whole and no word in common: an even spread of the notes goes, and what the model says about it is the app's line.
        let transport = ScriptedTutorTransport(reply("I couldn't find this topic in what you've added.", quote: nil))
        let app = makeApp(mode: .relay, consent: true)
        app.ai.transportOverride = transport
        let course = Course(name: "Law", now: app.now)
        app.context.insert(course)
        let long = Source(course: course, kind: .text, title: "Reading A", status: .ready, now: app.now)
        app.context.insert(long)
        course.sources.append(long)
        for page in 0..<40 {
            let lines = TutorFixtures.lines((0..<8).map { TutorFixtures.paragraph(page * 10 + $0) })
            let stored = SourcePage(source: long, pageIndex: page, label: "\(page + 1)", text: lines.map(\.text).joined(separator: "\n"), lines: lines)
            app.context.insert(stored)
            long.pages.append(stored)
        }
        app.save()
        let streams = AskStreams()
        let thread = app.startChat(courseID: course.id)
        streams.ask("Compute the eigenvalues.", in: thread, app: app, fromPhoto: true)
        await streams.waitForAnswer(thread.id)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertFalse(request.sources.isEmpty)
        XCTAssertEqual(request.fromPhoto, true)
        XCTAssertEqual(thread.sortedMessages.last?.text, LocalTutor.snapNotCovered)
    }

    // MARK: Who may

    func testWithoutConsentTheOfflineHintOffersThePhotosCard() async throws {
        let transport = ScriptedTutorTransport(reply("x", quote: nil))
        let (app, bio) = world(transport, consent: false)
        XCTAssertTrue(app.ai.canSnapProblem, "the camera shows: Cloud AI can be turned on")
        let (streams, thread) = await asked(app, bio)
        XCTAssertTrue(transport.requests.isEmpty, "nothing leaves without consent")
        let answer = try XCTUnwrap(thread.sortedMessages.last)
        XCTAssertEqual(answer.origin, "rules")
        XCTAssertEqual(streams.notes[answer.id]?.suggestion, .allowCloud(feature: "Work through a problem from a photo"))
    }

    func testUnderThirteenOrNoRelayHidesTheCamera() {
        // Each held for the call: the router holds its app weakly.
        let child = makeApp(mode: .relay, consent: true, age: .under13)
        XCTAssertFalse(child.ai.canSnapProblem)
        let local = makeApp(mode: .local)
        XCTAssertFalse(local.ai.canSnapProblem)
        let teen = makeApp(mode: .relay, consent: true, age: .teen)
        XCTAssertTrue(teen.ai.canSnapProblem)
    }

    func testUnderEighteenIsMarkedMinorOnHints() async throws {
        let transport = ScriptedTutorTransport(reply("Which line says it?", quote: realQuote))
        let (app, bio) = world(transport, age: .teen)
        _ = await asked(app, bio)
        XCTAssertEqual(transport.requests.first?.minor, true)
        XCTAssertEqual(transport.requests.first?.mode, .hints)
        XCTAssertEqual(transport.requests.first?.fromPhoto, true)
    }

    func testOneTutorMessageATurnOnTheMeter() async throws {
        let (app, bio) = world(ScriptedTutorTransport(reply("Which line says it?", quote: realQuote)))
        let before = app.ai.usage.cloudUsed(.tutor)
        _ = await asked(app, bio)
        XCTAssertEqual(app.ai.usage.cloudUsed(.tutor), before + 1)
    }

    // MARK: The relay's scripts

    func testTheMockChoosesAsTheRelayDoes() throws {
        var request = try fixtureRequest(TutorRequest.self, "tutor")
        XCTAssertEqual(MockRelayTransport.tutorScript(for: request, question: "x"), "tutor-hints")
        request.mode = .explain
        XCTAssertEqual(MockRelayTransport.tutorScript(for: request, question: "x"), "tutor-explain")
        request.context = TutorContext(itemPrompt: "p", expected: "e", given: "g")
        XCTAssertEqual(MockRelayTransport.tutorScript(for: request, question: "x"), "tutor-mistake")
        request.fromPhoto = true
        XCTAssertEqual(MockRelayTransport.tutorScript(for: request, question: "x"), "tutor-photo")
        XCTAssertEqual(MockRelayTransport.tutorScript(for: request, question: "x #uncovered"), "tutor-photo-uncited")
        XCTAssertEqual(MockRelayTransport.tutorScript(for: request, question: "x #fail"), "tutor-error")
    }

    // MARK: Words, not the photo

    func testTheConsentAndPurposeWordsSayWhatHappens() throws {
        let plist = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String)
        XCTAssertTrue(plist.contains("a problem you're stuck on"), plist)
        XCTAssertEqual(AIJob.snapFeature, "Work through a problem from a photo")
    }
}
