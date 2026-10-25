import Foundation

/// Finds the passages of the person's material that answer a question: BM25 over their pages and lecture
/// segments. The tutor (every tier) answers only from what this returns; the model never searches.
///
/// Pages are cut along their structure (a section with its heading, one passage per parallel heading with its
/// bullets, a definition line), so a passage reads as sentences and a quote from it is real text. Lectures are cut
/// into overlapping pairs of segments. Labels say where a passage is: "Textbook p. 87", "Lecture 6 · 12:05".
struct LocalRetriever: Sendable {

    struct Passage: Hashable, Sendable {
        /// Unique within this retriever.
        var key: String
        var sourceID: UUID
        var title: String
        var label: String
        var text: String
        var pageIndex: Int?
        /// Lecture time, seconds.
        var start: Double?
        /// The line or segment ids the passage was built from.
        var anchorIDs: [String]
    }

    struct Hit: Sendable {
        var passage: Passage
        var score: Double
        /// The share of the question's words the passage contains.
        var coverage: Double
        var matched: Set<String>
    }

    let passages: [Passage]
    private let termFrequencies: [[String: Int]]
    /// The words of each passage's heading ("Anaphase:" before its bullets, "What happens after mitosis?").
    private let headings: [Set<String>]
    private let lengths: [Int]
    private let averageLength: Double
    private let documentFrequency: [String: Int]

    init(material: [TutorMaterial]) {
        var passages: [Passage] = []
        for source in material {
            passages += Self.passages(of: source)
        }
        self.passages = passages
        var tfs: [[String: Int]] = []
        var headings: [Set<String>] = []
        var lengths: [Int] = []
        var df: [String: Int] = [:]
        for passage in passages {
            let stems = Lexicon.contentStems(passage.text)
            var tf: [String: Int] = [:]
            for stem in stems { tf[stem, default: 0] += 1 }
            tfs.append(tf)
            headings.append(Self.headingStems(of: passage))
            lengths.append(stems.count)
            for stem in tf.keys { df[stem, default: 0] += 1 }
        }
        self.termFrequencies = tfs
        self.headings = headings
        self.lengths = lengths
        self.averageLength = lengths.isEmpty ? 1 : max(1, Double(lengths.reduce(0, +)) / Double(lengths.count))
        self.documentFrequency = df
    }

    /// A page passage's heading: its first sentence when that is short, or the words before a colon near the
    /// start ("Anaphase: Sister chromatids …"). Lecture passages have none.
    private static func headingStems(of passage: Passage) -> Set<String> {
        guard passage.pageIndex != nil else { return [] }
        let text = passage.text
        if let colon = text.firstIndex(of: ":"), text[..<colon].split(separator: " ").count <= 3 {
            return Set(Lexicon.contentStems(String(text[..<colon])))
        }
        if let first = Lexicon.sentences(text).first, first.split(separator: " ").count <= 8, first.count < text.count {
            return Set(Lexicon.contentStems(first))
        }
        return []
    }

    /// The best passages for `query`, best first. A word of the query the material doesn't use is matched to a
    /// word it does when they are one typo apart ("cytokenesis").
    func search(_ query: String, limit: Int = 4) -> [Hit] {
        let terms = queryTerms(query)
        guard !terms.isEmpty, !passages.isEmpty else { return [] }
        let n = Double(passages.count)
        let k1 = 1.2, b = 0.75
        var hits: [Hit] = []
        for (i, passage) in passages.enumerated() {
            var score = 0.0
            var matched = Set<String>()
            for term in terms {
                guard let tf = termFrequencies[i][term], tf > 0 else { continue }
                let df = Double(documentFrequency[term] ?? 0)
                let idf = log(1 + (n - df + 0.5) / (df + 0.5))
                let norm = Double(tf) * (k1 + 1) / (Double(tf) + k1 * (1 - b + b * Double(lengths[i]) / averageLength))
                score += idf * norm
                // A passage headed by the word ("Anaphase: …") is about it, not just mentioning it.
                if headings[i].contains(term) { score += idf }
                matched.insert(term)
            }
            if score > 0 {
                hits.append(Hit(passage: passage, score: score, coverage: Double(matched.count) / Double(terms.count), matched: matched))
            }
        }
        return Array(hits.sorted { $0.score == $1.score ? $0.passage.key < $1.passage.key : $0.score > $1.score }.prefix(limit))
    }

    /// How telling a word is across the material (BM25's idf); 0 for a word it doesn't use.
    func idf(_ term: String) -> Double {
        guard let df = documentFrequency[term] else { return 0 }
        let n = Double(passages.count)
        return log(1 + (n - Double(df) + 0.5) / (Double(df) + 0.5))
    }

    /// The query's terms with their weights, for picking sentences.
    func weightedTerms(_ query: String) -> [String: Double] {
        Dictionary(queryTerms(query).map { ($0, max(0.1, idf($0))) }, uniquingKeysWith: { a, _ in a })
    }

    /// The query's content stems, with unknown ones mapped to the nearest word the material uses. General words
    /// ("happens", "difference") are left out unless nothing else is left.
    func queryTerms(_ query: String) -> [String] {
        let all = Lexicon.tokens(query).filter(\.isContent)
        let specific = all.filter { !LocalGenerator.genericStems.contains($0.stem) && !Self.questionWords.contains($0.stem) }
        var out: [String] = []
        for token in (specific.isEmpty ? all : specific) {
            if documentFrequency[token.stem] != nil {
                if !out.contains(token.stem) { out.append(token.stem) }
                continue
            }
            let nearest = documentFrequency.keys.sorted().first { stem in
                let probe = Lexicon.Token(word: stem, stem: stem, range: 0..<0, isStopWord: false, isNegation: false,
                                          isNumber: false, endsClause: false)
                return Lexicon.match(token, probe) == .fuzzy
            }
            let term = nearest ?? token.stem
            if !out.contains(term) { out.append(term) }
        }
        return out
    }

    /// Words of a question that say what kind of question it is, not what it is about.
    static let questionWords: Set<String> = Set(["difference", "explain", "describe", "mean", "meaning", "tell", "say",
                                                 "work", "works", "happen", "example", "define", "definition", "compare",
                                                 "versus", "vs", "please", "help", "understand", "confused", "mistake"].map(Lexicon.stem))

    // MARK: Passages

    private static func passages(of source: TutorMaterial) -> [Passage] {
        var out: [Passage] = []
        for page in source.pages {
            let label = pageLabel(title: source.title, kind: source.kind, page: page.label)
            var n = 0
            func add(_ text: String, _ ids: [String]) {
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard clean.split(separator: " ").count >= 3 else { return }
                n += 1
                out.append(Passage(key: "\(source.sourceID.uuidString)#\(page.index).\(n)", sourceID: source.sourceID,
                                   title: source.title, label: label, text: clean, pageIndex: page.index, start: nil,
                                   anchorIDs: ids))
            }
            let structure = PageStructure.read(page.lines)
            for section in structure.sections {
                // At most about sixty words a passage, cut between sentences.
                var units = section.sentences + section.bullets
                var heading = section.heading
                while !units.isEmpty {
                    var taken: [PageStructure.Unit] = []
                    var words = heading.map { $0.text.split(separator: " ").count } ?? 0
                    while let next = units.first, taken.isEmpty || words + next.text.split(separator: " ").count <= 60 {
                        taken.append(next)
                        words += next.text.split(separator: " ").count
                        units.removeFirst()
                    }
                    // A heading reads as its own sentence ("Mitosis: How Cells Divide."), never glued to the next.
                    let head = heading.map { h -> PageStructure.Unit in
                        var h = h
                        if let last = h.text.last, !".?!:".contains(last) { h.text += "." }
                        return h
                    }.map { [$0] } ?? []
                    add((head + taken).map(\.text).joined(separator: " "), (head + taken).flatMap(\.lineIDs))
                    heading = nil
                }
            }
            for group in structure.groups {
                if let leadIn = group.leadIn {
                    add(leadIn.text + " " + group.siblings.map(\.name.text).joined(separator: ", ") + ".",
                        leadIn.lineIDs + group.siblings.flatMap(\.name.lineIDs))
                }
                for sibling in group.siblings where !sibling.bullets.isEmpty {
                    let body = sibling.bullets.map { sentence($0.text) }.joined(separator: " ")
                    add("\(sibling.name.text): \(body)", sibling.name.lineIDs + sibling.bullets.flatMap(\.lineIDs))
                }
            }
            for definition in structure.definitions where definition.source.lineIDs.count == 1
                && structure.lineTexts[definition.source.lineIDs[0]] == definition.source.text {
                add(definition.source.text, definition.source.lineIDs)
            }
            if n == 0 {
                // No structure found: windows of five lines.
                let lines = page.lines
                var start = 0
                while start < lines.count {
                    let window = Array(lines[start..<min(lines.count, start + 5)])
                    add(window.map(\.text).joined(separator: " "), window.map(\.id))
                    start += 4
                }
            }
        }
        // Lectures: consecutive segments packed into windows of about 45 seconds (or 80 words), without overlap, so
        // a quote's timestamp is the window it is in.
        let segments = source.segments.sorted { $0.start < $1.start }
        var window: [TranscriptSegment] = []
        func flush() {
            guard let first = window.first else { return }
            let text = window.map(\.text).joined(separator: " ")
            if text.split(separator: " ").count >= 3 {
                out.append(Passage(key: "\(source.sourceID.uuidString)#\(first.id)", sourceID: source.sourceID,
                                   title: source.title, label: "\(ItemFactory.shortTitle(source.title)) · \(ItemFactory.timestamp(first.start))",
                                   text: text, pageIndex: nil, start: first.start, anchorIDs: window.map(\.id)))
            }
            window = []
        }
        for segment in segments {
            if let first = window.first {
                let words = window.reduce(0) { $0 + $1.text.split(separator: " ").count }
                if segment.end - first.start > 45 || words > 80 { flush() }
            }
            window.append(segment)
        }
        flush()
        return out
    }

    /// "Biology textbook", page "87" → "Textbook p. 87"; "Week 5 slides" → "Slides p. 3"; otherwise the short title.
    static func pageLabel(title: String, kind: SourceKind, page: String) -> String {
        let words = title.split(separator: " ")
        let materialNouns: Set<String> = ["textbook", "book", "notes", "slides", "handout", "reader", "workbook", "worksheet"]
        if words.count > 1, let last = words.last, materialNouns.contains(last.lowercased()) {
            return "\(Lexicon.capitalizedFirst(last.lowercased())) p. \(page)"
        }
        return "\(ItemFactory.shortTitle(title)) p. \(page)"
    }

    private static func sentence(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let last = t.last else { return t }
        return ".?!".contains(last) ? t : t + "."
    }
}
