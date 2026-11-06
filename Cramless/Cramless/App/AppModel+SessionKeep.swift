import Foundation
import SwiftData

// Nothing lost mid-answer: half-typed own-words answers (`AnswerDrafts`) and where a session stood (`SessionCheckpoint`), both kept in
// UserDefaults on this iPhone (never synced: they are moments, not records), so a session iOS closed picks up the same day with
// the typed words still there. The rules are pure, in `Features/Session/SessionKeep.swift`; this is their storage and the one
// decision that reads the store (`resumableCheckpoint(for:)`).
extension AppModel {

    // MARK: - Drafts

    private var answerDrafts: AnswerDrafts {
        guard let data = defaults.data(forKey: AnswerDrafts.defaultsKey),
              let drafts = try? JSONDecoder.cramless.decode(AnswerDrafts.self, from: data) else { return AnswerDrafts() }
        return drafts
    }

    private func storeAnswerDrafts(_ drafts: AnswerDrafts) {
        if drafts.drafts.isEmpty {
            defaults.removeObject(forKey: AnswerDrafts.defaultsKey)
        } else if let data = try? JSONEncoder.cramless.encode(drafts) {
            defaults.set(data, forKey: AnswerDrafts.defaultsKey)
        }
    }

    /// What the person had typed for this question and not yet sent, if it is still fresh (7 days).
    func answerDraft(for itemID: UUID) -> String? {
        answerDrafts.draft(for: itemID, now: now)?.text
    }

    /// Keeps a half-typed answer (blank text removes it). Equal text is not written again.
    func keepAnswerDraft(_ text: String, for itemID: UUID) {
        var drafts = answerDrafts
        guard drafts.drafts[itemID.uuidString]?.text != text else { return }
        drafts.keep(text, for: itemID, now: now)
        storeAnswerDrafts(drafts)
    }

    /// The answer was recorded: its draft goes.
    func clearAnswerDraft(for itemID: UUID) {
        var drafts = answerDrafts
        guard drafts.drafts[itemID.uuidString] != nil else { return }
        drafts.clear(itemID)
        storeAnswerDrafts(drafts)
    }

    // MARK: - Where a session stood

    func sessionCheckpoint() -> SessionCheckpoint? {
        guard let data = defaults.data(forKey: SessionCheckpoint.defaultsKey) else { return nil }
        return try? JSONDecoder.cramless.decode(SessionCheckpoint.self, from: data)
    }

    func keepSessionCheckpoint(_ checkpoint: SessionCheckpoint) {
        if let data = try? JSONEncoder.cramless.encode(checkpoint) {
            defaults.set(data, forKey: SessionCheckpoint.defaultsKey)
        }
    }

    /// The session finished or the person left: nothing to pick up. With a session id, only that session's checkpoint goes.
    func clearSessionCheckpoint(sessionID: UUID? = nil) {
        if let sessionID, let current = sessionCheckpoint(), current.sessionID != sessionID { return }
        defaults.removeObject(forKey: SessionCheckpoint.defaultsKey)
    }

    /// The checkpoint a request picks up, if any: a daily, catch-up or eve session of the same kind, today, whose `StudySession` is
    /// still open (iOS closed the app before it finished) and has time left or a drafted question. A checkpoint that can never be
    /// picked up any more (another day, its session finished or gone) is cleared.
    func resumableCheckpoint(for request: SessionRequest) -> SessionCheckpoint? {
        guard let checkpoint = sessionCheckpoint() else { return nil }
        let today = calendar.dayKey(for: now)
        guard let session = studySession(checkpoint.sessionID), session.endedAt == nil, checkpoint.dayKey == today else {
            clearSessionCheckpoint()
            return nil
        }
        guard checkpoint.resumes(request.kind, today: today), request.itemIDs.isEmpty,
              request.courseID == checkpoint.courseID else { return nil }
        let drafted = checkpoint.currentItemID.map { answerDraft(for: $0) != nil } ?? false
        guard checkpoint.isWorthResuming(activeSeconds: session.activeSeconds, hasDraft: drafted) else { return nil }
        return checkpoint
    }

    /// The ratings a session has so far, oldest first (a session picked up shows them on its progress bar).
    func sessionRatings(_ sessionID: UUID) -> [Rating] {
        let id: UUID? = sessionID
        return fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.sessionID == id },
                                                sortBy: [SortDescriptor(\.reviewedAt)])).map(\.rating)
    }

    /// Everything kept here goes (deleting everything on this iPhone).
    func clearSessionKeep() {
        defaults.removeObject(forKey: AnswerDrafts.defaultsKey)
        defaults.removeObject(forKey: SessionCheckpoint.defaultsKey)
    }

    // MARK: - DEBUG

    #if DEBUG
    /// `CRAMLESS_SESSION_RESUME=1`: a session of this kind cut off earlier today, as iOS leaves one: three answers recorded, words half
    /// typed on an own-words question (`CRAMLESS_SESSION_DRAFT`, or a half sentence of its own), its checkpoint written, never
    /// finished. The session that opens next picks it up.
    func debugCutOffSession(_ request: SessionRequest) {
        let runner = SessionRunner(app: self, request: request, options: .init(liveActivity: false))
        guard runner.phase == .ready else { return }
        runner.start()
        runner.debugAnswer(3, finishing: false)
        let waiting = runner.queue.entries.dropFirst(runner.queue.position).first { $0.kind.isOwnWords }?.itemID
        let fallback = fetch(FetchDescriptorFactory.allItems).filter { $0.deletedAt == nil && $0.status == .active && $0.kind.isOwnWords }
        let ownWords = waiting
            ?? fallback.first { $0.prompt.localizedCaseInsensitiveContains("why do cells divide") }?.id
            ?? fallback.first?.id
        guard var checkpoint = sessionCheckpoint(), let ownWords else { return }
        keepAnswerDraft(TestHarness.once("CRAMLESS_SESSION_DRAFT") ?? "So the body can grow and", for: ownWords)
        checkpoint.currentItemID = ownWords
        checkpoint.wallSeconds = 240
        keepSessionCheckpoint(checkpoint)
    }
    #endif
}
