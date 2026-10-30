import Foundation

/// When Capling asks for a rating. Rarely, and only at a moment the person has just had a good time: a session where every
/// answer was right first time, a session that saved two stars, or a streak milestone. Never on exam eve, never in the
/// first days, never twice in a season, and never in the harness or in tests. (Apple limits the system prompt to three a
/// year on top of this, and decides whether to show it at all.)
enum ReviewPromptPolicy {
    enum Reason: Sendable, Equatable {
        case perfectSession
        case saves
        case milestone
    }

    struct Facts: Sendable, Equatable {
        /// Distinct questions answered in the session, and how many were right the first time.
        var answered = 0
        var rightFirstTime = 0
        /// Stars the session saved ("Saved it.").
        var saves = 0
        /// The streak milestone the session reached, if it reached one.
        var streakMilestone: Int?
        var examEve = false
        /// Sessions finished since install, this one included.
        var sessionsFinished = 0
        var daysSinceInstall = 0
        /// Days since the app last asked; nil when it never has.
        var daysSincePrompt: Int?
        /// The app already asked in this version.
        var promptedThisVersion = false
        var harness = false
    }

    /// A perfect session has at least this many questions.
    static let perfectFrom = 8
    static let savesFrom = 2
    static let minimumDays = 4
    static let minimumSessions = 5
    static let spacingDays = 120

    /// The good moment this session was, if it was one.
    static func reason(_ facts: Facts) -> Reason? {
        if facts.streakMilestone != nil { return .milestone }
        if facts.answered >= perfectFrom, facts.rightFirstTime == facts.answered { return .perfectSession }
        if facts.saves >= savesFrom { return .saves }
        return nil
    }

    /// Whether to ask now.
    static func shouldAsk(_ facts: Facts) -> Bool {
        guard !facts.harness, !facts.examEve, !facts.promptedThisVersion,
              facts.daysSinceInstall >= minimumDays, facts.sessionsFinished >= minimumSessions,
              reason(facts) != nil else { return false }
        if let since = facts.daysSincePrompt, since < spacingDays { return false }
        return true
    }
}
