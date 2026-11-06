import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// The Library, exam and editor mutations in `AppModel+Library.swift`: every change stamps `updatedAt`, deletes are
/// soft, and a deleted course disappears from everything that reads the store.
@MainActor
final class LibraryMutationTests: XCTestCase {
    var cal: Calendar!
    var now: Date!
    var app: AppModel!
    var root: URL!
    var previousLive: AppModel?

    override func setUp() async throws {
        previousLive = AppModel.live
        root = FileManager.default.temporaryDirectory.appending(path: "library-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        FileStore.rootOverride = root
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        cal = c
        now = c.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 18))!
        let defaults = UserDefaults(suiteName: "library-tests-\(UUID().uuidString)")!
        app = AppModel(container: try Persistence.makeContainer(inMemory: true), defaults: defaults)
        app.calendar = c
        let frozen = now!
        app.clock = { frozen }
    }

    override func tearDown() async throws {
        FileStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
        AppModel.live = previousLive
        app = nil
    }

    // MARK: Helpers

    private func day(_ offset: Int, hour: Int = 9) -> Date {
        cal.adding(days: offset, to: cal.startOfDay(for: now)).addingTimeInterval(Double(hour) * 3600)
    }

    @discardableResult
    private func item(in course: Course, topic: Topic? = nil, kind: ItemKind = .flashcard, source: Source? = nil,
                      page: Int? = nil, studied: Bool = false) -> StudyItem {
        let ref = source.map { SourceRef(sourceID: $0.id, pageIndex: page, anchorIDs: ["p0.l1"], label: "p. 1") }
        let item = StudyItem(course: course, topicID: topic?.id, kind: kind, status: .active, origin: .person,
                             prompt: "Question \(UUID().uuidString.prefix(4))", answer: "Answer", sourceRef: ref, now: day(-10))
        if studied {
            item.memory = MemoryState(state: .review, stability: 5, difficulty: 5, due: day(2), lastReview: day(-3), reps: 2,
                                      lapses: 0, step: 0)
        }
        app.context.insert(item)
        course.items.append(item)
        return item
    }

    private func flashcard(_ front: String, _ back: String) -> ItemDraft {
        var draft = ItemDraft.blank(kind: .flashcard)
        draft.prompt = front
        draft.answer = back
        return draft
    }

    // MARK: Courses

    func testCreateCourseTrimsNameAndGoesLast() throws {
        let first = try XCTUnwrap(app.createCourse(name: "  Bio 101 ", color: .mint, symbol: "leaf"))
        let second = try XCTUnwrap(app.createCourse(name: "Chem 110", color: .sun, symbol: "flask"))
        XCTAssertEqual(first.name, "Bio 101")
        XCTAssertEqual(first.color, .mint)
        XCTAssertEqual(first.symbol, "leaf")
        XCTAssertGreaterThan(second.sortOrder, first.sortOrder)
        XCTAssertEqual(app.courses.map(\.name), ["Bio 101", "Chem 110"])
        XCTAssertEqual(first.updatedAt, now)
        XCTAssertNil(app.createCourse(name: "   ", color: .sky, symbol: "book.closed"))
        XCTAssertEqual(app.courses.count, 2)
    }

    func testUpdateCourseKeepsTheNameWhenBlankAndStampsOnlyOnChange() throws {
        let course = try XCTUnwrap(app.createCourse(name: "Bio", color: .sky, symbol: "leaf"))
        let created = course.updatedAt
        app.clock = { self.now.addingTimeInterval(60) }
        app.updateCourse(course.id, name: "Bio", color: .sky, symbol: "leaf")
        XCTAssertEqual(course.updatedAt, created, "nothing changed, nothing stamped")
        app.updateCourse(course.id, name: "  ", color: .rose, symbol: "atom")
        XCTAssertEqual(course.name, "Bio")
        XCTAssertEqual(course.color, .rose)
        XCTAssertEqual(course.symbol, "atom")
        XCTAssertEqual(course.updatedAt, now.addingTimeInterval(60))
    }

    func testDeleteCourseSoftDeletesEverythingInIt() throws {
        let course = try XCTUnwrap(app.createCourse(name: "Bio", color: .sky, symbol: "leaf"))
        let other = try XCTUnwrap(app.createCourse(name: "Chem", color: .sun, symbol: "flask"))
        let topic = try XCTUnwrap(app.addTopic(named: "Cells", to: course.id))
        let source = Source(course: course, kind: .text, title: "Notes", status: .ready, now: day(-5))
        app.context.insert(source)
        course.sources.append(source)
        item(in: course, topic: topic, source: source, page: 0, studied: true)
        item(in: other, studied: true)
        let confusion = Confusion(course: course, name: "A vs B", explanation: "", itemIDs: [], missCount: 2, now: day(-1))
        app.context.insert(confusion)
        course.confusions.append(confusion)
        _ = app.createExam(ExamDraft(title: "Midterm", courseID: course.id, date: day(10)))
        app.save()
        XCTAssertEqual(app.upcomingExams().count, 1)

        app.deleteCourse(course.id)

        XCTAssertEqual(app.courses.map(\.name), ["Chem"])
        XCTAssertNotNil(course.deletedAt)
        XCTAssertTrue(course.exams.allSatisfy { $0.deletedAt != nil })
        XCTAssertTrue(course.topics.allSatisfy { $0.deletedAt != nil })
        XCTAssertTrue(course.items.allSatisfy { $0.deletedAt != nil })
        XCTAssertTrue(course.sources.allSatisfy { $0.deletedAt != nil })
        XCTAssertNotNil(confusion.deletedAt)
        XCTAssertTrue(app.upcomingExams().isEmpty, "Today and the widget must not show a deleted course's exam")
        XCTAssertEqual(app.itemSnapshots().count, 1)
        XCTAssertTrue(app.confusionSnapshots().isEmpty)
        XCTAssertNil(app.topicNames()[topic.id])
    }

    // MARK: Topics

    func testAddTopicReusesAMatchingNameAndRejectsBlank() throws {
        let course = try XCTUnwrap(app.createCourse(name: "Bio", color: .sky, symbol: "leaf"))
        let meiosis = try XCTUnwrap(app.addTopic(named: "Meiosis", to: course.id))
        let again = try XCTUnwrap(app.addTopic(named: " meiosis ", to: course.id))
        XCTAssertEqual(meiosis.id, again.id)
        let mitosis = try XCTUnwrap(app.addTopic(named: "Mitosis", to: course.id))
        XCTAssertGreaterThan(mitosis.sortOrder, meiosis.sortOrder)
        XCTAssertNil(app.addTopic(named: "  ", to: course.id))
        XCTAssertEqual(course.liveTopics.map(\.name), ["Meiosis", "Mitosis"])
        // A topic with no questions is a coverage gap.
        XCTAssertEqual(app.topicMastery(course: course).map(\.value), [nil, nil])
    }

    func testRenameAndDeleteTopicKeepTheQuestionsAndFixExamScopes() throws {
        let course = try XCTUnwrap(app.createCourse(name: "Bio", color: .sky, symbol: "leaf"))
        let cells = try XCTUnwrap(app.addTopic(named: "Cells", to: course.id))
        let genes = try XCTUnwrap(app.addTopic(named: "Genes", to: course.id))
        let question = item(in: course, topic: cells)
        let narrow = try XCTUnwrap(app.createExam(ExamDraft(title: "Quiz", courseID: course.id, date: day(5), wholeCourse: false,
                                                            scope: [cells.id])))
        let both = try XCTUnwrap(app.createExam(ExamDraft(title: "Final", courseID: course.id, date: day(20), wholeCourse: false,
                                                          scope: [cells.id, genes.id])))

        app.renameTopic(cells.id, to: " Cell biology ")
        XCTAssertEqual(cells.name, "Cell biology")

        app.deleteTopic(cells.id)
        XCTAssertNotNil(cells.deletedAt)
        XCTAssertNil(question.topicID)
        XCTAssertNil(question.deletedAt, "deleting a topic never deletes its questions")
        XCTAssertEqual(narrow.scope, [], "an exam whose only topic went covers the whole course")
        XCTAssertEqual(both.scope, [genes.id])
        XCTAssertEqual(course.liveTopics.map(\.name), ["Genes"])
    }

    // MARK: Exams

    func testCreateExamResolvesTitleClampsTargetAndKeepsLiveScope() throws {
        let course = try XCTUnwrap(app.createCourse(name: "Bio 101", color: .sky, symbol: "leaf"))
        let cells = try XCTUnwrap(app.addTopic(named: "Cells", to: course.id))
        let stray = UUID()
        var draft = ExamDraft(title: "  ", courseID: course.id, date: day(14), wholeCourse: false, scope: [cells.id, stray])
        draft.target = 0.97
        draft.format.notes = "  open book  "
        let exam = try XCTUnwrap(app.createExam(draft))
        XCTAssertEqual(exam.title, "Bio 101 exam")
        XCTAssertEqual(exam.targetReadiness, 0.95, accuracy: 1e-9)
        XCTAssertEqual(exam.scope, [cells.id])
        XCTAssertEqual(exam.format.notes, "open book")
        XCTAssertEqual(exam.course?.id, course.id)
        XCTAssertNil(app.createExam(ExamDraft(title: "Orphan", courseID: nil, date: day(3))))
    }

    func testUpdateExamMovesCourseAndForgetsOldReadinessWhenTheDateMovesOut() throws {
        let bio = try XCTUnwrap(app.createCourse(name: "Bio", color: .sky, symbol: "leaf"))
        let chem = try XCTUnwrap(app.createCourse(name: "Chem", color: .sun, symbol: "flask"))
        let cells = try XCTUnwrap(app.addTopic(named: "Cells", to: bio.id))
        let moles = try XCTUnwrap(app.addTopic(named: "Moles", to: chem.id))
        let exam = try XCTUnwrap(app.createExam(ExamDraft(title: "Quiz", courseID: bio.id, date: day(-2), wholeCourse: false,
                                                          scope: [cells.id])))
        exam.readinessAtExam = 0.7
        var draft = ExamDraft(exam: exam)
        draft.courseID = chem.id
        draft.scope = [cells.id, moles.id]
        draft.date = day(6)
        app.updateExam(exam.id, with: draft)
        XCTAssertEqual(exam.course?.id, chem.id)
        XCTAssertEqual(exam.scope, [moles.id], "only the new course's topics stay in scope")
        XCTAssertNil(exam.readinessAtExam)
        XCTAssertEqual(exam.date, day(6))
        XCTAssertEqual(chem.liveExams.map(\.id), [exam.id])
        XCTAssertTrue(bio.liveExams.isEmpty)
    }

    func testDeleteExam() throws {
        let course = try XCTUnwrap(app.createCourse(name: "Bio", color: .sky, symbol: "leaf"))
        let exam = try XCTUnwrap(app.createExam(ExamDraft(title: "Quiz", courseID: course.id, date: day(4))))
        app.deleteExam(exam.id)
        XCTAssertNotNil(exam.deletedAt)
        XCTAssertTrue(app.upcomingExams().isEmpty)
    }

    func testLogGradeKeepsExamMorningReadinessAndCountsTowardCalibration() throws {
        let course = try XCTUnwrap(app.createCourse(name: "Bio", color: .sky, symbol: "leaf"))
        for _ in 0..<4 { item(in: course, studied: true) }
        let first = try XCTUnwrap(app.createExam(ExamDraft(title: "Quiz 1", courseID: course.id, date: day(10))))
        first.createdAt = day(-30)
        first.date = day(-3)
        app.save()
        XCTAssertNil(first.readinessAtExam)

        app.logGrade(examID: first.id, score: 1.3)
        XCTAssertEqual(first.resultScore, 1)
        XCTAssertEqual(first.resultLoggedAt, now)
        XCTAssertNotNil(first.readinessAtExam, "logging fills readiness on exam morning first")
        XCTAssertEqual(app.calibratingExamCount, 1)
        let soon = try XCTUnwrap(app.createExam(ExamDraft(title: "Quiz 3", courseID: course.id, date: day(9))))
        XCTAssertFalse(ExamPresentation.showsLetter(app.readiness(for: soon).projectedGrade), "no letter until calibrated")

        let second = try XCTUnwrap(app.createExam(ExamDraft(title: "Quiz 2", courseID: course.id, date: day(10))))
        second.createdAt = day(-30)
        second.date = day(-1)
        app.save()
        app.logGrade(examID: second.id, score: 0.82)
        XCTAssertEqual(app.calibratingExamCount, 2)
        let upcoming = try XCTUnwrap(app.createExam(ExamDraft(title: "Final", courseID: course.id, date: day(12))))
        XCTAssertTrue(app.readiness(for: upcoming).projectedGrade.isCalibrated)
        XCTAssertTrue(ExamPresentation.showsLetter(app.readiness(for: upcoming).projectedGrade), "two logged grades: the letter shows")
        XCTAssertTrue(app.projectedGrade(for: second).isCalibrated == false,
                      "an exam's own grade never calibrates its own projection (only one other exam has a grade)")
    }

    // MARK: Questions

    func testCreateItemIsAPersonItemAndRefusesAnUnfinishedDraft() throws {
        let course = try XCTUnwrap(app.createCourse(name: "Bio", color: .sky, symbol: "leaf"))
        let topic = try XCTUnwrap(app.addTopic(named: "Cells", to: course.id))
        XCTAssertNil(app.createItem(in: course.id, from: flashcard("Front", "")))

        var draft = flashcard("  Osmosis ", " Water across a membrane ")
        draft.topicID = topic.id
        let item = try XCTUnwrap(app.createItem(in: course.id, from: draft))
        XCTAssertEqual(item.origin, .person)
        XCTAssertEqual(item.status, .active)
        XCTAssertEqual(item.prompt, "Osmosis")
        XCTAssertEqual(item.answer, "Water across a membrane")
        XCTAssertEqual(item.topicID, topic.id)
        XCTAssertNil(item.checkedAt)
        XCTAssertEqual(item.memory.state, .new)
        XCTAssertEqual(app.itemSnapshots().map(\.id), [item.id])

        var suspended = flashcard("Diffusion", "High to low")
        suspended.suspended = true
        suspended.topicID = UUID()
        let paused = try XCTUnwrap(app.createItem(in: course.id, from: suspended))
        XCTAssertEqual(paused.status, .suspended)
        XCTAssertNil(paused.topicID, "a topic from another course is dropped")
    }

    func testUpdateItemChangesFormatKeepsMemoryAndClearsOtherFormatsFields() throws {
        let course = try XCTUnwrap(app.createCourse(name: "Bio", color: .sky, symbol: "leaf"))
        let original = item(in: course, kind: .flashcard, studied: true)
        let memory = original.memory
        var draft = ItemDraft(item: original)
        draft.kind = .mcq
        draft.prepareRows()
        draft.prompt = "Which phase lines up the chromosomes?"
        draft.options = [ItemDraft.Option(text: "Metaphase", correct: true), ItemDraft.Option(text: "Anaphase", correct: false),
                         ItemDraft.Option(text: "  ", correct: false)]
        app.clock = { self.now.addingTimeInterval(120) }
        app.updateItem(original.id, from: draft)
        XCTAssertEqual(original.kind, .mcq)
        XCTAssertEqual(original.answer, "Metaphase")
        XCTAssertEqual(original.choices.map(\.text), ["Metaphase", "Anaphase"])
        XCTAssertEqual(original.memory, memory, "editing keeps what Capling knows about your memory")
        XCTAssertEqual(original.updatedAt, now.addingTimeInterval(120))

        var back = ItemDraft(item: original)
        back.kind = .cloze
        back.clozeText = "During {{telophase}}, envelopes re-form."
        back.prompt = ""
        app.updateItem(original.id, from: back)
        XCTAssertEqual(original.kind, .cloze)
        XCTAssertTrue(original.choices.isEmpty)
        XCTAssertEqual(original.cloze?.answers, ["telophase"])
        XCTAssertEqual(original.prompt, ItemDraft.defaultClozePrompt)
        XCTAssertEqual(original.answer, "telophase")

        var pause = ItemDraft(item: original)
        pause.suspended = true
        app.updateItem(original.id, from: pause)
        XCTAssertEqual(original.status, .suspended)
        XCTAssertFalse(app.itemSnapshots().contains { $0.id == original.id })
    }

    func testUpdateItemNeverChangesADiagramsFormatOrLabels() throws {
        let course = try XCTUnwrap(app.createCourse(name: "Bio", color: .sky, symbol: "leaf"))
        let diagram = StudyItem(course: course, kind: .diagram, status: .active, origin: .cloud, prompt: "Label it",
                                answer: "Prophase, Metaphase",
                                diagram: DiagramSpec(sourceID: UUID(), pageIndex: 0,
                                                     targets: [DiagramTarget(anchorID: "p0.l3", label: "Prophase", box: .zero)]),
                                now: day(-4))
        app.context.insert(diagram)
        course.items.append(diagram)
        var draft = ItemDraft(item: diagram)
        draft.kind = .flashcard
        draft.prompt = "Name each phase"
        draft.answer = "changed"
        app.updateItem(diagram.id, from: draft)
        XCTAssertEqual(diagram.kind, .diagram)
        XCTAssertEqual(diagram.prompt, "Name each phase")
        XCTAssertEqual(diagram.answer, "Prophase, Metaphase")
        XCTAssertEqual(diagram.diagram?.targets.count, 1)
    }

    func testDeleteItemsIsSoft() throws {
        let course = try XCTUnwrap(app.createCourse(name: "Bio", color: .sky, symbol: "leaf"))
        let a = item(in: course), b = item(in: course)
        app.deleteItems([a.id])
        XCTAssertNotNil(a.deletedAt)
        XCTAssertNil(b.deletedAt)
        XCTAssertEqual(course.liveItems.map(\.id), [b.id])
    }

    // MARK: Sources

    func testDeleteSourceTakesItsQuestionsOrUnlinksThem() throws {
        let course = try XCTUnwrap(app.createCourse(name: "Bio", color: .sky, symbol: "leaf"))
        let notes = Source(course: course, kind: .text, title: "Notes", status: .ready, now: day(-5))
        let slides = Source(course: course, kind: .pdf, title: "Slides", status: .ready, now: day(-5))
        for source in [notes, slides] {
            app.context.insert(source)
            course.sources.append(source)
        }
        let fromNotes = item(in: course, source: notes, page: 0)
        let fromSlides = item(in: course, source: slides, page: 1)
        let label = StudyItem(course: course, kind: .diagram, status: .active, origin: .cloud, prompt: "Label", answer: "x",
                              diagram: DiagramSpec(sourceID: slides.id, pageIndex: 1, targets: []),
                              sourceRef: SourceRef(sourceID: slides.id, pageIndex: 1, label: "p. 2"), now: day(-5))
        app.context.insert(label)
        course.items.append(label)
        app.save()
        XCTAssertEqual(app.questions(from: slides).count, 2)
        XCTAssertEqual(app.questions(from: slides, pageIndex: 1).count, 2)
        XCTAssertEqual(app.questions(from: slides, pageIndex: 0).count, 0)

        app.deleteSource(notes.id, keepQuestions: false)
        XCTAssertNotNil(notes.deletedAt)
        XCTAssertNotNil(fromNotes.deletedAt)

        app.deleteSource(slides.id, keepQuestions: true)
        XCTAssertNil(fromSlides.deletedAt)
        XCTAssertNil(fromSlides.sourceRef, "a kept question loses its link to the gone page")
        XCTAssertNotNil(label.deletedAt, "a diagram can't live without its page")
        XCTAssertTrue(course.liveSources.isEmpty)
    }

    // MARK: Search entries

    func testSearchEntriesCoverLiveQuestionsSourcesAndLectures() throws {
        let course = try XCTUnwrap(app.createCourse(name: "Bio", color: .sky, symbol: "leaf"))
        let lecture = Source(course: course, kind: .lecture, title: "Lecture 6", status: .ready, now: day(-3))
        lecture.segments = [TranscriptSegment(id: "s1", start: 0, end: 5, text: "Anaphase pulls chromatids apart")]
        app.context.insert(lecture)
        course.sources.append(lecture)
        let kept = item(in: course)
        let gone = item(in: course)
        gone.deletedAt = now
        let draftItem = item(in: course)
        draftItem.status = .draft
        app.save()

        let entries = app.librarySearchEntries()
        XCTAssertEqual(Set(entries.filter { $0.kind == .question }.map(\.id)), [kept.id])
        XCTAssertEqual(entries.filter { $0.kind == .lecture }.map(\.id), [lecture.id])
        let results = LibrarySearch.search("chromatids", in: entries)
        XCTAssertEqual(results.lectures.map(\.id), [lecture.id])
        XCTAssertEqual(results.lectures.first?.snippet, "Anaphase pulls chromatids apart")
    }
}
