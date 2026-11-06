import Foundation
import SwiftData

// The read API over the engines: what Today, Progress, the exam screens, the widget and notifications show.
// Each call fetches its snapshots once and hands them to a pure engine (Engine/). Call these from a view's body
// or a task keyed on `app.revision`; never loop over models in a view.
extension AppModel {
    // MARK: Today

    /// Today's card: the daily session as it would be built now, and what's done.
    func todaySummary() -> TodaySummary { todayPlan().summary }

    /// Today's daily session as it would be built now: the one Today describes and starts.
    func todayBuiltSession() -> BuiltSession { todayPlan().session }

    /// Today's card and the daily session it describes, built once (Today, the exam page's "Study" and Cap's cards read the same
    /// session).
    func todayPlan() -> (summary: TodaySummary, session: BuiltSession) {
        let record = dayRecordSnapshot(for: now)
        let minutesDone = Int((record?.studySeconds ?? 0) / 60)
        let exams = examSnapshots(upcomingOnly: true)
        let built = SessionBuilder(settings: settings, calendar: calendar, now: now).build(
            SessionSpec(kind: .daily, minutes: dailyBudgetMinutes(done: minutesDone), focusItemIDs: boostedItemsToday()),
            items: itemSnapshots(), exams: exams, confusions: confusionSnapshots(), topicNames: topicNames())
        var summary = TodaySummary(minutesGoal: settings.dailyMinutes + boostMinutesToday(), minutesDone: minutesDone,
                                   plannedMinutes: built.plannedMinutes, reviews: built.reviewCount,
                                   newItems: built.newCount, weakSpots: built.weakSpots.count,
                                   weakChips: built.weakChips, studiedToday: (record?.sessions ?? 0) > 0,
                                   sessionReady: !built.isEmpty, catchUp: built.catchUp != nil)
        summary.dueTotal = built.dueTotal
        summary.catchUpDaysToClear = built.catchUp?.daysToClear ?? 0
        summary.examEveExamID = exams.first { calendar.dayDistance(from: now, to: $0.date) == 1 }?.id
        return (summary, built)
    }

    /// Which exam a session serves (`SessionFocus`): the exam holding at least 40% of its minutes, its topics and the exams that wait.
    func sessionFocus(_ session: BuiltSession) -> SessionFocus {
        SessionFocus.make(session, exams: examSnapshots(upcomingOnly: true))
    }

    /// Readiness for `exam` once `session` is done ("about 52% after today"): the ring's own function over the session's questions
    /// at their expected states (`ReadinessEngine.valueAfter`), with the person's first-try rate for new ones.
    func readinessAfter(_ session: BuiltSession, for exam: ExamSnapshot) -> Double {
        let items = exam.courseID.flatMap { course($0) }.map { itemSnapshots(in: $0) } ?? []
        return ReadinessEngine(fsrs: fsrs, calendar: calendar, now: now)
            .valueAfter(session.entries, exam: exam, items: items, newItemSuccess: studyHabits().newItemSuccess)
    }

    /// The daily session's size: the goal (with what "Fix my week" added to today), or what's left of it today (at least 5 minutes once
    /// some is done).
    func dailyBudgetMinutes(done: Int? = nil) -> Int {
        let done = done ?? Int((dayRecordSnapshot(for: now)?.studySeconds ?? 0) / 60)
        let goal = settings.dailyMinutes + boostMinutesToday()
        return done > 0 ? max(5, goal - done) : goal
    }

    // MARK: Exams

    /// A course's next exam: its soonest live exam still to come (`date > now`), nil when it has none. The one definition of "the
    /// next exam" for the Library, the course page and Progress.
    func nextExam(of courseID: UUID) -> Exam? {
        let now = self.now
        return fetch(FetchDescriptor<Exam>(predicate: #Predicate { $0.deletedAt == nil && $0.date > now },
                                           sortBy: [SortDescriptor(\.date)]))
            .first { $0.course?.id == courseID && $0.course?.deletedAt == nil }
    }

    /// Readiness for an exam. The ring's number is the mean recall of its questions; the projected grade also knows how much of the
    /// material those questions reach (`coverage(for:)`).
    func readiness(for exam: Exam) -> ExamReadiness { readinessAndPlan(for: exam).readiness }

    /// Readiness and the plan it projects from, read together (the plan is the shared one, `examPlans()`).
    func readinessAndPlan(for exam: Exam) -> (readiness: ExamReadiness, plan: StudyPlan) {
        let snapshot = ExamSnapshot(exam)
        let items = itemSnapshots(in: exam.course)
        let plan = self.plan(for: exam)
        let readiness = ReadinessEngine(fsrs: fsrs, calendar: calendar, now: now).readiness(
            for: snapshot, items: items, topics: topicSnapshots(in: exam.course),
            logs: reviewSnapshots(courseID: exam.course?.id), plan: plan, grade: gradeModel(for: snapshot),
            coverage: coverage(for: exam)?.share)
        return (readiness, plan)
    }

    /// Readiness per topic for an exam, in topic order, without building a plan; each with its practice round's seconds.
    func topicReadiness(for exam: Exam) -> [TopicReadiness] {
        ReadinessEngine(fsrs: fsrs, calendar: calendar, now: now).topicReadiness(
            for: ExamSnapshot(exam), items: itemSnapshots(in: exam.course), topics: topicSnapshots(in: exam.course))
    }

    /// The exam's day-by-day plan and its projected readiness curve: its share of the daily goal (`examPlans()`); a past exam's
    /// plan on its own.
    func plan(for exam: Exam) -> StudyPlan {
        if let shared = examPlans().first(where: { $0.examID == exam.id }) { return shared }
        return planBuilder().plan(for: ExamSnapshot(exam), items: itemSnapshots(in: exam.course))
    }

    /// The exam's plan with days off (day offsets from today, `PlanDay.offset`): "What if I skip Saturday?". The same share of
    /// each day as `plan(for:)`, nothing on the skipped days.
    func plan(for exam: Exam, skipping: Set<Int>) -> StudyPlan {
        var builder = planBuilder()
        builder.capacity = sharedPlans().capacity[exam.id]
        builder.skipping = skipping
        return builder.plan(for: ExamSnapshot(exam), items: itemSnapshots(in: exam.course))
    }

    /// Every upcoming exam's plan, soonest exam first, sharing one daily goal: each exam is given what the sooner ones leave of
    /// each day (the easy-day share on easy days; today, what's left of today's goal). An exam's eve keeps its 10 minutes, and
    /// the later exams wait that day, as Today does on the eve. Cached per revision, hour and settings.
    func examPlans() -> [StudyPlan] { sharedPlans().plans }

    /// The shared plans and the seconds each exam was given per day offset.
    func sharedPlans() -> ExamPlanCache.Plans {
        let exams = examSnapshots(upcomingOnly: true)
        let key = ExamPlanCache.Key(revision: revision, hour: Int((now.timeIntervalSinceReferenceDate / 3600).rounded(.down)),
                                    dailyMinutes: settings.dailyMinutes, easyDays: settings.easyDays,
                                    retention: settings.targetRetention, examIDs: exams.map(\.id))
        if let cached = examPlanCache.plans, cached.key == key { return cached.value }
        let builder = planBuilder()
        let today = calendar.dayNumber(for: now)
        let goal = Double(settings.dailyMinutes * 60)
        let doneToday = dayRecordSnapshot(for: now)?.studySeconds ?? 0
        /// The day's goal in seconds: the easy-day share on easy days, with what "Fix my week" added, and today only what's left of it.
        func dayGoal(_ offset: Int) -> Double {
            let base = (builder.isEasyDay(today + offset) ? goal * StudyScheduler.easyDayCapacity : goal)
                + Double((builder.boosts[offset] ?? 0) * 60)
            return offset == 0 ? max(0, base - doneToday) : base
        }
        var left: [Int: Double] = [:]
        var eves = Set<Int>()
        var value = ExamPlanCache.Plans()
        var itemsByCourse: [UUID: [ItemSnapshot]] = [:]
        for exam in exams {
            let examDay = calendar.dayNumber(for: exam.date)
            let days = max(0, examDay - today)
            var capacity: [Int: Double] = [:]
            for offset in 0..<days {
                if offset == days - 1 {
                    capacity[offset] = PlanBuilder.examEveSeconds
                } else {
                    capacity[offset] = eves.contains(offset) ? 0 : left[offset] ?? dayGoal(offset)
                }
            }
            var b = builder
            b.capacity = capacity
            let items: [ItemSnapshot]
            if let c = exam.courseID {
                if let cached = itemsByCourse[c] { items = cached } else {
                    items = course(c).map { itemSnapshots(in: $0) } ?? []
                    itemsByCourse[c] = items
                }
            } else {
                items = []
            }
            let plan = b.plan(for: exam, items: items)
            for day in plan.days where day.kind != .exam {
                left[day.offset] = max(0, (left[day.offset] ?? dayGoal(day.offset)) - day.seconds)
            }
            if days > 0 { eves.insert(days - 1) }
            value.plans.append(plan)
            value.capacity[exam.id] = capacity
        }
        examPlanCache.plans = (key, value)
        return value
    }

    /// Readiness at the end of each of the last `days` days, oldest first (today: now).
    func readinessHistory(for exam: Exam, days: Int = 14) -> [ReadinessPoint] {
        ReadinessEngine(fsrs: fsrs, calendar: calendar, now: now).history(
            of: ExamSnapshot(exam), items: itemSnapshots(in: exam.course),
            logs: reviewSnapshots(courseID: exam.course?.id), days: days)
    }

    /// Readiness now for an exam snapshot (the session summary's before and after).
    func readinessValue(of exam: ExamSnapshot) -> Double {
        let items = exam.courseID.flatMap { course($0) }.map { itemSnapshots(in: $0) } ?? []
        return ReadinessEngine(fsrs: fsrs, calendar: calendar, now: now).value(of: exam, items: items)
    }

    /// The grade model for an exam: calibrated once two past exams have both readiness and a logged grade. The line is fitted to the
    /// readiness each exam was projected from (with its coverage taken into account), the same kind of value it is given later.
    func gradeModel(for exam: ExamSnapshot) -> GradeModel {
        let past = fetch(FetchDescriptor<Exam>(predicate: #Predicate {
            $0.deletedAt == nil && $0.resultScore != nil && $0.readinessAtExam != nil
        }))
        let history = past.compactMap { e -> (readiness: Double, score: Double)? in
            guard e.id != exam.id, let r = ExamSnapshot(e).adjustedReadinessAtExam, let s = e.resultScore else { return nil }
            return (r, s)
        }
        return GradeModel.make(format: exam.format, history: history)
    }

    /// The plan builder with the person's own habits, so projections stay honest: how often a first look at new
    /// material succeeds, and how much of a plan they tend to do.
    func planBuilder() -> PlanBuilder {
        var builder = PlanBuilder(settings: settings, calendar: calendar, now: now)
        let habits = studyHabits()
        builder.newItemSuccess = habits.newItemSuccess
        builder.adherence = habits.adherence
        (builder.boosts, builder.pinned) = planBoosts()
        return builder
    }

    /// First-try success on new items over the last 60 days (75% until there are 20 first looks), and the share
    /// of recent days studied, a freeze counting as missed (80% until there's a week of history).
    func studyHabits() -> (newItemSuccess: Double, adherence: Double) {
        let since = calendar.adding(days: -60, to: now)
        let newState = CardState.new.rawValue
        let firstLooks = fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate {
            $0.reviewedAt >= since && $0.stateBeforeRaw == newState
        }))
        var success = 0.75
        if firstLooks.count >= 20 {
            let good = firstLooks.filter { $0.ratingRaw >= Rating.hard.rawValue }.count
            success = Double(good) / Double(firstLooks.count)
        }
        let windowStart = calendar.adding(days: -14, to: calendar.startOfDay(for: now))
        let records = fetch(FetchDescriptor<DayRecord>(predicate: #Predicate { $0.day >= windowStart }))
            .filter { calendar.dayDistance(from: $0.day, to: now) >= 1 }
        var adherence = 0.8
        if let first = records.map(\.day).min() {
            let span = min(14, calendar.dayDistance(from: first, to: now))
            if span >= 7 {
                let studied = records.filter { $0.sessions > 0 }.count
                adherence = Double(studied) / Double(span)
            }
        }
        return (min(0.95, max(0.4, success)), min(0.95, max(0.5, adherence)))
    }

    // MARK: Courses

    /// A course's one number: readiness for its next exam (`nextExam(of:)`), the exam page's ring. Nil when no exam is to come.
    func courseReadiness(_ course: Course) -> (exam: Exam, value: Double)? {
        guard let exam = nextExam(of: course.id) else { return nil }
        return (exam, readinessValue(of: ExamSnapshot(exam)))
    }

    /// A course's topics in topic order, each with its active questions: what the course page lists, with or without an exam.
    func courseTopics(_ course: Course) -> [LibraryFormat.CourseTopic] {
        var counts: [UUID: Int] = [:]
        for item in course.items where item.deletedAt == nil && item.status == .active {
            if let topic = item.topicID { counts[topic, default: 0] += 1 }
        }
        return topicSnapshots(in: course)
            .sorted { $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder : $0.name < $1.name }
            .map { LibraryFormat.CourseTopic(id: $0.id, name: $0.name, questionCount: counts[$0.id] ?? 0) }
    }

    /// Current recall per topic of a course, in topic order (nil: a topic with no material yet). Internal: Ask Cap and Teach Cap read
    /// it to pick a weak topic; no screen shows it as a number (each exam's readiness is the only learning percentage).
    func topicMastery(course: Course) -> [TopicReadiness] {
        ReadinessEngine(fsrs: fsrs, calendar: calendar, now: now)
            .topicMastery(courseID: course.id, items: itemSnapshots(in: course), topics: topicSnapshots(in: course))
    }

    // MARK: Habit

    func streak() -> StreakState {
        StreakEngine(calendar: calendar, now: now, dailyMinutes: settings.dailyMinutes).state(daySnapshots())
    }

    /// Whole calendar weeks of studied minutes ending with this week, oldest first.
    func heatmap(weeks: Int = 12) -> [HeatmapCell] {
        let since = calendar.adding(days: -(weeks + 1) * 7, to: now)
        return StreakEngine(calendar: calendar, now: now, dailyMinutes: settings.dailyMinutes)
            .heatmap(daySnapshots(since: since), weeks: weeks)
    }

    /// This calendar week's minutes, with last week's total for comparison.
    func weeklyStats() -> WeeklyStats {
        StreakEngine(calendar: calendar, now: now, dailyMinutes: settings.dailyMinutes)
            .weekly(daySnapshots(since: calendar.adding(days: -15, to: now)))
    }

    /// Reviews due on each of the next `days` days (today includes anything overdue).
    func dueForecast(days: Int = 7) -> [DueForecastDay] {
        DueForecastDay.forecast(items: itemSnapshots(), calendar: calendar, now: now, days: days)
    }

    /// Share of reviews of learned items answered right over the last `days` days (nil with none):
    /// "you remember 91% of what you review".
    func retentionRate(days: Int = 30) -> Double? {
        ReadinessEngine.trueRetention(reviewSnapshots(since: calendar.adding(days: -days, to: now)))
    }

    // MARK: Confusions

    /// Mix-ups worth naming from the last 14 days of answers (deterministic; the AI lane may rename them).
    func confusionCandidates() -> [ConfusionCandidate] {
        let finder = ConfusionFinder(calendar: calendar, now: now)
        let logs = reviewSnapshots(since: calendar.adding(days: -finder.windowDays, to: now))
        let courseIDs = Set(logs.filter { !$0.wasCorrect }.compactMap(\.courseID))
        guard !courseIDs.isEmpty else { return [] }
        let infos = courses.filter { courseIDs.contains($0.id) }.flatMap { course in
            course.items.filter { $0.deletedAt == nil && $0.status == .active }.map { ItemAnswerInfo($0, courseID: course.id) }
        }
        return finder.candidates(items: infos, logs: logs, existing: confusionSnapshots(), topicNames: topicNames())
    }
}

// MARK: - The shared plans

/// Every upcoming exam's plan for one revision, hour and set of settings (`AppModel.sharedPlans()`). They are built together, since
/// each exam's share of a day depends on the sooner exams, and every screen that shows a readiness reads them.
final class ExamPlanCache {
    struct Key: Equatable {
        var revision: Int
        var hour: Int
        var dailyMinutes: Int
        var easyDays: [Int]
        var retention: Double
        var examIDs: [UUID]
    }

    struct Plans {
        /// Soonest exam first.
        var plans: [StudyPlan] = []
        /// The seconds each exam was given, by day offset from today (`PlanBuilder.capacity`).
        var capacity: [UUID: [Int: Double]] = [:]
    }

    var plans: (key: Key, value: Plans)?
}

// MARK: - Snapshots (fetched once per call)

extension AppModel {
    var fsrs: FSRS { FSRS(desiredRetention: settings.targetRetention) }

    /// Active items in live courses.
    func itemSnapshots() -> [ItemSnapshot] {
        let active = ItemStatus.active.rawValue
        let items = fetch(FetchDescriptor<StudyItem>(predicate: #Predicate { $0.deletedAt == nil && $0.statusRaw == active }))
        return items.compactMap { item in
            let course = item.course
            if let course, course.deletedAt != nil { return nil }
            return ItemSnapshot(item, courseID: course?.id)
        }
    }

    /// One course's active items.
    func itemSnapshots(in course: Course?) -> [ItemSnapshot] {
        guard let course, course.deletedAt == nil else { return [] }
        return course.items.filter { $0.deletedAt == nil && $0.status == .active }
            .map { ItemSnapshot($0, courseID: course.id) }
    }

    /// Specific items in the given order, any status but rejected (a quick check may run on a fresh draft).
    func itemSnapshots(ids: [UUID]) -> [ItemSnapshot] {
        ids.compactMap { id in
            guard let item = item(id), item.deletedAt == nil, item.status != .rejected else { return nil }
            return ItemSnapshot(item, courseID: item.course?.id)
        }
    }

    func examSnapshots(upcomingOnly: Bool = false) -> [ExamSnapshot] {
        let exams = fetch(FetchDescriptor<Exam>(predicate: #Predicate { $0.deletedAt == nil },
                                                sortBy: [SortDescriptor(\.date)]))
        return exams.filter { ($0.course?.deletedAt == nil) && (!upcomingOnly || $0.date > now) }.map(ExamSnapshot.init)
    }

    func confusionSnapshots() -> [ConfusionSnapshot] {
        fetch(FetchDescriptor<Confusion>(predicate: #Predicate { $0.deletedAt == nil })).map(ConfusionSnapshot.init)
    }

    func topicSnapshots(in course: Course?) -> [TopicSnapshot] {
        guard let course else { return [] }
        return course.topics.filter { $0.deletedAt == nil }
            .map { TopicSnapshot(id: $0.id, courseID: course.id, name: $0.name, sortOrder: $0.sortOrder) }
    }

    func topicNames() -> [UUID: String] {
        let topics = fetch(FetchDescriptor<Topic>(predicate: #Predicate { $0.deletedAt == nil }))
        return Dictionary(topics.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    func daySnapshots(since: Date? = nil) -> [DaySnapshot] {
        let records: [DayRecord]
        if let since {
            let start = calendar.startOfDay(for: since)
            records = fetch(FetchDescriptor<DayRecord>(predicate: #Predicate { $0.day >= start }))
        } else {
            records = fetch(FetchDescriptor<DayRecord>())
        }
        return records.map(DaySnapshot.init)
    }

    func dayRecordSnapshot(for date: Date) -> DaySnapshot? {
        dayRecord(key: calendar.dayKey(for: date)).map(DaySnapshot.init)
    }

    func dayRecord(key: String) -> DayRecord? {
        fetch(FetchDescriptor<DayRecord>(predicate: #Predicate { $0.dayKey == key })).first
    }

    func reviewSnapshots(courseID: UUID?) -> [ReviewSnapshot] {
        guard courseID != nil else { return [] }
        let cid: UUID? = courseID
        return fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.courseID == cid },
                                                sortBy: [SortDescriptor(\.reviewedAt)])).map(ReviewSnapshot.init)
    }

    func reviewSnapshots(since: Date) -> [ReviewSnapshot] {
        fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.reviewedAt >= since },
                                         sortBy: [SortDescriptor(\.reviewedAt)])).map(ReviewSnapshot.init)
    }
}

extension ItemSnapshot {
    init(_ item: StudyItem, courseID: UUID?) {
        self.init(id: item.id, kind: item.kind, topicID: item.topicID, courseID: courseID, memory: item.memory,
                  status: item.status, createdAt: item.createdAt, difficultyHint: item.difficultyHint)
    }
}

extension ExamSnapshot {
    init(_ exam: Exam) {
        self.init(id: exam.id, courseID: exam.course?.id, title: exam.title, date: exam.date, scope: Set(exam.scope),
                  target: exam.targetReadiness, format: exam.format, readinessAtExam: exam.readinessAtExam,
                  resultScore: exam.resultScore, coverageAtExam: exam.coverageAtExam)
    }
}

extension ConfusionSnapshot {
    init(_ c: Confusion) {
        self.init(id: c.id, courseID: c.course?.id, name: c.name, itemIDs: c.itemIDs, fixItemIDs: c.fix?.itemIDs ?? [],
                  status: c.status, missCount: c.missCount, lastSeenAt: c.lastSeenAt)
    }
}

extension ReviewSnapshot {
    init(_ log: ReviewLog) {
        self.init(itemID: log.itemID, courseID: log.courseID, sessionID: log.sessionID, reviewedAt: log.reviewedAt,
                  rating: log.rating, score: log.score, answer: log.answer,
                  stateBefore: CardState(rawValue: log.stateBeforeRaw) ?? .new, stabilityAfter: log.stabilityAfter,
                  difficultyAfter: log.difficultyAfter, durationMs: log.durationMs)
    }
}

extension DaySnapshot {
    init(_ r: DayRecord) {
        self.init(dayKey: r.dayKey, day: r.day, studySeconds: r.studySeconds, itemsReviewed: r.itemsReviewed,
                  sessions: r.sessions, frozen: r.frozen, repaired: r.repaired, questMask: r.questMask)
    }
}

extension ItemAnswerInfo {
    /// Every answer that counts for the item: the model answer, correct choices, cloze blanks and their
    /// alternates.
    init(_ item: StudyItem, courseID: UUID?) {
        var accepted = [item.answer]
        accepted += item.choices.filter(\.correct).map(\.text)
        if let cloze = item.cloze {
            accepted += cloze.answers
            accepted += cloze.alternates.flatMap { $0 }
        }
        self.init(id: item.id, courseID: courseID, topicID: item.topicID, prompt: item.prompt, expected: item.answer,
                  accepted: accepted)
    }
}
