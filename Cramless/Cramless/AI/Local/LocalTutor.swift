import Foundation

/// What Cap will and won't do, for every tier: no essay writing and no "humanizing" text to hide AI, for anyone.
enum TutorPolicy {
    static func isRefused(_ question: String) -> Bool {
        let q = Lexicon.fold(question)
        let patterns = [
            #"\bwrite (me |my |an |a |the )?(whole |full |entire )?(essay|paper|report|assignment|coursework|homework)\b"#,
            #"\bhumani[sz]e\b"#, #"\bhumani[sz]er\b"#,
            #"\b(sound|seem|look) (more )?(human|like i wrote|like me)\b"#,
            #"\b(bypass|beat|avoid|get past|fool) (the |an |ai |gpt )*(detector|detection|turnitin|gptzero)\b"#,
            #"\bundetectable\b"#,
        ]
        return patterns.contains { q.range(of: $0, options: .regularExpression) != nil }
    }

    static let refusal = "I can't write essays or rewrite text to pass as your own. I can help you plan one from your notes, or quiz you on them."
}

/// The offline tutor (tier T0): answers from the passages the retriever found, quoting them, or says the notes
/// don't cover the question. In hints mode (always for under-18 accounts) it asks a guiding question built from the
/// passage, a sentence of the person's own notes with the key word left out, instead of telling.
enum LocalTutor {

    struct Quote: Equatable, Sendable {
        var passageKey: String
        var text: String
    }

    struct Reply: Equatable, Sendable {
        var text: String
        var quotes: [Quote]
        /// False when the notes don't cover the question (or Cap declined it).
        var grounded: Bool
    }

    static let notCovered = "Your notes don't cover that yet. Add the page or lecture where it comes up and I'll answer from it."
    static let smallTalk = "Ask me anything about your notes and I'll answer from them."

    /// The least share of the question's words the best passage must contain to count as covering it.
    static let minimumCoverage = 0.34

    /// - Parameter terms: the question's words as the retriever matched them (typos mapped to the material's
    ///   words), with how telling each is (`LocalRetriever.weightedTerms`); the question's own words when nil.
    static func reply(question: String, mode: TutorMode, hits: [LocalRetriever.Hit], context: TutorContext?,
                      terms: [String: Double]? = nil) -> Reply {
        if TutorPolicy.isRefused(question) { return Reply(text: TutorPolicy.refusal, quotes: [], grounded: false) }
        if context == nil, isSmallTalk(question) { return Reply(text: smallTalk, quotes: [], grounded: false) }
        let asked = context.map { "\($0.itemPrompt) \($0.expected)" } ?? question
        let weights = terms ?? Dictionary(Lexicon.contentStems(asked).map { ($0, 1.0) }, uniquingKeysWith: { a, _ in a })
        let questionStems = Set(weights.keys)
        if questionStems.isEmpty, context == nil { return Reply(text: smallTalk, quotes: [], grounded: false) }
        guard let best = hits.first, best.coverage >= minimumCoverage || best.matched.count >= 2 else {
            return Reply(text: notCovered, quotes: [], grounded: false)
        }

        // The sentences of the top passages that share the most words with the question. Headings and bare lists
        // ("Prophase, Metaphase, Anaphase, Telophase") say little, so they rank last.
        struct Candidate { var sentence: String; var hit: LocalRetriever.Hit; var index: Int; var score: Double }
        var candidates: [Candidate] = []
        for (rank, hit) in hits.prefix(3).enumerated() {
            for (index, sentence) in Lexicon.sentences(hit.passage.text).enumerated() where !sentence.hasSuffix("?") {
                let words = sentence.split(separator: " ").count
                guard words >= 4 else { continue }
                let stems = Set(Lexicon.contentStems(sentence))
                let shared = stems.intersection(questionStems)
                guard !shared.isEmpty else { continue }
                let weight = shared.reduce(0) { $0 + (weights[$1] ?? 1) }
                let commas = sentence.filter { $0 == "," }.count
                let listPenalty = commas >= 2 && words <= commas * 3 + 4 ? 1.5 : 0
                candidates.append(Candidate(sentence: sentence, hit: hit, index: index,
                                            score: weight - Double(rank) * 0.5 + min(0.4, Double(stems.count) / 30) - listPenalty))
            }
        }
        candidates.sort { $0.score > $1.score }
        guard let first = candidates.first else { return Reply(text: notCovered, quotes: [], grounded: false) }

        // The second sentence: the one right after the first when it carries on ("This is the division of …"),
        // otherwise the best other sentence that adds a word of the question.
        let passageSentences = Lexicon.sentences(first.hit.passage.text)
        var second: (sentence: String, key: String)?
        if first.index + 1 < passageSentences.count {
            let next = passageSentences[first.index + 1]
            let firstWord = Lexicon.fold(String(next.split(separator: " ").first ?? ""))
            let carriesOn = ["this", "it", "they", "these", "that", "each", "then"].contains(firstWord)
                || !Set(Lexicon.contentStems(next)).isDisjoint(with: Set(Lexicon.contentStems(first.sentence)).subtracting(questionStems))
            if carriesOn, !next.hasSuffix("?") { second = (next, first.hit.passage.key) }
        }
        if second == nil, let other = candidates.dropFirst().first(where: { c in
            c.sentence != first.sentence && c.score > 0
                && !Set(Lexicon.contentStems(c.sentence)).intersection(questionStems).isSubset(of: Set(Lexicon.contentStems(first.sentence)))
        }) {
            second = (other.sentence, other.hit.passage.key)
        }
        let label = first.hit.passage.label

        switch mode {
        case .explain:
            var text: String
            if let context {
                text = "You wrote “\(context.given)”, but the answer is “\(context.expected)”. Your notes say: \(first.sentence)"
            } else {
                text = "From your notes: \(first.sentence)"
            }
            var quotes = [Quote(passageKey: first.hit.passage.key, text: first.sentence)]
            if let second {
                text += " \(second.sentence)"
                quotes.append(Quote(passageKey: second.key, text: second.sentence))
            }
            text += " Quick check: can you say it back in your own words?"
            return Reply(text: text, quotes: quotes, grounded: true)

        case .hints:
            // The person's own sentence with its key word left out: they find the word on their page.
            let opener = context.map { "You wrote “\($0.given)”. Have another look: " } ?? "Let's work it out from your notes. "
            var options: [(shown: String, quote: Quote)] = []
            if let second, second.key == first.hit.passage.key, let gapped = gap(second.sentence, avoiding: questionStems) {
                options.append(("\(first.sentence) \(gapped)", Quote(passageKey: first.hit.passage.key, text: "\(first.sentence) \(second.sentence)")))
            }
            if let gapped = gap(first.sentence, avoiding: questionStems) {
                options.append((gapped, Quote(passageKey: first.hit.passage.key, text: first.sentence)))
            }
            if let pick = options.first {
                return Reply(text: "\(opener)\(label) says: “\(pick.shown)” What goes in the gap?", quotes: [pick.quote], grounded: true)
            }
            let text = (context.map { "You wrote “\($0.given)”. " } ?? "") + "Have a look at \(label). What does it say about \(focus(of: questionStems, in: first.sentence))?"
            return Reply(text: text, quotes: [Quote(passageKey: first.hit.passage.key, text: first.sentence)], grounded: true)
        }
    }

    static func isSmallTalk(_ text: String) -> Bool {
        let words = Lexicon.tokens(text).map(\.word)
        guard !words.isEmpty, words.count <= 4 else { return words.isEmpty }
        let phrases: Set<String> = ["hi", "hello", "hey", "thanks", "thank", "thx", "ty", "ok", "okay", "cool", "great",
                                    "nice", "bye", "goodbye", "yes", "no", "yep", "nope", "sure", "lol", "morning",
                                    "night", "good", "awesome", "perfect", "got", "it", "you", "cap", "much", "so"]
        return words.allSatisfy { phrases.contains($0) }
    }

    /// The sentence with its most telling word (not in the question, not a small word) replaced by "____".
    static func gap(_ sentence: String, avoiding questionStems: Set<String>) -> String? {
        let tokens = Lexicon.tokens(sentence)
        let chars = Array(sentence)
        let candidates = tokens.filter { t in
            t.isContent && !t.isNumber && t.word.count >= 4 && !questionStems.contains(t.stem)
                && !LocalGenerator.genericStems.contains(t.stem)
        }
        guard let pick = candidates.max(by: { $0.word.count < $1.word.count }) else { return nil }
        return String(chars[..<pick.range.lowerBound]) + "____" + String(chars[pick.range.upperBound...])
    }

    /// A word of the question the sentence also uses, for "what does it say about …".
    private static func focus(of questionStems: Set<String>, in sentence: String) -> String {
        let tokens = Lexicon.tokens(sentence)
        let chars = Array(sentence)
        if let t = tokens.first(where: { $0.isContent && questionStems.contains($0.stem) }) {
            return String(chars[t.range]).lowercased()
        }
        return "it"
    }
}
