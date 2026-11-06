#if DEBUG
import Foundation

// DEBUG stand-ins so the Simulator and the screenshot harness can show Study out loud and Teach Cap with no microphone and no speech model. The listener
// "hears" a script, word by word; the speaker takes as long as the words would. Neither makes a sound.

/// Takes as long as the words would, in silence, and can hold (a screenshot of Cap mid-sentence). The lines it was given are kept, for tests.
@MainActor
final class ScriptedSpeaker: SpokenSpeaking {
    private(set) var said: [String] = []
    private let secondsPerWord: Double
    /// Holds on this line (1 is the first), until stopped.
    private let holdsOnLine: Int?
    private var stopped = false

    init(secondsPerWord: Double = 0.05, holdsOnLine: Int? = nil) {
        self.secondsPerWord = secondsPerWord
        self.holdsOnLine = holdsOnLine
    }

    func say(_ text: String, language: String?) async {
        said.append(text)
        stopped = false
        if said.count == holdsOnLine {
            while !stopped, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
            return
        }
        let words = text.split(separator: " ").count
        let seconds = Double(words) * secondsPerWord
        guard seconds > 0 else { return }
        try? await Task.sleep(for: .seconds(seconds))
    }

    func stop() { stopped = true }
}

/// "Hears" what `script` says for each turn, a word at a time. Nil from the script: no answer comes, and the turn waits until it is stopped.
@MainActor
final class ScriptedSpokenListener: SpokenListening {
    var onLevel: ((Float) -> Void)?
    var onInterruption: ((LectureInterruption) -> Void)?

    private let script: @MainActor (SpokenTurn) -> String?
    private let wordInterval: Duration
    /// Fails `prepare` with this (the no-model state).
    private let failure: SpokenListenerFailure?
    /// After its words the turn stays open, until it's stopped (a screenshot of the microphone on).
    private let holdsAfterWords: Bool
    private var stopped = false

    init(failure: SpokenListenerFailure? = nil, wordInterval: Duration = .milliseconds(110), holdsAfterWords: Bool = false,
         script: @escaping @MainActor (SpokenTurn) -> String?) {
        self.failure = failure
        self.wordInterval = wordInterval
        self.holdsAfterWords = holdsAfterWords
        self.script = script
    }

    func prepare(progress: @escaping @MainActor (Double) -> Void) async throws {
        if let failure { throw failure }
    }

    func listen(_ turn: SpokenTurn, onWords: @escaping @MainActor (String) -> Void) async -> SpokenHearing {
        stopped = false
        guard let words = script(turn) else {
            while !stopped, !Task.isCancelled {
                onLevel?(Float.random(in: 0.05...0.15))
                try? await Task.sleep(for: .milliseconds(100))
            }
            return SpokenHearing(text: "", ending: .stopped)
        }
        var heard: [String] = []
        for word in words.split(separator: " ").map(String.init) {
            if stopped || Task.isCancelled { break }
            heard.append(word)
            onWords(heard.joined(separator: " "))
            onLevel?(Float.random(in: 0.35...0.8))
            try? await Task.sleep(for: wordInterval)
        }
        while holdsAfterWords, !stopped, !Task.isCancelled {
            onLevel?(Float.random(in: 0.05...0.5))
            try? await Task.sleep(for: .milliseconds(100))
        }
        onLevel?(0)
        return SpokenHearing(text: heard.joined(separator: " "), ending: stopped ? .stopped : .silence, seconds: 3)
    }

    func stopListening() { stopped = true }
    func suspend() { stopped = true }
    func resume() throws {}
    func close() { stopped = true }
}
#endif
