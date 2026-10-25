import AVFoundation
import Foundation

// MARK: - Files

/// Where a lecture's audio lives, relative to `FileStore.root`.
///
/// While recording, the audio is AAC in an ADTS stream (`recording.aac`); on Stop it is remuxed, without
/// re-encoding, into `lecture.m4a`. Measured (Oct 2026, macOS 26.6 and the iOS 27 Simulator): an `.m4a` that
/// `AVAudioFile` never got to close (the app killed mid-lecture, a force-quit from the app switcher) can't be opened
/// at all, and AAC in CAF reads as 0 seconds; an ADTS stream cut off the same way reads to its last packet (2.99 of
/// 3 s) and remuxes cleanly. So a crash costs a moment of a lecture, not the lecture.
/// `AppModel.recoverInterruptedLectures()` finishes the remux on the next launch (`LectureTests` keeps this true).
enum LectureFiles {
    static let recordingName = "recording.aac"
    static let audioName = "lecture.m4a"

    static func folder(_ sourceID: UUID) -> String { "sources/\(sourceID.uuidString)" }
    static func recording(_ sourceID: UUID) -> String { "\(folder(sourceID))/\(recordingName)" }
    static func audio(_ sourceID: UUID) -> String { "\(folder(sourceID))/\(audioName)" }

    /// Remuxes `recording.aac` into `lecture.m4a` (passthrough, then a re-encode if that fails) and deletes the
    /// stream. Returns the relative path of the playable file: the `.m4a`, or the `.aac` when both remuxes fail
    /// (still playable), or nil when there is no audio.
    static func finalize(_ sourceID: UUID) async -> String? {
        let recording = FileStore.url(for: recording(sourceID))
        let audio = FileStore.url(for: audio(sourceID))
        let manager = FileManager.default
        guard manager.fileExists(atPath: recording.path) else {
            return manager.fileExists(atPath: audio.path) ? Self.audio(sourceID) : nil
        }
        let size = (try? manager.attributesOfItem(atPath: recording.path)[.size] as? Int) ?? 0
        guard size > 0 else {
            try? manager.removeItem(at: recording)
            return nil
        }
        let asset = AVURLAsset(url: recording)
        for preset in [AVAssetExportPresetPassthrough, AVAssetExportPresetAppleM4A] {
            try? manager.removeItem(at: audio)
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            do {
                try await session.export(to: audio, as: .m4a)
                try? manager.removeItem(at: recording)
                return Self.audio(sourceID)
            } catch {
                AppConfig.log.error("lecture remux (\(preset, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        try? manager.removeItem(at: audio)
        return Self.recording(sourceID)
    }
}

// MARK: - The session's view of the microphone

/// Audio from the tap, handed to the transcriber on the audio thread.
typealias AudioListener = @Sendable (AVAudioPCMBuffer) -> Void

/// What a finished recording left on disk.
struct RecordedAudio: Equatable, Sendable {
    /// The playable file, relative to `FileStore.root`; nil when nothing was recorded (a demo).
    var fileName: String?
    /// Seconds of audio recorded (pauses excluded).
    var duration: Double
}

/// Something the system did to the recording.
enum LectureInterruption: Equatable, Sendable {
    /// A call or an alarm took the microphone. Recording is paused.
    case began
    /// It ended; `shouldResume` when the system says recording may carry on.
    case ended(shouldResume: Bool)
    /// The microphone went away and couldn't be restarted (a route change that failed). Recording is paused.
    case lostInput
}

enum LectureFailure: Error, Equatable, Sendable {
    /// Microphone access is off.
    case microphoneDenied
    /// The microphone or the audio session couldn't start.
    case microphoneUnavailable
    /// The recording couldn't be written (storage full).
    case storage

    var message: String {
        switch self {
        case .microphoneDenied: "Microphone access is off. Turn it on in Settings to record lectures."
        case .microphoneUnavailable: "Couldn't start the microphone. Close other apps using it and try again."
        case .storage: "Couldn't save the recording. Free up some space on your iPhone and try again."
        }
    }
}

/// The microphone, as the lecture session sees it: `LectureRecorder` on a device, a stand-in in DEBUG demos.
@MainActor
protocol LectureAudioCapturing: AnyObject {
    /// The input level, 0…1, about ten times a second while recording (on the main actor).
    var onLevel: ((Float) -> Void)? { get set }
    /// Something the system did (on the main actor).
    var onInterruption: ((LectureInterruption) -> Void)? { get set }
    /// Seconds of audio written so far.
    var recordedSeconds: Double { get }
    func start(sourceID: UUID, listener: AudioListener?) async throws
    func pause()
    func resume() throws
    func stop() async -> RecordedAudio
    /// Stops and deletes what was recorded.
    func cancel()
}

// MARK: - The recording file

/// Writes the microphone's buffers to `recording.aac` (AAC, mono, at the microphone's rate), converting when a
/// route change hands over another format. Written from the tap's thread; everything is behind one lock.
final class AudioFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var file: AVAudioFile?
    private var converter: FollowingConverter?
    private var frames: AVAudioFramePosition = 0
    private var sampleRate: Double = 0
    private(set) var failed = false

    init(url: URL) {
        self.url = url
    }

    var seconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return sampleRate > 0 ? Double(frames) / sampleRate : 0
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !failed, buffer.frameLength > 0 else { return }
        do {
            if file == nil { try open(sampleRate: buffer.format.sampleRate) }
            guard let file, let converter, let converted = converter.convert(buffer) else { return }
            try file.write(from: converted)
            frames += AVAudioFramePosition(converted.frameLength)
        } catch {
            failed = true
            AppConfig.log.error("lecture write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Finishes the file. The stream stays readable even if this never runs.
    func close() {
        lock.lock()
        defer { lock.unlock() }
        file?.close()
        file = nil
    }

    private func open(sampleRate rate: Double) throws {
        let rate = rate > 0 ? rate : 48_000
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]
        let opened: AVAudioFile
        do {
            opened = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            // Some rates don't take 64 kbps; let the encoder choose.
            settings[AVEncoderBitRateKey] = nil
            settings[AVEncoderAudioQualityKey] = AVAudioQuality.medium.rawValue
            opened = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        }
        file = opened
        sampleRate = opened.processingFormat.sampleRate
        converter = FollowingConverter(target: opened.processingFormat)
    }
}

// MARK: - The microphone

/// Records the microphone with `AVAudioEngine`: one tap writes the file, measures the level and hands each buffer
/// to the transcriber. The audio session is `.playAndRecord` on the built-in microphone (a Bluetooth headset's
/// microphone would hear the student, not the lecturer), and background audio keeps it running with the screen
/// locked. Calls and alarms pause it (`onInterruption`); a route change (headphones in or out) restarts the tap
/// on the new input; a media-services reset rebuilds the engine.
///
/// Needs a device (or the Simulator with the Mac's microphone): tests drive `LectureSession` with stand-ins.
@MainActor
final class LectureRecorder: LectureAudioCapturing {
    var onLevel: ((Float) -> Void)?
    var onInterruption: ((LectureInterruption) -> Void)?

    private var engine = AVAudioEngine()
    private var writer: AudioFileWriter?
    private var listener: AudioListener?
    private var sourceID: UUID?
    private var observers: [NSObjectProtocol] = []
    private var tapInstalled = false
    /// Recording (not paused, not stopped).
    private var isRunning = false

    var recordedSeconds: Double { writer?.seconds ?? 0 }

    func start(sourceID: UUID, listener: AudioListener?) async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .denied: throw LectureFailure.microphoneDenied
        case .undetermined:
            guard await AVAudioApplication.requestRecordPermission() else { throw LectureFailure.microphoneDenied }
        default: break
        }
        self.sourceID = sourceID
        self.listener = listener
        writer = AudioFileWriter(url: FileStore.url(for: LectureFiles.recording(sourceID)))
        do {
            try activateSession()
            observe()
            try startEngine()
        } catch {
            teardown()
            throw (error as? LectureFailure) ?? .microphoneUnavailable
        }
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        stopEngine()
    }

    func resume() throws {
        guard !isRunning, writer != nil else { return }
        do {
            try activateSession()
            try startEngine()
        } catch {
            throw LectureFailure.microphoneUnavailable
        }
    }

    func stop() async -> RecordedAudio {
        let duration = recordedSeconds
        let id = sourceID
        teardown()
        guard let id else { return RecordedAudio(fileName: nil, duration: duration) }
        let fileName = await LectureFiles.finalize(id)
        return RecordedAudio(fileName: fileName, duration: duration)
    }

    func cancel() {
        let id = sourceID
        teardown()
        if let id {
            try? FileManager.default.removeItem(at: FileStore.url(for: LectureFiles.recording(id)))
            try? FileManager.default.removeItem(at: FileStore.url(for: LectureFiles.audio(id)))
        }
    }

    // MARK: Engine

    private func startEngine() throws {
        guard let writer else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw LectureFailure.microphoneUnavailable }
        if tapInstalled { input.removeTap(onBus: 0) }
        input.installTap(onBus: 0, bufferSize: 4096, format: format,
                         block: Self.tap(writer: writer, listener: listener, level: levelSink()))
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
            Task { @MainActor in self?.onLevel?(level) }
        }
    }

    /// The tap: write, meter, hand on. Built outside the actor on purpose: it runs on the audio thread, and a
    /// closure formed inside a main-actor method would inherit that isolation.
    nonisolated private static func tap(writer: AudioFileWriter, listener: AudioListener?,
                                        level: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            writer.write(buffer)
            listener?(buffer)
            level(AudioLevel.level(of: buffer))
        }
    }

    private func teardown() {
        isRunning = false
        stopEngine()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        writer?.close()
        writer = nil
        listener = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        AudioFocus.release(.microphone)
    }

    // MARK: Session

    /// The microphone's session. Sound effects stop first and stay silent until the recording ends (`AudioFocus`).
    private func activateSession() throws {
        AudioFocus.claim(.microphone)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        // Haptics (the flag button) still play while the microphone is on.
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

    /// The engine stops itself when the input changes; restart the tap on the new input.
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
