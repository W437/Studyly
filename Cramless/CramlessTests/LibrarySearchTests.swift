import Foundation
import XCTest
@testable import Cramless

/// The Library's search and its wording helpers.
final class LibrarySearchTests: XCTestCase {
    private func entry(_ kind: LibrarySearch.Kind, _ title: String, body: String = "", daysAgo: Double = 0) -> LibrarySearch.Entry {
        LibrarySearch.Entry(kind: kind, id: UUID(), courseID: UUID(), courseName: "Bio 101", color: .sky, title: title,
                            detail: "Topic", body: body, systemImage: "doc", date: Date(timeIntervalSince1970: 1_000_000 - daysAgo * 86_400))
    }

    // MARK: Search

    func testEveryWordMustMatchInAnyOrderIgnoringCaseAndAccents() {
        let entries = [
            entry(.question, "What is the cell membrane made of?"),
            entry(.question, "Describe osmosis", body: "Water crosses a MEMBRANE from dilute to concentrated."),
            entry(.source, "Week 5 slides", body: "The cell membrane\nA phospholipid bilayer"),
            entry(.lecture, "Lecture 6", body: "Mitose et méiose"),
        ]
        let results = LibrarySearch.search("membrane cell", in: entries)
        XCTAssertEqual(results.questions.map(\.entry.title), ["What is the cell membrane made of?"])
        XCTAssertEqual(results.sources.map(\.entry.title), ["Week 5 slides"])
        XCTAssertTrue(results.lectures.isEmpty)
        XCTAssertEqual(LibrarySearch.search("MEIOSE", in: entries).lectures.count, 1, "accents don't matter")
        XCTAssertTrue(LibrarySearch.search("   ", in: entries).isEmpty)
    }

    func testTitleMatchesRankFirstAndBodyMatchesCarryTheirLine() throws {
        let inBody = entry(.question, "Describe osmosis", body: "First line\nWater crosses a membrane here.", daysAgo: 0)
        let inTitle = entry(.question, "Membrane proteins", daysAgo: 5)
        let results = LibrarySearch.search("membrane", in: [inBody, inTitle])
        XCTAssertEqual(results.questions.map(\.entry.title), ["Membrane proteins", "Describe osmosis"])
        let titleHit = results.questions[0]
        XCTAssertEqual(titleHit.titleMatch, 0..<8)
        XCTAssertNil(titleHit.snippet)
        let bodyHit = results.questions[1]
        XCTAssertNil(bodyHit.titleMatch)
        XCTAssertEqual(bodyHit.snippet, "Water crosses a membrane here.")
        let match = try XCTUnwrap(bodyHit.snippetMatch)
        let snippet = Array(try XCTUnwrap(bodyHit.snippet))
        XCTAssertEqual(String(snippet[match]), "membrane")
    }

    func testLongLinesAreTrimmedAroundTheMatchAtWordBoundaries() throws {
        let words = (1...60).map { "word\($0)" }
        let line = (words[0..<40] + ["anaphase"] + words[40...]).joined(separator: " ")
        let (snippet, match) = try XCTUnwrap(LibrarySearch.snippet(for: ["anaphase"], phrase: "anaphase", in: line, width: 60))
        XCTAssertTrue(snippet.hasPrefix("…"))
        XCTAssertTrue(snippet.hasSuffix("…"))
        XCTAssertLessThanOrEqual(snippet.count, 64)
        XCTAssertEqual(String(Array(snippet)[match]), "anaphase")
        XCTAssertFalse(snippet.dropFirst().hasPrefix(" "))
    }

    func testResultsAreCappedPerKindWithACountOfTheRest() {
        let entries = (0..<30).map { entry(.question, "Cell question \($0)", daysAgo: Double($0)) }
        let results = LibrarySearch.search("cell", in: entries, limit: 25)
        XCTAssertEqual(results.questions.count, 25)
        XCTAssertEqual(results.moreQuestions, 5)
        XCTAssertEqual(results.total, 30)
        XCTAssertEqual(results.questions.first?.entry.title, "Cell question 0", "ties go to the newest")
    }

    func testCharacterRangeCountsCharactersNotBytes() {
        XCTAssertEqual(LibrarySearch.characterRange(of: "rna", in: "Ⓐ ARN, DNA y RNA"), 13..<16)
        XCTAssertEqual(LibrarySearch.characterRange(of: "cafe", in: "👩🏽‍🔬 Café"), 2..<6, "an emoji sequence is one character")
        XCTAssertNil(LibrarySearch.characterRange(of: "", in: "anything"))
    }

    // MARK: Wording

    func testShortExamTitleDropsTheCourseName() {
        XCTAssertEqual(LibraryFormat.shortExamTitle("Bio 101 Midterm", courseName: "Bio 101"), "Midterm")
        XCTAssertEqual(LibraryFormat.shortExamTitle("AP Psych Exam", courseName: "AP Psychology"), "Exam")
        XCTAssertEqual(LibraryFormat.shortExamTitle("chem 110 quiz", courseName: "Chem 110"), "Quiz")
        XCTAssertEqual(LibraryFormat.shortExamTitle("Final", courseName: "Bio 101"), "Final")
        XCTAssertEqual(LibraryFormat.shortExamTitle("Bio 101", courseName: "Bio 101"), "Bio 101")
    }

    func testExamLineSaysWhenInPlainWords() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        cal.locale = Locale(identifier: "en_US")
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 18))!
        func at(_ days: Int) -> Date { cal.adding(days: days, to: now) }
        XCTAssertEqual(LibraryFormat.shortWhen(at(0), now: now, calendar: cal), "today")
        XCTAssertEqual(LibraryFormat.shortWhen(at(1), now: now, calendar: cal), "tomorrow")
        XCTAssertEqual(LibraryFormat.examLine(title: "Bio 101 Midterm", courseName: "Bio 101", date: nil, now: now, calendar: cal),
                       "No exam yet")
        XCTAssertEqual(LibraryFormat.examLine(title: nil, courseName: "Bio 101", date: at(3), now: now, calendar: cal), "No exam yet")
        XCTAssertTrue(LibraryFormat.examLine(title: "Bio 101 Midterm", courseName: "Bio 101", date: at(23), now: now, calendar: cal)
            .hasPrefix("Midterm "))
        XCTAssertEqual(LibraryFormat.countdown(days: 23), "23 days to go")
        XCTAssertEqual(LibraryFormat.countdown(days: 1), "Tomorrow")
        XCTAssertEqual(LibraryFormat.countdown(days: 0), "Today")
        XCTAssertEqual(LibraryFormat.countdown(days: -3), "3 days ago")
    }

    func testSourceAndCourseLines() {
        XCTAssertEqual(LibraryFormat.courseCounts(sources: 1, questions: 86), "1 source · 86 questions")
        XCTAssertEqual(LibraryFormat.sourceMeta(kind: .scan, pages: 12, duration: 0, questions: 14), "Scan · 12 pages · 14 questions")
        XCTAssertEqual(LibraryFormat.sourceMeta(kind: .lecture, pages: 0, duration: 52 * 60, questions: 9), "Lecture · 52 min · 9 questions")
        XCTAssertEqual(LibraryFormat.sourceMeta(kind: .quizlet, pages: 0, duration: 0, questions: 1), "Quizlet · 1 question")
        XCTAssertEqual(LibraryFormat.clozeDisplay("During {{telophase}}, the {{nuclear envelopes}} re-form."),
                       "During ____, the ____ re-form.")
        XCTAssertEqual(LibraryFormat.formatLine(ExamFormat(multipleChoice: true, shortAnswer: false, essay: false, notes: " 40 min ")),
                       "Multiple choice · 40 min")
    }
}
