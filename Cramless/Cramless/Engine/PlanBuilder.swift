import Foundation

/// One day of an exam plan.
struct PlanDay: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable {
        /// A normal study day.
        case study
        /// An easy day (settings.easyDays): no new material, a lighter session.
        case light
        /// Nothing for this exam that day.
        case rest
        /// The night before: weak spots only, at most 10 minutes, then stop.
        case examEve
        case exam
    }

    /// The start of the local day.
    var date: Date
    var dayNumber: Int
    var kind: Kind
    /// Minutes this exam's planned work takes that day (reviews, new items, the eve's weak spots).
    var minutes: Int
    /// The whole session planned that day: the daily goal (half on an easy day), more when this exam needs it;
    /// on the exam eve, just the eve's review.
    var sessionMinutes: Int
    var newItems: Int
    var reviews: Int
    var isToday: Bool
    var isEasyDay: Bool

    var id: Int { dayNumber }
}

/// A point on a readiness chart.
struct ReadinessPoint: Sendable, Equatable, Identifiable {
    var date: Date
    /// 0…1.
    var value: Double
    /// True for the future part of a chart (the plan's projection).
    var isProjection: Bool

    var id: Date { date }
}

/// An exam's plan: what to do each day until the exam, and where readiness gets to if it's followed.
struct StudyPlan: Sendable, Equatable {
    var examID: UUID
    var target: Double
    var daysLeft: Int
    /// The person's daily goal.
    var dailyMinutes: Int
    var itemsInScope: Int
    /// Items in scope not studied yet.
    var newItems: Int
    var reviewsPlanned: Int
    /// Today through the exam day.
    var days: [PlanDay]
    /// The day the last new material goes in (about three days before the exam).
    var lastIntroDay: Date?
    var examEve: Date?
    /// Readiness now, then at the start of each following day up to the exam morning, if the plan is followed.
    var curve: [ReadinessPoint]
    /// Readiness on exam morning if the plan is followed (the last point of `curve`).
    var projectedReadiness: Double
    /// The first day the projection reaches the target ("your path to 90% by Nov 14"); nil if it doesn't.
    var targetReachedOn: Date?
    /// Set when this exam alone needs more than the daily goal on some day: the minutes to suggest.
    var suggestedMinutes: Int?

    var currentReadiness: Double { curve.first?.value ?? 0 }
}

/// Shared arithmetic for spreading new material before an exam (the session builder uses it for today's share).
enum PlanMath {
    /// New material is in by this many days before the exam.
    static let introLeadDays = 3

    /// The last day new material goes in: about three days before the exam, today if the exam is that close.
    static func lastIntroDay(today: Int, examDay: Int) -> Int { max(today, examDay - introLeadDays) }

    /// New items per day from today through `lastIntroDay`, weighted by day (an easy day takes none unless it's
    /// the only day), earlier days rounding up.
    static func newItemsPerDay(unseen: Int, today: Int, examDay: Int, isEasyDay: (Int) -> Bool) -> [Int: Int] {
        guard unseen > 0 else { return [:] }
        let last = lastIntroDay(today: today, examDay: examDay)
        let days = Array(today...last)
        var weights = days.map { isEasyDay($0) ? 0.0 : 1.0 }
        if weights.allSatisfy({ $0 == 0 }) { weights = days.map { _ in 1.0 } }
        let total = weights.reduce(0, +)
        var out: [Int: Int] = [:]
        var cumulative = 0.0
        var given = 0
        for (i, day) in days.enumerated() {
            cumulative += weights[i]
            let target = i == days.count - 1
                ? unseen
                : min(unseen, Int((Double(unseen) * cumulative / total - 1e-9).rounded(.up)))
            let n = max(0, target - given)
            if n > 0 { out[day] = n }
            given += n
        }
        return out
    }

    static func newItemsToday(unseen: Int, today: Int, examDay: Int, isEasyDay: (Int) -> Bool) -> Int {
        newItemsPerDay(unseen: unseen, today: today, examDay: examDay, isEasyDay: isEasyDay)[today] ?? 0
    }
}

/// Builds an exam's day-by-day plan and its projected readiness curve by simulating FSRS forward:
/// - new material is introduced by ~3 days before the exam, spread over the days left (none on easy days);
/// - reviews happen on their due days; an item whose next due would miss the exam while its exam-day recall is
///   under target is pulled to 1–3 days before (the scheduler's exam capping);
/// - the last evening is the exam eve: weak spots only, at most 10 minutes;
/// - reviews already overdue (a missed day) are spread over the next three days, so a miss bends into the
///   following days instead of piling onto one;
/// - each simulated review assumes recall as likely as FSRS predicts: the new state is the expected one
///   (recalled with probability R, otherwise forgotten and relearned);
/// - a first look at new material succeeds with the person's own first-try rate (`newItemSuccess`, 75% until
///   there is history), the rest are relearned;
/// - the projection counts only the share of the plan the person tends to do (`adherence`, from the last two
///   weeks' study days; 80% until there is history): projected = now + adherence × (plan − now).
/// The plan is recomputed from the current memory every time, which is what makes it bend. All of this keeps the
/// projection a projection: optimistic numbers would make the readiness score worthless.
struct PlanBuilder: Sendable {
    var fsrs: FSRS
    var calendar: Calendar
    var now: Date
    var dailyMinutes: Int
    var easyDays: Set<Int>
    /// The chance a first look at a new item is recalled right away (else it's relearned).
    var newItemSuccess: Double = 0.75
    /// The share of planned study the person actually does, 0…1.
    var adherence: Double = 0.8

    /// Simulated reviews happen at this local hour.
    static let reviewHour = 18.0
    static let overdueSpreadDays = 3
    static let examEveSeconds = Double(SessionBuilder.examEveMinutes * 60)

    init(fsrs: FSRS, calendar: Calendar, now: Date, dailyMinutes: Int, easyDays: [Int] = []) {
        self.fsrs = fsrs
        self.calendar = calendar
        self.now = now
        self.dailyMinutes = dailyMinutes
        self.easyDays = Set(easyDays)
    }

    init(settings: AppSettings, calendar: Calendar, now: Date) {
        self.init(fsrs: FSRS(desiredRetention: settings.targetRetention), calendar: calendar, now: now,
                  dailyMinutes: settings.dailyMinutes, easyDays: settings.easyDays)
    }

    func isEasyDay(_ day: Int) -> Bool {
        !easyDays.isEmpty && easyDays.contains(Calendar.weekday(dayNumber: day))
    }

    private struct Sim {
        var item: ItemSnapshot
        var s: Double
        var d: Double
        var last: Date
        var examRecall: Double
    }

    private func recall(stability: Double, last: Date, on date: Date) -> Double {
        fsrs.retrievability(elapsedDays: Double(max(0, FSRS.elapsedDays(from: last, to: date))), stability: stability)
    }

    /// The expected state after a review at `when`.
    private func expectedReview(_ sim: inout Sim, at when: Date) {
        let elapsed = max(0, FSRS.elapsedDays(from: sim.last, to: when))
        let p = fsrs.retrievability(elapsedDays: Double(elapsed), stability: sim.s)
        let sGood: Double, sLapse: Double
        if elapsed < 1 {
            sGood = fsrs.shortTermStability(sim.s, rating: .good)
            sLapse = fsrs.shortTermStability(fsrs.shortTermStability(sim.s, rating: .again), rating: .good)
        } else {
            sGood = fsrs.nextStability(difficulty: sim.d, stability: sim.s, retrievability: p, rating: .good)
            let forgot = fsrs.nextStability(difficulty: sim.d, stability: sim.s, retrievability: p, rating: .again)
            sLapse = fsrs.shortTermStability(forgot, rating: .good)
        }
        let dGood = fsrs.nextDifficulty(sim.d, rating: .good)
        let dLapse = fsrs.nextDifficulty(fsrs.nextDifficulty(sim.d, rating: .again), rating: .good)
        sim.s = p * sGood + (1 - p) * sLapse
        sim.d = p * dGood + (1 - p) * dLapse
        sim.last = when
    }

    func plan(for exam: ExamSnapshot, items: [ItemSnapshot]) -> StudyPlan {
        let today = calendar.dayNumber(for: now)
        let examDay = calendar.dayNumber(for: exam.date)
        let daysLeft = max(0, examDay - today)
        let scope = items.filter { $0.isActive && exam.covers($0) }
        let n = Double(scope.count)
        let grid = DayGrid(calendar: calendar, firstDay: today, count: daysLeft + 2)

        var sims: [Sim] = []
        var dueDays: [Int] = []
        var unseen: [ItemSnapshot] = []
        for item in scope {
            if item.isStudied, let last = item.memory.lastReview {
                sims.append(Sim(item: item, s: item.memory.stability, d: item.memory.difficulty, last: last,
                                examRecall: recall(stability: item.memory.stability, last: last, on: exam.date)))
                dueDays.append(item.memory.due.map { grid.dayNumber(for: $0) } ?? today)
            } else {
                unseen.append(item)
            }
        }
        var sum = sims.reduce(0) { $0 + $1.examRecall }
        var curve = [ReadinessPoint(date: now, value: n > 0 ? sum / n : 0, isProjection: false)]
        var plan = StudyPlan(examID: exam.id, target: exam.target, daysLeft: daysLeft, dailyMinutes: dailyMinutes,
                             itemsInScope: scope.count, newItems: unseen.count, reviewsPlanned: 0, days: [],
                             lastIntroDay: nil, examEve: nil, curve: curve, projectedReadiness: curve[0].value,
                             targetReachedOn: nil, suggestedMinutes: nil)
        guard examDay > today else {
            plan.days = [PlanDay(date: grid.start(ofDay: today), dayNumber: today, kind: .exam, minutes: 0,
                                 sessionMinutes: 0, newItems: 0, reviews: 0, isToday: true, isEasyDay: isEasyDay(today))]
            plan.targetReachedOn = curve[0].value >= exam.target ? now : nil
            return plan
        }
        plan.examEve = grid.start(ofDay: examDay - 1)
        if !unseen.isEmpty { plan.lastIntroDay = grid.start(ofDay: PlanMath.lastIntroDay(today: today, examDay: examDay)) }

        // Where each studied item's next review falls. Overdue ones spread over the next few days.
        var buckets: [Int: [Int]] = [:]
        var load: [Int: Int] = [:]
        let overdue = sims.indices.filter { dueDays[$0] < today }
            .sorted { recall(stability: sims[$0].s, last: sims[$0].last, on: now)
                < recall(stability: sims[$1].s, last: sims[$1].last, on: now) }
        let overdueSeconds = overdue.reduce(0.0) { $0 + sims[$1].item.kind.typicalSeconds }
        let spread = overdueSeconds > Double(dailyMinutes * 60)
            ? min(Self.overdueSpreadDays, max(1, examDay - today - 1)) : 1
        for (k, i) in overdue.enumerated() { dueDays[i] = today + k * spread / max(1, overdue.count) }
        for i in sims.indices where dueDays[i] < examDay {
            let day = max(today, dueDays[i])
            buckets[day, default: []].append(i)
            load[day, default: 0] += 1
        }
        // Items scheduled past the exam (before it was set) that would be under target: pulled in like the
        // session builder's exam priority, 1–3 days before.
        let pullWindow = StudyScheduler.examPullWindow.map { examDay - $0 }.filter { $0 >= today }
        for i in sims.indices where dueDays[i] >= examDay && sims[i].examRecall < exam.target {
            guard let day = pullWindow.min(by: { (load[$0] ?? 0, -$0) < (load[$1] ?? 0, -$1) }) else { break }
            buckets[day, default: []].append(i)
            load[day, default: 0] += 1
        }

        /// The day of the next review after one at `day`, or nil when it falls after the exam.
        func nextDue(_ sim: Sim, after day: Int) -> Int? {
            let due = day + fsrs.nextInterval(stability: sim.s)
            if due < examDay { return due }
            guard sim.examRecall < exam.target else { return nil }
            let window = StudyScheduler.examPullWindow.map { examDay - $0 }.filter { $0 > day }
            return window.min { (load[$0] ?? 0, -$0) < (load[$1] ?? 0, -$1) }
        }

        let intro = PlanMath.newItemsPerDay(unseen: unseen.count, today: today, examDay: examDay, isEasyDay: isEasyDay)
        var queue = unseen.sorted {
            $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.difficultyHint < $1.difficultyHint
        }[...]
        var days: [PlanDay] = []
        var reviewsPlanned = 0
        for day in today..<examDay {
            let isEve = day == examDay - 1
            var when = grid.start(ofDay: day).addingTimeInterval(Self.reviewHour * 3600)
            if day == today { when = max(now, when) }
            if when >= exam.date { when = max(now, exam.date.addingTimeInterval(-3600)) }
            var seconds = 0.0, reviews = 0, news = 0
            var doneToday = Set<Int>()

            for _ in 0..<(intro[day] ?? 0) {
                guard let item = queue.popFirst() else { break }
                // First look and one learning step: Good with the person's first-try rate, else Again and relearned.
                let p0 = min(1, max(0, newItemSuccess))
                let sGood = fsrs.shortTermStability(fsrs.initialStability(.good), rating: .good)
                let sAgain = fsrs.shortTermStability(fsrs.shortTermStability(fsrs.initialStability(.again), rating: .good),
                                                     rating: .good)
                let dGood = fsrs.nextDifficulty(fsrs.initialDifficulty(.good), rating: .good)
                let dAgain = fsrs.nextDifficulty(fsrs.nextDifficulty(fsrs.initialDifficulty(.again), rating: .good),
                                                 rating: .good)
                let s = p0 * sGood + (1 - p0) * sAgain
                let d = p0 * dGood + (1 - p0) * dAgain
                var sim = Sim(item: item, s: s, d: d, last: when, examRecall: 0)
                sim.examRecall = recall(stability: s, last: when, on: exam.date)
                sum += sim.examRecall
                sims.append(sim)
                let i = sims.count - 1
                doneToday.insert(i)
                if let next = nextDue(sim, after: day) { buckets[next, default: []].append(i); load[next, default: 0] += 1 }
                seconds += item.kind.typicalSeconds * 2
                news += 1
            }

            for i in buckets[day] ?? [] where !doneToday.contains(i) {
                let old = sims[i].examRecall
                expectedReview(&sims[i], at: when)
                sims[i].examRecall = recall(stability: sims[i].s, last: when, on: exam.date)
                sum += sims[i].examRecall - old
                doneToday.insert(i)
                if let next = nextDue(sims[i], after: day) { buckets[next, default: []].append(i); load[next, default: 0] += 1 }
                seconds += sims[i].item.kind.typicalSeconds
                reviews += 1
            }

            if isEve {
                let weak = sims.indices.filter { !doneToday.contains($0) && sims[$0].examRecall < exam.target }
                    .sorted { sims[$0].examRecall < sims[$1].examRecall }
                var eve = 0.0
                for i in weak {
                    let cost = sims[i].item.kind.typicalSeconds
                    if eve + cost > Self.examEveSeconds { break }
                    let old = sims[i].examRecall
                    expectedReview(&sims[i], at: when)
                    sims[i].examRecall = recall(stability: sims[i].s, last: when, on: exam.date)
                    sum += sims[i].examRecall - old
                    eve += cost
                    seconds += cost
                    reviews += 1
                }
            }

            reviewsPlanned += reviews
            let minutes = seconds > 0 ? max(1, Int((seconds / 60).rounded(.up))) : 0
            let easy = isEasyDay(day)
            let kind: PlanDay.Kind = isEve ? .examEve : (minutes == 0 ? .rest : (easy ? .light : .study))
            let goal = easy ? Int((Double(dailyMinutes) * StudyScheduler.easyDayCapacity).rounded()) : dailyMinutes
            days.append(PlanDay(date: grid.start(ofDay: day), dayNumber: day, kind: kind, minutes: minutes,
                                sessionMinutes: isEve ? minutes : max(minutes, goal), newItems: news, reviews: reviews,
                                isToday: day == today, isEasyDay: easy))
            curve.append(ReadinessPoint(date: grid.start(ofDay: day + 1), value: n > 0 ? min(1, max(0, sum / n)) : 0,
                                        isProjection: true))
        }
        days.append(PlanDay(date: grid.start(ofDay: examDay), dayNumber: examDay, kind: .exam, minutes: 0,
                            sessionMinutes: 0, newItems: 0, reviews: 0, isToday: false, isEasyDay: isEasyDay(examDay)))

        // Only the share of the plan the person tends to do counts toward the projection.
        let a = min(1, max(0, adherence))
        let start = curve[0].value
        curve = curve.map { point in
            guard point.isProjection else { return point }
            var p = point
            p.value = min(1, max(0, start + a * (point.value - start)))
            return p
        }
        plan.days = days
        plan.curve = curve
        plan.reviewsPlanned = reviewsPlanned
        plan.projectedReadiness = curve.last?.value ?? 0
        plan.targetReachedOn = curve.first { $0.value >= exam.target }?.date
        let busiest = days.filter { $0.kind == .study || $0.kind == .light }.map(\.minutes).max() ?? 0
        if busiest > dailyMinutes { plan.suggestedMinutes = Int((Double(busiest) / 5).rounded(.up)) * 5 }
        return plan
    }
}
