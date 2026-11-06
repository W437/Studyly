import Foundation

/// One of Cap's cards on Today ("Cap noticed"): what he noticed, in a title and a line, and the one thing to do about it. Today shows
/// one at a time with "1 of N" and "Later" (`TodayNoticeCard`); `AppModel.todayNotices()` deals them, `snoozeNotice(_:)` puts one off
/// until tomorrow and `perform(_:)` runs its action. A plain value, so the notice engine (pure) can make them and every card is tested
/// without a view.
struct CapNotice: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable, CaseIterable {
        /// Two ideas the person keeps confusing (an open `Confusion`).
        case mixUp
        /// Two questions that look alike and keep being swapped.
        case lookAlike
        /// Questions fading before an exam.
        case fading
        /// Back after days away.
        case welcomeBack
    }

    /// What the card's button does.
    struct Action: Equatable, Sendable {
        enum Run: Equatable, Sendable {
            /// A mix-up's 2-minute fix drill.
            case fixMixUp(confusionID: UUID)
            /// A session: a practice round on a topic, a short review.
            case session(kind: SessionKind, minutes: Int?, courseID: UUID?, topicID: UUID?, examID: UUID?)
        }

        /// "Fix it · 2 min".
        var title: String
        var systemImage: String
        var run: Run
    }

    /// What a tap on the card's title opens, when there is more to read.
    enum Link: Equatable, Sendable {
        case confusion(UUID)
        case exam(UUID)
    }

    /// Stable for the day: "<kind>:<subject>" ("mixUp:<confusion id>"), so a snooze or an action finds the same card again.
    var id: String
    var kind: Kind
    /// "You keep mixing up anaphase and telophase."
    var title: String
    /// "Missed 3 of the last 4 times. Want a 2-minute fix?"
    var detail: String
    var action: Action?
    var link: Link? = nil
}
