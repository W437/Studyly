import AVFoundation
import Foundation
import Speech

// Lecture transcription on this iPhone (SpeechAnalyzer). The app opens no connection of its own: the one time the
// network is involved is the system installing a language's speech model the first time (`AssetInventory`,
// managed and shared by the system), which carries no audio.

// MARK: - Which language, which engine

/// The engine behind a language: the newer `SpeechTranscriber`, or `DictationTranscriber`, which covers
/// languages the newer one doesn't (measured on macOS 26.6: Hebrew, Arabic and Hindi have only the dictation model).
enum TranscriptionBackend: String, Codable, Sendable {
    case speech
    case dictation
}

/// `AssetInventory.Status`, in our own words so the gate is tested with a fake. Ordered.
enum SpeechAssetStatus: Int, Comparable, Sendable {
    case unsupported, downloading, supported, installed

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A language a lecture can be transcribed in, and how.
struct TranscriptionChoice: Equatable, Sendable {
    /// BCP 47, "en-US".
    var identifier: String
    var backend: TranscriptionBackend
    var status: SpeechAssetStatus

    var locale: Locale { Locale(identifier: identifier) }
    var isInstalled: Bool { status == .installed }
    /// The language's name in the screen's language: "English".
    var languageName: String { TranscriptionGate.languageName(of: identifier) }
}

enum TranscriptionAvailability: Equatable, Sendable {
    case available(TranscriptionChoice)
    /// This iPhone (or the Simulator) has no on-device speech model at all.
    case unavailableOnDevice
    /// None of the person's languages can be transcribed on device; the name is the first one's.
    case unavailableLanguage(String)
}

/// The framework's answers about a language, behind a seam so the gate is tested without speech models.
protocol SpeechProbe: Sendable {
    /// `SpeechTranscriber.isAvailable`: the newer engine runs on this device at all.
    var speechIsAvailable: Bool { get }
    /// `supportedLocale(equivalentTo:)`. **Not a gate**: it answers `en-GB` for "en" and `he-IL` for Hebrew,
    /// neither of which `SpeechTranscriber` will install (measured), so every answer is checked with `status`.
    func equivalent(_ locale: Locale, for backend: TranscriptionBackend) async -> Locale?
    /// `AssetInventory.status(forModules:)` for a transcriber of this backend and locale.
    func status(of locale: Locale, for backend: TranscriptionBackend) async -> SpeechAssetStatus
}

/// Picks the lecture's language from the person's preferred languages.
///
/// **Gate on the asset status, never on `supportedLocale(equivalentTo:)`** (the owner's Dozen app found this on a
/// device, and the macOS probe repeats it). For each of the first four preferred languages, in order, the
/// candidates are the exact locale, the engine's equivalent, the bare language and its equivalent; the newer
/// engine is tried first, then the dictation engine. A candidate passes when its status is not `.unsupported`.
enum TranscriptionGate {
    static let languageLimit = 4

    static func resolve(preferredLanguages: [String] = Locale.preferredLanguages,
                        probe: any SpeechProbe = SystemSpeechProbe()) async -> TranscriptionAvailability {
        let identifiers = preferredLanguages.isEmpty ? ["en-US"] : Array(preferredLanguages.prefix(languageLimit))
        for identifier in identifiers {
            if let choice = await choice(for: Locale(identifier: identifier), probe: probe) { return .available(choice) }
        }
        // English is the one language every engine has: when even it can't be had, the device has none.
        let english = Locale(identifier: "en-US")
        let speech = probe.speechIsAvailable ? await probe.status(of: english, for: .speech) : .unsupported
        let dictation = await probe.status(of: english, for: .dictation)
        let anything = speech != .unsupported || dictation != .unsupported
        return anything ? .unavailableLanguage(languageName(of: identifiers.first ?? "en")) : .unavailableOnDevice
    }

    /// With a course vocabulary, the dictation engine for the same language when it has one: measured on macOS
    /// 26.6, `SpeechTranscriber` ignored contextual strings while `DictationTranscriber` used them (a mitosis lecture
    /// went from "interface", "Anna faces" to "interphase", "anaphase", "telophase"). Without one, the choice stands.
    static func preferringVocabulary(_ choice: TranscriptionChoice, vocabulary: [String],
                                     probe: any SpeechProbe = SystemSpeechProbe()) async -> TranscriptionChoice {
        guard vocabulary.count >= 5, choice.backend == .speech else { return choice }
        let status = await probe.status(of: choice.locale, for: .dictation)
        guard status != .unsupported else { return choice }
        return TranscriptionChoice(identifier: choice.identifier, backend: .dictation, status: status)
    }

    static func choice(for wanted: Locale, probe: any SpeechProbe) async -> TranscriptionChoice? {
        let backends: [TranscriptionBackend] = probe.speechIsAvailable ? [.speech, .dictation] : [.dictation]
        for backend in backends {
            for candidate in await candidates(for: wanted, backend: backend, probe: probe) {
                let status = await probe.status(of: candidate, for: backend)
                if status != .unsupported {
                    return TranscriptionChoice(identifier: candidate.identifier(.bcp47), backend: backend, status: status)
                }
            }
        }
        return nil
    }

    /// The exact locale, its equivalent, the bare language and its equivalent, without repeats.
    static func candidates(for wanted: Locale, backend: TranscriptionBackend, probe: any SpeechProbe) async -> [Locale] {
        var found: [Locale] = []
        func add(_ locale: Locale?) {
            guard let locale, !found.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else { return }
            found.append(locale)
        }
        add(wanted)
        add(await probe.equivalent(wanted, for: backend))
        if let code = wanted.language.languageCode?.identifier {
            let bare = Locale(identifier: code)
            add(bare)
            add(await probe.equivalent(bare, for: backend))
        }
        return found
    }

    /// A language's name in the language of the screen: "Hebrew".
    static func languageName(of identifier: String, in display: Locale = .current) -> String {
        let code = Locale(identifier: identifier).language.languageCode?.identifier ?? identifier
        return display.localizedString(forLanguageCode: code) ?? identifier
    }
}

/// The real answers.
struct SystemSpeechProbe: SpeechProbe {
    var speechIsAvailable: Bool { SpeechTranscriber.isAvailable }

    func equivalent(_ locale: Locale, for backend: TranscriptionBackend) async -> Locale? {
        switch backend {
        case .speech: await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        case .dictation: await DictationTranscriber.supportedLocale(equivalentTo: locale)
        }
    }

    func status(of locale: Locale, for backend: TranscriptionBackend) async -> SpeechAssetStatus {
        let status = await AssetInventory.status(forModules: [SpeechModuleBox(locale: locale, backend: backend).module])
        switch status {
        case .unsupported: return .unsupported
        case .downloading: return .downloading
        case .supported: return .supported
        case .installed: return .installed
        @unknown default: return .unsupported
        }
    }
}

/// A transcriber module of either engine, and its results as plain values.
struct SpeechModuleBox {
    enum Kind {
        case speech(SpeechTranscriber)
        case dictation(DictationTranscriber)
    }

    let kind: Kind

    /// Lecture presets: progressive (volatile words while they're heard, then finals) for long-form speech.
    init(locale: Locale, backend: TranscriptionBackend) {
        switch backend {
        case .speech: kind = .speech(SpeechTranscriber(locale: locale, preset: .progressiveTranscription))
        case .dictation: kind = .dictation(DictationTranscriber(locale: locale, preset: .progressiveLongDictation))
        }
    }

    init(_ choice: TranscriptionChoice) { self.init(locale: choice.locale, backend: choice.backend) }

    var module: any SpeechModule {
        switch kind {
        case .speech(let transcriber): transcriber
        case .dictation(let transcriber): transcriber
        }
    }

    /// Every result as (text, start, end, isFinal), until the analyzer finishes.
    func results(_ body: (String, Double, Double, Bool) async -> Void) async throws {
        switch kind {
        case .speech(let transcriber):
            for try await result in transcriber.results {
                await body(String(result.text.characters), result.range.start.seconds, result.range.end.seconds, result.isFinal)
            }
        case .dictation(let transcriber):
            for try await result in transcriber.results {
                await body(String(result.text.characters), result.range.start.seconds, result.range.end.seconds, result.isFinal)
            }
        }
    }
}

// MARK: - Models

enum TranscriptionError: Error, Equatable {
    /// The language's model couldn't be had: not installed and not downloadable (no connection, no room).
    case model
    /// The analyzer failed or another analysis holds the slot.
    case recognition
}

enum LectureSpeechModels {
    /// Installs the language's model when it isn't there yet. `progress` (0…1) is called from any thread.
    /// A device can hold only so many languages' models: when that's the problem, the others are released and
    /// the request is made once more (from Dozen's engine, where a device showed it).
    static func install(_ choice: TranscriptionChoice, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let module = SpeechModuleBox(choice).module
        guard await AssetInventory.status(forModules: [module]) != .unsupported else { throw TranscriptionError.model }
        do {
            if let request = try await installationRequest(for: module) {
                let observation = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { p, _ in
                    progress(p.fractionCompleted)
                }
                defer { observation.invalidate() }
                try await request.downloadAndInstall()
            }
        } catch {
            throw TranscriptionError.model
        }
        // `downloadAndInstall` can return without throwing when its first attempt failed (no connection): the model
        // is there when the analyzer can name a format for it.
        guard await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) != nil else { throw TranscriptionError.model }
    }

    private static func installationRequest(for module: any SpeechModule) async throws -> AssetInstallationRequest? {
        do {
            return try await AssetInventory.assetInstallationRequest(supporting: [module])
        } catch {
            let ns = error as NSError
            guard ns.domain == SFSpeechError.errorDomain, SFSpeechError.Code(rawValue: ns.code) == .tooManyAssetLocalesAllocated
            else { throw error }
            for locale in await AssetInventory.reservedLocales { await AssetInventory.release(reservedLocale: locale) }
            return try await AssetInventory.assetInstallationRequest(supporting: [module])
        }
    }
}

// MARK: - Live transcription

/// What the transcriber reports to the session, on the main actor.
enum TranscriptionEvent: Equatable, Sendable {
    /// The words being heard now (they replace the previous volatile text).
    case volatile(String)
    /// A finished phrase with its audio times, in seconds from the start of the recording.
    case final(text: String, start: Double, end: Double)
    /// Transcription stopped by itself; recording carries on.
    case failed
}

/// The transcriber, as the lecture session sees it: `SpeechLectureTranscriber` on a device, a scripted stand-in
/// in DEBUG demos and tests.
@MainActor
protocol LectureTranscribing: AnyObject {
    /// Starts analysing and returns the listener the recorder feeds from its tap (on the audio thread).
    /// `timeOffset` is the audio already recorded, added to every time reported.
    func start(timeOffset: Double, onEvent: @escaping @MainActor (TranscriptionEvent) -> Void) async throws -> AudioListener
    /// Flushes what was heard into final results, then ends.
    func finish() async
    func cancel()
}

/// Transcribes the microphone live with `SpeechAnalyzer`: the tap's buffers are converted to the analyzer's format
/// (`FollowingConverter`) and streamed in; volatile and final results come back with their audio times. The model
/// must be installed first (`LectureSpeechModels.install`). Needs a device: the Simulator has no speech models to trust.
@MainActor
/// The course's own words (topic names, terms, answers), given to the analyzer as context so lecture jargon is
/// heard as the course spells it. Measured on macOS 26.6 with a spoken mitosis lecture: without context "interphase"
/// came out "interface" and "anaphase" "Anna faces".
enum LectureVocabulary {
    static let limit = 100

    static func apply(_ terms: [String], to analyzer: SpeechAnalyzer) async {
        guard !terms.isEmpty else { return }
        let context = AnalysisContext()
        context.contextualStrings[.general] = Array(terms.prefix(limit))
        try? await analyzer.setContext(context)
    }
}

final class SpeechLectureTranscriber: LectureTranscribing {
    let choice: TranscriptionChoice
    let vocabulary: [String]
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var isCancelled = false

    init(choice: TranscriptionChoice, vocabulary: [String] = []) {
        self.choice = choice
        self.vocabulary = vocabulary
    }

    func start(timeOffset: Double, onEvent: @escaping @MainActor (TranscriptionEvent) -> Void) async throws -> AudioListener {
        let box = SpeechModuleBox(choice)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [box.module]) else {
            throw TranscriptionError.model
        }
        let analyzer = SpeechAnalyzer(modules: [box.module])
        self.analyzer = analyzer
        await LectureVocabulary.apply(vocabulary, to: analyzer)
        do {
            try await analyzer.prepareToAnalyze(in: format)
        } catch {
            throw TranscriptionError.recognition
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.continuation = continuation
        resultsTask = Task { [weak self] in
            do {
                try await box.results { text, start, end, isFinal in
                    if isFinal {
                        onEvent(.final(text: text, start: start + timeOffset, end: end + timeOffset))
                    } else {
                        onEvent(.volatile(text))
                    }
                }
            } catch {
                if self?.isCancelled == false { onEvent(.failed) }
            }
        }
        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            cancel()
            throw TranscriptionError.recognition
        }
        return Self.listener(FollowingConverter(target: format), continuation)
    }

    func finish() async {
        guard !isCancelled else { return }
        continuation?.finish()
        continuation = nil
        if let analyzer { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
        await resultsTask?.value
        analyzer = nil
        resultsTask = nil
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        continuation?.finish()
        continuation = nil
        resultsTask?.cancel()
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
    }

    /// Converts and streams each tap buffer. Built outside the actor: it runs on the audio thread.
    nonisolated private static func listener(_ converter: FollowingConverter,
                                             _ continuation: AsyncStream<AnalyzerInput>.Continuation) -> AudioListener {
        { buffer in
            guard let converted = converter.convert(buffer) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }
}

// MARK: - A saved recording

/// Transcribes a saved recording (a lecture whose transcript was pending: the model was still downloading, or the
/// app was closed mid-lecture). The analyzer reads and converts the file itself.
enum LectureFileTranscriber {
    static func transcribe(_ url: URL, choice: TranscriptionChoice, vocabulary: [String] = []) async throws -> [TranscriptSegment] {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { throw TranscriptionError.recognition }
        let box = SpeechModuleBox(choice)
        let analyzer = SpeechAnalyzer(modules: [box.module])
        await LectureVocabulary.apply(vocabulary, to: analyzer)
        let collector = Task { () -> [TranscriptSegment] in
            var assembler = TranscriptAssembler()
            try await box.results { text, start, end, isFinal in
                if isFinal { assembler.final(text, start: start, end: end) }
            }
            return assembler.segments
        }
        do {
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
            return try await collector.value
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw TranscriptionError.recognition
        }
    }
}
