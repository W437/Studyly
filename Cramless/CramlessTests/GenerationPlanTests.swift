import XCTest
@testable import Cramless

/// How a reading is sized and cut for Cloud AI: the number of questions a source earns, the equal parts a long reading
/// goes in, how the questions are shared out over them, and the plain sentences that say what happened. Pure values.
final class GenerationPlanTests: XCTestCase {

    // MARK: How many questions

    func testAboutOneQuestionPerHundredFiftyWordsAtLeastEightAtMostTwentyFourFree() {
        let free: [(words: Int, questions: Int)] = [
            (0, 8), (90, 8), (1_200, 8), (1_500, 10), (1_955, 13), (3_000, 20), (3_600, 24), (3_910, 24), (5_820, 24),
            (40_000, 24),
        ]
        for (words, questions) in free {
            XCTAssertEqual(AIFreeLimits.questionCount(words: words, plan: .free), questions, "\(words) words, free")
        }
        let paid: [(words: Int, questions: Int)] = [(0, 8), (1_955, 13), (3_910, 26), (5_820, 39), (6_000, 40), (40_000, 40)]
        for plan in [Plan.pro, .squad, .pass] {
            for (words, questions) in paid {
                XCTAssertEqual(AIFreeLimits.questionCount(words: words, plan: plan), questions, "\(words) words, \(plan)")
            }
        }
    }

    func testWordsAreCountedAcrossEveryPageLine() {
        let lines = [TextLine(id: "p0.l0", text: "Mitosis makes two cells.", box: nil), TextLine(id: "p0.l1", text: "  Meiosis   makes four! ", box: nil)]
        let pages = [PageText(index: 0, label: "1", lines: lines), PageText(index: 1, label: "2", lines: [TextLine(id: "p1.l0", text: "Done", box: nil)])]
        XCTAssertEqual(GenerationPlan.wordCount(of: pages), 4 + 3 + 1)
        XCTAssertEqual(GenerationPlan.questionCount(for: pages, plan: .free), 8)
    }

    func testTheLimitsAreTheRelaysPageRuleAndLectureSize() {
        XCTAssertEqual(AIFreeLimits.pagesPerScan(.free), 10)
        XCTAssertEqual(AIFreeLimits.pagesPerScan(.pro), 40)
        XCTAssertEqual(AIFreeLimits.lectureQuestions, 10)
        XCTAssertEqual(AIFreeLimits.onDeviceQuestions, 16)
        XCTAssertEqual(LectureInput(course: "", title: "", segments: [], flags: []).maxItems, 10)
    }

    // MARK: Parts

    private func even(_ pages: Int, words: Int = 100) -> [Int] { Array(repeating: words, count: pages) }

    func testEvenPagesGoInTheFewestEqualPartsNeverTenPlusFour() {
        func cut(_ pages: Int, cap: Int = 10) -> [Range<Int>] {
            GenerationPlan.split(pageWords: even(pages), parts: (pages + cap - 1) / cap, cap: cap)
        }
        XCTAssertEqual(cut(14), [0..<7, 7..<14])
        XCTAssertEqual(cut(11), [0..<6, 6..<11], "the longer part comes first")
        XCTAssertEqual(cut(10), [0..<10])
        XCTAssertEqual(cut(1), [0..<1])
        XCTAssertEqual(cut(21), [0..<7, 7..<14, 14..<21])
        XCTAssertEqual(cut(25), [0..<9, 9..<17, 17..<25])
        XCTAssertEqual(cut(41, cap: 40), [0..<21, 21..<41])
        XCTAssertEqual(GenerationPlan.split(pageWords: [], parts: 2, cap: 10), [])
        XCTAssertEqual(GenerationPlan.split(pageWords: even(3), parts: 3, cap: 0), [0..<1, 1..<2, 2..<3], "a cap under one page is one page")
        for pages in 1...120 {
            let parts = cut(pages)
            XCTAssertEqual(parts.map(\.count).reduce(0, +), pages)
            XCTAssertTrue(parts.allSatisfy { $0.count <= 10 })
            XCTAssertLessThanOrEqual((parts.map(\.count).max() ?? 0) - (parts.map(\.count).min() ?? 0), 1, "\(pages) pages")
            XCTAssertEqual(parts.count, (pages + 9) / 10, "the fewest parts for \(pages) pages")
            XCTAssertEqual(parts.first?.lowerBound, 0)
            for (a, b) in zip(parts, parts.dropFirst()) { XCTAssertEqual(a.upperBound, b.lowerBound) }
        }
    }

    func testPartsHaveSimilarWordCountsNotJustPageCounts() {
        // Ten pages of 100 words and a long last one: 14 pages can't be 7 + 7 by words.
        let words = even(13) + [900]
        let parts = GenerationPlan.split(pageWords: words, parts: 2, cap: 10)
        XCTAssertEqual(parts, [0..<10, 10..<14], "1,000 and 1,200 words, the most even cut the page cap allows")
        // Two short pages and a long one for two parts: the long one stands alone.
        XCTAssertEqual(GenerationPlan.split(pageWords: [100, 100, 1_000], parts: 2, cap: 40), [0..<2, 2..<3])
        // A heavy page in the middle.
        XCTAssertEqual(GenerationPlan.split(pageWords: [100, 100, 100, 600, 100, 100, 100], parts: 2, cap: 10), [0..<4, 4..<7])
        // Pages without words are still pages.
        XCTAssertEqual(GenerationPlan.split(pageWords: even(14, words: 0), parts: 2, cap: 10), [0..<7, 7..<14])
        // Never fewer parts than the cap needs, whatever is asked.
        XCTAssertEqual(GenerationPlan.split(pageWords: even(14), parts: 1, cap: 10).count, 2)
        XCTAssertEqual(GenerationPlan.split(pageWords: even(2), parts: 5, cap: 10).count, 2, "never more parts than pages")
    }

    func testQuestionsAreSharedOutByWordsAndNoRequestAsksForMoreThanTwenty() {
        XCTAssertEqual(GenerationPlan.shareOut(24, weights: [700, 700]), [12, 12])
        XCTAssertEqual(GenerationPlan.shareOut(25, weights: [700, 700]), [13, 12], "the odd one goes to the earlier part")
        XCTAssertEqual(GenerationPlan.shareOut(24, weights: [900, 800, 800]), [8, 8, 8], "the two larger remainders each get one")
        XCTAssertEqual(GenerationPlan.shareOut(8, weights: [3, 3, 3]), [3, 3, 2])
        XCTAssertEqual(GenerationPlan.shareOut(24, weights: [1_000]), [24])
        XCTAssertEqual(GenerationPlan.shareOut(24, weights: [0, 0]), [12, 12], "no words at all: even")
        XCTAssertEqual(GenerationPlan.shareOut(0, weights: [4, 4]), [0, 0])
        XCTAssertEqual(GenerationPlan.shareOut(10, weights: []), [])
        // 40 questions over 55 and 45 percent of the words would be 22 and 18: no request takes 22.
        XCTAssertEqual(GenerationPlan.shareOut(40, weights: [550, 450], maxPerPart: 20), [20, 20])
        XCTAssertEqual(GenerationPlan.shareOut(39, weights: [1, 1], maxPerPart: 20), [20, 19])
        XCTAssertEqual(GenerationPlan.shareOut(40, weights: [100, 100, 1_000], maxPerPart: 20), [10, 10, 20],
                       "the heavy part takes 20 and the others share what is left")
        for total in 1...40 {
            for weights in [[5, 5], [6, 5], [9, 8, 8], [21, 20], [7, 7, 7], [1, 1, 1, 1, 1, 1, 1], [550, 450]] {
                let shares = GenerationPlan.shareOut(total, weights: weights, maxPerPart: 20)
                XCTAssertEqual(shares.reduce(0, +), min(total, 20 * weights.count), "\(total) over \(weights)")
                XCTAssertTrue(shares.allSatisfy { $0 <= 20 })
            }
        }
    }

    func testNoPartIsSharedOutToNoQuestionsWhileThereAreQuestionsToShare() {
        // One long page next to a few short ones: by words alone the short part's share rounds to nothing.
        XCTAssertEqual(GenerationPlan.shareOut(8, weights: [1_000, 55]), [8, 0], "by words alone")
        XCTAssertEqual(GenerationPlan.shareOut(8, weights: [1_000, 55], maxPerPart: 20, minPerPart: 3), [5, 3])
        XCTAssertEqual(GenerationPlan.shareOut(8, weights: [1_000, 5, 5], maxPerPart: 20, minPerPart: 3), [4, 2, 2],
                       "fewer than three each to go round: the same for all, the rest by words")
        XCTAssertEqual(GenerationPlan.shareOut(2, weights: [1, 1, 1], maxPerPart: 20, minPerPart: 3), [1, 1, 0],
                       "two questions can't reach three parts")
        XCTAssertEqual(GenerationPlan.shareOut(24, weights: [1_000, 55], maxPerPart: 20, minPerPart: 3), [20, 4], "the cap still holds")
        var checked = 0
        for total in 1...40 {
            for weights in [[5, 5], [1_000, 55], [1, 1_000], [9, 8, 8], [1_000, 5, 5], [21, 20], [0, 0], [0, 7], [700, 1, 1, 1]] {
                let shares = GenerationPlan.shareOut(total, weights: weights, maxPerPart: 20, minPerPart: 3)
                XCTAssertEqual(shares.reduce(0, +), min(total, 20 * weights.count), "\(total) over \(weights)")
                XCTAssertTrue(shares.allSatisfy { $0 <= 20 }, "\(total) over \(weights): \(shares)")
                XCTAssertTrue(shares.allSatisfy { $0 >= min(3, total / weights.count) }, "\(total) over \(weights): \(shares)")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 40 * 9)
    }

    func testAShortPartNextToALongPageIsStillAskedAndNeverReadAsScansUsedUp() {
        // The free 11-page PDF: one 1,000-word page and ten pages of five words, eight questions.
        let words = [1_000] + Array(repeating: 5, count: 10)
        let parts = GenerationPlan.parts(pageWords: words, pageCap: 10, questions: 8, plan: .free)
        XCTAssertEqual(parts.map(\.pages), [0..<1, 1..<11])
        XCTAssertEqual(parts.map(\.maxItems), [5, 3], "was [8, 0]")
        XCTAssertEqual(parts.map(\.affordable), [true, true], "nothing was left out for the scans")
        // With scans left for both, both are read.
        XCTAssertEqual(GenerationPlan.parts(pageWords: words, pageCap: 10, questions: 8, plan: .free, runnable: 3).map(\.affordable), [true, true])
        XCTAssertEqual(GenerationPlan.parts(pageWords: words, pageCap: 10, questions: 8, plan: .free, runnable: 2).map(\.affordable), [true, true])
        // A paid plan: the same, with nothing to run out.
        XCTAssertEqual(GenerationPlan.parts(pageWords: words, pageCap: 40, questions: 8, plan: .pro).map(\.maxItems), [8])
        // Whatever the words, a part that is afforded asks for something, and only a part the scans can't pay for asks for none.
        for questions in [8, 13, 24] {
            for shape in [words, Array(repeating: 100, count: 14), [900, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 900], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]] {
                for runnable in [nil, 3, 2, 1, 0] as [Int?] {
                    for part in GenerationPlan.parts(pageWords: shape, pageCap: 10, questions: questions, plan: .free, runnable: runnable) {
                        XCTAssertEqual(part.maxItems == 0, !part.affordable, "\(shape.count) pages, \(questions) questions, runnable \(String(describing: runnable)): \(part)")
                    }
                }
            }
        }
    }

    func testAFreeReadingIsSplitByItsPageCapOnly() {
        // 14 pages: 2 parts of 7 pages, 12 questions each, 2 scans.
        let fourteen = GenerationPlan.parts(pageWords: even(14), pageCap: 10, questions: 24, plan: .free)
        XCTAssertEqual(fourteen, [GenerationPlan.Part(number: 1, pages: 0..<7, words: 700, maxItems: 12),
                                  GenerationPlan.Part(number: 2, pages: 7..<14, words: 700, maxItems: 12)])
        // Ten pages fit one scan, and a request asks for at most 20 even when the reading deserves 24: no second scan
        // to reach a higher count.
        let ten = GenerationPlan.parts(pageWords: even(10, words: 400), pageCap: 10, questions: 24, plan: .free)
        XCTAssertEqual(ten.map(\.pages), [0..<10])
        XCTAssertEqual(ten.map(\.maxItems), [20])
        XCTAssertEqual(GenerationPlan.parts(pageWords: even(6), pageCap: 10, questions: 8, plan: .free).map(\.maxItems), [8])
        // A longer one is still 24 in all, over three parts.
        XCTAssertEqual(GenerationPlan.parts(pageWords: even(25), pageCap: 10, questions: 24, plan: .free).map(\.maxItems), [8, 8, 8])
        XCTAssertEqual(GenerationPlan.parts(pageWords: [], pageCap: 10, questions: 24, plan: .free), [])
    }

    func testAPaidReadingAboveTwentySplitsInTwoAndNeverAsksForMoreThanTwentyAtOnce() {
        let two = GenerationPlan.parts(pageWords: even(10, words: 600), pageCap: 40, questions: 39, plan: .pro)
        XCTAssertEqual(two.map(\.pages), [0..<5, 5..<10], "similar word counts")
        XCTAssertEqual(two.map(\.maxItems), [20, 19])
        XCTAssertEqual(GenerationPlan.parts(pageWords: even(10), pageCap: 40, questions: 40, plan: .squad).map(\.maxItems), [20, 20])
        // 20 or fewer is one request.
        XCTAssertEqual(GenerationPlan.parts(pageWords: even(10), pageCap: 40, questions: 20, plan: .pro).map(\.maxItems), [20])
        XCTAssertEqual(GenerationPlan.parts(pageWords: even(10), pageCap: 40, questions: 21, plan: .pass).map(\.maxItems), [11, 10])
        // One page can't be cut: it takes 20.
        XCTAssertEqual(GenerationPlan.parts(pageWords: [5_000], pageCap: 40, questions: 40, plan: .pro).map(\.maxItems), [20])
        // More pages than a scan holds: the page cap sets the parts, and the questions are shared over them.
        let hundred = GenerationPlan.parts(pageWords: even(100), pageCap: 40, questions: 40, plan: .pro)
        XCTAssertEqual(hundred.map(\.pages.count), [34, 33, 33])
        XCTAssertEqual(hundred.map(\.maxItems), [14, 13, 13])
        // A heavy part takes at most 20 and the rest go to the other.
        XCTAssertEqual(GenerationPlan.parts(pageWords: [550, 450], pageCap: 40, questions: 40, plan: .pro).map(\.maxItems), [20, 20])
    }

    func testQuestionsAreSharedOverThePartsThePlanCanStillPayFor() {
        // One free scan left: the first part is a whole scan of pages and asks for its 20; the pages after it wait, unasked.
        let one = GenerationPlan.parts(pageWords: even(14), pageCap: 10, questions: 24, plan: .free, runnable: 1)
        XCTAssertEqual(one.map(\.maxItems), [20, 0])
        XCTAssertEqual(one.map(\.affordable), [true, false])
        XCTAssertEqual(GenerationPlan.parts(pageWords: even(14), pageCap: 10, questions: 24, plan: .free, runnable: 0).map(\.maxItems), [0, 0])
        XCTAssertEqual(GenerationPlan.parts(pageWords: even(14), pageCap: 10, questions: 24, plan: .free, runnable: 0).map(\.affordable), [false, false])
        XCTAssertEqual(GenerationPlan.parts(pageWords: even(14), pageCap: 10, questions: 24, plan: .free, runnable: nil).map(\.maxItems), [12, 12])
        // Two scans left of three parts' worth: two whole scans of pages, shared by words (1,000 and 1,000).
        let two = GenerationPlan.parts(pageWords: even(25), pageCap: 10, questions: 24, plan: .free, runnable: 2)
        XCTAssertEqual(two.map(\.maxItems), [12, 12, 0])
        XCTAssertEqual(two.map(\.affordable), [true, true, false])
        // Halved after the relay refused the page count.
        XCTAssertEqual(GenerationPlan.parts(pageWords: even(14), pageCap: 5, questions: 24, plan: .free).map(\.pages.count), [5, 5, 4])
    }

    func testTheScansThatRemainReadAsManyPagesAsTheyCan() {
        // 14 pages, one scan left: the scan takes ten pages (it was seven, with three pages' worth of the scan wasted).
        let one = GenerationPlan.parts(pageWords: even(14), pageCap: 10, questions: 24, plan: .free, runnable: 1)
        XCTAssertEqual(one.map(\.pages), [0..<10, 10..<14])
        XCTAssertEqual(one.map(\.affordable), [true, false])
        // 25 pages, two scans left: twenty pages (it was seventeen).
        let two = GenerationPlan.parts(pageWords: even(25), pageCap: 10, questions: 24, plan: .free, runnable: 2)
        XCTAssertEqual(two.map(\.pages), [0..<10, 10..<20, 20..<25])
        XCTAssertEqual(two.filter(\.affordable).map { $0.pages.count }, [10, 10])
        // 25 pages, one scan left; 11 pages, one scan left.
        XCTAssertEqual(GenerationPlan.parts(pageWords: even(25), pageCap: 10, questions: 24, plan: .free, runnable: 1).filter(\.affordable).map(\.pages), [0..<10])
        XCTAssertEqual(GenerationPlan.parts(pageWords: even(11), pageCap: 10, questions: 24, plan: .free, runnable: 1).map(\.pages), [0..<10, 10..<11])
        // As many scans as the reading needs, or more: nothing waits, and the parts are the even ones.
        for runnable in [3, 4, nil] as [Int?] {
            let all = GenerationPlan.parts(pageWords: even(25), pageCap: 10, questions: 24, plan: .free, runnable: runnable)
            XCTAssertEqual(all.map(\.pages.count), [9, 8, 8], "\(String(describing: runnable))")
            XCTAssertTrue(all.allSatisfy(\.affordable))
        }
        // The pages that wait are listed in order after the ones read, so the notes can name them, and the whole reading is accounted for.
        for runnable in [0, 1, 2, 3] {
            let parts = GenerationPlan.parts(pageWords: even(25), pageCap: 10, questions: 24, plan: .free, runnable: runnable)
            XCTAssertEqual(parts.first?.pages.lowerBound, 0)
            XCTAssertEqual(parts.last?.pages.upperBound, 25)
            XCTAssertEqual(zip(parts, parts.dropFirst()).filter { $0.pages.upperBound != $1.pages.lowerBound }.count, 0)
            XCTAssertEqual(parts.filter(\.affordable).count, min(runnable, 3))
            XCTAssertTrue(parts.filter(\.affordable).allSatisfy { $0.pages.count <= 10 })
        }
    }

    func testTheRelaysTimeAndTheCostOfARequestStillAgreeWithTheSizesOfTheParts() {
        // The relay lets a generate take 115 s; the app waits 120 s. A question takes about 3.3 s to write (a live request for 14 took
        // 46 s), so the 20 a request may ask for take about 66 s: well inside both.
        XCTAssertEqual(AIFreeLimits.maximumQuestionsPerRequest, 20)
        XCTAssertGreaterThan(HTTPRelayTransport.Route.generate.timeout, 115)
        XCTAssertLessThan(Double(AIFreeLimits.maximumQuestionsPerRequest) * 3.3, 115)
        // The free set is at most 24 questions in at most two requests of 12 (about 3 cents in all); the paid one 40 in two of 20 (about 5).
        let free = GenerationPlan.parts(pageWords: even(14), pageCap: 10, questions: AIFreeLimits.questionCount(words: 5_820, plan: .free), plan: .free)
        XCTAssertEqual(free.map(\.maxItems), [12, 12])
        let paid = GenerationPlan.parts(pageWords: even(14), pageCap: 40, questions: AIFreeLimits.questionCount(words: 5_820, plan: .pro) + 1, plan: .pro)
        XCTAssertEqual(paid.map(\.maxItems), [20, 20])
        for plan in [Plan.free, .pro, .squad, .pass] {
            for pages in [1, 3, 10, 11, 14, 25, 100] {
                for words in [200, 1_500, 6_000, 60_000] {
                    let parts = GenerationPlan.parts(pageWords: even(pages, words: max(1, words / pages)), pageCap: AIFreeLimits.pagesPerScan(plan),
                                                     questions: AIFreeLimits.questionCount(words: words, plan: plan), plan: plan)
                    XCTAssertTrue(parts.allSatisfy { Double($0.maxItems) * 3.3 < 115 }, "\(plan), \(pages) pages, \(words) words")
                    if !plan.isPaid {
                        XCTAssertLessThanOrEqual(parts.map(\.maxItems).reduce(0, +), 24, "a free set is never more than 24")
                    } else {
                        XCTAssertLessThanOrEqual(parts.map(\.maxItems).reduce(0, +), 40)
                    }
                }
            }
        }
    }

    // MARK: Words

    private let labels = (1...14).map(String.init)

    func testPagePhrases() {
        XCTAssertEqual(GenerationPlan.pages([0..<7], labels: labels), "pages 1 to 7")
        XCTAssertEqual(GenerationPlan.pages([13..<14], labels: labels), "page 14")
        XCTAssertEqual(GenerationPlan.pages([7..<14], labels: labels, capitalized: true), "Pages 8 to 14")
        XCTAssertEqual(GenerationPlan.pages([0..<7, 7..<14], labels: labels), "pages 1 to 14", "neighbours join")
        XCTAssertEqual(GenerationPlan.pages([0..<3, 9..<12], labels: labels), "pages 1 to 3 and 10 to 12")
        XCTAssertEqual(GenerationPlan.pages([1..<2, 4..<5], labels: labels), "pages 2 and 5")
        // The pages carry their own labels: a scan of printed pages 87 to 93.
        XCTAssertEqual(GenerationPlan.pages([0..<7], labels: (87...93).map(String.init)), "pages 87 to 93")
    }

    func testTheNotesAreShortAndPlain() {
        XCTAssertEqual(GenerationPlan.partsNote(parts: 2, plan: .free), "Read in 2 parts (2 of your free scans this week).")
        XCTAssertEqual(GenerationPlan.partsNote(parts: 3, plan: .free), "Read in 3 parts (3 of your free scans this week).")
        XCTAssertEqual(GenerationPlan.partsNote(parts: 2, plan: .pro), "Read in 2 parts.")
        XCTAssertEqual(GenerationPlan.limitNote(read: [0..<7], left: [7..<14], labels: labels),
                       "Cloud AI read pages 1 to 7. Pages 8 to 14 are waiting: this week's free scans are used up.")
        XCTAssertEqual(GenerationPlan.limitNote(read: [0..<13], left: [13..<14], labels: labels),
                       "Cloud AI read pages 1 to 13. Page 14 is waiting: this week's free scans are used up.")
        XCTAssertEqual(GenerationPlan.skippedNote(read: [0..<7], skipped: [7..<14], labels: labels),
                       "Cloud AI read pages 1 to 7, but couldn't read pages 8 to 14 this time. Try those pages again later.")
        XCTAssertEqual(GenerationPlan.skippedNote(read: [0..<13], skipped: [13..<14], labels: labels),
                       "Cloud AI read pages 1 to 13, but couldn't read page 14 this time. Try that page again later.")
        XCTAssertNil(GenerationPlan.leftOutNote(0))
        XCTAssertEqual(GenerationPlan.leftOutNote(1), "1 more idea in the lecture wasn't turned into a question.")
        XCTAssertEqual(GenerationPlan.leftOutNote(5), "5 more ideas in the lecture weren't turned into questions.")
        XCTAssertEqual(GenerationPlan.joined([nil, "A.", "", "B."]), "A. B.")
        XCTAssertNil(GenerationPlan.joined([nil, ""]))
    }

    // MARK: The check

    /// Cardozo's opinion: the cited lines never name the judge or the case, so the strict check called every question
    /// unsupported ("does not identify Cardozo"), although the reviewers found all sixteen right.
    private func palsgrafVerdicts(rejected: Int, of total: Int) -> (verdicts: [CheckVerdict], ids: [String]) {
        let ids = (1...total).map { "i\($0)" }
        let verdicts = ids.enumerated().map { index, id in
            index < rejected
                ? CheckVerdict(id: id, verdict: .unsupported, reason: "The cited lines do not identify Cardozo as the judge, so the claim isn't supported.")
                : CheckVerdict(id: id, verdict: .supported, reason: "")
        }
        return (verdicts, ids)
    }

    func testAPalsgrafLikeRejectionIsAskedAgainThenCheckedOnThisIPhone() {
        let (verdicts, ids) = palsgrafVerdicts(rejected: 16, of: 16)
        XCTAssertTrue(CheckPolicy.rejectsNearlyAll(verdicts, itemIDs: ids))
        XCTAssertEqual(CheckPolicy.step(after: verdicts, itemIDs: ids, lenient: false), .retryLenient)
        XCTAssertEqual(CheckPolicy.step(after: verdicts, itemIDs: ids, lenient: true), .checkOnThisIPhone, "never a third request")
    }

    func testTheLenientAnswerIsBelievedWhenItIsNotSuspicious() {
        let (verdicts, ids) = palsgrafVerdicts(rejected: 1, of: 16)
        XCTAssertEqual(CheckPolicy.step(after: verdicts, itemIDs: ids, lenient: true), .accept)
        XCTAssertEqual(CheckPolicy.step(after: verdicts, itemIDs: ids, lenient: false), .accept)
    }

    func testNinetyPercentOfSixItemsIsTheLine() {
        // 9 of 10 is exactly 90%: suspicious. 8 of 10 is not.
        let nine = palsgrafVerdicts(rejected: 9, of: 10)
        XCTAssertTrue(CheckPolicy.rejectsNearlyAll(nine.verdicts, itemIDs: nine.ids))
        let eight = palsgrafVerdicts(rejected: 8, of: 10)
        XCTAssertFalse(CheckPolicy.rejectsNearlyAll(eight.verdicts, itemIDs: eight.ids))
        // Six items, all rejected: suspicious. Five items, all rejected: a small set may really be wrong.
        let six = palsgrafVerdicts(rejected: 6, of: 6)
        XCTAssertTrue(CheckPolicy.rejectsNearlyAll(six.verdicts, itemIDs: six.ids))
        let five = palsgrafVerdicts(rejected: 5, of: 5)
        XCTAssertFalse(CheckPolicy.rejectsNearlyAll(five.verdicts, itemIDs: five.ids))
        XCTAssertEqual(CheckPolicy.step(after: five.verdicts, itemIDs: five.ids, lenient: false), .accept)
    }

    func testFixedAndUnmentionedItemsAreNotRejections() {
        let ids = (1...10).map { "i\($0)" }
        var verdicts = ids.prefix(8).map { CheckVerdict(id: $0, verdict: .unsupported, reason: "no") }
        verdicts.append(CheckVerdict(id: "i9", verdict: .fixed, reason: "fixed", fixedAnswer: "A", fixedChoices: nil))
        // i10 is not mentioned at all: kept, as `applyCheck` keeps it.
        XCTAssertFalse(CheckPolicy.rejectsNearlyAll(verdicts, itemIDs: ids))
        // Verdicts about other questions don't count.
        let strangers = (1...10).map { CheckVerdict(id: "z\($0)", verdict: .unsupported, reason: "no") }
        XCTAssertFalse(CheckPolicy.rejectsNearlyAll(strangers, itemIDs: ids))
    }
}
