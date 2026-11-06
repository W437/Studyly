import Foundation

/// One of Cap's cards on Today ("Cap noticed") in words: what he noticed, in a title and a line, and the one thing to do about it.
/// Today shows one at a time with "1 of N" and "Later" (`TodayNoticeCard`). `NoticeEngine` decides which cards there are (`Notice`),
/// `NoticeContent` says them, `AppModel.todayNotices()` deals them, `snoozeNotice(_:)` puts one off until tomorrow and `perform(_:)`
/// runs its action. A plain value, so every card is tested without a view.
struct CapNotice: Identifiable, Equatable, Sendable {
    typealias Kind = NoticeKind

    /// What the card's button does.
    struct Action: Equatable, Sendable {
        enum Run: Equatable, Sendable {
            /// A mix-up's 2-minute fix drill.
            case fixMixUp(confusionID: UUID)
            /// A session: a practice round on a topic, a short review.
            case session(kind: SessionKind, minutes: Int?, courseID: UUID?, topicID: UUID?, examID: UUID?)
            /// "Show me": the sheet with two look-alikes side by side.
            case showLookAlike(LookAlikePair)
            /// "Fix my week": adds the minutes to the plan.
            case fixMyWeek(FadeRescue)
            /// Takes "Fix my week" back.
            case undoFixMyWeek(noticeID: String)
            /// "Take it": a mock of this exam.
            case takeMock(examID: UUID)
            /// "Fill the gap": how Cap can help with this exam's topics that have no notes.
            case fillGap(examID: UUID)
            /// "See it": the lecture the date was heard in, where it can be added.
            case openHeardDate(sourceID: UUID, noticeID: String)
            /// "Yes, harder": a harder question for this one.
            case raiseQuestion(itemID: UUID)
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

    /// The card's id in the deck (`Notice.id`), so a snooze or an action finds the same card again.
    var id: String
    var kind: Kind
    /// "You keep mixing up anaphase and telophase."
    var title: String
    /// "Missed 3 of the last 4 times. Want a 2-minute fix?"
    var detail: String
    var action: Action?
    var link: Link? = nil
    /// What the button uses: "No AI", "Uses Cloud AI".
    var cost: String? = nil
    /// "Plan updated": a card already acted on, saying what changed, with Undo and no "Later".
    var isConfirmation = false
}
