import XCTest
@testable import Cramless

/// "Why these?": at most three rows that say why today's session holds what it holds, none that repeats the card (`TodayReasons.make`).
final class TodayReasonsTests: XCTestCase {
    private func input() -> TodayReasons.Input {
        TodayReasons.Input(examTitle: "Chem 110 Quiz", daysLeft: 2, focusSeconds: 240,
                           weakestName: "Limiting reagents", weakestValue: 0.38, weakestToday: 4, due: 12, new: 0,
                           others: [TodayReasons.Other(name: "Bio 101", daysLeft: 23, inToday: false),
                                    TodayReasons.Other(name: "AP Psychology", daysLeft: 196, inToday: false)],
                           scopeCount: 7)
    }

    func testThePlanDaysReasonsInOrderThreeAtMost() {
        let rows = TodayReasons.make(input())
        XCTAssertEqual(rows.map(\.id), ["weakest", "due", "wait"], "the exam's own row is the card's chip; the thin-readiness note is fourth")
        XCTAssertEqual(rows[0].title, "Limiting reagents is the weakest: 38% ready")
        XCTAssertEqual(rows[0].detail, "4 of today's questions are on it.")
        XCTAssertEqual(rows[1].title, "12 to review")
        XCTAssertEqual(rows[1].detail, "They come back just before you'd forget them.")
        XCTAssertEqual(rows[2].title, "Bio 101 and AP Psychology can wait")
        XCTAssertEqual(rows[2].detail, "Their exams are 23 days and 6 months away.")
        // With fewer reasons, the thin readiness gets its row.
        var thin = input()
        thin.others = []
        XCTAssertEqual(TodayReasons.make(thin).map(\.id), ["weakest", "due", "few"])
        XCTAssertEqual(TodayReasons.make(thin)[2].title, "Chem 110 Quiz has 7 questions so far")
    }

    /// The demo's day: a quiz with 7 of 42 questions. The sheet says how the session is shared and why the other courses are in it.
    func testASharedSessionSaysHowItIsSharedAndWhoElseIsIn() {
        var i = input()
        i.sessionTotal = 42
        i.examQuestions = 7
        i.due = 6
        i.new = 1
        i.others = [TodayReasons.Other(name: "Bio 101", daysLeft: 23, inToday: true, seconds: 480),
                    TodayReasons.Other(name: "AP Psychology", daysLeft: 196, inToday: true, seconds: 180)]
        let rows = TodayReasons.make(i)
        XCTAssertEqual(rows.map(\.id), ["total", "alsoIn", "weakest"])
        XCTAssertEqual(rows[0].title, "About 42 questions today")
        XCTAssertEqual(rows[0].detail, "7 are for Chem 110 Quiz.")
        XCTAssertEqual(rows[1].title, "Bio 101 and AP Psychology questions are in too")
        XCTAssertEqual(rows[1].detail, "They're up for review. Their exams are further off.")
        i.examQuestions = 1
        XCTAssertEqual(TodayReasons.make(i)[0].detail, "1 is for Chem 110 Quiz.")
        // Shared, with nothing else to say: the counts are the exam's.
        i.others = []
        i.weakestName = nil
        XCTAssertEqual(TodayReasons.make(i).map(\.title), ["About 42 questions today", "6 to review for this exam", "1 new question for this exam"])
    }

    func testAllOfItForTheExamOrNoExam() {
        var i = input()
        i.sessionTotal = 12
        i.examQuestions = 12
        XCTAssertFalse(TodayReasons.make(i).contains { $0.id == "total" }, "nothing to tell apart")
        // No exam: what is to review and new, and what waits.
        let plain = TodayReasons.make(TodayReasons.Input(due: 6, new: 1, sessionTotal: 12))
        XCTAssertEqual(plain.map(\.id), ["due", "new"])
        XCTAssertEqual(plain[0].title, "6 to review")
        XCTAssertEqual(plain[1].detail, "A few at a time, so they stick.")
    }

    func testSingularCounts() {
        var i = input()
        i.weakestToday = 1
        i.due = 1
        i.new = 1
        i.others = [TodayReasons.Other(name: "Bio 101", daysLeft: 1, inToday: false)]
        let rows = TodayReasons.make(i)
        XCTAssertEqual(rows.first { $0.id == "weakest" }?.detail, "1 of today's questions is on it.")
        XCTAssertEqual(rows.first { $0.id == "due" }?.title, "1 to review")
        XCTAssertEqual(rows.first { $0.id == "new" }?.title, "1 new question")
        i.new = 0
        XCTAssertEqual(TodayReasons.make(i).first { $0.id == "wait" }?.detail, "Its exam is 1 day away.")
    }

    func testOtherExamsWithAFewQuestionsTodaySaySo() {
        var i = input()
        i.others = [TodayReasons.Other(name: "Bio 101", daysLeft: 23, inToday: true),
                    TodayReasons.Other(name: "AP Psychology", daysLeft: 196, inToday: false)]
        let rows = TodayReasons.make(i)
        XCTAssertEqual(rows.first { $0.id == "alsoIn" }?.title, "A few Bio 101 questions are in too")
        XCTAssertEqual(rows.map(\.id), ["alsoIn", "weakest", "due"], "what waits is fourth")
    }

    func testAnotherExamNearerThanTheOneTheSessionIsForIsNotCalledFurtherOff() {
        var i = input()
        i.examTitle = "Bio 101 Midterm"
        i.daysLeft = 23
        i.focusSeconds = 480
        i.others = [TodayReasons.Other(name: "Chem 110", daysLeft: 2, inToday: true, seconds: 240),
                    TodayReasons.Other(name: "AP Psychology", daysLeft: 196, inToday: true, seconds: 180)]
        let row = TodayReasons.make(i).first { $0.id == "alsoIn" }
        XCTAssertEqual(row?.title, "A few Chem 110 and AP Psychology questions are in too")
        XCTAssertEqual(row?.detail, "They're up for review.")
    }

    func testFurtherOffAndASmallerShareSaySoAndOnlyWhenBothAreTrue() {
        var i = input()
        i.others = [TodayReasons.Other(name: "Bio 101", daysLeft: 23, inToday: true, seconds: 120),
                    TodayReasons.Other(name: "AP Psychology", daysLeft: 196, inToday: true, seconds: 60)]
        var row = TodayReasons.make(i).first { $0.id == "alsoIn" }
        XCTAssertEqual(row?.title, "A few Bio 101 and AP Psychology questions are in too")
        XCTAssertEqual(row?.detail, "Their exams are further off, so they get a smaller share of today.")
        i.others.removeLast()
        XCTAssertEqual(TodayReasons.make(i).first { $0.id == "alsoIn" }?.detail,
                       "Its exam is further off, so it gets a smaller share of today.")

        // Further off, but more of today than the quiz, whose few questions are all in. Not "a few", not "smaller".
        i.others = [TodayReasons.Other(name: "Bio 101", daysLeft: 23, inToday: true, seconds: 480),
                    TodayReasons.Other(name: "AP Psychology", daysLeft: 196, inToday: true, seconds: 180)]
        row = TodayReasons.make(i).first { $0.id == "alsoIn" }
        XCTAssertEqual(row?.title, "Bio 101 and AP Psychology questions are in too")
        XCTAssertEqual(row?.detail, "They're up for review. Their exams are further off.")
    }

    func testUpForReviewOnlyWhenTheyAre() {
        var i = input()
        i.daysLeft = 30
        i.others = [TodayReasons.Other(name: "Bio 101", daysLeft: 23, inToday: true, seconds: 60, due: false)]
        XCTAssertEqual(TodayReasons.make(i).first { $0.id == "alsoIn" }?.title, "A few Bio 101 questions are in too")
        i.others[0].seconds = 600
        XCTAssertEqual(TodayReasons.make(i).first { $0.id == "alsoIn" }?.title, "Bio 101 questions are in too")
        XCTAssertNil(TodayReasons.make(i).first { $0.id == "alsoIn" }?.detail, "new questions, and 23 days isn't further off than 30")
    }

    func testWithNoExamNothingIsInToo() {
        let rows = TodayReasons.make(TodayReasons.Input(due: 18, new: 6, others: [TodayReasons.Other(name: "Bio 101", daysLeft: 23, inToday: true, seconds: 300)]))
        XCTAssertEqual(rows.map(\.id), ["due", "new"], "with no exam the session serves, nothing is \"in too\"")
    }

    func testNamesAreNotRepeatedAndTheWordsKeepTheRules() {
        var i = input()
        i.scopeCount = 40
        i.others = [TodayReasons.Other(name: "Bio 101", daysLeft: 23, inToday: false),
                    TodayReasons.Other(name: "Bio 101", daysLeft: 60, inToday: false)]
        let rows = TodayReasons.make(i)
        XCTAssertFalse(rows.contains { $0.id == "few" })
        XCTAssertEqual(rows.first { $0.id == "wait" }?.title, "Bio 101 can wait")
        for row in rows {
            let words = "\(row.title) \(row.detail ?? "")"
            XCTAssertFalse(words.contains("cards"))
            XCTAssertFalse(words.contains(" due"), "to review, not due")
            XCTAssertFalse(words.contains("about to forget"))
            XCTAssertFalse(words.contains(", then "))
        }
    }
}
