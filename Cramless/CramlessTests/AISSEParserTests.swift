import XCTest
@testable import Cramless

/// The tutor's event-stream parser: chunk boundaries anywhere, every line ending, multi-line data, comments, and
/// the spec's rules for fields and the end of the stream.
final class AISSEParserTests: XCTestCase {

    private func parse(_ chunks: [String]) -> [SSEEvent] {
        var parser = SSEParser()
        var out: [SSEEvent] = []
        for chunk in chunks { out += parser.feed(Array(chunk.utf8)) }
        out += parser.finish()
        return out
    }

    private func parseBytes(_ chunks: [[UInt8]]) -> [SSEEvent] {
        var parser = SSEParser()
        var out: [SSEEvent] = []
        for chunk in chunks { out += parser.feed(chunk) }
        return out
    }

    private let stream = "event: start\ndata: {\"model\":\"m\"}\n\n: keep-alive\nevent: delta\ndata: {\"text\":\"Hello \"}\n\nevent: delta\ndata: {\"text\":\"there\"}\n\nevent: done\ndata: {}\n\n"

    func testParsesNamedEventsAndSkipsComments() {
        let events = parse([stream])
        XCTAssertEqual(events.map(\.event), ["start", "delta", "delta", "done"])
        XCTAssertEqual(events[1].data, "{\"text\":\"Hello \"}")
    }

    func testEverySplitPointGivesTheSameEvents() {
        let whole = parse([stream])
        let bytes = Array(stream.utf8)
        for cut in 1..<bytes.count {
            let events = parseBytes([Array(bytes[..<cut]), Array(bytes[cut...])])
            XCTAssertEqual(events, whole, "split at \(cut)")
        }
    }

    func testByteAtATime() {
        let bytes = Array(stream.utf8)
        XCTAssertEqual(parseBytes(bytes.map { [$0] }), parse([stream]))
    }

    func testLineEndings() {
        let lf = parse(["data: a\n\n"])
        let crlf = parse(["data: a\r\n\r\n"])
        let cr = parse(["data: a\r\r"])
        XCTAssertEqual(lf.map(\.data), ["a"])
        XCTAssertEqual(crlf, lf)
        XCTAssertEqual(cr, lf)
    }

    func testCRLFSplitBetweenChunksIsOneLineEnd() {
        // CR ends chunk one, LF starts chunk two: one line end, not a blank line in between.
        let events = parse(["data: one\r", "\ndata: two\r\n\r\n"])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "one\ntwo")
    }

    func testMultiLineDataJoinsWithNewlines() {
        let events = parse(["event: delta\ndata: first\ndata: second\ndata:\ndata: fourth\n\n"])
        XCTAssertEqual(events.first?.data, "first\nsecond\n\nfourth")
    }

    func testOneLeadingSpaceIsStripped() {
        XCTAssertEqual(parse(["data:  two spaces\n\n"]).first?.data, " two spaces")
        XCTAssertEqual(parse(["data:none\n\n"]).first?.data, "none")
    }

    func testFieldWithoutColonHasEmptyValue() {
        let events = parse(["data\n\n"])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "")
    }

    func testEventWithoutDataIsNotDispatchedAndTypeResets() {
        let events = parse(["event: ping\n\n", "data: x\n\n"])
        XCTAssertEqual(events.map(\.event), ["message"])
    }

    func testIDCarriesOverAndRetryParses() {
        let events = parse(["id: 7\nretry: 1500\ndata: a\n\n", "data: b\n\n", "retry: soon\ndata: c\n\n"])
        XCTAssertEqual(events.map(\.id), ["7", "7", "7"])
        XCTAssertEqual(events.map(\.retry), [1500, 1500, 1500])
    }

    func testByteOrderMarkSkippedOnlyAtStart() {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let events = parseBytes([bom + Array("data: a\n\n".utf8)])
        XCTAssertEqual(events.first?.data, "a")
        let later = parseBytes([Array("data: a".utf8) + bom + Array("\n\n".utf8)])
        XCTAssertEqual(later.first?.data, "a\u{FEFF}")
    }

    func testMultiByteCharactersSplitAcrossChunks() {
        let text = "data: Café 🧬 mitose\n\n"
        let bytes = Array(text.utf8)
        let index = bytes.firstIndex(of: 0xC3)! + 1   // inside "é"
        let emoji = bytes.firstIndex(of: 0xF0)! + 2   // inside the emoji
        let events = parseBytes([Array(bytes[..<index]), Array(bytes[index..<emoji]), Array(bytes[emoji...])])
        XCTAssertEqual(events.first?.data, "Café 🧬 mitose")
    }

    func testUnfinishedEventAtEndOfStreamIsDropped() {
        let events = parse(["data: complete\n\ndata: cut off"])
        XCTAssertEqual(events.map(\.data), ["complete"])
    }

    func testTutorEventMapping() {
        XCTAssertEqual(HTTPRelayTransport.tutorEvent(from: SSEEvent(event: "start", data: "{\"model\":\"claude\"}")), .start(model: "claude"))
        XCTAssertEqual(HTTPRelayTransport.tutorEvent(from: SSEEvent(event: "delta", data: "{\"text\":\"Hi\"}")), .delta("Hi"))
        XCTAssertEqual(HTTPRelayTransport.tutorEvent(from: SSEEvent(event: "delta", data: "plain words")), .delta("plain words"))
        XCTAssertEqual(HTTPRelayTransport.tutorEvent(from: SSEEvent(event: "citation", data: "{\"sourceId\":\"s1\",\"label\":\"Textbook p. 87\",\"quote\":\"q\"}")),
                       .citation(sourceID: "s1", label: "Textbook p. 87", quote: "q"))
        XCTAssertEqual(HTTPRelayTransport.tutorEvent(from: SSEEvent(event: "error", data: "{\"code\":\"quota_exceeded\",\"message\":\"m\"}")),
                       .failure(code: "quota_exceeded", message: "m"))
        XCTAssertEqual(HTTPRelayTransport.tutorEvent(from: SSEEvent(event: "done", data: "{}")), .done(model: ""))
        XCTAssertNil(HTTPRelayTransport.tutorEvent(from: SSEEvent(event: "ping", data: "{}")))
    }
}

extension SSEEvent {
    init(event: String, data: String) { self.init(event: event, data: data, id: nil, retry: nil) }
}
