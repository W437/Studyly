import Foundation

/// The course page's Questions tab, as plain values: what each question is, which filter it passes and how many each chip counts. Pure:
/// recall and mix-ups come in from `AppModel.courseQuestionRows(_:)`.
enum CourseQuestions {
    struct Row: Identifiable, Equatable, Sendable {
        var id: UUID
        var kind: ItemKind
        var topicID: UUID?
        var isSuspended: Bool
        /// Its chance of recall now; nil if it hasn't been studied.
        var recall: Double?
        /// One of the questions of an open mix-up.
        var inMixUp: Bool

        /// Fading (studied and under the sky's dim line) or in an open mix-up. A suspended question waits for nothing.
        var needsAttention: Bool {
            guard !isSuspended else { return false }
            if inMixUp { return true }
            return recall.map { $0 < ReviewOutcome.fadingRecall } ?? false
        }
    }

    enum Filter: Hashable, Sendable {
        case all, attention, suspended
        case kind(ItemKind)
    }

    struct Counts: Equatable, Sendable {
        var all = 0
        var attention = 0
        var suspended = 0
        var kinds: [ItemKind: Int] = [:]
    }

    /// What each chip counts, within the chosen topic.
    static func counts(_ rows: [Row], topic: UUID?) -> Counts {
        var counts = Counts()
        for row in rows where topic == nil || row.topicID == topic {
            counts.all += 1
            if row.needsAttention { counts.attention += 1 }
            if row.isSuspended { counts.suspended += 1 }
            counts.kinds[row.kind, default: 0] += 1
        }
        return counts
    }

    /// The rows a filter shows, in their order; "Needs attention" puts the weakest first (a mix-up with no recall yet counts as nothing
    /// remembered).
    static func filtered(_ rows: [Row], filter: Filter, topic: UUID?) -> [Row] {
        let inTopic = rows.filter { topic == nil || $0.topicID == topic }
        switch filter {
        case .all: return inTopic
        case .suspended: return inTopic.filter(\.isSuspended)
        case .kind(let kind): return inTopic.filter { $0.kind == kind }
        case .attention:
            return inTopic.filter(\.needsAttention).enumerated().sorted { a, b in
                let ra = a.element.recall ?? 0, rb = b.element.recall ?? 0
                return ra != rb ? ra < rb : a.offset < b.offset
            }.map(\.element)
        }
    }

    /// `CRAMLESS_COURSE_FILTER`: `attention`, `suspended` or a format's raw value.
    static func filter(named name: String) -> Filter? {
        switch name {
        case "attention": .attention
        case "suspended": .suspended
        case "all": .all
        default: ItemKind(rawValue: name).map(Filter.kind)
        }
    }
}
