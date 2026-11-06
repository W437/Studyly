import SwiftData
import SwiftUI
import XCTest
@testable import Cramless

/// "Looks wrong?": what goes to the relay, what each verdict does, the day's limit, and that a report takes a question out of
/// sessions and leaves it in readiness.
@MainActor
final class LooksWrongTests: CaptureTestCase {
    private func world() throws -> (app: AppModel, course: Course, source: Source, item: StudyItem, relay: ScriptedRelay) {
        let app = try makeApp()
        app.allowCloudAI()
        let relay = ScriptedRelay()
        app.ai.transportOverride = relay
        let course = makeCourse(app)
        let source = Source(course: course, kind: .scan, title: "Biology textbook", status: .ready, now: app.now)
        app.context.insert(source)
        let lines = (0..<6).map { TextLine(id: "p0.l\($0)", text: "Line \($0) of the page.", box: nil) }
        let page = SourcePage(source: source, pageIndex: 0, label: "87", text: lines.map(\.text).joined(separator: "\n"), lines: lines)
        app.context.insert(page)
        let item = StudyItem(course: course, kind: .flashcard, status: .active, origin: .cloud, prompt: "Anaphase", answer: "Line up at the equator",
                             sourceRef: SourceRef(sourceID: source.id, pageIndex: 0, anchorIDs: ["p0.l2", "p0.l3"], start: nil, end: nil, label: "p. 87"),
                             now: app.now)
        app.context.insert(item)
        course.items.append(item)
        app.save()
        return (app, course, source, item, relay)
    }

    nonisolated private static func verdict(_ kind: CheckVerdict.Verdict, answer: String? = nil, choices: [Choice]? = nil) -> CheckResponse {
        CheckResponse(model: "scripted", verdicts: [CheckVerdict(id: AppModel.recheckKey, verdict: kind, reason: "The page says so.",
                                                                 fixedAnswer: answer, fixedChoices: choices)])
    }

    // MARK: What leaves the phone

    func testTheRequestHoldsOnlyTheQuestionsOwnLinesAndTheReport() async throws {
        let w = try world()
        w.app.reportItem(w.item.id, reason: .answerWrong, given: "Anaphase", note: "  Pulled apart, surely.  ")
        w.relay.onCheck = { _, _ in Self.verdict(.supported) }
        _ = await w.app.recheck(w.item.id)
        let request = try XCTUnwrap(w.relay.checkRequests.first)
        XCTAssertEqual(request.pages.count, 1)
        XCTAssertEqual(request.pages[0].lines.map(\.id), ["p0.l2", "p0.l3"], "only the anchored lines")
        XCTAssertNil(request.pages[0].image, "never a photo")
        XCTAssertEqual(request.sourceTitle, "Biology textbook")
        XCTAssertEqual(request.items.map(\.anchors), [["p0.l2", "p0.l3"]])
        let report = try XCTUnwrap(request.reports?.first)
        XCTAssertEqual(report.reason, .answerWrong)
        XCTAssertEqual(report.given, "Anaphase")
        XCTAssertEqual(report.note, "Pulled apart, surely.")
        XCTAssertEqual(report.id, request.items[0].id)
    }

    func testALecturesQuestionIsCheckedAgainstItsSegmentsAsOnePage() async throws {
        let app = try makeApp()
        app.allowCloudAI()
        let relay = ScriptedRelay()
        app.ai.transportOverride = relay
        let course = makeCourse(app)
        let lecture = Source(course: course, kind: .lecture, title: "Lecture 6: Cell division", status: .ready, now: app.now)
        app.context.insert(lecture)
        lecture.segments = [TranscriptSegment(id: "s1", start: 0, end: 5, text: "One."), TranscriptSegment(id: "s2", start: 5, end: 9, text: "Two."),
                            TranscriptSegment(id: "s3", start: 9, end: 12, text: "Three.")]
        let item = StudyItem(course: course, kind: .flashcard, status: .active, origin: .cloud, prompt: "Q", answer: "A",
                             sourceRef: SourceRef(sourceID: lecture.id, pageIndex: nil, anchorIDs: ["s2"], start: 5, end: 9, label: "Lecture 6 · 00:05"), now: app.now)
        app.context.insert(item)
        course.items.append(item)
        app.save()
        XCTAssertEqual(app.reportSource(of: item)?.lines, ["Two."])
        XCTAssertEqual(app.reportSource(of: item)?.place, "Lecture 6")
        app.reportItem(item.id, reason: .other)
        _ = await app.recheck(item.id)
        let request = try XCTUnwrap(relay.checkRequests.first)
        XCTAssertEqual(request.pages.count, 1)
        XCTAssertEqual(request.pages[0].lines.map(\.id), ["s2"])
        XCTAssertEqual(request.pages[0].lines.map(\.text), ["Two."])
    }

    // MARK: What each verdict does

    func testFixedReplacesTheAnswerAndClearsTheReport() async throws {
        let w = try world()
        w.app.reportItem(w.item.id, reason: .answerWrong)
        w.relay.onCheck = { _, _ in Self.verdict(.fixed, answer: "Pulled to opposite poles") }
        let result = await w.app.recheck(w.item.id)
        XCTAssertEqual(result, .fixed)
        XCTAssertEqual(w.item.answer, "Pulled to opposite poles")
        XCTAssertEqual(w.item.explanation, "The page says so.")
        XCTAssertFalse(w.item.reported)
        XCTAssertNotNil(w.item.checkedAt)
        XCTAssertEqual(w.item.status, .active)
    }

    func testAFixedMultipleChoiceTakesItsNewOptionsOrAMatchingOneOrWaitsForAnEdit() {
        let choices = [Choice(text: "Anaphase", correct: false), Choice(text: "Metaphase", correct: true)]
        let verdict = { (answer: String?, fixed: [Choice]?) in
            CheckVerdict(id: "x", verdict: .fixed, reason: "", fixedAnswer: answer, fixedChoices: fixed)
        }
        let swapped = [Choice(text: "Anaphase", correct: true), Choice(text: "Metaphase", correct: false)]
        XCTAssertEqual(RecheckChange.from(verdict(nil, swapped), kind: .mcq, choices: choices), .replace(answer: "Anaphase", choices: swapped))
        XCTAssertEqual(RecheckChange.from(verdict("anaphase", nil), kind: .mcq, choices: choices), .replace(answer: "Anaphase", choices: swapped))
        XCTAssertEqual(RecheckChange.from(verdict("Telophase", nil), kind: .mcq, choices: choices), .needsEdit, "not one of the options")
        let twoRight = [Choice(text: "Anaphase", correct: true), Choice(text: "Metaphase", correct: true)]
        XCTAssertEqual(RecheckChange.from(verdict("Telophase", twoRight), kind: .mcq, choices: choices), .needsEdit, "not a real question")
    }

    func testAFixedFillInOrDiagramRestsUntilItIsEdited() async throws {
        let w = try world()
        w.item.kind = .cloze
        w.app.reportItem(w.item.id, reason: .answerWrong)
        w.relay.onCheck = { _, _ in Self.verdict(.fixed, answer: "anaphase") }
        let result = await w.app.recheck(w.item.id)
        XCTAssertEqual(result, .needsEdit)
        XCTAssertEqual(w.item.status, .suspended)
        XCTAssertEqual(w.item.answer, "Line up at the equator", "its answer isn't changed behind the blank")
        XCTAssertFalse(w.item.reported)
    }

    func testSupportedClearsTheReportAndChangesNothingElse() async throws {
        let w = try world()
        w.app.reportItem(w.item.id, reason: .answerWrong)
        w.relay.onCheck = { _, _ in Self.verdict(.supported) }
        let result = await w.app.recheck(w.item.id)
        XCTAssertEqual(result, .stands)
        XCTAssertEqual(w.item.answer, "Line up at the equator")
        XCTAssertFalse(w.item.reported)
        XCTAssertNotNil(w.item.checkedAt)
        XCTAssertEqual(w.item.status, .active)
    }

    func testUnsupportedTakesItOutOfSessions() async throws {
        let w = try world()
        w.app.reportItem(w.item.id, reason: .questionUnclear)
        w.relay.onCheck = { _, _ in Self.verdict(.unsupported) }
        let result = await w.app.recheck(w.item.id)
        XCTAssertEqual(result, .retired)
        XCTAssertEqual(w.item.status, .suspended)
        XCTAssertFalse(w.item.reported)
    }

    // MARK: Waiting

    func testOfflineTheReportWaitsAndRunsLater() async throws {
        let w = try world()
        w.app.reportItem(w.item.id, reason: .answerWrong)
        w.relay.onCheck = { _, _ in throw RelayError.offline }
        let result = await w.app.recheck(w.item.id)
        XCTAssertEqual(result, .queued)
        XCTAssertTrue(w.item.reported, "it stays out of sessions until it's settled")

        w.relay.onCheck = { _, _ in Self.verdict(.fixed, answer: "Pulled apart") }
        await w.app.runPendingRechecks()
        XCTAssertEqual(w.item.answer, "Pulled apart")
        XCTAssertFalse(w.item.reported)
    }

    func testWithConsentOffNothingIsSentAndConsentRunsIt() async throws {
        let w = try world()
        w.app.withdrawCloudAI()
        w.app.reportItem(w.item.id, reason: .answerWrong)
        let result = await w.app.recheck(w.item.id)
        XCTAssertEqual(result, .queued)
        await w.app.runPendingRechecks()
        XCTAssertTrue(w.relay.checkRequests.isEmpty, "nothing left the phone")
        XCTAssertTrue(w.item.reported)

        w.relay.onCheck = { _, _ in Self.verdict(.supported) }
        w.app.allowCloudAI()
        await w.app.runPendingRechecks()
        XCTAssertFalse(w.item.reported)
        XCTAssertFalse(w.relay.checkRequests.isEmpty)
    }

    func testAReportFromAnotherDeviceHasNoWordsAndIsStillChecked() async throws {
        let w = try world()
        w.item.reported = true
        w.app.save()
        await w.app.runPendingRechecks()
        XCTAssertFalse(w.item.reported)
        XCTAssertEqual(w.relay.checkRequests.first?.reports?.first?.reason, .other)
    }

    func testAQuestionWithNothingBehindItIsLetGoSoItComesBack() async throws {
        let w = try world()
        w.app.reportItem(w.item.id, reason: .answerWrong)
        w.item.sourceRef = nil
        w.app.save()
        XCTAssertNil(w.app.reportSource(of: w.item), "the sheet offers Edit and Skip")
        await w.app.runPendingRechecks()
        XCTAssertFalse(w.item.reported)
        XCTAssertTrue(w.relay.checkRequests.isEmpty)
    }

    func testPuttingItBackDropsTheReport() async throws {
        let w = try world()
        w.app.reportItem(w.item.id, reason: .answerWrong)
        w.app.withdrawReport(w.item.id)
        XCTAssertFalse(w.item.reported)
        await w.app.runPendingRechecks()
        XCTAssertTrue(w.relay.checkRequests.isEmpty)
    }

    // MARK: The rules

    func testAtMostThreeMyAnswerShouldCountADay() throws {
        let w = try world()
        var day = w.app.now
        w.app.clock = { day }
        XCTAssertEqual(w.app.myAnswerReportsLeft(), 3)
        for left in [2, 1, 0] {
            XCTAssertTrue(w.app.reportItem(w.item.id, reason: .myAnswerCounts, given: "x"))
            XCTAssertEqual(w.app.myAnswerReportsLeft(), left)
        }
        XCTAssertFalse(w.app.reportItem(w.item.id, reason: .myAnswerCounts, given: "x"), "the fourth is refused")
        XCTAssertTrue(w.app.reportItem(w.item.id, reason: .answerWrong), "the other reasons aren't limited")
        day = day.addingTimeInterval(86_400)
        XCTAssertEqual(w.app.myAnswerReportsLeft(), 3, "tomorrow is a new day")
    }

    func testAReportedQuestionLeavesSessionsAndStaysInReadiness() throws {
        let w = try world()
        var memory = MemoryState()
        memory.state = .review
        memory.stability = 10
        memory.lastReview = w.app.now
        memory.due = w.app.now
        w.item.memory = memory
        let exam = Exam(course: w.course, title: "Quiz", date: w.app.now.addingTimeInterval(5 * 86_400), now: w.app.now)
        w.app.context.insert(exam)
        w.app.save()
        let snapshot = ExamSnapshot(exam)
        let before = w.app.readinessValue(of: snapshot)
        XCTAssertGreaterThan(before, 0)
        XCTAssertTrue(w.app.buildSession(SessionRequest(kind: .daily)).entries.contains { $0.itemID == w.item.id })

        w.app.reportItem(w.item.id, reason: .answerWrong)
        XCTAssertFalse(w.app.buildSession(SessionRequest(kind: .daily)).entries.contains { $0.itemID == w.item.id }, "out of sessions")
        XCTAssertFalse(w.app.buildSession(SessionRequest(kind: .practice, courseID: w.course.id)).entries.contains { $0.itemID == w.item.id })
        XCTAssertEqual(w.app.readinessValue(of: snapshot), before, accuracy: 0.0001, "still in readiness")
        XCTAssertEqual(w.item.status, .active)
    }

    // MARK: The open question

    func testASkipInASessionRecordsNothing() throws {
        let w = try world()
        let runner = SessionRunner(app: w.app, request: SessionRequest(kind: .practice, courseID: w.course.id, itemIDs: [w.item.id]))
        runner.start()
        XCTAssertEqual(runner.current?.itemID, w.item.id)
        runner.skipWithoutRecording()
        XCTAssertTrue(runner.answers.isEmpty, "nothing recorded")
        XCTAssertEqual(w.app.fetch(FetchDescriptor<ReviewLog>()).count, 0)
        XCTAssertEqual(runner.phase, .finished)
    }

    func testTheAnswerPanelsRowFitsTheSmallestIPhone() throws {
        let w = try world()
        // The row as the panel lays it out, at the text size the words show at: 375 wide less the gutters, 10 between.
        func width(_ view: some View) -> CGFloat {
            UIHostingController(rootView: view.environment(w.app).dynamicTypeSize(.large))
                .sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)).width
        }
        let explain = width(Label("Explain my mistake", systemImage: "bubble.left").clFont(.subheadlineEmphasis).padding(.horizontal, 16))
        let looksWrong = width(LooksWrongButton(item: w.item))
        XCTAssertLessThanOrEqual(looksWrong, 130)
        XCTAssertGreaterThanOrEqual(looksWrong, CLMetrics.minHitTarget)
        XCTAssertLessThanOrEqual(explain + 10 + looksWrong, 375 - 2 * CLSpace.gutter)
        XCTAssertLessThan(width(LooksWrongButton(item: w.item, compact: true)), looksWrong, "only the icon, with a third button in the row")
    }

    func testTheWordsSayWhatHappened() {
        XCTAssertEqual(LooksWrongCopy.outcome(.fixed, place: "p. 87", inSession: true), "You were right. Cap fixed the question. This one counts as right.")
        XCTAssertEqual(LooksWrongCopy.outcome(.fixed, place: "p. 87", inSession: false), "You were right. Cap fixed the question.")
        XCTAssertEqual(LooksWrongCopy.outcome(.stands, place: "p. 87", inSession: true), "The page agrees with the answer.")
        XCTAssertEqual(LooksWrongCopy.outcome(.retired, place: "p. 87", inSession: true), "Cap couldn't back this question with p. 87, so it's out of your sessions.")
        XCTAssertEqual(LooksWrongCopy.outcome(.queued, place: "p. 87", inSession: true), "Cap will check this when you're online. It won't count against you.")
    }
}
