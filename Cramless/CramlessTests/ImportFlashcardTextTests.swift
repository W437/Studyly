import XCTest
@testable import Cramless

/// Quizlet exports and CSV files: separator detection, quoting, headers, and the edges people actually paste.
@MainActor
final class ImportFlashcardTextTests: CaptureTestCase {
    // MARK: Quizlet

    func testQuizletDefaultExportTabAndNewLine() throws {
        let text = "mitosis\tDivision of a cell into two identical cells, used for growth\nmeiosis\tTwo divisions; makes four gametes\n\nanaphase\tSister chromatids separate\n"
        let preview = try QuizletImporter.preview(text, title: "Unit 3")
        XCTAssertEqual(preview.format, .quizlet)
        XCTAssertEqual(preview.count, 3)
        XCTAssertEqual(preview.cards[0].front, "mitosis")
        XCTAssertEqual(preview.cards[0].back, "Division of a cell into two identical cells, used for growth")
        XCTAssertEqual(preview.cards[1].back, "Two divisions; makes four gametes", "a semicolon inside a definition isn't a card break")
        XCTAssertEqual(preview.cards[0].topic, "Unit 3")
        XCTAssertEqual(preview.summary, "Tab between term and definition, one card per line")
        XCTAssertTrue(preview.warnings.isEmpty)
        XCTAssertEqual(preview.sampleRows.count, 3)
    }

    func testQuizletCommaAndSemicolonOnOneLine() throws {
        let preview = try QuizletImporter.preview("la biblioteca,the library;el examen,the exam;aprobar,to pass (an exam);", title: "")
        XCTAssertEqual(preview.cards.map(\.front), ["la biblioteca", "el examen", "aprobar"])
        XCTAssertEqual(preview.cards.map(\.back), ["the library", "the exam", "to pass (an exam)"])
        XCTAssertEqual(preview.summary, "Comma between term and definition, cards split by semicolons")
        XCTAssertEqual(preview.title, "Quizlet set")
    }

    func testQuizletDashSeparatorBeatsCommasInDefinitions() throws {
        let text = "Osmosis - water moves across a membrane, from dilute to concentrated\nDiffusion - particles spread out, high to low\nActive transport - uses energy, against the gradient"
        let preview = try QuizletImporter.preview(text, title: "Membranes")
        XCTAssertEqual(preview.cards.map(\.front), ["Osmosis", "Diffusion", "Active transport"])
        XCTAssertEqual(preview.cards[0].back, "water moves across a membrane, from dilute to concentrated")
    }

    func testQuizletContinuationLinesAndMissingParts() throws {
        let text = "prophase\tchromatin condenses\nthe nuclear envelope breaks down\nmetaphase\t\n\ttelophase without a term\ncytokinesis\tthe cytoplasm divides"
        let preview = try QuizletImporter.preview(text, title: "Phases")
        XCTAssertEqual(preview.cards.map(\.front), ["prophase", "cytokinesis"])
        XCTAssertEqual(preview.cards[0].back, "chromatin condenses\nthe nuclear envelope breaks down")
        XCTAssertEqual(preview.warnings.count, 2, "\(preview.warnings)")
    }

    func testQuizletLinksAndEmptyTextAreExplained() {
        XCTAssertThrowsError(try QuizletImporter.preview("https://quizlet.com/123456/bio-unit-3-flash-cards/", title: "")) {
            XCTAssertEqual($0 as? CaptureError, .quizletLink)
        }
        XCTAssertThrowsError(try QuizletImporter.preview("   \n ", title: ""))
        XCTAssertThrowsError(try QuizletImporter.preview("Just a paragraph of notes with no separators at all", title: ""))
    }

    func testQuizletWindowsLineEndingsAndBOM() throws {
        let preview = try QuizletImporter.preview("\u{FEFF}cell\tbasic unit of life\r\nnucleus\tholds the DNA\r\n", title: "x")
        XCTAssertEqual(preview.cards.map(\.back), ["basic unit of life", "holds the DNA"])
    }

    // MARK: CSV

    func testCSVQuotedFieldsWithDelimitersQuotesAndLineBreaks() throws {
        let csv = "Term,Definition\n\"Mitosis, the basics\",\"Makes \"\"two\"\" cells\"\n\"Cytokinesis\",\"Divides the cytoplasm\nafter mitosis\"\nMeiosis,Makes gametes\n"
        let preview = try CSVImporter.preview(csv, title: "Bio")
        XCTAssertEqual(preview.format, .csv)
        XCTAssertEqual(preview.count, 3)
        XCTAssertEqual(preview.cards[0].front, "Mitosis, the basics")
        XCTAssertEqual(preview.cards[0].back, "Makes \"two\" cells")
        XCTAssertEqual(preview.cards[1].back, "Divides the cytoplasm\nafter mitosis")
        XCTAssertEqual(preview.summary, "Comma-separated, with a header row")
    }

    func testCSVHeaderColumnsInAnyOrderWithNotesAndTopic() throws {
        let csv = "Topic,Answer,Question,Notes\nCell cycle,G1 S G2 M,What are the phases of the cell cycle?,Interphase is G1 S G2\nMoles,6.022e23,Avogadro's number?,\n"
        let preview = try CSVImporter.preview(csv, title: "Mixed")
        XCTAssertEqual(preview.cards[0].front, "What are the phases of the cell cycle?")
        XCTAssertEqual(preview.cards[0].back, "G1 S G2 M")
        XCTAssertEqual(preview.cards[0].explanation, "Interphase is G1 S G2")
        XCTAssertEqual(preview.cards[0].topic, "Cell cycle")
        XCTAssertEqual(preview.cards[1].topic, "Moles")
        XCTAssertEqual(preview.cards[1].explanation, "")
    }

    func testCSVWithoutHeaderSemicolonsAndTabs() throws {
        let semicolons = try CSVImporter.preview("Avogadro;6,022 × 10²³\nMolar mass;g/mol\n", title: "Chem")
        XCTAssertEqual(semicolons.cards.map(\.front), ["Avogadro", "Molar mass"])
        XCTAssertEqual(semicolons.cards[0].back, "6,022 × 10²³", "a decimal comma stays inside the field")
        XCTAssertEqual(semicolons.summary, "Semicolon-separated, first column front, second back")

        let tabs = try CSVImporter.preview("osmosis\twater moves, dilute to concentrated\ndiffusion\tparticles spread, high to low\n", title: "Bio")
        XCTAssertEqual(tabs.cards[1].back, "particles spread, high to low", "tabs win over commas inside definitions")
    }

    func testExcelSepLineAndLanguageHeader() throws {
        let preview = try CSVImporter.preview("sep=;\nEnglish;Spanish\nthe library;la biblioteca\n", title: "Vocab")
        XCTAssertEqual(preview.count, 1)
        XCTAssertEqual(preview.cards[0].front, "the library")
        XCTAssertEqual(preview.cards[0].back, "la biblioteca")
    }

    func testCSVSkipsRowsMissingASideAndRejectsEmptyFiles() throws {
        let preview = try CSVImporter.preview("front,back\ncell,unit of life\nnucleus,\n,orphan back\n", title: "x")
        XCTAssertEqual(preview.count, 1)
        XCTAssertEqual(preview.warnings, ["2 rows were missing a front or a back and left out."])
        XCTAssertThrowsError(try CSVImporter.preview("", title: "x"))
        XCTAssertThrowsError(try CSVImporter.preview("front,back\n", title: "x"))
    }

    func testTextDecodingHandlesUTF16AndWindows1252() {
        let utf16 = "front\tback\ncafé\tcoffee".data(using: .utf16)!
        XCTAssertEqual(DeckImporter.decodeText(utf16), "front\tback\ncafé\tcoffee")
        let cp1252 = Data([0x63, 0x61, 0x66, 0xE9])
        XCTAssertEqual(DeckImporter.decodeText(cp1252), "café")
    }

    func testFileRoutingByExtensionAndContent() throws {
        let csv = try temporaryFile("cards.csv", data: Data("Question,Answer\nWhat is ATP?,The cell's energy currency\n".utf8))
        XCTAssertEqual(try DeckImporter.preview(fileAt: csv).format, .csv)
        let quizlet = try temporaryFile("set.txt", data: Data("ATP\tenergy currency\nADP\tspent ATP\n".utf8))
        XCTAssertEqual(try DeckImporter.preview(fileAt: quizlet).format, .quizlet)
        let headed = try temporaryFile("headed.txt", data: Data("term,definition\nATP,energy currency\n".utf8))
        XCTAssertEqual(try DeckImporter.preview(fileAt: headed).format, .csv)
        let other = try temporaryFile("slides.key", data: Data("x".utf8))
        XCTAssertThrowsError(try DeckImporter.preview(fileAt: other)) { XCTAssertEqual($0 as? CaptureError, .unsupportedFile("key")) }

        XCTAssertTrue(DeckImporter.looksLikeDeck("ATP\tenergy\nADP\tspent\n"))
        XCTAssertFalse(DeckImporter.looksLikeDeck("Mitosis, in short, makes two cells.\nMeiosis, however, makes four.\n"),
                       "prose with commas is notes, not a deck")
    }

    func testQuizletImportCommitsActiveCardsWithTopics() throws {
        let app = try makeApp()
        let course = makeCourse(app, name: "Spanish II")
        let preview = try app.previewImport(text: "la biblioteca\tthe library\nel examen\tthe exam\n", title: "Unidad 4")
        let outcome = app.commitImport(preview, to: course)
        XCTAssertEqual(outcome.added, 2)
        let source = try XCTUnwrap(app.source(outcome.sourceID))
        XCTAssertEqual(source.kind, .quizlet)
        XCTAssertEqual(source.title, "Unidad 4 (Quizlet)")
        XCTAssertNil(source.fileName)
        XCTAssertTrue(course.liveItems.allSatisfy { $0.origin == .quizlet && $0.status == .active && $0.kind == .flashcard })
        XCTAssertTrue(course.liveItems.allSatisfy { $0.memory.state == .new })
        XCTAssertEqual(course.liveTopics.map(\.name), ["Unidad 4"])
        XCTAssertEqual(course.liveItems.first?.sourceRef?.label, "Unidad 4 (Quizlet)")
    }
}
