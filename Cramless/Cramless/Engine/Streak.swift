import Foundation

/// One square of the streak heatmap.
struct HeatmapCell: Sendable, Equatable, Identifiable {
    /// The start of the local day.
    var date: Date
    var dayKey: String
    var minutes: Int
    /// 0 nothing, 1 under half the goal, 2 under the goal, 3 under 1.5× the goal, 4 beyond.
    var level: Int
    var frozen: Bool
    var repaired: Bool
    var isToday: Bool
    /// Later this week (drawn empty).
    var isFuture: Bool

    var id: String { dayKey }
}

/// This calendar week's studying.
struct WeeklyStats: Sendable, Equatable {
    struct Day: Sendable, Equatable, Identifiable {
        var date: Date
        var minutes: Int
        var itemsReviewed: Int
        var isToday: Bool
        var isFuture: Bool
        var id: Date { date }
    }

    /// The week's days, in the calendar's week order.
    var days: [Day]
    var totalMinutes: Int
    var previousWeekMinutes: Int
    var activeDays: Int
    var itemsReviewed: Int
    /// The daily goal times seven.
    var goalMinutes: Int
}

/// Streaks from day records. Days are counted only through the calendar (`dayKey`, day numbers), so a
/// daylight-saving change never breaks or doubles a day.
/// - A day counts when it was studied, frozen or repaired. The current streak is alive through today when
///   yesterday counted (today doesn't have to count yet).
/// - Freezes: one earned per 7 studied days in a row (a frozen day neither adds nor breaks the run), at most 2
///   held. At rollover a freeze covers yesterday when it is a single missed day right after a studied day (a
///   freeze never covers two days in a row). Until the rollover writes it, the read model applies it virtually.
/// - Repair: a missed, unfrozen day within the last 2 days, whose repair would join the streak back up, is
///   repaired by a double session today (studied minutes today at least twice the daily goal).
struct StreakEngine: Sendable {
    var calendar: Calendar
    var now: Date
    var dailyMinutes: Int

    static let freezeEvery = 7
    static let maxFreezes = 2
    static let repairWindow = 2
    static let repairFactor = 2.0

    init(calendar: Calendar, now: Date, dailyMinutes: Int = 15) {
        self.calendar = calendar
        self.now = now
        self.dailyMinutes = max(1, dailyMinutes)
    }

    var today: Int { calendar.dayNumber(for: now) }

    /// Records by day number (the day key decides the day; the stored date is only a fallback).
    func index(_ records: [DaySnapshot]) -> [Int: DaySnapshot] {
        var out: [Int: DaySnapshot] = [:]
        for r in records {
            let day = calendar.dayNumber(forKey: r.dayKey) ?? calendar.dayNumber(for: r.day)
            if let existing = out[day] {
                var merged = existing
                merged.studySeconds += r.studySeconds
                merged.itemsReviewed += r.itemsReviewed
                merged.sessions += r.sessions
                merged.frozen = merged.frozen || r.frozen
                merged.repaired = merged.repaired || r.repaired
                out[day] = merged
            } else {
                out[day] = r
            }
        }
        return out
    }

    /// Freezes held after `last`, walking the history from its first day.
    func freezesHeld(_ byDay: [Int: DaySnapshot], through last: Int, virtualFrozen: Int? = nil) -> Int {
        guard let first = byDay.keys.min(), first <= last else { return 0 }
        var held = 0
        var run = 0
        for day in first...last {
            let r = byDay[day]
            if r?.studied == true {
                run += 1
                if run % Self.freezeEvery == 0 { held = min(Self.maxFreezes, held + 1) }
            } else if r?.frozen == true || day == virtualFrozen {
                held = max(0, held - 1)
            } else {
                run = 0
            }
        }
        return held
    }

    /// Yesterday's day number when the rollover should freeze it: a single missed day right after a studied
    /// day, with a freeze held.
    func freezeToApply(_ byDay: [Int: DaySnapshot]) -> Int? {
        let y = today - 1
        guard byDay[y]?.counts != true, byDay[y - 1]?.studied == true else { return nil }
        return freezesHeld(byDay, through: y - 1) > 0 ? y : nil
    }

    func freezeToApply(_ records: [DaySnapshot]) -> Date? {
        freezeToApply(index(records)).map { calendar.startOfDay(dayNumber: $0) }
    }

    private func counts(_ byDay: [Int: DaySnapshot], _ day: Int, pending: Int?) -> Bool {
        byDay[day]?.counts == true || day == pending
    }

    /// The missed day a double session today would repair.
    func repairableDay(_ byDay: [Int: DaySnapshot], pending: Int?) -> Int? {
        for back in 1...Self.repairWindow {
            let m = today - back
            guard !counts(byDay, m, pending: pending) else { continue }
            guard counts(byDay, m - 1, pending: pending) else { continue }
            if back > 1, !((m + 1)...(today - 1)).allSatisfy({ counts(byDay, $0, pending: pending) }) { continue }
            return m
        }
        return nil
    }

    /// Studied minutes today are enough to repair a day.
    func repairQualifies(todaySeconds: Double) -> Bool {
        todaySeconds >= Self.repairFactor * Double(dailyMinutes) * 60
    }

    func state(_ records: [DaySnapshot]) -> StreakState {
        let byDay = index(records)
        let today = self.today
        let pending = freezeToApply(byDay)
        var state = StreakState()
        state.studiedToday = byDay[today]?.studied == true && (byDay[today]?.sessions ?? 0) > 0

        let end: Int? = counts(byDay, today, pending: pending) ? today
            : (counts(byDay, today - 1, pending: pending) ? today - 1 : nil)
        if let end {
            var d = end
            while counts(byDay, d, pending: pending) { d -= 1 }
            state.current = end - d
        }

        // Best: the longest run of counted days.
        var best = state.current
        var run = 0
        var previous: Int?
        let days = Set(byDay.keys.filter { counts(byDay, $0, pending: pending) }).union(pending.map { [$0] } ?? [])
        for day in days.sorted() {
            run = (previous.map { day == $0 + 1 } ?? false) ? run + 1 : 1
            best = max(best, run)
            previous = day
        }
        state.best = best

        let throughDay = state.studiedToday ? today : today - 1
        state.freezesAvailable = freezesHeld(byDay, through: throughDay, virtualFrozen: pending)
        let horizon = today - 7 * 12
        state.frozenDays = Set(byDay.filter { $0.value.frozen }.map(\.key) + (pending.map { [$0] } ?? []))
            .filter { $0 >= horizon }.sorted(by: >).map { calendar.startOfDay(dayNumber: $0) }
        state.repairableDay = repairableDay(byDay, pending: pending).map { calendar.startOfDay(dayNumber: $0) }
        return state
    }

    // MARK: Heatmap and week

    /// The first day of the calendar week containing `day`.
    func weekStart(of day: Int) -> Int {
        let offset = (Calendar.weekday(dayNumber: day) - calendar.firstWeekday + 7) % 7
        return day - offset
    }

    func level(minutes: Int, studied: Bool) -> Int {
        guard studied else { return 0 }
        let ratio = Double(minutes) / Double(dailyMinutes)
        switch ratio {
        case ..<0.5: return 1
        case ..<1: return 2
        case ..<1.5: return 3
        default: return 4
        }
    }

    /// Whole calendar weeks ending with this one (`weeks × 7` cells, oldest first; later days this week are
    /// marked future).
    func heatmap(_ records: [DaySnapshot], weeks: Int = 12) -> [HeatmapCell] {
        let byDay = index(records)
        let today = self.today
        let last = weekStart(of: today) + 6
        let first = last - max(1, weeks) * 7 + 1
        let grid = DayGrid(calendar: calendar, firstDay: first, count: last - first + 1)
        return (first...last).map { day in
            let r = byDay[day]
            let start = grid.start(ofDay: day)
            let minutes = Int(((r?.studySeconds ?? 0) / 60).rounded())
            return HeatmapCell(date: start, dayKey: r?.dayKey ?? calendar.dayKey(for: start.addingTimeInterval(12 * 3600)),
                               minutes: minutes, level: level(minutes: minutes, studied: r?.studied == true),
                               frozen: r?.frozen == true, repaired: r?.repaired == true, isToday: day == today,
                               isFuture: day > today)
        }
    }

    func weekly(_ records: [DaySnapshot]) -> WeeklyStats {
        let byDay = index(records)
        let today = self.today
        let start = weekStart(of: today)
        let grid = DayGrid(calendar: calendar, firstDay: start - 7, count: 14)
        let days = (start..<(start + 7)).map { day in
            WeeklyStats.Day(date: grid.start(ofDay: day), minutes: Int(((byDay[day]?.studySeconds ?? 0) / 60).rounded()),
                            itemsReviewed: byDay[day]?.itemsReviewed ?? 0, isToday: day == today, isFuture: day > today)
        }
        let previous = ((start - 7)..<start).reduce(0.0) { $0 + (byDay[$1]?.studySeconds ?? 0) }
        return WeeklyStats(days: days, totalMinutes: days.reduce(0) { $0 + $1.minutes },
                           previousWeekMinutes: Int((previous / 60).rounded()),
                           activeDays: (start..<(start + 7)).filter { byDay[$0]?.studied == true }.count,
                           itemsReviewed: days.reduce(0) { $0 + $1.itemsReviewed }, goalMinutes: dailyMinutes * 7)
    }
}
