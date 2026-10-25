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
}
