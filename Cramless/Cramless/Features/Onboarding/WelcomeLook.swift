import CoreGraphics
import Foundation

// How the welcome's sky looks and moves, as plain numbers: the faint stars, and the envelopes of a star igniting, a line drawing
// itself, the finale's glow, a ripple and the hint. Pure, so the shape of every motion is tested; `WelcomeSkyDrawing` draws them.
// The welcome is deliberately light: a few dozen faint stars, seven in the constellation, hairlines and one glow each, with no blend
// modes, shadows or offscreen layers, so it runs at the display's full rate.

enum WelcomeLook {
    /// How far the phone's tilt moves the constellation and the faint stars behind it (points at the full tilt).
    static let tiltReach = 8.0
    static let faintReach = 2.5

    static let igniteSeconds = 0.9
    static let lineSeconds = 0.5
    static let glowSeconds = 2.2
    static let shootingSeconds = 0.7
    static let rippleSeconds = 0.8
    /// The finale: the rest of the cap ignites a beat after the third star, one star every `sweepGap`.
    static let sweepDelay = 0.16
    static let sweepGap = 0.075
    /// A ring opens round the star Cap would light next, once every `hintSeconds`.
    static let hintSeconds = 2.2

    // MARK: The faint stars

    /// One of the faint stars behind the constellation.
    struct Dot: Equatable, Sendable {
        /// Where, as shares of the width and of the sky's height (0 at the top).
        var x: Double
        var y: Double
        var radius: Double
        /// Which of three slow twinkles it follows.
        var group: Int
        /// Which of three brightnesses it has (0 faintest).
        var tier: Int
    }

    /// The same stars every launch, denser high in the sky, thinner where the constellation is (so its shape reads) and gone near
    /// the horizon.
    static func starField(count: Int = 52, seed: UInt64 = 0xCA9B_7A11) -> [Dot] {
        var dice = CapDice(seed: seed)
        return (0..<count).map { k in
            let u = Double.random(in: 0..<1, using: &dice)
            let y = pow(u, 1.3) * 0.94
            let x = Double.random(in: 0..<1, using: &dice)
            let size = Double.random(in: 0..<1, using: &dice)
            let behindTheCap = (0.2...0.8).contains(x) && (0.1...0.62).contains(y)
            let tier = behindTheCap ? 0 : (size < 0.55 ? 0 : size < 0.88 ? 1 : 2)
            return Dot(x: x, y: y, radius: 0.55 + 0.35 * Double(tier) + 0.3 * size * size, group: k % 3, tier: tier)
        }
    }

    /// How a faint star shines at `time`: a slow breath, a different one for each group.
    static func twinkle(group: Int, time: Double) -> Double {
        0.84 + 0.16 * sin(2 * .pi * (time / (4.0 + 1.3 * Double(group)) + Double(group) / 3))
    }

    /// The opacity of each tier of faint stars.
    static let tierAlpha: [Double] = [0.26, 0.5, 0.78]

    /// How a dark star of the constellation breathes: steady ones slowly, the fragile ones (every third) faster and unevenly.
    static func breath(star: Int, time: Double) -> Double {
        if star % 3 == 1 {
            return 0.7 + 0.3 * sin(2 * .pi * (time * 0.7 + Double(star) / 7) + 1.2 * sin(2 * .pi * time * 0.23))
        }
        return 0.86 + 0.14 * sin(2 * .pi * (time / 3.6 + Double(star) / 7))
    }

    // MARK: Envelopes

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private static func easeOut(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }
    private static func easeInOut(_ x: Double) -> Double { let t = clamp(x); return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }

    /// A star as it ignites, `t` seconds in (a negative `t` is a star still dark).
    struct Ignition: Equatable, Sendable {
        /// The disc's size against its resting one: it swells and settles.
        var core: Double
        /// 0 dim, 1 lit.
        var brightness: Double
        /// The soft glow's opacity.
        var halo: Double
        var ringRadius: Double
        var ringAlpha: Double
        /// The four-point glint's half length, and its opacity.
        var glint: Double
        var glintAlpha: Double

        static let dark = Ignition(core: 1, brightness: 0, halo: 0, ringRadius: 0, ringAlpha: 0, glint: 0, glintAlpha: 0)
        static let settled = Ignition(core: 1, brightness: 1, halo: restingHalo, ringRadius: 0, ringAlpha: 0, glint: 0, glintAlpha: 0)
    }

    static let restingHalo = 0.44

    static func ignition(after t: Double) -> Ignition {
        guard t >= 0 else { return .dark }
        guard t < igniteSeconds else { return .settled }
        let core: Double
        if t < 0.16 {
            core = 0.7 + 0.8 * easeOut(t / 0.16)
        } else if t < 0.6 {
            core = 1.5 - 0.5 * easeInOut((t - 0.16) / 0.44)
        } else {
            core = 1
        }
        let halo = restingHalo + 0.31 * (t < 0.2 ? easeOut(t / 0.2) : 1 - easeInOut((t - 0.2) / 0.6))
        let ring = clamp(t / 0.8)
        let glint = 1 - clamp(t / 0.5)
        return Ignition(core: core, brightness: easeOut(t / 0.25), halo: halo, ringRadius: 5 + 30 * easeOut(ring),
                        ringAlpha: 0.7 * pow(1 - ring, 2), glint: 16 * glint, glintAlpha: 0.9 * glint)
    }

    /// How much of a line is drawn, `t` seconds after both its stars were lit (0 before, 1 from `lineSeconds` on).
    static func lineProgress(after t: Double) -> Double { easeInOut(t / lineSeconds) }

    /// The glow that rises behind the cap when all of it is lit: up in half a second, away over the next two.
    static func glow(after t: Double) -> Double {
        guard t >= 0, t < glowSeconds else { return 0 }
        return t < 0.5 ? 0.2 * easeOut(t / 0.5) : 0.2 * (1 - easeInOut((t - 0.5) / (glowSeconds - 0.5)))
    }

    /// How far a shooting star has crossed (0 to 1), or nil when none is crossing.
    static func shooting(after t: Double) -> Double? {
        guard t >= 0, t < shootingSeconds else { return nil }
        return t / shootingSeconds
    }

    /// A touch's ripple, `t` seconds after it, or nil once it has gone.
    static func ripple(after t: Double) -> (radius: Double, alpha: Double)? {
        guard t >= 0, t < rippleSeconds else { return nil }
        let u = t / rippleSeconds
        return (3 + 31 * easeOut(u), 0.38 * pow(1 - u, 1.5))
    }

    /// The hint's ring at `time`.
    static func hint(at time: Double) -> (radius: Double, alpha: Double) {
        let phase = (time / hintSeconds).truncatingRemainder(dividingBy: 1)
        return (7 + 16 * phase, 0.55 * pow(1 - phase, 1.5))
    }
}
