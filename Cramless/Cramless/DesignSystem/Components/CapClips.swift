import Foundation

/// One of Cap's moving drawings: a short transparent video that starts and ends on a pose's still, so it can take over from
/// the still and hand back to it with no visible change. `scripts/cap_anim/produce.py` makes them from the character sheet
/// (`docs/cap/`); the manifest `cap-clips.json` in the bundle lists them. A clip is drawn on a 720 px square with the pose
/// at its true 600 px size in the middle, so it lines up with the still pixel for pixel.
struct CapClip: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable {
        /// A quiet loop for while Cap waits: breathing, blinking, the small things he does.
        case idle
        /// A reaction that plays once when the moment arrives: a cheer, a wave, a nod.
        case performance
        /// What he does when the person taps him: a reaction to a touch that starts and ends on his drawing, so it can
        /// play from any pose he is in. Each pose has its own.
        case poke
    }

    let id: String
    let pose: CapPose
    let role: Role
    let file: String
    let fps: Double
    let frames: Int
    let duration: Double
    let bytes: Int

    /// The clip's canvas against the pose in it: 720 px to 600 px.
    static let canvasScale = 720.0 / 600.0

    /// The file in the app.
    var url: URL? {
        Bundle.main.url(forResource: (file as NSString).deletingPathExtension, withExtension: (file as NSString).pathExtension)
    }
}

/// Every clip the app has: for each pose the clip that animates it, and the one that plays when he is tapped.
struct CapClipCatalog: Sendable {
    let clips: [CapClip]
    private let byPose: [CapPose: CapClip]
    private let pokes: [CapPose: CapClip]

    init(clips: [CapClip]) {
        self.clips = clips
        byPose = Dictionary(clips.filter { $0.role != .poke }.map { ($0.pose, $0) }, uniquingKeysWith: { first, _ in first })
        pokes = Dictionary(clips.filter { $0.role == .poke }.map { ($0.pose, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The clip that animates `pose`, if one has been made.
    func clip(for pose: CapPose) -> CapClip? { byPose[pose] }

    /// What `pose` does when it is tapped, if that clip has been made.
    func poke(for pose: CapPose) -> CapClip? { pokes[pose] }

    static let empty = CapClipCatalog(clips: [])

    static let shared = load()

    private struct Manifest: Decodable {
        var version: Int
        var clips: [Entry]

        /// One clip that may not decode (a role this build doesn't know): it is left out, not allowed to take every other
        /// clip down with it.
        struct Entry: Decodable {
            var clip: CapClip?
            init(from decoder: Decoder) throws { clip = try? CapClip(from: decoder) }
        }
    }

    /// The manifest `cap-clips.json`, or an empty catalog (Cap stays a still) if it is missing or unreadable.
    static func load(from bundle: Bundle = .main) -> CapClipCatalog {
        guard let url = bundle.url(forResource: "cap-clips", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return .empty }
        return decode(data)
    }

    /// The catalog a manifest describes; a clip it can't read is left out and the rest are kept.
    static func decode(_ data: Data) -> CapClipCatalog {
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return .empty }
        return CapClipCatalog(clips: manifest.clips.compactMap(\.clip))
    }
}

/// When Cap's clips may play. The views build it from the person's settings and the phone's state.
struct CapPlaybackPolicy: Equatable, Sendable {
    /// Clips may play at all: "Cap moves" is on and Reduce Motion is off.
    var clips: Bool
    /// Clips that play while Cap waits may play: Low Power Mode is off.
    var idles: Bool

    static let on = CapPlaybackPolicy(clips: true, idles: true)
    static let off = CapPlaybackPolicy(clips: false, idles: false)
}

/// What Cap does at a moment once his clips are counted in, as a plain value (so it is tested like an engine).
///
/// A moment names a pose, a motion, sparkles and how he waits (`CapMoment`). With a clip for the pose, the clip does the
/// moving and the code's own squash, wobble and nod stand down (the clip already has them); the entrance (`arrive`) and
/// the sparkles stay in code, because they are about the screen and not about Cap. With no clip, or with clips off, the
/// moment plays exactly as it did before clips existed.
struct CapScript: Equatable, Sendable {
    /// Plays once when the moment arrives (and again whenever it is triggered).
    var arrival: CapClip?
    /// Plays while Cap waits: on a loop (no gap), or now and then (a gap between plays).
    var idle: CapClip?
    /// Plays when he is tapped, from whatever he was doing.
    var poke: CapClip?
    /// Seconds of stillness between plays of `idle`; nil loops it.
    var idleGap: ClosedRange<Double>?
    /// Seconds to wait before the first play of `idle`.
    var firstDelay: Double = 0
    /// The motion the code still plays.
    var motion: CapMotion?
    var sparkles: Bool
    /// The code breathes for Cap (no clip does).
    var breathes: Bool
    /// Z's drift up from a dozing Cap.
    var dozes: Bool

    /// A clip plays on its own, with no tap.
    var hasClip: Bool { arrival != nil || idle != nil }
    /// The video layer is needed: a clip may play, now or when he is tapped.
    var plays: Bool { hasClip || poke != nil }

    /// The pause between plays of a periodic clip: long enough to feel like Cap, not a GIF.
    static let idleGapRange: ClosedRange<Double> = 5...10
    static let repeatGapRange: ClosedRange<Double> = 8...14

    static func make(pose: CapPose, motion: CapMotion?, sparkles: Bool, idle: CapIdle?, policy: CapPlaybackPolicy,
                     catalog: CapClipCatalog = .shared) -> CapScript {
        var script = CapScript(motion: motion, sparkles: sparkles, breathes: idle == .breathe, dozes: idle == .doze)
        guard policy.clips else { return script }
        // A tap's reaction is a reaction, not a way of waiting: Low Power Mode keeps it.
        script.poke = catalog.poke(for: pose.shown)
        guard let clip = catalog.clip(for: pose.shown) else { return script }
        switch clip.role {
        case .performance:
            script.arrival = clip
            // The clip hops, wobbles or nods for him; only the entrance stays in code.
            if let motion, motion != .arrive { script.motion = nil }
            // A pose he waits in (the welcome's wave) repeats now and then.
            if idle != nil, policy.idles {
                script.idle = clip
                script.idleGap = repeatGapRange
                script.firstDelay = repeatGapRange.lowerBound
            }
        case .poke:
            return script     // never a pose's own clip: `clip(for:)` doesn't return one
        case .idle:
            guard policy.idles else { return script }
            script.idle = clip
            if idle == nil {
                script.idleGap = idleGapRange
                script.firstDelay = 0.6
            }
        }
        if script.idle != nil { script.breathes = false }
        return script
    }
}
