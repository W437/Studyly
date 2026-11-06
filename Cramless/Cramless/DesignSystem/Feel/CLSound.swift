import AVFoundation
import os
import UIKit

/// Plays `CLSynth` sounds through AVAudioEngine in the ambient category: they mix with other apps' audio and the
/// Silent switch silences them. A palette's sounds are rendered once (at `prepare()`, or on first use); the
/// engine starts on demand and stops in the background, or when speech or the microphone takes the audio session
/// (`AudioFocus`). Four players take turns, so a flourish can ring over the note that started it.
///
/// This class is the app's side: the switches, the rendered sounds. Everything that talks to the audio system is `CLSoundOutput`, on its own
/// queue, built the first time a sound is prepared or played, never at launch: with sounds off (or before the first answer) the app doesn't
/// touch the audio system at all. A sound is a nicety: a stalled audio service means no sound, and it can't hold up a screen.
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

    private let format = AVAudioFormat(standardFormatWithSampleRate: CLSynth.sampleRate, channels: 1)!
    private lazy var output = CLSoundOutput(format: format)
    private var buffers: [String: AVAudioPCMBuffer] = [:]
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
    var hasAudioGraph: Bool { output.hasGraph }

    /// How many cues' sounds are rendered and waiting (tests read it).
    var renderedCount: Int { buffers.count }

    /// Renders the palette's sounds and starts the engine, so the first answer of a session plays without a gap.
    func prepare() {
        guard isEnabled, AudioFocus.allowsEffects else { return }
        for cue in CLCue.all { _ = buffer(for: cue) }
        output.warmUp()
    }

    /// `force` plays it with sounds switched off (Settings' "Hear an example"); the Silent switch and audio focus
    /// still apply.
    func play(_ cue: CLCue, force: Bool = false) {
        guard isEnabled || force, AudioFocus.allowsEffects, let buffer = buffer(for: cue) else { return }
        output.play(buffer, volume: isQuiet(at: Date()) ? 0.5 : 1)
    }

    /// Stops the engine (the app went to the background, or speech or the microphone took the session). When it returns the
    /// engine has stopped, so the caller may take the audio session, unless the audio system was still answering its first call.
    func suspend() {
        output.suspend()
    }

    /// Renders these cues' sounds off the main thread and starts the engine, ahead of the moment they are wanted. Left to the first
    /// `play`, a launch's first sound holds the main thread while it synthesises (about 160 ms in a debug build for a short note, 85 for a
    /// flourish), and whatever is animating then stutters.
    func prewarm(_ cues: [CLCue]) async {
        guard isEnabled, AudioFocus.allowsEffects else { return }
        let palette = self.palette
        let wanted = cues.filter { buffers[$0.key] == nil }
        let rendered = await Task.detached(priority: .userInitiated) { wanted.map { ($0.key, CLSynth(palette: palette).render($0)) } }.value
        guard palette.id == self.palette.id else { return }
        for (key, samples) in rendered where buffers[key] == nil {
            buffers[key] = makeBuffer(samples)
        }
        guard isEnabled, AudioFocus.allowsEffects else { return }
        output.warmUp()
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

/// The app's one door to the audio system: the engine, its players and the audio session, on one serial queue and never on the main thread.
///
/// The system can stall here: on a busy Mac the engine's first call (`AURemoteIO::Initialize`, reached from `mainMixerNode`) waited about 20
/// seconds on the main thread and then aborted the process from inside AudioToolbox (`_ReportRPCTimeout`), and nothing in the app can catch
/// that. So:
/// - a stall holds this queue, not a screen, and the cues asked for meanwhile are dropped rather than played late;
/// - the session is activated before the engine is touched. It answers a stalled service with an error or a long wait, where the engine
///   aborts: either one means no sound until the app next comes back (`suspend()` clears it);
/// - the simulator builds nothing unless a launch asks for sound (`CRAMLESS_SOUNDS=1`). Its recordings are silent (films are scored from the
///   cue log), and its audio path, through the Mac's, is where this abort has actually happened.
final class CLSoundOutput: @unchecked Sendable {
    /// A session this slow to answer means the audio service is in trouble: leave the engine alone.
    static let slowSession: Duration = .seconds(1.5)
    /// A cue this late is no longer the sound of what just happened.
    static let staleCue: Duration = .milliseconds(500)

    /// Whether this process may build an engine at all.
    static func mayBuild(simulator: Bool, askedForSound: Bool) -> Bool { !simulator || askedForSound }

    private static let isAllowed: Bool = {
        #if targetEnvironment(simulator)
        mayBuild(simulator: true, askedForSound: ProcessInfo.processInfo.environment["CRAMLESS_SOUNDS"] == "1")
        #else
        mayBuild(simulator: false, askedForSound: false)
        #endif
    }()

    private struct Flags {
        var hasGraph = false
        /// A call into the audio system is in flight: the queue may be stuck in it.
        var isStarting = false
    }

    private let queue = DispatchQueue(label: "capling.sound", qos: .userInteractive)
    private let format: AVAudioFormat
    /// Read from anywhere.
    private let flags = OSAllocatedUnfairLock(initialState: Flags())

    // The queue's alone.
    private var engine: AVAudioEngine?
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var gaveUp = false

    init(format: AVAudioFormat) {
        self.format = format
    }

    var hasGraph: Bool { flags.withLock(\.hasGraph) }

    /// Starts the engine ahead of the first sound.
    func warmUp() {
        guard Self.isAllowed else { return }
        queue.async { [self] in _ = start() }
    }

    func play(_ buffer: AVAudioPCMBuffer, volume: Float) {
        guard Self.isAllowed else { return }
        let asked = ContinuousClock.now
        queue.async { [self] in
            guard start(), ContinuousClock.now - asked < Self.staleCue, !players.isEmpty else { return }
            let player = players[nextPlayer]
            nextPlayer = (nextPlayer + 1) % players.count
            player.volume = volume
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !player.isPlaying { player.play() }
        }
    }

    /// Stops the engine and clears a give-up, so the next sound tries again. It waits for the queue, so the caller can take the session next,
    /// unless the queue may be stuck in the audio system: a screen never waits on that.
    func suspend() {
        guard Self.isAllowed else { return }
        if flags.withLock(\.isStarting) {
            queue.async { [self] in stop() }
        } else {
            queue.sync { stop() }
        }
    }

    private func stop() {
        gaveUp = false
        guard let engine, engine.isRunning else { return }
        for player in players { player.stop() }
        engine.stop()
    }

    /// On the queue. Whether the engine is running.
    private func start() -> Bool {
        if gaveUp { return false }
        if let engine, engine.isRunning { return true }
        flags.withLock { $0.isStarting = true }
        defer { flags.withLock { $0.isStarting = false } }
        let began = ContinuousClock.now
        do {
            let session = AVAudioSession.sharedInstance()
            if session.category != .ambient { try session.setCategory(.ambient, mode: .default) }
            try session.setActive(true)
        } catch {
            gaveUp = true
            AppConfig.log.error("no sounds for now: the audio session didn't start: \(error.localizedDescription, privacy: .public)")
            return false
        }
        guard ContinuousClock.now - began < Self.slowSession else {
            gaveUp = true
            AppConfig.log.error("no sounds for now: the audio session took too long to answer")
            return false
        }
        let engine = engine ?? makeGraph()
        do {
            engine.prepare()
            try engine.start()
            return true
        } catch {
            AppConfig.log.error("sound engine didn't start: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func makeGraph() -> AVAudioEngine {
        let engine = AVAudioEngine()
        for _ in 0..<4 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        self.engine = engine
        flags.withLock { $0.hasGraph = true }
        return engine
    }
}
