import Foundation

/// When a spoken answer is over. Pure: it is told when words came and what the level was, on a clock of seconds since the turn opened, and
/// says whether the turn has ended and why. `SpokenAnswerListener` asks it about ten times a second.
///
/// Speech is what the recogniser hears (new words), or sound well above the place's own noise: the floor follows the quietest level lately,
/// so a loud bus isn't taken for someone talking, and a person talking over it still is. The recogniser's words lag behind the voice by
/// a moment; the level is what stops a pause being declared while the first words are still on their way.
struct SpeechEndpoint: Sendable, Equatable {
    struct Config: Sendable, Equatable {
        /// This long without speech, once there has been some, ends the turn. Nil: only the cap or the person ends it.
        var silence: Double? = 1.5
        /// The longest a turn lasts.
        var cap: Double = 45
        /// This long with no speech at all ends the turn as `noSpeech`: time to think, on a walk. Nil: wait for the cap.
        var noSpeech: Double? = 15

        /// An answer to a question.
        static let answer = Config()
        /// A short reply: "got it", "again".
        static let reply = Config(silence: 1.0, cap: 15, noSpeech: 7)
        /// Explaining a topic to Cap: it goes on until the person says Done, for two minutes at most.
        static let teaching = Config(silence: nil, cap: 120, noSpeech: nil)
    }

    enum Ending: Sendable, Equatable {
        case silence, cap, noSpeech
    }

    /// How far above the floor a level counts as a voice: the level is 0…1 over 60 dB, so this is 15 dB.
    static let voiceAboveFloor: Float = 0.25
    /// How fast the floor rises towards a steady noise, per reading (it falls at once).
    static let floorRise: Float = 0.015

    let config: Config
    private(set) var lastSpeech: Double?
    private var floor: Float?

    init(_ config: Config = .answer) { self.config = config }

    var hasHeardSpeech: Bool { lastSpeech != nil }

    /// New words came from the recogniser.
    mutating func heardWords(at time: Double) {
        lastSpeech = max(lastSpeech ?? time, time)
    }

    /// An input level, 0…1.
    mutating func level(_ level: Float, at time: Double) {
        guard let current = floor else {
            floor = level
            return
        }
        if level > current + Self.voiceAboveFloor { lastSpeech = max(lastSpeech ?? time, time) }
        floor = level < current ? level : current + Self.floorRise
    }

    /// Whether the turn is over at `time`.
    func ending(at time: Double) -> Ending? {
        if time >= config.cap { return .cap }
        if let last = lastSpeech {
            if let silence = config.silence, time - last >= silence { return .silence }
            return nil
        }
        if let noSpeech = config.noSpeech, time >= noSpeech { return .noSpeech }
        return nil
    }
}

/// The words of one turn: what is settled, and what is still being heard. A volatile result replaces the one before it.
struct HeardWords: Sendable, Equatable {
    private(set) var finals: [String] = []
    private(set) var volatile = ""

    /// Everything said so far.
    var text: String {
        (finals + (volatile.isEmpty ? [] : [volatile])).joined(separator: " ")
    }

    var isEmpty: Bool { text.isEmpty }

    /// Returns whether anything changed.
    @discardableResult
    mutating func volatile(_ words: String) -> Bool {
        let clean = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean != volatile else { return false }
        volatile = clean
        return true
    }

    mutating func final(_ words: String) {
        let clean = words.trimmingCharacters(in: .whitespacesAndNewlines)
        volatile = ""
        if !clean.isEmpty { finals.append(clean) }
    }
}
