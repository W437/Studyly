import XCTest
@testable import Cramless

/// Both transports speak the contract: the mock serves every fixture (the same files the relay's MOCK mode serves)
/// with believable waits and the magic words; the HTTP transport builds the right requests and maps every answer.
final class AITransportTests: XCTestCase {

    private let mock = MockRelayTransport(latencyScale: 0)

    private func gradeRequest(_ response: String) throws -> GradeRequest {
        var request = try fixtureRequest(GradeRequest.self, "grade")
        request.response = response
        return request
    }

    // MARK: Mock: every fixture

    func testMockServesEveryFixture() async throws {
        let generateRequest = try fixtureRequest(GenerateRequest.self, "generate")
        let generated = try await mock.generate(generateRequest)
        XCTAssertEqual(generated.items.count, 16)
        XCTAssertEqual(generated.title, "Mitosis")
        let checked = try await mock.check(CheckRequest(pages: generateRequest.pages, items: generated.items))
        XCTAssertEqual(checked.verdicts.count, 16)
        let confusions = try await mock.confusions(ConfusionsRequest(course: "Bio 101", mistakes: []))
        XCTAssertEqual(confusions.confusions.first?.name, "Anaphase vs telophase")
        let lecture = try await mock.lecture(LectureRequest(course: "Bio 101", title: "Lecture 6", segments: [], flags: [], maxItems: 8))
        XCTAssertEqual(lecture.items.count, 3)
        let cards = try await mock.cardsFromChat(CardsFromChatRequest(course: nil, messages: [], maxItems: 6))
        XCTAssertEqual(cards.items.count, 2)
        let lines = try await mock.transcribeImage(TranscribeImageRequest(image: "", page: 0, label: "1"))
        XCTAssertEqual(lines.lines.count, 3)
        let quota = try await mock.quota()
        XCTAssertEqual(quota.plan, .free)
        XCTAssertEqual(quota.meter(.grades)?.limit, 20)
    }

    func testMockGradePicksTheFixtureByKeyIdeasHit() async throws {
        let all = try await mock.grade(gradeRequest("To grow and repair, making identical cells with the same number of chromosomes."))
        XCTAssertEqual(all.verdict, .correct)
        let some = try await mock.grade(gradeRequest("So the body can grow and repair tissue, making two identical cells."))
        XCTAssertEqual(some.verdict, .partial)
        XCTAssertEqual(some.hits.map(\.quote), ["grow and repair tissue", "two identical cells"])
        let none = try await mock.grade(gradeRequest("Cells divide so they can make sex cells."))
        XCTAssertEqual(none.verdict, .incorrect)
    }

    func testMockTutorReplaysTheScriptForTheMode() async throws {
        var request = try fixtureRequest(TutorRequest.self, "tutor")
        let hintsScript = try RelayFixtures.load(TutorScript.self, "tutor-hints")
        var events: [TutorEvent] = []
        for try await event in mock.tutor(request) { events.append(event) }
        XCTAssertEqual(events, hintsScript.events.compactMap(\.tutorEvent))

        request.mode = .explain
        let explainScript = try RelayFixtures.load(TutorScript.self, "tutor-explain")
        events = []
        for try await event in mock.tutor(request) { events.append(event) }
        XCTAssertEqual(events, explainScript.events.compactMap(\.tutorEvent))

        // A minor always gets the hints script, whatever the mode says.
        request.minor = true
        events = []
        for try await event in mock.tutor(request) { events.append(event) }
        XCTAssertEqual(events, hintsScript.events.compactMap(\.tutorEvent))
    }

    func testMockTutorKeepsTheScriptsTiming() async throws {
        let request = try fixtureRequest(TutorRequest.self, "tutor")
        let script = try RelayFixtures.load(TutorScript.self, "tutor-hints")
        let scale = 0.05
        let expected = Double(script.events.map(\.delayMs).reduce(0, +)) / 1000 * scale
        let start = Date()
        var count = 0
        for try await _ in MockRelayTransport(latencyScale: scale).tutor(request) { count += 1 }
        XCTAssertEqual(count, script.events.count)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), expected * 0.9)
    }

    func testMockWaitsLikeTheRelay() async throws {
        let scaled = MockRelayTransport(latencyScale: 0.1)
        let start = Date()
        _ = try await scaled.grade(gradeRequest("grow"))
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), MockRelayTransport.Latency.grade * 0.1 * 0.9)
    }

    func testMagicFailAndQuota() async throws {
        do {
            _ = try await mock.grade(gradeRequest("grow #fail"))
            XCTFail("expected an upstream error")
        } catch let error as RelayError {
            guard case .upstream = error else { return XCTFail("\(error)") }
        }
        do {
            _ = try await mock.grade(gradeRequest("grow #quota"))
            XCTFail("expected the quota error")
        } catch let error as RelayError {
            guard case .quotaExceeded(let status, let message) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(status?.meter(.grades)?.used, 20)
            XCTAssertTrue(message.contains("20 graded answers"))
        }
        var request = try fixtureRequest(TutorRequest.self, "tutor")
        request.messages = [TutorMessage(role: .user, text: "Explain this #fail")]
        var events: [TutorEvent] = []
        for try await event in mock.tutor(request) { events.append(event) }
        XCTAssertEqual(events.last, .failure(code: "upstream", message: "Cap couldn't reach the tutor. Try again in a moment."))
    }

    // MARK: HTTP

    override func setUp() {
        super.setUp()
        AIStubURLProtocol.reset()
    }

    private func http(tokens: any AccessTokenProvider = StaticToken()) -> HTTPRelayTransport {
        HTTPRelayTransport(baseURL: URL(string: "https://abcdefgh.supabase.co")!, anonKey: "anon-key", tokens: tokens,
                           session: AIStubURLProtocol.session())
    }

    private func fixtureData(_ name: String) -> Data { RelayFixtures.data(name)! }

    func testHTTPRequestShapeAndDecoding() async throws {
        AIStubURLProtocol.handler = { _ in .init(chunks: [self.fixtureData("grade-partial")]) }
        let response = try await http().grade(gradeRequest("So the body can grow and repair tissue, making two identical cells."))
        XCTAssertEqual(response.verdict, .partial)

        let request = try XCTUnwrap(AIStubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://abcdefgh.supabase.co/functions/v1/ai/grade")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, HTTPRelayTransport.Route.grade.timeout)

        // camelCase keys, decodable back into the contract.
        let body = try XCTUnwrap(AIStubURLProtocol.bodies.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil(json["modelAnswer"])
        XCTAssertNotNil(json["keyIdeas"])
        XCTAssertNotNil(json["sourceExcerpt"])
        XCTAssertEqual(try JSONDecoder.cramless.decode(GradeRequest.self, from: body).response,
                       "So the body can grow and repair tissue, making two identical cells.")
    }

    func testHTTPRoutesAndQuotaIsAGet() async throws {
        XCTAssertEqual(HTTPRelayTransport.Route.allCases.map(\.rawValue),
                       ["generate", "check", "grade", "tutor", "confusions", "lecture", "cards-from-chat", "transcribe-image", "quota"])
        AIStubURLProtocol.handler = { _ in .init(chunks: [self.fixtureData("quota-free")]) }
        let quota = try await http().quota()
        XCTAssertEqual(quota.meter(.scans)?.limit, 3)
        XCTAssertEqual(AIStubURLProtocol.requests.first?.httpMethod, "GET")
        XCTAssertEqual(AIStubURLProtocol.requests.first?.url?.path, "/functions/v1/ai/quota")
        XCTAssertTrue(AIStubURLProtocol.bodies.first?.isEmpty ?? false)
    }

    func testHTTPDecodesISODates() async throws {
        // The contract's dates are ISO 8601 (entitlement's expiresAt); the transport's decoder reads them.
        let entitlement = try RelayFixtures.load(EntitlementResponse.self, "entitlement")
        XCTAssertNotNil(entitlement.expiresAt)
        let encoded = String(decoding: try JSONEncoder.cramless.encode(entitlement), as: UTF8.self)
        XCTAssertTrue(encoded.contains("\"expiresAt\":\"2027-10-29T00:00:00Z\""))
    }

    func testHTTPErrorEnvelopeMapsToRelayErrors() async throws {
        AIStubURLProtocol.handler = { _ in .init(status: 429, chunks: [self.fixtureData("error-quota")]) }
        do {
            _ = try await http().grade(gradeRequest("x"))
            XCTFail("expected quota")
        } catch let error as RelayError {
            guard case .quotaExceeded(let status, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(status?.meter(.grades)?.used, 20)
        }

        let cases: [(Int, String?, RelayError)] = [
            (401, nil, .unauthorized),
            (402, nil, .entitlementRequired),
            (500, "{\"error\":{\"code\":\"upstream\",\"message\":\"The model is busy.\"}}", .upstream("The model is busy.")),
            (400, "{\"error\":{\"code\":\"bad_request\",\"message\":\"No pages.\"}}", .badRequest("No pages.")),
            (403, "{\"error\":{\"code\":\"entitlement_required\",\"message\":\"Pro only.\"}}", .entitlementRequired),
        ]
        for (status, body, expected) in cases {
            AIStubURLProtocol.handler = { _ in .init(status: status, chunks: body.map { [Data($0.utf8)] } ?? []) }
            do {
                _ = try await http().check(CheckRequest(pages: [], items: []))
                XCTFail("expected \(expected)")
            } catch let error as RelayError {
                XCTAssertEqual(error, expected, "status \(status)")
            }
        }
    }

    func testHTTPForbiddenWithoutAnEnvelopeNeedsAPlan() async throws {
        AIStubURLProtocol.handler = { _ in .init(status: 403, chunks: []) }
        do { _ = try await http().quota(); XCTFail() } catch let error as RelayError { XCTAssertEqual(error, .entitlementRequired) }
        // A bare 429 (a gateway's rate limit) isn't a free limit: a plain failure, so the app falls back quietly.
        AIStubURLProtocol.handler = { _ in .init(status: 429, chunks: []) }
        do { _ = try await http().quota(); XCTFail() } catch let error as RelayError {
            XCTAssertEqual(error, .upstream("Too many requests right now."))
        }
    }

    func testHTTPUnauthorizedIsRetriedOnceWithAFreshToken() async throws {
        // The contract: refresh the session, then retry once.
        var calls = 0
        AIStubURLProtocol.handler = { _ in
            calls += 1
            return calls == 1 ? .init(status: 401, chunks: [Data("{\"error\":{\"code\":\"unauthorized\",\"message\":\"Expired.\"}}".utf8)])
                : .init(chunks: [self.fixtureData("quota-free")])
        }
        let quota = try await http().quota()
        XCTAssertEqual(quota.plan, .free)
        XCTAssertEqual(AIStubURLProtocol.requests.count, 2)

        // A second 401 is the answer.
        AIStubURLProtocol.reset()
        AIStubURLProtocol.handler = { _ in .init(status: 401, chunks: []) }
        do { _ = try await http().quota(); XCTFail() } catch let error as RelayError { XCTAssertEqual(error, .unauthorized) }
        XCTAssertEqual(AIStubURLProtocol.requests.count, 2)
    }

    func testHTTPNetworkFailuresMap() async throws {
        AIStubURLProtocol.handler = { _ in .init(error: URLError(.notConnectedToInternet)) }
        do { _ = try await http().quota(); XCTFail() } catch let error as RelayError { XCTAssertEqual(error, .offline) }
        AIStubURLProtocol.handler = { _ in .init(error: URLError(.timedOut)) }
        do { _ = try await http().quota(); XCTFail() } catch let error as RelayError {
            guard case .upstream = error else { return XCTFail("\(error)") }
        }
        AIStubURLProtocol.handler = { _ in .init(chunks: [Data("{\"not\":\"quota\"}".utf8)]) }
        do { _ = try await http().quota(); XCTFail() } catch let error as RelayError {
            guard case .decoding = error else { return XCTFail("\(error)") }
        }
    }

    func testHTTPWithoutATokenSendsNothing() async throws {
        AIStubURLProtocol.handler = { _ in .init(chunks: [self.fixtureData("quota-free")]) }
        do { _ = try await http(tokens: NoToken()).quota(); XCTFail() } catch let error as RelayError {
            XCTAssertEqual(error, .notConfigured)
        }
        XCTAssertTrue(AIStubURLProtocol.requests.isEmpty)
    }

    /// The fixture script as the relay would stream it, cut into awkward chunks.
    private func sseChunks(_ name: String, size: Int) throws -> [Data] {
        let script = try RelayFixtures.load(TutorScript.self, name)
        var text = ": stream open\n\n"
        for event in script.events {
            let data = String(decoding: try JSONEncoder.cramless.encode(event.data), as: UTF8.self)
            text += "event: \(event.event)\r\ndata: \(data)\r\n\r\n"
        }
        let bytes = Array(text.utf8)
        return stride(from: 0, to: bytes.count, by: size).map { Data(bytes[$0..<min(bytes.count, $0 + size)]) }
    }

    func testHTTPTutorStreamsAcrossChunks() async throws {
        let script = try RelayFixtures.load(TutorScript.self, "tutor-explain")
        for size in [1, 7, 64] {
            let chunks = try sseChunks("tutor-explain", size: size)
            AIStubURLProtocol.handler = { _ in .init(headers: ["Content-Type": "text/event-stream"], chunks: chunks) }
            var events: [TutorEvent] = []
            for try await event in http().tutor(try fixtureRequest(TutorRequest.self, "tutor")) { events.append(event) }
            XCTAssertEqual(events, script.events.compactMap(\.tutorEvent), "chunk size \(size)")
            XCTAssertEqual(AIStubURLProtocol.requests.last?.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        }
    }

    func testHTTPTutorErrorsAndCutOffs() async throws {
        // An error before the stream starts is the envelope, mapped.
        AIStubURLProtocol.handler = { _ in .init(status: 429, chunks: [self.fixtureData("error-quota")]) }
        do {
            for try await _ in http().tutor(try fixtureRequest(TutorRequest.self, "tutor")) {}
            XCTFail("expected quota")
        } catch let error as RelayError {
            guard case .quotaExceeded = error else { return XCTFail("\(error)") }
        }
        // A stream that ends without done or error was cut off.
        AIStubURLProtocol.handler = { _ in .init(headers: ["Content-Type": "text/event-stream"],
                                               chunks: [Data("event: delta\ndata: {\"text\":\"Half an\"}\n\n".utf8)]) }
        var received: [TutorEvent] = []
        do {
            for try await event in http().tutor(try fixtureRequest(TutorRequest.self, "tutor")) { received.append(event) }
            XCTFail("expected a cut-off")
        } catch let error as RelayError {
            guard case .upstream = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(received, [.delta("Half an")])
    }

    func testHTTPTutorCancellationStopsTheRequest() async throws {
        let chunks = try sseChunks("tutor-hints", size: 40)
        AIStubURLProtocol.handler = { _ in .init(headers: ["Content-Type": "text/event-stream"], chunks: chunks, spacing: 0.05) }
        let transport = http()
        let request = try fixtureRequest(TutorRequest.self, "tutor")
        let task = Task { () -> Int in
            var n = 0
            for try await _ in transport.tutor(request) { n += 1 }
            return n
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        let start = Date()
        let count = (try? await task.value) ?? -1
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertLessThan(count, try RelayFixtures.load(TutorScript.self, "tutor-hints").events.count)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(AIStubURLProtocol.stopped)
    }
}
