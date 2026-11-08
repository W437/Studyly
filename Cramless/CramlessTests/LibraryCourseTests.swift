import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// The Library's "Recent" and the course page: exam chips, the course's session and the Questions tab's filters.
@MainActor
final class LibraryCourseTests: XCTestCase {
    /// Questions made in one go share a date, and the store hands them over in no fixed order: the tab reads the same on every launch.
    func testTheQuestionsTabHasOneOrderWhateverTheStoreSays() {
        struct Key { var topic: Int; var created: Date; var id: UUID }
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let ids = (0..<6).map { _ in UUID() }
        let keys = ids.map { Key(topic: 1, created: date, id: $0) } + [Key(topic: 0, created: date.addingTimeInterval(9), id: UUID()),
                                                                       Key(topic: 1, created: date.addingTimeInterval(-9), id: UUID())]
        func sorted(_ list: [Key]) -> [UUID] {
            list.sorted {
                CourseQuestions.comesBefore(topicA: $0.topic, createdA: $0.created, idA: $0.id, topicB: $1.topic, createdB: $1.created, idB: $1.id)
            }.map(\.id)
        }
        let order = sorted(keys)
        XCTAssertEqual(order[0], keys[6].id, "the first topic first")
        XCTAssertEqual(order[1], keys[7].id, "then the oldest")
        for _ in 0..<5 { XCTAssertEqual(sorted(keys.shuffled()), order) }
    }

    let cal = EngineTest.calendar()
    var clock: TestClock!
    var app: AppModel!
    var previousLive: AppModel?

    override func setUp() async throws {
        previousLive = AppModel.live
        clock = TestClock(EngineTest.date(2026, 11, 6, 14, in: cal))
        app = try StudyTestApp.make(clock: clock, calendar: cal)
    }

    override func tearDown() async throws {
        AppModel.live = previousLive
        app = nil
    }

    private var now: Date { clock.now }
    private func day(_ offset: Int) -> Date { cal.adding(days: offset, to: now) }

    // MARK: Recent

    private func candidate(_ title: String, kind: SourceKind = .pdf, drafts: Int = 0, opened: Int? = nil, added: Int = -60) -> LibraryRecent.Candidate {
        LibraryRecent.Candidate(id: UUID(), title: title, kind: kind, color: .sky, drafts: drafts, openedAt: opened.map(day), addedAt: day(added))
    }

    func testRecentPutsQuestionsToReviewFirstThenWhatWasOpenedOrAdded() {
        let rows = LibraryRecent.rows([candidate("Old", opened: -30), candidate("Added", kind: .lecture, added: -9), candidate("Opened", opened: 0),
                                       candidate("Waiting", drafts: 14, added: -40)], now: now, calendar: cal)
        XCTAssertEqual(rows.map(\.title), ["Waiting", "Opened", "Added"])
        XCTAssertEqual(rows.map(\.detail), ["14 questions to review", "PDF · opened today", "Lecture · added 9 days ago"])
    }

    func testRecentSkipsWhatIsOverTwoWeeksOldAndHidesUnderTwo() {
        XCTAssertTrue(LibraryRecent.rows([candidate("Only", opened: -1), candidate("Old", opened: -15)], now: now, calendar: cal).isEmpty)
        XCTAssertEqual(LibraryRecent.rows([candidate("A", opened: -1), candidate("B", opened: -14)], now: now, calendar: cal).count, 2)
        XCTAssertEqual(LibraryRecent.rows((0..<6).map { candidate("S\($0)", opened: -$0) }, now: now, calendar: cal).count, LibraryRecent.limit)
    }

    func testRecentOpensWhatItSays() {
        let waiting = candidate("Waiting", kind: .lecture, drafts: 2)
        let lecture = candidate("Lecture", kind: .lecture, opened: -1)
        let reading = candidate("Reading", opened: -2)
        let rows = LibraryRecent.rows([waiting, lecture, reading], now: now, calendar: cal)
        XCTAssertEqual(rows.map(\.destination), [.reviewDraft(waiting.id), .lecture(lecture.id), .source(reading.id)])
    }

    func testAnOpenIsRememberedOnThisIPhone() throws {
        let course = Course(name: "Bio 101", now: day(-60))
        app.context.insert(course)
        let a = Source(course: course, kind: .pdf, title: "Slides", status: .ready, now: day(-60))
        let b = Source(course: course, kind: .text, title: "Notes", status: .ready, now: day(-60))
        for source in [a, b] {
            app.context.insert(source)
            course.sources.append(source)
        }
        try app.context.save()
        XCTAssertTrue(app.libraryRecent().isEmpty)
        app.noteOpened(sourceID: a.id)
        clock.advance(60)
        app.noteOpened(sourceID: b.id)
        XCTAssertEqual(app.libraryRecent().map(\.title), ["Notes", "Slides"])
        app.noteOpened(sourceID: a.id, at: clock.now.addingTimeInterval(60))
        XCTAssertEqual(app.libraryRecent().map(\.title), ["Slides", "Notes"], "the newest open comes first")
    }

    // MARK: Exam chips

    func testExamChipWords() {
        func exam(_ title: String, _ offset: Int, result: Double? = nil) -> LibraryFormat.ChipExam {
            LibraryFormat.ChipExam(id: UUID(), title: title, date: day(offset), result: result)
        }
        let chips = LibraryFormat.examChips([exam("Bio 101 Quiz 1", -40, result: 0.91), exam("Bio 101 Final", 40),
                                             exam("Bio 101 Midterm", 23), exam("Bio 101 Quiz 2", -3)],
                                            courseName: "Bio 101", now: now, calendar: cal)
        XCTAssertEqual(chips.map(\.state), [.upcoming, .upcoming, .logGrade, .graded], "to come, soonest first; then what waits for a grade; then grades")
        XCTAssertEqual(chips[0].text, "Midterm · \(LibraryFormat.shortDate(day(23), calendar: cal))",
                       "no readiness on a chip: the course's one number is its ring")
        XCTAssertEqual(chips[2].text, "Quiz 2 · log your grade")
        XCTAssertEqual(chips[3].text, "Quiz 1 · you got 91%")
    }

    func testOnlyTheLatestGradesKeepAChip() {
        let graded = (1...4).map { LibraryFormat.ChipExam(id: UUID(), title: "Quiz \($0)", date: day(-$0 * 10), result: 0.8) }
        let chips = LibraryFormat.examChips(graded, courseName: "Bio", now: now, calendar: cal)
        XCTAssertEqual(chips.map { String($0.text.prefix(6)) }, ["Quiz 1", "Quiz 2"])
    }

    // MARK: The Questions tab

    private func row(_ kind: ItemKind = .mcq, topic: UUID? = nil, suspended: Bool = false, recall: Double? = nil, mixUp: Bool = false) -> CourseQuestions.Row {
        CourseQuestions.Row(id: UUID(), kind: kind, topicID: topic, isSuspended: suspended, recall: recall, inMixUp: mixUp)
    }

    func testNeedsAttentionIsFadingOrInAMixUp() {
        XCTAssertTrue(row(recall: 0.69).needsAttention, "under the sky's dim line")
        XCTAssertFalse(row(recall: ReviewOutcome.fadingRecall).needsAttention)
        XCTAssertFalse(row(recall: nil).needsAttention, "never studied: nothing to fade")
        XCTAssertTrue(row(recall: 0.95, mixUp: true).needsAttention)
        XCTAssertTrue(row(recall: nil, mixUp: true).needsAttention)
        XCTAssertFalse(row(suspended: true, recall: 0.2).needsAttention, "suspended waits for nothing")
    }

    func testNeedsAttentionPutsTheWeakestFirst() {
        let middle = row(recall: 0.6), weakest = row(recall: 0.2), fine = row(recall: 0.9), mixed = row(recall: 0.4, mixUp: true)
        let shown = CourseQuestions.filtered([middle, fine, weakest, mixed], filter: .attention, topic: nil)
        XCTAssertEqual(shown.map(\.id), [weakest.id, mixed.id, middle.id])
    }

    func testFilterCountsFollowTheTopic() {
        let a = UUID(), b = UUID()
        let rows = [row(.mcq, topic: a, recall: 0.3), row(.recall, topic: a), row(.mcq, topic: b, suspended: true), row(.cloze, topic: b, recall: 0.9)]
        let all = CourseQuestions.counts(rows, topic: nil)
        XCTAssertEqual(all.all, 4)
        XCTAssertEqual(all.attention, 1)
        XCTAssertEqual(all.suspended, 1)
        XCTAssertEqual(all.kinds[.mcq], 2)
        let onlyB = CourseQuestions.counts(rows, topic: b)
        XCTAssertEqual(onlyB.all, 2)
        XCTAssertEqual(onlyB.attention, 0)
        XCTAssertEqual(onlyB.kinds[.mcq], 1)

        XCTAssertEqual(CourseQuestions.filtered(rows, filter: .kind(.mcq), topic: a).count, 1)
        XCTAssertEqual(CourseQuestions.filtered(rows, filter: .suspended, topic: nil).count, 1)
        XCTAssertEqual(CourseQuestions.filtered(rows, filter: .all, topic: b).count, 2)
    }

    func testAFilterHookNamesAFilter() {
        XCTAssertEqual(CourseQuestions.filter(named: "attention"), .attention)
        XCTAssertEqual(CourseQuestions.filter(named: "suspended"), .suspended)
        XCTAssertEqual(CourseQuestions.filter(named: "mcq"), .kind(.mcq))
        XCTAssertNil(CourseQuestions.filter(named: "nonsense"))
    }

    func testQuestionRowsReadRecallAndOpenMixUps() throws {
        let course = Course(name: "Bio 101", now: day(-60))
        app.context.insert(course)
        func item(_ prompt: String, memory: MemoryState? = nil) -> StudyItem {
            let made = StudyItem(course: course, kind: .flashcard, status: .active, origin: .person, prompt: prompt, answer: "A", now: day(-60))
            if let memory { made.memory = memory }
            app.context.insert(made)
            course.items.append(made)
            return made
        }
        let fading = item("Fading", memory: MemoryState(state: .review, stability: 2, difficulty: 5, due: day(-5), lastReview: day(-30), reps: 3))
        let mixed = item("Mixed")
        let fresh = item("Fresh")
        let confusion = Confusion(course: course, name: "A vs B", explanation: "", itemIDs: [mixed.id], missCount: 2, now: day(-2))
        app.context.insert(confusion)
        course.confusions.append(confusion)
        try app.context.save()

        let rows = app.courseQuestionRows([fading, mixed, fresh])
        XCTAssertTrue(rows[0].needsAttention)
        XCTAssertNotNil(rows[0].recall)
        XCTAssertTrue(rows[1].inMixUp)
        XCTAssertNil(rows[2].recall)
        XCTAssertFalse(rows[2].needsAttention)
    }

    // MARK: Studying a course

    func testStudyingACourseIsThatCoursesDailyAtTheWholeGoalThenPractice() throws {
        let bio = Course(name: "Bio 101", now: day(-60)), chem = Course(name: "Chem 110", now: day(-60)), empty = Course(name: "Spanish", now: day(-60))
        for course in [bio, chem, empty] { app.context.insert(course) }
        for (course, count) in [(bio, 4), (chem, 4)] {
            for index in 0..<count {
                let item = StudyItem(course: course, kind: .flashcard, status: .active, origin: .person, prompt: "\(course.name) \(index)", answer: "A", now: day(-60))
                app.context.insert(item)
                course.items.append(item)
            }
        }
        try app.context.save()

        let study = try XCTUnwrap(app.courseStudy(bio))
        XCTAssertEqual(study.request.kind, .daily)
        XCTAssertEqual(study.request.courseID, bio.id)
        XCTAssertEqual(study.request.minutes, app.settings.dailyMinutes, "the whole goal, not what today has left")
        XCTAssertTrue(study.title.hasPrefix("Study Bio 101 · "), study.title)
        let built = app.buildSession(study.request)
        XCTAssertFalse(built.isEmpty)
        XCTAssertTrue(built.entries.allSatisfy { $0.courseID == bio.id }, "only this course")

        XCTAssertNil(app.courseStudy(empty), "nothing to study: the page offers Add material")

        // Everything reviewed, nothing due: the button is a practice round.
        for item in chem.items {
            item.memory = MemoryState(state: .review, stability: 60, difficulty: 5, due: day(40), lastReview: day(-1), reps: 3)
        }
        try app.context.save()
        let practice = try XCTUnwrap(app.courseStudy(chem))
        XCTAssertEqual(practice.request.kind, .practice)
        XCTAssertTrue(practice.title.hasPrefix("Practice Chem 110 · "), practice.title)
    }

    func testASessionForOneCourseSaysSo() {
        XCTAssertEqual(SessionCopy.studyCourse("Bio 101"), "Study · Bio 101")
        XCTAssertEqual(SessionCopy.title(for: .practice), "Practice", "one word per job")
    }
}
