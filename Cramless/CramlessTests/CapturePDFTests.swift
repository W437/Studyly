import PDFKit
import UIKit
import XCTest
@testable import Cramless

/// PDFs rendered in the test: a text-layer page (lines, no boxes, the printed number as its label) and an
/// image-only page (rendered at 2×, kept as the page image, read by Vision with boxes).
@MainActor
final class CapturePDFTests: CaptureTestCase {
    private func makePDF(extraTextPages: Int = 0) throws -> URL {
        let scan = Render.textImage(["Photosynthesis makes glucose", "Chlorophyll absorbs light"],
                                    font: .systemFont(ofSize: 44), size: CGSize(width: 1224, height: 1584))
        var pages: [(UIGraphicsPDFRendererContext) -> Void] = [
            { context in
                Render.drawText(["The cell cycle", "Interphase is the longest part of the cycle.",
                                 "During S phase the cell copies its DNA."], in: context)
                Render.drawText(["12"], in: context, size: 10, top: 740)
            },
            { _ in scan.draw(in: CGRect(x: 0, y: 0, width: 612, height: 792)) },
        ]
        for index in 0..<extraTextPages {
            pages.append { Render.drawText(["Extra page \(index) with enough letters to count as text."], in: $0) }
        }
        return try temporaryFile("Week 5 slides.pdf", data: Render.pdf(pages: pages))
    }

    func testTextPagesAndImagePagesAreBothRead() async throws {
        let url = try makePDF()
        XCTAssertNil(PDFDocument(url: url)?.page(at: 1)?.string?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil,
                     "the second page really is image-only")
        let result = try await PDFReader.read(url, imageFolder: "sources/pdf", preferredLanguages: ["en-US"])
        XCTAssertEqual(result.pageCount, 2)
        XCTAssertFalse(result.truncated)

        let text = result.pages[0]
        XCTAssertEqual(text.read, .pdfText)
        XCTAssertEqual(Array(text.lines.map(\.text).prefix(3)), ["The cell cycle", "Interphase is the longest part of the cycle.",
                                                                 "During S phase the cell copies its DNA."])
        XCTAssertTrue(text.lines.allSatisfy { $0.box == nil }, "a text layer has no boxes")
        XCTAssertEqual(text.label, "12", "the printed footer number")
        XCTAssertNil(text.imageFileName)

        let scanned = result.pages[1]
        XCTAssertEqual(scanned.read.engine, .vision)
        XCTAssertTrue(scanned.lines.contains { $0.text.localizedCaseInsensitiveContains("Photosynthesis") }, "\(scanned.lines.map(\.text))")
        XCTAssertTrue(scanned.lines.allSatisfy { $0.box != nil }, "recognised lines have boxes")
        XCTAssertEqual(scanned.lines.first?.id, "p1.l0")
        XCTAssertEqual(scanned.label, "2")
        let image = try XCTUnwrap(scanned.imageFileName)
        XCTAssertEqual(image, "sources/pdf/page-1.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: FileStore.url(for: image).path))
        XCTAssertEqual(scanned.height, 1584, "rendered at 2×")
    }

    func testLongPDFsAreCappedAndSaySo() async throws {
        let url = try makePDF(extraTextPages: 3)
        let pages = LockedCounter()
        let result = try await PDFReader.read(url, imageFolder: "sources/cap", maxPages: 3, preferredLanguages: ["en-US"]) { done, total in
            pages.record(done, total)
        }
        XCTAssertEqual(result.pageCount, 5)
        XCTAssertEqual(result.pages.count, 3)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(pages.last, [3, 3])
        XCTAssertEqual(PDFReader.maxPages, 300)
    }

    func testDamagedAndEmptyPDFs() async throws {
        let junk = try temporaryFile("junk.pdf", data: Data("%PDF-1.4 not really".utf8))
        do {
            _ = try await PDFReader.read(junk, imageFolder: "x")
            XCTFail("a damaged PDF throws")
        } catch {
            XCTAssertEqual(error as? CaptureError, .pdfUnreadable)
        }
    }

    func testAppModelMakesAPDFSource() async throws {
        let app = try makeApp()
        let course = makeCourse(app)
        var stages: [CaptureProgress] = []
        let source = try await app.createSource(fromPDF: makePDF(), course: course) { stages.append($0) }
        XCTAssertEqual(source.kind, .pdf)
        XCTAssertEqual(source.status, .read)
        XCTAssertEqual(source.title, "Week 5 slides")
        XCTAssertEqual(source.sortedPages.map(\.label), ["12", "2"])
        XCTAssertEqual(source.sortedPages[0].read?.engine, .pdfText)
        XCTAssertEqual(source.sortedPages[1].read?.engine, .vision)
        let file = try XCTUnwrap(source.fileName)
        XCTAssertEqual(file, "sources/\(source.id.uuidString)/document.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: FileStore.url(for: file).path))
        XCTAssertEqual(stages.first, .preparing)
        XCTAssertTrue(stages.contains { $0.stage == .saving && $0.total == 2 }, "\(stages)")
        XCTAssertTrue(course.liveSources.contains { $0.id == source.id })
    }

    // MARK: Formulas that vanished from the text layer

    /// Three pages of the chain-rule article as the PDF's text layer holds them: the prose, without its formulas.
    private func makeChainRulePDF() throws -> URL {
        let pages = [FormulaGapTests.first, FormulaGapTests.composites, FormulaGapTests.leibniz]
        return try temporaryFile("Chain rule.pdf", data: Render.pdf(pages: pages.map { lines in
            { context in Render.drawText(lines, in: context, size: 6) }
        }))
    }

    func testPDFPagesWhoseFormulasVanishedAreMarkedAndStillRead() async throws {
        let result = try await PDFReader.read(try makeChainRulePDF(), imageFolder: "sources/chain", preferredLanguages: ["en-US"])
        XCTAssertEqual(result.pages.count, 3)
        for page in result.pages {
            XCTAssertEqual(page.read.engine, .pdfText)
            XCTAssertEqual(page.read.issue, .mathLike, "page \(page.pageIndex + 1) lost its formulas")
            XCTAssertTrue(page.read.formulasMayBeMissing)
            XCTAssertFalse(page.read.wantsBetterRead, "a photo's better read is a different thing")
            XCTAssertFalse(page.lines.isEmpty, "the words are kept")
        }
        // An ordinary text page is not marked.
        let plain = try await PDFReader.read(try makePDF(), imageFolder: "sources/plain", preferredLanguages: ["en-US"])
        XCTAssertNil(plain.pages[0].read.issue)
        XCTAssertEqual(plain.pages[0].read, .pdfText)
    }

    // MARK: Formulas drawn as outlines

    /// Prose that gives no sign of a hole in it: four sentences, about seventeen points apart, from 72 points down the page.
    private static let intactProse = [
        "The cell cycle has four phases that the student should know well.",
        "Interphase is the longest part of the cycle and lasts most of the time.",
        "During S phase the cell copies its DNA so that each daughter cell gets a full set.",
        "Mitosis follows and divides the copied chromosomes between the two new nuclei.",
    ]

    /// A page of `intactProse`, with rows of small filled ovals drawn on it (`symbols` of them from 120 points across, ten points apart,
    /// five to eight points wide and eight to ten tall, their tops at `top`): what a browser draws for a formula that is an SVG
    /// picture, where the text layer has nothing. With `identical`, all of one size, like the markers of a chart. With `group`, drawn
    /// inside a transparency group, which the file keeps as a form of its own; with `scaled`, drawn at half size under a scale of two and
    /// a move down of a hundred points, so that they land in the same place on the page.
    private func outlinesPage(_ rows: [(symbols: Int, top: CGFloat)], tag: String = "alpha", identical: Bool = false,
                              group: Bool = false, scaled: Bool = false, prose: [String]? = nil) -> (UIGraphicsPDFRendererContext) -> Void {
        { context in
            // Each page's sentences end in a word of its own, so that no line repeats from page to page like a running header.
            Render.drawText(prose ?? Self.intactProse.map { $0 + " In group \(tag)." }, in: context, size: 10)
            let cg = context.cgContext
            UIColor.black.setFill()
            if group {
                cg.beginTransparencyLayer(auxiliaryInfo: nil)
                cg.setAlpha(0.9)
            }
            cg.saveGState()
            if scaled {
                cg.translateBy(x: 0, y: 100)
                cg.scaleBy(x: 2, y: 2)
            }
            let unit: CGFloat = scaled ? 0.5 : 1
            for row in rows {
                for index in 0..<row.symbols {
                    let size = identical ? CGSize(width: 6, height: 9) : CGSize(width: CGFloat(5 + index % 4), height: CGFloat(8 + index % 3))
                    let origin = CGPoint(x: (120 + CGFloat(index) * 10) * unit, y: scaled ? (row.top - 100) * unit : row.top)
                    UIBezierPath(ovalIn: CGRect(origin: origin, size: CGSize(width: size.width * unit, height: size.height * unit))).fill()
                }
            }
            cg.restoreGState()
            if group { cg.endTransparencyLayer() }
        }
    }

    func testAFormulaDrawnAsOutlinesIsFlaggedWhereTheTextAloneGivesNothingAway() async throws {
        let url = try temporaryFile("Outlines.pdf", data: Render.pdf(pages: [
            outlinesPage([(10, 170)], tag: "alpha"),   // a formula on a line of its own, below the first sentence
            outlinesPage([], tag: "bravo"),            // the same prose without it
            outlinesPage([(3, 170)], tag: "charlie"),  // a few marks: an icon, not a formula
            outlinesPage([(10, 170)], tag: "delta"),
        ]))
        let result = try await PDFReader.read(url, imageFolder: "sources/outlines", preferredLanguages: ["en-US"])
        XCTAssertEqual(result.pages.map(\.read.engine), Array(repeating: .pdfText, count: 4))
        XCTAssertEqual(result.pages.map(\.read.formulasMayBeMissing), [true, false, false, true])
        XCTAssertEqual(result.pages[0].read.issue, .mathLike)
        XCTAssertNil(result.pages[1].read.issue)
        XCTAssertFalse(result.pages[0].lines.isEmpty, "the words are kept")
    }

    func testOutlinesInsideAFormAndUnderATransformationAreFoundWhereTheyAreOnThePage() async throws {
        // The first page's marks are drawn small under a scale and a move: placed by their own numbers they would be above the first
        // sentence (a masthead, left aside); placed where they land, they are below it. The second page's are in a form of their own.
        let url = try temporaryFile("Forms.pdf", data: Render.pdf(pages: [
            outlinesPage([(10, 170)], tag: "alpha", scaled: true),
            outlinesPage([(10, 170)], tag: "bravo", group: true),
        ]))
        let result = try await PDFReader.read(url, imageFolder: "sources/forms", preferredLanguages: ["en-US"])
        XCTAssertEqual(result.pages.map(\.read.formulasMayBeMissing), [true, true])
    }

    func testTheMarkersOfAChartAreNotAFormula() async throws {
        let chart = try temporaryFile("Chart.pdf", data: Render.pdf(pages: [outlinesPage([(10, 170), (10, 200)], tag: "alpha", identical: true),
                                                                            outlinesPage([(10, 170)], tag: "bravo")]))
        let result = try await PDFReader.read(chart, imageFolder: "sources/chart", preferredLanguages: ["en-US"])
        XCTAssertEqual(result.pages.map(\.read.formulasMayBeMissing), [false, true],
                       "twenty identical ovals are the marks of a chart; ten of different sizes are the symbols of a formula")
    }

    func testALogoAboveTheFirstSentenceIsNotAFormulaButTheSameMarksBelowItAre() async throws {
        let masthead = try temporaryFile("Masthead.pdf", data: Render.pdf(pages: [outlinesPage([(12, 30)], tag: "alpha"), outlinesPage([], tag: "bravo")]))
        let result = try await PDFReader.read(masthead, imageFolder: "sources/masthead", preferredLanguages: ["en-US"])
        XCTAssertEqual(result.pages.map(\.read.formulasMayBeMissing), [false, false])
        // On a page that is not the first, the same marks are drawn in the page's own flow.
        let later = try temporaryFile("Later.pdf", data: Render.pdf(pages: [outlinesPage([], tag: "alpha"), outlinesPage([(12, 30)], tag: "bravo")]))
        let second = try await PDFReader.read(later, imageFolder: "sources/later", preferredLanguages: ["en-US"])
        XCTAssertEqual(second.pages.map(\.read.formulasMayBeMissing), [false, true])
    }

    func testTheFirstSentenceOfAScriptWithNoSpacesAlsoEndsTheMasthead() async throws {
        // A line of Chinese has no spaces to count words by; twenty letters make it a sentence all the same.
        let chinese = ["热力学第二定律指出孤立系统的熵不会减少，除非有外界对系统做功或者交换热量。"]
        let above = try temporaryFile("Above.pdf", data: Render.pdf(pages: [outlinesPage([(12, 30)], prose: chinese)]))
        let masthead = try await PDFReader.read(above, imageFolder: "sources/above", preferredLanguages: ["zh-Hans"])
        XCTAssertEqual(masthead.pages.map(\.read.engine), [.pdfText])
        XCTAssertEqual(masthead.pages.map(\.read.formulasMayBeMissing), [false], "the marks above the sentence are a masthead")
        let below = try temporaryFile("Below.pdf", data: Render.pdf(pages: [outlinesPage([(12, 170)], prose: chinese)]))
        let formula = try await PDFReader.read(below, imageFolder: "sources/below", preferredLanguages: ["zh-Hans"])
        XCTAssertEqual(formula.pages.map(\.read.formulasMayBeMissing), [true], "the same marks under it are a formula")
    }

    func testAMarkDrawnInTheSamePlaceOnEveryPageIsNotAFormula() async throws {
        // A logo on each slide, drawn under the first sentence so the masthead rule does not help: it repeats, so it belongs to the page's furniture.
        let slides = try temporaryFile("Slides.pdf", data: Render.pdf(pages: ["alpha", "bravo", "charlie", "delta", "echo"].map { outlinesPage([(10, 170)], tag: $0) }))
        let result = try await PDFReader.read(slides, imageFolder: "sources/slides", preferredLanguages: ["en-US"])
        XCTAssertEqual(result.pages.map(\.read.formulasMayBeMissing), Array(repeating: false, count: 5))
    }

    func testTheOutlinesOfAPDFPageMakeItOfferTheBetterRead() async throws {
        let app = try makeApp()
        let url = try temporaryFile("Outlines.pdf", data: Render.pdf(pages: [outlinesPage([], tag: "alpha"), outlinesPage([(10, 170)], tag: "bravo")]))
        let source = try await app.createSource(fromPDF: url, course: makeCourse(app))
        XCTAssertEqual(source.status, .read)
        XCTAssertEqual(source.pagesWithMissingFormulas.map(\.pageIndex), [1])
    }

    func testTheSourceSaysSoAndAMathPDFIsNotBlockedFromWritingQuestions() async throws {
        let app = try makeApp()
        let source = try await app.createSource(fromPDF: try makeChainRulePDF(), course: makeCourse(app))
        XCTAssertEqual(source.status, .read)
        XCTAssertEqual(source.pagesWithMissingFormulas.count, 3)
        XCTAssertEqual(Source.missingFormulasNote, "Formulas may be missing from this PDF. Read the page with Cloud AI to get them.")
        // The stored page keeps the mark through a round trip.
        XCTAssertTrue(source.sortedPages.allSatisfy { $0.formulasMayBeMissing && !$0.wantsBetterRead })
        // `readPagesWithCloud` is for photos; these pages have none.
        XCTAssertTrue(source.pagesWantingBetterRead.isEmpty)
    }

    private func mockApp(photos: Bool) throws -> AppModel {
        let defaults = UserDefaults(suiteName: "capture-pdf-tests-\(UUID().uuidString)")!
        let config = AppConfig(supabaseURL: nil, supabaseAnonKey: nil, aiMode: .mock, isHarness: false, inMemoryStore: true,
                               seedDemoData: false, environment: ["XCTestConfigurationFilePath": "capture-pdf-tests"])
        let app = AppModel(config: config, container: try Persistence.makeContainer(inMemory: true), defaults: defaults)
        app.clock = { Date(timeIntervalSince1970: 1_790_000_000) }
        app.settings.cloudConsentVersion = AIConsent.currentVersion
        app.settings.sendPhotos = photos
        app.ai.mockLatencyScale = 0
        app.ai.probe = FixedOnDeviceProbe(.unavailable(.notChecked))
        return app
    }

    func testFlaggedPagesAreDrawnAndReadWithCloudAIWhenPagePhotosAreAllowed() async throws {
        let app = try mockApp(photos: true)
        let source = try await app.createSource(fromPDF: try makeChainRulePDF(), course: makeCourse(app))
        let before = source.sortedPages.map(\.text)

        let result = await app.readPDFPagesWithCloud(sourceID: source.id)

        XCTAssertEqual(result, .read)
        XCTAssertTrue(source.pagesWithMissingFormulas.isEmpty, "the better text replaced the text layer")
        for (page, text) in zip(source.sortedPages, before) {
            XCTAssertEqual(page.read?.engine, .cloud)
            XCTAssertNotEqual(page.text, text)
            let image = try XCTUnwrap(page.imageFileName, "the drawn page is kept")
            XCTAssertTrue(FileManager.default.fileExists(atPath: FileStore.url(for: image).path))
        }
        // Nothing left to read: nothing is sent again.
        let again = await app.readPDFPagesWithCloud(sourceID: source.id)
        XCTAssertEqual(again, .read)
    }

    func testTheFormulasReadKeepsTheLinesApprovedQuestionsPointAtSoTheyKeepTheirSourceLinkExcerptAndCoverage() async throws {
        let app = try mockApp(photos: true)
        let course = makeCourse(app)
        let source = try await app.createSource(fromPDF: try makeChainRulePDF(), course: course)
        let before = try XCTUnwrap(source.sortedPages.first).lines
        XCTAssertGreaterThanOrEqual(before.count, 3)

        // Sequence A: questions are made from the PDF's lines and approved ("Add questions for the rest" does the same), and the formulas
        // card's read comes after.
        let anchors = before.prefix(3).map(\.id)
        let written = [GeneratedItem(id: "i1", kind: .flashcard, topic: "Chain rule", prompt: "What does the chain rule express?",
                                     answer: "The derivative of a composition of functions.", anchors: anchors)]
        let outcome = GenerationOutcome(title: "Chain rule", topics: [GeneratedTopic(name: "Chain rule", summary: "")], items: written, dropped: [],
                                        origin: .cloud, model: "mock", checkedBy: .cloud, note: nil, suggestion: nil, limitReached: nil,
                                        fellBack: false)
        app.makeDrafts(from: outcome, source: source, course: course)
        XCTAssertEqual(app.approveDrafts(sourceID: source.id, keeping: Set(app.draftItems(sourceID: source.id).map(\.id))), 1)
        let approved = try XCTUnwrap(app.items(fromSource: source.id).first)
        let excerpt = try XCTUnwrap(app.sourceExcerpt(for: approved))
        let coverage = try XCTUnwrap(app.coverage(of: source))
        XCTAssertGreaterThan(coverage.coveredWords, 0)

        let result = await app.readPDFPagesWithCloud(sourceID: source.id)
        XCTAssertEqual(result, .read)

        let page = try XCTUnwrap(source.sortedPages.first)
        XCTAssertEqual(page.read?.engine, .cloud)
        for line in before { XCTAssertTrue(page.lines.contains(line), "\(line.id) is still on the page, with the same words") }
        XCTAssertGreaterThan(page.lines.count, before.count, "and what the cloud read is added")
        XCTAssertEqual(Set(page.lines.map(\.id)).count, page.lines.count, "ids stay unique")
        XCTAssertEqual(approved.sourceRef?.anchorIDs, anchors)
        XCTAssertEqual(app.sourceExcerpt(for: approved), excerpt, "the grader still gets the lines the question came from")
        let after = try XCTUnwrap(app.coverage(of: source))
        XCTAssertGreaterThanOrEqual(after.coveredWords, coverage.coveredWords, "the passage the question covers is still covered")
        XCTAssertTrue(source.pagesWithMissingFormulas.isEmpty)
    }

    func testAReviewOfTheRestReadsOnlyTheRestsPagesAndMergesThemUnderTheirPageNumber() async throws {
        let app = try mockApp(photos: true)
        let source = try await app.createSource(fromPDF: try makeChainRulePDF(), course: makeCourse(app))
        XCTAssertEqual(source.pagesWithMissingFormulas.map(\.pageIndex), [0, 1, 2])

        let result = await app.readPDFPagesWithCloud(sourceID: source.id, onlyPages: [1])
        XCTAssertEqual(result, .read)
        XCTAssertEqual(source.pagesWithMissingFormulas.map(\.pageIndex), [0, 2], "only page 2 was drawn, sent and read")
        let read = source.sortedPages[1]
        XCTAssertEqual(read.read?.engine, .cloud)
        XCTAssertNotNil(read.imageFileName)
        XCTAssertNil(source.sortedPages[0].imageFileName, "the others were not drawn")
        // What the read adds to a page is numbered under that page, whatever the relay's numbering was.
        XCTAssertTrue(read.lines.contains { $0.id.hasPrefix("p1.c") })
        XCTAssertFalse(read.lines.contains { $0.id.hasPrefix("p0.") })
        XCTAssertEqual(Set(read.lines.map(\.id)).count, read.lines.count)

        // Nothing flagged among the pages asked for: nothing to read.
        let none = await app.readPDFPagesWithCloud(sourceID: source.id, onlyPages: [1])
        XCTAssertEqual(none, .read)
        XCTAssertEqual(source.pagesWithMissingFormulas.map(\.pageIndex), [0, 2])
    }

    // MARK: A PDF saved from a browser

    private static let carnotHeader = "11/3/26, 12:39 PM Carnot cycle - Wikipedia"
    private static let entropyHeader = "11/3/26, 12:39 PM Entropy - Wikipedia"

    /// Eight pages as a browser printed them: the first article's five pages (its reference list on the last two), then the first three of
    /// another article in the same file. Lines as PDFKit gave them for Wikipedia's "Carnot cycle" and "Entropy" (short excerpts): the header on
    /// every page, sometimes with the page's first words stuck to it and its title elsewhere on the page; the address and "n/7" below.
    private static var printout: [[String]] {
        func footer(_ n: Int) -> String { "https://en.wikipedia.org/wiki/Carnot_cycle \(n)/5" }
        func entropy(_ n: Int) -> String { "https://en.wikipedia.org/wiki/Entropy \(n)/31" }
        return [
            [carnotHeader, "Carnot cycle", "A Carnot cycle (English: /kɑːr", "nɔː/) is an ideal thermodynamic cycle proposed by French physicist Sadi Carnot in 1824.",
             "(https://m.youtube.com/watch?v=d6eJ8mccvu0", "In a Carnot cycle, a system or engine transfers energy in the form of heat between two thermal reservoirs.", footer(1)],
            [carnotHeader, "Stage One: the gas expands isothermally, taking heat from the hot reservoir at a constant temperature.",
             "Carnot cycle - Wikipedia", "Stage Two: the gas expands further without any exchange of heat with the surroundings.", footer(2)],
            ["11/3/26, 12:39 PM piston down further (Stage Four figure,", "right), increasing its internal energy,", "compressing it, and causing its temperature to rise.",
             "Carnot cycle - Wikipedia", "The engine is reversibly transporting entropy from the hot reservoir to the cold reservoir.", footer(3)],
            ["11/3/26, 12:39 PM Efficiency", "The efficiency η is defined to be:", "Carnot cycle - Wikipedia", "where",
             "W is the work done by the engine system (energy exiting the system as work),",
             "Carnot's theorem is a formal statement of this fact: No engine operating between two heat reservoirs can be more efficient than a Carnot engine.",
             "See also", "Carnot heat engine", "Reversible process (thermodynamics)", "References", "Notes",
             "1. Fermi, E. (1956). \"equation 64\". Thermodynamics (https://gutenberg.net.au/ebooks13/1305021p.p", "df) (PDF). Dover Publications. p. 48.",
             "2. Planck, M. (1945). \"equations 39, 40 and 65 in sections §90 & §137\". Treatise on",
             "Thermodynamics (https://www.gutenberg.org/ebooks/50880). Dover Publications. pp. 75, 135.", footer(4)],
            [carnotHeader, "3. Çengel, Yunus A., and Michael A. Boles. Thermodynamics: An Engineering Approach. 7th ed.",
             "New York: McGraw-Hill, 2011. p. 299. Print.",
             "4. Holubec, Viktor; Ryabov, Artem (2018). \"Cycling Tames Power Fluctuations near Optimum",
             "Efficiency\". Phys. Rev. Lett. 121 (12) 120601. arXiv:1805.00848 (https://arxiv.org/abs/1805.0084",
             "doi:10.1103/PhysRevLett.121.120601 (https://doi.org/10.1103%2FPhysRevLett.121.120601).",
             "Sources", "Carnot, Sadi, Reflections on the Motive Power of Fire",
             "Ewing, J. A. (1910) The Steam-Engine and Other Engines (https://archive.org/details/cu3192", "4004249532) edition 3, page 62, via Internet Archive",
             "External links", "Hyperphysics (http://hyperphysics.phy-astr.gsu.edu/hbase/thermo/carnot.html) article on the", "Carnot cycle.",
             "Retrieved from \"https://en.wikipedia.org/w/index.php?title=Carnot", "_", "cycle&oldid=1375057573\"", footer(5)],
            [entropyHeader, "Entropy", "Entropy is a thermodynamic state variable that quantifies the", "probabilistic distribution of accessible microstates in a",
             "Entropy", "system. The term and the concept are used in diverse fields,", "from classical thermodynamics (where it was first",
             "recognized), to the microscopic description of nature in", "Common symbols S", "SI unit joules per kelvin (J⋅K−1)",
             "statistical physics, and the principles of information theory. It", "has far-ranging applications in chemistry and physics, in",
             "biological systems and their relation to life, in cosmology, economics, and information systems including the",
             "transmission of information in telecommunication.", entropy(1)],
            ["11/3/26, 12:39 PM an analogy with how water falls in a water wheel. That was an early insight", "into the second law of thermodynamics.",
             "Entropy - Wikipedia", "[5] Carnot based his views of heat on the early ideas of the 18th century.", entropy(2)],
            [entropyHeader, "Since this equality holds over an entire Carnot cycle, it gave Clausius the hint that at each stage of the cycle", ".", entropy(3)],
        ]
    }

    func testTheHeaderFooterAndReferencesOfABrowserPrintoutAreTakenOutAndTheArticleStays() {
        let (pages, report) = PageLayout.cleanedPDFPages(Self.printout)
        let text = pages.flatMap { $0 }
        XCTAssertFalse(text.contains { $0.contains("Wikipedia") || $0.contains("https://en.wikipedia.org/wiki") || $0.contains("12:39 PM") })

        // The article is all there, in order: the lines the header's date was stuck to keep their words.
        XCTAssertEqual(pages[0], ["Carnot cycle", "A Carnot cycle (English: /kɑːr", "nɔː/) is an ideal thermodynamic cycle proposed by French physicist Sadi Carnot in 1824.",
                                  "In a Carnot cycle, a system or engine transfers energy in the form of heat between two thermal reservoirs."],
                       "and a bare link in the text goes")
        XCTAssertEqual(pages[1], ["Stage One: the gas expands isothermally, taking heat from the hot reservoir at a constant temperature.",
                                  "Stage Two: the gas expands further without any exchange of heat with the surroundings."], "the title that came out mid-page goes")
        XCTAssertEqual(pages[2].first, "piston down further (Stage Four figure,")
        XCTAssertEqual(pages[2].count, 4)
        XCTAssertEqual(Array(pages[3].prefix(2)), ["Efficiency", "The efficiency η is defined to be:"])
        XCTAssertTrue(pages[3].contains("Carnot's theorem is a formal statement of this fact: No engine operating between two heat reservoirs can be more efficient than a Carnot engine."))
        XCTAssertEqual(Array(pages[3].suffix(3)), ["See also", "Carnot heat engine", "Reversible process (thermodynamics)"],
                       "a list of related articles is not a list of citations: it stays")

        // The reference list goes, from its heading to where the next article begins, and the next article starts in full.
        XCTAssertFalse(text.contains { $0.contains("Dover Publications") || $0.contains("doi:") || $0 == "References" || $0 == "Sources" || $0 == "External links" })
        XCTAssertTrue(pages[4].isEmpty, "a page that was all references has no lines left")
        XCTAssertEqual(pages[5].prefix(3), ["Entropy", "Entropy is a thermodynamic state variable that quantifies the", "probabilistic distribution of accessible microstates in a"])
        XCTAssertEqual(pages[5].count, 13, "the box beside the first paragraph is still there")
        XCTAssertEqual(pages[6].first, "an analogy with how water falls in a water wheel. That was an early insight")
        XCTAssertTrue(pages[6].contains("[5] Carnot based his views of heat on the early ideas of the 18th century."), "a body line that starts with a footnote mark")

        // Counts: five headers whole (the three whose date is stuck to the page's first words keep those), eight footers, and four titles
        // that came out in the middle of a page; one bare link; and the reference list: its heading, "Notes", "Sources", "External links" and
        // what is under them.
        XCTAssertEqual(report.running, 5 + 8 + 4)
        XCTAssertEqual(report.stamps, 8)
        XCTAssertEqual(report.addresses, 1)
        XCTAssertEqual(report.references, 21)
        XCTAssertEqual(report.spaced, 0)
        XCTAssertEqual(report.removed, report.running + report.addresses + report.references)
    }

    func testNothingIsTakenOutOfADocumentThatIsNotAPrintout() {
        // Two pages with the same line at the top: too few to be a header.
        let two = [["Cell cycle notes", "Interphase is the longest part of the cell cycle."], ["Cell cycle notes", "Mitosis follows interphase and divides the chromosomes."]]
        XCTAssertEqual(PageLayout.cleanedPDFPages(two).pages, two)
        XCTAssertEqual(PageLayout.cleanedPDFPages(two).report, PageLayout.PDFCleaning())

        // A table: a page number at the foot of every page is a running line, and a cell that is a number on its own is not.
        let terms = ["autumn", "winter", "spring", "summer", "fall", "midyear"]
        let table = terms.enumerated().map { p, term in
            ["Grades in the \(term) term were the best of the year.", "The class met every week of the \(term) term and the marks were posted at once.",
             "Each mark below is the number of \(term) students who got that grade.", "Grade", "Count", "A", "12", "B", "25", "C", "31",
             "Most students scored a B or a C in the \(term) term.", "The marks of the \(term) class are shown.", "\(p + 1)"]
        }
        let cleaned = PageLayout.cleanedPDFPages(table)
        XCTAssertEqual(cleaned.pages.map(\.count), Array(repeating: 13, count: 6), "only the number at the foot")
        XCTAssertTrue(cleaned.pages.allSatisfy { $0.contains("12") && $0.contains("25") && $0.contains("31") })
        XCTAssertEqual(cleaned.report.running, 6)

        // "Notes" and "References" over prose are headings of a chapter, not a list of citations.
        let handout = [["Notes", "The cell cycle has two main stages, interphase and the mitotic phase, and the first is much the longer of the two.",
                        "During interphase the cell grows, copies its DNA and prepares to divide into two daughter cells.",
                        "Mitosis then separates the copied chromosomes so that each daughter cell gets a full set of them.",
                        "Cytokinesis finishes the job by pinching the cytoplasm in two, which happens in the last stage.",
                        "The whole cycle takes about a day in a typical cultured human cell, though some divide much faster.",
                        "References", "Sources of energy for the cell are covered in the next chapter of these lecture notes."]]
        XCTAssertEqual(PageLayout.cleanedPDFPages(handout).pages, handout)
        // A reference list is cut where the article goes on, not at the end of the file: a chapter's notes, then the next chapter.
        let chapters = [["Chapter one", "Notes", "1. Smith, J. (2001). The cell. Oxford University Press. p. 12.", "2. Jones, K. et al. (1999). Mitosis. doi:10.1000/x1",
                         "Chapter two", "Interphase is the longest part of the cell cycle and takes up most of the time in a typical cell.",
                         "During S phase the cell copies its DNA so that each daughter cell can have a full set of chromosomes.",
                         "Mitosis follows and divides the copied chromosomes between two nuclei in four short stages.",
                         "Cytokinesis then pinches the cytoplasm in two and the cell cycle begins again with growth.",
                         "Cells that stop dividing leave the cycle and enter a resting state that can last for years."]]
        XCTAssertEqual(PageLayout.cleanedPDFPages(chapters).pages, [["Chapter one"] + Array(chapters[0].suffix(6))],
                       "the notes go, and the second chapter, whose heading is given back, stays")
    }

    func testAnAddressAloneIsNotALineOfTheArticle() {
        for line in ["https://en.wikipedia.org/wiki/Carnot_cycle 1/7", "(https://m.youtube.com/watch?v=d6eJ8mccvu0", "www.ncbi.nlm.nih.gov/books/NBK551568",
                     "https://www.niddk.nih.gov/health-information/diabetes/overview/insulin-medicines-treatments 10/11"] {
            XCTAssertTrue(PageLayout.isAddressOnly(line), line)
        }
        for line in ["See https://example.com for the data", "Retrieved from \"https://en.wikipedia.org/w/index.php?title=Carnot", "3/14", "", "The address is www.example.org."] {
            XCTAssertFalse(PageLayout.isAddressOnly(line), line)
        }
    }

    func testLettersSpacedOutByTheTypesettingAreJoinedBackIntoWords() {
        XCTAssertEqual(PageLayout.collapsingSpacedLetters("C l i n i c a l D i a b et es ."), "Clinical Diabetes .")
        XCTAssertEqual(PageLayout.collapsingSpacedLetters("Wong EY, Kroon L. Ultra-rapid-acting insulins: how fast is really needed? C l i n i c a l D i a b et es . 2021;39(4):415–423."),
                       "Wong EY, Kroon L. Ultra-rapid-acting insulins: how fast is really needed? Clinical Diabetes . 2021;39(4):415–423.")
        XCTAssertEqual(PageLayout.collapsingSpacedLetters("A n n a l s o f S ur g er y."), "Annalsof Surgery.")
        let journal = PageLayout.collapsingSpacedLetters("In: S t a t P ea r l s [ I n t er n et ] . StatPearls Publishing; 2021.")
        XCTAssertEqual(journal, "In: Stat Pearls [ Internet ] . StatPearls Publishing; 2021.")
        // Not spaced out: ordinary text, a row of answers, a line of math, a short run.
        for line in ["Interphase is the longest part of the cell cycle.", "T F T F T F", "x + y = z and a b c", "Take the points A B C and then D E", ""] {
            XCTAssertNil(PageLayout.collapsingSpacedLetters(line), line)
        }
    }

    /// A PDF the way a browser saves one: a header and a footer on every page and the reference list at the end. Read, the lines are the
    /// article's, numbered afterwards.
    func testAPDFWithAHeaderAFooterAndReferencesIsReadWithoutThemAndNumberedAfterwards() async throws {
        let body = [
            ["Interphase is the longest part of the cell cycle and takes most of its time.", "During S phase the cell copies its DNA before it divides.",
             "G1 is a period of growth in which the cell makes proteins."],
            ["Mitosis follows and divides the copied chromosomes between two nuclei.", "Prophase condenses the chromosomes so that they become visible.",
             "Metaphase lines them up along the middle of the cell."],
            ["Anaphase pulls the sister chromatids apart towards opposite poles.", "Telophase forms two new nuclei around the two sets of chromosomes.",
             "Cytokinesis then pinches the cytoplasm in two."],
            ["Cells that stop dividing leave the cycle and enter a resting state.", "Checkpoints stop the cycle when something is wrong with the DNA.",
             "Cancer cells escape these checkpoints and divide without control."],
        ]
        let references = ["References", "1. Alberts B (2002). Molecular Biology of the Cell. Garland Science. ISBN 0-8153-4072-9.",
                          "2. Smith J et al. (2015). The cell cycle. doi:10.1000/182"]
        let pages: [(UIGraphicsPDFRendererContext) -> Void] = (0..<4).map { p in
            { context in
                Render.drawText(["11/3/26, 12:39 PM Cell cycle - Wikipedia"], in: context, size: 9, top: 20)
                Render.drawText(body[p], in: context, size: 11, top: 70)
                if p == 3 { Render.drawText(references, in: context, size: 11, top: 200) }
                Render.drawText(["https://en.wikipedia.org/wiki/Cell_cycle \(p + 1)/4"], in: context, size: 9, top: 760)
            }
        }
        let url = try temporaryFile("Cell cycle.pdf", data: Render.pdf(pages: pages))
        let result = try await PDFReader.read(url, imageFolder: "sources/printout", preferredLanguages: ["en-US"])

        XCTAssertEqual(result.pages.map { $0.lines.map(\.text) }, body)
        XCTAssertEqual(result.pages[3].lines.map(\.id), ["p3.l0", "p3.l1", "p3.l2"], "numbered after the cleaning")
        XCTAssertEqual(result.pages.map(\.label), ["1", "2", "3", "4"])
        XCTAssertEqual(result.cleaning.running, 8)
        XCTAssertEqual(result.cleaning.stamps, 4)
        XCTAssertEqual(result.cleaning.references, 3)
        XCTAssertTrue(result.pages.allSatisfy { $0.read.issue == nil })

        // As a source, and what is sent to be written up: the page left with nothing is not a page of the scan.
        let app = try makeApp()
        let source = try await app.createSource(fromPDF: url, course: makeCourse(app))
        XCTAssertEqual(source.sortedPages.map(\.lines.count), [3, 3, 3, 3])
        XCTAssertEqual(app.generationInput(for: source).pages.count, 4)
        let emptied = source.sortedPages[3]
        emptied.lines = []
        XCTAssertEqual(app.generationInput(for: source).pages.map(\.index), [0, 1, 2], "no lines and no photo: nothing to read")
    }

    func testWithoutThePhotosSwitchNothingIsSentAndTheOfferIsPagePhotos() async throws {
        let app = try mockApp(photos: false)
        let source = try await app.createSource(fromPDF: try makeChainRulePDF(), course: makeCourse(app))
        let result = await app.readPDFPagesWithCloud(sourceID: source.id)
        guard case .notAllowed(let suggestion?) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(suggestion, .allowPhotos)
        XCTAssertEqual(source.pagesWithMissingFormulas.count, 3, "unchanged")
    }

    func testOnlyAScansWorthOfPagesIsReadAtATime() async throws {
        let app = try mockApp(photos: true)
        let page = FormulaGapTests.first
        let pdf = try temporaryFile("Long.pdf", data: Render.pdf(pages: (0..<12).map { _ in { context in Render.drawText(page, in: context, size: 6) } }))
        let source = try await app.createSource(fromPDF: pdf, course: makeCourse(app))
        XCTAssertEqual(source.pagesWithMissingFormulas.count, 12)
        _ = await app.readPDFPagesWithCloud(sourceID: source.id)
        XCTAssertEqual(source.pagesWithMissingFormulas.count, 2, "ten pages a time on the free plan; the rest stay flagged")
    }

}

/// Collects progress callbacks from a background thread.
final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[Int]] = []

    func record(_ done: Int, _ total: Int) {
        lock.lock()
        values.append([done, total])
        lock.unlock()
    }

    var last: [Int]? {
        lock.lock()
        defer { lock.unlock() }
        return values.last
    }
}

private extension String {
    var nonEmptyOrNil: String? { isEmpty ? nil : self }

}
