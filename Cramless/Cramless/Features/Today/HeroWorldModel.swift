import CoreGraphics
import Foundation

// The pure parts of Today's hero as a world: where everything sits for a given screen, the field of background stars, the
// nebulae behind each course, where the card for a focused constellation goes, and how a tilt of the phone moves the layers.
// No views here, so every one is tested (`HeroWorldTests`). `HeroWorld.swift` draws them.

/// Where everything in the hero sits. The hero runs from the top of the screen (the sky goes up behind the status bar) to the
/// foot of the hills; the constellations fill the free part of the sky between the status bar and the hills, edge to edge.
struct HeroWorldGeometry: Equatable, Sendable {
    /// The hero's frame, in points: the full width, and the height from the top of the screen down to the ground.
    var width: CGFloat
    var height: CGFloat
    /// The status bar's height: the sky runs up behind it.
    var topInset: CGFloat
    /// Accessibility text sizes: a low band with no ground to speak of and no Cap, so the words get the width.
    var compact: Bool

    /// The share of the screen's height the hero's band takes on a phone, and its limits (the band is what is under the status
    /// bar): a little under half, so the day's button is still on screen without scrolling.
    static let bandShare: CGFloat = 0.43
    static let bandLimits: ClosedRange<CGFloat> = 300...440
    static let compactBand: CGFloat = 180

    /// The geometry for a screen: `width` is the hero's width, `screenHeight` the height of the screen it is on.
    static func make(width: CGFloat, screenHeight: CGFloat, topInset: CGFloat, compact: Bool) -> HeroWorldGeometry {
        let band = compact ? compactBand : min(bandLimits.upperBound, max(bandLimits.lowerBound, screenHeight * bandShare))
        return HeroWorldGeometry(width: width, height: topInset + band, topInset: topInset, compact: compact)
    }

    var band: CGFloat { height - topInset }

    // MARK: The sky

    /// The top of the free sky: just under the status bar. The title sits over it, so the stars behind the title are kept dim
    /// (`HeroSkyView` lays a soft scrim there).
    var skyTop: CGFloat { topInset + (compact ? 6 : 12) }
    /// The bottom of the free sky: just above the far hills' average crest. A star never sits below it.
    var skyBottom: CGFloat { farHills - 6 }
    var skyHeight: CGFloat { max(1, skyBottom - skyTop) }
    /// The shape (height over width) the sky is laid out for: the free sky exactly, so the constellations fill it.
    var skyAspect: Double { Double(skyHeight / max(width, 1)) }
    /// What `SkyCamera` keeps clear at the top and the bottom.
    var insetTop: Double { Double(skyTop) }
    var insetBottom: Double { Double(height - skyBottom) }

    // MARK: The ground and Cap

    /// Cap's size: large, standing in the world and not squeezed beside it.
    var capSize: CGFloat { compact ? 0 : min(196, max(120, width * 0.46)) }
    /// Where the water's top edge is, and how deep it is: the lake mirrors the stars above it.
    var lakeTop: CGFloat { height - (compact ? 14 : 50) }
    var lakeDepth: CGFloat { compact ? 10 : 34 }
    /// The far hills' average crest, and the mid hills'.
    var farHills: CGFloat { height - (compact ? 28 : 84) }
    var midHills: CGFloat { height - (compact ? 16 : 52) }

    /// The shape the sky of a screen is laid out for, before the view has been measured: the geometry of a phone of this width
    /// and height.
    static func skyAspect(width: CGFloat, screenHeight: CGFloat, topInset: CGFloat, compact: Bool) -> Double {
        make(width: width, screenHeight: screenHeight, topInset: topInset, compact: compact).skyAspect
    }
}

// MARK: - Background stars

/// The field of faint background stars that fills the empty sky, so a world with few constellations isn't a black void. They
/// are not data: they are the same on every launch (a seed), three depths deep, and twinkle slowly.
struct HeroDust: Equatable, Sendable {
    struct Mote: Equatable, Sendable {
        /// Where, as a share of the width and of the sky's height.
        var x: Double
        var y: Double
        var radius: Double
        var alpha: Double
        /// 0 far, 1 middle, 2 near: how much a tilt or a zoom moves it.
        var depth: Int
        var phase: Double
        var period: Double
        /// Warm or cool, as a share from cool (0) to warm (1).
        var warmth: Double
        /// One of the few that glint: a small four-point cross.
        var glints: Bool
    }

    var motes: [Mote]

    /// How far each depth moves with a tilt, in points per unit of tilt, and how much of a zoom it follows.
    static let parallax: [Double] = [2.5, 5.5, 10]
    static let zoomFollow: [Double] = [0.04, 0.09, 0.16]

    static func make(count: Int = 240, seed: UInt64 = 0xC4A9_5EED) -> HeroDust {
        var dice = CapDice(seed: seed)
        var motes: [Mote] = []
        motes.reserveCapacity(count)
        for k in 0..<count {
            let u = Double.random(in: 0..<1, using: &dice)
            // Denser high in the sky, thinning toward the horizon.
            let y = pow(u, 1.25)
            let depthRoll = Double.random(in: 0..<1, using: &dice)
            let depth = depthRoll < 0.45 ? 0 : (depthRoll < 0.82 ? 1 : 2)
            let size = Double.random(in: 0..<1, using: &dice)
            let reach = 0.8 + 0.5 * Double(depth)
            let radius = 0.45 + size * size * reach
            let strength = 0.7 + 0.18 * Double(depth)
            let alpha = 0.22 + 0.55 * size * strength
            let x = Double.random(in: 0..<1, using: &dice)
            let phase = Double.random(in: 0..<1, using: &dice)
            let period = Double.random(in: 2.6...6.2, using: &dice)
            let warmth = Double.random(in: 0..<1, using: &dice)
            // Every thirtieth star is a bright one with a glint, always a near one.
            let glints = k % 30 == 7
            motes.append(Mote(x: x, y: glints ? min(y, 0.7) : y, radius: glints ? 1.35 + 0.4 * size : radius,
                              alpha: glints ? 0.85 : alpha, depth: glints ? 2 : depth, phase: phase, period: period,
                              warmth: warmth, glints: glints))
        }
        return HeroDust(motes: motes)
    }

    /// How much a mote shines at `time`: a slow breath around one.
    static func twinkle(_ mote: Mote, time: Double, animated: Bool) -> Double {
        guard animated else { return 1 }
        return 0.78 + 0.22 * sin(2 * .pi * (time / mote.period + mote.phase))
    }
}

// MARK: - Nebulae

/// A soft cloud of a course's colour behind its constellations: what makes the world read as places (the biology corner, the
/// chemistry corner) before it reads as stars.
struct HeroCloud: Equatable, Sendable {
    var center: SkyPoint
    /// In layout units (star spacings).
    var radius: Double
    var color: CourseColor
    var courseID: UUID

    /// One cloud for every course with a constellation in the scene: centred on its constellations (weighted by how many
    /// stars each has) and reaching a little past the farthest one.
    static func clouds(for scene: SkyScene) -> [HeroCloud] {
        var order: [UUID] = []
        var groups: [UUID: [SkyLayout.Constellation]] = [:]
        for c in scene.layout.constellations {
            if groups[c.courseID] == nil { order.append(c.courseID) }
            groups[c.courseID, default: []].append(c)
        }
        return order.compactMap { id in
            guard let group = groups[id], let first = group.first else { return nil }
            let weights = group.map { Double(max(1, $0.stars.count)) }
            let total = weights.reduce(0, +)
            let x = zip(group, weights).reduce(0.0) { $0 + $1.0.center.x * $1.1 } / total
            let y = zip(group, weights).reduce(0.0) { $0 + $1.0.center.y * $1.1 } / total
            let center = SkyPoint(x: x, y: y)
            let reach = group.map { center.distance(to: $0.center) + $0.radius }.max() ?? 1
            return HeroCloud(center: center, radius: reach * 1.32, color: scene.color(of: first), courseID: id)
        }
    }
}

// MARK: - The focus card

/// Where the little card for a focused constellation goes: under it when there is room above the ground, else over it, and
/// kept inside the screen sideways.
enum HeroFocusPlacement {
    static func card(center: CGPoint, radius: CGFloat, card: CGSize, in size: CGSize, top: CGFloat, bottom: CGFloat,
                     margin: CGFloat = 12, gap: CGFloat = 10) -> CGPoint {
        let halfW = card.width / 2, halfH = card.height / 2
        let x: CGFloat
        if card.width + 2 * margin >= size.width {
            x = size.width / 2
        } else {
            x = min(max(center.x, margin + halfW), size.width - margin - halfW)
        }
        let below = center.y + radius + gap + halfH
        let above = center.y - radius - gap - halfH
        let y: CGFloat
        if below + halfH <= size.height - bottom { y = below }
        else if above - halfH >= top { y = above }
        else { y = min(max(below, top + halfH), size.height - bottom - halfH) }
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Tilt

/// How a tilt of the phone moves the layers: the gravity vector's sideways and forward-and-back parts against where the phone was
/// held a few seconds ago (a slow reference follows it, so holding it at an angle makes that the new middle), smoothed, each in
/// -1...1. Gravity and not the roll and pitch angles, which are unstable when a phone is held upright (gimbal lock), which is how
/// it is held. Pure: `HeroTilt` feeds it the motion sensor's readings.
struct HeroTiltFilter: Equatable, Sendable {
    var x = 0.0
    var y = 0.0
    private var referenceSide: Double?
    private var referenceLean = 0.0

    /// How much of the gravity vector's sideways part (about the sine of the tilt) reaches the full parallax: about 17 degrees.
    static let reach = 0.30
    /// Seconds the reference takes to follow a new way of holding the phone, and the output's smoothing.
    static let settle = 3.0
    static let smoothing = 0.12

    /// `side` is the gravity vector's x in the phone's own axes (it grows as the right edge goes down) and `lean` its z (it grows
    /// as the top leans away); `dt` is the seconds since the last reading.
    mutating func update(side: Double, lean: Double, dt: Double) {
        if referenceSide == nil { referenceSide = side; referenceLean = lean }
        let follow = min(1, dt / Self.settle)
        referenceSide = (referenceSide ?? side) + (side - (referenceSide ?? side)) * follow
        referenceLean += (lean - referenceLean) * follow
        let targetX = min(1, max(-1, (side - (referenceSide ?? side)) / Self.reach))
        let targetY = min(1, max(-1, (lean - referenceLean) / Self.reach))
        let blend = 1 - pow(1 - Self.smoothing, max(dt, 0.001) * 60)
        x += (targetX - x) * blend
        y += (targetY - y) * blend
    }

    mutating func reset() { self = HeroTiltFilter() }
}

// MARK: - Shooting stars

/// A star that crosses the sky now and then. Which, where and when are worked out from the time alone, so there is nothing to
/// store, and the same minute of a film shows the same stars.
enum HeroShootingStar {
    /// Seconds between one and the next, and how long one takes to cross.
    static let period = 19.0
    static let flight = 0.85

    struct Streak: Equatable {
        /// 0 at the start of its flight, 1 at the end.
        var progress: Double
        /// Where it starts and the way it goes, as shares of the width and the sky's height.
        var from: CGPoint
        var to: CGPoint
    }

    /// The streak crossing at `time`, if one is.
    static func streak(at time: Double) -> Streak? {
        guard time >= 5 else { return nil }
        let slot = Int(((time - 5) / period).rounded(.down))
        let into = (time - 5) - Double(slot) * period
        // Each slot's star leaves at a time of its own, and goes its own way.
        var dice = CapDice(seed: UInt64(truncatingIfNeeded: slot) &* 0x9E37_79B9_7F4A_7C15 ^ 0x57A2)
        let delay = 2.0 + Double.random(in: 0..<1, using: &dice) * (period - flight - 6)
        guard into >= delay, into < delay + flight else { return nil }
        let a = Double.random(in: 0..<1, using: &dice)
        let b = Double.random(in: 0..<1, using: &dice)
        let leftToRight = Bool.random(using: &dice)
        let startX = leftToRight ? 0.08 + 0.35 * a : 0.92 - 0.35 * a
        let from = CGPoint(x: startX, y: 0.04 + 0.30 * b)
        let to = CGPoint(x: from.x + (leftToRight ? 0.34 : -0.34), y: from.y + 0.20)
        return Streak(progress: (into - delay) / flight, from: from, to: to)
    }
}
