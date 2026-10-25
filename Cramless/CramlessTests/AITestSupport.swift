import XCTest
@testable import Cramless

/// Shared pieces for the AI lane's tests: an app wired for tests (in-memory store, its own defaults, no side
/// effects, no device model), the sample page, the fixtures, a transport that records what it was asked, and a
/// URL protocol stub for the HTTP transport.
@MainActor
enum AITestSupport {
    static func makeApp(mode: AppConfig.AIMode = .local, consent: Bool = false, photos: Bool = false,
                        age: AppSettings.AgeBand = .adult, level: AppSettings.Level? = .college) -> AppModel {
        let defaults = UserDefaults(suiteName: "capling.ai.tests.\(UUID().uuidString)")!
        let config = AppConfig(supabaseURL: nil, supabaseAnonKey: nil, aiMode: mode, isHarness: false, inMemoryStore: true,
                               seedDemoData: false, environment: ["XCTestConfigurationFilePath": "ai-tests"])
        let app = AppModel(config: config, defaults: defaults)
        var settings = app.settings
        settings.cloudConsentVersion = consent ? AIConsent.currentVersion : 0
        settings.sendPhotos = photos
        settings.ageBand = age
        settings.level = level
        app.settings = settings
        app.ai.mockLatencyScale = 0
        app.ai.streamPause = .zero
        app.ai.probe = FixedOnDeviceProbe(.unavailable(.notChecked))
        return app
    }

    static var sampleLines: [TextLine] { SamplePage.ocr()!.lines }
    static var samplePage: PageText { PageText(index: 0, label: "87", lines: sampleLines) }
    static var sampleInput: GenerationInput {
        GenerationInput(course: "Bio 101", sourceTitle: "Biology textbook", level: "college", pages: [samplePage])
    }

    static var fixture: GenerateResponse { try! RelayFixtures.load(GenerateResponse.self, "generate") }
    static func fixtureItem(_ id: String) -> GeneratedItem { fixture.items.first { $0.id == id }! }

    /// The lecture the demo world records (`SampleData`).
    static var lectureSegments: [TranscriptSegment] {
        [
            TranscriptSegment(id: "s1", start: 178, end: 190, text: "OK, so last time we finished interphase. Today: what actually happens when the cell divides."),
            TranscriptSegment(id: "s2", start: 192, end: 338, text: "Prophase first. The chromatin condenses, and you can finally see chromosomes under the microscope."),
            TranscriptSegment(id: "s3", start: 340, end: 458, text: "Then the nuclear envelope breaks down and the spindle starts forming from the centrosomes."),
            TranscriptSegment(id: "s4", start: 460, end: 723, text: "Metaphase is the easy one to spot: everything lines up along the middle, the metaphase plate."),
            TranscriptSegment(id: "s5", start: 725, end: 918, text: "This one will be on the midterm, by the way: anaphase is where the sister chromatids get pulled apart."),
            TranscriptSegment(id: "s6", start: 920, end: 1040, text: "And telophase is basically prophase in reverse. The nuclear envelopes re-form around each set."),
        ]
    }

    static let textbookID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let lectureID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    static var material: [TutorMaterial] {
        [TutorMaterial(sourceID: textbookID, title: "Biology textbook", kind: .sample, pages: [samplePage]),
         TutorMaterial(sourceID: lectureID, title: "Lecture 6: Cell division", kind: .lecture, segments: lectureSegments)]
    }

    /// The text of each mark, read back from the answer.
    static func marked(_ outcome: GradeOutcome, in answer: String) -> [String] {
        let chars = Array(answer)
        return outcome.highlightMarks.map { String(chars[$0.range]) }
    }
}

/// A request example from `fixtures/requests` (the relay's tests read the same files).
func fixtureRequest<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "fixtures/requests"),
                            "missing fixtures/requests/\(name).json")
    return try JSONDecoder.cramless.decode(type, from: Data(contentsOf: url))
}

/// A transport that records every request and answers from the fixtures (no waiting), with hooks to fail a route
/// or run code in the middle of a call (to change settings "during the wait").
final class RecordingTransport: RelayTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let base = MockRelayTransport(latencyScale: 0)
    private var _calls: [String] = []
    private var _generate: [GenerateRequest] = []
    private var _check: [CheckRequest] = []
    private var _grade: [GradeRequest] = []
    private var _tutor: [TutorRequest] = []

    /// Errors to throw, by route name.
    var failures: [String: RelayError] = [:]
    /// Runs on the main actor while `generate` is "on the network".
    var duringGenerate: (@MainActor () -> Void)?

    var calls: [String] { lock.withLock { _calls } }
    var generateRequests: [GenerateRequest] { lock.withLock { _generate } }
    var checkRequests: [CheckRequest] { lock.withLock { _check } }
    var gradeRequests: [GradeRequest] { lock.withLock { _grade } }
    var tutorRequests: [TutorRequest] { lock.withLock { _tutor } }

    private func record(_ name: String) throws {
        let failure: RelayError? = lock.withLock {
            _calls.append(name)
            return failures[name]
        }
        if let failure { throw failure }
    }

    func generate(_ request: GenerateRequest) async throws -> GenerateResponse {
        lock.withLock { _generate.append(request) }
        if let hook = duringGenerate { await MainActor.run { hook() } }
        try record("generate")
        return try await base.generate(request)
    }

    func check(_ request: CheckRequest) async throws -> CheckResponse {
        lock.withLock { _check.append(request) }
        try record("check")
        return try await base.check(request)
    }

    func grade(_ request: GradeRequest) async throws -> GradeResponse {
        lock.withLock { _grade.append(request) }
        try record("grade")
        return try await base.grade(request)
    }

    func tutor(_ request: TutorRequest) -> AsyncThrowingStream<TutorEvent, Error> {
        lock.withLock { _tutor.append(request) }
        do { try record("tutor") } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        return base.tutor(request)
    }

    func confusions(_ request: ConfusionsRequest) async throws -> ConfusionsResponse {
        try record("confusions")
        return try await base.confusions(request)
    }

    func lecture(_ request: LectureRequest) async throws -> LectureResponse {
        try record("lecture")
        return try await base.lecture(request)
    }

    func cardsFromChat(_ request: CardsFromChatRequest) async throws -> CardsFromChatResponse {
        try record("cardsFromChat")
        return try await base.cardsFromChat(request)
    }

    func transcribeImage(_ request: TranscribeImageRequest) async throws -> TranscribeImageResponse {
        try record("transcribeImage")
        return try await base.transcribeImage(request)
    }

    func quota() async throws -> QuotaStatus {
        try record("quota")
        return try await base.quota()
    }
}

/// An on-device backend that runs some code on the main actor (a settings change "while the model thinks") and
/// then fails.
struct HookBackend: OnDeviceBackend {
    let hook: @MainActor @Sendable () -> Void

    init(_ hook: @escaping @MainActor @Sendable () -> Void) { self.hook = hook }

    func respond<C: OnDeviceCall>(_ call: C) async throws -> C.Output {
        await MainActor.run { hook() }
        throw OnDeviceError.unusable
    }
}

struct StaticToken: AccessTokenProvider {
    var token = "test-token"
    func accessToken() async throws -> String { token }
}

struct NoToken: AccessTokenProvider {
    func accessToken() async throws -> String { throw RelayError.notConfigured }
}

/// Answers URL requests from a handler, delivering the body in the chunks given (optionally spaced out), and
/// records what it was asked (with the body read back from the stream URLSession turns it into).
final class AIStubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var headers: [String: String] = ["Content-Type": "application/json"]
        var chunks: [Data] = []
        /// Seconds between chunks; 0 sends them all at once.
        var spacing: TimeInterval = 0
        var error: URLError?
    }

    nonisolated(unsafe) static var handler: ((URLRequest) -> Reply)?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []
    nonisolated(unsafe) static var stopped = false

    private var cancelled = false

    static func reset() {
        handler = nil
        requests = []
        bodies = []
        stopped = false
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        Self.requests.append(request)
        Self.bodies.append(body)
        let reply = Self.handler?(request) ?? Reply(status: 500)
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if reply.spacing == 0 {
            for chunk in reply.chunks { client?.urlProtocol(self, didLoad: chunk) }
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let chunks = reply.chunks
        DispatchQueue.global().async { [weak self] in
            for chunk in chunks {
                Thread.sleep(forTimeInterval: reply.spacing)
                guard let self, !self.cancelled else { return }
                self.client?.urlProtocol(self, didLoad: chunk)
            }
            guard let self, !self.cancelled else { return }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        cancelled = true
        Self.stopped = true
    }
}
