import Foundation

/// A mix-up worth naming, found from the review log without AI. The AI lane may rename it and write the fix.
struct ConfusionCandidate: Sendable, Equatable, Identifiable {
    enum Reason: String, Sendable {
        /// The given answer of one item was the expected answer of another.
        case swappedAnswers
        /// Items missed again and again.
        case repeatedMisses
        /// Two questions that look alike, spotted before any mistake (`LookAlikeFinder`; the person chose to learn the difference).
        case lookAlike
    }

    /// One item's mistakes, ready for the relay's `MistakeInput`.
    struct Mistake: Sendable, Equatable {
        var itemID: UUID
        var prompt: String
        var expected: String
        /// The most recent wrong answer the person gave ("" when they didn't type one).
        var given: String
        var misses: Int
    }

    /// Stable for the same items: use it to avoid offering the same candidate twice.
    var id: String
    var courseID: UUID?
    var topicID: UUID?
    /// "Anaphase vs telophase" for two short answers that were swapped, or the topic's name for repeated misses. When the rules have
    /// no honest name (the answers are sentences, not terms; the questions have no topic) it is `unnamed`: a plain description, never
    /// a name made up from the text of a question. Cloud AI names a mix-up in plain words when it is allowed.
    var name: String
    var reason: Reason
    var itemIDs: [UUID]
    /// Wrong answers to these items in the window.
    var missCount: Int
    var lastMissAt: Date
    var mistakes: [Mistake]

    /// What the screens call a mix-up the rules can't name. It says what it is, and `defaultExplanation` says how many misses on
    /// how many questions.
    static let unnamed = "Questions you keep missing"

    var isNamed: Bool { name != Self.unnamed }

    /// What the rules can say about it: nothing that isn't counted for a mix-up they couldn't name ("3 misses on these 2 questions"),
    /// and the count of misses for one they could.
    var defaultExplanation: String {
        isNamed ? "You've missed these \(missCount) times in the last two weeks."
            : ConfusionFinder.description(misses: missCount, questions: itemIDs.count)
    }
}

/// Finds confusion candidates in the last 14 days of answers:
/// - swapped answers: an item's wrong answer equals another item's expected answer (same course, compared
///   case-, accent- and punctuation-blind); two or more such swaps between the same items make a candidate,
///   named "A vs b" from their expected answers (items swapped with each other in a chain join one group);
/// - repeated misses: an item missed 3 or more times, grouped by topic, named after the topic.
/// Items already in an open confusion are left out; a candidate inside a dismissed confusion is not offered
/// again.
struct ConfusionFinder: Sendable {
    var calendar: Calendar
    var now: Date
    var windowDays = 14
    var minMisses = 3
    var minSwaps = 2

    init(calendar: Calendar, now: Date, windowDays: Int = 14, minMisses: Int = 3, minSwaps: Int = 2) {
        self.calendar = calendar
        self.now = now
        self.windowDays = windowDays
        self.minMisses = minMisses
        self.minSwaps = minSwaps
    }

    /// Lowercased, accents folded, punctuation dropped, whitespace collapsed.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var out = ""
        var space = false
        for ch in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(ch) {
                if space && !out.isEmpty { out.append(" ") }
                out.unicodeScalars.append(ch)
                space = false
            } else {
                space = true
            }
        }
        return out
    }

    /// "Anaphase" from "Anaphase.", "the sister chromatids are pulled apart" → its first few words.
    static func shortName(_ text: String, words: Int = 4) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let parts = trimmed.split(separator: " ")
        let short = parts.prefix(words).joined(separator: " ")
        return parts.count > words ? short + "…" : short
    }

    /// A short answer that can stand as a name ("Anaphase", "Sister chromatids"): not a sentence cut short.
    static func isTerm(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.hasSuffix("…") else { return false }
        return t.trimmingCharacters(in: .punctuationCharacters).split(separator: " ").count <= 3
    }

    /// How many misses on how many questions, for a mix-up with no name: "3 misses on these 2 questions", "2 misses on this question".
    static func description(misses: Int, questions: Int) -> String {
        let m = max(1, misses), q = max(1, questions)
        return "\(m == 1 ? "1 miss" : "\(m) misses") on \(q == 1 ? "this question" : "these \(q) questions")"
    }

    static func joinNames(_ names: [String]) -> String {
        guard let first = names.first else { return "" }
        func lowerFirst(_ s: String) -> String {
            // Keep acronyms and proper-looking words ("DNA", "Mendel") as they are.
            guard let c = s.first, c.isUppercase, s.count > 1 else { return s }
            let second = s[s.index(after: s.startIndex)]
            return second.isUppercase ? s : c.lowercased() + s.dropFirst()
        }
        let head = first.prefix(1).uppercased() + first.dropFirst()
        let rest = names.dropFirst().map(lowerFirst)
        switch rest.count {
        case 0: return head
        case 1: return "\(head) vs \(rest[0])"
        case 2: return "\(head), \(rest[0]) and \(rest[1])"
        default: return "\(head), \(rest[0]) and \(rest.count - 1) more"
        }
    }

    static func stableID(_ prefix: String, _ ids: [UUID]) -> String {
        let joined = ids.map(\.uuidString).sorted().joined(separator: "+")
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in joined.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
        return "\(prefix)-" + String(StableRandom.mix(h), radix: 16)
    }

    func candidates(items: [ItemAnswerInfo], logs: [ReviewSnapshot], existing: [ConfusionSnapshot] = [],
                    topicNames: [UUID: String] = [:]) -> [ConfusionCandidate] {
        let since = calendar.adding(days: -windowDays, to: now)
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let openItems = Set(existing.filter { $0.status == .open }.flatMap { $0.itemIDs + $0.fixItemIDs })
        let dismissed = existing.filter { $0.status == .dismissed }.map { Set($0.itemIDs) }

        // Accepted answers by course: normalized answer → items it belongs to.
        var answers: [UUID?: [String: [UUID]]] = [:]
        var ownAnswers: [UUID: Set<String>] = [:]
        for item in items {
            let set = Set(item.accepted.map(Self.normalize).filter { $0.count >= 2 })
            ownAnswers[item.id] = set
            for a in set { answers[item.courseID, default: [:]][a, default: []].append(item.id) }
        }

        var misses: [UUID: Int] = [:]
        var lastMiss: [UUID: Date] = [:]
        var lastGiven: [UUID: (Date, String)] = [:]
        var swaps: [Pair: Int] = [:]
        for log in logs where log.reviewedAt >= since && log.reviewedAt <= now && !log.wasCorrect {
            guard let item = byID[log.itemID] else { continue }
            misses[item.id, default: 0] += 1
            if (lastMiss[item.id] ?? .distantPast) < log.reviewedAt { lastMiss[item.id] = log.reviewedAt }
            if let given = log.answer, !given.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if (lastGiven[item.id]?.0 ?? .distantPast) < log.reviewedAt { lastGiven[item.id] = (log.reviewedAt, given) }
                let g = Self.normalize(given)
                guard g.count >= 2, ownAnswers[item.id]?.contains(g) != true else { continue }
                for other in answers[item.courseID]?[g] ?? [] where other != item.id {
                    swaps[Pair(item.id, other), default: 0] += 1
                }
            }
        }

        // Swap groups: pairs with enough swaps, joined transitively.
        var parent: [UUID: UUID] = [:]
        func find(_ x: UUID) -> UUID {
            var r = x
            while let p = parent[r], p != r { r = p }
            var c = x
            while let p = parent[c], p != r { parent[c] = r; c = p }
            return r
        }
        func union(_ a: UUID, _ b: UUID) {
            if parent[a] == nil { parent[a] = a }
            if parent[b] == nil { parent[b] = b }
            let ra = find(a), rb = find(b)
            if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
        }
        for (pair, count) in swaps where count >= minSwaps { union(pair.a, pair.b) }
        var groups: [UUID: [UUID]] = [:]
        for id in parent.keys { groups[find(id), default: []].append(id) }

        var out: [ConfusionCandidate] = []
        var grouped = Set<UUID>()
        for members in groups.values {
            let ids = members.filter { !openItems.contains($0) }.sorted()
            guard ids.count >= 2 else { continue }
            grouped.formUnion(ids)
            if dismissed.contains(where: { Set(ids).isSubset(of: $0) }) { continue }
            let names = ids.compactMap { byID[$0] }.map { Self.shortName($0.expected) }
            let uniqueNames = Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let first = byID[ids[0]]
            // Named only when the swapped answers are terms; two sentences cut short are no name.
            let swapName = uniqueNames.allSatisfy(Self.isTerm) ? Self.joinNames(uniqueNames) : ConfusionCandidate.unnamed
            out.append(ConfusionCandidate(
                id: Self.stableID("swap", ids), courseID: first?.courseID,
                topicID: Set(ids.compactMap { byID[$0]?.topicID }).count == 1 ? first?.topicID : nil,
                name: swapName, reason: .swappedAnswers, itemIDs: ids,
                missCount: ids.reduce(0) { $0 + (misses[$1] ?? 0) },
                lastMissAt: ids.compactMap { lastMiss[$0] }.max() ?? now,
                mistakes: mistakes(ids, byID: byID, misses: misses, lastGiven: lastGiven)))
        }

        // Repeated misses, by topic.
        var byTopic: [String: [UUID]] = [:]
        for (id, count) in misses where count >= minMisses && !grouped.contains(id) && !openItems.contains(id) {
            guard let item = byID[id] else { continue }
            let key = "\(item.courseID?.uuidString ?? "-")|\(item.topicID?.uuidString ?? id.uuidString)"
            byTopic[key, default: []].append(id)
        }
        for ids in byTopic.values {
            let sorted = ids.sorted()
            if dismissed.contains(where: { Set(sorted).isSubset(of: $0) }) { continue }
            guard let first = byID[sorted[0]] else { continue }
            // The topic's name, which is the person's own; the text of a question is not a name.
            let name = first.topicID.flatMap { topicNames[$0] }.map { Self.joinNames([$0]) } ?? ConfusionCandidate.unnamed
            out.append(ConfusionCandidate(
                id: Self.stableID("miss", sorted), courseID: first.courseID, topicID: first.topicID,
                name: name, reason: .repeatedMisses, itemIDs: sorted,
                missCount: sorted.reduce(0) { $0 + (misses[$1] ?? 0) },
                lastMissAt: sorted.compactMap { lastMiss[$0] }.max() ?? now,
                mistakes: mistakes(sorted, byID: byID, misses: misses, lastGiven: lastGiven)))
        }

        return out.sorted { a, b in
            if a.reason != b.reason { return a.reason == .swappedAnswers }
            if a.missCount != b.missCount { return a.missCount > b.missCount }
            if a.lastMissAt != b.lastMissAt { return a.lastMissAt > b.lastMissAt }
            return a.id < b.id
        }
    }

    private func mistakes(_ ids: [UUID], byID: [UUID: ItemAnswerInfo], misses: [UUID: Int],
                          lastGiven: [UUID: (Date, String)]) -> [ConfusionCandidate.Mistake] {
        ids.compactMap { id in
            guard let item = byID[id] else { return nil }
            return ConfusionCandidate.Mistake(itemID: id, prompt: item.prompt, expected: item.expected,
                                              given: lastGiven[id]?.1 ?? "", misses: misses[id] ?? 0)
        }
    }

    /// An unordered pair of items.
    struct Pair: Hashable {
        let a: UUID
        let b: UUID
        init(_ x: UUID, _ y: UUID) {
            if x < y { a = x; b = y } else { a = y; b = x }
        }
    }
}
