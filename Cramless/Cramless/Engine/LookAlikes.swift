import Foundation

/// One question as the look-alike finder reads it. Its words are put in comparable form once, when it is made, so that finding pairs over
/// thousands of questions costs little.
struct LookAlikeItem: Sendable, Identifiable {
    var id: UUID
    var courseID: UUID?
    var topicID: UUID?
    /// What the question is about, when it has a short name: a flashcard's front if that's a term, else its answer if that's one.
    var term: String?
    /// The term in comparable form ("la casa").
    var key: String = ""
    /// The key's letters without its leading little words ("casa"): what two terms are compared on.
    var letters: [UInt8] = []
    /// Which letters it holds, as bits: two terms whose letters differ a lot can't be alike, whatever the order.
    fileprivate(set) var letterBits: UInt32 = 0
    /// More than one word.
    fileprivate(set) var isPhrase = false
    /// Everything that counts as this question's answer.
    var accepted: Set<String>
    /// Its multiple-choice wrong options.
    var distractors: Set<String>
    /// The prompt's content words.
    var promptWords: Set<String>
    var studied: Bool
    /// Recall now.
    var recall: Double
    /// Where the term can be found: its course and key, and each wrong option's key in the course, as numbers.
    fileprivate(set) var keyTag: UInt64 = 0
    fileprivate(set) var distractorTags: [UInt64] = []
    /// The buckets of alike terms it falls in: inside its topic, by how the term ends and begins.
    fileprivate(set) var buckets: [UInt64] = []

    init(id: UUID, courseID: UUID?, topicID: UUID?, kind: ItemKind, prompt: String, answer: String, accepted: [String] = [],
         distractors: [String] = [], studied: Bool, recall: Double) {
        self.id = id
        self.courseID = courseID
        self.topicID = topicID
        self.term = Self.term(kind: kind, prompt: prompt, answer: answer)
        // A sentence can never equal a term, so only short answers are worth comparing.
        self.accepted = Set((accepted + [answer]).filter { $0.count <= 60 }.map(ConfusionFinder.normalize).filter { !$0.isEmpty })
        self.distractors = Set(distractors.map(ConfusionFinder.normalize).filter { !$0.isEmpty })
        self.promptWords = term == nil ? [] : LookAlikeFinder.contentWords(prompt)
        self.studied = studied
        self.recall = recall
        guard let term else { return }
        key = ConfusionFinder.normalize(term)
        letters = Array(LookAlikeFinder.core(key).utf8)
        for letter in letters {
            if letter == UInt8(ascii: " ") { isPhrase = true }
            letterBits |= 1 << UInt32(letter & 31)
        }
        let course = courseID.map { StableRandom.seed($0, day: 0) } ?? 0
        let topic = topicID.map { StableRandom.seed($0, day: 1) } ?? 0x5bd1_e995
        keyTag = course ^ Self.tag(Array(key.utf8), salt: 1)
        distractorTags = self.distractors.map { course ^ Self.tag(Array($0.utf8), salt: 1) }
        let scope = course ^ topic
        buckets = [scope ^ Self.tag(Array(letters.suffix(4)), salt: 2), scope ^ Self.tag(Array(letters.prefix(3)), salt: 3)]
        // A short word can differ near both ends ("gato", "pato"; "casa", "cosa").
        if letters.count <= 6 { buckets.append(scope ^ Self.tag(Array(letters.suffix(2)) + [UInt8(letters.count)], salt: 4)) }
    }

    private static func tag(_ bytes: [UInt8], salt: UInt64) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325 ^ salt
        for byte in bytes { h = (h ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return StableRandom.mix(h)
    }

    /// A short name for the question, if it has one: never a sentence, a question, a number, two letters or a word that names nothing
    /// ("True", "Increases").
    static func term(kind: ItemKind, prompt: String, answer: String) -> String? {
        func usable(_ text: String) -> String? {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard ConfusionFinder.isTerm(t), t.count > 2, !t.contains(where: \.isNumber), !text.contains("?"),
                  !LookAlikeFinder.genericTerms.contains(ConfusionFinder.normalize(t)) else { return nil }
            return t
        }
        // A card's front names it, when it is short (a vocabulary card's back is only a gloss); anything else, its answer.
        if kind == .flashcard, let front = usable(prompt) { return front }
        return usable(answer)
    }
}

/// Two questions on the same exam that look alike, found before the first mistake.
struct LookAlikePair: Identifiable, Equatable, Sendable, Hashable {
    /// `pair-<hash>`: the same whichever way round the two come.
    var id: String
    var a: UUID
    var b: UUID
    var termA: String
    var termB: String
    var courseID: UUID?
    var topicID: UUID?
    var examID: UUID
    var examTitle: String
    var examDate: Date
    var daysLeft: Int
    /// How alike the two terms are, 0…1.
    var similarity: Double
    /// One question's wrong option is the other's answer.
    var linked: Bool
}

/// Finds look-alikes on the phone, with no AI, for exams in the next 21 days. Three signals:
/// 1. a link: a multiple-choice question's wrong option is the other question's term. Both ways round, that is enough; one way, it needs
///    the same topic and one of the signals below (a question writer's wrong option alone says little);
/// 2. alike terms, in the same topic: an edit distance of at most 0.45 of their length, or the same number of words with only the first
///    different ("classical conditioning", "operant conditioning": two kinds of one thing). Little words at the start don't count, and
///    terms that begin with the same word are compared on the rest ("cell wall", "cell cycle" are not alike; "la casa", "la cosa" are);
/// 3. alike prompts, in the same topic: most of the shorter prompt's content words (at least two) are in the other, and the answers
///    differ.
/// A pair counts with a link, or alike terms and prompts, or terms alike enough on their own (a similarity of 0.6; 0.55 when they share a
/// first or a last word, since only what differs is left to compare). Both questions must
/// be on the same exam, at least one studied and not both already solid; terms with numbers in them, of one or two letters or that name
/// nothing are left out, and so are one question's answer given as the other's, the same word in another form, questions already in an
/// open mix-up and any pair the person has seen before (any mix-up over the two, "Don't bring this up again" included). `NoticeEngineTests` holds
/// this to 90% precision on a labelled corpus (`Fixtures/lookalike-corpus.json`).
///
/// Terms are compared only inside buckets (a topic and how the term ends or begins), so it stays cheap over thousands of questions.
struct LookAlikeFinder: Sendable {
    static let examDays = 21
    /// The largest edit distance for alike terms, as a share of the longer term.
    static let maxDistance = 0.45
    /// Terms this alike count without any other signal.
    static let soloSimilarity = 0.6
    /// The share of the shorter prompt's content words the other must hold.
    static let promptOverlap = 0.7
    /// Recall at which a question is solid.
    static let solidRecall = 0.9
    /// At most this many questions are compared in one bucket.
    static let bucketLimit = 32
    /// At most this many questions with the same term are looked at for one wrong option.
    static let sameTermLimit = 4
    /// At most this many pairs are worked out to the end.
    static let pairLimit = 12

    var calendar: Calendar
    var now: Date

    /// The look-alike pairs on the exams ahead, best first (linked first, then the most alike, then the soonest exam).
    func pairs(items: [LookAlikeItem], exams: [ExamSnapshot], confusions: [ConfusionSnapshot]) -> [LookAlikePair] {
        let upcoming = exams.filter { $0.date > now }
            .map { (exam: $0, days: calendar.dayDistance(from: now, to: $0.date)) }
            .filter { $0.days >= 1 && $0.days <= Self.examDays }
            .sorted { $0.exam.date < $1.exam.date }
        guard !upcoming.isEmpty else { return [] }

        let courses = Set(upcoming.compactMap(\.exam.courseID))
        var openItems = Set<UUID>()
        var knownPairs = Set<ConfusionFinder.Pair>()
        for confusion in confusions {
            if confusion.status == .open { openItems.formUnion(confusion.itemIDs); openItems.formUnion(confusion.fixItemIDs) }
            let ids = confusion.itemIDs
            for i in ids.indices { for j in ids.indices where i < j { knownPairs.insert(.init(ids[i], ids[j])) } }
        }

        var pool: [LookAlikeItem] = []
        pool.reserveCapacity(items.count)
        for item in items where item.term != nil {
            guard let course = item.courseID, courses.contains(course), !openItems.contains(item.id) else { continue }
            pool.append(item)
        }
        // What most comparisons end on, kept apart from the rest of each question so they cost next to nothing.
        var quiet = [Bool](repeating: false, count: pool.count)
        var solid = [Bool](repeating: false, count: pool.count)
        var keyTags = [UInt64](repeating: 0, count: pool.count)
        for index in pool.indices {
            quiet[index] = !pool[index].studied
            solid[index] = pool[index].studied && pool[index].recall >= Self.solidRecall
            keyTags[index] = pool[index].keyTag
        }

        var candidates: [Candidate] = []
        var looked = Set<UInt64>()
        func consider(_ i: Int32, _ j: Int32) {
            let a = Int(i), b = Int(j)
            guard a != b, keyTags[a] != keyTags[b], !(quiet[a] && quiet[b]), !(solid[a] && solid[b]) else { return }
            guard looked.insert(UInt64(UInt32(min(i, j))) << 32 | UInt64(UInt32(max(i, j)))).inserted else { return }
            if let candidate = Self.candidate(pool[a], pool[b], i: i, j: j) { candidates.append(candidate) }
        }

        // Links: a wrong option that is another question's term.
        var byKey: [UInt64: [Int32]] = [:]
        byKey.reserveCapacity(pool.count)
        for index in pool.indices { byKey[keyTags[index], default: []].append(Int32(index)) }
        for index in pool.indices where !pool[index].distractorTags.isEmpty {
            for tag in pool[index].distractorTags {
                for other in (byKey[tag] ?? []).prefix(Self.sameTermLimit) { consider(Int32(index), other) }
            }
        }
        // Alike terms.
        var buckets: [UInt64: [Int32]] = [:]
        buckets.reserveCapacity(pool.count)
        for index in pool.indices {
            for bucket in pool[index].buckets { buckets[bucket, default: []].append(Int32(index)) }
        }
        for bucket in buckets.values where bucket.count > 1 {
            let members = bucket.prefix(Self.bucketLimit)
            for (offset, i) in members.enumerated() {
                for j in members.dropFirst(offset + 1) { consider(i, j) }
            }
        }

        // The best few become pairs, the same two names only once. The deck can use one a day, so the rest aren't worked out.
        candidates.sort { a, b in
            if a.linked != b.linked { return a.linked }
            if a.similarity != b.similarity { return a.similarity > b.similarity }
            return (a.i, a.j) < (b.i, b.j)
        }
        var found: [LookAlikePair] = []
        var names = Set<UInt64>()
        var refused: Set<UInt64>?
        for candidate in candidates where found.count < Self.pairLimit {
            let x = pool[Int(candidate.i)], y = pool[Int(candidate.j)]
            if refused == nil { refused = Self.refusedNames(items: items, knownPairs: knownPairs) }
            let name = x.keyTag ^ y.keyTag
            guard !(refused?.contains(name) ?? false), !names.contains(name) else { continue }
            guard let pair = pair(x, y, candidate, upcoming: upcoming, knownPairs: knownPairs) else { continue }
            names.insert(name)
            found.append(pair)
        }
        return found.sorted { a, b in
            if a.linked != b.linked { return a.linked }
            if a.similarity != b.similarity { return a.similarity > b.similarity }
            if a.daysLeft != b.daysLeft { return a.daysLeft < b.daysLeft }
            return a.id < b.id
        }
    }

    /// Two questions that passed the signals, before the checks that cost more.
    private struct Candidate {
        var i: Int32
        var j: Int32
        var similarity: Double
        var linked: Bool
        var sameTopic: Bool
    }

    /// The signals. Nil when they aren't enough.
    private static func candidate(_ x: LookAlikeItem, _ y: LookAlikeItem, i: Int32, j: Int32) -> Candidate? {
        let sameTopic = x.topicID == y.topicID
        let xNamesY = x.distractorTags.contains(y.keyTag), yNamesX = y.distractorTags.contains(x.keyTag)
        let bothWays = xNamesY && yNamesX
        guard bothWays || sameTopic else { return nil }
        let compared = comparison(x, y, exact: bothWays)
        let similarity = compared.similarity
        if bothWays { return Candidate(i: i, j: j, similarity: similarity, linked: true, sameTopic: sameTopic) }
        let twoKinds = x.isPhrase && y.isPhrase && onlyFirstWordDiffers(x.key, y.key)
        let termsAlike = twoKinds || similarity >= 1 - maxDistance
        let oneWay = xNamesY || yNamesX
        guard termsAlike || oneWay else { return nil }
        // Terms that share a first or a last word are compared on what differs, which is less to go on: they need less.
        let enough = compared.sharedFirstWord || twoKinds ? 1 - maxDistance : soloSimilarity
        if termsAlike, similarity >= enough { return Candidate(i: i, j: j, similarity: similarity, linked: oneWay, sameTopic: true) }
        guard promptsAlike(x.promptWords, y.promptWords) else { return nil }
        return Candidate(i: i, j: j, similarity: similarity, linked: oneWay, sameTopic: true)
    }

    /// The pair, unless it is the same thing twice, already known or not on one exam.
    private func pair(_ x: LookAlikeItem, _ y: LookAlikeItem, _ candidate: Candidate, upcoming: [(exam: ExamSnapshot, days: Int)],
                      knownPairs: Set<ConfusionFinder.Pair>) -> LookAlikePair? {
        guard !x.accepted.contains(y.key), !y.accepted.contains(x.key), !Self.sameWord(Self.core(x.key), Self.core(y.key)) else { return nil }
        guard !knownPairs.contains(.init(x.id, y.id)) else { return nil }
        guard let on = upcoming.first(where: { $0.exam.covers(topic: x.topicID, course: x.courseID) && $0.exam.covers(topic: y.topicID, course: y.courseID) }) else {
            return nil
        }
        let (first, second) = (x.term ?? "").localizedCaseInsensitiveCompare(y.term ?? "") == .orderedDescending ? (y, x) : (x, y)
        return LookAlikePair(id: ConfusionFinder.stableID("pair", [x.id, y.id]), a: first.id, b: second.id, termA: first.term ?? "",
                             termB: second.term ?? "", courseID: x.courseID, topicID: candidate.sameTopic ? x.topicID : nil, examID: on.exam.id,
                             examTitle: on.exam.title, examDate: on.exam.date, daysLeft: on.days, similarity: candidate.similarity,
                             linked: candidate.linked)
    }

    /// The same two names are one pair, however many questions carry them, and "Don't bring this up again" on two questions covers them all.
    private static func refusedNames(items: [LookAlikeItem], knownPairs: Set<ConfusionFinder.Pair>) -> Set<UInt64> {
        guard !knownPairs.isEmpty else { return [] }
        var tags: [UUID: UInt64] = [:]
        for item in items where item.term != nil { tags[item.id] = item.keyTag }
        return Set(knownPairs.compactMap { pair in tags[pair.a].flatMap { a in tags[pair.b].map { a ^ $0 } } })
    }

    // MARK: Words

    /// Answers that are no one's name: two of these aren't two ideas that look alike.
    static let genericTerms: Set<String> = [
        "true", "false", "yes", "no", "none", "all", "both", "neither", "either", "all of the above", "none of the above", "both a and b",
        "increase", "increases", "increased", "decrease", "decreases", "decreased", "more", "less", "higher", "lower", "greater", "smaller",
        "larger", "above", "below", "before", "after", "left", "right", "up", "down", "positive", "negative", "always", "never", "sometimes",
    ]

    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "can", "de", "del", "do", "does", "el", "for", "from", "how", "in", "is", "it",
        "its", "la", "las", "le", "les", "los", "of", "on", "or", "that", "the", "their", "these", "this", "to", "un", "una", "was",
        "what", "when", "where", "which", "who", "why", "with",
    ]

    /// A prompt's words that say something: no question words or little words.
    static func contentWords(_ text: String) -> Set<String> {
        Set(ConfusionFinder.normalize(text).split(separator: " ").map(String.init).filter { !stopWords.contains($0) })
    }

    /// A key without its leading little words ("la casa" is "casa", "the krebs cycle" is "krebs cycle"), unless that leaves nothing.
    static func core(_ key: String) -> String {
        var words = key.split(separator: " ")[...]
        while words.count > 1, let first = words.first, stopWords.contains(String(first)) { words = words.dropFirst() }
        return words.joined(separator: " ")
    }

    /// How alike two terms are, 0…1: one minus their edit distance over the longer one's length. A first word they share says nothing
    /// ("cell wall", "cell cycle"), so only the rest is compared. Terms too far apart to be alike come back as 0 without being worked out,
    /// unless `exact` (a link's pair is ranked by it).
    private static func comparison(_ x: LookAlikeItem, _ y: LookAlikeItem, exact: Bool) -> (similarity: Double, sharedFirstWord: Bool) {
        if !exact, !x.isPhrase, !y.isPhrase {
            let longer = max(x.letters.count, y.letters.count)
            let limit = Int(maxDistance * Double(longer))
            if abs(x.letters.count - y.letters.count) > limit { return (0, false) }
            // An edit changes which letters a word holds by two at most.
            if (x.letterBits ^ y.letterBits).nonzeroBitCount > 2 * limit { return (0, false) }
            guard let distance = editDistance(x.letters, y.letters, limit: limit) else { return (0, false) }
            return (1 - Double(distance) / Double(max(1, longer)), false)
        }
        var a = x.letters[...], b = y.letters[...]
        let space = UInt8(ascii: " ")
        var shared = false
        if x.isPhrase, y.isPhrase, let endA = a.firstIndex(of: space), let endB = b.firstIndex(of: space), a[..<endA] == b[..<endB] {
            a = a[(endA + 1)...]
            b = b[(endB + 1)...]
            shared = true
        }
        guard !a.isEmpty, !b.isEmpty else { return (0, shared) }
        let longer = max(a.count, b.count)
        return (1 - Double(editDistance(Array(a), Array(b), limit: longer) ?? longer) / Double(longer), shared)
    }

    private static func promptsAlike(_ a: Set<String>, _ b: Set<String>) -> Bool {
        let smaller = min(a.count, b.count)
        guard smaller >= 2 else { return false }
        return Double(a.intersection(b).count) / Double(smaller) >= promptOverlap
    }

    /// The same number of words with only the first different, and the words they share being content words of four letters or more
    /// (little words such as "of" aside): two kinds of one thing.
    private static func onlyFirstWordDiffers(_ a: String, _ b: String) -> Bool {
        let x = core(a).split(separator: " "), y = core(b).split(separator: " ")
        guard x.count == y.count, x.count >= 2, x[0] != y[0], x.dropFirst().elementsEqual(y.dropFirst()) else { return false }
        var shared = 0
        for word in x.dropFirst() where !stopWords.contains(String(word)) {
            guard word.count >= 4 else { return false }
            shared += 1
        }
        return shared >= 1
    }

    /// Endings that make the same word in another form or spelling ("chromosomes", "mitochondria", "fibre"); "chromatid" and "chromatin"
    /// are two words.
    private static let sameWordEndings: [(String, String)] = [
        ("", "s"), ("", "es"), ("", "ed"), ("", "ing"), ("y", "ies"), ("on", "a"), ("um", "a"), ("us", "i"), ("is", "es"),
        ("ur", "r"), ("re", "er"), ("se", "ze"),
    ]

    static func sameWord(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        var common = 0
        while common < x.count, common < y.count, x[common] == y[common] { common += 1 }
        guard common >= 3 else { return false }
        let restX = String(x[common...]), restY = String(y[common...])
        return sameWordEndings.contains { ($0.0 == restX && $0.1 == restY) || ($0.0 == restY && $0.1 == restX) }
    }

    /// Levenshtein over bytes; nil once it is sure to be over `limit`.
    static func editDistance(_ a: [UInt8], _ b: [UInt8], limit: Int) -> Int? {
        if a.isEmpty { return b.count <= limit ? b.count : nil }
        if b.isEmpty { return a.count <= limit ? a.count : nil }
        return a.withUnsafeBufferPointer { x in
            b.withUnsafeBufferPointer { y in
                var row = [Int](repeating: 0, count: y.count + 1)
                return row.withUnsafeMutableBufferPointer { r -> Int? in
                    for j in 0...y.count { r[j] = j }
                    for i in 0..<x.count {
                        var diagonal = r[0]
                        r[0] = i + 1
                        var best = r[0]
                        for j in 0..<y.count {
                            let above = r[j + 1]
                            let cost = x[i] == y[j] ? 0 : 1
                            let cell = Swift.min(Swift.min(above + 1, r[j] + 1), diagonal + cost)
                            r[j + 1] = cell
                            if cell < best { best = cell }
                            diagonal = above
                        }
                        if best > limit { return nil }
                    }
                    return r[y.count] <= limit ? r[y.count] : nil
                }
            }
        }
    }
}
