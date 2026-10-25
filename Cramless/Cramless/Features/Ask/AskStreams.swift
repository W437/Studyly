import Foundation

/// Cap's answers while they stream, by chat. It outlives the screen that asked: leave the Ask tab mid-answer and the
/// answer still arrives and is saved. Only the finished answer (or what arrived before the person pressed stop)
/// becomes a `ChatMessage`, through `AppModel.saveAnswer`.
///
/// What an answer said about itself (who answered, a note, a consent or paywall suggestion, whether it was cut
/// short) is kept here for this run of the app, by message id; the stored message keeps its origin.
@MainActor
@Observable
final class AskStreams {
    static let shared = AskStreams()

    /// The answer being written.
    struct Live: Equatable {
        var question: String
        var text = ""
        var citations: [Citation] = []
        /// Nil until the first words arrive (Cap is still reading the notes).
        var origin: ItemOrigin?
    }

    /// What a finished answer said about itself.
    struct Note: Equatable {
        var origin: ItemOrigin
        var note: String?
        var suggestion: AISuggestion?
        var grounded: Bool
        var interrupted: Bool
    }

    private(set) var live: [UUID: Live] = [:]
    private(set) var notes: [UUID: Note] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    /// The ask each chat's task belongs to, so a stopped one finishing late never clears a newer answer.
    @ObservationIgnored private var tickets: [UUID: UUID] = [:]
    /// The item an "Explain my mistake" answer is about, so a stopped one keeps it.
    @ObservationIgnored private var contextItems: [UUID: UUID] = [:]

    #if DEBUG
    /// Harness: stop reading after this many text pieces, so an answer can be shown mid-stream.
    @ObservationIgnored var freezeAfterPieces: Int?
    #endif

    init() {}

    func isAnswering(_ threadID: UUID?) -> Bool {
        guard let threadID else { return false }
        return live[threadID] != nil
    }

    /// Asks Cap in a chat: adds the question, streams the answer, saves it when complete. One answer at a time per
    /// chat. `sendAs` is what the tutor reads instead of the shown words when they lean on the chat ("Explain with
    /// an analogy", a quick-check answer). `context` seeds an "Explain my mistake" chat; `contextItemID` marks its
    /// messages.
    func ask(_ question: String, in thread: ChatThread, app: AppModel, sendAs: String? = nil, context: TutorContext? = nil,
             contextItemID: UUID? = nil, preferring sourceID: UUID? = nil) {
        let threadID = thread.id
        guard live[threadID] == nil, app.addQuestion(question, to: thread, contextItemID: contextItemID) != nil else { return }
        let input = app.tutorInput(for: thread, context: context, preferring: sourceID, lastQuestionAs: sendAs)
        let ticket = UUID()
        tickets[threadID] = ticket
        contextItems[threadID] = contextItemID
        live[threadID] = Live(question: question)
        tasks[threadID] = Task { [weak self, weak app] in
            guard let app else { return }
            var outcome: TutorOutcome?
            var pieces = 0
            for await update in app.ai.tutor(input) {
                guard let self, self.tickets[threadID] == ticket else { return }
                switch update {
                case .started(let origin):
                    self.live[threadID]?.origin = origin
                case .text(let piece):
                    self.live[threadID]?.text += piece
                    pieces += 1
                case .citation(let citation):
                    self.live[threadID]?.citations.append(citation)
                case .finished(let finished):
                    outcome = finished
                }
                #if DEBUG
                if let freeze = self.freezeAfterPieces, pieces >= freeze {
                    // Hold the answer mid-way for a screenshot: never finish.
                    try? await Task.sleep(for: .seconds(3600))
                    return
                }
                #endif
            }
            guard let self, self.tickets[threadID] == ticket else { return }
            self.finish(threadID, thread: thread, outcome: outcome, app: app, contextItemID: contextItemID)
        }
    }

    /// Stops the answer being written. What arrived so far is kept, marked as stopped.
    func stop(_ threadID: UUID, app: AppModel) {
        guard let task = tasks[threadID] else { return }
        task.cancel()
        tasks[threadID] = nil
        tickets[threadID] = nil
        let contextItemID = contextItems.removeValue(forKey: threadID)
        guard let current = live[threadID] else { return }
        live[threadID] = nil
        let text = current.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let thread = app.thread(threadID) else { return }
        let outcome = TutorOutcome(text: text, citations: current.citations, origin: current.origin ?? .rules, model: "",
                                   mode: app.settings.effectiveTutorMode, grounded: !current.citations.isEmpty,
                                   interrupted: true, note: "You stopped Cap part way. This is what arrived.")
        if let message = app.saveAnswer(outcome, to: thread, contextItemID: contextItemID) {
            notes[message.id] = Note(origin: outcome.origin, note: outcome.note, suggestion: nil, grounded: outcome.grounded,
                                     interrupted: true)
        }
    }

    /// Stops every answer in a chat that is about to be deleted, without saving it.
    func discard(_ threadID: UUID) {
        tasks[threadID]?.cancel()
        tasks[threadID] = nil
        tickets[threadID] = nil
        contextItems[threadID] = nil
        live[threadID] = nil
    }

    /// Waits for a chat's answer to finish (tests).
    func waitForAnswer(_ threadID: UUID) async {
        await tasks[threadID]?.value
    }

    private func finish(_ threadID: UUID, thread: ChatThread, outcome: TutorOutcome?, app: AppModel, contextItemID: UUID?) {
        tasks[threadID] = nil
        tickets[threadID] = nil
        contextItems[threadID] = nil
        let current = live[threadID]
        live[threadID] = nil
        // The stream ended without an outcome only when it was cancelled; `stop` saved what arrived.
        guard var outcome else { return }
        if outcome.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let current, !current.text.isEmpty {
            outcome.text = current.text
        }
        guard let message = app.saveAnswer(outcome, to: thread, contextItemID: contextItemID) else { return }
        notes[message.id] = Note(origin: outcome.origin, note: outcome.note, suggestion: outcome.suggestion,
                                 grounded: outcome.grounded, interrupted: outcome.interrupted)
    }
}
