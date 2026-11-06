import XCTest
@testable import Cramless

/// "Why these?": the rows that say why today's session holds what it holds (`TodayReasons.make`).
final class TodayReasonsTests: XCTestCase {
    private func input() -> TodayReasons.Input {
        TodayReasons.Input(examTitle: "Chem 110 Quiz", when: "Sun · in 2 days",
                           scopeTopics: ["Limiting reagents", "Stoichiometry", "Moles"], courseName: "Chem 110",
                           weakestName: "Limiting reagents", weakestValue: 0.38, weakestToday: 4, due: 12, new: 0,
                           others: [TodayReasons.Other(name: "Bio 101", daysLeft: 23, inToday: false),
                                    TodayReasons.Other(name: "AP Psychology", daysLeft: 196, inToday: false)],
                           scopeCount: 7)
    }

    func testThePlanDaysReasonsInOrder() {
        let rows = TodayReasons.make(input())
        XCTAssertEqual(rows.map(\.id), ["exam", "weakest", "due", "wait", "few"])
        XCTAssertEqual(rows[0].title, "Chem 110 Quiz · Sun · in 2 days")
        XCTAssertEqual(rows[0].detail, "It covers Limiting reagents, Stoichiometry, and Moles.")
        XCTAssertEqual(rows[1].title, "Limiting reagents is the weakest: 38% ready")
        XCTAssertEqual(rows[1].detail, "4 of today's questions are on it.")
        XCTAssertEqual(rows[2].title, "12 questions are due")
        XCTAssertEqual(rows[3].title, "Bio 101 and AP Psychology can wait")
        XCTAssertEqual(rows[3].detail, "Their exams are 23 days and 6 months away.")
        XCTAssertEqual(rows[4].title, "Chem 110 Quiz has 7 questions so far")
    }

    func testAWholeCourseExamAndSingularCounts() {
        var i = input()
        i.scopeTopics = []
        i.weakestToday = 1
        i.due = 1
        i.new = 1
        i.others = [TodayReasons.Other(name: "Bio 101", daysLeft: 1, inToday: false)]
        let rows = TodayReasons.make(i)
        XCTAssertEqual(rows.first { $0.id == "exam" }?.detail, "It covers all of Chem 110.")
        XCTAssertEqual(rows.first { $0.id == "weakest" }?.detail, "1 of today's questions is on it.")
        XCTAssertEqual(rows.first { $0.id == "due" }?.title, "1 question is due")
        XCTAssertEqual(rows.first { $0.id == "new" }?.title, "1 new question")
        XCTAssertEqual(rows.first { $0.id == "wait" }?.detail, "Its exam is 1 day away.")
    }

    func testOtherExamsWithAFewQuestionsTodaySaySo() {
        var i = input()
        i.others = [TodayReasons.Other(name: "Bio 101", daysLeft: 23, inToday: true),
                    TodayReasons.Other(name: "AP Psychology", daysLeft: 196, inToday: false)]
        let rows = TodayReasons.make(i)
        XCTAssertEqual(rows.first { $0.id == "wait" }?.title, "AP Psychology can wait")
        XCTAssertEqual(rows.first { $0.id == "alsoIn" }?.title, "A few Bio 101 questions are in too")
    }

    func testWithNoExamOnlyWhatIsDueAndNew() {
        let rows = TodayReasons.make(TodayReasons.Input(due: 18, new: 6))
        XCTAssertEqual(rows.map(\.id), ["due", "new"])
        XCTAssertEqual(rows[1].detail, "A few at a time, so they stick.")
    }

    func testEnoughQuestionsNeedNoNoteAndNamesAreNotRepeated() {
        var i = input()
        i.scopeCount = 40
        i.others = [TodayReasons.Other(name: "Bio 101", daysLeft: 23, inToday: false),
                    TodayReasons.Other(name: "Bio 101", daysLeft: 60, inToday: false)]
        let rows = TodayReasons.make(i)
        XCTAssertFalse(rows.contains { $0.id == "few" })
        XCTAssertEqual(rows.first { $0.id == "wait" }?.title, "Bio 101 can wait")
        for row in rows {
            XCTAssertFalse(row.title.contains("cards"))
            XCTAssertFalse((row.detail ?? "").contains(", then "))
        }
    }
}
