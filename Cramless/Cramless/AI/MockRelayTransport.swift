import Foundation

/// The relay with canned replies: the same fixture files the relay's MOCK mode serves
/// (`supabase/functions/_shared/fixtures`, bundled as `fixtures`), so tests, screenshots and demos tell one story
/// whichever transport runs. It waits like the real thing (generate ≈2.5 s, check ≈1.5 s, grade ≈0.9 s, confusions
/// ≈1.2 s, lecture ≈2 s) so every in-flight state of the UI gets exercised; the tutor replays its script's delays.
///
/// Grading picks `grade-correct`, `grade-partial` or `grade-incorrect` by how many key ideas have a term in the
/// response. Magic words in any text the request carries: `#fail` gives an upstream error (the tutor plays
/// `tutor-error`), `#quota` gives the quota error of `error-quota.json`, `#uncovered` is a problem from a photo the notes don't hold.
struct MockRelayTransport: RelayTransport {

    enum Latency {
        static let generate = 2.5
        static let check = 1.5
        static let grade = 0.9
        static let confusions = 1.2
        static let syllabus = 1.8
        static let examMention = 0.9
        static let lastLook = 0.9
        static let lecture = 2.0
        static let cardsFromChat = 1.2
        static let transcribeImage = 1.5
        static let quota = 0.25
    }

    /// Multiplies every wait: 1 in the app, 0 in tests that don't measure time.
    var latencyScale: Double = 1

    init(latencyScale: Double = 1) {
        self.latencyScale = latencyScale
    }

    func generate(_ request: GenerateRequest) async throws -> GenerateResponse {
        try await pause(Latency.generate)
        try magic(request.pages.flatMap { $0.lines.map(\.text) } + [request.sourceTitle, request.course])
        if request.rung != nil { return try harderQuestion(for: request) }
        return try load(GenerateResponse.self, "generate")
    }

    func check(_ request: CheckRequest) async throws -> CheckResponse {
        try await pause(Latency.check)
        try magic(request.pages.flatMap { $0.lines.map(\.text) })
        return try load(CheckResponse.self, (request.reports?.isEmpty ?? true) ? "check" : "check-reported")
    }

    /// The fixture's harder question, in the format asked for, pointing at lines the request holds.
    private func harderQuestion(for request: GenerateRequest) throws -> GenerateResponse {
        var response = try load(GenerateResponse.self, "generate-rung")
        let lines = request.pages.flatMap { $0.lines.map(\.id) }
        let kind = request.formats.first ?? .apply
        response.items = response.items.map { item in
            var item = item
            item.kind = kind
            item.anchors = Array(lines.prefix(2))
            if kind == .cloze {
                item.prompt = "Fill in the blank."
                item.cloze = ClozeSpec(text: "The cell stays at {{metaphase}} when the chromatids are never pulled apart.", alternates: [[]])
                item.answer = "metaphase"
                item.keyIdeas = []
            }
            return item
        }
        return response
    }

    func grade(_ request: GradeRequest) async throws -> GradeResponse {
        try await pause(Latency.grade)
        try magic([request.response])
        return Self.naming(request, in: try load(GradeResponse.self, Self.gradeFixture(for: request)))
    }

    /// The canned grades name the sample's ideas ("k1"). A subject with ideas of its own (Teach Cap's "t1"…) gets them back under its own ids, by the same
    /// test that picked the fixture, as the real relay would answer.
    static func naming(_ request: GradeRequest, in canned: GradeResponse) -> GradeResponse {
        let ids = Set(request.keyIdeas.map(\.id))
        guard !ids.isEmpty, !canned.hits.contains(where: { ids.contains($0.ideaId) }), !canned.missing.contains(where: ids.contains) else { return canned }
        let said = request.response.lowercased()
        var response = canned
        response.hits = []
        response.missing = []
        for idea in request.keyIdeas {
            if let term = (idea.terms + [idea.label]).first(where: { !$0.isEmpty && said.contains($0.lowercased()) }) {
                response.hits.append(.init(ideaId: idea.id, quote: term))
            } else {
                response.missing.append(idea.id)
            }
        }
        return response
    }

    /// The canned grade for a request, as the relay's MOCK mode picks it: a key idea counts when one of its terms or
    /// its label is in the answer (any case); every idea → correct, none → incorrect, otherwise partial.
    static func gradeFixture(for request: GradeRequest) -> String {
        let response = request.response.lowercased()
        let hit = request.keyIdeas.filter { idea in
            (idea.terms + [idea.label]).contains { !$0.isEmpty && response.contains($0.lowercased()) }
        }.count
        if hit == 0 { return "grade-incorrect" }
        return hit == request.keyIdeas.count ? "grade-correct" : "grade-partial"
    }

    func tutor(_ request: TutorRequest) -> AsyncThrowingStream<TutorEvent, Error> {
        let scale = latencyScale
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let question = request.messages.last { $0.role == .user }?.text ?? ""
                    #if DEBUG
                    if OfflineHarness.isOffline { throw URLError(.notConnectedToInternet) }
                    #endif
                    if question.contains("#quota") { throw Self.quotaError() }
                    let script = try RelayFixtures.load(TutorScript.self, Self.tutorScript(for: request, question: question))
                    for step in script.events {
                        try await Self.sleep(Double(step.delayMs) / 1000 * scale)
                        if let event = step.tutorEvent { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: HTTPRelayTransport.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The canned reply a tutor request gets, chosen as the relay's MOCK mode chooses (`tutorFixture` in mock.ts): a problem from a photo,
    /// then "Explain my mistake", then the mode. `#uncovered` is the reply a problem the notes don't hold gets.
    static func tutorScript(for request: TutorRequest, question: String) -> String {
        if question.contains("#fail") { return "tutor-error" }
        if request.fromPhoto == true {
            var uncovered = question.contains("#uncovered")
            #if DEBUG
            if ProcessInfo.processInfo.environment["CRAMLESS_SNAP"] == "notcovered" { uncovered = true }
            #endif
            return uncovered ? "tutor-photo-uncited" : "tutor-photo"
        }
        if request.context != nil { return "tutor-mistake" }
        return request.mode == .hints || request.minor ? "tutor-hints" : "tutor-explain"
    }

    func assistant(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
        let scale = latencyScale
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let question = request.messages.last { $0.role == .user }?.text ?? ""
                    #if DEBUG
                    if OfflineHarness.isOffline { throw URLError(.notConnectedToInternet) }
                    #endif
                    if question.contains("#quota") { throw Self.quotaError() }
                    let script = try RelayFixtures.load(AssistantScript.self, request.mockScript)
                    for step in script.events {
                        try await Self.sleep(Double(step.delayMs) / 1000 * scale)
                        if let event = step.assistantEvent { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: HTTPRelayTransport.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func research(_ request: ResearchRequest) -> AsyncThrowingStream<ResearchEvent, Error> {
        let scale = latencyScale
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if request.topic.contains("#quota") { throw Self.quotaError() }
                    #if DEBUG
                    // The harness can show what a free account sees: web research is part of Capling Pro.
                    if ProcessInfo.processInfo.environment["CRAMLESS_RESEARCH"] == "pro" { throw RelayError.entitlementRequired }
                    #endif
                    let name = request.topic.lowercased().contains("#fail") ? "research-error" : "research-mitosis"
                    let script = try RelayFixtures.load(ResearchScript.self, name)
                    for step in script.events {
                        try await Self.sleep(Double(step.delayMs) / 1000 * scale)
                        if let event = step.researchEvent { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: HTTPRelayTransport.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func confusions(_ request: ConfusionsRequest) async throws -> ConfusionsResponse {
        try await pause(Latency.confusions)
        try magic(request.mistakes.map(\.given) + [request.course])
        guard request.lookAlike == true else { return try load(ConfusionsResponse.self, "confusions") }
        // The look-alike's lesson, about the two questions it was asked about.
        var response = try load(ConfusionsResponse.self, "confusions-lookalike")
        for index in response.confusions.indices { response.confusions[index].itemIds = request.mistakes.map(\.itemId) }
        return response
    }

    func lecture(_ request: LectureRequest) async throws -> LectureResponse {
        try await pause(Latency.lecture)
        try magic(request.segments.map(\.text) + [request.title])
        return try load(LectureResponse.self, "lecture")
    }

    func cardsFromChat(_ request: CardsFromChatRequest) async throws -> CardsFromChatResponse {
        try await pause(Latency.cardsFromChat)
        try magic(request.messages.map(\.text))
        return try load(CardsFromChatResponse.self, "cards-from-chat")
    }

    func transcribeImage(_ request: TranscribeImageRequest) async throws -> TranscribeImageResponse {
        try await pause(Latency.transcribeImage)
        try magic([request.label])
        return try load(TranscribeImageResponse.self, "transcribe-image")
    }

    /// The fixture, with its topic ids put right for this course by name (the request makes its ids up), and its line ids only when the
    /// request has those lines (the sample syllabus does).
    func syllabus(_ request: SyllabusRequest) async throws -> SyllabusResponse {
        try await pause(Latency.syllabus)
        var response = try load(SyllabusResponse.self, "syllabus")
        let ids = Dictionary(request.topics.map { ($0.name.lowercased(), $0.id) }, uniquingKeysWith: { a, _ in a })
        let lines = Set(request.pages.flatMap { $0.lines.map(\.id) })
        for e in response.exams.indices {
            for t in response.exams[e].topics.indices {
                let topic = response.exams[e].topics[t]
                response.exams[e].topics[t].topicId = ids[topic.name.lowercased()]
                response.exams[e].topics[t].lineIds = topic.lineIds.filter(lines.contains)
            }
        }
        return response
    }

    /// The fixture's verdict, for each mention asked about: its id, and the mention's own first candidate.
    func examMention(_ request: ExamMentionRequest) async throws -> ExamMentionResponse {
        try await pause(Latency.examMention)
        var response = try load(ExamMentionResponse.self, "exam-mention")
        guard let verdict = response.mentions.first else { return response }
        response.mentions = request.mentions.map { mention in
            var out = verdict
            out.id = mention.id
            out.date = mention.candidates.first
            return out
        }
        return response
    }

    /// The fixture's model, and for each idea asked about something the app's check is bound to keep: a term says its definition, a question with lines its first line. A question
    /// with no lines gets no sentence, as a model with nothing to go on would answer.
    func lastLook(_ request: LastLookRequest) async throws -> LastLookResponse {
        try await pause(Latency.lastLook)
        var response = try load(LastLookResponse.self, "last-look")
        response.ideas = request.ideas.compactMap { idea in
            if !idea.prompt.contains("?") { return LastLookSentence(id: idea.id, sentence: "\(idea.prompt): \(idea.answer)") }
            return idea.lines.first.map { LastLookSentence(id: idea.id, sentence: $0) }
        }
        return response
    }

    func quota() async throws -> QuotaStatus {
        try await pause(Latency.quota)
        return try load(QuotaStatus.self, "quota-free")
    }

    // MARK: Helpers

    private func pause(_ seconds: Double) async throws {
        try await Self.sleep(seconds * latencyScale)
    }

    private static func sleep(_ seconds: Double) async throws {
        do {
            if seconds > 0 { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } else { try Task.checkCancellation() }
        } catch {
            throw RelayError.cancelled
        }
    }

    private func load<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        do { return try RelayFixtures.load(type, name) } catch { throw HTTPRelayTransport.map(error) }
    }

    private func magic(_ texts: [String]) throws {
        if texts.contains(where: { $0.contains("#quota") }) { throw Self.quotaError() }
        if texts.contains(where: { $0.contains("#fail") }) { throw RelayError.upstream("The mock relay was asked to fail (#fail).") }
    }

    /// The error of `error-quota.json`, as the HTTP transport would map it.
    static func quotaError() -> RelayError {
        guard let body = try? RelayFixtures.load(RelayErrorBody.self, "error-quota") else {
            return .quotaExceeded(nil, message: "Quota reached.")
        }
        return RelayError.from(code: body.error.code, message: body.error.message, quota: body.error.quota)
    }
}
