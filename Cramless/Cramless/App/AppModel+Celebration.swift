import Foundation
import SwiftData

extension AppModel {
    /// What a finished session's summary celebrates (`CelebrationPolicy`). `streakBefore` is the streak when the
    /// session started; `readinessTarget` the exam's goal, when there is an exam.
    func celebration(for summary: SessionSummary, streakBefore: StreakState, readinessTarget: Double?,
                     mixUpFixed: Bool) -> CelebrationDecision {
        CelebrationPolicy.decide(celebrationFacts(for: summary, streakBefore: streakBefore,
                                                  readinessTarget: readinessTarget, mixUpFixed: mixUpFixed))
    }

    func celebrationFacts(for summary: SessionSummary, streakBefore: StreakState, readinessTarget: Double?,
                          mixUpFixed: Bool) -> CelebrationFacts {
        var facts = CelebrationFacts()
        facts.examEve = summary.stopNow || summary.kind == .examEve
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        facts.quietHours = CLSound.isQuiet(minute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0),
                                           start: settings.quietHoursStart, end: settings.quietHoursEnd)
        facts.firstSession = summary.kind != .quickCheck && !hasFinishedSession(besides: summary.sessionID)
        facts.streakExtended = summary.streakExtended
        if summary.streakExtended {
            facts.streakMilestone = CelebrationPolicy.milestone(from: streakBefore.current, to: summary.streak.current)
        }
        if let target = readinessTarget, let before = summary.readinessBefore, let after = summary.readinessAfter {
            facts.readinessReachedGoal = before < target && after >= target
        }
        facts.mixUpFixed = mixUpFixed
        facts.perfect = summary.itemsReviewed >= CelebrationPolicy.perfectFrom
            && summary.correctFirstTry == summary.itemsReviewed
        facts.bigToday = settings.lastBigCelebrationAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        return facts
    }

    /// A celebration played: after a big one, any other today is medium.
    func noteCelebration(_ decision: CelebrationDecision) {
        guard decision.size == .big else { return }
        var s = settings
        s.lastBigCelebrationAt = now
        settings = s
    }

    /// Another finished session, not counting onboarding's quick check.
    private func hasFinishedSession(besides id: UUID) -> Bool {
        let quick = SessionKind.quickCheck.rawValue
        var descriptor = FetchDescriptor<StudySession>(predicate: #Predicate {
            $0.endedAt != nil && $0.id != id && $0.kindRaw != quick
        })
        descriptor.fetchLimit = 1
        return !fetch(descriptor).isEmpty
    }
}
