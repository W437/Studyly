import Foundation

/// What a syllabus says about the exam being set up, as the person checks it: its date and the words that say so, its topics (the ones the course has
/// and the new ones), and its format. Pure. It is built from what the relay or the rules read, keeps only what the app can stand behind, and does nothing
/// until "Looks right" fills the draft; Add or Save in the editor is what stores anything.
struct SyllabusProposal: Equatable, Sendable {
    /// A date further off than this isn't this term's exam.
    static let maxDaysAhead = 400
    /// New topics a proposal may bring: a schedule misread as topics shouldn't flood a course.
    static let maxNewTopics = 20

    struct Topic: Identifiable, Equatable, Sendable {
        var id: String { name.lowercased() }
        var name: String
        /// The course's own topic; nil for a new one, which has no notes yet.
        var existingID: UUID?
        var included = true

        var isNew: Bool { existingID == nil }
    }

    /// "Also on this syllabus: Final, Dec 14": said, never set, in this version.
    struct OtherExam: Equatable, Sendable {
        var title: String
        var date: Date?
    }

    var title: String
    var date: Date?
    /// The syllabus gives a time, so the draft takes it; without one the draft keeps its own.
    var hasTime = false
    var dateQuote: String?
    var topics: [Topic] = []
    var format: ExamFormat
    /// The syllabus says something about the format.
    var formatKnown = false
    var formatQuote: String?
    var others: [OtherExam] = []
    var origin: ItemOrigin

    /// The ids a request uses for the course's topics: "t1", "t2", in the order it sends them.
    static func requestIDs(for topics: [(id: UUID, name: String)]) -> [String: (id: UUID, name: String)] {
        var out: [String: (id: UUID, name: String)] = [:]
        for (index, topic) in topics.prefix(RelayLimits.syllabusTopics).enumerated() { out["t\(index + 1)"] = topic }
        return out
    }

    /// The proposal for the exam being set up: the exam of that name, else the soonest one with a date, else the first. Nil when the reading says
    /// nothing about any exam. A date needs its words on the page and a day from today to 400 days off; a topic id must be one the request sent.
    static func make(exams: [SyllabusExam], examTitle: String, topicIDs: [String: (id: UUID, name: String)], base: ExamDraft, pageText: String,
                     origin: ItemOrigin, now: Date, calendar: Calendar) -> SyllabusProposal? {
        let page = normalized(pageText)
        func checkedDate(_ exam: SyllabusExam) -> Date? {
            guard let day = exam.date, let quote = exam.dateQuote, page.contains(normalized(quote)),
                  let date = TextDates.date(day: day, time: exam.time, calendar: calendar) else { return nil }
            return (0...maxDaysAhead).contains(calendar.dayDistance(from: now, to: date)) ? date : nil
        }
        let dated = exams.map { (exam: $0, date: checkedDate($0)) }
        let chosen = dated.first { ExamWords.sameExam($0.exam.title, examTitle) }
            ?? dated.filter { $0.date != nil }.min { $0.date! < $1.date! }
            ?? dated.first
        guard let chosen else { return nil }

        var seen = Set<String>()
        var topics: [Topic] = []
        var newCount = 0
        for topic in chosen.exam.topics {
            let existing = topic.topicId.flatMap { topicIDs[$0] }
            let name = existing?.name ?? topic.name.clTrimmed
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            if existing == nil {
                guard newCount < maxNewTopics else { continue }
                newCount += 1
            }
            topics.append(Topic(name: name, existingID: existing?.id))
        }
        guard chosen.date != nil || !topics.isEmpty else { return nil }

        let known = chosen.exam.format
        var format = base.format
        let sayable = [known.multipleChoice, known.shortAnswer, known.essay]
        // "30 multiple choice and 10 short answers" rules out what it doesn't name.
        if sayable.contains(true) {
            format.multipleChoice = known.multipleChoice ?? false
            format.shortAnswer = known.shortAnswer ?? false
            format.essay = known.essay ?? false
        }
        format.questionCount = known.questionCount ?? format.questionCount
        format.minutes = known.minutes ?? format.minutes
        if let notes = known.notes?.clTrimmed.clNonEmpty, format.notes.clTrimmed.isEmpty { format.notes = notes }
        let formatKnown = sayable.contains(where: { $0 != nil }) || known.questionCount != nil || known.minutes != nil || known.notes != nil

        let others = dated.filter { $0.exam.title != chosen.exam.title }.map { OtherExam(title: $0.exam.title, date: $0.date) }
        return SyllabusProposal(title: chosen.exam.title, date: chosen.date, hasTime: chosen.date != nil && chosen.exam.time != nil,
                                dateQuote: chosen.date == nil ? nil : chosen.exam.dateQuote, topics: topics, format: format, formatKnown: formatKnown,
                                formatQuote: chosen.exam.formatQuote, others: others, origin: origin)
    }

    /// "Looks right": what the person kept goes into the draft. A date without a time keeps the draft's hour. With no topic kept, what's on it stays as it was.
    func apply(to draft: inout ExamDraft, courseName: String, calendar: Calendar) {
        if draft.title.clTrimmed.isEmpty {
            draft.title = courseName.isEmpty ? title : "\(courseName) \(title)"
        }
        if let date {
            if hasTime {
                draft.date = date
            } else {
                let keep = calendar.dateComponents([.hour, .minute], from: draft.date)
                draft.date = calendar.date(bySettingHour: keep.hour ?? 9, minute: keep.minute ?? 0, second: 0, of: date) ?? date
            }
        }
        let kept = topics.filter(\.included)
        if !kept.isEmpty {
            draft.wholeCourse = false
            draft.scope = Set(kept.compactMap(\.existingID))
            draft.newTopics = kept.filter(\.isNew).map(\.name)
        }
        draft.format = format
        draft.fromSyllabus = true
    }

    private static func normalized(_ text: String) -> String {
        Lexicon.fold(text).lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// The words of the syllabus flow.
enum SyllabusCopy {
    static let question: LocalizedStringResource = "What does it cover?"
    static let pitch: LocalizedStringResource = "Snap the syllabus or a past paper. Cap sets the topics, the date and the format."
    static let snap: LocalizedStringResource = "Snap the syllabus"
    static let pickTopics: LocalizedStringResource = "Pick topics"
    static let setFromSyllabus: LocalizedStringResource = "Set from your syllabus"
    static let reading: LocalizedStringResource = "Reading your syllabus"
    static let readingDetail: LocalizedStringResource = "Topics, the date and the format"
    static let found: LocalizedStringResource = "Here's what I found"
    static let fromPhoto: LocalizedStringResource = "From your photo of the syllabus"
    static let noNotes: LocalizedStringResource = "No notes yet"
    static let mockMatch: LocalizedStringResource = "Mock exams will match this"
    static let edit: LocalizedStringResource = "Edit"
    static let looksRight: LocalizedStringResource = "Looks right"
    static let offline: LocalizedStringResource = "Read on your iPhone. Cloud AI reads syllabi better."
    static let turnOnCloud: LocalizedStringResource = "Turn on Cloud AI"
    static let unreadable: LocalizedStringResource = "Couldn't read this page. Try a flatter photo in good light, or a PDF."
    static let noDate: LocalizedStringResource = "I couldn't find a date. Set it yourself."
    static let noTopics: LocalizedStringResource = "I couldn't find any topics on this page."
    static let filledNote: LocalizedStringResource = "Set from your syllabus. Check anything Cap misread before you save."

    /// "Also on this syllabus: Final exam, Dec 14".
    static func alsoOnIt(_ others: [SyllabusProposal.OtherExam], calendar: Calendar) -> String? {
        guard !others.isEmpty else { return nil }
        let style = LibraryFormat.dateStyle(calendar).month(.abbreviated).day()
        let list = others.map { other in other.date.map { "\(other.title), \($0.formatted(style))" } ?? other.title }.formatted(.list(type: .and))
        return String(localized: "Also on this syllabus: \(list)")
    }
}
