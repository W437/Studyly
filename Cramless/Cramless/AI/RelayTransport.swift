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
    func quota() async throws -> QuotaStatus
}

/// Supplies the bearer token for relay and backend calls (a Supabase access token; an anonymous session is
/// created on first need). Implemented by `AccountService`.
protocol AccessTokenProvider: Sendable {
    func accessToken() async throws -> String
}
