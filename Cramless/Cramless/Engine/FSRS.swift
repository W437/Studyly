import Foundation

/// FSRS-6, ported from the reference implementation py-fsrs (PyPI `fsrs` 6.3.2, `fsrs/scheduler.py`): the 21
/// default parameters, retrievability with the trainable decay (w20), initial stability and difficulty, the
/// difficulty update with linear damping and mean reversion, recall and forget stability, same-day (short-term)
/// stability (w17–w19), and the Scheduler's learning steps (1 min, 10 min), relearning step (10 min), interval
/// from desired retention and the 36,500-day cap. `FSRSParityTests` replays py-fsrs histories
/// (`CramlessTests/Fixtures/fsrs-reference.json`) and matches them to 1e-6.
///
/// Faithful details that matter for parity:
/// - Elapsed days are whole 24-hour periods since the last review (Python's `timedelta.days`, a floor), not
///   calendar days. This is the one place in the app that counts days from seconds, because the reference does;
///   everything a person sees (streaks, days left, plans) counts calendar days.
/// - Python's `round` is round-half-to-even, so intervals use `.toNearestOrEven`.
/// - A new item is a learning item at step 0 with no stability or difficulty yet.
/// - `math.e ** x` is `pow(e, x)` here (the same libm call), so results agree to the last bits.
///
/// No fuzz here: `StudyScheduler` adds deterministic fuzz and load balancing on top.
struct FSRS: Sendable, Equatable {
    static let defaultParameters: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, 1.4835, 0.0614,
        0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
    ]
    static let stabilityMin = 0.001
    static let minDifficulty = 1.0
    static let maxDifficulty = 10.0
    static let defaultLearningSteps: [TimeInterval] = [60, 600]
    static let defaultRelearningSteps: [TimeInterval] = [600]
    static let defaultMaximumInterval = 36_500

    /// The fuzz ranges of py-fsrs (`FUZZ_RANGES`): (start, end, factor) in days.
    static let fuzzRanges: [(start: Double, end: Double, factor: Double)] = [
        (2.5, 7.0, 0.15), (7.0, 20.0, 0.1), (20.0, .infinity, 0.05),
    ]

    let parameters: [Double]
    let desiredRetention: Double
    let learningSteps: [TimeInterval]
    let relearningSteps: [TimeInterval]
    let maximumInterval: Int
    /// -w20.
    let decay: Double
    /// 0.9^(1/decay) - 1, so that retrievability is 0.9 when elapsed days equal stability.
    let factor: Double

    init(parameters: [Double] = FSRS.defaultParameters, desiredRetention: Double = 0.9,
         learningSteps: [TimeInterval] = FSRS.defaultLearningSteps,
         relearningSteps: [TimeInterval] = FSRS.defaultRelearningSteps,
         maximumInterval: Int = FSRS.defaultMaximumInterval) {
        precondition(parameters.count == 21, "FSRS-6 takes 21 parameters")
        self.parameters = parameters
        self.desiredRetention = min(0.99, max(0.5, desiredRetention))
        self.learningSteps = learningSteps
        self.relearningSteps = relearningSteps
        self.maximumInterval = max(1, maximumInterval)
        decay = -parameters[20]
        factor = pow(0.9, 1 / decay) - 1
    }

    private static let e = M_E

    // MARK: Days

    /// Whole 24-hour periods from `a` to `b`, floored like Python's `timedelta.days` (negative when `b` is earlier).
    static func elapsedDays(from a: Date, to b: Date) -> Int {
        Int((b.timeIntervalSince(a) / 86_400).rounded(.down))
    }

    // MARK: Retrievability

    /// Probability of recall after `elapsedDays` with this stability.
    func retrievability(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + factor * max(0, elapsedDays) / stability, decay)
    }

    /// An item's probability of recall at `date` (0 for an item never studied), as py-fsrs computes it.
    func retrievability(of memory: MemoryState, at date: Date) -> Double {
        guard memory.state != .new, let last = memory.lastReview, memory.stability > 0 else { return 0 }
        let days = max(0, Self.elapsedDays(from: last, to: date))
        return retrievability(elapsedDays: Double(days), stability: memory.stability)
    }

    // MARK: The model

    func clampDifficulty(_ d: Double) -> Double { min(max(d, Self.minDifficulty), Self.maxDifficulty) }
    func clampStability(_ s: Double) -> Double { max(s, Self.stabilityMin) }

    func initialStability(_ rating: Rating) -> Double {
        clampStability(parameters[rating.rawValue - 1])
    }

    func initialDifficulty(_ rating: Rating, clamp: Bool = true) -> Double {
        let w = parameters
        let d = w[4] - pow(Self.e, w[5] * Double(rating.rawValue - 1)) + 1
        return clamp ? clampDifficulty(d) : d
    }

    /// Whole days until recall falls to the desired retention: banker's rounding, at least 1, at most the cap.
    func nextInterval(stability: Double) -> Int {
        let raw = (stability / factor) * (pow(desiredRetention, 1 / decay) - 1)
        guard raw.isFinite else { return maximumInterval }
        let rounded = raw.rounded(.toNearestOrEven)
        if rounded >= Double(maximumInterval) { return maximumInterval }
        return max(Int(rounded), 1)
    }

    /// Same-day review (w17–w19).
    func shortTermStability(_ stability: Double, rating: Rating) -> Double {
        let w = parameters
        var increase = pow(Self.e, w[17] * (Double(rating.rawValue - 3) + w[18])) * pow(stability, -w[19])
        if rating != .again { increase = max(increase, 1.0) }
        return clampStability(stability * increase)
    }

    /// Linear damping toward 10, then mean reversion toward the Easy initial difficulty (w7).
    func nextDifficulty(_ difficulty: Double, rating: Rating) -> Double {
        let w = parameters
        let target = initialDifficulty(.easy, clamp: false)
        let delta = -(w[6] * Double(rating.rawValue - 3))
        let damped = difficulty + (10.0 - difficulty) * delta / 9.0
        return clampDifficulty(w[7] * target + (1 - w[7]) * damped)
    }

    func nextStability(difficulty: Double, stability: Double, retrievability: Double, rating: Rating) -> Double {
        let next = rating == .again
            ? nextForgetStability(difficulty: difficulty, stability: stability, retrievability: retrievability)
            : nextRecallStability(difficulty: difficulty, stability: stability, retrievability: retrievability, rating: rating)
        return clampStability(next)
    }

    func nextForgetStability(difficulty: Double, stability: Double, retrievability: Double) -> Double {
        let w = parameters
        let longTerm = w[11] * pow(difficulty, -w[12]) * (pow(stability + 1, w[13]) - 1)
            * pow(Self.e, (1 - retrievability) * w[14])
        let shortTerm = stability / pow(Self.e, w[17] * w[18])
        return min(longTerm, shortTerm)
    }

    func nextRecallStability(difficulty: Double, stability: Double, retrievability: Double, rating: Rating) -> Double {
        let w = parameters
        let hardPenalty = rating == .hard ? w[15] : 1
        let easyBonus = rating == .easy ? w[16] : 1
        return stability * (1 + pow(Self.e, w[8]) * (11 - difficulty) * pow(stability, -w[9])
            * (pow(Self.e, (1 - retrievability) * w[10]) - 1) * hardPenalty * easyBonus)
    }

    /// py-fsrs's fuzz bounds for a whole-day interval (no fuzz below 2.5 days).
    func fuzzRange(intervalDays: Int) -> ClosedRange<Int> {
        guard Double(intervalDays) >= 2.5 else { return intervalDays...intervalDays }
        var delta = 1.0
        for r in Self.fuzzRanges {
            delta += r.factor * max(min(Double(intervalDays), r.end) - r.start, 0)
        }
        var lo = Int((Double(intervalDays) - delta).rounded(.toNearestOrEven))
        var hi = Int((Double(intervalDays) + delta).rounded(.toNearestOrEven))
        lo = max(2, lo)
        hi = min(hi, maximumInterval)
        lo = min(lo, hi)
        return lo...hi
    }

    // MARK: Reviewing

    struct Outcome: Sendable, Equatable {
        /// The state after the answer; `due` is the unfuzzed due time.
        var memory: MemoryState
        /// Time until due: a learning step, or whole days for a review.
        var interval: TimeInterval
        /// Whole days until due when the item is in review after the answer; nil for a (re)learning step.
        var intervalDays: Int?
        /// Whole days since the previous review (nil for a first review).
        var elapsedDays: Int?
        /// Probability of recall at the moment of the answer (0 for a new item).
        var retrievability: Double
    }

    /// Applies one answer, exactly as py-fsrs's `Scheduler.review_card` with fuzzing off.
    func review(_ memory: MemoryState, rating: Rating, at now: Date) -> Outcome {
        let fresh = memory.state == .new || memory.stability <= 0 || memory.difficulty <= 0
        let stateBefore: CardState = fresh ? .learning : memory.state
        let stepBefore = fresh ? 0 : max(0, memory.step)
        let daysSince: Int? = fresh ? nil : memory.lastReview.map { Self.elapsedDays(from: $0, to: now) }
        let r = fresh ? 0 : retrievability(of: memory, at: now)

        // Stability and difficulty.
        var s = memory.stability
        var d = memory.difficulty
        if fresh {
            s = initialStability(rating)
            d = initialDifficulty(rating, clamp: true)
        } else {
            if let ds = daysSince, ds < 1 {
                s = shortTermStability(s, rating: rating)
            } else {
                s = nextStability(difficulty: d, stability: s, retrievability: r, rating: rating)
            }
            d = nextDifficulty(d, rating: rating)
        }

        // The next interval.
        let next: StepResult
        switch stateBefore {
        case .new, .learning:
            next = stepResult(steps: learningSteps, step: stepBefore, rating: rating, state: .learning)
        case .review:
            if rating == .again && !relearningSteps.isEmpty {
                next = .step(state: .relearning, index: 0, interval: relearningSteps[0])
            } else {
                next = .graduate
            }
        case .relearning:
            next = stepResult(steps: relearningSteps, step: stepBefore, rating: rating, state: .relearning)
        }

        var after = memory
        after.stability = s
        after.difficulty = d
        after.lastReview = now
        after.reps = memory.reps + 1
        if memory.state == .review && rating == .again { after.lapses = memory.lapses + 1 }
        var interval: TimeInterval
        var intervalDays: Int?
        switch next {
        case .graduate:
            let days = nextInterval(stability: s)
            after.state = .review
            after.step = 0
            interval = Double(days) * 86_400
            intervalDays = days
        case .step(let state, let index, let seconds):
            after.state = state
            after.step = index
            interval = seconds
        }
        after.due = now.addingTimeInterval(interval)
        return Outcome(memory: after, interval: interval, intervalDays: intervalDays, elapsedDays: daysSince,
                       retrievability: r)
    }

    private enum StepResult {
        case graduate
        case step(state: CardState, index: Int, interval: TimeInterval)
    }

    /// The (re)learning-steps branch of py-fsrs's scheduler; `state` is the state the item stays in.
    private func stepResult(steps: [TimeInterval], step: Int, rating: Rating, state: CardState) -> StepResult {
        if steps.isEmpty || (step >= steps.count && rating != .again) { return .graduate }
        switch rating {
        case .again:
            return .step(state: state, index: 0, interval: steps[0])
        case .hard:
            if step == 0 && steps.count == 1 { return .step(state: state, index: 0, interval: steps[0] * 1.5) }
            if step == 0 && steps.count >= 2 {
                return .step(state: state, index: 0, interval: (steps[0] + steps[1]) / 2.0)
            }
            return .step(state: state, index: step, interval: steps[min(step, steps.count - 1)])
        case .good:
            if step + 1 == steps.count { return .graduate }
            return .step(state: state, index: step + 1, interval: steps[step + 1])
        case .easy:
            return .graduate
        }
    }
}
