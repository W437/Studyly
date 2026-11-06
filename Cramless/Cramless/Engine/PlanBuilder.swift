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
    /// Days from today (0 is today): the key of `PlanBuilder.capacity` and `skipping`.
    var offset: Int = 0
    /// Seconds of this exam's work planned that day: what fits the day's capacity (`minutes` is this, rounded up).
    var seconds: Double = 0
    /// Seconds this exam's own work for the day would take with no limit (reviews falling due that day, its share of new
    /// material, the eve's weak spots); work carried over from an earlier day isn't counted again. `suggestedMinutes` reads it.
    var neededSeconds: Double = 0
    /// A day off in a what-if (`PlanBuilder.skipping`): nothing planned.
    var isSkipped: Bool = false

    /// This exam's minutes that day as the plan's stops and Today's strip show them: at least 1.
    var shownMinutes: Int { max(1, Int((seconds / 60).rounded())) }

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
    /// the only kind of day left, a skipped day never), earlier days rounding up. With every day skipped, all on the first (a plan
    /// carries them on to the next day it studies).
    static func newItemsPerDay(unseen: Int, today: Int, examDay: Int, isEasyDay: (Int) -> Bool,
                               isSkipped: (Int) -> Bool = { _ in false }) -> [Int: Int] {
        guard unseen > 0 else { return [:] }
        let last = lastIntroDay(today: today, examDay: examDay)
        let days = Array(today...last)
        var weights = days.map { isSkipped($0) || isEasyDay($0) ? 0.0 : 1.0 }
        if weights.allSatisfy({ $0 == 0 }) { weights = days.map { isSkipped($0) ? 0.0 : 1.0 } }
        if weights.allSatisfy({ $0 == 0 }) { return [today: unseen] }
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
/// - each simulated review is an `ExpectedReview`: right as often as FSRS forecasts at that hour, else forgotten and relearned.
///   A question is followed as weighted branches, one per run of right and wrong answers (at most `maxBranches`, the closest
///   merged), so exam-day recall is the expectation over the outcomes, never the recall of an average state; the mean stability
///   schedules the next review;
/// - a first look at new material succeeds with the person's own first-try rate (`newItemSuccess`, `StudyHabits`: 75% until
///   there is history, then a blend), the rest are relearned;
/// - recall is forecast in hours, not whole days (`FSRS.forecastRecall`): a review the evening before a morning exam is
///   not certain recall;
/// - with a `capacity` (an exam sharing the daily goal with sooner ones, `AppModel.examPlans()`), each day holds only what fits:
///   reviews claim it first (new material keeps up to 40% of it, as in the daily session), reviews that don't fit move on to the
///   next day and new material to the next day that isn't the eve; `suggestedMinutes` still reads what the exam alone needs;
/// - `skipping` days (a what-if) get no work at all: their reviews move on and no new material is spread there;
/// - the projection counts only the share of the plan the person tends to do (`adherence`, `StudyHabits`: from the last two
///   weeks' study days, blended with a high prior): projected = now + adherence × (plan − now).
/// The plan is recomputed from the current memory every time, which is what makes it bend. All of this keeps the
/// projection a projection: optimistic numbers would make the readiness score worthless.
struct PlanBuilder: Sendable {
    var fsrs: FSRS
    var calendar: Calendar
    var now: Date
    var dailyMinutes: Int
    var easyDays: Set<Int>
    /// The chance a first look at a new item is recalled right away (else it's relearned).
    var newItemSuccess: Double = StudyHabits.firstLookPrior
    /// The share of planned study the person actually does, 0…1.
    var adherence: Double = StudyHabits.followThroughPrior
    /// Seconds of study this exam may use on each day, by day offset from today (0 is today). Nil: no limit; a day missing from it
    /// has no limit either.
    var capacity: [Int: Double]? = nil
    /// Days off, by day offset from today: no work those days.
    var skipping: Set<Int> = []

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

    /// One way a simulated question's memory may stand, with its weight: each simulated review splits every branch into a right
    /// and a wrong answer, so recall stays the expectation over the outcomes and is never read off an average state.
    private struct Branch {
        var w: Double
        var s: Double
        var d: Double
    }

    private struct Sim {
        var item: ItemSnapshot
        var branches: [Branch]
        var last: Date
        var examRecall: Double

        /// The mean stability: what scheduling reads.
        var s: Double { branches.reduce(0) { $0 + $1.w * $1.s } }
    }

    /// Branches kept per question; beyond, the two with the closest stabilities merge (exact for three reviews).
    static let maxBranches = 8

    private func recall(stability: Double, last: Date, on date: Date) -> Double {
        fsrs.forecastRecall(stability: stability, last: last, at: date)
    }

    private func recall(of branches: [Branch], last: Date, on date: Date) -> Double {
        branches.reduce(0) { $0 + $1.w * recall(stability: $1.s, last: last, on: date) }
    }

    /// Zero weights dropped, then the closest stabilities (in log terms) merged until at most `maxBranches` are left.
    private static func merged(_ branches: [Branch]) -> [Branch] {
        var list = branches.filter { $0.w > 1e-12 }.sorted { $0.s < $1.s }
        if list.isEmpty { return branches }
        while list.count > maxBranches {
            var at = 0
            var gap = Double.infinity
            for k in 0..<(list.count - 1) {
                let g = log(list[k + 1].s) - log(list[k].s)
                if g < gap { gap = g; at = k }
            }
            let a = list[at], b = list[at + 1]
            let w = a.w + b.w
            list[at] = Branch(w: w, s: (a.w * a.s + b.w * b.s) / w, d: (a.w * a.d + b.w * b.d) / w)
            list.remove(at: at + 1)
        }
        return list
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
                sims.append(Sim(item: item, branches: [Branch(w: 1, s: item.memory.stability, d: item.memory.difficulty)],
                                last: last, examRecall: recall(stability: item.memory.stability, last: last, on: exam.date)))
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

        func isSkipped(_ day: Int) -> Bool { skipping.contains(day - today) }
        func limit(_ day: Int) -> Double { isSkipped(day) ? 0 : (capacity?[day - today] ?? .infinity) }

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

        /// A review of sim `i` at `when`: every branch splits into a right and a wrong answer (`ExpectedReview`).
        func review(_ i: Int, at when: Date) {
            var next: [Branch] = []
            next.reserveCapacity(sims[i].branches.count * 2)
            for b in sims[i].branches {
                let step = fsrs.expectedReview(stability: b.s, difficulty: b.d, last: sims[i].last, at: when)
                next.append(Branch(w: b.w * step.p, s: step.sGood, d: step.dGood))
                next.append(Branch(w: b.w * (1 - step.p), s: step.sLapse, d: step.dLapse))
            }
            let old = sims[i].examRecall
            sims[i].branches = Self.merged(next)
            sims[i].last = when
            sims[i].examRecall = recall(of: sims[i].branches, last: when, on: exam.date)
            sum += sims[i].examRecall - old
        }

        let intro = PlanMath.newItemsPerDay(unseen: unseen.count, today: today, examDay: examDay, isEasyDay: isEasyDay,
                                            isSkipped: isSkipped)
        var queue = unseen.sorted {
            $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.difficultyHint < $1.difficultyHint
        }[...]
        var days: [PlanDay] = []
        var reviewsPlanned = 0
        // Work that didn't fit its day: reviews go to the next day, new material to the next day that isn't the eve.
        var carriedReviews: [Int] = []
        var carriedNew: [ItemSnapshot] = []
        for day in today..<examDay {
            let isEve = day == examDay - 1
            let cap = limit(day)
            var when = grid.start(ofDay: day).addingTimeInterval(Self.reviewHour * 3600)
            if day == today { when = max(now, when) }
            if when >= exam.date { when = max(now, exam.date.addingTimeInterval(-3600)) }
            var seconds = 0.0, needed = 0.0, reviews = 0, news = 0
            var doneToday = Set<Int>()

            // What wants this day: yesterday's leftovers first, then its own.
            var freshToday: [ItemSnapshot] = []
            for _ in 0..<(intro[day] ?? 0) {
                guard let item = queue.popFirst() else { break }
                freshToday.append(item)
            }
            let ownReviews = buckets[day] ?? []
            needed += freshToday.reduce(0) { $0 + $1.kind.typicalSeconds * 2 }
                + ownReviews.reduce(0) { $0 + sims[$1].item.kind.typicalSeconds }
            let newOffered = (isEve ? [] : carriedNew) + freshToday
            if !isEve { carriedNew = [] }
            var reviewOffered: [Int] = []
            var offered = Set<Int>()
            for i in carriedReviews + ownReviews where offered.insert(i).inserted { reviewOffered.append(i) }
            carriedReviews = []

            // What fits: reviews first (new material keeps up to 40% of the day, as in the daily session), then new material,
            // then more reviews. With no limit, everything.
            var newTaken: [ItemSnapshot] = []
            var reviewTaken = Set<Int>()
            if cap == .infinity {
                newTaken = newOffered
                reviewTaken = Set(reviewOffered)
            } else {
                var used = 0.0
                let newCost = newOffered.reduce(0) { $0 + $1.kind.typicalSeconds * 2 }
                let reviewLimit = max(cap - min(newCost, cap * SessionBuilder.newShare), cap * 0.5)
                for i in reviewOffered where used + sims[i].item.kind.typicalSeconds <= reviewLimit {
                    used += sims[i].item.kind.typicalSeconds
                    reviewTaken.insert(i)
                }
                for item in newOffered {
                    if used + item.kind.typicalSeconds * 2 <= cap {
                        used += item.kind.typicalSeconds * 2
                        newTaken.append(item)
                    } else {
                        carriedNew.append(item)
                    }
                }
                for i in reviewOffered where !reviewTaken.contains(i) && used + sims[i].item.kind.typicalSeconds <= cap {
                    used += sims[i].item.kind.typicalSeconds
                    reviewTaken.insert(i)
                }
                carriedReviews = reviewOffered.filter { !reviewTaken.contains($0) }
            }

            for item in newTaken {
                // First look and one learning step: right with the person's first-try rate, else Again and relearned.
                let step = fsrs.expectedFirstLook(success: newItemSuccess, at: when)
                let sim = Sim(item: item, branches: Self.merged([Branch(w: step.p, s: step.sGood, d: step.dGood),
                                                                 Branch(w: 1 - step.p, s: step.sLapse, d: step.dLapse)]),
                              last: when, examRecall: step.recall(at: exam.date, fsrs: fsrs))
                sum += sim.examRecall
                sims.append(sim)
                let i = sims.count - 1
                doneToday.insert(i)
                if let next = nextDue(sim, after: day) { buckets[next, default: []].append(i); load[next, default: 0] += 1 }
                seconds += item.kind.typicalSeconds * 2
                news += 1
            }

            for i in reviewOffered where reviewTaken.contains(i) && !doneToday.contains(i) {
                review(i, at: when)
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
                    needed += cost
                    if seconds + cost > cap { break }
                    review(i, at: when)
                    eve += cost
                    seconds += cost
                    reviews += 1
                }
            }

            reviewsPlanned += reviews
            let minutes = seconds > 0 ? max(1, Int((seconds / 60).rounded(.up))) : 0
            let easy = isEasyDay(day)
            let skipped = isSkipped(day)
            let kind: PlanDay.Kind = isEve ? .examEve : (minutes == 0 ? .rest : (easy ? .light : .study))
            let goal = easy ? Int((Double(dailyMinutes) * StudyScheduler.easyDayCapacity).rounded()) : dailyMinutes
            days.append(PlanDay(date: grid.start(ofDay: day), dayNumber: day, kind: kind, minutes: minutes,
                                sessionMinutes: skipped ? 0 : (isEve ? minutes : max(minutes, goal)), newItems: news,
                                reviews: reviews, isToday: day == today, isEasyDay: easy, offset: day - today,
                                seconds: seconds, neededSeconds: needed, isSkipped: skipped))
            curve.append(ReadinessPoint(date: grid.start(ofDay: day + 1), value: n > 0 ? min(1, max(0, sum / n)) : 0,
                                        isProjection: true))
        }
        days.append(PlanDay(date: grid.start(ofDay: examDay), dayNumber: examDay, kind: .exam, minutes: 0,
                            sessionMinutes: 0, newItems: 0, reviews: 0, isToday: false, isEasyDay: isEasyDay(examDay),
                            offset: examDay - today))

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
        // What this exam alone would need on its busiest day, whatever share of the day it was given.
        let busiest = days.filter { $0.kind != .examEve && $0.kind != .exam }
            .map { $0.neededSeconds > 0 ? max(1, Int(($0.neededSeconds / 60).rounded(.up))) : 0 }.max() ?? 0
        if busiest > dailyMinutes { plan.suggestedMinutes = Int((Double(busiest) / 5).rounded(.up)) * 5 }
        return plan
    }
}
