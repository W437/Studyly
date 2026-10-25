import AppIntents
import Foundation

/// "Start today's session": opens Capling on today's session. It's the action of the Control Center and Lock
/// Screen control (CramlessWidgets/StartSessionControl.swift) and a Siri and Shortcuts action (the app's
/// `CramlessShortcuts`), so it lives in Shared/ and is compiled into both targets. It needs the foreground, so the
/// system brings the app up and performs it there, where the handler `CramlessAppDelegate` installs routes the
/// link through `DeepLinks`.
struct StartSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start today's session"
    static let description = IntentDescription("Opens Capling on today's study session.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    #if HAS_IOS27_SDK
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult {
        CramlessIntentBridge.open(CramlessLink.session)
        return .result()
    }
}
