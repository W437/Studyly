import Accelerate
import Foundation
import NaturalLanguage

// The offline tutor's search: which sentence of the person's material answers a question, and is it convincing.
//
// Before, the tutor took the four passages the keyword search (`LocalRetriever.search`) liked best and chose a sentence among the
// first three. On the user test (seven students, 78 questions, each written with the exact line of the notes that answers it) that
// showed the right line for 5 of them: the questions were put in other words than the notes' ("expecting" for "pregnant",
// "navigation systems" for "routing systems"), and the keyword search had the right passage among its first twenty for only 6 in 10.
// Here a sentence is the unit, and the search has two stages, cheapest first:
//
//   1. Every sentence of the library is scored on its words (BM25 over sentences, the question's chat shorthand left out, the
//      rarest words counting most) and on the average meaning of its words (`OfflineWordVectors`). The best few dozen go on.
//   2. Those are read by the contextual model (`OfflineEncoder`): each word of the question looks for the word of the sentence nearest
//      to it in meaning, and the sentence's whole vector is compared with the question's. What it read is kept, so the second
//      question about the same notes costs almost nothing.
//
// Each signal is a z-score among the sentences it was computed for, and they are added with the weights in `Weights`. When the system
// has no contextual model (or none for the notes' language) stage 2 is skipped and the words decide; the verdict is then judged on the
// words alone as well (`OfflineRanking.usedMeaning`).
//
// Sentences are taken from the page as it is read, not from the passages' text: a section lists its prose first and its bullets last,
// and a bullet has no full stop, so in the passage a list is cut off from its lead-in and its items run into each other. The search
// puts the units of a page back in the order of the page (`LocalRetriever.Passage.pieces`), so "There are different types of blood
// thinners:" is followed by the types, and a sentence is shown with the lines really before and after it.
//
// The last thing the search does is say whether the best sentence is *convincing* (`Gate`): a quote that is not about the question is
// worse than "I couldn't find that", so a sentence that neither the question's words nor their meaning support is not offered.

struct OfflineRanking: Sendable {

    /// A sentence of the material, where it is, and how it is shown.
    struct Candidate: Sendable {
        /// The passage the sentence is credited to.
        var passage: LocalRetriever.Passage
        var sentence: String
        var score: Double
        /// What is shown: the sentence, with the line before it when it opens by pointing back ("This one will be on the midterm …"), the
        /// line after it when that one does ("This is the division of …"), or the items of the list, up to three, when it introduces one.
        /// Each line is credited to the passage it is in.
        var lines: [LocalTutor.Quote] = []
        /// The line right after the sentence in the notes, shown or not (a hint is built on it).
        var after: LocalTutor.Quote?
    }

    /// What the gate looked at, kept for tests and for tuning.
    struct Evidence: Sendable {
        /// The share of the question's words (by how rare they are) the best sentence uses; 1 when it uses all.
        var sentenceCoverage: Double = 0
        /// The same for the whole passage the sentence is in.
        var passageCoverage: Double = 0
        /// How many of the question's own words (not the earlier question's) the best sentence, or its passage, contains.
        var sharedTerms = 0
        /// How far above the other sentences read in stage 2 the best one is in meaning (standard deviations); nil without stage 2.
        var meaning: Double?
        /// The best sentence's word-by-word cosine with the question in the contextual model, nil without stage 2.
        var similarity: Double?
        /// The best sentence's lead over the next one, in the units of the final score.
        var margin: Double = 0
        /// The best sentence's z-score on its words (stage 1).
        var words: Double = 0
        /// The final score of the best sentence.
        var score: Double = 0
        /// Words of the question that are in none of the notes and that the language's word vectors do not know either: a name or a
        /// term the notes cannot be answering ("stirling", "querfront").
        var unfamiliar: [String] = []
    }

    /// How one of the sentences that reached stage 2 scored on each signal (for tests and for tuning the weights).
    struct Detail: Sendable {
        var candidate: Candidate
        /// Stage 1: z-scores of the words and of the average word vector (0 when that signal was not used).
        var lexical: Double
        var wordVectors: Double
        /// Stage 2: the word-by-word match and the whole-sentence match, raw and as z-scores among the candidates read.
        var wordMatchRaw: Double?
        var wordMatch: Double?
        var sentenceMatchRaw: Double?
        var sentenceMatch: Double?
    }

    enum Verdict: Equatable, Sendable {
        case convincing
        /// Why not, in a few words (for tests and logs; never shown).
        case weak(String)
    }

    /// Best first. Sentences that talk to an assistant, questions and fragments are not among them.
    var candidates: [Candidate] = []
    /// The best sentence of another place in the notes, when it is nearly as good as the first (the search cannot tell them apart, so it
    /// shows both rather than guess).
    var alsoClose: Candidate?
    var verdict: Verdict = .weak("no candidates")
    var evidence = Evidence()
    /// Every sentence that went on to stage 2, with its scores, in the order of the final score.
    var pool: [Detail] = []
    /// The contextual model took part in the ranking.
    var usedMeaning = false
    /// The static word vectors took part in the first stage.
    var usedWordVectors = false
    /// The question was read as a follow-up and the earlier question was searched with it.
    var usedHistory = false
    var seconds: Double = 0
    /// Where the time went: the first stage (all the sentences), the contextual model reading the candidates, and the rest.
    var stageSeconds: (first: Double, reading: Double) = (0, 0)

    var isConvincing: Bool { verdict == .convincing && !candidates.isEmpty }
}

/// Words of a question that say what kind of question it is, or are chat shorthand, not what it is about. Used where a word's own
/// text matters (the words of the contextual model); the keyword side has its own lists (`LocalRetriever.questionWords`).
enum OfflineWords {

    /// The word is a small word of a question, or says what kind of question it is ("what", "happens", "difference"): the keyword search
    /// leaves such words out (`LocalRetriever.queryTerms`), and so do the two meaning signals, or "what happens in anaphase?" would find
    /// the sentence "Today: what actually happens when the cell divides." (General words that are not about the kind of question, such as
    /// "type" or "first", stay: "two kinds of blood thinner" is the link to "different types of blood thinners".)
    static func isGeneral(_ word: String) -> Bool {
        questionWords.contains(word) || LocalRetriever.questionWords.contains(Lexicon.stem(word))
    }

    static let questionWords: Set<String> = [
        "what", "whats", "which", "who", "whom", "whose", "when", "where", "why", "how", "does", "do", "did", "is", "are", "was", "were",
        "can", "could", "would", "should", "will", "may", "might", "i", "me", "my", "we", "our", "you", "your", "it", "its", "they", "them",
        "their", "he", "she", "his", "her", "him", "the", "a", "an", "of", "to", "in", "on", "at", "by", "for", "with", "from", "as", "and",
        "or", "but", "if", "then", "so", "that", "this", "these", "those", "there", "here", "be", "been", "being", "am", "have", "has", "had",
        "about", "into", "than", "also", "just", "ever", "really", "tell", "say", "said", "mean", "means", "meant", "please", "im", "ive",
        "youre", "youve", "thats", "theres", "heres", "hows", "whos", "wheres", "hes", "shes", "gonna", "wanna", "gotta", "dont", "doesnt",
        "cant", "wont", "isnt", "arent", "ya", "yall", "cuz",
    ]
}

// MARK: - The search

extension LocalRetriever {

    /// The sentences that answer `question`, best first, and whether the best is convincing. `earlier` are the person's questions
    /// before this one in the chat: a follow-up ("and how is that different from a pen?") is searched together with the last of them.
    /// Slow the first time (the contextual model loads, about a second) and fast after; call it off the main thread.
    func rankSentences(for question: String, earlier: [String] = [], options: OfflineSearch.Options = .init()) -> OfflineRanking {
        OfflineSearch.index(for: self).rank(question: question, earlier: earlier, retriever: self, options: options)
    }
}

/// The sentences of one library, indexed for the search. Built from a retriever's passages and kept for the next question (the
/// retriever itself is made again for every question, and the index of an unchanged library is the same).
final class OfflineSearch: @unchecked Sendable {

    struct Options: Sendable {
        /// Off: the words alone decide (what a device without the contextual model does).
        var useContextualModel = true
        /// Off: stage 1 uses the words alone.
        var useWordVectors = true
        /// How many sentences go on to stage 2.
        var secondStage = 24
        /// The most time stage 2 may spend reading sentences it has not read before, in seconds. The sentences it reaches are the
        /// ones stage 1 liked best, so a slow device (or a cold start) loses the least likely ones. At least eight are always read.
        var readingBudget = 1.2
    }

    // MARK: Weights and the gate
    //
    // `var` so that the tuning bench (the lab of `ut2`) can sweep them in one run; nothing in the app changes them.

    /// How the signals add up.
    enum Weights {
        /// Stage 1, to pick the sentences that go on.
        nonisolated(unsafe) static var lexical = 1.0
        nonisolated(unsafe) static var wordVectors = 1.0
        /// Stage 2: the average word vectors again (as a z-score among all the sentences), the contextual model's word-by-word match,
        /// and its whole-sentence match.
        nonisolated(unsafe) static var secondStageWordVectors = 0.5
        nonisolated(unsafe) static var wordMatch = 1.0
        nonisolated(unsafe) static var sentenceMatch = 0.5
        /// Taken off a sentence of fewer than five words ("Pump."): short lines match everything and answer nothing.
        nonisolated(unsafe) static var shortSentence = 1.5
        /// Taken off a sentence that holds a link: a reference list, or a page's footer ("https://en.wikipedia.org/wiki/… 3/9") that a
        /// printout runs into the last sentence of the page.
        nonisolated(unsafe) static var link = 1.5
        /// A question that leans on the one before it counts the earlier question's words for this much.
        nonisolated(unsafe) static var history = 0.5
        /// Two places are "nearly as good" when the second's score is within this of the first's.
        nonisolated(unsafe) static var tie = 0.5
        /// Added to every sentence of a passage that is headed by words of the question ("Anaphase: …" for "what happens in anaphase?").
        nonisolated(unsafe) static var heading = 1.5
        /// How many of the items after a sentence that introduces a list are scored with it.
        nonisolated(unsafe) static var leadInItems = 2
    }

    /// When the best sentence is convincing. Both stages measure how well the sentence stands out *among the others of this library*, so
    /// a z-score is the unit there; the share of the question's words it contains is the check that does not depend on either model.
    enum Gate {
        /// With the contextual model: the least cosine the question's words must reach with the best sentence's words (the mean over the
        /// question's pieces of the nearest piece of the sentence, after both are centred on the candidates read). Set on the user test
        /// (seven students, 78 questions with the line that answers each, 13 without): 0.48 is the lowest value at which no more than 2
        /// of the 13 questions the notes do not cover are answered from them. At 0.46 it is 4 of the 13, and 4 more of the 78 are answered
        /// right; at 0.50 it is 2, and 2 fewer are. How well a sentence matches does not say whether it is the answer (the right ones and
        /// the wrong ones overlap), so this is a floor against the unrelated, not a test of the right.
        nonisolated(unsafe) static var similarity = 0.48
        /// Or the share of the question's words (by rarity) the best sentence, or its passage, contains: a sentence that has half of
        /// the question's words is about it, whatever the model thinks (a small library, a question with an odd word in it).
        nonisolated(unsafe) static var coverage = 0.5
        /// And, whatever the model says, the least number of the question's words the sentence or its passage must contain: a sentence
        /// that shares not one of them is not an answer. A count and not a share: in notes about insulin, "insulin" is in every
        /// sentence and weighs next to nothing.
        nonisolated(unsafe) static var anchor = 1
        /// Without the contextual model: the share of the question's words (by rarity) the best sentence, or its passage, must contain.
        nonisolated(unsafe) static var wordsOnlyCoverage = 0.3
        nonisolated(unsafe) static var wordsOnlyPassageCoverage = 0.4
        /// A question in Japanese or Chinese: the share of its words (by rarity) the best sentence, or its passage, must contain. The contextual
        /// model's similarities run high for these languages (0.8 to 0.99 for sentences that are not about the question, against 0.48 as the
        /// floor in the other languages), so they decide nothing there; the words do.
        nonisolated(unsafe) static var cjkCoverage = 0.5
    }

    // MARK: The index

    struct Entry {
        /// The passage the sentence is credited to.
        var passage: Int
        /// The sentence as it shows.
        var text: String
        /// What is scored: the sentence, and the first items after it when it introduces a list.
        var scoreText: String
        var stems: [String]
        var words: Int
        /// A question, or too few words to say anything: never an answer.
        var excluded: Bool
        var short: Bool
        var link: Bool
        /// The sentences before and after it, in reading order: the entries of `sequences[sequence]`, at `slot`.
        var sequence: Int
        var slot: Int
    }

    private final class Sentences { let value: [String]; init(_ value: [String]) { self.value = value } }
    private final class Stems { let value: [String]; init(_ value: [String]) { self.value = value } }
    private final class VectorBox { let value: [Float]?; init(_ value: [Float]?) { self.value = value } }

    private static let sentenceCache: NSCache<NSString, Sentences> = {
        let cache = NSCache<NSString, Sentences>()
        cache.countLimit = 40_000
        return cache
    }()

    private static let stemCache: NSCache<NSString, Stems> = {
        let cache = NSCache<NSString, Stems>()
        cache.countLimit = 60_000
        return cache
    }()

    private static let sentenceVectors: NSCache<NSString, VectorBox> = {
        let cache = NSCache<NSString, VectorBox>()
        cache.countLimit = 60_000
        return cache
    }()

    private static let lock = NSLock()
    private static var recent: [(fingerprint: Int, index: OfflineSearch)] = []

    /// The index for the retriever's passages: the last one made when the library has not changed.
    static func index(for retriever: LocalRetriever) -> OfflineSearch {
        var hasher = Hasher()
        hasher.combine(retriever.passages.count)
        for passage in retriever.passages {
            hasher.combine(passage.key)
            hasher.combine(passage.text)
        }
        let fingerprint = hasher.finalize()
        lock.lock()
        if let known = recent.first(where: { $0.fingerprint == fingerprint }) {
            lock.unlock()
            return known.index
        }
        lock.unlock()
        let made = OfflineSearch(passages: retriever.passages)
        lock.lock()
        recent.insert((fingerprint, made), at: 0)
        if recent.count > 3 { recent.removeLast() }
        lock.unlock()
        return made
    }

    /// Forget the indexes and what was read, for tests.
    static func reset() {
        lock.lock(); recent.removeAll(); lock.unlock()
        sentenceCache.removeAllObjects()
        stemCache.removeAllObjects()
        sentenceVectors.removeAllObjects()
    }

    let entries: [Entry]
    /// Entries in reading order: one list for each page of each source, and one for each passage that is not a page's (a lecture
    /// window, a card, a group of parallel headings).
    let sequences: [[Int]]
    private let postings: [String: [(entry: Int32, count: UInt16)]]
    private let documentFrequency: [String: Int]
    private let averageLength: Double
    /// The words each passage is headed by ("Anaphase: …", or a short first sentence before the rest); empty for a lecture, a card or a
    /// passage with no heading.
    private let headings: [Set<String>]
    /// The language of the notes ("en", "de"), as the system recognises it.
    let language: String
    /// The unit vectors of the sentences' average word, centred on the library's mean; nil without word vectors for the language.
    private let wordMatrix: [Float]?
    private let wordMean: [Float]?
    private let wordDimension: Int

    private static func sentences(of text: String) -> [String] {
        let key = text as NSString
        if let known = sentenceCache.object(forKey: key) { return known.value }
        let made = Lexicon.sentences(text)
        sentenceCache.setObject(Sentences(made), forKey: key)
        return made
    }

    private static func stems(of text: String) -> [String] {
        let key = text as NSString
        if let known = stemCache.object(forKey: key) { return known.value }
        let made = Lexicon.contentStems(text)
        stemCache.setObject(Stems(made), forKey: key)
        return made
    }

    private init(passages: [LocalRetriever.Passage]) {
        // 1. The units, by page: what each page passage was joined from, once (the same line can be in a section's passage and in a
        //    definition's), in the order of the page. Passages not made of lines have their sentences, in their own order.
        struct Unit { var passage: Int; var text: String; var position: Int; var arrival: Int }
        var pageUnits: [String: [Unit]] = [:]
        var pageOrder: [String] = []
        var seen: Set<String> = []
        var orphans: [(passage: Int, units: [String])] = []
        var arrival = 0
        for (p, passage) in passages.enumerated() {
            if let page = passage.pageIndex, !passage.pieces.isEmpty {
                let pageKey = "\(passage.sourceID.uuidString)#\(page)"
                if pageUnits[pageKey] == nil { pageOrder.append(pageKey) }
                var last = 0
                for piece in passage.pieces {
                    let position = piece.position >= 0 ? piece.position : last
                    last = position
                    for sentence in Self.sentences(of: piece.text) {
                        guard seen.insert("\(pageKey)|\(position)|\(sentence)").inserted else { continue }
                        pageUnits[pageKey, default: []].append(Unit(passage: p, text: sentence, position: position, arrival: arrival))
                        arrival += 1
                    }
                }
            } else {
                orphans.append((p, passage.isCard ? [passage.text] : Self.sentences(of: passage.text)))
            }
        }

        // 2. The entries and their reading order.
        var entries: [Entry] = []
        var sequences: [[Int]] = []
        func append(passage: Int, text: String, sequence: Int) {
            let words = text.split(whereSeparator: \.isWhitespace).count + Lexicon.cjkWords(in: text)
            entries.append(Entry(passage: passage, text: text, scoreText: text, stems: [], words: words,
                                 excluded: Self.asksSomething(text) || words < 4, short: words < 5,
                                 link: text.contains("://") || text.contains("www."), sequence: sequence, slot: sequences[sequence].count))
            sequences[sequence].append(entries.count - 1)
        }
        for pageKey in pageOrder {
            let units = (pageUnits[pageKey] ?? []).sorted { $0.position == $1.position ? $0.arrival < $1.arrival : $0.position < $1.position }
            sequences.append([])
            for unit in units { append(passage: unit.passage, text: unit.text, sequence: sequences.count - 1) }
        }
        for orphan in orphans {
            sequences.append([])
            for text in orphan.units { append(passage: orphan.passage, text: text, sequence: sequences.count - 1) }
        }

        // 3. What is scored: a sentence that introduces a list (ends in a colon) is scored together with the first items after it, since
        //    the items are what it announces ("There are different types of blood thinners:" / "Anticoagulants, such as heparin …").
        var postings: [String: [(entry: Int32, count: UInt16)]] = [:]
        var df: [String: Int] = [:]
        var total = 0
        for i in entries.indices {
            let e = entries[i]
            var scoreText = e.text
            if e.text.hasSuffix(":"), Weights.leadInItems > 0 {
                var added = 0
                var j = e.slot + 1
                while j < sequences[e.sequence].count, added < Weights.leadInItems {
                    let next = entries[sequences[e.sequence][j]]
                    if Self.asksSomething(next.text) { break }
                    if next.words >= 3 { scoreText += " " + next.text; added += 1 }
                    j += 1
                }
            }
            entries[i].scoreText = scoreText
            let stems = Self.stems(of: scoreText)
            entries[i].stems = stems
            var counts: [String: Int] = [:]
            for stem in stems { counts[stem, default: 0] += 1 }
            for (stem, count) in counts {
                postings[stem, default: []].append((Int32(i), UInt16(min(count, 60_000))))
                df[stem, default: 0] += 1
            }
            total += stems.count
        }
        self.entries = entries
        self.sequences = sequences
        self.postings = postings
        self.documentFrequency = df
        self.averageLength = entries.isEmpty ? 1 : max(1, Double(total) / Double(entries.count))

        // The words each passage is headed by.
        self.headings = passages.map { passage in
            guard passage.pageIndex != nil, !passage.isCard else { return [] }
            let text = passage.text
            if let colon = text.firstIndex(of: ":"), text[..<colon].split(separator: " ").count <= 3 {
                return Set(Lexicon.contentStems(String(text[..<colon])))
            }
            if let first = passage.pieces.first, passage.pieces.count > 1, first.text.split(separator: " ").count <= 8 {
                return Set(Lexicon.contentStems(first.text))
            }
            return []
        }

        // The notes' language: from a spread of the passages, not only the first.
        let step = max(1, passages.count / 24)
        let sample = stride(from: 0, to: passages.count, by: step).map { passages[$0].text }.joined(separator: " ")
        self.language = LocalGenerator.confidentLanguage(String(sample.prefix(6000))) ?? "en"

        // Stage 1's meaning: the average of the words' vectors, for every sentence.
        var matrix: [Float]?
        var mean: [Float]?
        var dimension = 0
        if let vectors = OfflineWordVectors.shared(language), !entries.isEmpty {
            dimension = vectors.dimension
            var raw = [Float](repeating: 0, count: entries.count * dimension)
            var present = 0
            for (i, entry) in entries.enumerated() {
                guard let v = Self.averageVector(of: entry.scoreText, vectors: vectors) else { continue }
                raw.replaceSubrange((i * dimension)..<((i + 1) * dimension), with: v)
                present += 1
            }
            if present > 0 {
                let m = OfflineMath.meanRow(of: [(raw, entries.count)], dimension: dimension)
                matrix = OfflineMath.centeredUnitRows(raw, rows: entries.count, dimension: dimension, mean: m)
                mean = m
            }
        }
        self.wordMatrix = matrix
        self.wordMean = mean
        self.wordDimension = dimension
    }

    /// The average of the unit vectors of the text's content words (the question words and chat shorthand left out), nil when the
    /// model knows none of them. Kept by text across indexes.
    private static func averageVector(of text: String, vectors: OfflineWordVectors) -> [Float]? {
        let key = text as NSString
        if let known = sentenceVectors.object(forKey: key) { return known.value }
        var sum = [Float](repeating: 0, count: vectors.dimension)
        var count = 0
        sum.withUnsafeMutableBufferPointer { acc in
            for token in Lexicon.tokens(text) where token.isContent && !token.isNumber && !OfflineWords.isGeneral(token.word) {
                guard let v = vectors.vector(for: token.word) else { continue }
                vDSP_vadd(acc.baseAddress!, 1, v, 1, acc.baseAddress!, 1, vDSP_Length(v.count))
                count += 1
            }
        }
        let result: [Float]? = count > 0 ? sum.map { $0 / Float(count) } : nil
        sentenceVectors.setObject(VectorBox(result), forKey: key)
        return result
    }

    // MARK: Words

    private func idf(_ stem: String) -> Double {
        let n = Double(entries.count)
        let df = Double(documentFrequency[stem] ?? 0)
        return log(1 + (n - df + 0.5) / (df + 0.5))
    }

    /// BM25 over the sentences for weighted terms.
    private func lexicalScores(_ terms: [(stem: String, weight: Double)]) -> [Double] {
        var scores = [Double](repeating: 0, count: entries.count)
        let k1 = 1.2, b = 0.75
        for (stem, weight) in terms {
            guard let list = postings[stem] else { continue }
            let idf = idf(stem) * weight
            for (id, count) in list {
                let tf = Double(count)
                let length = Double(max(1, entries[Int(id)].stems.count))
                scores[Int(id)] += idf * tf * (k1 + 1) / (tf + k1 * (1 - b + b * length / averageLength))
            }
        }
        return scores
    }

    /// The share of the terms' weight (their rarity) found in `stems`. A word the notes never use weighs as much as the middle one of
    /// the question's words that they do use: that it is missing counts against the sentence, but a question with one odd word in it
    /// ("… in plants?") is not refused for it alone. (A word no language knows is judged apart: `unfamiliarWords`.)
    private func coverage(of terms: [(stem: String, weight: Double)], in stems: Set<String>) -> Double {
        let seenWeights = terms.compactMap { documentFrequency[$0.stem] != nil ? idf($0.stem) * $0.weight : nil }.sorted()
        let unseen = seenWeights.isEmpty ? idf("") : seenWeights[seenWeights.count / 2]
        var total = 0.0, found = 0.0
        for (stem, weight) in terms {
            let w = documentFrequency[stem] == nil ? unseen : idf(stem) * weight
            total += w
            if stems.contains(stem) { found += w }
        }
        return total > 0 ? found / total : 0
    }

    // MARK: Ranking

    func rank(question: String, earlier: [String], retriever: LocalRetriever, options: Options) -> OfflineRanking {
        let started = Date()
        var ranking = OfflineRanking()
        guard !entries.isEmpty else { return ranking }

        // The question, and the one before it when this one leans on it.
        let history = earlier.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let followUp = history != nil && LocalTutor.isFollowUp(question)
        ranking.usedHistory = followUp
        var terms: [(stem: String, weight: Double)] = retriever.offlineTerms(question).map { ($0, 1.0) }
        if followUp, let history {
            let own = Set(terms.map(\.stem))
            terms += retriever.offlineTerms(history).filter { !own.contains($0) }.map { ($0, Weights.history) }
        }

        // Stage 1: the words, and the average meaning of the words.
        let lexical = lexicalScores(terms)
        let lexicalZ = OfflineMath.zScores(lexical)
        var stage1 = lexicalZ.map { $0 * Weights.lexical }
        var wordZ: [Double] = []
        if options.useWordVectors, let matrix = wordMatrix, let mean = wordMean,
           let vectors = OfflineWordVectors.shared(language) {
            var query = Self.averageVector(of: question, vectors: vectors)
            if followUp, let history, let past = Self.averageVector(of: history, vectors: vectors) {
                if let q = query {
                    query = zip(q, past).map { $0 + Float(Weights.history) * $1 }
                } else {
                    query = past
                }
            }
            if let q = query {
                let centred = OfflineMath.centeredUnitRows(q, rows: 1, dimension: wordDimension, mean: mean)
                var product = [Float](repeating: 0, count: entries.count)
                vDSP_mmul(matrix, 1, centred, 1, &product, 1, vDSP_Length(entries.count), 1, vDSP_Length(wordDimension))
                wordZ = OfflineMath.zScores(product.map(Double.init))
                for i in stage1.indices { stage1[i] += wordZ[i] * Weights.wordVectors }
                ranking.usedWordVectors = true
            }
        }
        let asked = Set(terms.map(\.stem))
        func headed(_ entry: Int) -> Bool {
            let h = headings[entries[entry].passage]
            return !h.isEmpty && h.isSubset(of: asked)
        }
        for i in stage1.indices {
            if entries[i].excluded { stage1[i] = -.infinity; continue }
            if entries[i].short { stage1[i] -= Weights.shortSentence }
            if entries[i].link { stage1[i] -= Weights.link }
            if headed(i) { stage1[i] += Weights.heading }
        }
        // With no word vectors a sentence needs one of the question's words to be a candidate at all.
        let order = stage1.indices.filter { stage1[$0] > -.infinity && (ranking.usedWordVectors || lexical[$0] > 0) }
            .sorted { stage1[$0] == stage1[$1] ? $0 < $1 : stage1[$0] > stage1[$1] }
        // Candidates that talk to an assistant are never offered.
        var pool: [Int] = []
        for i in order {
            let entry = entries[i]
            if TutorPolicy.looksLikeInstruction(entry.text, context: retriever.passages[entry.passage].text) { continue }
            pool.append(i)
            if pool.count >= max(options.secondStage, 8) { break }
        }
        guard !pool.isEmpty else { ranking.seconds = Date().timeIntervalSince(started); return ranking }

        ranking.stageSeconds.first = Date().timeIntervalSince(started)
        // Stage 2: the contextual model reads the candidates.
        var final: [(entry: Int, score: Double)] = pool.map { ($0, stage1[$0]) }
        var meaningZ: [Int: Double] = [:]
        var similarity: [Int: Double] = [:]
        var detail: [Int: (ms: Scored, pooled: Scored)] = [:]
        if options.useContextualModel, let encoder = OfflineEncoder.shared(language), encoder.warmUp(),
           let q = encoder.encode(question, language: language, pieces: true),
           let scored = readCandidates(pool, encoder: encoder, question: q, history: followUp ? history : nil,
                                       frequent: frequentWords(), budget: options.readingBudget, started: Date()) {
            final = scored.map { entry, ms, pooled in
                var z = ms.zValue * Weights.wordMatch + pooled.zValue * Weights.sentenceMatch
                if !wordZ.isEmpty { z += wordZ[entry] * Weights.secondStageWordVectors }
                if headed(entry) { z += Weights.heading }
                meaningZ[entry] = ms.zValue
                similarity[entry] = ms.raw
                detail[entry] = (ms, pooled)
                return (entry, z - (entries[entry].short ? Weights.shortSentence : 0) - (entries[entry].link ? Weights.link : 0))
            }
            ranking.usedMeaning = true
        }
        ranking.stageSeconds.reading = Date().timeIntervalSince(started) - ranking.stageSeconds.first
        final.sort { $0.score == $1.score ? $0.entry < $1.entry : $0.score > $1.score }

        // The answer: the candidates in order, each with its place.
        func candidate(_ entry: Int, _ score: Double) -> OfflineRanking.Candidate {
            let shown = displayLines(of: entry, retriever: retriever)
            return OfflineRanking.Candidate(passage: retriever.passages[entries[entry].passage], sentence: entries[entry].text, score: score,
                                            lines: shown.lines, after: shown.after)
        }
        ranking.candidates = final.prefix(8).map { candidate($0.entry, $0.score) }
        ranking.pool = final.map { entry, score in
            OfflineRanking.Detail(candidate: candidate(entry, score), lexical: lexicalZ[entry], wordVectors: wordZ.isEmpty ? 0 : wordZ[entry],
                                  wordMatchRaw: detail[entry]?.ms.raw, wordMatch: detail[entry]?.ms.zValue,
                                  sentenceMatchRaw: detail[entry]?.pooled.raw, sentenceMatch: detail[entry]?.pooled.zValue)
        }
        let best = final[0].entry
        let bestEntry = entries[best]
        // Another place that is nearly as good: not the same sentence, and not within two of it in the notes.
        let other = final.dropFirst().first { item in
            let e = entries[item.entry]
            if e.text == bestEntry.text { return false }
            return !(e.sequence == bestEntry.sequence && abs(e.slot - bestEntry.slot) <= 2)
        }
        if let other, final[0].score - other.score < Weights.tie { ranking.alsoClose = candidate(other.entry, other.score) }

        // The gate.
        var evidence = OfflineRanking.Evidence()
        let bestStems = Set(bestEntry.stems)
        evidence.sentenceCoverage = coverage(of: terms, in: bestStems)
        let passageStems = Set(Self.stems(of: retriever.passages[bestEntry.passage].text))
        evidence.passageCoverage = coverage(of: terms, in: passageStems)
        evidence.sharedTerms = terms.filter { $0.weight >= 1 && (bestStems.contains($0.stem) || passageStems.contains($0.stem)) }.count
        evidence.words = stage1[best].isFinite ? stage1[best] : 0
        evidence.score = final[0].score
        evidence.margin = final.count > 1 ? final[0].score - final[1].score : final[0].score
        if ranking.usedMeaning {
            evidence.meaning = meaningZ[best]
            evidence.similarity = similarity[best]
        }
        evidence.unfamiliar = unfamiliarWords(in: question, retriever: retriever)
        ranking.evidence = evidence
        ranking.verdict = Self.verdict(for: evidence, usedMeaning: ranking.usedMeaning, wordsOnly: Lexicon.cjkWords(in: question) > 0)
        ranking.seconds = Date().timeIntervalSince(started)
        return ranking
    }

    /// A question ends in a question mark, a full-width one in Japanese and Chinese too.
    private static func asksSomething(_ text: String) -> Bool { text.hasSuffix("?") || text.hasSuffix("？") }

    /// Opening words that point back at the sentence before ("This one …", "However, …", "Dies …"): such a sentence is read with it.
    private static let pointsBackWords: Set<String> = [
        "this", "these", "that", "those", "it", "its", "they", "their", "he", "she", "such", "however", "thus", "therefore", "also",
        "then", "but", "and", "so", "which", "whereas", "yet", "dies", "diese", "dieser", "dieses", "es", "er", "sie", "dabei", "daher",
        "deshalb", "jedoch", "aber", "und", "esto", "ello", "pero", "cela", "cette", "mais", "et", "questo", "questa", "ma",
    ]

    private static func pointsBack(_ text: String) -> Bool {
        let first = text.prefix(24).split(whereSeparator: { !$0.isLetter }).first.map { Lexicon.fold(String($0)) } ?? ""
        return pointsBackWords.contains(first)
    }

    /// The sentence as it is shown, and the line right after it. Questions, fragments and lines written to an assistant are left out.
    private func displayLines(of entry: Int, retriever: LocalRetriever) -> (lines: [LocalTutor.Quote], after: LocalTutor.Quote?) {
        let e = entries[entry]
        let sequence = sequences[e.sequence]
        func quote(_ i: Int) -> LocalTutor.Quote {
            LocalTutor.Quote(passageKey: retriever.passages[entries[i].passage].key, text: entries[i].text)
        }
        func fit(_ i: Int) -> Bool {
            let n = entries[i]
            return !Self.asksSomething(n.text) && n.words >= 3
                && !TutorPolicy.looksLikeInstruction(n.text, context: retriever.passages[n.passage].text)
        }
        var lines: [LocalTutor.Quote] = []
        if e.slot > 0, Self.pointsBack(e.text), fit(sequence[e.slot - 1]) { lines.append(quote(sequence[e.slot - 1])) }
        lines.append(quote(entry))
        var after: LocalTutor.Quote?
        let introducesList = e.text.hasSuffix(":")
        var taken = 0
        var j = e.slot + 1
        while j < sequence.count {
            let next = sequence[j]
            if Self.asksSomething(entries[next].text) { break }
            if fit(next) {
                if after == nil { after = quote(next) }
                if introducesList, taken < 3 {
                    lines.append(quote(next)); taken += 1
                } else if !introducesList, Self.pointsBack(entries[next].text) {
                    lines.append(quote(next))
                }
                if !introducesList || taken >= 3 { break }
            }
            j += 1
        }
        return (lines, after)
    }

    /// Words of the question that are in none of the notes (not even a typo of one) and that the language's word vectors have never seen:
    /// the name of a thing the notes cannot be telling about. A common word the notes happen not to use ("antidote") is known to the
    /// vectors, so it is not one. Nothing without word vectors for the language, and nothing in German, which builds words by
    /// compounding ("Elektronenquelle") so that a word no vocabulary lists proves nothing.
    private func unfamiliarWords(in question: String, retriever: LocalRetriever) -> [String] {
        guard language != "de", let vectors = OfflineWordVectors.shared(language) else { return [] }
        var out: [String] = []
        for token in Lexicon.tokens(question) where token.isContent && !token.isNumber && token.word.count >= 5
            && token.word.allSatisfy(\.isLetter) && !LocalRetriever.chatShorthand.contains(token.word) {
            if documentFrequency[token.stem] != nil { continue }
            if let mapped = retriever.offlineTerms(token.word).first, documentFrequency[mapped] != nil { continue }
            // A shortening of a word the notes use ("hiper" for "hiperinflación") is that word.
            if token.stem.count >= 4, documentFrequency.keys.contains(where: { $0.hasPrefix(token.stem) }) { continue }
            if !vectors.knows(token.word) && !out.contains(token.word) { out.append(token.word) }
        }
        return out
    }

    /// `wordsOnly`: the question is in Japanese or Chinese, so the contextual model's similarity says nothing and the words alone decide.
    static func verdict(for evidence: OfflineRanking.Evidence, usedMeaning: Bool, wordsOnly: Bool = false) -> OfflineRanking.Verdict {
        if !evidence.unfamiliar.isEmpty { return .weak("the notes never use \(evidence.unfamiliar[0]) and it is not a word the language knows") }
        let shared = max(evidence.sentenceCoverage, evidence.passageCoverage)
        if wordsOnly {
            if evidence.sharedTerms < Gate.anchor { return .weak("none of the question's words are in it") }
            return shared >= Gate.cjkCoverage ? .convincing : .weak("too few of the question's words are in the best sentence")
        }
        if usedMeaning, let similarity = evidence.similarity {
            if evidence.sharedTerms < Gate.anchor { return .weak("none of the question's words are in it") }
            return similarity >= Gate.similarity || shared >= Gate.coverage
                ? .convincing : .weak("the question's words find no close match in the best sentence")
        }
        if evidence.sentenceCoverage >= Gate.wordsOnlyCoverage || evidence.passageCoverage >= Gate.wordsOnlyPassageCoverage {
            return .convincing
        }
        return .weak("the question's words are not in it")
    }

    // MARK: Stage 2

    private struct Scored { var raw: Double; var zValue: Double }

    /// Words so common in these notes (more than one sentence in six) that they tell nothing apart: "the", "der", and the notes' own
    /// subject. Whole words only.
    private func frequentWords() -> Set<String> {
        let limit = max(8, Int(Double(entries.count) * 0.15))
        return Set(documentFrequency.filter { $0.value >= limit }.keys)
    }

    /// Reads the candidates with the encoder and scores each: the word-by-word match with the question, and the whole-sentence match,
    /// both centred on the candidates themselves (the contextual model's vectors share a large common part that says nothing).
    /// Nil when the question could not be read. Candidates not read in time are left out.
    private func readCandidates(_ pool: [Int], encoder: OfflineEncoder, question: TokenMatrix, history: String?, frequent: Set<String>,
                                budget: Double, started: Date) -> [(entry: Int, ms: Scored, pooled: Scored)]? {
        let dim = question.dimension
        func keptRows(_ matrix: TokenMatrix, weight: Float) -> (rows: [Float], weights: [Float]) {
            var rows: [Float] = []
            var weights: [Float] = []
            for r in 0..<matrix.rows {
                let word = Lexicon.fold(matrix.pieces[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if OfflineWords.isGeneral(word) { continue }
                if word.count >= 2, frequent.contains(Lexicon.stem(word)) { continue }
                rows.append(contentsOf: matrix.data[(r * dim)..<((r + 1) * dim)])
                weights.append(weight)
            }
            if weights.isEmpty { return (matrix.data, [Float](repeating: weight, count: matrix.rows)) }
            return (rows, weights)
        }
        var query = keptRows(question, weight: 1)
        if let history, let h = encoder.encode(history, language: language, pieces: true) {
            let past = keptRows(h, weight: Float(Weights.history))
            query.rows += past.rows
            query.weights += past.weights
        }
        let queryRows = query.weights.count

        var read: [(entry: Int, matrix: TokenMatrix)] = []
        for i in pool {
            if Date().timeIntervalSince(started) > budget, read.count >= 8 { break }
            if let m = encoder.encode(entries[i].scoreText, language: language) { read.append((i, m)) }
        }
        guard !read.isEmpty, queryRows > 0 else { return nil }

        // Centre on everything read for this question.
        let mean = OfflineMath.meanRow(of: read.map { ($0.matrix.data, $0.matrix.rows) } + [(query.rows, queryRows)], dimension: dim)
        let q = OfflineMath.centeredUnitRows(query.rows, rows: queryRows, dimension: dim, mean: mean)
        var wordMatch: [Double] = []
        for item in read {
            let c = OfflineMath.centeredUnitRows(item.matrix.data, rows: item.matrix.rows, dimension: dim, mean: mean)
            wordMatch.append(OfflineMath.maxSimilarity(query: q, queryRows: queryRows, weights: query.weights, candidate: c,
                                                       candidateRows: item.matrix.rows, dimension: dim))
        }
        // The whole sentence: the mean of its words against the mean of the question's.
        let pooledQuery = OfflineMath.meanRow(of: [(query.rows, queryRows)], dimension: dim)
        let pooledRows = read.map { OfflineMath.meanRow(of: [($0.matrix.data, $0.matrix.rows)], dimension: dim) }
        let flat = pooledRows.flatMap { $0 } + pooledQuery
        let pooledMean = OfflineMath.meanRow(of: [(flat, pooledRows.count + 1)], dimension: dim)
        let unit = OfflineMath.centeredUnitRows(flat, rows: pooledRows.count + 1, dimension: dim, mean: pooledMean)
        let queryUnit = Array(unit[(pooledRows.count * dim)...])
        var sentenceMatch: [Double] = []
        for r in 0..<pooledRows.count {
            sentenceMatch.append(OfflineMath.dot(Array(unit[(r * dim)..<((r + 1) * dim)]), queryUnit))
        }
        let wz = OfflineMath.zScores(wordMatch), sz = OfflineMath.zScores(sentenceMatch)
        return read.indices.map { i in
            (read[i].entry, Scored(raw: wordMatch[i], zValue: wz[i]), Scored(raw: sentenceMatch[i], zValue: sz[i]))
        }
    }
}
