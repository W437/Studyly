import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// The chat as it was stored before `ChatMessage` gained `fromPhoto`, `waitingSince` and `answersQuestionID`: to prove that a store from an
/// earlier build opens.
private enum OldChat {
    @Model
    final class ChatThread {
        @Attribute(.unique) var id: UUID
        var courseID: UUID?
        var title: String
        var modeRaw: String
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \ChatMessage.thread) var messages: [ChatMessage] = []

        init(id: UUID, title: String, now: Date) {
            self.id = id
            self.title = title
            self.modeRaw = TutorMode.hints.rawValue
            self.createdAt = now
            self.updatedAt = now
        }
    }

    @Model
    final class ChatMessage {
        @Attribute(.unique) var id: UUID
        var thread: ChatThread?
        var roleRaw: String
        var text: String
        var citationsData: Data?
        var origin: String?
        var contextItemID: UUID?
        var createdAt: Date
        var actionsData: Data?

        init(id: UUID, thread: ChatThread?, text: String, now: Date) {
            self.id = id
            self.thread = thread
            self.roleRaw = ChatRole.user.rawValue
            self.text = text
            self.createdAt = now
        }
    }
}

/// "Answer it later": the tutor only, up to three questions waiting, oldest first, each for a week at most, and never without consent.
@MainActor
final class AskLaterTests: AskTestCase {

    private func world(_ transport: any RelayTransport, consent: Bool = true, age: AppSettings.AgeBand = .adult) -> (AppModel, Bio) {
        let app = makeApp(mode: .relay, consent: consent, age: age)
        app.ai.transportOverride = transport
        app.ai.assistantRetryAt = app.now.addingTimeInterval(3600)
        return (app, makeBio(app))
    }

    private func answer(_ text: String = "After mitosis, cytokinesis divides the cytoplasm.") -> [TutorEvent] {
        [.start(model: "test"), .delta(text),
         .citation(sourceID: "s1", label: "Textbook p. 87", quote: "After mitosis, cytokinesis takes place."),
         .done(model: "test")]
    }

    /// A question asked with no connection, the reply from this iPhone, and the question kept.
    @discardableResult
    private func kept(_ app: AppModel, _ bio: Bio, _ question: String) async throws -> (thread: ChatThread, question: ChatMessage) {
        let thread = app.startChat(courseID: bio.course.id)
        let streams = AskStreams()
        streams.ask(question, in: thread, app: app)
        await streams.waitForAnswer(thread.id)
        let asked = try XCTUnwrap(thread.sortedMessages.first { $0.role == .user })
        XCTAssertTrue(app.keepForLater(questionID: asked.id))
        return (thread, asked)
    }

    // MARK: What is offered

    func testOfflineTheReplySaysSoAndOffersIt() async throws {
        let transport = ScriptedTutorTransport([], error: URLError(.notConnectedToInternet))
        let (app, bio) = world(transport)
        let streams = AskStreams()
        let thread = app.startChat(courseID: bio.course.id)
        streams.ask("What happens after mitosis?", in: thread, app: app)
        await streams.waitForAnswer(thread.id)
        let reply = try XCTUnwrap(thread.sortedMessages.last)
        XCTAssertEqual(reply.origin, "rules")
        let note = try XCTUnwrap(streams.notes[reply.id])
        XCTAssertEqual(note.note, "You're offline, so Cap answered from your notes on this iPhone.")
        XCTAssertTrue(note.offersLater)
    }

    func testAServerErrorOffersItTooAndSaysItCouldntBeReached() async throws {
        let transport = ScriptedTutorTransport([.failure(code: "upstream", message: "Cap couldn't reach the tutor.")])
        let (app, bio) = world(transport)
        let streams = AskStreams()
        let thread = app.startChat(courseID: bio.course.id)
        streams.ask("What happens after mitosis?", in: thread, app: app)
        await streams.waitForAnswer(thread.id)
        let reply = try XCTUnwrap(thread.sortedMessages.last)
        XCTAssertEqual(streams.notes[reply.id]?.note, "Cloud AI couldn't be reached, so Cap answered from your notes on this iPhone.")
        XCTAssertEqual(streams.notes[reply.id]?.offersLater, true)
    }

    func testAFreeLimitARefusalOrNoConsentOfferNothing() async throws {
        // A free limit: asking again wouldn't change it.
        let limit = ScriptedTutorTransport([], error: MockRelayTransport.quotaError())
        var (app, bio) = world(limit)
        var streams = AskStreams()
        var thread = app.startChat(courseID: bio.course.id)
        streams.ask("What happens after mitosis?", in: thread, app: app)
        await streams.waitForAnswer(thread.id)
        XCTAssertEqual(streams.notes[try XCTUnwrap(thread.sortedMessages.last).id]?.offersLater, false)

        // The model refused: the same.
        (app, bio) = world(ScriptedTutorTransport([.failure(code: "upstream", message: "Cap can't help with that one. Try asking about your notes.")]))
        streams = AskStreams()
        thread = app.startChat(courseID: bio.course.id)
        streams.ask("What happens after mitosis?", in: thread, app: app)
        await streams.waitForAnswer(thread.id)
        XCTAssertEqual(streams.notes[try XCTUnwrap(thread.sortedMessages.last).id]?.offersLater, false)

        // Cloud AI off: nothing was tried.
        (app, bio) = world(ScriptedTutorTransport(answer()), consent: false)
        streams = AskStreams()
        thread = app.startChat(courseID: bio.course.id)
        streams.ask("What happens after mitosis?", in: thread, app: app)
        await streams.waitForAnswer(thread.id)
        XCTAssertEqual(streams.notes[try XCTUnwrap(thread.sortedMessages.last).id]?.offersLater, false)
    }

    func testADeclinedRequestOrSmallTalkOffersNothingAndExplainMyMistakeNeither() async throws {
        let transport = ScriptedTutorTransport([], error: URLError(.notConnectedToInternet))
        let (app, bio) = world(transport)
        let streams = AskStreams()
        for question in ["Do my homework: problems 1 to 10.", "hi cap"] {
            let thread = app.startChat(courseID: bio.course.id)
            streams.ask(question, in: thread, app: app)
            await streams.waitForAnswer(thread.id)
            XCTAssertEqual(streams.notes[try XCTUnwrap(thread.sortedMessages.last).id]?.offersLater, false, question)
        }
        let mistake = app.startChat(courseID: bio.course.id)
        let context = TutorContext(itemPrompt: "What happens after mitosis?", expected: "Cytokinesis", given: "Nothing")
        streams.ask("What did I miss?", in: mistake, app: app, context: context, contextItemID: UUID())
        await streams.waitForAnswer(mistake.id)
        XCTAssertEqual(streams.notes[try XCTUnwrap(mistake.sortedMessages.last).id]?.offersLater, false)
    }

    // MARK: Keeping

    func testThreeAtMost() async throws {
        let (app, bio) = world(ScriptedTutorTransport([], error: URLError(.notConnectedToInternet)))
        for question in ["What is mitosis?", "What is cytokinesis?", "What is anaphase?"] { try await kept(app, bio, question) }
        XCTAssertEqual(app.waitingQuestions().count, AnswerLater.maxWaiting)
        let thread = app.startChat(courseID: bio.course.id)
        let fourth = try XCTUnwrap(app.addQuestion("What is telophase?", to: thread))
        XCTAssertFalse(app.keepForLater(questionID: fourth.id))
        XCTAssertNil(fourth.waitingSince)
    }

    func testOnlyAQuestionOfTheStudentsAndNeverTwice() async throws {
        let (app, bio) = world(ScriptedTutorTransport([], error: URLError(.notConnectedToInternet)))
        let (thread, question) = try await kept(app, bio, "What is mitosis?")
        XCTAssertFalse(app.keepForLater(questionID: question.id), "kept already")
        let reply = try XCTUnwrap(thread.sortedMessages.last { $0.role == .assistant })
        XCTAssertFalse(app.keepForLater(questionID: reply.id), "Cap's own words")
        XCTAssertFalse(app.keepForLater(questionID: UUID()))
    }

    func testNotWithoutConsentOrUnderThirteen() async throws {
        for (consent, age) in [(false, AppSettings.AgeBand.adult), (true, .under13)] {
            let (app, bio) = world(ScriptedTutorTransport(answer()), consent: consent, age: age)
            let thread = app.startChat(courseID: bio.course.id)
            let question = try XCTUnwrap(app.addQuestion("What is mitosis?", to: thread))
            XCTAssertFalse(app.keepForLater(questionID: question.id))
        }
    }

    // MARK: Answering

    func testOldestFirstInItsPlaceAndTheChatRises() async throws {
        let offline = ScriptedTutorTransport([], error: URLError(.notConnectedToInternet))
        let (app, bio) = world(offline)
        var clock = app.now
        app.clock = { clock }
        let (older, olderQuestion) = try await kept(app, bio, "What happens after mitosis?")
        clock = clock.addingTimeInterval(60)
        let (newer, newerQuestion) = try await kept(app, bio, "What is cytokinesis?")
        // The student goes on in the older chat before the connection returns.
        clock = clock.addingTimeInterval(60)
        app.addQuestion("And what about anaphase?", to: older)
        let sentAfter = try XCTUnwrap(older.sortedMessages.last)

        let online = ScriptedTutorTransport(answer())
        app.ai.transportOverride = online
        clock = clock.addingTimeInterval(60)
        let answered = await app.answerWaitingQuestions(trigger: .reconnected)
        XCTAssertEqual(answered, 2)
        XCTAssertTrue(app.waitingQuestions().isEmpty)
        XCTAssertNil(olderQuestion.waitingSince)
        XCTAssertNil(newerQuestion.waitingSince)

        // Oldest first, and each request only holds the chat up to its question.
        XCTAssertEqual(online.requests.map { $0.messages.last?.text }, ["What happens after mitosis?", "What is cytokinesis?"])
        XCTAssertFalse(online.requests[0].messages.contains { $0.text == sentAfter.text }, "what was said after it plays no part")

        // In its place: after the reply Cap gave then, before what the student said next.
        let sorted = older.sortedMessages
        let late = try XCTUnwrap(sorted.first { $0.answersQuestionID == olderQuestion.id })
        let at = try XCTUnwrap(sorted.firstIndex { $0.id == late.id })
        XCTAssertEqual(sorted[at - 1].role, .assistant)
        XCTAssertEqual(sorted[at + 1].id, sentAfter.id)
        XCTAssertEqual(late.origin, "cloud")
        XCTAssertFalse(late.citations.isEmpty, "checked against the notes, as ever")
        XCTAssertEqual(older.updatedAt, clock, "the chat rises in the history")
        XCTAssertEqual(newer.sortedMessages.last?.answersQuestionID, newerQuestion.id)
        XCTAssertTrue(ChatEntry(late).isLateAnswer)
        XCTAssertEqual(app.router.toast.map { String(localized: $0.message) }, "Answered when you were back online")
    }

    func testStillOfflineTheyWaitInOrder() async throws {
        let offline = ScriptedTutorTransport([], error: URLError(.notConnectedToInternet))
        let (app, bio) = world(offline)
        let (thread, _) = try await kept(app, bio, "What is mitosis?")
        try await kept(app, bio, "What is anaphase?")
        let before = offline.requests.count
        let count = thread.messages.count
        let answered = await app.answerWaitingQuestions(trigger: .reconnected)
        XCTAssertEqual(answered, 0)
        XCTAssertEqual(app.waitingQuestions().count, 2)
        XCTAssertEqual(offline.requests.count, before + 1, "the round stops at the first failure")
        XCTAssertEqual(thread.messages.count, count, "no offline fallback is saved as the answer")
        XCTAssertNil(app.router.toast)
    }

    func testAFreeLimitWaitsPastMidnight() async throws {
        let offline = ScriptedTutorTransport([], error: URLError(.notConnectedToInternet))
        let (app, bio) = world(offline)
        var clock = app.now
        app.clock = { clock }
        try await kept(app, bio, "What is mitosis?")
        // The relay says today's are used up: it waits, unanswered, and nothing falls back.
        app.ai.transportOverride = ScriptedTutorTransport([], error: MockRelayTransport.quotaError())
        let refused = await app.answerWaitingQuestions(trigger: .reconnected)
        XCTAssertEqual(refused, 0)
        XCTAssertEqual(app.waitingQuestions().count, 1)
        // The meter is known to be spent: not even asked until it turns over.
        let waitingOut = ScriptedTutorTransport(answer())
        app.ai.transportOverride = waitingOut
        app.ai.setServerQuota(QuotaStatus(plan: .free, meters: [QuotaMeter(key: .tutor, used: 10, limit: 10, period: .day)]))
        let stillToday = await app.answerWaitingQuestions(trigger: .active)
        XCTAssertEqual(stillToday, 0)
        XCTAssertTrue(waitingOut.requests.isEmpty)
        // The next day.
        clock = app.calendar.date(byAdding: .day, value: 1, to: clock)!
        let nextDay = await app.answerWaitingQuestions(trigger: .active)
        XCTAssertEqual(nextDay, 1)
        XCTAssertEqual(waitingOut.requests.count, 1)
    }

    func testAnAnswerCutOffPartWayKeepsWaiting() async throws {
        let (app, bio) = world(ScriptedTutorTransport([], error: URLError(.notConnectedToInternet)))
        let (thread, question) = try await kept(app, bio, "What is mitosis?")
        let count = thread.messages.count
        app.ai.transportOverride = ScriptedTutorTransport([.start(model: "t"), .delta("Mitosis is")], error: URLError(.networkConnectionLost))
        let answered = await app.answerWaitingQuestions(trigger: .reconnected)
        XCTAssertEqual(answered, 0)
        XCTAssertNotNil(question.waitingSince)
        XCTAssertEqual(thread.messages.count, count)
    }

    func testDroppedAfterSevenDays() async throws {
        let (app, bio) = world(ScriptedTutorTransport([], error: URLError(.notConnectedToInternet)))
        var clock = app.now
        app.clock = { clock }
        let (_, old) = try await kept(app, bio, "What is mitosis?")
        clock = app.calendar.date(byAdding: .day, value: 3, to: clock)!
        let (_, recent) = try await kept(app, bio, "What is anaphase?")
        clock = app.calendar.date(byAdding: .day, value: 4, to: clock)!
        let online = ScriptedTutorTransport(answer())
        app.ai.transportOverride = online
        await app.answerWaitingQuestions(trigger: .active)
        XCTAssertNil(old.waitingSince)
        XCTAssertEqual(online.requests.map { $0.messages.last?.text }, ["What is anaphase?"], "only the one still in its week")
        XCTAssertNil(recent.waitingSince)
        XCTAssertNil(old.thread?.messages.first { $0.answersQuestionID == old.id }, "dropped, not answered")
    }

    func testConsentWithdrawnOrAnAccountUnderThirteenSendsNothing() async throws {
        let (app, bio) = world(ScriptedTutorTransport([], error: URLError(.notConnectedToInternet)))
        try await kept(app, bio, "What is mitosis?")
        let online = ScriptedTutorTransport(answer())
        app.ai.transportOverride = online
        app.settings.cloudConsentVersion = 0
        await app.answerWaitingQuestions(trigger: .active)
        XCTAssertTrue(online.requests.isEmpty)
        XCTAssertEqual(app.waitingQuestions().count, 1)
        app.settings.cloudConsentVersion = AIConsent.currentVersion
        app.settings.ageBand = .under13
        await app.answerWaitingQuestions(trigger: .active)
        XCTAssertTrue(online.requests.isEmpty)
    }

    func testAKeptQuestionGoesThroughTheTutorNeverTheAssistant() async throws {
        let spy = AssistantSpyTransport()
        let (app, bio) = world(spy)
        app.ai.assistantRetryAt = nil
        let thread = app.startChat(courseID: bio.course.id)
        let question = try XCTUnwrap(app.addQuestion("Make flashcards on mitosis", to: thread))
        question.waitingSince = app.now
        app.save()
        await app.answerWaitingQuestions(trigger: .active)
        XCTAssertTrue(spy.requests.isEmpty, "nothing is drafted while the student isn't looking")
        XCTAssertTrue(thread.sortedMessages.last?.steps.isEmpty ?? false)
    }

    func testAChatFromAPhotoKeepsItsRulesWhenAnsweredLater() async throws {
        let (app, bio) = world(ScriptedTutorTransport([], error: URLError(.notConnectedToInternet)))
        let streams = AskStreams()
        let thread = app.startChat(courseID: bio.course.id)
        streams.ask("What happens after mitosis?", in: thread, app: app, fromPhoto: true)
        await streams.waitForAnswer(thread.id)
        let question = try XCTUnwrap(thread.sortedMessages.first)
        XCTAssertTrue(app.keepForLater(questionID: question.id))
        let online = ScriptedTutorTransport(answer("What does your page say comes next?"))
        app.ai.transportOverride = online
        await app.answerWaitingQuestions(trigger: .reconnected)
        XCTAssertEqual(online.requests.first?.fromPhoto, true)
        XCTAssertEqual(online.requests.first?.mode, .hints)
        XCTAssertEqual(thread.sortedMessages.last?.text, "What does your page say comes next?")
    }

    func testADeletedChatTakesItsQuestionWithIt() async throws {
        let (app, bio) = world(ScriptedTutorTransport([], error: URLError(.notConnectedToInternet)))
        let (thread, _) = try await kept(app, bio, "What is mitosis?")
        app.deleteChat(thread)
        XCTAssertTrue(app.waitingQuestions().isEmpty)
    }

    // MARK: Pure

    func testTheWeek() {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSince1970: 1_792_000_000)
        XCTAssertFalse(AnswerLater.isExpired(since: start, now: start.addingTimeInterval(6 * 86_400), calendar: calendar))
        XCTAssertTrue(AnswerLater.isExpired(since: start, now: start.addingTimeInterval(7 * 86_400), calendar: calendar))
        XCTAssertEqual(AnswerLater.maxWaiting, 3)
    }

    func testWhatCountsAsUnreachable() {
        XCTAssertTrue(RelayError.offline.isUnreachable)
        XCTAssertTrue(RelayError.upstream("The relay took too long to answer.").isUnreachable)
        XCTAssertTrue(RelayError.accountPending.isUnreachable)
        XCTAssertFalse(RelayError.upstream("Cap can't help with that one. Try asking about your notes.").isUnreachable)
        XCTAssertFalse(RelayError.quotaExceeded(nil, message: "").isUnreachable)
        XCTAssertFalse(RelayError.consentRequired.isUnreachable)
        XCTAssertFalse(RelayError.badRequest("x").isUnreachable)
        XCTAssertFalse(RelayError.unauthorized.isUnreachable)
        XCTAssertFalse(RelayError.cancelled.isUnreachable)
    }

    // MARK: The store

    func testAStoreFromBeforeTheNewFieldsOpensWithThemEmpty() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "chat-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = url.appending(path: "Cramless.store")
        let threadID = UUID()
        let messageID = UUID()
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        // The app's models as they were, with the chat as it was.
        do {
            let others = Persistence.models.filter { $0 != ChatThread.self && $0 != ChatMessage.self }
            let schema = Schema(others + [OldChat.ChatThread.self, OldChat.ChatMessage.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: file)])
            let context = ModelContext(container)
            let thread = OldChat.ChatThread(id: threadID, title: "Mitosis", now: now)
            context.insert(thread)
            let message = OldChat.ChatMessage(id: messageID, thread: thread, text: "What is mitosis?", now: now)
            context.insert(message)
            try context.save()
        }
        let schema = Persistence.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: file)])
        let message = try XCTUnwrap(try ModelContext(container).fetch(FetchDescriptor<ChatMessage>()).first)
        XCTAssertEqual(message.id, messageID)
        XCTAssertEqual(message.text, "What is mitosis?")
        XCTAssertFalse(message.fromPhoto)
        XCTAssertNil(message.waitingSince)
        XCTAssertNil(message.answersQuestionID)
        XCTAssertEqual(message.thread?.id, threadID)
        XCTAssertFalse(message.thread?.isFromPhoto ?? true)
    }
}
