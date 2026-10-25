import Foundation

/// Today's top card.
enum TodayHero: Equatable, Sendable {
    /// No courses yet: Cap and "Try a sample page".
    case empty
    /// Courses, but nothing to study in them yet.
    case noMaterial
    /// Today's session, sized to the person's minutes.
    case session
    /// A backlog too big for one day, cleared over the next few.
    case catchUp
    /// An exam tomorrow: weak spots only, then sleep.
    case examEve(UUID)
    /// The exam-eve session is done: sleep.
    case examEveDone(UUID)
    /// Today's goal is met (or nothing is left after studying): a calm celebration and a bonus round.
    case done
    /// Nothing due and nothing studied today.
    case caughtUp

    /// The rules, in order: no courses → empty; no questions → no material; an exam tomorrow → its eve (or its
    /// rest once done); studied today and the goal met (or nothing left) → done; nothing due → caught up;
    /// a backlog → catch-up; else the session.
    static func resolve(summary: TodaySummary, hasCourses: Bool, hasItems: Bool, examEveDone: Bool) -> TodayHero {
        guard hasCourses else { return .empty }
        guard hasItems else { return .noMaterial }
        if let exam = summary.examEveExamID { return examEveDone ? .examEveDone(exam) : .examEve(exam) }
        let goalMet = summary.minutesDone >= summary.minutesGoal
        if summary.studiedToday, goalMet || !summary.sessionReady { return .done }
        if !summary.sessionReady { return .caughtUp }
        return summary.catchUp ? .catchUp : .session
    }
}

/// One upcoming exam as Today shows it.
struct TodayExam: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var courseName: String
    var color: CourseColor
    var date: Date
    var daysLeft: Int
    var readiness: Double
    var delta: Double
}

/// Everything Today shows, computed once per change of the store (`app.revision`), the settings or the day.
struct TodaySnapshot: Equatable, Sendable {
    var hero: TodayHero
    var summary: TodaySummary
    var streak: StreakState
    var answersToday: Int
    var exams: [TodayExam]
    var confusion: ConfusionNote?
    /// The exam-eve session would have questions (weak spots in scope).
    var eveHasWork = true
    var isSquad = false
    var firstCourseID: UUID?
    var initials: String
    /// The person's memory sky, laid out for the hero's band.
    var sky: SkyScene = SkyScene.empty

    /// The shape (height over width) the hero's sky is laid out for when the screen isn't known: a phone's world. The real
    /// one comes from the hero's geometry (`HeroWorldGeometry.skyAspect`), so the constellations fill the sky exactly.
    static let skyAspect = HeroWorldGeometry.skyAspect(width: 402, screenHeight: 874, topInset: 62, compact: false)

    @MainActor
    static func make(app: AppModel, skyAspect: Double = TodaySnapshot.skyAspect) -> TodaySnapshot {
        let summary = app.todaySummary()
        let courses = app.courses
        let hasItems = !courses.isEmpty && app.hasActiveItems()
        let eveDone = summary.examEveExamID.map { app.finishedSessionToday(kind: .examEve, examID: $0) } ?? false
        let exams: [TodayExam] = app.upcomingExams()
            .filter { $0.course?.deletedAt == nil && $0.date > app.now }
            .prefix(5)
            .map { exam in
                let r = app.readiness(for: exam)
                return TodayExam(id: exam.id, title: exam.title, courseName: exam.course?.name ?? "",
                                 color: exam.course?.color ?? .sky, date: exam.date, daysLeft: r.daysLeft,
                                 readiness: r.value, delta: r.deltaThisWeek)
            }
        var snapshot = TodaySnapshot(
            hero: TodayHero.resolve(summary: summary, hasCourses: !courses.isEmpty, hasItems: hasItems,
                                    examEveDone: eveDone),
            summary: summary, streak: app.streak(), answersToday: app.answersToday(), exams: exams,
            confusion: hasItems ? app.todayConfusionNote() : nil, isSquad: app.purchases.plan == .squad,
            firstCourseID: courses.first?.id, initials: initials(app.settings.firstName),
            sky: hasItems ? app.skyScene(aspect: skyAspect) : .empty)
        if case .examEve(let id) = snapshot.hero {
            snapshot.eveHasWork = !app.buildSession(SessionRequest(kind: .examEve, examID: id)).isEmpty
        }
        #if DEBUG
        debugOverride(&snapshot)
        #endif
        return snapshot
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }

    #if DEBUG
    /// `CRAMLESS_TODAY=catchup|examEve|eveDone|done|caughtUp|noMaterial|empty` shows that state over the demo world's
    /// numbers (the real states come from the data; this only makes each one reachable for a screenshot).
    @MainActor
    private static func debugOverride(_ snapshot: inout TodaySnapshot) {
        guard let state = TestHarness.value("CRAMLESS_TODAY") else { return }
        let firstExam = snapshot.exams.first?.id ?? UUID()
        switch state {
        case "catchup":
            snapshot.summary.catchUp = true
            snapshot.summary.dueTotal = 142
            snapshot.summary.catchUpDaysToClear = 4
            snapshot.summary.plannedMinutes = snapshot.summary.minutesGoal
            snapshot.hero = .catchUp
        case "examEve":
            snapshot.summary.examEveExamID = firstExam
            snapshot.hero = .examEve(firstExam)
            snapshot.eveHasWork = true
        case "eveDone":
            snapshot.summary.examEveExamID = firstExam
            snapshot.hero = .examEveDone(firstExam)
        case "done":
            snapshot.summary.studiedToday = true
            snapshot.summary.minutesDone = max(snapshot.summary.minutesGoal, 16)
            snapshot.answersToday = max(snapshot.answersToday, 24)
            snapshot.streak.studiedToday = true
            snapshot.hero = .done
        case "caughtUp":
            snapshot.hero = .caughtUp
        case "noMaterial":
            snapshot.hero = .noMaterial
            snapshot.exams = []
            snapshot.confusion = nil
        case "empty":
            snapshot.hero = .empty
            snapshot.exams = []
            snapshot.confusion = nil
        default:
            break
        }
    }
    #endif
}
