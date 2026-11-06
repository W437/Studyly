import Foundation

/// The Library's and exam screens' wording, in one place so each line reads the same everywhere it appears.
enum LibraryFormat {
    /// Dates in the calendar's own locale, time zone and system (the app passes `app.calendar`; tests pin one).
    static func dateStyle(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: calendar.locale ?? .autoupdatingCurrent, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// "Midterm Nov 14", "Quiz Friday", "Exam tomorrow"; "No exam yet" without one. The exam is the course's next one
    /// (`AppModel.nextExam(of:)`), the same exam its ring is for.
    static func examLine(title: String?, courseName: String, date: Date?, now: Date, calendar: Calendar) -> String {
        guard let title, let date else { return String(localized: "No exam yet") }
        return "\(shortExamTitle(title, courseName: courseName)) \(shortWhen(date, now: now, calendar: calendar))"
    }

    /// The exam's title without the course's name in front: "Bio 101 Midterm" → "Midterm", "AP Psych Exam" in
    /// AP Psychology → "Exam". A title that is nothing but the course's name stays whole.
    static func shortExamTitle(_ title: String, courseName: String) -> String {
        let titleWords = title.split(separator: " ").map(String.init)
        let courseWords = courseName.split(separator: " ").map(String.init)
        var dropped = 0
        while dropped < titleWords.count, dropped < courseWords.count {
            let word = titleWords[dropped], courseWord = courseWords[dropped]
            let same = word.caseInsensitiveCompare(courseWord) == .orderedSame
            let abbreviation = word.count >= 3 && courseWord.lowercased().hasPrefix(word.lowercased())
            guard same || abbreviation else { break }
            dropped += 1
        }
        guard dropped > 0, dropped < titleWords.count else { return title }
        let rest = titleWords[dropped...].joined(separator: " ")
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }

    /// "today", "tomorrow", "Friday" within the coming week, "Nov 14" after, "Oct 3" before.
    static func shortWhen(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dayDistance(from: now, to: date)
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case 2...6: return date.formatted(LibraryFormat.dateStyle(calendar).weekday(.wide))
        default: return date.formatted(LibraryFormat.dateStyle(calendar).month(.abbreviated).day())
        }
    }

    // MARK: One number

    /// What VoiceOver says for a course's ring: "53 percent ready for the Midterm".
    static func ringAccessibility(value: Double, examTitle: String, courseName: String) -> String {
        let percent = Int((max(0, min(1, value)) * 100).rounded())
        return String(localized: "\(percent) percent ready for the \(shortExamTitle(examTitle, courseName: courseName))")
    }

    /// A course's topic with its active questions (`AppModel.courseTopics`).
    struct CourseTopic: Equatable, Sendable, Identifiable {
        var id: UUID
        var name: String
        var questionCount: Int
    }

    /// One topic on the course page. Readiness is shown only for the course's next exam, and only for its topics.
    struct TopicLine: Equatable, Sendable, Identifiable {
        enum State: Equatable, Sendable {
            /// Readiness for the next exam, 0…1.
            case value(Double)
            /// No material yet: nothing can count toward readiness.
            case gap
            /// Outside the next exam's scope: "Not on the Midterm", no number.
            case notOnExam(String)
            /// The course has no exam to come: its questions, no number.
            case noExam
        }

        var id: UUID
        var name: String
        var questionCount: Int
        var state: State
    }

    /// The course's topics in course order: each topic on the next exam with its readiness for it (a gap when it has no material),
    /// the others "Not on the <exam>", and with no exam to come, only their questions. `examTopics` is
    /// `AppModel.topicReadiness(for:)` of the next exam (nil without one).
    static func topicLines(courseTopics: [CourseTopic], examTopics: [TopicReadiness]?, examTitle: String?,
                           courseName: String) -> [TopicLine] {
        guard let examTopics, let examTitle else {
            return courseTopics.map {
                TopicLine(id: $0.id, name: $0.name, questionCount: $0.questionCount, state: $0.questionCount == 0 ? .gap : .noExam)
            }
        }
        let onExam = Dictionary(examTopics.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let short = shortExamTitle(examTitle, courseName: courseName)
        return courseTopics.map { topic in
            let state: TopicLine.State
            if let r = onExam[topic.id] {
                state = r.value.map { .value($0) } ?? .gap
            } else {
                state = .notOnExam(short)
            }
            return TopicLine(id: topic.id, name: topic.name, questionCount: topic.questionCount, state: state)
        }
    }

    /// The topic list's note under a course's ring: "Ready for the Midterm, Nov 29."
    static func topicsFootnote(examTitle: String, courseName: String, date: Date, calendar: Calendar) -> String {
        String(localized: "Ready for the \(shortExamTitle(examTitle, courseName: courseName)), \(shortDate(date, calendar: calendar)).")
    }

    /// The source screen's line about its questions: "Questions cover 17% of this reading".
    static func coverageLine(share: Double, kind: SourceKind) -> String {
        "Questions cover \(CLFormat.percent(share)) of this \(kind == .lecture ? "lecture" : "reading")"
    }

    /// "Nov 14".
    static func shortDate(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(LibraryFormat.dateStyle(calendar).month(.abbreviated).day())
    }

    /// "23 days to go", "Tomorrow", "Today", "3 days ago".
    static func countdown(days: Int) -> String {
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case let d where d > 1: return "\(d) days to go"
        case -1: return "Yesterday"
        default: return "\(-days) days ago"
        }
    }

    /// "4 sources · 86 questions".
    static func courseCounts(sources: Int, questions: Int) -> String {
        "\(CLFormat.count(sources, "source")) · \(CLFormat.count(questions, "question"))"
    }

    static func sourceKindName(_ kind: SourceKind) -> String {
        switch kind {
        case .scan, .photo: "Scan"
        case .sample: "Sample page"
        case .pdf: "PDF"
        case .text: "Notes"
        case .lecture: "Lecture"
        case .quizlet: "Quizlet"
        case .anki: "Anki"
        case .csv: "CSV"
        case .chat: "From a chat"
        }
    }

    /// The line under a source's title: "Scan · 1 page · 14 questions", "Lecture · 52 min · 9 questions",
    /// "Quizlet · 7 questions".
    static func sourceMeta(kind: SourceKind, pages: Int, duration: Double, questions: Int) -> String {
        var parts = [sourceKindName(kind)]
        switch kind {
        case .lecture:
            if duration > 0 { parts.append(CLFormat.minutes(max(1, Int((duration / 60).rounded())))) }
        case .quizlet, .anki, .csv, .chat:
            break
        default:
            if pages > 0 { parts.append(CLFormat.count(pages, "page")) }
        }
        parts.append(CLFormat.count(questions, "question"))
        return parts.joined(separator: " · ")
    }

    /// "Multiple choice + short answer" with notes after a dot when there are some.
    static func formatLine(_ format: ExamFormat) -> String {
        var parts = [format.summary]
        if let count = format.questionCount { parts.append(String(localized: "\(count) questions")) }
        if let minutes = format.minutes { parts.append(String(localized: "\(minutes) min")) }
        let notes = format.notes.clTrimmed
        if !notes.isEmpty { parts.append(notes) }
        return parts.joined(separator: " · ")
    }

    /// "91%".
    static func grade(_ value: Double) -> String { CLFormat.percent(value) }

    /// A fill-in's text as read: "During {{telophase}}, …" → "During ____, …".
    static func clozeDisplay(_ text: String) -> String {
        var out = ""
        var rest = Substring(text)
        while let open = rest.range(of: "{{"), let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) {
            out += rest[..<open.lowerBound]
            out += "____"
            rest = rest[close.upperBound...]
        }
        return out + rest
    }
}

extension ItemKind {
    /// The format's glyph in lists and chips.
    var libraryIcon: String {
        switch self {
        case .recall: "text.bubble"
        case .apply: "lightbulb"
        case .mcq: "list.bullet"
        case .cloze: "text.cursor"
        case .diagram: "photo"
        case .flashcard: "rectangle.on.rectangle"
        }
    }

    /// A short name for filter chips ("Own words", "Choice").
    var shortName: String {
        switch self {
        case .recall: "Own words"
        case .apply: "Apply it"
        case .mcq: "Choice"
        case .cloze: "Fill in"
        case .diagram: "Diagram"
        case .flashcard: "Flashcard"
        }
    }

    /// What a new question of this format is for, in the editor.
    var editorHint: String {
        switch self {
        case .flashcard: "A front and a back. You rate yourself."
        case .recall: "Answered in your own words and graded by its key ideas."
        case .apply: "A situation to work through, graded by its key ideas."
        case .mcq: "One right answer among a few."
        case .cloze: "A sentence with words to fill in."
        case .diagram: "Labels to fill in on a page."
        }
    }
}

extension SourceKind {
    /// Lectures open their notes; everything else opens the source.
    var opensLectureNotes: Bool { self == .lecture }
}
