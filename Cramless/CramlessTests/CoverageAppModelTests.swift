import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// Coverage as the app reads it from the store: which sources and questions count, the exam's share (and the stretch an exam on some
/// topics draws on), what the projected grade knows that the ring doesn't and keeps when the exam starts, and "Add questions for the
/// rest" end to end (a new draft set from the part decided when the person asked, written again from the same part after Cloud AI is
/// allowed, moving on at each tap, and the source it adds to is never thrown away).
@MainActor
final class CoverageAppModelTests: CaptureTestCase {

    private func makeFlowApp(mode: AppConfig.AIMode = .local) -> AppModel {
        let defaults = UserDefaults(suiteName: "coverage-app-tests-\(UUID().uuidString)")!
        let config = AppConfig(supabaseURL: nil, supabaseAnonKey: nil, aiMode: mode, isHarness: false, inMemoryStore: true,
                               seedDemoData: false, environment: ["XCTestConfigurationFilePath": "coverage-app-tests"])
        let app = AppModel(config: config, defaults: defaults)
        app.ai.mockLatencyScale = 0
        app.ai.streamPause = .zero
        app.ai.probe = FixedOnDeviceProbe(.unavailable(.notChecked))
        return app
    }

    /// A source of typed pages in `course`.
    @discardableResult
    private func addSource(_ app: AppModel, to course: Course, title: String, words: Int, status: SourceStatus = .ready) -> Source {
        let source = Source(course: course, kind: .text, title: title, status: status, now: app.now)
        app.context.insert(source)
        course.sources.append(source)
        for page in TextPaginator.pages(from: CoverageTests.opinion(words: words)) {
            let model = SourcePage(source: source, pageIndex: page.pageIndex, label: page.label,
                                   text: page.lines.map(\.text).joined(separator: "\n"), lines: page.lines)
            app.context.insert(model)
            source.pages.append(model)
        }
        app.save()
        return source
    }

    private func sections(_ app: AppModel, _ source: Source) -> [Coverage.Section] {
        Coverage.sections(of: app.coverageReading(of: source))
    }

    @discardableResult
    private func addQuestion(_ app: AppModel, in course: Course, from source: Source, anchors: [String], status: ItemStatus = .active,
                             topic: Topic? = nil) -> StudyItem {
        let ref = SourceRef(sourceID: source.id, pageIndex: 0, anchorIDs: anchors, label: "p. 1")
        let item = StudyItem(course: course, topicID: topic?.id, kind: .flashcard, status: status, origin: .person,
                             prompt: "Question \(UUID().uuidString.prefix(6))", answer: "Answer", sourceRef: ref, now: app.now)
        app.context.insert(item)
        course.items.append(item)
        app.save()
        return item
    }

    private func addExam(_ app: AppModel, in course: Course, scope: [UUID] = []) -> Exam {
        let exam = Exam(course: course, title: "Midterm", date: app.now.addingTimeInterval(14 * 86_400), scope: scope, now: app.now)
        app.context.insert(exam)
        course.exams.append(exam)
        app.save()
        return exam
    }

    // MARK: What counts

    func testASourcesShareComesFromItsActiveQuestionsOnly() throws {
        let app = makeFlowApp()
        let course = makeCourse(app)
        let source = addSource(app, to: course, title: "Palsgraf", words: 3000)
        let all = sections(app, source)
        XCTAssertEqual(try XCTUnwrap(app.coverage(of: source)).share, 0, "no questions yet")

        let active = addQuestion(app, in: course, from: source, anchors: [all[0].anchorIDs[0]])
        addQuestion(app, in: course, from: source, anchors: [all[1].anchorIDs[0]], status: .draft)
        addQuestion(app, in: course, from: source, anchors: [all[2].anchorIDs[0]], status: .suspended)
        addQuestion(app, in: course, from: source, anchors: [all[3].anchorIDs[0]], status: .rejected)
        let one = try XCTUnwrap(app.coverage(of: source))
        XCTAssertEqual(one.coveredWords, all[0].words, "a draft, a paused or a rejected question reaches nothing")
        XCTAssertEqual(one.uncovered.count, one.sections - 1)

        // A deleted question reaches nothing either.
        active.deletedAt = app.now
        app.save()
        XCTAssertEqual(try XCTUnwrap(app.coverage(of: source)).coveredWords, 0)
    }

    func testASourceWaitingForReviewAndADeckAreLeftOut() throws {
        let app = makeFlowApp()
        let course = makeCourse(app)
        let reading = addSource(app, to: course, title: "Reading", words: 1500, status: .drafted)
        XCTAssertNil(app.coverage(of: reading), "its questions are drafts waiting for review")
        reading.status = .ready
        XCTAssertNotNil(app.coverage(of: reading))

        let deck = Source(course: course, kind: .anki, title: "Classmate deck (21 cards)", status: .ready, now: app.now)
        app.context.insert(deck)
        course.sources.append(deck)
        app.save()
        XCTAssertNil(app.coverage(of: deck), "a deck has no text to cover")
        let summary = try XCTUnwrap(app.coverage(for: addExam(app, in: course)))
        XCTAssertEqual(summary.sources.map(\.title), ["Reading"])
    }

    func testAnExamCountsTheCoursesSourcesOrOnlyThoseWithQuestionsOnItsTopics() throws {
        let app = makeFlowApp()
        let course = makeCourse(app)
        let torts = try XCTUnwrap(ItemFactory.topic(named: "Torts", in: course, now: app.now))
        let contracts = try XCTUnwrap(ItemFactory.topic(named: "Contracts", in: course, now: app.now))
        let palsgraf = addSource(app, to: course, title: "Palsgraf", words: 2400)
        let hadley = addSource(app, to: course, title: "Hadley v. Baxendale", words: 1200)
        let first = sections(app, palsgraf)
        let second = sections(app, hadley)
        addQuestion(app, in: course, from: palsgraf, anchors: [first[0].anchorIDs[0]], topic: torts)
        addQuestion(app, in: course, from: hadley, anchors: [second[0].anchorIDs[0], second[1].anchorIDs[0]], topic: contracts)

        let whole = try XCTUnwrap(app.coverage(for: addExam(app, in: course)))
        XCTAssertEqual(Set(whole.sources.map(\.title)), ["Palsgraf", "Hadley v. Baxendale"])
        XCTAssertEqual(whole.share, Double(whole.coveredWords) / Double(whole.words), accuracy: 1e-9)
        XCTAssertEqual(whole.mainGap?.title, "Palsgraf", "most of what is left is in the long one")

        // An exam on contracts only is about the reading that has questions on them.
        let scoped = try XCTUnwrap(app.coverage(for: addExam(app, in: course, scope: [contracts.id])))
        XCTAssertEqual(scoped.sources.map(\.title), ["Hadley v. Baxendale"])
        XCTAssertGreaterThan(scoped.share, whole.share)
        XCTAssertNil(scoped.mainGap, "one source on its own is the whole story")
        // The exam's target for "the rest" is a reading, the one with the most left.
        XCTAssertEqual(app.restTarget(in: whole)?.title, "Palsgraf")
    }

    func testALectureIsNotCountedItsNotesAreASummaryNotAReading() throws {
        let app = makeFlowApp()
        let course = makeCourse(app)
        let reading = addSource(app, to: course, title: "Reading", words: 1500)
        let lecture = Source(course: course, kind: .lecture, title: "Lecture 7", status: .ready, now: app.now)
        lecture.segments = (0..<20).map { i in
            TranscriptSegment(id: "s\(i)", start: Double(i) * 30, end: Double(i) * 30 + 29,
                              text: "Today we go through the reasoning in the case, step \(i), and why the court held as it did on this point.")
        }
        app.context.insert(lecture)
        course.sources.append(lecture)
        app.save()
        let exam = addExam(app, in: course)
        // Ten questions about it, as a lecture gets: by the transcript's windows they would reach a fraction of it, with nothing to add.
        addQuestion(app, in: course, from: lecture, anchors: ["s0"])
        XCTAssertNil(app.coverage(of: lecture), "no coverage line, no amber card, no button for a lecture")
        XCTAssertEqual(try XCTUnwrap(app.coverage(for: exam)).sources.map(\.title), ["Reading"])
        XCTAssertNil(app.restRequest(for: lecture))

        // An exam whose material is only lectures has nothing to measure, and is projected as before.
        let lectureOnly = makeCourse(app, name: "Seminar")
        let notes = Source(course: lectureOnly, kind: .lecture, title: "Lecture 1", status: .ready, now: app.now)
        notes.segments = lecture.segments
        app.context.insert(notes)
        lectureOnly.sources.append(notes)
        app.save()
        XCTAssertNil(app.coverage(for: addExam(app, in: lectureOnly)))
    }

    func testAnExamOnSomeTopicsCountsOnlyTheStretchItsQuestionsAreIn() throws {
        let app = makeFlowApp()
        let course = makeCourse(app)
        let early = try XCTUnwrap(ItemFactory.topic(named: "Chapter 1", in: course, now: app.now))
        let third = try XCTUnwrap(ItemFactory.topic(named: "Chapter 3", in: course, now: app.now))
        let book = addSource(app, to: course, title: "Casebook", words: 9000)
        let all = sections(app, book).filter { $0.words >= Coverage.minimumWords }
        XCTAssertGreaterThan(all.count, 60)
        // Chapter 1 questions near the start, chapter 3 questions between passages 30 and 36.
        for section in all[0...2] { addQuestion(app, in: course, from: book, anchors: [section.anchorIDs[0]], topic: early) }
        for index in [30, 33, 36] { addQuestion(app, in: course, from: book, anchors: [all[index].anchorIDs[0]], topic: third) }

        let whole = try XCTUnwrap(app.coverage(for: addExam(app, in: course)))
        let exam = addExam(app, in: course, scope: [third.id])
        let scoped = try XCTUnwrap(app.coverage(for: exam))
        XCTAssertEqual(scoped.sources.map(\.title), ["Casebook"])
        XCTAssertEqual(scoped.sources.first?.sections, 7, "from passage 30 to passage 36")
        XCTAssertGreaterThan(scoped.share, 0.4)
        XCTAssertLessThan(whole.share, 0.15, "the same questions over the whole casebook")

        // "The rest" for the chapter 3 exam is from those passages, not the first pages of the book.
        let request = try XCTUnwrap(app.restRequest(for: exam))
        let plan = try XCTUnwrap(request.rest)
        let wanted = Set(all[30...36].flatMap(\.anchorIDs))
        XCTAssertTrue(plan.anchorIDs.isSubset(of: wanted), "nothing from chapter 1")
        XCTAssertTrue(plan.anchorIDs.contains(all[31].anchorIDs[0]), "the passages between its questions")
        XCTAssertFalse(plan.anchorIDs.contains(all[30].anchorIDs[0]), "a passage that has a question is not sent")
        XCTAssertEqual(plan.sections, 4)
        // The same book for an exam on the whole course starts at the beginning.
        let courseWide = try XCTUnwrap(app.restRequest(for: addExam(app, in: course))?.rest)
        XCTAssertTrue(courseWide.pages.contains(0) || courseWide.pages.contains(1))
        XCTAssertFalse(courseWide.anchorIDs.isSubset(of: wanted))
    }

    // MARK: The projected grade

    func testTheProjectedGradeKnowsWhatTheRingDoesNot() throws {
        let app = makeFlowApp()
        let course = makeCourse(app)
        let source = addSource(app, to: course, title: "Palsgraf", words: 5800)
        let all = sections(app, source)
        // Sixteen well-remembered questions on the first eight passages.
        let studied = MemoryState(state: .review, stability: 90, difficulty: 3, due: app.now.addingTimeInterval(80 * 86_400),
                                  lastReview: app.now.addingTimeInterval(-86_400), reps: 6)
        for section in all.prefix(8) {
            for id in section.anchorIDs.prefix(2) {
                addQuestion(app, in: course, from: source, anchors: [id]).memory = studied
            }
        }
        app.save()
        let exam = addExam(app, in: course)
        let r = app.readiness(for: exam)
        XCTAssertGreaterThan(r.value, 0.9, "the ring is how well the questions are remembered")
        let coverage = try XCTUnwrap(r.coverage)
        XCTAssertEqual(coverage, 0.17, accuracy: 0.02)
        XCTAssertEqual(coverage, try XCTUnwrap(app.coverage(for: exam)).share)
        XCTAssertEqual(r.projectedGrade.letter, "F", "94% on a sixth of the reading is not an A")
        XCTAssertLessThan(r.projectedGrade.percent, 0.6)
        XCTAssertEqual(app.projectedGrade(for: exam), r.projectedGrade)

        // Questions on the rest of the reading bring it back.
        for section in all.dropFirst(8) { addQuestion(app, in: course, from: source, anchors: [section.anchorIDs[0]]).memory = studied }
        app.save()
        let full = app.readiness(for: exam)
        XCTAssertEqual(full.coverage ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(full.projectedGrade, GradeModel.uncalibrated(for: exam.format).grade(full.projected), "full coverage is unchanged")
    }

    func testAnExamWithNothingToMeasureIsProjectedAsBefore() throws {
        let app = makeFlowApp()
        let course = makeCourse(app)
        let exam = addExam(app, in: course)
        let r = app.readiness(for: exam)
        XCTAssertNil(r.coverage)
        XCTAssertEqual(r.projectedGrade, GradeModel.uncalibrated(for: exam.format).grade(r.projected))
    }

    // MARK: The rest

    func testTheRestIsPagesOfJustTheLinesNoQuestionReaches() throws {
        let app = makeFlowApp()
        let course = makeCourse(app)
        let source = addSource(app, to: course, title: "Palsgraf", words: 3000)
        let all = sections(app, source)
        addQuestion(app, in: course, from: source, anchors: [all[0].anchorIDs[0]])
        addQuestion(app, in: course, from: source, anchors: [all[1].anchorIDs[1]])

        let plan = try XCTUnwrap(app.restRequest(for: source)?.rest)
        let input = try XCTUnwrap(app.generationInput(for: plan, of: source))
        let wanted = Set(try XCTUnwrap(app.coverage(of: source)).uncovered.flatMap(\.anchorIDs))
        let sent = Set(input.pages.flatMap { $0.lines.map(\.id) })
        XCTAssertEqual(sent, wanted, "the lines of the passages nothing asks about, and no others")
        XCTAssertTrue(sent.isDisjoint(with: all[0].anchorIDs + all[1].anchorIDs))
        XCTAssertEqual(input.pages.map(\.index), input.pages.map(\.index).sorted(), "in reading order")
        XCTAssertEqual(input.sourceTitle, "Palsgraf")
        XCTAssertEqual(input.course, course.name)
        XCTAssertTrue((6...24).contains(input.maxItems), "\(input.maxItems)")
        XCTAssertEqual(app.restRequest(for: source)?.restOf, source.id)

        // Everything covered: nothing to ask for, and no button.
        for section in all { addQuestion(app, in: course, from: source, anchors: [section.anchorIDs[0]]) }
        XCTAssertNil(app.restRequest(for: source))
    }

    /// A formulas read of a rest's pages puts lines on them that the plan, decided before, doesn't name.
    func testAFormulasReadOfARestsPagesReachesTheNewQuestions() throws {
        let app = makeFlowApp()
        let course = makeCourse(app)
        let source = addSource(app, to: course, title: "Chain rule", words: 3000)
        let all = sections(app, source)
        addQuestion(app, in: course, from: source, anchors: [all[0].anchorIDs[0]])
        let plan = try XCTUnwrap(app.restRequest(for: source)?.rest)
        let planned = try XCTUnwrap(source.sortedPages.flatMap(\.lines).first { plan.anchorIDs.contains($0.id) })
        let covered = try XCTUnwrap(all[0].anchorIDs.first)
        XCTAssertFalse(plan.anchorIDs.contains(covered))

        // What the read added: a formula after a planned line, and one after a line that already has a question.
        let page = try XCTUnwrap(source.sortedPages.first { $0.lines.contains { $0.id == planned.id } })
        let coveredPage = try XCTUnwrap(source.sortedPages.first { $0.lines.contains { $0.id == covered } })
        func add(_ id: String, after anchor: String, to page: SourcePage) {
            var lines = page.lines
            let at = lines.firstIndex { $0.id == anchor }! + 1
            lines.insert(TextLine(id: id, text: "dz/dx = (dz/dy)(dy/dx)", box: nil), at: at)
            page.lines = lines
        }
        let kept = "p\(page.pageIndex).c0", other = "p\(coveredPage.pageIndex).c1"
        add(kept, after: planned.id, to: page)
        add(other, after: covered, to: coveredPage)
        app.save()

        let input = try XCTUnwrap(app.generationInput(for: plan, of: source))
        let sent = Set(input.pages.flatMap { $0.lines.map(\.id) })
        XCTAssertTrue(sent.contains(kept), "the formula the read put beside a planned line goes with it")
        XCTAssertFalse(sent.contains(other), "one beside a line that already has questions does not")
        XCTAssertTrue(plan.anchorIDs.isSubset(of: sent))
    }

    func testOnlyThePagesOfThePartsThatWereReadAreUsed() throws {
        let app = makeFlowApp()
        let course = makeCourse(app)
        let source = addSource(app, to: course, title: "A long reading", words: 12_000)
        let plan = try XCTUnwrap(app.restRequest(for: source)?.rest)
        XCTAssertGreaterThanOrEqual(plan.pages.count, 6)
        let read = Set(plan.pages.prefix(plan.pages.count / 2))
        app.noteRestRun(plan, readPages: read)
        XCTAssertEqual(app.restPagesUsed(source.id), read, "the pages of the parts that failed or never started are left for the next tap")
        let next = try XCTUnwrap(app.restRequest(for: source)?.rest)
        XCTAssertTrue(Set(next.pages).isDisjoint(with: read), "the next tap begins with the pages that never got a question")
        XCTAssertFalse(next.startsOver)
        // Pages that aren't the plan's don't count, and nil means every page of the plan was read.
        app.noteRestRun(next, readPages: [9_999])
        XCTAssertEqual(app.restPagesUsed(source.id), read)
        app.noteRestRun(next)
        XCTAssertEqual(app.restPagesUsed(source.id), read.union(next.pages))

        // The outcome says which pages its parts read.
        func part(_ n: Int, _ pages: [Int], _ status: GenerationPartReport.Status) -> GenerationPartReport {
            GenerationPartReport(number: n, firstPage: "\(pages[0] + 1)", lastPage: "\(pages[pages.count - 1] + 1)", pageCount: pages.count,
                                 pageIndexes: pages, status: status)
        }
        var outcome = GenerationOutcome(title: "T", topics: [], items: [], dropped: [], origin: .cloud, model: "m", checkedBy: .cloud, note: nil,
                                        suggestion: nil, limitReached: nil, fellBack: false)
        XCTAssertNil(outcome.pagesRead, "this iPhone's model or the rules wrote it: every page it was given counts")
        outcome.parts = [part(1, [0, 1, 2], .read), part(2, [3, 4], .failed), part(3, [5], .notStarted)]
        XCTAssertEqual(outcome.pagesRead, [0, 1, 2])
    }

    /// A paid reading with more than twenty questions is two requests; when the second fails, its pages never got a question.
    func testARestWhoseSecondRequestFailedLeavesItsPagesForTheNextTap() async throws {
        let app = makeFlowApp(mode: .relay)
        app.settings.cloudConsentVersion = AIConsent.currentVersion
        let relay = ScriptedRelay()
        relay.onGenerate = { request, call in
            if call == 2 { throw RelayError.offline }
            return ScriptedRelay.response(for: request, call: call)
        }
        app.ai.transportOverride = relay
        app.ai.setServerQuota(QuotaStatus(plan: .pro, meters: []))   // a scan takes 40 pages, a request asks for at most 20 questions
        let course = makeCourse(app)
        let source = addSource(app, to: course, title: "A long reading", words: 12_000)
        let request = try XCTUnwrap(app.restRequest(for: source))
        let plan = try XCTUnwrap(request.rest)
        XCTAssertGreaterThan(plan.sections, 20, "enough for two requests")

        let run = CaptureRun(app: app, request: request, regenerating: source.id, skipMathGate: true)
        run.pace = 0
        run.start()
        let deadline = Date().addingTimeInterval(30)
        while run.phase == .running, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        guard case .review = run.phase else { return XCTFail("expected the review, got \(run.phase)") }
        XCTAssertEqual(relay.generateRequests.count, 2)
        let firstPart = Set(relay.generateRequests[0].pages.map(\.page))
        let used = app.restPagesUsed(source.id)
        XCTAssertEqual(used, firstPart, "only the pages the first request read")
        XCTAssertLessThan(used.count, plan.pages.count)

        // Once these drafts are decided, the next tap begins with the pages that never got a question.
        app.approveDrafts(sourceID: source.id, keeping: Set(app.draftItems(sourceID: source.id).map(\.id)))
        let next = try XCTUnwrap(app.restRequest(for: source)?.rest)
        XCTAssertTrue(Set(next.pages).isDisjoint(with: used), "\(next.pages) after \(used.sorted())")
    }

    func testAScanTakesNoMorePagesThanThePlanAllows() throws {
        let app = makeFlowApp()
        let course = makeCourse(app)
        let source = addSource(app, to: course, title: "A long reading", words: 12_000)
        XCTAssertGreaterThan(source.pages.count, 12)
        let plan = try XCTUnwrap(app.restRequest(for: source)?.rest)
        let input = try XCTUnwrap(app.generationInput(for: plan, of: source))
        XCTAssertEqual(input.pages.count, AIFreeLimits.pagesPerScan(.free), "the free plan's scan; the rest waits for the next tap")
        XCTAssertEqual(AIFreeLimits.pagesPerScan(.pro), 40)
        XCTAssertEqual(input.pages.map(\.index), Array(source.sortedPages.prefix(10).map(\.pageIndex)))
    }

    /// A passage whose draft was left out in review stays uncovered, and used to be sent first at every tap, each one a scan of the week.
    func testTheNextRestMovesOnToOtherPagesAndComesRoundAgainAfterTheLast() throws {
        let app = makeFlowApp()
        let course = makeCourse(app)
        let source = addSource(app, to: course, title: "A long reading", words: 15_000)
        var seen: [[Int]] = []
        var wrapped = false
        for _ in 0..<6 {
            let plan = try XCTUnwrap(app.restRequest(for: source)?.rest)
            if plan.startsOver { wrapped = true }
            seen.append(plan.pages)
            // The run that wrote these drafts, whatever the person then kept: the pages are used.
            app.noteRestRun(plan)
            if wrapped { break }
        }
        XCTAssertTrue(wrapped, "after every page has been through a run the round begins again")
        XCTAssertEqual(seen.first?.count, 10)
        XCTAssertTrue(Set(seen[0]).isDisjoint(with: seen[1]), "the second tap is not the first one again: \(seen)")
        XCTAssertEqual(seen.last, seen.first, "and it begins at the start")
        XCTAssertEqual(app.restPagesUsed(source.id), Set(seen.last ?? []), "a round that starts again forgets the one before")

        // It is a small record of this iPhone, keyed by source: another source is its own round, and it outlasts the app model.
        let other = addSource(app, to: course, title: "Another", words: 3000)
        XCTAssertTrue(app.restPagesUsed(other.id).isEmpty)
        let again = AppModel(config: app.config, container: try Persistence.makeContainer(inMemory: true), defaults: app.defaults)
        XCTAssertEqual(again.restPagesUsed(source.id), app.restPagesUsed(source.id))
    }

    func testAddingQuestionsForTheRestWritesDraftsFromThoseLinesAndKeepsTheSource() async throws {
        let app = makeFlowApp()
        let course = makeCourse(app)
        // The sample page, as a source whose first passage already has a question.
        let source = Source(course: course, kind: .sample, title: "Biology textbook", status: .ready, now: app.now)
        app.context.insert(source)
        course.sources.append(source)
        let lines = AITestSupport.sampleLines
        let page = SourcePage(source: source, pageIndex: 0, label: "87", text: lines.map(\.text).joined(separator: "\n"), lines: lines)
        app.context.insert(page)
        source.pages.append(page)
        app.save()
        let counted = Coverage.sections(of: app.coverageReading(of: source)).filter { $0.words >= Coverage.minimumWords }
        let existing = addQuestion(app, in: course, from: source, anchors: [counted[0].anchorIDs[0]])
        let before = try XCTUnwrap(app.coverage(of: source))
        let wanted = Set(before.uncovered.flatMap(\.anchorIDs))
        XCTAssertFalse(wanted.isEmpty)

        let request = try XCTUnwrap(app.restRequest(for: source))
        let run = CaptureRun(app: app, request: request, regenerating: source.id, skipMathGate: true)
        run.pace = 0
        run.start()
        let deadline = Date().addingTimeInterval(20)
        while run.phase == .running, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        guard case .review(let id) = run.phase else { return XCTFail("expected the review, got \(run.phase)") }
        XCTAssertEqual(id, source.id, "a new draft set for the same source")

        let drafts = app.draftItems(sourceID: source.id)
        XCTAssertFalse(drafts.isEmpty)
        for draft in drafts {
            XCTAssertTrue(Set(draft.sourceRef?.anchorIDs ?? []).isSubset(of: wanted), "\(draft.prompt) is from a passage already asked about")
        }
        XCTAssertEqual(existing.status, .active, "the question that was there stays")
        XCTAssertNil(app.coverage(of: source), "while its drafts wait for review it isn't counted")
        XCTAssertEqual(app.restPagesUsed(source.id), Set(try XCTUnwrap(request.rest).pages), "its pages are used now")

        // Leaving the flow throws the drafts away, not the reading or the questions it already had.
        run.discard()
        XCTAssertNotNil(app.source(source.id))
        XCTAssertEqual(source.status, .ready)
        XCTAssertTrue(app.draftItems(sourceID: source.id).isEmpty)
        XCTAssertEqual(existing.status, .active)
        XCTAssertEqual(try XCTUnwrap(app.coverage(of: source)).share, before.share, accuracy: 1e-9)

        // Approving the drafts raises the share. (The pages were all used, so the new request begins the round again.)
        let again = CaptureRun(app: app, request: try XCTUnwrap(app.restRequest(for: source)), regenerating: source.id, skipMathGate: true)
        again.pace = 0
        again.start()
        let second = Date().addingTimeInterval(20)
        while again.phase == .running, Date() < second { try await Task.sleep(for: .milliseconds(10)) }
        guard case .review = again.phase else { return XCTFail("expected the review, got \(again.phase)") }
        let kept = Set(app.draftItems(sourceID: source.id).map(\.id))
        XCTAssertEqual(app.approveDrafts(sourceID: source.id, keeping: kept), kept.count)
        XCTAssertGreaterThan(try XCTUnwrap(app.coverage(of: source)).share, before.share + 0.3)
    }

    /// Cloud AI off, "Add questions for the rest", the offline rules write the drafts, the review offers to allow Cloud AI, and the set is
    /// written again. The source is waiting on those drafts then, which keeps it out of the coverage count the rest was worked out from:
    /// the rewrite used to ask for it again, find nothing, and say everything was covered. It is worked out once, when the person asks.
    func testARestSetWrittenOfflineCanBeWrittenAgainAfterCloudAIIsAllowed() async throws {
        let app = makeFlowApp(mode: .local)
        let course = makeCourse(app)
        let source = Source(course: course, kind: .sample, title: "Biology textbook", status: .ready, now: app.now)
        app.context.insert(source)
        course.sources.append(source)
        let lines = AITestSupport.sampleLines
        let page = SourcePage(source: source, pageIndex: 0, label: "87", text: lines.map(\.text).joined(separator: "\n"), lines: lines)
        app.context.insert(page)
        source.pages.append(page)
        app.save()
        let request = try XCTUnwrap(app.restRequest(for: source))

        func finish(_ run: CaptureRun) async throws -> CaptureRun.Phase {
            run.pace = 0
            run.start()
            let deadline = Date().addingTimeInterval(20)
            while run.phase == .running, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            return run.phase
        }
        let first = CaptureRun(app: app, request: request, regenerating: source.id, skipMathGate: true)
        guard case .review = try await finish(first) else { return XCTFail("expected the review, got \(first.phase)") }
        XCTAssertEqual(first.origin, .rules)
        XCTAssertEqual(source.status, .drafted)
        XCTAssertNil(app.coverage(of: source), "the source is waiting on its drafts, so a rest can't be worked out from it now")
        XCTAssertNil(app.restRequest(for: source))

        // Cloud AI is allowed in the review: the flow writes the set again with the same request.
        app.ai.modeOverride = .mock
        let again = CaptureRun(app: app, request: request, regenerating: source.id, skipMathGate: true)
        let phase = try await finish(again)
        guard case .review(let id) = phase else { return XCTFail("the rewrite should reach the review, not \(phase)") }
        XCTAssertEqual(id, source.id)
        XCTAssertEqual(again.origin, .cloud, "Cloud AI wrote it this time")
        XCTAssertFalse(app.draftItems(sourceID: source.id).isEmpty)
        XCTAssertEqual(source.status, .drafted)
    }

    func testAPlanWhoseLinesAreGoneSaysEverythingIsCoveredAndKeepsTheSource() async throws {
        let app = makeFlowApp()
        let course = makeCourse(app)
        let source = addSource(app, to: course, title: "Short", words: 400)
        let gone = Coverage.Rest(sourceID: source.id, anchorIDs: ["p9.l9"], pages: [9], sections: 1, startsOver: false)
        let run = CaptureRun(app: app, request: .rest(gone, in: course.id), regenerating: source.id, skipMathGate: true)
        run.pace = 0
        run.start()
        let deadline = Date().addingTimeInterval(20)
        while run.phase == .running, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        guard case .failed(.noQuestions(let note)) = run.phase else { return XCTFail("expected a failure, got \(run.phase)") }
        XCTAssertEqual(note, "Your questions already cover everything in this one.")
        XCTAssertTrue(app.restPagesUsed(source.id).isEmpty, "nothing was written, so nothing is used")
        run.discard()
        XCTAssertNotNil(app.source(source.id), "closing the problem screen keeps the reading")
    }

    // MARK: When the exam starts

    /// The projection kept on exam morning is the one the card showed, and calibration is fitted to what was projected from.
    func testTheCoverageIsKeptWhenTheExamStartsAndTheProjectionAfterItIsTheSame() throws {
        let app = makeFlowApp()
        let course = makeCourse(app)
        let source = addSource(app, to: course, title: "Palsgraf", words: 5800)
        let all = sections(app, source)
        let studied = MemoryState(state: .review, stability: 90, difficulty: 3, due: app.now.addingTimeInterval(80 * 86_400),
                                  lastReview: app.now.addingTimeInterval(-86_400), reps: 6)
        for section in all.prefix(8) {
            for id in section.anchorIDs.prefix(2) { addQuestion(app, in: course, from: source, anchors: [id]).memory = studied }
        }
        let exam = Exam(course: course, title: "Midterm", date: app.now.addingTimeInterval(14 * 86_400), now: app.now)
        app.context.insert(exam)
        course.exams.append(exam)
        app.save()
        let morning = app.projectedGrade(for: exam)
        XCTAssertLessThan(morning.percent, 0.6)

        // The exam starts: the next launch keeps the readiness and, with it, how much of the material the questions reached.
        let hourIn = exam.date.addingTimeInterval(3600)
        app.clock = { hourIn }
        app.applyDailyRollover()
        XCTAssertNotNil(exam.readinessAtExam)
        XCTAssertEqual(try XCTUnwrap(exam.coverageAtExam), 0.17, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(exam.coverageAtExam), try XCTUnwrap(app.coverage(for: exam)).share, accuracy: 1e-9)
        XCTAssertEqual(ExamSnapshot(exam).adjustedReadinessAtExam,
                       GradeModel.adjusted(readiness: try XCTUnwrap(exam.readinessAtExam), coverage: exam.coverageAtExam))

        // "Capling projected" after the exam reads the adjusted value: it is no longer the ring's, as it was.
        let after = app.projectedGrade(for: exam)
        let ring = GradeModel.uncalibrated(for: exam.format).grade(try XCTUnwrap(exam.readinessAtExam))
        XCTAssertLessThan(after.percent, 0.6)
        XCTAssertLessThan(after.percent, ring.percent - 0.3, "the ring said \(ring.letter) and the card on exam morning did not")
        XCTAssertEqual(after.percent, morning.percent, accuracy: 0.05, "close to the grade the exam-morning card showed")

        // Moving the exam to the future forgets both.
        var moved = ExamDraft(exam: exam)
        moved.date = app.now.addingTimeInterval(30 * 86_400)
        app.updateExam(exam.id, with: moved)
        XCTAssertNil(exam.readinessAtExam)
        XCTAssertNil(exam.coverageAtExam)
    }

    func testACalibratedLineIsFittedToWhatEachPastExamWasProjectedFrom() throws {
        let app = makeFlowApp()
        let course = makeCourse(app)
        func past(ring: Double, coverage: Double?, got: Double) -> Exam {
            let exam = Exam(course: course, title: "Past", date: app.now.addingTimeInterval(-10 * 86_400), now: app.now)
            exam.readinessAtExam = ring
            exam.coverageAtExam = coverage
            exam.resultScore = got
            app.context.insert(exam)
            course.exams.append(exam)
            return exam
        }
        let a = past(ring: 0.9, coverage: 1.0 / 3, got: 0.55)
        let b = past(ring: 0.8, coverage: 0.5, got: 0.62)
        app.save()
        let next = Exam(course: course, title: "Next", date: app.now.addingTimeInterval(20 * 86_400), now: app.now)
        app.context.insert(next)
        app.save()
        let fitted = app.gradeModel(for: ExamSnapshot(next))
        let expected = GradeModel.make(format: next.format, history: [
            (GradeModel.adjusted(readiness: 0.9, coverage: 1.0 / 3), 0.55), (GradeModel.adjusted(readiness: 0.8, coverage: 0.5), 0.62),
        ])
        XCTAssertTrue(fitted.isCalibrated)
        XCTAssertEqual(fitted.slope, expected.slope, accuracy: 1e-9)
        XCTAssertEqual(fitted.intercept, expected.intercept, accuracy: 1e-9)
        // What a past exam is shown as projected is read the same way.
        XCTAssertEqual(app.projectedGrade(for: a).percent,
                       app.gradeModel(for: ExamSnapshot(a)).grade(0.9, coverage: 1.0 / 3).percent, accuracy: 1e-12)
        _ = b
    }
}
