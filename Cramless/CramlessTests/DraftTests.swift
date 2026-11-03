import XCTest
@testable import Cramless

/// `AppModel+Drafts`: a generated set becomes drafts in a course (topics made once, anchors and diagram boxes kept),
/// is approved or thrown away, and can move between courses, including a provisional one made for it.
@MainActor
final class DraftTests: CaptureTestCase {

    /// The sample page's set as the cloud path hands it over: the fixtures with the check applied.
    private func sampleOutcome(origin: ItemOrigin = .cloud) throws -> GenerationOutcome {
        let generated = try XCTUnwrap(SamplePage.generated())
        let (topics, items, verdicts) = SamplePage.checkedItems()
        let dropped = verdicts.compactMap { verdict in
            generated.items.first { $0.id == verdict.id }.map { DroppedItem(item: $0, reason: verdict.reason) }
        }
        return GenerationOutcome(title: generated.title, topics: topics, items: items, dropped: dropped, origin: origin,
                                 model: "mock", checkedBy: origin, note: nil, suggestion: nil, limitReached: nil,
                                 fellBack: false)
    }

    // MARK: Making drafts

    func testTheSampleOutcomeBecomesDraftsWithTheirAnchorsAndBoxes() throws {
        let app = try makeApp()
        let course = makeCourse(app)
        let source = app.createSampleSource(course: course)
        let outcome = try sampleOutcome()

        let drafts = app.makeDrafts(from: outcome, source: source)

        XCTAssertEqual(drafts.count, 15)
        XCTAssertEqual(outcome.items.count, 15, "16 written, one left out by the check")
        XCTAssertEqual(source.status, .drafted)
        XCTAssertTrue(drafts.allSatisfy { $0.status == .draft && $0.course?.id == course.id && $0.origin == .cloud })
        XCTAssertTrue(drafts.allSatisfy { $0.checkedAt != nil }, "every draft passed a check")
        // The review lists them in the generator's order.
        let listed = app.draftItems(sourceID: source.id)
        XCTAssertEqual(listed.map(\.prompt), outcome.items.map(\.prompt))
        for (draft, generated) in zip(listed, outcome.items) {
            XCTAssertEqual(draft.sourceRef?.sourceID, source.id)
            XCTAssertEqual(draft.sourceRef?.anchorIDs, generated.anchors)
            XCTAssertEqual(draft.sourceRef?.pageIndex, 0)
            XCTAssertTrue(draft.sourceRef?.label.hasPrefix("p. 87") == true)
        }
        // The diagram's labels are boxed from the page's own lines.
        let diagram = try XCTUnwrap(listed.first { $0.kind == .diagram }?.diagram)
        XCTAssertEqual(diagram.sourceID, source.id)
        XCTAssertEqual(diagram.targets.map(\.anchorID), ["p0.l8", "p0.l9", "p0.l10", "p0.l11"])
        XCTAssertEqual(diagram.targets.map(\.label), ["Prophase", "Metaphase", "Anaphase", "Telophase"])
        XCTAssertTrue(diagram.targets.allSatisfy { $0.box.w > 0 && $0.box.h > 0 })
        // The fixed answer came through.
        let fixed = try XCTUnwrap(listed.first { $0.prompt.contains("genetically identical daughter cells") })
        XCTAssertTrue(fixed.answer.contains("same number of chromosomes"))
        // What the check left out, and why, is kept for the review.
        let report = try XCTUnwrap(app.draftReport(sourceID: source.id))
        XCTAssertEqual(report.leftOut.map(\.id), ["i8"])
        XCTAssertTrue(report.leftOut[0].reason.contains("never mentions sex cells"))
        XCTAssertEqual(report.origin, .cloud)
        XCTAssertEqual(report.title, "Mitosis")
        XCTAssertEqual(report.topics, ["Phases of mitosis", "Cytokinesis", "Why mitosis matters", "Chromosome number"])
        XCTAssertNil(report.provisionalCourseID)
    }

    func testTopicsAreMadeOnceAndAnExistingTopicIsReused() throws {
        let app = try makeApp()
        let course = makeCourse(app)
        let existing = try XCTUnwrap(ItemFactory.topic(named: "phases of mitosis", in: course, now: app.now))
        app.save()
        let source = app.createSampleSource(course: course)
        let outcome = try sampleOutcome()

        let drafts = app.makeDrafts(from: outcome, source: source)

        let names = course.liveTopics.map { $0.name.lowercased() }
        XCTAssertEqual(names.count, Set(names).count, "no topic twice")
        XCTAssertEqual(Set(names), ["phases of mitosis", "cytokinesis", "why mitosis matters", "chromosome number"])
        let phases = drafts.filter { $0.prompt.contains("anaphase") || $0.prompt.contains("prophase") }
        XCTAssertFalse(phases.isEmpty)
        XCTAssertTrue(phases.allSatisfy { $0.topicID == existing.id }, "the course's own topic is reused")
        XCTAssertFalse(app.draftReport(sourceID: source.id)?.createdTopicIDs.contains(existing.id) ?? true)

        // Writing the set again (with Cloud AI, say) replaces the drafts and makes no new topics.
        let again = app.makeDrafts(from: outcome, source: source)
        XCTAssertEqual(again.count, 15)
        XCTAssertEqual(app.draftItems(sourceID: source.id).count, 15)
        XCTAssertEqual(course.liveTopics.count, 4)
    }

    // MARK: A write-again by a weaker tier

    func testASetNeverReplacesOneFromABetterTier() {
        for (new, old, may) in [(ItemOrigin.cloud, ItemOrigin.cloud, true), (.cloud, .onDevice, true), (.cloud, .rules, true),
                                (.onDevice, .onDevice, true), (.onDevice, .rules, true), (.rules, .rules, true),
                                (.onDevice, .cloud, false), (.rules, .cloud, false), (.rules, .onDevice, false)] {
            XCTAssertEqual(new.mayReplace(old), may, "\(new) over \(old)")
        }
        XCTAssertTrue(ItemOrigin.rules.mayReplace(.person), "what no tier wrote is not a tier's to protect")
    }

    func testTheNoteOnKeptQuestionsSaysWhatIsTrue() {
        typealias Failure = AIRouter.CloudFailure
        XCTAssertEqual(AIRouter.keptNote(nil, limitReached: nil, earlier: .cloud), "Cloud AI couldn't be reached, so your earlier questions are kept.")
        XCTAssertEqual(AIRouter.keptNote(.unreachable, limitReached: nil, earlier: .cloud), "Cloud AI couldn't be reached, so your earlier questions are kept.")
        XCTAssertEqual(AIRouter.keptNote(.gettingReady, limitReached: nil, earlier: .cloud),
                       "Cloud AI is getting ready, so your earlier questions are kept. Try again in a minute.")
        XCTAssertEqual(AIRouter.keptNote(.refused("That's all the cloud AI for today."), limitReached: nil, earlier: .cloud),
                       "That's all the cloud AI for today. Your earlier questions are kept.")
        XCTAssertEqual(AIRouter.keptNote(.nothingUsable, limitReached: nil, earlier: .cloud),
                       "Cloud AI's questions didn't match your page, so your earlier questions are kept.")
        XCTAssertEqual(AIRouter.keptNote(.tooLong, limitReached: nil, earlier: .cloud),
                       "Cloud AI couldn't take a reading this long, so your earlier questions are kept.")
        XCTAssertEqual(AIRouter.keptNote(.unreachable, limitReached: .scans, earlier: .cloud),
                       "You've used this week's free Cloud AI scans, so your earlier questions are kept.")
        XCTAssertEqual(AIRouter.keptNote(nil, limitReached: nil, earlier: .onDevice),
                       "Your iPhone's AI couldn't write them again, so your earlier questions are kept.")
    }

    func testAWeakerSetWrittenAgainLeavesTheQuestionsInReviewAndTheReviewSaysWhy() throws {
        let app = try makeApp()
        let course = makeCourse(app)
        let source = app.createSampleSource(course: course)
        let cloud = try sampleOutcome()
        let written = app.makeDrafts(from: cloud, source: source)
        XCTAssertFalse(app.keepsEarlierDrafts(over: cloud, source: source), "the same tier replaces")

        // Cloud AI couldn't be reached when the set was written again: the rules wrote this one.
        var rules = cloud
        rules.origin = .rules
        rules.checkedBy = .rules
        rules.fellBack = true
        rules.cloudFailure = .unreachable
        XCTAssertTrue(app.keepsEarlierDrafts(over: rules, source: source))
        app.noteEarlierDraftsKept(over: rules, source: source)
        var report = try XCTUnwrap(app.draftReport(sourceID: source.id))
        XCTAssertEqual(report.origin, .cloud, "it is still the cloud's set")
        XCTAssertEqual(report.note, "Cloud AI couldn't be reached, so your earlier questions are kept.")
        XCTAssertNil(report.suggestion)
        XCTAssertEqual(app.draftItems(sourceID: source.id).map(\.id), written.map(\.id), "not one was deleted")

        // The free scans are used up: the same, and the plans are offered (allowing them writes the set again).
        rules.cloudFailure = nil
        rules.limitReached = .scans
        rules.suggestion = .upgrade(.scans, message: "The week's free scans are used up.")
        app.noteEarlierDraftsKept(over: rules, source: source)
        report = try XCTUnwrap(app.draftReport(sourceID: source.id))
        XCTAssertEqual(report.note, "You've used this week's free Cloud AI scans, so your earlier questions are kept.")
        XCTAssertEqual(report.suggestion?.aiSuggestion, .upgrade(.scans, message: "The week's free scans are used up."))

        // Nothing in review to keep: a first set, and drafts that were thrown away.
        let fresh = app.createSampleSource(course: course)
        XCTAssertFalse(app.keepsEarlierDrafts(over: rules, source: fresh))
        app.discardDrafts(sourceID: source.id, keepSource: true)
        XCTAssertFalse(app.keepsEarlierDrafts(over: rules, source: source))
    }

    // MARK: A write-again that read only part of the source

    /// Two typed pages of three lines, `p0.l0…` and `p1.l0…`.
    private func makeTwoPageSource(_ app: AppModel, course: Course) -> Source {
        let source = Source(course: course, kind: .text, title: "Cell notes", status: .ready, now: app.now)
        app.context.insert(source)
        course.sources.append(source)
        for p in 0..<2 {
            let lines = (0..<3).map { TextLine(id: "p\(p).l\($0)", text: "Page \(p + 1) sentence \($0) about the cell cycle and its phases.", box: nil) }
            let page = SourcePage(source: source, pageIndex: p, label: "\(p + 1)", text: lines.map(\.text).joined(separator: "\n"), lines: lines)
            app.context.insert(page)
            source.pages.append(page)
        }
        app.save()
        return source
    }

    private func outcome(_ prompts: [(String, String)], parts: [GenerationPartReport] = [], note: String? = nil) -> GenerationOutcome {
        let items = prompts.enumerated().map { index, entry in
            GeneratedItem(id: "i\(index + 1)", kind: .flashcard, topic: "Cell cycle", prompt: entry.0, answer: "Something about the cell cycle.",
                          anchors: [entry.1])
        }
        return GenerationOutcome(title: "Cell notes", topics: [GeneratedTopic(name: "Cell cycle", summary: "")], items: items, dropped: [],
                                 origin: .cloud, model: "mock", checkedBy: .cloud, note: note, suggestion: nil, limitReached: nil,
                                 fellBack: false, parts: parts)
    }

    private func part(_ number: Int, _ pages: [Int], _ status: GenerationPartReport.Status) -> GenerationPartReport {
        GenerationPartReport(number: number, firstPage: "\(pages.first! + 1)", lastPage: "\(pages.last! + 1)", pageCount: pages.count,
                             pageIndexes: pages, status: status, kept: status == .read ? 2 : 0)
    }

    func testAWriteAgainThatCouldNotReadSomePagesKeepsTheQuestionsAlreadyWrittenForThem() throws {
        let app = try makeApp()
        let course = makeCourse(app)
        let source = makeTwoPageSource(app, course: course)
        // The first set: two questions on each page.
        app.makeDrafts(from: outcome([("A on page 1", "p0.l0"), ("B on page 1", "p0.l1"), ("C on page 2", "p1.l0"), ("D on page 2", "p1.l1")]),
                       source: source, course: course)
        XCTAssertEqual(app.draftItems(sourceID: source.id).count, 4)

        // Written again, but the free scans only reached page 1: the fuller set is not swapped for a smaller one.
        let partial = outcome([("E on page 1", "p0.l0"), ("F on page 1", "p0.l2")],
                              parts: [part(1, [0], .read), part(2, [1], .notStarted)],
                              note: "Cloud AI read page 1. Page 2 is waiting: this week's free scans are used up.")
        app.makeDrafts(from: partial, source: source, course: course)

        let prompts = Set(app.draftItems(sourceID: source.id).map(\.prompt))
        XCTAssertEqual(prompts, ["E on page 1", "F on page 1", "C on page 2", "D on page 2"], "page 1 is rewritten, page 2 keeps its questions")
        let note = try XCTUnwrap(app.draftReport(sourceID: source.id)?.note)
        XCTAssertEqual(note, "Cloud AI read page 1. Page 2 is waiting: this week's free scans are used up. Kept the questions already written for page 2.")
        // The kept ones still point at their lines.
        let kept = app.draftItems(sourceID: source.id).filter { $0.prompt.hasSuffix("page 2") }
        XCTAssertTrue(kept.allSatisfy { $0.sourceRef?.pageIndex == 1 && $0.status == .draft })

        // A part that failed counts the same; a set that read every page replaces everything, as before.
        app.makeDrafts(from: outcome([("G on page 1", "p0.l1")], parts: [part(1, [0], .read), part(2, [1], .failed)]), source: source, course: course)
        XCTAssertEqual(Set(app.draftItems(sourceID: source.id).map(\.prompt)), ["G on page 1", "C on page 2", "D on page 2"])
        app.makeDrafts(from: outcome([("H on page 1", "p0.l0"), ("I on page 2", "p1.l0")], parts: [part(1, [0, 1], .read)]), source: source, course: course)
        XCTAssertEqual(Set(app.draftItems(sourceID: source.id).map(\.prompt)), ["H on page 1", "I on page 2"])
        XCTAssertNil(app.draftReport(sourceID: source.id)?.note, "nothing was kept, so nothing is said")
    }

    func testASetWithNoPartsReplacesTheOldOneAsBefore() throws {
        let app = try makeApp()
        let course = makeCourse(app)
        let source = makeTwoPageSource(app, course: course)
        app.makeDrafts(from: outcome([("A on page 1", "p0.l0"), ("C on page 2", "p1.l0")]), source: source, course: course)
        app.makeDrafts(from: outcome([("Z on page 1", "p0.l1")]), source: source, course: course)
        XCTAssertEqual(app.draftItems(sourceID: source.id).map(\.prompt), ["Z on page 1"])
    }

    // MARK: The formulas card's steps

    func testTheFormulasCardHoldsTheAutomaticRewriteWhileItAsksForWhatItNeedsAndThenReads() {
        var steps = FormulasSteps()
        // Before the card is used, allowing Cloud AI is the offer's business: the set is written again as usual.
        XCTAssertEqual(steps.consentChanged(cloudAllowed: true, photosAllowed: false), .ordinary)
        // The card's button with Cloud AI not allowed: its consent sheet comes first.
        XCTAssertEqual(steps.tapped(cloudAllowed: false, photosAllowed: false), .askCloudAI)
        XCTAssertTrue(steps.started)
        // Cloud AI is allowed from that sheet: not a rewrite from the text that still lacks its formulas (that spent two scans, and the
        // read then a third); the photos are the next step.
        XCTAssertEqual(steps.consentChanged(cloudAllowed: true, photosAllowed: false), .hold)
        // The photos are allowed: the read goes ahead, once.
        XCTAssertEqual(steps.consentChanged(cloudAllowed: true, photosAllowed: true), .read)
        steps.readStarted()
        XCTAssertTrue(steps.reading, "the Add button waits")
        XCTAssertEqual(steps.consentChanged(cloudAllowed: true, photosAllowed: true), .hold, "never a second read")
        steps.readEnded(continuing: false)
        XCTAssertFalse(steps.reading)
        XCTAssertFalse(steps.started)
        XCTAssertEqual(steps.consentChanged(cloudAllowed: true, photosAllowed: true), .ordinary)

        // Everything already allowed: the button reads at once.
        var ready = FormulasSteps()
        XCTAssertEqual(ready.tapped(cloudAllowed: true, photosAllowed: true), .read)
        var photos = FormulasSteps()
        XCTAssertEqual(photos.tapped(cloudAllowed: true, photosAllowed: false), .askPhotos)
    }

    func testTheFormulasCardsStepsEndWhenASheetIsClosedWithoutAllowingAndWhenARefusedReadAsksAgain() {
        var closed = FormulasSteps()
        _ = closed.tapped(cloudAllowed: false, photosAllowed: false)
        closed.sheetClosed(cloudAllowed: false, photosAllowed: false)
        XCTAssertFalse(closed.started, "the sheet was dismissed: the card's steps are over")
        XCTAssertEqual(closed.consentChanged(cloudAllowed: true, photosAllowed: false), .ordinary, "allowing Cloud AI from the offer later rewrites as usual")

        // A sheet closed after both were allowed leaves the steps to the read that the change started.
        var allowed = FormulasSteps()
        _ = allowed.tapped(cloudAllowed: false, photosAllowed: false)
        allowed.sheetClosed(cloudAllowed: true, photosAllowed: true)
        XCTAssertTrue(allowed.started)

        // A read that found something missing presents what is missing and goes on when it is allowed.
        var again = FormulasSteps()
        _ = again.tapped(cloudAllowed: true, photosAllowed: true)
        again.readStarted()
        again.readEnded(continuing: true)
        XCTAssertTrue(again.started)
        XCTAssertFalse(again.reading)
        XCTAssertEqual(again.consentChanged(cloudAllowed: true, photosAllowed: true), .read)

        // While a read runs, a sheet closing changes nothing.
        var running = FormulasSteps()
        _ = running.tapped(cloudAllowed: true, photosAllowed: true)
        running.readStarted()
        running.sheetClosed(cloudAllowed: false, photosAllowed: false)
        XCTAssertTrue(running.started)
        XCTAssertTrue(running.reading)
    }

    // MARK: Deciding

    func testApprovingKeepsTheTickedAndRejectsTheRest() throws {
        let app = try makeApp()
        let course = makeCourse(app)
        let source = app.createSampleSource(course: course)
        let drafts = app.makeDrafts(from: try sampleOutcome(), source: source)
        let kept = Set(drafts.prefix(11).map(\.id))

        let added = app.approveDrafts(sourceID: source.id, keeping: kept)

        XCTAssertEqual(added, 11)
        XCTAssertEqual(drafts.filter { $0.status == .active }.count, 11)
        XCTAssertEqual(drafts.filter { $0.status == .rejected }.count, 4)
        XCTAssertTrue(drafts.filter { kept.contains($0.id) }.allSatisfy { $0.status == .active })
        XCTAssertEqual(source.status, .ready)
        XCTAssertTrue(app.draftItems(sourceID: source.id).isEmpty)
        XCTAssertNil(app.draftReport(sourceID: source.id), "the report goes once the set is decided")
        XCTAssertEqual(Set(course.activeItems.map(\.id)), kept)
        XCTAssertEqual(app.items(fromSource: source.id).count, 11)
    }

    func testThrowingASetAwayLeavesNothingBehind() throws {
        let app = try makeApp()
        let course = makeCourse(app)
        let source = app.createSampleSource(course: course)
        let sourceID = source.id
        app.makeDrafts(from: try sampleOutcome(), source: source)
        XCTAssertEqual(course.liveTopics.count, 4)

        app.discardDrafts(sourceID: sourceID)

        XCTAssertNil(app.source(sourceID))
        XCTAssertTrue(app.draftItems(sourceID: sourceID).isEmpty)
        XCTAssertTrue(course.liveItems.isEmpty)
        XCTAssertTrue(course.liveTopics.isEmpty, "topics made for the set go with it")
        XCTAssertEqual(app.courses.map(\.id), [course.id], "a course the person chose stays")
        XCTAssertFalse(FileManager.default.fileExists(atPath: FileStore.url(for: PageImageStore.sourceFolder(sourceID)).path))
    }

    func testKeepingTheSourceButNotTheQuestions() throws {
        let app = try makeApp()
        let course = makeCourse(app)
        let source = app.createSampleSource(course: course)
        app.makeDrafts(from: try sampleOutcome(), source: source)

        app.discardDrafts(sourceID: source.id, keepSource: true)

        XCTAssertNotNil(app.source(source.id))
        XCTAssertEqual(source.status, .read)
        XCTAssertTrue(app.draftItems(sourceID: source.id).isEmpty)
        XCTAssertNil(app.draftReport(sourceID: source.id))
    }

    // MARK: Courses

    func testMovingASetCarriesItsTopicsAndCleansUpBehindIt() throws {
        let app = try makeApp()
        let bio = makeCourse(app, name: "Bio 101")
        let chem = makeCourse(app, name: "Chem 110")
        let source = app.createSampleSource(course: bio)
        let drafts = app.makeDrafts(from: try sampleOutcome(), source: source)

        app.moveDrafts(sourceID: source.id, to: chem)

        XCTAssertEqual(source.course?.id, chem.id)
        XCTAssertTrue(chem.sources.contains { $0.id == source.id })
        XCTAssertFalse(bio.sources.contains { $0.id == source.id })
        XCTAssertTrue(drafts.allSatisfy { $0.course?.id == chem.id })
        XCTAssertTrue(bio.liveItems.isEmpty)
        XCTAssertEqual(Set(chem.liveTopics.map(\.name)), ["Phases of mitosis", "Cytokinesis", "Why mitosis matters", "Chromosome number"])
        let chemTopics = Set(chem.liveTopics.map(\.id))
        XCTAssertTrue(drafts.allSatisfy { $0.topicID.map(chemTopics.contains) ?? false })
        XCTAssertTrue(bio.liveTopics.isEmpty, "topics the set made in Bio 101 hold nothing now")

        // Approving into a course made on the spot.
        let new = app.createCourse(named: "AP Biology")
        XCTAssertEqual(app.createCourse(named: "ap biology").id, new.id, "same name, same course")
        let added = app.approveDrafts(sourceID: source.id, keeping: Set(drafts.map(\.id)), in: new)
        XCTAssertEqual(added, 15)
        XCTAssertEqual(new.activeItems.count, 15)
        XCTAssertTrue(chem.liveItems.isEmpty)
        XCTAssertEqual(new.symbol, "leaf")
    }

    func testWithNoCoursesAProvisionalCourseIsNamedFromThePageAndRenamedByTheClassQuestion() throws {
        let app = try makeApp()
        let source = app.createSampleSource(course: nil)

        app.makeDrafts(from: try sampleOutcome(), source: source)

        let provisional = try XCTUnwrap(source.course)
        XCTAssertEqual(provisional.name, "Biology", "named from the page")
        XCTAssertEqual(app.draftReport(sourceID: source.id)?.provisionalCourseID, provisional.id)
        XCTAssertEqual(app.suggestedCourseNames(sourceID: source.id).first, "Biology")

        let named = try XCTUnwrap(app.assignDrafts(sourceID: source.id, toCourseNamed: "Bio 101"))
        XCTAssertEqual(named.id, provisional.id, "the provisional course is renamed, not replaced")
        XCTAssertEqual(app.courses.map(\.name), ["Bio 101"])

        app.approveDrafts(sourceID: source.id, keeping: Set(app.draftItems(sourceID: source.id).map(\.id)))
        XCTAssertEqual(app.courses.map(\.name), ["Bio 101"])
        XCTAssertEqual(named.activeItems.count, 15)
    }

    func testAProvisionalCourseGoesAwayWhenTheSetGoesElsewhereOrIsThrownAway() throws {
        let app = try makeApp()
        let first = app.createSampleSource(course: nil)
        app.makeDrafts(from: try sampleOutcome(), source: first)
        let provisional = try XCTUnwrap(first.course)
        let chem = app.createCourse(named: "Chem 110")

        app.moveDrafts(sourceID: first.id, to: chem)
        XCTAssertNil(app.course(provisional.id), "nothing else was in it")
        XCTAssertEqual(app.courses.map(\.name), ["Chem 110"])

        app.discardDrafts(sourceID: first.id)
        XCTAssertEqual(app.courses.map(\.name), ["Chem 110"], "a course the person made stays")

        // A provisional course whose set is thrown away goes too. (With Chem 110 there, a new set would go to it, so
        // start from an empty library again.)
        let empty = try makeApp()
        let second = empty.createSampleSource(course: nil)
        empty.makeDrafts(from: try sampleOutcome(), source: second)
        XCTAssertEqual(empty.courses.count, 1)
        empty.discardDrafts(sourceID: second.id)
        XCTAssertTrue(empty.courses.isEmpty)
    }

    func testSuggestedClassNamesFollowThePageAndTheLevel() throws {
        let app = try makeApp()
        app.settings.level = .college
        let source = app.createSampleSource(course: nil)
        XCTAssertEqual(Array(app.suggestedCourseNames(for: source, title: "Mitosis", topics: []).prefix(2)), ["Biology", "Bio 101"])
        app.settings.level = .highSchool
        XCTAssertEqual(Array(app.suggestedCourseNames(for: source, title: "Mitosis", topics: []).prefix(2)), ["Biology", "AP Biology"])
        XCTAssertEqual(CourseGuess.subjects(in: ["Moles and molar mass", "Balance the reaction"], headline: ["Stoichiometry"]).first,
                       "Chemistry")
        XCTAssertEqual(CourseGuess.subjects(in: ["The weather was lovely"]), [], "no guess without a reason")
    }

    // MARK: Editing

    func testEditingADraftKeepsItsFormatWhole() throws {
        let app = try makeApp()
        let course = makeCourse(app)
        let source = app.createSampleSource(course: course)
        let drafts = app.makeDrafts(from: try sampleOutcome(), source: source)

        let recall = try XCTUnwrap(drafts.first { $0.kind == .recall })
        app.updateDraft(recall.id, prompt: "  Why do cells divide?  ", answer: "To grow and repair.")
        XCTAssertEqual(recall.prompt, "Why do cells divide?")
        XCTAssertEqual(recall.answer, "To grow and repair.")

        let mcq = try XCTUnwrap(drafts.first { $0.kind == .mcq && $0.choices.count == 4 })
        var choices = mcq.choices
        let wrong = try XCTUnwrap(choices.firstIndex { !$0.correct })
        for i in choices.indices { choices[i].correct = i == wrong }
        app.updateDraft(mcq.id, prompt: mcq.prompt, answer: "", choices: choices)
        XCTAssertEqual(mcq.choices.filter(\.correct).count, 1)
        XCTAssertEqual(mcq.answer, choices[wrong].text, "the answer follows the right option")

        // Two right options is no multiple choice: nothing changes.
        var broken = mcq.choices
        for i in broken.indices { broken[i].correct = true }
        app.updateDraft(mcq.id, prompt: mcq.prompt, answer: "", choices: broken)
        XCTAssertEqual(mcq.choices.filter(\.correct).count, 1)

        let cloze = try XCTUnwrap(drafts.first { $0.kind == .cloze })
        app.updateDraft(cloze.id, prompt: cloze.prompt, answer: "", clozeText: "In {{metaphase}}, chromosomes line up.")
        XCTAssertEqual(cloze.cloze?.answers, ["metaphase"])
        XCTAssertEqual(cloze.answer, "metaphase")
    }

    // MARK: Lectures

    func testLectureNotesAreSavedAndItsQuestionsBecomeDraftsAtTheirMoments() throws {
        let app = try makeApp()
        let course = makeCourse(app)
        let lecture = app.startLecture(courseID: course.id, title: "Lecture 7")
        app.finishLecture(lecture.id, audioFile: nil, duration: 1100, segments: AITestSupport.lectureSegments, flags: [])
        let response = try RelayFixtures.load(LectureResponse.self, "lecture")
        let outcome = LectureOutcome(title: response.title,
                                     notes: LectureNotes(summary: response.summary, sections: response.sections,
                                                         keyTerms: response.keyTerms, origin: ItemOrigin.cloud.rawValue),
                                     examFlags: response.examFlags, items: response.items, dropped: [], origin: .cloud,
                                     model: response.model)

        let drafts = app.saveLectureNotes(outcome, lecture: lecture)

        XCTAssertEqual(lecture.notes?.sections.count, 4)
        XCTAssertEqual(lecture.title, "Lecture 7: Cell division")
        XCTAssertEqual(lecture.status, .drafted)
        XCTAssertEqual(drafts.count, 3)
        let anaphase = try XCTUnwrap(drafts.first { $0.sourceRef?.anchorIDs == ["s5"] })
        XCTAssertEqual(anaphase.sourceRef?.start, 725)
        XCTAssertEqual(anaphase.sourceRef?.label, "Lecture 7 · 12:05")
        XCTAssertNil(anaphase.sourceRef?.pageIndex)
        XCTAssertEqual(app.draftReport(sourceID: lecture.id)?.checkedBy, .rules, "checked on this iPhone against the transcript")
    }

    func testOfflineLectureNotesThatAreNotWorthKeepingAreNotSaved() throws {
        let app = try makeApp()
        let course = makeCourse(app)
        let lecture = app.startLecture(courseID: course.id, title: "Lecture 9")
        app.finishLecture(lecture.id, audioFile: nil, duration: 700, segments: AITestSupport.lectureSegments, flags: [])
        let outcome = LectureOutcome(title: "Lecture 9", notes: LectureNotes(summary: "", sections: [], origin: ItemOrigin.rules.rawValue),
                                     examFlags: [], items: [], dropped: [], origin: .rules, model: "rules",
                                     note: "The offline rules can't make good notes from this lecture. Cloud AI can.",
                                     suggestion: .allowCloud(feature: AIJob.lecture.feature), needsCloud: true)

        let drafts = app.saveLectureNotes(outcome, lecture: lecture)

        XCTAssertTrue(drafts.isEmpty)
        XCTAssertNil(lecture.notes, "no empty notes: the lecture still says it has none, and Cloud AI can make them")
        XCTAssertNotEqual(lecture.status, .ready)
        // The same lecture with good notes saves them as before.
        let good = LectureOutcome(title: "Lecture 9", notes: LectureNotes(summary: "S", sections: [], origin: ItemOrigin.cloud.rawValue),
                                  examFlags: [], items: [], dropped: [], origin: .cloud, model: "mock")
        _ = app.saveLectureNotes(good, lecture: lecture)
        XCTAssertEqual(lecture.notes?.summary, "S")
    }

    func testTheQuestionCountScalesWithTheSourceLength() throws {
        let app = try makeApp()
        func input(words: Int) throws -> GenerationInput {
            let body = (0..<(words / 10)).map { "Paragraph \($0) sentence has exactly ten words in it ok." }.joined(separator: "\n\n")
            return app.generationInput(for: try app.createSource(fromText: body, title: "Reading", course: nil))
        }
        XCTAssertEqual(try input(words: 300).maxItems, 8, "at least 8")
        XCTAssertEqual(try input(words: 1_500).maxItems, 10)
        XCTAssertEqual(try input(words: 3_000).maxItems, 20)
        XCTAssertEqual(try input(words: 9_000).maxItems, 24, "at most 24 on the free plan")
        // A caller that wants another size says so.
        let source = try app.createSource(fromText: "Mitosis makes two cells. Meiosis makes four.", title: "Short", course: nil)
        XCTAssertEqual(app.generationInput(for: source, maxItems: 5).maxItems, 5)
        XCTAssertEqual(app.lectureInput(for: source).maxItems, 10)
    }
}
