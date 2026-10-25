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
