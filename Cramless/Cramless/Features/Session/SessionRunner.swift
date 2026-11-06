import Foundation
import Observation
import SwiftData
import SwiftUI

/// One session in progress: the queue, what each answer was, the `StudySession` row and the Live Activity.
///
/// The question views grade (through `app.ai`) and decide the rating; the runner records the answer once the
/// person commits it (Continue, or a flashcard rating), moves on (an item still in a learning step comes back
/// later through `SessionQueue`), keeps the Live Activity in step, and finishes into the engine's summary. It never
/// grades and fires no haptics: those belong to the views, where the person acts.
///
/// A rating the person gave themselves can be taken back for a moment (`Options.undoWindow`): it is held (`PendingGrade`) with nothing
/// written, the session moves on from a preview of what it will do, and it is recorded through the same path when the window ends,
/// the next answer is recorded, the session closes or the app goes to the background. Holding rather than reverting is the point: a
/// review log is append-only once sync has pushed it.
@MainActor
@Observable
final class SessionRunner: Identifiable {
    /// How an answer went, for the progress segments and the summary.
    enum Outcome: String, Sendable, Equatable {
        case right, partial, wrong

        init(_ verdict: GradeResponse.Verdict) {
            switch verdict {
            case .correct: self = .right
            case .partial: self = .partial
            case .incorrect: self = .wrong
            }
        }

        init(rating: Rating) {
            switch rating {
            case .again: self = .wrong
            case .hard: self = .partial
            case .good, .easy: self = .right
            }
        }
    }

    enum Phase: Equatable, Sendable {
        /// Built, not started.
        case ready
        /// Nothing to study.
        case empty
        case question
        /// The last question's rating is held for Undo: "That was the last one." The summary starts when it is recorded.
        case wrapping
        case finished
    }

    struct Options: Sendable {
        /// The session's Live Activity (off in onboarding).
        var liveActivity = true
        /// Items still in a learning step come back later in the session (off for the two-question check).
        var requeues = true
        /// How long a self-given rating can be taken back. Nil: recorded at once (tests, onboarding, the quick check).
        var undoWindow: Duration? = nil
    }

    /// One answer, in order. `isPending`: held for Undo, not recorded yet.
    struct Answer: Sendable, Equatable {
        var entry: SessionEntry
        var outcome: Outcome
        var review: ReviewOutcome
        var isPending = false
    }

    /// What a question view needs to come back as it was when its rating is undone.
    enum AnswerRestore {
        /// A flashcard: flipped, its time to the flip kept.
        case flashcard(flippedAtMs: Int)
        /// An own-words answer: its panel, with no new grade and no sounds.
        case ownWords(OwnWordsRestore)
    }

    /// An own-words answer as it stood on Continue.
    struct OwnWordsRestore {
        var submitted: String
        var grade: GradeOutcome
        var durationMs: Int
        var intervals: [Rating: Double]
        var ticked: Set<String>
        var marked: Bool
        var rulesFound: Bool
        var override: Rating?
        var secondLook: String?
        var run: Int
        var saved: Bool
    }

    /// A rating held for Undo: everything `recordReview` needs later, and how to go back.
    struct PendingGrade {
        var reviewID: UUID
        var entry: SessionEntry
        var rating: Rating
        var score: Double
        var answer: String?
        var gradedBy: String
        var durationMs: Int
        var sessionID: UUID?
        /// When the rating was given and the day it counts for, whenever it ends up recorded.
        var ratedAt: Date
        var dayKey: String
        /// What recording it will do.
        var preview: ReviewOutcome
        var queueBefore: SessionQueue
        var restore: AnswerRestore
    }

    /// How the next question comes on screen.
    enum Arrival: Sendable, Equatable {
        /// From the trailing edge.
        case forward
        /// Back from the leading edge (an Undo).
        case back
        /// Rising in place (after a flashcard flew off by a swipe).
        case rise
    }

    /// Got it and Again for the flashcards so far, a held rating included. Hard and Easy count as got it.
    struct FlashcardTally: Sendable, Equatable {
        var gotIt = 0
        var again = 0
        var isEmpty: Bool { gotIt == 0 && again == 0 }
    }

    let id = UUID()
    let request: SessionRequest
    let options: Options
    private(set) var built: BuiltSession
    private(set) var queue: SessionQueue
    private(set) var phase: Phase
    private(set) var session: StudySession?
    private(set) var summary: SessionSummary?
    /// Committed outcomes by entry id ("<item>#<attempt>").
    private(set) var outcomes: [String: Outcome] = [:]
    /// The current question's grade before it is committed (colours its segment early).
    private(set) var provisional: Outcome?
    private(set) var answers: [Answer] = []
    /// The rating being held for Undo, if any.
    private(set) var pending: PendingGrade?
    /// How the next question comes on screen (`SessionQuestionHost` reads it).
    private(set) var arrival: Arrival = .forward
    /// The streak as it was when the session started (the summary shows what changed).
    private(set) var streakBefore: StreakState
    /// Wall clock, for the timer and answer durations (the app clock may be frozen by the harness).
    private(set) var startedAt = Date()
    private(set) var questionShownAt = Date()
    /// The current question has an answer that isn't recorded yet: typed, picked or graded.
    var hasUnsavedAnswer = false
    /// Words are being typed on the current question (kept as a draft if the person leaves).
    @ObservationIgnored var isTypingAnswer = false
    /// The latest save ("Saved it."), for the sky's flare over the session.
    private(set) var saveFlare: SaveFlare?
    @ObservationIgnored private var saveCount = 0
    /// What an undone rating leaves for its question view to pick up as it comes back.
    @ObservationIgnored private var restoring: (entryID: String, restore: AnswerRestore)?
    /// Ends the Undo window.
    @ObservationIgnored private var pendingTimer: Task<Void, Never>?
    #if DEBUG
    /// The Undo pill stays until it is pressed (a screenshot of it).
    @ObservationIgnored var debugHoldsUndo = false
    #endif

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var items: [UUID: StudyItem] = [:]
    @ObservationIgnored private let topicNames: [UUID: String]
    /// Distinct items in the session when it started (the Live Activity's total).
    @ObservationIgnored private var activityTotal = 0
    /// Picking up a session iOS closed: its open `StudySession`, and the seconds it had been on screen before.
    @ObservationIgnored private var resumedSession: StudySession?
    @ObservationIgnored private var priorWallSeconds = 0.0
    /// The app clock when this runner started (what the checkpoint's wall time counts from).
    @ObservationIgnored private var clockStart: Date?
    /// This runner picked up a session that was cut off ("Picked up where you left off.").
    let resumed: Bool

    /// `resuming`: a checkpoint of a session iOS closed today (`AppModel.resumableCheckpoint(for:)`). The session goes on in the same
    /// `StudySession` with the minutes it had left, the question that was on screen first; the time the app was closed isn't
    /// counted. A checkpoint whose session is gone or finished is ignored.
    init(app: AppModel, request: SessionRequest, options: Options = Options(), resuming checkpoint: SessionCheckpoint? = nil) {
        self.app = app
        self.request = request
        self.options = options
        var built: BuiltSession
        if let checkpoint, let session = app.studySession(checkpoint.sessionID), session.endedAt == nil {
            var rest = request
            rest.minutes = checkpoint.remainingMinutes(activeSeconds: session.activeSeconds)
            built = app.buildSession(rest)
            if let current = checkpoint.currentItemID { Self.putFirst(current, in: &built, app: app) }
            resumedSession = session
            priorWallSeconds = checkpoint.wallSeconds
            resumed = !built.isEmpty
        } else {
            built = app.buildSession(request)
            resumed = false
        }
        self.built = built
        self.queue = SessionQueue(built)
        self.phase = built.isEmpty ? .empty : .ready
        self.streakBefore = app.streak()
        self.topicNames = app.topicNames()
    }

    /// The question that was on screen when the session was cut off comes first: moved up if the rebuilt session has it, else
    /// added (it is still active and in a live course).
    private static func putFirst(_ itemID: UUID, in built: inout BuiltSession, app: AppModel) {
        if let index = built.entries.firstIndex(where: { $0.itemID == itemID }) {
            built.entries.insert(built.entries.remove(at: index), at: 0)
        } else if let item = app.item(itemID), item.deletedAt == nil, item.status == .active, item.course?.deletedAt == nil {
            built.entries.insert(SessionEntry(itemID: item.id, reason: .due, kind: item.kind, topicID: item.topicID,
                                              courseID: item.course?.id, estimatedSeconds: item.kind.typicalSeconds), at: 0)
        }
    }

    // MARK: Reading

    var current: SessionEntry? { phase == .question || phase == .ready ? queue.current : nil }
    var sessionID: UUID? { session?.id }
    var kind: SessionKind { request.kind }

    /// Distinct items answered, and how many of them were right the first time.
    var distinctAnswered: Int { Set(answers.map(\.entry.itemID)).count }
    var rightFirstTime: Int {
        var seen = Set<UUID>()
        var right = 0
        for answer in answers where seen.insert(answer.entry.itemID).inserted {
            if answer.review.wasCorrect { right += 1 }
        }
        return right
    }

    /// The tally of the flashcards rated so far (ratings, not distinct cards: a card that came back counts again).
    var flashcardTally: FlashcardTally {
        var tally = FlashcardTally()
        for answer in answers where answer.entry.kind == .flashcard {
            if answer.review.rating == .again { tally.again += 1 } else { tally.gotIt += 1 }
        }
        return tally
    }

    func item(for entry: SessionEntry) -> StudyItem? {
        if let cached = items[entry.itemID], cached.modelContext != nil, cached.deletedAt == nil { return cached }
        guard let item = app.item(entry.itemID), item.deletedAt == nil else { return nil }
        items[entry.itemID] = item
        return item
    }

    func topicName(_ id: UUID?) -> String? { id.flatMap { topicNames[$0] } }

    /// The course a session is limited to.
    var courseName: String? { request.courseID.flatMap { app.course($0)?.name } }

    /// The segment colour for queue position `index`.
    func segment(_ index: Int) -> SegmentState {
        let entries = queue.entries
        guard entries.indices.contains(index) else { return .pending }
        if let outcome = outcomes[entries[index].id] { return .done(outcome) }
        if index == queue.position, phase == .question {
            return provisional.map(SegmentState.done) ?? .current
        }
        return .pending
    }

    enum SegmentState: Equatable {
        case pending, current
        case done(Outcome)
    }

    /// Milliseconds since the current question appeared.
    func elapsedMs() -> Int { max(0, Int(Date().timeIntervalSince(questionShownAt) * 1000)) }

    // MARK: Runs, saves and cues

    /// The run of right answers so far (`ComboRun`), counting the current question as `outcome` when given.
    func combo(adding outcome: Outcome? = nil, kind: ItemKind? = nil) -> Int {
        // An answer the person marked themselves counts like any other: right when the rating they came to is Good or better, which is
        // what the quests read from the log (`AppModel.questFacts`), so the run on screen and the run the quests see are one.
        var steps = answers.map { ComboRun.Step(counts: $0.entry.kind != .flashcard, right: $0.outcome == .right) }
        if let outcome, let kind { steps.append(ComboRun.Step(counts: kind != .flashcard, right: outcome == .right)) }
        return ComboRun.length(steps)
    }

    /// What the panel shows for this answer's run: nothing in Quiet mode, where no run is counted out loud.
    func shownRun(adding outcome: Outcome, kind: ItemKind) -> Int {
        app.settings.quietMode ? 0 : combo(adding: outcome, kind: kind)
    }

    /// The run as it stands, counting the question on screen once it's checked. Quiet mode shows none.
    var liveCombo: Int {
        guard !app.settings.quietMode else { return 0 }
        guard let provisional, let entry = queue.current else { return combo() }
        return combo(adding: provisional, kind: entry.kind)
    }

    /// A right answer now would be a save: the item was studied before and its chance of recall has fallen below
    /// `ReviewOutcome.fadingRecall` (the same test `ReviewOutcome.isSave` makes once it's recorded).
    func wouldSave(_ item: StudyItem) -> Bool {
        let memory = item.memory
        guard memory.state != .new else { return false }
        return app.fsrs.retrievability(of: memory, at: app.now) < ReviewOutcome.fadingRecall
    }

    /// "Saved it." has just come up for `item`: the sky's flare plays over the question, with the save's sound. The
    /// views call this where they play the verdict's cues (a flashcard when it is rated), once per question.
    func flareSave(of item: StudyItem) {
        saveCount += 1
        saveFlare = SaveFlare(id: saveCount, color: item.course?.color ?? .sky)
    }

    /// The sounds for a checked answer, which the view plays as its verdict shows: the run's next note (then the
    /// flourish at 5, 10, 15), the save's sparkle, a soft step down for "Almost", a muted pair for "Not yet", and the
    /// answer shown for "I don't know".
    func cues(for outcome: Outcome, item: StudyItem, answered: Bool) -> [CLCue] {
        guard answered else { return [.revealed] }
        switch outcome {
        case .right:
            let run = combo(adding: .right, kind: item.kind)
            // In Quiet mode no run is counted out loud, so the milestone has no flourish either.
            let flourish: [CLCue] = ComboRun.isMilestone(run) && !app.settings.quietMode ? [.flourish] : []
            return (wouldSave(item) ? [.saved] : [.right(combo: run)]) + flourish
        case .partial:
            return [.almost]
        case .wrong:
            return [.notYet]
        }
    }

    // MARK: Running

    /// Starts the StudySession (readiness before) and the Live Activity, or carries on the one that was cut off. Idempotent.
    func start() {
        guard phase == .ready else { return }
        if let resumedSession, resumedSession.modelContext != nil, resumedSession.endedAt == nil {
            session = resumedSession
            StudyRuntime.setLoad(app.currentDueLoad(), for: resumedSession.id)
        } else {
            session = app.startSession(built)
        }
        clockStart = app.now
        startedAt = Date()
        questionShownAt = Date()
        phase = .question
        activityTotal = Set(queue.entries.map(\.itemID)).count
        if options.liveActivity {
            let title = request.kind == .daily ? courseName.map(SessionCopy.studyCourse) : nil
            app.liveActivities.startSession(title: title ?? SessionCopy.title(for: request.kind), total: activityTotal,
                                            plannedMinutes: built.plannedMinutes)
        }
        keepCheckpoint()
    }

    /// The current question was graded (not yet committed).
    func setProvisional(_ outcome: Outcome?) {
        provisional = outcome
        hasUnsavedAnswer = outcome != nil || hasUnsavedAnswer
    }

    /// Records the current question's answer through the engine. Idempotent per entry. `gradedBy` says who graded it: "rules",
    /// "onDevice", "cloud", "person" for a rating the person gave (a flashcard, or another rating than the grade's), and "self" for an
    /// own-words answer the person marked against the model answer because no model graded it.
    ///
    /// `undo`: this is a rating the person gave themselves, and this is how its question comes back. With `Options.undoWindow` set it is
    /// held instead of recorded, and what is returned is what recording it will do. Any older held rating is recorded first.
    @discardableResult
    func record(rating: Rating, score: Double, answer: String?, gradedBy: String, durationMs: Int,
                outcome: Outcome, undo restore: AnswerRestore? = nil) -> ReviewOutcome? {
        guard phase == .question, let entry = queue.current else { return nil }
        if let done = answers.first(where: { $0.entry.id == entry.id }) { return done.review }
        commitPending()
        let trimmed = answer?.trimmingCharacters(in: .whitespacesAndNewlines)
        let given = (trimmed?.isEmpty ?? true) ? nil : trimmed
        if let restore, options.undoWindow != nil {
            return hold(entry, rating: rating, score: score, answer: given, gradedBy: gradedBy, durationMs: durationMs,
                        outcome: outcome, restore: restore)
        }
        guard let review = app.recordReview(itemID: entry.itemID, rating: rating, score: score, answer: given, gradedBy: gradedBy,
                                            durationMs: durationMs, sessionID: session?.id) else { return nil }
        answers.append(Answer(entry: entry, outcome: outcome, review: review))
        outcomes[entry.id] = outcome
        provisional = nil
        hasUnsavedAnswer = false
        // Recorded: what was typed for it is no longer a draft.
        app.clearAnswerDraft(for: entry.itemID)
        updateLiveActivity()
        return review
    }

    private func updateLiveActivity() {
        guard options.liveActivity else { return }
        let next = queue.upcoming.first
        app.liveActivities.update(answered: min(distinctAnswered, max(activityTotal, 1)), correct: rightFirstTime,
                                  topic: topicName(next?.topicID))
    }

    /// Moves past the current question: an item still in a learning step is re-queued; the last one finishes (or, with its rating
    /// held for Undo, waits on "That was the last one.").
    func advance(arriving arrival: Arrival = .forward) {
        guard phase == .question, let entry = queue.current else { return }
        // A question left without an answer leaves a held rating behind: it can't come back past this one.
        if let pending, pending.entry.id != entry.id { commitPending() }
        prepareArrival(arrival)
        if options.requeues, let answer = answers.last(where: { $0.entry.id == entry.id }) {
            queue.advance(rating: answer.review.rating, memoryAfter: answer.review.after)
        } else {
            queue.skip()
        }
        provisional = nil
        hasUnsavedAnswer = false
        isTypingAnswer = false
        questionShownAt = Date()
        if queue.isFinished {
            if pending != nil { phase = .wrapping } else { finish() }
        } else {
            keepCheckpoint()
        }
    }

    /// Moves past the current question with nothing recorded: it has gone to Cap to check, so it counts for nothing.
    func skipWithoutRecording() {
        guard phase == .question, let entry = queue.current else { return }
        app.clearAnswerDraft(for: entry.itemID)
        advance()
    }

    /// "Looks wrong?" belongs to a real session, not to onboarding's two-question check.
    var offersLooksWrong: Bool { request.kind != .quickCheck }

    // MARK: Undo

    /// Holds a rating for the Undo window. The answer joins the session at once (segments, tally, Live Activity); nothing is written
    /// until it is committed.
    private func hold(_ entry: SessionEntry, rating: Rating, score: Double, answer: String?, gradedBy: String, durationMs: Int,
                      outcome: Outcome, restore: AnswerRestore) -> ReviewOutcome? {
        let reviewID = ModelID.make()
        let ratedAt = app.now
        guard let preview = app.previewReview(itemID: entry.itemID, rating: rating, score: score, sessionID: session?.id,
                                              at: ratedAt, reviewID: reviewID) else { return nil }
        pending = PendingGrade(reviewID: reviewID, entry: entry, rating: rating, score: score, answer: answer, gradedBy: gradedBy,
                               durationMs: durationMs, sessionID: session?.id, ratedAt: ratedAt,
                               dayKey: app.calendar.dayKey(for: ratedAt), preview: preview, queueBefore: queue, restore: restore)
        answers.append(Answer(entry: entry, outcome: outcome, review: preview, isPending: true))
        outcomes[entry.id] = outcome
        provisional = nil
        hasUnsavedAnswer = false
        updateLiveActivity()
        startPendingTimer()
        return preview
    }

    private func startPendingTimer() {
        pendingTimer?.cancel()
        pendingTimer = nil
        guard let window = options.undoWindow else { return }
        #if DEBUG
        if debugHoldsUndo || TestHarness.value("CRAMLESS_UNDO_HOLD") == "1" { return }
        #endif
        pendingTimer = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: window) } catch { return }
            guard let self, !Task.isCancelled else { return }
            withAnimation(CLMotion.settle) { self.commitPending() }
        }
    }

    /// Records the held rating, if any, through the idempotent path, with the time and day it was given. On "That was the last one." the
    /// summary starts here.
    func commitPending() {
        guard settlePending(), phase == .wrapping else { return }
        finish()
    }

    /// Writes the held rating. True if there was one.
    @discardableResult
    private func settlePending() -> Bool {
        guard let pending else { return false }
        self.pending = nil
        pendingTimer?.cancel()
        pendingTimer = nil
        let review = app.recordReview(itemID: pending.entry.itemID, rating: pending.rating, score: pending.score, answer: pending.answer,
                                      gradedBy: pending.gradedBy, durationMs: pending.durationMs, sessionID: pending.sessionID,
                                      at: pending.ratedAt, dayKey: pending.dayKey, reviewID: pending.reviewID)
        if let index = answers.lastIndex(where: { $0.entry.id == pending.entry.id }) {
            answers[index].isPending = false
            if let review { answers[index].review = review }
        }
        // Recorded: what was typed for it is no longer a draft.
        app.clearAnswerDraft(for: pending.entry.itemID)
        return true
    }

    /// Takes the held rating back: the question returns (a copy it re-queued goes with it) and nothing was written.
    func undoPending() {
        guard let pending else { return }
        self.pending = nil
        pendingTimer?.cancel()
        pendingTimer = nil
        if let index = answers.lastIndex(where: { $0.entry.id == pending.entry.id }) { answers.remove(at: index) }
        outcomes[pending.entry.id] = nil
        queue = pending.queueBefore
        restoring = (pending.entry.id, pending.restore)
        provisional = nil
        hasUnsavedAnswer = false
        isTypingAnswer = false
        phase = .question
        questionShownAt = Date()
        updateLiveActivity()
        keepCheckpoint()
    }

    /// The way a question picks up the state it had when its rating was undone (once).
    func takeRestore(for entryID: String) -> AnswerRestore? {
        guard let restoring, restoring.entryID == entryID else { return nil }
        self.restoring = nil
        return restoring.restore
    }

    /// The next question is coming from this side. Set a moment before the change, so the question leaving takes it too.
    func prepareArrival(_ arrival: Arrival) {
        if self.arrival != arrival { self.arrival = arrival }
    }

    /// Ends the session (idempotent): the engine's summary, the Live Activity's last word. Nothing is left to pick up.
    func finish() {
        guard phase != .finished else { return }
        settlePending()
        let wasEmpty = phase == .empty
        phase = .finished
        if let session {
            app.clearSessionCheckpoint(sessionID: session.id)
            // A session picked up after a close counts the time it was on screen, never the gap.
            let wallStart = resumedSession == nil ? nil : app.now.addingTimeInterval(-wallSeconds)
            summary = app.finishSession(session, wallStart: wallStart)
        } else if let resumedSession, resumedSession.modelContext != nil, resumedSession.endedAt == nil {
            // Picked up with nothing left to study: the session that was cut off ends here, so it isn't offered again.
            app.clearSessionCheckpoint(sessionID: resumedSession.id)
            app.finishSession(resumedSession, wallStart: app.now.addingTimeInterval(-priorWallSeconds))
        }
        if options.liveActivity, !wasEmpty { app.liveActivities.end() }
    }

    // MARK: Picking up after a close

    /// Seconds this session has been on screen: before a close it was picked up from, and since this runner started (app clock).
    var wallSeconds: Double {
        priorWallSeconds + max(0, clockStart.map { app.now.timeIntervalSince($0) } ?? 0)
    }

    /// Where the session stands, written at the start and at each question (and when the app leaves the screen), for a session
    /// kind that can pick up again (`SessionCheckpoint.resumableKinds`).
    func keepCheckpoint() {
        guard phase == .question || phase == .wrapping, let session,
              SessionCheckpoint.resumableKinds.contains(request.kind) else { return }
        app.keepSessionCheckpoint(SessionCheckpoint(
            sessionID: session.id, kindRaw: request.kind.rawValue, courseID: request.courseID, examID: session.examID,
            dayKey: app.calendar.dayKey(for: session.startedAt), plannedSeconds: session.plannedSeconds,
            currentItemID: queue.current?.itemID, wallSeconds: wallSeconds, savedAt: app.now))
    }

    /// Whether this entry's answer is recorded (or held for Undo).
    func hasRecorded(_ entryID: String) -> Bool { outcomes[entryID] != nil }

    /// The person left early: everything answered stays recorded.
    func close() { finish() }

    // MARK: DEBUG

    #if DEBUG
    /// Puts the first entry of one of `kinds` first (adding one for an item of that kind when the session has none),
    /// so a screenshot can open on a format.
    func debugFront(kinds: [ItemKind], preferring prompt: String? = nil) {
        guard phase == .ready else { return }
        var entries = queue.entries
        let isMatch: (SessionEntry) -> Bool = { kinds.contains($0.kind) }
        if let prompt, let item = app.fetch(FetchDescriptorFactory.allItems).first(where: {
            $0.deletedAt == nil && kinds.contains($0.kind) && $0.prompt.localizedCaseInsensitiveContains(prompt)
        }) {
            entries.removeAll { $0.itemID == item.id }
            entries.insert(Self.debugEntry(for: item), at: 0)
        } else if let i = entries.firstIndex(where: isMatch) {
            entries.insert(entries.remove(at: i), at: 0)
        } else if let item = app.fetch(FetchDescriptorFactory.allItems).first(where: {
            $0.deletedAt == nil && $0.status == .active && kinds.contains($0.kind)
        }) {
            entries.insert(Self.debugEntry(for: item), at: 0)
        }
        queue = SessionQueue(entries: entries)
    }

    /// A session of only these kinds (a film of a run of flashcards), filled from every active item when the session has too few.
    func debugOnly(kinds: [ItemKind]) {
        guard phase == .ready else { return }
        var entries = queue.entries.filter { kinds.contains($0.kind) }
        let have = Set(entries.map(\.itemID))
        for item in app.fetch(FetchDescriptorFactory.allItems) where entries.count < 8 {
            guard item.deletedAt == nil, item.status == .active, kinds.contains(item.kind), !have.contains(item.id) else { continue }
            entries.append(Self.debugEntry(for: item))
        }
        queue = SessionQueue(entries: entries)
    }

    /// Cuts the session down to its first question (a film of what follows the last one).
    func debugKeepFirstOnly() {
        guard phase == .ready, let first = queue.current else { return }
        queue = SessionQueue(entries: [first])
    }

    private static func debugEntry(for item: StudyItem) -> SessionEntry {
        SessionEntry(itemID: item.id, reason: .due, kind: item.kind, topicID: item.topicID, courseID: item.course?.id,
                     estimatedSeconds: item.kind.typicalSeconds)
    }

    /// Answers the next `count` questions with a fixed pattern of ratings, then finishes when `finishing`.
    func debugAnswer(_ count: Int, pattern: [Rating] = [.good, .good, .again, .good, .hard, .good, .easy, .good],
                     finishing: Bool = true) {
        var n = 0
        while n < count, phase == .question, let entry = queue.current {
            let rating = pattern[n % pattern.count]
            let isGraded = entry.kind != .flashcard
            let score = isGraded ? (rating == .again ? 0.2 : rating == .hard ? 0.67 : 1) : -1
            record(rating: rating, score: score, answer: nil, gradedBy: isGraded ? "rules" : "person",
                   durationMs: Int(entry.kind.typicalSeconds * 900), outcome: Outcome(rating: rating))
            advance()
            n += 1
        }
        if finishing { finish() }
    }

    /// Records a swapped answer for two items (each answered with the other's answer), the way a real mix-up
    /// looks in the log, so the summary finds a confusion.
    func debugSwap(_ a: StudyItem, _ b: StudyItem) {
        guard let session else { return }
        app.recordReview(itemID: a.id, rating: .again, score: 0, answer: b.answer, gradedBy: "rules", durationMs: 9000,
                         sessionID: session.id)
        app.recordReview(itemID: b.id, rating: .again, score: 0, answer: a.answer, gradedBy: "rules", durationMs: 9000,
                         sessionID: session.id)
    }
    #endif
}

#if DEBUG
extension FetchDescriptorFactory {
    static var allItems: FetchDescriptor<StudyItem> {
        FetchDescriptor<StudyItem>(sortBy: [SortDescriptor(\.createdAt)])
    }
}
#endif
