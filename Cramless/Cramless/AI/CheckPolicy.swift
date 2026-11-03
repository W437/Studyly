import Foundation

// What to do with the cloud check's verdicts. The second pass reads only the lines each question cites, so a question
// about a court opinion fails it for a reason that has nothing to do with the question: the cited lines never name the
// judge or the case ("does not identify Cardozo"). On Palsgraf the check marked all 16 correct questions unsupported,
// and the router, finding nothing left, threw the whole cloud attempt away for this iPhone's weaker model.
//
// A check that rejects nearly everything has misjudged the source, not the questions. So it is asked once more, leniently
// (and with the source's title and headings, which `CheckRequest` now carries), and if it still rejects nearly
// everything its verdicts are not believed: this iPhone checks the questions against the page itself.

enum CheckPolicy {

    /// A check that rejects this share of at least `minimumItems` questions has probably misjudged the source.
    static let suspiciousShare = 0.9
    static let minimumItems = 6

    enum Step: Equatable, Sendable {
        /// Use the verdicts as they are.
        case accept
        /// Ask again, with `lenient: true`.
        case retryLenient
        /// Don't believe the verdicts: check on this iPhone against the page, and say so.
        case checkOnThisIPhone
    }

    /// The verdicts reject at least 90% of at least 6 questions. Only verdicts about the given questions count.
    static func rejectsNearlyAll(_ verdicts: [CheckVerdict], itemIDs: [String]) -> Bool {
        let ids = Set(itemIDs)
        guard ids.count >= minimumItems else { return false }
        let rejected = Set(verdicts.filter { $0.verdict == .unsupported && ids.contains($0.id) }.map(\.id))
        return Double(rejected.count) >= suspiciousShare * Double(ids.count)
    }

    /// The next step after a check. `lenient` is whether this answer was already the lenient retry: a second near-total
    /// rejection ends in the local check, never in a third request.
    static func step(after verdicts: [CheckVerdict], itemIDs: [String], lenient: Bool) -> Step {
        guard rejectsNearlyAll(verdicts, itemIDs: itemIDs) else { return .accept }
        return lenient ? .checkOnThisIPhone : .retryLenient
    }
}
