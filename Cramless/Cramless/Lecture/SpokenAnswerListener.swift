import AVFoundation
import Foundation

// Listening to one spoken answer at a time, on this iPhone. No audio is kept: the tap hands buffers to the speech analyzer while a turn is open
// and drops them the rest of the time, nothing is written to a file, and when the turn ends only its words are left.

enum SpokenListenerFailure: Error, Equatable, Sendable {
    /// Microphone access is off.
    case microphoneDenied
    /// The microphone or the audio session couldn't start.
    case microphoneUnavailable
    /// The speech model for this language can't be had (nil: this iPhone has none at all).
    case noSpeechModel(language: String?)
}

/// One turn of listening.
struct SpokenTurn: Sendable {
    var endpoint: SpeechEndpoint.Config = .answer
    /// Words this turn is likely to hold: the options read out, the commands. They prime the recogniser, ahead of the course's own words.
    var terms: [String] = []
    /// The question being answered (a scripted listener answers it; the real one has no use for it).
    var question: OutLoudQuestion?
    /// How a flashcard or a self-marked answer went, not an answer.
    var isReply = false
}

/// What a turn came to.
struct SpokenHearing: Sendable, Equatable {
    enum Ending: Sendable, Equatable {
        case silence, cap, noSpeech
        /// The person (a button) or something else ended it.
        case stopped
        /// The speech engine failed.
        case failed
    }

    var text: String
    var ending: Ending
    /// From the start of the turn to the end of what was said: how long the answer took.
    var seconds: Double = 0
}

/// The microphone and the speech engine, as Study out loud and Teach Cap see them: `SpokenAnswerListener` on a device, a scripted stand-in in
/// DEBUG demos and tests.
@MainActor
protocol SpokenListening: AnyObject {
    /// The input level, 0…1, about ten times a second during a turn.
    var onLevel: ((Float) -> Void)? { get set }
    /// Something the system did to the microphone.
    var onInterruption: ((LectureInterruption) -> Void)? { get set }
    /// Asks for the microphone, makes sure the language's speech model is here (`progress`, 0…1, while it downloads) and opens the
    /// audio session. The engine then keeps running between turns, so a locked phone keeps the session.
    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws
    /// Listens until the turn ends. `onWords` gets everything said so far, as it is heard.
    func listen(_ turn: SpokenTurn, onWords: @escaping @MainActor (String) -> Void) async -> SpokenHearing
    /// Ends the turn now, with what was heard.
    func stopListening()
    /// The microphone goes off (a person's pause) and comes back.
    func suspend()
    func resume() throws
    /// Everything stops, and the audio session goes back.
    func close()
}

/// Where the tap's buffers go: to the open turn, or nowhere. Used from the tap's thread.
final class SpokenTapGate: @unchecked Sendable {
    private let lock = NSLock()
    private var listener: AudioListener?

    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return listener != nil
    }

    func open(_ listener: @escaping AudioListener) {
        lock.lock()
        defer { lock.unlock() }
        self.listener = listener
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        listener = nil
    }

    /// Hands the buffer on when a turn is open. Returns whether one is.
    @discardableResult
    func receive(_ buffer: AVAudioPCMBuffer) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let listener else { return false }
        listener(buffer)
        return true
    }
}

/// The real one: `AVAudioEngine` with one tap, on a `.playAndRecord` session for speech (AirPods and other headsets are both ears and mouth here,
/// unlike a lecture, where the microphone has to hear the room), and `SpeechLectureTranscriber` for each turn.
///
/// Speak, then listen: Cap's voice comes out while the tap's buffers are being dropped, so he isn't heard answering himself. A call or an
/// alarm stops the engine and says so (`onInterruption`); a route change restarts the tap on the new input; a media-services reset rebuilds
/// the engine. Needs a device.
@MainActor
final class SpokenAnswerListener: SpokenListening {
    var onLevel: ((Float) -> Void)?
    var onInterruption: ((LectureInterruption) -> Void)?

    /// How long the words from before the analyzer is ready are held for it.
    private static let backlogSeconds = 10.0
    /// How long the last words have to come out once a turn is over.
    private static let flushSeconds = 3.0

    private let vocabulary: [String]
    /// The course's language, when it isn't the person's own: tried first.
    private let language: String?
    private let gate = SpokenTapGate()
    private var engine = AVAudioEngine()
    private var choice: TranscriptionChoice?
    private var observers: [NSObjectProtocol] = []
    private var tapInstalled = false
    private var isRunning = false
    private var turn: OpenTurn?

    /// The turn in progress.
    @MainActor
    private final class OpenTurn {
        var endpoint: SpeechEndpoint
        var words = HeardWords()
        let openedAt = ContinuousClock.now
        var lastWordsAt: Double = 0
        var stopped = false
        var failed = false

        init(_ config: SpeechEndpoint.Config) { endpoint = SpeechEndpoint(config) }

        var elapsed: Double { (ContinuousClock.now - openedAt).timeInterval }
    }

    init(vocabulary: [String] = [], language: String? = nil) {
        self.vocabulary = vocabulary
        self.language = language
    }

    // MARK: Preparing

    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .denied: throw SpokenListenerFailure.microphoneDenied
        case .undetermined:
            guard await AVAudioApplication.requestRecordPermission() else { throw SpokenListenerFailure.microphoneDenied }
        default: break
        }
        choice = try await speechChoice(progress: progress)
        do {
            try activateSession()
            observe()
            try startEngine()
        } catch {
            teardown()
            throw SpokenListenerFailure.microphoneUnavailable
        }
    }

    private func speechChoice(progress: @escaping @MainActor (Double) -> Void) async throws -> TranscriptionChoice {
        let preferred = (language.map { [$0] } ?? []) + Locale.preferredLanguages
        switch await TranscriptionGate.resolve(preferredLanguages: preferred) {
        case .available(let found):
            let choice = await TranscriptionGate.preferringVocabulary(found, vocabulary: vocabulary)
            guard !choice.isInstalled else { return choice }
            do {
                try await LectureSpeechModels.install(choice) { fraction in
                    Task { @MainActor in progress(fraction) }
                }
                return choice
            } catch {
                throw SpokenListenerFailure.noSpeechModel(language: choice.languageName)
            }
        case .unavailableOnDevice:
            throw SpokenListenerFailure.noSpeechModel(language: nil)
        case .unavailableLanguage(let name):
            throw SpokenListenerFailure.noSpeechModel(language: name)
        }
    }

    // MARK: A turn

    func listen(_ spoken: SpokenTurn, onWords: @escaping @MainActor (String) -> Void) async -> SpokenHearing {
        guard let choice, isRunning else { return SpokenHearing(text: "", ending: .failed) }
        let open = OpenTurn(spoken.endpoint)
        turn = open
        // Buffers are kept from this moment, so the first words aren't lost while the analyzer gets ready.
        let relay = AudioListenerRelay(maxSeconds: Self.backlogSeconds)
        gate.open(relay.listener)
        let terms = Array((spoken.terms + vocabulary).prefix(LectureVocabulary.limit))
        let transcriber = SpeechLectureTranscriber(choice: choice, vocabulary: terms)
        do {
            let listener = try await transcriber.start(timeOffset: 0) { [weak open] event in
                guard let open else { return }
                switch event {
                case .volatile(let words):
                    if open.words.volatile(words) {
                        open.endpoint.heardWords(at: open.elapsed)
                        open.lastWordsAt = open.elapsed
                    }
                case .final(let words, _, _):
                    open.words.final(words)
                    open.endpoint.heardWords(at: open.elapsed)
                    open.lastWordsAt = open.elapsed
                case .failed:
                    open.failed = true
                }
                onWords(open.words.text)
            }
            relay.attach(listener)
        } catch {
            gate.close()
            relay.close()
            turn = nil
            return SpokenHearing(text: "", ending: .failed)
        }
        var ending: SpokenHearing.Ending?
        while ending == nil {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled || open.stopped {
                ending = .stopped
            } else if open.failed {
                ending = .failed
            } else if let reached = open.endpoint.ending(at: open.elapsed) {
                switch reached {
                case .silence: ending = .silence
                case .cap: ending = .cap
                case .noSpeech: ending = .noSpeech
                }
            }
        }
        // The turn is over: nothing more is taken from the microphone, and what was held goes with it.
        gate.close()
        relay.close()
        // The last words are flushed; a recogniser that doesn't finish can't hold the session up.
        let watchdog = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.flushSeconds))
            if !Task.isCancelled { transcriber.cancel() }
        }
        await transcriber.finish()
        watchdog.cancel()
        onWords(open.words.text)
        turn = nil
        return SpokenHearing(text: open.words.text, ending: ending ?? .stopped, seconds: open.lastWordsAt)
    }

    func stopListening() { turn?.stopped = true }

    private func noteLevel(_ level: Float) {
        guard let turn else { return }
        turn.endpoint.level(level, at: turn.elapsed)
        onLevel?(level)
    }

    // MARK: Pause

    func suspend() {
        stopListening()
        guard isRunning else { return }
        isRunning = false
        stopEngine()
    }

    func resume() throws {
        guard !isRunning, choice != nil else { return }
        do {
            try activateSession()
            try startEngine()
        } catch {
            throw SpokenListenerFailure.microphoneUnavailable
        }
    }

    func close() {
        stopListening()
        teardown()
    }

    private func teardown() {
        isRunning = false
        gate.close()
        stopEngine()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        AudioFocus.release(.microphone)
    }

    // MARK: Engine

    private func startEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpokenListenerFailure.microphoneUnavailable }
        if tapInstalled { input.removeTap(onBus: 0) }
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.tap(gate: gate, level: levelSink()))
        tapInstalled = true
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    private func stopEngine() {
        if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        tapInstalled = false
        engine.stop()
    }

    private func levelSink() -> @Sendable (Float) -> Void {
        { [weak self] level in
            Task { @MainActor in self?.noteLevel(level) }
        }
    }

    /// The tap. Built outside the actor on purpose: it runs on the audio thread, and a closure formed inside a main-actor method would inherit
    /// that isolation. Between turns the gate is shut and nothing happens to the buffer.
    nonisolated private static func tap(gate: SpokenTapGate, level: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard gate.receive(buffer) else { return }
            level(AudioLevel.level(of: buffer))
        }
    }

    // MARK: Session

    /// Sound effects stop first and stay silent until this ends (`AudioFocus`).
    private func activateSession() throws {
        AudioFocus.claim(.microphone)
        let session = AVAudioSession.sharedInstance()
        let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: options)
        } catch {
            try session.setCategory(.playAndRecord, mode: .default, options: options)
        }
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true)
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = AVAudioSession.InterruptionOptions(rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated { self?.handleInterruption(type, options: options) }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleReset() }
        })
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType?, options: AVAudioSession.InterruptionOptions) {
        switch type {
        case .began:
            guard isRunning else { return }
            isRunning = false
            stopEngine()
            onInterruption?(.began)
        case .ended:
            onInterruption?(.ended(shouldResume: options.contains(.shouldResume)))
        default:
            break
        }
    }

    /// The engine stops itself when the input changes (AirPods in or out); the tap restarts on the new input.
    private func handleConfigurationChange() {
        guard isRunning else { return }
        stopEngine()
        do {
            try startEngine()
        } catch {
            isRunning = false
            onInterruption?(.lostInput)
        }
    }

    private func handleReset() {
        let wasRunning = isRunning
        stopEngine()
        engine = AVAudioEngine()
        tapInstalled = false
        guard wasRunning else { return }
        do {
            try activateSession()
            try startEngine()
        } catch {
            isRunning = false
            onInterruption?(.lostInput)
        }
    }
}
