import Foundation

/// Turns the speech analyzer's results into the lecture's transcript.
///
/// Measured on SpeechTranscriber (`.progressiveTranscription`, Oct 2026): final results arrive a sentence or two at
/// a time (2–12 s of audio), so each final result becomes one `TranscriptSegment` ("s1", "s2", …) with its audio
/// times. A final of a word or two said right after the previous one ("Right.") joins that segment instead of
/// standing alone. Volatile results are the words being heard now: they replace each other, and only their start
/// time means anything (their range always runs to the end of the audio so far).
struct TranscriptAssembler: Sendable {
    /// A final this short, this soon after the previous segment, joins it.
    static let tinyWords = 2
    static let joinGap: Double = 1.5

    private(set) var segments: [TranscriptSegment]
    /// The words being heard now, not final yet. Empty between phrases.
    private(set) var volatileText = ""

    init(segments: [TranscriptSegment] = []) {
        self.segments = segments
    }

    /// A volatile result: the live line under the transcript.
    mutating func volatile(_ text: String) {
        volatileText = Self.clean(text)
    }

    /// A final result. Returns the segment it made or extended, or nil when the text was empty.
    @discardableResult
    mutating func final(_ text: String, start: Double, end: Double) -> TranscriptSegment? {
        volatileText = ""
        let text = Self.clean(text)
        guard !text.isEmpty else { return nil }
        let start = max(0, start.isFinite ? start : 0)
        let end = max(start, end.isFinite ? end : start)
        if var last = segments.last, TextPaginator.wordCount(text) <= Self.tinyWords, start - last.end < Self.joinGap {
            last.text += " " + text
            last.end = max(last.end, end)
            segments[segments.count - 1] = last
            return last
        }
        let segment = TranscriptSegment(id: nextID(), start: start, end: end, text: text)
        segments.append(segment)
        return segment
    }

    /// The transcript so far and the words being heard, for the record screen's live text.
    var liveText: String { volatileText }

    private func nextID() -> String {
        let highest = segments.compactMap { Int($0.id.dropFirst()) }.max() ?? 0
        return "s\(highest + 1)"
    }

    /// Single spaces, no leading space (the analyzer starts most finals with one), first letter as given.
    static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
