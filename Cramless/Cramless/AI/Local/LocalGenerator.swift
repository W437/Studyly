import Foundation
import NaturalLanguage

/// The offline question writer (tier T0): no model, always available, never metered, instant. It reads each page's
/// structure (`PageStructure`) and writes the questions plain rules can stand behind:
///
/// - definitions ("X is the …", "Key term: X - …") become flashcards and fill-ins;
/// - bullets under a heading become an own-words question with one key idea per bullet;
/// - four or more parallel headings (the phases of mitosis) become multiple choice with the siblings as the wrong
///   options, an order question when they are steps, flashcards, and a diagram when they label a figure;
/// - a question heading ("Why is mitosis important?") becomes an own-words question answered by its paragraph;
/// - a sentence with a word the page keeps using becomes a fill-in.
///
/// Every item is anchored to the real line ids it came from. The result is honestly labelled basic: it can't write
/// "apply it" scenarios or check meaning, so the router shows a note and offers Cloud AI where it exists.
/// English only: on another language it keeps to the language-free "term: meaning" lines and says so.
///
/// What it asks about is chosen, not just found. The pages are cleaned first (`SourceHygiene`: back matter, captions, listings,
/// citations), a "definition" must define something (a term that isn't a piece of a sentence, a meaning that says something), a
/// fill-in comes from a sentence that explains (8 to 40 words, a verb, nothing that needs a figure or the sentence before) and blanks
/// a noun the page doesn't use everywhere, and the set is spread over the sections and never blanks the same word twice. When the
/// text has few such sentences the set is short: a student is better off with 8 questions than with 24 of which half are junk.
enum LocalGenerator {

    struct Result: Equatable, Sendable {
        enum Quality: String, Sendable {
            /// Enough to study from.
            case basic
            /// One to three questions.
            case thin
            case empty
            /// Not English: only "term: meaning" lines were used.
            case unsupportedLanguage
        }

        var title: String
        var topics: [GeneratedTopic]
        var items: [GeneratedItem]
        var quality: Quality
        /// The page language as recognised ("en", "es", …).
        var language: String
    }

    static func generate(pages rawPages: [PageText], sourceTitle: String, maxItems: Int = 16,
                         formats: Set<ItemKind> = Set(ItemKind.allCases), courseLanguage: String? = nil) -> Result {
        let pages = SourceHygiene.prepare(rawPages)
        let allText = pages.flatMap { $0.lines.map(\.text) }.joined(separator: "\n")
        let language = dominantLanguage(allText, courseLanguage: courseLanguage)
        let structures = pages.map { PageStructure.read($0.lines) }
        let document = DocumentContext(structures: structures, firstPage: pages.first?.index ?? 0)
        let tagger = SentenceTagger()
        var candidates: [Candidate] = []
        var title = ""
        var summaries: [String: String] = [:]
        for (page, structure) in zip(pages, structures) {
            if title.isEmpty { title = structure.subject ?? structure.title?.text ?? "" }
            let writer = PageWriter(structure: structure, pageIndex: page.index, englishRules: language == "en",
                                    document: document, tagger: tagger)
            candidates += writer.candidates()
            summaries.merge(writer.topicSummaries()) { first, _ in first }
        }
        // Headings, citation tails and cut-off prompts never become questions (`QuestionQuality`).
        candidates = candidates.filter { formats.contains($0.item.kind) && QuestionQuality.problem(with: $0.item) == nil }
        let words = allText.split(whereSeparator: { $0.isWhitespace }).count
        let chosen = select(candidates, limit: max(1, maxItems), minimum: minimumQuestions(words: words))

        var items: [GeneratedItem] = []
        var topicOrder: [String] = []
        for (n, candidate) in chosen.enumerated() {
            var item = candidate.item
            item.id = "r\(n + 1)"
            var seen = Set<String>()
            item.anchors = item.anchors.filter { seen.insert($0).inserted }
            items.append(item)
            if !topicOrder.contains(item.topic) { topicOrder.append(item.topic) }
            if summaries[item.topic] == nil, let s = candidate.topicSummary { summaries[item.topic] = s }
        }
        let topics = topicOrder.map { GeneratedTopic(name: $0, summary: summaries[$0] ?? "") }
        let quality: Result.Quality = language != "en" && !allText.isEmpty ? .unsupportedLanguage
            : items.isEmpty ? .empty : items.count < 4 ? .thin : .basic
        return Result(title: title.isEmpty ? sourceTitle : title, topics: topics, items: items, quality: quality, language: language)
    }

    /// How many questions a text of `words` words should get when it has good sentences for them: about seven for every 3,000 words
    /// (never fewer than three). The set stops short of this only when the text has nothing better to ask than what the filters keep out.
    static func minimumQuestions(words: Int) -> Int {
        max(3, Int((Double(words) / 3000 * 7).rounded()))
    }

    /// The language of `text`, as a code ("en", "es", …): what the recogniser reads in it when it is sure (`confidentLanguage`), else
    /// the language of the student's other sources in the course (`courseLanguage`), else the device's (`deviceLanguage`, "en" when
    /// the app doesn't speak it). Never a rare language guessed from equations: an English chemistry worksheet of symbols read
    /// Polish at 0.63, and Cloud AI wrote its questions in Polish.
    static func dominantLanguage(_ text: String, courseLanguage: String? = nil,
                                 deviceLanguage: String = LocalGenerator.deviceLanguage()) -> String {
        confidentLanguage(text) ?? courseLanguage ?? deviceLanguage
    }

    /// Letters the recogniser needs to go on: under this, a few words read as whatever language they could be ("call Sam" read as
    /// Polish).
    static let minimumLanguageLetters = 40

    /// The recogniser's dominant language code for `text`, read without hints (an English hint makes it read Spanish, French and
    /// German as English: see `OnDeviceLanguageGate`), when it is sure of it: at least 80% sure (`OnDeviceLanguageGate.minimumConfidence`)
    /// and with `minimumLanguageLetters` letters to judge from. Nil otherwise.
    static func confidentLanguage(_ text: String) -> String? {
        guard text.unicodeScalars.filter({ $0.properties.isAlphabetic }).count >= minimumLanguageLetters else { return nil }
        return OnDeviceLanguageGate.dominantLanguage(text)?.rawValue
    }

    /// The language most of `texts` (the student's other sources in a course, newest first) are in, among those the recogniser is sure
    /// of; nil when it is sure of none. A tie goes to the earlier one.
    static func commonLanguage(of texts: [String]) -> String? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for text in texts {
            guard let code = confidentLanguage(text) else { continue }
            if counts[code] == nil { order.append(code) }
            counts[code, default: 0] += 1
        }
        return order.max { counts[$0, default: 0] < counts[$1, default: 0] }
    }

    /// The device's language when the app speaks it (it has a localization in it), else "en".
    static func deviceLanguage(locale: Locale = .current, known: [String] = Bundle.main.localizations) -> String {
        guard let code = locale.language.languageCode?.identifier, known.contains(code) else { return "en" }
        return code
    }

    // MARK: Choosing


    struct Candidate: Sendable {
        var item: GeneratedItem
        /// Higher is better within a kind.
        var score: Double
        /// Where its first anchor sits: page, then line.
        var order: Int
        var topicSummary: String?
        /// Good enough to ask without being short of questions. A candidate that isn't strong is used only to reach the minimum number
        /// of questions a text deserves.
        var strong: Bool = true
    }

    /// Takes the best of each kind in turn (own words, multiple choice, fill in, flashcard, diagram), so a set is a mix, then puts them in
    /// page order within each topic. Within a kind the next question is the best one after what the set already has: a section that
    /// already has questions, a word that is already a blank and a fact that is already asked (in any format) count against it. Strong
    /// candidates come first; the rest only fill the set up to `minimum`.
    static func select(_ candidates: [Candidate], limit: Int, minimum: Int = 0) -> [Candidate] {
        let kindOrder: [ItemKind] = [.recall, .mcq, .cloze, .flashcard, .diagram, .apply]
        // What each candidate is, worked out once: its repeat key, its blank, the words of its fact.
        struct Entry {
            var candidate: Candidate
            var key: String
            var blank: String?
            var stems: Set<String>
        }
        let entries = candidates.map { c in
            Entry(candidate: c, key: QuestionQuality.duplicateKey(c.item),
                  blank: c.item.kind == .cloze ? Lexicon.contentStems(c.item.answer).joined(separator: " ") : nil,
                  stems: QuestionQuality.factStems(of: c.item))
        }
        func pools(_ strong: Bool) -> [ItemKind: [Entry]] {
            var out: [ItemKind: [Entry]] = [:]
            for kind in kindOrder {
                out[kind] = entries.filter { $0.candidate.item.kind == kind && $0.candidate.strong == strong }.sorted {
                    $0.candidate.score == $1.candidate.score ? $0.candidate.order < $1.candidate.order : $0.candidate.score > $1.candidate.score
                }
            }
            return out
        }
        var chosen: [Entry] = []
        var seenKeys = Set<String>()
        var topicCounts: [String: Int] = [:]
        var blankCounts: [String: Int] = [:]
        func admissible(_ e: Entry) -> Bool {
            if seenKeys.contains(e.key) { return false }
            if let blank = e.blank, !blank.isEmpty, blankCounts[blank, default: 0] >= 1 { return false }
            return !chosen.contains { QuestionQuality.isNearDuplicate(kind: $0.candidate.item.kind, stems: $0.stems, kind: e.candidate.item.kind, stems: e.stems) }
        }
        func take(_ e: Entry) {
            chosen.append(e)
            seenKeys.insert(e.key)
            topicCounts[e.candidate.item.topic, default: 0] += 1
            if let blank = e.blank, !blank.isEmpty { blankCounts[blank, default: 0] += 1 }
        }
        func fill(_ source: [ItemKind: [Entry]], upTo target: Int) {
            var pools = source
            while chosen.count < target {
                var took = false
                for kind in kindOrder where chosen.count < target {
                    guard var pool = pools[kind], !pool.isEmpty else { continue }
                    // The best of the next few after what the set already has.
                    var best: (index: Int, value: Double)?
                    var examined = 0
                    var index = 0
                    while index < pool.count, examined < 14 {
                        if !admissible(pool[index]) { pool.remove(at: index); continue }
                        let c = pool[index].candidate
                        let value = c.score - 0.45 * Double(topicCounts[c.item.topic, default: 0])
                        if best == nil || value > best!.value { best = (index, value) }
                        examined += 1
                        index += 1
                    }
                    if let best {
                        take(pool.remove(at: best.index))
                        took = true
                    }
                    pools[kind] = pool
                }
                if !took { break }
            }
        }
        fill(pools(true), upTo: limit)
        if chosen.count < minimum { fill(pools(false), upTo: min(limit, minimum)) }
        // A set that is mostly fill-ins asks one kind of question again and again: past three fill-ins to two other questions, the weakest
        // fill-ins go, though never below the minimum.
        // (A fill-in of a defined term is a card in spirit and counts with the others.)
        let clozes = chosen.indices.filter { chosen[$0].candidate.item.kind == .cloze && !chosen[$0].candidate.item.prompt.localizedCaseInsensitiveContains("key") }
        let others = chosen.count - clozes.count
        let allowed = max(4, Int((Double(others) * 1.5).rounded(.up)), minimum / 2)
        if clozes.count > allowed {
            let drop = Set(clozes.sorted { chosen[$0].candidate.score < chosen[$1].candidate.score }.prefix(clozes.count - allowed))
            chosen = chosen.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
        }

        var topicFirst: [String: Int] = [:]
        for e in chosen { topicFirst[e.candidate.item.topic] = min(topicFirst[e.candidate.item.topic] ?? .max, e.candidate.order) }
        return chosen.map(\.candidate).sorted {
            let a = topicFirst[$0.item.topic] ?? 0, b = topicFirst[$1.item.topic] ?? 0
            if a != b { return a < b }
            if $0.item.kind != $1.item.kind {
                return (kindOrder.firstIndex(of: $0.item.kind) ?? 0) < (kindOrder.firstIndex(of: $1.item.kind) ?? 0)
            }
            return $0.order < $1.order
        }
    }

    // MARK: Light synonyms

    /// Everyday alternatives for verbs and adjectives study pages lean on, added to the terms of the key ideas this
    /// generator writes (never to a curated item's), so "the envelope dissolves" counts for "breaks down".
    static let synonyms: [String: [String]] = [
        "break": ["dissolve", "disappear", "fall apart", "break up", "break down"],
        "condense": ["coil", "coil up", "thicken", "compact"],
        "separate": ["split", "move apart", "pull apart"],
        "pull": ["drag", "tug", "move apart", "pulled apart"],
        "identical": ["same", "copies", "copy", "clone"],
        "grow": ["growth", "get bigger", "increase"],
        "growth": ["grow", "get bigger"],
        "repair": ["fix", "heal", "mend"],
        "copy": ["replicate", "duplicate"],
        "visible": ["seen", "see"],
        "unwind": ["uncoil", "loosen", "relax"],
        "equator": ["middle", "centre", "center"],
        "divide": ["split", "division"],
        "division": ["divide", "split"],
        "replace": ["renew", "repair"],
        "increase": ["rise", "go up", "grow"],
        "decrease": ["fall", "drop", "go down", "shrink"],
        "produce": ["make", "create"],
        "attach": ["connect", "join", "bind", "hook"],
        "opposite": ["other end", "each end", "both ends"],
    ]

    static let synonymsByStem: [String: [String]] = {
        var out: [String: [String]] = [:]
        for (word, alternatives) in synonyms { out[Lexicon.stem(word), default: []] += alternatives }
        return out
    }()

    /// Words too general to be a key term, a blank or a hint's gap ("become", "process", "after", "same").
    static let genericStems: Set<String> = Set([
        "become", "make", "take", "get", "go", "come", "use", "way", "part", "new", "set", "many", "much", "help",
        "allow", "process", "occur", "happen", "place", "include", "call", "know", "begin", "start", "mean", "able",
        "type", "form", "kind", "main", "certain", "various", "number", "thing", "lot", "down", "up", "out", "off",
        "around", "two", "three", "four", "one", "first", "second", "also", "known", "called", "important", "essential",
        "produce", "after", "before", "during", "between", "within", "without", "over", "under", "through", "across",
        "toward", "towards", "near", "next", "other", "same", "different", "result", "cause", "lead", "last", "time",
        "today", "finally", "actually", "really", "basically", "midterm", "exam", "test", "quiz", "final", "way",
        "remember", "easy", "hard", "spot", "everything", "something", "anything", "nothing", "reverse",
        // Nouns that name no thing of the subject.
        "example", "instance", "fact", "idea", "reason", "question", "answer", "issue", "situation", "aspect", "factor", "method",
        "approach", "technique", "consideration", "condition", "point", "account", "subject", "matter", "manner", "extent", "respect",
        "regard", "course", "concept", "notion", "sense", "amount", "quantity", "portion", "phenomenon",
    ].map(Lexicon.stem))
}

// MARK: - One page's questions

/// What the whole document is about, so a page's writer doesn't ask for the word the whole text keeps repeating.
struct DocumentContext: Sendable {
    var firstPage: Int
    /// The first page's subject ("Dijkstra's algorithm"), for a heading that means nothing alone ("History").
    var subject: String?
    var subjectStems: Set<String>
    /// Sentences and bullets of the whole document that use each content stem.
    var frequency: [String: Int]
    /// Stems the document keeps coming back to (its subject matter): no good as a blank.
    var topicStems: Set<String>
    /// How many sentences and bullets the document has. Under `smallDocument` there is no telling a word the text keeps coming back to
    /// from one it uses once, so the rules that rest on that (a blank used once is decoration) do not apply.
    var unitCount: Int
    static let smallDocument = 10
    var isSmall: Bool { unitCount < Self.smallDocument }

    init(structures: [PageStructure], firstPage: Int = 0) {
        self.firstPage = firstPage
        subject = structures.first?.subject
        var stems = Set(Lexicon.contentStems(subject ?? ""))
        var units: [String] = []
        for structure in structures {
            units += structure.sections.flatMap { $0.sentences.map(\.text) + $0.bullets.map(\.text) }
            units += structure.groups.flatMap { g in g.siblings.flatMap { $0.bullets.map(\.text) } }
            stems.formUnion(Lexicon.contentStems(structure.title?.text ?? ""))
        }
        var frequency: [String: Int] = [:]
        for unit in units { for stem in Set(Lexicon.contentStems(unit)) { frequency[stem, default: 0] += 1 } }
        self.frequency = frequency
        unitCount = units.count
        subjectStems = Set(Lexicon.contentStems(subject ?? ""))
        // About one sentence in twenty, and at least five.
        let threshold = max(5, Int((Double(units.count) * 0.05).rounded(.up)))
        topicStems = Set(frequency.filter { $0.value >= threshold }.map(\.key)).union(stems)
    }
}

/// Part-of-speech tags for a sentence's words, by the offset of each word's first character. One tagger per run: the first use loads
/// the model, the rest cost well under a millisecond a sentence.
final class SentenceTagger: @unchecked Sendable {
    private let tagger = NLTagger(tagSchemes: [.lexicalClass])

    func tags(for text: String) -> [Int: NLTag] {
        tagger.string = text
        var out: [Int: NLTag] = [:]
        var offset = 0
        var cursor = text.startIndex
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            offset += text.distance(from: cursor, to: range.lowerBound)
            cursor = range.lowerBound
            if let tag { out[offset] = tag }
            return true
        }
        return out
    }
}

private struct PageWriter {
    let structure: PageStructure
    let pageIndex: Int
    let englishRules: Bool
    let document: DocumentContext
    let tagger: SentenceTagger
    /// The page the document starts on: its title is the document's title, not a section to ask about.
    var isFirstPage: Bool { pageIndex == document.firstPage }

    /// Stems the page uses in many places ("mitosis", "cell", "chromosome"): no good as a blank or a key term.
    let ubiquitous: Set<String>
    /// How many sentences and bullets each stem appears in.
    let frequency: [String: Int]

    init(structure: PageStructure, pageIndex: Int, englishRules: Bool, document: DocumentContext, tagger: SentenceTagger) {
        self.structure = structure
        self.pageIndex = pageIndex
        self.englishRules = englishRules
        self.document = document
        self.tagger = tagger
        var units: [String] = structure.sections.flatMap { $0.sentences.map(\.text) + $0.bullets.map(\.text) }
        units += structure.groups.flatMap { g in g.siblings.flatMap { $0.bullets.map(\.text) } }
        var frequency: [String: Int] = [:]
        for unit in units {
            for stem in Set(Lexicon.contentStems(unit)) { frequency[stem, default: 0] += 1 }
        }
        self.frequency = frequency
        let threshold = max(4, Int((Double(units.count) * 0.3).rounded(.up)))
        // The page's own subject is everywhere by definition ("mitosis" on a mitosis page).
        let subjectStems = Lexicon.contentStems(structure.subject ?? "")
        self.ubiquitous = Set(frequency.filter { $0.value >= threshold }.map(\.key)).union(subjectStems)
    }

    /// A one-line summary for each topic this page names: a group lists its headings, a section gives its first
    /// sentence.
    func topicSummaries() -> [String: String] {
        var out: [String: String] = [:]
        for group in structure.groups {
            let names = group.siblings.map { $0.name.text.lowercased() }
            guard names.count > 1 else { continue }
            out[group.name] = Lexicon.capitalizedFirst(names.dropLast().joined(separator: ", ") + " and " + names.last!) + "."
        }
        for section in structure.sections {
            guard let first = section.sentences.first?.text ?? section.bullets.first?.text else { continue }
            let words = first.split(separator: " ")
            let line = words.count <= 16 ? first : words.prefix(16).joined(separator: " ") + "…"
            let name = topicName(for: section)
            if out[name] == nil { out[name] = line }
        }
        return out
    }

    func candidates() -> [LocalGenerator.Candidate] {
        guard englishRules else { return definitionCards(lineDefinitionsOnly: true) }
        var out: [LocalGenerator.Candidate] = []
        out += definitionCards(lineDefinitionsOnly: false)
        for group in structure.groups { out += groupItems(group) }
        // The lines an own-words question answers with are noted: a fill-in from the other sentences of the section is the better one.
        var answered = Set<String>()
        for section in structure.sections {
            let items = sectionItems(section)
            for candidate in items where QuestionQuality.problem(with: candidate.item) == nil { answered.formUnion(candidate.item.anchors) }
            out += items
        }
        out += explanatoryClozes(excluding: Set(out.compactMap { $0.item.cloze.map { Lexicon.normalizedAnswer($0.text.replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: "")) } }),
                                 answered: answered)
        return out
    }

    // MARK: Helpers

    private func order(_ ids: [String]) -> Int {
        pageIndex * 100_000 + (ids.compactMap { structure.lineOrder[$0] }.min() ?? 99_999)
    }

    private func numberWord(_ n: Int) -> String {
        ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"][min(n, 10)]
    }

    /// "Chromosomes line up" → "chromosomes line up"; acronyms and names keep their capital.
    private func lowerFirst(_ text: String) -> String {
        guard let firstWord = text.split(separator: " ").first else { return text }
        if firstWord.filter(\.isUppercase).count >= 2 { return text }
        return text.prefix(1).lowercased() + text.dropFirst()
    }

    private func sentence(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let last = t.last else { return t }
        if ".?!".contains(last) { return Lexicon.capitalizedFirst(t) }
        // A sentence that closes a quotation or a bracket after its full stop already ends: … another."
        let closers: Set<Character> = ["\"", "\u{201D}", "\u{2019}", "'", ")", "]"]
        if closers.contains(last), let stop = t.last(where: { !closers.contains($0) }), ".?!".contains(stop) { return Lexicon.capitalizedFirst(t) }
        return Lexicon.capitalizedFirst(t) + "."
    }

    /// The topic a section's items belong to.
    private func topicName(for section: PageStructure.Section) -> String {
        guard let heading = section.heading?.text else { return document.subject ?? structure.subject ?? "Key ideas" }
        if heading == structure.title?.text { return structure.subject ?? Self.topicName(forHeading: heading) }
        return Self.topicName(forHeading: heading)
    }

    static func topicName(forHeading heading: String) -> String {
        let t = Lexicon.trimmedSentence(heading.replacingOccurrences(of: "?", with: ""))
        if let m = t.firstMatch(of: #/^(?i:why\s+(?:is|are|do|does))\s+(?<x>.+?)\s+(?i:important|needed|necessary|useful|matter)$/#) {
            return "Why \(m.x) matters"
        }
        if let m = t.firstMatch(of: #/^(?i:what\s+happens\s+)(?<when>after|before|during|in)\s+(?<x>.+)$/#) {
            return "\(Lexicon.capitalizedFirst(String(m.when))) \(m.x)"
        }
        if let m = t.firstMatch(of: #/^(?i:what\s+(?:is|are)\s+)(?:(?i:a|an|the)\s+)?(?<x>.+)$/#) {
            return Lexicon.capitalizedFirst(String(m.x))
        }
        if let colon = t.firstIndex(of: ":"), t.distance(from: t.startIndex, to: colon) > 2 {
            return String(t[..<colon])
        }
        return t
    }

    /// The section a term is discussed in most, for a definition's topic.
    private func topicForTerm(_ term: String, fallback: PageStructure.Unit) -> String {
        let termStems = Set(Lexicon.contentStems(term))
        var best: (score: Int, name: String)?
        for section in structure.sections {
            let texts = section.sentences.map(\.text) + section.bullets.map(\.text) + [section.heading?.text ?? ""]
            let score = texts.reduce(0) { sum, text in sum + (Set(Lexicon.contentStems(text)).isSuperset(of: termStems) ? 1 : 0) }
            if score > 0, score > (best?.score ?? 0) { best = (score, topicName(for: section)) }
        }
        for group in structure.groups where group.siblings.contains(where: { Set(Lexicon.contentStems($0.name.text)) == termStems }) {
            return group.name
        }
        if let best { return best.name }
        if let home = structure.sections.first(where: { s in s.sentences.contains(fallback) || s.bullets.contains(fallback) }) {
            return topicName(for: home)
        }
        return structure.subject ?? "Key terms"
    }

    // MARK: What is worth asking about

    private static let firstPerson = Pattern(#"\b(?:I|me|my|mine|myself)\b"#)

    /// A line or sentence the questions can stand on: no reference entry, web address, picture caption, formula or markup, not cut off
    /// at an abbreviation or in a quotation, not a list's number, not a sentence that carries on from the one before it, not someone's
    /// own voice ("I designed it in twenty minutes": an interview, a speech).
    private func isClean(_ text: String) -> Bool {
        !TextArtifacts.looksLikeReference(text) && !QuestionQuality.looksLikeCitation(text) && !TextArtifacts.hasWebAddress(text)
            && !TextArtifacts.refersToMissingFigure(text) && !TextArtifacts.hasCodeSymbols(text) && !QuestionQuality.isMostlyFormula(text)
            && !TextArtifacts.hasMarkdownMarker(text) && !TextArtifacts.endsOnAbbreviation(text) && QuestionQuality.quotesMatch(text)
            && !QuestionQuality.isQuotedTitle(text) && !QuestionQuality.startsWithStructure(text)
            && !QuestionQuality.startsWithConjunction(text) && !Self.firstPerson.matches(text) && !TextArtifacts.hasFusedSentences(text)
            && !TextArtifacts.hasLostSymbols(text) && !TextArtifacts.hasDebris(text)
    }

    /// Clean and able to stand alone on a card: it doesn't lean on a numbered line, a listing or the paragraph around it.
    private func isStandalone(_ text: String) -> Bool { isClean(text) && !TextArtifacts.leansOnItsSurroundings(text) }

    /// A definition defines: a term that is a term, a meaning that says something and isn't "that …" (an implication: "X means that
    /// no path can be found"), from a line that is clean.
    private func acceptable(_ d: PageStructure.Definition) -> Bool {
        if TextArtifacts.termProblem(d.term) != nil || !TextArtifacts.hasSubstance(d.meaning) { return false }
        // "The Boltzmann constant." names the thing a formula's symbol stands for; it doesn't define a term.
        if d.meaning.split(whereSeparator: { $0.isWhitespace }).count < 5 { return false }
        if QuestionQuality.isPossessive(d.term), !d.term.contains(" ") { return false }
        let meaning = d.meaning.lowercased()
        if meaning.hasPrefix("that ") || meaning.hasPrefix("how ") || meaning.hasPrefix("whether ") { return false }
        return isStandalone(d.source.text)
    }

    // MARK: Definitions

    /// A "Term: meaning" or "Term - meaning" line (a glossary entry, "Key term: X - …"), as opposed to a sentence that happens to define a
    /// term ("Mitosis is the process by which …").
    private func isTermLine(_ d: PageStructure.Definition) -> Bool {
        var text = d.source.text.trimmingCharacters(in: .whitespaces)
        if let colon = text.firstIndex(of: ":"), text[..<colon].lowercased().hasPrefix("key term") || text[..<colon].lowercased().hasPrefix("term")
            || text[..<colon].lowercased().hasPrefix("definition") || text[..<colon].lowercased().hasPrefix("vocab") || text[..<colon].lowercased().hasPrefix("define"),
           text[text.index(after: colon)...].lowercased().trimmingCharacters(in: .whitespaces).hasPrefix(d.term.lowercased()) {
            text = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        guard text.lowercased().hasPrefix(d.term.lowercased()) else { return false }
        let rest = text.dropFirst(d.term.count).trimmingCharacters(in: .whitespaces)
        return rest.hasPrefix(":") || rest.hasPrefix("-") || rest.hasPrefix("–") || rest.hasPrefix("—")
    }

    private func definitionCards(lineDefinitionsOnly: Bool) -> [LocalGenerator.Candidate] {
        var out: [LocalGenerator.Candidate] = []
        var seenTerms = Set<String>()
        for d in structure.definitions {
            let isLine = d.source.lineIDs.count == 1 && structure.lineTexts[d.source.lineIDs[0]] == d.source.text
            if lineDefinitionsOnly, !isLine { continue }
            // The checks that read English (pronouns, linking words, what a term can look like) apply to English pages only; another
            // language keeps to its "term: meaning" lines as before.
            guard !englishRules || acceptable(d) else { continue }
            let key = Lexicon.contentStems(d.term).joined(separator: " ")
            let topic = topicForTerm(d.term, fallback: d.source)
            let first = seenTerms.insert(key).inserted
            if first {
                out.append(.init(item: GeneratedItem(id: "", kind: .flashcard, topic: topic, prompt: d.term,
                                                     answer: sentence(d.meaning), explanation: "",
                                                     anchors: d.source.lineIDs, difficulty: 0.25),
                                 score: 2, order: order(d.source.lineIDs)))
            }
            guard englishRules else { continue }
            let termLine = isTermLine(d)
            let what = d.term.split(separator: " ").count > 1 ? "term" : "word"
            out.append(.init(item: GeneratedItem(id: "", kind: .cloze, topic: topic, prompt: "Fill in the key \(what).",
                                                 answer: d.term, explanation: "\(d.term): \(d.meaning).",
                                                 cloze: ClozeSpec(text: d.clozeText), anchors: d.source.lineIDs,
                                                 difficulty: 0.3),
                             // A "Term: meaning" line is a card already: its fill-in only repeats it, so it comes after the card (and is
                             // left out when the card is asked). A sentence that defines a term keeps its context in the fill-in.
                             score: first ? (termLine ? 1.4 : 2.5) : 1.5, order: order(d.source.lineIDs), strong: !termLine))
        }
        return out
    }

    // MARK: Parallel headings

    private func groupItems(_ group: PageStructure.Group) -> [LocalGenerator.Candidate] {
        var out: [LocalGenerator.Candidate] = []
        let names = group.siblings.map(\.name.text)
        let noun = group.noun ?? "one"
        let isProcess = group.isSequence
        let summary = names.count > 1
            ? Lexicon.capitalizedFirst(names.dropLast().map { $0.lowercased() }.joined(separator: ", ") + " and " + names.last!.lowercased()) + "."
            : nil
        let allBulletTexts = group.siblings.flatMap { $0.bullets.map(\.text) }
        var mcqCount = 0

        for (index, sibling) in group.siblings.enumerated() {
            let ids = sibling.name.lineIDs + sibling.bullets.flatMap(\.lineIDs)
            guard !sibling.bullets.isEmpty else { continue }
            let answer = sibling.bullets.map { sentence($0.text) }.joined(separator: " ")

            // Own words: one key idea per bullet. (Not for a "heading" that is a list marker or half a sentence: asked with the
            // heading as printed, so "DNA" and "If statements" stay.)
            let prompt = isProcess ? "What happens in \(sibling.name.text.lowercased())?" : "Describe \(lowerFirst(sibling.name.text)) in your own words."
            if !QuestionQuality.isWeakHeading(sibling.name.text) {
                let echo = Set(Lexicon.contentStems(prompt + " " + sibling.name.text))
                let used = Array(sibling.bullets.prefix(3))
                let ideas = makeIdeas(used, labels: used.map { bulletLabel($0.text) },
                                      context: allBulletTexts, echo: echo)
                out.append(.init(item: GeneratedItem(id: "", kind: .recall, topic: group.name, prompt: prompt, answer: answer,
                                                     explanation: "\(sibling.name.text): \(answer)", keyIdeas: ideas,
                                                     anchors: ids, difficulty: min(0.7, 0.4 + 0.08 * Double(ideas.count))),
                                 score: 3, order: order(ids), topicSummary: summary))
            }

            // Flashcard: the heading and its bullets.
            out.append(.init(item: GeneratedItem(id: "", kind: .flashcard, topic: group.name, prompt: sibling.name.text,
                                                 answer: answer, anchors: ids, difficulty: 0.3),
                             score: 1.5, order: order(ids), topicSummary: summary))

            // Multiple choice from the bullet only this heading has; a fill-in from another one, so the two
            // don't ask the same fact.
            guard names.count >= 3, let bullet = mostDistinctive(sibling.bullets, among: allBulletTexts) else { continue }
            let clozeBullet = sibling.bullets.first { $0 != bullet } ?? bullet
            let fact = Lexicon.trimmedSentence(bullet.text)
            let clozeFact = Lexicon.trimmedSentence(clozeBullet.text)
            var choices: [Choice] = []
            let others = nearestSiblings(of: index, in: group.siblings.count, take: 3)
            for i in (others + [index]).sorted() {
                let s = group.siblings[i]
                if i == index {
                    choices.append(Choice(text: s.name.text, correct: true, why: "\(s.name.text): \(lowerFirst(fact))."))
                } else {
                    let why = s.bullets.first.map { "In \(s.name.text.lowercased()), \(lowerFirst(Lexicon.trimmedSentence($0.text)))." }
                    choices.append(Choice(text: s.name.text, correct: false, why: why))
                }
            }
            let mcqIDs = sibling.name.lineIDs + bullet.lineIDs
            out.append(.init(item: GeneratedItem(id: "", kind: .mcq, topic: group.name,
                                                 prompt: "Which \(noun) is this: \(lowerFirst(fact))?",
                                                 answer: sibling.name.text, explanation: "\(sibling.name.text): \(lowerFirst(fact)).",
                                                 choices: choices, anchors: mcqIDs, difficulty: 0.35),
                             score: mcqCount < 2 ? 3 : 2.4, order: order(mcqIDs), topicSummary: summary))
            mcqCount += 1
            if group.noun != nil {
                let clozeIDs = sibling.name.lineIDs + clozeBullet.lineIDs
                out.append(.init(item: GeneratedItem(id: "", kind: .cloze, topic: group.name, prompt: "Fill in the \(noun).",
                                                     answer: sibling.name.text.lowercased(),
                                                     explanation: "\(sibling.name.text): \(lowerFirst(clozeFact)).",
                                                     cloze: ClozeSpec(text: "In {{\(sibling.name.text.lowercased())}}, \(lowerFirst(clozeFact)).",
                                                                      alternates: [[sibling.name.text]]),
                                                     anchors: clozeIDs, difficulty: 0.4),
                                 score: 2, order: order(clozeIDs), topicSummary: summary))
            }
        }

        // The order of steps.
        if isProcess, names.count >= 3 {
            let ids = (group.leadIn?.lineIDs ?? []) + group.siblings.flatMap(\.name.lineIDs)
            out.append(.init(item: GeneratedItem(id: "", kind: .mcq, topic: group.name, prompt: "Which \(noun) comes first?",
                                                 answer: names[0], explanation: "In order: \(names.joined(separator: ", ")).",
                                                 choices: names.prefix(4).enumerated().map { Choice(text: $0.element, correct: $0.offset == 0) },
                                                 anchors: ids, difficulty: 0.3),
                             score: 2, order: order(ids), topicSummary: summary))
            let k = names.count >= 4 ? 1 : 0
            let rest = names.enumerated().filter { $0.offset != k }.prefix(4).map(\.element)
            out.append(.init(item: GeneratedItem(id: "", kind: .mcq, topic: group.name,
                                                 prompt: "Which \(noun) comes right after \(names[k].lowercased())?",
                                                 answer: names[k + 1], explanation: "In order: \(names.joined(separator: ", ")).",
                                                 choices: rest.map { Choice(text: $0, correct: $0 == names[k + 1]) },
                                                 anchors: ids, difficulty: 0.45),
                             score: 2.6, order: order(ids), topicSummary: summary))
        }

        // A labelled figure.
        if group.isRow, names.count >= 3, names.allSatisfy({ $0.split(separator: " ").count <= 2 }) {
            let ids = group.siblings.flatMap(\.name.lineIDs)
            out.append(.init(item: GeneratedItem(id: "", kind: .diagram, topic: group.name,
                                                 prompt: "Label the \(numberWord(names.count)) \(group.name.lowercased()).",
                                                 answer: names.joined(separator: ", "),
                                                 explanation: "From left to right: \(names.joined(separator: ", ")).",
                                                 diagramLabels: ids, anchors: ids, difficulty: 0.4),
                             score: 2, order: order(ids), topicSummary: summary))
        }
        return out
    }

    /// Up to `take` sibling indices nearest `index`, for wrong options.
    private func nearestSiblings(of index: Int, in count: Int, take: Int) -> [Int] {
        (0..<count).filter { $0 != index }.sorted { abs($0 - index) == abs($1 - index) ? $0 < $1 : abs($0 - index) < abs($1 - index) }
            .prefix(take).sorted()
    }

    /// The bullet whose words the other bullets use least.
    private func mostDistinctive(_ bullets: [PageStructure.Unit], among all: [String]) -> PageStructure.Unit? {
        bullets.max { a, b in distinctiveness(a.text, among: all) < distinctiveness(b.text, among: all) }
    }

    private func distinctiveness(_ text: String, among all: [String]) -> Double {
        let mine = Set(Lexicon.contentStems(text))
        guard !mine.isEmpty else { return 0 }
        let others = all.filter { $0 != text }.map { Set(Lexicon.contentStems($0)) }
        let unique = mine.filter { stem in !others.contains { $0.contains(stem) } }
        return Double(unique.count) + Double(mine.count) * 0.01
    }

    // MARK: Sections

    /// Words that name a kind of section rather than a thing ("History", "Proof", "Applications"): a heading made only of them means
    /// nothing without the subject it belongs to.
    private static let sectionWords: Set<String> = [
        "history", "overview", "background", "application", "use", "example", "type", "property", "advantage", "disadvantage",
        "benefit", "limitation", "cause", "effect", "result", "discussion", "analysis", "proof", "definition", "description",
        "derivation", "intuition", "motivation", "variant", "variation", "extension", "generalization", "implementation", "performance",
        "complexity", "statement", "explicit", "formal", "general", "alternative", "pseudocode", "running", "time", "origin", "etymology",
        "criticism", "reception", "legacy", "summary", "conclusion", "theory", "principle",
    ]

    private static let sectionStems: Set<String> = Set(sectionWords.map(Lexicon.stem))

    /// "Describe history (Dijkstra's algorithm) in your own words.": a heading that only names a kind of section says what it is about; a
    /// heading that is just part of the subject's name ("Algorithm") asks about the subject itself.
    private func describePrompt(for heading: String, answer: String = "") -> String {
        // "First Section: Transition from the common rational knowledge of morality to the philosophical": the title's second half says it.
        var shortened = Lexicon.trimmedSentence(heading)
        if shortened.split(separator: " ").count > 8, let colon = shortened.range(of: ": ") { shortened = String(shortened[colon.upperBound...]) }
        let phrase = lowerFirst(shortened)
        let stems = Lexicon.contentStems(heading)
        if let subject = document.subject, !QuestionQuality.isWeakHeading(subject), subject.split(separator: " ").count <= 5, !stems.isEmpty {
            if stems.allSatisfy({ document.subjectStems.contains($0) }) { return "Describe \(subject) in your own words." }
            if stems.allSatisfy({ Self.sectionStems.contains($0) }) { return "Describe \(phrase) (\(subject)) in your own words." }
            // A one-word heading that is not a word of the subject ("Economics" in a text on Le Chatelier's principle) asks nothing alone;
            // when what the section says is about the subject, the subject is named.
            if stems.count == 1, !stems.contains(where: { document.frequency[$0, default: 0] >= 6 }),
               !Set(Lexicon.contentStems(answer)).isDisjoint(with: document.subjectStems) {
                return "Describe \(phrase) (\(subject)) in your own words."
            }
        }
        return "Describe \(phrase) in your own words."
    }

    private func sectionItems(_ section: PageStructure.Section) -> [LocalGenerator.Candidate] {
        guard let heading = section.heading, heading.text != structure.title?.text || section.isQuestion || !isFirstPage else { return [] }
        // A list of three or more is the section's content; otherwise its sentences and bullets, in the order they were written. Only
        // lines that stand alone are used: a caption, a reference or "the following pseudocode:" is left out of the answer.
        let firstLine: (PageStructure.Unit) -> Int = { structure.lineOrder[$0.lineIDs.first ?? ""] ?? 0 }
        let ordered = (section.sentences + section.bullets).sorted { firstLine($0) < firstLine($1) }
        let candidates = section.bullets.count >= 3 ? section.bullets : ordered
        // A question in the middle of an answer is rhetoric, not something to recall.
        let units = candidates.filter { isStandalone($0.text) && !$0.text.hasSuffix("?") }
        guard units.count >= (section.isQuestion ? 1 : 2) else { return [] }
        // A section of which most lines were left out (an interview, a program listing) is not described by what remains.
        guard units.count * 2 >= candidates.count else { return [] }
        // A heading that is a list marker, or the first half of a sentence the next line carries on, is nothing to describe.
        if !section.isQuestion,
           QuestionQuality.isWeakHeading(heading.text, next: section.bullets.count >= 3 ? nil : units.first?.text) {
            return []
        }
        let topic = topicName(for: section)
        let used = Array(units.prefix(3))
        let prompt = section.isQuestion ? heading.text : describePrompt(for: heading.text, answer: used.map(\.text).joined(separator: " "))
        let echo = Set(Lexicon.contentStems(prompt))
        let headingStems = Set(Lexicon.contentStems(heading.text))
        let labels = used.map { section.bullets.contains($0) ? bulletLabel($0.text) : sentenceLabel($0.text, headingStems: headingStems) }
        let ideas = makeIdeas(used, labels: labels, context: units.map(\.text), echo: echo)
        let answer = used.map { sentence($0.text) }.joined(separator: " ")
        let ids = heading.lineIDs + used.flatMap(\.lineIDs)
        let summary = section.sentences.first.map { first -> String in
            let words = first.text.split(separator: " ")
            return words.count <= 16 ? first.text : words.prefix(16).joined(separator: " ") + "…"
        }
        return [.init(item: GeneratedItem(id: "", kind: .recall, topic: topic, prompt: prompt, answer: answer,
                                          explanation: answer, keyIdeas: ideas, anchors: ids,
                                          difficulty: min(0.7, 0.4 + 0.08 * Double(ideas.count))),
                      score: section.isQuestion ? 3.5 : 2.5, order: order(ids), topicSummary: summary)]
    }

    // MARK: Fill-ins from sentences that explain

    private static let definitional = Pattern(#"\b(?:(?:is|are|was|were)\s+(?:a|an|the|called|known|defined|said|considered|when|where|used|made|one\s+of)|means?|refers?\s+to|consists?\s+of|defined\s+as|known\s+as|stands?\s+for|comprises?|includes?|contains?)\b"#)
    private static let causal = Pattern(#"\b(?:because|due\s+to|results?\s+in|leads?\s+to|causes?|caused|so\s+that|in\s+order\s+to|as\s+a\s+result|therefore|thus|hence|prevents?|allows?|enables?|depends?\s+on|increases?|decreases?|reduces?|produces?|generates?|removes?|lowers?|raises?|slows?|triggers?|carries|stores|makes)\b"#)
    private static let comparative = Pattern(#"\b(?:unlike|whereas|compared\s+(?:to|with)|in\s+contrast|differs?|different\s+from|rather\s+than|more\s+\w+\s+than|less\s+\w+\s+than|while)\b"#)
    private static let necessity = Pattern(#"\b(?:must|should|needs?\s+to|has\s+to|requires?|only\s+if)\b"#)
    private static let pronounOpener = Pattern(#"^(?:It|Its|This|That|These|Those|They|Their|Them|He|His|Him|She|Her|Such|There|Here|Other|Another)\b"#)
    /// "Because of these considerations, …", "In this case, …", "For the first iteration, this is …": the first words point back.
    private static let anaphoricStart = Pattern(#"^(?:\S+\s+){0,7}?\S*\b(?:this|these|those|such|former|latter|above|aforementioned)\b|^(?:\S+\s+){0,2}?\S*\b(?:both|either|neither)\b"#, ignoreCase: true)
    private static let subjectPronoun = Pattern(#"\b(?:this|these|those|it|they|he|she)\s+(?:is|are|was|were|has|have|can|will|would|does|do)\b|\b(?:as to|of|to|for|by|with) (?:them|him|her)\b"#, ignoreCase: true)
    /// "A key feature is …", "The main idea is …": the author's label for a point, said before the point.
    private static let labelOpener = Pattern(#"^(?:A|The)\s+(?:key|main|important|major|central|basic)\s+(?:feature|idea|point|property|difference|step|concept)\b"#, ignoreCase: true)
    private static let adverbOpener = Pattern(#"^(?:However|Thus|Therefore|Moreover|Furthermore|Also|Then|Finally|Hence|Indeed|Additionally|Similarly|Likewise|Consequently|Nevertheless|Nonetheless|Meanwhile|Otherwise|For\s+(?:example|instance)|In\s+fact|In\s+addition|In\s+other\s+words|In\s+contrast|By\s+contrast|On\s+the\s+(?:other\s+hand|contrary)|Conversely|Instead|As\s+(?:a\s+result|noted|mentioned|said))\b"#)

    /// How well a sentence stands alone as a fill-in. `explains`: it defines, gives a cause, compares or requires something. `alone`: it
    /// doesn't point back at the sentence before it.
    struct SentenceFit {
        var score: Double
        var explains: Bool
        var alone: Bool
        /// "X is a …", "X means …": the subject is what the sentence defines, so a blank there is the term itself.
        var defines = false
    }

    /// How well a sentence works as a fill-in: it explains something (defines, gives a cause, compares), has a sensible length, and
    /// doesn't lean on the sentence before it. Nil when it can't be a fill-in at all.
    private func sentenceFit(_ text: String, isFirstInSection: Bool, tags: [Int: NLTag]) -> SentenceFit? {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        guard (8...40).contains(words), !text.hasSuffix("?"), let first = text.first, first.isUppercase || first.isNumber,
              isStandalone(text) else { return nil }
        let letters = text.filter(\.isLetter).count, digits = text.filter(\.isNumber).count
        guard digits * 6 <= letters, text.filter({ $0 == "(" }).count <= 1 else { return nil }
        // A statement has a verb. When the tagger has nothing to say, that isn't asked: a device without its model answers nothing, and the
        // iOS Simulator answers "other word" for every word, which tells as little.
        guard !tags.values.contains(where: { $0 != .otherWord }) || tags.values.contains(.verb) else { return nil }
        var fit = SentenceFit(score: 1.0, explains: false, alone: true)
        if Self.definitional.matches(text) { fit.score += 1.5; fit.explains = true; fit.defines = true }
        if Self.causal.matches(text) { fit.score += 1.0; fit.explains = true }
        if Self.comparative.matches(text) { fit.score += 0.8; fit.explains = true }
        if Self.necessity.matches(text) { fit.score += 0.5; fit.explains = true }
        if (12...30).contains(words) { fit.score += 0.6 }
        if isFirstInSection { fit.score += 0.4 }
        if Self.pronounOpener.matches(text) { fit.score -= 1.2; fit.alone = false }
        if Self.anaphoricStart.matches(text) { fit.score -= 1.0; fit.alone = false }
        if Self.subjectPronoun.matches(text) { fit.score -= 1.0; fit.alone = false }
        if Self.labelOpener.matches(text) { fit.score -= 1.0; fit.alone = false }
        if Self.adverbOpener.matches(text) { fit.score -= 0.6 }
        return fit
    }

    /// The blank of a sentence: a noun the page doesn't keep repeating, that the rest of the sentence doesn't use, with a key term or a
    /// term the document comes back to scoring best. Nil when no word is worth blanking.
    private func bestBlank(in text: String, tags: [Int: NLTag], keyTerms: Set<String>, headingTerms: Set<String>, skip: Set<String>, defines: Bool) -> (token: Lexicon.Token, score: Double)? {
        let tokens = Lexicon.tokens(text)
        let chars = Array(text)
        var depth = 0
        var parenAt = [Bool](repeating: false, count: chars.count + 1)
        for (i, c) in chars.enumerated() {
            if c == "(" { depth += 1 }
            parenAt[i] = depth > 0
            if c == ")" { depth = max(0, depth - 1) }
        }
        // The words before a comma that follow nothing ("In contrast,", "For present purposes,") only introduce the sentence.
        var introEnd = 0
        if let comma = chars.prefix(30).firstIndex(of: ","), text[..<text.index(text.startIndex, offsetBy: comma)].split(separator: " ").count <= 3 { introEnd = comma }
        // "For present purposes …", "In this case …": an opening phrase of place, time or reason is an idiom, not an idea.
        let openers: Set<String> = ["for", "in", "on", "at", "by", "under", "with", "from", "after", "before", "during", "since", "as"]
        let idiomEnd = tokens.first.map { openers.contains($0.word) } == true ? min(4, tokens.count) : 0
        var best: (token: Lexicon.Token, score: Double)?
        for (i, token) in tokens.enumerated() {
            let word = String(chars[token.range])
            let acronym = word.count >= 2 && word.count <= 6 && word.allSatisfy { $0.isUppercase || $0.isNumber } && word.contains(where: \.isLetter)
            guard token.isContent, !token.isNumber, token.word.count >= 5 || (acronym && word.count >= 3) else { continue }
            // A past participle ("described") is a verb dressed as a noun.
            if token.word.count >= 6, token.word.hasSuffix("ed") { continue }
            // Not what the whole document (or this page, or this section's heading) keeps saying, and not a word that names no thing.
            guard !document.topicStems.contains(token.stem), !ubiquitous.contains(token.stem), !skip.contains(token.stem),
                  !Self.genericStems.contains(token.stem) else { continue }
            guard !QuestionQuality.isPossessive(word), !QuestionQuality.isAdverb(word), QuestionQuality.isContentBlank(word) else { continue }
            guard !parenAt[token.range.lowerBound] else { continue }
            guard token.range.lowerBound >= introEnd else { continue }
            // Not a piece of a compound ("twenty-minute", "Bellman–Ford") or of a name ("Mathematical Center").
            let before = token.range.lowerBound > 0 ? chars[token.range.lowerBound - 1] : " "
            let after = token.range.upperBound < chars.count ? chars[token.range.upperBound] : " "
            guard !"-–—_/".contains(before), !"-–—_/".contains(after) else { continue }
            if word.first?.isUppercase == true, token.range.lowerBound > 0 {
                let neighbours = [i > 0 ? tokens[i - 1] : nil, i + 1 < tokens.count ? tokens[i + 1] : nil].compactMap { $0 }
                if neighbours.contains(where: { chars[$0.range.lowerBound].isUppercase && !$0.isStopWord }) { continue }
            }
            // A noun (or a word the tagger doesn't know: "LDL", "ARMAC").
            if let tag = tags[token.range.lowerBound], tag != .noun, tag != .otherWord { continue }
            // The rest of the sentence must not give it away: not by the same word, nor by one from the same root ("too remote" / "remoteness").
            guard tokens.filter({ $0.stem == token.stem }).count == 1 else { continue }
            guard !tokens.enumerated().contains(where: { $0.offset != i && $0.element.isContent && TextArtifacts.sharesRoot($0.element.word, token.word) }) else { continue }
            guard i >= idiomEnd else { continue }
            var score = 0.0
            let freq = document.frequency[token.stem] ?? 1
            if keyTerms.contains(token.stem) { score += 2.0 } else if headingTerms.contains(token.stem) { score += 1.0 }
            if (2...12).contains(freq) { score += 0.8 }
            if token.word.count >= 8 { score += 0.5 } else if token.word.count >= 6 { score += 0.25 }
            if acronym { score += 0.6 }
            if i > 0, tokens[i - 1].word == "the" || tokens[i - 1].word == "a" || tokens[i - 1].word == "an" { score += 0.2 }
            // The sentence's own subject, when it defines nothing, is whatever the sentence before it was about ("The gain is one of …").
            if i <= 2, !defines, !acronym { score -= 1.0 }
            // "arts and sciences", "or interests": the second of a pair is a fixed phrase or one of several that fit.
            if i > 0, tokens[i - 1].word == "and" || tokens[i - 1].word == "or" { score -= 0.8 }
            // A common word that is used once in the whole text decorates the sentence; it is not what the text is about.
            if freq <= 1, !document.isSmall, token.word.count <= 8, !acronym, word.first?.isUppercase != true, !keyTerms.contains(token.stem) { score -= 0.5 }
            guard score >= 0.5 else { continue }
            if best == nil || score > best!.score { best = (token, score) }
        }
        return best
    }

    private func explanatoryClozes(excluding used: Set<String>, answered: Set<String>) -> [LocalGenerator.Candidate] {
        var out: [LocalGenerator.Candidate] = []
        let keyTerms = Set(structure.definitions.filter(acceptable).flatMap { Lexicon.contentStems($0.term) }
                           + structure.groups.flatMap { g in g.siblings.flatMap { Lexicon.contentStems($0.name.text) } })
        let headingTerms = Set(structure.sections.flatMap { Lexicon.contentStems($0.heading?.text ?? "") })
        for section in structure.sections {
            // The section's own heading is its topic: not a blank inside it.
            let own = Set(Lexicon.contentStems(section.heading?.text ?? ""))
            for (index, unit) in section.sentences.enumerated() {
                let plain = Lexicon.normalizedAnswer(unit.text)
                if used.contains(plain) { continue }
                // A sentence an own-words question already answers with is a fill-in a little less new than one the section left out.
                let fresh = !unit.lineIDs.allSatisfy(answered.contains)
                let tags = tagger.tags(for: unit.text)
                guard let fit = sentenceFit(unit.text, isFirstInSection: index == 0, tags: tags) else { continue }
                guard let (token, blank) = bestBlank(in: unit.text, tags: tags, keyTerms: keyTerms, headingTerms: headingTerms, skip: own, defines: fit.defines) else {
                    continue
                }
                let total = fit.score + blank + (fresh ? 0.3 : 0)
                // A sentence that leans on the one before it, or a blank that decorates it, is not worth a question at all.
                guard fit.alone, blank >= (document.isSmall ? 0.5 : 1.0), total >= (document.isSmall ? 1.7 : 2.3) else { continue }
                let chars = Array(unit.text)
                let word = String(chars[token.range])
                let clozeText = String(chars[..<token.range.lowerBound]) + "{{\(word)}}" + String(chars[token.range.upperBound...])
                out.append(.init(item: GeneratedItem(id: "", kind: .cloze, topic: topicName(for: section), prompt: "Fill in the word.",
                                                     answer: word, explanation: sentence(unit.text),
                                                     cloze: ClozeSpec(text: sentence(clozeText)), anchors: unit.lineIDs,
                                                     difficulty: 0.35),
                                 score: 1 + total * 0.2, order: order(unit.lineIDs), strong: fit.explains && blank >= 1.2 && total >= 3.4))
            }
        }
        return out
    }

    // MARK: Key ideas

    static var genericStems: Set<String> { LocalGenerator.genericStems }

    private static let particles: Set<String> = ["up", "down", "apart", "out", "off", "away", "together", "back"]

    /// Key ideas for the bullets or sentences of one question: a label each, and the words that show each idea.
    /// A word is a good term when its section or group doesn't use it elsewhere (it says what is special about
    /// this line), when the question's other ideas don't use it (so the ideas stay apart), and when it is neither
    /// in the question nor a word the whole page uses. A term two ideas would share is dropped from both.
    private func makeIdeas(_ units: [PageStructure.Unit], labels: [String], context: [String], echo: Set<String>) -> [KeyIdea] {
        var termLists = units.enumerated().map { n, unit in
            terms(for: unit, context: context.filter { $0 != unit.text },
                  itemOthers: units.enumerated().filter { $0.offset != n }.map(\.element.text), echo: echo)
        }
        let all = termLists.flatMap { Set($0) }
        let shared = Set(all.filter { term in all.filter { $0 == term }.count > 1 })
        termLists = termLists.map { list in
            let kept = list.filter { !shared.contains($0) }
            return kept.isEmpty ? list : kept
        }
        return units.indices.map { n in
            KeyIdea(id: "k\(n + 1)", label: labels[n], terms: termLists[n].isEmpty ? [labels[n].lowercased()] : termLists[n])
        }
    }

    private func terms(for unit: PageStructure.Unit, context: [String], itemOthers: [String], echo: Set<String>) -> [String] {
        let tokens = Lexicon.tokens(unit.text)
        let chars = Array(unit.text)
        let contextStems = Set(context.flatMap(Lexicon.contentStems))
        let otherStems = Set(itemOthers.flatMap(Lexicon.contentStems))
        func original(_ t: Lexicon.Token) -> String { String(chars[t.range]).lowercased() }

        var scored: [(index: Int, score: Double)] = []
        for (i, t) in tokens.enumerated() where t.isContent && !t.isNumber {
            if echo.contains(t.stem) || Self.genericStems.contains(t.stem) || ubiquitous.contains(t.stem) { continue }
            var score = 1.0
            if !contextStems.contains(t.stem) { score += 2 }
            if !otherStems.contains(t.stem) { score += 1 }
            if t.word.count >= 6 { score += 0.5 }
            scored.append((i, score))
        }
        let ranked = scored.sorted { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }
        var picked = ranked.filter { $0.score >= 3 }.prefix(3).map(\.index)
        if picked.isEmpty { picked = ranked.filter { $0.score >= 2 }.prefix(2).map(\.index) }
        if picked.isEmpty { picked = ranked.prefix(2).map(\.index) }

        var terms: [String] = []
        func add(_ term: String) {
            let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty, !terms.contains(clean) { terms.append(clean) }
        }
        for i in picked.sorted() {
            add(original(tokens[i]))
            // A phrasal verb keeps its particle ("line up", "breaks down").
            if i + 1 < tokens.count, Self.particles.contains(tokens[i + 1].word), !tokens[i].endsClause {
                add(original(tokens[i]) + " " + tokens[i + 1].word)
            }
            for alternative in LocalGenerator.synonymsByStem[tokens[i].stem] ?? [] { add(alternative) }
        }
        return Array(terms.prefix(10))
    }

    /// A bullet as a label: no trailing period, no leading article, at most ten words.
    private func bulletLabel(_ text: String) -> String {
        var t = Lexicon.trimmedSentence(text)
        if let m = t.firstMatch(of: #/^(?i:the|a|an)\s+/#) { t = String(t[m.range.upperBound...]) }
        let words = t.split(separator: " ")
        if words.count > 10 { t = words.prefix(10).joined(separator: " ") }
        return Lexicon.capitalizedFirst(t)
    }

    /// A sentence as a label: the point it makes, without the subject the question already names.
    /// "Mitosis is essential for growth and development, allowing …" → "Growth and development".
    private func sentenceLabel(_ text: String, headingStems: Set<String>) -> String {
        var s = Lexicon.trimmedSentence(text)
        var qualifier: String?
        if let m = s.firstMatch(of: #/^(?<lead>(?i:in|for|during|after|before|at|within|among|inside|when|once)\s[^,]{2,40}),\s+(?<rest>.+)$/#) {
            let lead = String(m.lead)
            if !Set(Lexicon.contentStems(lead)).isSubset(of: headingStems) { qualifier = lead.prefix(1).lowercased() + lead.dropFirst() }
            s = String(m.rest)
        }
        if let m = s.firstMatch(of: #/^(?i:(?:it|this|they|these|that|those)\s+(?:also\s+|then\s+|still\s+|usually\s+)?)/#) {
            s = String(s[m.range.upperBound...])
        }
        if let subject = structure.subject, s.lowercased().hasPrefix(subject.lowercased() + " ") {
            s = String(s.dropFirst(subject.count + 1))
        }
        if let m = s.firstMatch(of: #/^(?i:is|are)\s+/#) { s = String(s[m.range.upperBound...]) }
        if let m = s.firstMatch(of: #/^(?i:essential for|important for|needed for|necessary for|responsible for|used for|a form of|a type of|a kind of|one of the|one of|the process of|able to)\s+/#) {
            s = String(s[m.range.upperBound...])
        }
        for cut in [",", ";", " such as ", " which ", " allowing ", " so that ", " because "] {
            if let r = s.range(of: cut), s.distance(from: s.startIndex, to: r.lowerBound) > 6 {
                s = String(s[..<r.lowerBound])
                break
            }
        }
        if s.split(separator: " ").count > 7, let r = s.range(of: " is ") ?? s.range(of: " are ") {
            s = String(s[r.upperBound...])
        }
        if let m = s.firstMatch(of: #/^(?i:the|a|an)\s+/#) { s = String(s[m.range.upperBound...]) }
        var words = s.split(separator: " ").map(String.init)
        if words.count > 8 { words = Array(words.prefix(8)) }
        if let qualifier, words.count + qualifier.split(separator: " ").count <= 10 { words.append(qualifier) }
        return Lexicon.capitalizedFirst(words.joined(separator: " "))
    }
}
