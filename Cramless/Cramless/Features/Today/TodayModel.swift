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

/// One upcoming exam as Today shows it (the exams row, the card's chip, the done card's ring).
struct TodayExam: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var courseName: String
    var color: CourseColor
    var date: Date
    var daysLeft: Int
    var readiness: Double
    var delta: Double
    /// "Sun · in 2 days" (`TodayCopy.when`).
    var when: String = ""
    /// Questions in its scope: under `TodayCopy.fewQuestions` the readiness is a thin guess.
    var itemsInScope: Int = 0
    /// Readiness gained since the start of today.
    var deltaToday: Double = 0
}

/// The exam the session serves (`SessionFocus`: one this week with 20% of its minutes, else one with 40%), as the day card names it.
struct TodayFocus: Equatable, Sendable {
    var exam: TodayExam
    /// The session's topics for it, weakest first (the order "Why these?" reads them in).
    var topics: [String]
    /// "About N% after today": the ring's own function over today's session (`AppModel.readinessAfter`).
    var forecast: Double
    var weakCount: Int
    var dueCount: Int
    var newCount: Int
    /// All of the session's questions for it: "7" where the session holds 39.
    var questions: Int = 0
}

/// The exam the day's finished sessions counted toward, for the done card's ring ("+10% today · 2 days to go").
struct TodayDoneExam: Equatable, Sendable {
    var title: String
    var readiness: Double
    var deltaToday: Double
    var daysLeft: Int
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
    /// The exam eve session would have questions (weak spots in scope), and on which topics.
    var eveHasWork = true
    /// That session's planned minutes, rounded up, at most 10 (`BuiltSession.tonightMinutes`).
    var eveMinutes = SessionBuilder.examEveMinutes
    var eveTopics: [String] = []
    /// On the eve: the other exams' courses, which wait until after it (exams on the same day share the evening; they don't wait).
    var eveOthers: [String] = []
    /// The exam today's finished sessions counted toward.
    var doneExam: TodayDoneExam?
    /// A topic to practise on a day with nothing due.
    var practice: TodayPractice?
    /// "Your plan": two days back, today and four ahead.
    var strip: [TodayPlanDay] = []
    /// Cap's cards still to show today, at most three, the first one on screen.
    var notices: [CapNotice] = []
    /// Where that first one stands among today's: "2 of 3".
    var noticePosition = 1
    var noticeTotal = 0
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
        let exams: [TodayExam] = app.upcomingExams()
            .filter { $0.course?.deletedAt == nil && $0.date > now }
            .prefix(5)
            .map { exam in
                let r = app.readiness(for: exam)
                return TodayExam(id: exam.id, title: exam.title, courseName: exam.course?.name ?? "",
                                 color: exam.course?.color ?? .sky, date: exam.date, daysLeft: r.daysLeft,
                                 readiness: r.value, delta: r.deltaThisWeek,
                                 when: TodayCopy.when(exam.date, now: now, calendar: calendar),
                                 itemsInScope: r.itemsInScope, deltaToday: r.deltaToday)
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
        if let id = focus.examID, let exam = exams.first(where: { $0.id == id }),
           let examSnapshot = app.examSnapshots(upcomingOnly: true).first(where: { $0.id == id }) {
            var readiness: [UUID: Double] = [:]
            if let model = app.exam(id) {
                for topic in app.topicReadiness(for: model) { readiness[topic.id] = topic.value }
            }
            snapshot.focus = TodayFocus(exam: exam, topics: focus.topicsWeakestFirst(readiness: readiness).compactMap { names[$0] },
                                        forecast: max(exam.readiness, app.readinessAfter(session, for: examSnapshot)),
                                        weakCount: focus.weakCount, dueCount: focus.dueCount, newCount: focus.newCount, questions: focus.questionCount)
        }
        snapshot.sessionTopics = focus.examID == nil ? focus.topicIDs.compactMap { names[$0] } : []
        if snapshot.sessionTopics.isEmpty {
            let ids = session.entries.compactMap(\.courseID)
            var seen = Set<UUID>()
            snapshot.sessionTopics = ids.filter { seen.insert($0).inserted }.compactMap { app.course($0)?.name }
        }

        // The eve: tonight's topics, and the exams that wait.
        if let eve = snapshot.eveExam {
            let built = app.buildSession(SessionRequest(kind: .examEve, examID: eve.id))
            snapshot.eveHasWork = !built.isEmpty
            snapshot.eveMinutes = built.tonightMinutes
            snapshot.eveTopics = eveTopicNames(of: built, exams: snapshot.eveExams, names: names, app: app)
            snapshot.eveOthers = otherCourses(exams, besides: snapshot.eveExams)
        }
        snapshot.doneExam = app.todayDoneExamID().flatMap { id in exams.first { $0.id == id } }.map {
            TodayDoneExam(title: $0.title, readiness: $0.readiness, deltaToday: $0.deltaToday, daysLeft: $0.daysLeft)
        }
        snapshot.practice = practice(in: snapshot.sky)
        snapshot.strip = app.todayStrip(summary: summary, tonightMinutes: snapshot.eveExam == nil ? nil : snapshot.eveMinutes)
        snapshot.notices = app.todayNotices(session: session)
        let place = app.todayNoticePlace(session: session)
        (snapshot.noticePosition, snapshot.noticeTotal) = (place.position, snapshot.notices.first?.isConfirmation == true ? 1 : place.count)
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
            (snapshot.noticePosition, snapshot.noticeTotal) = (1, snapshot.notices.count)
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
            snapshot.strip = snapshot.strip.map { day in
                var d = day
                switch d.mark {
                case .eve, .exam: d.mark = .minutes(snapshot.summary.minutesGoal); d.examTitles = []
                default: break
                }
                return d
            }
            snapshot.hero = .session
        case "examEve", "eveDone", "twoEves":
            let id = firstExam?.id ?? UUID()
            snapshot.summary.examEveExamID = id
            snapshot.summary.examEveExamIDs = state == "twoEves" ? snapshot.exams.prefix(2).map(\.id) : [id]
            snapshot.hero = state == "eveDone" ? .examEveDone(id) : .examEve(id)
            snapshot.eveHasWork = true
            if let first = firstExam {
                // The demo's first exam is days away: say it as its eve would.
                snapshot.exams[0].when = TodayCopy.when(first.date, now: first.date.addingTimeInterval(-86_400), calendar: app.calendar)
                let built = app.buildSession(SessionRequest(kind: .examEve, examID: id))
                snapshot.eveMinutes = built.tonightMinutes
                snapshot.eveTopics = eveTopicNames(of: built, exams: [first], names: app.topicNames(), app: app)
                snapshot.eveOthers = otherCourses(snapshot.exams, besides: snapshot.eveExams)
                // The week as the eve's: tonight's moon, tomorrow's exam.
                for i in snapshot.strip.indices {
                    switch snapshot.strip[i].offset {
                    case 0: snapshot.strip[i].mark = .eve(minutes: built.tonightMinutes); snapshot.strip[i].examTitles = [first.title]
                    case 1: snapshot.strip[i].mark = .exam(count: 1); snapshot.strip[i].examTitles = [first.title]
                    default:
                        if case .exam = snapshot.strip[i].mark { snapshot.strip[i].mark = .minutes(snapshot.summary.minutesGoal) }
                        if case .eve = snapshot.strip[i].mark { snapshot.strip[i].mark = .minutes(snapshot.summary.minutesGoal) }
                    }
                }
            }
            snapshot.quests = QuestsToday()
        case "done":
            snapshot.summary.studiedToday = true
            snapshot.summary.minutesDone = max(snapshot.summary.minutesGoal, 15)
            snapshot.answersToday = max(snapshot.answersToday, 24)
            snapshot.streak.studiedToday = true
            snapshot.hero = .done
            if let exam = snapshot.focus?.exam ?? firstExam {
                snapshot.doneExam = TodayDoneExam(title: exam.title, readiness: min(1, exam.readiness + 0.10), deltaToday: 0.10,
                                                  daysLeft: exam.daysLeft)
            }
            if let i = snapshot.strip.firstIndex(where: \.isToday) { snapshot.strip[i].mark = .done }
        case "caughtUp":
            snapshot.hero = .caughtUp
        case "noMaterial":
            snapshot.hero = .noMaterial
            snapshot.exams = []
            snapshot.notices = []
            snapshot.strip = []
            snapshot.quests = QuestsToday()
        case "empty":
            snapshot.hero = .empty
            snapshot.exams = []
            snapshot.notices = []
            snapshot.strip = []
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
