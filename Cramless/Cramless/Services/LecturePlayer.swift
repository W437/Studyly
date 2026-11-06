import AVFoundation
import Foundation
import MediaPlayer

// Hearing a lecture back. `LecturePlayer` is the one player (the notes screen and the lock screen both drive it), and what it plays
// through is a `LecturePlayback`, so its rules are tested with a fake and the harness can play the seeded lecture, which has no audio.

/// The audio underneath the player.
@MainActor
protocol LecturePlayback: AnyObject {
    /// Something the system did to the audio, or that it reached its end.
    var onEvent: ((LecturePlaybackEvent) -> Void)? { get set }
    func position() async -> Double
    func play(from seconds: Double, rate: Double)
    func seek(to seconds: Double)
    func pause()
    func setRate(_ rate: Double)
    /// Pauses and hands the audio session back.
    func close()
    /// What the lock screen shows and the time it counts from.
    func publish(_ info: LecturePlayer.NowPlaying)
}

enum LecturePlaybackEvent: Equatable, Sendable {
    case finished
    /// A call or an alarm took the audio. It comes back as `.resumeAllowed` when the system says it may carry on.
    case interrupted
    case resumeAllowed
    /// Headphones came out: pause, as every player does.
    case routeLost
    /// The audio system restarted: this playback is gone, and the next play makes a new one.
    case lost
}

/// Hears a lecture: 1×, 1.5× or 2×, back 15 seconds, and from any moment of it (with a few seconds' run-up, so a sentence isn't
/// heard from its middle). Keeps playing with the screen off, with Now Playing on the lock screen and its remote commands. Refuses
/// while a lecture is recording. Leaving the notes pauses it and gives the audio session back, and coming back finds the same place.
@MainActor
@Observable
final class LecturePlayer {
    static let shared = LecturePlayer()

    struct Track: Equatable {
        var sourceID: UUID
        var title: String
        /// The audio, relative to `FileStore.root`. Nil only for the harness's demo.
        var fileName: String?
        var duration: Double
        var segments: [TranscriptSegment] = []
    }

    enum Speed: Double, CaseIterable, Sendable {
        case normal = 1, faster = 1.5, fastest = 2

        var next: Speed {
            let all = Self.allCases
            return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
        }

        var label: String {
            switch self {
            case .normal: "1×"
            case .faster: "1.5×"
            case .fastest: "2×"
            }
        }
    }

    struct NowPlaying: Equatable {
        var title: String
        var duration: Double
        var position: Double
        /// 0 while paused, which is what stops the lock screen's clock.
        var rate: Double
    }

    /// A chip plays from this much before its moment.
    static let runUp: Double = 5
    /// What "Back 15 seconds" goes back.
    static let skipBack: Double = 15

    /// Where a moment plays from.
    nonisolated static func startPoint(for moment: Double) -> Double { max(0, moment - runUp) }

    /// The transcript part being said at `seconds`: the one around it, else the last one before it.
    nonisolated static func segmentID(at seconds: Double, in segments: [TranscriptSegment]) -> String? {
        (segments.first { seconds >= $0.start && seconds <= $0.end } ?? segments.last { $0.start <= seconds })?.id
    }

    private(set) var track: Track?
    private(set) var isPlaying = false
    /// Seconds into the lecture, updated about four times a second while playing.
    private(set) var position: Double = 0
    private(set) var speed: Speed = .normal
    /// The player was pointed at a moment and is waiting to be started ("Play from 12:36").
    private(set) var isCued = false
    /// Asked to play while a lecture is recording, and refused.
    private(set) var refusedForRecording = false
    /// What's being said now, for the transcript to follow. Changes only when the part changes, so the notes don't redraw on every tick.
    private(set) var currentSegmentID: String?

    @ObservationIgnored private var playback: (any LecturePlayback)?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var ticking: Task<Void, Never>?
    @ObservationIgnored private var commandsReady = false
    /// Interrupted while playing, so a call's end picks it up again.
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private let makePlayback: @MainActor (Track) async -> (any LecturePlayback)?
    @ObservationIgnored private let usesRemoteCommands: Bool

    init(makePlayback: (@MainActor (Track) async -> (any LecturePlayback)?)? = nil) {
        self.makePlayback = makePlayback ?? Self.systemPlayback
        usesRemoteCommands = makePlayback == nil
    }

    private static func systemPlayback(_ track: Track) async -> (any LecturePlayback)? {
        #if DEBUG
        if track.fileName == nil { return DemoLecturePlayback(duration: track.duration) }
        #endif
        guard let fileName = track.fileName else { return nil }
        return await SystemLecturePlayback.make(url: FileStore.url(for: fileName))
    }

    // MARK: The notes screen

    /// The notes screen shows this lecture. The same lecture keeps its place; another one starts at the top.
    func open(_ new: Track) {
        guard track?.sourceID != new.sourceID else {
            track = new
            refusedForRecording = false
            updateSegment()
            return
        }
        close()
        track = new
        position = 0
        isCued = false
        refusedForRecording = false
        updateSegment()
    }

    /// The notes screen went away: pause, and hand the audio back. The place is kept for coming back.
    func leave() {
        guard track != nil else { return }
        close()
    }

    /// Points at a moment and waits (a question or a citation opened the notes: the person may be in a quiet place).
    func cue(at moment: Double) {
        guard track != nil else { return }
        let start = clamped(Self.startPoint(for: moment))
        setPosition(start)
        isCued = true
        if isPlaying { pause() }
        playback?.seek(to: start)
    }

    /// A time chip: hear this moment now.
    func play(fromMoment moment: Double) {
        play(at: clamped(Self.startPoint(for: moment)))
    }

    func togglePlay() {
        if isPlaying { pause() } else { resume() }
    }

    /// Starts from where it is, or from the top if it had reached the end.
    func resume() {
        guard let track else { return }
        play(at: position >= track.duration - 0.25 ? 0 : position)
    }

    func pause() {
        guard isPlaying else { return }
        ticking?.cancel()
        isPlaying = false
        resumeAfterInterruption = false
        playback?.pause()
        publish()
    }

    func back15() {
        seek(to: position - Self.skipBack)
    }

    /// Moves without changing whether it's playing.
    func seek(to seconds: Double) {
        guard track != nil else { return }
        let target = clamped(seconds)
        setPosition(target)
        isCued = false
        playback?.seek(to: target)
        publish()
    }

    func cycleSpeed() {
        speed = speed.next
        if isPlaying { playback?.setRate(speed.rawValue) }
        publish()
    }

    /// The recorder or read-aloud has claimed the audio (`AudioFocus`): the lecture stops talking over it.
    func yieldAudio() {
        guard playback != nil else { return }
        close()
    }

    /// Reads the audio's own position: one tick of the clock, about four times a second while playing.
    func refreshPosition() async {
        guard let playback else { return }
        let now = await playback.position()
        guard isPlaying else { return }
        setPosition(now)
    }

    // MARK: Playing

    private func play(at start: Double) {
        guard track != nil else { return }
        guard !AudioFocus.owners.contains(.microphone) else {
            refusedForRecording = true
            return
        }
        refusedForRecording = false
        isCued = false
        setPosition(start)
        isPlaying = true
        resumeAfterInterruption = false
        ReadAloud.shared.stop()
        AudioFocus.claim(.playback)
        readyCommands()
        withPlayback { [weak self] playback in
            guard let self, self.isPlaying else { return }
            playback.play(from: self.position, rate: self.speed.rawValue)
            self.publish()
            self.startTicking()
        }
    }

    /// Runs `body` with the playback, making it first if there is none yet (opening a file happens off the main thread).
    private func withPlayback(_ body: @escaping (any LecturePlayback) -> Void) {
        if let playback {
            body(playback)
            return
        }
        guard let track else { return }
        loading?.cancel()
        loading = Task { [weak self, makePlayback] in
            guard let made = await makePlayback(track) else {
                self?.isPlaying = false
                AudioFocus.release(.playback)
                return
            }
            guard let self, !Task.isCancelled, self.track?.sourceID == track.sourceID else {
                made.close()
                return
            }
            made.onEvent = { [weak self] event in self?.handle(event) }
            self.playback = made
            body(made)
        }
    }

    private func close() {
        loading?.cancel()
        loading = nil
        ticking?.cancel()
        ticking = nil
        isPlaying = false
        resumeAfterInterruption = false
        playback?.close()
        playback = nil
        AudioFocus.release(.playback)
        setCommandsEnabled(false)
    }

    private func handle(_ event: LecturePlaybackEvent) {
        switch event {
        case .finished:
            ticking?.cancel()
            isPlaying = false
            if let track { setPosition(track.duration) }
            publish()
        case .interrupted:
            let wasPlaying = isPlaying
            ticking?.cancel()
            isPlaying = false
            resumeAfterInterruption = wasPlaying
            publish()
        case .resumeAllowed:
            guard resumeAfterInterruption else { return }
            resumeAfterInterruption = false
            play(at: position)
        case .routeLost:
            pause()
        case .lost:
            ticking?.cancel()
            isPlaying = false
            resumeAfterInterruption = false
            playback = nil
            AudioFocus.release(.playback)
        }
    }

    private func startTicking() {
        ticking?.cancel()
        ticking = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await self?.refreshPosition()
            }
        }
    }

    private func setPosition(_ seconds: Double) {
        guard abs(seconds - position) > 0.01 else { return }
        position = seconds
        updateSegment()
    }

    private func updateSegment() {
        let id = Self.segmentID(at: position, in: track?.segments ?? [])
        if id != currentSegmentID { currentSegmentID = id }
    }

    private func clamped(_ seconds: Double) -> Double {
        max(0, min(seconds, track?.duration ?? seconds))
    }

    private func publish() {
        guard let track else { return }
        playback?.publish(NowPlaying(title: track.title, duration: track.duration, position: position,
                                     rate: isPlaying ? speed.rawValue : 0))
    }

    // MARK: Remote commands

    private func readyCommands() {
        guard usesRemoteCommands else { return }
        if !commandsReady {
            commandsReady = true
            let center = MPRemoteCommandCenter.shared()
            center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipBack)]
            center.playCommand.addTarget { [weak self] _ in self?.runCommand { $0.resume() } ?? .commandFailed }
            center.pauseCommand.addTarget { [weak self] _ in self?.runCommand { $0.pause() } ?? .commandFailed }
            center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.runCommand { $0.togglePlay() } ?? .commandFailed }
            center.skipBackwardCommand.addTarget { [weak self] _ in self?.runCommand { $0.back15() } ?? .commandFailed }
            center.changePlaybackPositionCommand.addTarget { [weak self] event in
                guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                let seconds = event.positionTime
                return self?.runCommand { $0.seek(to: seconds) } ?? .commandFailed
            }
        }
        setCommandsEnabled(true)
    }

    nonisolated private func runCommand(_ action: @escaping @MainActor (LecturePlayer) -> Void) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor [weak self] in
            if let self { action(self) }
        }
        return .success
    }

    private func setCommandsEnabled(_ enabled: Bool) {
        guard usesRemoteCommands, commandsReady else { return }
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand, center.skipBackwardCommand,
                        center.changePlaybackPositionCommand] {
            command.isEnabled = enabled
        }
    }
}

// MARK: - The real one

/// `AVAudioPlayer` on a serial queue of its own: the audio session, a file's first read, a start and the Now Playing update each talk to a
/// system server, so none of them happens on the main thread.
@MainActor
final class SystemLecturePlayback: NSObject, LecturePlayback {
    var onEvent: ((LecturePlaybackEvent) -> Void)?

    private let audio: AudioBox
    private var observers: [NSObjectProtocol] = []

    /// The player and the session, only ever touched on `queue`.
    private final class AudioBox: NSObject, @unchecked Sendable, AVAudioPlayerDelegate {
        let queue = DispatchQueue(label: "capling.lecture-playback", qos: .userInitiated)
        let player: AVAudioPlayer
        var onFinish: (@Sendable () -> Void)?

        init(player: AVAudioPlayer) {
            self.player = player
            super.init()
            player.delegate = self
            player.enableRate = true
            player.prepareToPlay()
        }

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish?() }
    }

    /// Opens the file off the main thread. Nil when it can't be read.
    static func make(url: URL) async -> SystemLecturePlayback? {
        let box = await Task.detached(priority: .userInitiated) { () -> AudioBox? in
            guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
            return AudioBox(player: player)
        }.value
        return box.map(SystemLecturePlayback.init(audio:))
    }

    private init(audio: AudioBox) {
        self.audio = audio
        super.init()
        audio.onFinish = { [weak self] in
            Task { @MainActor in self?.onEvent?(.finished) }
        }
        observe()
    }

    func position() async -> Double {
        await withCheckedContinuation { continuation in
            let audio = self.audio
            audio.queue.async { continuation.resume(returning: audio.player.currentTime) }
        }
    }

    func play(from seconds: Double, rate: Double) {
        let audio = self.audio
        audio.queue.async {
            let session = AVAudioSession.sharedInstance()
            do {
                // Spoken audio that stops other apps' music while it talks; plays with the Silent switch on, as any lecture would.
                try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
                try session.setActive(true)
            } catch {
                AppConfig.log.error("lecture playback session: \(error.localizedDescription, privacy: .public)")
            }
            audio.player.currentTime = seconds
            audio.player.rate = Float(rate)
            audio.player.play()
        }
    }

    func seek(to seconds: Double) {
        let audio = self.audio
        audio.queue.async { audio.player.currentTime = seconds }
    }

    func pause() {
        let audio = self.audio
        audio.queue.async { audio.player.pause() }
    }

    func setRate(_ rate: Double) {
        let audio = self.audio
        audio.queue.async { audio.player.rate = Float(rate) }
    }

    func close() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        let audio = self.audio
        audio.onFinish = nil
        audio.queue.async {
            audio.player.stop()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func publish(_ info: LecturePlayer.NowPlaying) {
        audio.queue.async {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPMediaItemPropertyTitle: info.title,
                MPMediaItemPropertyPlaybackDuration: info.duration,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: info.position,
                MPNowPlayingInfoPropertyPlaybackRate: info.rate,
            ]
        }
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = AVAudioSession.InterruptionOptions(rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated {
                switch type {
                case .began: self?.onEvent?(.interrupted)
                case .ended where options.contains(.shouldResume): self?.onEvent?(.resumeAllowed)
                default: break
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            guard reason == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { self?.onEvent?(.routeLost) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.lost) }
        })
    }
}
