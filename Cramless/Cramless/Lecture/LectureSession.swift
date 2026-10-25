import Foundation
import Observation

/// What a lecture session is built from, so tests and demos swap the microphone and the speech engine.
@MainActor
struct LecturePorts {
    var makeAudio: @MainActor () -> LectureAudioCapturing
    /// Which language and engine, from the person's languages (`TranscriptionGate`).
    var availability: @MainActor () async -> TranscriptionAvailability
    /// A live transcriber for an installed model. The second argument reads the session's clock (demos stamp
    /// their scripted lines with it; the real engine uses the audio's own times).
    var makeTranscriber: @MainActor (TranscriptionChoice, @escaping @MainActor () -> Double) -> LectureTranscribing
    /// Installs a model that isn't on the iPhone yet; progress 0…1 from any thread.
    var install: (TranscriptionChoice, @escaping @Sendable (Double) -> Void) async throws -> Void
    /// A scripted transcript stands in for the speech engine (DEBUG demos). The status line says so.
    var isDemo = false
    /// Seconds already on the clock when recording starts (a screenshot of a lecture mid-way).
    var startOffset: Double = 0

    static var system: LecturePorts { system(vocabulary: []) }

    /// The microphone and the on-device engine, primed with the course's words (`AppModel.lectureVocabulary`).
    static func system(vocabulary: [String]) -> LecturePorts {
        LecturePorts(
            makeAudio: { LectureRecorder() },
            availability: {
                let gate = await TranscriptionGate.resolve()
                guard case .available(let choice) = gate else { return gate }
                return .available(await TranscriptionGate.preferringVocabulary(choice, vocabulary: vocabulary))
            },
            makeTranscriber: { choice, _ in SpeechLectureTranscriber(choice: choice, vocabulary: vocabulary) },
            install: { choice, progress in try await LectureSpeechModels.install(choice, progress: progress) })
    }
}

/// One lecture being recorded: the object the record screen binds to.
///
///     let session = app.makeLectureSession(courseID: course.id)
///     await session.start()          // asks for the microphone, records at once, then picks the language
///     session.flag()                  // the person's own "this matters" tap
///     session.pause(); session.resume()
///     let sourceID = await session.stop()   // saves audio, transcript and flags into a `.lecture` source
///
/// Live transcription runs when the language's speech model is on the iPhone. When it isn't (the model is
/// still downloading, the language or the device has none, the Simulator), the recording carries on, the transcript
/// is marked pending and `statusLine` says so; a pending transcript is made from the saved audio after Stop once a
/// model is there (`AppModel.transcribeLecture`). Phrase flags ("this will be on the midterm") are found as final
/// phrases arrive.
@MainActor
@Observable
final class LectureSession {
    enum State: Equatable, Sendable {
        case idle
        case starting
        case recording
        case paused(PauseReason)
        case finishing
        case finished(sourceID: UUID)
        case failed(LectureFailure)
        case discarded
    }

    enum PauseReason: Equatable, Sendable {
        /// The person tapped Pause.
        case person
        /// A call or an alarm took the microphone. Recording resumes by itself when the system allows.
        case interruption
        /// The microphone went away (a route change that couldn't recover). Resume tries again.
        case lostInput
    }

    enum Transcription: Equatable, Sendable {
        case checking
        /// Transcribing as it records.
        case live(language: String)
        /// The model is downloading; the transcript is made after Stop.
        case downloading(language: String, progress: Double)
        /// The model is ready; the transcript is made from the recording after Stop.
        case afterStop(language: String)
        /// The model couldn't be downloaded (no connection, no room, or the Simulator). The transcript stays
        /// pending until it can be.
        case modelUnavailable(language: String)
        case unavailableOnDevice
        case unavailableLanguage(String)
        /// The speech engine stopped by itself; the transcript is made from the recording after Stop.
        case failed(language: String)
        /// DEBUG: a scripted transcript stands in for the speech engine.
        case demo
    }

    // MARK: What the screen shows

    private(set) var state: State = .idle
    private(set) var transcription: Transcription = .checking
    /// Seconds recorded, pauses excluded.
    private(set) var elapsed: TimeInterval = 0
    /// The input level now, 0…1.
    private(set) var level: Float = 0
    /// Recent levels, oldest first, for a waveform (`levelHistoryCount` values).
    private(set) var levels: [Float]
    /// The words being heard now, before they become a segment.
    private(set) var liveText = ""
    private(set) var segments: [TranscriptSegment] = []
    private(set) var flags: [ExamFlag] = []
    private(set) var sourceID: UUID?
    let courseID: UUID?
    private(set) var title: String

    static let levelHistoryCount = 34

    var isActive: Bool {
        switch state {
        case .recording, .paused: true
        default: false
        }
    }

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    /// "12:41", or "1:02:05" past an hour.
    var elapsedText: String { Self.clock(elapsed) }

    /// One honest line about the transcript, for under the timer.
    var statusLine: String {
        switch transcription {
        case .checking: "Getting ready…"
        case .live: "Transcribed on your iPhone. Works offline."
        case .downloading(let language, let progress):
            "Downloading the \(language) speech model (\(Int((progress * 100).rounded()))%). It's a one-time download, no audio is sent, and your transcript is made after you stop."
        case .afterStop(let language): "Recording. The \(language) transcript is made on your iPhone when you stop."
        case .modelUnavailable(let language):
            "Couldn't download the \(language) speech model right now. Your recording is saved and the transcript is pending."
        case .unavailableOnDevice: "This iPhone can't transcribe lectures yet. Your recording is saved and the transcript is pending."
        case .unavailableLanguage(let name):
            "Transcripts in \(name) aren't available on this iPhone yet. Your recording is saved and the transcript is pending."
        case .failed: "Live transcription stopped. Recording continues, and the transcript is made when you stop."
        case .demo: "Demo transcript: the Simulator can't transcribe speech."
        }
    }

    // MARK: Plumbing

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private let ports: LecturePorts
    @ObservationIgnored private var audio: LectureAudioCapturing?
    @ObservationIgnored private var transcriber: LectureTranscribing?
    @ObservationIgnored private var assembler = TranscriptAssembler()
    /// Carries the tap's audio to the transcriber (kept so a failed engine stops receiving it).
    @ObservationIgnored private var relay: AudioListenerRelay?
    @ObservationIgnored private var installTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var resumedAt: ContinuousClock.Instant?
    @ObservationIgnored private var lastCheckpoint: TimeInterval = 0

    /// `ports` defaults to the microphone and the on-device speech engine (`LecturePorts.system`).
    init(app: AppModel, courseID: UUID?, title: String? = nil, ports: LecturePorts? = nil) {
        let ports = ports ?? .system
        self.app = app
        self.courseID = courseID
        self.ports = ports
        self.title = title ?? app.nextLectureTitle(courseID: courseID)
        self.levels = Array(repeating: 0, count: Self.levelHistoryCount)
        self.accumulated = ports.startOffset
        self.elapsed = ports.startOffset
    }

    // MARK: Recording

    /// Asks for the microphone and starts recording at once, creates the lecture source, then picks the language
    /// and starts transcribing while it records (the relay keeps the first seconds for the transcriber).
    func start() async {
        guard state == .idle, let app else { return }
        state = .starting
        let id = UUID()
        let relay = AudioListenerRelay()
        self.relay = relay
        let audio = ports.makeAudio()
        audio.onLevel = { [weak self] level in self?.record(level: level) }
        audio.onInterruption = { [weak self] event in self?.handle(event) }
        self.audio = audio
        do {
            try await audio.start(sourceID: id, listener: relay.listener)
        } catch {
            relay.close()
            self.audio = nil
            state = .failed((error as? LectureFailure) ?? .microphoneUnavailable)
            return
        }
        LectureJobs.recording.insert(id)
        let source = app.startLecture(id: id, courseID: courseID, title: title)
        sourceID = source.id
        state = .recording
        startClock()
        await startTranscription(relay: relay)
    }

    private func startTranscription(relay: AudioListenerRelay) async {
        let availability: TranscriptionAvailability = ports.isDemo
            ? .available(TranscriptionChoice(identifier: "en-US", backend: .speech, status: .installed))
            : await ports.availability()
        guard isActive else { return relay.close() }
        switch availability {
        case .available(let choice) where choice.isInstalled:
            let transcriber = ports.makeTranscriber(choice) { [weak self] in self?.currentTime() ?? 0 }
            do {
                let listener = try await transcriber.start(timeOffset: ports.startOffset + relay.droppedSeconds) { [weak self] event in
                    self?.handle(event)
                }
                guard isActive else {
                    transcriber.cancel()
                    return relay.close()
                }
                relay.attach(listener)
                self.transcriber = transcriber
                transcription = ports.isDemo ? .demo : .live(language: choice.languageName)
            } catch {
                relay.close()
                transcription = .afterStop(language: choice.languageName)
            }
        case .available(let choice):
            relay.close()
            transcription = .downloading(language: choice.languageName, progress: 0)
            let session = WeakReference(self)
            installTask = Task { [ports] in
                do {
                    try await ports.install(choice) { fraction in
                        Task { @MainActor in
                            guard let self = session.value, case .downloading = self.transcription else { return }
                            self.transcription = .downloading(language: choice.languageName, progress: fraction)
                        }
                    }
                    session.value?.transcription = .afterStop(language: choice.languageName)
                } catch {
                    guard !Task.isCancelled else { return }
                    session.value?.transcription = .modelUnavailable(language: choice.languageName)
                }
            }
        case .unavailableOnDevice:
            relay.close()
            transcription = .unavailableOnDevice
        case .unavailableLanguage(let name):
            relay.close()
            transcription = .unavailableLanguage(name)
        }
    }

    func pause() {
        guard state == .recording else { return }
        audio?.pause()
        stopClock()
        state = .paused(.person)
        checkpoint()
    }

    func resume() {
        guard isPaused, let audio else { return }
        do {
            try audio.resume()
            state = .recording
            startClock()
        } catch {
            state = .paused(.lostInput)
        }
    }

    /// The person's own flag ("this matters") at this moment, with what was being said. Taps within two seconds
    /// of the last one are the same tap. Returns the flag for a confirmation ("Marked at 12:58").
    @discardableResult
    func flag() -> ExamFlag? {
        guard isActive else { return nil }
        tick()
        let time = elapsed
        if let last = flags.last(where: { $0.reason == .tapped }), abs(last.time - time) < 2 { return nil }
        let context = liveText.isEmpty ? (segments.last?.text ?? "") : liveText
        let flag = ExamFlag(id: ExamFlagDetector.nextID(after: flags), time: time, reason: .tapped, text: context)
        flags.append(flag)
        checkpoint()
        return flag
    }

    /// Stops, saves the audio, transcript and flags into the lecture source, and returns its id. A pending
    /// transcript is started from the recording when a model is there.
    @discardableResult
    func stop() async -> UUID? {
        guard isActive, let audio, let id = sourceID else { return nil }
        state = .finishing
        stopClock()
        // No more buffers, then let the analyzer turn what it heard into final phrases.
        audio.pause()
        await transcriber?.finish()
        transcriber = nil
        let recorded = await audio.stop()
        self.audio = nil
        relay?.close()
        relay = nil
        liveText = ""
        // The audio's own length when there is audio; the clock otherwise (a demo records none).
        let seconds = recorded.fileName != nil && recorded.duration > 0 ? recorded.duration : elapsed
        app?.finishLecture(id, audioFile: recorded.fileName, duration: seconds, segments: segments, flags: flags)
        LectureJobs.recording.remove(id)
        state = .finished(sourceID: id)
        // No transcript, or a live one that broke off: make it from the whole recording now.
        let brokeOff = if case .failed = transcription { true } else { false }
        if segments.isEmpty || brokeOff, recorded.fileName != nil, let app {
            Task { await app.transcribeLecture(id, replacing: brokeOff) }
        }
        return id
    }

    /// Stops and throws the recording away.
    func discard() {
        transcriber?.cancel()
        transcriber = nil
        installTask?.cancel()
        audio?.cancel()
        audio = nil
        relay?.close()
        relay = nil
        stopClock()
        if let id = sourceID {
            LectureJobs.recording.remove(id)
            app?.discardLecture(id)
        }
        state = .discarded
    }

    // MARK: Events

    private func handle(_ event: TranscriptionEvent) {
        switch event {
        case .volatile(let text):
            assembler.volatile(text)
            liveText = assembler.liveText
        case .final(let text, let start, let end):
            guard let segment = assembler.final(text, start: start, end: end) else { return }
            segments = assembler.segments
            liveText = ""
            flags += ExamFlagDetector.phraseFlags(in: [segment], existing: flags)
            if elapsed - lastCheckpoint > 15 { checkpoint() }
        case .failed:
            if case .live(let language) = transcription { transcription = .failed(language: language) }
            relay?.close()
            transcriber = nil
            liveText = ""
        }
    }

    private func handle(_ interruption: LectureInterruption) {
        switch interruption {
        case .began:
            guard state == .recording else { return }
            stopClock()
            state = .paused(.interruption)
            checkpoint()
        case .ended(let shouldResume):
            if state == .paused(.interruption), shouldResume { resume() }
        case .lostInput:
            guard isActive else { return }
            stopClock()
            state = .paused(.lostInput)
        }
    }

    private func record(level: Float) {
        guard state == .recording else { return }
        self.level = level
        levels.removeFirst()
        levels.append(level)
    }

    /// Writes the transcript and flags so far into the source, so a crash keeps them.
    private func checkpoint() {
        guard let id = sourceID else { return }
        lastCheckpoint = elapsed
        app?.checkpointLecture(id, duration: elapsed, segments: segments, flags: flags)
    }

    // MARK: Clock

    private func startClock() {
        resumedAt = .now
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                if self.elapsed - self.lastCheckpoint > 30 { self.checkpoint() }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopClock() {
        if let resumedAt { accumulated += resumedAt.duration(to: .now).timeInterval }
        resumedAt = nil
        clockTask?.cancel()
        clockTask = nil
        elapsed = accumulated
        level = 0
    }

    private func tick() {
        elapsed = currentTime()
    }

    /// Seconds recorded at this instant (`elapsed` is refreshed four times a second).
    func currentTime() -> TimeInterval {
        accumulated + (resumedAt?.duration(to: .now).timeInterval ?? 0)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

/// A weak reference that can travel into a sendable closure (a progress callback from another thread).
final class WeakReference<Object: AnyObject>: @unchecked Sendable {
    weak var value: Object?

    init(_ value: Object) { self.value = value }
}
