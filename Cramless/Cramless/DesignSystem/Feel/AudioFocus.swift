import Foundation

/// Who owns the audio session. Read-aloud and the lecture recorder claim it before they touch AVAudioSession and
/// release it when they're done. While either holds it, sound effects stay silent and their engine is stopped,
/// so speech can deactivate the session afterwards (giving other apps their music back) and the microphone never
/// hears an effect.
@MainActor
enum AudioFocus {
    enum Owner: Hashable, Sendable {
        case speech, microphone
    }

    private(set) static var owners: Set<Owner> = []

    static var allowsEffects: Bool { owners.isEmpty }

    static func claim(_ owner: Owner) {
        owners.insert(owner)
        CLSound.shared.suspend()
    }

    static func release(_ owner: Owner) {
        owners.remove(owner)
    }
}
