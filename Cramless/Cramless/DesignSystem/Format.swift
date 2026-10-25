import Foundation

/// The app's wording for dates, durations and numbers, in one place so every screen says them the same way.
enum CLFormat {
    /// "64%".
    static func percent(_ value: Double) -> String {
        "\(Int((max(0, min(1, value)) * 100).rounded()))%"
    }

    /// "+5%", "−3%", "±0%" for a change in a 0…1 value.
    static func delta(_ value: Double) -> String {
        let points = Int((value * 100).rounded())
        if points > 0 { return "+\(points)%" }
        if points < 0 { return "−\(abs(points))%" }
        return "±0%"
    }

    /// "15 min", "1 h 5 min".
    static func minutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// "Fri, Nov 14".
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "today", "tomorrow", "in 23 days", "2 days ago".
    static func relativeDays(to date: Date, from now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dayDistance(from: now, to: date)
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case let d where d > 1: return "in \(d) days"
        default: return "\(-days) days ago"
        }
    }

    /// "23 days", "1 day", "Today".
    static func daysLeft(_ days: Int) -> String {
        switch days {
        case ..<1: return "Today"
        case 1: return "1 day"
        default: return "\(days) days"
        }
    }

    /// "12:05" for a lecture timestamp.
    static func timestamp(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "Wednesday, Oct 22" for a screen's eyebrow.
    static func longDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// "1 question" / "14 questions".
    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }
}
