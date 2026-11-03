import Foundation

/// One page as the offline rules read it: a title, sections (a heading with its sentences and bullets), groups of
/// parallel headings with the bullets under each (the four phases of mitosis), and definitions. Every piece keeps
/// the ids of the lines it came from, so anything built from it is anchored to real lines.
///
/// Two layouts are understood. A **stacked** page puts each heading above its own bullets. A **row** page (common
/// in textbooks) prints parallel headings side by side with a column of bullets under each; text recognition reads
/// such a page row by row, interleaving the columns, so with line boxes the bullets are put back under the heading
/// whose column they sit in. Without boxes (typed text, PDFs) only the stacked layout is assumed.
struct PageStructure: Sendable {

    /// Text with the lines it came from.
    struct Unit: Hashable, Sendable {
        var text: String
        var lineIDs: [String]
    }

    struct Section: Sendable {
        var heading: Unit?
        var sentences: [Unit]
        var bullets: [Unit]

        var isQuestion: Bool { heading?.text.hasSuffix("?") ?? false }
    }

    struct Sibling: Sendable {
        var name: Unit
        var bullets: [Unit]
    }

    /// Parallel headings: "Prophase, Metaphase, Anaphase, Telophase".
    struct Group: Sendable {
        /// "Phases of mitosis".
        var name: String
        /// The singular noun the headings share, when known: "phase".
        var noun: String?
        var leadIn: Unit?
        var siblings: [Sibling]
        /// The headings are steps in order (phases, stages, steps), so "what comes after" questions make sense.
        var isSequence: Bool
        /// Printed side by side (the labels of a figure), as opposed to stacked.
        var isRow: Bool
    }

    struct Definition: Hashable, Sendable {
        var term: String
        var meaning: String
        var source: Unit
        /// The sentence with the term marked as a blank: "{{Cytokinesis}} is the division of the cytoplasm."
        var clozeText: String
    }

    var title: Unit?
    /// What the page is about, from the title: "Mitosis".
    var subject: String?
    var sections: [Section]
    var groups: [Group]
    var definitions: [Definition]
    /// Every line id to its text, for anchors and the grounding check.
    var lineTexts: [String: String]
    /// Every line id to its position on the page.
    var lineOrder: [String: Int]

    // MARK: - Reading

    private enum Kind { case noise, heading, leadIn, bullet, definition, text }

    static func read(_ input: [TextLine]) -> PageStructure {
        // A Markdown heading ("## Statins": pasted notes, copied web pages, a chatbot's answer) is a heading whatever its length;
        // the marks are not part of the text.
        var lines: [TextLine] = []
        var marked: [Bool] = []
        for line in input {
            let (text, isMarked) = markdownHeading(in: clean(line.text))
            guard !text.isEmpty else { continue }
            lines.append(TextLine(id: line.id, text: text, box: line.box))
            marked.append(isMarked)
        }
        var lineTexts: [String: String] = [:]
        var lineOrder: [String: Int] = [:]
        for (i, line) in lines.enumerated() { lineTexts[line.id] = line.text; lineOrder[line.id] = i }

        var kinds = lines.indices.map { marked[$0] ? Kind.heading : classify(lines[$0]) }
        // A heading followed by a lowercase line is a wrapped line of a paragraph ("During mitosis the DNA is copied"
        // / "and separated …"), not a heading.
        for i in lines.indices where kinds[i] == .heading && !marked[i] && !lines[i].text.hasSuffix("?") {
            if let next = lines[(i + 1)...].first(where: { classify($0) != .noise }), let first = next.text.first,
               first.isLowercase, !isBullet(next.text), !lines[i].text.contains(":") {
                kinds[i] = .text
            }
        }
        // A heading right after a line that stops on an abbreviation or an initial is the rest of a name the line splitter cut in two
        // ("Brown v." / "Board of Education of Topeka"; "… by Edsger W." / "Dijkstra in 1956 …").
        for i in lines.indices where kinds[i] == .heading && !marked[i] && i > 0 {
            if let previous = lines[..<i].last(where: { classify($0) != .noise }), cutsAName(previous.text) { kinds[i] = .text }
        }
        // With boxes, the title is the tallest heading near the top; smaller lines above it are a running header
        // ("Unit 3 Cell Biology" over "Mitosis: How Cells Divide").
        var titleIndex: Int?
        let topHeadings = lines.indices.filter { kinds[$0] == .heading && (lines[$0].box?.y ?? 1) < 0.35 }
        if let tallest = topHeadings.max(by: { (lines[$0].box?.h ?? 0) < (lines[$1].box?.h ?? 0) }),
           let titleBox = lines[tallest].box {
            titleIndex = tallest
            for i in lines.indices where i < tallest {
                if let box = lines[i].box, box.y < titleBox.y, box.h < titleBox.h * 0.6 { kinds[i] = .noise }
            }
        } else if let first = lines.indices.first(where: { kinds[$0] != .noise }), kinds[first] == .heading {
            titleIndex = first
        }

        // Row groups: three or more short headings side by side, with the columns of bullets under them.
        var consumed = Set<Int>()
        var groups: [Group] = []
        var index = 0
        while index < lines.count {
            if let row = rowGroup(at: index, lines: lines, kinds: kinds) {
                groups.append(row.group)
                consumed.formUnion(row.consumed)
                index = (row.consumed.max() ?? index) + 1
            } else {
                index += 1
            }
        }

        // Sections, in reading order, over what the rows didn't take.
        var sections: [Section] = []
        var current = Section(heading: nil, sentences: [], bullets: [])
        var paragraph: [(id: String, text: String)] = []
        var definitions: [Definition] = []
        var lastWasBullet = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            current.sentences.append(contentsOf: sentenceUnits(paragraph))
            paragraph = []
        }
        func flushSection() {
            flushParagraph()
            // A heading with nothing under it makes no questions; the title is kept apart.
            if !current.sentences.isEmpty || !current.bullets.isEmpty { sections.append(current) }
            current = Section(heading: nil, sentences: [], bullets: [])
        }

        for (i, line) in lines.enumerated() where !consumed.contains(i) {
            switch kinds[i] {
            case .noise:
                continue
            case .heading:
                flushSection()
                current.heading = Unit(text: line.text, lineIDs: [line.id])
                lastWasBullet = false
            case .bullet:
                flushParagraph()
                current.bullets.append(Unit(text: stripBullet(line.text), lineIDs: [line.id]))
                lastWasBullet = true
            case .definition:
                flushParagraph()
                if let d = lineDefinition(line.text) {
                    definitions.append(Definition(term: d.term, meaning: d.meaning, source: Unit(text: line.text, lineIDs: [line.id]),
                                                  clozeText: clozeFromLineDefinition(term: d.term, meaning: d.meaning)))
                }
                lastWasBullet = false
            case .leadIn, .text:
                if lastWasBullet, let first = line.text.first, first.isLowercase, var last = current.bullets.popLast() {
                    last.text = join(last.text, line.text)
                    last.lineIDs.append(line.id)
                    current.bullets.append(last)
                } else {
                    paragraph.append((line.id, line.text))
                    lastWasBullet = false
                    kinds[i] = .text
                }
            }
        }
        flushSection()

        // Stacked groups: three or more consecutive sections with short headings and bullets of their own.
        var stacked: [Group] = []
        var run: [Int] = []
        func closeRun() {
            if run.count >= 3 {
                let siblings = run.map { Sibling(name: sections[$0].heading!, bullets: sections[$0].bullets) }
                let noun = sharedNoun(siblings.map(\.name.text))
                stacked.append(Group(name: groupName(noun: noun, leadIn: nil, subject: nil, fallback: siblings.map(\.name.text)),
                                     noun: noun, leadIn: nil, siblings: siblings,
                                     isSequence: noun.map(isSequenceNoun) ?? false, isRow: false))
            }
            run = []
        }
        for (i, section) in sections.enumerated() {
            if let heading = section.heading, heading.text.split(separator: " ").count <= 3, !section.bullets.isEmpty,
               !heading.text.hasSuffix("?") {
                run.append(i)
            } else {
                closeRun()
            }
        }
        closeRun()
        let stackedIndices = Set(stacked.flatMap { g in g.siblings.compactMap { s in sections.firstIndex { $0.heading == s.name } } })
        let keptSections = sections.enumerated().filter { !stackedIndices.contains($0.offset) }.map(\.element)

        // Definitions inside sentences ("Mitosis is the process by which …").
        for section in keptSections {
            for sentence in section.sentences {
                if let d = sentenceDefinition(sentence.text) {
                    definitions.append(Definition(term: d.term, meaning: d.meaning, source: sentence, clozeText: d.cloze))
                }
            }
        }

        let title = titleIndex.map { Unit(text: lines[$0].text, lineIDs: [lines[$0].id]) }
        let subject = title.flatMap { subjectOf(title: $0.text) } ?? mostFrequentNoun(lines.map(\.text))
        // A row group's name can use the page's subject ("Phases of mitosis") once it is known.
        groups = groups.map { g in
            var g = g
            if g.name.isEmpty {
                g.name = groupName(noun: g.noun, leadIn: g.leadIn?.text, subject: subject, fallback: g.siblings.map(\.name.text))
            }
            return g
        }
        return PageStructure(title: title, subject: subject, sections: keptSections, groups: groups + stacked,
                             definitions: definitions, lineTexts: lineTexts, lineOrder: lineOrder)
    }

    // MARK: Lines

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static let markdownTitle = Pattern(#"^#{1,6}\s+(\S.*?)(?:\s+#+)?$"#)
    private static let endsOnInitial = Pattern(#"(?:\b[A-Z][a-z]+|\b[A-Z]\.)\s+[A-Z]\.$"#)

    /// "## Statins" → ("Statins", true). Up to six marks, a space, then a title of at most 24 words; a closing run of marks is dropped.
    static func markdownHeading(in text: String) -> (text: String, isHeading: Bool) {
        guard let title = markdownTitle.capture(1, in: text) else { return (text, false) }
        return title.split(separator: " ").count <= 24 ? (title, true) : (text, false)
    }

    /// The text stops on an abbreviation or on a first-name initial: the next piece is the rest of the same sentence.
    static func cutsAName(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        return TextArtifacts.endsOnAbbreviation(t) || endsOnInitial.matches(t)
    }

    /// The piece starts like the rest of a name or a citation, not like a new sentence: a capitalised word that isn't a function word,
    /// or a number.
    static func continuesAName(_ text: String) -> Bool {
        guard let first = text.split(separator: " ").first.map(String.init), let c = first.first else { return false }
        if c.isNumber { return true }
        return c.isUppercase && !Lexicon.stopWords.contains(Lexicon.fold(first).trimmingCharacters(in: .punctuationCharacters))
    }

    private static let bulletMarks: Set<Character> = ["•", "·", "▪", "●", "◦", "‣", "-", "–", "*", "■", "□", "○"]

    static func isBullet(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        if bulletMarks.contains(first), text.dropFirst().first == " " { return true }
        return text.firstMatch(of: #/^(?:\d{1,2}|[a-z])[.)]\s+\S/#) != nil
    }

    static func stripBullet(_ text: String) -> String {
        var t = Substring(text)
        if let first = t.first, bulletMarks.contains(first) {
            t = t.dropFirst()
        } else if let m = text.firstMatch(of: #/^(?:\d{1,2}|[a-z])[.)]\s+/#) {
            t = text[m.range.upperBound...]
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static func join(_ a: String, _ b: String) -> String {
        if a.hasSuffix("-"), let first = b.first, first.isLowercase { return String(a.dropLast()) + b }
        return a + " " + b
    }

    private static func classify(_ line: TextLine) -> Kind {
        let t = line.text
        let words = t.split(separator: " ")
        if t.allSatisfy({ $0.isNumber || $0.isWhitespace || $0 == "." || $0 == "|" }) { return .noise }
        if t.count <= 2 { return .noise }
        if isBullet(t) { return .bullet }
        if lineDefinition(t) != nil { return .definition }
        if t.hasSuffix(":"), words.count >= 4 { return .leadIn }
        if isHeadingText(t) { return .heading }
        return .text
    }

    static func isHeadingText(_ t: String) -> Bool {
        let words = t.split(separator: " ")
        guard !words.isEmpty, words.count <= 8, let first = t.first, first.isUppercase || first.isNumber else { return false }
        if t.contains(",") { return false }
        if let last = t.last, ".;,".contains(last) { return false }
        if t.hasSuffix(":"), words.count >= 4 { return false }
        let lastWord = Lexicon.fold(String(words.last!)).trimmingCharacters(in: .punctuationCharacters)
        if Lexicon.stopWords.contains(lastWord), !t.hasSuffix("?") { return false }   // a wrapped line: "… cells and"
        return true
    }

    // MARK: Rows of parallel headings

    private static func rowGroup(at start: Int, lines: [TextLine], kinds: [Kind]) -> (group: Group, consumed: Set<Int>)? {
        guard kinds[start] == .heading, let firstBox = lines[start].box else { return nil }
        var row = [start]
        var i = start + 1
        while i < lines.count, kinds[i] == .heading, let box = lines[i].box, abs(box.y - firstBox.y) < 0.02,
              box.x > (lines[row.last!].box?.x ?? 0), lines[i].text.split(separator: " ").count <= 3 {
            row.append(i)
            i += 1
        }
        guard row.count >= 3, lines[start].text.split(separator: " ").count <= 3 else { return nil }

        // The columns: narrow lines below the row, until something wide (a paragraph or a full heading) starts.
        let centers = row.map { idx -> Double in let b = lines[idx].box!; return b.x + b.w / 2 }
        var columns = [[Int]](repeating: [], count: row.count)
        var consumed = Set(row)
        var j = i
        while j < lines.count {
            guard let box = lines[j].box, box.y > firstBox.y else { break }
            if box.w > 0.33 || kinds[j] == .leadIn || kinds[j] == .definition { break }
            if kinds[j] == .heading, lines[j].text.split(separator: " ").count > 3 { break }
            let center = box.x + box.w / 2
            let nearest = centers.enumerated().min { abs($0.element - center) < abs($1.element - center) }!.offset
            columns[nearest].append(j)
            consumed.insert(j)
            j += 1
        }

        var siblings: [Sibling] = []
        for (c, idx) in row.enumerated() {
            let ordered = columns[c].sorted { (lines[$0].box?.y ?? 0) < (lines[$1].box?.y ?? 0) }
            var bullets: [Unit] = []
            for k in ordered {
                let text = lines[k].text
                if isBullet(text) || bullets.isEmpty {
                    bullets.append(Unit(text: stripBullet(text), lineIDs: [lines[k].id]))
                } else {
                    bullets[bullets.count - 1].text = join(bullets[bullets.count - 1].text, text)
                    bullets[bullets.count - 1].lineIDs.append(lines[k].id)
                }
            }
            siblings.append(Sibling(name: Unit(text: lines[idx].text, lineIDs: [lines[idx].id]), bullets: bullets))
        }

        var leadIn: Unit?
        if start > 0, kinds[start - 1] == .leadIn {
            leadIn = Unit(text: lines[start - 1].text, lineIDs: [lines[start - 1].id])
            consumed.insert(start - 1)
        }
        let parsed = leadIn.flatMap { parseLeadIn($0.text) }
        let noun = parsed?.noun ?? sharedNoun(siblings.map(\.name.text))
        let sequence = noun.map(isSequenceNoun) ?? false
        // The name waits for the page's subject when the lead-in doesn't give one (filled in by `read`).
        let name = parsed.map { "\(pluralTitle($0.noun)) of \($0.subject.lowercased())" } ?? ""
        return (Group(name: name, noun: noun, leadIn: leadIn, siblings: siblings, isSequence: sequence, isRow: true), consumed)
    }

    /// "Mitosis occurs in four main phases:" → ("Mitosis", "phase").
    static func parseLeadIn(_ text: String) -> (subject: String, noun: String)? {
        let pattern = #/^(?<subject>[A-Za-z][\w\- ]{1,40}?)\s+(?:occurs|happens|takes place|proceeds|is divided|can be divided|has|have|consists|is made up|goes)\s+(?:in|into|of|through)?\s*(?:the\s+)?(?:\w+\s+)?(?:main\s+|key\s+|basic\s+|major\s+|different\s+|distinct\s+)?(?<noun>[A-Za-z]+?)s?:$/#
        guard let m = text.firstMatch(of: pattern) else { return nil }
        let noun = String(m.noun).lowercased()
        guard noun.count >= 3 else { return nil }
        return (String(m.subject), noun)
    }

    /// The word every heading ends with ("prophase", "metaphase" … → "phase").
    static func sharedNoun(_ names: [String]) -> String? {
        let folded = names.map { Lexicon.fold($0) }
        guard let first = folded.first, folded.count >= 2 else { return nil }
        for length in stride(from: min(8, first.count - 1), through: 4, by: -1) {
            let suffix = String(first.suffix(length))
            if folded.allSatisfy({ $0.hasSuffix(suffix) && $0.count > suffix.count }) { return suffix }
        }
        return nil
    }

    static func isSequenceNoun(_ noun: String) -> Bool {
        ["phase", "stage", "step", "period", "era", "round", "level", "generation"].contains(noun)
    }

    private static func pluralTitle(_ noun: String) -> String {
        Lexicon.capitalizedFirst(noun.hasSuffix("s") ? noun : noun + "s")
    }

    private static func groupName(noun: String?, leadIn: String?, subject: String?, fallback: [String]) -> String {
        if let leadIn, let parsed = parseLeadIn(leadIn) { return "\(pluralTitle(parsed.noun)) of \(parsed.subject.lowercased())" }
        if let noun, let subject { return "\(pluralTitle(noun)) of \(subject.lowercased())" }
        if let noun { return pluralTitle(noun) }
        if let leadIn { return Lexicon.trimmedSentence(leadIn) }
        return fallback.prefix(3).joined(separator: ", ")
    }

    private static func subjectOf(title: String) -> String? {
        let head = title.split(separator: ":", maxSplits: 1).first.map(String.init) ?? title
        let words = head.split(separator: " ")
        guard !words.isEmpty, words.count <= 4 else { return nil }
        return head.trimmingCharacters(in: .whitespaces)
    }

    /// The content word the page repeats most, as written the first time: the subject when there is no title.
    private static func mostFrequentNoun(_ texts: [String]) -> String? {
        var counts: [String: Int] = [:]
        var firstSpelling: [String: String] = [:]
        for text in texts {
            let chars = Array(text)
            for token in Lexicon.tokens(text) where token.isContent && !token.isNumber && token.word.count >= 4 {
                counts[token.stem, default: 0] += 1
                if firstSpelling[token.stem] == nil {
                    firstSpelling[token.stem] = String(chars[token.range])
                }
            }
        }
        guard let best = counts.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }), best.value >= 3 else {
            return nil
        }
        return firstSpelling[best.key].map(Lexicon.capitalizedFirst)
    }

    // MARK: Sentences

    /// Joins a paragraph's lines and cuts it into sentences, each with the lines it spans.
    private static func sentenceUnits(_ lines: [(id: String, text: String)]) -> [Unit] {
        var text = ""
        var spans: [(id: String, range: Range<Int>)] = []
        for line in lines {
            if !text.isEmpty {
                if text.hasSuffix("-"), let first = line.text.first, first.isLowercase { text.removeLast() } else { text += " " }
            }
            let start = text.count
            text += line.text
            spans.append((line.id, start..<text.count))
        }
        var pieces: [(text: String, lower: Int, upper: Int)] = []
        let chars = Array(text)
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences]) { sub, range, _, _ in
            guard let sentence = sub?.trimmingCharacters(in: .whitespacesAndNewlines), sentence.count > 2 else { return }
            let lower = text.distance(from: text.startIndex, to: range.lowerBound)
            let upper = min(chars.count, text.distance(from: text.startIndex, to: range.upperBound))
            // "Edsger W." / "Dijkstra in 1956 …", "Paul v." / "Chicago and Northwestern …": one sentence the splitter cut after a
            // name's abbreviation.
            if let last = pieces.last, cutsAName(last.text), continuesAName(sentence) {
                pieces[pieces.count - 1] = (last.text + " " + sentence, last.lower, upper)
            } else {
                pieces.append((sentence, lower, upper))
            }
        }
        return pieces.map { piece in
            let ids = spans.filter { $0.range.overlaps(piece.lower..<max(piece.lower + 1, piece.upper)) }.map(\.id)
            return Unit(text: piece.text, lineIDs: ids)
        }
    }

    // MARK: Definitions

    /// "Key term: Cytokinesis - the division of the cytoplasm." and "Diffusion: particles move from high to low
    /// concentration."
    static func lineDefinition(_ text: String) -> (term: String, meaning: String)? {
        if let m = text.firstMatch(of: #/^(?i:key\s+terms?|term|definition|vocab(?:ulary)?|define)\s*:\s*(?<term>[^:–—]+?)\s+[-–—:]\s+(?<meaning>.+)$/#) {
            let meaning = Lexicon.trimmedSentence(String(m.meaning))
            guard !meaning.isEmpty else { return nil }
            return (String(m.term).trimmingCharacters(in: .whitespaces), meaning)
        }
        if let m = text.firstMatch(of: #/^(?<term>[A-Z][\w'’\- ]{1,40}?)\s*(?::|\s[-–—])\s+(?<meaning>.+)$/#) {
            let term = String(m.term).trimmingCharacters(in: .whitespaces)
            let meaning = Lexicon.trimmedSentence(String(m.meaning))
            let termWords = term.split(separator: " ").count
            let meaningWords = meaning.split(separator: " ").count
            guard termWords <= 4, meaningWords >= 3 else { return nil }
            // "Short version: …", "Note: …", "Quick check: …" introduce text; they don't define a term.
            let discourse: Set<String> = ["short version", "in short", "note", "notes", "tip", "example", "for example",
                                          "remember", "quick check", "answer", "hint", "summary", "important",
                                          "warning", "reminder", "question", "fun fact", "why", "how", "what",
                                          "step", "steps", "source", "page", "chapter", "unit", "lesson"]
            if discourse.contains(Lexicon.fold(term)) || Lexicon.fold(term).hasPrefix("step ") { return nil }
            guard meaning.first?.isLowercase == true || text.hasSuffix(".") else { return nil }
            return (term, meaning)
        }
        return nil
    }

    private static func clozeFromLineDefinition(term: String, meaning: String) -> String {
        let lower = meaning.lowercased()
        let joiner = (lower.hasPrefix("the ") || lower.hasPrefix("a ") || lower.hasPrefix("an ")) ? " is " : ": "
        return "{{\(term)}}\(joiner)\(meaning)."
    }

    private static let pronounSubjects: Set<String> = [
        "it", "this", "that", "these", "those", "they", "there", "here", "each", "every", "one", "which", "what",
        "who", "he", "she", "we", "you", "i", "its", "their", "our", "his", "her", "all", "some", "most", "many",
        "such", "both", "another", "other", "the result", "the answer",
    ]

    /// "Mitosis is the process by which …" → ("Mitosis", "the process by which …"), with the cloze
    /// "{{Mitosis}} is the process by which …". Also "X means Y", "X refers to Y" and "Y is called X".
    static func sentenceDefinition(_ sentence: String) -> (term: String, meaning: String, cloze: String)? {
        let s = sentence.trimmingCharacters(in: .whitespaces)
        if let m = s.firstMatch(of: #/^(?:(?<qual>(?:In|For|During|At|Within|Among|Inside)\s[^,]{2,40}),\s+)?(?<term>[A-Za-z][\w\-'’]*(?:\s[\w\-'’]+){0,4}?)\s+(?:is|are)\s+(?<meaning>(?:a|an|the)\s.+?)\.?$/#) {
            // "The nuclear envelope is …": the blank and the card are "nuclear envelope", without the article.
            var termStart = m.term.startIndex
            if let article = m.term.firstMatch(of: #/^(?i:the|a|an)\s+/#) { termStart = article.range.upperBound }
            let term = String(s[termStart..<m.term.endIndex])
            guard acceptableTerm(term) else { return nil }
            let meaning = Lexicon.trimmedSentence(String(m.meaning))
            guard meaning.split(separator: " ").count >= 3 else { return nil }
            var cloze = s
            cloze.replaceSubrange(termStart..<m.term.endIndex, with: "{{\(term)}}")
            return (Lexicon.capitalizedFirst(term), meaning, ensurePeriod(cloze))
        }
        if let m = s.firstMatch(of: #/^(?<term>[A-Z][\w\-'’]*(?:\s[\w\-'’]+){0,4}?)\s+(?:means|refers to|is defined as)\s+(?<meaning>.+?)\.?$/#) {
            let term = String(m.term)
            guard acceptableTerm(term) else { return nil }
            var cloze = s
            cloze.replaceSubrange(m.term.startIndex..<m.term.endIndex, with: "{{\(term)}}")
            return (term, Lexicon.trimmedSentence(String(m.meaning)), ensurePeriod(cloze))
        }
        if let m = s.firstMatch(of: #/^(?<meaning>[A-Z].{8,120}?)\s+(?:is|are)\s+(?:called|known as)\s+(?<term>[\w\-'’]+(?:\s[\w\-'’]+){0,3}?)\.?$/#) {
            let term = String(m.term)
            guard acceptableTerm(term) else { return nil }
            var cloze = s
            cloze.replaceSubrange(m.term.startIndex..<m.term.endIndex, with: "{{\(term)}}")
            return (Lexicon.capitalizedFirst(term), Lexicon.trimmedSentence(String(m.meaning)), ensurePeriod(cloze))
        }
        return nil
    }

    private static func acceptableTerm(_ term: String) -> Bool {
        let folded = Lexicon.fold(term)
        let firstWord = folded.split(separator: " ").first.map(String.init) ?? folded
        if pronounSubjects.contains(firstWord) || pronounSubjects.contains(folded) { return false }
        return !Lexicon.contentStems(term).isEmpty
    }

    private static func ensurePeriod(_ s: String) -> String {
        guard let last = s.last else { return s }
        return ".?!".contains(last) ? s : s + "."
    }
}
