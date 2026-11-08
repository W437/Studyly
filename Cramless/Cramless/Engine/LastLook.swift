import Foundation

/// What a last look holds on to between the days before an exam and its eve: the ideas picked, and the sentences written for them. It stays on this iPhone (a
/// moment, not a record) and goes with its exam.
struct LastLookPack: Codable, Equatable, Sendable {
    /// A sentence, with the words it was written from: once they change (a question that was fixed), it says the old thing, and it goes.
    struct Sentence: Codable, Equatable, Sendable {
        var sentence: String
        var prompt: String
        var answer: String
    }

    var examID: UUID
    /// The day the ideas were picked. They are picked again once on a later day, while the window lasts.
    var day: String
    /// The ideas, the shakiest first.
    var itemIDs: [UUID]
    /// By question id.
    var sentences: [UUID: Sentence] = [:]
    /// The day the cloud last answered, so a pack is asked for once a day at most.
    var askedDay: String?
}

/// Every exam's pack: `capling.lastlook.v1` in UserDefaults.
struct LastLookStore: Codable, Equatable, Sendable {
    static let defaultsKey = "capling.lastlook.v1"

    var packs: [UUID: LastLookPack] = [:]
}

/// The last look on an exam's eve (pure): the ideas a student is shakiest on, to read once and go to bed. No quiz, and nothing recorded. The same recall as the eve's
/// session reads (`FSRS.forecastRecall` on the exam's date), and no topic gets more than its share, so the screen isn't one chapter five times.
///
/// The ideas are chosen when the look opens, from everything the exam holds, as they stand then: an idea tonight's session put right sinks down the list, and one it didn't stays. Sentences
/// are written ahead of time for what's shakiest, from 48 hours before the exam until 18:00 on its eve (`AppModel.prepareLastLooks()`), so they're on the phone with no connection; an idea
/// without one says its question and answer. With fewer than five studied ideas it fills with questions not studied yet, so an eve with questions always has something to look at.
struct LastLookEngine: Sendable {
    /// How many ideas are prepared, and how many are shown.
    static let prepared = 8
    static let shown = 5
    static let perTopic = 2
    /// The window opens this long before the exam...
    static let opensBefore: TimeInterval = 48 * 3600
    /// ...and closes at this hour on its eve.
    static let closesAtHour = 18
    /// About how long it takes to read one idea and look away.
    static let secondsPerIdea = 24.0
    /// A sentence's content words that must be in the question, its answer and its lines.
    static let requiredOverlap = 0.8
    /// Fewer words than this aren't a sentence: "4" says nothing without its question.
    static let shortestSentence = 3

    var fsrs: FSRS
    var calendar: Calendar
    var now: Date

    /// The window is open for this exam.
    func isPreparing(for exam: ExamSnapshot) -> Bool {
        guard exam.date > now, now >= exam.date.addingTimeInterval(-Self.opensBefore) else { return false }
        let eve = calendar.adding(days: -1, to: calendar.startOfDay(for: exam.date))
        guard let closes = calendar.date(bySettingHour: Self.closesAtHour, minute: 0, second: 0, of: eve) else { return false }
        return now < closes
    }

    /// The ideas that may be looked at, the shakiest first, at most `limit`: studied, active questions in these exams' scopes (exams on one day share an evening) with lowest
    /// recall on the exam's day. A diagram needs its picture, and a question the student reported may be wrong, so neither is here. At most
    /// `perTopic` from a topic, unless the scope has too few topics to reach `limit`. `taken`: ideas already chosen, which count toward their topics.
    func picks(items: [ItemSnapshot], exams: [ExamSnapshot], limit: Int, taken: [ItemSnapshot] = []) -> [UUID] {
        guard limit > 0 else { return [] }
        var ranked: [(item: ItemSnapshot, recall: Double)] = []
        let chosen = Set(taken.map(\.id))
        for item in items where item.isActive && item.isStudied && !item.reported && item.kind != .diagram && !chosen.contains(item.id) {
            guard let exam = exams.first(where: { $0.covers(item) }), let last = item.memory.lastReview else { continue }
            ranked.append((item, fsrs.forecastRecall(stability: item.memory.stability, last: last, at: exam.date)))
        }
        ranked.sort { a, b in
            a.recall != b.recall ? a.recall < b.recall : a.item.id < b.item.id
        }
        var counts: [UUID: Int] = [:]
        for item in taken { if let topic = item.topicID { counts[topic, default: 0] += 1 } }
        var out: [UUID] = []
        var skipped: [UUID] = []
        for entry in ranked where out.count < limit {
            if let topic = entry.item.topicID {
                if counts[topic, default: 0] >= Self.perTopic {
                    skipped.append(entry.item.id)
                    continue
                }
                counts[topic, default: 0] += 1
            }
            out.append(entry.item.id)
        }
        // A scope of one or two topics: its next shakiest, rather than a screen of two ideas.
        out += skipped.prefix(limit - out.count)
        return out
    }

    /// What tonight shows: the shakiest of everything these exams hold, as they stand now, then (if too few have been studied) questions not studied yet.
    func shown(items: [ItemSnapshot], exams: [ExamSnapshot]) -> [UUID] {
        let studied = picks(items: items, exams: exams, limit: Self.shown)
        guard studied.count < Self.shown else { return studied }
        let fresh = items.filter { item in
            item.isActive && !item.isStudied && !item.reported && item.kind != .diagram && exams.contains { $0.covers(item) }
        }
        return studied + fresh.sorted { $0.id < $1.id }.prefix(Self.shown - studied.count).map(\.id)
    }

    /// "About 2 minutes".
    static func minutes(ideas: Int) -> Int { max(1, Int((Double(ideas) * secondsPerIdea / 60).rounded())) }

    /// A sentence may be shown only if it says what the question, its answer and its lines say: its content words are there, and every number and every "not" in it. It can't judge
    /// meaning, only catch a sentence that strays, and then the question and its answer are said instead.
    static func keeps(sentence: String, question: String, answer: String, lines: [String]) -> Bool {
        let words = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return false }
        let source = ([question, answer] + lines).joined(separator: "\n")
        let tokens = Lexicon.tokens(words)
        guard tokens.count >= shortestSentence, Lexicon.overlap(of: words, with: source) >= requiredOverlap else { return false }
        let theirs = Lexicon.tokens(source)
        let numbers = Set(theirs.filter(\.isNumber).map(\.word))
        let negative = theirs.contains(where: \.isNegation)
        for token in tokens {
            if token.isNumber, !numbers.contains(token.word) { return false }
            if token.isNegation, !negative { return false }
        }
        return true
    }
}

/// One idea on the screen.
struct LastLookIdea: Identifiable, Equatable, Sendable {
    var id: UUID
    var topic: String?
    /// Empty for a fill-in, whose answer is its whole sentence.
    var question: String
    var answer: String
    /// Cap's sentence, written from the student's own question and lines. Nil: the question and its answer say it.
    var sentence: String?
    var ref: SourceRef?

    /// An answer that means nothing on a line of its own: a number or a word or two, which reads in one breath with its question.
    var answerIsBare: Bool { sentence == nil && !question.isEmpty && answer.count <= 12 && Lexicon.wordCount(answer) <= 2 }
}

/// A last look as its screen shows it.
struct LastLook: Equatable, Sendable {
    var examID: UUID
    var ideas: [LastLookIdea]

    var minutes: Int { LastLookEngine.minutes(ideas: ideas.count) }
    /// Any of it is Cap's own wording.
    var isWritten: Bool { ideas.contains { $0.sentence != nil } }
}

/// The last look's words. The night says good night once: on the eve's summary, which holds the ideas itself, or on this screen when it
/// opens on its own.
enum LastLookCopy {
    /// The screen's title when it opens on its own: "Your 5 shakiest ideas".
    static func title(ideas: Int) -> String { String(localized: "Your \(ideas) shakiest ideas") }

    /// "2 min · no quiz".
    static func line(minutes: Int) -> String { String(localized: "\(minutes) min · no quiz") }

    /// The eve summary's heading over the ideas: "Read these once · 2 min".
    static func readOnce(minutes: Int) -> String { String(localized: "Read these once · \(minutes) min") }

    /// Under the ideas, when Cap wrote any of them. Nil when he wrote none.
    static func written(_ look: LastLook) -> String? {
        let his = look.ideas.filter { $0.sentence != nil }.count
        guard his > 0 else { return nil }
        return his == look.ideas.count ? String(localized: "Cap wrote these from your questions and notes.")
            : String(localized: "Cap wrote the sentences from your questions and notes. The rest are your own questions.")
    }

    static func spoken(ideas: Int) -> LocalizedStringResource { "Your last look: \(ideas) ideas, no quiz" }
}
