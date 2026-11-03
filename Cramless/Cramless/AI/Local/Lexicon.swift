import Foundation
import NaturalLanguage

// Words as the offline rules see them: one tokenizer, one normaliser, one stemmer and one fuzzy matcher, shared by
// the grader, the generator, the retriever and the grounding check, so "the same word" means one thing everywhere.
//
// English (and the languages written with spaces) for the stemmer and the matchers; the tokenizer also splits Japanese and Chinese, which have no spaces, into words, so
// that retrieval can see them. Every function is pure and deterministic; nothing here touches a model or the network.
//
// Ranges are Swift `Character` offsets into the original text, the unit `HighlightMark` uses, so a range the grader
// returns can be drawn on the person's own answer without conversion.

enum Lexicon {

    /// One word of a text.
    struct Token: Equatable, Hashable, Sendable {
        /// Lowercased, diacritics folded, straight apostrophes: "chromosomes", "don't".
        var word: String
        /// The light stem the matchers compare: "chromosom", "divid".
        var stem: String
        /// Where the word sits in the original text, in `Character` offsets.
        var range: Range<Int>
        var isStopWord: Bool
        var isNegation: Bool
        var isNumber: Bool
        /// A clause boundary (`, . ; : ! ? ( )` or a contrast word) comes right after this token.
        var endsClause: Bool

        /// A word that carries meaning: not a stop word and not a negation.
        var isContent: Bool { !isStopWord && !isNegation }
    }

    /// How two words matched.
    enum MatchKind: Int, Comparable, Sendable {
        case exact = 0
        case fuzzy = 1

        static func < (lhs: MatchKind, rhs: MatchKind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    // MARK: Tokenizing

    /// Splits `text` into words with their ranges. Letters and digits make words; an apostrophe inside a word
    /// stays ("don't"); hyphens and other punctuation split.
    static func tokens(_ text: String) -> [Token] {
        let chars = Array(text)
        var out: [Token] = []
        var start: Int?
        var buffer = ""

        func flush(at end: Int) {
            guard let begin = start, !buffer.isEmpty else { start = nil; buffer = ""; return }
            let word = fold(buffer)
            let stemmed = stem(word)
            let number = word.allSatisfy { $0.isNumber }
            let contrast = contrastWords.contains(word)
            // "what's", "it's", "that'll": a function word with a contraction is still a function word.
            let base = word.split(separator: "'").first.map(String.init) ?? word
            let stop = stopWords.contains(word) || (word.contains("'") && stopWords.contains(base)) || contrast
            out.append(Token(word: word, stem: stemmed, range: begin..<end,
                             isStopWord: stop && !isNegationWord(word), isNegation: isNegationWord(word),
                             isNumber: number, endsClause: false))
            if contrast, out.count >= 2 { out[out.count - 2].endsClause = true }
            start = nil
            buffer = ""
        }

        // Japanese and Chinese have no spaces, so a sentence would be one "word" and nothing could match it: a run of Han, kana or katakana is cut into
        // words by the system's tokenizer (kana in the text means Japanese; Han alone is taken for Chinese).
        var cjk: (NLTokenizer, NLLanguage)?   // one tokenizer for every run of the text: making one is most of the cost
        var index = 0
        while index < chars.count {
            let c = chars[index]
            if isCJK(c) {
                flush(at: index)
                var end = index
                while end < chars.count, isCJK(chars[end]) { end += 1 }
                if cjk == nil { cjk = (NLTokenizer(unit: .word), chars.contains { isKana($0) } ? .japanese : .simplifiedChinese) }
                out += cjkTokens(chars, from: index, to: end, with: cjk!.0, language: cjk!.1)
                index = end
                continue
            }
            if c.isLetter || c.isNumber {
                if start == nil { start = index }
                buffer.append(c)
            } else if isApostrophe(c), start != nil, index + 1 < chars.count, chars[index + 1].isLetter {
                buffer.append("'")
            } else {
                flush(at: index)
                if clausePunctuation.contains(c), !out.isEmpty { out[out.count - 1].endsClause = true }
            }
            index += 1
        }
        flush(at: chars.count)
        return out
    }

    /// The content words' stems of `text`, in order (stop words and negations removed).
    static func contentStems(_ text: String) -> [String] {
        tokens(text).filter(\.isContent).map(\.stem)
    }

    /// Lowercase, no diacritics, straight apostrophes.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
    }

    /// Whitespace collapsed and trimmed, folded, outer punctuation removed: for exact answers ("Telophase." →
    /// "telophase").
    static func normalizedAnswer(_ text: String) -> String {
        let words = tokens(text).map(\.word)
        return words.joined(separator: " ")
    }

    // MARK: Japanese and Chinese

    private static func isKana(_ c: Character) -> Bool {
        guard c.unicodeScalars.count == 1, let v = c.unicodeScalars.first?.value else { return false }
        return (0x3040...0x30FF).contains(v) || (0x31F0...0x31FF).contains(v) || (0xFF66...0xFF9F).contains(v)
    }

    /// Japanese and Chinese are written without spaces, so splitting at spaces counts a whole sentence as one word. This is what the run of Han and
    /// kana in `text` is worth in words (about one for every two characters) and 0 for any other text: add it to a count of the space-separated
    /// words wherever the length of a sentence decides something.
    static func cjkWords(in text: String) -> Int {
        var n = 0
        for c in text where isCJK(c) { n += 1 }
        return (n + 1) / 2
    }

    /// The words of `text` between spaces, and the words a Japanese or Chinese run is worth (`cjkWords`).
    static func wordCount(_ text: String) -> Int {
        text.split(separator: " ").count + cjkWords(in: text)
    }

    /// A character of a language written without spaces: Han (also as Japanese kanji), hiragana, katakana.
    private static func isCJK(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v) || isKana(c)
    }

    /// The words of a run of `chars[from..<to]`, with their ranges in the whole text. Particles (a hiragana word of one or two letters, the common
    /// Chinese ones) are stop words; the rest are content.
    private static func cjkTokens(_ chars: [Character], from: Int, to: Int, with tokenizer: NLTokenizer, language: NLLanguage) -> [Token] {
        let run = String(chars[from..<to])
        tokenizer.string = run
        tokenizer.setLanguage(language)   // after the string: a language set before it is not kept, and 維新 falls apart into two characters
        var out: [Token] = []
        var low = from, cursor = run.startIndex
        tokenizer.enumerateTokens(in: run.startIndex..<run.endIndex) { range, _ in
            // Ranges are walked forward from the last one: the run's characters are counted once, not once per word.
            low += run.distance(from: cursor, to: range.lowerBound)
            let word = String(run[range])
            let high = low + run.distance(from: range.lowerBound, to: range.upperBound)
            out.append(Token(word: word, stem: word, range: low..<high, isStopWord: isCJKFunctionWord(word), isNegation: false, isNumber: false, endsClause: false))
            low = high
            cursor = range.upperBound
            return true
        }
        if out.isEmpty { out = [Token(word: String(run), stem: String(run), range: from..<to, isStopWord: false, isNegation: false, isNumber: false, endsClause: false)] }
        return out
    }

    private static let chineseParticles: Set<String> = ["的", "了", "是", "在", "和", "有", "不", "也", "就", "都", "而", "及", "与", "或", "之", "其", "于", "为", "对", "把", "被", "吗", "呢", "吧", "啊"]

    private static func isCJKFunctionWord(_ word: String) -> Bool {
        if chineseParticles.contains(word) { return true }
        // Hiragana only, one or two letters: the particles and endings (の, を, は, です, ます, いつ).
        return word.count <= 2 && word.unicodeScalars.allSatisfy { (0x3040...0x309F).contains($0.value) }
    }

    private static func isApostrophe(_ c: Character) -> Bool { c == "'" || c == "\u{2019}" || c == "\u{2018}" }

    private static let clausePunctuation: Set<Character> = [",", ".", ";", ":", "!", "?", "(", ")", "\u{2014}", "\u{2013}", "\n", "\u{3001}", "\u{3002}", "\u{FF01}", "\u{FF1F}", "\u{FF0C}"]
    /// Words that end a negation's reach: "not mitosis, but growth".
    private static let contrastWords: Set<String> = ["but", "however", "although", "though", "whereas", "yet"]

    // MARK: Stop words and negations

    /// Function words that carry no idea on their own. Kept small on purpose: "same", "two", "after", "before",
    /// "between", "opposite" and the like stay content words because ideas hinge on them.
    static let stopWords: Set<String> = [
        "a", "an", "the", "of", "to", "in", "on", "at", "by", "for", "with", "from", "into", "onto", "as", "about",
        "and", "or", "so", "that", "which", "who", "whom", "whose", "than", "then", "there", "here", "this", "these",
        "those", "it", "its", "it's", "they", "them", "their", "theirs", "we", "us", "our", "you", "your", "i", "me",
        "my", "he", "him", "his", "she", "her", "is", "are", "was", "were", "be", "been", "being", "am", "do", "does",
        "did", "doing", "have", "has", "had", "having", "can", "could", "will", "would", "shall", "should", "may",
        "might", "must", "what", "when", "where", "why", "how", "each", "every", "all", "any", "some", "both",
        "also", "too", "very", "really", "just", "quite", "basically", "actually", "like", "if", "because", "such",
        "while", "until", "again", "own", "s", "etc", "eg", "ie", "via", "one's", "thing", "things", "kind", "sort",
        "lot", "lots", "get", "gets", "got", "let", "lets", "let's", "um", "uh", "ok", "okay", "yeah", "well",
        "but", "however", "although", "though", "whereas", "yet",
    ]

    private static let negationWords: Set<String> = [
        "not", "no", "never", "none", "nothing", "nobody", "neither", "nor", "without", "cannot", "dont", "doesnt",
        "isnt", "arent", "wasnt", "werent", "cant", "couldnt", "wont", "wouldnt", "shouldnt", "hasnt", "havent",
        "hadnt", "didnt", "mustnt", "aint",
    ]

    static func isNegationWord(_ word: String) -> Bool {
        negationWords.contains(word) || word.hasSuffix("n't")
    }

    // MARK: Stemming
    //
    // Why a hand-made stemmer and not NaturalLanguage's lemmas: measured on these words (macOS 27, Oct 2026), the
    // `.lemma` scheme read "broke" as "brake" in a sentence and "nuclei" as "nucleo", returned nothing for "grew",
    // "copies" and "poles" out of context, and cost about 17 ms per tagger. A grader that turns "the envelope broke
    // down" into brakes is worse than none, so the rules use suffixes plus the irregular forms below.

    /// Irregular plurals science text is full of, to their singular.
    private static let irregularNouns: [String: String] = [
        "nuclei": "nucleus", "mitochondria": "mitochondrion", "bacteria": "bacterium", "criteria": "criterion",
        "phenomena": "phenomenon", "children": "child", "people": "person", "men": "man", "women": "woman",
        "feet": "foot", "teeth": "tooth", "mice": "mouse", "geese": "goose", "indices": "index",
        "matrices": "matrix", "vertices": "vertex", "analyses": "analysis", "hypotheses": "hypothesis",
        "theses": "thesis", "crises": "crisis", "axes": "axis", "fungi": "fungus", "cacti": "cactus",
        "stimuli": "stimulus", "radii": "radius", "loci": "locus", "foci": "focus", "genera": "genus", "ova": "ovum",
        "larvae": "larva", "algae": "alga", "vertebrae": "vertebra", "formulae": "formula", "antennae": "antenna",
        "media": "medium", "spectra": "spectrum", "strata": "stratum",
    ]

    /// Irregular past forms, to the base verb. Words that are also common nouns ("left", "wound", "saw", "felt",
    /// "rose", "ground") are left out on purpose.
    private static let irregularVerbs: [String: String] = [
        "broke": "break", "broken": "break", "grew": "grow", "grown": "grow", "made": "make", "began": "begin",
        "begun": "begin", "fell": "fall", "fallen": "fall", "took": "take", "taken": "take", "gave": "give",
        "given": "give", "went": "go", "gone": "go", "came": "come", "became": "become", "held": "hold",
        "kept": "keep", "lost": "lose", "ran": "run", "seen": "see", "shook": "shake", "shaken": "shake",
        "threw": "throw", "thrown": "throw", "wore": "wear", "worn": "wear", "wrote": "write", "written": "write",
        "drew": "draw", "drawn": "draw", "drove": "drive", "driven": "drive", "ate": "eat", "eaten": "eat",
        "flew": "fly", "flown": "fly", "froze": "freeze", "frozen": "freeze", "hid": "hide", "hidden": "hide",
        "risen": "rise", "shrank": "shrink", "shrunk": "shrink", "spun": "spin", "stuck": "stick", "struck": "strike",
        "tore": "tear", "torn": "tear", "woke": "wake", "woken": "wake", "built": "build", "bought": "buy",
        "brought": "bring", "caught": "catch", "chose": "choose", "chosen": "choose", "dug": "dig", "fed": "feed",
        "fought": "fight", "found": "find", "heard": "hear", "led": "lead", "meant": "mean", "met": "meet",
        "paid": "pay", "said": "say", "sold": "sell", "sent": "send", "slept": "sleep", "spent": "spend",
        "stood": "stand", "taught": "teach", "told": "tell", "thought": "think", "understood": "understand",
        "won": "win", "learnt": "learn", "spelt": "spell", "split": "split", "spread": "spread", "shed": "shed",
        "swollen": "swell", "bitten": "bite", "forgot": "forget", "forgotten": "forget", "got": "get",
        "gotten": "get", "did": "do", "done": "do", "was": "be", "were": "be", "been": "be", "had": "have",
    ]

    /// A light stemmer: plurals, then -ing/-ed, then -ly, then a final e, with British spellings folded to
    /// American and the irregular forms above. "divides", "divided", "dividing" and "divide" share "divid";
    /// "fibres" meets "fiber"; "broke down" meets "breaks down". The order (plural before verb endings) keeps
    /// "strings" and "string" together, and -ing/-ed only come off when what is left has a vowel ("string" stays).
    static func stem(_ input: String) -> String {
        var w = input
        if w.hasSuffix("'s") { w.removeLast(2) }
        if let base = irregularNouns[w] ?? irregularVerbs[w] { w = base }
        guard w.count > 3, w.allSatisfy(\.isLetter) else { return w }
        w = americanSpelling(w)

        // 1. Plurals and the third person.
        if w.hasSuffix("ies"), w.count > 4 {
            w.removeLast(3); w += "y"
        } else if w.hasSuffix("sses") {
            w.removeLast(2)
        } else if w.hasSuffix("ss") || w.hasSuffix("us") || w.hasSuffix("is") {
            // "process", "virus", "mitosis" are not plurals.
        } else if w.hasSuffix("s") {
            w.removeLast()
        }

        // 2. Verb endings.
        func hasVowel(_ s: Substring) -> Bool { s.contains { "aeiouy".contains($0) } }
        var stripped = false
        if w.hasSuffix("ied"), w.count > 4 {
            w.removeLast(3); w += "y"
        } else if w.hasSuffix("ing"), w.count > 5, hasVowel(w.dropLast(3)) {
            w.removeLast(3); stripped = true
        } else if w.hasSuffix("ed"), !w.hasSuffix("eed"), w.count > 4, hasVowel(w.dropLast(2)) {
            w.removeLast(2); stripped = true
        }
        if stripped, w.count > 3, let last = w.last, w.dropLast().last == last,
           !"lsz".contains(last), !"aeiou".contains(last) {
            w.removeLast()   // "splitting" → "split", "stopped" → "stop"; "pulled" keeps "pull"
        }

        // 3. Adverbs, 4. a final e.
        if w.hasSuffix("ly"), w.count > 5 { w.removeLast(2) }
        if w.hasSuffix("e"), w.count > 3 { w.removeLast() }
        return w
    }

    /// "fibre" → "fiber", "colour" → "color". Applied to both sides of every comparison, so a wrong guess costs
    /// nothing.
    private static func americanSpelling(_ w: String) -> String {
        var s = w
        for (british, american) in [("bres", "bers"), ("tres", "ters"), ("bre", "ber"), ("tre", "ter")] where s.hasSuffix(british) {
            s = String(s.dropLast(british.count)) + american
            return s
        }
        if s.count >= 6, s.hasSuffix("our") || s.hasSuffix("ours") {
            s = s.replacingOccurrences(of: "our", with: "or", options: [.backwards], range: s.index(s.endIndex, offsetBy: -4)..<s.endIndex)
        }
        if s.count >= 6, s.hasSuffix("ise") || s.hasSuffix("ised") || s.hasSuffix("ising") || s.hasSuffix("ises") {
            s = s.replacingOccurrences(of: "is", with: "iz", options: [.backwards], range: s.index(s.endIndex, offsetBy: -6)..<s.endIndex)
        }
        return s
    }

    // MARK: Matching

    /// Whether two words are the same word, allowing a small typo in long words: one edit from 5 letters, two
    /// from 9, and the first letter must agree (people rarely mistype it). Numbers match exactly.
    static func match(_ a: Token, _ b: Token) -> MatchKind? {
        if a.stem == b.stem || a.word == b.word { return .exact }
        if a.isNumber || b.isNumber { return nil }
        let shorter = min(a.stem.count, b.stem.count)
        guard shorter >= 5, a.stem.first == b.stem.first else { return nil }
        let allowed = shorter >= 9 ? 2 : 1
        guard abs(a.stem.count - b.stem.count) <= allowed else { return nil }
        return editDistance(a.stem, b.stem, limit: allowed) <= allowed ? .fuzzy : nil
    }

    /// Optimal string alignment distance (Levenshtein with adjacent transpositions), stopping early past `limit`.
    static func editDistance(_ a: String, _ b: String, limit: Int = .max) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prevPrev = [Int](repeating: 0, count: t.count + 1)
        var prev = Array(0...t.count)
        var current = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            current[0] = i
            var rowMin = current[0]
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                var value = min(prev[j] + 1, current[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] {
                    value = min(value, prevPrev[j - 2] + 1)
                }
                current[j] = value
                rowMin = min(rowMin, value)
            }
            if rowMin > limit { return limit + 1 }
            prevPrev = prev
            prev = current
        }
        return prev[t.count]
    }

    /// One occurrence of a phrase in a text.
    struct PhraseMatch: Equatable, Sendable {
        /// Indices into the text's token list, first to last matched word.
        var tokenIndices: [Int]
        /// From the first matched word's start to the last one's end, in `Character` offsets.
        var range: Range<Int>
        var kind: MatchKind
    }

    /// Finds `phrase` in `text`'s tokens: its content words in order, each matched by `match(_:_:)`, with at most
    /// `slop` other content words between two of them. A phrase with no content words ("the same") is matched
    /// word for word. Returns every non-overlapping occurrence, left to right.
    static func find(_ phrase: [Token], in text: [Token], slop: Int = 1) -> [PhraseMatch] {
        var needle = phrase.filter(\.isContent)
        if needle.isEmpty { needle = phrase }
        guard !needle.isEmpty else { return [] }
        let candidates: [Int] = needle.allSatisfy(\.isContent)
            ? text.indices.filter { text[$0].isContent }
            : Array(text.indices)
        var results: [PhraseMatch] = []
        var position = 0
        while position < candidates.count {
            guard let first = match(needle[0], text[candidates[position]]) else { position += 1; continue }
            var matched = [candidates[position]]
            var worst = first
            var cursor = position + 1
            var ok = true
            for word in needle.dropFirst() {
                var found = false
                let limit = min(candidates.count, cursor + slop + 1)
                var probe = cursor
                while probe < limit {
                    if let kind = match(word, text[candidates[probe]]) {
                        matched.append(candidates[probe])
                        worst = max(worst, kind)
                        cursor = probe + 1
                        found = true
                        break
                    }
                    probe += 1
                }
                if !found { ok = false; break }
            }
            if ok, let lo = matched.first, let hi = matched.last {
                results.append(PhraseMatch(tokenIndices: matched, range: text[lo].range.lowerBound..<text[hi].range.upperBound, kind: worst))
                position = cursor
            } else {
                position += 1
            }
        }
        return results
    }

    /// True when a negation sits within three words before `index`, in the same clause: "doesn't help it grow".
    /// "Not only" and "not just" affirm what follows, so they don't count.
    static func isNegated(at index: Int, in text: [Token]) -> Bool {
        var probe = index - 1
        var seen = 0
        while probe >= 0, seen < 3 {
            if text[probe].endsClause { return false }
            if text[probe].isNegation {
                let next = probe + 1 < text.count ? text[probe + 1].word : ""
                if !["only", "just", "merely", "simply"].contains(next) { return true }
            }
            if text[probe].isContent { seen += 1 }
            probe -= 1
        }
        return false
    }

    // MARK: Text helpers

    /// The sentences of `text`, trimmed, in order.
    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .localized]) { sub, _, _, _ in
            if let s = sub?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { out.append(s) }
        }
        return out.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? [text.trimmingCharacters(in: .whitespacesAndNewlines)] : out
    }

    /// The share of `text`'s content stems that also appear in `reference`, 0…1 (1 when `text` has none).
    static func overlap(of text: String, with reference: String) -> Double {
        let mine = Set(contentStems(text))
        guard !mine.isEmpty else { return 1 }
        let theirs = tokens(reference).filter(\.isContent)
        let theirStems = Set(theirs.map(\.stem))
        var shared = 0
        for stem in mine {
            if theirStems.contains(stem) { shared += 1; continue }
            let probe = Token(word: stem, stem: stem, range: 0..<0, isStopWord: false, isNegation: false,
                              isNumber: stem.allSatisfy(\.isNumber), endsClause: false)
            if theirs.contains(where: { match(probe, $0) != nil }) { shared += 1 }
        }
        return Double(shared) / Double(mine.count)
    }

    /// "fill in the blank" → "Fill in the blank".
    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// The text without a trailing period or colon, trimmed.
    static func trimmedSentence(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = s.last, ".:;,".contains(last) { s.removeLast() }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
