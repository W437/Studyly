import Foundation

/// What the exam editor edits, as plain values: `AppModel.createExam` / `updateExam` store it.
struct ExamDraft: Equatable, Sendable {
    var title = ""
    var courseID: UUID?
    var date: Date
    /// The whole course is in scope; otherwise `scope`'s topics are.
    var wholeCourse = true
    var scope: Set<UUID> = []
    var format = ExamFormat()
    /// The readiness the plan aims for, kept within `targetRange`.
    var target = 0.9

    static let targetRange: ClosedRange<Double> = 0.7...0.95
    static let targetStep = 0.05

    init(title: String = "", courseID: UUID? = nil, date: Date, wholeCourse: Bool = true, scope: Set<UUID> = [],
         format: ExamFormat = ExamFormat(), target: Double = 0.9) {
        self.title = title
        self.courseID = courseID
        self.date = date
        self.wholeCourse = wholeCourse
        self.scope = scope
        self.format = format
        self.target = target
    }

    /// A new exam two weeks out, at 9 in the morning.
    static func new(courseID: UUID?, now: Date, calendar: Calendar) -> ExamDraft {
        let day = calendar.adding(days: 14, to: calendar.startOfDay(for: now))
        let date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        return ExamDraft(courseID: courseID, date: date)
    }

    init(exam: Exam) {
        self.init(title: exam.title, courseID: exam.course?.id, date: exam.date, wholeCourse: exam.scope.isEmpty,
                  scope: Set(exam.scope), format: exam.format, target: exam.targetReadiness)
    }

    /// The title as saved: what was typed, else "<course> exam".
    func resolvedTitle(courseName: String) -> String {
        let clean = title.clTrimmed
        if !clean.isEmpty { return clean }
        return courseName.isEmpty ? "Exam" : "\(courseName) exam"
    }

    /// Topic ids in scope as stored: empty means the whole course.
    var scopeIDs: [UUID] { wholeCourse ? [] : scope.sorted { $0.uuidString < $1.uuidString } }

    /// The target on the editor's 5% steps, within range.
    var clampedTarget: Double {
        let stepped = (target / Self.targetStep).rounded() * Self.targetStep
        return min(Self.targetRange.upperBound, max(Self.targetRange.lowerBound, stepped))
    }

    /// The format with its notes trimmed.
    var cleanFormat: ExamFormat {
        var f = format
        f.notes = f.notes.clTrimmed
        return f
    }

    /// What still stops the draft from being saved, said plainly; nil when it's ready.
    var problem: String? {
        if courseID == nil { return "Pick the course this exam is for." }
        if !wholeCourse && scope.isEmpty { return "Pick at least one topic, or the whole course." }
        return nil
    }
}
