import Foundation

#if DEBUG
/// Launch-time hooks for headless screenshots and UI checks (DEBUG only). Pass them through simctl with the
/// SIMCTL_CHILD_ prefix:
///
///     SIMCTL_CHILD_CRAMLESS_UITEST=1 SIMCTL_CHILD_CRAMLESS_ROUTE=exam xcrun simctl launch <udid> com.loopware.Capling
///
/// - `CRAMLESS_UITEST=1` in-memory store, the seeded demo world (`CRAMLESS_SEED=0` for an empty one), mock AI
///   (`CRAMLESS_MOCK_AI=0` for local), onboarding skipped.
/// - `CRAMLESS_ROUTE=<name>[:<arg>]` opens one screen (the list is `apply(route:)`). Consumed once.
/// - `CRAMLESS_ONBOARDING=1` (or `CRAMLESS_ROUTE=onboarding:<page>`) shows onboarding without wiping data.
/// - `CRAMLESS_NOW=<ISO 8601>` freezes the clock. `CRAMLESS_THEME=light|dark`, `CRAMLESS_DYSLEXIC=1`,
///   `CRAMLESS_PLAN=free|pro|squad|pass` (the purchase store reads it) set the matching state.
/// - `CRAMLESS_QUOTA=scans:2,lectures:1,grades:20`: the free AI uses left (`quota(_:)`).
///
/// A screen that needs a deeper state (a graded answer, a half-played scene) reads its own variable in its own
/// view, and documents it beside the view.
@MainActor
enum TestHarness {
    private static var consumed: Set<String> = []

    static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// Returns the value of `key` the first time it is asked for, nil afterwards.
    static func once(_ key: String) -> String? {
        guard !consumed.contains(key), let value = environment[key], !value.isEmpty else { return nil }
        consumed.insert(key)
        return value
    }

    /// Any value, every time (for hooks that only read state).
    static func value(_ key: String) -> String? {
        environment[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `CRAMLESS_CAP_POKE=3000,6500`: tap every Cap on screen at these times, in milliseconds after he appears (films).
    static var capPokeTimes: [Int] {
        (value("CRAMLESS_CAP_POKE") ?? "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// `CRAMLESS_CAP_SEED=7`: his dice, so what he says and how he squishes repeat from launch to launch.
    static var capSeed: UInt64? { value("CRAMLESS_CAP_SEED").flatMap { UInt64($0) } }

    static var skipsOnboarding: Bool {
        value("CRAMLESS_ONBOARDING") != "1" && !(value("CRAMLESS_ROUTE")?.hasPrefix("onboarding") ?? false)
    }

    static func applyLaunchSettings(to app: AppModel) {
        guard app.config.isHarness else { return }
        if let theme = value("CRAMLESS_THEME"), let t = AppSettings.Theme(rawValue: theme) { app.settings.theme = t }
        if value("CRAMLESS_DYSLEXIC") == "1" { app.settings.dyslexicFont = true }
        if app.settings.firstName.isEmpty { app.settings.firstName = "Maya" }
        if value("CRAMLESS_CONSENT") != "0" {
            app.settings.cloudConsentVersion = max(app.settings.cloudConsentVersion, AIConsent.currentVersion)
        }
        if value("CRAMLESS_ONBOARDING") == "1" { app.settings.onboardingCompleted = false }
        if let raw = value("CRAMLESS_QUOTA") { app.ai.setServerQuota(quota(raw)) }
    }

    /// `CRAMLESS_QUOTA=scans:2,lectures:1,grades:20`: the free AI uses left this period on each named meter, as if the server had
    /// said so (the others are untouched: none used). `scans:0` is the limit reached. For the allowance lines (`AllowanceCopy`).
    static func quota(_ raw: String) -> QuotaStatus {
        var left: [QuotaMeter.Key: Int] = [:]
        for part in raw.split(separator: ",") {
            let pair = part.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, let key = QuotaMeter.Key(rawValue: pair[0]), let n = Int(pair[1]) else { continue }
            left[key] = max(0, n)
        }
        let meters = AIFreeLimits.keys.map { key -> QuotaMeter in
            let limit = max(AIFreeLimits.limit(key), left[key] ?? 0)
            return QuotaMeter(key: key, used: limit - (left[key] ?? limit), limit: limit, period: AIFreeLimits.period(key))
        }
        return QuotaStatus(plan: .free, meters: meters)
    }

    /// Opens the screen named by CRAMLESS_ROUTE (`CRAMLESS_FEELLAB=<section>` alone opens the Feel lab). Called
    /// after the first frame and the seed.
    static func applyRoute(to app: AppModel) {
        guard let raw = once("CRAMLESS_ROUTE") ?? (value("CRAMLESS_FEELLAB") != nil ? "settings:feelLab" : nil) else {
            return
        }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        // What Cap "added" earlier (CRAMLESS_ASSISTANT_SEED) is in the library before the Settings page lays out, so a page that starts at
        // its foot has it.
        AskDemo.seedAdditions(app)
        apply(route: parts[0], arg: parts.count > 1 ? parts[1] : nil, app: app)
    }

    /// Toasts that launch raises, on demand. `CRAMLESS_LECTURE_RECOVERED=2480`: a lecture cut off by a crash and kept up to 41:20 (the
    /// demo world's lecture stands in for it); `=2480,3100` two of them.
    static func applyLaunchToasts(to app: AppModel) {
        guard let raw = once("CRAMLESS_LECTURE_RECOVERED") else { return }
        let lectures = app.courses.flatMap(\.liveSources).filter { $0.kind == .lecture }
        let recovered = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .enumerated().map { index, seconds in
                RecoveredLecture(id: lectures.indices.contains(index) ? lectures[index].id : (lectures.first?.id ?? UUID()),
                                 duration: seconds)
            }
        app.announceRecoveredLectures(recovered)
    }

    static func apply(route: String, arg: String?, app: AppModel) {
        let r = app.router
        let firstExam = app.upcomingExams().first
        let firstCourse = app.courses.first
        // The oldest source with pages (a deck import has none to show).
        let firstSource = firstCourse?.liveSources.sorted { $0.createdAt < $1.createdAt }.first { !$0.pages.isEmpty }
        switch route {
        case "today": r.tab = .today
        case "library": r.tab = .library
        case "ask": r.tab = .ask
        case "progress": r.tab = .progress
        case "exam":
            let exams = app.upcomingExams()
            let index = Int(arg ?? "") ?? 0
            if exams.indices.contains(index) { r.push(.exam(exams[index].id), on: .today) }
        // `course:<n>`: the nth course in Library order (`course:3` is Spanish II, with no exam); the first without a number.
        case "course":
            let courses = app.courses
            let index = Int(arg ?? "") ?? 0
            if courses.indices.contains(index) { r.push(.course(courses[index].id), on: .library) }
        case "source": if let s = firstSource { r.push(.source(s.id), on: .library) }
        case "sourcePage":
            if let s = firstSource {
                let anchors = firstCourse?.activeItems
                    .filter { $0.sourceRef?.sourceID == s.id && $0.sourceRef?.pageIndex == 0 && $0.sourceRef?.anchorIDs.isEmpty == false }
                    .min { $0.prompt < $1.prompt }?.sourceRef?.anchorIDs ?? []
                r.push(.sourcePage(sourceID: s.id, pageIndex: 0, highlight: anchors), on: .library)
            }
        case "lectureNotes":
            if let lecture = firstCourse?.liveSources.first(where: { $0.kind == .lecture }) {
                r.push(.lectureNotes(lecture.id), on: .library)
            }
        case "confusion":
            if let c = firstCourse?.confusions.first(where: { $0.status == .open }) { r.push(.confusion(c.id), on: .today) }
        case "settings":
            r.push(.settings, on: .today)
            if let arg, let page = SettingsPage(rawValue: arg) { r.push(.settingsPage(page), on: .today) }
        case "squad": r.push(.squad, on: .today)
        case "streak": r.push(.streak, on: .progress)
        // Every badge, and one badge up close: `badge:<id>` (see `Badge`), `badge:streak30`.
        case "badges": r.push(.badges, on: .progress)
        case "badge": if let id = arg.flatMap(Badge.init(rawValue:)) { r.present(.badge(id)) }
        // The memory sky; `CRAMLESS_SKY=…` (see `SkyDebug`) sets its state.
        case "sky": r.push(.sky, on: .progress)
        // Today's "Why these?", the sky as a list ("Study something else"), and today's quests up close.
        case "todayWhy": r.tab = .today; r.present(.todayReasons)
        case "skyList": r.push(.skyList, on: .today)
        case "quests": r.tab = .today; r.present(.quests)
        case "chat":
            r.tab = .ask
            if let t = app.fetch(FetchDescriptorFactory.latestThread).first { r.push(.chat(t.id), on: .ask) }
        case "session":
            let kind = arg.flatMap(SessionKind.init(rawValue:)) ?? .daily
            let confusion = kind == .fix ? firstCourse?.confusions.first?.id : nil
            // `CRAMLESS_SESSION_MINUTES=5`: a shorter session, so a film reaches the summary.
            r.present(.session(SessionRequest(kind: kind, courseID: nil, examID: kind == .examEve ? firstExam?.id : nil,
                                              confusionID: confusion,
                                              minutes: value("CRAMLESS_SESSION_MINUTES").flatMap(Int.init))))
        // `mock:<n>`: a mock of the nth upcoming exam; without a number, the first with enough questions. `CRAMLESS_MOCK` sets its state
        // (see `MockExamView`).
        case "mock":
            let exams = app.upcomingExams()
            let exam = arg.flatMap(Int.init).flatMap { exams.indices.contains($0) ? exams[$0] : nil }
                ?? exams.first { if case .ready = app.mockOffer(for: $0) { true } else { false } } ?? exams.first
            if let exam { r.present(.mockExam(examID: exam.id)) }
        case "scanner": r.present(.scanner(courseID: firstCourse?.id, isOnboarding: false))
        case "capture": r.present(.capture(courseID: firstCourse?.id))
        case "captureFlow", "review":
            r.present(.captureFlow(CaptureRequest(input: .sample, courseID: firstCourse?.id)))
        case "paste": r.present(.paste(courseID: firstCourse?.id))
        case "importDeck": r.present(.importDeck(courseID: firstCourse?.id))
        case "newCourse": r.present(.newCourse)
        case "newExam": r.present(.newExam(courseID: firstCourse?.id))
        case "editExam": if let e = firstExam { r.present(.editExam(e.id)) }
        case "logGrade": if let e = firstExam { r.present(.logGrade(examID: e.id)) }
        case "editItem": if let i = firstCourse?.activeItems.first { r.present(.editItem(i.id)) }
        case "newItem": r.present(.newItem(courseID: firstCourse?.id))
        case "explain":
            if let i = firstCourse?.activeItems.first(where: { $0.kind.isOwnWords }) {
                r.present(.explain(itemID: i.id, given: "Cells divide so they can make sex cells."))
            }
        case "makeCards":
            if let t = app.fetch(FetchDescriptorFactory.latestThread).first { r.present(.makeCards(threadID: t.id)) }
        case "paywall":
            if arg == "onboarding" {
                r.present(.paywall(.onboarding(planLine: "Your Bio 101 plan is set: 15 minutes a day until Nov 14.")))
            } else {
                r.present(.paywall(.settings))
            }
        case "examPass": r.present(.examPass(examID: firstExam?.id))
        case "consent": r.present(.consent(arg == "photos" ? .photos : .cloudAI(feature: "Write questions from your pages")))
        case "squadRedeem": r.present(.squadRedeem(code: arg))
        case "record": r.present(.record(courseID: firstCourse?.id))
        case "onboarding":
            app.settings.onboardingCompleted = false
            r.present(.onboarding(page: arg.flatMap(Int.init)))
        default:
            AppConfig.log.error("unknown CRAMLESS_ROUTE \(route, privacy: .public)")
        }
    }
}
#endif

import SwiftData

enum FetchDescriptorFactory {
    static var latestThread: FetchDescriptor<ChatThread> {
        var d = FetchDescriptor<ChatThread>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        d.fetchLimit = 1
        return d
    }
}
