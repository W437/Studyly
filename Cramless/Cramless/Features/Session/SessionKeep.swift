import Foundation

/// Half-typed own-words answers, kept across a call, a switch to another app, or iOS closing the app, so nothing typed is lost.
/// One draft per question (item id), at most `limit`, each kept `lifetime`; the newest win. Saved as the person types (a 400 ms
/// pause) and when the app leaves the screen; restored into an empty editor; cleared when the answer is recorded. Pure: storage
/// is `AppModel+SessionKeep`.
struct AnswerDrafts: Codable, Equatable, Sendable {
    struct Draft: Codable, Equatable, Sendable {
        var text: String
        var savedAt: Date
    }

    static let defaultsKey = "capling.session.drafts.v1"
    static let limit = 30
    static let lifetime: TimeInterval = 7 * 86_400

    /// Item id (uuidString) → its draft.
    var drafts: [String: Draft] = [:]

    /// The draft for a question, unless it has expired.
    func draft(for itemID: UUID, now: Date) -> Draft? {
        guard let draft = drafts[itemID.uuidString], now.timeIntervalSince(draft.savedAt) < Self.lifetime else { return nil }
        return draft
    }

    /// Keeps `text` for a question (blank text removes its draft), dropping expired drafts and the oldest past the limit.
    mutating func keep(_ text: String, for itemID: UUID, now: Date) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drafts[itemID.uuidString] = nil
        } else {
            drafts[itemID.uuidString] = Draft(text: text, savedAt: now)
        }
        prune(now: now)
    }

    mutating func clear(_ itemID: UUID) {
        drafts[itemID.uuidString] = nil
    }

    /// Expired drafts go; past the limit, the oldest go.
    mutating func prune(now: Date) {
        drafts = drafts.filter { now.timeIntervalSince($0.value.savedAt) < Self.lifetime }
        guard drafts.count > Self.limit else { return }
        let keep = drafts.sorted { $0.value.savedAt > $1.value.savedAt }.prefix(Self.limit)
        drafts = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }
}

/// Where a session stood, written when it starts and at each question, cleared when it finishes or the person leaves. One that
/// is still there at the next launch belongs to a session iOS closed (or that crashed): the same day, a daily, catch-up or eve
/// session picks up from it (`SessionRunner(…, resuming:)`), in the same `StudySession`, with the minutes it had left and the
/// question that was on screen first. The time the app was closed is never counted (`wallSeconds`).
struct SessionCheckpoint: Codable, Equatable, Sendable {
    static let defaultsKey = "capling.session.checkpoint.v1"

    var sessionID: UUID
    var kindRaw: String
    var courseID: UUID?
    var examID: UUID?
    /// "2026-11-06": the day it counts for; a checkpoint from another day is never resumed.
    var dayKey: String
    var plannedSeconds: Double
    /// The question on screen (it comes first when the session picks up).
    var currentItemID: UUID?
    /// Seconds the session was open on screen, up to this checkpoint (the gap while the app was closed is not in it).
    var wallSeconds: Double
    var savedAt: Date

    var kind: SessionKind? { SessionKind(rawValue: kindRaw) }

    /// The kinds that pick up where they left off: the day's own sessions. A practice round or a fix starts again.
    static let resumableKinds: Set<SessionKind> = [.daily, .catchUp, .examEve]

    /// Whether this checkpoint can be picked up by a request of `kind` today (`dayKey` is today's).
    func resumes(_ kind: SessionKind, today dayKey: String) -> Bool {
        Self.resumableKinds.contains(kind) && self.kind == kind && self.dayKey == dayKey
    }

    /// Seconds still planned, from what was studied before the close.
    func remainingSeconds(activeSeconds: Double) -> Double {
        max(0, plannedSeconds - activeSeconds)
    }

    /// The whole minutes a resumed session is built for: what is left, rounded up, at least one (the drafted question still waits).
    func remainingMinutes(activeSeconds: Double) -> Int {
        max(1, Int((remainingSeconds(activeSeconds: activeSeconds) / 60).rounded(.up)))
    }

    /// A session worth picking up: time left, or a question with a draft on it.
    func isWorthResuming(activeSeconds: Double, hasDraft: Bool) -> Bool {
        remainingSeconds(activeSeconds: activeSeconds) >= 60 || hasDraft
    }
}
