import Foundation

/// How big a moment's celebration is. Learning earns celebrations; buying never does (the purchase screen stays
/// calm, with no confetti).
///
/// - `none`: Cap arrives and the session's sound plays, nothing more.
/// - `nudge`: Cap hops as the streak rolls over.
/// - `small`: a handful of confetti from behind Cap.
/// - `medium`: a burst of confetti, and sparkles around Cap.
/// - `big`: confetti from both bottom corners, across the whole screen.
/// - `calm`: exam eve and quiet hours. No confetti and no hop; a reason still gets its words, and Cap's sparkles.
enum Celebration: String, CaseIterable, Sendable {
    case none, nudge, small, medium, big, calm

    /// Order by size, for "the biggest wins" (calm is a cap on size, not a size).
    var rank: Int {
        switch self {
        case .none: 0
        case .calm: 1
        case .nudge: 2
        case .small: 3
        case .medium: 4
        case .big: 5
        }
    }

    var hasConfetti: Bool { self == .small || self == .medium || self == .big }
}

/// Why a moment celebrates, most important first: when two reasons are the same size, the earlier one names it.
enum CelebrationReason: Equatable, Sendable {
    case firstSession
    case streakMilestone(days: Int)
    case readinessGoal
    case mixUpFixed
    case badge
    case perfect
}

/// What a finished session achieved, as the policy needs it (`AppModel.celebrationFacts`).
struct CelebrationFacts: Equatable, Sendable {
    var examEve = false
    var quietHours = false
    /// The first session after onboarding's quick check.
    var firstSession = false
    /// The streak milestone this session reached (`CelebrationPolicy.milestone(from:to:)`).
    var streakMilestone: Int?
    var streakExtended = false
    /// The exam's readiness crossed the goal during this session.
    var readinessReachedGoal = false
    var mixUpFixed = false
    var badgeEarned = false
    /// Every question right the first time, in a session of at least `CelebrationPolicy.perfectFrom` questions.
    var perfect = false
    /// A big celebration has played today already.
    var bigToday = false
}

struct CelebrationDecision: Equatable, Sendable {
    var size: Celebration
    var reason: CelebrationReason?

    static let none = CelebrationDecision(size: .none, reason: nil)
}

/// Whether a moment earns a celebration, and how big. One per screen: the biggest reason wins. Exam eve and quiet
/// hours are always calm, and a big celebration plays at most once a day (a second one that day is medium).
enum CelebrationPolicy {
    /// Streak lengths that celebrate, and how big.
    static let streakMilestones: [Int: Celebration] = [3: .small, 7: .medium, 30: .big, 100: .big, 365: .big]
    /// A perfect session has at least this many questions.
    static let perfectFrom = 5

    static func decide(_ facts: CelebrationFacts) -> CelebrationDecision {
        var candidates: [CelebrationDecision] = []
        if facts.firstSession { candidates.append(.init(size: .big, reason: .firstSession)) }
        if let days = facts.streakMilestone, let size = streakMilestones[days] {
            candidates.append(.init(size: size, reason: .streakMilestone(days: days)))
        }
        if facts.readinessReachedGoal { candidates.append(.init(size: .medium, reason: .readinessGoal)) }
        if facts.mixUpFixed { candidates.append(.init(size: .medium, reason: .mixUpFixed)) }
        if facts.badgeEarned { candidates.append(.init(size: .medium, reason: .badge)) }
        if facts.perfect { candidates.append(.init(size: .small, reason: .perfect)) }

        var decision = candidates.reduce(nil as CelebrationDecision?) { best, next in
            guard let best else { return next }
            return next.size.rank > best.size.rank ? next : best
        } ?? CelebrationDecision(size: facts.streakExtended ? .nudge : .none, reason: nil)

        if decision.size == .big, facts.bigToday { decision.size = .medium }
        if facts.examEve || (facts.quietHours && decision.size.hasConfetti) { decision.size = .calm }
        return decision
    }

    /// The biggest milestone a streak passed going from `before` to `after` days (a repair can jump two).
    static func milestone(from before: Int, to after: Int) -> Int? {
        StreakEngine.milestoneCrossed(from: before, to: after)
    }
}
