import Foundation

/// One server-sent event.
struct SSEEvent: Equatable, Sendable {
    /// The `event:` field; "message" when the event named none.
    var event: String
    /// The `data:` lines joined with "\n".
    var data: String
    /// The last `id:` seen on the stream (it carries over to later events, as the spec says).
    var id: String?
    var retry: Int?
}

/// An incremental parser for `text/event-stream` (WHATWG HTML, "Server-sent events"), fed bytes as they arrive.
///
/// It works on bytes, not strings, so a chunk boundary can fall anywhere: inside a line, between the CR and LF of
/// a CRLF, or in the middle of a multi-byte UTF-8 character. Lines end with LF, CR or CRLF. A line starting with
/// ":" is a comment (servers send them as keep-alives). `data:` lines accumulate and are joined with "\n"; a blank
/// line dispatches the event; an event with no data is not dispatched. A UTF-8 byte order mark at the very start is
/// skipped. At the end of the stream an event that never got its blank line is dropped, as the spec requires.
struct SSEParser: Sendable {
    private var line: [UInt8] = []
    private var lastWasCR = false
    private var atStreamStart = true
    private var bomBytesSeen = 0

    private var eventType = ""
    private var dataLines: [String] = []
    private var lastEventID: String?
    private var retry: Int?

    init() {}

    /// Feeds bytes; returns the events completed by them, in order.
    mutating func feed<S: Sequence>(_ bytes: S) -> [SSEEvent] where S.Element == UInt8 {
        var out: [SSEEvent] = []
        for byte in bytes {
            if let event = feed(byte: byte) { out.append(event) }
        }
        return out
    }

    /// Feeds one byte; returns the event it completed, if any (at most one: events end at a line end).
    mutating func feed(byte: UInt8) -> SSEEvent? {
        // The byte order mark (EF BB BF) is only skipped at the very start of the stream.
        if atStreamStart {
            let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
            if byte == bom[bomBytesSeen] {
                bomBytesSeen += 1
                if bomBytesSeen == bom.count { atStreamStart = false }
                return nil
            }
            atStreamStart = false
            if bomBytesSeen > 0 {
                // Not a BOM after all: those bytes were content.
                line.append(contentsOf: bom.prefix(bomBytesSeen))
                bomBytesSeen = 0
            }
        }
        switch byte {
        case 0x0D: // CR
            lastWasCR = true
            return endLine()
        case 0x0A: // LF
            if lastWasCR { lastWasCR = false; return nil }   // the LF of a CRLF
            return endLine()
        default:
            lastWasCR = false
            line.append(byte)
            return nil
        }
    }

    /// The stream ended. A pending event without its blank line is discarded (spec); returns nothing, but resets.
    mutating func finish() -> [SSEEvent] {
        line = []
        eventType = ""
        dataLines = []
        lastWasCR = false
        return []
    }

    private mutating func endLine() -> SSEEvent? {
        let text = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)
        return process(text)
    }

    private mutating func process(_ text: String) -> SSEEvent? {
        if text.isEmpty { return dispatch() }
        if text.hasPrefix(":") { return nil }   // a comment
        let field: Substring
        var value: Substring
        if let colon = text.firstIndex(of: ":") {
            field = text[..<colon]
            value = text[text.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(text)
            value = ""
        }
        switch field {
        case "event":
            eventType = String(value)
        case "data":
            dataLines.append(String(value))
        case "id":
            if !value.contains("\u{0}") { lastEventID = String(value) }
        case "retry":
            if !value.isEmpty, value.allSatisfy(\.isASCIIDigit) { retry = Int(value) }
        default:
            break   // unknown fields are ignored
        }
        return nil
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            eventType = ""
            dataLines = []
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(event: eventType.isEmpty ? "message" : eventType, data: dataLines.joined(separator: "\n"),
                        id: lastEventID, retry: retry)
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
