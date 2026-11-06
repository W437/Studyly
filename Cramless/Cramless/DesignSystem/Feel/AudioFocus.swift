import Foundation

/// Who owns the audio session. Read-aloud, the lecture recorder and lecture playback claim it before they touch
/// AVAudioSession and release it when they're done. While any of them holds it, sound effects stay silent and their
/// engine is stopped, so speech can deactivate the session afterwards (giving other apps their music back) and the
/// microphone never hears an effect. Speech or the microphone taking it also stops a lecture that is playing.
@MainActor
enum AudioFocus {
    enum Owner: Hashable, Sendable {
        case speech, microphone, playback
    }

    private(set) static var owners: Set<Owner> = []

    static var allowsEffects: Bool { owners.isEmpty }

    static func claim(_ owner: Owner) {
        owners.insert(owner)
        CLSound.shared.suspend()
        if owner != .playback { LecturePlayer.shared.yieldAudio() }
    }

    static func release(_ owner: Owner) {
        owners.remove(owner)
    }
}
