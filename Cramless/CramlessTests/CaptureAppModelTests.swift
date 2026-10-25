import UIKit
import XCTest
@testable import Cramless

/// `AppModel+Capture`: sources from staged pages and the sample, files opened from other apps, discarding, and the
/// hook for a better read.
@MainActor
final class CaptureAppModelTests: CaptureTestCase {
    func testStagedPagesBecomeAReadSource() async throws {
        let app = try makeApp()
        let course = makeCourse(app)
        let sample = try XCTUnwrap(SamplePage.imageURL)
        let staged = try PageImageStore.stage(imageData: [Data(contentsOf: sample)])
        var progress: [CaptureProgress] = []
        let source = try await app.createSource(from: CaptureRequest(input: .images(staged), courseID: course.id)) { progress.append($0) }

        XCTAssertEqual(source.kind, .scan)
        XCTAssertEqual(source.status, .read)
        XCTAssertTrue(source.title.contains("How Cells Divide"), "the page's heading names the source: \(source.title)")
        let page = try XCTUnwrap(source.sortedPages.first)
        XCTAssertEqual(page.label, "87")
        XCTAssertEqual(page.imageFileName, "sources/\(source.id.uuidString)/page-0.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: FileStore.url(for: page.imageFileName!).path))
        XCTAssertGreaterThan(page.lines.count, 30)
        XCTAssertEqual(page.text, page.lines.map(\.text).joined(separator: "\n"))
        XCTAssertEqual(page.read?.engine, .vision)
        XCTAssertFalse(page.wantsBetterRead)
        XCTAssertEqual(page.width, 1200)
        XCTAssertEqual(progress.last, CaptureProgress(stage: .saving, completed: 1, total: 1))
        XCTAssertTrue(course.liveSources.contains { $0.id == source.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: FileStore.url(for: staged[0]).path), "staging is emptied")
    }

    func testAGivenTitleIsKept() async throws {
        let app = try makeApp()
        let staged = try PageImageStore.stage(imageData: [Render.jpeg(Render.textImage(["Notes from Tuesday"]))])
        let source = try await app.createSource(fromImages: staged, course: nil, title: "My notes", kind: .photo)
        XCTAssertEqual(source.title, "My notes")
        XCTAssertEqual(source.kind, .photo)
    }

    func testAnUnreadablePageFailsHonestlyAndCanBeReadBetterLater() async throws {
        let app = try makeApp()
        let blank = try PageImageStore.stage(imageData: [Render.jpeg(Render.textImage([]))])
        let source = try await app.createSource(fromImages: blank, course: nil)
        XCTAssertEqual(source.status, .failed, "nothing readable: no lines are invented")
        XCTAssertTrue(source.title.hasPrefix("Scan, "))
        let page = try XCTUnwrap(source.sortedPages.first)
        XCTAssertEqual(page.read?.issue, .noText)

        // A cloud transcription (the AI lane's job) or typed text puts the lines in.
        app.replaceLines(of: page, with: [TextLine(id: "p0.c0", text: "Mitosis notes", box: nil)])
        XCTAssertEqual(page.text, "Mitosis notes")
        XCTAssertEqual(page.read?.engine, .cloud)
        XCTAssertEqual(source.status, .read)
    }

    func testTheSampleWithAndWithoutACourse() throws {
        let app = try makeApp()
        let course = makeCourse(app)
        let inCourse = app.createSampleSource(course: course)
        XCTAssertEqual(inCourse.kind, .sample)
        XCTAssertEqual(inCourse.sortedPages.first?.label, "87")
        XCTAssertEqual(inCourse.sortedPages.first?.lines.count, 40)
        XCTAssertEqual(inCourse.sortedPages.first?.read, .sample)
        XCTAssertTrue(course.liveSources.contains { $0.id == inCourse.id })

        let loose = app.createSampleSource(course: nil)
        XCTAssertNil(loose.course)
        XCTAssertEqual(loose.status, .read)
        XCTAssertEqual(loose.sortedPages.first?.lines.first?.id, "p0.l0")
        let image = try XCTUnwrap(loose.sortedPages.first?.imageFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: FileStore.url(for: image).path))
    }

    func testTheSampleRequestGoesThroughCreateSource() async throws {
        let app = try makeApp()
        let source = try await app.createSource(from: CaptureRequest(input: .sample, courseID: nil))
        XCTAssertEqual(source.kind, .sample)
        let text = try await app.createSource(from: CaptureRequest(input: .text(title: "Ch. 3", body: "Moles count particles."), courseID: nil))
        XCTAssertEqual(text.title, "Ch. 3")
    }

    func testDiscardRemovesAnUnsyncedSourceAndItsFiles() async throws {
        let app = try makeApp()
        let staged = try PageImageStore.stage(imageData: [Render.jpeg(Render.textImage(["Throw me away"]))])
        let source = try await app.createSource(fromImages: staged, course: nil)
        let folder = FileStore.url(for: PageImageStore.sourceFolder(source.id))
        let id = source.id
        app.discardSource(source)
        XCTAssertNil(app.source(id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testDiscardSoftDeletesASyncedSource() throws {
        let app = try makeApp()
        let source = try app.createSource(fromText: "Already on the server.", course: nil)
        source.syncedAt = app.now
        app.discardSource(source)
        XCTAssertEqual(app.source(source.id)?.deletedAt, app.now)
    }

    // MARK: Files from other apps

    func testAnOpenedPDFStartsTheCaptureFlow() throws {
        let app = try makeApp()
        let pdf = try temporaryFile("Slides.pdf", data: Render.pdf(pages: [{ Render.drawText(["Hello cells, this is a slide"], in: $0) }]))
        app.importFile(pdf)
        guard case .captureFlow(let request)? = app.router.cover, case .pdf(let kept) = request.input else {
            return XCTFail("expected the capture flow, got \(String(describing: app.router.cover))")
        }
        XCTAssertEqual(kept.lastPathComponent, "Slides.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
    }

    func testAnOpenedDeckWaitsForTheImportSheet() throws {
        let app = try makeApp()
        let csv = try temporaryFile("cards.csv", data: Data("front,back\nATP,energy\n".utf8))
        app.importFile(csv)
        XCTAssertEqual(app.router.sheet, .importDeck(courseID: nil))
        let pending = try XCTUnwrap(app.pendingImportFile)
        XCTAssertEqual(pending.lastPathComponent, "cards.csv")
        XCTAssertEqual(try DeckImporter.preview(fileAt: pending).count, 1)
        app.clearPendingImport()
        XCTAssertNil(app.pendingImportFile)
    }

    func testAnOpenedTextFileIsADeckOrNotes() throws {
        let app = try makeApp()
        app.importFile(try temporaryFile("set.txt", data: Data("ATP\tenergy\nADP\tspent\n".utf8)))
        XCTAssertEqual(app.router.sheet, .importDeck(courseID: nil))
        app.router.dismissSheet()
        app.clearPendingImport()

        app.importFile(try temporaryFile("Lecture notes.txt", data: Data("Mitosis, in short, makes two cells.\nMeiosis makes four.".utf8)))
        guard case .captureFlow(let request)? = app.router.cover, case .text(let title, let body) = request.input else {
            return XCTFail("notes go to the capture flow")
        }
        XCTAssertEqual(title, "Lecture notes")
        XCTAssertTrue(body.hasPrefix("Mitosis"))
    }

    func testAnUnsupportedFileGetsAToast() throws {
        let app = try makeApp()
        app.importFile(try temporaryFile("talk.key", data: Data("x".utf8)))
        XCTAssertNil(app.router.cover)
        XCTAssertNil(app.router.sheet)
        XCTAssertEqual(app.router.toast?.tone, .warning)
        XCTAssertTrue(app.router.toast.map { String(localized: $0.message).contains(".key") } == true)
    }
}
