import XCTest
@testable import Cramless

/// capling:// links: the parser (pure) and what each link does to the router.
@MainActor
final class DeepLinkTests: XCTestCase {
    private var previousLive: AppModel?

    override func setUp() async throws {
        previousLive = AppModel.live
    }

    override func tearDown() async throws {
        AppModel.live = previousLive
        CramlessIntentBridge.reset()
    }

    private func parse(_ string: String) -> DeepLink? {
        DeepLinks.parse(URL(string: string)!)
    }

    // MARK: Parsing

    func testTabs() {
        XCTAssertEqual(parse("capling://today"), .tab(.today))
        XCTAssertEqual(parse("capling://ask"), .tab(.ask))
        XCTAssertEqual(parse("capling://progress"), .tab(.progress))
        XCTAssertEqual(parse("capling://library"), .tab(.library))
        XCTAssertEqual(parse("CAPLING://Today"), .tab(.today), "scheme and host ignore case")
        XCTAssertEqual(parse("capling://streak"), .streak)
        XCTAssertEqual(parse("capling://today?notice=pair-abc123"), .notice("pair-abc123"))
        XCTAssertEqual(parse("capling://today?notice=fade-00000000-0000-0000-0000-000000000000"), .notice("fade-00000000-0000-0000-0000-000000000000"))
        XCTAssertEqual(parse("capling://today?notice=has%20space"), .tab(.today), "not an id: Today, as it is")
    }

    func testAChatLink() {
        let id = UUID()
        XCTAssertEqual(parse(CramlessLink.chat(id).absoluteString), .chat(id))
        XCTAssertEqual(parse("capling://ask/chat/\(id.uuidString.lowercased())"), .chat(id))
        XCTAssertEqual(parse("capling://ask/chat/not-a-uuid"), .tab(.ask), "a bad id still opens Ask")
        XCTAssertEqual(parse("capling://ask/chat"), .tab(.ask))
    }

    func testAChatLinkOpensTheChatInAsk() {
        let app = AITestSupport.makeApp()
        app.settings.onboardingCompleted = true
        let thread = app.startChat(courseID: nil)
        app.router.tab = .today
        app.router.present(.newCourse)
        DeepLinks.perform(.chat(thread.id), app: app)
        XCTAssertEqual(app.router.tab, .ask)
        XCTAssertNil(app.router.sheet)
        XCTAssertEqual(app.router.paths[.ask], [.chat(thread.id)])
        // A chat that has gone: Ask, and nothing pushed.
        app.router.popToRoot(.ask)
        app.router.tab = .today
        DeepLinks.perform(.chat(UUID()), app: app)
        XCTAssertEqual(app.router.tab, .ask)
        XCTAssertEqual(app.router.paths[.ask], [])
    }

    func testSessions() {
        let confusion = UUID()
        let exam = UUID()
        XCTAssertEqual(parse("capling://session"), .session(kind: .daily, examID: nil, confusionID: nil, courseID: nil))
        XCTAssertEqual(parse("capling://session?kind=fix&confusion=\(confusion.uuidString)"),
                       .session(kind: .fix, examID: nil, confusionID: confusion, courseID: nil))
        XCTAssertEqual(parse("capling://session?kind=examEve&exam=\(exam.uuidString)"),
                       .session(kind: .examEve, examID: exam, confusionID: nil, courseID: nil))
        XCTAssertEqual(parse("capling://session?kind=EXAMEVE"), .session(kind: .examEve, examID: nil, confusionID: nil, courseID: nil))
        XCTAssertEqual(parse("capling://session?kind=fix"), .session(kind: .daily, examID: nil, confusionID: nil, courseID: nil),
                       "a fix without its confusion is today's session")
        XCTAssertEqual(parse("capling://session?kind=quickCheck"), .session(kind: .daily, examID: nil, confusionID: nil, courseID: nil))
        XCTAssertEqual(parse("capling://session?kind=mock"), .session(kind: .daily, examID: nil, confusionID: nil, courseID: nil),
                       "a mock isn't reachable from outside: it opens from its exam")
        XCTAssertEqual(parse("capling://session?kind=nonsense"), .session(kind: .daily, examID: nil, confusionID: nil, courseID: nil))
    }

    func testScreensExamsSquadAndFiles() {
        let id = UUID()
        let course = UUID()
        XCTAssertEqual(parse("capling://scan"), .scan(courseID: nil))
        XCTAssertEqual(parse("capling://scan?course=\(course.uuidString)"), .scan(courseID: course))
        XCTAssertEqual(parse("capling://record"), .record(courseID: nil))
        XCTAssertEqual(parse("capling://exam/\(id.uuidString)"), .exam(id))
        XCTAssertEqual(parse("capling://exam/\(id.uuidString.lowercased())"), .exam(id))
        XCTAssertEqual(parse("capling://exam/new"), .newExam)
        XCTAssertNil(parse("capling://exam/not-a-uuid"))
        XCTAssertNil(parse("capling://exam"))
        XCTAssertEqual(parse("capling://squad/K7Q2-MX"), .squad(code: "K7Q2-MX"))
        XCTAssertNil(parse("capling://squad/ab"), "too short")
        XCTAssertNil(parse("capling://squad/%3Cscript%3E"), "letters, digits and dashes only")
        XCTAssertNil(parse("capling://squad"))
        let file = URL(fileURLWithPath: "/tmp/Unit 3.apkg")
        XCTAssertEqual(DeepLinks.parse(file), .importFile(file))
        XCTAssertEqual(parse("capling://settings"), .settings(nil))
        XCTAssertEqual(parse("capling://settings/notifications"), .settings(.notifications))
        XCTAssertNil(parse("capling://settings/debug"), "the debug page isn't reachable by link")
        XCTAssertNil(parse("capling://settings/nope"))
        XCTAssertNil(parse("https://capling.app/today"), "only our scheme")
        XCTAssertNil(parse("capling://settings-of-doom"))
    }

    /// Every link the widgets, activities, control and notifications build parses to what they mean.
    func testEveryBuiltLinkParses() {
        let id = UUID()
        XCTAssertEqual(DeepLinks.parse(CramlessLink.today), .tab(.today))
        XCTAssertEqual(DeepLinks.parse(CramlessLink.ask), .tab(.ask))
        XCTAssertEqual(DeepLinks.parse(CramlessLink.progress), .tab(.progress))
        XCTAssertEqual(DeepLinks.parse(CramlessLink.library), .tab(.library))
        XCTAssertEqual(DeepLinks.parse(CramlessLink.streak), .streak)
        XCTAssertEqual(DeepLinks.parse(CramlessLink.session), .session(kind: .daily, examID: nil, confusionID: nil, courseID: nil))
        XCTAssertEqual(DeepLinks.parse(CramlessLink.session(kind: SessionKind.fix.rawValue, confusion: id)),
                       .session(kind: .fix, examID: nil, confusionID: id, courseID: nil))
        XCTAssertEqual(DeepLinks.parse(CramlessLink.session(kind: SessionKind.practice.rawValue, course: id)),
                       .session(kind: .practice, examID: nil, confusionID: nil, courseID: id))
        XCTAssertEqual(DeepLinks.parse(CramlessLink.scan), .scan(courseID: nil))
        XCTAssertEqual(DeepLinks.parse(CramlessLink.record), .record(courseID: nil))
        XCTAssertEqual(DeepLinks.parse(CramlessLink.outLoud), .outLoud)
        XCTAssertEqual(DeepLinks.parse(CramlessLink.exam(id)), .exam(id))
        XCTAssertEqual(DeepLinks.parse(CramlessLink.newExam), .newExam)
        XCTAssertEqual(DeepLinks.parse(CramlessLink.settings(page: SettingsPage.subscription.rawValue)),
                       .settings(.subscription))
        XCTAssertEqual(DeepLinks.parse(CramlessLink.settings()), .settings(nil))
        XCTAssertEqual(DeepLinks.parse(CramlessLink.squad("k7q2 mx!")), .squad(code: "k7q2mx"))
        XCTAssertEqual(DeepLinks.parse(ExamWidgetView.url(for: nil)), .tab(.today))
        XCTAssertEqual(DeepLinks.parse(StreakWidgetView.url), .streak)
    }

    // MARK: Dispatch

    func testTabAndExamLinksNavigate() throws {
        let app = WidgetTestSupport.makeApp()
        let exam = WidgetTestSupport.addExam(to: app, title: "Bio 101 Midterm", course: "Bio 101", days: 23)
        app.router.present(.newCourse)
        DeepLinks.handle(URL(string: "capling://progress")!, app: app)
        XCTAssertEqual(app.router.tab, .progress)
        XCTAssertNil(app.router.sheet, "a link closes the sheet it would be hidden behind")

        DeepLinks.handle(CramlessLink.exam(exam.id), app: app)
        XCTAssertEqual(app.router.tab, .today)
        XCTAssertEqual(app.router.paths[.today], [.exam(exam.id)])

        DeepLinks.handle(CramlessLink.exam(UUID()), app: app)
        XCTAssertEqual(app.router.paths[.today], [], "a deleted exam lands on Today")

        DeepLinks.handle(CramlessLink.streak, app: app)
        XCTAssertEqual(app.router.tab, .progress)
        XCTAssertEqual(app.router.paths[.progress], [.streak])
    }

    func testSessionScannerAndRecorderOpenOnce() {
        let app = WidgetTestSupport.makeApp()
        DeepLinks.handle(CramlessLink.session, app: app)
        guard case .session(let request)? = app.router.cover else { return XCTFail("no session") }
        XCTAssertEqual(request.kind, .daily)

        DeepLinks.handle(CramlessLink.session, app: app)
        guard case .session(let again)? = app.router.cover else { return XCTFail("session gone") }
        XCTAssertEqual(again.id, request.id, "a second tap returns to the same session")

        DeepLinks.handle(CramlessLink.scan, app: app)
        DeepLinks.handle(CramlessLink.record, app: app)
        if case .session? = app.router.cover {} else { XCTFail("work in progress was replaced") }

        app.router.dismissCover()
        DeepLinks.handle(CramlessLink.record, app: app)
        XCTAssertEqual(app.router.cover, .record(courseID: nil))
        app.router.dismissCover()
        DeepLinks.handle(CramlessLink.scan, app: app)
        XCTAssertEqual(app.router.cover, .scanner(courseID: nil, isOnboarding: false))
    }

    func testANoticeLinkOpensTodayWithThatCardFirst() throws {
        let clock = TestClock(EngineTest.date(2026, 10, 22, 18))
        let app = try StudyTestApp.make(clock: clock, calendar: EngineTest.calendar())
        app.settings.onboardingCompleted = true
        app.router.tab = .library
        app.router.present(.newCourse)
        DeepLinks.handle(CramlessLink.today(notice: "pair-1"), app: app)
        XCTAssertEqual(app.router.tab, .today)
        XCTAssertNil(app.router.sheet)
        XCTAssertEqual(app.noticeLedger.front, "pair-1")
    }

    func testAFixLinkNeedsARealConfusion() {
        let app = WidgetTestSupport.makeApp()
        DeepLinks.handle(CramlessLink.session(kind: "fix", confusion: UUID()), app: app)
        guard case .session(let request)? = app.router.cover else { return XCTFail("no session") }
        XCTAssertEqual(request.kind, .daily, "the confusion is gone: today's session instead")
        XCTAssertNil(request.confusionID)
    }

    func testSettingsLinksOpenThePage() {
        let app = WidgetTestSupport.makeApp()
        app.router.tab = .library
        DeepLinks.handle(CramlessLink.settings(page: "notifications"), app: app)
        XCTAssertEqual(app.router.tab, .today)
        XCTAssertEqual(app.router.paths[.today], [.settings, .settingsPage(.notifications)])
    }

    func testSquadAndNewExamOpenTheirSheets() {
        let app = WidgetTestSupport.makeApp()
        DeepLinks.handle(URL(string: "capling://squad/K7Q2MX")!, app: app)
        XCTAssertEqual(app.router.sheet, .squadRedeem(code: "K7Q2MX"))
        DeepLinks.handle(CramlessLink.newExam, app: app)
        XCTAssertEqual(app.router.sheet, .newExam(courseID: nil))
    }

    func testLinksWaitForOnboarding() {
        let app = WidgetTestSupport.makeApp()
        app.settings.onboardingCompleted = false
        DeepLinks.handle(CramlessLink.session, app: app)
        DeepLinks.handle(CramlessLink.progress, app: app)
        XCTAssertNil(app.router.cover)
        XCTAssertEqual(app.router.tab, .today)
    }

    // MARK: Intent bridge

    func testIntentLinksWaitForTheAppAndThenRoute() {
        CramlessIntentBridge.reset()
        let app = WidgetTestSupport.makeApp()
        CramlessIntentBridge.open(CramlessLink.progress)
        XCTAssertEqual(app.router.tab, .today, "nothing installed yet: the link waits")
        DeepLinks.installIntentBridge()
        XCTAssertEqual(app.router.tab, .progress, "delivered on install")
        CramlessIntentBridge.open(CramlessLink.library)
        XCTAssertEqual(app.router.tab, .library)
    }
}
