import SwiftUI
import XCTest
@testable import Cramless

/// What Today's sky hero says and offers on each kind of day: one button (or none, with a headline in its place),
/// one caption, Cap on the horizon in the right mood, and the sky in the right state.
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

    private func exam() -> TodayExam {
        TodayExam(id: examID, title: "Chem quiz", courseName: "Chem 110", color: .tangerine,
                  date: Date(timeIntervalSince1970: 1_790_000_000), daysLeft: 1, readiness: 0.6, delta: 0.05)
    }

    private func content(_ hero: TodayHero, _ s: TodaySummary? = nil, answers: Int = 0, eveHasWork: Bool = true) -> TodayHeroContent {
        TodayHeroContent.make(hero: hero, summary: s ?? summary(), answersToday: answers,
                              exam: { $0 == self.examID ? self.exam() : nil }, eveHasWork: eveHasWork)
    }

    private func text(_ r: LocalizedStringResource) -> String { String(localized: r) }

    // MARK: The days

    func testASessionDayIsOneButtonToRelightAndWhatsInIt() throws {
        let c = content(.session)
        let action = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(c.actions.count, 1)
        XCTAssertEqual(text(action.title), "Relight · 15 min")
        XCTAssertTrue(action.prominent)
        XCTAssertEqual(action.kind, .session(.daily, minutes: nil, examID: nil), "it sizes itself")
        XCTAssertEqual(action.request?.kind, .daily)
        XCTAssertNil(c.headline, "the button is the headline")
        XCTAssertEqual(text(c.caption), "18\u{00A0}reviews\u{00A0}· 6\u{00A0}new\u{00A0}· 2\u{00A0}weak\u{00A0}spots")
        XCTAssertEqual(c.sky, .live)
        XCTAssertEqual(c.cap.pose, .stargaze)
        XCTAssertTrue(c.twinkles)
    }

    func testPartWayThroughTheGoalTheCaptionSaysHowFarAndTheButtonHowMuchIsLeft() throws {
        let c = content(.session, summary(planned: 9, done: 6))
        XCTAssertEqual(text(try XCTUnwrap(c.actions.first).title), "Relight · 9 min")
        XCTAssertTrue(text(c.caption).hasPrefix("6 of 15 minutes done · "), text(c.caption))
    }

    func testCatchUpIsHonestAboutTheBacklogAndKindAboutThePace() throws {
        let c = content(.catchUp, summary(due: 142, days: 4))
        let action = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(text(action.title), "Catch up · 15 min")
        XCTAssertEqual(action.request?.kind, .catchUp)
        XCTAssertTrue(text(c.caption).hasPrefix("142 reviews piled up. At 15 minutes a day they're cleared in 4 days"), text(c.caption))
        XCTAssertTrue(text(content(.catchUp, summary(due: 1, days: 1)).caption).hasPrefix("1 review piled up. At 15 minutes a day they're cleared in a day"))
    }

    func testExamEveOffersTonightsTenMinutesWithTheExamsRegionLit() throws {
        let c = content(.examEve(examID))
        let action = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(text(action.title), "Tonight · 10 min")
        XCTAssertEqual(action.kind, .session(.examEve, minutes: nil, examID: examID))
        XCTAssertEqual(action.request?.examID, examID)
        XCTAssertEqual(c.sky, .regionLit(examID))
        XCTAssertTrue(text(c.caption).hasPrefix("Chem quiz is tomorrow. 10 minutes on your weak spots, then sleep."), text(c.caption))
        XCTAssertTrue(c.twinkles)
    }

    func testExamEveWithNothingWeakSaysSleepInsteadOfOfferingWork() throws {
        let c = content(.examEve(examID), eveHasWork: false)
        XCTAssertTrue(c.actions.isEmpty)
        XCTAssertEqual(text(try XCTUnwrap(c.headline)), "Nothing left to review tonight")
        XCTAssertEqual(c.cap, .asleep)
        XCTAssertFalse(c.twinkles, "the sky settles")
        XCTAssertEqual(c.sky, .regionLit(examID))
        XCTAssertTrue(text(c.caption).contains("Sleep is part of studying."))
    }

    func testAfterTheEveSessionTheSkySettlesAndCapSleeps() throws {
        let c = content(.examEveDone(examID))
        XCTAssertTrue(c.actions.isEmpty)
        XCTAssertEqual(text(try XCTUnwrap(c.headline)), "That's enough for tonight")
        XCTAssertEqual(c.cap, .asleep)
        XCTAssertFalse(c.twinkles)
        XCTAssertTrue(text(c.caption).hasPrefix("Chem quiz is tomorrow at "), text(c.caption))
        XCTAssertTrue(text(c.caption).hasSuffix("Sleep is part of studying."))
    }

    func testDoneIsBrightTonightWithAnOptionalExtra() throws {
        let c = content(.done, summary(done: 15), answers: 24)
        XCTAssertEqual(text(try XCTUnwrap(c.headline)), "Bright tonight")
        let extra = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(c.actions.count, 1)
        XCTAssertEqual(text(extra.title), "5 more minutes")
        XCTAssertFalse(extra.prominent, "nothing is asked of you tonight")
        XCTAssertEqual(extra.kind, .session(.daily, minutes: 5, examID: nil))
        XCTAssertEqual(text(c.caption), "15 minutes, 24 answers. Back tomorrow. Your streak is safe.")
        XCTAssertEqual(c.cap.pose, .proud)
        // With nothing left in the queue, the extra is a practice round.
        XCTAssertEqual(try XCTUnwrap(content(.done, summary(done: 6, ready: false), answers: 6).actions.first).kind,
                       .session(.practice, minutes: 5, examID: nil))
    }

    func testCaughtUpIsAllLitWithAShortPractice() throws {
        let c = content(.caughtUp, summary(ready: false))
        XCTAssertEqual(text(try XCTUnwrap(c.headline)), "All lit")
        let extra = try XCTUnwrap(c.actions.first)
        XCTAssertEqual(text(extra.title), "Practice 5 minutes")
        XCTAssertEqual(extra.kind, .session(.practice, minutes: 5, examID: nil))
        XCTAssertFalse(extra.prominent)
        XCTAssertEqual(c.cap.pose, .relax)
    }

    func testWithNoQuestionsYetTheSkyIsUnlitOutlinesAndTheWayInIsASamplePage() throws {
        for (hero, headline) in [(TodayHero.empty, "Let's make your first set"), (.noMaterial, "Add your first material")] {
            let c = content(hero)
            XCTAssertEqual(c.sky, .outline, "\(hero)")
            XCTAssertEqual(text(try XCTUnwrap(c.headline)), headline)
            XCTAssertEqual(c.actions.map(\.kind), [.sample, .scan])
            XCTAssertEqual(c.actions.map(\.prominent), [true, false])
            XCTAssertEqual(text(c.actions[0].title), "Try a sample page")
            XCTAssertEqual(text(c.actions[1].title), "Scan a page")
            XCTAssertNil(c.actions[0].request)
            XCTAssertEqual(c.cap.pose, .stargaze, "Cap waits at his telescope with nothing to see yet")
        }
    }

    // MARK: Words

    func testCountedCopyReadsRightInTheSingular() {
        XCTAssertEqual(TodayHeroContent.doneLine(minutes: 1, answers: 1), "1 minute, 1 answer. Back tomorrow. Your streak is safe.")
        XCTAssertEqual(TodayHeroContent.doneLine(minutes: 15, answers: 24), "15 minutes, 24 answers. Back tomorrow. Your streak is safe.")
        XCTAssertEqual(TodayHeroContent.doneLine(minutes: 15, answers: 1), "15 minutes, 1 answer. Back tomorrow. Your streak is safe.")
        XCTAssertTrue(TodayHeroContent.sessionLine(summary(done: 1, goal: 1)).hasPrefix("1 of 1 minute done · "))
        XCTAssertTrue(TodayHeroContent.sessionLine(summary(done: 6, goal: 15)).hasPrefix("6 of 15 minutes done · "))
        XCTAssertEqual(TodayHeroContent.sessionLine(summary(done: 0)), SessionCopy.sessionMix(reviews: 18, new: 6, weak: 2),
                       "before anything is done it is just the mix")
        XCTAssertTrue(TodayHeroContent.catchUpLine(summary(due: 2, days: 0)).hasPrefix("2 reviews piled up. At 15 minutes a day they're cleared in a day,"),
                      "a backlog is never cleared in no days")
    }

    // MARK: Rules that hold on every day

    func testEveryDayHasOneCaptionAtMostOneBigButtonAndSomethingToSay() {
        let heroes: [TodayHero] = [.empty, .noMaterial, .session, .catchUp, .examEve(examID), .examEveDone(examID), .done, .caughtUp]
        for hero in heroes {
            for work in [true, false] {
                let c = content(hero, summary(done: 15), answers: 3, eveHasWork: work)
                XCTAssertFalse(text(c.caption).isEmpty, "\(hero)")
                XCTAssertLessThanOrEqual(c.actions.count, 2, "\(hero)")
                XCTAssertLessThanOrEqual(c.actions.filter(\.prominent).count, 1, "\(hero): one big button")
                if !c.actions.contains(where: \.prominent) {
                    XCTAssertNotNil(c.headline, "\(hero): with no big button the day still says what it is")
                }
                XCTAssertTrue(CapPose.drawn.contains(c.cap.pose), "\(hero)")
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
