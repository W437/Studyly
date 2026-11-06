import Foundation

// The pure text work behind the tutor screens: starters drawn from the person's material, the quick-check question
// at the end of Cap's answer, the small Markdown Cap writes (bold, lists, small tables), and what to offer after a
// request Cap declines. No SwiftUI, no store: tested in `AskTextTests`.

// MARK: - Starters

/// Questions to start an empty chat with, drawn from the material Cap can read: a mix-up the person keeps making,
/// questions the pages ask themselves, terms the pages define, the steps of a sequence, the terms on the front of an
/// imported deck's cards. Each one is kept only when the retriever finds it covered (the same rule the offline tutor
/// uses), so a starter never gets "your notes don't cover that".
enum AskStarters {
    static func make(material: [TutorMaterial], confusions: [String], limit: Int = 3) -> [String] {
        guard limit > 0 else { return [] }
        var byKind: [[String]] = [[], [], [], [], []]
        for name in confusions {
            if let question = differenceQuestion(name) { byKind[0].append(question) }
        }
        for source in material {
            for card in source.cards {
                if let question = cardQuestion(card) { byKind[4].append(question) }
            }
            for page in source.pages {
                let structure = PageStructure.read(page.lines)
                for section in structure.sections where section.isQuestion {
                    if let heading = section.heading?.text, (3...10).contains(heading.split(separator: " ").count) {
                        byKind[1].append(heading)
                    }
                }
                for definition in structure.definitions where definition.term.split(separator: " ").count <= 3 {
                    byKind[2].append("What is \(lowerFirst(definition.term))?")
                }
                for group in structure.groups where group.isSequence {
                    for sibling in group.siblings where !sibling.bullets.isEmpty {
                        byKind[3].append("What happens in \(lowerFirst(sibling.name.text))?")
                    }
                }
            }
        }
        let retriever = LocalRetriever(material: material)
        var seen = Set<String>()
        var picked: [String] = []
        // One of each kind first, then the rest in the same order.
        var cursors = Array(repeating: 0, count: byKind.count)
        var progressed = true
        while picked.count < limit, progressed {
            progressed = false
            for kind in byKind.indices where picked.count < limit {
                while cursors[kind] < byKind[kind].count {
                    let candidate = byKind[kind][cursors[kind]]
                    cursors[kind] += 1
                    let key = Lexicon.normalizedAnswer(candidate)
                    guard !key.isEmpty, !seen.contains(key) else { continue }
                    seen.insert(key)
                    if isCovered(candidate, by: retriever) {
                        picked.append(candidate)
                        progressed = true
                        break
                    }
                }
            }
        }
        return picked
    }

    /// The notes cover the question the way the offline tutor counts it.
    static func isCovered(_ question: String, by retriever: LocalRetriever) -> Bool {
        guard let best = retriever.search(question, limit: 4).first else { return false }
        return best.coverage >= LocalTutor.minimumCoverage || best.matched.count >= 2
    }

    /// A card whose front is a term ("Krebs cycle") → "What is the Krebs cycle?"-style question; a front that is a question is
    /// asked as it is. Nil for a front that is neither (a sentence, a formula, a few words too many).
    static func cardQuestion(_ card: TutorCard) -> String? {
        let front = card.front.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let count = front.split(separator: " ").count
        if front.hasSuffix("?") { return (3...12).contains(count) ? front : nil }
        guard (1...4).contains(count), front.contains(where: \.isLetter), !front.contains("{{"),
              !front.hasSuffix("."), !front.hasSuffix(":") else { return nil }
        return "What is \(lowerFirst(front))?"
    }

    /// "Anaphase vs telophase" → "What's the difference between anaphase and telophase?"
    static func differenceQuestion(_ name: String) -> String? {
        let parts = sides(of: name)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return "What's the difference between \(lowerFirst(parts[0])) and \(lowerFirst(parts[1]))?"
    }

    /// A starter as a chip says it: "What's the difference between anaphase and telophase?" → "Anaphase vs telophase?". Any other question
    /// is short enough as it is.
    static func chipLabel(_ question: String) -> String {
        let lead = "What's the difference between "
        guard question.hasPrefix(lead), question.hasSuffix("?") else { return question }
        let parts = question.dropFirst(lead.count).dropLast().components(separatedBy: " and ")
        guard parts.count == 2 else { return question }
        return Lexicon.capitalizedFirst(parts[0]) + " vs " + parts[1] + "?"
    }

    /// "A vs B", "A vs. B", "A versus B" → its two sides.
    static func sides(of name: String) -> [String] {
        for separator in [" vs. ", " vs ", " versus ", " VS "] {
            let parts = name.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { return parts }
        }
        return [name]
    }

    /// Lowercases the first letter unless the word looks like an acronym ("DNA").
    static func lowerFirst(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let first = t.first, first.isUppercase else { return t }
        let second = t.dropFirst().first
        if let second, second.isUppercase { return t }
        return first.lowercased() + t.dropFirst()
    }
}

// MARK: - The dock's chips

/// The one row of chips over the composer in an empty chat: what Cap can make, as first words for the composer, around up to two
/// questions drawn from the notes. Without the assistant: a quiz and the questions.
enum AskDockChips {
    enum Action: Equatable, Sendable {
        /// Put these words in the composer to be finished.
        case compose(String)
        /// Ask this question.
        case ask(String)
        /// A practice session.
        case quiz
    }

    struct Chip: Equatable, Identifiable, Sendable {
        var title: String
        var icon: String
        var action: Action
        var id: String { title }
        var isQuestion: Bool { if case .ask = action { true } else { false } }
    }

    static func make(quickStarts: [AssistantQuickStart.Start], starters: [String]) -> [Chip] {
        func start(_ kind: AssistantQuickStart.Kind) -> Chip? {
            quickStarts.first { $0.kind == kind }.map { Chip(title: $0.title, icon: $0.icon, action: .compose($0.prefix)) }
        }
        func questions(_ limit: Int) -> [Chip] {
            starters.prefix(limit).map { Chip(title: AskStarters.chipLabel($0), icon: "text.bubble", action: .ask($0)) }
        }
        guard !quickStarts.isEmpty else {
            return [Chip(title: String(localized: "Quiz me"), icon: "checklist", action: .quiz)] + questions(3)
        }
        return [start(.quiz), start(.cards)].compactMap { $0 } + questions(2)
            + [start(.note), start(.exam), start(.research)].compactMap { $0 }
    }
}

// MARK: - Quick check

/// The question Cap ends an answer with ("Quick check: which one happens first?"), split from the rest so it can be
/// answered inline. `options` are short choices when the question lists them ("2, 4 or 8?"), or, for a "which"
/// question in a chat about two things ("the difference between mitosis and cytokinesis"), those two.
struct QuickCheck: Equatable, Sendable {
    /// The answer's text before the question (may be empty: the whole answer is the question).
    var lead: String
    /// The question, without its "Quick check" label.
    var question: String
    var options: [String]
    /// Cap called it a quick check.
    var isLabelled: Bool

    /// Nil when the answer doesn't end with a question.
    static func split(_ text: String, chatContext: String = "") -> QuickCheck? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("?") else { return nil }
        // The last line; a question inside a table or list isn't a quick check.
        let lines = trimmed.components(separatedBy: "\n")
        guard let lastLine = lines.last?.trimmingCharacters(in: .whitespaces), !lastLine.hasPrefix("|"),
              !lastLine.hasPrefix("-"), !lastLine.hasPrefix("*") else { return nil }
        let before = lines.dropLast().joined(separator: "\n")
        var lead: String
        var question: String
        if let label = lastLine.range(of: #"(?i)quick check\b"#, options: .regularExpression) {
            lead = String(lastLine[..<label.lowerBound])
            question = String(lastLine[label.lowerBound...])
        } else {
            let sentences = Lexicon.sentences(lastLine)
            guard let last = sentences.last, last.hasSuffix("?"), let range = lastLine.range(of: last, options: .backwards) else {
                return nil
            }
            lead = String(lastLine[..<range.lowerBound])
            question = last
        }
        lead = (before.isEmpty ? lead : before + "\n" + lead).trimmingCharacters(in: .whitespacesAndNewlines)
        // The label: "Quick check:", "Quick check before we go on:".
        var labelled = false
        if let label = question.range(of: #"^(?i)quick check[^:?]{0,30}[:,.—–-]\s*"#, options: .regularExpression) {
            question.removeSubrange(label)
            labelled = true
        }
        question = Lexicon.capitalizedFirst(question.trimmingCharacters(in: .whitespaces))
        guard question.count > 1 else { return nil }
        var options: [String] = []
        if let listed = listedOptions(in: question) {
            // The options become buttons, so the question no longer lists them: "…end with: 2, 4 or 8?" → "…end with?"
            options = listed.options
            question = listed.prompt
        } else if question.lowercased().hasPrefix("which") {
            options = pair(in: chatContext)
        }
        return QuickCheck(lead: lead, question: question, options: options, isLabelled: labelled)
    }

    /// "…end with: 2, 4 or 8?" → ["2", "4", "8"] and "…end with?"; "Which happens first, mitosis or cytokinesis?" →
    /// ["Mitosis", "Cytokinesis"] and "Which happens first?". Nil when the question doesn't list two to four short
    /// options.
    static func listedOptions(in question: String) -> (options: [String], prompt: String)? {
        let trimmed = question.trimmingCharacters(in: CharacterSet(charactersIn: "?").union(.whitespaces))
        let bodyStart = trimmed.lastIndex(of: ":").map { trimmed.index(after: $0) } ?? trimmed.startIndex
        let body = trimmed[bodyStart...]
        guard let or = body.range(of: " or ", options: .backwards) else { return nil }
        let last = body[or.upperBound...].trimmingCharacters(in: .whitespaces)
        let parts = body[..<or.lowerBound].components(separatedBy: ",")
        let questionWords: Set<String> = ["which", "what", "how", "when", "where", "who", "why", "is", "are", "does",
                                          "do", "can", "will", "would", "should"]
        var options: [String] = []
        for part in parts.reversed() {
            let item = part.trimmingCharacters(in: .whitespaces)
            let words = item.split(separator: " ")
            guard !item.isEmpty, words.count <= 3,
                  !questionWords.contains(words.first.map { $0.lowercased() } ?? "") else { break }
            options.insert(item, at: 0)
        }
        guard !options.isEmpty, !last.isEmpty, last.split(separator: " ").count <= 3 else { return nil }
        options.append(last)
        guard (2...4).contains(options.count) else { return nil }
        // Where the list starts: after the parts that weren't options, and their commas.
        let dropped = parts.count - (options.count - 1)
        let offset = parts.prefix(dropped).reduce(0) { $0 + $1.count } + dropped
        let listStart = body.index(body.startIndex, offsetBy: min(offset, body.count))
        var prompt = String(trimmed[..<listStart]).trimmingCharacters(in: CharacterSet(charactersIn: " ,:;—–-"))
        guard prompt.split(separator: " ").count >= 2 else { return nil }
        prompt += "?"
        return (options.map { Lexicon.capitalizedFirst($0) }, prompt)
    }

    /// The two things a chat compares: "the difference between X and Y", "X vs Y", "X or Y".
    static func pair(in text: String) -> [String] {
        let patterns = [#"(?i)difference between ([\w\s-]{2,30}?) and ([\w\s-]{2,30}?)(?:[?.!,]|$)"#,
                        #"(?i)\b([\w-]{3,30}) (?:vs\.?|versus) ([\w-]{3,30})"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let a = Range(match.range(at: 1), in: text), let b = Range(match.range(at: 2), in: text) else { continue }
            let first = text[a].trimmingCharacters(in: .whitespaces)
            let second = text[b].trimmingCharacters(in: .whitespaces)
            guard !first.isEmpty, !second.isEmpty, first.lowercased() != second.lowercased() else { continue }
            return [Lexicon.capitalizedFirst(first), Lexicon.capitalizedFirst(second)]
        }
        return []
    }
}

// MARK: - Markdown

/// The Markdown Cap writes, as blocks: paragraphs (with **bold** and *italic* inline), bullet and numbered lists, and
/// small pipe tables. Tolerant of half-arrived text: a table row that's still streaming is a row with fewer cells.
enum CapMarkdown {
    enum Block: Equatable, Sendable {
        case paragraph(String)
        case heading(String)
        case bullets([String])
        case numbered([String])
        case table(header: [String]?, rows: [[String]])
    }

    static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbered: [String] = []
        var tableRows: [[String]] = []
        var tableHeader: [String]?

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
        }
        func flushLists() {
            if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
            if !numbered.isEmpty { blocks.append(.numbered(numbered)); numbered = [] }
        }
        func flushTable() {
            if !tableRows.isEmpty || tableHeader != nil { blocks.append(.table(header: tableHeader, rows: tableRows)) }
            tableRows = []
            tableHeader = nil
        }
        func flushAll() { flushParagraph(); flushLists(); flushTable() }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flushAll(); continue }
            if line.hasPrefix("|") {
                flushParagraph(); flushLists()
                let cells = tableCells(line)
                if cells.allSatisfy(isSeparatorCell), !cells.isEmpty {
                    // The row before the separator is the header.
                    if tableHeader == nil, let last = tableRows.popLast() { tableHeader = last }
                } else {
                    tableRows.append(cells)
                }
                continue
            }
            flushTable()
            if let item = bulletItem(line) {
                flushParagraph()
                if !numbered.isEmpty { blocks.append(.numbered(numbered)); numbered = [] }
                bullets.append(item)
            } else if let item = numberedItem(line) {
                flushParagraph()
                if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
                numbered.append(item)
            } else if line.hasPrefix("#") {
                flushAll()
                let heading = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty { blocks.append(.heading(heading)) }
            } else {
                flushLists()
                paragraph.append(line)
            }
        }
        flushAll()
        return blocks
    }

    static func tableCells(_ line: String) -> [String] {
        var parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.first?.isEmpty == true { parts.removeFirst() }
        if parts.last?.isEmpty == true, line.hasSuffix("|") { parts.removeLast() }
        return parts
    }

    private static func isSeparatorCell(_ cell: String) -> Bool {
        let core = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return core.count >= 2 && core.allSatisfy { $0 == "-" }
    }

    private static func bulletItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numberedItem(_ line: String) -> String? {
        guard let match = line.range(of: #"^\d{1,2}[.)]\s+"#, options: .regularExpression) else { return nil }
        return String(line[match.upperBound...])
    }

    /// Inline Markdown (bold, italic, code) as an attributed string. A `**` still waiting for its partner (the
    /// answer is streaming) is left out rather than shown.
    static func inline(_ text: String) -> AttributedString {
        var source = text
        if source.components(separatedBy: "**").count % 2 == 0, let last = source.range(of: "**", options: .backwards) {
            source.removeSubrange(last)
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }

    /// The text without Markdown marks, for VoiceOver and read-aloud: tables read row by row.
    static func plain(_ text: String) -> String {
        blocks(text).map { block -> String in
            switch block {
            case .paragraph(let t), .heading(let t): return String(inline(t).characters)
            case .bullets(let items), .numbered(let items): return items.map { String(inline($0).characters) }.joined(separator: ". ")
            case .table(let header, let rows):
                return rows.map { row in
                    row.enumerated().map { i, cell in
                        let name = header.flatMap { i < $0.count ? $0[i] : nil } ?? ""
                        let value = String(inline(cell).characters)
                        return name.isEmpty ? value : "\(String(inline(name).characters)): \(value)"
                    }.joined(separator: ", ")
                }.joined(separator: ". ")
            }
        }.joined(separator: "\n")
    }
}

// MARK: - After a declined request

/// What Cap offers instead of writing an essay, doing an exam or "humanizing" text: to explain the topic from the notes, or to
/// quiz the person on it. The topic is one the student's own material has (a topic of the course, or what a source is about),
/// found by the words of the request that aren't the request ("write my essay on mitosis" → "Mitosis"). A request that names
/// none gets the plain offers ("Explain the key ideas", "Quiz me on my notes"), never words picked out of the sentence.
enum AskPolicy {
    /// The words of a request that say what is being asked for, not what it is about.
    private static let requestStems: Set<String> = Set([
        "write", "writing", "rewrite", "make", "sound", "seem", "look", "more", "human", "humanize", "humanise", "humanizer",
        "humaniser", "wrote", "paragraph", "text", "please", "essay", "paper", "report", "assignment", "coursework", "homework",
        "whole", "full", "entire", "bypass", "beat", "avoid", "get", "past", "fool", "detector", "detection", "turnitin", "gptzero",
        "undetectable", "help", "words", "word", "page", "pages", "do", "give", "answers", "answer", "exam", "test", "quiz", "midterm",
        "final", "finals", "problems", "problem", "just", "lab", "submit", "turn", "hand", "cheat", "take", "online", "solve", "finish",
        "complete", "worksheet", "hw", "irac", "thesis", "dissertation", "reflection", "draft", "compose", "generate", "produce",
    ].map(Lexicon.stem))

    /// The topic the declined request is about: the name, among `names`, that shares the most words with it; nil when none shares
    /// one.
    static func topic(ofRefused question: String, among names: [String]) -> String? {
        let asked = Set(Lexicon.contentStems(question)).subtracting(requestStems)
        guard !asked.isEmpty else { return nil }
        var best: (name: String, shared: Int)?
        for name in names {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let shared = Set(Lexicon.contentStems(clean)).subtracting(requestStems).intersection(asked).count
            if shared > (best?.shared ?? 0) { best = (clean, shared) }
        }
        return best?.name
    }

    /// What a source's title is about, as names to offer: "Lecture 6: Cell division" → "Cell division" and "Lecture 6", "Federalist
    /// No. 10 (Madison, 1787)" → itself, an imported deck's " (Quizlet)" left off.
    static func names(inTitle title: String) -> [String] {
        var clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tag = clean.range(of: #"\s*\((quizlet|anki|csv)\)$"#, options: [.regularExpression, .caseInsensitive]) {
            clean.removeSubrange(tag)
        }
        guard let colon = clean.firstIndex(of: ":") else { return clean.isEmpty ? [] : [clean] }
        let before = String(clean[..<colon]).trimmingCharacters(in: .whitespaces)
        let after = String(clean[clean.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return [after, before].filter { !$0.isEmpty }
    }
}
