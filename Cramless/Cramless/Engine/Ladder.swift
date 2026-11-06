import Foundation

// Harder questions: when a question has become easy, the same idea asked a harder way takes its place. One idea stays one review, so
// nothing piles up: the easy question rests (suspended, its memory kept), and the harder one arrives as a draft the student adds. Pure.
enum Ladder {
    /// What "too easy" means: in review, remembered for at least this many days...
    static let strongStability = 21.0
    /// ...and this many right answers in a row (Good or Easy), each...
    static let strongRun = 3
    /// ...at least this far from the one before, so a cram doesn't count.
    static let strongGap: TimeInterval = 4 * 86_400
    /// Not this close to an exam that covers it: nobody changes a question they're about to be tested on.
    static let examClearDays = 3
    /// How far readiness may move when a harder question takes over, in points.
    static let maxReadinessDrop = 2.0
    /// The lines either side of a question's own that the writer reads.
    static let contextLines = 2

    /// The next harder format for the same idea. Nil: nothing harder (an applied question, a diagram).
    static func next(after kind: ItemKind) -> ItemKind? {
        switch kind {
        case .mcq: .cloze
        case .cloze: .recall
        case .recall: .apply
        case .flashcard: .recall
        case .apply, .diagram: nil
        }
    }

    /// Whether this question has become too easy. `reviews` in any order.
    static func isStrong(_ memory: MemoryState, reviews: [ReviewSnapshot]) -> Bool {
        guard memory.state == .review, memory.stability >= strongStability else { return false }
        let lastRun = reviews.sorted { $0.reviewedAt < $1.reviewedAt }.suffix(strongRun)
        guard lastRun.count == strongRun, lastRun.allSatisfy({ $0.rating == .good || $0.rating == .easy }) else { return false }
        return zip(lastRun, lastRun.dropFirst()).allSatisfy { $1.reviewedAt.timeIntervalSince($0.reviewedAt) >= strongGap }
    }

    /// Where the harder question starts, so taking over doesn't sink readiness: as a review, not a new question (which counts as nothing
    /// remembered), weaker and harder than the easy one, and due tomorrow. It's a guess at how it will go, and its first answer corrects it.
    static func seedMemory(parent: MemoryState, now: Date, calendar: Calendar) -> MemoryState {
        var memory = MemoryState()
        memory.state = .review
        memory.stability = min(14, max(3, parent.stability * 0.5))
        memory.difficulty = min(10, max(1, parent.difficulty + 1.5))
        memory.lastReview = now
        memory.due = calendar.date(byAdding: .day, value: 1, to: now)
        memory.reps = 1
        return memory
    }

    /// What decides an offer, read from the store once.
    struct Candidate: Equatable, Sendable {
        var id: UUID
        var kind: ItemKind
        var memory: MemoryState
        var reviews: [ReviewSnapshot]
        /// It points at lines of its source, so there's something to write from.
        var hasAnchors: Bool
        /// A harder question exists for it already (a draft or added).
        var climbed = false
        /// "Not this one" or "Later", not expired yet.
        var snoozed = false
        /// The soonest exam that covers it.
        var soonestExam: Date? = nil
    }

    struct Offer: Equatable, Sendable {
        var itemID: UUID
        var next: ItemKind
    }

    /// The questions worth moving up, the strongest first. Nothing without Cloud AI: only a model can write the harder one.
    static func offers(_ candidates: [Candidate], cloudUsable: Bool, now: Date, calendar: Calendar) -> [Offer] {
        guard cloudUsable else { return [] }
        return candidates
            .filter { candidate in
                guard candidate.hasAnchors, !candidate.climbed, !candidate.snoozed, next(after: candidate.kind) != nil,
                      isStrong(candidate.memory, reviews: candidate.reviews) else { return false }
                guard let exam = candidate.soonestExam else { return true }
                return calendar.dayDistance(from: now, to: exam) > examClearDays
            }
            .sorted { ($0.memory.stability, $0.id.uuidString) > ($1.memory.stability, $1.id.uuidString) }
            .compactMap { candidate in next(after: candidate.kind).map { Offer(itemID: candidate.id, next: $0) } }
    }

    /// The writer's lines: the question's own and the `contextLines` either side of each, in order, at most `limit`, its own first if it must cut.
    static func neighbourhood(of anchors: [String], in lines: [TextLine], limit: Int) -> [TextLine] {
        let wanted = Set(anchors)
        var keep = Set<Int>()
        for (index, line) in lines.enumerated() where wanted.contains(line.id) {
            keep.formUnion(max(0, index - contextLines)...min(lines.count - 1, index + contextLines))
        }
        var chosen = keep.sorted()
        if chosen.count > limit {
            let own = chosen.filter { wanted.contains(lines[$0].id) }
            chosen = Array(own.prefix(limit))
        }
        return chosen.map { lines[$0] }
    }
}
