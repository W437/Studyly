import Foundation

/// What a syllabus says about the exam being set up, as the person checks it: its date and the words that say so, its topics (the ones the course has
/// and the new ones), and its format. Pure. It is built from what the relay or the rules read, keeps only what the app can stand behind, and does nothing
/// until the found page's button ("Add Midterm", "Save changes") fills the draft, which the editor then stores.
struct SyllabusProposal: Equatable, Sendable {
    /// A date further off than this isn't this term's exam.
    static let maxDaysAhead = 400
    /// New topics a proposal may bring: a schedule misread as topics shouldn't flood a course.
    static let maxNewTopics = 20

    struct Topic: Identifiable, Equatable, Sendable {
        var id: String { name.lowercased() }
        var name: String
        /// The course's own topic of that name; nil when none has it.
        var existingID: UUID?
        var included = true
        /// The student's questions that speak of it, in whatever topics they sit (`SyllabusMatcher`).
        var questions = 0
        /// The course topics those questions sit in.
        var matchedTopics: Set<UUID> = []
        /// The student's notes speak of it.
        var inNotes = false
        /// A title with nothing to match on ("Chapter 3"): it can't be said to have notes or not.
        var saysNothing = false

        var isNew: Bool { existingID == nil }
        /// Nothing the student has speaks of it: this one has no notes yet. Only this makes a new topic: the rest are already in the exam.
        var isGap: Bool { isNew && questions == 0 && !inNotes && !saysNothing }
        /// Only a new, empty topic or one of the course's own can be taken off. What's matched by its questions alone has nothing to take.
        var canUntick: Bool { !isNew || isGap }
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
    /// The course's topics the syllabus says nothing of. They stay on the exam unless the student unticks them.
    var alsoInCourse: [Topic] = []
    var format: ExamFormat
    /// The syllabus says something about the format.
    var formatKnown = false
    var formatQuote: String?
    var others: [OtherExam] = []
    var origin: ItemOrigin
    /// The questions the course holds, in all and by topic (`match(against:)`): what "Looks right" keeps is counted from them.
    var courseQuestions = 0
    var questionsByTopic: [UUID: Int] = [:]
    var courseTopicIDs: [UUID] = []

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
        // How many of each: what the reading counted, or the numbers in its words when those are on the page.
        let quote = chosen.exam.formatQuote.flatMap { page.contains(normalized($0)) ? $0 : nil }
        let counts = quote.map(StatedCounts.init) ?? StatedCounts()
        let stated = (known.multipleChoiceCount ?? counts.multipleChoice, known.shortAnswerCount ?? counts.shortAnswer, known.essayCount ?? counts.essay)
        if stated.0 != nil || stated.1 != nil || stated.2 != nil {
            (format.multipleChoiceCount, format.shortAnswerCount, format.essayCount) = stated
        }
        if let notes = known.notes?.clTrimmed.clNonEmpty, format.notes.clTrimmed.isEmpty { format.notes = notes }
        let formatKnown = sayable.contains(where: { $0 != nil }) || known.questionCount != nil || known.minutes != nil || known.notes != nil

        let others = dated.filter { $0.exam.title != chosen.exam.title }.map { OtherExam(title: $0.exam.title, date: $0.date) }
        return SyllabusProposal(title: chosen.exam.title, date: chosen.date, hasTime: chosen.date != nil && chosen.exam.time != nil,
                                dateQuote: chosen.date == nil ? nil : chosen.exam.dateQuote, topics: topics, format: format, formatKnown: formatKnown,
                                formatQuote: chosen.exam.formatQuote, others: others, origin: origin)
    }

    /// Reads the topics against what the course already holds, so a topic with questions is never called empty.
    mutating func match(against library: SyllabusLibrary) {
        let matcher = SyllabusMatcher(library)
        courseQuestions = library.questions.count
        courseTopicIDs = library.topics.map(\.id)
        questionsByTopic = library.questions.reduce(into: [:]) { counts, question in
            if let topic = question.topicID { counts[topic, default: 0] += 1 }
        }
        for index in topics.indices {
            let found = matcher.match(topics[index].name)
            let own = topics[index].existingID.flatMap { questionsByTopic[$0] } ?? 0
            topics[index].questions = max(found.questions, own)
            topics[index].matchedTopics = found.topicIDs
            topics[index].inNotes = found.inNotes
            topics[index].saysNothing = SyllabusMatcher.saysNothing(topics[index].name)
        }
        let named = Set(topics.compactMap(\.existingID)).union(topics.flatMap(\.matchedTopics))
        alsoInCourse = library.topics.filter { !named.contains($0.id) && questionsByTopic[$0.id] != nil }.map {
            Topic(name: $0.name, existingID: $0.id, questions: questionsByTopic[$0.id] ?? 0)
        }
    }

    /// "Looks right": what the person kept goes into the draft. A date without a time keeps the draft's hour. A syllabus never takes a question out of an exam by itself: what's on the
    /// draft stays, a topic nothing speaks of joins as a gap, and a scope the student already narrowed grows by what the syllabus names. A course topic leaves only when they untick it.
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
        draft.newTopics = kept.filter(\.isGap).map(\.name)
        if !draft.wholeCourse {
            for topic in kept {
                if let id = topic.existingID { draft.scope.insert(id) }
                draft.scope.formUnion(topic.matchedTopics)
            }
        }
        let removed = (topics + alsoInCourse).filter { !$0.included }.compactMap(\.existingID)
        if !removed.isEmpty {
            if draft.wholeCourse {
                draft.wholeCourse = false
                draft.scope = Set(courseTopicIDs)
            }
            draft.scope.subtract(removed)
        }
        draft.format = format
        draft.fromSyllabus = true
    }

    /// What "Looks right" will do to this draft, in plain words, before it's pressed.
    func effect(on base: ExamDraft) -> String {
        var after = base
        apply(to: &after, courseName: "", calendar: .current)
        let kept = after.wholeCourse ? courseQuestions : after.scope.reduce(0) { $0 + (questionsByTopic[$1] ?? 0) }
        return SyllabusCopy.effect(kept: kept, of: courseQuestions, gaps: after.newTopics.count)
    }

    private static func normalized(_ text: String) -> String {
        Lexicon.fold(text).lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// The numbers a line of a syllabus gives each kind of question ("30 multiple choice and 10 short answers"). Pure.
struct StatedCounts: Equatable, Sendable {
    var multipleChoice: Int?
    var shortAnswer: Int?
    var essay: Int?

    init() {}

    init(_ text: String) {
        let lower = text.lowercased()
        func number(_ pattern: String) -> Int? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  let range = Range(match.range(at: 1), in: lower) else { return nil }
            return Int(lower[range])
        }
        multipleChoice = number(#"(\d{1,3})\s*(?:multiple[- ]choice|mcqs?\b|mc\b)"#)
        shortAnswer = number(#"(\d{1,3})\s*short\b"#)
        essay = number(#"(\d{1,2})\s*essays?\b"#)
    }
}

/// The words of the syllabus flow.
enum SyllabusCopy {
    static let pitch: LocalizedStringResource = "Snap the syllabus or a past paper. Cap sets the topics, the date and the format."
    static let snap: LocalizedStringResource = "Snap the syllabus"
    static let pickTopics: LocalizedStringResource = "Pick topics"
    static let setFromSyllabus: LocalizedStringResource = "Set from your syllabus"
    static let reading: LocalizedStringResource = "Reading your syllabus"
    static let readingDetail: LocalizedStringResource = "Topics, the date and the format"
    static let found: LocalizedStringResource = "Here's what I found"
    static let fromPhoto: LocalizedStringResource = "From your photo of the syllabus"
    static let fromPDF: LocalizedStringResource = "From your syllabus PDF"
    static let noNotes: LocalizedStringResource = "No notes yet"
    static let mockMatch: LocalizedStringResource = "Mock exams follow this mix, as far as your questions go"
    static let edit: LocalizedStringResource = "Edit"
    static let looksRight: LocalizedStringResource = "Looks right"
    static let offline: LocalizedStringResource = "Read on your iPhone. Cloud AI reads syllabi better."
    static let turnOnCloud: LocalizedStringResource = "Turn on Cloud AI"
    static let unreadable: LocalizedStringResource = "Couldn't read this page. Try a flatter photo in good light, or a PDF."
    static let noDate: LocalizedStringResource = "I couldn't find a date. Set it yourself."
    static let noTopics: LocalizedStringResource = "I couldn't find any topics on this page."
    static let filledNote: LocalizedStringResource = "Set from your syllabus."
    static let inNotes: LocalizedStringResource = "In your notes"
    static let alsoInCourse: LocalizedStringResource = "Also in this course"
    static let alreadyOnIt: LocalizedStringResource = "Its questions are on the exam already, under other topics."
    static let alsoInCourseNote: LocalizedStringResource = "The syllabus doesn't name these. They stay on the exam unless you untick them."

    /// Fewer questions than this, or under a third of the course's, is too little for a ring to mean much.
    static let fewQuestions = 10

    static func isFew(_ kept: Int, of total: Int) -> Bool { kept < total && (kept < fewQuestions || kept * 3 < total) }

    /// "Keeps your 99 questions. Adds 3 topics you have no notes for."
    static func effect(kept: Int, of total: Int, gaps: Int) -> String {
        var parts: [String] = []
        if total == 0 {
            parts.append(String(localized: "Your questions join this exam as you add notes."))
        } else if kept >= total {
            parts.append(String(localized: "Keeps your \(total) questions."))
        } else {
            parts.append(String(localized: "Keeps \(kept) of your \(total) questions."))
            if isFew(kept, of: total) { parts.append(String(localized: "That's very few for a number to mean much.")) }
        }
        if gaps > 0 { parts.append(String(localized: "Adds \(gaps) topics you have no notes for.")) }
        return parts.joined(separator: " ")
    }

    /// A topic's question count on the proposal: "17 questions".
    static func questions(_ count: Int) -> LocalizedStringResource { "\(count) questions" }

    /// On the exam page: a scope that holds too little for its ring to mean anything.
    static func thinScope(_ inScope: Int, of total: Int) -> String {
        String(localized: "This exam rests on \(inScope) of your \(total) questions, too few for a number that means much.")
    }

    static let useWholeCourse: LocalizedStringResource = "Use the whole course"

    /// "Also on this syllabus: Final exam, Dec 14".
    static func alsoOnIt(_ others: [SyllabusProposal.OtherExam], calendar: Calendar) -> String? {
        guard !others.isEmpty else { return nil }
        let style = LibraryFormat.dateStyle(calendar).month(.abbreviated).day()
        let list = others.map { other in other.date.map { "\(other.title), \($0.formatted(style))" } ?? other.title }.formatted(.list(type: .and))
        return String(localized: "Also on this syllabus: \(list)")
    }
}
