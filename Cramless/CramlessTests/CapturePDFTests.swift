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
