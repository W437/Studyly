import AVFoundation
import Foundation

/// Reads questions aloud (Settings ▸ Accessibility ▸ Read aloud). Uses the person's own Spoken Content settings
/// (voice, rate) when they have them, ducks other audio while it speaks, and leaves the audio session alone while a
/// lecture is recording. Callers go through `AppModel.readAloud(_:force:)`, which checks the setting; an explicit
/// speaker button passes `force`.
@MainActor
@Observable
final class ReadAloud: NSObject {
    static let shared = ReadAloud()

    private(set) var isSpeaking = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var ownsAudioSession = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text` when `enabled`, interrupting anything it was saying. `language` is a BCP 47 code ("es-ES");
    /// nil uses the person's language.
    func speak(_ text: String, enabled: Bool, language: String? = nil) {
        guard enabled else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        activateAudioSession()
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.prefersAssistiveTechnologySettings = true
        utterance.voice = AVSpeechSynthesisVoice(language: language ?? AVSpeechSynthesisVoice.currentLanguageCode())
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        finished()
    }

    private func finished() {
        isSpeaking = false
        guard ownsAudioSession else { return }
        ownsAudioSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        AudioFocus.release(.speech)
    }

    /// Spoken audio that lowers music while it talks. Not while the recorder holds the session. Sound effects
    /// stop first (`AudioFocus`), so the session can be handed back afterwards.
    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .playAndRecord, session.category != .record else { return }
        AudioFocus.claim(.speech)
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            ownsAudioSession = true
        } catch {
            ownsAudioSession = false
            AudioFocus.release(.speech)
        }
    }

    // MARK: What to say

    /// A question the way it reads on screen: the prompt; a fill-in's sentence with "blank" for each gap; a
    /// multiple choice's options lettered.
    nonisolated static func spokenQuestion(kind: ItemKind, prompt: String, choices: [String], cloze: ClozeSpec?) -> String {
        var parts = [prompt.trimmingCharacters(in: .whitespacesAndNewlines)]
        switch kind {
        case .cloze:
            if let cloze { parts.append(blanked(cloze.text)) }
        case .mcq:
            let letters = ["A", "B", "C", "D", "E", "F"]
            for (index, choice) in choices.prefix(letters.count).enumerated() {
                parts.append("\(letters[index]): \(choice.trimmingCharacters(in: .whitespacesAndNewlines)).")
            }
        default:
            break
        }
        return parts.filter { !$0.isEmpty }.map(endsSentence).joined(separator: " ")
    }

    /// "During {{telophase}}, the …" → "During blank, the …".
    nonisolated static func blanked(_ text: String) -> String {
        text.replacingOccurrences(of: #"\{\{[^}]*\}\}"#, with: "blank", options: .regularExpression)
    }

    nonisolated private static func endsSentence(_ s: String) -> String {
        guard let last = s.last, !".?!:".contains(last) else { return s }
        return s + "."
    }
}

extension ReadAloud: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if !self.synthesizer.isSpeaking { self.finished() }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if !self.synthesizer.isSpeaking { self.finished() }
        }
    }
}
