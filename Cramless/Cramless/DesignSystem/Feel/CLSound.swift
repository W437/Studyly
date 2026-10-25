import AVFoundation
import UIKit

/// Plays `CLSynth` sounds through AVAudioEngine in the ambient category: they mix with other apps' audio and the
/// Silent switch silences them. A palette's sounds are rendered once (at `prepare()`, or on first use); the
/// engine starts on demand and stops in the background, or when speech or the microphone takes the audio session
/// (`AudioFocus`). Four players take turns, so a flourish can ring over the note that started it.
///
/// The engine and its players are built the first time a sound is prepared or played, never at launch: with sounds off
/// (or before the first answer) the app doesn't touch the audio system at all, so a stalled audio service can't hold up
/// the first screen.
@MainActor
final class CLSound {
    static let shared = CLSound()

    /// Settings ▸ Accessibility ▸ Sounds (AppModel sets it; the harness keeps it off unless `CRAMLESS_SOUNDS=1`).
    var isEnabled = true

    /// The person's quiet hours, in minutes after midnight: sounds play 6 dB softer inside them.
    var quietHours: (start: Int, end: Int)?

    var palette: CLSynth.Palette = .standard {
        didSet { if palette.id != oldValue.id { buffers = [:] } }
    }

    /// The engine and its four players, built on first use (see above).
    private var graph: (engine: AVAudioEngine, players: [AVAudioPlayerNode])?
    private var nextPlayer = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: CLSynth.sampleRate, channels: 1)!
    private var observers: [NSObjectProtocol] = []

    /// The app uses `shared`; a test makes its own to check that nothing touches audio until a sound is wanted.
    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                                            queue: .main) { _ in
            MainActor.assumeIsolated { CLSound.shared.suspend() }
        })
    }

    /// The audio engine has been built, because a sound was prepared or played.
    var hasAudioGraph: Bool { graph != nil }

    /// How many cues' sounds are rendered and waiting (tests read it).
    var renderedCount: Int { buffers.count }

    private func audioGraph() -> (engine: AVAudioEngine, players: [AVAudioPlayerNode]) {
        if let graph { return graph }
        let engine = AVAudioEngine()
        var players: [AVAudioPlayerNode] = []
        for _ in 0..<4 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        graph = (engine, players)
        return (engine, players)
    }

    /// Renders the palette's sounds and starts the engine, so the first answer of a session plays without a gap.
    func prepare() {
        guard isEnabled, AudioFocus.allowsEffects else { return }
        for cue in CLCue.all { _ = buffer(for: cue) }
        start()
    }

    /// `force` plays it with sounds switched off (Settings' "Hear an example"); the Silent switch and audio focus
    /// still apply.
    func play(_ cue: CLCue, force: Bool = false) {
        guard isEnabled || force, AudioFocus.allowsEffects, let buffer = buffer(for: cue), start() else { return }
        let players = audioGraph().players
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = isQuiet(at: Date()) ? 0.5 : 1
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    /// Stops the engine (the app went to the background, or speech or the microphone took the session).
    func suspend() {
        guard let graph, graph.engine.isRunning else { return }
        for player in graph.players { player.stop() }
        graph.engine.stop()
    }

    @discardableResult
    private func start() -> Bool {
        let engine = audioGraph().engine
        if engine.isRunning { return true }
        do {
            let session = AVAudioSession.sharedInstance()
            if session.category != .ambient { try session.setCategory(.ambient, mode: .default) }
            try session.setActive(true)
            engine.prepare()
            try engine.start()
            return true
        } catch {
            AppConfig.log.error("sound engine didn't start: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Renders these cues' sounds off the main thread and starts the engine, ahead of the moment they are wanted. Left to the first
    /// `play`, a launch's first sound holds the main thread while it synthesises (about 160 ms in a debug build for a short note, 85 for a
    /// flourish) and the engine starts, and whatever is animating then stutters.
    func prewarm(_ cues: [CLCue]) async {
        guard isEnabled, AudioFocus.allowsEffects else { return }
        let palette = self.palette
        let wanted = cues.filter { buffers[$0.key] == nil }
        let rendered = await Task.detached(priority: .userInitiated) { wanted.map { ($0.key, CLSynth(palette: palette).render($0)) } }.value
        guard palette.id == self.palette.id else { return }
        for (key, samples) in rendered where buffers[key] == nil {
            buffers[key] = makeBuffer(samples)
        }
        start()
    }

    private func buffer(for cue: CLCue) -> AVAudioPCMBuffer? {
        if let cached = buffers[cue.key] { return cached }
        let buffer = makeBuffer(CLSynth(palette: palette).render(cue))
        buffers[cue.key] = buffer
        return buffer
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    private func isQuiet(at date: Date) -> Bool {
        guard let quietHours else { return false }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Self.isQuiet(minute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0), start: quietHours.start,
                            end: quietHours.end)
    }

    /// Inside quiet hours that may wrap midnight (22:00–07:00).
    nonisolated static func isQuiet(minute: Int, start: Int, end: Int) -> Bool {
        guard start != end else { return false }
        return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }
}
