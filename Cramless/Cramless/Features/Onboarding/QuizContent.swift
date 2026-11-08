import Foundation

/// The words of onboarding's one question (the exam's date) and of the plan screen that follows it.
enum QuizContent {
    /// The plan screen's minutes a day: plain numbers, no labels.
    static let minuteOptions = [5, 10, 15, 20, 30]

    /// "When's your Bio 101 exam?", named after the course the first page went to.
    static func examQuestion(courseName: String?) -> String {
        guard let name = courseName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return String(localized: "When's your next exam?")
        }
        return String(localized: "When's your \(name) exam?")
    }

    /// "Sat, Nov 14 · 23 days away" under the calendar.
    static func examSummary(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dayDistance(from: now, to: date)
        let day = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        switch days {
        case ..<1: return String(localized: "\(day) · today")
        case 1: return String(localized: "\(day) · tomorrow")
        default: return String(localized: "\(day) · \(days) days away")
        }
    }

    /// The plan's exam line: "Bio 101 exam · 23 days".
    static func examLine(title: String, days: Int) -> String {
        days < 1 ? String(localized: "\(title) · today") : String(localized: "\(title) · \(days) days")
    }

    /// The plan's one line, from the plan engine's projection: "15 minutes a day gets you to 90% by Nov 28.", or, when the target
    /// isn't reached before the exam, how far it does get ("… to 72% by exam day.").
    static func planLine(minutes: Int, target: Double, reachedOn: Date?, projected: Double) -> String {
        if let reachedOn {
            let day = reachedOn.formatted(.dateTime.month(.abbreviated).day())
            return String(localized: "\(minutes) minutes a day gets you to \(CLFormat.percent(target)) by \(day).")
        }
        return String(localized: "\(minutes) minutes a day gets you to \(CLFormat.percent(projected)) by exam day.")
    }

    /// The plan's line with no exam: no readiness to promise.
    static func noExamLine(minutes: Int) -> String {
        String(localized: "\(minutes) minutes a day keeps your questions fresh until you add an exam.")
    }

    /// "7:00 PM" for minutes after midnight.
    static func timeString(minutes: Int) -> String {
        var parts = DateComponents()
        parts.year = 2001
        parts.month = 1
        parts.day = 1
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        let date = Calendar(identifier: .gregorian).date(from: parts) ?? .now
        return date.formatted(.dateTime.hour().minute())
    }
}
