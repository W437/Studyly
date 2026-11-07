import SwiftUI
import XCTest
@testable import Cramless

/// What Today's day card says and offers on each kind of day: the chip (who the day is for and when), the title, one reason, the
/// rings (now and about where today takes it), one big button (or none, with a title that says what the day is), "Why these?", Cap
/// in the band in the right mood and the sky in the right state.
final class TodayHeroContentTests: XCTestCase {
    private let examID = UUID()

    private func summary(planned: Int = 15, reviews: Int = 18, new: Int = 6, weak: Int = 2, done: Int = 0, goal: Int = 15,
                         ready: Bool = true, due: Int = 0, days: Int = 0) -> TodaySummary {
        var s = TodaySummary()
        s.plannedMinutes = planned
        s.reviews = reviews
        s.newItems = new
        s.weakSpots = weak
        s.minutesDone = done
        s.minutesGoal = goal
        s.sessionReady = ready
        s.dueTotal = due
        s.catchUpDaysToClear = days
        return s
    }

    private func exam(readiness: Double = 0.42, scope: Int = 7) -> TodayExam {
        TodayExam(id: examID, title: "Chem 110 Quiz", courseName: "Chem 110", color: .tangerine,
                  date: Date(timeIntervalSince1970: 1_790_000_000), daysLeft: 2, readiness: readiness, delta: 0.05,
                  when: "Sun · in 2 days", itemsInScope: scope, deltaToday: 0.1)
    }

    private func focus(forecast: Double = 0.52, scope: Int = 7, topics: [String] = ["Limiting reagents", "Stoichiometry"],
                       weak: Int = 2, due: Int = 12, new: Int = 0) -> TodayFocus {
        TodayFocus(exam: exam(scope: scope), topics: topics, forecast: forecast, weakCount: weak, dueCount: due, newCount: new)
    }

    private func snapshot(_ hero: TodayHero, _ s: TodaySummary? = nil, answers: Int = 0, focus: TodayFocus? = nil,
                          eveHasWork: Bool = true) -> TodaySnapshot {
        var snap = TodaySnapshot(hero: hero, summary: s ?? summary(), streak: StreakState(), answersToday: answers,
                                 exams: [exam()], firstCourseID: nil, initials: "M")
        snap.focus = focus
        snap.eveHasWork = eveHasWork
        snap.eveTopics = ["Limiting reagents", "Stoichiometry"]
        return snap
    }

    private func content(_ hero: TodayHero, _ s: TodaySummary? = nil, answers: Int = 0, focus: TodayFocus? = nil,
                         eveHasWork: Bool = true) -> TodayHeroContent {
        TodayHeroContent.make(snapshot(hero, s, answers: answers, focus: focus, eveHasWork: eveHasWork))
    }

    private func text(_ r: LocalizedStringResource) -> String { String(localized: r) }

    // MARK: The days

    func testTheCardSaysTheWholeSessionOnlyWhenItHoldsMoreThanTheExams() {
        var whole = summary()
        whole.plannedQuestions = 39
        var mine = focus(weak: 0, due: 6, new: 1)
        mine.questions = 7
        XCTAssertEqual(content(.session, whole, focus: mine).reason,
                       "6 questions you're about to forget and 1 new one for this exam. About 39 questions fit in today's session.")
        whole.plannedQuestions = 7
        XCTAssertEqual(content(.session, whole, focus: mine).reason, "6 questions you're about to forget, and 1 new one.")
    }

    func testAPlanDayNamesItsExamTopicsAndWhereTodayTakesIt() throws {
        let c = content(.session, focus: focus())
        XCTAssertEqual(c.chip?.text, "For Chem 110 Quiz")
        XCTAssertEqual(c.chip?.tone, .exam)
        XCTAssertEqual(c.when, "Sun · in 2 days")
        XCTAssertEqual(c.title, "Limiting reagents and Stoichiometry")
        XCTAssertEqual(c.reason, "The weakest topics for this exam, plus 12 questions you're about to forget.")
        let rings = try XCTUnwrap(c.rings)
        XCTAssertEqual(rings.now, 0.42)
        XCTAssertEqual(rings.after, 0.52)
        XCTAssertEqual(rings.footnote, "Based on 7 questions so far.", "a quiz with few questions says so")
        let action = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(c.actions.count, 1)
        XCTAssertEqual(text(action.title), "Study · 15 min")
        XCTAssertEqual(text(try XCTUnwrap(action.spoken)), "Study for 15 minutes")
        XCTAssertTrue(action.prominent)
        XCTAssertEqual(action.kind, .session(.daily, minutes: nil, examID: nil), "it sizes itself")
        XCTAssertTrue(c.showsWhy)
        XCTAssertEqual(c.sky, .live)
        XCTAssertEqual(c.cap.pose, .stargaze)
        XCTAssertTrue(c.twinkles)
    }

    func testTheForecastShowsOnlyWhenTodayMovesItAPointAndTheFootnoteOnlyForAFewQuestions() throws {
        let flat = try XCTUnwrap(content(.session, focus: focus(forecast: 0.425, scope: 40)).rings)
        XCTAssertNil(flat.after, "under a point it is not a projection worth drawing")
        XCTAssertNil(flat.footnote)
        XCTAssertNotNil(try XCTUnwrap(content(.session, focus: focus(forecast: 0.43, scope: 15)).rings).after)
        XCTAssertNil(try XCTUnwrap(content(.session, focus: focus(scope: 15)).rings).footnote, "15 is enough")
    }

    func testMoreThanTwoTopicsAreCountedAndNeverChainedWithThen() {
        let c = content(.session, focus: focus(topics: ["Moles", "Stoichiometry", "Limiting reagents", "Yield"]))
        XCTAssertEqual(c.title, "Moles, Stoichiometry, and 2 more")
        XCTAssertFalse(c.title.contains("then"))
        XCTAssertEqual(content(.session, focus: focus(topics: [])).title, "Chem 110 Quiz", "no topics: the exam itself")
    }

    func testWithNoExamToNameTheCardHasNoChipAndNoRings() throws {
        var snap = snapshot(.session)
        snap.sessionTopics = ["Cell cycle", "Moles"]
        let c = TodayHeroContent.make(snap)
        XCTAssertNil(c.chip)
        XCTAssertNil(c.rings)
        XCTAssertNil(c.when)
        XCTAssertEqual(c.title, "Cell cycle and Moles")
        XCTAssertEqual(c.reason, "Your weakest topics, plus 18 questions you're about to forget.")
        XCTAssertEqual(text(try XCTUnwrap(c.actions.first).title), "Study · 15 min")
        XCTAssertTrue(c.showsWhy)
    }

    func testPartWayThroughTheGoalTheReasonSaysHowFarAndTheButtonHowMuchIsLeft() throws {
        let c = content(.session, summary(planned: 9, done: 6), focus: focus())
        XCTAssertEqual(text(try XCTUnwrap(c.actions.first).title), "Study · 9 min")
        XCTAssertTrue(c.reason.hasPrefix("6 of 15 minutes done. "), c.reason)
    }

    func testCatchUpIsTheSameCardWithTheBacklogAsItsReasonAndTheSameWord() throws {
        let c = content(.catchUp, summary(due: 142, days: 4), focus: focus())
        let action = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(text(action.title), "Study · 15 min", "one word for the day's job")
        XCTAssertEqual(action.request?.kind, .catchUp)
        XCTAssertEqual(c.chip?.text, "For Chem 110 Quiz")
        XCTAssertTrue(c.reason.hasPrefix("142 reviews piled up. At 15 minutes a day they're cleared in 4 days"), c.reason)
        XCTAssertTrue(content(.catchUp, summary(due: 1, days: 1)).reason.hasPrefix("1 review piled up. At 15 minutes a day they're cleared in a day"))
    }

    func testExamEveOffersTonightsTenMinutesOnItsWeakSpots() throws {
        let c = content(.examEve(examID))
        let action = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(text(action.title), "Tonight · 10 min")
        XCTAssertEqual(action.kind, .session(.examEve, minutes: nil, examID: examID))
        XCTAssertEqual(action.request?.examID, examID)
        XCTAssertEqual(c.chip?.text, "Chem 110 Quiz")
        XCTAssertEqual(c.chip?.symbol, "moon.stars.fill")
        XCTAssertEqual(c.title, "Tonight: weak spots only")
        XCTAssertEqual(c.reason, "10 minutes on Limiting reagents and Stoichiometry, then sleep. That's the whole plan tonight.")
        XCTAssertEqual(c.sky, .regionLit(examID))
        XCTAssertNil(c.rings)
        XCTAssertFalse(c.showsWhy)
        XCTAssertTrue(c.twinkles)
    }

    /// The button, its spoken words and the reason all say the session's own minutes.
    func testTheEveSaysItsSessionsOwnMinutes() throws {
        var snap = snapshot(.examEve(examID))
        snap.eveMinutes = 4
        var c = TodayHeroContent.make(snap)
        var action = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(text(action.title), "Tonight · 4 min")
        XCTAssertEqual(text(try XCTUnwrap(action.spoken)), "Tonight, 4 minutes")
        XCTAssertEqual(c.reason, "4 minutes on Limiting reagents and Stoichiometry, then sleep. That's the whole plan tonight.")
        snap.eveMinutes = 1
        snap.eveTopics = []
        c = TodayHeroContent.make(snap)
        action = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(text(action.title), "Tonight · 1 min")
        XCTAssertEqual(text(try XCTUnwrap(action.spoken)), "Tonight, 1 minute")
        XCTAssertEqual(c.reason, "1 minute on your weak spots, then sleep. That's the whole plan tonight.")
    }

    func testExamEveWithNothingWeakSaysSleepInsteadOfOfferingWork() throws {
        let c = content(.examEve(examID), eveHasWork: false)
        XCTAssertTrue(c.actions.isEmpty)
        XCTAssertEqual(c.title, "Nothing left to review tonight")
        XCTAssertEqual(c.cap, .asleep)
        XCTAssertFalse(c.twinkles, "the sky settles")
        XCTAssertEqual(c.sky, .regionLit(examID))
        XCTAssertEqual(c.reason, "Chem 110 Quiz is tomorrow. Sleep is part of studying.")
    }

    func testAfterTheEveSessionTheSkySettlesAndCapSleeps() throws {
        let c = content(.examEveDone(examID))
        XCTAssertTrue(c.actions.isEmpty)
        XCTAssertEqual(c.title, "That's enough for today")
        XCTAssertEqual(c.cap, .asleep)
        XCTAssertFalse(c.twinkles)
        XCTAssertTrue(c.reason.hasPrefix("Chem 110 Quiz is tomorrow at "), c.reason)
        XCTAssertTrue(c.reason.hasSuffix("Sleep is part of studying."))
    }

    func testOnceTheEveSessionIsDoneTheLastLookIsAQuietButton() throws {
        var snap = snapshot(.examEveDone(examID))
        snap.lastLookIdeas = 5
        let c = TodayHeroContent.make(snap)
        XCTAssertEqual(c.actions.count, 1)
        let action = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(action.kind, .lastLook(examID: examID))
        XCTAssertEqual(text(action.title), "Your last look")
        XCTAssertFalse(action.prominent, "Good night is the evening's big moment")
        XCTAssertEqual(action.spoken.map(text), "Your last look: 5 ideas, no quiz")
        XCTAssertNil(action.request)
        // Before tonight's session, and on a night with nothing to review, it isn't offered.
        var before = snapshot(.examEve(examID))
        before.lastLookIdeas = 5
        XCTAssertFalse(TodayHeroContent.make(before).actions.contains { $0.kind == .lastLook(examID: examID) })
        var rest = snapshot(.examEve(examID), eveHasWork: false)
        rest.lastLookIdeas = 5
        XCTAssertTrue(TodayHeroContent.make(rest).actions.isEmpty)
    }

    func testDoneIsBrightTonightWithTheExamItMovedAndAnOptionalExtra() throws {
        var snap = snapshot(.done, summary(done: 15), answers: 24)
        snap.doneExam = TodayDoneExam(title: "Chem 110 Quiz", readiness: 0.52, deltaToday: 0.10, daysLeft: 2)
        let c = TodayHeroContent.make(snap)
        XCTAssertEqual(c.chip?.text, "Done for today")
        XCTAssertEqual(c.chip?.tone, .done)
        XCTAssertEqual(c.when, "15 min · 24 answers")
        XCTAssertEqual(c.title, "Bright tonight")
        XCTAssertEqual(c.reason, "Back tomorrow. Your streak is safe.")
        let line = try XCTUnwrap(c.ringLine)
        XCTAssertEqual(line.title, "Chem 110 Quiz: 52% ready")
        XCTAssertEqual(line.detail, "+10% today · 2 days to go")
        let extra = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(c.actions.count, 1)
        XCTAssertEqual(text(extra.title), "5 more minutes")
        XCTAssertFalse(extra.prominent, "nothing is asked of you tonight")
        XCTAssertEqual(extra.kind, .session(.daily, minutes: 5, examID: nil))
        XCTAssertEqual(c.cap.pose, .proud)
        // With nothing left in the queue, the extra is a practice round; with no exam studied for, no ring line.
        let practice = content(.done, summary(done: 6, ready: false), answers: 6)
        XCTAssertEqual(try XCTUnwrap(practice.actions.first).kind, .session(.practice, minutes: 5, examID: nil))
        XCTAssertNil(practice.ringLine)
    }

    func testAllLitOffersAPracticeOnTheTopicRememberedLeast() throws {
        var snap = snapshot(.caughtUp, summary(ready: false))
        let topic = UUID(), course = UUID()
        snap.practice = TodayPractice(name: "Limiting reagents", topicID: topic, courseID: course)
        let c = TodayHeroContent.make(snap)
        XCTAssertEqual(c.title, "All lit")
        XCTAssertEqual(c.reason, "Nothing due right now. A short practice on Limiting reagents keeps it fresh.",
                       "the reason names the topic: the button may be too narrow to")
        let action = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(text(action.title), "Practice Limiting reagents · 5 min")
        XCTAssertEqual(text(try XCTUnwrap(action.shortTitle)), "Practice · 5 min")
        XCTAssertTrue(action.prominent)
        let request = try XCTUnwrap(action.request)
        XCTAssertEqual(request.kind, .practice)
        XCTAssertEqual(request.topicID, topic)
        XCTAssertEqual(request.courseID, course)
        XCTAssertEqual(request.minutes, 5)
        XCTAssertEqual(c.cap.pose, .relax)
        let noTopic = content(.caughtUp, summary(ready: false))
        XCTAssertEqual(text(try XCTUnwrap(noTopic.actions.first).title), "Practice · 5 min", "with no topic to name, a short practice")
        XCTAssertEqual(noTopic.reason, "Nothing due right now. A short practice keeps it fresh.")
    }

    func testWithNoQuestionsYetTheSkyIsUnlitOutlinesAndTheWayInIsASamplePage() throws {
        for (hero, title) in [(TodayHero.empty, "Let's make your first set"), (.noMaterial, "Add your first material")] {
            let c = content(hero)
            XCTAssertEqual(c.sky, .outline, "\(hero)")
            XCTAssertEqual(c.title, title)
            XCTAssertNil(c.chip)
            XCTAssertNil(c.rings)
            XCTAssertFalse(c.showsWhy)
            XCTAssertEqual(c.actions.map(\.kind), [.sample, .scan])
            XCTAssertEqual(c.actions.map(\.prominent), [true, false])
            XCTAssertEqual(text(c.actions[0].title), "Try a sample page")
            XCTAssertEqual(text(c.actions[1].title), "Scan a page")
            XCTAssertNil(c.actions[0].request)
            XCTAssertEqual(c.cap.pose, .stargaze, "Cap waits at his telescope with nothing to see yet")
        }
    }

    // MARK: Rules that hold on every day

    func testEveryDayHasAReasonAtMostOneBigButtonAndSomethingToSay() {
        let heroes: [TodayHero] = [.empty, .noMaterial, .session, .catchUp, .examEve(examID), .examEveDone(examID), .done, .caughtUp]
        for hero in heroes {
            for work in [true, false] {
                for f in [nil, focus()] {
                    let c = content(hero, summary(done: 15), answers: 3, focus: f, eveHasWork: work)
                    XCTAssertFalse(c.reason.isEmpty, "\(hero)")
                    XCTAssertFalse(c.title.isEmpty, "\(hero)")
                    XCTAssertLessThanOrEqual(c.actions.count, 2, "\(hero)")
                    XCTAssertLessThanOrEqual(c.actions.filter(\.prominent).count, 1, "\(hero): one big button")
                    XCTAssertTrue(CapPose.drawn.contains(c.cap.pose), "\(hero)")
                    for words in [c.title, c.reason] {
                        XCTAssertFalse(words.localizedCaseInsensitiveContains(" cards"), "\(hero): questions, not cards")
                        // "then sleep" on the eve is the plan for the night; between topics there is never a "then".
                        XCTAssertFalse(words.replacingOccurrences(of: ", then sleep", with: "").contains(" then "),
                                       "\(hero): the session interleaves; no 'then' between topics")
                    }
                    if let rings = c.rings {
                        XCTAssertGreaterThanOrEqual(rings.after ?? rings.now, rings.now, "\(hero): a forecast never goes down")
                    }
                }
            }
        }
    }

    func testEachRequestIsFreshAndCarriesWhatTheActionSays() throws {
        let action = TodayHeroContent.Action(kind: .session(.practice, minutes: 5, examID: nil), title: "x", systemImage: "x", prominent: false)
        let a = try XCTUnwrap(action.request), b = try XCTUnwrap(action.request)
        XCTAssertNotEqual(a.id, b.id, "each start is its own session")
        XCTAssertEqual(a.kind, .practice)
        XCTAssertEqual(a.minutes, 5)
    }
}

/// Today's snapshot carries the sky.
@MainActor
final class TodaySkySnapshotTests: XCTestCase {
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

    func testANewPersonHasNoStarsAndGetsTheOutlineSky() {
        let snapshot = TodaySnapshot.make(app: app)
        XCTAssertTrue(snapshot.sky.isEmpty)
        XCTAssertEqual(TodayHeroContent.make(snapshot).sky, .outline)
    }

    func testEveryActiveItemIsAStarInTheHeroSky() {
        let course = Course(name: "Bio 101", now: clock.now)
        app.context.insert(course)
        for i in 0..<7 {
            let item = StudyItem(course: course, kind: .flashcard, status: .active, origin: .person, prompt: "Q\(i)",
                                 answer: "A", now: clock.now)
            if i < 4 {
                item.memory = MemoryState(state: .review, stability: 30, difficulty: 5, due: clock.now.addingTimeInterval(86_400),
                                          lastReview: clock.now.addingTimeInterval(-2 * 86_400), reps: 3)
            }
            app.context.insert(item)
            course.items.append(item)
        }
        app.save()
        let snapshot = TodaySnapshot.make(app: app)
        XCTAssertEqual(snapshot.sky.starCount, 7)
        XCTAssertEqual(snapshot.sky.hollowCount, 3)
        XCTAssertEqual(snapshot.sky, TodaySnapshot.make(app: app).sky, "the same data draws the same sky")
        XCTAssertEqual(TodayHeroContent.make(snapshot).sky, .live)
    }
}
