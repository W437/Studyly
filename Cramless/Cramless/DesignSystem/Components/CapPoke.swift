import Foundation

// What a tap does to Cap's body. His clip (`CapClip`, role `.poke`) does his face and paws; this does the rest, on top of it:
// the press, the spring back, the lean. It is rolled afresh on every tap, so no two feel the same, and it is a plain value, so
// it is tested like an engine. `CapView` plays it.

/// A small, seedable random source: splitmix64. Taps use the system's; tests and films pass a seed so they repeat.
struct CapDice: RandomNumberGenerator, Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The system's random source, or a seeded one: the one generator type `CapTouch` hands out.
struct CapRNG: RandomNumberGenerator, Sendable {
    private var seeded: CapDice?
    private var system = SystemRandomNumberGenerator()

    init(seed: UInt64? = nil) { seeded = seed.map(CapDice.init(seed:)) }

    mutating func next() -> UInt64 {
        if seeded != nil { return seeded!.next() }
        return system.next()
    }
}

/// How one tap squashes, stretches and rocks Cap: damped springs rooted at his feet.
///
/// Time zero is the tap. He is pressed down quickly (`ramp`), then let go, and springs back past where he was and settles:
/// the free swing of a damped spring, so the overshoot and the settling look like something with weight. His width follows
/// his height so his volume stays about the same (a squashed Cap is a wider Cap). Everything ends at rest by `duration`.
struct CapPoke: Equatable, Sendable {
    enum Style: String, CaseIterable, Sendable {
        /// Pressed down and sprung back, once, soft.
        case squish
        /// Pressed, then up in the air and back down with a second, smaller squash.
        case boing
        /// A small press and a big rock from side to side, like a jelly.
        case wobble
        /// Squeezed two or three times in a row, like a hug.
        case squeeze
        /// A quick ticklish shimmy.
        case wriggle
    }

    /// One press and its spring back.
    struct Press: Equatable, Sendable {
        /// Seconds after the tap that the press begins.
        var start: Double
        /// How far he is squashed at the bottom of it, as a fraction of his height.
        var amount: Double
        /// Seconds he takes to go down.
        var ramp: Double

        func squash(at t: Double, hertz: Double, damping: Double) -> Double {
            guard t > start, amount != 0 else { return 0 }
            let local = t - start
            if local < ramp {
                let x = local / ramp
                return amount * (1 - (1 - x) * (1 - x) * (1 - x))
            }
            return amount * CapPoke.spring(local - ramp, hertz: hertz, damping: damping)
        }
    }

    var style: Style
    var presses: [Press]
    /// The spring's speed and how quickly it dies away (0 to 1; below 1 it overshoots).
    var hertz: Double
    var damping: Double
    /// How much wider he gets as he squashes (1 keeps his volume).
    var fatness: Double
    /// The rock from his feet, in degrees (signed: which way it starts), and its speed against the spring's.
    var lean: Double
    var leanSpeed: Double
    /// A sideways shimmy as a fraction of his size (signed), and its speed against the spring's.
    var sway: Double
    var swaySpeed: Double
    /// How high he goes, as a fraction of his size, and how long he is in the air.
    var hop: Double
    var air: Double
    /// Seconds the whole thing takes.
    var duration: Double
    /// How hard it felt, 0 to 1: what the haptic follows.
    var strength: Double
    /// How quickly the whole thing plays against its usual pace: above one is faster. His reaction clip is played at the same
    /// pace, so the body and the face stay together.
    var pace: Double = 1

    /// The free response of a damped spring let go from one unit of displacement at rest: 1 at the start, swinging through
    /// zero to a stretch of about a third and dying away.
    static func spring(_ t: Double, hertz: Double, damping: Double) -> Double {
        guard t > 0 else { return 1 }
        let w = 2 * Double.pi * hertz
        let z = min(max(damping, 0.01), 0.99)
        let wd = w * (1 - z * z).squareRoot()
        return exp(-z * w * t) * (cos(wd * t) + (z * w / wd) * sin(wd * t))
    }

    /// Cap's transform `seconds` after the tap. Scales and the lean pivot on his feet; `lift` and `sway` are fractions of his
    /// size. At rest, before the tap and from `duration` on, every value is neutral.
    func frame(at seconds: Double) -> CapFrame {
        guard seconds > 0, seconds < duration else { return CapFrame() }
        let t = seconds
        // The last moments ease to exactly nothing, so a spring still ringing a hair when time runs out never ends in a pop.
        let tail = min(0.2, duration * 0.3)
        let window = t > duration - tail ? CapPoke.smooth((duration - t) / tail) : 1
        var squash = 0.0
        for press in presses { squash += press.squash(at: t, hertz: hertz, damping: damping) }
        // Springs that overlap (a squeeze, a run of hard taps) add up: this eases the total into a ceiling and a floor, and
        // leaves everything under the knee exactly as it was.
        squash = Self.limited(squash, knee: 0.18, ceiling: 0.30) * window
        var frame = CapFrame()
        let height = 1 - squash
        frame.scaleY = height
        // He is wider as he is squashed, by about half what keeping his volume exactly would ask: it reads as soft, not rubber.
        frame.scaleX = pow(height, -0.55 * fatness)
        if hop > 0, let first = presses.first {
            let u = (t - first.start - first.ramp) / air
            if u > 0, u < 1 { frame.lift = hop * 4 * u * (1 - u) * window }
        }
        if lean != 0 {
            let w = 2 * Double.pi * hertz * leanSpeed
            let z = min(damping * 0.8, 0.9)
            frame.tilt = lean * exp(-z * w * t) * sin(w * t) * window
        }
        if sway != 0 {
            let w = 2 * Double.pi * hertz * swaySpeed
            let z = min(damping * 0.9, 0.9)
            frame.sway = sway * exp(-z * w * t) * sin(w * t) * window
        }
        return frame
    }

    /// `x` unchanged up to `knee` (a stretch, below zero, uses a third of it), then eased toward `ceiling` and never past it.
    static func limited(_ x: Double, knee: Double, ceiling: Double) -> Double {
        if x < 0 { return -limited(-x, knee: knee * 0.55, ceiling: ceiling * 0.6) }
        guard x > knee else { return x }
        let room = ceiling - knee
        return knee + room * tanh((x - knee) / room)
    }

    private static func smooth(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    // MARK: Rolling one

    /// How a pose takes being tapped: a sleeper is nudged, a cheerer bounces.
    enum Mood: Sendable {
        case drowsy, calm, lively

        init(_ pose: CapPose) {
            switch pose {
            case .sleep, .sleepy, .tuckIn, .relax: self = .drowsy
            case .wave, .celebrate, .nice, .point, .ask, .proud: self = .lively
            default: self = .calm
            }
        }

        var energy: Double {
            switch self {
            case .drowsy: 0.7
            case .calm: 0.92
            case .lively: 1.08
            }
        }

        /// Style odds, in the order of `Style.allCases`: squish, boing, wobble, squeeze, wriggle.
        var odds: [Double] {
            switch self {
            case .drowsy: [0.55, 0, 0.15, 0.30, 0]
            case .calm: [0.34, 0.10, 0.24, 0.20, 0.12]
            case .lively: [0.20, 0.34, 0.18, 0.10, 0.18]
            }
        }
    }

    /// A fresh poke for `pose`. `rapid` counts taps in a quick run (1 is a single tap): each one a little stronger and quicker,
    /// up to a point, and a long run turns into a shimmy.
    static func roll<G: RandomNumberGenerator>(for pose: CapPose, rapid: Int = 1, using g: inout G) -> CapPoke {
        let mood = Mood(pose)
        let run = Double(min(max(rapid - 1, 0), 5))
        let excite = 1 + 0.06 * run
        let style = rapid >= 6 ? Style.wriggle : pick(mood.odds, using: &g)
        let energy = mood.energy * excite
        let tempo = Double.random(in: 0.9...1.12, using: &g) / (1 + 0.03 * run)
        let hertz = Double.random(in: 2.0...3.0, using: &g) / tempo
        let side: Double = Bool.random(using: &g) ? 1 : -1

        var poke = CapPoke(style: style, presses: [], hertz: hertz, damping: Double.random(in: 0.17...0.30, using: &g),
                           fatness: Double.random(in: 0.85...1.2, using: &g), lean: 0, leanSpeed: 0.9,
                           sway: 0, swaySpeed: 1.3, hop: 0, air: 0.34, duration: 0, strength: 0)
        let ramp = Double.random(in: 0.055...0.085, using: &g)
        let press = Double.random(in: 0.10...0.20, using: &g) * energy
        switch style {
        case .squish:
            poke.presses = [Press(start: 0, amount: press, ramp: ramp)]
            poke.lean = side * Double.random(in: 1.5...4.5, using: &g)
        case .boing:
            poke.presses = [Press(start: 0, amount: press * 0.9, ramp: ramp)]
            poke.hop = Double.random(in: 0.07...0.15, using: &g) * energy
            poke.air = Double.random(in: 0.30...0.40, using: &g) / tempo
            poke.damping = Double.random(in: 0.16...0.24, using: &g)
            poke.presses.append(Press(start: ramp + poke.air, amount: press * Double.random(in: 0.45...0.65, using: &g), ramp: 0.05))
            poke.lean = side * Double.random(in: 1.0...3.0, using: &g)
        case .wobble:
            poke.presses = [Press(start: 0, amount: press * 0.45, ramp: ramp)]
            poke.lean = side * Double.random(in: 5.5...9.5, using: &g) * min(energy, 1.15)
            poke.leanSpeed = Double.random(in: 0.75...0.95, using: &g)
            poke.damping = Double.random(in: 0.13...0.2, using: &g)
        case .squeeze:
            let beat = Double.random(in: 0.20...0.26, using: &g) / tempo
            poke.presses = [Press(start: 0, amount: press, ramp: ramp),
                            Press(start: beat, amount: press * 0.7, ramp: ramp),
                            Press(start: beat * 2, amount: press * 0.4, ramp: ramp)]
            poke.damping = Double.random(in: 0.22...0.34, using: &g)
            poke.fatness = Double.random(in: 1.05...1.3, using: &g)
        case .wriggle:
            poke.presses = [Press(start: 0, amount: press * 0.4, ramp: ramp)]
            poke.sway = side * Double.random(in: 0.018...0.032, using: &g)
            poke.swaySpeed = Double.random(in: 1.9...2.4, using: &g)
            poke.lean = -side * Double.random(in: 2.0...3.5, using: &g)
            poke.leanSpeed = poke.swaySpeed * 0.9
            poke.damping = Double.random(in: 0.14...0.2, using: &g)
        }
        poke.strength = min(1, max(0, (poke.presses.map(\.amount).max() ?? 0) / 0.26))
        poke.pace = 1 / tempo
        poke.duration = poke.settleTime()
        return poke
    }

    /// When every part has died away to under half a percent, with a floor of half a second and a ceiling of 1.7 s (the last
    /// moments ease out in `frame(at:)`).
    func settleTime() -> Double {
        let decay = 5.3
        let spring = decay / (min(max(damping, 0.01), 0.99) * 2 * Double.pi * hertz)
        var end = (presses.map { $0.start + $0.ramp }.max() ?? 0) + spring
        if lean != 0 { end = max(end, decay / (min(damping * 0.8, 0.9) * 2 * Double.pi * hertz * leanSpeed)) }
        if sway != 0 { end = max(end, decay / (min(damping * 0.9, 0.9) * 2 * Double.pi * hertz * swaySpeed)) }
        return min(1.7, max(0.5, end))
    }

    private static func pick<G: RandomNumberGenerator>(_ odds: [Double], using g: inout G) -> Style {
        let total = odds.reduce(0, +)
        var roll = Double.random(in: 0..<total, using: &g)
        for (style, weight) in zip(Style.allCases, odds) {
            if roll < weight { return style }
            roll -= weight
        }
        return .squish
    }
}
