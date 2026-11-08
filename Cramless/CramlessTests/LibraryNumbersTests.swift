import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// One number everywhere: a course's number is its next exam's readiness (the exam page's own ring), its topics show readiness only
/// for that exam, and a course with no exam to come shows no number at all.
@MainActor
final class LibraryNumbersTests: XCTestCase {
    var cal: Calendar!
    var now: Date!
    var app: AppModel!
    var root: URL!
    var previousLive: AppModel?

    override func setUp() async throws {
        previousLive = AppModel.live
        root = FileManager.default.temporaryDirectory.appending(path: "library-numbers-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        FileStore.rootOverride = root
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        cal = c
        now = c.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 14))!
        let defaults = UserDefaults(suiteName: "library-numbers-\(UUID().uuidString)")!
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

    private func day(_ offset: Int, hour: Int = 9) -> Date {
        cal.adding(days: offset, to: cal.startOfDay(for: now)).addingTimeInterval(Double(hour) * 3600)
    }

    @discardableResult
    private func item(in course: Course, topic: Topic?, studied: Bool) -> StudyItem {
        let item = StudyItem(course: course, topicID: topic?.id, kind: .flashcard, status: .active, origin: .person,
                             prompt: "Question \(UUID().uuidString.prefix(4))", answer: "Answer", now: day(-10))
        if studied {
            item.memory = MemoryState(state: .review, stability: 6, difficulty: 5, due: day(3), lastReview: day(-2), reps: 3,
                                      lapses: 0, step: 0)
        }
        app.context.insert(item)
        course.items.append(item)
        return item
    }

    private func course(_ name: String) throws -> Course {
        try XCTUnwrap(app.createCourse(name: name, color: .sky, symbol: "leaf"))
    }

    private func topic(_ name: String, in course: Course) throws -> Topic {
        try XCTUnwrap(ItemFactory.topic(named: name, in: course, now: now))
    }

    // MARK: The next exam

    func testTheNextExamIsTheSoonestStillToComeAmongSeveral() throws {
        let bio = try course("Bio 101")
        for _ in 0..<3 { item(in: bio, topic: nil, studied: true) }
        let final = try XCTUnwrap(app.createExam(ExamDraft(title: "Bio 101 Final", courseID: bio.id, date: day(40))))
        let midterm = try XCTUnwrap(app.createExam(ExamDraft(title: "Bio 101 Midterm", courseID: bio.id, date: day(12))))
        let started = try XCTUnwrap(app.createExam(ExamDraft(title: "Bio 101 Quiz", courseID: bio.id, date: day(5))))
        started.date = now.addingTimeInterval(-3600) // began an hour ago: no longer to come
        app.save()

        XCTAssertEqual(app.nextExam(of: bio.id)?.id, midterm.id)
        let next = try XCTUnwrap(app.courseReadiness(bio))
        XCTAssertEqual(next.exam.id, midterm.id)
        XCTAssertEqual(next.value, app.readiness(for: midterm).value, accuracy: 1e-12, "the course's ring is the exam page's ring")
        XCTAssertNotEqual(next.value, app.readiness(for: final).value, accuracy: 1e-6, "a later exam reads differently")
    }

    func testACourseWithOnlyPastExamsOrNoneHasNoNumber() throws {
        let past = try course("Chem 110")
        item(in: past, topic: nil, studied: true)
        let quiz = try XCTUnwrap(app.createExam(ExamDraft(title: "Chem 110 Quiz", courseID: past.id, date: day(5))))
        quiz.date = day(-3)
        let none = try course("Spanish II")
        item(in: none, topic: nil, studied: true)
        app.save()

        XCTAssertNil(app.nextExam(of: past.id))
        XCTAssertNil(app.courseReadiness(past))
        XCTAssertNil(app.courseReadiness(none))
        let model = LibraryCourseModel(course: none, app: app)
        XCTAssertNil(model.readiness)
        XCTAssertEqual(model.examLine, "No exam yet")
        XCTAssertEqual(model.readinessAccessibility, "No exam date yet")
    }

    func testTheRingAndTheExamLineNameTheSameExam() throws {
        let bio = try course("Bio 101")
        for _ in 0..<4 { item(in: bio, topic: nil, studied: true) }
        _ = try XCTUnwrap(app.createExam(ExamDraft(title: "Bio 101 Final", courseID: bio.id, date: day(40))))
        let midterm = try XCTUnwrap(app.createExam(ExamDraft(title: "Bio 101 Midterm", courseID: bio.id, date: day(23))))
        app.save()

        let model = LibraryCourseModel(course: bio, app: app)
        XCTAssertEqual(model.examTitle, midterm.title)
        XCTAssertEqual(model.examLine, "Midterm \(LibraryFormat.shortDate(midterm.date, calendar: cal))")
        let value = try XCTUnwrap(model.readiness)
        XCTAssertEqual(value, app.readiness(for: midterm).value, accuracy: 1e-12)
        XCTAssertEqual(model.readinessAccessibility, "\(Int((value * 100).rounded())) percent ready for the Midterm")
    }

    // MARK: Topic lines

    func testTopicLinesShowReadinessOnlyForTheNextExamsTopics() throws {
        let bio = try course("Bio 101")
        let mitosis = try topic("Mitosis", in: bio)
        let meiosis = try topic("Meiosis", in: bio)
        let dna = try topic("DNA replication", in: bio)
        let ecology = try topic("Ecology", in: bio)
        item(in: bio, topic: mitosis, studied: true)
        item(in: bio, topic: mitosis, studied: false)
        item(in: bio, topic: meiosis, studied: false)
        item(in: bio, topic: ecology, studied: true)
        let midterm = try XCTUnwrap(app.createExam(ExamDraft(title: "Bio 101 Midterm", courseID: bio.id, date: day(23),
                                                             wholeCourse: false, scope: [mitosis.id, meiosis.id, dna.id])))
        app.save()

        let lines = LibraryFormat.topicLines(courseTopics: app.courseTopics(bio), examTopics: app.topicReadiness(for: midterm),
                                             examTitle: midterm.title, courseName: bio.name)
        XCTAssertEqual(lines.map(\.name), ["Mitosis", "Meiosis", "DNA replication", "Ecology"], "the course's own order")
        XCTAssertEqual(lines.map(\.questionCount), [2, 1, 0, 1])
        guard case .value(let mitosisValue) = lines[0].state else { return XCTFail("\(lines[0].state)") }
        XCTAssertEqual(mitosisValue, app.topicReadiness(for: midterm)[0].value ?? -1, accuracy: 1e-12)
        XCTAssertEqual(lines[1].state, .value(0), "unstudied questions count 0 toward readiness")
        XCTAssertEqual(lines[2].state, .gap)
        XCTAssertEqual(lines[3].state, .notOnExam("Midterm"), "outside the exam's scope: no number")
    }

    func testWithNoExamTheTopicsShowNoNumber() throws {
        let spanish = try course("Spanish II")
        let verbs = try topic("Verbs", in: spanish)
        let food = try topic("Food", in: spanish)
        item(in: spanish, topic: verbs, studied: true)
        app.save()

        let lines = LibraryFormat.topicLines(courseTopics: app.courseTopics(spanish), examTopics: nil, examTitle: nil,
                                             courseName: spanish.name)
        XCTAssertEqual(lines.map(\.state), [.noExam, .gap])
        XCTAssertEqual(lines.map(\.name), [verbs.name, food.name])
    }

    /// The course page's head names the next exam once, with its day; the ring beside it is the number.
    func testTheCourseHeadNamesTheNextExamAndItsDay() {
        let date = day(23)
        let line = LibraryFormat.headerExamLine(title: "Bio 101 Midterm", courseName: "Bio 101", date: date, calendar: cal)
        XCTAssertTrue(line.hasPrefix("Midterm · "), line)
        XCTAssertTrue(line.contains(date.formatted(LibraryFormat.dateStyle(cal).weekday(.abbreviated))), "the weekday is in it: \(line)")
        XCTAssertFalse(line.contains("%"), "no readiness in the words")
    }
}
