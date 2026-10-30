import Foundation

// What the screens hand `AIRouter.assistant` and what comes back, as plain values (the same idea as `AIOutcomes.swift`).

/// Ask Cap's message and the material Cap may read for it.
struct AssistantInput: Hashable, Sendable {
    /// The chat so far; the last user message is the request. Earlier replies carry what their steps drafted.
    var messages: [TutorMessage]
    /// The chat's course (nil: every course).
    var courseID: UUID?
    var courseName: String?
    var material: [TutorMaterial]
}

enum AssistantUpdate: Equatable, Sendable {
    /// Cap has begun (a first word, or the first tool). Sent once.
    case started
    case text(String)
    case citation(Citation)
    /// A step began or changed: replace the step with this id, or add it at the end.
    case step(AssistantStep)
    case finished(AssistantOutcome)
    /// Nothing was shown and nothing was spent: answer with the tutor instead.
    case declined
}

struct AssistantOutcome: Equatable, Sendable {
    var text: String
    var citations: [Citation]
    var steps: [AssistantStep]
    var model: String
    /// The reply broke off part way (connection lost, or the student pressed stop).
    var interrupted = false
    var note: String?
    /// A free allowance ran out during this reply ("drafts"): the screen offers Capling Pro.
    var limit: String?
}

/// One tool call, as the model made it.
struct AssistantToolCall: Hashable, Sendable {
    var callID: String
    var name: AssistantToolName
    var arguments: AnyJSON
}

/// What running a tool gave: the step to show, and the short text the model is told.
struct AssistantToolRun: Equatable, Sendable {
    var step: AssistantStep
    var output: String
}

extension AnyJSON {
    /// Compact JSON text, keys sorted: what the model reads as a tool's result.
    var jsonString: String {
        guard let data = try? JSONEncoder.cramless.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// An object from pairs, for tool results.
    static func result(_ pairs: [String: AnyJSON]) -> AnyJSON { .object(pairs) }
}
