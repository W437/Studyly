import CoreHaptics
import UIKit

// The only file that touches UIKit's feedback generators and Core Haptics. Haptics belong to things the person
// does (a tap, a page turn, an answer landing), never to an animation playing on its own schedule: demo scenes
// fire none. `isEnabled` is the one gate (Settings ▸ Accessibility ▸ Haptics), set by AppModel from the settings.
// A cue's haptic (`CLHapticPatterns`) is played by `CLFeel` together with its sound.

@MainActor
enum CLHaptics {
    static var isEnabled = true

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    /// A button press that moves somewhere (navigation, a primary action).
    static func tap() { guard isEnabled else { return }; light.impactOccurred() }
    /// A firmer commit: submitting an answer, starting a session.
    static func commit() { guard isEnabled else { return }; medium.impactOccurred() }
    /// A soft landing: a card settling, a chip popping in after the person's own action.
    static func land() { guard isEnabled else { return }; soft.impactOccurred(intensity: 0.7) }
    /// A crisp tick: a key idea highlighted while grading the person's answer.
    static func tick() { guard isEnabled else { return }; rigid.impactOccurred(intensity: 0.55) }
    /// A tap on Cap: a soft press as he squashes and a lighter bounce as he springs back. `strength` (0 to 1) follows how hard
    /// he squashed, so no two feel quite the same.
    static func poke(strength: Double) {
        guard isEnabled else { return }
        let level = min(max(strength, 0), 1)
        soft.impactOccurred(intensity: CGFloat(0.45 + 0.5 * level))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard isEnabled else { return }
            light.impactOccurred(intensity: CGFloat(0.25 + 0.3 * level))
        }
    }
    /// Selection changes: page turns, segmented controls, option picks.
    static func select() { guard isEnabled else { return }; selection.selectionChanged() }
    static func success() { guard isEnabled else { return }; notification.notificationOccurred(.success) }
    static func warning() { guard isEnabled else { return }; notification.notificationOccurred(.warning) }
    static func error() { guard isEnabled else { return }; notification.notificationOccurred(.error) }

    /// Warms the generators before a burst (a session starting).
    static func prepare() {
        guard isEnabled else { return }
        light.prepare(); rigid.prepare(); selection.prepare(); notification.prepare()
    }

    /// One impact for a cue on an iPhone without Core Haptics: crisp cues tick, dull ones land softly.
    fileprivate static func fallback(sharpness: Double, intensity: Double) {
        guard isEnabled else { return }
        let generator = sharpness >= 0.6 ? rigid : sharpness >= 0.3 ? light : soft
        generator.impactOccurred(intensity: CGFloat(max(0.2, min(1, intensity))))
    }
}

/// A cue's haptic: one tap under each of its notes, at the note's time, so the touch and the sound land together
/// (a run's taps grow stronger and crisper as its notes climb), plus a soft swell under a finish. Played by
/// `CLFeel`; built from the same `CLSynth.Score` as the sound.
@MainActor
enum CLHapticPatterns {
    private static var engine: CHHapticEngine?
    private static var supported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    static func prepare() {
        _ = startedEngine()
    }

    static func play(_ score: CLSynth.Score) {
        guard let engine = startedEngine() else {
            if let first = score.notes.first {
                CLHaptics.fallback(sharpness: score.sharpness, intensity: first.velocity * hapticLevel(score))
            }
            return
        }
        do {
            let pattern = try CHHapticPattern(events: events(for: score), parameters: [])
            // The engine shuts itself down when idle; starting a running one returns at once.
            try engine.start()
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            AppConfig.log.error("haptic pattern failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The events for a score (tests read them).
    static func events(for score: CLSynth.Score) -> [CHHapticEvent] {
        let level = hapticLevel(score)
        var events = score.notes.map { note in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(min(1, note.velocity * level))),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(score.sharpness)),
            ], relativeTime: note.time)
        }
        if score.swell > 0 {
            events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15),
                CHHapticEventParameter(parameterID: .attackTime, value: Float(score.swell * 0.6)),
                CHHapticEventParameter(parameterID: .releaseTime, value: Float(score.swell * 0.4)),
            ], relativeTime: 0, duration: score.swell))
        }
        return events
    }

    /// Louder cues are felt more firmly.
    private static func hapticLevel(_ score: CLSynth.Score) -> Double { 0.45 + 0.55 * score.gain }

    private static func startedEngine() -> CHHapticEngine? {
        guard supported else { return nil }
        if let engine { return engine }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = {
                Task { @MainActor in try? CLHapticPatterns.engine?.start() }
            }
            try engine.start()
            self.engine = engine
            return engine
        } catch {
            AppConfig.log.error("haptic engine didn't start: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
