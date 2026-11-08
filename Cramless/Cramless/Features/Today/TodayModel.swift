import Foundation

/// Today's day card: what kind of day it is.
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
    /// Today's goal is met (or nothing is left after studying): a calm celebration and a few more minutes if wanted.
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

/// One upcoming exam as Today shows it (the card's chip and ring, the night before, the done card).
struct TodayExam: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var courseName: String
    var date: Date
    var daysLeft: Int
    var readiness: Double
    /// Its day on the chip: "Tue", "Tomorrow at 10:00", "29 Nov" (`TodayCopy.examDay`).
    var day: String = ""
    /// The same in full, for VoiceOver ("Tuesday"), when it differs.
    var daySpoken: String? = nil
}

/// The exam the session serves (`SessionFocus`: one this week with 20% of its minutes, else one with 40%), as the day card names it.
struct TodayFocus: Equatable, Sendable {
    var exam: TodayExam
    /// The session's topics for it, weakest first (the order "Why these?" reads them in).
    var topics: [String]
    /// All of the session's questions for it: "7" where the session holds 42. Under half, the card's title names the courses instead.
    var questions: Int = 0
}

/// A short practice on one topic, for a day with nothing due ("Practice Limiting reagents · 5 min").
struct TodayPractice: Equatable, Sendable {
    var name: String
    var topicID: UUID
    var courseID: UUID
}

/// Everything Today shows, computed once per change of the store (`app.revision`), the settings or the day.
struct TodaySnapshot: Equatable, Sendable {
    var hero: TodayHero
    var summary: TodaySummary
    var streak: StreakState
    var answersToday: Int
    /// Upcoming exams, soonest first (at most five).
    var exams: [TodayExam]
    var firstCourseID: UUID?
    var initials: String
    /// "Good afternoon, Maya".
    var greeting: String = ""
    /// The exam the session serves; nil with no exam or a session spread over several.
    var focus: TodayFocus?
    /// The session's topics (and with none, its courses), for a card with no exam to name.
    var sessionTopics: [String] = []
    /// The session's courses, soonest exam first (courses with no exam after them): the title when no one exam has half the session.
    var sessionCourses: [String] = []
    /// The exam eve session would have questions (weak spots in scope), and on which topics.
    var eveHasWork = true
    /// That session's planned minutes, rounded up, at most 10 (`BuiltSession.tonightMinutes`).
    var eveMinutes = SessionBuilder.examEveMinutes
    var eveTopics: [String] = []
    /// On the eve: the other exams' courses, which wait until after it (exams on the same day share the evening; they don't wait).
    var eveOthers: [String] = []
    /// Once tonight's session is done: how many ideas the last look holds.
    var lastLookIdeas = 0
    /// The exam today's finished sessions counted toward: the done card's chip and ring.
    var doneExam: TodayExam?
    /// A topic to practice on a day with nothing to review.
    var practice: TodayPractice?
    /// Cap's cards still to show today, at most three, the first one on screen.
    var notices: [CapNotice] = []
    /// No session has ever been finished: the band says "Welcome".
    var firstDay = false
    /// The person's memory sky, laid out for the band.
    var sky: SkyScene = SkyScene.empty
    /// Today's quests. Empty until a first session is done, on exam eve, with nothing to study, and in Quiet mode.
    var quests = QuestsToday()
    /// Quiet mode: no flame on the band, no word about the streak.
    var quiet = false

    /// The shape (height over width) the band's sky is laid out for when the screen isn't known: a phone's. The real one comes from
    /// the band's geometry (`HeroWorldGeometry.skyAspect`), so the constellations fill the sky exactly.
    static let skyAspect = HeroWorldGeometry.bandSkyAspect(width: 402, topInset: 62, compact: false)

    /// There is material to study.
    var hasMaterial: Bool { hero != .empty && hero != .noMaterial }
    /// The quests row may say who in the Squad has studied: never the night before an exam, which is calm, or in Quiet mode.
    var showsSquad: Bool { !isEve && !quiet }
    /// The day is an exam's eve (before or after its session).
    var isEve: Bool {
        switch hero {
        case .examEve, .examEveDone: true
        default: false
        }
    }
    /// The eve's exam, when it is one.
    var eveExam: TodayExam? {
        switch hero {
        case .examEve(let id), .examEveDone(let id): exams.first { $0.id == id }
        default: nil
        }
    }
    /// Every exam tomorrow, sharing tonight (the eve's exam first).
    var eveExams: [TodayExam] {
        guard let eve = eveExam else { return [] }
        let tonight = exams.filter { summary.examEveExamIDs.contains($0.id) && $0.id != eve.id }
        return [eve] + tonight
    }
    /// Their titles: "Hydrology exam" or "Hydrology exam and Org Chem midterm".
    var eveTitle: String? { eveExams.isEmpty ? nil : eveExams.map(\.title).formatted(.list(type: .and)) }

    @MainActor
    static func make(app: AppModel, skyAspect: Double = TodaySnapshot.skyAspect) -> TodaySnapshot {
        let (summary, session) = app.todayPlan()
        let courses = app.courses
        let hasItems = !courses.isEmpty && app.hasActiveItems()
        let calendar = app.calendar
        let now = app.now
        let eveDone = app.eveSessionDone(summary)
        let upcoming = app.upcomingExams().filter { $0.course?.deletedAt == nil && $0.date > now }
        let exams: [TodayExam] = upcoming
            .prefix(5)
            .map { exam in
                let r = app.readiness(for: exam)
                let day = TodayCopy.examDay(exam.date, now: now, calendar: calendar)
                let spoken = TodayCopy.examDay(exam.date, now: now, calendar: calendar, spoken: true)
                return TodayExam(id: exam.id, title: exam.title, courseName: exam.course?.name ?? "", date: exam.date, daysLeft: r.daysLeft,
                                 readiness: r.value, day: day, daySpoken: spoken == day ? nil : spoken)
            }
        let firstDay = !app.hasFinishedAnySession()
        var snapshot = TodaySnapshot(
            hero: TodayHero.resolve(summary: summary, hasCourses: !courses.isEmpty, hasItems: hasItems, examEveDone: eveDone),
            summary: summary, streak: app.streak(), answersToday: app.answersToday(), exams: exams,
            firstCourseID: courses.first?.id, initials: initials(app.settings.firstName),
            greeting: TodayCopy.greeting(hour: calendar.component(.hour, from: now), name: app.settings.firstName,
                                         firstDay: firstDay || courses.isEmpty),
            firstDay: firstDay,
            sky: hasItems ? app.skyScene(aspect: skyAspect) : .empty,
            quiet: app.settings.quietMode)
        guard hasItems else {
            #if DEBUG
            debugOverride(&snapshot, app: app)
            #endif
            return snapshot
        }

        // What the day's session is for.
        let names = app.topicNames()
        let focus = app.sessionFocus(session)
        if let id = focus.examID, let exam = exams.first(where: { $0.id == id }) {
            var readiness: [UUID: Double] = [:]
            if let model = app.exam(id) {
                for topic in app.topicReadiness(for: model) { readiness[topic.id] = topic.value }
            }
            snapshot.focus = TodayFocus(exam: exam, topics: focus.topicsWeakestFirst(readiness: readiness).compactMap { names[$0] },
                                        questions: focus.questionCount)
        }
        snapshot.sessionCourses = sessionCourses(session, exams: upcoming, app: app)
        snapshot.sessionTopics = focus.examID == nil ? focus.topicIDs.compactMap { names[$0] } : []
        if snapshot.sessionTopics.isEmpty { snapshot.sessionTopics = snapshot.sessionCourses }

        // The eve: tonight's topics, and the exams that wait.
        if let eve = snapshot.eveExam {
            let built = app.buildSession(SessionRequest(kind: .examEve, examID: eve.id))
            snapshot.eveHasWork = !built.isEmpty
            snapshot.eveMinutes = built.tonightMinutes
            snapshot.eveTopics = eveTopicNames(of: built, exams: snapshot.eveExams, names: names, app: app)
            snapshot.eveOthers = otherCourses(exams, besides: snapshot.eveExams)
            if case .examEveDone = snapshot.hero { snapshot.lastLookIdeas = app.lastLookCount(for: eve.id) }
        }
        snapshot.doneExam = app.todayDoneExamID().flatMap { id in exams.first { $0.id == id } }
        snapshot.practice = practice(in: snapshot.sky)
        snapshot.notices = app.todayNotices(session: session)
        if app.hasFinishedAnySession(), !app.settings.quietMode { snapshot.quests = app.questsToday() }
        #if DEBUG
        debugOverride(&snapshot, app: app)
        #endif
        return snapshot
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }

    /// The courses a session holds, by name: those with an upcoming exam soonest first, then the rest in the order they first come up.
    @MainActor
    static func sessionCourses(_ session: BuiltSession, exams: [Exam], app: AppModel) -> [String] {
        var soonest: [UUID: Date] = [:]
        for exam in exams {
            guard let id = exam.course?.id else { continue }
            soonest[id] = min(soonest[id] ?? exam.date, exam.date)
        }
        var seen = Set<UUID>()
        let ids = session.entries.compactMap(\.courseID).filter { seen.insert($0).inserted }
        return ids.enumerated()
            .sorted { (soonest[$0.element] ?? .distantFuture, $0.offset) < (soonest[$1.element] ?? .distantFuture, $1.offset) }
            .compactMap { app.course($0.element)?.name }
    }

    /// A session's topics by name, in the order they first come up.
    static func topicNames(of session: BuiltSession, names: [UUID: String]) -> [String] {
        topicIDs(of: session).compactMap { names[$0] }
    }

    private static func topicIDs(of session: BuiltSession) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        for spot in session.weakSpots where spot.source == .topic && seen.insert(spot.id).inserted { result.append(spot.id) }
        for entry in session.entries {
            guard let t = entry.topicID, seen.insert(t).inserted else { continue }
            result.append(t)
        }
        return result
    }

    /// The eve session's topics by name, weakest first, as the day card's title reads them.
    @MainActor
    private static func eveTopicNames(of session: BuiltSession, exams: [TodayExam], names: [UUID: String], app: AppModel) -> [String] {
        var readiness: [UUID: Double] = [:]
        for exam in exams {
            guard let model = app.exam(exam.id) else { continue }
            for topic in app.topicReadiness(for: model) where readiness[topic.id] == nil { readiness[topic.id] = topic.value }
        }
        return SessionFocus.weakestFirst(topicIDs(of: session), readiness: readiness).compactMap { names[$0] }
    }

    /// The other exams' courses, soonest first, without tonight's exams and their courses.
    static func otherCourses(_ exams: [TodayExam], besides tonight: [TodayExam]) -> [String] {
        var seen = Set(tonight.map(\.courseName))
        let ids = Set(tonight.map(\.id))
        return exams.filter { !ids.contains($0.id) }
            .map { $0.courseName.isEmpty ? $0.title : $0.courseName }
            .filter { seen.insert($0).inserted }
    }

    /// The topic whose questions are remembered least, for a short practice when nothing is due.
    static func practice(in sky: SkyScene) -> TodayPractice? {
        let best = sky.layout.constellations
            .compactMap { c -> (SkyLayout.Constellation, Double)? in
                guard c.topicID != nil, let r = sky.light.meanRecall(c) else { return nil }
                return (c, r)
            }
            .min { $0.1 < $1.1 }
        guard let (c, _) = best, let topic = c.topicID else { return nil }
        return TodayPractice(name: c.name, topicID: topic, courseID: c.courseID)
    }

    #if DEBUG
    /// `CRAMLESS_TODAY=catchup|partway|split|noExam|examEve|twoEves|eveDone|done|caughtUp|noMaterial|empty` shows that state over the demo
    /// world's numbers (the real states come from the data; this only makes each one reachable for a screenshot), and
    /// `CRAMLESS_TODAY_NOTICES=0|1|2|3` deals that many of Cap's cards.
    @MainActor
    private static func debugOverride(_ snapshot: inout TodaySnapshot, app: AppModel) {
        if let raw = TestHarness.value("CRAMLESS_TODAY_NOTICES"), let n = Int(raw) {
            snapshot.notices = Array(TodayNoticesDemo.notices(base: snapshot.notices).prefix(max(0, n)))
        }
        guard let state = TestHarness.value("CRAMLESS_TODAY") else { return }
        let firstExam = snapshot.exams.first
        switch state {
        case "catchup":
            snapshot.summary.catchUp = true
            snapshot.summary.dueTotal = 142
            snapshot.summary.catchUpDaysToClear = 4
            snapshot.summary.plannedMinutes = snapshot.summary.minutesGoal
            snapshot.hero = .catchUp
        case "partway":
            snapshot.summary.minutesDone = 6
            snapshot.summary.studiedToday = true
            snapshot.summary.plannedMinutes = max(5, snapshot.summary.minutesGoal - 6)
            snapshot.hero = .session
        case "split":
            // A session spread over several exams: no one exam to name, its topics from every course.
            snapshot.sessionTopics = topicNames(of: app.todayBuiltSession(), names: app.topicNames())
            snapshot.focus = nil
            snapshot.hero = .session
        case "noExam":
            if let focus = snapshot.focus { snapshot.sessionTopics = focus.topics }
            snapshot.focus = nil
            snapshot.exams = []
            snapshot.hero = .session
        case "examEve", "eveDone", "twoEves":
            let id = firstExam?.id ?? UUID()
            snapshot.summary.examEveExamID = id
            snapshot.summary.examEveExamIDs = state == "twoEves" ? snapshot.exams.prefix(2).map(\.id) : [id]
            snapshot.hero = state == "eveDone" ? .examEveDone(id) : .examEve(id)
            snapshot.eveHasWork = true
            if let first = firstExam {
                // The demo's first exam is days away: say it as its eve would.
                let eve = first.date.addingTimeInterval(-86_400)
                snapshot.exams[0].day = TodayCopy.examDay(first.date, now: eve, calendar: app.calendar)
                snapshot.exams[0].daySpoken = nil
                let built = app.buildSession(SessionRequest(kind: .examEve, examID: id))
                snapshot.eveMinutes = built.tonightMinutes
                snapshot.eveTopics = eveTopicNames(of: built, exams: [first], names: app.topicNames(), app: app)
                snapshot.eveOthers = otherCourses(snapshot.exams, besides: snapshot.eveExams)
                snapshot.lastLookIdeas = state == "eveDone" ? app.lastLookCount(for: id) : 0
            }
            snapshot.quests = QuestsToday()
        case "done":
            snapshot.summary.studiedToday = true
            snapshot.summary.minutesDone = max(snapshot.summary.minutesGoal, 15)
            snapshot.answersToday = max(snapshot.answersToday, 24)
            snapshot.streak.studiedToday = true
            snapshot.hero = .done
            if var exam = snapshot.focus?.exam ?? firstExam {
                exam.readiness = min(1, exam.readiness + 0.10)
                snapshot.doneExam = exam
            }
        case "caughtUp":
            snapshot.hero = .caughtUp
        case "noMaterial":
            snapshot.hero = .noMaterial
            snapshot.exams = []
            snapshot.notices = []
            snapshot.quests = QuestsToday()
        case "empty":
            snapshot.hero = .empty
            snapshot.exams = []
            snapshot.notices = []
            snapshot.quests = QuestsToday()
            snapshot.firstDay = true
            snapshot.greeting = TodayCopy.greeting(hour: app.calendar.component(.hour, from: app.now),
                                                   name: app.settings.firstName, firstDay: true)
        default:
            break
        }
    }
    #endif
}
