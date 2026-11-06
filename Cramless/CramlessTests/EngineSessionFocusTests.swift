import Foundation
import XCTest
@testable import Cramless

/// `SessionFocus`: which exam a built session serves, read from its questions' exams.
final class EngineSessionFocusTests: XCTestCase {
    let cal = EngineTest.calendar()
    lazy var now = EngineTest.date(2026, 11, 6, 14, in: cal)
    let chemCourse = UUID(), bioCourse = UUID(), psychCourse = UUID()
    let moles = UUID(), limiting = UUID(), cells = UUID(), memory = UUID()
    lazy var chem = ExamSnapshot(courseID: chemCourse, title: "Chem 110 Quiz", date: cal.adding(days: 2, to: now))
    lazy var bio = ExamSnapshot(courseID: bioCourse, title: "Bio 101 Midterm", date: cal.adding(days: 23, to: now))
    lazy var psych = ExamSnapshot(courseID: psychCourse, title: "AP Psych Exam", date: cal.adding(days: 196, to: now))
    lazy var exams = [chem, bio, psych]

    func entry(_ exam: ExamSnapshot?, topic: UUID?, seconds: Double, reason: SessionEntry.Reason = .due,
               course: UUID? = nil) -> SessionEntry {
        SessionEntry(itemID: UUID(), reason: reason, kind: .mcq, topicID: topic, courseID: course ?? exam?.courseID,
                     estimatedSeconds: seconds, examID: exam?.id)
    }

    func session(_ entries: [SessionEntry], weak: [WeakSpot] = []) -> BuiltSession {
        BuiltSession(id: UUID(), kind: .daily, entries: entries, budgetSeconds: 900, courseID: nil, topicID: nil, examID: nil,
                     confusionID: nil, weakSpots: weak)
    }

    func testTheExamWithMostOfTheSessionIsItsFocus() {
        // Chem 50%, Bio 30%, Spanish (no exam) 20%.
        let entries = [entry(chem, topic: moles, seconds: 200), entry(chem, topic: limiting, seconds: 250, reason: .new),
                       entry(chem, topic: limiting, seconds: 50), entry(bio, topic: cells, seconds: 300),
                       entry(nil, topic: nil, seconds: 200, course: UUID())]
        let focus = SessionFocus.make(session(entries), exams: exams, now: now, calendar: cal)
        XCTAssertEqual(focus.examID, chem.id)
        XCTAssertEqual(focus.topicIDs, [limiting, moles], "by seconds")
        XCTAssertEqual(focus.dueCount, 2)
        XCTAssertEqual(focus.newCount, 1)
        XCTAssertEqual(focus.focusSeconds, 500)
        XCTAssertEqual(focus.totalSeconds, 1000)
        XCTAssertEqual(focus.secondsByExam[bio.id], 300)
        XCTAssertEqual(focus.otherExamIDs, [psych.id], "Bio's 30% is more than a few questions; AP Psych gets nothing")
    }

    func testWithNoExamNearbyNoneHoldingFortyPercentMeansNoFocus() {
        var later = chem
        later.date = cal.adding(days: 30, to: now)
        let split = [entry(later, topic: moles, seconds: 350), entry(bio, topic: cells, seconds: 350),
                     entry(nil, topic: nil, seconds: 300, course: UUID())]
        let none = SessionFocus.make(session(split), exams: [later, bio, psych], now: now, calendar: cal)
        XCTAssertNil(none.examID)
        XCTAssertEqual(Set(none.topicIDs), [moles, cells], "every topic in the session")
        XCTAssertEqual(none.dueCount, 3, "the whole session's")
        XCTAssertEqual(none.otherExamIDs, [psych.id])
        // Exactly 40% is enough.
        let edge = [entry(later, topic: moles, seconds: 400), entry(bio, topic: cells, seconds: 300),
                    entry(nil, topic: nil, seconds: 300, course: UUID())]
        XCTAssertEqual(SessionFocus.make(session(edge), exams: [later, bio, psych], now: now, calendar: cal).examID, later.id)
        // An empty session has none.
        let empty = SessionFocus.make(session([]), exams: exams, now: now, calendar: cal)
        XCTAssertNil(empty.examID)
        XCTAssertEqual(empty.otherExamIDs, [chem.id, bio.id, psych.id])
    }

    /// The Friday of the demo world: a small quiz in two days has all its questions in the session, and a midterm further off has
    /// twice the minutes. The quiz is what today is for.
    func testAnExamThisWeekWithAFifthOfTheSessionTakesTheFocusFromABiggerShareFurtherOff() {
        let friday = [entry(chem, topic: moles, seconds: 240), entry(bio, topic: cells, seconds: 480),
                      entry(psych, topic: memory, seconds: 180)]
        let focus = SessionFocus.make(session(friday), exams: exams, now: now, calendar: cal)
        XCTAssertEqual(focus.examID, chem.id)
        XCTAssertEqual(focus.topicIDs, [moles], "only the focus exam's topics")
        XCTAssertEqual(focus.focusSeconds, 240)
        // Exactly a fifth is enough; just under it, the biggest share with 40% takes it.
        let fifth = [entry(chem, topic: moles, seconds: 200), entry(bio, topic: cells, seconds: 800)]
        XCTAssertEqual(SessionFocus.make(session(fifth), exams: exams, now: now, calendar: cal).examID, chem.id)
        let under = [entry(chem, topic: moles, seconds: 199), entry(bio, topic: cells, seconds: 801)]
        XCTAssertEqual(SessionFocus.make(session(under), exams: exams, now: now, calendar: cal).examID, bio.id)
    }

    func testAWeekCountsAndAWeekAndADayDoesNot() {
        var near = chem
        near.date = cal.adding(days: 7, to: now)
        let entries = [entry(near, topic: moles, seconds: 300), entry(bio, topic: cells, seconds: 700)]
        XCTAssertEqual(SessionFocus.make(session(entries), exams: [near, bio, psych], now: now, calendar: cal).examID, near.id)
        near.date = cal.adding(days: 8, to: now)
        XCTAssertEqual(SessionFocus.make(session(entries), exams: [near, bio, psych], now: now, calendar: cal).examID, bio.id)
    }

    func testOfTwoExamsThisWeekTheSoonerWinsWhateverTheShares() {
        var midterm = bio
        midterm.date = cal.adding(days: 5, to: now)
        let entries = [entry(midterm, topic: cells, seconds: 700), entry(chem, topic: moles, seconds: 300)]
        XCTAssertEqual(SessionFocus.make(session(entries), exams: [chem, midterm, psych], now: now, calendar: cal).examID, chem.id)
    }

    /// The title reads weakest first, as "Why these?" does; topics with no number come last, ties keep their order.
    func testTopicsWeakestFirst() {
        let entries = [entry(chem, topic: limiting, seconds: 300), entry(chem, topic: moles, seconds: 200), entry(chem, topic: cells, seconds: 100)]
        let focus = SessionFocus.make(session(entries), exams: exams, now: now, calendar: cal)
        XCTAssertEqual(focus.topicIDs, [limiting, moles, cells], "by seconds")
        XCTAssertEqual(focus.topicsWeakestFirst(readiness: [limiting: 0.42, moles: 0.39]), [moles, limiting, cells])
        XCTAssertEqual(focus.topicsWeakestFirst(readiness: [limiting: 0.4, moles: 0.4, cells: 0.4]), [limiting, moles, cells])
        XCTAssertEqual(focus.topicsWeakestFirst(readiness: [:]), [limiting, moles, cells])
    }

    func testATieGoesToTheSoonerExam() {
        let tied = [entry(bio, topic: cells, seconds: 300), entry(chem, topic: moles, seconds: 300)]
        XCTAssertEqual(SessionFocus.make(session(tied), exams: exams, now: now, calendar: cal).examID, chem.id)
        var later = chem
        later.date = cal.adding(days: 30, to: now)
        XCTAssertEqual(SessionFocus.make(session(tied), exams: [later, bio, psych], now: now, calendar: cal).examID, bio.id)
    }

    func testQuestionsOutsideAnyExam() {
        let spanish = UUID(), vocab = UUID()
        let entries = (0..<4).map { _ in entry(nil, topic: vocab, seconds: 9, course: spanish) }
        let focus = SessionFocus.make(session(entries), exams: exams, now: now, calendar: cal)
        XCTAssertNil(focus.examID)
        XCTAssertEqual(focus.topicIDs, [vocab])
        XCTAssertEqual(focus.dueCount, 4)
        XCTAssertTrue(focus.secondsByExam.isEmpty)
        XCTAssertEqual(focus.otherExamIDs, [chem.id, bio.id, psych.id], "every exam can wait")
    }

    /// A quiz on one topic and a midterm on the whole course: questions on the quiz's topic serve the quiz (the sooner exam), the
    /// rest the midterm; the focus exam's topics stay inside its scope, weak spots first.
    func testTwoExamsInOneCourse() {
        let quiz = ExamSnapshot(courseID: chemCourse, title: "Quiz", date: cal.adding(days: 10, to: now), scope: [moles])
        let final = ExamSnapshot(courseID: chemCourse, title: "Final", date: cal.adding(days: 30, to: now))
        let entries = (0..<4).map { _ in entry(quiz, topic: moles, seconds: 16) }
            + (0..<2).map { _ in entry(final, topic: limiting, seconds: 16, reason: .weak) }
        let weak = [WeakSpot(id: limiting, name: "Limiting reagents", source: .topic, courseID: chemCourse,
                             itemIDs: entries.suffix(2).map(\.itemID)),
                    WeakSpot(id: moles, name: "Moles", source: .topic, courseID: chemCourse, itemIDs: [entries[0].itemID])]
        let focus = SessionFocus.make(session(entries, weak: weak), exams: [quiz, final], now: now, calendar: cal)
        XCTAssertEqual(focus.examID, quiz.id, "two thirds of the session")
        XCTAssertEqual(focus.topicIDs, [moles], "Limiting reagents is weak but not on the quiz")
        XCTAssertEqual(focus.dueCount, 4)
        XCTAssertEqual(focus.weakCount, 0)
        XCTAssertEqual(focus.otherExamIDs, [], "the final gets a third")

        // When the final holds most of it, the weak topic comes first, and the quiz's topic is on the final too.
        let more = entries + (0..<6).map { _ in entry(final, topic: limiting, seconds: 16) }
        let finalFocus = SessionFocus.make(session(more, weak: weak), exams: [quiz, final], now: now, calendar: cal)
        XCTAssertEqual(finalFocus.examID, final.id)
        XCTAssertEqual(finalFocus.topicIDs, [limiting, moles], "weak spots first, both in the final's scope")
        XCTAssertEqual(finalFocus.weakCount, 2)
    }

    /// A mix-up's questions name their topics.
    func testAMixUpsTopicsComeFirst() {
        let entries = [entry(chem, topic: limiting, seconds: 100), entry(chem, topic: moles, seconds: 16)]
        let mixUp = WeakSpot(id: UUID(), name: "Moles vs molar mass", source: .confusion, courseID: chemCourse,
                             itemIDs: [entries[1].itemID])
        XCTAssertEqual(SessionFocus.make(session(entries, weak: [mixUp]), exams: exams, now: now, calendar: cal).topicIDs, [moles, limiting])
    }
}
