import XCTest
@testable import Cramless

/// How much of a reading the questions reach: sections (headings, or windows of about 120 words), the share weighted by words, what is
/// left uncovered, and the share over several sources.
final class CoverageTests: XCTestCase {

    // MARK: Material

    /// A court opinion's worth of plain prose with no headings: `words` words in sentences of 14 to 24 words.
    static func opinion(words target: Int) -> String {
        let subjects = ["The plaintiff", "The defendant's guard", "The railroad", "A passenger", "The court", "The package", "The scales",
                        "The jury", "The conductor"]
        let verbs = ["carried", "pushed", "considered", "dropped", "observed", "owed", "failed to foresee", "held", "answered"]
        let objects = ["a small package wrapped in newspaper", "the duty of reasonable care to everyone nearby",
                       "the risk that a stranger could be hurt far away", "the explosion that followed on the crowded platform",
                       "the question of negligence that the jury had decided", "a wrong to the person standing at the scales"]
        let tails = ["before the train left the station", "as the opinion explains at length", "in the circumstances of this case",
                     "according to the record below", "and the judgment was therefore reversed", "which the law does not protect against"]
        var text = ""
        var n = 0
        while text.split(whereSeparator: \.isWhitespace).count < target {
            text += "\(subjects[n % subjects.count]) \(verbs[(n / 3) % verbs.count]) \(objects[(n / 2) % objects.count]) "
                + "\(tails[(n / 5) % tails.count]) in event number \(n)." + (n % 7 == 6 ? "\n\n" : " ")
            n += 1
        }
        return text
    }

    private func reading(_ title: String = "Palsgraf", words: Int = 5800) -> Coverage.Reading {
        let pages = TextPaginator.pages(from: Self.opinion(words: words))
        return Coverage.Reading(sourceID: UUID(), title: title,
                                pages: pages.map { Coverage.Page(index: $0.pageIndex, label: $0.label, lines: $0.lines) })
    }

    private func page(_ index: Int, _ lines: [String]) -> Coverage.Page {
        Coverage.Page(index: index, label: "\(index + 1)",
                      lines: lines.enumerated().map { TextLine(id: "p\(index).l\($0.offset)", text: $0.element, box: nil) })
    }

    /// A line of `n` words that reads as a sentence: capitalised and ended with a full stop.
    private func words(_ n: Int, _ word: String = "word") -> String {
        word.prefix(1).uppercased() + word.dropFirst() + String(repeating: " " + word, count: max(0, n - 1)) + "."
    }

    // MARK: Sections

    func testTextWithoutHeadingsIsCutIntoWindowsOfAboutAHundredAndTwentyWords() {
        let sections = Coverage.sections(of: reading())
        XCTAssertGreaterThan(sections.count, 40)
        // Every window but the last on its page has crossed 120 words, on the line that crossed it.
        for (_, onPage) in Dictionary(grouping: sections, by: \.pageIndex) {
            for section in onPage.dropLast() {
                XCTAssertGreaterThanOrEqual(section.words, Coverage.windowWords)
                XCTAssertLessThan(section.words, Coverage.windowWords + 40, "it ends on the line that crosses the window")
            }
        }
        for section in sections {
            XCTAssertNotNil(section.pageIndex)
            XCTAssertTrue(section.title.hasSuffix("…"), "a window is named by its first words: \(section.title)")
        }
        // A section never runs across a page, and every line is in exactly one section.
        let pages = reading().pages
        XCTAssertEqual(sections.flatMap(\.anchorIDs).count, pages.flatMap(\.lines).count)
        XCTAssertEqual(Set(sections.flatMap(\.anchorIDs)).count, pages.flatMap(\.lines).count)
        for section in sections {
            let prefixes = Set(section.anchorIDs.map { $0.split(separator: ".").first.map(String.init) ?? "" })
            XCTAssertEqual(prefixes.count, 1, "\(section.anchorIDs)")
        }
    }

    func testAHeadingAndWhatIsUnderItIsASection() {
        let p = page(0, ["The Facts", words(30), words(25), "The Holding", words(40), "A title", words(5)])
        let sections = Coverage.sections(of: p)
        XCTAssertEqual(sections.map(\.title), ["The Facts", "The Holding", "A title"])
        XCTAssertEqual(sections.map(\.words), [2 + 30 + 25, 2 + 40, 2 + 5])
        XCTAssertEqual(sections[0].anchorIDs, ["p0.l0", "p0.l1", "p0.l2"])
        XCTAssertEqual(sections[1].anchorIDs, ["p0.l3", "p0.l4"])
        // The one with a heading and five words is too short to count.
        XCTAssertNil(Coverage.coverage(sourceID: UUID(), title: "t", sections: [sections[2]], anchors: []))
        let counted = Coverage.coverage(sourceID: UUID(), title: "t", sections: sections, anchors: ["p0.l4"])
        XCTAssertEqual(counted?.sections, 2)
        XCTAssertEqual(counted?.words, 57 + 42)
        XCTAssertEqual(counted?.coveredWords, 42)
        XCTAssertEqual(counted?.uncovered.map(\.title), ["The Facts"])
    }

    func testALongSectionIsCutIntoWindowsToo() {
        let lines = ["Negligence"] + Array(repeating: "The court weighed the duty of care owed to a bystander far from the harm.", count: 40)
        let sections = Coverage.sections(of: page(0, lines))
        XCTAssertGreaterThan(sections.count, 3, "one heading over 500 words is not one idea")
        XCTAssertEqual(sections.first?.title, "Negligence")
        XCTAssertTrue(sections.dropFirst().allSatisfy { $0.title.hasSuffix("…") }, "the windows after it are named by their first words")
    }

    func testAWrappedLineIsNotAHeading() {
        // "The plaintiff was standing on the platform" is followed by a lowercase line, so it is the start of a sentence.
        let p = page(0, ["The plaintiff was standing on the platform", "of the station when the guard pushed a man", words(30)])
        XCTAssertEqual(Coverage.sections(of: p).count, 1)
        XCTAssertTrue(Coverage.sections(of: p)[0].title.hasPrefix("The plaintiff was standing"))
    }

    func testPageNumbersAndMarksAreNotReadingMatter() {
        let sections = Coverage.sections(of: page(0, ["87", "|", "· · ·", words(30)]))
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].anchorIDs, ["p0.l3"])
    }

    func testALectureIsReadInWindowsOfItsTranscript() {
        let segments = (0..<20).map { TranscriptSegment(id: "s\($0)", start: Double($0) * 10, end: Double($0) * 10 + 10, text: words(30, "talk")) }
        let sections = Coverage.windows(of: Array(segments.reversed()))
        XCTAssertEqual(sections.map(\.words), [120, 120, 120, 120, 120])
        XCTAssertEqual(sections.map(\.start), [0, 40, 80, 120, 160], "by start time, whatever the order they came in")
        XCTAssertTrue(sections.allSatisfy { $0.pageIndex == nil })
        let lecture = Coverage.Reading(sourceID: UUID(), title: "Lecture 7", segments: segments)
        let covered = Coverage.coverage(of: lecture, anchors: ["s9"])
        XCTAssertEqual(covered?.share ?? 0, 0.2, accuracy: 1e-9, "a question anchored to a segment covers its window")
    }

    func testADeckHasNothingToCover() {
        let deck = Coverage.Reading(sourceID: UUID(), title: "Classmate deck (21 cards)")
        XCTAssertTrue(Coverage.sections(of: deck).isEmpty)
        XCTAssertNil(Coverage.coverage(of: deck, anchors: ["p0.l0"]))
        XCTAssertNil(Coverage.summary([]))
    }

    // MARK: The share

    func testSixteenQuestionsOnAPalsgrafSizedReadingCoverLittleOfIt() {
        let palsgraf = reading()
        let sections = Coverage.sections(of: palsgraf)
        let total = palsgraf.pages.flatMap(\.lines).map { $0.text.split(separator: " ").count }.reduce(0, +)
        XCTAssertTrue((5800..<6000).contains(total), "\(total) words")

        // Sixteen questions, two to a passage, from the first stretch of the reading (what a generator that read only the start wrote).
        var anchors = Set<String>()
        for section in sections.prefix(8) { anchors.formUnion(section.anchorIDs.prefix(2)) }
        XCTAssertEqual(anchors.count, 16)
        let first = try! XCTUnwrap(Coverage.coverage(of: palsgraf, anchors: anchors))
        XCTAssertEqual(first.share, 0.17, accuracy: 0.02, "about a sixth of the reading")
        XCTAssertLessThan(first.share, 0.25)
        XCTAssertEqual(first.uncovered.count, first.sections - 8)
        XCTAssertEqual(first.uncovered.first?.pageIndex, sections[8].pageIndex, "the first section nothing asks about, in reading order")
        XCTAssertEqual(first.uncoveredWords, first.words - first.coveredWords)

        // Questions on the sections that were left raise it.
        var more = anchors
        for section in first.uncovered.prefix(20) { more.insert(section.anchorIDs[0]) }
        let second = try! XCTUnwrap(Coverage.coverage(of: palsgraf, anchors: more))
        XCTAssertGreaterThan(second.share, first.share + 0.3)
        XCTAssertEqual(second.uncovered.count, first.uncovered.count - 20)
        for section in first.uncovered { more.insert(section.anchorIDs[0]) }
        let all = try! XCTUnwrap(Coverage.coverage(of: palsgraf, anchors: more))
        XCTAssertEqual(all.share, 1)
        XCTAssertTrue(all.uncovered.isEmpty)
    }

    func testTheShareIsWeightedByWordsAndOnlyCountsAnchorsInTheSource() {
        // A long section and a short one: asking about the short one covers 25 of 125 words.
        let p = page(0, ["Long", words(98), "Short", words(23)])
        let sections = Coverage.sections(of: p)
        XCTAssertEqual(sections.map(\.words), [99, 24])
        let c = Coverage.coverage(sourceID: UUID(), title: "t", sections: sections, anchors: ["p0.l3", "elsewhere.l9"])
        XCTAssertEqual(c?.share ?? 0, 24.0 / 123.0, accuracy: 1e-9)
        XCTAssertEqual(Coverage.coverage(sourceID: UUID(), title: "t", sections: sections, anchors: [])?.share, 0)
        XCTAssertEqual(Coverage.coverage(sourceID: UUID(), title: "t", sections: sections, anchors: ["p0.l1", "p0.l3"])?.share, 1)
    }

    func testTheExamsShareIsWeightedOverItsSourcesAndNamesTheMainGap() throws {
        let big = reading("Palsgraf", words: 3000)
        let small = reading("Reading 2", words: 600)
        func covered(_ r: Coverage.Reading, sections n: Int) -> Coverage.SourceCoverage {
            var anchors = Set<String>()
            for section in Coverage.sections(of: r).prefix(n) { anchors.formUnion(section.anchorIDs) }
            return Coverage.coverage(of: r, anchors: anchors)!
        }
        let a = covered(big, sections: 3)
        let b = try XCTUnwrap(Coverage.coverage(of: small, anchors: Set(small.pages.flatMap(\.lines).map(\.id))))
        XCTAssertEqual(b.share, 1)
        let summary = try XCTUnwrap(Coverage.summary([a, b]))
        XCTAssertEqual(summary.words, a.words + b.words)
        XCTAssertEqual(summary.share, Double(a.coveredWords + b.coveredWords) / Double(a.words + b.words), accuracy: 1e-9)
        XCTAssertGreaterThan(summary.share, a.share, "the small, well-covered source lifts it, by its words")
        XCTAssertLessThan(summary.share, b.share)
        XCTAssertEqual(summary.mainGap?.title, "Palsgraf", "it holds nearly all of what is left")
        XCTAssertEqual(summary.biggestGap?.title, "Palsgraf")

        // One source on its own is the whole story: nothing to name.
        XCTAssertNil(Coverage.summary([a])?.mainGap)
        XCTAssertEqual(Coverage.summary([a])?.biggestGap?.title, "Palsgraf")
        // Two sources that share what is left evenly have no main gap, but the exam still has somewhere to add questions.
        let even = try XCTUnwrap(Coverage.summary([covered(reading("One", words: 1200), sections: 1), covered(reading("Two", words: 1200), sections: 1)]))
        XCTAssertNil(even.mainGap)
        XCTAssertNotNil(even.biggestGap)
        // Fully covered: no gap.
        let done = Coverage.coverage(of: small, anchors: Set(small.pages.flatMap(\.lines).map(\.id)))!
        XCTAssertEqual(Coverage.summary([done])?.share, 1)
        XCTAssertNil(Coverage.summary([done])?.biggestGap)
    }

    // MARK: An exam on some topics

    func testAnExamOnSomeTopicsDrawsOnTheStretchBetweenItsOwnQuestions() throws {
        // A reading of about forty passages whose third chapter is somewhere in the middle: the on-topic questions are in passages 14
        // to 19, and the one chapter 1 question (another topic) is in passage 2.
        let book = reading("Casebook", words: 5000)
        let sections = Coverage.sections(of: book)
        XCTAssertGreaterThan(sections.count, 30)
        let onTopic: Set<String> = [sections[14].anchorIDs[0], sections[17].anchorIDs[1], sections[19].anchorIDs[0]]
        let span = Coverage.span(of: sections, around: onTopic)
        XCTAssertEqual(span.first, sections[14])
        XCTAssertEqual(span.last, sections[19])
        XCTAssertEqual(span.count, 6, "from the first on-topic passage to the last, passages between them included")

        let scoped = try XCTUnwrap(Coverage.coverage(sourceID: book.sourceID, title: book.title, sections: span, anchors: onTopic))
        XCTAssertEqual(scoped.sections, 6)
        XCTAssertEqual(scoped.uncovered.count, 3, "the passages in between nobody has asked about")
        XCTAssertTrue(scoped.uncovered.allSatisfy { sections[14...19].contains($0) }, "nothing from the first chapter")
        // Counted over the whole reading the same questions would look like a sixth of it, for an exam that is on one chapter.
        let whole = try XCTUnwrap(Coverage.coverage(of: book, anchors: onTopic))
        XCTAssertLessThan(whole.share, 0.15)
        XCTAssertGreaterThan(scoped.share, 0.4)

        XCTAssertTrue(Coverage.span(of: sections, around: ["somewhere.else"]).isEmpty, "no anchor in the reading: nothing to go on")
        XCTAssertEqual(Coverage.span(of: sections, around: [sections[3].anchorIDs[0]]), [sections[3]], "one passage is a stretch of one")
    }

    // MARK: The rest, a tap at a time

    private func rest(_ book: Coverage.Reading, covering anchors: Set<String> = [], used: Set<Int> = [], limit: Int = 10) -> Coverage.Rest? {
        let c = Coverage.coverage(of: book, anchors: anchors)!
        return Coverage.rest(of: c, usedPages: used, pageLimit: limit)
    }

    func testTheRestIsTheLinesOfUncoveredPassagesOnAScansPagesInReadingOrder() throws {
        let book = reading("Casebook", words: 12_000)
        XCTAssertGreaterThan(book.pages.count, 12)
        let sections = Coverage.sections(of: book)
        let first = try XCTUnwrap(rest(book, covering: Set(sections[0].anchorIDs)))
        XCTAssertEqual(first.pages.count, 10, "a free scan's pages, and no more")
        XCTAssertEqual(first.pages, first.pages.sorted(), "in reading order")
        XCTAssertFalse(first.anchorIDs.contains(sections[0].anchorIDs[0]), "a passage with a question is not sent")
        XCTAssertFalse(first.startsOver)
        XCTAssertEqual(first.sections, sections.dropFirst().filter { $0.words >= Coverage.minimumWords && first.pages.contains($0.pageIndex ?? -1) }.count)
        XCTAssertGreaterThan(try XCTUnwrap(rest(book, limit: 40)).pages.count, 10, "a paid scan takes more pages than a free one")
        XCTAssertNil(rest(book, covering: Set(sections.flatMap(\.anchorIDs))), "everything has a question")
    }

    func testTheNextTapMovesOnToDifferentPassagesAndAFullRoundStartsAgain() throws {
        let book = reading("Casebook", words: 15_000)
        // Questions in none of the passages, as when every draft was left out in review: the same passages stay uncovered.
        var pages: [Int] = []
        for section in try XCTUnwrap(Coverage.coverage(of: book, anchors: [])).uncovered {
            if let page = section.pageIndex, !pages.contains(page) { pages.append(page) }
        }
        XCTAssertGreaterThan(pages.count, 20, "more than two scans' worth")
        let rounds = stride(from: 0, to: pages.count, by: 10).map { Array(pages[$0..<min($0 + 10, pages.count)]) }

        var used = Set<Int>()
        for expected in rounds {
            let plan = try XCTUnwrap(rest(book, used: used))
            XCTAssertEqual(plan.pages, expected, "each tap moves on to the pages after those the last ones used")
            XCTAssertFalse(plan.startsOver)
            XCTAssertTrue(used.isDisjoint(with: plan.pages))
            used.formUnion(plan.pages)
        }
        let wrapped = try XCTUnwrap(rest(book, used: used))
        XCTAssertTrue(wrapped.startsOver, "every page with something left has been through a run")
        XCTAssertEqual(wrapped.pages, rounds[0], "and the round begins again")
    }

    func testTheLinesAFormulasReadAddedJoinThePassageTheyFollowAndNoOther() {
        func lines(_ ids: [String]) -> [TextLine] { ids.map { TextLine(id: $0, text: "A line of the page.", box: nil) } }
        // Page 0 as a formulas read left it: the lines it always had ("p0.l…") and what the read added after them ("p0.c…").
        let merged = lines(["p0.l0", "p0.l1", "p0.c0", "p0.l2", "p0.l3", "p0.c1", "p0.c2", "p0.l4", "p0.c3"])
        let reading = Coverage.Reading(sourceID: UUID(), title: "Math", pages: [
            Coverage.Page(index: 0, label: "1", lines: merged),
            Coverage.Page(index: 1, label: "2", lines: lines(["p1.l0", "p1.c0"])),
        ])
        let plan = Coverage.Rest(sourceID: reading.sourceID, anchorIDs: ["p0.l0", "p0.l1", "p0.l3"], pages: [0], sections: 2, startsOver: false)
        // l0, l1 and l3 are the plan's. c0 follows l1, and c1 and c2 follow l3. c3 follows l4, which already has questions; page 1 is not
        // the plan's.
        XCTAssertEqual(Coverage.lineIDs(of: plan, in: reading), ["p0.l0", "p0.l1", "p0.c0", "p0.l3", "p0.c1", "p0.c2"])

        // A page read wholly by Cloud AI has only "c" lines and gained none: the plan's lines, as they were decided.
        let whole = Coverage.Reading(sourceID: reading.sourceID, title: "Photo", pages: [Coverage.Page(index: 0, label: "1", lines: lines(["p0.c0", "p0.c1", "p0.c2", "p0.c3"]))])
        let photo = Coverage.Rest(sourceID: whole.sourceID, anchorIDs: ["p0.c1", "p0.c2"], pages: [0], sections: 1, startsOver: false)
        XCTAssertEqual(Coverage.lineIDs(of: photo, in: whole), ["p0.c1", "p0.c2"])
        // A page nothing was added to is the plan's lines, as before.
        let plain = Coverage.Reading(sourceID: reading.sourceID, title: "Plain", pages: [Coverage.Page(index: 0, label: "1", lines: lines(["p0.l0", "p0.l1", "p0.l2"]))])
        let same = Coverage.Rest(sourceID: plain.sourceID, anchorIDs: ["p0.l1"], pages: [0], sections: 1, startsOver: false)
        XCTAssertEqual(Coverage.lineIDs(of: same, in: plain), ["p0.l1"])
        // A line the plan names that is gone stays named: the filter on the page drops it.
        XCTAssertTrue(Coverage.lineIDs(of: Coverage.Rest(sourceID: reading.sourceID, anchorIDs: ["p9.l0"], pages: [9], sections: 1, startsOver: false),
                                       in: reading).contains("p9.l0"))
    }

    func testARestSkipsPagesThatAreAllCoveredOrUsedButNeverTheOnesLeftOver() throws {
        let book = reading("Casebook", words: 4000)
        let sections = Coverage.sections(of: book)
        // Pages 0 and 1 are covered in full, page 2 was used: the next goes to page 3 first, then comes back to 2.
        let coveredPages = Set(sections.filter { ($0.pageIndex ?? 99) <= 1 }.flatMap(\.anchorIDs))
        let plan = try XCTUnwrap(rest(book, covering: coveredPages, used: [2], limit: 1))
        XCTAssertEqual(plan.pages, [3])
        let later = try XCTUnwrap(rest(book, covering: coveredPages, used: Set(2...book.pages.count), limit: 1))
        XCTAssertTrue(later.startsOver)
        XCTAssertEqual(later.pages, [2], "with every page left over used, the round begins at the first page with something left")
    }
}
