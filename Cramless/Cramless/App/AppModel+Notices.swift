import Foundation
import SwiftData

// Cap's cards on Today ("Cap noticed", `CapNotice`). Until the notice engine deals them, the cards are today's open mix-ups: the
// one with the most misses first (the note Today always had), at most three, each put off until tomorrow by "Later" (the same
// snooze store as before, `snoozeConfusion`).
extension AppModel {
    /// At most this many cards a day.
    static let noticesPerDay = 3

    /// Today's cards, in the order Today shows them (the first is on screen; "1 of N" counts the rest).
    func todayNotices() -> [CapNotice] {
        guard hasActiveItems() else { return [] }
        return openConfusionNotes().map(Self.notice(for:))
    }

    /// "Later": the card waits until tomorrow.
    func snoozeNotice(_ id: String) {
        guard let subject = Self.subject(of: id, kind: .mixUp) else { return }
        snoozeConfusion(subject)
    }

    /// Runs a card's action: readies what it needs and presents it.
    @discardableResult
    func perform(_ action: CapNotice.Action) -> SessionRequest? {
        let request: SessionRequest?
        switch action.run {
        case .fixMixUp(let id):
            request = prepareFix(id)
        case .session(let kind, let minutes, let courseID, let topicID, let examID):
            request = SessionRequest(kind: kind, courseID: courseID, examID: examID, minutes: minutes, topicID: topicID)
        }
        if let request { router.present(.session(request)) }
        return request
    }

    /// A mix-up as one of Cap's cards.
    static func notice(for note: ConfusionNote) -> CapNotice {
        CapNotice(id: "\(CapNotice.Kind.mixUp.rawValue):\(note.id.uuidString)", kind: .mixUp,
                  title: SessionCopy.mixUpLine(note.name), detail: SessionCopy.missLine(note),
                  action: CapNotice.Action(title: String(localized: "Fix it · 2 min"), systemImage: "wand.and.stars",
                                           run: .fixMixUp(confusionID: note.id)),
                  link: .confusion(note.id))
    }

    /// The id a card of `kind` was made with: "mixUp:<uuid>" → the uuid.
    static func subject(of id: String, kind: CapNotice.Kind) -> UUID? {
        let prefix = "\(kind.rawValue):"
        guard id.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(id.dropFirst(prefix.count)))
    }
}

#if DEBUG
/// `CRAMLESS_TODAY_NOTICES=<n>`: the demo world has one open mix-up; these stand in for more, so "1 of 3" and "Later" can be seen.
@MainActor
enum TodayNoticesDemo {
    static func notices(base: [CapNotice]) -> [CapNotice] {
        let fixID = base.first.flatMap { notice -> UUID? in
            if case .fixMixUp(let id)? = notice.action?.run { return id }
            return nil
        }
        let extras = [("Meiosis vs mitosis", 4, 3), ("Moles vs molar mass", 3, 2)].enumerated().map { index, demo in
            AppModel.notice(for: ConfusionNote(id: fixID ?? StableRandom.uuid("demo-notice-\(index)"), name: demo.0,
                                               missCount: demo.1, recentMisses: demo.2, recentAnswers: 4))
        }.enumerated().map { index, notice -> CapNotice in
            var n = notice
            n.id = "mixUp:demo-\(index)"
            return n
        }
        return base + extras
    }
}
#endif

private extension AppModel {
    /// Open mix-ups not put off today, the most missed first (the most recent first on a tie): the order Today's note always had
    /// (`todayConfusionNote()` is the first of them).
    func openConfusionNotes() -> [ConfusionNote] {
        let open = fetch(FetchDescriptor<Confusion>(predicate: #Predicate { $0.deletedAt == nil }))
            .filter { $0.status == .open && $0.course?.deletedAt == nil && !isConfusionSnoozed($0.id) }
            .sorted { ($0.missCount, $0.lastSeenAt) > ($1.missCount, $1.lastSeenAt) }
        return open.prefix(Self.noticesPerDay).map { confusion in
            let recent = recentAnswers(itemIDs: confusion.itemIDs, limit: 4)
            return ConfusionNote(id: confusion.id, name: confusion.name, missCount: confusion.missCount,
                                 recentMisses: recent.filter { !$0.wasCorrect }.count, recentAnswers: recent.count)
        }
    }
}
