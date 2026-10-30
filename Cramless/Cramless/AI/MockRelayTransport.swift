import Foundation

/// The relay with canned replies: the same fixture files the relay's MOCK mode serves
/// (`supabase/functions/_shared/fixtures`, bundled as `fixtures`), so tests, screenshots and demos tell one story
/// whichever transport runs. It waits like the real thing (generate ≈2.5 s, check ≈1.5 s, grade ≈0.9 s, confusions
/// ≈1.2 s, lecture ≈2 s) so every in-flight state of the UI gets exercised; the tutor replays its script's delays.
///
/// Grading picks `grade-correct`, `grade-partial` or `grade-incorrect` by how many key ideas have a term in the
/// response. Magic words in any text the request carries: `#fail` gives an upstream error (the tutor plays
/// `tutor-error`), `#quota` gives the quota error of `error-quota.json`.
struct MockRelayTransport: RelayTransport {

    enum Latency {
        static let generate = 2.5
        static let check = 1.5
        static let grade = 0.9
        static let confusions = 1.2
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
        return try load(GenerateResponse.self, "generate")
    }

    func check(_ request: CheckRequest) async throws -> CheckResponse {
        try await pause(Latency.check)
        try magic(request.pages.flatMap { $0.lines.map(\.text) })
        return try load(CheckResponse.self, "check")
    }

    func grade(_ request: GradeRequest) async throws -> GradeResponse {
        try await pause(Latency.grade)
        try magic([request.response])
        return try load(GradeResponse.self, Self.gradeFixture(for: request))
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
                    if question.contains("#quota") { throw Self.quotaError() }
                    let name = question.contains("#fail") ? "tutor-error"
                        : (request.mode == .hints || request.minor) ? "tutor-hints" : "tutor-explain"
                    let script = try RelayFixtures.load(TutorScript.self, name)
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

    func assistant(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
        let scale = latencyScale
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let question = request.messages.last { $0.role == .user }?.text ?? ""
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
        return try load(ConfusionsResponse.self, "confusions")
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
