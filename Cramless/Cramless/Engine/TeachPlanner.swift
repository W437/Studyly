import Foundation

/// One question of a topic, as Teach Cap reads it.
struct TeachItem: Sendable, Equatable {
    var id: UUID
    var kind: ItemKind
    var prompt: String
    /// The right option's words, a fill-in's blank, or the model answer.
    var answer: String
    var ideas: [KeyIdea] = []
    /// Chance of recall now; nil when it has never been studied.
    var recall: Double? = nil
}

/// One idea Cap hopes to hear, and the question behind it.
struct TeachIdea: Sendable, Equatable, Identifiable {
    /// "t1"…: unique in the plan (two questions can each have a "k1").
    var idea: KeyIdea
    var itemID: UUID
    var id: String { idea.id }
    var label: String { idea.label }
}

/// What explaining a topic to Cap is checked against.
struct TeachPlan: Sendable, Equatable {
    var topicID: UUID
    var topicName: String
    var courseID: UUID?
    var ideas: [TeachIdea]

    /// The grader's view of it: a question that isn't in the student's library, whose key ideas are the plan's. Goes through the same grade path
    /// as any own-words answer, so the relay needs nothing new (it takes up to 12 ideas; this has at most 6).
    func subject(level: String?) -> GradeSubject {
        GradeSubject(kind: .recall, prompt: "Explain \(topicName)", modelAnswer: ideas.map(\.label).joined(separator: ". "),
                     keyIdeas: ideas.map(\.idea), level: level)
    }

    /// The first idea of these that wasn't covered, in the plan's order: weakest first.
    func firstMissing(covered: Set<String>) -> TeachIdea? {
        ideas.first { !covered.contains($0.id) }
    }
}

/// A topic the student knows well enough to be offered Teach Cap.
struct NoticeTeachBack: Equatable, Sendable {
    var topicID: UUID
    var topicName: String
    var courseID: UUID?
}

/// What Teach Cap asks about, and when Cap offers it. Pure.
///
/// A plan is up to six ideas, weakest first: a question's key ideas, or its answer as one idea when it has none, one idea from each question before
/// a second from any. Questions never studied come last: nobody should be marked down for what they haven't met yet.
///
/// The offer ("You know \(topic). Can you teach it?") reads topic recall (`ReadinessEngine.topicMastery`), which no screen shows as a number. It
/// wants most of the topic studied and well remembered, an exam a week or more away (closer than that, reviews matter more), and no teaching of it in the last
/// 14 days.
enum TeachPlanner {
    static let maxIdeas = 6
    static let minIdeas = 2
    /// How well a topic has to be remembered for Cap to say "you know it".
    static let offerRecall = 0.85
    static let offerMinStudied = 3
    static let offerStudiedShare = 0.6
    static let offerExamDays = 7
    static let offerQuietDays = 14

    static func plan(topicID: UUID, topicName: String, courseID: UUID?, items: [TeachItem]) -> TeachPlan? {
        // The weakest first; the never studied after every studied one; ties in a fixed order.
        let ordered = items.sorted { a, b in
            switch (a.recall, b.recall) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.id.uuidString < b.id.uuidString
            }
        }
        let perItem = ordered.map { (item: $0, ideas: ideas(of: $0)) }
        var chosen: [TeachIdea] = []
        var seen = Set<String>()
        var round = 0
        while chosen.count < maxIdeas, perItem.contains(where: { round < $0.ideas.count }) {
            for entry in perItem where round < entry.ideas.count && chosen.count < maxIdeas {
                let idea = entry.ideas[round]
                guard seen.insert(normal(idea.label)).inserted else { continue }
                chosen.append(TeachIdea(idea: KeyIdea(id: "t\(chosen.count + 1)", label: idea.label, terms: idea.terms), itemID: entry.item.id))
            }
            round += 1
        }
        guard chosen.count >= minIdeas else { return nil }
        return TeachPlan(topicID: topicID, topicName: topicName, courseID: courseID, ideas: chosen)
    }

    /// A question's ideas: its own, or its answer as one idea.
    static func ideas(of item: TeachItem) -> [KeyIdea] {
        if !item.ideas.isEmpty { return item.ideas.filter { !$0.label.isEmpty } }
        let answer = item.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return [] }
        return [KeyIdea(id: "a", label: answer, terms: terms(of: answer))]
    }

    /// A short answer is its own term; in a long one nobody says every word in order, so its longest words count too.
    static func terms(of answer: String) -> [String] {
        let words = answer.split(whereSeparator: \.isWhitespace).map { $0.trimmingCharacters(in: .punctuationCharacters) }
        guard words.count > 4 else { return [answer.lowercased()] }
        let long = words.filter { $0.count >= 6 }.sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }.prefix(3)
        return [answer.lowercased()] + long.map { $0.lowercased() }
    }

    /// The grader's view of the question behind a missed idea, whatever its kind: the follow-up is answered in the person's own words, without its options.
    static func followUpSubject(_ item: TeachItem, level: String?) -> GradeSubject {
        GradeSubject(kind: .recall, prompt: item.prompt, modelAnswer: item.answer, keyIdeas: ideas(of: item), level: level)
    }

    /// The topics to offer, the best remembered first. `mastery`: `ReadinessEngine.topicMastery` of each course. `taught`: when each topic (its uuidString)
    /// was last taught.
    static func offers(mastery: [TopicReadiness], courseOf: [UUID: UUID], items: [ItemSnapshot], exams: [ExamSnapshot], taught: [String: Date], now: Date,
                       calendar: Calendar) -> [NoticeTeachBack] {
        let index = ExamIndex(exams, after: now, calendar: calendar)
        var byTopic: [UUID: [ItemSnapshot]] = [:]
        for item in items where item.isActive {
            if let topic = item.topicID { byTopic[topic, default: []].append(item) }
        }
        let good = mastery.compactMap { topic -> (NoticeTeachBack, Double)? in
            guard let recall = topic.value, recall >= offerRecall, let its = byTopic[topic.id] else { return nil }
            let studied = its.filter(\.isStudied).count
            guard studied >= offerMinStudied, Double(studied) / Double(its.count) >= offerStudiedShare else { return nil }
            if let date = taught[topic.id.uuidString], calendar.dayDistance(from: date, to: now) < offerQuietDays { return nil }
            let days = its.compactMap { index.soonest(covering: $0) }.compactMap { index.daysLeft[$0.id] }.min()
            if let days, days < offerExamDays { return nil }
            return (NoticeTeachBack(topicID: topic.id, topicName: topic.name, courseID: courseOf[topic.id]), recall)
        }
        return good.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.topicName < $1.0.topicName }.map(\.0)
    }

    private static func normal(_ label: String) -> String {
        label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
