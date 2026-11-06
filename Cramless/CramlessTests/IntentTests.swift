import AppIntents
import XCTest
@testable import Cramless

/// The App Intents: the open-a-screen intents route through the bridge to the router, and "How ready am I?"
/// answers from the live data.
@MainActor
final class IntentTests: XCTestCase {
    private var previousLive: AppModel?

    override func setUp() async throws {
        previousLive = AppModel.live
        CramlessIntentBridge.reset()
    }

    override func tearDown() async throws {
        AppModel.live = previousLive
        CramlessIntentBridge.reset()
    }

    func testStartSessionOpensTodaysSession() async throws {
        let app = WidgetTestSupport.makeApp()
        DeepLinks.installIntentBridge()
        _ = try await StartSessionIntent().perform()
        guard case .session(let request)? = app.router.cover else { return XCTFail("no session") }
        XCTAssertEqual(request.kind, .daily)
    }

    func testScanAndRecordOpenTheirScreens() async throws {
        let app = WidgetTestSupport.makeApp()
        _ = try await ScanPagesIntent().perform()
        XCTAssertEqual(app.router.cover, .scanner(courseID: nil, isOnboarding: false),
                       "the app-side intents install the bridge themselves")
        app.router.dismissCover()
        _ = try await RecordLectureIntent().perform()
        XCTAssertEqual(app.router.cover, .record(courseID: nil))
    }

    func testStartSessionDeclaresTheForeground() {
        XCTAssertEqual(StartSessionIntent.supportedModes, .foreground(.immediate))
        XCTAssertEqual(ScanPagesIntent.supportedModes, .foreground(.immediate))
        XCTAssertEqual(RecordLectureIntent.supportedModes, .foreground(.immediate))
        XCTAssertEqual(HowReadyAmIIntent.supportedModes, .background)
    }

    func testHowReadyReadsTheLiveData() throws {
        let app = WidgetTestSupport.makeApp()
        WidgetTestSupport.addExam(to: app, title: "Bio 101 Midterm", course: "Bio 101", days: 23)
        WidgetTestSupport.addExam(to: app, title: "Chem 110 Quiz", course: "Chem 110", color: .tangerine, days: 2, hour: 10)
        let snapshot = try XCTUnwrap(HowReadyAmIIntent.snapshot(app: app, now: app.now, calendar: app.calendar))
        XCTAssertEqual(snapshot.exams.map(\.title), ["Chem 110 Quiz", "Bio 101 Midterm"])
        let answer = WidgetCopy.readinessAnswer(snapshot, now: app.now, calendar: app.calendar)
        XCTAssertTrue(answer.contains("Chem 110 Quiz"), answer)
        XCTAssertTrue(answer.contains("2 days to go") || answer.contains("getting started"), answer)
        XCTAssertTrue(answer.contains("Next: Bio 101 Midterm in 23 days"), answer)
    }

    func testHowReadyWithoutTheAppUsesTheStoredSnapshot() {
        // No app model: the shared store. In unsigned simulator builds there's often no App Group, so either answer
        // is fine as long as it doesn't fail.
        let snapshot = HowReadyAmIIntent.snapshot(app: nil, now: WidgetTestSupport.now, calendar: WidgetTestSupport.calendar)
        let answer = WidgetCopy.readinessAnswer(snapshot, now: WidgetTestSupport.now, calendar: WidgetTestSupport.calendar)
        XCTAssertFalse(answer.isEmpty)
    }

    func testFiveShortcuts() {
        let shortcuts = CramlessShortcuts.appShortcuts
        XCTAssertEqual(shortcuts.count, 5)
    }

    func testStudyOutLoudOpensItAndStartsIt() async throws {
        let app = try StudyTestApp.make(clock: TestClock(WidgetTestSupport.now), calendar: WidgetTestSupport.calendar)
        AppModel.live = app
        app.settings.onboardingCompleted = true
        _ = try await StudyOutLoudIntent().perform()
        guard case .outLoud(let request, let startsAtOnce) = app.router.cover else { return XCTFail("\(String(describing: app.router.cover))") }
        XCTAssertTrue(startsAtOnce, "the person already said to")
        XCTAssertTrue(request.spokenOnly)
        XCTAssertEqual(StudyOutLoudIntent.supportedModes, .foreground(.immediate), "the microphone starts with the app in front")
    }
}
