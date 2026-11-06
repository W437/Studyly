import SwiftData
import XCTest
@testable import Cramless

/// When a question has become too easy, and what a harder one starts from. Pure.
final class LadderEngineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func review(_ daysAgo: Double, _ rating: Rating = .good) -> ReviewSnapshot {
        ReviewSnapshot(itemID: UUID(), courseID: nil, sessionID: nil, reviewedAt: now.addingTimeInterval(-daysAgo * 86_400), rating: rating, stabilityAfter: 30)
    }

    private func strongMemory(_ stability: Double = 30) -> MemoryState {
        var memory = MemoryState()
        memory.state = .review
        memory.stability = stability
        memory.difficulty = 5
        memory.lastReview = now.addingTimeInterval(-86_400)
        return memory
    }

    func testTheLadderOfFormats() {
        XCTAssertEqual(Ladder.next(after: .mcq), .cloze)
        XCTAssertEqual(Ladder.next(after: .cloze), .recall)
        XCTAssertEqual(Ladder.next(after: .recall), .apply)
        XCTAssertEqual(Ladder.next(after: .flashcard), .recall)
        XCTAssertNil(Ladder.next(after: .apply))
        XCTAssertNil(Ladder.next(after: .diagram))
    }

    func testStrongMeansARealRunNotACram() {
        let run = [review(1), review(8), review(20)]
        XCTAssertTrue(Ladder.isStrong(strongMemory(), reviews: run))
        XCTAssertTrue(Ladder.isStrong(strongMemory(), reviews: run.reversed()), "any order")
        XCTAssertFalse(Ladder.isStrong(strongMemory(20.9), reviews: run), "not stable enough")
        var learning = strongMemory()
        learning.state = .learning
        XCTAssertFalse(Ladder.isStrong(learning, reviews: run))
        XCTAssertFalse(Ladder.isStrong(strongMemory(), reviews: [review(1), review(8)]), "fewer than three")
        XCTAssertFalse(Ladder.isStrong(strongMemory(), reviews: [review(1), review(2), review(20)]), "two within four days")
        XCTAssertFalse(Ladder.isStrong(strongMemory(), reviews: [review(1, .hard), review(8), review(20)]), "Hard isn't too easy")
        XCTAssertTrue(Ladder.isStrong(strongMemory(), reviews: [review(1, .easy), review(5, .good), review(9, .easy), review(10, .again)]),
                      "only the last three count")
    }

    func testTheSeedStartsWeakerHarderAndSoon() throws {
        let seed = Ladder.seedMemory(parent: strongMemory(40), now: now, calendar: calendar)
        XCTAssertEqual(seed.state, .review)
        XCTAssertEqual(seed.stability, 14, "at most 14 days")
        XCTAssertEqual(seed.difficulty, 6.5)
        XCTAssertEqual(seed.lastReview, now)
        XCTAssertEqual(calendar.dayDistance(from: now, to: try XCTUnwrap(seed.due)), 1, "due tomorrow")
        XCTAssertEqual(Ladder.seedMemory(parent: strongMemory(4), now: now, calendar: calendar).stability, 3, "at least 3 days")
        XCTAssertEqual(Ladder.seedMemory(parent: strongMemory(21), now: now, calendar: calendar).stability, 10.5)
        var hardest = strongMemory()
        hardest.difficulty = 9.5
        XCTAssertEqual(Ladder.seedMemory(parent: hardest, now: now, calendar: calendar).difficulty, 10)
    }

    private func candidate(_ kind: ItemKind = .mcq, stability: Double = 30, hasAnchors: Bool = true, climbed: Bool = false, snoozed: Bool = false,
                           exam: Date? = nil) -> Ladder.Candidate {
        Ladder.Candidate(id: UUID(), kind: kind, memory: strongMemory(stability), reviews: [review(1), review(8), review(20)],
                         hasAnchors: hasAnchors, climbed: climbed, snoozed: snoozed, soonestExam: exam)
    }

    func testWhatIsOffered() {
        let inDays = { (days: Double) in self.now.addingTimeInterval(days * 86_400) }
        XCTAssertEqual(Ladder.offers([candidate()], cloudUsable: true, now: now, calendar: calendar).first?.next, .cloze)
        XCTAssertTrue(Ladder.offers([candidate()], cloudUsable: false, now: now, calendar: calendar).isEmpty, "only with Cloud AI")
        XCTAssertTrue(Ladder.offers([candidate(hasAnchors: false)], cloudUsable: true, now: now, calendar: calendar).isEmpty, "needs lines to write from")
        XCTAssertTrue(Ladder.offers([candidate(climbed: true)], cloudUsable: true, now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(Ladder.offers([candidate(snoozed: true)], cloudUsable: true, now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(Ladder.offers([candidate(.apply)], cloudUsable: true, now: now, calendar: calendar).isEmpty, "nothing harder")
        XCTAssertTrue(Ladder.offers([candidate(exam: inDays(3))], cloudUsable: true, now: now, calendar: calendar).isEmpty, "not 3 days before its exam")
        XCTAssertEqual(Ladder.offers([candidate(exam: inDays(4))], cloudUsable: true, now: now, calendar: calendar).count, 1)
        let weaker = candidate(stability: 25), stronger = candidate(stability: 60)
        XCTAssertEqual(Ladder.offers([weaker, stronger], cloudUsable: true, now: now, calendar: calendar).map(\.itemID), [stronger.id, weaker.id], "the strongest first")
    }

    func testTheWritersLinesAreItsOwnAndTwoEitherSide() {
        let lines = (0..<20).map { TextLine(id: "l\($0)", text: "x", box: nil) }
        XCTAssertEqual(Ladder.neighbourhood(of: ["l5"], in: lines, limit: 60).map(\.id), ["l3", "l4", "l5", "l6", "l7"])
        XCTAssertEqual(Ladder.neighbourhood(of: ["l0"], in: lines, limit: 60).map(\.id), ["l0", "l1", "l2"])
        XCTAssertEqual(Ladder.neighbourhood(of: ["l19"], in: lines, limit: 60).map(\.id), ["l17", "l18", "l19"])
        XCTAssertEqual(Ladder.neighbourhood(of: ["l5", "l6"], in: lines, limit: 60).map(\.id), ["l3", "l4", "l5", "l6", "l7", "l8"])
        XCTAssertEqual(Ladder.neighbourhood(of: ["l1", "l9"], in: lines, limit: 2).map(\.id), ["l1", "l9"], "over the limit, its own lines")
        XCTAssertTrue(Ladder.neighbourhood(of: ["gone"], in: lines, limit: 60).isEmpty)
    }

    func testTheCardsWords() {
        XCTAssertEqual(LadderCopy.noticeTitle(topic: "Limiting reagents"), "Limiting reagents is too easy now")
        XCTAssertEqual(LadderCopy.noticeTitle(topic: nil), "This one is too easy now")
        XCTAssertEqual(LadderCopy.noticeLine(next: .apply), "Next time, the same idea in a real problem?")
        XCTAssertEqual(LadderCopy.noticeLine(next: .cloze), "Next time, the same idea as a fill-in?")
        XCTAssertEqual(LadderCopy.noticeLine(next: .recall), "Next time, the same idea in your own words?")
        XCTAssertEqual(LadderCopy.noticeAction, "Yes, harder")
    }

    // MARK: The card

    private func inputs(_ change: (inout NoticeInputs) -> Void = { _ in }) -> NoticeInputs {
        var inputs = NoticeInputs(now: now, calendar: calendar, fsrs: FSRS())
        change(&inputs)
        return inputs
    }

    private func offer(_ topic: String? = "Limiting reagents", next: ItemKind = .apply) -> NoticeTooEasy {
        NoticeTooEasy(itemID: UUID(), next: next, topicName: topic)
    }

    func testTheCardNamesTheIdeaSaysWhatItSpendsAndOpensTheSheet() throws {
        let first = offer(), second = offer("Moles")
        let cards = NoticeEngine(inputs { $0.tooEasy = [first, second] }).candidates()
        XCTAssertEqual(cards.map(\.kind), [.tooEasy], "one idea at a time")
        let card = try XCTUnwrap(cards.first)
        XCTAssertEqual(card.id, NoticeEngine.tooEasyID(first.itemID))
        XCTAssertFalse(card.notifiable, "there's no hurry in it")
        let said = NoticeContent.card(card, firstName: "Maya", now: now, calendar: calendar)
        XCTAssertEqual(said.title, "Limiting reagents is too easy now")
        XCTAssertEqual(said.detail, "Next time, the same idea in a real problem?")
        XCTAssertEqual(said.action?.title, "Yes, harder")
        XCTAssertEqual(said.action?.run, .raiseQuestion(itemID: first.itemID))
        XCTAssertEqual(said.cost, "1 draft")
    }

    func testTheSwitchTurnsItOffAndAnExamTomorrowQuietsIt() {
        var off = NoticeSettings()
        off.off = [.tooEasy]
        XCTAssertTrue(NoticeEngine(inputs { $0.tooEasy = [offer()]; $0.settings = off }).candidates().isEmpty)
        let tomorrow = ExamSnapshot(id: UUID(), courseID: nil, title: "Quiz", date: now.addingTimeInterval(86_400), scope: [], target: 0.8)
        XCTAssertTrue(NoticeEngine(inputs { $0.tooEasy = [offer()]; $0.exams = [tomorrow] }).candidates().isEmpty)
    }

    func testItWaitsBehindWhatNeedsHelp() {
        let fix = NoticeMixUp(note: ConfusionNote(id: UUID(), name: "A vs B", missCount: 1, recentMisses: 1, recentAnswers: 2), itemIDs: [])
        let cards = NoticeEngine(inputs { $0.tooEasy = [offer()]; $0.mixUps = [fix] }).candidates()
        XCTAssertEqual(cards.map(\.kind), [.mixUp, .tooEasy])
    }
}

/// A harder question from offer to added, and that readiness holds.
@MainActor
final class LadderAppModelTests: CaptureTestCase {
    private struct World {
        var app: AppModel
        var course: Course
        var exam: Exam
        var parent: StudyItem
        var relay: ScriptedRelay
    }

    /// A course of `others` studied questions plus one that has become too easy, and an exam 30 days away.
    private func world(others: Int = 24, stability: Double = 30) throws -> World {
        let app = try makeApp()
        app.allowCloudAI()
        let relay = ScriptedRelay()
        app.ai.transportOverride = relay
        let course = makeCourse(app)
        let source = Source(course: course, kind: .scan, title: "Biology textbook", status: .ready, now: app.now)
        app.context.insert(source)
        let lines = (0..<10).map { TextLine(id: "p0.l\($0)", text: "Line \($0) of the page, with enough words in it.", box: nil) }
        app.context.insert(SourcePage(source: source, pageIndex: 0, label: "87", text: "", lines: lines))
        let exam = Exam(course: course, title: "Midterm", date: app.now.addingTimeInterval(30 * 86_400), now: app.now)
        app.context.insert(exam)
        var memory = MemoryState()
        memory.state = .review
        memory.stability = stability
        memory.difficulty = 5
        memory.lastReview = app.now.addingTimeInterval(-2 * 86_400)
        memory.due = app.now.addingTimeInterval(20 * 86_400)
        memory.reps = 3
        let parent = StudyItem(course: course, kind: .mcq, status: .active, origin: .cloud, prompt: "Which phase?", answer: "Anaphase",
                               choices: [Choice(text: "Anaphase", correct: true), Choice(text: "Metaphase", correct: false)],
                               sourceRef: SourceRef(sourceID: source.id, pageIndex: 0, anchorIDs: ["p0.l4"], start: nil, end: nil, label: "p. 87"),
                               now: app.now.addingTimeInterval(-40 * 86_400))
        parent.memory = memory
        app.context.insert(parent)
        course.items.append(parent)
        for days in [2.0, 10, 20] {
            let log = ReviewLog(itemID: parent.id, courseID: course.id, sessionID: nil, reviewedAt: app.now.addingTimeInterval(-days * 86_400), rating: .good,
                                gradedBy: "rules", durationMs: 1000, before: memory, after: memory, elapsedDays: 8, scheduledDays: 8)
            app.context.insert(log)
        }
        for n in 0..<others {
            let other = StudyItem(course: course, kind: .flashcard, status: .active, origin: .cloud, prompt: "Q\(n)", answer: "A\(n)", now: app.now)
            other.memory = memory
            other.memory.stability = 12
            app.context.insert(other)
            course.items.append(other)
        }
        app.save()
        relay.onGenerate = { request, _ in
            let id = request.pages[0].lines[0].id
            let item = GeneratedItem(id: "i1", kind: request.formats[0], topic: "Mitosis", prompt: "Harder question", answer: "Harder answer",
                                     cloze: ClozeSpec(text: "It is {{anaphase}}.", alternates: [[]]), anchors: [id, "made-up"], difficulty: 0.7)
            return GenerateResponse(title: "x", model: "scripted", topics: [], items: [item])
        }
        return World(app: app, course: course, exam: exam, parent: parent, relay: relay)
    }

    func testATooEasyQuestionIsOfferedOnlyWhenItCan() throws {
        let w = try world()
        XCTAssertEqual(w.app.ladderOffers().map(\.itemID), [w.parent.id])
        XCTAssertEqual(w.app.ladderOffers().first?.next, .cloze)
        w.app.withdrawCloudAI()
        XCTAssertTrue(w.app.ladderOffers().isEmpty, "no harder question without Cloud AI")
    }

    func testWritingAsksForOneHarderQuestionOnTheLinesAroundIt() async throws {
        let w = try world()
        let writing = await w.app.writeRung(for: w.parent.id)
        guard case .proposal(let id) = writing else { return XCTFail("\(writing)") }
        let request = try XCTUnwrap(w.relay.generateRequests.first)
        XCTAssertEqual(request.formats, [.cloze])
        XCTAssertEqual(request.maxItems, 1)
        XCTAssertEqual(request.pages.count, 1)
        XCTAssertEqual(request.pages[0].lines.map(\.id), ["p0.l2", "p0.l3", "p0.l4", "p0.l5", "p0.l6"])
        XCTAssertNil(request.pages[0].image)
        XCTAssertEqual(request.rung, RungRequest(kind: .mcq, prompt: "Which phase?", answer: "Anaphase"))
        XCTAssertEqual(w.relay.checkRequests.count, 1, "checked like every written question")
        XCTAssertNil(w.relay.checkRequests[0].reports)

        let draft = try XCTUnwrap(w.app.item(id))
        XCTAssertEqual(draft.status, .draft, "it arrives as a draft")
        XCTAssertEqual(draft.rungOf, w.parent.id)
        XCTAssertEqual(draft.topicID, w.parent.topicID)
        XCTAssertNotNil(draft.checkedAt)
        XCTAssertEqual(draft.sourceRef?.anchorIDs, ["p0.l2"], "only lines it was given")
        XCTAssertEqual(w.parent.status, .active, "nothing changes until it's added")
        XCTAssertTrue(w.app.draftItems(sourceID: try XCTUnwrap(draft.sourceRef?.sourceID)).isEmpty, "not with the source's new questions")
        XCTAssertEqual(w.app.ladderOffers().map(\.itemID), [w.parent.id], "the card can come back for a draft not decided on")

        // Asked again, it's the same draft: nothing is spent twice.
        let again = await w.app.writeRung(for: w.parent.id)
        XCTAssertEqual(again, .proposal(id))
        XCTAssertEqual(w.relay.generateRequests.count, 1)
    }

    func testAddingRestsTheEasyOneAndReadinessHolds() async throws {
        let w = try world()
        let snapshot = ExamSnapshot(w.exam)
        let before = w.app.readinessValue(of: snapshot)
        let writing = await w.app.writeRung(for: w.parent.id)
        guard case .proposal(let id) = writing else { return XCTFail("\(writing)") }
        XCTAssertEqual(w.app.readinessValue(of: snapshot), before, accuracy: 0.0001, "a draft doesn't count")

        XCTAssertTrue(w.app.adoptRung(id))
        let rung = try XCTUnwrap(w.app.item(id))
        XCTAssertEqual(rung.status, .active)
        XCTAssertEqual(rung.memory.state, .review)
        XCTAssertEqual(rung.memory.stability, 14)
        XCTAssertEqual(w.parent.status, .suspended)
        XCTAssertTrue(w.app.ladderOffers().isEmpty, "the idea has moved up: nothing more to offer for it")
        let after = w.app.readinessValue(of: snapshot)
        XCTAssertLessThan(abs(after - before) * 100, Ladder.maxReadinessDrop, "readiness moves less than 2 points")
    }

    func testAnOfferThatWouldSinkReadinessIsNotMade() throws {
        // On its own, a very strong question swapped for a 14-day seed would cost far more than 2 points.
        let w = try world(others: 0, stability: 200)
        XCTAssertGreaterThan(w.app.readinessDrop(ifRaising: ItemSnapshot(w.parent, courseID: w.course.id), items: w.app.itemSnapshots(),
                                                 exams: w.app.examSnapshots(upcomingOnly: true)), Ladder.maxReadinessDrop)
        XCTAssertTrue(w.app.ladderOffers().isEmpty)
    }

    func testUndoPutsItBackAsItWas() async throws {
        let w = try world()
        let snapshot = ExamSnapshot(w.exam)
        let before = w.app.readinessValue(of: snapshot)
        let writing = await w.app.writeRung(for: w.parent.id)
        guard case .proposal(let id) = writing else { return XCTFail("\(writing)") }
        w.app.adoptRung(id)
        w.app.undoRung(id)
        let rung = try XCTUnwrap(w.app.item(id))
        XCTAssertEqual(rung.status, .draft)
        XCTAssertEqual(rung.memory, .new)
        XCTAssertEqual(w.parent.status, .active)
        XCTAssertEqual(w.app.readinessValue(of: snapshot), before, accuracy: 0.0001)
    }

    func testDeletingAnAddedOneWakesTheEasyOne() async throws {
        let w = try world()
        let writing = await w.app.writeRung(for: w.parent.id)
        guard case .proposal(let id) = writing else { return XCTFail("\(writing)") }
        w.app.adoptRung(id)
        XCTAssertEqual(w.parent.status, .suspended)
        w.app.deleteItems([id])
        XCTAssertEqual(w.parent.status, .active)
    }

    func testDeletingAnUnrelatedQuestionWakesNothing() async throws {
        let w = try world()
        w.app.suspend(w.parent)
        let other = try XCTUnwrap(w.course.liveItems.first { $0.id != w.parent.id })
        w.app.deleteItems([other.id])
        XCTAssertEqual(w.parent.status, .suspended)
    }

    func testNotThisOneDropsTheDraftAndWaitsAMonth() async throws {
        let w = try world()
        var day = w.app.now
        w.app.clock = { day }
        let writing = await w.app.writeRung(for: w.parent.id)
        guard case .proposal(let id) = writing else { return XCTFail("\(writing)") }
        w.app.declineRung(id)
        XCTAssertNotNil(w.app.item(id)?.deletedAt)
        XCTAssertEqual(w.parent.status, .active)
        XCTAssertTrue(w.app.ladderOffers().isEmpty)
        day = day.addingTimeInterval(31 * 86_400)
        XCTAssertEqual(w.app.ladderOffers().map(\.itemID), [w.parent.id], "offered again after the month")
    }

    func testAWriterWithNothingToSayOrAnOfflinePhoneSaysSo() async throws {
        let w = try world()
        w.relay.onGenerate = { _, _ in throw RelayError.upstream("no items") }
        let nothing = await w.app.writeRung(for: w.parent.id)
        XCTAssertEqual(nothing, .failed("Cap couldn't write a harder one from these lines."))
        w.relay.onGenerate = { _, _ in throw RelayError.offline }
        let offline = await w.app.writeRung(for: w.parent.id)
        XCTAssertEqual(offline, .failed("Cap needs a connection for this. It can wait."))
        w.relay.onGenerate = { _, _ in throw RelayError.quotaExceeded(nil, message: "That's today's 3 free drafts.") }
        let limit = await w.app.writeRung(for: w.parent.id)
        XCTAssertEqual(limit, .failed("That's today's 3 free drafts."))
        XCTAssertNil(w.app.rungDraft(of: w.parent.id), "nothing left behind")
    }

    func testACheckThatDoesNotBackItLeavesNothing() async throws {
        let w = try world()
        w.relay.onCheck = { request, _ in
            CheckResponse(model: "scripted", verdicts: request.items.map { CheckVerdict(id: $0.id, verdict: .unsupported, reason: "Not on the page.") })
        }
        let writing = await w.app.writeRung(for: w.parent.id)
        XCTAssertEqual(writing, .failed("Cap couldn't write a harder one from these lines."))
        XCTAssertNil(w.app.rungDraft(of: w.parent.id))
    }

    func testTheCardsButtonOpensTheSheetAndKeepsTheCardAwayForItsWeek() throws {
        let w = try world()
        XCTAssertNil(w.app.perform(CapNotice.Action(title: "Yes, harder", systemImage: "arrow.up.right", run: .raiseQuestion(itemID: w.parent.id))))
        XCTAssertEqual(w.app.router.sheet, .ladder(parentID: w.parent.id))
        XCTAssertNotNil(w.app.noticeLedger.acted[NoticeEngine.tooEasyID(w.parent.id)])
    }

    func testTheEngineSeesATooEasyQuestion() throws {
        let w = try world()
        let inputs = w.app.noticeInputs()
        XCTAssertEqual(inputs.tooEasy.map(\.itemID), [w.parent.id])
        XCTAssertEqual(inputs.tooEasy.first?.next, .cloze)
    }

    func testTheLinkSyncs() throws {
        let w = try world()
        let rung = StudyItem(course: w.course, kind: .recall, status: .active, origin: .cloud, prompt: "Q", answer: "A", now: w.app.now)
        rung.rungOf = w.parent.id
        let row = SyncRecords.row(rung)
        XCTAssertEqual(row.uuid("rung_of"), w.parent.id)
        let plain = SyncRecords.row(w.parent)
        XCTAssertNil(plain.uuid("rung_of"), "null for almost every question")
        // A row from before the column has no link, and the row is the truth: it clears one.
        var old = row
        old["rung_of"] = nil
        let resolver = SyncResolver(course: { _ in nil }, source: { _ in nil })
        let copy = try XCTUnwrap(SyncRecords.makeItem(row, resolver))
        XCTAssertEqual(copy.rungOf, w.parent.id)
        SyncRecords.fill(copy, from: old, resolver)
        XCTAssertNil(copy.rungOf)
    }
}
