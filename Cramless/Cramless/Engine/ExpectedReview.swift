import Foundation

/// What one review is expected to do to a memory, for forecasts: the plan's simulated days, "about N% after today"
/// (`ReadinessEngine.valueAfter`) and anything else that asks where a question will be after it is studied.
///
/// A review is answered right with probability `p`, the recall forecast at the moment of the review (hours counted, `FSRS.forecastRecall`),
/// and leaves stability `sGood`; otherwise the question is forgotten, relearned with one learning step, and leaves `sLapse`. Recall on a
/// later day is the expectation over both outcomes, `p·R(sGood) + (1 − p)·R(sLapse)`, never the recall of the mean stability: recall is
/// concave in stability, so the mean's recall overstates it, most when a lapse is likely. A plan follows both outcomes on to the next
/// review (`PlanBuilder`'s branches); the mean stability is what schedules it.
///
/// The stabilities follow the scheduler exactly (py-fsrs's whole days decide whether a review is a same-day one, and the scheduler's
/// whole-day retrievability goes into the stability update), so a forecast step lands where answering would.
struct ExpectedReview: Sendable, Equatable {
    var sGood: Double
    var sLapse: Double
    var dGood: Double
    var dLapse: Double
    /// The chance the review is answered right, 0…1.
    var p: Double
    /// When the review happens.
    var at: Date

    var meanStability: Double { p * sGood + (1 - p) * sLapse }
    var meanDifficulty: Double { p * dGood + (1 - p) * dLapse }

    /// Expected recall at `date`, over the right and the wrong answer.
    func recall(at date: Date, fsrs: FSRS) -> Double {
        p * fsrs.forecastRecall(stability: sGood, last: at, at: date)
            + (1 - p) * fsrs.forecastRecall(stability: sLapse, last: at, at: date)
    }
}

extension FSRS {
    /// A review at `when` of a studied memory (its stability, difficulty and last review).
    func expectedReview(stability: Double, difficulty: Double, last: Date, at when: Date) -> ExpectedReview {
        let p = forecastRecall(stability: stability, last: last, at: when)
        let wholeDays = max(0, Self.elapsedDays(from: last, to: when))
        let sGood: Double, sLapse: Double
        if wholeDays < 1 {
            sGood = shortTermStability(stability, rating: .good)
            sLapse = shortTermStability(shortTermStability(stability, rating: .again), rating: .good)
        } else {
            let r = retrievability(elapsedDays: Double(wholeDays), stability: stability)
            sGood = nextStability(difficulty: difficulty, stability: stability, retrievability: r, rating: .good)
            let forgot = nextStability(difficulty: difficulty, stability: stability, retrievability: r, rating: .again)
            sLapse = shortTermStability(forgot, rating: .good)
        }
        let dGood = nextDifficulty(difficulty, rating: .good)
        let dLapse = nextDifficulty(nextDifficulty(difficulty, rating: .again), rating: .good)
        return ExpectedReview(sGood: sGood, sLapse: sLapse, dGood: dGood, dLapse: dLapse, p: min(1, max(0, p)), at: when)
    }

    /// A review at `when` of a studied memory.
    func expectedReview(of memory: MemoryState, at when: Date) -> ExpectedReview? {
        guard memory.state != .new, let last = memory.lastReview, memory.stability > 0 else { return nil }
        return expectedReview(stability: memory.stability, difficulty: memory.difficulty, last: last, at: when)
    }

    /// A first look at a new question at `when` and its learning step: right first time with probability `success` (the person's
    /// first-try rate), else Again and relearned.
    func expectedFirstLook(success: Double, at when: Date) -> ExpectedReview {
        let sGood = shortTermStability(initialStability(.good), rating: .good)
        let sAgain = shortTermStability(shortTermStability(initialStability(.again), rating: .good), rating: .good)
        let dGood = nextDifficulty(initialDifficulty(.good), rating: .good)
        let dAgain = nextDifficulty(nextDifficulty(initialDifficulty(.again), rating: .good), rating: .good)
        return ExpectedReview(sGood: sGood, sLapse: sAgain, dGood: dGood, dLapse: dAgain, p: min(1, max(0, success)), at: when)
    }
}
