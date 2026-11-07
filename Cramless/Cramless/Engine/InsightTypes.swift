import Foundation

// The read model the screens, widgets and notifications use: what today looks like, how ready each exam is,
// the streak. Computed by the engines through `AppModel+Insights.swift`. Extend these types by adding fields with
// defaults; don't rename (several lanes read them).

struct TodaySummary: Equatable, Sendable {
    /// The person's daily goal (settings).
    var minutesGoal: Int = 15
    /// Minutes studied today so far.
    var minutesDone: Int = 0
    /// The size of today's session as built now, in minutes.
    var plannedMinutes: Int = 0
    /// And in questions: what the session from Today's card holds (a question that comes back counts once).
    var plannedQuestions: Int = 0
    var reviews: Int = 0
    var newItems: Int = 0
    var weakSpots: Int = 0
    /// Short names for the weak spots in today's session ("Meiosis I vs II", "Chromosome number").
    var weakChips: [String] = []
    var studiedToday = false
    /// There is something to study right now.
    var sessionReady = false
    /// A backlog too big for one day: the session runs in catch-up mode.
    var catchUp = false
    /// Everything due right now, including what doesn't fit in today's session.
    var dueTotal: Int = 0
    /// In catch-up mode: days at the daily goal to clear the backlog.
    var catchUpDaysToClear: Int = 0
    /// An exam tomorrow: offer its exam-eve session (weak spots only, then stop).
    var examEveExamID: UUID? = nil
    /// Every exam tomorrow, soonest first (`examEveExamID` is the first): they share tonight's session.
    var examEveExamIDs: [UUID] = []
}

struct TopicReadiness: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    /// 0…1; nil when the topic has no material yet (a coverage gap).
    var value: Double?
    var itemCount: Int
    /// For an exam's topic: the seconds a practice round on it takes (its questions under the exam's goal on exam day, its unseen
    /// ones twice). 0 for a course's topic (`topicMastery`).
    var practiceSeconds: Double = 0

    /// "Practice · N min": the practice round's minutes, from 2 to 10.
    var practiceMinutes: Int { min(10, max(2, Int((practiceSeconds / 60).rounded(.up)))) }
}

struct ProjectedGrade: Equatable, Sendable {
    /// 0…1.
    var percent: Double
    var letter: String
    /// True once logged grades have calibrated the projection.
    var isCalibrated: Bool
}

struct ExamReadiness: Equatable, Sendable {
    var examID: UUID
    /// Predicted recall over the exam's scope on exam day if the person stopped studying now. 0…1.
    var value: Double
    /// The same, if the plan is followed. 0…1.
    var projected: Double
    /// Change in `value` over the last 7 days, on the questions the student has had the chance to study: adding new ones doesn't take ground back
    /// (`ReadinessEngine.readiness(for:…)`).
    var deltaThisWeek: Double
    var daysLeft: Int
    var topics: [TopicReadiness]
    var projectedGrade: ProjectedGrade
    var itemsInScope: Int
    /// Items in scope never studied.
    var unseenItems: Int
    /// The exam's target readiness, 0…1.
    var target: Double = 0.9
    /// When the plan's projection first reaches the target (nil: it doesn't before the exam).
    var targetReachedOn: Date? = nil
    /// Topics in scope with no material yet.
    var coverageGaps: Int = 0
    /// The share (0…1) of the exam's material its questions reach, when it can be told. `value` doesn't take it into account (it is
    /// the mean recall of the questions the app made); `projectedGrade` does.
    var coverage: Double? = nil
    /// Change in `value` since the start of today ("+10% today"), read as `deltaThisWeek` is.
    var deltaToday: Double = 0
    /// Questions added lately and not studied yet, while they hold `value` down by a point or more (0 otherwise): why the number moved.
    var newQuestions: Int = 0
    /// The plan has places for new questions.
    var newQuestionsInPlan = false
}

struct StreakState: Equatable, Sendable {
    var current: Int = 0
    var best: Int = 0
    var studiedToday = false
    var freezesAvailable: Int = 0
    /// Days covered by a freeze, most recent first.
    var frozenDays: [Date] = []
    /// A missed day that a double session today would repair.
    var repairableDay: Date?
}
