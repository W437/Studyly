import Foundation

/// How long a streak is, as the flame shows it: five stages, each a step up in how the flame looks (`StreakFlame`).
/// Foundation only, so the widgets and the Watch read it too.
enum StreakStage: Int, CaseIterable, Sendable, Comparable {
    /// No streak: an unlit flame.
    case none
    /// 1 to 6 days: a small flame.
    case spark
    /// 7 to 29: the full flame.
    case week
    /// 30 to 99: a glow, and embers.
    case month
    /// 100 to 364: gold.
    case hundred
    /// 365 and more: gold, with a star above it.
    case year

    init(days: Int) {
        switch days {
        case ..<1: self = .none
        case 1..<7: self = .spark
        case 7..<30: self = .week
        case 30..<100: self = .month
        case 100..<365: self = .hundred
        default: self = .year
        }
    }

    /// The streak length at which the stage begins.
    var firstDay: Int {
        switch self {
        case .none: 0
        case .spark: 1
        case .week: 7
        case .month: 30
        case .hundred: 100
        case .year: 365
        }
    }

    /// The stage a streak grows into next; nil for the last one.
    var next: StreakStage? { StreakStage(rawValue: rawValue + 1) }

    static func < (a: StreakStage, b: StreakStage) -> Bool { a.rawValue < b.rawValue }

    // MARK: Milestones

    /// The lengths that mark a moment: the summary says so, the streak screen lists them, and the day before one the
    /// reminder says one session makes it. The flame changes at 7, 30, 100 and 365; 3 days is the first, small one.
    static let milestones = [3, 7, 30, 100, 365]

    /// The first milestone after `days`; nil once the last one is behind.
    static func nextMilestone(after days: Int) -> Int? {
        milestones.first { $0 > days }
    }

    /// The biggest milestone passed going from `before` to `after` days (a repair can jump over two).
    static func milestoneCrossed(from before: Int, to after: Int) -> Int? {
        milestones.last { $0 > before && $0 <= after }
    }
}
