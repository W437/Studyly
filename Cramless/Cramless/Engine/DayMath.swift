import Foundation

// Calendar-day arithmetic for the engines. Days are counted through the calendar's year-month-day, the same way
// as `Calendar.dayDistance(from:to:)` (Model/Persistence.swift), so a 23- or 25-hour day still counts as one:
// for a Gregorian calendar `dayNumber(b) - dayNumber(a) == dayDistance(from: a, to: b)`. Day numbers are read
// back in the same calendar system with a UTC clock, so they also hold for Buddhist or Hebrew calendars.
// Bulk lookups (thousands of items) use `DayGrid`, a binary search over precomputed day starts.

extension Calendar {
    /// This calendar's system on a UTC clock: turns year-month-day into an exact midnight with no time zone.
    var utcTwin: Calendar {
        if identifier == .gregorian { return Calendar.gregorianUTC }
        var c = Calendar(identifier: identifier)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// The local day containing `date`, as a whole number of days since 1970-01-01. Only differences and
    /// equality mean anything.
    func dayNumber(for date: Date) -> Int {
        let c = dateComponents([.era, .year, .month, .day], from: date)
        guard let utc = utcTwin.date(from: c) else { return 0 }
        return Int((utc.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// The day number of a day key ("yyyy-MM-dd", from `dayKey(for:)` in this calendar).
    func dayNumber(forKey key: String) -> Int? {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              let utc = utcTwin.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
        return Int((utc.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// The start of the local day with this day number.
    func startOfDay(dayNumber: Int) -> Date {
        let twin = utcTwin
        let utc = Date(timeIntervalSince1970: Double(dayNumber) * 86_400)
        var c = twin.dateComponents([.era, .year, .month, .day], from: utc)
        c.hour = 12
        let noon = date(from: c) ?? utc
        return startOfDay(for: noon)
    }

    /// The weekday (1 = Sunday … 7 = Saturday) of the day with this day number.
    static func weekday(dayNumber: Int) -> Int {
        // 1970-01-01 was a Thursday (weekday 5).
        ((dayNumber % 7 + 7) % 7 + 4) % 7 + 1
    }

    /// `date` moved by whole local days, keeping its wall-clock time where the day allows it.
    func adding(days: Int, to date: Date) -> Date {
        self.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
    }
}

/// Local day boundaries for a run of days, so per-item day lookups are a binary search over dates instead of a
/// calendar call each.
struct DayGrid: Sendable {
    let calendar: Calendar
    /// Day number of `starts[0]`.
    let firstDay: Int
    /// `starts[i]` is the start of local day `firstDay + i`; one extra boundary closes the last day.
    let starts: [Date]

    init(calendar: Calendar, firstDay: Int, count: Int) {
        self.calendar = calendar
        self.firstDay = firstDay
        let n = max(count, 1)
        var starts: [Date] = []
        starts.reserveCapacity(n + 1)
        var current = calendar.startOfDay(dayNumber: firstDay)
        starts.append(current)
        for _ in 0..<n {
            // Noon never falls in a daylight-saving gap, so stepping from it lands inside the next day.
            let noon = current.addingTimeInterval(12 * 3600)
            current = calendar.startOfDay(for: calendar.adding(days: 1, to: noon))
            starts.append(current)
        }
        self.starts = starts
    }

    /// The grid that starts on the day containing `date`.
    init(calendar: Calendar, from date: Date, count: Int) {
        self.init(calendar: calendar, firstDay: calendar.dayNumber(for: date), count: count)
    }

    var lastDay: Int { firstDay + starts.count - 2 }

    /// The day number of the local day containing `date`.
    func dayNumber(for date: Date) -> Int {
        guard let first = starts.first, let last = starts.last, date >= first, date < last else {
            return calendar.dayNumber(for: date)
        }
        var lo = 0, hi = starts.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if starts[mid] <= date { lo = mid } else { hi = mid }
        }
        return firstDay + lo
    }

    func start(ofDay day: Int) -> Date {
        let i = day - firstDay
        if i >= 0 && i < starts.count { return starts[i] }
        return calendar.startOfDay(dayNumber: day)
    }

    /// The end of a day (the next day's start).
    func end(ofDay day: Int) -> Date { start(ofDay: day + 1) }
}
