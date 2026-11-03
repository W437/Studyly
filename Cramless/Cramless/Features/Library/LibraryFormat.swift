import Foundation

/// The Library's and exam screens' wording, in one place so each line reads the same everywhere it appears.
enum LibraryFormat {
    /// Dates in the calendar's own locale, time zone and system (the app passes `app.calendar`; tests pin one).
    static func dateStyle(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: calendar.locale ?? .autoupdatingCurrent, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// "Midterm Nov 14", "Quiz Friday", "Exam tomorrow"; "No exam set" without one.
    static func examLine(title: String?, courseName: String, date: Date?, now: Date, calendar: Calendar) -> String {
        guard let title, let date else { return "No exam set" }
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
        let notes = format.notes.clTrimmed
        return notes.isEmpty ? format.summary : "\(format.summary) · \(notes)"
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
