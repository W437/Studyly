import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// Today's rules (which card leads the day) and the words it uses.
@MainActor
final class TodayTests: XCTestCase {
    let cal = EngineTest.calendar()
    var clock: TestClock!
    var app: AppModel!
    var previousLive: AppModel?

    override func setUp() async throws {
        previousLive = AppModel.live
        clock = TestClock(EngineTest.date(2026, 10, 22, 18, in: cal))
        app = try StudyTestApp.make(clock: clock, calendar: cal)
        AppModel.schedulerFuzz = false
    }

    override func tearDown() async throws {
        AppModel.schedulerFuzz = true
        AppModel.live = previousLive
        app = nil
    }

    // MARK: The hero rules

    private func summary(ready: Bool = true, studied: Bool = false, done: Int = 0, goal: Int = 15,
                         catchUp: Bool = false, eve: UUID? = nil) -> TodaySummary {
        var s = TodaySummary()
        s.sessionReady = ready
        s.studiedToday = studied
        s.minutesDone = done
        s.minutesGoal = goal
        s.catchUp = catchUp
        s.examEveExamID = eve
        return s
    }

    func testTheHeroFollowsTheDay() {
        let exam = UUID()
        XCTAssertEqual(TodayHero.resolve(summary: summary(), hasCourses: false, hasItems: false, examEveDone: false), .empty)
        XCTAssertEqual(TodayHero.resolve(summary: summary(), hasCourses: true, hasItems: false, examEveDone: false), .noMaterial)
        XCTAssertEqual(TodayHero.resolve(summary: summary(), hasCourses: true, hasItems: true, examEveDone: false), .session)
        XCTAssertEqual(TodayHero.resolve(summary: summary(catchUp: true), hasCourses: true, hasItems: true, examEveDone: false),
                       .catchUp)
        XCTAssertEqual(TodayHero.resolve(summary: summary(eve: exam), hasCourses: true, hasItems: true, examEveDone: false),
                       .examEve(exam), "the exam eve replaces the daily session")
        XCTAssertEqual(TodayHero.resolve(summary: summary(studied: true, done: 16, eve: exam), hasCourses: true,
                                         hasItems: true, examEveDone: true), .examEveDone(exam))
        XCTAssertEqual(TodayHero.resolve(summary: summary(studied: true, done: 15), hasCourses: true, hasItems: true,
                                         examEveDone: false), .done)
        XCTAssertEqual(TodayHero.resolve(summary: summary(ready: false, studied: true, done: 6), hasCourses: true,
                                         hasItems: true, examEveDone: false), .done, "nothing left after studying")
        XCTAssertEqual(TodayHero.resolve(summary: summary(studied: true, done: 6), hasCourses: true, hasItems: true,
                                         examEveDone: false), .session, "half done: keep going")
        XCTAssertEqual(TodayHero.resolve(summary: summary(ready: false), hasCourses: true, hasItems: true,
                                         examEveDone: false), .caughtUp)
    }

    func testTheSnapshotFindsTheExamEveAndItsRest() throws {
        let course = Course(name: "Chem 110", now: clock.now)
        app.context.insert(course)
        for i in 0..<3 {
            let item = StudyItem(course: course, kind: .flashcard, status: .active, origin: .person, prompt: "Q\(i)",
                                 answer: "A\(i)", now: clock.now)
            app.context.insert(item)
            course.items.append(item)
        }
        let exam = Exam(course: course, title: "Chem quiz", date: EngineTest.date(2026, 10, 23, 10, in: cal), now: clock.now)
        app.context.insert(exam)
        course.exams.append(exam)
        app.save()

        let snapshot = TodaySnapshot.make(app: app)
        XCTAssertEqual(snapshot.hero, .examEve(exam.id))
        XCTAssertEqual(snapshot.exams.first?.id, exam.id)
        XCTAssertEqual(snapshot.exams.first?.daysLeft, 1)

        // The eve session, done: Today says sleep.
        let (session, built) = app.startSession(SessionRequest(kind: .examEve, examID: exam.id))
        let item = try XCTUnwrap(course.items.first)
        app.recordReview(itemID: built.entries.first?.itemID ?? item.id, rating: .good, sessionID: session.id)
        app.finishSession(session)
        XCTAssertEqual(TodaySnapshot.make(app: app).hero, .examEveDone(exam.id))
    }

    func testANewPersonSeesTheEmptyState() {
        let snapshot = TodaySnapshot.make(app: app)
        XCTAssertEqual(snapshot.hero, .empty)
        XCTAssertTrue(snapshot.exams.isEmpty)
        XCTAssertNil(snapshot.confusion)
    }

    func testInitials() {
        XCTAssertEqual(TodaySnapshot.initials("Maya"), "M")
        XCTAssertEqual(TodaySnapshot.initials("maya rivera"), "MR")
        XCTAssertEqual(TodaySnapshot.initials(""), "")
    }

    // MARK: Words

    func testMixUpLines() {
        XCTAssertEqual(SessionCopy.mixUpLine("Anaphase vs telophase"), "You keep mixing up anaphase and telophase.")
        XCTAssertEqual(SessionCopy.mixUpLine("DNA vs mRNA"), "You keep mixing up DNA and mRNA.")
        XCTAssertEqual(SessionCopy.mixUpLine("Mendelian genetics"), "Mendelian genetics keeps tripping you up.")
        XCTAssertEqual(SessionCopy.mixUpPair("Anaphase vs telophase"), "anaphase and telophase")
        let recent = ConfusionNote(id: UUID(), name: "x", missCount: 5, recentMisses: 3, recentAnswers: 4)
        XCTAssertEqual(SessionCopy.missLine(recent), "Missed 3 of the last 4 times. Want a 2-minute fix?")
        let thin = ConfusionNote(id: UUID(), name: "x", missCount: 3, recentMisses: 1, recentAnswers: 1)
        XCTAssertEqual(SessionCopy.missLine(thin), "Missed 3 times lately. Want a 2-minute fix?")
    }

    func testIntervalsReadLikeTheButtons() {
        XCTAssertEqual(SessionCopy.interval(days: 10.0 / 1440), "10 min")
        XCTAssertEqual(SessionCopy.interval(days: 1.0 / 1440), "1 min")
        XCTAssertEqual(SessionCopy.interval(days: 1), "1 day")
        XCTAssertEqual(SessionCopy.interval(days: 4), "4 days")
        XCTAssertEqual(SessionCopy.interval(days: 28), "4 weeks")
        XCTAssertEqual(SessionCopy.interval(days: 91), "3 months")
        XCTAssertEqual(SessionCopy.interval(days: 400), "1 year")
        XCTAssertEqual(SessionCopy.inInterval(days: 10.0 / 1440), "in 10 minutes")
        XCTAssertEqual(SessionCopy.inInterval(days: 1), "tomorrow")
        XCTAssertEqual(SessionCopy.inInterval(days: 4), "in 4 days")
    }

    func testTheSessionMixNeverBreaksAPart() {
        let mix = SessionCopy.sessionMix(reviews: 18, new: 6, weak: 2)
        XCTAssertEqual(mix.replacingOccurrences(of: "\u{00A0}", with: " "), "18 reviews · 6 new · 2 weak spots")
        XCTAssertFalse(mix.contains("2 weak"), "the parts hold together with non-breaking spaces")
        XCTAssertEqual(SessionCopy.sessionMix(reviews: 0, new: 3, weak: 0), "3\u{00A0}new")
        XCTAssertEqual(SessionCopy.sessionMix(reviews: 0, new: 0, weak: 0), "A short review")
    }

    func testScoreLinesAndVerdicts() {
        XCTAssertEqual(SessionCopy.scoreLine(hits: 2, total: 3, verdict: .partial), "2 of 3 key ideas")
        XCTAssertEqual(SessionCopy.scoreLine(hits: 1, total: 1, verdict: .correct), "1 of 1 key idea")
        XCTAssertEqual(SessionCopy.scoreLine(hits: 0, total: 0, verdict: .correct), "Matches")
        XCTAssertEqual(String(localized: SessionCopy.headline(.partial)), "Almost.")
        XCTAssertEqual(String(localized: SessionCopy.headline(.wrong, answered: false)), "Here's the answer.")
        XCTAssertEqual(String(localized: SessionCopy.headline(.right)), "Nice!")
        XCTAssertEqual(String(localized: SessionCopy.headline(.right, saved: true)), "Saved it.")
        XCTAssertEqual(String(localized: SessionCopy.headline(.wrong, saved: true)), "Not yet.", "only a right answer saves")
        XCTAssertEqual(SessionCopy.moreQuestions(5), "5 more questions")
        XCTAssertEqual(SessionCopy.unbroken("Bio 101 exam"), "Bio\u{00A0}101\u{00A0}exam")
    }
}
