import Foundation

/// What a student's own record says about how a plan will go, as blends that start at a prior and move a little with each day: there is no
/// day on which the number jumps because a threshold was passed, and a student with no record isn't marked down for it. Pure.
enum StudyHabits {
    /// The share of a plan a student with no record is taken to do. High: in replays a missed day costs 0 to 3 points, and a low prior
    /// started every student's projection about 10 points under where they ended.
    static let followThroughPrior = 0.95
    /// How many days of record the prior weighs as much as.
    static let followThroughWeight = 7.0
    static let followThroughRange = 0.5...0.95

    /// The share of the plan the student tends to do: the days studied of the `span` days since they began (up to two weeks), blended
    /// with the prior. Students who skip days come down from it as the days pass.
    static func followThrough(studied: Int, span: Int) -> Double {
        let blended = (Double(studied) + followThroughPrior * followThroughWeight) / (Double(max(0, span)) + followThroughWeight)
        return min(followThroughRange.upperBound, max(followThroughRange.lowerBound, blended))
    }

    /// The chance a first look at a new question is right, with no record.
    static let firstLookPrior = 0.75
    /// How many first looks the prior weighs as much as.
    static let firstLookWeight = 20.0
    static let firstLookRange = 0.4...0.95

    /// The student's first-try rate: `right` of `looks` first looks, blended with the prior.
    static func firstLookSuccess(right: Int, looks: Int) -> Double {
        let blended = (Double(right) + firstLookPrior * firstLookWeight) / (Double(max(0, looks)) + firstLookWeight)
        return min(firstLookRange.upperBound, max(firstLookRange.lowerBound, blended))
    }
}
