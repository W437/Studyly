import Foundation

/// What `AppModel.recordReview` did with one answer.
struct ReviewOutcome: Sendable, Equatable {
    var itemID: UUID
    var rating: Rating
    var before: MemoryState
    var after: MemoryState
    /// The same rule as `ReviewLog.wasCorrect`.
    var wasCorrect: Bool
    /// Days until due (fractional for a learning step).
    var scheduledDays: Double
    var adjustment: ScheduleAdjustment
    var logID: UUID
    /// Probability of recall at the moment of the answer (FSRS; 0 for an item seen for the first time).
    var recallBefore: Double = 1

    /// The answer left the item in a learning step: `SessionQueue` brings it back later in the session.
    var stillLearning: Bool { after.state == .learning || after.state == .relearning }

    /// Below this chance of recall a memory counts as fading: the sky draws its star dim, and getting it right
    /// saves it.
    static let fadingRecall = 0.7

    /// "Just in time!": a right answer (Good or Easy; a "Hard" is "Almost.", not a save) on an item studied before whose
    /// recall had fallen below `fadingRecall`. A first look is never a save. The one definition behind the feedback
    /// headline, the sky's flare and "saved" count, the rescue quest and the badges.
    var isSave: Bool {
        wasCorrect && rating.rawValue >= Rating.good.rawValue && before.state != .new && recallBefore < Self.fadingRecall
    }
}

/// The end-of-session summary.
struct SessionSummary: Sendable, Equatable {
    var sessionID: UUID
    var kind: SessionKind
    /// Every answer, repeats included.
    var answers: Int
    /// Distinct items answered.
    var itemsReviewed: Int
    /// Items right the first time they came up in this session ("9/12 right first time").
    var correctFirstTry: Int
    /// `correctFirstTry / itemsReviewed` (0 with nothing answered).
    var accuracy: Double
    /// Items seen for the first time.
    var newLearned: Int
    var minutes: Int
    /// The exam the readiness numbers are for: the session's exam, else the next exam among the courses
    /// studied, else the next exam.
    var examID: UUID?
    var examTitle: String?
    var readinessBefore: Double?
    var readinessAfter: Double?
    var streak: StreakState
    /// This session made today count for the streak.
    var streakExtended: Bool
    /// A missed day this session repaired.
    var repairedDay: Date?
    /// Exam eve: the summary says stop and sleep, and offers no "keep going".
    var stopNow: Bool
    /// Stars the session visibly relit in the memory sky (`SkyEngine.relights`), and the saves among the answers.
    var starsRelit: Int = 0
    var starsSaved: Int = 0

    /// The change as it reads beside "53% → 67%": the difference of the two rounded percentages (+14%), never a rounding of the raw gap.
    var readinessDelta: Double? {
        guard let readinessBefore, let readinessAfter else { return nil }
        func shown(_ value: Double) -> Int { Int((max(0, min(1, value)) * 100).rounded()) }
        return Double(shown(readinessAfter) - shown(readinessBefore)) / 100
    }
}

/// Turning a grade into an FSRS rating.
enum Grading {
    /// Thresholds for a graded own-words or typed answer (score 0…1):
    /// - below 0.6: Again (wrong; matches `ReviewLog.wasCorrect`, which needs 0.6);
    /// - 0.6 up to 0.8: Hard (partly right: "grade-partial" is 0.67);
    /// - 0.8 and up: Good;
    /// - 0.95 and up, answered in under 60% of the format's typical time: Easy.
    /// A right/wrong format (multiple choice, fill in, diagram) passes 1 or 0.
    static let againBelow = 0.6
    static let goodFrom = 0.8
    static let easyFrom = 0.95
    static let easyTimeShare = 0.6

    static func rating(forScore score: Double, kind: ItemKind? = nil, durationMs: Int? = nil) -> Rating {
        let s = min(1, max(0, score))
        if s < againBelow { return .again }
        if s < goodFrom { return .hard }
        if s >= easyFrom, let kind, let durationMs, durationMs > 0,
           Double(durationMs) < kind.typicalSeconds * 1000 * easyTimeShare {
            return .easy
        }
        return .good
    }

    /// The score to log for a rating the person chose themselves, over the grade the answer earned: the score itself when it is
    /// already in that rating's band, else a score that stands for the rating (Again 0, Hard 0.67, the partly right grade, Good 0.9,
    /// Easy 1). So the log never says "Good" over a score that says "wrong" (`ReviewLog.wasCorrect` needs 0.6 and a rating of Hard or
    /// better), whichever way the answer was marked.
    static func score(standingFor rating: Rating, near score: Double) -> Double {
        let s = min(1, max(0, score))
        switch rating {
        case .again: return s < againBelow ? s : 0
        case .hard: return s >= againBelow && s < goodFrom ? s : 0.67
        case .good: return s >= goodFrom ? s : 0.9
        case .easy: return s >= easyFrom ? s : 1
        }
    }
}
