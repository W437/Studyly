import Foundation

/// The text the offline question writer reads: the pages with what is not the lesson taken out. A copied web page, a printout or a
/// PDF with no layout brings the page's furniture along (a running header on every page, "8/9", a date and time), its pictures'
/// captions, a program listing with line numbers, footnote numbers, pronunciation guides, citations in parentheses and, at the end,
/// the list of references. Questions written from those were the commonest kind of junk the blind reviewers found ("Describe 17
/// prev[v] ← u", a blank inside a bibliography entry, "Filled nodes").
///
/// Every line keeps its id, so anchors stay real: a line that loses all its text is dropped, and one that loses a part keeps the rest.
/// Nothing here changes what the person's source says; it only decides what the question writer may ask about. Pure and
/// deterministic.
enum SourceHygiene {

    /// `pages` with the back matter cut, the furniture, captions and listings dropped, and the markers and citations taken out of the
    /// lines that remain.
    static func prepare(_ pages: [PageText]) -> [PageText] {
        struct Entry { var page: Int; var line: TextLine }
        var entries: [Entry] = []
        for (p, page) in pages.enumerated() { for line in page.lines { entries.append(Entry(page: p, line: line)) } }
        guard !entries.isEmpty else { return pages }

        let back = backMatter(in: entries.map(\.line.text))
        entries = entries.enumerated().filter { !back.contains($0.offset) }.map(\.element)
        // "…applied.[" / "12][13][14]": the line splitter cut a footnote number after its bracket. The pieces go back together (before the
        // second one is taken for page furniture and dropped, which would leave the bracket behind).
        var k = 0
        var joined: [Entry] = []
        while k < entries.count {
            var entry = entries[k]
            while k + 1 < entries.count, entry.line.text.hasSuffix("["), entries[k + 1].page == entry.page, splitMarkerTail.matches(entries[k + 1].line.text) {
                entry.line.text += entries[k + 1].line.text
                k += 1
            }
            joined.append(entry)
            k += 1
        }
        entries = joined
        let texts = entries.map(\.line.text)
        var drop = [Bool](repeating: false, count: texts.count)
        markFigureBlocks(texts, &drop)
        markListings(texts, &drop)
        markRepeats(texts, &drop)
        for (i, text) in texts.enumerated() where isFurniture(text) { drop[i] = true }

        var cleaned: [[TextLine]] = Array(repeating: [], count: pages.count)
        for (i, entry) in entries.enumerated() where !drop[i] {
            var line = entry.line
            // A sentence that introduced a listing or a figure ("… in pseudocode:") ends where the listing was, not in the next paragraph.
            if i + 1 < drop.count, drop[i + 1], line.text.hasSuffix(":") { line.text = String(line.text.dropLast()) + "." }
            cleaned[entry.page].append(line)
        }
        return pages.enumerated().map { p, page in
            var out = page
            // A line the scrub left with nothing but a full stop (the end of a citation's sentence) goes.
            out.lines = scrub(cleaned[p]).filter { $0.text.contains { $0.isLetter || $0.isNumber } }
            return out
        }
    }

    // MARK: Back matter

    /// Headings that start the list of references and everything after it.
    private static let backMatterLabels: Set<String> = [
        "references", "reference", "bibliography", "works cited", "further reading", "external links", "see also", "footnotes",
        "endnotes", "citations", "notes and references", "references and notes", "sources", "selected bibliography",
        "suggested reading", "recommended reading", "additional reading", "general references", "references and further reading",
        "bibliography of cited sources", "credits", "acknowledgements", "acknowledgments",
    ]

    /// The lines of back matter: from a heading in `backMatterLabels` that comes after a quarter of the text, or whose next lines are
    /// reference entries, until prose resumes (a printout of two articles has the second one after the first one's references). A
    /// heading near the start is a section of the lesson; "Sources of energy" is not on the list. A printout of an encyclopaedia page
    /// can be mostly references, so the quarter is of the words, not of the way.
    static func backMatter(in texts: [String]) -> Set<Int> {
        let total = texts.reduce(0) { $0 + $1.split(whereSeparator: { $0.isWhitespace }).count }
        func isProse(_ k: Int) -> Bool {
            guard k < texts.count else { return false }
            let t = texts[k].trimmingCharacters(in: .whitespaces)
            return t.split(whereSeparator: { $0.isWhitespace }).count >= 8 && ".!?\"”".contains(t.last ?? " ")
                && !TextArtifacts.looksLikeReference(t) && !numberedEntry.matches(t)
        }
        func proseResumes(at k: Int) -> Bool {
            if isProse(k), isProse(k + 1) { return true }
            let t = texts[k].trimmingCharacters(in: .whitespaces)
            let headingLike = t.split(whereSeparator: { $0.isWhitespace }).count <= 6 && !".,;:!?".contains(t.last ?? "x") && t.first?.isUppercase == true
            return headingLike && !backMatterLabels.contains(t.lowercased()) && isProse(k + 1) && isProse(k + 2)
        }
        var out = Set<Int>()
        var seen = 0
        var i = 0
        while i < texts.count {
            let label = texts[i].trimmingCharacters(in: CharacterSet(charactersIn: "# :\t")).lowercased()
            if backMatterLabels.contains(label) {
                let followers = texts[(i + 1)..<min(texts.count, i + 9)]
                let entries = followers.filter { TextArtifacts.looksLikeReference($0) || numberedEntry.matches($0) }.count
                if seen * 4 >= total || entries >= 2 {
                    var j = i + 1
                    while j < texts.count, !proseResumes(at: j) { j += 1 }
                    for k in i..<j { out.insert(k) }
                    for k in i..<j { seen += texts[k].split(whereSeparator: { $0.isWhitespace }).count }
                    i = j
                    continue
                }
            }
            seen += texts[i].split(whereSeparator: { $0.isWhitespace }).count
            i += 1
        }
        return out
    }

    /// The same, as the index of the line where the first back matter begins, or `texts.count`.
    static func backMatterStart(in texts: [String]) -> Int { backMatter(in: texts).min() ?? texts.count }

    /// "1. Fermi, E. (1956)." / "[3] Smith": how a reference list numbers its entries.
    private static let numberedEntry = Pattern(#"^\s*(?:\[\d{1,3}\]|\d{1,3}[.)])\s+\S"#)

    // MARK: Lines that are not text

    private static let furniture = Pattern(
        #"^\d{1,3}\s*/\s*\d{1,3}$|^(?i:page\s+\d+(?:\s+of\s+\d+)?)$|^\d{1,2}/\d{1,2}/\d{2,4},?\s+\d{1,2}:\d{2}(?::\d{2})?\s*(?:[AaPp][Mm])?$|^(?:https?://|www\.)\S+$|^(?:Retrieved|Archived)\s+(?:from|on)\b|^[—―]\s*\S|^(?i:pp?\.)\s*\d+(?:\s*[-–]\s*\d+)?\.?$|^(?i:pp?|nos?|vols?|ch|sec|fig|eq)\.$"#)
    /// "NIH: National Heart, Lung, and Blood Institute": the credit line under a copied page, an acronym and a name in capitals.
    private static let credit = Pattern(#"^[A-Z]{2,8}:\s+(?:(?:[A-Z][\w'&\-]*|and|of|the|for),?\s*){3,}$"#)
    private static let figureOpening = Pattern(#"^\[(?:figure|fig\.?|image|photo|photograph|table|diagram|chart|video|illustration|map|graph)\b"#, ignoreCase: true)
    private static let captionOpening = Pattern(#"^(?:figure|fig\.|table|diagram|chart|photo|image)\s*\d+[a-z]?\s*[:.\-–—]"#, ignoreCase: true)
    private static let splitMarkerTail = Pattern(#"^\s*\d{1,3}\s*\](?:\s*\[\s*\d{1,3}\s*\])*(?:\s|$)"#)
    private static let footnote = Pattern(#"^\[\s*(?:\d{1,3}|(?i:citation needed|clarification needed|note \d{1,3}|nb \d{1,3}))\s*\]$"#)
    private static let numberedLine = Pattern(#"^\d{1,3}(?:\s+\S.*)?$"#)
    private static let caseName = Pattern(#"\b[A-Z][\w.'’]*(?:\s+[A-Z][\w.'’&]*)*\s+v\.\s+[A-Z]"#)
    private static let seeStart = Pattern(#"^(?:see\b|cf\.|compare\b|but see\b|accord\b|id\.|ibid|supra\b|e\.\s?g\.,?\s+see\b)"#, ignoreCase: true)
    private static let locator = Pattern(#"\d|§|(?:figure|fig\.|table|section|chapter|page|above|below|appendix|equation)"#, ignoreCase: true)
    private static let figureStart = Pattern(#"^(?:figure|fig\.|table|equation|eq\.|diagram)\s*\d"#, ignoreCase: true)
    private static let phonetic = Pattern("[\u{0250}-\u{02FF}]")
    private static let spaceBeforePunctuation = Pattern(#"\s+([.,;:!?)\]])"#)
    private static let spaceAfterOpening = Pattern(#"([(\[])\s+"#)

    /// "8/9", "Page 3 of 9", "11/3/26, 12:39 PM", a web address alone, "Retrieved from …", an attribution ("— Edsger Dijkstra, in an
    /// interview …"), "Pp. 486-496.", a line of symbols.
    static func isFurniture(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        if furniture.matches(t) || credit.matches(t) { return true }
        let letters = t.filter(\.isLetter).count, marks = t.filter { !$0.isWhitespace }.count
        if marks >= 4, Double(letters) / Double(marks) < 0.3 { return true }
        return false
    }

    /// "[Figure: …]" over one line or several, and a line that begins "Figure 3:" or "Table 2.": a picture's caption.
    static func markFigureBlocks(_ texts: [String], _ drop: inout [Bool]) {
        var i = 0
        while i < texts.count {
            let t = texts[i].trimmingCharacters(in: .whitespaces)
            if figureOpening.matches(t) {
                var end = i
                while end < texts.count - 1, end < i + 8, !texts[end].trimmingCharacters(in: .whitespaces).hasSuffix("]") { end += 1 }
                if texts[end].trimmingCharacters(in: .whitespaces).hasSuffix("]") {
                    for k in i...end { drop[k] = true }
                    i = end + 1
                    continue
                }
                drop[i] = true
            } else if captionOpening.matches(t) {
                drop[i] = true
            }
            i += 1
        }
    }

    /// A program listing: four or more lines in a row that begin with a line number and a space ("1 function Dijkstra(Graph, source):",
    /// "2", "3 for each vertex v in Graph.Vertices:"). A numbered list of sentences writes "1." with a full stop.
    static func markListings(_ texts: [String], _ drop: inout [Bool]) {
        func numbered(_ t: String) -> Bool {
            numberedLine.matches(t.trimmingCharacters(in: .whitespaces))
        }
        var i = 0
        while i < texts.count {
            guard numbered(texts[i]) else { i += 1; continue }
            var j = i
            while j < texts.count, numbered(texts[j]) { j += 1 }
            if j - i >= 4 { for k in i..<j { drop[k] = true } }
            i = j
        }
    }

    /// A short line without a full stop that comes back three times or more is a running header or footer ("Le Chatelier's principle -
    /// Wikipedia").
    static func markRepeats(_ texts: [String], _ drop: inout [Bool]) {
        var count: [String: Int] = [:]
        func key(_ t: String) -> String { t.lowercased().filter { !$0.isNumber }.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        for t in texts { count[key(t), default: 0] += 1 }
        for (i, t) in texts.enumerated() {
            let words = t.split(whereSeparator: { $0.isWhitespace }).count
            guard (2...12).contains(words), let last = t.trimmingCharacters(in: .whitespaces).last, !".?!:;".contains(last) else { continue }
            if (count[key(t)] ?? 0) >= 3 { drop[i] = true }
        }
    }

    // MARK: Inside the lines

    /// Citations in parentheses, footnote numbers and pronunciation guides taken out of the lines. A citation can run over several lines
    /// (the line splitter cuts at every "v." and "p."), so a page's lines are scrubbed as one run and each keeps what is left of its own text.
    static func scrub(_ lines: [TextLine]) -> [TextLine] {
        var chars: [Character] = []
        var owner: [Int] = []
        for (n, line) in lines.enumerated() {
            if !chars.isEmpty { chars.append(" "); owner.append(n) }
            for c in line.text { chars.append(c); owner.append(n) }
        }
        var drop = [Bool](repeating: false, count: chars.count)
        var i = 0
        while i < chars.count {
            // A footnote number the line splitter cut in two ("equilibrium.[" / "2] Other names …").
            if chars[i] == "[", let close = chars[i...].prefix(30).firstIndex(of: "]"), footnote.matches(String(chars[i...close])) {
                var start = i
                while start > 0, chars[start - 1] == " " { start -= 1 }
                for k in start...close { drop[k] = true }
                i = close + 1
                continue
            }
            if chars[i] == "(", let close = closing(chars, from: i, within: 600) {
                let inner = String(chars[(i + 1)..<close])
                if isCitation(inner) {
                    var start = i
                    while start > 0, chars[start - 1] == " " { start -= 1 }
                    for k in start...close { drop[k] = true }
                    i = close + 1
                    continue
                }
            }
            i += 1
        }
        var texts = [String](repeating: "", count: lines.count)
        for k in chars.indices where !drop[k] { texts[owner[k]].append(chars[k]) }
        return zip(lines, texts).map { line, text in
            TextLine(id: line.id, text: tidy(TextArtifacts.withoutMarkers(text)), box: line.box)
        }
    }

    /// The index of the parenthesis that closes the one at `start`, or nil.
    private static func closing(_ chars: [Character], from start: Int, within limit: Int) -> Int? {
        var depth = 0
        var k = start
        while k < chars.count, k - start <= limit {
            if chars[k] == "(" { depth += 1 }
            if chars[k] == ")" { depth -= 1; if depth == 0 { return k } }
            k += 1
        }
        return nil
    }

    /// What is inside a parenthesis that cites rather than says: a case and its reporter, a page, a section, a figure, a pronunciation.
    static func isCitation(_ inner: String) -> Bool {
        let t = inner.trimmingCharacters(in: .whitespaces)
        if t.count < 2 { return false }
        if TextArtifacts.looksLikeReference(t) || QuestionQuality.looksLikeCitation(t) { return true }
        if caseName.matches(t) { return true }                                                                                   // Martin v. Herzog
        if seeStart.matches(t), locator.matches(t) { return true }
        if figureStart.matches(t) { return true }
        if phonetic.matches(t) || t.range(of: "pronounced", options: .caseInsensitive) != nil { return true }
        return false
    }

    /// No double spaces, no space before a full stop, comma or closing bracket, none inside an opening one.
    static func tidy(_ text: String) -> String {
        var t = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        t = spaceBeforePunctuation.replacing(in: t, with: "$1")
        t = spaceAfterOpening.replacing(in: t, with: "$1")
        return t.trimmingCharacters(in: .whitespaces)
    }
}
