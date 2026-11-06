import ActivityKit
import AppIntents
import Foundation

/// Repeat and Skip on Study out loud's Live Activity. They run in the app, which is already awake (it holds the microphone), so nothing has to open:
/// a phone in a pocket stays in the pocket. Compiled into both targets because the widget draws the buttons; the app listens through
/// `OutLoudRemote`, and with no session running they do nothing.
@MainActor
enum OutLoudRemote {
    enum Command: Equatable, Sendable {
        case repeatQuestion, skip
    }

    /// The session in progress (`OutLoudController`).
    static var handler: ((Command) -> Void)?

    static func send(_ command: Command) {
        handler?(command)
    }
}

struct OutLoudRepeatIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Repeat the question"
    static let description = IntentDescription("Cap asks the question again.")
    static let isDiscoverable = false

    #if HAS_IOS27_SDK
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult {
        OutLoudRemote.send(.repeatQuestion)
        return .result()
    }
}

struct OutLoudSkipIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip the question"
    static let description = IntentDescription("Cap moves on to the next question.")
    static let isDiscoverable = false

    #if HAS_IOS27_SDK
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult {
        OutLoudRemote.send(.skip)
        return .result()
    }
}
