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
        /// What Cap's assistant is doing for this reply (cards being written, a search under way, …).
        var steps: [AssistantStep] = []

        /// Changes whenever the reply has grown, so the chat can follow it down.
        var progress: Int {
            steps.reduce(text.count / 80 + steps.count * 100_000) { $0 &+ $1.growth }
        }
    }

    /// What a finished answer said about itself.
    struct Note: Equatable {
        var origin: ItemOrigin
        var note: String?
        var suggestion: AISuggestion?
        var grounded: Bool
        var interrupted: Bool
        /// Cloud AI couldn't be reached, so the reply came from this iPhone: the student can have Cap answer it later.
        var offersLater = false
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
    /// Harness: hold an assistant reply after this many updates (text, steps), to show a card half way through its work.
    @ObservationIgnored var freezeAfterUpdates: Int?
    #endif

    init() {}

    func isAnswering(_ threadID: UUID?) -> Bool {
        guard let threadID else { return false }
        return live[threadID] != nil
    }

    /// Asks Cap in a chat: adds the question, streams the answer, saves it when complete. One answer at a time per
    /// chat. `sendAs` is what the tutor reads instead of the shown words when they lean on the chat ("Explain with
    /// an analogy", a quick-check answer). `context` seeds an "Explain my mistake" chat; `contextItemID` marks its
    /// messages. `fromPhoto`: the words were read off a photo the student snapped; the chat stays with the tutor from then on.
    func ask(_ question: String, in thread: ChatThread, app: AppModel, sendAs: String? = nil, context: TutorContext? = nil,
             contextItemID: UUID? = nil, preferring sourceID: UUID? = nil, fromPhoto: Bool = false) {
        let threadID = thread.id
        guard live[threadID] == nil, app.addQuestion(question, to: thread, contextItemID: contextItemID, fromPhoto: fromPhoto) != nil else { return }
        let input = app.tutorInput(for: thread, context: context, preferring: sourceID, lastQuestionAs: sendAs)
        // Ask Cap's assistant first (it can make things as well as answer); the tutor when it can't or shouldn't.
        let assistantWanted = !input.fromPhoto && contextItemID == nil
            && app.ai.assistantAvailable(question: sendAs ?? question, hasContext: context != nil)
        let assistantInput = assistantWanted ? app.assistantInput(for: thread, lastQuestionAs: sendAs) : nil
        let ticket = UUID()
        tickets[threadID] = ticket
        contextItems[threadID] = contextItemID
        live[threadID] = Live(question: question)
        tasks[threadID] = Task { [weak self, weak app] in
            guard let app else { return }
            if let assistantInput {
                var outcome: AssistantOutcome?
                var declined = false
                var updates = 0
                for await update in app.ai.assistant(assistantInput) {
                    guard let self, self.tickets[threadID] == ticket else { return }
                    switch update {
                    case .started:
                        self.live[threadID]?.origin = .cloud
                    case .text(let piece):
                        self.live[threadID]?.text += piece
                    case .citation(let citation):
                        self.live[threadID]?.citations.append(citation)
                    case .step(let step):
                        self.upsert(step, in: threadID)
                    case .finished(let finished):
                        outcome = finished
                    case .declined:
                        declined = true
                    }
                    updates += 1
                    #if DEBUG
                    if let freeze = self.freezeAfterUpdates, updates >= freeze {
                        try? await Task.sleep(for: .seconds(3600))
                        return
                    }
                    #endif
                }
                guard let self, self.tickets[threadID] == ticket else { return }
                if !declined {
                    self.finishAssistant(threadID, thread: thread, outcome: outcome, app: app)
                    return
                }
                // Nothing was shown: the tutor answers instead.
                self.live[threadID]?.steps = []
            }
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

    /// A step began or changed: replaces the one with its id, else is added after the others.
    private func upsert(_ step: AssistantStep, in threadID: UUID) {
        guard var current = live[threadID] else { return }
        if let i = current.steps.firstIndex(where: { $0.id == step.id }) { current.steps[i] = step } else { current.steps.append(step) }
        live[threadID] = current
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
        // What the assistant had made so far stays, as it stood.
        if !current.steps.isEmpty, let thread = app.thread(threadID) {
            let outcome = AssistantOutcome(text: text, citations: current.citations, steps: current.steps, model: "", interrupted: true,
                                           note: String(localized: "You stopped Cap part way. This is what arrived."))
            if let message = app.saveAssistantAnswer(outcome, to: thread) {
                notes[message.id] = Note(origin: .cloud, note: outcome.note, suggestion: nil, grounded: !current.citations.isEmpty, interrupted: true)
            }
            return
        }
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

    private func finishAssistant(_ threadID: UUID, thread: ChatThread, outcome: AssistantOutcome?, app: AppModel) {
        tasks[threadID] = nil
        tickets[threadID] = nil
        contextItems[threadID] = nil
        let current = live[threadID]
        live[threadID] = nil
        guard var outcome else { return }
        if outcome.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let current, !current.text.isEmpty {
            outcome.text = current.text
        }
        guard let message = app.saveAssistantAnswer(outcome, to: thread) else { return }
        // A free allowance that ran out is said once, with the way to lift it.
        let suggestion: AISuggestion? = outcome.limit == "drafts" && !app.ai.plan.isPaid
            ? .upgrade(.tutor, message: AIFreeLimits.draftsMessage) : nil
        notes[message.id] = Note(origin: .cloud, note: outcome.note, suggestion: suggestion, grounded: !outcome.citations.isEmpty,
                                 interrupted: outcome.interrupted)
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
                                 grounded: outcome.grounded, interrupted: outcome.interrupted,
                                 offersLater: outcome.cloudUnreachable && contextItemID == nil)
    }
}
