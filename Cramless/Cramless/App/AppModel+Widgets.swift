import Foundation

// The read side the widgets, Live Activities, notifications and Siri share, plus read-aloud conveniences. No
// mutations here: everything reads through the Engine lane's API (`todaySummary()`, `readiness(for:)`, `streak()`).
extension AppModel {
    /// The widget snapshot as of now.
    func makeWidgetSnapshot() -> WidgetSnapshot {
        let exams = upcomingExams()
            .filter { $0.course?.deletedAt == nil && $0.date.addingTimeInterval(WidgetSnapshot.examLength) > now }
            .prefix(WidgetSnapshot.maxExams)
            .map { exam -> WidgetSnapshotBuilder.ExamInput in
                let r = readiness(for: exam)
                return WidgetSnapshotBuilder.ExamInput(id: exam.id, title: exam.title, courseName: exam.course?.name ?? "",
                                                       color: exam.course?.color ?? .sky, date: exam.date,
                                                       readiness: r.value, delta: r.deltaThisWeek)
            }
        let courseValues = courses.map { WidgetSnapshot.Course(id: $0.id, name: $0.name, color: $0.color) }
        return WidgetSnapshotBuilder.make(now: now, summary: todaySummary(), streak: streak(), exams: Array(exams),
                                          courses: courseValues)
    }

    /// The upcoming exams as the notification planner sees them.
    func notificationExams() -> [NotificationPlanner.ExamInfo] {
        upcomingExams()
            .filter { $0.course?.deletedAt == nil }
            .map { NotificationPlanner.ExamInfo(id: $0.id, title: $0.title, courseName: $0.course?.name, date: $0.date) }
    }

    // MARK: Read aloud

    /// Reads `text` aloud when the person turned on Read aloud (Settings ▸ Accessibility). Pass `force` for an
    /// explicit speaker button, which works whatever the setting.
    func readAloud(_ text: String, force: Bool = false) {
        ReadAloud.shared.speak(text, enabled: force || settings.readAloud)
    }

    /// Reads a question the way it's shown: the prompt, a fill-in's blanks as "blank", a multiple choice's options.
    func readAloud(question item: StudyItem, force: Bool = false) {
        guard item.modelContext != nil else { return }
        let text = ReadAloud.spokenQuestion(kind: item.kind, prompt: item.prompt, choices: item.choices.map(\.text),
                                            cloze: item.cloze)
        readAloud(text, force: force)
    }

    func stopReadingAloud() {
        ReadAloud.shared.stop()
    }
}

/// Builds a snapshot from the engines' values. Pure; `WidgetSnapshotTests` checks it.
enum WidgetSnapshotBuilder {
    struct ExamInput: Equatable {
        var id: UUID
        var title: String
        var courseName: String
        var color: CourseColor
        var date: Date
        var readiness: Double
        var delta: Double
    }

    /// Three decimals: finer than anything shown, coarse enough that readiness drifting by a hair between saves
    /// doesn't rewrite the snapshot and reload every widget.
    static func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    static func make(now: Date, summary: TodaySummary, streak: StreakState, exams: [ExamInput],
                     courses: [WidgetSnapshot.Course]) -> WidgetSnapshot {
        let studied = streak.studiedToday || summary.studiedToday
        return WidgetSnapshot(
            generatedAt: now,
            streak: .init(current: max(0, streak.current), studiedToday: studied, freezes: max(0, streak.freezesAvailable)),
            today: .init(goalMinutes: max(1, summary.minutesGoal), doneMinutes: max(0, summary.minutesDone),
                         plannedMinutes: max(0, summary.plannedMinutes), reviews: max(0, summary.reviews),
                         newItems: max(0, summary.newItems), weakSpots: max(0, summary.weakSpots),
                         weakChips: Array(summary.weakChips.prefix(3)), ready: summary.sessionReady),
            exams: exams.sorted { $0.date < $1.date }.prefix(WidgetSnapshot.maxExams).map {
                WidgetSnapshot.Exam(id: $0.id, title: $0.title, courseName: $0.courseName, color: $0.color, date: $0.date,
                                    readiness: rounded(max(0, min(1, $0.readiness))),
                                    delta: rounded(max(-1, min(1, $0.delta))))
            },
            courses: courses)
    }
}
