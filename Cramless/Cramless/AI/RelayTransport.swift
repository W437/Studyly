import Foundation

/// The relay's endpoints as the app calls them. Two implementations: `HTTPRelayTransport` (the real Supabase
/// `ai` function) and `MockRelayTransport` (the bundled fixtures with believable latency). Both speak the same
/// normalized contract (RelayContract.swift); feature code never sees which one it has.
protocol RelayTransport: Sendable {
    func generate(_ request: GenerateRequest) async throws -> GenerateResponse
    func check(_ request: CheckRequest) async throws -> CheckResponse
    func grade(_ request: GradeRequest) async throws -> GradeResponse
    /// Streams the tutor's normalized events. Cancelling the consuming task cancels the request.
    func tutor(_ request: TutorRequest) -> AsyncThrowingStream<TutorEvent, Error>
    func confusions(_ request: ConfusionsRequest) async throws -> ConfusionsResponse
    func lecture(_ request: LectureRequest) async throws -> LectureResponse
    func cardsFromChat(_ request: CardsFromChatRequest) async throws -> CardsFromChatResponse
    func transcribeImage(_ request: TranscribeImageRequest) async throws -> TranscribeImageResponse
    /// Streams one round of Ask Cap's assistant: text, and calls to tools that the app runs. Cancelling the consuming task
    /// cancels the request.
    func assistant(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error>
    /// Streams web research from trusted study sites: the search as it happens, then a cited summary. Pro only.
    func research(_ request: ResearchRequest) -> AsyncThrowingStream<ResearchEvent, Error>
    func quota() async throws -> QuotaStatus
}

extension RelayTransport {
    // Transports (and the test doubles) that predate the assistant refuse it, so Ask Cap falls back to the tutor.
    func assistant(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: RelayError.upstream("The assistant isn't available here.")) }
    }

    func research(_ request: ResearchRequest) -> AsyncThrowingStream<ResearchEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: RelayError.upstream("Web research isn't available here.")) }
    }
}

/// Supplies the bearer token for relay and backend calls (a Supabase access token; an anonymous session is
/// created on first need). Implemented by `AccountService`.
protocol AccessTokenProvider: Sendable {
    func accessToken() async throws -> String
}
