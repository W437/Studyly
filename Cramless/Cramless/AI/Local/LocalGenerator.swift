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

    static func generate(pages: [PageText], sourceTitle: String, maxItems: Int = 16,
                         formats: Set<ItemKind> = Set(ItemKind.allCases)) -> Result {
        let allText = pages.flatMap { $0.lines.map(\.text) }.joined(separator: "\n")
        let language = dominantLanguage(allText)
        var candidates: [Candidate] = []
        var title = ""
        var summaries: [String: String] = [:]
        for page in pages {
            let structure = PageStructure.read(page.lines)
            if title.isEmpty { title = structure.subject ?? structure.title?.text ?? "" }
            let writer = PageWriter(structure: structure, pageIndex: page.index, englishRules: language == "en")
            candidates += writer.candidates()
            summaries.merge(writer.topicSummaries()) { first, _ in first }
        }
        candidates = candidates.filter { formats.contains($0.item.kind) }
        let chosen = select(candidates, limit: max(1, maxItems))

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

    /// The recogniser's dominant language code for `text`, read without hints (an English hint makes it read
    /// Spanish, French and German as English: see `OnDeviceLanguageGate`); "en" when it can't tell.
    static func dominantLanguage(_ text: String) -> String {
        guard text.unicodeScalars.filter({ $0.properties.isAlphabetic }).count >= 24 else { return "en" }
        return OnDeviceLanguageGate.dominantLanguage(text)?.rawValue ?? "en"
    }

    // MARK: Choosing

    struct Candidate: Sendable {
        var item: GeneratedItem
        /// Higher is better within a kind.
        var score: Double
        /// Where its first anchor sits: page, then line.
        var order: Int
        var topicSummary: String?
    }

    /// Takes the best of each kind in turn (own words, multiple choice, fill in, flashcard, diagram), so a set is
    /// a mix, then puts them in page order within each topic.
    static func select(_ candidates: [Candidate], limit: Int) -> [Candidate] {
        let kindOrder: [ItemKind] = [.recall, .mcq, .cloze, .flashcard, .diagram, .apply]
        var pools: [ItemKind: [Candidate]] = [:]
        for kind in kindOrder {
            pools[kind] = candidates.filter { $0.item.kind == kind }.sorted {
                $0.score == $1.score ? $0.order < $1.order : $0.score > $1.score
            }
        }
        var chosen: [Candidate] = []
        var seenPrompts = Set<String>()
        while chosen.count < limit {
            var took = false
            for kind in kindOrder where chosen.count < limit {
                guard var pool = pools[kind], !pool.isEmpty else { continue }
                while !pool.isEmpty {
                    let next = pool.removeFirst()
                    let key = Lexicon.normalizedAnswer(next.item.prompt + "|" + (next.item.cloze?.text ?? next.item.answer))
                    if seenPrompts.insert(key).inserted { chosen.append(next); took = true; break }
                }
                pools[kind] = pool
            }
            if !took { break }
        }
        var topicFirst: [String: Int] = [:]
        for c in chosen { topicFirst[c.item.topic] = min(topicFirst[c.item.topic] ?? .max, c.order) }
        return chosen.sorted {
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
    ].map(Lexicon.stem))
}

// MARK: - One page's questions

private struct PageWriter {
    let structure: PageStructure
    let pageIndex: Int
    let englishRules: Bool

    /// Stems the page uses in many places ("mitosis", "cell", "chromosome"): no good as a blank or a key term.
    let ubiquitous: Set<String>
    /// How many sentences and bullets each stem appears in.
    let frequency: [String: Int]

    init(structure: PageStructure, pageIndex: Int, englishRules: Bool) {
        self.structure = structure
        self.pageIndex = pageIndex
        self.englishRules = englishRules
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
        for section in structure.sections { out += sectionItems(section) }
        out += salientClozes(excluding: Set(out.compactMap { $0.item.cloze.map { Lexicon.normalizedAnswer($0.text.replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: "")) } }))
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
        return ".?!".contains(last) ? Lexicon.capitalizedFirst(t) : Lexicon.capitalizedFirst(t) + "."
    }

    /// The topic a section's items belong to.
    private func topicName(for section: PageStructure.Section) -> String {
        guard let heading = section.heading?.text else { return structure.subject ?? "Key ideas" }
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

    // MARK: Definitions

    private func definitionCards(lineDefinitionsOnly: Bool) -> [LocalGenerator.Candidate] {
        var out: [LocalGenerator.Candidate] = []
        var seenTerms = Set<String>()
        for d in structure.definitions {
            let isLine = d.source.lineIDs.count == 1 && structure.lineTexts[d.source.lineIDs[0]] == d.source.text
            if lineDefinitionsOnly, !isLine { continue }
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
            let what = d.term.split(separator: " ").count > 1 ? "term" : "word"
            out.append(.init(item: GeneratedItem(id: "", kind: .cloze, topic: topic, prompt: "Fill in the key \(what).",
                                                 answer: d.term, explanation: "\(d.term): \(d.meaning).",
                                                 cloze: ClozeSpec(text: d.clozeText), anchors: d.source.lineIDs,
                                                 difficulty: 0.3),
                             score: first ? 2.5 : 1.5, order: order(d.source.lineIDs)))
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

            // Own words: one key idea per bullet.
            let prompt = isProcess ? "What happens in \(sibling.name.text.lowercased())?" : "Describe \(lowerFirst(sibling.name.text)) in your own words."
            let echo = Set(Lexicon.contentStems(prompt + " " + sibling.name.text))
            let used = Array(sibling.bullets.prefix(3))
            let ideas = makeIdeas(used, labels: used.map { bulletLabel($0.text) },
                                  context: allBulletTexts, echo: echo)
            out.append(.init(item: GeneratedItem(id: "", kind: .recall, topic: group.name, prompt: prompt, answer: answer,
                                                 explanation: "\(sibling.name.text): \(answer)", keyIdeas: ideas,
                                                 anchors: ids, difficulty: min(0.7, 0.4 + 0.08 * Double(ideas.count))),
                             score: 3, order: order(ids), topicSummary: summary))

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

    private func sectionItems(_ section: PageStructure.Section) -> [LocalGenerator.Candidate] {
        guard let heading = section.heading, heading.text != structure.title?.text || section.isQuestion else { return [] }
        let units = section.bullets.isEmpty ? section.sentences : section.bullets
        guard units.count >= (section.isQuestion ? 1 : 2) else { return [] }
        let topic = topicName(for: section)
        let prompt = section.isQuestion ? heading.text : "Describe \(lowerFirst(Lexicon.trimmedSentence(heading.text))) in your own words."
        let echo = Set(Lexicon.contentStems(prompt))
        let used = Array(units.prefix(3))
        let headingStems = Set(Lexicon.contentStems(heading.text))
        let labels = used.map { section.bullets.isEmpty ? sentenceLabel($0.text, headingStems: headingStems) : bulletLabel($0.text) }
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

    // MARK: Fill-ins from the page's repeated words

    private func salientClozes(excluding used: Set<String>) -> [LocalGenerator.Candidate] {
        var out: [LocalGenerator.Candidate] = []
        let keyTerms = Set(structure.definitions.flatMap { Lexicon.contentStems($0.term) }
                           + structure.groups.flatMap { g in g.siblings.flatMap { Lexicon.contentStems($0.name.text) } })
        for section in structure.sections {
            for unit in section.sentences {
                let plain = Lexicon.normalizedAnswer(unit.text)
                if used.contains(plain) { continue }
                let tokens = Lexicon.tokens(unit.text)
                guard tokens.count >= 6 else { continue }
                let scored = tokens.enumerated().compactMap { index, token -> (Lexicon.Token, Double)? in
                    guard token.isContent, !token.isNumber, token.word.count >= 5, !ubiquitous.contains(token.stem),
                          !Self.genericStems.contains(token.stem) else { return nil }
                    let freq = frequency[token.stem] ?? 0
                    let key = keyTerms.contains(token.stem)
                    guard key || (freq >= 2 && token.word.count >= 6) else { return nil }
                    return (token, Double(min(freq, 3)) + (key ? 2 : 0) + Double(token.word.count) * 0.1 - (index == 0 ? 0.5 : 0))
                }
                guard let (token, score) = scored.max(by: { $0.1 < $1.1 }) else { continue }
                let chars = Array(unit.text)
                let word = String(chars[token.range])
                let clozeText = String(chars[..<token.range.lowerBound]) + "{{\(word)}}" + String(chars[token.range.upperBound...])
                out.append(.init(item: GeneratedItem(id: "", kind: .cloze, topic: topicName(for: section), prompt: "Fill in the word.",
                                                     answer: word, explanation: sentence(unit.text),
                                                     cloze: ClozeSpec(text: sentence(clozeText)), anchors: unit.lineIDs,
                                                     difficulty: 0.35),
                                 score: 1 + score * 0.2, order: order(unit.lineIDs)))
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
