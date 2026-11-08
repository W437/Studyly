import Foundation

/// A badge. Each is earned once, from what the person has done, and kept: nothing here can be lost, bought or missed.
/// More arrive with the features they belong to (a wrapped term, an event).
enum Badge: String, CaseIterable, Sendable, Identifiable {
    /// The first session finished.
    case firstSession
    /// 10 stars saved ("Just in time!").
    case saves10
    /// 25 answers written in your own words.
    case ownWords25
    /// A mix-up fixed, then five.
    case firstFix
    case fifthFix
    /// A best streak of 7, 30, 100 and 365 days: the flame's stages.
    case streak7
    case streak30
    case streak100
    case streak365
    /// 80% ready on the morning of an exam.
    case ready
    /// A grade within 5 points of the readiness the exam morning showed.
    case calledIt
    /// 1,000 answers.
    case thousand
    /// A missed day repaired.
    case comeback

    var id: String { rawValue }

    /// What it takes, in the badge's own unit (days of streak, answers, saves…), for "7 of 10".
    var target: Int {
        switch self {
        case .firstSession, .firstFix, .ready, .calledIt, .comeback: 1
        case .saves10: 10
        case .ownWords25: 25
        case .fifthFix: 5
        case .streak7: 7
        case .streak30: 30
        case .streak100: 100
        case .streak365: 365
        case .thousand: 1000
        }
    }
}

/// What the person's history amounts to, as the badges read it. Every field only grows: more sessions, more saves, a longer
/// best streak. (`AppModel.achievementFacts()` reads them from the log, the day records and the exams.)
struct AchievementFacts: Sendable, Equatable {
    var sessionsFinished = 0
    var saves = 0
    var ownWordsAnswers = 0
    var mixUpsFixed = 0
    var bestStreak = 0
    /// Exams whose readiness on the morning was 80% or more.
    var readyExams = 0
    /// Exams graded within 5 points of that readiness.
    var calledItExams = 0
    var answers = 0
    var repairedDays = 0

    /// The readiness that makes an exam morning "ready".
    static let readyAt = 0.8
    /// How close the grade is to the readiness to "call it": 5 points.
    static let calledItWithin = 0.05
}

struct BadgeProgress: Sendable, Equatable {
    var value: Int
    var target: Int

    var isEarned: Bool { value >= target }
    /// 0 to 1.
    var fraction: Double { target > 0 ? min(1, Double(max(0, value)) / Double(target)) : 0 }
}

enum AchievementEngine {
    static func progress(_ badge: Badge, _ facts: AchievementFacts) -> BadgeProgress {
        let value: Int
        switch badge {
        case .firstSession: value = facts.sessionsFinished
        case .saves10: value = facts.saves
        case .ownWords25: value = facts.ownWordsAnswers
        case .firstFix, .fifthFix: value = facts.mixUpsFixed
        case .streak7, .streak30, .streak100, .streak365: value = facts.bestStreak
        case .ready: value = facts.readyExams
        case .calledIt: value = facts.calledItExams
        case .thousand: value = facts.answers
        case .comeback: value = facts.repairedDays
        }
        return BadgeProgress(value: min(max(0, value), badge.target), target: badge.target)
    }

    /// Every badge these facts have earned.
    static func earned(_ facts: AchievementFacts) -> Set<Badge> {
        Set(Badge.allCases.filter { progress($0, facts).isEarned })
    }

    /// What `after` has that `before` didn't, in the catalog's order: the badges a session just earned.
    static func newlyEarned(before: Set<Badge>, after: Set<Badge>) -> [Badge] {
        Badge.allCases.filter { after.contains($0) && !before.contains($0) }
    }
}
