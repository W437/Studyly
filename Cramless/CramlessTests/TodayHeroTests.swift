import SwiftUI
import XCTest
@testable import Cramless

/// What Today's day card says and offers on each kind of day: the chip (the exam and its day, which opens it), one ring with its
/// readiness, the title, at most one short line, one big button (or none, with a title that says what the day is), "Why these?", Cap
/// in the band in the right mood and the sky in the right state.
final class TodayHeroContentTests: XCTestCase {
    private let examID = UUID()

    private func summary(planned: Int = 15, questions: Int = 7, reviews: Int = 18, new: Int = 6, weak: Int = 2, done: Int = 0,
                         goal: Int = 15, ready: Bool = true, due: Int = 0, days: Int = 0) -> TodaySummary {
        var s = TodaySummary()
        s.plannedMinutes = planned
        s.plannedQuestions = questions
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

    private func exam(readiness: Double = 0.42) -> TodayExam {
        TodayExam(id: examID, title: "Chem 110 Quiz", courseName: "Chem 110", date: Date(timeIntervalSince1970: 1_790_000_000), daysLeft: 2,
                  readiness: readiness, day: "Tue", daySpoken: "Tuesday")
    }

    private func focus(topics: [String] = ["Limiting reagents", "Stoichiometry"], questions: Int = 7) -> TodayFocus {
        TodayFocus(exam: exam(), topics: topics, questions: questions)
    }

    private func snapshot(_ hero: TodayHero, _ s: TodaySummary? = nil, focus: TodayFocus? = nil, eveHasWork: Bool = true,
                          exams: [TodayExam]? = nil) -> TodaySnapshot {
        var snap = TodaySnapshot(hero: hero, summary: s ?? summary(), streak: StreakState(), answersToday: 0,
                                 exams: exams ?? [exam()], firstCourseID: nil, initials: "M")
        snap.focus = focus
        snap.eveHasWork = eveHasWork
        snap.eveTopics = ["Limiting reagents", "Stoichiometry"]
        return snap
    }

    private func content(_ hero: TodayHero, _ s: TodaySummary? = nil, focus: TodayFocus? = nil, eveHasWork: Bool = true) -> TodayHeroContent {
        TodayHeroContent.make(snapshot(hero, s, focus: focus, eveHasWork: eveHasWork))
    }

    private func text(_ r: LocalizedStringResource) -> String { String(localized: r) }

    /// The words above the button: the chip, the ring's words, the title and the line.
    private func wordsAboveTheButton(_ c: TodayHeroContent) -> Int {
        let parts = [c.chip?.text, c.readiness.map(TodayCopy.ready), c.title, c.line].compactMap { $0 }
        return parts.joined(separator: " ").split(whereSeparator: { $0 == " " || $0 == "·" }).count
    }

    // MARK: The days

    func testAPlanDayIsTheChipTheTitleOneRingAndTheButton() throws {
        let c = content(.session, focus: focus())
        let chip = try XCTUnwrap(c.chip)
        XCTAssertEqual(chip.text, "Chem 110 Quiz · Tue", "no \"For\"")
        XCTAssertEqual(chip.spoken, "Chem 110 Quiz, Tuesday")
        XCTAssertEqual(chip.tone, .exam)
        XCTAssertEqual(chip.link, .exam(examID), "the chip opens the exam")
        XCTAssertEqual(c.readiness, 0.42, "one ring: readiness now")
        XCTAssertEqual(TodayCopy.ready(0.42), "42% ready")
        XCTAssertEqual(c.title, "Limiting reagents and Stoichiometry")
        XCTAssertNil(c.line, "no paragraph: the reasons are in Why these?")
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
        XCTAssertLessThanOrEqual(wordsAboveTheButton(c), 12, "a dozen words at most to read before Study")
    }

    /// An exam a few days off with a fifth of the session doesn't claim the title: the courses do, soonest exam first. The session is
    /// the same.
    func testWhenTheExamHasLessThanHalfTheSessionTheTitleNamesTheCourses() throws {
        var snap = snapshot(.session, summary(questions: 42), focus: focus(questions: 7))
        snap.sessionCourses = ["Chem 110", "Bio 101", "AP Psychology"]
        var c = TodayHeroContent.make(snap)
        XCTAssertEqual(c.title, "Chem 110, Bio 101, and AP Psychology")
        XCTAssertEqual(c.chip?.text, "Chem 110 Quiz · Tue")
        XCTAssertEqual(c.readiness, 0.42)
        XCTAssertEqual(try XCTUnwrap(c.actions.first).kind, .session(.daily, minutes: nil, examID: nil))

        // Half or more: its topics.
        snap.focus = focus(questions: 21)
        XCTAssertEqual(TodayHeroContent.make(snap).title, "Limiting reagents and Stoichiometry")
        // Four courses: three named, the rest counted.
        snap.focus = focus(questions: 7)
        snap.sessionCourses = ["Chem 110", "Bio 101", "AP Psychology", "Spanish II"]
        XCTAssertEqual(TodayHeroContent.make(snap).title, "Chem 110, Bio 101, AP Psychology, and 1 more")
        // One course only (two exams in it): its topics say more than its name.
        snap.sessionCourses = ["Chem 110"]
        c = TodayHeroContent.make(snap)
        XCTAssertEqual(c.title, "Limiting reagents and Stoichiometry")
    }

    func testMoreThanTwoTopicsAreCountedAndNeverChainedWithThen() {
        let c = content(.session, focus: focus(topics: ["Moles", "Stoichiometry", "Limiting reagents", "Yield"]))
        XCTAssertEqual(c.title, "Moles, Stoichiometry, and 2 more")
        XCTAssertFalse(c.title.contains("then"))
        XCTAssertEqual(content(.session, focus: focus(topics: [])).title, "Chem 110 Quiz", "no topics: the exam itself")
    }

    func testWithNoExamTheSessionServesTheCardHasNoChipAndNoRing() throws {
        var snap = snapshot(.session)
        snap.sessionTopics = ["Cell cycle", "Moles"]
        let c = TodayHeroContent.make(snap)
        XCTAssertNil(c.chip, "exams exist, the session serves none of them")
        XCTAssertNil(c.readiness)
        XCTAssertNil(c.line)
        XCTAssertEqual(c.title, "Cell cycle and Moles")
        XCTAssertEqual(text(try XCTUnwrap(c.actions.first).title), "Study · 15 min")
        XCTAssertTrue(c.showsWhy)
    }

    func testWithNoExamAtAllTheChipOffersOne() throws {
        var snap = snapshot(.session, exams: [])
        snap.sessionTopics = ["Cell cycle"]
        let chip = try XCTUnwrap(TodayHeroContent.make(snap).chip)
        XCTAssertEqual(chip.text, "Add exam")
        XCTAssertEqual(chip.link, .addExam)
        XCTAssertEqual(chip.tone, .add)
        XCTAssertEqual(TodayHeroContent.make(snapshot(.caughtUp, summary(ready: false), exams: [])).chip?.link, .addExam)
        XCTAssertNil(TodayHeroContent.make(snapshot(.noMaterial, exams: [])).chip, "first the material")
    }

    func testPartWayThroughTheGoalTheLineSaysHowFarAndTheButtonHowMuchIsLeft() throws {
        let c = content(.session, summary(planned: 9, done: 6), focus: focus())
        XCTAssertEqual(text(try XCTUnwrap(c.actions.first).title), "Study · 9 min")
        XCTAssertEqual(c.line, "6 of 15 minutes done.")
    }

    func testCatchUpIsTheSameCardWithTheBacklogAsItsLine() throws {
        let c = content(.catchUp, summary(due: 142, days: 4), focus: focus())
        let action = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(text(action.title), "Study · 15 min", "one word for the day's job")
        XCTAssertEqual(action.request?.kind, .catchUp)
        XCTAssertEqual(c.chip?.text, "Chem 110 Quiz · Tue")
        XCTAssertEqual(c.line, "Catching up: about 4 days at 15 minutes a day.", "no second count beside the band's")
        XCTAssertEqual(content(.catchUp, summary(due: 1, days: 1)).line, "Catching up: about a day at 15 minutes a day.")
    }

    func testTheNightBeforeOffersTonightsMinutesOnItsWeakSpots() throws {
        let c = content(.examEve(examID))
        let action = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(text(action.title), "Tonight · 10 min")
        XCTAssertEqual(action.kind, .session(.examEve, minutes: nil, examID: examID))
        XCTAssertEqual(action.request?.examID, examID)
        XCTAssertEqual(c.chip?.text, "Chem 110 Quiz · Tue")
        XCTAssertEqual(c.chip?.symbol, "moon.stars.fill")
        XCTAssertEqual(c.chip?.link, .exam(examID))
        XCTAssertEqual(c.title, "Tonight: weak spots only")
        XCTAssertEqual(c.line, "Limiting reagents and Stoichiometry, then sleep.")
        XCTAssertEqual(c.sky, .regionLit(examID))
        XCTAssertNil(c.readiness, "the night before is calm: no number")
        XCTAssertFalse(c.showsWhy)
        XCTAssertTrue(c.twinkles)
    }

    /// The button and its spoken words say the session's own minutes.
    func testTheNightBeforeSaysItsSessionsOwnMinutes() throws {
        var snap = snapshot(.examEve(examID))
        snap.eveMinutes = 4
        var action = try XCTUnwrap(TodayHeroContent.make(snap).actions.first)
        XCTAssertEqual(text(action.title), "Tonight · 4 min")
        XCTAssertEqual(text(try XCTUnwrap(action.spoken)), "Tonight, 4 minutes")
        snap.eveMinutes = 1
        snap.eveTopics = []
        let c = TodayHeroContent.make(snap)
        action = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(text(action.title), "Tonight · 1 min")
        XCTAssertEqual(text(try XCTUnwrap(action.spoken)), "Tonight, 1 minute")
        XCTAssertEqual(c.line, "Then sleep. That's the whole plan tonight.")
    }

    func testTwoExamsSharingTheEveningAreBothOnTheChip() throws {
        var snap = snapshot(.examEve(examID))
        var bio = exam()
        bio.id = UUID()
        bio.title = "Bio 101 Midterm"
        snap.exams = [exam(), bio]
        snap.summary.examEveExamIDs = [examID, bio.id]
        XCTAssertEqual(TodayHeroContent.make(snap).chip?.text, "Chem 110 Quiz and Bio 101 Midterm · Tomorrow")
    }

    func testTheNightBeforeWithNothingWeakSaysSleepInsteadOfOfferingWork() throws {
        let c = content(.examEve(examID), eveHasWork: false)
        XCTAssertTrue(c.actions.isEmpty)
        XCTAssertEqual(c.title, "Nothing left to review tonight")
        XCTAssertEqual(c.cap, .asleep)
        XCTAssertFalse(c.twinkles, "the sky settles")
        XCTAssertEqual(c.sky, .regionLit(examID))
        XCTAssertEqual(c.line, "Sleep is part of studying.", "the chip already says when")
    }

    func testAfterTheNightBeforesSessionTheSkySettlesAndCapSleeps() throws {
        let c = content(.examEveDone(examID))
        XCTAssertTrue(c.actions.isEmpty)
        XCTAssertEqual(c.title, "That's enough for today")
        XCTAssertEqual(c.cap, .asleep)
        XCTAssertFalse(c.twinkles)
        XCTAssertEqual(c.line, "Sleep is part of studying.")
    }

    func testOnceTheNightBeforesSessionIsDoneTheLastLookIsAQuietButton() throws {
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

    func testDoneNamesTheExamItMovedAndOffersAnOptionalExtra() throws {
        var snap = snapshot(.done, summary(done: 15))
        snap.doneExam = exam(readiness: 0.52)
        let c = TodayHeroContent.make(snap)
        XCTAssertEqual(c.chip?.text, "Chem 110 Quiz · Tue")
        XCTAssertEqual(c.readiness, 0.52)
        XCTAssertEqual(c.title, "Done for today")
        XCTAssertEqual(c.line, "Back tomorrow. Your streak is safe.")
        let extra = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(c.actions.count, 1)
        XCTAssertEqual(text(extra.title), "5 more minutes")
        XCTAssertFalse(extra.prominent, "nothing is asked of you tonight")
        XCTAssertEqual(extra.kind, .session(.daily, minutes: 5, examID: nil))
        XCTAssertEqual(c.cap.pose, .proud)
        // With nothing left in the queue, the extra is a practice round; with no exam studied for, no chip and no ring.
        let practice = content(.done, summary(done: 6, ready: false))
        XCTAssertEqual(try XCTUnwrap(practice.actions.first).kind, .session(.practice, minutes: 5, examID: nil))
        XCTAssertNil(practice.chip)
        XCTAssertNil(practice.readiness)
        // Quiet mode says nothing about the streak.
        var quiet = snapshot(.done, summary(done: 15))
        quiet.quiet = true
        XCTAssertEqual(TodayHeroContent.make(quiet).line, "Back tomorrow.")
    }

    func testAllLitOffersAPracticeOnTheTopicRememberedLeast() throws {
        var snap = snapshot(.caughtUp, summary(ready: false))
        let topic = UUID(), course = UUID()
        snap.practice = TodayPractice(name: "Limiting reagents", topicID: topic, courseID: course)
        let c = TodayHeroContent.make(snap)
        XCTAssertEqual(c.title, "All lit")
        XCTAssertEqual(c.line, "Nothing to review right now.")
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
    }

    func testWithNoQuestionsYetTheSkyIsUnlitOutlinesAndTheWayInIsASamplePage() throws {
        for (hero, title, line) in [(TodayHero.empty, "Let's make your first set", "Capling turns a page from class into questions."),
                                    (.noMaterial, "Add your first material", "One page from class is enough to start.")] {
            let c = content(hero)
            XCTAssertEqual(c.sky, .outline, "\(hero)")
            XCTAssertEqual(c.title, title)
            XCTAssertEqual(c.line, line)
            XCTAssertNil(c.chip)
            XCTAssertNil(c.readiness)
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

    func testEveryDayHasATitleAtMostOneShortLineOneBigButtonAndOneNumber() {
        let heroes: [TodayHero] = [.empty, .noMaterial, .session, .catchUp, .examEve(examID), .examEveDone(examID), .done, .caughtUp]
        for hero in heroes {
            for work in [true, false] {
                for f in [nil, focus()] {
                    let c = content(hero, summary(done: 15, due: 142, days: 4), focus: f, eveHasWork: work)
                    XCTAssertFalse(c.title.isEmpty, "\(hero)")
                    XCTAssertLessThanOrEqual(c.actions.count, 2, "\(hero)")
                    XCTAssertLessThanOrEqual(c.actions.filter(\.prominent).count, 1, "\(hero): one big button")
                    XCTAssertTrue(CapPose.drawn.contains(c.cap.pose), "\(hero)")
                    if let line = c.line {
                        XCTAssertLessThanOrEqual(line.split(separator: " ").count, 12, "\(hero): a short line: \(line)")
                    }
                    for words in [c.title, c.line ?? "", c.chip?.text ?? ""] {
                        XCTAssertFalse(words.localizedCaseInsensitiveContains(" cards"), "\(hero): questions, not cards")
                        XCTAssertFalse(words.contains("%"), "\(hero): the ring's words are the one number")
                        XCTAssertFalse(words.contains("forget"), "\(hero): to review")
                        XCTAssertFalse(words.hasPrefix("For "), "\(hero): the chip names the exam")
                        // "then sleep" on the night before is the plan for the night; between topics there is never a "then".
                        XCTAssertFalse(words.replacingOccurrences(of: ", then sleep", with: "").contains(" then "),
                                       "\(hero): the session interleaves; no 'then' between topics")
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
