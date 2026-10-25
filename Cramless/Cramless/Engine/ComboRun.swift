import Foundation

/// A run of right answers in a session, the way the answer panel and the progress bar count it.
///
/// - A checked answer (multiple choice, fill-in, a diagram, an answer in your own words) builds the run when it's
///   right and ends it otherwise: "Almost", "Not yet" and "I don't know" all end it, quietly (nothing ever says a run
///   was lost).
/// - A flashcard's self-rating neither builds nor breaks it, so there's no reason to rate yourself generously.
enum ComboRun {
    struct Step: Sendable, Equatable {
        /// Checked by the app (not a self-rated flashcard).
        var counts: Bool
        var right: Bool
    }

    /// The run ending at the last step.
    static func length(_ steps: [Step]) -> Int {
        var length = 0
        for step in steps.reversed() where step.counts {
            guard step.right else { break }
            length += 1
        }
        return length
    }

    /// 5, 10, 15 in a row: the run earns its flourish.
    static func isMilestone(_ length: Int) -> Bool { length > 0 && length % 5 == 0 }

    /// The panel and the top bar show a run from three in a row.
    static let shownFrom = 3
}
