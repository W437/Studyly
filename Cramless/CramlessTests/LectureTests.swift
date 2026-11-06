import AVFoundation
import SwiftData
import XCTest
@testable import Cramless

/// Lectures without a microphone or speech models: flag phrases, transcript assembly, the language gate, the
/// session driven by stand-ins, the audio converter, and the crash-safe recording file.
@MainActor
final class LectureTests: CaptureTestCase {
    // MARK: Exam flags

    func testExamPhrasesAreFlagged() {
        let flagged = [
            "This one will be on the midterm, by the way: anaphase is where the sister chromatids get pulled apart.",
            "This is definitely going to be on the exam.",
            "You'll be tested on the Krebs cycle.",
            "It will be tested, so learn the steps.",
            "Make sure you know the order of the phases.",
            "Be sure that you understand osmosis.",
            "OK, this is really important.",
            "That’s important for the final.",
            "Remember this one.",
            "Don't forget that the spindle attaches at the centromere.",
            "Write this down.",
            "Expect an exam question on this.",
            "It might show up on the quiz next week.",
            "Here's the key point.",
            "Esto es muy importante para el examen.",
            "C'est important, retenez bien ça.",
            "Das ist prüfungsrelevant.",
            "זה יופיע במבחן",
        ]
        for text in flagged { XCTAssertTrue(ExamFlagDetector.matches(text), text) }
    }

    func testOrdinarySentencesAreNot() {
        let plain = [
            "Put the sample in the test tube.",
            "The final answer is twelve.",
            "It is important that cells divide.",
            "Mitosis is essential for growth.",
            "We ran the test cases yesterday.",
            "On the final slide you can see the spindle.",
            "Today: what actually happens when the cell divides.",
            "I remember when microscopes were worse.",
        ]
        for text in plain { XCTAssertFalse(ExamFlagDetector.matches(text), text) }
    }

    func testPhraseFlagsMergeNearbyMentionsAndNumberOn() {
        let segments = [
            TranscriptSegment(id: "s1", start: 10, end: 18, text: "This will be on the exam."),
            TranscriptSegment(id: "s2", start: 19, end: 25, text: "Make sure you know it."),
            TranscriptSegment(id: "s3", start: 60, end: 70, text: "Ordinary sentence."),
            TranscriptSegment(id: "s4", start: 90, end: 99, text: "Remember this too."),
        ]
        let existing = [ExamFlag(id: "f1", time: 3, reason: .tapped, text: "")]
        let flags = ExamFlagDetector.phraseFlags(in: segments, existing: existing)
        XCTAssertEqual(flags.map(\.time), [10, 90], "the second mention nine seconds later repeats the first")
        XCTAssertEqual(flags.map(\.id), ["f2", "f3"])
        XCTAssertTrue(flags.allSatisfy { $0.reason == .phrase })
        XCTAssertEqual(flags.first?.text, "This will be on the exam.")
    }

    // MARK: Transcript

    func testFinalsBecomeSegmentsAndTinyOnesJoin() {
        var assembler = TranscriptAssembler()
        assembler.volatile(" Okay so")
        XCTAssertEqual(assembler.liveText, "Okay so")
        assembler.final(" Okay, so last time we finished interphase.", start: 0, end: 4.2)
        XCTAssertEqual(assembler.liveText, "")
        assembler.final("Right.", start: 4.5, end: 4.9)
        assembler.final("Prophase comes first.", start: 6, end: 8)
        assembler.final("   ", start: 8, end: 9)
        XCTAssertEqual(assembler.segments, [
            TranscriptSegment(id: "s1", start: 0, end: 4.9, text: "Okay, so last time we finished interphase. Right."),
            TranscriptSegment(id: "s2", start: 6, end: 8, text: "Prophase comes first."),
        ])
        var resumed = TranscriptAssembler(segments: assembler.segments)
        XCTAssertEqual(resumed.final("Then metaphase.", start: 30, end: 33)?.id, "s3")
    }

    // MARK: The language gate

    private struct FakeProbe: SpeechProbe {
        var speechIsAvailable = true
        var equivalents: [String: String] = [:]
        var statuses: [String: SpeechAssetStatus] = [:]

        func equivalent(_ locale: Locale, for backend: TranscriptionBackend) async -> Locale? {
            equivalents["\(backend.rawValue):\(locale.identifier(.bcp47))"].map { Locale(identifier: $0) }
        }

        func status(of locale: Locale, for backend: TranscriptionBackend) async -> SpeechAssetStatus {
            statuses["\(backend.rawValue):\(locale.identifier(.bcp47))"] ?? .unsupported
        }
    }

    func testGateChoosesAnInstalledSpeechModel() async {
        let probe = FakeProbe(statuses: ["speech:en-US": .installed, "dictation:en-US": .supported])
        let result = await TranscriptionGate.resolve(preferredLanguages: ["en-US"], probe: probe)
        XCTAssertEqual(result, .available(TranscriptionChoice(identifier: "en-US", backend: .speech, status: .installed)))
    }

    func testGateNeverTrustsAnEquivalentWithoutItsStatus() async {
        // SpeechTranscriber says he-IL is "equivalent" to Hebrew but won't install it; the dictation engine will.
        let probe = FakeProbe(equivalents: ["speech:he-IL": "he-IL", "speech:he": "he-IL"],
                              statuses: ["dictation:he-IL": .supported, "speech:en-US": .installed])
        let result = await TranscriptionGate.resolve(preferredLanguages: ["he-IL", "en-US"], probe: probe)
        XCTAssertEqual(result, .available(TranscriptionChoice(identifier: "he-IL", backend: .dictation, status: .supported)))
    }

    func testGateFallsThroughToTheEquivalentWhenItIsReallySupported() async {
        let probe = FakeProbe(equivalents: ["speech:en-IL": "en-GB"], statuses: ["speech:en-GB": .downloading])
        let result = await TranscriptionGate.resolve(preferredLanguages: ["en-IL"], probe: probe)
        XCTAssertEqual(result, .available(TranscriptionChoice(identifier: "en-GB", backend: .speech, status: .downloading)))
    }

    func testGateSaysWhichLanguageOrThatTheDeviceCant() async {
        let english = FakeProbe(statuses: ["speech:en-US": .installed])
        let language = await TranscriptionGate.resolve(preferredLanguages: ["he-IL"], probe: english)
        XCTAssertEqual(language, .unavailableLanguage(TranscriptionGate.languageName(of: "he-IL")))
        let nothing = await TranscriptionGate.resolve(preferredLanguages: ["en-US"], probe: FakeProbe(speechIsAvailable: false))
        XCTAssertEqual(nothing, .unavailableOnDevice)
        let dictationOnly = FakeProbe(speechIsAvailable: false, statuses: ["speech:en-US": .installed, "dictation:en-US": .installed])
        let result = await TranscriptionGate.resolve(preferredLanguages: ["en-US"], probe: dictationOnly)
        XCTAssertEqual(result, .available(TranscriptionChoice(identifier: "en-US", backend: .dictation, status: .installed)),
                       "the newer engine isn't on this device: dictation only")
    }

    /// What this Simulator says, for the record (not asserted: it changes with the runtime).
    func testLogTheSimulatorsSpeechAnswers() async {
        let result = await TranscriptionGate.resolve(preferredLanguages: ["en-US"])
        print("Speech on this runtime: SpeechTranscriber.isAvailable=\(SystemSpeechProbe().speechIsAvailable) gate=\(result)")
    }

    // MARK: The session

    private func waitUntil(_ condition: () -> Bool, timeout: Double = 8, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out", file: file, line: line) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func fastDemo() -> LecturePorts {
        .demo(wordInterval: .milliseconds(2), linePause: .milliseconds(5))
    }

    func testARecordedLectureKeepsItsTranscriptAndFlags() async throws {
        let app = try makeApp()
        let course = makeCourse(app)
        let session = app.makeLectureSessionForTests(courseID: course.id, ports: fastDemo())
        XCTAssertEqual(session.title, "Lecture 1")
        XCTAssertEqual(session.state, .idle)
        await session.start()
        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(session.transcription, .demo)
        XCTAssertTrue(session.statusLine.contains("Demo"))
        let id = try XCTUnwrap(session.sourceID)
        XCTAssertEqual(app.source(id)?.status, .captured, "the source exists from the first second")
        XCTAssertTrue(LectureJobs.recording.contains(id))

        try await waitUntil { session.segments.count == ScriptedLectureTranscriber.sampleLecture.count }
        XCTAssertEqual(session.segments.map(\.id), ["s1", "s2", "s3", "s4", "s5", "s6"])
        XCTAssertEqual(session.flags.filter { $0.reason == .phrase }.map(\.text), [ScriptedLectureTranscriber.sampleLecture[4]],
                       "\"on the midterm\" is flagged")
        try await waitUntil { session.levels.contains { $0 > 0 } }
        XCTAssertEqual(session.levels.count, LectureSession.levelHistoryCount)

        let tap = try XCTUnwrap(session.flag())
        XCTAssertEqual(tap.reason, .tapped)
        XCTAssertNil(session.flag(), "a second tap straight after is the same tap")
        session.pause()
        XCTAssertEqual(session.state, .paused(.person))
        let paused = session.elapsed
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(session.elapsed, paused, "the clock stands still while paused")
        XCTAssertEqual(app.source(id)?.flags.count, 2, "pausing checkpoints the flags")
        session.resume()
        XCTAssertEqual(session.state, .recording)

        let finished = await session.stop()
        XCTAssertEqual(finished, id)
        XCTAssertEqual(session.state, .finished(sourceID: id))
        XCTAssertFalse(LectureJobs.recording.contains(id))
        let source = try XCTUnwrap(app.source(id))
        XCTAssertEqual(source.kind, .lecture)
        XCTAssertEqual(source.status, .read)
        XCTAssertEqual(source.title, "Lecture 1")
        XCTAssertEqual(source.segments.count, 6)
        XCTAssertEqual(source.flags.count, 2)
        XCTAssertGreaterThan(source.duration, 0)
        XCTAssertTrue(source.segments.allSatisfy { $0.end >= $0.start })
        XCTAssertTrue(course.liveSources.contains { $0.id == id })
        XCTAssertEqual(app.nextLectureTitle(courseID: course.id), "Lecture 2")
    }

    func testWithoutASpeechModelTheRecordingIsKeptAndTheTranscriptPending() async throws {
        let app = try makeApp()
        var ports = fastDemo()
        ports.isDemo = false
        ports.availability = { .unavailableLanguage("Hebrew") }
        let session = app.makeLectureSessionForTests(courseID: nil, ports: ports)
        await session.start()
        XCTAssertEqual(session.transcription, .unavailableLanguage("Hebrew"))
        XCTAssertTrue(session.statusLine.contains("Hebrew") && session.statusLine.contains("pending"), session.statusLine)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(session.segments.isEmpty)
        let stopped = await session.stop()
        let id = try XCTUnwrap(stopped)
        let source = try XCTUnwrap(app.source(id))
        XCTAssertEqual(source.status, .captured, "audio without a transcript: pending")
        XCTAssertTrue(source.segments.isEmpty)
    }

    func testAModelStillDownloadingMeansTheTranscriptComesAfterStop() async throws {
        let app = try makeApp()
        let choice = TranscriptionChoice(identifier: "en-US", backend: .speech, status: .supported)
        var ports = fastDemo()
        ports.isDemo = false
        ports.availability = { .available(choice) }
        ports.install = { _, progress in
            progress(0.5)
            try await Task.sleep(for: .milliseconds(400))
        }
        let session = app.makeLectureSessionForTests(courseID: nil, ports: ports)
        await session.start()
        if case .downloading = session.transcription {} else { XCTFail("downloading first: \(session.transcription)") }
        try await waitUntil { session.transcription == .afterStop(language: choice.languageName) }
        XCTAssertTrue(session.statusLine.contains("when you stop"))
        session.discard()
    }

    func testAModelThatCantBeDownloadedSaysSo() async throws {
        let app = try makeApp()
        let choice = TranscriptionChoice(identifier: "en-US", backend: .dictation, status: .supported)
        var ports = fastDemo()
        ports.isDemo = false
        ports.availability = { .available(choice) }
        ports.install = { _, _ in throw TranscriptionError.model }
        let session = app.makeLectureSessionForTests(courseID: nil, ports: ports)
        await session.start()
        try await waitUntil { session.transcription == .modelUnavailable(language: choice.languageName) }
        XCTAssertTrue(session.statusLine.contains("Couldn't download") && session.statusLine.contains("pending"), session.statusLine)
        XCTAssertEqual(session.state, .recording, "the recording carries on")
        session.discard()
    }

    func testInterruptionsPauseAndResume() async throws {
        let app = try makeApp()
        let audio = ControlledAudio()
        var ports = fastDemo()
        ports.makeAudio = { audio }
        let session = app.makeLectureSessionForTests(courseID: nil, ports: ports)
        await session.start()
        audio.onInterruption?(.began)
        XCTAssertEqual(session.state, .paused(.interruption))
        XCTAssertEqual(audio.events, ["start"])
        audio.onInterruption?(.ended(shouldResume: true))
        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(audio.events, ["start", "resume"])
        audio.onInterruption?(.lostInput)
        XCTAssertEqual(session.state, .paused(.lostInput))
        audio.onInterruption?(.ended(shouldResume: true))
        XCTAssertEqual(session.state, .paused(.lostInput), "only an interruption pause resumes by itself")
        session.resume()
        XCTAssertEqual(session.state, .recording)
        session.discard()
        XCTAssertEqual(session.state, .discarded)
        XCTAssertEqual(audio.events.last, "cancel")
        XCTAssertNil(app.source(try XCTUnwrap(session.sourceID)), "a discarded lecture leaves nothing behind")
    }

    func testMicrophoneDeniedFailsWithoutMakingASource() async throws {
        let app = try makeApp()
        let audio = ControlledAudio()
        audio.startError = .microphoneDenied
        var ports = fastDemo()
        ports.makeAudio = { audio }
        let session = app.makeLectureSessionForTests(courseID: nil, ports: ports)
        await session.start()
        XCTAssertEqual(session.state, .failed(.microphoneDenied))
        XCTAssertNil(session.sourceID)
        XCTAssertTrue(app.fetch(FetchDescriptorFactory.allSources).isEmpty)
        XCTAssertEqual(LectureFailure.microphoneDenied.message, "Microphone access is off. Turn it on in Settings to record lectures.")
    }

    func testTheDemoLectureIsTheSeededLecture() throws {
        let app = try makeApp()
        SampleData.seed(into: app)
        let lecture = try XCTUnwrap(app.courses.flatMap(\.liveSources).first { $0.kind == .lecture })
        XCTAssertEqual(lecture.segments.map(\.text), ScriptedLectureTranscriber.sampleLecture)
    }

    func testClockText() {
        XCTAssertEqual(LectureSession.clock(761), "12:41")
        XCTAssertEqual(LectureSession.clock(3725), "1:02:05")
        XCTAssertEqual(LectureSession.clock(-3), "0:00")
    }

    // MARK: Audio

    private func sine(rate: Double, channels: AVAudioChannelCount, frames: AVAudioFrameCount, offset: Int = 0) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            for i in 0..<Int(frames) { buffer.floatChannelData![channel][i] = 0.3 * sin(Float(offset + i) * 2 * .pi * 440 / Float(rate)) }
        }
        return buffer
    }

    func testConverterResamplesToTheAnalyzersFormat() throws {
        let target = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let first = sine(rate: 48_000, channels: 2, frames: 4800)
        let converter = try XCTUnwrap(AudioBufferConverter(from: first.format, to: target))
        var total: AVAudioFrameCount = 0
        var deficits: [Double] = []
        for index in 0..<40 {
            let output = try XCTUnwrap(converter.convert(sine(rate: 48_000, channels: 2, frames: 4800, offset: index * 4800)))
            XCTAssertEqual(output.format.sampleRate, 16_000)
            XCTAssertEqual(output.format.channelCount, 1)
            total += output.frameLength
            if index % 10 == 9 { deficits.append(Double(index + 1) * 1600 - Double(total)) }
        }
        // The converter takes at most 4096 input frames a call and carries the rest, so it holds back up to one
        // block (4096 at 48 kHz = 1365 frames at 16 kHz, 85 ms) and saw-tooths below that (measured on the
        // Simulator: 982, 598, 214, 1195). Bounded, never accumulating: nothing is dropped as a lecture goes on.
        print("Converter shortfall after 1, 2, 3, 4 s (frames at 16 kHz): \(deficits)")
        XCTAssertTrue(deficits.allSatisfy { $0 >= 0 && $0 < 1600 }, "held back under a tenth of a second, always: \(deficits)")
        let level = AudioLevel.level(of: first)
        XCTAssertGreaterThan(level, 0.5)
        XCTAssertLessThan(level, 1)
        XCTAssertEqual(AudioLevel.level(of: sine(rate: 48_000, channels: 1, frames: 0)), 0)
    }

    func testTheRelayKeepsTheFirstSecondsForTheTranscriber() {
        let relay = AudioListenerRelay(maxSeconds: 1)
        for index in 0..<15 { relay.receive(sine(rate: 48_000, channels: 1, frames: 4800, offset: index * 4800)) }
        XCTAssertEqual(relay.droppedSeconds, 0.5, accuracy: 0.001, "a second and a half before the transcriber: half a second overflowed")
        let received = FrameTally()
        relay.attach { received.add($0) }
        XCTAssertEqual(received.frames, 48_000, "the kept second is replayed first")
        XCTAssertEqual(received.firstSample, 0.3 * sin(Float(5 * 4800) * 2 * .pi * 440 / 48_000), accuracy: 0.0001, "in order, oldest kept first")
        relay.receive(sine(rate: 48_000, channels: 1, frames: 4800))
        XCTAssertEqual(received.frames, 52_800, "then live")
        relay.close()
        relay.receive(sine(rate: 48_000, channels: 1, frames: 4800))
        XCTAssertEqual(received.frames, 52_800, "closed: nothing more")
    }

    func testTheRecordingIsRemuxedIntoM4A() async throws {
        let id = UUID()
        let writer = AudioFileWriter(url: FileStore.url(for: LectureFiles.recording(id)))
        for index in 0..<20 { writer.write(sine(rate: 48_000, channels: 1, frames: 4800, offset: index * 4800)) }
        XCTAssertEqual(writer.seconds, 2, accuracy: 0.01)
        writer.close()
        let path = await LectureFiles.finalize(id)
        XCTAssertEqual(path, LectureFiles.audio(id))
        let asset = AVURLAsset(url: FileStore.url(for: try XCTUnwrap(path)))
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: FileStore.url(for: LectureFiles.recording(id)).path))
    }

    /// The app killed mid-lecture: the stream was never closed. The next launch finishes it.
    func testALectureInterruptedByACrashIsRecovered() async throws {
        let app = try makeApp()
        let source = app.startLecture(courseID: nil, title: "Lecture 3")
        app.checkpointLecture(source.id, duration: 1, segments: [TranscriptSegment(id: "s1", start: 0, end: 1, text: "Hello.")], flags: [])
        let live = AudioFileWriter(url: root.appending(path: "live.aac"))
        for index in 0..<30 { live.write(sine(rate: 48_000, channels: 1, frames: 4800, offset: index * 4800)) }
        // Copy the stream while the writer still has it open: what a crash leaves on disk.
        try FileManager.default.createDirectory(at: FileStore.url(for: LectureFiles.folder(source.id)), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root.appending(path: "live.aac"), to: FileStore.url(for: LectureFiles.recording(source.id)))
        live.close()

        let recovered = await app.recoverInterruptedLectures()
        XCTAssertEqual(source.fileName, LectureFiles.audio(source.id))
        XCTAssertGreaterThan(source.duration, 1.5)
        XCTAssertEqual(source.status, .read, "the transcript checkpointed before the crash is kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: FileStore.url(for: LectureFiles.audio(source.id)).path))
        // What was kept is reported, for the toast at launch.
        XCTAssertEqual(recovered.map(\.id), [source.id])
        XCTAssertEqual(recovered.first?.duration ?? 0, source.duration, accuracy: 0.001)
        XCTAssertNil(RecoveredLecture.toast(for: recovered), "three seconds is a stray tap on record: nothing to say")
        let again = await app.recoverInterruptedLectures()
        XCTAssertTrue(again.isEmpty, "a lecture is recovered, and told about, once")
    }

    func testTheRecoveredLectureToastSaysHowMuchWasKept() throws {
        let id = UUID()
        let one = try XCTUnwrap(RecoveredLecture.toast(for: [RecoveredLecture(id: id, duration: 2480)]))
        XCTAssertEqual(String(localized: one.message), "Cap kept your lecture up to 41:20.")
        XCTAssertEqual(one.action, .push(.lectureNotes(id), .library), "Open shows its notes")
        let long = try XCTUnwrap(RecoveredLecture.toast(for: [RecoveredLecture(id: id, duration: 3725)]))
        XCTAssertEqual(String(localized: long.message), "Cap kept your lecture up to 1:02:05.")
        let two = try XCTUnwrap(RecoveredLecture.toast(for: [RecoveredLecture(id: id, duration: 2480),
                                                             RecoveredLecture(id: UUID(), duration: 900),
                                                             RecoveredLecture(id: UUID(), duration: 4)]))
        XCTAssertEqual(String(localized: two.message), "Cap kept 2 lectures that were cut off.")
        XCTAssertNil(two.action)
        XCTAssertNil(RecoveredLecture.toast(for: []))
    }

    func testTheToastRaisedAtLaunchOpensTheLecture() throws {
        let app = try makeApp()
        app.settings.onboardingCompleted = true
        let id = UUID()
        app.announceRecoveredLectures([RecoveredLecture(id: id, duration: 2480)])
        let toast = try XCTUnwrap(app.router.toast)
        XCTAssertEqual(String(localized: toast.message), "Cap kept your lecture up to 41:20.")
        XCTAssertEqual(toast.actionTitle.map { String(localized: $0) }, "Open")
        app.router.runToastAction()
        XCTAssertNil(app.router.toast)
        XCTAssertEqual(app.router.tab, .library)
        XCTAssertEqual(app.router.paths[.library], [.lectureNotes(id)])

        app.settings.onboardingCompleted = false
        app.announceRecoveredLectures([RecoveredLecture(id: id, duration: 2480)])
        XCTAssertNil(app.router.toast, "nothing over onboarding")
    }
}

/// Counts what a listener received (it's called from whatever thread feeds the relay).
private final class FrameTally: @unchecked Sendable {
    private let lock = NSLock()
    private var total: AVAudioFramePosition = 0
    private var first: Float?

    func add(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        if first == nil { first = buffer.floatChannelData?[0][0] }
        total += AVAudioFramePosition(buffer.frameLength)
    }

    var frames: AVAudioFramePosition { lock.lock(); defer { lock.unlock() }; return total }
    var firstSample: Float { lock.lock(); defer { lock.unlock() }; return first ?? .nan }
}

/// A microphone stand-in whose interruptions the test fires.
@MainActor
private final class ControlledAudio: LectureAudioCapturing {
    var onLevel: ((Float) -> Void)?
    var onInterruption: ((LectureInterruption) -> Void)?
    var recordedSeconds: Double = 0
    var startError: LectureFailure?
    private(set) var events: [String] = []

    func start(sourceID: UUID, listener: AudioListener?) async throws {
        if let startError { throw startError }
        events.append("start")
    }

    func pause() { events.append("pause") }
    func resume() throws { events.append("resume") }

    func stop() async -> RecordedAudio {
        events.append("stop")
        return RecordedAudio(fileName: nil, duration: 0)
    }

    func cancel() { events.append("cancel") }
}

extension AppModel {
    /// A session on the given stand-ins.
    func makeLectureSessionForTests(courseID: UUID?, ports: LecturePorts) -> LectureSession {
        LectureSession(app: self, courseID: courseID, ports: ports)
    }
}

extension FetchDescriptorFactory {
    static var allSources: FetchDescriptor<Source> { FetchDescriptor<Source>() }
}

/// The engine choice for a course with its own words (measured with scripts/speech_live/run.sh).
final class LectureVocabularyTests: XCTestCase {
    private struct Probe: SpeechProbe {
        var dictation: SpeechAssetStatus
        var speechIsAvailable: Bool { true }
        func equivalent(_ locale: Locale, for backend: TranscriptionBackend) async -> Locale? { locale }
        func status(of locale: Locale, for backend: TranscriptionBackend) async -> SpeechAssetStatus {
            backend == .dictation ? dictation : .installed
        }
    }

    func testAVocabularyPrefersTheEngineThatUsesIt() async {
        let speech = TranscriptionChoice(identifier: "en-US", backend: .speech, status: .installed)
        let terms = ["interphase", "prophase", "metaphase", "anaphase", "telophase"]
        let chosen = await TranscriptionGate.preferringVocabulary(speech, vocabulary: terms, probe: Probe(dictation: .supported))
        XCTAssertEqual(chosen.backend, .dictation)
        XCTAssertEqual(chosen.identifier, "en-US")
        let unchanged = await TranscriptionGate.preferringVocabulary(speech, vocabulary: ["mitosis"], probe: Probe(dictation: .supported))
        XCTAssertEqual(unchanged.backend, .speech, "a couple of words isn't worth switching engines")
        let noDictation = await TranscriptionGate.preferringVocabulary(speech, vocabulary: terms, probe: Probe(dictation: .unsupported))
        XCTAssertEqual(noDictation.backend, .speech)
    }
}
