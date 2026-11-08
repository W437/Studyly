import Foundation

/// Arranges the engine's habit values and the sky's counts for the Progress and Streak screens: the streak's row, a month's calendar,
/// the topics to review soon, the pairs often confused. Pure: nothing here computes recall.
enum ProgressPresentation {
    // MARK: Streak

    /// Progress's one row for the streak and the week: "12-day streak · 3 h 5 min this week". `streak` nil (Quiet mode): only the minutes.
    /// No comparison with last week: a week in progress against a whole one always reads as a loss early on.
    static func weekRowParts(streak days: Int?, onHold: Bool, minutes: Int) -> [String] {
        let week = String(localized: "\(CLFormat.minutes(minutes)) this week")
        guard let days else { return [week] }
        let streak: String
        if onHold {
            streak = String(localized: "\(days)-day streak on hold")
        } else {
            streak = days > 0 ? String(localized: "\(days)-day streak") : String(localized: "Start a streak today")
        }
        return [streak, week]
    }

    /// The run of counted days (studied, frozen or repaired) that ends the day before `day`: what a repair of `day`
    /// joins back onto.
    static func runBefore(_ day: Date, cells: [HeatmapCell], calendar: Calendar) -> Int {
        let counted = Set(cells.filter { $0.level > 0 || $0.frozen || $0.repaired }.map { calendar.dayNumber(for: $0.date) })
        var d = calendar.dayNumber(for: day) - 1
        var run = 0
        while counted.contains(d) { run += 1; d -= 1 }
        return run
    }

    // MARK: Month calendar

    /// A month as weeks of seven in the calendar's week order; nil pads the days outside the month.
    static func monthGrid(for month: Date, calendar: Calendar) -> [[Date?]] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let first = interval.start
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for offset in 0..<days.count {
            cells.append(calendar.adding(days: offset, to: first))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
    }

    /// Weekday initials in the calendar's order ("S M T W T F S").
    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    // MARK: Exams

    /// An exam's row: "in 2 days · +15% this week".
    static func examLine(days: Int, delta: Double) -> String {
        let when: String
        switch days {
        case ...0: when = String(localized: "today")
        case 1: when = String(localized: "tomorrow")
        default: when = String(localized: "in \(days) days")
        }
        return "\(when) · \(String(localized: "\(CLFormat.delta(delta)) this week"))"
    }

    // MARK: The sky

    /// The sky's tile: "63 stars · 17 to review".
    static func skyLine(stars: Int, dim: Int) -> String {
        "\(String(localized: SkyCopy.stars(stars))) · \(reviewLine(dim))"
    }

    // MARK: Topics

    /// A topic as its constellation in the sky, for the "Review soon" list. Counts only, never a percentage.
    struct TopicLight: Equatable, Sendable, Identifiable {
        var id: UUID
        var name: String
        var courseID: UUID
        var courseName: String
        var color: CourseColor
        /// Its place in the sky's constellations.
        var index: Int
        /// Studied stars under the sky's dim line (`ReviewOutcome.fadingRecall`): "2 to review".
        var dimCount: Int
        /// Days to the nearest exam that covers it; nil when none does.
        var examDays: Int?
    }

    /// Days to the nearest exam covering each constellation, by its index: an exam's region records what it covers.
    static func daysToNearestExam(regions: [SkyLayout.Region], examDates: [UUID: Date], now: Date, calendar: Calendar) -> [Int: Int] {
        var nearest: [Int: Int] = [:]
        for region in regions {
            guard let date = examDates[region.examID], date > now else { continue }
            let days = calendar.dayDistance(from: now, to: date)
            for index in region.covers { nearest[index] = min(nearest[index] ?? days, days) }
        }
        return nearest
    }

    /// Topics with questions to review, at most `count`: the nearest exam's first, then most fading; topics on no exam after.
    static func fading(_ topics: [TopicLight], count: Int = 3) -> [TopicLight] {
        let sorted = topics.filter { $0.dimCount > 0 }.sorted { a, b in
            switch (a.examDays, b.examDays) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.dimCount != b.dimCount ? a.dimCount > b.dimCount : a.name < b.name
            }
        }
        return Array(sorted.prefix(count))
    }

    /// "2 to review".
    static func reviewLine(_ dim: Int) -> String { String(localized: "\(dim) to review") }

    // MARK: Often confused

    /// A pair's row: "Missed 3 times · Bio 101"; one taken up before any miss: "Not missed yet · Bio 101".
    static func confusedLine(misses: Int, courseName: String) -> String {
        let missed = misses > 0 ? String(localized: "Missed \(misses) times") : String(localized: "Not missed yet")
        return "\(missed) · \(courseName)"
    }
}
