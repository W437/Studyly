import XCTest
@testable import Cramless

/// Typed and pasted text: pages of about 600 words, a line per sentence and per line break, no boxes.
@MainActor
final class CaptureTextTests: CaptureTestCase {
    /// Ten sentences of ten words: 100 words.
    private func paragraph(_ index: Int, sentences: Int = 10) -> String {
        (0..<sentences).map { "Paragraph \(index) sentence \($0) has exactly ten words in it." }.joined(separator: " ")
    }

    func testLinesBySentenceAndLineBreak() {
        let text = "Mitosis makes two cells. Meiosis makes four!\nKey term: cytokinesis\n\n  Dr. Smith said it's on the test.  "
        let pages = TextPaginator.pages(from: text)
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].lines.map(\.text), [
            "Mitosis makes two cells.", "Meiosis makes four!", "Key term: cytokinesis", "Dr. Smith said it's on the test.",
        ])
        XCTAssertEqual(pages[0].lines.map(\.id), ["p0.l0", "p0.l1", "p0.l2", "p0.l3"])
        XCTAssertTrue(pages[0].lines.allSatisfy { $0.box == nil })
        XCTAssertEqual(pages[0].label, "1")
        XCTAssertEqual(pages[0].read, .typed)
    }

    func testPagesOfAboutSixHundredWordsBreakAtParagraphs() {
        // 15 paragraphs of 100 words: 1500 words.
        let text = (0..<15).map { paragraph($0) }.joined(separator: "\n\n")
        let pages = TextPaginator.pages(from: text)
        let counts = pages.map { TextPaginator.wordCount($0.lines.map(\.text)) }
        XCTAssertEqual(counts.reduce(0, +), 1500, "no words lost")
        XCTAssertEqual(counts, [600, 600, 300])
        XCTAssertEqual(pages.first?.lines.count, 60, "a line per sentence")
        for page in pages {
            XCTAssertTrue(page.lines.first?.text.hasSuffix("sentence 0 has exactly ten words in it.") == true,
                          "each page starts at a paragraph: \(page.lines.first?.text ?? "")")
            XCTAssertEqual(page.lines.first?.id, "p\(page.pageIndex).l0")
        }
        XCTAssertEqual(pages.map(\.label), ["1", "2", "3"])
    }

    func testARunOnWithoutPunctuationIsCut() {
        let words = (0..<150).map { "word\($0)" }.joined(separator: " ")
        let lines = TextPaginator.lines(from: words, splitSentences: true)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines.allSatisfy { TextPaginator.wordCount($0) <= TextPaginator.maxLineWords })
    }

    func testEmptyTextIsRefused() throws {
        let app = try makeApp()
        XCTAssertThrowsError(try app.createSource(fromText: " \n\n ", course: nil)) { XCTAssertEqual($0 as? CaptureError, .emptyText) }
    }

    func testPastedTextBecomesAReadSource() throws {
        let app = try makeApp()
        let course = makeCourse(app)
        let source = try app.createSource(fromText: "Osmosis moves water. Diffusion moves particles.", title: "  Membranes ", course: course)
        XCTAssertEqual(source.kind, .text)
        XCTAssertEqual(source.status, .read)
        XCTAssertEqual(source.title, "Membranes")
        XCTAssertEqual(source.sortedPages.count, 1)
        XCTAssertEqual(source.sortedPages[0].text, "Osmosis moves water.\nDiffusion moves particles.")
        XCTAssertEqual(source.sortedPages[0].read?.engine, .typed)
        XCTAssertTrue(course.liveSources.contains { $0.id == source.id })
        XCTAssertNotNil(source.updatedAt)

        let untitled = try app.createSource(fromText: "Chapter 3 notes on moles.\nMore.", course: nil)
        XCTAssertEqual(untitled.title, "Chapter 3 notes on moles.")
    }
}
