import Foundation

/// Arranges the engine's habit values and the sky's counts for the Progress and Streak screens: weeks of the heatmap, last
/// week beside this one, a month's calendar, the fading and brightest topics. Pure: nothing here computes recall.
enum ProgressPresentation {
    // MARK: Heatmap

    /// Heatmap cells as weeks of seven (columns), oldest first.
    static func weeks(_ cells: [HeatmapCell]) -> [[HeatmapCell]] {
        stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min(cells.count, $0 + 7)]) }
    }

    /// The column where each month first shows, labelled "Aug": for the heatmap's month row. A month that starts
    /// in the first column's week is labelled there.
    static func monthLabels(_ weeks: [[HeatmapCell]], calendar: Calendar) -> [(column: Int, label: String)] {
        var labels: [(Int, String)] = []
        var lastMonth: Int?
        for (column, week) in weeks.enumerated() {
            guard let first = week.first else { continue }
            let month = calendar.component(.month, from: first.date)
            if month != lastMonth {
                // Label a month only where there's room before the next one (two columns).
                if let previous = labels.last, column - previous.0 < 2 { labels.removeLast() }
                labels.append((column, first.date.formatted(LibraryFormat.dateStyle(calendar).month(.abbreviated))))
                lastMonth = month
            }
        }
        return labels
    }

    /// The heatmap's colour step for a cell: 0 nothing, 1…4 by minutes against the goal; frozen and future apart.
    enum CellStyle: Equatable, Sendable {
        case empty, level(Int), frozen, future
    }

    static func style(_ cell: HeatmapCell) -> CellStyle {
        if cell.isFuture { return .future }
        if cell.level > 0 { return .level(min(4, cell.level)) }
        if cell.frozen { return .frozen }
        return .empty
    }

    /// A heatmap day drawn as a star: a dot that grows and brightens with the minutes studied, and a sparkle from the
    /// third step. Size and shape say it as well as colour does, so no step rests on colour alone.
    struct StarMark: Equatable, Sendable {
        enum Shape: Equatable, Sendable { case dot, sparkle }
        var shape: Shape
        /// The share of the cell it fills, 0…1.
        var size: Double
        var opacity: Double
        /// A soft glow round it: the days at the top of the scale.
        var glow: Bool
    }

    /// The star for a cell's style, or nil for a day that hasn't come yet (drawn as a faint ring).
    static func starMark(_ style: CellStyle) -> StarMark? {
        switch style {
        case .future: nil
        case .empty: StarMark(shape: .dot, size: 0.26, opacity: 1, glow: false)
        case .frozen: StarMark(shape: .dot, size: 0.62, opacity: 1, glow: false)
        case .level(let level):
            switch level {
            case 1: StarMark(shape: .dot, size: 0.40, opacity: 0.45, glow: false)
            case 2: StarMark(shape: .dot, size: 0.56, opacity: 0.70, glow: false)
            case 3: StarMark(shape: .sparkle, size: 0.80, opacity: 0.90, glow: false)
            default: StarMark(shape: .sparkle, size: 1.0, opacity: 1, glow: true)
            }
        }
    }

    /// "Tue, Oct 14" and "12 minutes" (or "Not studied", "Frozen", "Repaired") for a cell's VoiceOver label and value.
    static func accessibility(_ cell: HeatmapCell, calendar: Calendar) -> (label: String, value: String) {
        let label = cell.date.formatted(LibraryFormat.dateStyle(calendar).weekday(.abbreviated).month(.abbreviated).day())
        let value: String
        if cell.isFuture {
            value = "Later this week"
        } else if cell.level > 0 {
            value = (cell.isToday ? "Today, " : "") + CLFormat.count(cell.minutes, "minute") + (cell.repaired ? ", repaired" : "")
        } else if cell.frozen {
            value = "Covered by a streak freeze"
        } else if cell.repaired {
            value = "Repaired"
        } else {
            value = cell.isToday ? "Today, not studied yet" : "Not studied"
        }
        return (label, value)
    }

    // MARK: This week and last

    /// Last week's minutes on the same weekdays as `week.days`, read from the heatmap.
    static func lastWeekMinutes(cells: [HeatmapCell], week: WeeklyStats, calendar: Calendar) -> [Int] {
        let byDay = Dictionary(cells.map { (calendar.dayNumber(for: $0.date), $0.minutes) }, uniquingKeysWith: { a, _ in a })
        return week.days.map { byDay[calendar.dayNumber(for: $0.date) - 7] ?? 0 }
    }

    /// "+12 min" / "−8 min" / "Same as last week" comparing this week's total with last week's.
    static func weekComparison(this: Int, last: Int) -> String {
        let diff = this - last
        if diff == 0 { return "Same as last week" }
        return "\(diff > 0 ? "+" : "−")\(CLFormat.minutes(abs(diff))) vs last week"
    }

    // MARK: Streak

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

    // MARK: The month and the sky

    /// The month sheet's line: "12-day streak · Best 12 · 1 freeze saved".
    static func monthHeadline(days: Int, best: Int, freezes: Int) -> String {
        [String(localized: "\(days)-day streak"), String(localized: "Best \(best)"), String(localized: "\(freezes) freezes saved")]
            .joined(separator: " · ")
    }

    /// The sky's tile: "63 stars · 17 dim".
    static func skyLine(stars: Int, dim: Int) -> String {
        "\(String(localized: SkyCopy.stars(stars))) · \(String(localized: SkyCopy.dim(dim)))"
    }

    // MARK: Topics

    /// A topic as its constellation in the sky, for the Fading list. Counts only, never a percentage.
    struct TopicLight: Equatable, Sendable, Identifiable {
        var id: UUID
        var name: String
        var courseID: UUID
        var courseName: String
        var color: CourseColor
        /// Its place in the sky's constellations.
        var index: Int
        /// Studied stars under the sky's dim line (`ReviewOutcome.fadingRecall`): "2 questions fading".
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

    /// Topics with questions fading, at most `count`: the nearest exam's first, then most fading; topics on no exam after.
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

    /// "2 questions fading".
    static func fadingLine(_ dim: Int) -> String { String(localized: "\(dim) questions fading") }
}
