import XCTest
@testable import Cramless

/// The text the offline question writer reads: what a printout, a copied web page or a PDF brings along that is not the lesson (the
/// references, a picture's caption, a program listing, the page's header and number, a citation in parentheses, a footnote number) is
/// taken out before anything is asked, and every line that stays keeps its id.
@MainActor
final class SourceHygieneTests: XCTestCase {

    private func page(_ lines: [String], index: Int = 0) -> PageText {
        PageText(index: index, label: "\(index + 1)", lines: lines.enumerated().map { TextLine(id: "p\(index).l\($0.offset)", text: $0.element, box: nil) })
    }

    private func texts(_ pages: [PageText]) -> [String] { pages.flatMap { $0.lines.map(\.text) } }

    private let lesson = [
        "Cholesterol is a waxy, fat-like substance that is found in all the cells in your body.",
        "Your body needs some cholesterol to work properly, but too much of it can narrow the arteries.",
        "Statins are a type of cholesterol medicine that lowers the LDL cholesterol in your blood.",
        "They also increase the ability of the liver to remove LDL cholesterol that is already in the blood.",
    ]

    // MARK: Back matter

    func testTheListOfReferencesAtTheEndIsCutAndTheLessonStays() {
        let reference = [
            "References",
            "1. Fermi, E. (1956). Thermodynamics (https://example.org/book.pdf). Dover Publications. p. 48.",
            "2. Planck, M. (1945). Treatise on Thermodynamics. Dover Publications. pp. 75, 135.",
            "3. Callen, H.B. (1960). Thermodynamics. Wiley, New York.",
        ]
        let out = texts(SourceHygiene.prepare([page(lesson + reference)]))
        XCTAssertEqual(out, lesson)
    }

    func testAnotherArticleAfterTheReferencesIsKept() {
        let second = [
            "Entropy",
            "Entropy is a thermodynamic state variable that measures the number of ways a system can be arranged.",
            "The second law of thermodynamics says that the entropy of an isolated system never decreases over time.",
        ]
        let reference = ["See also", "Carnot heat engine", "References", "1. Fermi, E. (1956). Thermodynamics. Dover. p. 48.", "2. Planck, M. (1945). Treatise. Dover. pp. 75, 135."]
        let out = texts(SourceHygiene.prepare([page(lesson + reference + second)]))
        XCTAssertEqual(out, lesson + second)
    }

    func testAHeadingCalledSourcesNearTheStartIsALessonSection() {
        let lines = ["Sources", "Primary sources are documents written at the time of the events that they describe.", "Secondary sources are written later by historians who interpret them."] + lesson + lesson
        XCTAssertEqual(texts(SourceHygiene.prepare([page(lines)])), lines)
    }

    // MARK: Lines that are not text

    func testPageFurnitureAndAttributionsGo() {
        let furniture = ["8/9", "11/3/26, 12:39 PM", "Page 3 of 9", "https://en.wikipedia.org/wiki/Le_Chatelier%27s_principle", "Retrieved from \"https://en.wikipedia.org/w/index.php\"",
                         "— Edsger Dijkstra, in an interview with Philip L. Frana, Communications of the ACM, 2001", "Pp. 486-496.", "-----"]
        let out = texts(SourceHygiene.prepare([page(Array(lesson.prefix(2)) + furniture + Array(lesson.suffix(2)))]))
        XCTAssertEqual(out, lesson)
    }

    func testARunningHeaderRepeatedOnEveryPageGoesButARepeatedSentenceStays() {
        let header = "Le Chatelier's principle - Wikipedia"
        let lines = [header] + lesson + [header] + lesson + [header] + ["Yes it is.", "Yes it is.", "Yes it is."]
        let out = texts(SourceHygiene.prepare([page(lines)]))
        XCTAssertFalse(out.contains(header))
        XCTAssertEqual(out.filter { $0 == "Yes it is." }.count, 3, "a sentence with a full stop is not a header")
    }

    func testAFigureCaptionOverSeveralLinesAndAProgramListingGo() {
        let figure = ["[Figure: A demo of Dijkstra's algorithm based on Euclidean distance.", "Red lines are the shortest path covering, i.e., connecting u and prev[u].",
                      "Blue lines indicate where relaxing happens.]"]
        let listing = ["1 function Dijkstra(Graph, source):", "2", "3 for each vertex v in Graph.Vertices:", "4 dist[v] ← INFINITY", "5 prev[v] ← UNDEFINED", "6 return dist[], prev[]"]
        let numbered = ["1.", "Create a set of all unvisited nodes.", "2.", "Assign to every node a distance from start."]
        let out = texts(SourceHygiene.prepare([page(Array(lesson.prefix(1)) + figure + Array(lesson.dropFirst().prefix(1)) + listing + numbered)]))
        XCTAssertEqual(out, Array(lesson.prefix(2)) + numbered)
        XCTAssertEqual(texts(SourceHygiene.prepare([page(["Figure 3: The cycle on a pressure-volume diagram."] + lesson)])), lesson)
    }

    func testASentenceThatIntroducedAListingEndsWhereTheListingWas() {
        let lines = ["It is implemented separately in pseudocode:", "1 function Dijkstra(Graph, source):", "2", "3 return dist[]", "4 end", "Instead of filling the queue with all nodes it starts with the source."]
        XCTAssertEqual(texts(SourceHygiene.prepare([page(lines)])), ["It is implemented separately in pseudocode.", "Instead of filling the queue with all nodes it starts with the source."])
    }

    // MARK: Inside a line

    func testACitationInParenthesesIsTakenOutEvenWhenTheLinesWereCutInTheMiddleOfIt() {
        let lines = ["\"Negligence is the absence of care, according to the circumstances\" (Willes, J., in Vaughan v. Taff Vale Ry. Co., 5 H. & N. 679, 688; 1 Beven, Negligence [4th ed.], 7; Paul v.",
                     "Consol. Fireworks Co., 212 N.Y. 117; Adams v. Bullock, 227 N.Y. 208, 211).", "The plaintiff sues in her own right for a wrong personal to her."]
        let out = SourceHygiene.prepare([page(lines)])
        XCTAssertEqual(texts(out), ["\"Negligence is the absence of care, according to the circumstances\"", "The plaintiff sues in her own right for a wrong personal to her."])
        XCTAssertEqual(out[0].lines.map(\.id), ["p0.l0", "p0.l2"], "ids stay; the emptied line goes")
    }

    func testFootnoteNumbersAndPronunciationGuidesAreTakenOut() {
        let lines = ["Le Chatelier's principle (pronounced UK: /lə ʃæˈtɛljeɪ/ or US: /ˈʃɑːtəljeɪ/)[1] is a principle used to predict the effect of a change.",
                     "Dijkstra's algorithm (/ˈdaɪk.strəz/, DYKE-strəz) finds the shortest paths in a graph.[citation needed]",
                     "A principle used to predict the effect of a change in conditions on chemical equilibrium.[", "2] Other names include Chatelier's principle."]
        XCTAssertEqual(texts(SourceHygiene.prepare([page(lines)])), [
            "Le Chatelier's principle is a principle used to predict the effect of a change.",
            "Dijkstra's algorithm finds the shortest paths in a graph.",
            "A principle used to predict the effect of a change in conditions on chemical equilibrium. Other names include Chatelier's principle.",
        ])
    }

    func testAnAsideThatSaysSomethingStaysAndACrossReferenceGoes() {
        let lines = ["If the unvisited set is empty, or contains only nodes with infinite distance (which are unreachable), then the algorithm terminates (see Figure 3).",
                     "Further optimizations include bidirectional variants (see § Related problems and algorithms) and goal-directed variants."]
        XCTAssertEqual(texts(SourceHygiene.prepare([page(lines)])), [
            "If the unvisited set is empty, or contains only nodes with infinite distance (which are unreachable), then the algorithm terminates.",
            "Further optimizations include bidirectional variants and goal-directed variants.",
        ])
    }

    func testAPageWithNothingToCleanComesBackUnchanged() {
        let clean = page(lesson)
        XCTAssertEqual(SourceHygiene.prepare([clean]), [clean])
        XCTAssertEqual(SourceHygiene.prepare([]), [])
    }

    func testAFootnoteNumberTheLineSplitterCutAfterItsBracketGoesBackTogether() {
        let lines = ["The equilibrium is perturbed by changing the thermodynamic operations through which a perturbation is to be applied.[", "12][13][14]",
                     "In theory and, nearly, in some practical scenarios, a body can be in a stationary state with zero flows."]
        let out = texts(SourceHygiene.prepare([page(lines)]))
        XCTAssertEqual(out, ["The equilibrium is perturbed by changing the thermodynamic operations through which a perturbation is to be applied.",
                             "In theory and, nearly, in some practical scenarios, a body can be in a stationary state with zero flows."])
        XCTAssertFalse(out.joined().contains("["))
    }

    func testALineThatIsOnlyAnAbbreviationIsNotTextAndDoesNotGlueTheNextSentenceToItself() {
        let lines = ["Segregation of children in public schools solely on the basis of race denies them the equal protection of the laws.", "Pp.", "486-496.",
                     "(a) The history of the Fourteenth Amendment is inconclusive as to its intended effect on public education."]
        let out = texts(SourceHygiene.prepare([page(lines)]))
        XCTAssertEqual(out.count, 2, "\(out)")
        XCTAssertFalse(out.contains("Pp."))
        XCTAssertTrue(out.last?.hasPrefix("(a) The history") == true)
    }
}
