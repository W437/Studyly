import Foundation

// Capling's sounds, synthesized: there are no audio files. A palette is a handful of numbers (the partials of a
// struck bar, how fast each dies away, how hard the mallet hits), and every cue is a few notes played on it.
// Pure and deterministic (the mallet noise is seeded), so tests pin the output, the audition script renders the
// same samples the app plays, and films are scored with them. Foundation only: `scripts/sound_audition` compiles
// this file on the Mac.

/// A moment with a sound and the haptic paired with it. `CLFeel.play(_:)` is the only way to play one.
enum CLCue: Hashable, Sendable {
    /// A right answer. `combo` is the run it makes (1 for the first right answer in a row); each step of a run
    /// plays the next note up the scale, holding at the top from eight on.
    case right(combo: Int)
    case almost
    case notYet
    /// "Here's the answer": the answer shown after "I don't know".
    case revealed
    case flip
    /// A flashcard rated.
    case rated
    /// "Saved it": a fading memory answered right.
    case saved
    /// 5, 10 and 15 in a row.
    case flourish
    /// A session finished.
    case done
    /// The nth question card flying out of a scanned page.
    case cardOut(Int)
    case listenOn
    case listenOff
    /// The exam-eve finale.
    case goodnight

    /// A stable name for logs and files: "right3", "notYet", "cardOut2".
    var key: String {
        switch self {
        case .right(let combo): "right\(CLSynth.scaleStep(combo) + 1)"
        case .almost: "almost"
        case .notYet: "notYet"
        case .revealed: "revealed"
        case .flip: "flip"
        case .rated: "rated"
        case .saved: "saved"
        case .flourish: "flourish"
        case .done: "done"
        case .cardOut(let n): "cardOut\(max(0, n) % CLSynth.scale.count)"
        case .listenOn: "listenOn"
        case .listenOff: "listenOff"
        case .goodnight: "goodnight"
        }
    }

    /// The cue a `key` names (the cue log, the audition files).
    init?(key: String) {
        func number(after prefix: String) -> Int? {
            key.hasPrefix(prefix) ? Int(key.dropFirst(prefix.count)) : nil
        }
        if let n = number(after: "right") {
            self = .right(combo: n)
        } else if let n = number(after: "cardOut") {
            self = .cardOut(n)
        } else if let cue = Self.all.first(where: { $0.key == key }) {
            self = cue
        } else {
            return nil
        }
    }

    /// Every distinct sound, in the order the Feel lab lists them.
    static let all: [CLCue] = (1...CLSynth.scale.count).map { .right(combo: $0) }
        + [.almost, .notYet, .revealed, .flip, .rated, .saved, .flourish, .done]
        + (0..<CLSynth.scale.count).map { .cardOut($0) }
        + [.listenOn, .listenOff, .goodnight]
}

struct CLSynth: Sendable {
    /// One partial of a struck bar: a multiple of the note's frequency, its loudness, and the seconds it takes to
    /// fall to 1/e.
    struct Partial: Sendable, Equatable {
        var ratio: Double
        var amplitude: Double
        var decay: Double
    }

    struct Palette: Sendable, Equatable, Identifiable {
        var id: String
        var name: String
        var partials: [Partial]
        /// Seconds to full level (0 is a hard mallet).
        var attack: Double
        /// The mallet's click: noise level at the hit and the seconds it lasts.
        var strike: Double
        var strikeDecay: Double
        /// How long each note rings before its fade.
        var length: Double
        var gain: Double
    }

    struct Note: Sendable, Equatable {
        var time: Double
        var frequency: Double
        var velocity: Double = 1
        /// Below 1 the note is muted: every partial dies away faster.
        var damp: Double = 1
        var length: Double?
    }

    /// A cue as notes, with its level and the feel of its haptic.
    struct Score: Sendable, Equatable {
        var notes: [Note]
        /// Peak level relative to the loudest cue.
        var gain: Double
        /// Haptic sharpness, 0 (dull) to 1 (crisp).
        var sharpness: Double
        /// Seconds of a soft continuous haptic under the taps (0 for none).
        var swell: Double = 0
    }

    static let sampleRate: Double = 44_100
    /// Peak level of the loudest cue: −3 dBFS.
    static let ceiling = 0.708

    /// C major pentatonic, C5 to E6: the steps a run of right answers climbs.
    static let scale: [Double] = [523.25, 587.33, 659.25, 783.99, 880.00, 1046.50, 1174.66, 1318.51]

    static func scaleStep(_ combo: Int) -> Int { min(max(combo, 1), scale.count) - 1 }

    private enum Pitch {
        static let c4 = 261.63, d4 = 293.66, g4 = 392.00, a4 = 440.00
        static let c5 = 523.25, e5 = 659.25, g5 = 783.99
        static let c6 = 1046.50, d6 = 1174.66, e6 = 1318.51, g6 = 1567.98, c7 = 2093.00
    }

    static func score(for cue: CLCue) -> Score {
        typealias N = Note
        switch cue {
        case .right(let combo):
            let step = scaleStep(combo)
            return Score(notes: [N(time: 0, frequency: scale[step])], gain: 0.64 + 0.03 * Double(step),
                         sharpness: 0.38 + 0.05 * Double(step))
        case .almost:
            return Score(notes: [N(time: 0, frequency: Pitch.a4), N(time: 0.11, frequency: Pitch.g4, velocity: 0.8)],
                         gain: 0.55, sharpness: 0.15)
        case .notYet:
            return Score(notes: [N(time: 0, frequency: Pitch.d4, damp: 0.55, length: 0.45),
                                 N(time: 0.12, frequency: Pitch.c4, velocity: 0.85, damp: 0.5, length: 0.5)],
                         gain: 0.5, sharpness: 0.08)
        case .revealed:
            return Score(notes: [N(time: 0, frequency: Pitch.e5), N(time: 0.1, frequency: Pitch.c5, velocity: 0.8)],
                         gain: 0.5, sharpness: 0.25)
        case .flip:
            return Score(notes: [N(time: 0, frequency: Pitch.c7, damp: 0.25, length: 0.25)], gain: 0.3, sharpness: 0.9)
        case .rated:
            return Score(notes: [N(time: 0, frequency: Pitch.c5, damp: 0.7)], gain: 0.45, sharpness: 0.4)
        case .saved:
            return Score(notes: [N(time: 0, frequency: Pitch.c5, velocity: 0.7),
                                 N(time: 0.05, frequency: Pitch.e6, velocity: 0.8, damp: 0.8),
                                 N(time: 0.10, frequency: Pitch.g6, velocity: 0.9, damp: 0.8),
                                 N(time: 0.15, frequency: Pitch.c7, damp: 0.8)],
                         gain: 0.8, sharpness: 0.8)
        case .flourish:
            return Score(notes: [N(time: 0, frequency: Pitch.c5, velocity: 0.85),
                                 N(time: 0.045, frequency: Pitch.e5, velocity: 0.9),
                                 N(time: 0.09, frequency: Pitch.g5, velocity: 0.95),
                                 N(time: 0.135, frequency: Pitch.c6)],
                         gain: 0.85, sharpness: 0.6)
        case .done:
            return Score(notes: [N(time: 0, frequency: Pitch.c5, velocity: 0.8),
                                 N(time: 0.08, frequency: Pitch.g5, velocity: 0.85),
                                 N(time: 0.16, frequency: Pitch.c6, velocity: 0.9),
                                 N(time: 0.24, frequency: Pitch.e6, length: 1.6)],
                         gain: 0.9, sharpness: 0.5, swell: 0.35)
        case .cardOut(let n):
            return Score(notes: [N(time: 0, frequency: scale[max(0, n) % scale.count], damp: 0.6)],
                         gain: 0.4, sharpness: 0.7)
        case .listenOn:
            return Score(notes: [N(time: 0, frequency: Pitch.g5), N(time: 0.08, frequency: Pitch.c6)],
                         gain: 0.45, sharpness: 0.5)
        case .listenOff:
            return Score(notes: [N(time: 0, frequency: Pitch.c6), N(time: 0.08, frequency: Pitch.g5, velocity: 0.9)],
                         gain: 0.4, sharpness: 0.4)
        case .goodnight:
            return Score(notes: [N(time: 0, frequency: Pitch.e6), N(time: 0.24, frequency: Pitch.d6, velocity: 0.92),
                                 N(time: 0.48, frequency: Pitch.c6, velocity: 0.85, length: 1.6)],
                         gain: 0.5, sharpness: 0.15)
        }
    }

    var palette: Palette

    /// Mono samples at `sampleRate`, peaking at `ceiling × score.gain × palette.gain`. Each partial is a rotating
    /// phasor with a per-sample decay factor (two multiplies a sample instead of `sin` and `exp`), so a whole
    /// palette renders in milliseconds.
    func render(_ score: Score) -> [Float] {
        let sr = Self.sampleRate
        let lengths = score.notes.map { $0.length ?? palette.length }
        let end = zip(score.notes, lengths).map { $0.time + $1 }.max() ?? 0
        let count = Int((end + 0.01) * sr)
        guard count > 0 else { return [] }
        var mix = [Double](repeating: 0, count: count)
        var noise = SeededNoise(seed: 0x5eed_cafe)
        let fadeLength = Int(0.03 * sr)
        for (note, length) in zip(score.notes, lengths) {
            let start = Int((note.time * sr).rounded())
            let frames = min(Int(length * sr), count - start)
            guard frames > 0 else { continue }
            // Partials above the audible band are dropped rather than folded back.
            let partials = palette.partials.filter { note.frequency * $0.ratio < sr * 0.45 }
            var re = [Double](repeating: 1, count: partials.count)
            var im = [Double](repeating: 0, count: partials.count)
            var level = partials.map { $0.amplitude }
            let rotCos = partials.map { cos(2 * .pi * note.frequency * $0.ratio / sr) }
            let rotSin = partials.map { sin(2 * .pi * note.frequency * $0.ratio / sr) }
            let fall = partials.map { exp(-1 / (max(0.001, $0.decay * note.damp) * sr)) }
            var click = palette.strike
            let clickFall = exp(-1 / (max(0.0005, palette.strikeDecay) * sr))
            let attackFrames = palette.attack * sr
            for i in 0..<frames {
                var s = 0.0
                for k in 0..<partials.count {
                    s += level[k] * im[k]
                    let r = re[k] * rotCos[k] - im[k] * rotSin[k]
                    im[k] = re[k] * rotSin[k] + im[k] * rotCos[k]
                    re[k] = r
                    level[k] *= fall[k]
                }
                if click > 1e-5 {
                    s += click * noise.next()
                    click *= clickFall
                }
                var envelope = attackFrames > 0 ? min(1, Double(i) / attackFrames) : 1
                if i >= frames - fadeLength { envelope *= Double(frames - i) / Double(fadeLength) }
                mix[start + i] += note.velocity * envelope * s
            }
        }
        let peak = mix.reduce(0) { max($0, abs($1)) }
        guard peak > 0 else { return mix.map(Float.init) }
        // A gentle soft clip where notes pile up, then the cue's level.
        let drive = 1.3
        let target = Self.ceiling * score.gain * palette.gain / tanh(drive)
        return mix.map { Float(tanh(drive * $0 / peak) * target) }
    }

    func render(_ cue: CLCue) -> [Float] { render(Self.score(for: cue)) }

    /// Several cues at their times, mixed (the audition's session, a film's soundtrack).
    func mix(_ events: [(time: Double, cue: CLCue)]) -> [Float] {
        let rendered = events.map { (start: Int(($0.time * Self.sampleRate).rounded()), samples: render($0.cue)) }
        let count = rendered.map { $0.start + $0.samples.count }.max() ?? 0
        var out = [Float](repeating: 0, count: count)
        for r in rendered {
            for (i, s) in r.samples.enumerated() { out[r.start + i] += s }
        }
        let peak = out.reduce(Float(0)) { max($0, abs($1)) }
        if peak > Float(Self.ceiling) {
            let scale = Float(Self.ceiling) / peak
            for i in out.indices { out[i] *= scale }
        }
        return out
    }

    /// Thirty seconds of a session: a run climbing, an almost, a run to five with its flourish, a miss and the
    /// answer, a save, a rated card, the finish. The Feel lab plays it; the audition renders it.
    static let sampleSession: [(time: Double, cue: CLCue)] = [
        (0.6, .right(combo: 1)), (3.0, .right(combo: 2)), (5.2, .right(combo: 3)), (7.8, .almost),
        (10.4, .right(combo: 1)), (12.6, .right(combo: 2)), (14.7, .right(combo: 3)), (16.9, .right(combo: 4)),
        (19.0, .right(combo: 5)), (19.2, .flourish), (21.8, .notYet), (23.0, .revealed), (25.2, .saved),
        (27.1, .flip), (28.0, .rated), (29.6, .done),
    ]

    /// 16-bit PCM WAV of mono samples.
    static func wav(_ samples: [Float], sampleRate: Double = sampleRate) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + bytes); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(bytes)
        for s in samples { append(Int16((max(-1, min(1, s)) * 32_767).rounded())) }
        return data
    }
}

extension CLSynth.Palette {
    /// A marimba: wooden bars, the overtones of a tuned bar (1 : 3.93 : 9.2), quick to fade.
    static let marimba = CLSynth.Palette(
        id: "marimba", name: "Marimba",
        partials: [.init(ratio: 1, amplitude: 1, decay: 0.42), .init(ratio: 3.93, amplitude: 0.32, decay: 0.11),
                   .init(ratio: 9.2, amplitude: 0.1, decay: 0.045)],
        attack: 0.002, strike: 0.22, strikeDecay: 0.004, length: 0.9, gain: 0.95)

    /// A kalimba: metal tines with a long ring and a bright, short overtone.
    static let kalimba = CLSynth.Palette(
        id: "kalimba", name: "Kalimba",
        partials: [.init(ratio: 1, amplitude: 1, decay: 0.85), .init(ratio: 5.4, amplitude: 0.22, decay: 0.07),
                   .init(ratio: 2, amplitude: 0.08, decay: 0.35)],
        attack: 0.0015, strike: 0.18, strikeDecay: 0.003, length: 1.4, gain: 0.9)

    /// Glass: a soft attack and long, airy overtones, like a tapped wine glass.
    static let glass = CLSynth.Palette(
        id: "glass", name: "Glass",
        partials: [.init(ratio: 1, amplitude: 1, decay: 1.1), .init(ratio: 2.76, amplitude: 0.28, decay: 0.5),
                   .init(ratio: 5.4, amplitude: 0.12, decay: 0.22)],
        attack: 0.012, strike: 0, strikeDecay: 0.001, length: 1.8, gain: 0.85)

    static let all: [CLSynth.Palette] = [.marimba, .kalimba, .glass]

    /// The palette the app plays until the owner picks one from the audition.
    static let standard: CLSynth.Palette = .marimba

    static func named(_ id: String) -> CLSynth.Palette? { all.first { $0.id == id } }
}

/// xorshift64*: the mallet noise, the same on every render.
struct SeededNoise: Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9e37_79b9_7f4a_7c15 : seed }

    /// Uniform in [-1, 1).
    mutating func next() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let value = state &* 0x2545_f491_4f6c_dd1d
        return Double(value >> 11) * 0x1.0p-52 - 1
    }
}
