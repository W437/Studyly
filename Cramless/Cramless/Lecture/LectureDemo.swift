#if DEBUG
import AVFoundation
import Foundation

// DEBUG stand-ins so the Simulator and the screenshot harness can show a lecture being recorded: a "microphone"
// that only moves the level meter, and a transcriber that replays Lecture 6 word by word. Used when
// `CRAMLESS_UITEST=1` (the harness) or `CRAMLESS_FAKE_LECTURE=1`; the status line says it's a demo.
// `CRAMLESS_LECTURE_PREFILL=<n>` shows the first n lines at once; `CRAMLESS_LECTURE_ELAPSED=<seconds>` starts
// the clock part-way through (the prototype's 12:41).

extension LecturePorts {
    static func demo(prefill: Int = 0, startOffset: Double = 0, wordInterval: Duration = .milliseconds(170),
                     linePause: Duration = .milliseconds(1100)) -> LecturePorts {
        LecturePorts(
            makeAudio: { DemoLectureAudio() },
            availability: { .available(TranscriptionChoice(identifier: "en-US", backend: .speech, status: .installed)) },
            makeTranscriber: { _, clock in
                ScriptedLectureTranscriber(clock: clock, prefill: prefill, wordInterval: wordInterval, linePause: linePause)
            },
            install: { _, _ in },
            isDemo: true,
            startOffset: startOffset)
    }
}

/// Lecture playback with no audio, for the seeded lecture: the clock runs at the chosen speed and nothing is heard.
@MainActor
final class DemoLecturePlayback: LecturePlayback {
    var onEvent: ((LecturePlaybackEvent) -> Void)?
    private let duration: Double
    private var anchor: Double = 0
    private var rate: Double = 1
    private var startedAt: ContinuousClock.Instant?

    init(duration: Double) { self.duration = duration }

    private var now: Double {
        anchor + (startedAt?.duration(to: .now).timeInterval ?? 0) * rate
    }

    func position() async -> Double { min(now, duration) }

    func play(from seconds: Double, rate: Double) {
        anchor = seconds
        self.rate = rate
        startedAt = .now
    }

    func seek(to seconds: Double) {
        anchor = seconds
        if startedAt != nil { startedAt = .now }
    }

    func pause() {
        anchor = now
        startedAt = nil
    }

    func setRate(_ rate: Double) {
        anchor = now
        if startedAt != nil { startedAt = .now }
        self.rate = rate
    }

    func close(releasingSession: Bool) { pause() }

    func publish(_ info: LecturePlayer.NowPlaying) {}
}

/// A microphone that records nothing: it moves the level meter like speech and counts the time.
@MainActor
final class DemoLectureAudio: LectureAudioCapturing {
    var onLevel: ((Float) -> Void)?
    var onInterruption: ((LectureInterruption) -> Void)?
    private var task: Task<Void, Never>?
    private var accumulated: Double = 0
    private var resumedAt: ContinuousClock.Instant?

    var recordedSeconds: Double { accumulated + (resumedAt?.duration(to: .now).timeInterval ?? 0) }

    func start(sourceID: UUID, listener: AudioListener?) async throws { run() }

    func pause() {
        accumulated = recordedSeconds
        resumedAt = nil
        task?.cancel()
    }

    func resume() throws { run() }

    func stop() async -> RecordedAudio {
        pause()
        return RecordedAudio(fileName: nil, duration: accumulated)
    }

    func cancel() { pause() }

    private func run() {
        resumedAt = .now
        task?.cancel()
        task = Task { [weak self] in
            var phase = 0.0
            while !Task.isCancelled {
                phase += 0.37
                // Syllable-ish bursts with breaths between phrases.
                let envelope = 0.55 + 0.45 * sin(phase * 0.21)
                let level = max(0.05, 0.25 + 0.5 * abs(sin(phase)) * envelope)
                self?.onLevel?(Float(level))
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
    }
}

/// Replays a lecture's lines as if they were being heard: volatile words one at a time, then the final line
/// stamped with the session's clock.
@MainActor
final class ScriptedLectureTranscriber: LectureTranscribing {
    /// Lecture 6 of the demo world (the same lines `SampleData` seeds; a test keeps them equal).
    nonisolated static let sampleLecture = [
        "OK, so last time we finished interphase. Today: what actually happens when the cell divides.",
        "Prophase first. The chromatin condenses, and you can finally see chromosomes under the microscope.",
        "Then the nuclear envelope breaks down and the spindle starts forming from the centrosomes.",
        "Metaphase is the easy one to spot: everything lines up along the middle, the metaphase plate.",
        "This one will be on the midterm, by the way: anaphase is where the sister chromatids get pulled apart.",
        "And telophase is basically prophase in reverse. The nuclear envelopes re-form around each set.",
    ]

    private let clock: @MainActor () -> Double
    private let lines: [String]
    private let prefill: Int
    private let wordInterval: Duration
    private let linePause: Duration
    private var task: Task<Void, Never>?
    private var onEvent: (@MainActor (TranscriptionEvent) -> Void)?
    private var partial: (words: [String], start: Double)?
    private var lastClock: Double = -1

    init(clock: @escaping @MainActor () -> Double, lines: [String] = sampleLecture, prefill: Int = 0,
         wordInterval: Duration = .milliseconds(170), linePause: Duration = .milliseconds(1100)) {
        self.clock = clock
        self.lines = lines
        self.prefill = prefill
        self.wordInterval = wordInterval
        self.linePause = linePause
    }

    func start(timeOffset: Double, onEvent: @escaping @MainActor (TranscriptionEvent) -> Void) async throws -> AudioListener {
        self.onEvent = onEvent
        task = Task { [weak self] in await self?.play(from: timeOffset) }
        return { _ in }
    }

    private func play(from offset: Double) async {
        // Lines shown at once sit before the clock's start, ten seconds apart.
        let shown = min(prefill, lines.count)
        for (index, line) in lines.prefix(shown).enumerated() {
            let start = max(0, offset - Double(shown - index) * 10)
            onEvent?(.final(text: line, start: start, end: start + 8))
        }
        for line in lines.dropFirst(shown) {
            let words = line.split(separator: " ").map(String.init)
            await waitWhilePaused()
            partial = ([], clock())
            for word in words {
                await waitWhilePaused()
                guard !Task.isCancelled else { return }
                partial?.words.append(word)
                onEvent?(.volatile(partial?.words.joined(separator: " ") ?? ""))
                try? await Task.sleep(for: wordInterval)
            }
            guard !Task.isCancelled else { return }
            onEvent?(.final(text: line, start: partial?.start ?? clock(), end: clock()))
            partial = nil
            try? await Task.sleep(for: linePause)
        }
    }

    /// The session's clock stands still while it's paused; nobody is heard then. (While recording the clock has
    /// always moved since the last word, so this returns at once.)
    private func waitWhilePaused() async {
        while !Task.isCancelled {
            let now = clock()
            if now != lastClock {
                lastClock = now
                return
            }
            try? await Task.sleep(for: .milliseconds(60))
        }
    }

    /// Like the real engine's flush: what was being heard becomes a final line.
    func finish() async {
        task?.cancel()
        task = nil
        if let partial, !partial.words.isEmpty {
            onEvent?(.final(text: partial.words.joined(separator: " "), start: partial.start, end: clock()))
        }
        partial = nil
        onEvent = nil
    }

    func cancel() {
        task?.cancel()
        task = nil
        partial = nil
        onEvent = nil
    }
}
#endif
