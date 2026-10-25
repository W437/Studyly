import ActivityKit
import Foundation

// The Live Activities' data. The app starts and updates them (`LiveActivityController`); the widget extension draws
// them (CramlessWidgets/LiveActivityWidgets.swift with the views in Shared/Widgets/LiveActivityViews.swift).
// Payloads stay tiny (ActivityKit caps them at 4 KB): counts, a topic name, dates.

/// A study session in progress: Lock Screen and Dynamic Island, from the first question to the summary.
struct StudySessionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var answered: Int
        var correct: Int
        /// The current question's topic ("Phases of mitosis").
        var topic: String?
        var finished = false
    }

    /// "Today's session", "Bio 101 practice", "2-minute fix".
    var title: String
    var total: Int
    var startedAt: Date
    /// The planned length when known; shows "6 min left".
    var plannedMinutes: Int?
}

extension StudySessionAttributes.ContentState {
    func progress(total: Int) -> Double {
        guard total > 0 else { return 0 }
        return max(0, min(1, Double(answered) / Double(total)))
    }
}

/// The week before an exam: readiness and days left on the Lock Screen and in the Dynamic Island. One at a time,
/// for the next exam once it's 7 days away or less, ended after the exam.
struct ExamWeekAttributes: ActivityAttributes, Equatable {
    struct ContentState: Codable, Hashable, Sendable {
        /// 0…1.
        var readiness: Double
        /// Change over the last 7 days.
        var delta: Double
        var daysLeft: Int
        /// Minutes planned for today's session.
        var todayMinutes: Int
        var studiedToday: Bool
    }

    var examID: UUID
    var title: String
    var courseName: String
    var color: CourseColor
    var examDate: Date
}

/// Which exam gets the exam-week activity, and what it shows. Pure; `LiveActivityController` applies it on launch
/// and on every widget refresh.
enum ExamWeekPlan {
    /// Days before the exam the activity appears.
    static let window = 7

    /// The next exam that is at most `window` days away and not over yet, or nil.
    static func focus(in snapshot: WidgetSnapshot, now: Date, calendar: Calendar) -> WidgetSnapshot.Exam? {
        snapshot.exams
            .filter { !$0.isOver(at: now) }
            .min { $0.date < $1.date }
            .flatMap { WidgetCalendar.days(from: now, to: $0.date, calendar: calendar) <= window ? $0 : nil }
    }

    static func attributes(for exam: WidgetSnapshot.Exam) -> ExamWeekAttributes {
        ExamWeekAttributes(examID: exam.id, title: exam.title, courseName: exam.courseName, color: exam.color,
                           examDate: exam.date)
    }

    static func state(for exam: WidgetSnapshot.Exam, in snapshot: WidgetSnapshot, now: Date,
                      calendar: Calendar) -> ExamWeekAttributes.ContentState {
        ExamWeekAttributes.ContentState(
            readiness: exam.readiness, delta: exam.delta,
            daysLeft: max(0, WidgetCalendar.days(from: now, to: exam.date, calendar: calendar)),
            todayMinutes: snapshot.streak.studiedToday ? 0 : snapshot.today.sessionMinutes,
            studiedToday: snapshot.streak.studiedToday)
    }
}

// MARK: - Samples (render tests and previews)

extension StudySessionAttributes {
    static func sample(now: Date = .now) -> StudySessionAttributes {
        StudySessionAttributes(title: "Today's session", total: 18, startedAt: now.addingTimeInterval(-252),
                               plannedMinutes: 15)
    }
}

extension StudySessionAttributes.ContentState {
    static let sample = StudySessionAttributes.ContentState(answered: 9, correct: 7, topic: "Phases of mitosis")
    static let sampleFinished = StudySessionAttributes.ContentState(answered: 18, correct: 15, topic: nil,
                                                                      finished: true)
}

extension ExamWeekAttributes {
    static func sample(now: Date = .now, calendar: Calendar = .current) -> ExamWeekAttributes {
        let start = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return ExamWeekAttributes(examID: WidgetSnapshot.SampleID.bioMidterm, title: "Bio 101 Midterm",
                                  courseName: "Bio 101", color: .sky,
                                  examDate: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day)
    }
}

extension ExamWeekAttributes.ContentState {
    static let sample = ExamWeekAttributes.ContentState(readiness: 0.64, delta: 0.05, daysLeft: 6, todayMinutes: 15,
                                                        studiedToday: false)
}
