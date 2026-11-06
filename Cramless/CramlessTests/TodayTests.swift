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
        let (_, quiz, _) = world(quizIn: 2)
        let strip = TodaySnapshot.make(app: app).strip
        XCTAssertEqual(strip.map(\.offset), [-2, -1, 0, 1, 2, 3, 4])
        let eve = try XCTUnwrap(app.examPlans().first?.days.first { $0.kind == .examEve })
        XCTAssertGreaterThan(eve.shownMinutes, 0)
        XCTAssertEqual(strip[3].mark, .eve(minutes: app.builtEveMinutes(examID: quiz.id)), "tomorrow's eve: what its button will say")
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
        let readiness = app.topicReadiness(for: quiz)
        let values = snapshot.eveTopics.map { name in readiness.first { $0.name == name }?.value ?? 2 }
        XCTAssertEqual(values, values.sorted(), "weakest first, like the day's title")
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

    /// Two exams tomorrow share the evening: the card names both, the session holds both, and neither "can wait" for the other.
    func testTwoExamsTomorrowShareTheEvening() throws {
        let (_, quiz, bio) = world(quizIn: 1, withBio: true)
        let course = try XCTUnwrap(bio)
        for i in 0..<6 {
            let item = StudyItem(course: course, kind: .flashcard, status: .active, origin: .person, prompt: "M\(i)", answer: "A", now: clock.now)
            item.memory = due(cal, clock.now)
            app.context.insert(item)
            course.items.append(item)
        }
        let midterm = try XCTUnwrap(course.exams.first)
        midterm.date = quiz.date.addingTimeInterval(3 * 3600)
        let third = Course(name: "AP Psychology", now: clock.now)
        app.context.insert(third)
        let far = Exam(course: third, title: "AP Psych Exam", date: EngineTest.date(2026, 11, 14, 9, in: cal), now: clock.now)
        app.context.insert(far)
        third.exams.append(far)
        app.save()

        XCTAssertEqual(app.todaySummary().examEveExamIDs, [quiz.id, midterm.id])
        let snapshot = TodaySnapshot.make(app: app)
        XCTAssertEqual(snapshot.hero, .examEve(quiz.id))
        XCTAssertEqual(snapshot.eveTitle, "Chem 110 Quiz and Bio 101 Midterm")
        XCTAssertEqual(snapshot.eveOthers, ["AP Psychology"], "Bio isn't waiting for anything")
        XCTAssertEqual(TodayCopy.quietLine(examTitle: try XCTUnwrap(snapshot.eveTitle), others: snapshot.eveOthers),
                       "Cap is quiet tonight. AP Psychology can wait until after Chem 110 Quiz and Bio 101 Midterm.")
        let content = TodayHeroContent.make(snapshot)
        XCTAssertEqual(content.chip?.text, "Chem 110 Quiz and Bio 101 Midterm")

        let built = app.buildSession(SessionRequest(kind: .examEve, examID: quiz.id))
        XCTAssertEqual(Set(built.entries.compactMap(\.examID)), [quiz.id, midterm.id], "both exams' weak spots")
        XCTAssertEqual(snapshot.eveMinutes, built.tonightMinutes)

        // Done once, from either exam's page, the evening is done for both.
        let session = app.startSession(built)
        for entry in built.entries { app.recordReview(itemID: entry.itemID, rating: .good, sessionID: session.id) }
        app.finishSession(session)
        let after = TodaySnapshot.make(app: app)
        XCTAssertEqual(after.hero, .examEveDone(quiz.id))
        XCTAssertEqual(TodayHeroContent.make(after).reason, "Chem 110 Quiz and Bio 101 Midterm are tomorrow. Sleep is part of studying.")
        XCTAssertTrue(app.eveSessionDone(app.todaySummary()))
        XCTAssertEqual(after.strip.first { $0.isToday }?.mark, .done)
    }

    /// The day after an exam the card names the next one, whatever was due on the finished one.
    func testTheDayAfterAnExamTheSessionServesTheNext() throws {
        let (chem, quiz, bio) = world(quizIn: 2, withBio: true)
        let course = try XCTUnwrap(bio)
        for i in 0..<120 {
            let item = StudyItem(course: course, kind: .flashcard, status: .active, origin: .person, prompt: "M\(i)", answer: "A", now: clock.now)
            app.context.insert(item)
            course.items.append(item)
        }
        for i in 0..<20 {
            let item = StudyItem(course: chem, kind: .flashcard, status: .active, origin: .person, prompt: "D\(i)", answer: "A", now: clock.now)
            item.memory = due(cal, clock.now)
            app.context.insert(item)
            chem.items.append(item)
        }
        quiz.date = clock.now.addingTimeInterval(-3600)
        let midterm = try XCTUnwrap(course.exams.first)
        midterm.date = cal.adding(days: 3, to: clock.now)
        app.save()
        let session = app.todayBuiltSession()
        XCTAssertEqual(session.entries.filter { $0.courseID == chem.id }.count, 0, "the quiz is over")
        XCTAssertEqual(app.sessionFocus(session).examID, midterm.id)
        XCTAssertEqual(TodaySnapshot.make(app: app).focus?.exam.id, midterm.id)
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
        let (chem, _, _) = world(quizIn: 5)
        let items = chem.items.prefix(2).map(\.id)
        let first = Confusion(course: chem, name: "Moles vs molar mass", explanation: "", itemIDs: Array(items), missCount: 4, now: clock.now)
        let second = Confusion(course: chem, name: "Limiting vs excess", explanation: "", itemIDs: Array(items), missCount: 2, now: clock.now)
        app.context.insert(first)
        app.context.insert(second)
        app.save()
        var notices = TodaySnapshot.make(app: app).notices
        XCTAssertEqual(notices.map(\.kind), [.mixUp], "one card per kind a day")
        XCTAssertEqual(notices.first?.title, "You keep mixing up moles and molar mass.", "the most missed first")
        XCTAssertEqual(notices.first?.action?.title, "Fix it · 2 min")
        XCTAssertEqual(notices.first?.link, .confusion(first.id))
        XCTAssertEqual(notices.first?.cost, "No AI")
        if case .fixMixUp(let id)? = notices.first?.action?.run { XCTAssertEqual(id, first.id) } else { XCTFail("the fix") }

        app.snoozeNotice(try XCTUnwrap(notices.first).id)
        notices = TodaySnapshot.make(app: app).notices
        XCTAssertTrue(notices.isEmpty, "the second mix-up waits for another day")
        clock.advance(86_400)
        notices = TodaySnapshot.make(app: app).notices
        XCTAssertEqual(notices.first?.title, "You keep mixing up moles and molar mass.", "tomorrow it is back")
    }

    func testTheOldLaterStoreIsReadOnce() throws {
        let (chem, _, _) = world(quizIn: 5)
        let confusion = Confusion(course: chem, name: "Moles vs molar mass", explanation: "", itemIDs: chem.items.prefix(2).map(\.id), missCount: 4, now: clock.now)
        app.context.insert(confusion)
        app.save()
        let fresh = try StudyTestApp.make(clock: clock, calendar: cal, defaults: app.defaults, container: app.container)
        fresh.defaults.removeObject(forKey: AppModel.noticeLedgerKey)
        fresh.defaults.set([confusion.id.uuidString: cal.dayKey(for: clock.now), UUID().uuidString: "2020-01-01"], forKey: "capling.study.confusionSnooze")
        XCTAssertTrue(fresh.todayNotices().isEmpty, "put off today, in the old store")
        XCTAssertNil(fresh.defaults.object(forKey: "capling.study.confusionSnooze"), "and the old store is gone")
        XCTAssertTrue(fresh.defaults.data(forKey: AppModel.noticeLedgerKey) != nil)
        clock.advance(86_400)
        XCTAssertEqual(fresh.todayNotices().count, 1)
    }

    func testCapsCardsSayWhereTheyStand() throws {
        let (chem, _, _) = world()
        let confusion = Confusion(course: chem, name: "Moles vs molar mass", explanation: "", itemIDs: chem.items.prefix(2).map(\.id), missCount: 4, now: clock.now)
        app.context.insert(confusion)
        app.save()
        let snapshot = TodaySnapshot.make(app: app)
        XCTAssertEqual(snapshot.noticePosition, 1)
        XCTAssertEqual(snapshot.noticeTotal, 1)
    }

    func testDontShowTheseSwitchesTheKindOff() throws {
        let (chem, _, _) = world()
        let confusion = Confusion(course: chem, name: "Moles vs molar mass", explanation: "", itemIDs: chem.items.prefix(2).map(\.id), missCount: 4, now: clock.now)
        app.context.insert(confusion)
        app.save()
        XCTAssertEqual(app.todayNotices().count, 1)
        app.setNoticeKind(.mixUp, on: false)
        XCTAssertTrue(app.todayNotices().isEmpty)
        app.setNoticeKind(.mixUp, on: true)
        XCTAssertEqual(app.todayNotices().count, 1)
    }

    // MARK: Fix my week on the day card

    /// Chem 110 with long-overdue questions and a quiz in 6 days. 200 are more than the sessions before it can reach, so a fading card fires.
    @discardableResult
    private func fadingWorld(questions: Int = 200) throws -> (chem: Course, quiz: Exam) {
        let chem = Course(name: "Chem 110", now: clock.now)
        app.context.insert(chem)
        for i in 0..<questions {
            let item = StudyItem(course: chem, kind: .recall, status: .active, origin: .person, prompt: "Q\(i)", answer: "A long enough answer number \(i).", now: clock.now)
            item.memory = MemoryState(state: .review, stability: 1.4, difficulty: 5, due: cal.adding(days: -20, to: clock.now),
                                      lastReview: cal.adding(days: -25, to: clock.now), reps: 3)
            app.context.insert(item)
            chem.items.append(item)
        }
        let quiz = Exam(course: chem, title: "Chem 110 Quiz", date: EngineTest.date(2026, 10, 28, 10, in: cal), now: clock.now)
        app.context.insert(quiz)
        chem.exams.append(quiz)
        app.save()
        return (chem, quiz)
    }

    /// 80 own-words questions at the daily goal clear before the quiz: the catch-up card says so, and no card says they'll go dim.
    func testABacklogThatClearsBeforeTheExamDealsNoFadingCard() throws {
        try fadingWorld(questions: 80)
        let snapshot = TodaySnapshot.make(app: app)
        XCTAssertEqual(snapshot.hero, .catchUp)
        XCTAssertLessThan(snapshot.summary.catchUpDaysToClear, 6, "cleared before the quiz")
        XCTAssertFalse(snapshot.notices.contains { $0.kind == .fading })
    }

    func testABacklogTooBigForTheDaysLeftCountsOnlyWhatTheyCantReach() throws {
        try fadingWorld()
        let (_, rescue) = try fadingCard()
        XCTAssertLessThan(rescue.dimCount, 200 - 25, "the sessions ahead reach the rest")
        XCTAssertGreaterThan(rescue.dimCount, 80)
    }

    private func fadingCard() throws -> (card: CapNotice, rescue: FadeRescue) {
        let card = try XCTUnwrap(app.todayNotices().first { $0.kind == .fading })
        guard case .fixMyWeek(let rescue)? = card.action?.run else { throw XCTSkip("not a fading card") }
        return (card, rescue)
    }

    /// The whole way from the store to the plan: the planner's own tests hand it a ping, so they can't see the app failing to make one.
    private func plannedNotices() -> [NotificationPlanner.Planned] {
        NotificationPlanner.plan(app.notifications.planInput(for: app), calendar: cal).filter { $0.kind == .notice }
    }

    func testAFadingCardIsPlannedAsANotificationTonight() throws {
        try fadingWorld()
        app.settings.reminderMinutes = 19 * 60
        let planned = plannedNotices()
        XCTAssertEqual(planned.count, 1, "one card, once")
        XCTAssertEqual(planned.first.map { cal.dayKey(for: $0.date) }, cal.dayKey(for: clock.now))
    }

    func testAFadingCardFirstDealtAfterTheReminderTimeGoesOutTomorrow() throws {
        try fadingWorld()
        app.settings.reminderMinutes = 19 * 60
        clock.now = EngineTest.date(2026, 10, 22, 21, in: cal)
        app.save()
        let planned = plannedNotices()
        XCTAssertEqual(planned.count, 1, "tonight's time has gone by")
        XCTAssertEqual(planned.first.map { cal.dayKey(for: $0.date) }, cal.dayKey(for: cal.adding(days: 1, to: clock.now)))
    }

    func testAFadingCardAlreadySeenTodayGoesOutTomorrow() throws {
        try fadingWorld()
        app.settings.reminderMinutes = 19 * 60
        app.noteNoticeShown(try fadingCard().card.id)
        XCTAssertEqual(plannedNotices().map { cal.dayKey(for: $0.date) }, [cal.dayKey(for: cal.adding(days: 1, to: clock.now))])
    }

    /// The store's order changes between launches, and here every question ties, so the engines' ties are all decided by it.
    func testTheSameQuestionsMakeTheSameSessionAndCardHoweverTheyWereStored() throws {
        let ids = (0..<200).map { _ in UUID() }
        func make(_ order: [UUID]) throws -> (session: [UUID], dim: Int?) {
            let app = try StudyTestApp.make(clock: clock, calendar: cal)
            let chem = Course(name: "Chem 110", now: clock.now)
            app.context.insert(chem)
            for id in order {
                let item = StudyItem(id: id, course: chem, kind: .recall, status: .active, origin: .person, prompt: "Q", answer: "A long enough answer.", now: clock.now)
                item.memory = MemoryState(state: .review, stability: 1.4, difficulty: 5, due: cal.adding(days: -20, to: clock.now),
                                          lastReview: cal.adding(days: -25, to: clock.now), reps: 3)
                app.context.insert(item)
                chem.items.append(item)
            }
            let quiz = Exam(course: chem, title: "Chem 110 Quiz", date: EngineTest.date(2026, 10, 28, 10, in: cal), now: clock.now)
            app.context.insert(quiz)
            chem.exams.append(quiz)
            app.save()
            var dim: Int?
            if case .fading(let rescue)? = app.noticeDeck().first(where: { $0.kind == .fading })?.evidence { dim = rescue.dimCount }
            return (app.todayBuiltSession().entries.map(\.itemID), dim)
        }
        let first = try make(ids), second = try make(ids.reversed())
        XCTAssertEqual(first.session, second.session)
        XCTAssertEqual(first.dim, second.dim)
        XCTAssertNotNil(first.dim)
    }

    func testFixMyWeekAddsMinutesToTheDayCardAndThePlanStrip() throws {
        try fadingWorld()
        let before = TodaySnapshot.make(app: app)
        let (card, rescue) = try fadingCard()
        XCTAssertEqual(card.action?.title, "Fix my week")
        XCTAssertEqual(rescue.days.first?.offset, 0)
        app.perform(try XCTUnwrap(card.action))

        let after = TodaySnapshot.make(app: app)
        XCTAssertEqual(after.summary.minutesGoal, before.summary.minutesGoal + rescue.minutesPerDay, "the goal grows by today's boost")
        XCTAssertGreaterThan(after.summary.plannedMinutes, before.summary.plannedMinutes, "and so does the day card's button")
        XCTAssertEqual(after.notices.first?.title, "Plan updated")
        XCTAssertEqual(after.notices.first?.action?.title, "Undo")
        // Tomorrow's boost shows on the strip.
        if rescue.days.count > 1 {
            let tomorrow = try XCTUnwrap(after.strip.first { $0.offset == 1 })
            guard case .minutes(let minutes) = tomorrow.mark else { return XCTFail("a study day") }
            XCTAssertGreaterThanOrEqual(minutes, app.settings.dailyMinutes + rescue.minutesPerDay)
        }
        // The day's session takes its questions first.
        let built = app.todayBuiltSession()
        XCTAssertFalse(Set(built.entries.map(\.itemID)).isDisjoint(with: rescue.days[0].itemIDs))
    }

    func testFixMyWeekWritesNoMemoryAndUndoTakesItAllBack() throws {
        let (chem, _) = try fadingWorld()
        let memory = chem.items.map(\.memory)
        let before = TodaySnapshot.make(app: app).summary
        let (card, rescue) = try fadingCard()
        app.perform(try XCTUnwrap(card.action))
        XCTAssertEqual(chem.items.map(\.memory), memory, "no due date moved")
        let undo = try XCTUnwrap(TodaySnapshot.make(app: app).notices.first?.action)
        app.perform(undo)
        let after = TodaySnapshot.make(app: app)
        XCTAssertEqual(after.summary.minutesGoal, before.minutesGoal)
        XCTAssertEqual(after.summary.plannedMinutes, before.plannedMinutes)
        XCTAssertEqual(after.notices.first?.id, rescue.noticeID, "the card is back")
        XCTAssertTrue(app.noticeLedger.boosts.isEmpty)
    }

    func testTheDayIsDoneOnlyAfterTheBoostedMinutes() throws {
        try fadingWorld()
        let (card, rescue) = try fadingCard()
        app.perform(try XCTUnwrap(card.action))
        let goal = app.settings.dailyMinutes
        let record = app.dayRecord(for: clock.now)
        record.sessions = 1
        record.studySeconds = Double(goal * 60)
        app.save()
        XCTAssertNotEqual(TodaySnapshot.make(app: app).hero, .done, "the daily goal alone isn't the day any more")
        record.studySeconds = Double((goal + rescue.minutesPerDay) * 60)
        app.save()
        XCTAssertEqual(TodaySnapshot.make(app: app).hero, .done)
    }

    func testBoostedQuestionsDontFireAgainAndAMissedDayCanBringACardBack() throws {
        try fadingWorld()
        let (card, rescue) = try fadingCard()
        app.perform(try XCTUnwrap(card.action))
        app.dismissNoticeConfirmation()
        // Enough left over to fire on their own? Only if the rest are still at least five; the boosted ones aren't among them.
        if let again = app.noticeDeck().first(where: { $0.kind == .fading }), case .fading(let next) = again.evidence {
            XCTAssertTrue(Set(next.itemIDs).isDisjoint(with: rescue.itemIDs))
        }
        // Past the boost's last day, its questions may be noticed again, under a new id.
        clock.advance(86_400 * Double(rescue.days.count))
        XCTAssertTrue(app.noticeLedger.boosts.isEmpty, "over")
        let later = try XCTUnwrap(app.noticeDeck().first { $0.kind == .fading })
        XCTAssertNotEqual(later.id, rescue.noticeID)
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
        let spotted = ConfusionNote(id: UUID(), name: "x", missCount: 0, recentMisses: 0, recentAnswers: 0)
        XCTAssertEqual(SessionCopy.missLine(spotted), "Spotted before any mix-up. Want a 2-minute fix?")
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
