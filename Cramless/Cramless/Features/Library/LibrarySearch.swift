import Foundation

/// The Library's search over questions, sources and lectures. Pure: `AppModel.librarySearchEntries()` builds the
/// entries once per change of the store, and every keystroke filters them here.
///
/// Every word of the query must appear (in any order, ignoring case and accents) in an entry's title or text.
/// Title matches rank first; each hit carries the line that matched, trimmed around the match, with the match's
/// character range so the row can mark it.
enum LibrarySearch {
    enum Kind: String, Sendable { case question, source, lecture }

    struct Entry: Equatable, Sendable, Identifiable {
        var kind: Kind
        var id: UUID
        var courseID: UUID
        var courseName: String
        var color: CourseColor
        var title: String
        /// A short secondary line: the topic, the kind of source.
        var detail: String
        /// Everything else that can match, one line per paragraph.
        var body: String
        var systemImage: String
        var date: Date
    }

    struct Hit: Equatable, Sendable, Identifiable {
        var entry: Entry
        /// Where the query matched in the title (character offsets), if it did.
        var titleMatch: Range<Int>?
        /// The matching line of the body when the title alone didn't match, trimmed around the match.
        var snippet: String?
        var snippetMatch: Range<Int>?
        var score: Int

        var id: UUID { entry.id }
    }

    struct Results: Equatable, Sendable {
        var questions: [Hit] = []
        var sources: [Hit] = []
        var lectures: [Hit] = []
        /// Matches beyond the limit, per kind.
        var moreQuestions = 0
        var moreSources = 0
        var moreLectures = 0

        var isEmpty: Bool { questions.isEmpty && sources.isEmpty && lectures.isEmpty }
        var total: Int {
            questions.count + sources.count + lectures.count + moreQuestions + moreSources + moreLectures
        }
    }

    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The query's words ("  Cell   membrane " → ["cell", "membrane"]).
    static func words(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func search(_ query: String, in entries: [Entry], limit: Int = 25) -> Results {
        let words = self.words(query)
        guard !words.isEmpty else { return Results() }
        let phrase = words.joined(separator: " ")
        var hits: [Hit] = []
        for entry in entries {
            let inTitle = words.filter { entry.title.range(of: $0, options: options) != nil }
            guard words.allSatisfy({ inTitle.contains($0) || entry.body.range(of: $0, options: options) != nil }) else { continue }
            let phraseInTitle = characterRange(of: phrase, in: entry.title)
            var score = inTitle.count * 10
            if phraseInTitle != nil { score += 100 }
            if entry.title.range(of: phrase, options: options.union(.anchored)) != nil { score += 20 }
            var hit = Hit(entry: entry, titleMatch: phraseInTitle ?? inTitle.first.flatMap { characterRange(of: $0, in: entry.title) },
                          snippet: nil, snippetMatch: nil, score: score)
            // Some words matched only in the text: show the line they matched in.
            if inTitle.count < words.count, let (line, match) = snippet(for: words, phrase: phrase, in: entry.body) {
                hit.snippet = line
                hit.snippetMatch = match
                if entry.body.range(of: phrase, options: options) != nil { hit.score += 20 }
            }
            hits.append(hit)
        }
        hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.entry.date > $1.entry.date }
        var results = Results()
        for hit in hits {
            switch hit.entry.kind {
            case .question:
                if results.questions.count < limit { results.questions.append(hit) } else { results.moreQuestions += 1 }
            case .source:
                if results.sources.count < limit { results.sources.append(hit) } else { results.moreSources += 1 }
            case .lecture:
                if results.lectures.count < limit { results.lectures.append(hit) } else { results.moreLectures += 1 }
            }
        }
        return results
    }

    /// The first line of `body` with the whole phrase (else the first word), trimmed to about `width` characters
    /// around the match, and the match's range in the result.
    static func snippet(for words: [String], phrase: String, in body: String, width: Int = 110) -> (String, Range<Int>)? {
        let lines = body.split(whereSeparator: \.isNewline).map(String.init)
        for needle in [phrase] + words {
            for line in lines {
                guard let match = characterRange(of: needle, in: line) else { continue }
                return trim(line, around: match, width: width)
            }
        }
        return nil
    }

    /// Cuts `line` to about `width` characters around `match` at word boundaries, adding "…" where it was cut.
    static func trim(_ line: String, around match: Range<Int>, width: Int) -> (String, Range<Int>) {
        let chars = Array(line)
        guard chars.count > width else { return (line, match) }
        let lead = max(12, (width - match.count) / 3)
        var start = max(0, match.lowerBound - lead)
        var end = min(chars.count, max(match.upperBound, start + width))
        if end - start < width { start = max(0, end - width) }
        // Back off to word boundaries without losing the match.
        while start > 0, start < match.lowerBound, !chars[start - 1].isWhitespace { start += 1 }
        while end < chars.count, end > match.upperBound, !chars[end].isWhitespace { end -= 1 }
        var text = String(chars[start..<end]).trimmingCharacters(in: .whitespaces)
        let trimmedLead = String(chars[start..<end]).prefix { $0.isWhitespace }.count
        var lower = match.lowerBound - start - trimmedLead
        if start > 0 { text = "…" + text; lower += 1 }
        if end < chars.count { text += "…" }
        return (text, lower..<(lower + match.count))
    }

    /// The character offsets of `needle` in `text` (ignoring case and accents), or nil.
    static func characterRange(of needle: String, in text: String) -> Range<Int>? {
        guard !needle.isEmpty, let r = text.range(of: needle, options: options) else { return nil }
        let lower = text.distance(from: text.startIndex, to: r.lowerBound)
        return lower..<(lower + text.distance(from: r.lowerBound, to: r.upperBound))
    }
}
