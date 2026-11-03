import Foundation

// How a reading is sized and cut for Cloud AI, and the plain sentences that say what happened. Pure values, so the
// splitting, the sharing out of questions and every note are tested without a relay (`GenerationPlanTests`).
//
// A free reading of more than 10 pages used to be refused by the relay in under a second and quietly written by this
// iPhone's weaker model instead. Now it is cut into the fewest parts the plan allows, slices of consecutive pages with
// similar word counts (14 even pages are 7 + 7, never 10 + 4), each part is a normal generate and check, and the relay
// counts each part as one scan, which is why the notes below say how many of the week's free scans a reading took.
// No request asks for more than 20 questions: a request writes them in one call at about three seconds each.

enum GenerationPlan {

    // MARK: Size

    /// Whitespace-separated words on a page, or across pages.
    static func wordCount(of page: PageText) -> Int {
        page.lines.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    static func wordCount(of pages: [PageText]) -> Int {
        pages.reduce(0) { $0 + wordCount(of: $1) }
    }

    /// The questions a set of pages earns on a plan (`AIFreeLimits.questionCount`).
    static func questionCount(for pages: [PageText], plan: Plan) -> Int {
        AIFreeLimits.questionCount(words: wordCount(of: pages), plan: plan)
    }

    // MARK: Parts

    struct Part: Equatable, Sendable {
        /// 1-based.
        var number: Int
        /// Indexes into the reading's pages.
        var pages: Range<Int>
        var words: Int
        /// The questions this part may ask for: at least a few (`minimumPerPart`), so no part is asked for none.
        var maxItems: Int
        /// The plan can pay for this part. False for the pages after the ones the scans left can read: they wait. Decided by the
        /// scans meter only, never by `maxItems`.
        var affordable = true
    }

    /// A part asks for at least this many questions (or all of them, when fewer are wanted): a part that is a few short pages next to
    /// a long one would otherwise share out to none and be skipped.
    static let minimumPerPart = 3

    /// The parts a reading goes to Cloud AI in, each a slice of consecutive pages with a share of the questions.
    ///
    /// - A part has at most `pageCap` pages (the plan's pages per scan) and asks for at most 20 questions
    ///   (`AIFreeLimits.maximumQuestionsPerRequest`).
    /// - There are as many parts as the page cap needs. A paid plan that deserves more than 20 questions has at least two
    ///   (it can afford the scans); a free reading is split by its page cap only, never to reach a higher count, so a free
    ///   reading that fits one scan asks for at most 20.
    /// - Parts have similar word counts (`split`), and the questions are shared out by words, each part getting at least
    ///   `minimumPerPart`.
    /// - `runnable` is how many parts the plan can still pay for (a free plan's weekly scans left). When that is fewer than the
    ///   reading needs, the scans that remain read as many pages as they can: that many parts of up to `pageCap` pages each, from
    ///   the start, and the pages after them wait (listed as parts that aren't `affordable`, without questions). One scan left
    ///   reads ten pages of fourteen, not seven.
    static func parts(pageWords: [Int], pageCap: Int, questions: Int, plan: Plan, runnable: Int? = nil) -> [Part] {
        let pages = pageWords.count
        guard pages > 0 else { return [] }
        let cap = max(1, pageCap)
        let perRequest = AIFreeLimits.maximumQuestionsPerRequest
        let byPages = (pages + cap - 1) / cap
        let byQuestions = plan.isPaid ? (questions + perRequest - 1) / perRequest : 1
        let needed = min(pages, max(1, byPages, byQuestions))

        // The parts the scans left can pay for, and the pages they read.
        let affordable = min(needed, max(0, runnable ?? needed))
        let readable = affordable == needed ? pages : min(pages, affordable * cap)
        let ranges = affordable == 0 ? [] : split(pageWords: Array(pageWords[0..<readable]), parts: affordable, cap: cap)
        // The pages that wait are listed too (as parts that aren't affordable), cut the way they would have been read.
        let waiting = affordable == needed ? [] : split(pageWords: Array(pageWords[readable...]), parts: 1, cap: cap)
            .map { ($0.lowerBound + readable)..<($0.upperBound + readable) }
        let words = (ranges + waiting).map { range in pageWords[range].reduce(0, +) }

        let total = min(questions, perRequest * ranges.count)
        let shares = shareOut(total, weights: Array(words.prefix(ranges.count)), maxPerPart: perRequest, minPerPart: minimumPerPart)
        return (ranges + waiting).enumerated().map { index, range in
            Part(number: index + 1, pages: range, words: words[index], maxItems: index < ranges.count ? shares[index] : 0,
                 affordable: index < ranges.count)
        }
    }

    /// `parts` slices of consecutive pages, each at most `cap` pages, cut so the parts have similar word counts: the cut
    /// that makes the longest part (in words) shortest wins, then the one with the most even parts; on a tie the longer part
    /// comes first. Equal pages give the fewest equal parts: 14 pages at 10 a scan are 7 + 7 (never 10 + 4), 11 are 6 + 5.
    /// Never fewer parts than the cap needs.
    static func split(pageWords: [Int], parts: Int, cap: Int) -> [Range<Int>] {
        let n = pageWords.count
        guard n > 0 else { return [] }
        let size = max(1, cap)
        let k = min(n, max(1, parts, (n + size - 1) / size))
        // Each page weighs its words plus one, so pages with no words still count as pages (and a text of empty pages is
        // cut evenly); the one is nothing next to a real page.
        var prefix = [0]
        for w in pageWords { prefix.append(prefix[prefix.count - 1] + max(0, w) + 1) }

        // best[j][i]: the best way to cut the first i pages into j parts, as (longest part, sum of squares, where the last
        // part starts).
        typealias Cost = (longest: Int, squares: Int, from: Int)
        var best = [[Cost?]](repeating: [Cost?](repeating: nil, count: n + 1), count: k + 1)
        best[0][0] = (0, 0, 0)
        for j in 1...k {
            guard j <= n else { break }
            for i in j...n {
                var choice: Cost?
                // The last part is pages from..<i, at most `size` of them, leaving at least j - 1 pages for the others.
                for from in stride(from: i - 1, through: max(j - 1, i - size), by: -1) {
                    guard let before = best[j - 1][from] else { continue }
                    let words = prefix[i] - prefix[from]
                    let candidate: Cost = (max(before.longest, words), before.squares + words * words, from)
                    if let current = choice, (candidate.longest, candidate.squares) >= (current.longest, current.squares) { continue }
                    choice = candidate
                }
                best[j][i] = choice
            }
        }
        var ranges: [Range<Int>] = []
        var end = n
        for j in stride(from: k, through: 1, by: -1) {
            guard let cost = best[j][end] else { break }
            ranges.append(cost.from..<end)
            end = cost.from
        }
        return ranges.reversed()
    }

    /// `total` questions shared out over parts in proportion to their weights (words; equal when all are 0), largest remainder
    /// first, ties to the earlier part. Every part gets at least `minPerPart` (fewer when there aren't that many to go round: `total`
    /// over the parts), and none more than `maxPerPart`: what a part can't take goes to the parts with room, the one furthest below
    /// its share first. The shares add up to `total` unless the parts can't hold it.
    static func shareOut(_ total: Int, weights: [Int], maxPerPart: Int = .max, minPerPart: Int = 0) -> [Int] {
        guard total > 0, !weights.isEmpty else { return weights.map { _ in 0 } }
        let w = weights.reduce(0, +) > 0 ? weights.map { max(0, $0) } : weights.map { _ in 1 }
        let floorEach = max(0, min(minPerPart, maxPerPart, total / weights.count))
        // The floors first; the rest goes by weight.
        let rest = total - floorEach * weights.count
        let sum = w.reduce(0, +)
        var extra = w.map { rest * $0 / sum }
        var left = rest - extra.reduce(0, +)
        let order = w.indices.sorted { a, b in
            let ra = rest * w[a] % sum, rb = rest * w[b] % sum
            return ra == rb ? a < b : ra > rb
        }
        for i in order where left > 0 {
            extra[i] += 1
            left -= 1
        }
        var shares = extra.map { $0 + floorEach }
        var excess = 0
        for i in shares.indices where shares[i] > maxPerPart {
            excess += shares[i] - maxPerPart
            shares[i] = maxPerPart
        }
        while excess > 0 {
            // The part furthest below its fair share (by weight) takes the next question.
            let room = w.indices.filter { shares[$0] < maxPerPart }
            let need = { (i: Int) in Double(w[i]) / Double(shares[i] + 1) }
            guard let i = room.max(by: { need($0) < need($1) || (need($0) == need($1) && $0 > $1) }) else { break }
            shares[i] += 1
            excess -= 1
        }
        return shares
    }

    // MARK: Words

    /// "page 9", "pages 1 to 7", "pages 1 to 7 and 15 to 21": the labels of the pages in `ranges` (indexes into
    /// `labels`), neighbouring ranges joined. `capitalized` starts a sentence with it.
    static func pages(_ ranges: [Range<Int>], labels: [String], capitalized: Bool = false) -> String {
        let merged = merge(ranges).filter { $0.lowerBound >= 0 && $0.upperBound <= labels.count && !$0.isEmpty }
        let pieces = merged.map { range -> String in
            range.count == 1 ? labels[range.lowerBound] : "\(labels[range.lowerBound]) to \(labels[range.upperBound - 1])"
        }
        let single = merged.count == 1 && merged[0].count == 1
        let phrase = (single ? "page " : "pages ") + list(pieces)
        return capitalized ? phrase.prefix(1).uppercased() + phrase.dropFirst() : phrase
    }

    private static func merge(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = out.last, range.lowerBound <= last.upperBound {
                out[out.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                out.append(range)
            }
        }
        return out
    }

    /// "a", "a and b", "a, b and c".
    static func list(_ pieces: [String]) -> String {
        switch pieces.count {
        case 0: ""
        case 1: pieces[0]
        default: pieces.dropLast().joined(separator: ", ") + " and " + pieces[pieces.count - 1]
        }
    }

    /// "1 idea", "3 ideas".
    static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    // MARK: Notes

    /// Said whenever a reading needed more than one part and every part was read:
    /// "Read in 2 parts (2 of your free scans this week)." On a paid plan there are no scans to count.
    static func partsNote(parts: Int, plan: Plan) -> String {
        plan.isPaid ? "Read in \(parts) parts." : "Read in \(parts) parts (\(parts) of your free scans this week)."
    }

    /// The free scans ran out between parts: "Cloud AI read pages 1 to 7. Pages 8 to 14 are waiting: this week's free
    /// scans are used up."
    static func limitNote(read: [Range<Int>], left: [Range<Int>], labels: [String]) -> String {
        let waiting = pages(left, labels: labels, capitalized: true)
        let verb = left.reduce(0) { $0 + $1.count } == 1 ? "is" : "are"
        return "Cloud AI read \(pages(read, labels: labels)). \(waiting) \(verb) waiting: this week's free scans are used up."
    }

    /// Part of the reading failed for another reason: "Cloud AI read pages 1 to 7, but couldn't read pages 8 to 14 this
    /// time. Try those pages again later."
    static func skippedNote(read: [Range<Int>], skipped: [Range<Int>], labels: [String]) -> String {
        let again = skipped.reduce(0) { $0 + $1.count } == 1 ? "that page" : "those pages"
        return "Cloud AI read \(pages(read, labels: labels)), but couldn't read \(pages(skipped, labels: labels)) this time. Try \(again) again later."
    }

    /// A set written again that couldn't read some pages keeps the questions it already had for them.
    static func keptEarlierNote(pages ranges: [Range<Int>], labels: [String]) -> String {
        "Kept the questions already written for \(pages(ranges, labels: labels))."
    }

    /// The second pass rejected everything, so this iPhone checked the questions against the page instead.
    static let checkedOnThisIPhoneNote =
        "Cloud AI wrote these; your iPhone checked them against the page because the second pass rejected everything."

    /// A lecture's questions stopped at the cap: "3 more ideas in the lecture weren't turned into questions."
    static func leftOutNote(_ n: Int) -> String? {
        guard n > 0 else { return nil }
        return n == 1 ? "1 more idea in the lecture wasn't turned into a question."
            : "\(n) more ideas in the lecture weren't turned into questions."
    }

    /// Joins the notes of a run into the one the review shows.
    static func joined(_ notes: [String?]) -> String? {
        let parts = notes.compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
