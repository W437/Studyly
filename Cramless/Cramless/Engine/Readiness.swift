import Foundation

/// Turns readiness into a projected exam grade.
///
/// Uncalibrated (the default): the share of the material recalled, plus a little for guessing on the multiple
/// choice share of the exam (a quarter of what isn't known): `percent = g + (1 − g) · readiness` with
/// `g = 0.25 × (multiple-choice share)`, so a mixed multiple-choice and short-answer exam gets g = 0.125.
/// Calibrated: once two or more past exams have both `readinessAtExam` and a logged `resultScore`, a
/// least-squares line `percent = a + b · readiness` through them (slope kept within 0.2…2; with no spread in
/// readiness, the default slope shifted to their mean). Always shown as a projection.
struct GradeModel: Sendable, Equatable {
    var intercept: Double
    var slope: Double
    var isCalibrated: Bool

    static func uncalibrated(for format: ExamFormat) -> GradeModel {
        let parts = [format.multipleChoice, format.shortAnswer, format.essay].filter { $0 }.count
        let multipleChoiceShare = format.multipleChoice ? 1 / Double(max(1, parts)) : 0
        let guess = 0.25 * multipleChoiceShare
        return GradeModel(intercept: guess, slope: 1 - guess, isCalibrated: false)
    }

    /// The model for an exam: calibrated from past exams when there are at least two, else the default.
    static func make(format: ExamFormat, history: [(readiness: Double, score: Double)]) -> GradeModel {
        let base = uncalibrated(for: format)
        guard history.count >= 2 else { return base }
        let n = Double(history.count)
        let mx = history.map(\.readiness).reduce(0, +) / n
        let my = history.map(\.score).reduce(0, +) / n
        let vx = history.reduce(0) { $0 + ($1.readiness - mx) * ($1.readiness - mx) }
        let cov = history.reduce(0) { $0 + ($1.readiness - mx) * ($1.score - my) }
        let slope = vx > 1e-6 ? min(2, max(0.2, cov / vx)) : base.slope
        return GradeModel(intercept: my - slope * mx, slope: slope, isCalibrated: true)
    }

    func percent(_ readiness: Double) -> Double { min(1, max(0, intercept + slope * readiness)) }

    func grade(_ readiness: Double) -> ProjectedGrade {
        let p = percent(readiness)
        return ProjectedGrade(percent: p, letter: Self.letter(p), isCalibrated: isCalibrated)
    }

    /// The usual US letter scale.
    static func letter(_ percent: Double) -> String {
        let p = (percent * 100).rounded()
        switch p {
        case 97...: return "A+"
        case 93..<97: return "A"
        case 90..<93: return "A−"
        case 87..<90: return "B+"
        case 83..<87: return "B"
        case 80..<83: return "B−"
        case 77..<80: return "C+"
        case 73..<77: return "C"
        case 70..<73: return "C−"
        case 67..<70: return "D+"
        case 63..<67: return "D"
        case 60..<63: return "D−"
        default: return "F"
        }
    }
}

/// Readiness and mastery, from item memories (now) and the review log (the past).
/// - Exam readiness: mean predicted recall on exam day over the exam's active items; never-studied items count 0.
/// - Topic readiness: the same per topic; nil when a topic has no items (a coverage gap).
/// - Mastery: mean current recall of studied items.
/// - The past (a week ago, a chart's history): each item's state rebuilt from the last review-log entry before
///   that moment (`stabilityAfter` at `reviewedAt`); items with no log at all but a memory (an Anki import) use
///   their memory once their last review is in the past of that moment.
struct ReadinessEngine: Sendable {
    var fsrs: FSRS
    var calendar: Calendar
    var now: Date

    init(fsrs: FSRS = FSRS(), calendar: Calendar, now: Date) {
        self.fsrs = fsrs
        self.calendar = calendar
        self.now = now
    }

    func recall(stability: Double, last: Date, on date: Date) -> Double {
        fsrs.retrievability(elapsedDays: Double(max(0, FSRS.elapsedDays(from: last, to: date))), stability: stability)
    }

    func examRecall(_ memory: MemoryState, on date: Date) -> Double {
        guard memory.state != .new, let last = memory.lastReview, memory.stability > 0 else { return 0 }
        return recall(stability: memory.stability, last: last, on: date)
    }

    func scope(of exam: ExamSnapshot, in items: [ItemSnapshot]) -> [ItemSnapshot] {
        items.filter { $0.isActive && exam.covers($0) }
    }

    /// Mean predicted recall on exam day over the exam's active items (0 with no items).
    func value(of exam: ExamSnapshot, items: [ItemSnapshot]) -> Double {
        let scope = scope(of: exam, in: items)
        guard !scope.isEmpty else { return 0 }
        return scope.reduce(0) { $0 + examRecall($1.memory, on: exam.date) } / Double(scope.count)
    }

    /// Readiness as it stood at `date`, rebuilt from the review log. `logsByItem` must be sorted by time.
    func value(of exam: ExamSnapshot, items: [ItemSnapshot], at date: Date,
               logsByItem: [UUID: [ReviewSnapshot]]) -> Double {
        let scope = scope(of: exam, in: items)
        guard !scope.isEmpty else { return 0 }
        var sum = 0.0
        for item in scope {
            if let logs = logsByItem[item.id], !logs.isEmpty {
                if let last = Self.last(logs, before: date) {
                    sum += recall(stability: last.stabilityAfter, last: last.reviewedAt, on: exam.date)
                }
            } else if item.isStudied, let last = item.memory.lastReview, last < date {
                sum += examRecall(item.memory, on: exam.date)
            }
        }
        return sum / Double(scope.count)
    }

    /// The last entry strictly before `date` (binary search over entries sorted by time).
    static func last(_ logs: [ReviewSnapshot], before date: Date) -> ReviewSnapshot? {
        var lo = 0, hi = logs.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if logs[mid].reviewedAt < date { lo = mid + 1 } else { hi = mid }
        }
        return lo > 0 ? logs[lo - 1] : nil
    }

    /// Share of reviews of learned items (in review before the answer) answered right; nil with none.
    static func trueRetention(_ logs: [ReviewSnapshot]) -> Double? {
        let reviews = logs.filter { $0.stateBefore == .review }
        guard !reviews.isEmpty else { return nil }
        return Double(reviews.filter(\.wasCorrect).count) / Double(reviews.count)
    }

    static func byItem(_ logs: [ReviewSnapshot]) -> [UUID: [ReviewSnapshot]] {
        Dictionary(grouping: logs, by: \.itemID).mapValues { $0.sorted { $0.reviewedAt < $1.reviewedAt } }
    }

    /// Per topic in the exam's scope (the scope's topics, or all the course's topics), in topic order.
    func topicReadiness(for exam: ExamSnapshot, items: [ItemSnapshot], topics: [TopicSnapshot]) -> [TopicReadiness] {
        let scope = scope(of: exam, in: items)
        var sums: [UUID: (Double, Int)] = [:]
        for item in scope {
            guard let t = item.topicID else { continue }
            let r = examRecall(item.memory, on: exam.date)
            let s = sums[t] ?? (0, 0)
            sums[t] = (s.0 + r, s.1 + 1)
        }
        let listed = topics.filter { $0.courseID == exam.courseID && (exam.wholeCourse || exam.scope.contains($0.id)) }
            .sorted { $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder : $0.name < $1.name }
        return listed.map { t in
            let s = sums[t.id]
            return TopicReadiness(id: t.id, name: t.name, value: s.map { $0.0 / Double($0.1) }, itemCount: s?.1 ?? 0)
        }
    }

    /// Mean current recall of the studied, active items (0 when nothing is studied).
    func mastery(of items: [ItemSnapshot]) -> Double {
        let studied = items.filter { $0.isActive && $0.isStudied }
        guard !studied.isEmpty else { return 0 }
        return studied.reduce(0) { $0 + fsrs.retrievability(of: $1.memory, at: now) } / Double(studied.count)
    }

    /// Current recall per topic of a course, in topic order: nil for a topic with no items (a coverage gap), 0
    /// for one with items none of which are studied yet.
    func topicMastery(courseID: UUID, items: [ItemSnapshot], topics: [TopicSnapshot]) -> [TopicReadiness] {
        var stats: [UUID: (sum: Double, studied: Int, count: Int)] = [:]
        for item in items where item.isActive && item.courseID == courseID {
            guard let t = item.topicID else { continue }
            var s = stats[t] ?? (0, 0, 0)
            s.count += 1
            if item.isStudied {
                s.sum += fsrs.retrievability(of: item.memory, at: now)
                s.studied += 1
            }
            stats[t] = s
        }
        return topics.filter { $0.courseID == courseID }
            .sorted { $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder : $0.name < $1.name }
            .map { t in
                guard let s = stats[t.id], s.count > 0 else {
                    return TopicReadiness(id: t.id, name: t.name, value: nil, itemCount: 0)
                }
                return TopicReadiness(id: t.id, name: t.name, value: s.studied > 0 ? s.sum / Double(s.studied) : 0,
                                      itemCount: s.count)
            }
    }

    /// Readiness at the end of each of the last `days` days (today: now), oldest first.
    func history(of exam: ExamSnapshot, items: [ItemSnapshot], logs: [ReviewSnapshot], days: Int) -> [ReadinessPoint] {
        let count = max(1, days)
        let today = calendar.dayNumber(for: now)
        let grid = DayGrid(calendar: calendar, firstDay: today - count + 1, count: count + 1)
        let byItem = Self.byItem(logs)
        return ((today - count + 1)...today).map { day in
            let v = day == today
                ? value(of: exam, items: items)
                : value(of: exam, items: items, at: grid.end(ofDay: day), logsByItem: byItem)
            return ReadinessPoint(date: grid.start(ofDay: day), value: v, isProjection: false)
        }
    }

    /// Everything the exam screens show.
    func readiness(for exam: ExamSnapshot, items: [ItemSnapshot], topics: [TopicSnapshot], logs: [ReviewSnapshot],
                   plan: StudyPlan, grade: GradeModel) -> ExamReadiness {
        let scope = scope(of: exam, in: items)
        let current = value(of: exam, items: items)
        let weekAgo = value(of: exam, items: items, at: calendar.adding(days: -7, to: now), logsByItem: Self.byItem(logs))
        let topicList = topicReadiness(for: exam, items: items, topics: topics)
        return ExamReadiness(examID: exam.id, value: current, projected: plan.projectedReadiness,
                             deltaThisWeek: current - weekAgo,
                             daysLeft: max(0, calendar.dayDistance(from: now, to: exam.date)), topics: topicList,
                             projectedGrade: grade.grade(plan.projectedReadiness), itemsInScope: scope.count,
                             unseenItems: scope.filter { !$0.isStudied }.count, target: exam.target,
                             targetReachedOn: plan.targetReachedOn,
                             coverageGaps: topicList.filter { $0.value == nil }.count)
    }
}
