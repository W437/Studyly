import Foundation
import WidgetKit

/// One widget timeline entry: the snapshot as it reads at `date` (nil when the app hasn't written one).
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var relevance: TimelineEntryRelevance?
}

/// When the widgets redraw without the app: now, each of the next two midnights (days left tick over, "today"
/// starts empty) and the moment an exam in that window is over. The app reloads the timelines whenever its data
/// changes (`WidgetSync`), and the timeline asks for a new one after its last entry. Pure; tested.
enum WidgetTimeline {
    static func dates(from now: Date, snapshot: WidgetSnapshot?, calendar: Calendar) -> [Date] {
        let first = WidgetCalendar.nextMidnight(after: now, calendar: calendar)
        let second = WidgetCalendar.nextMidnight(after: first, calendar: calendar)
        var dates = [now, first, second]
        for exam in snapshot?.exams ?? [] {
            let over = exam.date.addingTimeInterval(WidgetSnapshot.examLength)
            if over > now, over < second { dates.append(over) }
        }
        return Array(Set(dates)).sorted()
    }

    static func entries(from now: Date, stored: WidgetSnapshot?, calendar: Calendar) -> [SnapshotEntry] {
        dates(from: now, snapshot: stored, calendar: calendar).map { date in
            let rolled = stored?.rolled(to: date, calendar: calendar)
            return SnapshotEntry(date: date, snapshot: rolled, relevance: relevance(of: rolled, at: date, calendar: calendar))
        }
    }

    /// Smart Stack relevance: higher while today's session is waiting, highest the day before an exam.
    static func relevance(of snapshot: WidgetSnapshot?, at date: Date, calendar: Calendar) -> TimelineEntryRelevance? {
        guard let s = snapshot else { return nil }
        var score: Float = 0
        if !s.streak.studiedToday, s.today.ready { score = 40 }
        if let exam = s.nextExam {
            let days = WidgetCalendar.days(from: date, to: exam.date, calendar: calendar)
            if days <= 1 { score = max(score, 80) } else if days <= 7 { score = max(score, 50) }
        }
        return score > 0 ? TimelineEntryRelevance(score: score) : nil
    }
}
