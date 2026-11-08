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

    /// What one reading will take, said where it is about to start, once its pages are known: "This is 21 pages, so it takes 3 of your free
    /// AI scans." With too few scans left, "You have 1 free AI scan left, so Cap reads the first 10 of 12 pages." Nil for a reading that
    /// fits one scan, or with nothing to say (`left` nil). `needed`: the scans all its pages take; `readable`: the pages `left` scans read.
    static func reading(pages: Int, needed: Int, readable: Int, left: Int?) -> LocalizedStringResource? {
        guard let left else { return nil }
        guard left > 0 else { return scans(left: 0) }
        if readable < pages { return "You have \(left) free AI scans left, so Cap reads the first \(readable) of \(pages) pages." }
        return needed > 1 ? "This is \(pages) pages, so it takes \(needed) of your free AI scans." : nil
    }

    /// The + sheet's one line under its list, on the free plan: "This week: 3 free AI scans, 1 lecture." With the scans used up, that and what
    /// still works (a lecture's own line is the recorder's). Nil with nothing to say (a paid plan, Cloud AI off, a child's account).
    static func week(scans: Int?, lectures: Int?) -> LocalizedStringResource? {
        guard let scans else { return nil }
        guard scans > 0 else { return self.scans(left: 0) }
        if let lectures, lectures > 0 { return "This week: \(scans) free AI scans, \(lectures) lectures." }
        return "This week: \(scans) free AI scans."
    }

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
