import Foundation

/// How much of a person's material their questions reach.
///
/// A reading is cut into sections the way a person would point at it: a heading with what is under it, and where there are no
/// headings (a pasted court opinion, a PDF's running text) windows of about 120 words. Anything longer than a window is cut into
/// windows too, so one heading over twenty pages doesn't count as one idea. A section is covered when at least one of the person's
/// active questions is anchored in it (an anchor is the id of a line of the page, or of a segment of a lecture). The share is
/// weighted by words, so a long section nothing asks about weighs more than a short one. Sections under 20 words (a page number, a
/// caption, a stray heading) are left out of both sides.
///
/// A lecture can be read the same way, in windows of about 120 words of its transcript, but the app leaves lectures out of every
/// share it shows (`AppModel+Coverage`): its notes are a summary of what was said, not a reading, and a lecture gets about ten
/// questions whatever its length, so a share of its transcript would be a gap nothing could close. A source with no text of its own
/// (an imported deck) has no sections and is left out: there is nothing to say it covers.
///
/// Pure and clock-free. It takes values (the pages as the retriever reads them, the anchor ids of the active questions) and gives
/// values back; `AppModel+Coverage` reads the store and caches the sections of each source.
enum Coverage {
    /// A section closes once it holds this many words (about; it ends on the line that crosses it).
    static let windowWords = 120
    /// Sections shorter than this are not counted.
    static let minimumWords = 20

    // MARK: Inputs

    /// One page of a reading, as the retriever and the generator see it.
    struct Page: Hashable, Sendable {
        var index: Int
        /// What the page calls itself: "87".
        var label: String
        var lines: [TextLine]

        init(index: Int, label: String, lines: [TextLine]) {
            self.index = index
            self.label = label
            self.lines = lines
        }
    }

    /// A source's own text: pages for a reading, transcript segments for a lecture. A deck has neither.
    struct Reading: Hashable, Sendable {
        var sourceID: UUID
        var title: String
        var pages: [Page] = []
        var segments: [TranscriptSegment] = []

        init(sourceID: UUID, title: String, pages: [Page] = [], segments: [TranscriptSegment] = []) {
            self.sourceID = sourceID
            self.title = title
            self.pages = pages
            self.segments = segments
        }
    }

    // MARK: Outputs

    /// A stretch of a source a question can be about.
    struct Section: Hashable, Sendable, Identifiable {
        /// The page it is on; nil for a window of a lecture.
        var pageIndex: Int?
        var pageLabel: String?
        /// The heading, or the first words.
        var title: String
        var words: Int
        /// The ids a question can be anchored to in it: the lines of the page, or the segments of the lecture.
        var anchorIDs: [String]
        /// Where a lecture window starts, in seconds.
        var start: Double?

        var id: String { "\(pageIndex ?? -1)/\(anchorIDs.first ?? title)" }
    }

    /// How much of one source the questions reach.
    struct SourceCoverage: Hashable, Sendable, Identifiable {
        var sourceID: UUID
        var title: String
        /// Words in the sections counted, and in those a question is anchored in.
        var words: Int
        var coveredWords: Int
        /// The sections counted.
        var sections: Int
        /// The sections no question is anchored in, in reading order.
        var uncovered: [Section]

        var id: UUID { sourceID }
        /// 0…1.
        var share: Double { words == 0 ? 1 : Double(coveredWords) / Double(words) }
        var uncoveredWords: Int { words - coveredWords }
    }

    /// How much of everything an exam draws on the questions reach.
    struct Summary: Hashable, Sendable {
        var sources: [SourceCoverage]
        var words: Int
        var coveredWords: Int
        /// 0…1, weighted by words over every source.
        var share: Double
        /// With more than one source: the source that holds most (three fifths) of what isn't reached ("Palsgraf: 18%").
        var mainGap: SourceCoverage?
        /// The source with the most left to cover: where "Add questions for the rest" works.
        var biggestGap: SourceCoverage?
    }

    /// The part of a source one "Add questions for the rest" writes questions from: the lines of passages no question reaches, on at
    /// most a scan's pages. It is decided once, when the person asks, and kept with the request, so a set written again (after Cloud AI
    /// is allowed, in the review) is written from the same lines even though the source is then waiting on its drafts.
    struct Rest: Hashable, Sendable, CustomStringConvertible {
        var sourceID: UUID
        /// The ids of the lines to write questions from.
        var anchorIDs: Set<String>
        /// The pages they are on, in reading order.
        var pages: [Int]
        /// The passages they make up.
        var sections: Int
        /// Every page with something left had been used by an earlier run, so this one begins the round again.
        var startsOver: Bool
        /// The kinds of question to write; nil: any.
        var formats: [ItemKind]? = nil

        /// Short, so a request carrying it stays cheap to identify.
        var description: String { "rest of \(sourceID): \(pages.count) pages, \(sections) passages" }
    }

    // MARK: Sections

    /// The sections of a source, in reading order: a page at a time (a section never runs across a page), with those under
    /// `minimumWords` still in the list (they are dropped when coverage is counted).
    static func sections(of reading: Reading) -> [Section] {
        if !reading.segments.isEmpty { return windows(of: reading.segments) }
        return reading.pages.sorted { $0.index < $1.index }.flatMap(sections(of:))
    }

    static func sections(of page: Page) -> [Section] {
        let lines = page.lines.compactMap { line -> (id: String, text: String)? in
            let text = line.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return isReadable(text) ? (line.id, text) : nil
        }
        let headings = headingFlags(lines.map(\.text))
        var out: [Section] = []
        var title: String?
        var ids: [String] = []
        var words = 0
        var first = ""

        func close() {
            guard !ids.isEmpty else { return }
            out.append(Section(pageIndex: page.index, pageLabel: page.label, title: title ?? firstWords(first), words: words,
                               anchorIDs: ids, start: nil))
            title = nil
            ids = []
            words = 0
            first = ""
        }
        for (i, line) in lines.enumerated() {
            if headings[i] {
                close()
                title = line.text
            }
            if ids.isEmpty { first = line.text }
            ids.append(line.id)
            words += wordCount(line.text)
            if words >= windowWords { close() }
        }
        close()
        return out
    }

    /// A lecture's transcript in windows of about `windowWords` words, by start time.
    static func windows(of segments: [TranscriptSegment]) -> [Section] {
        var out: [Section] = []
        var ids: [String] = []
        var words = 0
        var first = ""
        var start = 0.0
        func close() {
            guard !ids.isEmpty else { return }
            out.append(Section(pageIndex: nil, pageLabel: nil, title: firstWords(first), words: words, anchorIDs: ids, start: start))
            ids = []
            words = 0
            first = ""
        }
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let text = segment.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard isReadable(text) else { continue }
            if ids.isEmpty {
                first = text
                start = segment.start
            }
            ids.append(segment.id)
            words += wordCount(text)
            if words >= windowWords { close() }
        }
        close()
        return out
    }

    // MARK: Coverage

    /// How much of a source the anchors reach, from its sections. Nil when it has no section worth counting.
    static func coverage(sourceID: UUID, title: String, sections: [Section], anchors: Set<String>) -> SourceCoverage? {
        let counted = sections.filter { $0.words >= minimumWords }
        guard !counted.isEmpty else { return nil }
        var covered = 0
        var uncovered: [Section] = []
        for section in counted {
            if section.anchorIDs.contains(where: anchors.contains) { covered += section.words } else { uncovered.append(section) }
        }
        return SourceCoverage(sourceID: sourceID, title: title, words: counted.reduce(0) { $0 + $1.words },
                              coveredWords: covered, sections: counted.count, uncovered: uncovered)
    }

    static func coverage(of reading: Reading, anchors: Set<String>) -> SourceCoverage? {
        coverage(sourceID: reading.sourceID, title: reading.title, sections: sections(of: reading), anchors: anchors)
    }

    /// The ids of the lines a rest is written from when its pages may have gained lines since it was decided. A formulas read puts the
    /// formulas it finds beside the lines they follow, under ids of their own (`PageLayout.merged`: "p3.c4" on a page whose own lines
    /// are "p3.l0…"), and the plan, made before they existed, doesn't name them. So the plan's lines are joined, on the plan's pages, by the
    /// lines a read added right after them, up to the next line the page always had: a formula goes with the passage it belongs to,
    /// and not with a neighbouring one that already has questions. (A page read wholly by Cloud AI has only "c" lines and gained none.)
    static func lineIDs(of plan: Rest, in reading: Reading) -> Set<String> {
        var ids = plan.anchorIDs
        for page in reading.pages where plan.pages.contains(page.index) {
            let added = "p\(page.index).c"
            guard page.lines.contains(where: { $0.id.hasPrefix(added) }), page.lines.contains(where: { !$0.id.hasPrefix(added) }) else { continue }
            var following = false
            for line in page.lines {
                if plan.anchorIDs.contains(line.id) {
                    following = true
                } else if line.id.hasPrefix(added) {
                    if following { ids.insert(line.id) }
                } else {
                    following = false
                }
            }
        }
        return ids
    }

    /// The stretch of a reading an exam on some topics draws on, as far as the data shows it. A source doesn't record which topic a
    /// passage belongs to, only the questions made from it do, so with nothing else to go on a reading's chapters are taken to run
    /// in order: from the first passage an on-topic question is anchored in to the last. Empty when none of the anchors is in the
    /// sections.
    static func span(of sections: [Section], around anchors: Set<String>) -> [Section] {
        let holds: (Section) -> Bool = { $0.anchorIDs.contains(where: anchors.contains) }
        guard let first = sections.firstIndex(where: holds), let last = sections.lastIndex(where: holds) else { return [] }
        return Array(sections[first...last])
    }

    // MARK: The rest

    /// What the next "Add questions for the rest" of a source works on: the passages no question reaches, in reading order, on at most
    /// `pageLimit` pages (what one scan takes). Pages a run already used (`usedPages`, kept per source) come last: a passage whose
    /// questions were left out in review stays uncovered, and would be sent first every time. With every page that has something left
    /// already used, the round begins again (`startsOver`). Nil when nothing is left.
    static func rest(of coverage: SourceCoverage, usedPages: Set<Int>, pageLimit: Int) -> Rest? {
        let left = coverage.uncovered.filter { $0.pageIndex != nil }
        guard !left.isEmpty else { return nil }
        var fresh = left.filter { !usedPages.contains($0.pageIndex ?? -1) }
        let startsOver = fresh.isEmpty
        if startsOver { fresh = left }
        var pages: [Int] = []
        var chosen: [Section] = []
        for section in fresh {
            guard let page = section.pageIndex else { continue }
            if !pages.contains(page) {
                if pages.count >= max(1, pageLimit) { break }
                pages.append(page)
            }
            chosen.append(section)
        }
        return Rest(sourceID: coverage.sourceID, anchorIDs: Set(chosen.flatMap(\.anchorIDs)), pages: pages, sections: chosen.count,
                    startsOver: startsOver)
    }

    /// The share over several sources, weighted by words. Nil when none had anything to count.
    static func summary(_ sources: [SourceCoverage]) -> Summary? {
        let words = sources.reduce(0) { $0 + $1.words }
        guard words > 0 else { return nil }
        let covered = sources.reduce(0) { $0 + $1.coveredWords }
        let left = words - covered
        let biggest = sources.filter { $0.uncoveredWords > 0 }
            .sorted { $0.uncoveredWords != $1.uncoveredWords ? $0.uncoveredWords > $1.uncoveredWords : $0.title < $1.title }
            .first
        var main: SourceCoverage?
        if sources.count > 1, let biggest, left > 0, biggest.uncoveredWords * 5 >= left * 3 { main = biggest }
        return Summary(sources: sources, words: words, coveredWords: covered, share: Double(covered) / Double(words),
                       mainGap: main, biggestGap: biggest)
    }

    // MARK: Reading the lines

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// A line with words in it: not a page number, a rule or a stray mark.
    private static func isReadable(_ text: String) -> Bool {
        text.count > 2 && text.contains(where: \.isLetter)
    }

    /// The first words of a section with no heading: "The plaintiff was standing on a platform of…".
    private static func firstWords(_ text: String, count: Int = 7) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        let head = words.prefix(count).joined(separator: " ")
        return words.count > count ? head + "…" : head
    }

    /// Which lines are headings, as the page reader sees them: short, capitalised, no sentence punctuation, and not a wrapped line of
    /// a paragraph (a "heading" followed by a lowercase line). A bullet or a "Term: meaning" line is never one.
    private static func headingFlags(_ texts: [String]) -> [Bool] {
        texts.indices.map { i in
            let text = texts[i]
            guard PageStructure.isHeadingText(text), !PageStructure.isBullet(text), PageStructure.lineDefinition(text) == nil else {
                return false
            }
            if !text.hasSuffix("?"), !text.contains(":"), i + 1 < texts.count, texts[i + 1].first?.isLowercase == true { return false }
            return true
        }
    }
}
