import SwiftUI

/// Numbers counting up, in at most 12 steps along the fill curve (the readiness ring's), with one light tick per
/// step. One count drives every number on a screen, so they land together and the ticks never double up.
enum CountUp {
    static let maxSteps = 12

    /// Steps for a count up to the largest of `targets`: one per unit, at most 12.
    static func steps(to targets: [Int]) -> Int {
        min(maxSteps, targets.map(abs).max() ?? 0)
    }

    /// The number shown at `step` of `steps` on the way to `target`: 0 at the start, exactly `target` at the end.
    static func value(_ target: Int, step: Int, of steps: Int) -> Int {
        guard steps > 0 else { return target }
        let done = Double(min(max(step, 0), steps)) / Double(steps)
        return Int((Double(target) * done).rounded())
    }

    /// Seconds after the count starts at which each step lands.
    static func times(steps: Int, duration: Double) -> [Double] {
        guard steps > 0 else { return [] }
        return (1...steps).map { SweepTiming.time(toReach: Double($0) / Double(steps)) * duration }
    }
}

/// A number that counts up with `CountUp`: `value` at `step` of `steps`, its digits rolling as they change.
struct CLCountingText: View {
    let value: Int
    let step: Int
    let steps: Int
    var format: (Int) -> String = { "\($0)" }

    var body: some View {
        let shown = CountUp.value(value, step: step, of: steps)
        Text(verbatim: format(shown))
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(shown)))
    }
}
