import AppIntents
import Foundation

// Intents that open a screen. Each one hands a capling:// link to the app through `CramlessIntentBridge`, the
// same path the widgets and notifications take, so `DeepLinks` is the one place that decides what opening means.
// "Start today's session" (`StartSessionIntent`) lives in Shared/ because the Control Center control uses it too.

/// "Scan pages": opens the scanner.
struct ScanPagesIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan pages"
    static let description = IntentDescription("Opens the Capling scanner to turn pages of notes into questions.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinks.installIntentBridge()
        CramlessIntentBridge.open(CramlessLink.scan)
        return .result()
    }
}

/// "Record a lecture": opens the recorder.
struct RecordLectureIntent: AppIntent {
    static let title: LocalizedStringResource = "Record a lecture"
    static let description = IntentDescription("Opens the Capling lecture recorder.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinks.installIntentBridge()
        CramlessIntentBridge.open(CramlessLink.record)
        return .result()
    }
}
