import Foundation

/// What the free AI allowance says before the work starts, so nobody learns of a limit by hitting it: lines under the + sheet's
/// Scan, PDF and Record rows, under "Scan pages" in the scanner, and in the recorder's "Making notes" line. Pure: the counts come
/// from `AIRouter.freeCloudUsesLeft(for:)`, which is nil when there is nothing to say (a paid plan, Cloud AI off or not in this
/// build, a child's account), and then so is every line here. The lines name the meters only, which stay true even when the
/// day's cost cap pauses Cloud AI first.
enum AllowanceCopy {
    /// "2 free AI scans left this week", or that they're used up and what still works. (A PDF is read as a scan too.)
    static func scans(left: Int?) -> LocalizedStringResource? {
        guard let left else { return nil }
        return left > 0 ? "\(left) free AI scans left this week"
            : "Free AI scans are used up until Monday. Cap still writes questions on your iPhone."
    }

    /// "AI notes for 1 lecture left this week", or that they're used and the transcript still works.
    static func lectures(left: Int?) -> LocalizedStringResource? {
        guard let left else { return nil }
        return left > 0 ? "AI notes for \(left) lecture left this week"
            : "This week's AI lecture notes are used. Transcripts still work."
    }

    /// The + sheet's footer, on the free plan.
    static let alwaysFree: LocalizedStringResource = "Reviews, cards you make and imports are always free."

    /// The recorder's line while it makes notes. `cloud`: Cloud AI may write them (consent, a relay in this build, not a child);
    /// `lecturesLeft`: the free lecture notes left when the person pressed stop (nil on a paid plan).
    static func makingNotes(cloud: Bool, lecturesLeft: Int?) -> LocalizedStringResource {
        guard cloud else {
            return "Sections with their times, the moments flagged for the exam, key terms and questions, on your iPhone."
        }
        switch lecturesLeft {
        case nil:
            return "Sections with their times, the moments flagged for the exam, key terms and questions, with Cloud AI."
        case let left? where left > 0:
            return "Sections with their times, the moments flagged for the exam, key terms and questions, with Cloud AI, using this week's free AI notes."
        default:
            return "Sections with their times, the moments flagged for the exam, key terms and questions, on your iPhone. This week's AI lecture notes are used. Transcripts still work."
        }
    }
}
