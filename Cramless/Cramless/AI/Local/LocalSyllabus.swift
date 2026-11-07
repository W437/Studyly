import Foundation

/// A syllabus read on this iPhone, by rules: the exams it names with their dates, the topics of its schedule, and its format. English first (the date
/// detector reads more). It answers in the relay's shape, so the app treats both the same way, and it is what a student sees with no network and no Cloud AI.
/// Cloud AI reads a real syllabus better (the screen says so): tables and odd layouts are beyond these rules.
///
/// A schedule says what an exam covers in one of two ways. A heading with its topics under it ("Midterm exam", "Covers:", "Week 4: Meiosis") gives
/// the exam what follows. A row among rows ("Week 8: Midterm (Oct 12)") gives it what came before, since the last exam.
enum LocalSyllabus {
    /// At most this many exams, as the relay's reply.
    static let maxExams = 4

    private struct Draft {
        var exam: SyllabusExam
        /// The topics above it, for an exam with none of its own.
        var before: [SyllabusTopic] = []
        var multipleChoiceCount: Int?
        var shortAnswerCount: Int?
        var essayCount: Int?
    }

    static func read(pages: [PageInput], topics: [SyllabusTopicInput], examTitle: String?, today: Date, calendar: Calendar) -> [SyllabusExam] {
        let lines = pages.flatMap(\.lines)
        var drafts: [Draft] = []
        var current: Int?
        var waiting: [SyllabusTopic] = []   // topics not under an exam's heading
        var waitingDate: Int?               // the exam heading the next lines may date
        var linesSinceHeading = 0
        var general = FormatLine()
        var seenNames = Set<String>()

        func add(_ topic: SyllabusTopic) {
            let key = topic.name.lowercased()
            guard seenNames.insert(key).inserted else { return }
            if let current { drafts[current].exam.topics.append(topic) } else { waiting.append(topic) }
        }

        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let hits = TextDates.find(in: text, from: today, calendar: calendar)
            let word = ExamWords.first(in: text)
            let format = FormatLine(text)

            if let word, isAboutAnExam(text) {
                let isRow = scheduleSubject(of: text, hits: hits) != nil || hits.first?.range.lowerBound == text.startIndex
                let index: Int
                if let known = drafts.firstIndex(where: { $0.exam.title == word.title }) {
                    index = known
                } else {
                    drafts.append(Draft(exam: SyllabusExam(title: word.title, topics: [], format: SyllabusFormat()), before: waiting))
                    waiting = []
                    index = drafts.count - 1
                }
                if let hit = hits.first(where: { isReachable($0, today: today, calendar: calendar) }), drafts[index].exam.date == nil {
                    set(hit, on: &drafts[index].exam)
                    waitingDate = nil
                } else if drafts[index].exam.date == nil {
                    waitingDate = index
                    linesSinceHeading = 0
                }
                current = isRow ? nil : index
                format.apply(to: &drafts[index], quote: text)
                continue
            }
            if let index = waitingDate {
                linesSinceHeading += 1
                if let hit = hits.first(where: { isReachable($0, today: today, calendar: calendar) }) {
                    set(hit, on: &drafts[index].exam)
                    waitingDate = nil
                    if isOnlyADate(text, hit: hit) { continue }
                } else if linesSinceHeading >= 3 {
                    waitingDate = nil
                }
            }
            if !format.isEmpty {
                if let target = current ?? drafts.indices.last { format.apply(to: &drafts[target], quote: text) } else { general.merge(format, quote: text) }
                continue
            }
            for name in topicNames(in: text, hits: hits, underHeading: current != nil) {
                add(SyllabusTopic(name: name, topicId: match(name, in: topics), lineIds: [line.id]))
            }
        }

        // A page with a schedule and no exam named: the exam being set up, from that schedule.
        if drafts.isEmpty, !waiting.isEmpty || !general.isEmpty {
            drafts.append(Draft(exam: SyllabusExam(title: examTitle?.clTrimmed.clNonEmpty ?? String(localized: "Exam"), topics: [], format: SyllabusFormat()), before: waiting))
            waiting = []
        }
        guard !drafts.isEmpty else { return [] }
        if !general.isEmpty { general.apply(to: &drafts[0], quote: general.quote ?? "") }
        var out: [SyllabusExam] = []
        for var draft in drafts {
            if draft.exam.topics.isEmpty { draft.exam.topics = draft.before }
            if draft.exam.format.questionCount == nil {
                let parts = [draft.multipleChoiceCount, draft.shortAnswerCount, draft.essayCount].compactMap { $0 }
                if !parts.isEmpty { draft.exam.format.questionCount = parts.reduce(0, +) }
            }
            draft.exam.format.multipleChoiceCount = draft.multipleChoiceCount
            draft.exam.format.shortAnswerCount = draft.shortAnswerCount
            draft.exam.format.essayCount = draft.essayCount
            if !draft.exam.topics.isEmpty || draft.exam.date != nil { out.append(draft.exam) }
        }
        return Array(out.prefix(maxExams))
    }

    // MARK: Dates

    private static func isReachable(_ hit: TextDates.Hit, today: Date, calendar: Calendar) -> Bool {
        guard let date = TextDates.date(day: hit.day, calendar: calendar) else { return false }
        let days = calendar.dayDistance(from: today, to: date)
        return (0...SyllabusProposal.maxDaysAhead).contains(days)
    }

    private static func set(_ hit: TextDates.Hit, on exam: inout SyllabusExam) {
        exam.date = hit.day
        exam.time = hit.time
        exam.dateQuote = hit.quote
    }

    private static func isOnlyADate(_ text: String, hit: TextDates.Hit) -> Bool {
        var rest = text
        rest.removeSubrange(hit.range)
        return rest.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)).isEmpty
    }

    // MARK: What isn't an exam

    private static let notAnnouncing = ["%", "policy", "policies", "make-up", "makeup", "missed", "absence", "accommodation", "grade", "grading", "review for", "review session", "academic", "cheating", "study guide"]

    /// A line that is about an exam, not one that uses the word: "Grading: midterm 30%" and "Make-up exams are only given…" aren't.
    private static func isAboutAnExam(_ text: String) -> Bool {
        let lower = text.lowercased()
        guard !notAnnouncing.contains(where: { lower.contains($0) }) else { return false }
        // A long sentence that mentions one in passing, with no date in it, isn't its heading.
        return Lexicon.wordCount(text) <= 14
    }

    // MARK: Topics

    nonisolated(unsafe) private static let rowPrefix = try? NSRegularExpression(
        pattern: #"^\s*(?:week|wk|lecture|lec|class|session|day|unit|module|topic)\.?\s*\d{1,2}\s*[:\-–—.)]*\s*"#, options: [.caseInsensitive])
    nonisolated(unsafe) private static let chapterRange = try? NSRegularExpression(
        pattern: #"^\s*(?:chapters?|chaps?\.?|chs?\.?)\s*(\d{1,2})\s*(?:-|–|—|to|through|thru)\s*(\d{1,2})\b"#, options: [.caseInsensitive])
    nonisolated(unsafe) private static let oneChapter = try? NSRegularExpression(
        pattern: #"^\s*(?:chapter|chap\.?|ch\.?)\s*(\d{1,2})\s*[:\-–—.)]*\s*"#, options: [.caseInsensitive])

    private static let notATopic = ["review", "break", "holiday", "no class", "homework", "assignment", "due", "reading", "lab report", "project", "paper", "presentation", "tba", "tbd", "office hours", "syllabus", "introduction to the course", "course overview", "recess", "thanksgiving", "spring break"]

    /// The subject of a schedule row ("Week 4: Meiosis (Oct 3)" is "Meiosis"); nil for a line that isn't one or has no subject ("Week 8").
    private static func scheduleSubject(of text: String, hits: [TextDates.Hit]) -> String? {
        let whole = NSRange(text.startIndex..., in: text)
        if let prefix = rowPrefix?.firstMatch(in: text, range: whole), let range = Range(prefix.range, in: text) {
            return clean(String(text[range.upperBound...]), hits: hits)
        }
        return nil
    }

    private static func topicNames(in text: String, hits: [TextDates.Hit], underHeading: Bool) -> [String] {
        let whole = NSRange(text.startIndex..., in: text)
        if let range = chapterRange?.firstMatch(in: text, range: whole), let a = Range(range.range(at: 1), in: text), let b = Range(range.range(at: 2), in: text),
           let from = Int(text[a]), let to = Int(text[b]), from <= to, to - from < 20 {
            return (from...to).map { String(localized: "Chapter \($0)") }
        }
        if let chapter = oneChapter?.firstMatch(in: text, range: whole), let number = Range(chapter.range(at: 1), in: text),
           let matched = Range(chapter.range, in: text) {
            let subject = clean(String(text[matched.upperBound...]), hits: hits)
            return [isGoodName(subject) ? subject : String(localized: "Chapter \(String(text[number]))")]
        }
        if let subject = scheduleSubject(of: text, hits: hits) { return isGoodName(subject) ? [subject] : [] }
        // A row that starts with its date: "Oct 3: Meiosis".
        if let first = hits.first, first.range.lowerBound == text.startIndex {
            let subject = clean(String(text[first.range.upperBound...]), hits: hits)
            return isGoodName(subject) ? [subject] : []
        }
        if PageStructure.isBullet(text) {
            let subject = clean(PageStructure.stripBullet(text), hits: hits)
            return isGoodName(subject) ? [subject] : []
        }
        // A short line under an exam's "Covers:".
        if underHeading, !text.hasSuffix(":") {
            let subject = clean(text, hits: hits)
            return isGoodName(subject) && Lexicon.wordCount(subject) <= 5 && !subject.hasSuffix(".") ? [subject] : []
        }
        return []
    }

    /// A row's words without its dates, brackets and trailing marks.
    private static func clean(_ raw: String, hits: [TextDates.Hit]) -> String {
        var text = raw
        for hit in hits { text = text.replacingOccurrences(of: hit.quote, with: "") }
        text = text.replacingOccurrences(of: "()", with: "").replacingOccurrences(of: "( )", with: "")
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " \t:-–—.,;()[]"))
    }

    private static func isGoodName(_ name: String) -> Bool {
        guard name.count >= 2, Lexicon.wordCount(name) <= 8, name.contains(where: \.isLetter) else { return false }
        let lower = name.lowercased()
        return !notATopic.contains { lower.contains($0) } && ExamWords.first(in: name) == nil
    }

    /// The course's topic this name means: the same words, or nearly (their stems overlap by at least 60%).
    static func match(_ name: String, in topics: [SyllabusTopicInput]) -> String? {
        let folded = Lexicon.fold(name)
        if let same = topics.first(where: { Lexicon.fold($0.name) == folded }) { return same.id }
        let stems = Set(Lexicon.contentStems(name))
        guard !stems.isEmpty else { return nil }
        var best: (id: String, score: Double)?
        for topic in topics {
            let other = Set(Lexicon.contentStems(topic.name))
            guard !other.isEmpty else { continue }
            let score = Double(stems.intersection(other).count) / Double(stems.union(other).count)
            if score >= 0.6, score > (best?.score ?? 0) { best = (topic.id, score) }
        }
        return best?.id
    }

    // MARK: The format

    /// What one line says about an exam's form.
    private struct FormatLine {
        var multipleChoice: Bool?
        var multipleChoiceCount: Int?
        var shortAnswer: Bool?
        var shortAnswerCount: Int?
        var essay: Bool?
        var essayCount: Int?
        var questionCount: Int?
        var minutes: Int?
        var notes: String?
        var quote: String?

        var isEmpty: Bool {
            multipleChoice == nil && shortAnswer == nil && essay == nil && questionCount == nil && minutes == nil && notes == nil
        }

        init() {}

        init(_ text: String) {
            let lower = text.lowercased()
            // A due date or a lab's length isn't an exam's.
            guard !["homework", "assignment", " due", "lab ", "office hours", "lecture", "class meets"].contains(where: { lower.contains($0) }) else { return }
            func number(_ pattern: String) -> Int? {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                      let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                      let range = Range(match.range(at: 1), in: lower) else { return nil }
                return Int(lower[range])
            }
            func has(_ pattern: String) -> Bool { lower.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
            let counts = StatedCounts(lower)
            multipleChoiceCount = counts.multipleChoice
            shortAnswerCount = counts.shortAnswer
            essayCount = counts.essay
            if multipleChoiceCount != nil || has(#"\bmultiple[- ]choice\b"#) { multipleChoice = true }
            if shortAnswerCount != nil || has(#"\bshort[- ]answers?\b"#) { shortAnswer = true }
            if essayCount != nil || has(#"\bessay (?:questions?|exam|section)\b"#) { essay = true }
            questionCount = number(#"(\d{1,3})\s*(?:total\s+)?questions?\b"#)
            if let m = number(#"(\d{1,3})\s*(?:-\s*)?(?:minutes?|mins?)\b"#) {
                minutes = m
            } else if let h = number(#"(\d)\s*(?:-\s*)?(?:hours?|hrs?)\b"#) {
                minutes = h * 60
            } else if has(#"\bone[- ]hour\b"#) {
                minutes = 60
            } else if has(#"\btwo[- ]hours?\b"#) {
                minutes = 120
            } else if has(#"\bthree[- ]hours?\b"#) {
                minutes = 180
            }
            for rule in ["open book", "open-book", "closed book", "closed-book", "open notes", "open-notes", "closed notes", "one page of notes", "calculators allowed", "no calculators"]
            where lower.contains(rule) {
                notes = Lexicon.capitalizedFirst(rule.replacingOccurrences(of: "-", with: " "))
                break
            }
            if !isEmpty { quote = text }
        }

        mutating func merge(_ other: FormatLine, quote text: String) {
            multipleChoice = other.multipleChoice ?? multipleChoice
            multipleChoiceCount = other.multipleChoiceCount ?? multipleChoiceCount
            shortAnswer = other.shortAnswer ?? shortAnswer
            shortAnswerCount = other.shortAnswerCount ?? shortAnswerCount
            essay = other.essay ?? essay
            essayCount = other.essayCount ?? essayCount
            questionCount = other.questionCount ?? questionCount
            minutes = other.minutes ?? minutes
            notes = other.notes ?? notes
            quote = quote ?? text
        }

        func apply(to draft: inout Draft, quote text: String) {
            guard !isEmpty else { return }
            draft.exam.format.multipleChoice = multipleChoice ?? draft.exam.format.multipleChoice
            draft.exam.format.shortAnswer = shortAnswer ?? draft.exam.format.shortAnswer
            draft.exam.format.essay = essay ?? draft.exam.format.essay
            draft.exam.format.questionCount = questionCount ?? draft.exam.format.questionCount
            draft.exam.format.minutes = minutes ?? draft.exam.format.minutes
            draft.exam.format.notes = notes ?? draft.exam.format.notes
            draft.multipleChoiceCount = multipleChoiceCount ?? draft.multipleChoiceCount
            draft.shortAnswerCount = shortAnswerCount ?? draft.shortAnswerCount
            draft.essayCount = essayCount ?? draft.essayCount
            draft.exam.formatQuote = draft.exam.formatQuote ?? text
        }
    }
}
