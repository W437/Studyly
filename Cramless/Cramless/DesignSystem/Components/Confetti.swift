import SwiftUI

/// Confetti for a celebration (`CelebrationPolicy`): paper pieces in the course colours, Sun twice as often, bursting
/// out, fluttering down and stopping when they're done. The field is seeded, so a celebration replays exactly in a
/// film. Under Reduce Motion there's none at all.
struct ConfettiField: Sendable {
    enum Burst: Sendable, Equatable {
        /// A handful puffing up from a point (in unit coordinates of the screen): `small`.
        case puff(CGPoint)
        /// A burst from a point: `medium`.
        case burst(CGPoint)
        /// Two cannons from the bottom corners, across the whole screen: `big`.
        case cannons
    }

    struct Piece: Sendable, Equatable {
        /// Where it starts, in unit coordinates.
        var origin: CGPoint
        /// Points per second; negative `dy` is up.
        var velocity: CGVector
        var delay: Double
        var width: Double
        var height: Double
        var angle: Double
        /// Radians per second in the plane of the screen.
        var spin: Double
        /// Turns per second of the paper flipping over.
        var flip: Double
        var phase: Double
        /// Side-to-side drift, in points, once the burst has slowed.
        var sway: Double
        /// An index into the palette.
        var colour: Int
    }

    /// A piece at a moment: its centre in points, its angle, how far it has turned over (−1…1, negative shows the
    /// back) and its opacity.
    struct Spot: Equatable {
        var x: Double
        var y: Double
        var angle: Double
        var turn: Double
        var opacity: Double
    }

    let pieces: [Piece]
    /// Seconds from the burst until the last piece has gone.
    let duration: Double
    /// How long each piece lives once launched.
    let life: Double

    /// Air drag per second, and gravity in points per second squared: pieces fall at about 315 pt/s at most.
    static let drag = 2.6
    static let gravity = 820.0
    /// The last stretch of a piece's life, in seconds, over which it fades.
    static let fade = 0.45

    init(burst: Burst, seed: UInt64, colours: Int) {
        var random = SeededRandom(seed: seed)
        var pieces: [Piece] = []
        func add(_ count: Int, from origin: CGPoint, heading: ClosedRange<Double>, speed: ClosedRange<Double>,
                 stagger: Double) {
            for _ in 0..<count {
                // Heading in degrees from straight up, positive to the right.
                let direction = random.in(heading) * .pi / 180
                let v = random.in(speed)
                let long = random.in(7...11)
                pieces.append(Piece(origin: origin,
                                    velocity: CGVector(dx: sin(direction) * v, dy: -cos(direction) * v),
                                    delay: random.in(0...stagger),
                                    width: long, height: long * random.in(0.45...0.7),
                                    angle: random.in(0...(2 * .pi)), spin: random.in(-6...6),
                                    flip: random.in(0.8...2.2), phase: random.in(0...(2 * .pi)),
                                    sway: random.in(6...18), colour: Int(random.unit() * Double(colours)) % colours))
            }
        }
        switch burst {
        case .puff(let point):
            add(26, from: point, heading: -50...50, speed: 380...700, stagger: 0.05)
            life = 2.4
        case .burst(let point):
            add(64, from: point, heading: -75...75, speed: 520...1050, stagger: 0.08)
            life = 3.0
        case .cannons:
            // Fast enough to reach the top third of the screen through the drag, crossing as they rise.
            add(70, from: CGPoint(x: 0.02, y: 1.02), heading: 8...38, speed: 2100...3000, stagger: 0.25)
            add(70, from: CGPoint(x: 0.98, y: 1.02), heading: -38 ... -8, speed: 2100...3000, stagger: 0.25)
            life = 3.6
        }
        self.pieces = pieces
        duration = (pieces.map(\.delay).max() ?? 0) + life
    }

    /// Where `piece` is `t` seconds after the burst on a screen of `size`, or nil before its launch, after its life,
    /// or once it has fallen out of sight.
    func spot(of piece: Piece, at t: Double, in size: CGSize) -> Spot? {
        let age = t - piece.delay
        guard age >= 0, age < life else { return nil }
        let k = Self.drag
        let slowed = 1 - exp(-k * age)
        let terminal = Self.gravity / k
        let sway = piece.sway * slowed * sin(2 * .pi * 0.9 * age + piece.phase)
        let x = piece.origin.x * size.width + piece.velocity.dx / k * slowed + sway
        let y = piece.origin.y * size.height + terminal * age + (piece.velocity.dy - terminal) / k * slowed
        guard y < size.height + 40 else { return nil }
        return Spot(x: x, y: y, angle: piece.angle + piece.spin * age,
                    turn: cos(2 * .pi * piece.flip * age + piece.phase),
                    opacity: min(1, (life - age) / Self.fade))
    }
}

/// A small seeded generator for the field (successive SplitMix64 mixes): the same seed, the same confetti.
private struct SeededRandom {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func unit() -> Double {
        state = StableRandom.mix(state)
        return Double(state >> 11) * 0x1.0p-53
    }

    mutating func `in`(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }
}

/// The confetti layer: lay it over a whole screen. It bursts when it appears and again whenever `trigger` changes,
/// draws nothing once the pieces are gone, and never takes a touch.
struct CLConfetti: View {
    let burst: ConfettiField.Burst
    var seed: UInt64 = 1
    var trigger = 0

    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var field: ConfettiField?
    @State private var started = Date.distantPast

    private static let colours: [Color] = CourseColor.allCases.map(\.fill) + [CLColor.sun]

    var body: some View {
        ZStack {
            if let field, !reduceMotion {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        draw(field, at: timeline.date.timeIntervalSince(started), in: &context, size: size)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: fire)
        .onChange(of: trigger) { fire() }
        .task(id: started) {
            guard let field else { return }
            try? await Task.sleep(for: .seconds(field.duration))
            if !Task.isCancelled { self.field = nil }
        }
    }

    private func fire() {
        guard !reduceMotion else { return }
        field = ConfettiField(burst: burst, seed: seed &+ UInt64(trigger), colours: Self.colours.count)
        started = Date()
    }

    private func draw(_ field: ConfettiField, at t: Double, in context: inout GraphicsContext, size: CGSize) {
        for piece in field.pieces {
            guard let spot = field.spot(of: piece, at: t, in: size) else { continue }
            var paper = context
            paper.opacity = spot.opacity
            paper.translateBy(x: spot.x, y: spot.y)
            paper.rotate(by: .radians(spot.angle))
            paper.scaleBy(x: 1, y: max(0.08, abs(spot.turn)))
            let rect = CGRect(x: -piece.width / 2, y: -piece.height / 2, width: piece.width, height: piece.height)
            let path = Path(roundedRect: rect, cornerRadius: 1.2)
            paper.fill(path, with: .color(Self.colours[piece.colour]))
            // The back of the paper, turned away from the light.
            if spot.turn < 0 { paper.fill(path, with: .color(.black.opacity(0.16))) }
        }
    }
}
