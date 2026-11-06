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
                       ["generate", "check", "grade", "tutor", "confusions", "lecture", "cards-from-chat", "transcribe-image",
                        "assistant", "research", "syllabus", "exam-mention", "last-look", "quota"])
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

    /// Any script of the relay (assistant or research) as server-sent events, cut into awkward chunks.
    private func sseChunks(events: [(event: String, data: AnyJSON)], size: Int) throws -> [Data] {
        var text = ": stream open\n\n"
        for event in events {
            let data = String(decoding: try JSONEncoder.cramless.encode(event.data), as: UTF8.self)
            text += "event: \(event.event)\r\ndata: \(data)\r\n\r\n"
        }
        let bytes = Array(text.utf8)
        return stride(from: 0, to: bytes.count, by: size).map { Data(bytes[$0..<min(bytes.count, $0 + size)]) }
    }

    func testHTTPAssistantPostsItsTurnsAndEveryEventDecodesAcrossChunks() async throws {
        let script = try RelayFixtures.load(AssistantScript.self, "assistant-cards")
        let events = script.events.map { (event: $0.event, data: $0.data) }
        var request = try fixtureRequest(AssistantRequest.self, "assistant")
        request.turns = [AssistantTurn(
            continuation: [.object(["type": .string("function_call"), "call_id": .string("call_1"), "name": .string("search_notes"),
                                    "arguments": .string("{\"query\":\"mitosis\"}")])],
            results: [AssistantResult(callId: "call_1", output: "{\"passages\":[]}")])]
        for size in [1, 13, 97] {
            let chunks = try sseChunks(events: events, size: size)
            AIStubURLProtocol.handler = { _ in .init(headers: ["Content-Type": "text/event-stream"], chunks: chunks) }
            var received: [AssistantEvent] = []
            for try await event in http().assistant(request) { received.append(event) }
            XCTAssertEqual(received, script.events.compactMap(\.assistantEvent), "chunk size \(size)")
        }
        XCTAssertTrue(script.events.compactMap(\.assistantEvent).contains { if case .toolItem = $0 { true } else { false } },
                      "the script has the cards as they are written")

        // What was posted: the route, camelCase keys, the study state, the tools and the turn with its continuation.
        let posted = try XCTUnwrap(AIStubURLProtocol.requests.last)
        XCTAssertEqual(posted.url?.absoluteString, "https://abcdefgh.supabase.co/functions/v1/ai/assistant")
        XCTAssertEqual(posted.httpMethod, "POST")
        XCTAssertEqual(posted.timeoutInterval, HTTPRelayTransport.Route.assistant.timeout)
        let body = try XCTUnwrap(AIStubURLProtocol.bodies.last)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil(json["study"])
        XCTAssertEqual((json["tools"] as? [String])?.count, 8)
        let turns = try XCTUnwrap(json["turns"] as? [[String: Any]])
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual((turns[0]["continuation"] as? [[String: Any]])?.first?["call_id"] as? String, "call_1",
                       "the continuation goes back exactly as the relay sent it, snake_case and all")
        XCTAssertEqual((turns[0]["results"] as? [[String: Any]])?.first?["callId"] as? String, "call_1")
        XCTAssertEqual(try JSONDecoder.cramless.decode(AssistantRequest.self, from: body), request)
    }

    func testHTTPResearchDecodesTheSearchTheSourcesAndTheCitations() async throws {
        let script = try RelayFixtures.load(ResearchScript.self, "research-mitosis")
        let events = script.events.map { (event: $0.event, data: $0.data) }
        let request = ResearchRequest(minor: false, topic: "Mitosis and meiosis", focus: nil, course: "Bio 101")
        for size in [3, 64] {
            let chunks = try sseChunks(events: events, size: size)
            AIStubURLProtocol.handler = { _ in .init(headers: ["Content-Type": "text/event-stream"], chunks: chunks) }
            var received: [ResearchEvent] = []
            for try await event in http().research(request) { received.append(event) }
            XCTAssertEqual(received, script.events.compactMap(\.researchEvent), "chunk size \(size)")
            XCTAssertTrue(received.contains { if case .citation = $0 { true } else { false } })
        }
        let posted = try XCTUnwrap(AIStubURLProtocol.requests.last)
        XCTAssertEqual(posted.url?.absoluteString, "https://abcdefgh.supabase.co/functions/v1/ai/research")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(AIStubURLProtocol.bodies.last)) as? [String: Any])
        XCTAssertEqual(json["minor"] as? Bool, false)
        XCTAssertEqual(json["topic"] as? String, "Mitosis and meiosis")
        XCTAssertNil(json["focus"], "an absent value is left out, not sent as null")
    }

    func testHTTPAssistantErrorsMapLikeTheTutors() async throws {
        let request = try fixtureRequest(AssistantRequest.self, "assistant")
        AIStubURLProtocol.handler = { _ in .init(status: 429, chunks: [self.fixtureData("error-quota")]) }
        do {
            for try await _ in http().assistant(request) {}
            XCTFail("expected quota")
        } catch let error as RelayError {
            guard case .quotaExceeded = error else { return XCTFail("\(error)") }
        }
        // A stream that ends with no done or error was cut off, and what arrived is kept by the caller.
        AIStubURLProtocol.handler = { _ in .init(headers: ["Content-Type": "text/event-stream"],
                                               chunks: [Data("event: start\ndata: {\"model\":\"m\"}\n\n".utf8)]) }
        var seen: [AssistantEvent] = []
        do {
            for try await event in http().assistant(request) { seen.append(event) }
            XCTFail("expected a cut-off")
        } catch let error as RelayError {
            guard case .upstream = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(seen, [.start(model: "m")])
        // A free account asking for web research is told it needs a plan.
        let envelope = Data(#"{"error":{"code":"entitlement_required","message":"Web research is part of Capling Pro."}}"#.utf8)
        AIStubURLProtocol.handler = { _ in .init(status: 403, chunks: [envelope]) }
        do {
            for try await _ in http().research(ResearchRequest(minor: false, topic: "mitosis", focus: nil, course: nil)) {}
            XCTFail("expected entitlement")
        } catch let error as RelayError {
            XCTAssertEqual(error, .entitlementRequired)
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

    // MARK: One quiet retry of a transient failure

    /// A transport that pauses 0 s before its retry, so the tests don't wait.
    private func quickHTTP(pause: ClosedRange<TimeInterval> = 0...0) -> HTTPRelayTransport {
        var transport = http()
        transport.retryPause = pause
        return transport
    }

    func testTheGenerateRouteHasRoomForTwentyQuestions() {
        XCTAssertEqual(HTTPRelayTransport.Route.generate.timeout, 120)
        XCTAssertGreaterThanOrEqual(HTTPRelayTransport.Route.check.timeout, 45)
    }

    func testAGatewayErrorIsRetriedOnceAndTheSecondAnswerIsUsed() async throws {
        for status in [503, 504] {
            AIStubURLProtocol.reset()
            var calls = 0
            AIStubURLProtocol.handler = { _ in
                calls += 1
                return calls == 1 ? .init(status: status, chunks: [Data("<html>busy</html>".utf8)]) : .init(chunks: [self.fixtureData("quota-free")])
            }
            let quota = try await quickHTTP().quota()
            XCTAssertEqual(quota.plan, .free, "status \(status)")
            XCTAssertEqual(AIStubURLProtocol.requests.count, 2, "status \(status)")
        }
    }

    func testA502IsNeverRetriedBecauseTheRelayAnswersItForFailuresItWasPaidFor() async throws {
        // The relay's 502: every item dropped, a reply cut off, an unreadable reply. The scan is given back but the model's cost counts
        // toward the day's 10 cents, so asking again would spend it again for the same answer.
        let billed = Data("{\"error\":{\"code\":\"upstream\",\"message\":\"The model's reply could not be used.\"}}".utf8)
        for body in [billed, Data("<html>bad gateway</html>".utf8), Data()] {
            AIStubURLProtocol.reset()
            AIStubURLProtocol.handler = { _ in .init(status: 502, chunks: [body]) }
            do { _ = try await quickHTTP().generate(try fixtureRequest(GenerateRequest.self, "generate")); XCTFail("expected the failure") } catch is RelayError {}
            XCTAssertEqual(AIStubURLProtocol.requests.count, 1, "a 502 is asked once")
        }
        // Not on any JSON route.
        AIStubURLProtocol.reset()
        AIStubURLProtocol.handler = { _ in .init(status: 502, chunks: [billed]) }
        do { _ = try await quickHTTP().check(CheckRequest(pages: [], items: [])); XCTFail() } catch is RelayError {}
        do { _ = try await quickHTTP().quota(); XCTFail() } catch is RelayError {}
        XCTAssertEqual(AIStubURLProtocol.requests.count, 2, "one request each")
    }

    func testA503ThatNamesALongWaitIsNotRetriedAndAShortOneIsWaitedFor() async throws {
        func busy(_ seconds: Int) -> Data {
            Data("{\"error\":{\"code\":\"upstream\",\"message\":\"Busy.\",\"retryAfter\":\(seconds)}}".utf8)
        }
        // The provider is overloaded and says to come back in 20 seconds (15 for a server error): not waited for.
        AIStubURLProtocol.handler = { _ in .init(status: 503, chunks: [busy(20)]) }
        do { _ = try await quickHTTP().quota(); XCTFail() } catch let error as RelayError { XCTAssertEqual(error, .upstream("Busy.")) }
        XCTAssertEqual(AIStubURLProtocol.requests.count, 1, "20 seconds is too long to keep the person waiting")

        // A short named wait is honoured: the retry comes after it, not after the usual 1.5 to 3 seconds (0 here).
        AIStubURLProtocol.reset()
        var calls = 0
        AIStubURLProtocol.handler = { _ in
            calls += 1
            return calls == 1 ? .init(status: 503, chunks: [busy(1)]) : .init(chunks: [self.fixtureData("quota-free")])
        }
        let started = Date()
        let quota = try await quickHTTP().quota()
        XCTAssertEqual(quota.plan, .free)
        XCTAssertEqual(AIStubURLProtocol.requests.count, 2)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.95, "waited for the 1 second the relay named")

        // The Retry-After header says the same when there is no envelope.
        AIStubURLProtocol.reset()
        calls = 0
        AIStubURLProtocol.handler = { _ in
            calls += 1
            return calls == 1 ? .init(status: 503, headers: ["Retry-After": "30"], chunks: [Data("<html>busy</html>".utf8)])
                : .init(chunks: [self.fixtureData("quota-free")])
        }
        do { _ = try await quickHTTP().quota(); XCTFail() } catch is RelayError {}
        XCTAssertEqual(AIStubURLProtocol.requests.count, 1, "a header naming 30 seconds is not waited for either")
    }

    func testTheRetryCarriesTheSameBodyAndKeepsWithinTheRoutesTimeout() async throws {
        var calls = 0
        AIStubURLProtocol.handler = { _ in
            calls += 1
            return calls == 1 ? .init(status: 503, chunks: []) : .init(chunks: [self.fixtureData("grade-partial")])
        }
        // A pause of a second on a 20-second route (grade): the retry gets what is left of the 20, not another 20.
        let response = try await quickHTTP(pause: 1...1).grade(gradeRequest("They grow."))
        XCTAssertEqual(response.verdict, .partial)
        XCTAssertEqual(AIStubURLProtocol.bodies.count, 2)
        XCTAssertEqual(AIStubURLProtocol.bodies[0], AIStubURLProtocol.bodies[1])
        let route = HTTPRelayTransport.Route.grade.timeout
        XCTAssertEqual(AIStubURLProtocol.requests[0].timeoutInterval, route)
        XCTAssertLessThanOrEqual(AIStubURLProtocol.requests[1].timeoutInterval, route - 1)
        XCTAssertGreaterThan(AIStubURLProtocol.requests[1].timeoutInterval, route - 4)
    }

    func testAFailureTwiceIsTheAnswerNeverAThirdTry() async throws {
        AIStubURLProtocol.handler = { _ in .init(status: 503, chunks: [Data("{\"error\":{\"code\":\"upstream\",\"message\":\"Busy.\"}}".utf8)]) }
        do { _ = try await quickHTTP().check(CheckRequest(pages: [], items: [])); XCTFail("expected the failure") } catch let error as RelayError {
            XCTAssertEqual(error, .upstream("Busy."))
        }
        XCTAssertEqual(AIStubURLProtocol.requests.count, 2)
    }

    func testADroppedConnectionIsRetriedOnce() async throws {
        var calls = 0
        AIStubURLProtocol.handler = { _ in
            calls += 1
            return calls == 1 ? .init(error: URLError(.networkConnectionLost)) : .init(chunks: [self.fixtureData("quota-free")])
        }
        let quota = try await quickHTTP().quota()
        XCTAssertEqual(quota.plan, .free)
        XCTAssertEqual(AIStubURLProtocol.requests.count, 2)

        AIStubURLProtocol.reset()
        AIStubURLProtocol.handler = { _ in .init(error: URLError(.networkConnectionLost)) }
        do { _ = try await quickHTTP().quota(); XCTFail() } catch let error as RelayError { XCTAssertEqual(error, .offline) }
        XCTAssertEqual(AIStubURLProtocol.requests.count, 2, "once, and no more")
    }

    func testDecisionsAreNeverRetried() async throws {
        let quota = Data(fixtureData("error-quota"))
        let cases: [(String, Int, [Data])] = [
            ("bad request", 400, [Data("{\"error\":{\"code\":\"bad_request\",\"message\":\"No pages.\"}}".utf8)]),
            ("forbidden", 403, [Data("{\"error\":{\"code\":\"entitlement_required\",\"message\":\"Pro only.\"}}".utf8)]),
            ("quota", 429, [quota]),
            ("a gateway's rate limit", 429, []),
            ("not found", 404, []),
            ("the relay's own server error", 500, []),
            ("a billed failure", 502, [Data("{\"error\":{\"code\":\"upstream\",\"message\":\"The reply was cut off.\"}}".utf8)]),
            ("a gateway's bad gateway", 502, [Data("<html>bad gateway</html>".utf8)]),
            ("an overloaded provider that says to wait a minute", 503,
             [Data("{\"error\":{\"code\":\"upstream\",\"message\":\"Busy.\",\"retryAfter\":60}}".utf8)]),
        ]
        for (name, status, chunks) in cases {
            AIStubURLProtocol.reset()
            AIStubURLProtocol.handler = { _ in .init(status: status, chunks: chunks) }
            do { _ = try await quickHTTP().quota(); XCTFail(name) } catch is RelayError {}
            XCTAssertEqual(AIStubURLProtocol.requests.count, 1, name)
        }
        for code in [URLError.Code.notConnectedToInternet, .timedOut, .cannotFindHost, .secureConnectionFailed] {
            AIStubURLProtocol.reset()
            AIStubURLProtocol.handler = { _ in .init(error: URLError(code)) }
            do { _ = try await quickHTTP().quota(); XCTFail("\(code)") } catch is RelayError {}
            XCTAssertEqual(AIStubURLProtocol.requests.count, 1, "\(code)")
        }
    }

    func testACancelledCallIsNotRetried() async throws {
        AIStubURLProtocol.handler = { _ in .init(status: 503, chunks: []) }
        let transport = quickHTTP(pause: 3...3)
        let task = Task { try await transport.quota() }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(AIStubURLProtocol.requests.count, 1, "the retry is still waiting out its pause")
        task.cancel()
        let started = Date()
        do { _ = try await task.value; XCTFail() } catch let error as RelayError { XCTAssertEqual(error, .cancelled) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertEqual(AIStubURLProtocol.requests.count, 1)
    }

    func testTheRetryPolicy() {
        let slow = HTTPRelayTransport.Route.generate.timeout
        // 1.5 to 3 seconds, by jitter, for a 503 that names no wait, a 504 and a dropped connection.
        XCTAssertEqual(RelayRetry.pause(after: .status(503), attempt: 1, elapsed: 0.4, timeout: slow, jitter: 0), 1.5)
        XCTAssertEqual(RelayRetry.pause(after: .status(503), attempt: 1, elapsed: 0.4, timeout: slow, jitter: 1), 3)
        XCTAssertEqual(RelayRetry.pause(after: .status(504), attempt: 1, elapsed: 0.4, timeout: slow, jitter: 0.5), 2.25)
        XCTAssertEqual(RelayRetry.pause(after: .status(504), attempt: 1, elapsed: 0.4, timeout: slow, jitter: 5), 3, "jitter is kept in 0...1")
        XCTAssertNotNil(RelayRetry.pause(after: .connectionLost, attempt: 1, elapsed: 0.4, timeout: slow, jitter: 0.5))
        // A 503 that names a wait of 15 seconds or less is retried after that wait (and the jitter); a longer one is not retried.
        XCTAssertEqual(RelayRetry.pause(after: .status(503, retryAfter: 15), attempt: 1, elapsed: 0.4, timeout: slow, jitter: 0), 15)
        XCTAssertEqual(RelayRetry.pause(after: .status(503, retryAfter: 15), attempt: 1, elapsed: 0.4, timeout: slow, jitter: 1), 16.5)
        XCTAssertEqual(RelayRetry.pause(after: .status(503, retryAfter: 4), attempt: 1, elapsed: 0.4, timeout: slow, jitter: 0), 4)
        XCTAssertEqual(RelayRetry.pause(after: .status(503, retryAfter: 0.2), attempt: 1, elapsed: 0.4, timeout: slow, jitter: 0), 1.5,
                       "never sooner than the usual pause")
        XCTAssertNil(RelayRetry.pause(after: .status(503, retryAfter: 15.5), attempt: 1, elapsed: 0.4, timeout: slow, jitter: 0))
        XCTAssertNil(RelayRetry.pause(after: .status(503, retryAfter: 20), attempt: 1, elapsed: 0.4, timeout: slow, jitter: 0), "the provider's 429 says 20")
        XCTAssertNil(RelayRetry.pause(after: .status(503, retryAfter: 60), attempt: 1, elapsed: 0.4, timeout: slow, jitter: 0))
        // The wait must fit in half of the route's time: a 15 second wait on a 20 second route (grade) never happens.
        XCTAssertNil(RelayRetry.pause(after: .status(503, retryAfter: 15), attempt: 1, elapsed: 0.4, timeout: HTTPRelayTransport.Route.grade.timeout, jitter: 0))
        XCTAssertNotNil(RelayRetry.pause(after: .status(503, retryAfter: 15), attempt: 1, elapsed: 0.4, timeout: HTTPRelayTransport.Route.check.timeout, jitter: 0))
        // Never a 502 (billed, and it would come back the same), whatever it names; and no decision, ever; never twice.
        for failure in [RelayRetry.Failure.status(502), .status(502, retryAfter: 1), .status(400), .status(401), .status(403), .status(404),
                        .status(429), .status(500), .status(501), .other] {
            XCTAssertNil(RelayRetry.pause(after: failure, attempt: 1, elapsed: 0.4, timeout: slow, jitter: 0.5), "\(failure)")
        }
        XCTAssertNil(RelayRetry.pause(after: .status(503), attempt: 2, elapsed: 0.4, timeout: slow, jitter: 0.5))
        // Fast failures only: the first attempt and the pause use at most half the route's time (60 s of a 120 s generate).
        XCTAssertNotNil(RelayRetry.pause(after: .status(503), attempt: 1, elapsed: 58, timeout: slow, jitter: 0))
        XCTAssertNil(RelayRetry.pause(after: .status(503), attempt: 1, elapsed: 59, timeout: slow, jitter: 0))
        XCTAssertNil(RelayRetry.pause(after: .status(504), attempt: 1, elapsed: 75, timeout: slow, jitter: 0), "a function that ran 75 seconds and gave up")
        // The retry gets what is left, so a 120 second generate never waits 240.
        XCTAssertEqual(RelayRetry.remainingTimeout(timeout: 120, elapsed: 10, pause: 2), 108)
        XCTAssertEqual(RelayRetry.remainingTimeout(timeout: 120, elapsed: 200, pause: 2), 1, "never zero")
        // What the transport saw becomes a failure.
        XCTAssertEqual(RelayRetry.Failure(status: 503, urlError: nil), .status(503))
        XCTAssertEqual(RelayRetry.Failure(status: 503, retryAfter: 15, urlError: nil), .status(503, retryAfter: 15))
        XCTAssertEqual(RelayRetry.Failure(status: nil, urlError: .networkConnectionLost), .connectionLost)
        XCTAssertEqual(RelayRetry.Failure(status: nil, urlError: .notConnectedToInternet), .other)
        XCTAssertEqual(RelayRetry.Failure(status: nil, urlError: nil), .other)
        // The wait an answer names: the envelope's, else the header's seconds.
        let envelope = Data("{\"error\":{\"code\":\"upstream\",\"message\":\"Busy.\",\"retryAfter\":15}}".utf8)
        XCTAssertEqual(RelayRetry.retryAfter(body: envelope, header: nil), 15)
        XCTAssertEqual(RelayRetry.retryAfter(body: envelope, header: "30"), 15, "the envelope first")
        XCTAssertEqual(RelayRetry.retryAfter(body: Data("<html>".utf8), header: " 12 "), 12)
        XCTAssertNil(RelayRetry.retryAfter(body: Data("<html>".utf8), header: "Wed, 21 Oct 2026 07:28:00 GMT"), "a date is not read")
        XCTAssertNil(RelayRetry.retryAfter(body: Data(), header: nil))
        XCTAssertNil(RelayRetry.retryAfter(body: Data(), header: "-5"))
    }

    func testTheStreamingRoutesAreLeftAlone() async throws {
        AIStubURLProtocol.handler = { _ in .init(status: 503, chunks: [Data("{\"error\":{\"code\":\"upstream\",\"message\":\"Busy.\"}}".utf8)]) }
        var seen: Error?
        do {
            for try await _ in quickHTTP().tutor(try fixtureRequest(TutorRequest.self, "tutor")) {}
        } catch { seen = error }
        XCTAssertEqual(seen as? RelayError, .upstream("Busy."))
        XCTAssertEqual(AIStubURLProtocol.requests.count, 1)
    }
}
