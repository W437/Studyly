import Foundation

/// A date a lecturer gave for an exam: "the midterm is on November 20th". The rules decide on their own: a date counts only with an exam word beside it, only within 200 days after
/// the recording, and only when its sentence isn't about something else (an example, an exam that isn't happening or was last year, the homework or the review session that goes with
/// it). They can still mishear, which is why the words are always shown, nothing is added without a tap, and refusing it is one tap.
struct ExamMention: Codable, Hashable, Sendable, Identifiable {
    /// `<segment>-<day>`: stable for what was said.
    var id: String
    var segmentID: String
    /// Seconds into the lecture.
    var time: Double
    /// The sentence, as transcribed.
    var quote: String
    /// yyyy-MM-dd.
    var day: String
    /// HH:mm, when it was said.
    var clock: String?
    /// "Midterm", "Quiz 2".
    var word: String
    /// Every day read from those words, for the one check on a tap.
    var candidates: [String]
}

enum ExamDateFinder {
    /// A date further off than this, after the recording, isn't an announcement.
    static let maxDaysAhead = 200
    /// How close the exam word has to be to the date, in characters.
    static let nearby = 80
    /// A sentence can run over two segments when they follow each other within this many seconds.
    static let segmentGap: Double = 5

    /// The dates announced in a transcript, in order, the first time each day is said. Only segments with an exam word, or next to one, reach the date detector, so a long lecture
    /// costs little.
    static func find(in segments: [TranscriptSegment], recordedAt: Date, calendar: Calendar) -> [ExamMention] {
        let sorted = segments.sorted { $0.start < $1.start }
        let words = sorted.map { ExamWords.all(in: $0.text) }
        var seen = Set<String>()
        var out: [ExamMention] = []
        for index in sorted.indices {
            let segment = sorted[index]
            let before = index > 0 && segment.start - sorted[index - 1].end <= segmentGap ? words[index - 1].last : nil
            let after = index + 1 < sorted.count && sorted[index + 1].start - segment.end <= segmentGap ? words[index + 1].first : nil
            guard !words[index].isEmpty || before != nil || after != nil else { continue }
            let hits = TextDates.find(in: segment.text, from: recordedAt, calendar: calendar)
            for hit in hits {
                guard let date = TextDates.date(day: hit.day, calendar: calendar),
                      (1...maxDaysAhead).contains(calendar.dayDistance(from: recordedAt, to: date)),
                      !isAboutSomethingElse(hit, in: segment.text),
                      let word = wordBeside(hit, in: segment.text, own: words[index], before: before.map { ($0, sorted[index - 1].text) },
                                            after: after) else { continue }
                guard seen.insert(hit.day).inserted else { continue }
                let lead = before != nil && words[index].isEmpty ? Lexicon.sentences(sorted[index - 1].text).last.map { $0 + " " } ?? "" : ""
                out.append(ExamMention(id: "\(segment.id)-\(hit.day)", segmentID: segment.id, time: segment.start,
                                       quote: (lead + sentence(holding: hit, in: segment.text)).clipped(toScalars: 240), day: hit.day, clock: hit.time, word: word,
                                       candidates: Array(hits.map(\.day).prefix(RelayLimits.mentionCandidates))))
            }
        }
        return out
    }

    /// Words that make a whole sentence something other than an announcement: an example, an exam that won't happen, one that has been.
    nonisolated(unsafe) private static let notAnAnnouncement = try? NSRegularExpression(pattern: #"\b(?:for example|for instance|suppose|imagine|let'?s say|por ejemplo|supongamos|zum beispiel|angenommen|par exemple)\b"#
        + #"|\b(?:no|not an?|isn'?t an?|won'?t be an?|there won'?t be|kein(?:e|en)?|no hay|no habr[aá])\s+(?:exam|test|quiz|midterm|final|class|lecture|examen|parcial|pr[uü]fung|klausur)"#
        + #"|\b(?:exam|test|quiz|midterm|final)\s+(?:is|was|has been)\s+(?:cancell?ed|off)\b"#
        + #"|\b(?:last (?:year|semester|term|time|spring|fall|month)|was on|were on|took place|happened|began|aired|published|el a[nñ]o pasado|letztes jahr)\b"#, options: [.caseInsensitive])
    /// Another event in the date's own clause: the date is its, whatever exam comes up beside it.
    nonisolated(unsafe) private static let anotherEvent = try? NSRegularExpression(pattern: #"\b(?:homework|assignments?|problem sets?|psets?|office hours?|review sessions?|study guides?|practice (?:exam|test|quiz)s?|presentations?|deadlines?|due|last day|drop|withdraw|grades?|graded|results?|essays?|lab reports?|tarea|entrega|hausaufgaben?|abgabe|sprechstunde|devoirs)\b"#
        + #"|\b(?:get|gets|hand|hands|handed|give|gives|return|returned)\b[^.,;]{0,40}\bback\b"#, options: [.caseInsensitive])

    /// The date's sentence says it isn't this exam's date.
    static func isAboutSomethingElse(_ hit: TextDates.Hit, in text: String) -> Bool {
        let whole = sentence(holding: hit, in: text)
        if notAnAnnouncement?.firstMatch(in: whole, range: NSRange(whole.startIndex..., in: whole)) != nil { return true }
        // "moved from the 18th": the old date.
        if text[..<hit.range.lowerBound].lowercased().range(of: #"\b(?:moved|changed|rescheduled|pushed|postponed)\b.*\bfrom\s*$"#, options: .regularExpression) != nil { return true }
        if hit.quote.lowercased().hasPrefix("from "), whole.lowercased().range(of: #"\b(?:moved|changed|rescheduled|pushed|postponed)\b"#, options: .regularExpression) != nil { return true }
        // The clause: from the mark before the date to the mark after it.
        let marks = CharacterSet(charactersIn: ",;:—–()")
        func isMark(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { marks.contains($0) } }
        var start = hit.range.lowerBound
        while start > text.startIndex, !isMark(text[text.index(before: start)]), text[text.index(before: start)] != "." { start = text.index(before: start) }
        var end = hit.range.upperBound
        while end < text.endIndex, !isMark(text[end]), text[end] != "." { end = text.index(after: end) }
        let clause = String(text[start..<end])
        return anotherEvent?.firstMatch(in: clause, range: NSRange(clause.startIndex..., in: clause)) != nil
    }

    private static func wordBeside(_ hit: TextDates.Hit, in text: String, own: [ExamWords.Found], before: (ExamWords.Found, String)?,
                                   after: ExamWords.Found?) -> String? {
        var best: (title: String, distance: Int)?
        for word in own {
            let distance = word.range.upperBound <= hit.range.lowerBound
                ? text.distance(from: word.range.upperBound, to: hit.range.lowerBound)
                : text.distance(from: hit.range.upperBound, to: max(word.range.lowerBound, hit.range.upperBound))
            if distance <= nearby, distance < (best?.distance ?? .max) { best = (word.title, distance) }
        }
        if let best { return best.title }
        if let (word, previous) = before {
            let gap = previous.distance(from: word.range.upperBound, to: previous.endIndex) + text.distance(from: text.startIndex, to: hit.range.lowerBound)
            if gap <= nearby { return word.title }
        }
        if let after, text.distance(from: hit.range.upperBound, to: text.endIndex) <= nearby { return after.title }
        return nil
    }

    private static func sentence(holding hit: TextDates.Hit, in text: String) -> String {
        Lexicon.sentences(text).first { $0.contains(hit.quote) } ?? text
    }
}

/// How a heard date stands against the exams already in the plan. Pure.
enum ExamHeardMatch: Equatable, Sendable {
    /// Nothing like it: it can be added.
    case new
    /// An exam on that day already.
    case known(examID: UUID, title: String)
    /// The same exam by name, on another day.
    case moved(examID: UUID, title: String, currentDate: Date)

    static func classify(_ mention: ExamMention, exams: [ExamSnapshot], now: Date, calendar: Calendar) -> ExamHeardMatch {
        guard let date = TextDates.date(day: mention.day, calendar: calendar) else { return .new }
        let upcoming = exams.filter { $0.date > now }
        if let same = upcoming.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) { return .known(examID: same.id, title: same.title) }
        if let named = upcoming.first(where: { ExamWords.sameExam($0.title, mention.word) }) {
            return .moved(examID: named.id, title: named.title, currentDate: named.date)
        }
        // "The exam" in a course with one exam ahead can only be that one.
        let generic = ["exam", "test"].contains(mention.word.lowercased())
        if generic, upcoming.count == 1, let only = upcoming.first { return .moved(examID: only.id, title: only.title, currentDate: only.date) }
        return .new
    }
}

/// The words of a heard date.
enum ExamHeardCopy {
    static let title: LocalizedStringResource = "Cap heard an exam date"
    static let add: LocalizedStringResource = "Add the exam"
    /// Refusing it, on the card and on the lecture's page: it doesn't come back.
    static let wrong = String(localized: "That's wrong")
    static let refused = String(localized: "Cap won't bring it up again")
    static let known: LocalizedStringResource = "Already in your exams"
    static let wholeCourse: LocalizedStringResource = "It will cover the whole course. You can narrow it down in the exam."
    static let doubt: LocalizedStringResource = "Cap isn't sure this was about an exam."
    static let addAnyway: LocalizedStringResource = "Add it anyway"

    /// "Exam added, 14 days away".
    static func added(days: Int) -> String { String(localized: "Exam added, \(days) days away") }

    /// "Your Bio 101 Midterm is set for Nov 29. Cap heard Nov 20."
    static func moved(title: String, current: String, heard: String) -> String {
        String(localized: "Your \(title) is set for \(current). Cap heard \(heard).")
    }

    static func use(_ day: String) -> String { String(localized: "Use \(day)") }
}
