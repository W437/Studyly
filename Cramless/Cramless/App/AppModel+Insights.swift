import Foundation
import SwiftData

// The read API over the engines: what Today, Progress, the exam screens, the widget and notifications show.
// Each call fetches its snapshots once and hands them to a pure engine (Engine/). Call these from a view's body
// or a task keyed on `app.revision`; never loop over models in a view.
extension AppModel {
    // MARK: Today

    /// Today's card: the daily session as it would be built now, and what's done.
    func todaySummary() -> TodaySummary {
        let record = dayRecordSnapshot(for: now)
        let minutesDone = Int((record?.studySeconds ?? 0) / 60)
        let exams = examSnapshots(upcomingOnly: true)
        let built = SessionBuilder(settings: settings, calendar: calendar, now: now).build(
            SessionSpec(kind: .daily, minutes: dailyBudgetMinutes(done: minutesDone)),
            items: itemSnapshots(), exams: exams, confusions: confusionSnapshots(), topicNames: topicNames())
        var summary = TodaySummary(minutesGoal: settings.dailyMinutes, minutesDone: minutesDone,
                                   plannedMinutes: built.plannedMinutes, reviews: built.reviewCount,
                                   newItems: built.newCount, weakSpots: built.weakSpots.count,
                                   weakChips: built.weakChips, studiedToday: (record?.sessions ?? 0) > 0,
                                   sessionReady: !built.isEmpty, catchUp: built.catchUp != nil)
        summary.dueTotal = built.dueTotal
        summary.catchUpDaysToClear = built.catchUp?.daysToClear ?? 0
        summary.examEveExamID = exams.first { calendar.dayDistance(from: now, to: $0.date) == 1 }?.id
        return summary
    }

    /// The daily session's size: the goal, or what's left of it today (at least 5 minutes once some is done).
    func dailyBudgetMinutes(done: Int? = nil) -> Int {
        let done = done ?? Int((dayRecordSnapshot(for: now)?.studySeconds ?? 0) / 60)
        return done > 0 ? max(5, settings.dailyMinutes - done) : settings.dailyMinutes
    }

    // MARK: Exams

    func readiness(for exam: Exam) -> ExamReadiness {
        let snapshot = ExamSnapshot(exam)
        let items = itemSnapshots(in: exam.course)
        let plan = planBuilder().plan(for: snapshot, items: items)
        return ReadinessEngine(fsrs: fsrs, calendar: calendar, now: now).readiness(
            for: snapshot, items: items, topics: topicSnapshots(in: exam.course),
            logs: reviewSnapshots(courseID: exam.course?.id), plan: plan, grade: gradeModel(for: snapshot))
    }

    /// The exam's day-by-day plan and its projected readiness curve.
    func plan(for exam: Exam) -> StudyPlan {
        planBuilder().plan(for: ExamSnapshot(exam), items: itemSnapshots(in: exam.course))
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

    /// The grade model for an exam: calibrated once two past exams have both readiness and a logged grade.
    func gradeModel(for exam: ExamSnapshot) -> GradeModel {
        let past = fetch(FetchDescriptor<Exam>(predicate: #Predicate {
            $0.deletedAt == nil && $0.resultScore != nil && $0.readinessAtExam != nil
        }))
        let history = past.compactMap { e -> (readiness: Double, score: Double)? in
            guard e.id != exam.id, let r = e.readinessAtExam, let s = e.resultScore else { return nil }
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

    /// Mean current recall over a course's studied items, 0…1.
    func mastery(of course: Course) -> Double {
        ReadinessEngine(fsrs: fsrs, calendar: calendar, now: now).mastery(of: itemSnapshots(in: course))
    }

    /// Current recall per topic of a course, in topic order (nil: a topic with no material yet).
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
                  resultScore: exam.resultScore)
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
