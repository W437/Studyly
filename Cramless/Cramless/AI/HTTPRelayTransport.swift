import Foundation

/// The real relay: the Supabase `ai` Edge Function at `<supabaseURL>/functions/v1/ai/<route>`.
///
/// Every call carries the project's anon key (`apikey`) and the person's access token (`Authorization: Bearer`)
/// from an `AccessTokenProvider` (`AccountService`). Bodies are the contract's camelCase JSON with ISO 8601 dates.
/// A non-2xx answer is read as the relay's error envelope (`{"error": {"code", "message", …}}`) and mapped to a
/// `RelayError`; network failures map to `.offline`, cancellation to `.cancelled`. The tutor streams server-sent
/// events through `SSEParser`; cancelling the consuming task cancels the request.
struct HTTPRelayTransport: RelayTransport {

    /// The relay's routes, as path components after `/functions/v1/ai/`.
    enum Route: String, CaseIterable, Sendable {
        case generate
        case check
        case grade
        case tutor
        case confusions
        case lecture
        case cardsFromChat = "cards-from-chat"
        case transcribeImage = "transcribe-image"
        case quota

        var method: String { self == .quota ? "GET" : "POST" }

        /// Seconds without data before the request fails. Long jobs get room; grading must stay snappy because
        /// the person already has the offline grade on screen.
        var timeout: TimeInterval {
            switch self {
            case .generate: 75
            case .check: 45
            case .grade: 20
            case .tutor: 30
            case .confusions: 30
            case .lecture: 90
            case .cardsFromChat: 30
            case .transcribeImage: 60
            case .quota: 10
            }
        }
    }

    let baseURL: URL
    let anonKey: String
    let tokens: any AccessTokenProvider
    let session: URLSession

    init(baseURL: URL, anonKey: String, tokens: any AccessTokenProvider, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.tokens = tokens
        self.session = session
    }

    func url(for route: Route) -> URL {
        baseURL.appending(path: "functions/v1/ai/\(route.rawValue)")
    }

    // MARK: RelayTransport

    func generate(_ request: GenerateRequest) async throws -> GenerateResponse { try await send(.generate, request) }
    func check(_ request: CheckRequest) async throws -> CheckResponse { try await send(.check, request) }
    func grade(_ request: GradeRequest) async throws -> GradeResponse { try await send(.grade, request) }
    func confusions(_ request: ConfusionsRequest) async throws -> ConfusionsResponse { try await send(.confusions, request) }
    func lecture(_ request: LectureRequest) async throws -> LectureResponse { try await send(.lecture, request) }
    func cardsFromChat(_ request: CardsFromChatRequest) async throws -> CardsFromChatResponse { try await send(.cardsFromChat, request) }
    func transcribeImage(_ request: TranscribeImageRequest) async throws -> TranscribeImageResponse { try await send(.transcribeImage, request) }
    func quota() async throws -> QuotaStatus { try await send(.quota, Optional<Int>.none) }

    func tutor(_ request: TutorRequest) -> AsyncThrowingStream<TutorEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = try JSONEncoder.cramless.encode(request)
                    // An error before the stream starts is an ordinary envelope; `unauthorized` is retried once with
                    // a token asked for again (the contract's "refresh the session, then retry once").
                    var bytes: URLSession.AsyncBytes
                    var attempt = 0
                    while true {
                        attempt += 1
                        let urlRequest = try await makeRequest(.tutor, body: body, accept: "text/event-stream")
                        let (opened, response) = try await session.bytes(for: urlRequest)
                        guard let http = response as? HTTPURLResponse else { throw RelayError.upstream("No response from the relay.") }
                        if (200..<300).contains(http.statusCode) {
                            bytes = opened
                            break
                        }
                        var data = Data()
                        for try await byte in opened {
                            data.append(byte)
                            if data.count > 64_000 { break }
                        }
                        let error = Self.error(status: http.statusCode, body: data)
                        if error == .unauthorized, attempt == 1 { continue }
                        throw error
                    }
                    var parser = SSEParser()
                    var ended = false
                    for try await byte in bytes {
                        guard let sse = parser.feed(byte: byte), let event = Self.tutorEvent(from: sse) else { continue }
                        continuation.yield(event)
                        switch event {
                        case .done, .failure: ended = true
                        default: break
                        }
                        if ended { break }
                    }
                    _ = parser.finish()
                    if !ended { throw RelayError.upstream("The answer was cut off.") }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Requests

    private func send<Body: Encodable, Response: Decodable>(_ route: Route, _ body: Body?) async throws -> Response {
        do {
            let data = try body.map { try JSONEncoder.cramless.encode($0) }
            do {
                return try await attempt(route, data)
            } catch RelayError.unauthorized {
                // The contract: refresh the session, then retry once. The retry asks the provider for the token
                // again, which refreshes a session that is about to lapse.
                return try await attempt(route, data)
            }
        } catch {
            throw Self.map(error)
        }
    }

    private func attempt<Response: Decodable>(_ route: Route, _ data: Data?) async throws -> Response {
        let request = try await makeRequest(route, body: data, accept: "application/json")
        let (payload, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RelayError.upstream("No response from the relay.") }
        guard (200..<300).contains(http.statusCode) else { throw Self.error(status: http.statusCode, body: payload) }
        do {
            return try JSONDecoder.cramless.decode(Response.self, from: payload)
        } catch {
            throw RelayError.decoding("\(route.rawValue): \(error)")
        }
    }

    /// The request for a route, with the anon key and a fresh access token. Built at call time, so the token is
    /// whatever is current after any wait.
    func makeRequest(_ route: Route, body: Data?, accept: String) async throws -> URLRequest {
        let token: String
        do {
            token = try await tokens.accessToken()
        } catch let error as RelayError {
            throw error
        } catch {
            throw RelayError.unauthorized
        }
        var request = URLRequest(url: url(for: route), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: route.timeout)
        request.httpMethod = route.method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    // MARK: Errors

    /// A non-2xx answer: the relay's envelope when it sent one, otherwise the status as `docs/relay-contract.md`
    /// assigns them (403 is `entitlement_required`, 429 a quota, 5xx upstream).
    static func error(status: Int, body: Data) -> RelayError {
        if let envelope = try? JSONDecoder.cramless.decode(RelayErrorBody.self, from: body) {
            return RelayError.from(code: envelope.error.code, message: envelope.error.message, quota: envelope.error.quota)
        }
        switch status {
        case 401: return .unauthorized
        case 402, 403: return .entitlementRequired
        case 429: return .upstream("Too many requests right now.")   // a rate limit with no envelope is not a free limit
        case 400, 404, 405, 409, 410, 413, 422: return .badRequest("The relay couldn't take the request (\(status)).")
        default: return .upstream("The relay answered \(status).")
        }
    }

    static func map(_ error: Error) -> RelayError {
        if let relay = error as? RelayError { return relay }
        if error is CancellationError { return .cancelled }
        if let url = error as? URLError {
            switch url.code {
            case .cancelled:
                return .cancelled
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed, .callIsActive:
                return .offline
            case .timedOut:
                return .upstream("The relay took too long to answer.")
            default:
                return .upstream(url.localizedDescription)
            }
        }
        if error is DecodingError || error is EncodingError { return .decoding(String(describing: error)) }
        return .upstream(error.localizedDescription)
    }

    // MARK: Tutor events

    /// The relay's SSE event as a `TutorEvent`. The data is the same JSON payload the fixtures' scripts hold; a
    /// `delta` whose data isn't JSON is taken as plain text. Unknown events (pings) are skipped.
    static func tutorEvent(from sse: SSEEvent) -> TutorEvent? {
        let payload = (try? JSONDecoder.cramless.decode(TutorScriptEvent.Payload.self, from: Data(sse.data.utf8)))
        if payload == nil, sse.event == "delta" { return .delta(sse.data) }
        let data = payload ?? TutorScriptEvent.Payload()
        return TutorScriptEvent(event: sse.event, delayMs: 0, data: data).tutorEvent
    }
}
