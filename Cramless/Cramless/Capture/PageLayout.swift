import Foundation

/// A recognised line before it gets its anchor id: its text, its box (top-left unit space) and the recogniser's
/// confidence.
struct RawLine: Hashable, Sendable {
    var text: String
    var box: NormRect
    var confidence: Double

    var top: Double { box.y }
    var bottom: Double { box.y + box.h }
    var left: Double { box.x }
    var right: Double { box.x + box.w }
    var centerY: Double { box.y + box.h / 2 }
}

/// Pure page geometry: reading order, the printed page number, and whether a page reads as math. No Vision here,
/// so all of it is tested with hand-made boxes.
enum PageLayout {
    // MARK: Reading order

    /// Lines in reading order.
    ///
    /// The page is cut recursively at its whitespace (XY-cut): first into bands at horizontal gaps taller than
    /// ~0.6 of a line, then each band into columns at vertical gutters. A band with no gutter is read row by row
    /// (rows top to bottom by their centres, with a tolerance of half a line; left to right inside a row).
    ///
    /// Grids stay sensible: a band of side-by-side columns is read column by column, so a bullet and its
    /// continuation line stay together. Consecutive bands whose columns line up (a table's header row above a
    /// diagram above its bullets) are joined, so each column is read whole: "Prophase", its bullets, then
    /// "Metaphase", its bullets. Reading the same grid row by row would interleave four columns' half-sentences.
    static func readingOrder(_ lines: [RawLine]) -> [RawLine] {
        guard lines.count > 1 else { return lines }
        let lineHeight = median(lines.map(\.box.h))
        let metrics = Metrics(hGap: max(0.004, 0.6 * lineHeight), vGap: max(0.006, 0.8 * lineHeight), rowTolerance: 0.5)
        return order(lines, metrics: metrics, depth: 0)
    }

    struct Metrics {
        /// The smallest vertical whitespace that separates bands, in page units.
        var hGap: Double
        /// The smallest horizontal whitespace that separates columns, in page units.
        var vGap: Double
        /// Two lines share a row when their centres are within this share of the shorter one's height.
        var rowTolerance: Double
    }

    private static func order(_ lines: [RawLine], metrics: Metrics, depth: Int) -> [RawLine] {
        guard lines.count > 1, depth < 24 else { return rowOrder(lines, tolerance: metrics.rowTolerance) }
        let bands = split(lines, axis: .vertical, minGap: metrics.hGap)
        if bands.count > 1 {
            var result: [RawLine] = []
            var index = 0
            while index < bands.count {
                // Join this band with the following ones while their columns line up.
                var columns = split(bands[index], axis: .horizontal, minGap: metrics.vGap)
                var next = index + 1
                if columns.count > 1 {
                    while next < bands.count {
                        let following = split(bands[next], axis: .horizontal, minGap: metrics.vGap)
                        guard let merged = mergeColumns(columns, following) else { break }
                        columns = merged
                        next += 1
                    }
                }
                if next > index + 1 {
                    for column in columns { result += order(column, metrics: metrics, depth: depth + 1) }
                } else {
                    result += order(bands[index], metrics: metrics, depth: depth + 1)
                }
                index = next
            }
            return result
        }
        let columns = split(lines, axis: .horizontal, minGap: metrics.vGap)
        if columns.count > 1 {
            return columns.flatMap { order($0, metrics: metrics, depth: depth + 1) }
        }
        return rowOrder(lines, tolerance: metrics.rowTolerance)
    }

    enum Axis { case vertical, horizontal }

    /// Splits lines at gaps in their coverage along an axis (`.vertical`: by y into bands; `.horizontal`: by x
    /// into columns), keeping each part in order of position.
    static func split(_ lines: [RawLine], axis: Axis, minGap: Double) -> [[RawLine]] {
        let sorted = lines.sorted { axis == .vertical ? $0.top < $1.top : $0.left < $1.left }
        var groups: [[RawLine]] = []
        var current: [RawLine] = []
        var reach = -Double.infinity
        for line in sorted {
            let start = axis == .vertical ? line.top : line.left
            let end = axis == .vertical ? line.bottom : line.right
            if !current.isEmpty, start - reach >= minGap {
                groups.append(current)
                current = []
            }
            current.append(line)
            reach = max(reach, end)
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    /// Joins a band's columns onto the columns above when they line up: `b` has at least two columns, each lies
    /// under exactly one of `a`'s (overlapping it by at least half the narrower, and the others by less than a
    /// tenth), and no two share one. `b` may fill fewer columns than `a` (a grid's last, shorter rows). Nil when
    /// they don't line up; a single-column band (a heading, a full-width paragraph) never joins.
    static func mergeColumns(_ a: [[RawLine]], _ b: [[RawLine]]) -> [[RawLine]]? {
        guard a.count > 1, b.count > 1, b.count <= a.count else { return nil }
        let spansA = a.map(span), spansB = b.map(span)
        var merged = a
        var used = Set<Int>()
        for (j, sb) in spansB.enumerated() {
            var match: Int?
            for (i, sa) in spansA.enumerated() {
                let overlap = min(sa.upperBound, sb.upperBound) - max(sa.lowerBound, sb.lowerBound)
                let narrower = max(min(sa.upperBound - sa.lowerBound, sb.upperBound - sb.lowerBound), 0.0001)
                if overlap >= 0.5 * narrower {
                    guard match == nil else { return nil }
                    match = i
                } else if overlap > 0.1 * narrower {
                    return nil
                }
            }
            guard let i = match, used.insert(i).inserted else { return nil }
            merged[i] += b[j]
        }
        return merged
    }

    private static func span(_ column: [RawLine]) -> ClosedRange<Double> {
        (column.map(\.left).min() ?? 0)...(column.map(\.right).max() ?? 0)
    }

    /// Rows top to bottom, left to right inside a row. A line joins a row when its centre is within `tolerance` of
    /// the shorter line's height from the row's centre, and it sits beside the row's lines rather than under them.
    static func rowOrder(_ lines: [RawLine], tolerance: Double) -> [RawLine] {
        rows(lines, tolerance: tolerance).flatMap { $0 }
    }

    static func rows(_ lines: [RawLine], tolerance: Double = 0.5) -> [[RawLine]] {
        let sorted = lines.sorted { ($0.centerY, $0.left) < ($1.centerY, $1.left) }
        var rows: [[RawLine]] = []
        for line in sorted {
            let candidates = rows.indices.suffix(3).reversed()
            if let index = candidates.first(where: { fits(line, rows[$0], tolerance: tolerance) }) {
                rows[index].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { $0.sorted { $0.left < $1.left } }
    }

    private static func fits(_ line: RawLine, _ row: [RawLine], tolerance: Double) -> Bool {
        let rowCenter = median(row.map(\.centerY))
        let rowHeight = median(row.map(\.box.h))
        guard abs(line.centerY - rowCenter) <= tolerance * min(line.box.h, rowHeight) else { return false }
        return !row.contains { member in
            let overlap = min(member.right, line.right) - max(member.left, line.left)
            return overlap > 0.1 * min(member.box.w, line.box.w)
        }
    }

    // MARK: Page number

    /// The printed page number: a short number ("87", "Page 87", "- 87 -", "12 / 40") alone on a line at the top
    /// or bottom edge of the text, near a corner or centred. Nil when there is none.
    static func pageNumber(in lines: [RawLine]) -> String? {
        guard let top = lines.map(\.top).min(), let bottom = lines.map(\.bottom).max() else { return nil }
        // Three or more number-only lines are a list or a table of numbers, not a page number.
        guard lines.filter({ pageNumberText($0.text) != nil }).count <= 2 else { return nil }
        let height = max(bottom - top, 0.0001)
        let candidates = lines.compactMap { line -> (number: String, edge: Double)? in
            guard let number = pageNumberText(line.text), line.box.w < 0.2 else { return nil }
            let fromTop = (line.top - top) / height
            let fromBottom = (bottom - line.bottom) / height
            let edge = min(fromTop, fromBottom)
            let centre = line.left + line.box.w / 2
            let placed = centre < 0.3 || centre > 0.7 || abs(centre - 0.5) < 0.12
            return edge < 0.06 && placed ? (number, edge) : nil
        }
        return candidates.min { $0.edge < $1.edge }?.number
    }

    /// The number in a line that is only a page number, else nil.
    static func pageNumberText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 16 else { return nil }
        let patterns = [
            #"^(?:page|pg\.?|p\.)?\s*[-–—(\[|]?\s*(\d{1,4})\s*[-–—)\]|]?$"#,
            #"^(?:page\s+)?(\d{1,4})\s*(?:/|of)\s*\d{1,4}$"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  let range = Range(match.range(at: 1), in: trimmed)
            else { continue }
            let number = String(trimmed[range])
            guard let value = Int(number), value > 0 else { return nil }
            return String(value)
        }
        return nil
    }

    // MARK: Math

    private static let mathScalars = CharacterSet(charactersIn: "=∫∑Σ√±≤≥≠∞π→⇒∂∇^≈∝÷×∆Δ")
    private static let arithmetic = try? NSRegularExpression(pattern: #"\d\s*[+×*÷−]\s*\(?\d|\b\d{1,3}/\d{1,3}\b(?!/)|\b[a-z][0-9]\b"#)

    /// A line written in math or chemistry notation (an equation, an operator between numbers, "x2" for x²).
    static func isMathLike(_ text: String) -> Bool {
        if text.unicodeScalars.contains(where: mathScalars.contains) { return true }
        guard let arithmetic else { return false }
        return arithmetic.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// At least two lines, and a quarter of the page, are notation.
    static func isMathLike(page lines: [String]) -> Bool {
        let math = lines.filter(isMathLike).count
        return math >= 2 && Double(math) >= 0.25 * Double(lines.count)
    }

    // MARK: Formulas lost from a text layer

    /// Typeset formulas are pictures or glyphs a PDF has no characters for, so a page that was maths comes out as prose with
    /// holes in it: "…the chain rule is expressed as" / "and" / "for indicating at which points…". Reading the page as an image
    /// would bring them back, and that spends one of the week's scans, so a page is flagged only on firm evidence.
    ///
    /// Two kinds of sign are counted (`FormulaGapEvidence`):
    ///
    /// - **Traces**, which a removed formula leaves and prose doesn't:
    ///   a line that is only a connector, in lower case ("and", "or, equivalently,"), beside a long line of prose (1.5 each, two at most);
    ///   an introducer ("…is expressed as", "…is:") followed by such a leftover, a lone symbol or a stub (2 each, two at most);
    ///   a run of one-character lines between lines of prose, the rest of a fraction (1.5 each, two at most; digits don't count, so
    ///   a table isn't one);
    ///   a line that starts with "," "." ")" or "]", the punctuation after a formula that sat at the end of the line above (1.5 each,
    ///   two at most);
    ///   a stub of four words or fewer with a space before a comma or a period (1 each, two at most);
    ///   "where" starting a line right after a short one (1 each, two at most);
    ///   a formula the page draws as outlines where the text layer has nothing (`FormulaInk`): one set on a line of its own (3 each, two
    ///   at most, so one flags the page), or a symbol with its subscript inside a line (0.4 each, eight at most). Many formulas leave
    ///   no hole in the prose at all (one in the middle of a line), and these are the ones this sign finds.
    /// - **Ambiguous signs**, which prose and lists produce too and which can't flag a page alone:
    ///   an introducer ending "is:", "are:", "that:", "as follows:" … before a new sentence (1 each, two at most) or a short heading
    ///   (0.75), or ending the page (0.5); any other line ending in ":" before a sentence, and a line ending "is" or "as" before
    ///   one (0.5 each); a space before a comma or a period (0.75 each, three at most); formula words with almost no symbols
    ///   (1); a page of lines far shorter than the document's (1).
    ///
    /// A page is flagged when the points reach three AND there is a trace of 1.5 or more, or four introducers each followed by a new
    /// sentence (several on one page is what a page of display formulas looks like). A space before ":" ";" "?" or "!" is
    /// ordinary French typography and is never counted.
    ///
    /// Tuned on a Wikipedia PDF of the chain rule (the twelve pages with formulas are flagged, the two reference pages are not),
    /// on a hundred and nine pages of English prose and twenty-three in Spanish, Hebrew and Arabic, and on French, German and
    /// Spanish pages with colon lists, English lists, tables, slides, code, a contents page and an OCR'd scan (none flagged). A
    /// false flag costs a scan the student may spend; a miss costs answers that say "the formula isn't in the passages".
    ///
    /// The outlines were checked on six browser printouts whose pages Cloud AI had read as images (51 pages, 19 of which gained three
    /// maths characters or more): the text signs alone found 8 of the 19, with the outlines 18; the page left has a few subscripts
    /// the text layer holds in full. The two pages flagged without that gain each lost one formula. The values are not fitted to those
    /// pages: the result is the same for outlines of two to four curves and up to 30 to 90 points, for gaps of 6 to 14 points, for a
    /// displayed formula of four to eight symbols and 12 to 36 points, and when each printout was left out in turn and the values were
    /// chosen on the other five.
    static let formulaGapThreshold = 3.0

    /// What a page's text shows of lost formulas, and what its drawing shows (`FormulaInkSummary`).
    struct FormulaGapEvidence: Equatable, Sendable {
        /// Points from signs only a removed formula leaves (the formulas drawn as outlines are among them).
        var traces = 0.0
        /// Points from signs prose and lists produce too.
        var ambiguous = 0.0
        /// Introducers followed by a new sentence, a short heading or the end of the page.
        var introducers = 0
        /// Displayed formulas the page draws as outlines, and how many of them there are inside a line (already in `traces`).
        var inkDisplays = 0
        var inkInlines = 0

        var total: Double { traces + ambiguous }
        var flagged: Bool { total >= PageLayout.formulaGapThreshold && (traces >= 1.5 || introducers >= 4) }
    }

    static func formulasMayBeMissing(page lines: [String], documentMedianLineLength: Double? = nil, ink: FormulaInkSummary? = nil) -> Bool {
        formulaGapEvidence(page: lines, documentMedianLineLength: documentMedianLineLength, ink: ink).flagged
    }

    /// The points a page's signs add up to (`formulaGapEvidence(...).total`).
    static func formulaGapScore(page lines: [String], documentMedianLineLength: Double? = nil, ink: FormulaInkSummary? = nil) -> Double {
        formulaGapEvidence(page: lines, documentMedianLineLength: documentMedianLineLength, ink: ink).total
    }

    /// Which pages of a PDF's text layer lost formulas (the document's typical line length is the median of the pages'). `ink` is what
    /// each page draws as outlines (`FormulaInk`, one entry per page, nil where the page's drawing wasn't read); a page with no entry
    /// is judged by its text alone.
    static func pagesMissingFormulas(_ pages: [[String]], ink: [FormulaInk?] = []) -> [Bool] {
        let means = pages.filter { $0.count >= 3 }.map { Double($0.reduce(0) { $0 + $1.count }) / Double($0.count) }
        let median = means.isEmpty ? nil : self.median(means)
        let summaries = ink.isEmpty ? [] : inkSummaries(ink)
        return pages.enumerated().map { index, lines in
            formulasMayBeMissing(page: lines, documentMedianLineLength: median, ink: index < summaries.count ? summaries[index] : nil)
        }
    }

    static func formulaGapEvidence(page input: [String], documentMedianLineLength median: Double? = nil,
                                   ink: FormulaInkSummary? = nil) -> FormulaGapEvidence {
        let lines = input.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let n = lines.count
        var evidence = FormulaGapEvidence()
        // What the page draws where a text layer has no characters counts whatever the text looks like.
        if let ink {
            evidence.inkDisplays = ink.displays
            evidence.inkInlines = ink.inlines
            evidence.traces += Double(min(ink.displays, 2)) * displayInkPoints + Double(min(ink.inlines, 8)) * inlineInkPoints
        }
        guard n >= 3 else { return evidence }
        func words(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }

        // A connector alone on a line, beside a long line of prose.
        var connectors = 0
        for (i, line) in lines.enumerated() where line.first?.isLowercase == true && isConnectorLine(line) {
            if (i > 0 && words(lines[i - 1]) >= 8) || (i + 1 < n && words(lines[i + 1]) >= 8) { connectors += 1 }
        }
        evidence.traces += Double(min(connectors, 2)) * 1.5

        // Introducers, and what follows each.
        var leftovers = 0, strong = 0.0, headings = 0, weakColons = 0, weakEndings = 0
        for (i, line) in lines.enumerated() {
            let text = line.replacingOccurrences(of: #"\s*(\[\d{1,3}\]|\(\d{1,3}\))\s*$"#, with: "", options: .regularExpression)
            let colon = text.hasSuffix(":")
            let strongColon = colon && (firstMatch(strongIntroducer, in: text) || firstMatch(mathWords, in: text))
            let weakEnding = !colon && firstMatch(weakIntroducer, in: text)
            guard colon || weakEnding else { continue }
            guard i + 1 < n else {
                // The last line of the page promises a formula that isn't there.
                if strongColon { strong += 0.5; evidence.introducers += 1 }
                continue
            }
            let next = lines[i + 1]
            if firstMatch(listMarker, in: next) { continue }
            if isLeftover(next) {
                leftovers += 1
                evidence.introducers += 1
            } else if next.first?.isUppercase == true, words(next) >= 6 {
                if strongColon { strong += 1; evidence.introducers += 1 }
                else if weakEnding { weakEndings += 1; evidence.introducers += 1 }
                else { weakColons += 1 }
            } else if strongColon, isShortHeading(next) {
                headings += 1
                evidence.introducers += 1
            }
        }
        evidence.traces += Double(min(leftovers, 2)) * 2

        // Lines of one or two characters between lines of prose (not digits: a table's cells).
        var runs = 0, run = 0, runStart = 0
        for (i, line) in (lines + ["x y z w"]).enumerated() {
            if i < n, line.count <= 2, !isAllDigits(line) {
                if run == 0 { runStart = i }
                run += 1
            } else {
                if run >= 2 {
                    let before = runStart > 0 ? lines[runStart - 1] : "", after = i < n ? lines[i] : ""
                    if words(before) >= 3 && words(after) >= 3 { runs += 1 }
                }
                run = 0
            }
        }
        evidence.traces += Double(min(runs, 2)) * 1.5

        evidence.traces += Double(min(lines.filter { firstMatch(startsWithPunctuation, in: $0) }.count, 2)) * 1.5
        evidence.traces += Double(min(lines.filter(isStub).count, 2))
        var wheres = 0
        for (i, line) in lines.enumerated() where line.lowercased().hasPrefix("where ") || line.lowercased() == "where" {
            if i == 0 || lines[i - 1].count < 30 { wheres += 1 }
        }
        evidence.traces += Double(min(wheres, 2))

        evidence.ambiguous += min(strong, 2)
        evidence.ambiguous += Double(min(headings, 2)) * 0.75
        evidence.ambiguous += Double(min(weakColons, 2)) * 0.5
        evidence.ambiguous += Double(min(weakEndings, 2)) * 0.5
        evidence.ambiguous += Double(min(lines.filter { firstMatch(spaceBeforeCommaOrPeriod, in: $0) }.count, 3)) * 0.75

        let mathWordCount = lines.reduce(0) { $0 + matchCount(mathWords, in: $1) }
        let symbolLines = lines.filter { line in
            line.unicodeScalars.contains(where: formulaScalars.contains) || firstMatch(operatorBetweenDigits, in: line)
        }.count
        if mathWordCount >= 4, symbolLines <= max(1, n / 8) { evidence.ambiguous += 1 }
        if let median, n >= 8, Double(lines.reduce(0) { $0 + $1.count }) / Double(n) < 0.55 * median { evidence.ambiguous += 1 }
        return evidence
    }

    /// A line that is only a connector between two formulas: "and", "or, equivalently,", "or for short,".
    static func isConnectorLine(_ line: String) -> Bool {
        let normalized = line.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }.trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty, normalized.count <= 24 else { return false }
        return connectorPhrases.contains(normalized) || normalized.split(separator: " ").allSatisfy { connectorWords.contains(String($0)) }
    }

    /// What a vanished formula leaves between two lines of prose: a lowercase connector, an equation number, a lone symbol, or a
    /// stub with a hole in it ("So that .").
    private static func isLeftover(_ line: String) -> Bool {
        if line.first?.isLowercase == true, isConnectorLine(line) { return true }
        if firstMatch(formulaNumber, in: line) { return true }
        if line.count <= 2, !isAllDigits(line) { return true }
        if !line.contains(where: \.isLetter), !isAllDigits(line) { return true }
        return isStub(line)
    }

    /// Four words or fewer with a space before a comma or a period: "So that ." / "where , and for each".
    private static func isStub(_ line: String) -> Bool {
        line.split(whereSeparator: \.isWhitespace).count <= 4 && firstMatch(spaceBeforeCommaOrPeriod, in: line)
    }

    /// A capitalised line of one to four words with no closing punctuation: "Example", "Further generalizations".
    private static func isShortHeading(_ line: String) -> Bool {
        let count = line.split(whereSeparator: \.isWhitespace).count
        return line.first?.isUppercase == true && (1...4).contains(count) && !".!?:,;".contains(line.last ?? ".")
    }

    private static func isAllDigits(_ text: String) -> Bool { !text.isEmpty && text.allSatisfy(\.isNumber) }

    /// Symbols that mean a formula survived on the line (the maths scalars, plus composition and prime marks).
    private static let formulaScalars = mathScalars.union(CharacterSet(charactersIn: "∘′·"))

    private static let connectorPhrases: Set<String> = [
        "and", "or", "where", "so", "then", "thus", "hence", "therefore", "that is", "ie", "equivalently", "or equivalently",
        "or for short", "for short", "in other words", "which", "with", "such that", "if", "for",
    ]
    private static let connectorWords: Set<String> = [
        "and", "or", "equivalently", "for", "short", "that", "is", "ie", "so", "then", "thus", "hence", "where", "with", "in",
        "other", "words",
    ]

    private static func regex(_ pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }

    /// A line ending where a formula would come next: "…is:", "…as follows:", "…equal to:".
    private static let strongIntroducer = regex(#"\b(is|are|as|that|follows|by|to|equals?|becomes|gives|yields|being|therefore|notation|form|formula|expression|equation|identity)\s*[\)\]]?:$"#)
    /// A line ending on a word that wants a formula after it, without a colon: "…is expressed as", "…we have".
    private static let weakIntroducer = regex(#"\b(as|is|are|by|have|form|furthermore|follows|then|equals?|being)$"#)
    private static let listMarker = regex(#"^([•\-\*–]|\d+[.)]|[a-z][.)])\s"#)
    private static let formulaNumber = regex(#"^(\(\d+\)|\[\d+\])$"#, options: [])
    /// A space before a comma or a period, where a symbol vanished: "the composite function ,". (Not before ":" or ";", which
    /// French sets in front of them.)
    private static let spaceBeforeCommaOrPeriod = regex(#"[A-Za-z0-9\)]\s+[,.](\s|$)"#, options: [])
    /// A line that starts with the punctuation that followed a formula: ", which is not differentiable".
    private static let startsWithPunctuation = regex(#"^[,.)\]](\s|$)"#, options: [])
    private static let operatorBetweenDigits = regex(#"\d\s*[=+\-*/]\s*\d"#, options: [])
    private static let mathWords = regex(#"\b(formulas?|equations?|derivatives?|integrals?|theorem|differentiable|variables?|coefficients?|polynomial)\b"#)

    private static func firstMatch(_ expression: NSRegularExpression?, in text: String) -> Bool {
        guard let expression else { return false }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func matchCount(_ expression: NSRegularExpression?, in text: String) -> Int {
        guard let expression else { return 0 }
        return expression.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    // MARK: Formulas drawn as outlines

    /// A browser that prints a page whose formulas are SVG pictures draws each one as a row of small filled outlines, one per symbol,
    /// and the text layer has nothing there: no hole in the prose shows when the formula sat in the middle of a line, and a page can lose
    /// a dozen of them with no line left over to find. `PDFReader` reads the outlines off the page's drawing (`PDFInk`) and hands over
    /// their boxes: the filled shapes the size of a character, in points from the top left of the page.
    struct FormulaInk: Equatable, Sendable {
        struct Piece: Equatable, Sendable {
            var x: Double
            var y: Double
            var width: Double
            var height: Double
        }

        var pieces: [Piece]
        /// Outlines whose middle is above this line are not the page's own: a first page's masthead, a site's logo above its first
        /// sentence (`.infinity`: the page has no sentence, so it is a cover).
        var ignoreAbove = 0.0
    }

    /// Outlines that sit together (a symbol and its subscript, the symbols of a formula): their box, how many they are, and how many
    /// different sizes (to the half point) they come in. Symbols vary; the marks of a chart, a column of bullets and a row of dots do not.
    struct InkCluster: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var pieces: Int
        var sizes: Int
    }

    /// What a page's outlines make of it, once what repeats from page to page is taken out.
    struct FormulaInkSummary: Equatable, Sendable {
        /// Clusters of `displayInkPieces` outlines or more, `displayInkWidth` points wide or more, in `displayInkSizes` sizes or more: a
        /// formula set on a line of its own.
        var displays = 0
        /// Clusters of two outlines or more, in two sizes or more, that are not: a symbol with its subscript, a short formula inside a line.
        var inlines = 0
    }

    /// Outlines whose boxes are this close, horizontally and vertically (a fraction's bar between its two lines), are one formula.
    static let inkGapX = 10.0
    static let inkGapY = 6.0
    static let displayInkPieces = 6
    static let displayInkWidth = 24.0
    static let displayInkSizes = 4
    /// Points a displayed formula adds (two at most: it flags a page alone), and each one inside a line (eight at most: an icon or two
    /// are not a page of formulas, but a line of symbols on top of a few signs of the text is).
    static let displayInkPoints = 3.0
    static let inlineInkPoints = 0.4
    /// More outlines than this on a page and it is a map or a diagram: nothing is said of it.
    static let drawingInkPieces = 2_500

    static func inkClusters(of pieces: [FormulaInk.Piece]) -> [InkCluster] {
        let sorted = pieces.sorted { $0.x < $1.x }
        var parent = Array(sorted.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }
        for i in sorted.indices {
            let a = sorted[i]
            var j = i + 1
            while j < sorted.count, sorted[j].x <= a.x + a.width + inkGapX {
                let b = sorted[j]
                if max(a.y - (b.y + b.height), b.y - (a.y + a.height), 0) <= inkGapY { parent[root(j)] = root(i) }
                j += 1
            }
        }
        var boxes: [Int: (x0: Double, y0: Double, x1: Double, y1: Double, count: Int)] = [:]
        var sizes: [Int: Set<Int>] = [:]
        for (i, p) in sorted.enumerated() {
            let r = root(i)
            let old = boxes[r] ?? (p.x, p.y, p.x + p.width, p.y + p.height, 0)
            boxes[r] = (min(old.x0, p.x), min(old.y0, p.y), max(old.x1, p.x + p.width), max(old.y1, p.y + p.height), old.count + 1)
            sizes[r, default: []].insert(cell(p.width, 0.5) * 10_000 + cell(p.height, 0.5))
        }
        return boxes.map { root, box in
            InkCluster(x: box.x0, y: box.y0, width: box.x1 - box.x0, height: box.y1 - box.y0, pieces: box.count, sizes: sizes[root]?.count ?? 0)
        }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    }

    /// `value` in cells of `size` points, as a whole number (a number that is not a sensible one is cell 0).
    private static func cell(_ value: Double, _ size: Double) -> Int {
        let cells = (value / size).rounded()
        return cells.isFinite && abs(cells) < 1e9 ? Int(cells) : 0
    }

    /// What each page of a document draws as outlines: the clusters of the page (its masthead left aside), without the ones that sit in
    /// the same place on a quarter of the pages and at least three (a logo or a mark on every slide, as running lines are taken out of
    /// the text). Nil for a page whose drawing wasn't read, and for a map or a diagram.
    static func inkSummaries(_ inks: [FormulaInk?]) -> [FormulaInkSummary?] {
        let clusters: [[InkCluster]?] = inks.map { ink in
            guard let ink, ink.pieces.count <= drawingInkPieces else { return nil }
            return inkClusters(of: ink.pieces.filter { $0.y + $0.height / 2 >= ink.ignoreAbove })
        }
        func place(_ c: InkCluster) -> String {
            [c.x, c.y, c.width, c.height].map { String(cell($0, 4)) }.joined(separator: ",") + ":\(c.pieces)"
        }
        var pagesWith: [String: Int] = [:]
        for page in clusters {
            for key in Set((page ?? []).map(place)) { pagesWith[key, default: 0] += 1 }
        }
        let need = max(runningMinimumPages, Int((Double(clusters.compactMap { $0 }.count) * runningPageShare).rounded(.up)))
        let running = Set(pagesWith.filter { $0.value >= need }.keys)
        return clusters.map { page in
            guard let page else { return nil }
            var summary = FormulaInkSummary()
            for c in page where !running.contains(place(c)) {
                if c.pieces >= displayInkPieces, c.width >= displayInkWidth, c.sizes >= displayInkSizes {
                    summary.displays += 1
                } else if c.pieces >= 2, c.sizes >= 2 {
                    summary.inlines += 1
                }
            }
            return summary
        }
    }

    // MARK: A better read of a page

    /// A cloud reading of a page merged into the lines the page already has.
    ///
    /// Questions point at lines by id (their source link, their grading context, what coverage counts), so the lines a page had
    /// keep their ids, their text and their order. What the cloud read adds is slipped in beside them: each of its lines the old
    /// text doesn't already hold (a formula, a table cell, a caption) goes after the old line it follows in the page, under an id
    /// the page hasn't used ("p3.c0": the lines a read adds are the page's "c" lines, `Coverage.lineIDs` relies on it). A line the old
    /// text holds is dropped, so the prose isn't written twice, and merging the same reading again adds nothing.
    ///
    /// A cloud line is "held" when four in five of its pairs of neighbouring words (a symbol is a word) are neighbours somewhere in
    /// the old text. Where it belongs is found by the last pair it shares with the old text, looking forward from the previous
    /// match, so a formula lands after the sentence that introduces it.
    static func merged(old: [TextLine], cloud: [TextLine], pageIndex: Int) -> [TextLine] {
        var used = Set(old.map(\.id))
        var nextID = 0
        let namespace = "p\(pageIndex).c"
        func freshID(preferring id: String) -> String {
            // The relay numbers a page's lines "p3.c0…"; one that doesn't (or is taken, or belongs to another page) is numbered here, so
            // the lines a read adds are the page's "c" lines and its own ("p3.l0…") are never confused with them.
            if id.hasPrefix(namespace), used.insert(id).inserted { return id }
            while true {
                let candidate = "p\(pageIndex).c\(nextID)"
                nextID += 1
                if used.insert(candidate).inserted { return candidate }
            }
        }
        guard !old.isEmpty else {
            return cloud.map { ($0.id, $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }.filter { !$0.1.isEmpty }
                .map { TextLine(id: freshID(preferring: $0.0), text: $0.1, box: nil) }
        }

        // The old text as one stream of words, each remembering its line.
        var stream: [String] = []
        var owner: [Int] = []
        var lineStart: [Int] = []
        var lineTokens: [[String]] = []
        for (index, line) in old.enumerated() {
            let tokens = mergeTokens(line.text)
            lineStart.append(stream.count)
            lineTokens.append(tokens)
            for token in tokens { stream.append(token); owner.append(index) }
        }
        var pairs: [String: [Int]] = [:]
        for i in 0..<max(0, stream.count - 1) { pairs[stream[i] + "\u{1F}" + stream[i + 1], default: []].append(i) }
        let words = Set(stream)

        var after: [Int: [TextLine]] = [:]   // old line index (-1: before the first) → cloud lines to put after it
        var slot = -1                        // the old line the last cloud line matched
        var cursor = 0                       // where in the stream to look for the next match
        for line in cloud {
            let tokens = mergeTokens(line.text)
            guard !tokens.isEmpty else { continue }
            var held: Bool
            var end: Int?                    // the stream position of the last old word this line shares
            if tokens.count == 1 {
                // A word alone: held by an old line that is that word alone, just after the last match (an "and" between formulas),
                // else by any old line that has it.
                let next = slot + 1
                if next < old.count, let j = (next...min(old.count - 1, next + 4)).first(where: { lineTokens[$0] == tokens }) {
                    held = true
                    end = lineStart[j]
                } else {
                    held = tokens[0].count >= 3 && tokens[0].allSatisfy(\.isLetter) && words.contains(tokens[0])
                }
            } else {
                let keys = zip(tokens, tokens.dropFirst()).map { $0 + "\u{1F}" + $1 }
                held = keys.filter { pairs[$0] != nil }.count * 5 >= keys.count * 4
                // Where this line ends in the old text: its last pair with a real word in it, from the cursor on.
                for (k, key) in keys.enumerated().reversed() where tokens[k].count >= 4 || tokens[k + 1].count >= 4 {
                    if let at = pairs[key]?.first(where: { $0 >= cursor && $0 < cursor + 400 }) { end = at + 1; break }
                }
            }
            if let end {
                slot = max(slot, owner[end])
                cursor = end + 1
            }
            if !held { after[slot, default: []].append(line) }
        }

        func fresh(_ lines: [TextLine]?) -> [TextLine] {
            (lines ?? []).map { TextLine(id: freshID(preferring: $0.id), text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), box: nil) }
        }
        var out = fresh(after[-1])
        for (index, line) in old.enumerated() {
            out.append(line)
            out += fresh(after[index])
        }
        return out
    }

    /// Words, numbers and symbols of a line, lowercase and without accents; ordinary punctuation and hyphens only separate. "x²"
    /// reads as "x2", as a PDF's text layer has it.
    private static func mergeTokens(_ text: String) -> [String] {
        let plain = text.precomposedStringWithCompatibilityMapping.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        var tokens: [String] = []
        var word = ""
        func flush() {
            if !word.isEmpty { tokens.append(word); word = "" }
        }
        for character in plain {
            if character.isLetter || character.isNumber {
                word.append(character)
            } else if "'’‘`".contains(character) {
                continue
            } else if character.isWhitespace || ",.;:!?\"“”«»-–—‐‑".contains(character) {
                flush()
            } else {
                flush()
                tokens.append(String(character))
            }
        }
        flush()
        return tokens
    }

    // MARK: Title

    /// A provisional title for a scanned source: the tallest short line near the top of the first page
    /// ("Mitosis: How Cells Divide"), else nil.
    static func titleLine(in lines: [TextLine]) -> String? {
        let boxed = lines.prefix(12).filter { $0.box != nil }
        let candidates = boxed.filter { line in
            let words = line.text.split(separator: " ").count
            return (1...9).contains(words) && line.text.count >= 3 && pageNumberText(line.text) == nil
                && line.text.rangeOfCharacter(from: .letters) != nil
        }
        guard let tallest = candidates.max(by: { ($0.box?.h ?? 0) < ($1.box?.h ?? 0) }),
              let height = tallest.box?.h else { return nil }
        let typical = median(boxed.compactMap { $0.box?.h })
        return height >= 1.3 * typical ? tallest.text.trimmingCharacters(in: CharacterSet(charactersIn: " .:")) : nil
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

// MARK: - A PDF saved from a browser

/// What a browser's "Print to PDF" puts in a page's text layer besides the article: its date and the page's title along the top, the
/// address and "3/14" along the bottom of every page, and the article's reference list at the end. None of it is the student's
/// material, and the offline rules and the models turn it into questions all the same (a cloze blank on the running header, a
/// pasted paragraph of citations). `cleanedPDFPages` takes it out of a PDF's text layer, before the lines get their ids. A pasted
/// text is not cleaned: it is the student's own choice.
extension PageLayout {

    /// What cleaning took out, as counts of lines.
    struct PDFCleaning: Equatable, Sendable {
        /// Lines that run along the top or bottom of the pages: a browser's date and title, the address with the page counter.
        var running = 0
        /// Lines that only held a web address.
        var addresses = 0
        /// Lines of a reference list, its heading included.
        var references = 0
        /// Lines whose spaced-out letters ("C l i n i c a l") were joined into words.
        var spaced = 0
        /// Lines that lost the date and time stuck to their front (the header and the first line of the page came out as one) but kept
        /// their words. Not removed lines.
        var stamps = 0

        /// Lines gone.
        var removed: Int { running + addresses + references }
    }

    /// A line repeats on this share of the pages, and on at least `runningMinimumPages`, to be a running header or footer. A third of
    /// a browser printout is two articles in one file (each title on only a few of the pages), so the bar is a quarter.
    static let runningPageShare = 0.25
    static let runningMinimumPages = 3
    /// The first and last this many lines of a page are where a header and a footer sit.
    static let edgeLines = 3

    /// The text layer of a PDF's pages (the lines of each page that has one) cleaned of what is not the article:
    /// - a line that repeats, with its digits taken out, along the top or bottom of the pages (the first or last 3 lines of at least 3
    ///   pages and a quarter of them: "11/3/26, 12:39 PM Carnot cycle - Wikipedia", "https://en.wikipedia.org/wiki/Carnot_cycle 3/14"),
    ///   wherever it sits on the page, and a date and time stuck to the front of the first line of a page;
    /// - a line that is only a web address;
    /// - a reference list: from a heading named "References", "Notes", "Bibliography", "Sources" (or its German and Spanish names) to
    ///   where the article goes on, when most of its lines look like citations;
    /// - letters spaced out so far that each stands alone ("C l i n i c a l"), joined into the words they spell.
    /// Everything else stays, in its order. A page may end up with no lines.
    static func cleanedPDFPages(_ input: [[String]]) -> (pages: [[String]], report: PDFCleaning) {
        var pages = input.map { $0.map { $0.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ") }.filter { !$0.isEmpty } }
        var report = PDFCleaning()
        stripRunningLines(&pages, report: &report)
        for p in pages.indices {
            let before = pages[p].count
            pages[p].removeAll(where: isAddressOnly)
            report.addresses += before - pages[p].count
        }
        dropReferenceLists(&pages, report: &report)
        for p in pages.indices {
            for i in pages[p].indices {
                if let joined = collapsingSpacedLetters(pages[p][i]) {
                    pages[p][i] = joined
                    report.spaced += 1
                }
            }
        }
        return (pages, report)
    }

    // MARK: Running headers and footers

    /// A line with each run of digits as "#", so "3/14" and "10/14" are the same line.
    private static func digitsAsHash(_ text: String) -> String {
        var out = ""
        var inDigits = false
        for character in text {
            if character.isASCII, character.isNumber {
                if !inDigits { out.append("#") }
                inDigits = true
            } else {
                out.append(character)
                inDigits = false
            }
        }
        return out
    }

    private static func edgeIndexes(_ count: Int) -> [Int] {
        Array(Set(0..<min(edgeLines, count)).union(max(0, count - edgeLines)..<count)).sorted()
    }

    private static let datePattern = try? NSRegularExpression(pattern: #"^\(?\d{1,4}[/.\-]\d{1,2}[/.\-]\d{1,4},?$"#)
    private static let timePattern = try? NSRegularExpression(pattern: #"^\d{1,2}:\d{2}(?::\d{2})?,?$"#)

    /// A date and time at the front of a line ("11/3/26, 12:39 PM Carnot cycle - Wikipedia"): what it is, and the rest of the line.
    private static func stamp(of line: String) -> (shape: String, rest: String)? {
        let tokens = line.split(separator: " ")
        var length = 0
        var sawDate = false, sawTime = false
        for token in tokens {
            let t = String(token)
            if matches(datePattern, t) { sawDate = true } else if matches(timePattern, t) { sawTime = true }
            else if ["am", "pm"].contains(t.lowercased()), sawTime { } else { break }
            length += 1
        }
        guard sawDate || sawTime, length >= 2, length < tokens.count else { return nil }
        return (digitsAsHash(tokens[0..<length].joined(separator: " ")), tokens[length...].joined(separator: " "))
    }

    private static func matches(_ expression: NSRegularExpression?, _ text: String) -> Bool {
        guard let expression else { return false }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func stripRunningLines(_ pages: inout [[String]], report: inout PDFCleaning) {
        let filled = pages.filter { !$0.isEmpty }.count
        guard filled >= runningMinimumPages else { return }
        let need = max(runningMinimumPages, Int((Double(filled) * runningPageShare).rounded(.up)))

        // A date and time that starts the first line of most pages ("11/3/26, 12:39 PM") but is followed by the page's title on some and
        // by the page's first words on others (the header and the first line came out as one line): cut off the front of those.
        var stamps: [String: Set<Int>] = [:]
        for (p, lines) in pages.enumerated() {
            for i in edgeIndexes(lines.count) {
                if let found = stamp(of: lines[i]) { stamps[found.shape, default: []].insert(p) }
            }
        }
        let running = Set(stamps.filter { $0.value.count >= need }.keys)
        if !running.isEmpty {
            for p in pages.indices {
                for i in edgeIndexes(pages[p].count) {
                    if let found = stamp(of: pages[p][i]), running.contains(found.shape) {
                        pages[p][i] = found.rest
                        report.stamps += 1
                    }
                }
            }
        }

        // What repeats along the top and bottom of the pages, once those are cut.
        var seen: [String: Set<Int>] = [:]
        for (p, lines) in pages.enumerated() {
            for i in edgeIndexes(lines.count) { seen[digitsAsHash(lines[i]), default: []].insert(p) }
        }
        let repeated = Set(seen.filter { $0.value.count >= need }.keys)
        guard !repeated.isEmpty else { return }
        for p in pages.indices {
            let edges = Set(edgeIndexes(pages[p].count))
            var kept: [String] = []
            for (i, line) in pages[p].enumerated() {
                let shape = digitsAsHash(line)
                // Along the edges, whatever repeats. Elsewhere on the page (the header's title sometimes comes out in the middle of
                // the text) only a line with words in it: a number alone ("12") may be a cell of a table.
                if repeated.contains(shape), edges.contains(i) || line.filter(\.isLetter).count >= 8 {
                    report.running += 1
                } else {
                    kept.append(line)
                }
            }
            pages[p] = kept
        }
    }

    // MARK: Addresses

    /// A line that is only a web address (and perhaps the page counter after it).
    static func isAddressOnly(_ line: String) -> Bool {
        var sawAddress = false
        for token in line.split(separator: " ") {
            let t = token.trimmingCharacters(in: CharacterSet(charactersIn: "()[]<>.,;:\"'“”")).lowercased()
            if t.hasPrefix("http://") || t.hasPrefix("https://") || t.hasPrefix("www.") {
                sawAddress = true
            } else if t.range(of: #"^\d{1,4}/\d{1,4}$"#, options: .regularExpression) == nil {
                return false
            }
        }
        return sawAddress
    }

    // MARK: Reference lists

    private static let referenceHeadings: Set<String> = [
        "references", "notes", "bibliography", "sources", "works cited", "literatur", "einzelnachweise", "referencias",
    ]

    private static let citationSignals = try? NSRegularExpression(pattern: [
        #"^\[\d{1,3}\]"#,                                 // [2] Wong EY (a marker inside a sentence, "…as follows:[13]", is not one)
        #"\bet al\b"#,                                    // Smith et al.
        #"\bdoi\s*:|doi\.org|\bdoi\s+10\."#,              // doi:10.1000/182
        #"\b(?:Retrieved|Archived|Accessed|Updated)\b"#,  // Retrieved 2024-09-29
        #"\b(?:ISBN|ISSN|PMID|PMC\d|S2CID|Bibcode|arXiv|JSTOR|OCLC|CiteSeerX)\b"#,
        #"\((?:[^()]*\s)?(?:1[5-9]|20)\d\d[a-z]?(?:[-–/]\d{1,2}(?:[-–/]\d{1,2})?)?\)"#,   // (1995), (2016-09-01), (18 August 2017)
        #"^\d{1,3}\.\s+\p{Lu}"#,                          // 3. Çengel, Yunus A.
        #"\bpp?\.\s*\d"#,                                 // p. 299, pp. 75, 135
        #"https?://"#,
        #"\b(?:vol|no)\.\s*\d|\b\d+\s*\(\d+\)\s*:\s*\d+"#,  // Vol. 3, 20 (1): 19
    ].joined(separator: "|"), options: [.caseInsensitive])

    /// A line of a reference list: a bracketed number, "et al.", "doi:", "Retrieved", a year in parentheses, a page range, an address.
    static func looksLikeCitation(line: String) -> Bool {
        matches(citationSignals, line)
    }

    private static func words(_ line: String) -> Int { line.split(separator: " ").count }

    /// A sentence of the article: seven words or more and nothing of a citation in it.
    private static func isProse(_ line: String) -> Bool { words(line) >= 7 && !looksLikeCitation(line: line) }

    private static func isHeadingLike(_ line: String) -> Bool {
        words(line) <= 5 && line.first?.isUppercase == true && !line.hasSuffix(".") && !looksLikeCitation(line: line)
    }

    static func isReferenceHeading(_ line: String) -> Bool {
        var name = line.lowercased().trimmingCharacters(in: .whitespaces)
        if name.hasSuffix("[edit]") { name = String(name.dropLast(6)).trimmingCharacters(in: .whitespaces) }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: ":.").union(.whitespaces))
        return referenceHeadings.contains(name)
    }

    /// Where a reference list that starts after line `at` of `flat` ends (exclusive): at the first stretch of `articleWindow` lines with
    /// no sign of a citation in them and `articleSentences` or more sentences of the article, which means the article goes on (the list
    /// was in the middle of a file of two articles, or ended a chapter). The start of the stretch is its first sentence, and the line
    /// before it is given back to the article when it looks like its heading. The end of the document when there is no such stretch.
    /// (A stretch rather than a run of lines: a box beside the first paragraph interrupts it with a few short lines.)
    private static let articleWindow = 6
    private static let articleSentences = 4

    private static func referenceListEnd(after at: Int, in flat: [String]) -> Int {
        guard flat.count - (at + 1) >= articleWindow else { return flat.count }
        for j in (at + 1)...(flat.count - articleWindow) {
            let window = flat[j..<(j + articleWindow)]
            guard !window.contains(where: { looksLikeCitation(line: $0) }), window.filter(isProse).count >= articleSentences else { continue }
            guard var end = window.firstIndex(where: isProse) else { continue }
            if end - 1 > at, isHeadingLike(flat[end - 1]) { end -= 1 }
            return end
        }
        return flat.count
    }

    private static func dropReferenceLists(_ pages: inout [[String]], report: inout PDFCleaning) {
        var flat: [String] = []
        var pageOf: [Int] = []
        for (p, lines) in pages.enumerated() {
            for line in lines { flat.append(line); pageOf.append(p) }
        }
        var gone = Set<Int>()
        var at = 0
        while at < flat.count {
            guard isReferenceHeading(flat[at]) else { at += 1; continue }
            let end = referenceListEnd(after: at, in: flat)
            let entries = flat[(at + 1)..<end]
            // Only a list of citations: most of its lines carry one of the signs of a citation.
            if !entries.isEmpty, entries.filter({ looksLikeCitation(line: $0) }).count * 2 >= entries.count {
                gone.formUnion(at..<end)
                report.references += end - at
                at = end
            } else {
                at += 1
            }
        }
        guard !gone.isEmpty else { return }
        var rebuilt = Array(repeating: [String](), count: pages.count)
        for (i, line) in flat.enumerated() where !gone.contains(i) { rebuilt[pageOf[i]].append(line) }
        pages = rebuilt
    }

    // MARK: Letters spaced out

    /// "C l i n i c a l D i a b et es ." → "Clinical Diabetes .": a run of six or more pieces of one or two letters, most of them
    /// one, is a word whose letters a journal's typesetting spread apart. A space goes back where a capital follows a small letter.
    /// Nil when nothing in the line is spaced out. (A row of capitals, like the answers "T F T F T F", and a line of math are left alone.)
    static func collapsingSpacedLetters(_ line: String) -> String? {
        guard !isMathLike(line) else { return nil }
        let tokens = line.split(separator: " ").map(String.init)
        guard tokens.count >= 6 else { return nil }
        var out: [String] = []
        var run: [(core: String, trailing: String)] = []
        var changed = false

        func flush() {
            defer { run = [] }
            let singles = run.filter { $0.core.count == 1 }.count
            let small = run.reduce(0) { $0 + $1.core.filter(\.isLowercase).count }
            guard run.count >= 6, singles * 3 >= run.count * 2, small >= 3 else {
                out += run.map { $0.core + $0.trailing }
                return
            }
            var word = ""
            for piece in run {
                if let last = word.last, last.isLowercase, piece.core.first?.isUppercase == true { word += " " }
                word += piece.core
            }
            out.append(word + (run.last?.trailing ?? ""))
            changed = true
        }

        for token in tokens {
            let core = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
            let trailing = String(token.dropFirst(core.count))
            if (1...2).contains(core.count), core.allSatisfy(\.isLetter), token.hasPrefix(core) {
                run.append((core, trailing))
                // A piece that ends in punctuation ends the word.
                if !trailing.isEmpty { flush() }
            } else {
                flush()
                out.append(token)
            }
        }
        flush()
        return changed ? out.joined(separator: " ") : nil
    }
}
