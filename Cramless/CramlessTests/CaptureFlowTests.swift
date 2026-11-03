import XCTest
@testable import Cramless

/// `CaptureRun`, the processing screen's runner: the real work in order, every step shown in order, the honest
/// failures, and nothing left behind when the person leaves.
@MainActor
final class CaptureFlowTests: CaptureTestCase {

    /// An app on an in-memory store with the AI ladder of `mode`, no waits, and no device model.
    private func makeFlowApp(mode: AppConfig.AIMode, consent: Bool = true) -> AppModel {
        let defaults = UserDefaults(suiteName: "capture-flow-tests-\(UUID().uuidString)")!
        var environment = ["XCTestConfigurationFilePath": "capture-flow-tests"]
        if !consent { environment["CRAMLESS_CONSENT"] = "0" }
        let config = AppConfig(supabaseURL: nil, supabaseAnonKey: nil, aiMode: mode, isHarness: false, inMemoryStore: true,
                               seedDemoData: false, environment: environment)
        let app = AppModel(config: config, defaults: defaults)
        app.settings.cloudConsentVersion = consent ? AIConsent.currentVersion : 0
        app.ai.mockLatencyScale = 0
        app.ai.streamPause = .zero
        app.ai.probe = FixedOnDeviceProbe(.unavailable(.notChecked))
        return app
    }

    private func run(_ app: AppModel, _ request: CaptureRequest, regenerating: UUID? = nil,
                     skipMathGate: Bool = false) async throws -> CaptureRun {
        let run = CaptureRun(app: app, request: request, regenerating: regenerating, skipMathGate: skipMathGate)
        run.pace = 0
        run.start()
        let deadline = Date().addingTimeInterval(20)
        while run.phase == .running, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotEqual(run.phase, .running, "the run didn't finish")
        return run
    }

    func testTheSamplePassesThroughEveryStepToItsReview() async throws {
        let app = makeFlowApp(mode: .mock)
        let course = makeCourse(app)

        let run = try await run(app, CaptureRequest(input: .sample, courseID: course.id))

        guard case .review(let sourceID) = run.phase else { return XCTFail("expected the review, got \(run.phase)") }
        XCTAssertEqual(run.stepLog, [.reading, .ideas, .writing, .checking, .done])
        XCTAssertEqual(run.topics, ["Phases of mitosis", "Cytokinesis", "Why mitosis matters", "Chromosome number"])
        XCTAssertEqual(run.shownWritten, 16)
        XCTAssertEqual(run.checkLine, "15 of 16 match the page")
        XCTAssertEqual(run.origin, .cloud)
        XCTAssertEqual(run.cards.count, 3)
        XCTAssertTrue(run.cards.allSatisfy { $0.label == "p. 87" })
        // Only real, boxed lines of the page are ever marked.
        let boxed = Set((SamplePage.ocr()?.lines ?? []).filter { $0.box != nil }.map(\.id))
        XCTAssertFalse(run.marked.isEmpty)
        XCTAssertTrue(Set(run.marked).isSubset(of: boxed))
        XCTAssertEqual(run.marked.count, Set(run.marked).count, "no line marked twice")
        XCTAssertEqual(app.draftItems(sourceID: sourceID).count, 15)
        XCTAssertEqual(app.source(sourceID)?.course?.id, course.id)
    }

    func testASetWrittenAgainByAWeakerTierKeepsTheCloudQuestionsAndTheReviewSaysWhy() async throws {
        let app = makeFlowApp(mode: .relay)
        let relay = RecordingTransport()
        app.ai.transportOverride = relay
        let course = makeCourse(app)
        let first = try await run(app, CaptureRequest(input: .sample, courseID: course.id))
        guard case .review(let sourceID) = first.phase else { return XCTFail("expected the review, got \(first.phase)") }
        let written = app.draftItems(sourceID: sourceID)
        XCTAssertEqual(written.count, 15)
        XCTAssertEqual(app.draftReport(sourceID: sourceID)?.origin, .cloud)

        // The formulas read worked, and then Cloud AI couldn't be reached to write the set again: the rules wrote one. It never replaces
        // the questions in review, which would have been deleted for it.
        relay.failures["generate"] = .offline
        let again = try await run(app, CaptureRequest(input: .sample, courseID: course.id), regenerating: sourceID, skipMathGate: true)
        guard case .review(let id) = again.phase else { return XCTFail("expected the review, got \(again.phase)") }
        XCTAssertEqual(id, sourceID)
        XCTAssertEqual(again.stepLog.last, .done)
        XCTAssertEqual(app.draftItems(sourceID: sourceID).map(\.id), written.map(\.id), "the same questions, not a basic set")
        XCTAssertTrue(app.draftItems(sourceID: sourceID).allSatisfy { $0.origin == .cloud })
        var report = try XCTUnwrap(app.draftReport(sourceID: sourceID))
        XCTAssertEqual(report.origin, .cloud)
        XCTAssertEqual(report.note, "Cloud AI couldn't be reached, so your earlier questions are kept.")
        XCTAssertTrue(again.cards.isEmpty, "no questions of the weaker set land on the screen")

        // The week's free scans are used up when it is written again: the same, and the plans are offered.
        relay.failures["generate"] = .quotaExceeded(QuotaStatus(plan: .free, meters: [QuotaMeter(key: .scans, used: 3, limit: 3, period: .week)]),
                                                    message: "That's this week's 3 AI scans on the free plan.")
        let limited = try await run(app, CaptureRequest(input: .sample, courseID: course.id), regenerating: sourceID, skipMathGate: true)
        guard case .review = limited.phase else { return XCTFail("expected the review, got \(limited.phase)") }
        XCTAssertEqual(app.draftItems(sourceID: sourceID).map(\.id), written.map(\.id))
        report = try XCTUnwrap(app.draftReport(sourceID: sourceID))
        XCTAssertEqual(report.note, "You've used this week's free Cloud AI scans, so your earlier questions are kept.")
        guard case .upgrade(.scans, _)? = report.suggestion?.aiSuggestion else { return XCTFail("\(String(describing: report.suggestion))") }

        // Cloud AI answers: a set from the same tier replaces them, as ever.
        relay.failures["generate"] = nil
        app.ai.setServerQuota(nil)
        app.ai.resetUsage()
        let better = try await run(app, CaptureRequest(input: .sample, courseID: course.id), regenerating: sourceID, skipMathGate: true)
        guard case .review = better.phase else { return XCTFail("expected the review, got \(better.phase)") }
        let replaced = app.draftItems(sourceID: sourceID)
        XCTAssertEqual(replaced.count, 15)
        XCTAssertTrue(Set(replaced.map(\.id)).isDisjoint(with: written.map(\.id)), "new questions")
        XCTAssertNil(app.draftReport(sourceID: sourceID)?.note)
    }

    func testOfflineTheRulesWriteTheSetAndTheReviewSaysSo() async throws {
        let app = makeFlowApp(mode: .local, consent: false)
        let course = makeCourse(app)

        let run = try await run(app, CaptureRequest(input: .sample, courseID: course.id))

        guard case .review(let sourceID) = run.phase else { return XCTFail("expected the review, got \(run.phase)") }
        XCTAssertEqual(run.origin, .rules)
        XCTAssertEqual(run.stepLog, [.reading, .ideas, .writing, .checking, .done])
        let report = try XCTUnwrap(app.draftReport(sourceID: sourceID))
        XCTAssertEqual(report.origin, .rules)
        XCTAssertEqual(report.note, "Basic questions from the offline rules.")
        XCTAssertNil(report.suggestion, "no Cloud AI in this build, so nothing to suggest")
        XCTAssertFalse(app.draftItems(sourceID: sourceID).isEmpty)
        XCTAssertTrue(app.draftItems(sourceID: sourceID).allSatisfy { $0.origin == .rules })
    }

    func testWithoutConsentTheReviewOffersCloudAI() async throws {
        let app = makeFlowApp(mode: .mock, consent: false)
        let course = makeCourse(app)

        let run = try await run(app, CaptureRequest(input: .sample, courseID: course.id))

        guard case .review(let sourceID) = run.phase else { return XCTFail("expected the review, got \(run.phase)") }
        let report = try XCTUnwrap(app.draftReport(sourceID: sourceID))
        XCTAssertEqual(report.origin, .rules)
        guard case .allowCloud = report.suggestion else { return XCTFail("expected the Cloud AI suggestion") }
        XCTAssertTrue(report.note?.contains("Turn on Cloud AI") == true)
    }

    func testPastedTextGoesThroughTheSameSteps() async throws {
        let app = makeFlowApp(mode: .local, consent: false)
        let course = makeCourse(app)
        let notes = "Mitosis makes two daughter cells that are genetically identical to the parent cell. "
            + "In prophase the chromosomes condense and the nuclear envelope breaks down. "
            + "In metaphase the chromosomes line up at the equator of the cell. "
            + "After mitosis, cytokinesis divides the cytoplasm into two cells."

        let run = try await run(app, CaptureRequest(input: .text(title: "Cell division", body: notes), courseID: course.id))

        guard case .review(let sourceID) = run.phase else { return XCTFail("expected the review, got \(run.phase)") }
        XCTAssertNil(run.preview?.imagePath, "text is drawn on paper")
        XCTAssertEqual(app.source(sourceID)?.title, "Cell division")
        XCTAssertFalse(app.draftItems(sourceID: sourceID).isEmpty)
    }

    func testNothingPastedFailsWithASentence() async throws {
        let app = makeFlowApp(mode: .local)

        let run = try await run(app, CaptureRequest(input: .text(title: "", body: "   \n "), courseID: nil))

        XCTAssertEqual(run.phase, .failed(.message(CaptureError.emptyText.errorDescription ?? "")))
    }

    func testAPhotoWithNoTextFailsHonestlyAndKeepsNothing() async throws {
        let app = makeFlowApp(mode: .local)
        let blank = Render.jpeg(Render.textImage([]))
        let paths = try PageImageStore.stage(imageData: [blank])

        let run = try await run(app, CaptureRequest(input: .images(paths), courseID: nil))

        XCTAssertEqual(run.phase, .failed(.noText))
        let id = try XCTUnwrap(run.sourceID)
        XCTAssertTrue(app.source(id)?.pages.allSatisfy { $0.lines.isEmpty } ?? false, "empty, never guessed")
        XCTAssertTrue(app.draftItems(sourceID: id).isEmpty)

        // Closing the problem screen (or trying another photo) leaves no unreadable source behind.
        run.discard()
        XCTAssertNil(app.source(id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: FileStore.url(for: PageImageStore.sourceFolder(id)).path))
    }

    func testAMathPageStopsBeforeWritingUnlessThePersonGoesOn() async throws {
        let app = makeFlowApp(mode: .local)
        let course = makeCourse(app)
        let source = Source(course: course, kind: .scan, title: "Calculus notes", status: .read, now: app.now)
        app.context.insert(source)
        course.sources.append(source)
        let lines = ["Derivatives measure how a function changes as its input changes.",
                     "The derivative of a constant is zero.",
                     "f(x) = x² + 3x, so f′(x) = 2x + 3",
                     "∫ 2x dx = x² + C"].enumerated().map {
            TextLine(id: "p0.l\($0.offset)", text: $0.element, box: NormRect(x: 0.1, y: 0.1 + Double($0.offset) * 0.05, w: 0.6, h: 0.03))
        }
        let page = SourcePage(source: source, pageIndex: 0, label: "1", text: lines.map(\.text).joined(separator: "\n"),
                              lines: lines, width: 1000, height: 1400)
        page.read = PageRead(engine: .vision, confidence: 1, issue: .mathLike)
        app.context.insert(page)
        source.pages.append(page)
        app.save()
        let request = CaptureRequest(input: .images([]), courseID: course.id)

        let stopped = try await run(app, request, regenerating: source.id)
        XCTAssertEqual(stopped.phase, .failed(.mathLike))
        XCTAssertTrue(app.draftItems(sourceID: source.id).isEmpty)

        let onward = try await run(app, request, regenerating: source.id, skipMathGate: true)
        XCTAssertNotEqual(onward.phase, .failed(.mathLike), "the person chose to go on")
    }

    func testAPDFWhoseFormulasVanishedIsNotStoppedAsMath() async throws {
        let app = makeFlowApp(mode: .local)
        let course = makeCourse(app)
        let source = Source(course: course, kind: .pdf, title: "Chain rule", status: .read, now: app.now)
        app.context.insert(source)
        course.sources.append(source)
        let lines = ["The chain rule is a formula for the derivative of a composite function.",
                     "It is expressed in Leibniz's notation as", "and", "Intuitively, rates of change multiply along the chain."].enumerated().map {
            TextLine(id: "p0.l\($0.offset)", text: $0.element, box: nil)
        }
        let page = SourcePage(source: source, pageIndex: 0, label: "1", text: lines.map(\.text).joined(separator: "\n"), lines: lines)
        page.read = PageRead(engine: .pdfText, confidence: 1, issue: .mathLike)
        app.context.insert(page)
        source.pages.append(page)
        app.save()

        let ran = try await run(app, CaptureRequest(input: .images([]), courseID: course.id), regenerating: source.id)

        XCTAssertNotEqual(ran.phase, .failed(.mathLike), "the words are right; the review says the formulas may be missing")
        XCTAssertTrue(page.formulasMayBeMissing)
    }

    func testAnEmptyOfflineSetCarriesTheOfferToCloudAI() async throws {
        let app = makeFlowApp(mode: .mock, consent: false)
        let course = makeCourse(app)
        // Text the offline rules find nothing to ask about.
        let request = CaptureRequest(input: .text(title: "Notes", body: "ok so yeah then we go on to the next one and so on and so forth, you know."),
                                     courseID: course.id)
        let first = try await run(app, request)
        guard case .failed(.noQuestions(let note?)) = first.phase else { return XCTFail("expected no questions, got \(first.phase)") }
        XCTAssertEqual(note, "The offline rules couldn't find questions on this page.")
        XCTAssertEqual(first.noQuestionsSuggestion, .allowCloud(feature: AIJob.generate.feature))
    }

    func testLeavingPartWayThrowsAwayWhatWasMade() async throws {
        let app = makeFlowApp(mode: .mock)
        app.ai.mockLatencyScale = 0.4
        let course = makeCourse(app)
        let run = CaptureRun(app: app, request: CaptureRequest(input: .sample, courseID: course.id))
        run.pace = 0
        run.start()
        let deadline = Date().addingTimeInterval(10)
        while run.sourceID == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        let id = try XCTUnwrap(run.sourceID)

        run.discard()
        try await Task.sleep(for: .seconds(2))

        XCTAssertNil(app.source(id))
        XCTAssertTrue(app.draftItems(sourceID: id).isEmpty, "no drafts arrive after the person left")
        XCTAssertTrue(course.liveItems.isEmpty)
        XCTAssertEqual(run.phase, .running, "the screen is gone; nothing more is shown")
    }
}
