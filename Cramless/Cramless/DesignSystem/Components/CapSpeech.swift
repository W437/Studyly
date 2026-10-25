import Foundation

// How Cap decides what to say when he is tapped. The lines are `CapLines`; this deals them out so one doesn't come back soon,
// whichever pose he is in and however long the person has been using the app. Pure, so it is tested like an engine.

/// A part of the day, for the greetings.
enum CapDayPart: Sendable, CaseIterable {
    case morning, afternoon, evening, night

    init(hour: Int) {
        switch hour {
        case 5..<12: self = .morning
        case 12..<17: self = .afternoon
        case 17..<22: self = .evening
        default: self = .night
        }
    }
}

/// A set of lines that is dealt out together.
enum CapLinePool: Hashable, Sendable {
    case pose(CapPose)
    case general
    case time(CapDayPart)
    case flustered
    case refreshed

    var id: String {
        switch self {
        case .pose(let pose): "pose.\(pose.rawValue)"
        case .general: "general"
        case .time(let part): "time.\(part)"
        case .flustered: "flustered"
        case .refreshed: "refreshed"
        }
    }

    var lines: [LocalizedStringResource] {
        switch self {
        case .pose(let pose): CapLines.lines(for: pose)
        case .general: CapLines.general
        case .time(.morning): CapLines.morning
        case .time(.afternoon): CapLines.afternoon
        case .time(.evening): CapLines.evening
        case .time(.night): CapLines.night
        case .flustered: CapLines.flustered
        case .refreshed: CapLines.refreshed
        }
    }

    /// Every pool there is.
    static var all: [CapLinePool] {
        CapPose.allCases.map { .pose($0) } + [.general, .flustered, .refreshed] + CapDayPart.allCases.map { .time($0) }
    }
}

/// One thing Cap says.
struct CapLine: Equatable, Identifiable, Sendable {
    let pool: String
    let index: Int
    let text: LocalizedStringResource

    var id: String { "\(pool)#\(index)" }

    static func == (a: CapLine, b: CapLine) -> Bool { a.id == b.id }

    /// How long the bubble stays up: time to read it, with a floor and a ceiling.
    var seconds: Double { Self.seconds(forLength: String(localized: text).count) }

    static func seconds(forLength count: Int) -> Double { min(4.4, max(1.9, 1.1 + 0.055 * Double(count))) }
}

/// Deals each pool's lines in a random order without repeating one until the pool has been used up, and never starts a new
/// round with the line that ended the last. Codable, so it carries on from where it was after the app is closed.
struct CapLineBag: Codable, Equatable, Sendable {
    /// Pool id to the indices shown in its current round.
    var seen: [String: [Int]] = [:]
    /// Pool id to the line shown last.
    var last: [String: Int] = [:]

    /// The index of the next line to show from a pool of `count`.
    mutating func draw<G: RandomNumberGenerator>(pool: String, count: Int, using g: inout G) -> Int {
        guard count > 0 else { return 0 }
        var used = Set((seen[pool] ?? []).filter { $0 < count })
        if used.count >= count { used.removeAll() }
        var open = (0..<count).filter { !used.contains($0) }
        if open.count > 1, let previous = last[pool] { open.removeAll { $0 == previous } }
        let pick = open.randomElement(using: &g) ?? 0
        used.insert(pick)
        seen[pool] = used.sorted()
        last[pool] = pick
        return pick
    }
}

enum CapSpeech {
    /// Which pool he speaks from: a quick run of taps gets the flustered lines; otherwise mostly what he is doing, with some
    /// that suit any pose and some that greet the hour.
    static func pool(for pose: CapPose, rapid: Int, hour: Int, roll: Double) -> CapLinePool {
        if rapid >= 4 { return .flustered }
        if roll < 0.68 { return .pose(pose) }
        if roll < 0.84 { return .general }
        return .time(CapDayPart(hour: hour))
    }

    /// Where a bubble of `bubbleWidth` sits sideways so it stays on screen: how far to move it from being centred over Cap,
    /// whose middle is at `capMidX` on a screen `screenWidth` wide.
    static func shift(capMidX: Double, bubbleWidth: Double, screenWidth: Double, margin: Double = 12) -> Double {
        let low = margin + bubbleWidth / 2
        let high = screenWidth - margin - bubbleWidth / 2
        guard low <= high else { return screenWidth / 2 - capMidX }
        return min(max(capMidX, low), high) - capMidX
    }
}

/// The one place taps on Cap are decided: his dice, what he says, and whether he says it. Settings ▸ Accessibility ▸ Feel
/// ▸ "Cap talks" turns the talking off (the harness turns his persistence off and may seed the dice, so films repeat).
@MainActor
final class CapTouch {
    static let shared = CapTouch()

    /// Settings ▸ Accessibility ▸ Feel ▸ "Cap talks".
    var talks = true

    private var bag: CapLineBag
    private var rng: CapRNG
    private var persists = true
    private static let key = "capling.capTouch.bag"

    private init() {
        rng = CapRNG()
        if let data = UserDefaults.standard.data(forKey: Self.key), let saved = try? JSONDecoder().decode(CapLineBag.self, from: data) {
            bag = saved
        } else {
            bag = CapLineBag()
        }
    }

    /// The harness: no memory between launches, and dice that repeat when given a seed. Once only: it can be asked again as
    /// settings change, and starting the dice over would replay the same rolls.
    func configureForHarness(seed: UInt64?) {
        guard persists else { return }
        persists = false
        bag = CapLineBag()
        rng = CapRNG(seed: seed)
    }

    /// A fresh poke for the pose he is in.
    func roll(_ pose: CapPose, rapid: Int) -> CapPoke {
        CapPoke.roll(for: pose, rapid: rapid, using: &rng)
    }

    /// What he says: the next line from a pool chosen for the pose and the tap.
    func line(for pose: CapPose, rapid: Int, hour: Int = Calendar.current.component(.hour, from: .now)) -> CapLine {
        let roll = Double.random(in: 0..<1, using: &rng)
        return line(in: CapSpeech.pool(for: pose.shown, rapid: rapid, hour: hour, roll: roll))
    }

    /// The next line from one pool (the sky has been refreshed), dealt like any other: none comes back until the pool is used up.
    func line(in pool: CapLinePool) -> CapLine {
        let lines = pool.lines
        let index = bag.draw(pool: pool.id, count: lines.count, using: &rng)
        if persists, let data = try? JSONEncoder().encode(bag) { UserDefaults.standard.set(data, forKey: Self.key) }
        return CapLine(pool: pool.id, index: index, text: lines[index])
    }
}
