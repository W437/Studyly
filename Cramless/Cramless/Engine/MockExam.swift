import Foundation

/// A mock exam before it starts: its questions in order, its time limit, and the fair score for it.
struct MockPlan: Sendable, Equatable {
    var examID: UUID
    var courseID: UUID?
    /// Multiple choice first, then the rest, each part with its topics interleaved. No repeats: a mock asks each question once.
    var entries: [SessionEntry]
    /// The time limit, in whole minutes, rounded up to 5.
    var minutes: Int
    /// What each question is expected to earn, by item: its recall now, plus the guessing floor on multiple choice. Nothing else goes
    /// into "Cap predicted".
    var expectedByItem: [UUID: Double]

    var multipleChoiceCount: Int { entries.filter { $0.kind == .mcq }.count }
    /// Fill-ins are marked at once; short answers and essays go to marking.
    var fillInCount: Int { entries.filter { $0.kind == .cloze }.count }
    var shortCount: Int { entries.filter { $0.kind == .recall }.count }
    var essayCount: Int { entries.filter { $0.kind == .apply }.count }

    /// The fair score for the whole mock.
    var expected: Double { MockScorer.mean(entries.map { expectedByItem[$0.itemID] ?? 0 }) }

    /// The session this mock runs as.
    func built(id: UUID = UUID()) -> BuiltSession {
        BuiltSession(id: id, kind: .mock, entries: entries, budgetSeconds: Double(minutes) * 60, courseID: courseID, examID: examID)
    }
}

/// Builds a mock from an exam's own questions. Pure and seeded: the same inputs give the same mock.
///
/// Only the exam's scope, only the kinds its format has (multiple choice: `.mcq`; short answer: `.recall` and `.cloze`; essay: `.apply`; none
/// ticked: all four). Flashcards and diagrams don't sit in a mock. Questions never studied are in there in proportion: a real exam
/// doesn't skip them. Every topic gets its share by how many questions it has (largest remainder, at least one each while there's
/// room), and multiple choice takes three in four places where the format has both.
struct MockExamBuilder: Sendable {
    /// Below this a mock wouldn't be worth the name.
    static let minimumQuestions = 8
    static let defaultSize = 20
    static let maximumSize = 40
    /// Multiple choice's share of a mock whose format also has written answers.
    static let multipleChoiceShare = 0.75
    /// A blind guess on a multiple-choice question with an unknown number of options.
    static let defaultChoices = 4

    var fsrs: FSRS
    var calendar: Calendar
    var now: Date

    /// The kinds a format's mock asks.
    static func kinds(for format: ExamFormat) -> Set<ItemKind> {
        var kinds: Set<ItemKind> = []
        if format.multipleChoice { kinds.insert(.mcq) }
        if format.shortAnswer { kinds.formUnion([.recall, .cloze]) }
        if format.essay { kinds.insert(.apply) }
        return kinds.isEmpty ? [.mcq, .recall, .cloze, .apply] : kinds
    }

    /// The questions of `items` a mock of this exam can ask.
    static func eligible(_ items: [ItemSnapshot], exam: ExamSnapshot) -> [ItemSnapshot] {
        let kinds = kinds(for: exam.format)
        return items.filter { $0.isActive && kinds.contains($0.kind) && exam.covers($0) }
    }

    /// How long a mock's question gets, when the exam's own pace isn't known.
    static func seconds(for kind: ItemKind) -> Double {
        switch kind {
        case .mcq: 60
        case .cloze: 45
        case .recall: 120
        case .apply: 180
        case .diagram, .flashcard: 45
        }
    }

    /// The mock's size: what the exam says, kept to what a sitting can take.
    static func size(format: ExamFormat, requested: Int?) -> Int {
        let wanted = requested ?? format.questionCount ?? defaultSize
        return min(maximumSize, max(minimumQuestions, wanted))
    }

    /// The time limit: the real exam's pace for this many questions when both its length and its size are known, else the kinds' own
    /// time (never past the real exam's length, when only that is known); rounded up to 5 minutes.
    static func minutes(for entries: [SessionEntry], format: ExamFormat) -> Int {
        var raw = entries.reduce(0) { $0 + seconds(for: $1.kind) } / 60
        if let minutes = format.minutes, minutes > 0 {
            if let count = format.questionCount, count > 0 {
                raw = Double(minutes) * Double(entries.count) / Double(count)
            } else {
                raw = min(raw, Double(minutes))
            }
        }
        return max(5, Int((raw / 5).rounded(.up)) * 5)
    }

    /// `choices`: how many options each multiple-choice question has (a blind guess's chance), by item. `items` are what may be asked
    /// beyond the format's rules (the app leaves out what the student reported). Nil below `minimumQuestions`.
    func build(exam: ExamSnapshot, items: [ItemSnapshot], choices: [UUID: Int] = [:], seed: UInt64, size: Int? = nil) -> MockPlan? {
        let pool = Self.eligible(items, exam: exam)
        guard pool.count >= Self.minimumQuestions else { return nil }
        let wanted = min(Self.size(format: exam.format, requested: size), pool.count)
        let picked = pick(pool, count: wanted, seed: seed)

        let entries = picked.map { item in
            SessionEntry(itemID: item.id, reason: item.isStudied ? .due : .new, kind: item.kind, topicID: item.topicID,
                         courseID: item.courseID, estimatedSeconds: Self.seconds(for: item.kind), examID: exam.id)
        }
        // Multiple choice first, then the rest; inside each part no topic twice in a row when it can be helped.
        let multiple = SessionBuilder.interleave(entries.filter { $0.kind == .mcq })
        let written = SessionBuilder.interleave(entries.filter { $0.kind != .mcq })
        let ordered = multiple + written

        var expected: [UUID: Double] = [:]
        for item in picked {
            let guess = item.kind == .mcq ? 1 / Double(max(2, choices[item.id] ?? Self.defaultChoices)) : 0
            expected[item.id] = Self.expectedCredit(recall: recall(of: item), guess: guess)
        }
        return MockPlan(examID: exam.id, courseID: exam.courseID, entries: ordered,
                        minutes: Self.minutes(for: ordered, format: exam.format), expectedByItem: expected)
    }

    /// The chance of remembering it now; 0 for a question never studied.
    private func recall(of item: ItemSnapshot) -> Double {
        guard item.isStudied, let last = item.memory.lastReview else { return 0 }
        return fsrs.forecastRecall(stability: item.memory.stability, last: last, at: now)
    }

    /// Remembered, or not remembered and guessed.
    static func expectedCredit(recall p: Double, guess g: Double) -> Double { p + (1 - p) * g }

    // MARK: Choosing

    private func pick(_ pool: [ItemSnapshot], count: Int, seed: UInt64) -> [ItemSnapshot] {
        // Each topic's questions in a seeded order, the buckets in a stable order (no topic comes last).
        var byTopic: [UUID?: [ItemSnapshot]] = [:]
        for item in pool { byTopic[item.topicID, default: []].append(item) }
        func rank(_ item: ItemSnapshot) -> UInt64 { StableRandom.mix(StableRandom.seed(item.id, day: 0) ^ seed) }
        let topics = byTopic.keys.sorted { a, b in
            let ca = byTopic[a]?.count ?? 0, cb = byTopic[b]?.count ?? 0
            if ca != cb { return ca > cb }
            return (a?.uuidString ?? "") < (b?.uuidString ?? "")
        }
        let quotas = Self.quotas(counts: topics.map { byTopic[$0]?.count ?? 0 }, total: count)

        // How many of each: three in four multiple choice where the pool has both, topped up from the other kind when one runs short.
        let multiple = pool.filter { $0.kind == .mcq }.count
        let written = pool.count - multiple
        var multipleTotal = written == 0 ? count : min(multiple, Int((Double(count) * Self.multipleChoiceShare).rounded()))
        if count - multipleTotal > written { multipleTotal = count - written }

        // Each topic's questions in the seeded order, split by kind, and that mix shared over the topics.
        let sorted = topics.map { (byTopic[$0] ?? []).sorted { rank($0) < rank($1) } }
        let multipleSplit = Self.split(multipleTotal, of: quotas, available: sorted.map { $0.filter { $0.kind == .mcq }.count },
                                       others: sorted.map { $0.filter { $0.kind != .mcq }.count })
        var picked: [ItemSnapshot] = []
        for (index, questions) in sorted.enumerated() {
            picked += questions.filter { $0.kind == .mcq }.prefix(multipleSplit[index])
            picked += questions.filter { $0.kind != .mcq }.prefix(quotas[index] - multipleSplit[index])
        }
        return picked
    }

    /// How many of each bucket's `quotas` places are multiple choice, `total` in all and as even a share of each as its questions allow:
    /// a bucket can't take more than it has, nor leave more places than its other questions can fill.
    static func split(_ total: Int, of quotas: [Int], available: [Int], others: [Int]) -> [Int] {
        let places = quotas.reduce(0, +)
        guard places > 0 else { return quotas.map { _ in 0 } }
        let share = Double(total) / Double(places)
        let lows = zip(quotas, others).map { max(0, $0 - $1) }
        let highs = zip(quotas, available).map { min($0, $1) }
        var split = quotas.indices.map { max(lows[$0], min(highs[$0], Int(Double(quotas[$0]) * share))) }
        var left = total - split.reduce(0, +)
        let order = quotas.indices.sorted { a, b in
            let ra = Double(quotas[a]) * share - Double(split[a]), rb = Double(quotas[b]) * share - Double(split[b])
            return ra != rb ? ra > rb : a < b
        }
        while left > 0 {
            var moved = false
            for index in order where left > 0 && split[index] < highs[index] {
                split[index] += 1
                left -= 1
                moved = true
            }
            if !moved { break }
        }
        // Over the total because of what the buckets must take: give back where a bucket can spare it.
        for index in order.reversed() {
            while left < 0, split[index] > lows[index] {
                split[index] -= 1
                left += 1
            }
        }
        return split
    }

    /// Shares of `total` by size, largest remainder, at least one each while there's room (the biggest first when there isn't), never
    /// more than a bucket holds.
    static func quotas(counts: [Int], total: Int) -> [Int] {
        let sum = counts.reduce(0, +)
        guard sum > 0, total > 0 else { return counts.map { _ in 0 } }
        let exact = counts.map { Double($0) * Double(total) / Double(sum) }
        var quotas = exact.map { Int($0) }
        let remainders = exact.indices.map { exact[$0] - Double(quotas[$0]) }
        var left = total - quotas.reduce(0, +)
        for index in exact.indices.sorted(by: { remainders[$0] != remainders[$1] ? remainders[$0] > remainders[$1] : $0 < $1 }) where left > 0 {
            guard quotas[index] < counts[index] else { continue }
            quotas[index] += 1
            left -= 1
        }
        // A small topic with nothing yet takes one from the bucket furthest over its exact share.
        for index in counts.indices where quotas[index] == 0 && counts[index] > 0 {
            let donors = quotas.indices.filter { quotas[$0] > 1 }
            guard let donor = donors.max(by: { Double(quotas[$0]) - exact[$0] < Double(quotas[$1]) - exact[$1] }) else { break }
            quotas[donor] -= 1
            quotas[index] = 1
        }
        return quotas
    }
}

/// Whether an exam offers a mock now.
enum MockOffer: Sendable, Equatable {
    /// Not on the eve, not on the day, not after.
    case hidden
    /// Fewer questions than a mock needs.
    case tooFew(have: Int)
    case ready(MockPlan)
}

/// When Today offers a mock (through Cap's cards): the exam is 2 to 7 days away, there are enough questions, and there hasn't been a mock
/// in the last 4 days.
enum MockSuggestion {
    static let days = 2...7
    static let restDays = 4

    static func isDue(daysLeft: Int, eligible: Int, lastMockAt: Date?, now: Date, calendar: Calendar) -> Bool {
        guard days.contains(daysLeft), eligible >= MockExamBuilder.minimumQuestions else { return false }
        guard let lastMockAt else { return true }
        return calendar.dayDistance(from: lastMockAt, to: now) >= restDays
    }
}

// MARK: - The score

/// One question at the end of a mock. `credit` is what it earned, 0…1; nil when it doesn't count (left blank, or not marked yet).
struct MockLine: Sendable, Equatable, Identifiable {
    var itemID: UUID
    var topicID: UUID?
    var expected: Double
    var credit: Double?

    var id: UUID { itemID }
}

/// How a mock went.
struct MockResult: Sendable, Equatable {
    enum Verdict: Sendable, Equatable { case asExpected, better, below }

    struct Topic: Sendable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var score: Double
        var counted: Int
    }

    /// Questions in the mock.
    var total: Int
    /// Questions that have a mark.
    var counted: Int
    /// Mean credit over those; nil when none has a mark yet.
    var score: Double?
    /// "Cap predicted": the same questions' expected credit, so stopping early stays a fair comparison.
    var expected: Double
    var verdict: Verdict?
    /// Weakest first.
    var topics: [Topic]
    /// Up to three topics under `MockScorer.weakBelow`.
    var weakest: [Topic]
}

/// Scores a mock from its lines. Only what has a mark counts, on both sides of the comparison.
enum MockScorer {
    /// Within this many points of the prediction is "Right where Cap expected."
    static let band = 5
    static let weakBelow = 0.7
    static let weakestShown = 3

    static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    static func score(_ lines: [MockLine], topicNames: [UUID: String]) -> MockResult {
        let counted = lines.filter { $0.credit != nil }
        let score = counted.isEmpty ? nil : mean(counted.compactMap(\.credit))
        let expected = mean((counted.isEmpty ? lines : counted).map(\.expected))
        var byTopic: [UUID: [Double]] = [:]
        for line in counted {
            guard let topic = line.topicID, let credit = line.credit else { continue }
            byTopic[topic, default: []].append(credit)
        }
        let topics = byTopic.compactMap { id, credits -> MockResult.Topic? in
            guard let name = topicNames[id] else { return nil }
            return MockResult.Topic(id: id, name: name, score: mean(credits), counted: credits.count)
        }.sorted { $0.score != $1.score ? $0.score < $1.score : $0.name < $1.name }
        let weakest = Array(topics.filter { $0.score < weakBelow }.prefix(weakestShown))
        return MockResult(total: lines.count, counted: counted.count, score: score, expected: expected,
                          verdict: score.map { verdict(score: $0, expected: expected) }, topics: topics, weakest: weakest)
    }

    /// Judged on the two numbers the person reads.
    static func verdict(score: Double, expected: Double) -> MockResult.Verdict {
        let gap = Int((score * 100).rounded()) - Int((expected * 100).rounded())
        if abs(gap) <= band { return .asExpected }
        return gap > 0 ? .better : .below
    }
}
