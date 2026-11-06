import AVFoundation
import Foundation

/// Reads questions aloud (Settings ▸ Accessibility ▸ Read aloud). Uses the person's own Spoken Content settings
/// (voice, rate) when they have them, ducks other audio while it speaks, and leaves the audio session alone while a
/// lecture is recording. Callers go through `AppModel.readAloud(_:force:)`, which checks the setting; an explicit
/// speaker button passes `force`. Study out loud waits for each line to end (`speak(onFinish:)`, `ReadAloudSpeaker`).
@MainActor
@Observable
final class ReadAloud: NSObject {
    static let shared = ReadAloud()

    private(set) var isSpeaking = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var ownsAudioSession = false
    /// What waits for each utterance to end, or to be cut off.
    @ObservationIgnored private var onFinish: [ObjectIdentifier: () -> Void] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text` when `enabled`, interrupting anything it was saying. `language` is a BCP 47 code ("es-ES");
    /// nil uses the person's language. `onFinish` runs when this line has ended or been cut off, and at once when there is nothing to say.
    func speak(_ text: String, enabled: Bool, language: String? = nil, onFinish: (() -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !trimmed.isEmpty else {
            onFinish?()
            return
        }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        activateAudioSession()
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.prefersAssistiveTechnologySettings = true
        utterance.voice = AVSpeechSynthesisVoice(language: language ?? AVSpeechSynthesisVoice.currentLanguageCode())
        isSpeaking = true
        if let onFinish { self.onFinish[ObjectIdentifier(utterance)] = onFinish }
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

    /// An utterance has ended, or was cut off.
    private func utteranceEnded(_ id: ObjectIdentifier) {
        onFinish.removeValue(forKey: id)?()
        if !synthesizer.isSpeaking { finished() }
    }

    /// Spoken audio that lowers music while it talks. Not while the microphone holds the session: a lecture recording, or Study out loud, which
    /// set it up to speak through. Sound effects stop first (`AudioFocus`), so the session can be handed back afterwards.
    private func activateAudioSession() {
        guard !AudioFocus.owners.contains(.microphone) else { return }
        let session = AVAudioSession.sharedInstance()
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
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }
}

/// Cap's voice, as Study out loud sees it: `ReadAloudSpeaker` on a device, a silent stand-in in DEBUG demos and tests.
@MainActor
protocol SpokenSpeaking: AnyObject {
    /// Says `text` and returns when it has ended or been stopped. `language`: BCP 47, nil for the person's own.
    func say(_ text: String, language: String?) async
    func stop()
}

/// Says each line through `ReadAloud`, with the person's own Spoken Content voice and rate.
@MainActor
final class ReadAloudSpeaker: SpokenSpeaking {
    func say(_ text: String, language: String?) async {
        // A line that never reports its end (a route change mid-word) can't hold the session up for good.
        let limit = Double(text.split(whereSeparator: \.isWhitespace).count) * 1.2 + 8
        let watchdog = Task { @MainActor in
            try? await Task.sleep(for: .seconds(limit))
            if !Task.isCancelled { ReadAloud.shared.stop() }
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                ReadAloud.shared.speak(text, enabled: true, language: language) { continuation.resume() }
            }
        } onCancel: {
            Task { @MainActor in ReadAloud.shared.stop() }
        }
        watchdog.cancel()
    }

    func stop() { ReadAloud.shared.stop() }
}
