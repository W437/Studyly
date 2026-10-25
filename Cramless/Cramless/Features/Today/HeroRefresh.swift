import CoreGraphics
import Foundation
import Observation

// Pull to refresh on Today's hero. Pulling the page down doesn't move the hero: it stays where it is, and the world answers the
// pull instead. The layers lean down by different amounts and the sky wakes; past a line (a tick under the finger) letting go
// relights it: an arc of light climbs from the horizon and every star flashes as it passes, a star falls, and Cap says
// something. Everything that can be wrong is pure and tested (`HeroRefreshTests`); `HeroPullModel` feeds it the scroll view's
// readings, `HeroWorldRenderer` draws what it says.

// MARK: - The pull

/// How far a pull has gone, and what letting go will do.
struct HeroPull: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// Nothing is pulling.
        case idle
        /// A finger is dragging the page down, not yet far enough.
        case pulling
        /// Far enough: letting go now refreshes.
        case armed
        /// The flourish and the refresh are running.
        case refreshing
    }

    enum Event: Equatable, Sendable {
        /// The pull reached the line (a tick under the finger).
        case armed
        /// It came back past the line before the finger lifted: letting go won't refresh.
        case disarmed
        /// The refresh begins.
        case started
    }

    private(set) var phase = Phase.idle
    /// Points the page is pulled past its top, never negative.
    private(set) var distance = 0.0
    /// A finger is on the page and dragging it.
    private(set) var dragging = false
    /// A finger pulled the page down and let go with it still moving: the momentum may carry it past the line by itself.
    private(set) var flicked = false

    /// How far past the top (points) a pull counts. The rubber band shows about half of what the finger travels (the line is about
    /// 140 points of drag), so it is a firm pull, not a stretch.
    static let threshold = 72.0
    /// An armed pull that falls back below this is no longer armed, so a hand wobbling over the line doesn't flicker.
    static let release = 52.0
    /// The least pull a finger lets go at for what follows to count as a flick.
    static let flick = 24.0

    /// The pull as the world feels it: 0 at rest, 1 at the line, 1.25 at the most.
    var progress: Double { Self.progress(distance: distance) }

    static func progress(distance: Double) -> Double { min(1.25, max(0, distance) / threshold) }

    /// The scroll view's latest readings: how far past its top the page is, and whether a finger is on it. Returns what happened.
    @discardableResult
    mutating func update(distance raw: Double, dragging now: Bool) -> Event? {
        let was = dragging
        dragging = now
        distance = max(0, raw)
        if phase == .refreshing { return nil }
        if now {
            flicked = false
            if distance >= Self.threshold {
                guard phase != .armed else { return nil }
                phase = .armed
                return .armed
            }
            if phase == .armed, distance >= Self.release { return nil }
            let before = phase
            phase = distance > 0 ? .pulling : .idle
            return before == .armed ? .disarmed : nil
        }
        // No finger on it. Letting go of an armed pull refreshes, and so does a quick flick that reached the line before anyone
        // saw it. A flick that lets go short of the line but carries the page past it by momentum counts too: it began under the
        // finger, so it was meant. (A page that is flung up and bounces off its top never had a finger pulling it down.)
        if phase == .armed || (was && distance >= Self.threshold) {
            flicked = false
            phase = .refreshing
            return .started
        }
        if was, distance >= Self.flick { flicked = true }
        if flicked, distance >= Self.threshold {
            flicked = false
            phase = .refreshing
            return .started
        }
        if distance <= 0 { flicked = false }
        phase = .idle
        return nil
    }

    /// A refresh with no pull (VoiceOver's "Refresh", the DEBUG hook).
    @discardableResult
    mutating func begin() -> Event? {
        guard phase != .refreshing else { return nil }
        phase = .refreshing
        return .started
    }

    /// The refresh is over.
    mutating func finish() {
        if phase == .refreshing { phase = .idle }
    }
}

/// How the world leans into a pull: points each layer moves down at the line (the ground never moves), and how much the
/// background wakes. The nearer a layer, the further it goes, which is what makes the sky feel like a place being pulled.
enum HeroPullLook {
    /// Background stars, far to near.
    static let dust: [Double] = [4, 8, 13]
    static let clouds = 9.0
    static let milkyWay = 5.0
    /// The memory sky itself.
    static let sky = 16.0
    /// How much brighter the background stars get at the line, as a share.
    static let wake = 0.45
    /// How much brighter the dusk at the horizon gets, as a share.
    static let dawn = 0.7
    /// How strongly the sky's own stars are lit a second time at the line.
    static let skyGlow = 0.34
}

// MARK: - The flourish

/// What happens over time once the pull is let go: an arc of light climbs from the horizon to above the sky and the stars flash as it
/// passes (`front`, `flash`, `glow`), a star falls (`HeroShootingStar.burst`), and under Reduce Motion the sky only brightens for a
/// moment (`calm`).
enum HeroRefreshWave {
    /// The whole flourish, and how long the arc takes to climb, in seconds from letting go.
    static let seconds = 1.3
    static let climb = 0.95

    /// Where the arc is: 0 at the horizon, 1 above the top of the sky.
    static func front(at t: Double) -> Double {
        let x = min(1, max(0, t / climb))
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    /// How strong the flourish is: it comes up in a tenth of a second, holds while the arc climbs, then fades out.
    static func glow(at t: Double) -> Double {
        guard t >= 0, t < seconds else { return 0 }
        let rise = min(1, t / 0.1)
        let tail = t <= climb ? 1 : 1 - (t - climb) / (seconds - climb)
        return rise * tail * tail * (3 - 2 * tail)
    }

    /// How lit a star `distance` points from the arc is: 1 on it, 0 further than `reach`, a soft bump between.
    static func flash(distance: Double, reach: Double = 72) -> Double {
        let x = abs(distance) / reach
        guard x < 1 else { return 0 }
        let bump = 1 - x * x
        return bump * bump
    }

    /// Reduce Motion's version: the sky brightens evenly and settles, over about 0.8 seconds, with nothing moving.
    static func calm(at t: Double) -> Double {
        guard t >= 0, t < 0.8 else { return 0 }
        let x = t / 0.8
        return sin(.pi * x) * sin(.pi * x)
    }
}

extension HeroShootingStar {
    /// How long the star that falls on a refresh takes, and when it leaves.
    static let burstFlight = 0.7
    static let burstDelay = 0.1

    /// The star that falls when the sky is refreshed, `t` seconds after letting go: a fixed path from high on the right toward the middle
    /// of the sky, quicker than the ambient ones.
    static func burst(at t: Double) -> Streak? {
        let into = t - burstDelay
        guard into >= 0, into < burstFlight else { return nil }
        return Streak(progress: into / burstFlight, from: CGPoint(x: 0.92, y: 0.04), to: CGPoint(x: 0.44, y: 0.42))
    }
}

// MARK: - The model

/// Reads the page's pull (how far past its top, whether a finger is on it) and runs the refresh when letting go of a long enough
/// pull. Today feeds it from the scroll view and gives it the work to do; the hero reads it each frame to draw.
@MainActor
@Observable
final class HeroPullModel {
    enum Outcome: Equatable, Sendable {
        /// The sky is as current as it can be.
        case fresh
        /// The account couldn't be reached: the sky is current on this iPhone only.
        case offline
    }

    /// How far past its top the page is pulled, in points. Changes with every frame of a pull.
    private(set) var distance = 0.0
    /// What the pull has become. Changes a few times in a pull.
    private(set) var phase = HeroPull.Phase.idle
    /// When the flourish began, how many refreshes have finished, and how the last one went.
    private(set) var startedAt: Date?
    private(set) var finished = 0
    private(set) var outcome = Outcome.fresh

    /// What refreshing does: look at the world again, and say whether it could reach everything. Set by Today.
    @ObservationIgnored var work: (@MainActor () async -> Outcome)?
    @ObservationIgnored private var pull = HeroPull()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let minimum: Double
    @ObservationIgnored private let haptics: Bool

    /// The flourish takes at least `minimum` seconds, however quickly the work is done.
    init(minimum: Double = HeroRefreshWave.seconds, haptics: Bool = true) {
        self.minimum = minimum
        self.haptics = haptics
    }

    // MARK: Readings

    /// From the scroll view: the page is `distance` points past its top (0 when it isn't).
    func scrolled(to distance: Double) {
        let event = pull.update(distance: distance, dragging: pull.dragging)
        trace("scrolled \(Int(distance.rounded()))", event)
        apply(event)
    }

    /// From the scroll view: a finger is dragging the page, or has let go.
    func finger(dragging: Bool) {
        let event = pull.update(distance: pull.distance, dragging: dragging)
        trace("finger \(dragging ? "down" : "up") at \(Int(pull.distance.rounded()))", event)
        apply(event)
    }

    /// `CRAMLESS_PULL_LOG=1` writes what the scroll view told the pull to the log, for working out a gesture that didn't count.
    private func trace(_ what: String, _ event: HeroPull.Event?) {
        #if DEBUG
        guard Self.tracing, pull.distance > 0 || event != nil || what.hasPrefix("finger") else { return }
        AppConfig.log.notice("pull: \(what, privacy: .public) -> \(String(describing: self.pull.phase), privacy: .public) \(event.map { String(describing: $0) } ?? "", privacy: .public)")
        #endif
    }

    #if DEBUG
    private static let tracing = ProcessInfo.processInfo.environment["CRAMLESS_PULL_LOG"] != nil
    #endif

    /// Refresh without a pull: VoiceOver's "Refresh" action.
    func refreshNow() {
        apply(pull.begin())
    }

    // MARK: What it does

    private func apply(_ event: HeroPull.Event?) {
        switch event {
        case .armed: if haptics { CLHaptics.tick() }
        case .started: start()
        case .disarmed, nil: break
        }
        publish()
    }

    /// Passes on only what changed, so what reads `phase` isn't woken by every frame of `distance`.
    private func publish() {
        if distance != pull.distance { distance = pull.distance }
        if phase != pull.phase { phase = pull.phase }
    }

    private func start() {
        startedAt = Date()
        task?.cancel()
        let minimum = minimum
        task = Task { [weak self] in
            let began = Date()
            let outcome = await self?.work?() ?? .fresh
            let rest = minimum - Date().timeIntervalSince(began)
            if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
            guard !Task.isCancelled else { return }
            self?.finish(outcome)
        }
    }

    private func finish(_ outcome: Outcome) {
        pull.finish()
        self.outcome = outcome
        finished += 1
        publish()
    }

    /// Seconds into the flourish at `date`, while it is running.
    func waveTime(at date: Date) -> Double? {
        guard let startedAt else { return nil }
        let t = date.timeIntervalSince(startedAt)
        return t >= 0 && t < HeroRefreshWave.seconds ? t : nil
    }
}
