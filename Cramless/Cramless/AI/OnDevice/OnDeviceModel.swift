import Foundation
import FoundationModels

// The on-device model's seam (tier T1). A job is a typed call (instructions, a prompt, the shape of the answer);
// a backend answers it; `OnDeviceRunner` runs it with a timeout and **never throws**: any error, timeout,
// refusal or unusable answer comes back as nil, which means "keep the offline rules' answer". Nothing here shows
// an error to anyone.
//
// `FoundationModelsBackend` is the only code that talks to `LanguageModelSession`. It is compiled into every build
// and reached only when the router chose T1 (the model available, the text English and within the window). Tests
// install `ScriptedOnDeviceBackend` instead and the real calls never run in the simulator.

enum OnDeviceCallKind: String, Sendable {
    case generate, grade, tutor, lectureSection, cards, pick
}

/// One question to the model.
protocol OnDeviceCall: Sendable {
    associatedtype Output: Generable & Codable & Sendable
    static var kind: OnDeviceCallKind { get }
    static var instructions: String { get }
    /// Tokens the schema adds to the prompt (`includeSchemaInPrompt`), estimated high.
    static var schemaTokens: Int { get }
    /// Tokens kept for the answer.
    static var responseTokens: Int { get }
    static var timeout: Duration { get }
    static var temperature: Double { get }
    var prompt: String { get }
}

extension OnDeviceCall {
    static var temperature: Double { 0 }
}

enum OnDeviceError: Error, Equatable, Sendable {
    case unavailable
    case promptTooLong
    case timedOut
    case unusable
}

/// Something that answers calls: this iPhone's model, Private Cloud Compute, or a script.
protocol OnDeviceBackend: Sendable {
    func respond<C: OnDeviceCall>(_ call: C) async throws -> C.Output
}

/// This iPhone's model. One session per call (a session answers one request at a time).
struct FoundationModelsBackend: OnDeviceBackend {
    func respond<C: OnDeviceCall>(_ call: C) async throws -> C.Output {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { throw OnDeviceError.unavailable }
        let session = LanguageModelSession(model: model, instructions: C.instructions)
        let options = GenerationOptions(temperature: C.temperature, maximumResponseTokens: C.responseTokens)
        let response = try await session.respond(to: call.prompt, generating: C.Output.self, includeSchemaInPrompt: true,
                                                 options: options)
        return response.content
    }
}

enum OnDeviceRunner {
    /// Runs `call` on `backend`, checked against the window first and raced against the call's timeout.
    /// **Never throws.** Nil means use the offline answer.
    static func run<C: OnDeviceCall>(_ call: C, on backend: any OnDeviceBackend, budget: OnDeviceBudget) async -> C.Output? {
        guard budget.fits(call.prompt, instructions: C.instructions, schemaTokens: C.schemaTokens,
                          responseTokens: C.responseTokens) else { return nil }
        let timeout = C.timeout
        do {
            return try await withThrowingTaskGroup(of: C.Output?.self) { group in
                group.addTask { try await backend.respond(call) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw OnDeviceError.timedOut
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { return nil }
                return first
            }
        } catch {
            return nil
        }
    }
}

#if DEBUG
/// A backend that answers from a script, for tests and the debug harness. It touches no model. It returns, call
/// by call, the JSON it was given (decoded into the call's real `Output`, so the real mapping runs), throws, or
/// hangs until cancelled; and it records everything the model would have been told.
final class ScriptedOnDeviceBackend: OnDeviceBackend, @unchecked Sendable {
    enum Step {
        case json(String)
        case failure(any Error)
        /// Never answers; only cancellation (the runner's timeout) ends it.
        case hang
    }

    struct Recorded: Equatable {
        var kind: OnDeviceCallKind
        var instructions: String
        var prompt: String
    }

    private let lock = NSLock()
    private var steps: [Step]
    private var calls: [Recorded] = []

    init(_ steps: [Step]) { self.steps = steps }

    var requests: [Recorded] { lock.withLock { calls } }
    var callCount: Int { lock.withLock { calls.count } }

    func respond<C: OnDeviceCall>(_ call: C) async throws -> C.Output {
        let step: Step? = lock.withLock {
            calls.append(Recorded(kind: C.kind, instructions: C.instructions, prompt: call.prompt))
            return steps.isEmpty ? nil : steps.removeFirst()
        }
        guard let step else { throw OnDeviceError.unavailable }
        switch step {
        case .json(let text):
            do { return try JSONDecoder().decode(C.Output.self, from: Data(text.utf8)) } catch { throw OnDeviceError.unusable }
        case .failure(let error):
            throw error
        case .hang:
            try await Task.sleep(for: .seconds(3600))
            throw OnDeviceError.unavailable
        }
    }
}
#endif
