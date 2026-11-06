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
        XCTAssertTrue(snapshot.notices.isEmpty)
        XCTAssertTrue(snapshot.strip.isEmpty)
        XCTAssertTrue(snapshot.firstDay)
        XCTAssertTrue(snapshot.greeting.hasPrefix("Welcome"), "the band says welcome on the first day")
    }

    func testInitials() {
        XCTAssertEqual(TodaySnapshot.initials("Maya"), "M")
        XCTAssertEqual(TodaySnapshot.initials("maya rivera"), "MR")
        XCTAssertEqual(TodaySnapshot.initials(""), "")
    }

    // MARK: The day card's world

    private let due = { (cal: Calendar, now: Date) in
        MemoryState(state: .review, stability: 3, difficulty: 5, due: cal.adding(days: -1, to: now),
                    lastReview: cal.adding(days: -4, to: now), reps: 3)
    }

    /// Chem 110 with two topics and due questions, a quiz in `days` days; optionally Bio 101 with a midterm further off.
    @discardableResult
    private func world(quizIn days: Int = 2, withBio: Bool = false, items: Int = 6) -> (chem: Course, quiz: Exam, bio: Course?) {
        let chem = Course(name: "Chem 110", now: clock.now)
        app.context.insert(chem)
        let reagents = Topic(course: chem, name: "Limiting reagents", sortOrder: 0, now: clock.now)
        let moles = Topic(course: chem, name: "Moles", sortOrder: 1, now: clock.now)
        app.context.insert(reagents)
        app.context.insert(moles)
        chem.topics.append(contentsOf: [reagents, moles])
        for i in 0..<items {
            let item = StudyItem(course: chem, topicID: i % 2 == 0 ? reagents.id : moles.id, kind: .flashcard, status: .active,
                                 origin: .person, prompt: "Q\(i)", answer: "A\(i)", now: clock.now)
            item.memory = due(cal, clock.now)
            app.context.insert(item)
            chem.items.append(item)
        }
        let quiz = Exam(course: chem, title: "Chem 110 Quiz", date: EngineTest.date(2026, 10, 22 + days, 10, in: cal), now: clock.now)
        app.context.insert(quiz)
        chem.exams.append(quiz)
        var bio: Course?
        if withBio {
            let b = Course(name: "Bio 101", now: clock.now)
            app.context.insert(b)
            let item = StudyItem(course: b, kind: .flashcard, status: .active, origin: .person, prompt: "B", answer: "B", now: clock.now)
            app.context.insert(item)
            b.items.append(item)
            let midterm = Exam(course: b, title: "Bio 101 Midterm", date: EngineTest.date(2026, 11, 14, 9, in: cal), now: clock.now)
            app.context.insert(midterm)
            b.exams.append(midterm)
            bio = b
        }
        app.save()
        return (chem, quiz, bio)
    }

    func testTheCardNamesTheExamItsTopicsAndAForecastThatNeverGoesDown() throws {
        let (_, quiz, _) = world()
        let snapshot = TodaySnapshot.make(app: app)
        XCTAssertEqual(snapshot.hero, .session)
        let focus = try XCTUnwrap(snapshot.focus, "every question today is for the quiz")
        XCTAssertEqual(focus.exam.id, quiz.id)
        XCTAssertEqual(Set(focus.topics), ["Limiting reagents", "Moles"])
        XCTAssertGreaterThanOrEqual(focus.forecast, focus.exam.readiness)
        XCTAssertLessThanOrEqual(focus.forecast, 1)
        XCTAssertGreaterThan(focus.forecast, focus.exam.readiness, "studying six due questions moves it")
        XCTAssertEqual(focus.exam.itemsInScope, 6)
        XCTAssertEqual(focus.dueCount, 6)
        let content = TodayHeroContent.make(snapshot)
        XCTAssertEqual(content.chip?.text, "For Chem 110 Quiz")
        XCTAssertTrue(content.when?.contains("in 2 days") ?? false, content.when ?? "")
        XCTAssertEqual(content.rings?.footnote, "Based on 6 questions so far.")
        // The forecast is the ring's own function over today's session.
        let snapshotExam = try XCTUnwrap(app.examSnapshots(upcomingOnly: true).first)
        XCTAssertEqual(focus.forecast, max(focus.exam.readiness, app.readinessAfter(app.todayBuiltSession(), for: snapshotExam)),
                       accuracy: 1e-9)
    }

    func testTheWeekShowsTheEveAndTheExamAndNothingRed() throws {
        world(quizIn: 2)
        let strip = TodaySnapshot.make(app: app).strip
        XCTAssertEqual(strip.map(\.offset), [-2, -1, 0, 1, 2, 3, 4])
        let eve = try XCTUnwrap(app.examPlans().first?.days.first { $0.kind == .examEve })
        XCTAssertEqual(strip[3].mark, .eve(minutes: eve.shownMinutes), "what the exam page's plan says about that evening")
        XCTAssertEqual(strip[3].examTitles, ["Chem 110 Quiz"])
        XCTAssertEqual(strip[4].mark, .exam(count: 1))
        XCTAssertEqual(strip[0].mark, .missed, "no record: a hollow circle")
        if case .minutes(let m) = strip[2].mark { XCTAssertGreaterThan(m, 0) } else { XCTFail("today: its minutes") }
    }

    func testOnTheEveTheCardNamesTonightsTopicsAndCapIsQuietAboutTheOthers() throws {
        let (_, quiz, _) = world(quizIn: 1, withBio: true)
        let snapshot = TodaySnapshot.make(app: app)
        XCTAssertEqual(snapshot.hero, .examEve(quiz.id))
        XCTAssertTrue(snapshot.isEve)
        XCTAssertFalse(snapshot.eveTopics.isEmpty)
        XCTAssertTrue(Set(snapshot.eveTopics).isSubset(of: ["Limiting reagents", "Moles"]))
        XCTAssertEqual(snapshot.eveOthers, ["Bio 101"])
        XCTAssertEqual(TodayCopy.quietLine(examTitle: quiz.title, others: snapshot.eveOthers),
                       "Cap is quiet tonight. Bio 101 can wait until after Chem 110 Quiz.")
        let content = TodayHeroContent.make(snapshot)
        XCTAssertEqual(content.title, "Tonight: weak spots only")
        // The button, the reason and the week all say tonight's session's own minutes.
        let built = app.buildSession(SessionRequest(kind: .examEve, examID: quiz.id))
        XCTAssertEqual(snapshot.eveMinutes, built.plannedMinutes)
        XCTAssertTrue((1...10).contains(snapshot.eveMinutes), "\(snapshot.eveMinutes)")
        XCTAssertEqual(String(localized: try XCTUnwrap(content.actions.first).title), "Tonight · \(snapshot.eveMinutes) min")
        XCTAssertTrue(content.reason.hasPrefix("\(snapshot.eveMinutes) minute"), content.reason)
        XCTAssertEqual(snapshot.strip.first { $0.isToday }?.mark, .eve(minutes: snapshot.eveMinutes))
        XCTAssertTrue(content.when?.hasPrefix("Tomorrow · ") ?? false, content.when ?? "")
    }

    /// A quiz this week with a fifth of the session is what the day is for, however much of it goes to a midterm further off; the
    /// session's readiness follows it.
    func testAQuizThisWeekTakesTheCardFromABiggerMidtermFurtherOff() throws {
        let (_, quiz, bio) = world(withBio: true)
        let course = try XCTUnwrap(bio)
        for i in 0..<12 {
            let item = StudyItem(course: course, kind: .flashcard, status: .active, origin: .person, prompt: "M\(i)", answer: "A", now: clock.now)
            item.memory = due(cal, clock.now)
            app.context.insert(item)
            course.items.append(item)
        }
        app.save()
        let session = app.todayBuiltSession()
        let focus = app.sessionFocus(session)
        XCTAssertEqual(focus.examID, quiz.id)
        let midterm = try XCTUnwrap(app.examSnapshots(upcomingOnly: true).first { $0.title == "Bio 101 Midterm" })
        XCTAssertGreaterThan(focus.secondsByExam[midterm.id] ?? 0, focus.focusSeconds, "the midterm has more of the session")
        XCTAssertEqual(TodaySnapshot.make(app: app).focus?.exam.id, quiz.id)
        XCTAssertEqual(app.trackedExam(for: session)?.id, quiz.id)
        // "Why these?" says what is true: not "a few", not "a smaller share".
        let row = try XCTUnwrap(TodayReasons.make(app.todayReasonsInput()).first { $0.id == "alsoIn" })
        XCTAssertEqual(row.title, "Bio 101 questions are in too", "one of them is new, so not \"because they're due\"")
        XCTAssertEqual(row.detail, "Its exam is further off.")
    }

    /// The card's title and "Why these?" agree on what is weakest.
    func testTheTitleLeadsWithTheTopicWhyTheseCallsWeakest() throws {
        let (chem, _, _) = world()
        // Moles barely remembered, Limiting reagents well: readiness says Moles, the session's own order says otherwise.
        for item in chem.items {
            let weak = item.topicID == chem.topics.first { $0.name == "Moles" }?.id
            item.memory = MemoryState(state: .review, stability: weak ? 0.5 : 30, difficulty: 5, due: cal.adding(days: -1, to: clock.now),
                                      lastReview: cal.adding(days: weak ? -4 : -2, to: clock.now), reps: 3)
        }
        app.save()
        let snapshot = TodaySnapshot.make(app: app)
        let focus = try XCTUnwrap(snapshot.focus)
        XCTAssertEqual(focus.topics.first, "Moles")
        XCTAssertEqual(app.todayReasonsInput().weakestName, focus.topics.first)
        XCTAssertTrue(TodayHeroContent.make(snapshot).title.hasPrefix("Moles"))
    }

    func testTheDoneCardsGainBelongsToTheExamTheSessionCountedToward() throws {
        let (chem, quiz, _) = world(withBio: true)
        let (session, built) = app.startSession(SessionRequest(kind: .daily))
        XCTAssertEqual(session.examID, quiz.id, "the session was mostly for the quiz")
        for entry in built.entries where entry.courseID == chem.id {
            app.recordReview(itemID: entry.itemID, rating: .good, sessionID: session.id)
        }
        app.finishSession(session)
        XCTAssertEqual(app.todayDoneExamID(), quiz.id)
        let snapshot = TodaySnapshot.make(app: app)
        let done = try XCTUnwrap(snapshot.doneExam)
        XCTAssertEqual(done.title, "Chem 110 Quiz")
        XCTAssertGreaterThan(done.deltaToday, 0, "today's reviews moved its readiness")
    }

    func testAMixUpIsCapsCardAndLaterPutsItOffUntilTomorrow() throws {
        let (chem, _, _) = world()
        let items = chem.items.prefix(2).map(\.id)
        let first = Confusion(course: chem, name: "Moles vs molar mass", explanation: "", itemIDs: Array(items), missCount: 4, now: clock.now)
        let second = Confusion(course: chem, name: "Limiting vs excess", explanation: "", itemIDs: Array(items), missCount: 2, now: clock.now)
        app.context.insert(first)
        app.context.insert(second)
        app.save()
        var notices = TodaySnapshot.make(app: app).notices
        XCTAssertEqual(notices.map(\.kind), [.mixUp, .mixUp])
        XCTAssertEqual(notices.first?.title, "You keep mixing up moles and molar mass.", "the most missed first")
        XCTAssertEqual(notices.first?.action?.title, "Fix it · 2 min")
        XCTAssertEqual(notices.first?.link, .confusion(first.id))
        if case .fixMixUp(let id)? = notices.first?.action?.run { XCTAssertEqual(id, first.id) } else { XCTFail("the fix") }

        app.snoozeNotice(try XCTUnwrap(notices.first).id)
        notices = TodaySnapshot.make(app: app).notices
        XCTAssertEqual(notices.count, 1, "Later moves to the next")
        XCTAssertEqual(notices.first?.title, "You keep mixing up limiting and excess.")
        clock.advance(86_400)
        XCTAssertEqual(TodaySnapshot.make(app: app).notices.count, 2, "tomorrow it is back")
    }

    func testCapsActionRunsTheFixDrill() throws {
        let (chem, _, _) = world()
        let confusion = Confusion(course: chem, name: "Moles vs molar mass", explanation: "", itemIDs: chem.items.prefix(2).map(\.id),
                                  missCount: 3, now: clock.now)
        app.context.insert(confusion)
        app.save()
        let action = try XCTUnwrap(app.todayNotices().first?.action)
        let request = try XCTUnwrap(app.perform(action))
        XCTAssertEqual(request.kind, .fix)
        XCTAssertEqual(request.confusionID, confusion.id)
        XCTAssertEqual(app.router.cover, .session(request))
    }

    func testAllLitPracticesTheTopicRememberedLeast() {
        world()
        let snapshot = TodaySnapshot.make(app: app)
        XCTAssertNotNil(snapshot.practice)
        XCTAssertTrue(["Limiting reagents", "Moles"].contains(snapshot.practice?.name ?? ""))
    }

    func testAnExamWithNoCourseYetMakesItsCourse() throws {
        XCTAssertTrue(app.courses.isEmpty)
        var draft = ExamDraft.new(courseID: nil, now: clock.now, calendar: cal)
        XCTAssertNotNil(draft.problem, "no course and no name")
        draft.newCourseName = "  Bio 101 "
        XCTAssertNil(draft.problem)
        let exam = try XCTUnwrap(app.createExam(draft))
        XCTAssertEqual(exam.course?.name, "Bio 101")
        XCTAssertEqual(exam.title, "Bio 101 exam")
        XCTAssertEqual(app.courses.map(\.name), ["Bio 101"])
    }

    func testReasonsSayWhatTheSessionIsForAndWhatWaits() throws {
        world(withBio: true)
        let input = app.todayReasonsInput()
        XCTAssertEqual(input.examTitle, "Chem 110 Quiz")
        XCTAssertEqual(input.courseName, "Chem 110")
        XCTAssertEqual(input.scopeCount, 6)
        XCTAssertNotNil(input.weakestName)
        XCTAssertEqual(input.others.map(\.name), ["Bio 101"])
        let rows = TodayReasons.make(input)
        XCTAssertEqual(rows.first?.id, "exam")
        XCTAssertTrue(rows.contains { $0.id == "few" }, "six questions is a thin guess")
    }

    // MARK: The exams row

    /// The third tile always shows at the edge of the screen, so the row says it scrolls.
    func testTheNextTilePeeks() {
        for width in [375.0, 393, 402, 430, 440] {
            let tile = TodayExamsRow.tileWidth(rowWidth: width)
            let third = CLSpace.gutter + 2 * (tile + 12)
            XCTAssertGreaterThanOrEqual(width - third, 24, "\(width)")
            XCTAssertLessThan(third, width)
            XCTAssertGreaterThanOrEqual(tile, 150)
        }
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
