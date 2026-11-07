import XCTest
@testable import Cramless

/// The Widgets lane's services: WidgetSync's writes and reloads, the exam-week activity plan, read-aloud text and
/// the age-band rules.
@MainActor
final class WidgetLaneServiceTests: XCTestCase {
    private let cal = WidgetTestSupport.calendar
    private let now = WidgetTestSupport.now
    private var previousLive: AppModel?

    override func setUp() async throws {
        previousLive = AppModel.live
    }

    override func tearDown() async throws {
        AppModel.live = previousLive
    }

    // MARK: WidgetSync

    func testRefreshWritesTheSnapshotAndReloadsOnlyOnChange() async throws {
        let app = WidgetTestSupport.makeApp()
        WidgetTestSupport.addExam(to: app, title: "Bio 101 Midterm", course: "Bio 101", days: 23)
        let folder = try WidgetTestSupport.temporaryFolder()
        let sync = WidgetSync(app: app)
        sync.store = WidgetSnapshotStore(directory: folder)
        sync.reloadWindow = .seconds(1)
        var reloads = 0
        sync.reloadTimelines = { reloads += 1 }

        sync.refresh()
        XCTAssertEqual(sync.store.read()?.nextExam?.title, "Bio 101 Midterm")
        XCTAssertEqual(reloads, 1, "the first write reloads at once")

        sync.refresh()
        XCTAssertEqual(reloads, 1, "nothing changed: no write, no reload")

        WidgetTestSupport.addExam(to: app, title: "Chem 110 Quiz", course: "Chem 110", days: 2)
        sync.refresh()
        XCTAssertEqual(sync.store.read()?.nextExam?.title, "Chem 110 Quiz")
        XCTAssertEqual(reloads, 1, "a second change inside the window waits")
        WidgetTestSupport.addExam(to: app, title: "AP Psych Exam", course: "AP Psychology", days: 196)
        sync.refresh()
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertEqual(reloads, 2, "the changes inside the window reload once, at its end")
        XCTAssertEqual(sync.store.read()?.exams.count, 3)
    }

    func testANewDayAlwaysWrites() {
        let app = WidgetTestSupport.makeApp()
        let sync = WidgetSync(app: app)
        let today = app.makeWidgetSnapshot()
        XCTAssertTrue(sync.needsWrite(today, calendar: cal))
        sync.store = WidgetSnapshotStore(directory: nil)
        sync.refresh()
        XCTAssertNil(sync.lastWritten, "no App Group: nothing recorded as written")
    }

    func testNeedsWriteComparesContentNotTime() throws {
        let app = WidgetTestSupport.makeApp()
        let sync = WidgetSync(app: app)
        sync.store = WidgetSnapshotStore(directory: try WidgetTestSupport.temporaryFolder())
        sync.reloadTimelines = {}
        sync.refresh()
        var later = try XCTUnwrap(sync.lastWritten)
        later.generatedAt = cal.date(byAdding: .hour, value: 2, to: later.generatedAt)!
        XCTAssertFalse(sync.needsWrite(later, calendar: cal))
        later.generatedAt = cal.date(byAdding: .day, value: 1, to: later.generatedAt)!
        XCTAssertTrue(sync.needsWrite(later, calendar: cal), "a new day: the widgets must roll from today's write")
    }

    // MARK: Exam week

    func testTheExamWeekActivityFollowsTheNextExamInItsLastWeek() throws {
        var s = WidgetSnapshot.sample(now: now, calendar: cal)
        XCTAssertNil(ExamWeekPlan.focus(in: s, now: now, calendar: cal), "23 days out: no activity")
        s.exams[0].date = WidgetTestSupport.date(2026, 10, 29, 9)   // 7 days
        let focus = try XCTUnwrap(ExamWeekPlan.focus(in: s, now: now, calendar: cal))
        XCTAssertEqual(focus.title, "Bio 101 Midterm")
        let state = ExamWeekPlan.state(for: focus, in: s, now: now, calendar: cal)
        XCTAssertEqual(state.daysLeft, 7)
        XCTAssertEqual(state.readiness, 0.64)
        XCTAssertEqual(state.todayMinutes, 15)
        XCTAssertFalse(state.studiedToday)
        XCTAssertNil(ExamWeekPlan.focus(in: s, now: WidgetTestSupport.date(2026, 10, 29, 12, 1), calendar: cal),
                     "ended three hours after it starts")
        s.exams[0].date = WidgetTestSupport.date(2026, 10, 30, 9)
        XCTAssertNil(ExamWeekPlan.focus(in: s, now: now, calendar: cal), "8 days out")
        XCTAssertEqual(ExamWeekPlan.attributes(for: focus).examID, focus.id)
    }

    func testExamWeekCopyStaysCalm() {
        var state = ExamWeekAttributes.ContentState.sample
        XCTAssertEqual(ExamWeekCopy.today(state: state, courseName: "Bio 101"), "15 minutes today keeps you on track.")
        state.studiedToday = true
        XCTAssertEqual(ExamWeekCopy.today(state: state, courseName: "Bio 101"), "Today's session is done.")
        state.daysLeft = 1
        XCTAssertEqual(ExamWeekCopy.today(state: state, courseName: "Bio 101"), "Weak spots tonight, then sleep.")
        state.daysLeft = 0
        XCTAssertEqual(ExamWeekCopy.today(state: state, courseName: "Bio 101"), "Today. You've prepared for this.")
    }

    func testSessionActivityCopy() {
        let attributes = StudySessionAttributes.sample(now: now)
        XCTAssertEqual(SessionActivityCopy.detail(attributes: attributes, state: .sample, isStale: false),
                       "Question 10 of 18 · 7 correct")
        XCTAssertEqual(SessionActivityCopy.detail(attributes: attributes, state: .sampleFinished, isStale: false),
                       "18 answered · 15 correct")
        XCTAssertEqual(StudySessionAttributes.ContentState.sample.progress(total: 18), 0.5)
        XCTAssertEqual(StudySessionAttributes.ContentState(answered: 30, correct: 3).progress(total: 18), 1)
    }

    func testLiveActivitiesStayOffInTests() {
        let app = WidgetTestSupport.makeApp()
        XCTAssertFalse(app.liveActivities.isEnabled)
        app.liveActivities.startSession(title: "Today's session", total: 18)
        XCTAssertFalse(app.liveActivities.hasSession)
        app.liveActivities.update(answered: 1, correct: 1, topic: "Meiosis")
        app.liveActivities.end()
    }

    // MARK: Read aloud

    func testQuestionsReadTheWayTheyShow() {
        XCTAssertEqual(ReadAloud.spokenQuestion(kind: .mcq, prompt: "What does anaphase I separate?",
                                                choices: ["Homologous pairs", "Sister chromatids"], cloze: nil),
                       "What does anaphase I separate? A: Homologous pairs. B: Sister chromatids.")
        XCTAssertEqual(ReadAloud.spokenQuestion(kind: .cloze, prompt: "Fill in the word", choices: [],
                                                cloze: ClozeSpec(text: "In {{osmosis}}, water moves from {{dilute}} to concentrated.")),
                       "Fill in the word. In blank, water moves from blank to concentrated.")
        XCTAssertEqual(ReadAloud.spokenQuestion(kind: .flashcard, prompt: "la biblioteca", choices: [], cloze: nil),
                       "la biblioteca.")
        XCTAssertEqual(ReadAloud.spokenQuestion(kind: .recall, prompt: "  Why does spacing beat cramming?  ",
                                                choices: [], cloze: nil),
                       "Why does spacing beat cramming?")
    }

    func testReadAloudRespectsTheSetting() {
        let app = WidgetTestSupport.makeApp()
        app.settings.readAloud = false
        app.readAloud("What is diffusion?")
        XCTAssertFalse(ReadAloud.shared.isSpeaking, "off unless the person turned it on")
        ReadAloud.shared.stop()
    }

    // MARK: Age range

    func testAgeBands() {
        XCTAssertEqual(AgeRange.band(lowerBound: nil, upperBound: 12), .under13)
        XCTAssertEqual(AgeRange.band(lowerBound: 13, upperBound: 17), .teen)
        XCTAssertEqual(AgeRange.band(lowerBound: 18, upperBound: nil), .adult)
        XCTAssertEqual(AgeRange.band(lowerBound: nil, upperBound: 17), .teen, "a minor of unknown age is teen-safe")
        XCTAssertEqual(AgeRange.band(lowerBound: nil, upperBound: nil), .unknown)
        XCTAssertEqual(AgeRange.fallback(level: .highSchool), .teen)
        XCTAssertEqual(AgeRange.fallback(level: .college), .adult)
        XCTAssertEqual(AgeRange.fallback(level: nil), .notShared)
        XCTAssertEqual(AgeRange.resolved(declared: .teen, current: .adult, level: .college), .teen, "a shared range wins")
        XCTAssertEqual(AgeRange.resolved(declared: nil, current: .adult, level: .highSchool), .adult,
                       "a band already shared isn't overwritten by a guess")
        XCTAssertEqual(AgeRange.resolved(declared: nil, current: .unknown, level: .highSchool), .teen)
    }
}
