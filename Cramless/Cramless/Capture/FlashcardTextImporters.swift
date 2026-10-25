import Foundation

/// A Quizlet set exported as text (Quizlet: … → Export → Copy text). Quizlet lets the person pick both
/// separators, so they're detected: between term and definition a tab (the default), a comma, or " - "; between
/// cards a new line (the default) or a semicolon. Lines with no separator are joined to the card above (a
/// definition that ran over two lines).
enum QuizletImporter {
    struct Separators: Hashable, Sendable {
        var term: String
        var card: String

        var description: String {
            let term = switch self.term {
            case "\t": "Tab"
            case ",": "Comma"
            default: "\"\(self.term.trimmingCharacters(in: .whitespaces))\""
            }
            return "\(term) between term and definition, \(card == "\n" ? "one card per line" : "cards split by semicolons")"
        }
    }

    static let termSeparators = ["\t", " - ", " – ", " — ", ","]

    static func preview(_ text: String, title: String) throws -> ImportPreview {
        let trimmed = TextPaginator.normalized(text)
        guard !trimmed.isEmpty else { throw CaptureError.noCards("Paste the text Quizlet exported to see your cards here.") }
        if trimmed.range(of: #"^https?://\S*quizlet\.com"#, options: [.regularExpression, .caseInsensitive]) != nil
            || (trimmed.lowercased().contains("quizlet.com/") && !trimmed.contains("\n")) {
            throw CaptureError.quizletLink
        }
        guard let separators = detect(trimmed) else {
            throw CaptureError.noCards("Couldn't find a term and a definition on each line. In Quizlet's export, keep Tab between term and definition and New line between rows.")
        }
        return parse(trimmed, separators: separators, title: title.isEmpty ? "Quizlet set" : title)
    }

    /// The separators that split the most rows in two. Between terms and definitions, ties go to the more specific
    /// separator (tab before " - " before comma), since definitions are full of commas. Cards are one per line
    /// unless semicolons split the text into at least twice as many rows that nearly all hold a term separator
    /// (Quizlet's semicolon export puts every card on one line).
    static func detect(_ text: String) -> Separators? {
        func best(card: String) -> (term: String, coverage: Double, rows: Int)? {
            let rows = rows(text, card: card)
            guard !rows.isEmpty else { return nil }
            var result: (term: String, coverage: Double, rows: Int)?
            for term in termSeparators {
                let coverage = Double(rows.filter { $0.contains(term) }.count) / Double(rows.count)
                if coverage > (result?.coverage ?? 0) { result = (term, coverage, rows.count) }
            }
            return result
        }
        let lines = best(card: "\n")
        let semicolons = best(card: ";")
        if let semicolons, semicolons.rows >= 2, semicolons.coverage >= 0.9, semicolons.rows >= 2 * (lines?.rows ?? 0) {
            return Separators(term: semicolons.term, card: ";")
        }
        if let lines, lines.coverage >= 0.5 { return Separators(term: lines.term, card: "\n") }
        if let semicolons, semicolons.rows >= 2, semicolons.coverage >= 0.5 { return Separators(term: semicolons.term, card: ";") }
        return nil
    }

    static func parse(_ text: String, separators: Separators, title: String) -> ImportPreview {
        var cards: [ImportedCard] = []
        var joined = 0
        var skipped = 0
        for row in rows(text, card: separators.card) {
            if let range = row.range(of: separators.term) {
                let term = row[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let definition = row[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if term.isEmpty || definition.isEmpty { skipped += 1; continue }
                cards.append(ImportedCard(front: term, back: definition, topic: title))
            } else if separators.card == "\n", !cards.isEmpty {
                cards[cards.count - 1].back += "\n" + row.trimmingCharacters(in: .whitespaces)
                joined += 1
            } else {
                skipped += 1
            }
        }
        var warnings: [String] = []
        if joined > 0 { warnings.append("\(joined) \(joined == 1 ? "line had" : "lines had") no separator and \(joined == 1 ? "was" : "were") added to the definition above.") }
        if skipped > 0 { warnings.append("\(skipped) \(skipped == 1 ? "row was" : "rows were") missing a term or a definition and left out.") }
        return ImportPreview(format: .quizlet, title: title, cards: cards, summary: separators.description, warnings: warnings)
    }

    /// Rows trimmed of spaces and line breaks but not tabs: "metaphase<TAB>" is a term with an empty definition,
    /// not a line without a separator.
    private static func rows(_ text: String, card: String) -> [String] {
        let edges = CharacterSet(charactersIn: " \r\n\u{00A0}")
        return text.components(separatedBy: card)
            .map { $0.trimmingCharacters(in: edges) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// Flashcards as CSV (or TSV, or semicolon-separated from a European Excel): RFC 4180 quoting (quoted fields may
/// hold the delimiter, doubled quotes and line breaks), the delimiter detected, and a header row recognised by its
/// column names. Without a header, the first column is the front and the second the back.
enum CSVImporter {
    enum Column: Equatable { case front, back, extra, topic }

    static let headerNames: [Column: Set<String>] = [
        .front: ["front", "term", "question", "prompt", "word", "side 1", "side a", "q", "front side", "card front",
                 "concept", "vocab", "vocabulary", "kanji"],
        .back: ["back", "definition", "answer", "meaning", "side 2", "side b", "a", "back side", "card back",
                "translation", "explanation of term", "reading"],
        .extra: ["notes", "note", "extra", "explanation", "hint", "example", "examples", "comment", "comments", "context"],
        .topic: ["topic", "deck", "category", "chapter", "unit", "section", "tag", "tags", "subject", "lesson"],
    ]

    static func preview(_ text: String, title: String) throws -> ImportPreview {
        var body = TextPaginator.normalized(text)
        guard !body.isEmpty else { throw CaptureError.noCards("This file is empty.") }
        var delimiter: Character
        // Excel's "sep=;" first line names the delimiter.
        if body.lowercased().hasPrefix("sep="), let first = body.split(separator: "\n", maxSplits: 1).first, first.count == 5 {
            delimiter = first.last!
            body = String(body.dropFirst(first.count)).trimmingCharacters(in: .newlines)
        } else {
            delimiter = detectDelimiter(body)
        }
        var table = rows(body, delimiter: delimiter).filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard !table.isEmpty else { throw CaptureError.noCards("This file is empty.") }
        var columns: [Column?] = []
        var hasHeader = false
        if let mapping = headerMapping(table[0]) {
            columns = mapping
            hasHeader = true
            table.removeFirst()
        } else {
            columns = [.front, .back]
        }
        guard let front = columns.firstIndex(of: .front), let back = columns.firstIndex(of: .back) else {
            throw CaptureError.noCards("Couldn't tell which column is the front of each card. Name the columns Front and Back.")
        }
        var cards: [ImportedCard] = []
        var skipped = 0
        for row in table {
            func cell(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let f = cell(front), b = cell(back)
            guard !f.isEmpty, !b.isEmpty else { skipped += 1; continue }
            let extra = columns.indices.filter { columns[$0] == .extra }.map(cell).filter { !$0.isEmpty }.joined(separator: "\n")
            let topic = cell(columns.firstIndex(of: .topic))
            cards.append(ImportedCard(front: f, back: b, explanation: extra, topic: topic.isEmpty ? title : topic))
        }
        guard !cards.isEmpty else { throw CaptureError.noCards("Couldn't find any rows with both a front and a back.") }
        var warnings: [String] = []
        if skipped > 0 { warnings.append("\(skipped) \(skipped == 1 ? "row was" : "rows were") missing a front or a back and left out.") }
        let name = switch delimiter {
        case "\t": "Tab-separated"
        case ";": "Semicolon-separated"
        default: "Comma-separated"
        }
        let summary = "\(name), \(hasHeader ? "with a header row" : "first column front, second back")"
        return ImportPreview(format: .csv, title: title.isEmpty ? "Imported cards" : title, cards: cards, summary: summary,
                             warnings: warnings)
    }

    /// Whether the first row names a front and a back column (so pasted text with a header reads as CSV).
    static func hasKnownHeader(_ text: String) -> Bool {
        let body = TextPaginator.normalized(text)
        guard let first = rows(String(body.prefix(2000)), delimiter: detectDelimiter(body)).first,
              let mapping = headerMapping(first) else { return false }
        return mapping.contains(.front) && mapping.contains(.back)
    }

    /// Column headers that are language names ("English, Spanish"): a vocabulary list's header, front then back.
    static let languageNames: Set<String> = [
        "english", "spanish", "french", "german", "italian", "portuguese", "chinese", "mandarin", "japanese", "korean",
        "arabic", "hebrew", "russian", "latin", "greek", "dutch", "swedish", "polish", "turkish", "hindi",
        "español", "inglés", "français", "anglais", "deutsch", "englisch", "italiano", "português", "עברית", "אנגלית",
    ]

    /// Column roles from a header row; nil unless it names a front or a back.
    static func headerMapping(_ row: [String]) -> [Column?]? {
        let names = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let filled = names.filter { !$0.isEmpty }
        if filled.count >= 2, filled.allSatisfy(languageNames.contains) {
            return names.enumerated().map { $0.offset == 0 ? .front : ($0.offset == 1 ? .back : nil) }
        }
        var columns: [Column?] = names.map { name in headerNames.first { $0.value.contains(name) }?.key }
        let hasFront = columns.contains(.front), hasBack = columns.contains(.back)
        guard hasFront || hasBack else { return nil }
        // A header that names only one side: the next unnamed column is the other.
        if hasFront, !hasBack, let f = columns.firstIndex(of: .front), let i = columns.indices.first(where: { $0 > f && columns[$0] == nil }) {
            columns[i] = .back
        }
        if hasBack, !hasFront, let i = columns.indices.first(where: { columns[$0] == nil }) {
            columns[i] = .front
        }
        return columns
    }

    /// The delimiter that splits the first rows most consistently, outside quotes: tab, semicolon or comma. Tabs
    /// get a head start: they almost never appear inside a card, while commas and semicolons do.
    static func detectDelimiter(_ text: String) -> Character {
        let sample = String(text.prefix(4000))
        var best: (delimiter: Character, score: Double) = (",", -1)
        for (delimiter, bonus) in [("\t", 2.0), (";", 0), (",", 0.5)] as [(Character, Double)] {
            let counts = rows(sample, delimiter: delimiter).prefix(20).map { $0.count }
            guard let first = counts.first, first > 1 else { continue }
            let consistent = Double(counts.filter { $0 == first }.count) / Double(counts.count)
            let score = consistent * 10 + Double(min(first, 6)) + bonus
            if score > best.score { best = (delimiter, score) }
        }
        return best.delimiter
    }

    /// RFC 4180 rows: quoted fields may contain the delimiter, line breaks and doubled quotes.
    static func rows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending: Character? = nil
        func next() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }
        while let c = next() {
            if quoted {
                if c == "\"" {
                    if let following = next() {
                        if following == "\"" { field.append("\"") } else { quoted = false; pending = following }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && field.trimmingCharacters(in: .whitespaces).isEmpty {
                field = ""
                quoted = true
            } else if c == delimiter {
                row.append(field)
                field = ""
            } else if c == "\n" || c == "\r\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
