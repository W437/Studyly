import Foundation

/// How many items are due on each local day: what load balancing spreads reviews against.
struct DueLoad: Sendable, Equatable {
    /// Items due per day number (`Calendar.dayNumber(for:)`).
    var counts: [Int: Int] = [:]

    init(counts: [Int: Int] = [:]) { self.counts = counts }

    /// Counts the review items' due days (items in learning steps are due today and don't move).
    init(items: [ItemSnapshot], grid: DayGrid) {
        var counts: [Int: Int] = [:]
        for item in items where item.isActive && item.memory.state == .review {
            guard let due = item.memory.due else { continue }
            counts[grid.dayNumber(for: due), default: 0] += 1
        }
        self.counts = counts
    }

    func count(onDay day: Int) -> Int { counts[day] ?? 0 }

    /// Moves one item from one due day to another (either may be nil: new to the schedule, or leaving it).
    mutating func move(from old: Int?, to new: Int?) {
        if let old, let c = counts[old], c > 0 { counts[old] = c - 1 }
        if let new { counts[new, default: 0] += 1 }
    }
}

/// Reviews due on one day ("Reviews due, next 7 days").
struct DueForecastDay: Sendable, Equatable, Identifiable {
    /// The start of the local day.
    var date: Date
    var count: Int
    var isToday: Bool

    var id: Date { date }

    /// The next `days` days from today; today includes anything overdue and learning steps.
    static func forecast(items: [ItemSnapshot], calendar: Calendar, now: Date, days: Int) -> [DueForecastDay] {
        let n = max(1, days)
        let grid = DayGrid(calendar: calendar, from: now, count: n)
        var counts = [Int](repeating: 0, count: n)
        for item in items where item.isActive && item.memory.state != .new {
            guard let due = item.memory.due else { continue }
            let offset = max(0, grid.dayNumber(for: due) - grid.firstDay)
            if offset < n { counts[offset] += 1 }
        }
        return (0..<n).map { DueForecastDay(date: grid.start(ofDay: grid.firstDay + $0), count: counts[$0], isToday: $0 == 0) }
    }
}

/// Why a due date differs from the plain FSRS interval.
enum ScheduleAdjustment: String, Sendable, Equatable, Codable {
    /// The FSRS interval as is (fuzz off, a learning step, or an interval too short to fuzz).
    case none
    /// A deterministic pick inside the fuzz range.
    case fuzzed
    /// The least-loaded day inside the fuzz range (easy days count as fuller).
    case balanced
    /// Pulled to 1–3 days before an exam the item would otherwise miss.
    case examCapped
}

/// The result of scheduling one answer.
struct ScheduledReview: Sendable, Equatable {
    /// The state after the answer, with the final due date.
    var memory: MemoryState
    var adjustment: ScheduleAdjustment
    /// The exam that capped the interval.
    var examID: UUID?
    /// Whole days since the previous review, as FSRS counted them (0 for a first review).
    var elapsedDays: Double
    /// Days from now to the due date (fractional for a learning step).
    var scheduledDays: Double
    /// The FSRS interval before fuzz, balancing and capping; nil for a learning step.
    var fsrsIntervalDays: Int?
    /// Probability of recall at the moment of the answer.
    var retrievability: Double
}

/// FSRS plus the app's scheduling policy:
/// - target retention from settings;
/// - deterministic fuzz, seeded from the item id and the review day (so it never changes on a replay and tests
///   can turn it off);
/// - load balancing: inside the fuzz range, the day with the least scheduled load wins (ties go to the day
///   closest to the FSRS interval, then to the seeded pick);
/// - easy days: `settings.easyDays` weekdays count as `1 / easyDayCapacity` times fuller, so they get about half
///   the load;
/// - exam-aware capping: an item in an upcoming exam's scope whose next due would land on or after the exam day
///   is pulled to 1–3 days before it when its predicted recall on exam day would fall below the exam's target.
struct StudyScheduler: Sendable {
    var fsrs: FSRS
    var calendar: Calendar
    /// Weekdays, 1 = Sunday … 7 = Saturday.
    var easyDays: Set<Int>
    /// Off: exact FSRS intervals (no fuzz, no balancing, no easy days). Exam capping still applies.
    var fuzz: Bool
    /// With fuzz on: pick the least-loaded day (on) or a seeded day (off) inside the fuzz range.
    var loadBalance: Bool

    /// The share of a normal day's load an easy day takes.
    static let easyDayCapacity = 0.5
    /// How far before an exam a capped item may land.
    static let examPullWindow = 1...3

    init(fsrs: FSRS = FSRS(), calendar: Calendar, easyDays: [Int] = [], fuzz: Bool = true, loadBalance: Bool = true) {
        self.fsrs = fsrs
        self.calendar = calendar
        self.easyDays = Set(easyDays)
        self.fuzz = fuzz
        self.loadBalance = loadBalance
    }

    init(settings: AppSettings, calendar: Calendar, fuzz: Bool = true) {
        self.init(fsrs: FSRS(desiredRetention: settings.targetRetention), calendar: calendar,
                  easyDays: settings.easyDays, fuzz: fuzz)
    }

    func isEasyDay(_ dayNumber: Int) -> Bool {
        !easyDays.isEmpty && easyDays.contains(Calendar.weekday(dayNumber: dayNumber))
    }

    /// How full a day looks to the balancer.
    func effectiveLoad(_ load: DueLoad, day: Int) -> Double {
        let base = Double(load.count(onDay: day) + 1)
        return fuzz && isEasyDay(day) ? base / Self.easyDayCapacity : base
    }

    /// Schedules one answer. `load` is the current due load (the item's own old due day included or not: the
    /// difference is one item); `exams` are the upcoming exams (any order).
    func schedule(_ item: ItemSnapshot, rating: Rating, at now: Date, load: DueLoad = DueLoad(),
                  exams: [ExamSnapshot] = []) -> ScheduledReview {
        let outcome = fsrs.review(item.memory, rating: rating, at: now)
        var memory = outcome.memory
        let elapsed = Double(outcome.elapsedDays ?? 0)
        guard let fsrsDays = outcome.intervalDays else {
            // A (re)learning step: minutes, due today.
            return ScheduledReview(memory: memory, adjustment: .none, examID: nil, elapsedDays: elapsed,
                                   scheduledDays: outcome.interval / 86_400, fsrsIntervalDays: nil,
                                   retrievability: outcome.retrievability)
        }

        let today = calendar.dayNumber(for: now)
        var days = fsrsDays
        var adjustment = ScheduleAdjustment.none
        if fuzz {
            let range = fsrs.fuzzRange(intervalDays: fsrsDays)
            if range.count > 1 {
                let u = StableRandom.unit(item.id, day: today)
                let seeded = range.lowerBound + min(range.count - 1, Int(u * Double(range.count)))
                if loadBalance {
                    var best = seeded
                    var bestLoad = effectiveLoad(load, day: today + seeded)
                    for candidate in range where candidate != seeded {
                        let l = effectiveLoad(load, day: today + candidate)
                        if l < bestLoad || (l == bestLoad && abs(candidate - fsrsDays) < abs(best - fsrsDays)) {
                            best = candidate
                            bestLoad = l
                        }
                    }
                    days = best
                    adjustment = .balanced
                } else {
                    days = seeded
                    adjustment = .fuzzed
                }
            }
        }

        // Exam-aware capping: the soonest exam this item would miss.
        var cappedBy: UUID?
        let covering = exams.filter { $0.date > now && $0.covers(item) }.sorted { $0.date < $1.date }
        for exam in covering {
            let examDay = calendar.dayNumber(for: exam.date)
            guard today + days >= examDay else { continue }
            let recallOnExam = fsrs.retrievability(
                elapsedDays: Double(max(0, FSRS.elapsedDays(from: now, to: exam.date))), stability: memory.stability)
            guard recallOnExam < exam.target else { continue }
            let candidates = Self.examPullWindow.map { examDay - $0 }.filter { $0 > today }
            guard !candidates.isEmpty else { continue }
            // Least loaded; ties go to the later day (the fresher memory on exam day).
            var best = candidates[0]
            for c in candidates.dropFirst() {
                let lc = effectiveLoad(load, day: c), lb = effectiveLoad(load, day: best)
                if lc < lb || (lc == lb && c > best) { best = c }
            }
            days = best - today
            adjustment = .examCapped
            cappedBy = exam.id
            break
        }

        // Whole calendar days at the same wall-clock time, so "in 1 day" is tomorrow even across a
        // daylight-saving change (py-fsrs adds 24-hour periods; the difference is an hour, never a day).
        memory.due = calendar.adding(days: days, to: now)
        return ScheduledReview(memory: memory, adjustment: adjustment, examID: cappedBy, elapsedDays: elapsed,
                               scheduledDays: Double(days), fsrsIntervalDays: fsrsDays,
                               retrievability: outcome.retrievability)
    }
}
