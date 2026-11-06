import CoreGraphics
import ImageIO
import UIKit
import XCTest
@testable import Cramless

/// Text recognition on this iPhone's Vision (the Simulator runs the same models): the bundled sample page, the
/// confidence gate's test pair, and the pure geometry behind reading order and page numbers.
@MainActor
final class OCRTests: CaptureTestCase {
    private func sampleImage() throws -> CGImage {
        let url = try XCTUnwrap(SamplePage.imageURL, "the sample page ships in the app bundle")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func index(_ needle: String, in lines: [TextLine], file: StaticString = #filePath, line: UInt = #line) throws -> Int {
        try XCTUnwrap(lines.firstIndex { $0.text.localizedCaseInsensitiveContains(needle) }, "no line contains \(needle)", file: file, line: line)
    }

    // MARK: Another language first

    /// With Traditional Chinese first, Vision scores printed English under the gate: the page would come back empty.
    func testAnEnglishPageIsReadOnAnIPhoneSetToChinese() async throws {
        let image = try sampleImage()
        let page = try await TextRecognizer.readingEnglishToo(preferredLanguages: ["zh-Hant", "en-US"]) {
            try await TextRecognizer.read(image, pageIndex: 0, preferredLanguages: $0)
        }
        XCTAssertGreaterThanOrEqual(page.lines.count, 34)
        _ = try index("How Cells Divide", in: page.lines)
    }

    func testTheSecondReadIsInEnglishAndOnlyWhenTheFirstKeptNothing() async throws {
        func captured(_ lines: [String]) -> CapturedPage {
            CapturedPage(pageIndex: 0, label: "1", lines: lines.enumerated().map { TextLine(id: "p0.l\($0.offset)", text: $0.element, box: nil) },
                         width: 100, height: 100, read: PageRead(engine: .vision, confidence: 1))
        }
        var asked: [[String]] = []
        func read(_ first: [String], second: [String], preferred: [String]) async throws -> CapturedPage {
            asked = []
            return try await TextRecognizer.readingEnglishToo(preferredLanguages: preferred) { languages in
                asked.append(languages)
                return captured(asked.count == 1 ? first : second)
            }
        }
        var page = try await read(["讀到了"], second: ["read"], preferred: ["zh-Hant"])
        XCTAssertEqual(page.lines.map(\.text), ["讀到了"])
        XCTAssertEqual(asked, [["zh-Hant"]], "a page that was read isn't read again")
        page = try await read([], second: ["read"], preferred: ["zh-Hant", "en-US"])
        XCTAssertEqual(page.lines.map(\.text), ["read"])
        XCTAssertEqual(asked, [["zh-Hant", "en-US"], ["en-US"]])
        page = try await read([], second: [], preferred: ["he-IL"])
        XCTAssertTrue(page.lines.isEmpty, "still nothing: the empty page stands")
        page = try await read([], second: ["read"], preferred: ["en-GB"])
        XCTAssertTrue(page.lines.isEmpty)
        XCTAssertEqual(asked, [["en-GB"]], "English came first: nothing to retry")
    }

    // MARK: The sample page

    func testRecognisesTheSamplePage() async throws {
        let page = try await TextRecognizer.read(sampleImage(), pageIndex: 0, preferredLanguages: ["en-US"])
        print("OCR sample: \(page.lines.count) lines, confidence \(page.read.confidence), dropped \(page.read.droppedLines)")
        for line in page.lines { print("  \(line.id) \(line.text)") }

        XCTAssertGreaterThanOrEqual(page.lines.count, 34, "about 40 lines on the page")
        XCTAssertEqual(page.label, "87", "the printed page number in the top corner")
        XCTAssertEqual(page.read.engine, .vision)
        XCTAssertNil(page.read.issue)
        XCTAssertGreaterThanOrEqual(page.read.confidence, TextRecognizer.pageFloor)
        XCTAssertEqual(page.width, 1200)
        XCTAssertEqual(page.height, 1800)
        // Anchor ids in order, matching the bundled recognition's format.
        XCTAssertEqual(page.lines.map(\.id), page.lines.indices.map { "p0.l\($0)" })
        for line in page.lines {
            let box = try XCTUnwrap(line.box, "scanned lines have boxes")
            XCTAssertTrue((0...1).contains(box.x) && (0...1).contains(box.y) && box.w > 0 && box.h > 0 && box.x + box.w <= 1.001)
        }

        // The lines a student studies from, tolerating small differences in recognition.
        let title = try index("How Cells Divide", in: page.lines)
        XCTAssertTrue(page.lines[title].text.hasPrefix("Mitosis"))
        _ = try index("cytokinesis takes place", in: page.lines)
        _ = try index("Key term", in: page.lines)

        // Reading order: header, title, introduction, then the phase grid column by column (each phase with its
        // own bullets), then the sections below.
        let unit = try index("Cell Biology", in: page.lines)
        let intro = try index("process by which a single", in: page.lines)
        let prophase = try XCTUnwrap(page.lines.firstIndex { $0.text == "Prophase" })
        let condense = try index("Chromosomes condense", in: page.lines)
        let breaks = try index("breaks down", in: page.lines)
        let metaphase = try XCTUnwrap(page.lines.firstIndex { $0.text == "Metaphase" })
        let equator = try index("equator of the cell", in: page.lines)
        let telophase = try XCTUnwrap(page.lines.firstIndex { $0.text == "Telophase" })
        let after = try index("What happens after mitosis", in: page.lines)
        XCTAssertLessThan(unit, title)
        XCTAssertLessThan(title, intro)
        XCTAssertLessThan(intro, prophase)
        XCTAssertLessThan(prophase, condense)
        XCTAssertLessThan(condense, breaks, "a column reads top to bottom")
        XCTAssertLessThan(breaks, metaphase, "Prophase's bullets come before the next phase")
        XCTAssertLessThan(metaphase, equator)
        XCTAssertLessThan(equator, telophase)
        XCTAssertLessThan(telophase, after)
        XCTAssertEqual(page.lines[condense + 1].text.lowercased().contains("become visible"), true,
                       "a bullet's continuation follows it: \(page.lines[condense + 1].text)")

        XCTAssertEqual(PageLayout.titleLine(in: page.lines).map { $0.contains("How Cells Divide") }, true)
    }

    func testReadsAStoredPageImage() async throws {
        let url = try XCTUnwrap(SamplePage.imageURL)
        let stored = try FileStore.copy(from: url, folder: "sources/test", name: "page-0.jpg")
        let page = try await TextRecognizer.read(imageAt: stored, pageIndex: 2, preferredLanguages: ["en-US"])
        XCTAssertEqual(page.imageFileName, stored)
        XCTAssertEqual(page.pageIndex, 2)
        XCTAssertEqual(page.lines.first?.id, "p2.l0")
        XCTAssertEqual(page.label, "87")
    }

    // MARK: The gate's test pair (ml-honesty)

    /// Hebrew is not a script Vision reads here: what it returns is Latin-looking garbage at low confidence, and the
    /// gate must turn that into an empty page. Printed English on the same background must survive. One without
    /// the other proves nothing.
    func testUnsupportedScriptGatesToEmptyWhileAPrintedControlSurvives() async throws {
        let hebrew = Render.textImage(["מיטוזה היא חלוקת תא", "שלבים: פרופאזה, מטאפאזה", "אנאפאזה וטלופאזה",
                                       "הכרומוזומים מתיישרים במרכז"], font: .systemFont(ofSize: 48))
        let control = Render.textImage(["Mitosis notes - Tuesday", "PMAT: prophase, metaphase,", "anaphase, telophase",
                                        "chromosomes line up in the middle"], font: .systemFont(ofSize: 44))
        let gated = try await TextRecognizer.read(XCTUnwrap(hebrew.cgImage), pageIndex: 0, preferredLanguages: ["en-US"])
        let kept = try await TextRecognizer.read(XCTUnwrap(control.cgImage), pageIndex: 0, preferredLanguages: ["en-US"])
        print("OCR gate: hebrew confidence \(gated.read.confidence) dropped \(gated.read.droppedLines) issue \(String(describing: gated.read.issue)); control confidence \(kept.read.confidence) lines \(kept.lines.count)")

        XCTAssertTrue(gated.lines.isEmpty, "garbage must not be stored: \(gated.lines.map(\.text))")
        XCTAssertTrue(gated.read.issue == .unreadable || gated.read.issue == .noText)
        XCTAssertTrue(gated.read.wantsBetterRead || gated.read.issue == .noText)

        XCTAssertEqual(kept.lines.count, 4)
        XCTAssertNil(kept.read.issue)
        XCTAssertEqual(kept.read.confidence, 1, accuracy: 0.2)
        XCTAssertEqual(kept.lines.first?.text.hasPrefix("Mitosis notes"), true, "\(kept.lines.map(\.text))")
    }

    func testABlankPageHasNoText() async throws {
        let blank = Render.textImage([])
        let page = try await TextRecognizer.read(XCTUnwrap(blank.cgImage), pageIndex: 0)
        XCTAssertTrue(page.lines.isEmpty)
        XCTAssertEqual(page.read.issue, .noText)
        XCTAssertEqual(page.label, "1")
    }

    // MARK: A problem from a photo

    private func stagedProblem(_ lines: [String]) throws -> String {
        let image = Render.textImage(lines)
        return try XCTUnwrap(PageImageStore.stage(imageData: [Render.jpeg(image)]).first)
    }

    func testAPrintedProblemIsReadAndItsPhotoIsGone() async throws {
        let path = try stagedProblem(["Problem 3.", "A cell with 46 chromosomes goes through mitosis.", "How many chromosomes does each daughter cell have?"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: FileStore.url(for: path).path))
        let reading = await SnapReader.read(stagedAt: path, preferredLanguages: ["en-US"])
        XCTAssertTrue(reading.hasWords)
        XCTAssertTrue(reading.text.contains("46 chromosomes"), reading.text)
        XCTAssertTrue(reading.text.contains("daughter cell"), reading.text)
        XCTAssertNil(reading.issue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: FileStore.url(for: path).path), "the photo stays on this iPhone only for the reading")
        let folder = (path as NSString).deletingLastPathComponent
        XCTAssertFalse(FileManager.default.fileExists(atPath: FileStore.url(for: folder).path), "nor does its folder")
    }

    func testASheetInEnglishIsReadOnAnIPhoneSetToAnotherLanguage() async throws {
        let lines = ["Problem 3.", "A cell with 46 chromosomes goes through mitosis.", "How many chromosomes does each daughter cell have?"]
        // Read with Chinese first, printed English scores under the gate and the page keeps nothing (measured at 0.3 to 0.5).
        let image = try XCTUnwrap(Render.textImage(lines).cgImage)
        let gated = try await TextRecognizer.read(image, pageIndex: 0, preferredLanguages: ["zh-Hant-TW"])
        print("OCR snap: zh-Hant first, confidence \(gated.read.confidence), lines \(gated.lines.count)")
        let reading = await SnapReader.read(stagedAt: try stagedProblem(lines), preferredLanguages: ["zh-Hant-TW"])
        XCTAssertTrue(reading.text.contains("46 chromosomes"), reading.text)
    }

    func testABlankPhotoHasNoWordsAndIsGoneToo() async throws {
        let path = try stagedProblem([])
        let reading = await SnapReader.read(stagedAt: path, preferredLanguages: ["en-US"])
        XCTAssertFalse(reading.hasWords)
        XCTAssertEqual(reading.issue, .noText)
        XCTAssertFalse(FileManager.default.fileExists(atPath: FileStore.url(for: path).path))
    }

    func testAPhotoThatCantBeOpenedIsUnreadable() async throws {
        let path = try FileStore.write(Data("not an image".utf8), folder: "\(PageImageStore.stagingFolder)/bad", name: "page-0.jpg")
        let reading = await SnapReader.read(stagedAt: path)
        XCTAssertFalse(reading.hasWords)
        XCTAssertEqual(reading.issue, .unreadable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: FileStore.url(for: path).path))
    }

    func testAMathPageKeepsItsWordsAndSaysSo() {
        let page = CapturedPage(pageIndex: 0, label: "1", lines: [TextLine(id: "p0.l0", text: "Solve 2x² + 3x = 5", box: nil)], read: PageRead(engine: .vision, issue: .mathLike))
        let reading = SnapReader.reading(from: page)
        XCTAssertEqual(reading.text, "Solve 2x² + 3x = 5")
        XCTAssertEqual(reading.issue, .mathLike)
        XCTAssertTrue(reading.hasWords)
    }

    func testLinesBrokenByThePageRunOnAndPartsKeepTheirOwn() {
        XCTAssertEqual(SnapReader.flowing(["Homework 3", "Problem 4. A cell with 46 chromosomes goes through",
                                           "mitosis. How many chromosomes does each daughter", "cell have?"]),
                       "Homework 3\nProblem 4. A cell with 46 chromosomes goes through mitosis. How many chromosomes does each daughter cell have?")
        XCTAssertEqual(SnapReader.flowing(["1. Name the phases of mitosis in the order they happen", "2. Say what happens in the last of them, in a sentence"]),
                       "1. Name the phases of mitosis in the order they happen\n2. Say what happens in the last of them, in a sentence")
        XCTAssertEqual(SnapReader.flowing(["Solve for x and show every step of your working", "2x + 3 = 11"]),
                       "Solve for x and show every step of your working\n2x + 3 = 11")
        XCTAssertEqual(SnapReader.flowing(["What is it?"]), "What is it?")
        XCTAssertEqual(SnapReader.flowing([]), "")
    }

    func testOneLineOfNotationIsEnoughForTheNoteOnAProblem() {
        func reading(_ lines: [String]) -> SnapReader.Reading {
            let textLines = lines.enumerated().map { TextLine(id: "p0.l\($0.offset)", text: $0.element, box: nil) }
            return SnapReader.reading(from: CapturedPage(pageIndex: 0, label: "1", lines: textLines, read: PageRead(engine: .vision)))
        }
        XCTAssertEqual(reading(["Solve for x:", "2x + 3 = 11"]).issue, .mathLike)
        XCTAssertNil(reading(["Problem 3.", "A cell with 46 chromosomes goes through mitosis."]).issue, "a number is not notation")
    }

    func testAWholePageReadByMistakeIsCut() {
        let line = TextLine(id: "p0.l0", text: String(repeating: "word ", count: 2_000), box: nil)
        let page = CapturedPage(pageIndex: 0, label: "1", lines: [line], read: PageRead(engine: .vision))
        XCTAssertLessThanOrEqual(SnapReader.reading(from: page).text.count, SnapReader.maxCharacters)
    }

    func testDiscardingLeavesEverythingButStagedPages() throws {
        let kept = try FileStore.write(Data([1]), folder: "sources/x", name: "page-0.jpg")
        PageImageStore.discardStaged([kept])
        XCTAssertTrue(FileManager.default.fileExists(atPath: FileStore.url(for: kept).path))
    }

    // MARK: The gate, pure

    private func raw(_ text: String, x: Double = 0.1, y: Double, w: Double = 0.6, h: Double = 0.02, confidence: Double = 1) -> RawLine {
        RawLine(text: text, box: NormRect(x: x, y: y, w: w, h: h), confidence: confidence)
    }

    func testFloorDropsALowLineAndKeepsTheRest() {
        let page = TextRecognizer.page(from: [raw("Real text", y: 0.1), raw("GLIGNAL VANGNIU", y: 0.2, confidence: 0.5),
                                              raw("More real text", y: 0.3)], pageIndex: 1, width: 100, height: 100)
        XCTAssertEqual(page.lines.map(\.text), ["Real text", "More real text"])
        XCTAssertEqual(page.lines.map(\.id), ["p1.l0", "p1.l1"])
        XCTAssertEqual(page.read.droppedLines, 1)
        XCTAssertEqual(page.read.confidence, 0.833, accuracy: 0.001)
        XCTAssertNil(page.read.issue)
        XCTAssertEqual(page.label, "2", "no printed number: the position")
    }

    func testALowConfidencePageKeepsNothing() {
        let page = TextRecognizer.page(from: [raw("Maybe words", y: 0.1, confidence: 1), raw("ALEO GLIGNIL", y: 0.2, confidence: 0.5),
                                              raw("UCLICLICO", y: 0.3, confidence: 0.5)], pageIndex: 0, width: 1, height: 1)
        XCTAssertTrue(page.lines.isEmpty)
        XCTAssertEqual(page.read.issue, .unreadable)
        XCTAssertEqual(page.read.droppedLines, 3)
        XCTAssertTrue(page.read.wantsBetterRead)
    }

    func testMathPagesAreFlaggedNotDropped() {
        let page = TextRecognizer.page(from: [raw("Integrals", y: 0.05), raw("So1 x2 dx = 1/3", y: 0.1), raw("E (n=1 → ∞) 1/n2 = n2/6", y: 0.2),
                                              raw("f'(x) = lim h→0 [f(x+h) - f(x)]/h", y: 0.3)], pageIndex: 0, width: 1, height: 1)
        XCTAssertEqual(page.lines.count, 4)
        XCTAssertEqual(page.read.issue, .mathLike)
        XCTAssertTrue(page.read.wantsBetterRead)
    }

    // MARK: Reading order, pure

    func testTwoColumnPageReadsColumnByColumn() {
        let lines = [
            raw("Chapter 5: Cells", x: 0.1, y: 0.05, w: 0.8, h: 0.03),
            raw("Left one", x: 0.08, y: 0.2, w: 0.38), raw("Right one", x: 0.54, y: 0.2, w: 0.38),
            raw("Left two", x: 0.08, y: 0.225, w: 0.38), raw("Right two", x: 0.54, y: 0.227, w: 0.38),
            raw("Left three", x: 0.08, y: 0.25, w: 0.38), raw("Right three", x: 0.54, y: 0.249, w: 0.38),
            raw("A closing paragraph across the page", x: 0.08, y: 0.4, w: 0.84),
        ]
        XCTAssertEqual(PageLayout.readingOrder(lines.shuffled()).map(\.text), [
            "Chapter 5: Cells", "Left one", "Left two", "Left three", "Right one", "Right two", "Right three",
            "A closing paragraph across the page",
        ])
    }

    func testTableHeaderJoinsItsColumnAcrossAGap() {
        let lines = [
            raw("Prophase", x: 0.13, y: 0.27, w: 0.09, h: 0.015), raw("Metaphase", x: 0.34, y: 0.27, w: 0.1, h: 0.015),
            raw("• Chromosomes condense", x: 0.08, y: 0.42, w: 0.19, h: 0.012), raw("• Line up at", x: 0.29, y: 0.42, w: 0.18, h: 0.012),
            raw("and become visible.", x: 0.09, y: 0.433, w: 0.14, h: 0.012), raw("the equator.", x: 0.31, y: 0.433, w: 0.15, h: 0.012),
            raw("What happens after mitosis?", x: 0.07, y: 0.55, w: 0.42, h: 0.025),
        ]
        XCTAssertEqual(PageLayout.readingOrder(lines.reversed()).map(\.text), [
            "Prophase", "• Chromosomes condense", "and become visible.", "Metaphase", "• Line up at", "the equator.",
            "What happens after mitosis?",
        ])
    }

    func testRowsKeepSideBySideItemsLeftToRight() {
        let rows = PageLayout.rows([raw("B", x: 0.5, y: 0.1, w: 0.1), raw("A", x: 0.1, y: 0.101, w: 0.1), raw("C", x: 0.1, y: 0.2, w: 0.1)])
        XCTAssertEqual(rows.map { $0.map(\.text) }, [["A", "B"], ["C"]])
    }

    func testPageNumbers() {
        let body = (0..<10).map { raw("Body line \($0)", y: 0.15 + Double($0) * 0.05) }
        XCTAssertEqual(PageLayout.pageNumber(in: body + [raw("87", x: 0.83, y: 0.08, w: 0.03, h: 0.01)]), "87")
        XCTAssertEqual(PageLayout.pageNumber(in: body + [raw("- 12 -", x: 0.47, y: 0.7, w: 0.06, h: 0.01)]), "12", "bottom centre")
        XCTAssertEqual(PageLayout.pageNumber(in: body + [raw("Page 4", x: 0.85, y: 0.7, w: 0.08, h: 0.01)]), "4")
        XCTAssertNil(PageLayout.pageNumber(in: body + [raw("42", x: 0.45, y: 0.4, w: 0.03, h: 0.01)]), "a number mid-page isn't a page number")
        XCTAssertNil(PageLayout.pageNumber(in: body), "no number")
        let list = (1...4).map { raw("\($0)", x: 0.05, y: 0.08 + Double($0) * 0.15, w: 0.02, h: 0.01) }
        XCTAssertNil(PageLayout.pageNumber(in: body + list), "a column of list numbers isn't a page number")
        XCTAssertEqual(PageLayout.pageNumberText("12 / 40"), "12")
        XCTAssertEqual(PageLayout.pageNumberText("p. 87"), "87")
        XCTAssertNil(PageLayout.pageNumberText("Unit 3"))
        XCTAssertNil(PageLayout.pageNumberText("0"))
    }

    func testMathLikeLines() {
        XCTAssertTrue(PageLayout.isMathLike("2H2 + O2 → 2H2O"))
        XCTAssertTrue(PageLayout.isMathLike("x2 + 3x = 10"))
        XCTAssertTrue(PageLayout.isMathLike("∫ f(x) dx"))
        XCTAssertFalse(PageLayout.isMathLike("Mitosis is the process by which a single cell divides."))
        XCTAssertFalse(PageLayout.isMathLike("Read pages 12-14 by Friday, 10/22/2026."))
        XCTAssertFalse(PageLayout.isMathLike(page: ["One = sign in prose", "and plain text", "more text", "even more"]))
    }

    func testRecognitionLanguagesFollowThePersonThenEnglish() {
        let supported = ["en-US", "fr-FR", "zh-Hant-TW", "de-DE"].map { Locale.Language(identifier: $0) }
        let chosen = TextRecognizer.languages(preferred: ["fr-CA", "he-IL", "zh-TW"], supported: supported)
        XCTAssertEqual(chosen.map { $0.languageCode?.identifier }, ["fr", "zh", "en"], "Hebrew isn't read, so it's skipped")
        XCTAssertEqual(chosen[1].script?.identifier, "Hant", "Taiwan's Chinese is the traditional script")
        XCTAssertEqual(TextRecognizer.languages(preferred: [], supported: supported).map { $0.languageCode?.identifier }, ["en"])
    }
}
