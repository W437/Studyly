import Foundation

/// A kind of daily quest. The raw values are the bits of `DayRecord.questMask`: they are stored and synced, so they never
/// change and never move.
enum QuestKind: Int, CaseIterable, Sendable, Codable {
    /// Finish today's session. Every day has it.
    case finishSession = 0
    /// Save 3 fading stars: right answers on memories that had fallen below 70% (`ReviewOutcome.isSave`).
    case rescueFading = 1
    /// Answer 2 questions in your own words.
    case ownWords = 2
    /// Finish a session before noon. Only offered to someone who opens the app before 10:00.
    case beforeNoon = 3
    /// Fix a mix-up.
    case fixMixUp = 4
    /// Meet 5 new questions.
    case learnNew = 5
    /// Get 5 right in a row, in one session.
    case rightInARow = 6
    /// Answer 5 questions an exam in the next month covers.
    case examTopic = 7
    /// An In-App Event's own quest (Phase 13).
    case event = 8

    var bit: Int { 1 << rawValue }

    /// What it takes: how many of the thing (a session, a save, an answer…).
    var goal: Int {
        switch self {
        case .finishSession, .beforeNoon, .fixMixUp, .event: 1
        case .ownWords: 2
        case .rescueFading: 3
        case .learnNew, .rightInARow, .examTopic: 5
        }
    }

    /// The kinds whose bits are set in a day's mask, in bit order.
    static func kinds(inMask mask: Int) -> [QuestKind] {
        allCases.filter { mask & $0.bit != 0 }
    }
}

/// What the day's answers amount to, as the quests read them (`AppModel.questFacts(forDay:)` works it out from the log).
struct QuestFacts: Sendable, Equatable {
    var sessionsFinished = 0
    /// The minute of the day (0…1439) the first session of the day finished.
    var firstFinishedMinute: Int?
    var saves = 0
    var ownWordsAnswers = 0
    var mixUpsFixed = 0
    /// Questions seen for the first time.
    var newLearned = 0
    /// The longest run of right answers in a session (flashcards neither build nor break it: `ComboRun`).
    var bestRun = 0
    /// Answers to questions an exam in the next month covers.
    var examAnswers = 0
    var eventDone = false
}

struct QuestProgress: Sendable, Equatable {
    /// How far, never past `goal`.
    var done: Int
    var goal: Int

    var isComplete: Bool { done >= goal }
}

/// What a day's picks depend on: what there is to study, and when the person first opened the app.
struct QuestContext: Sendable, Equatable {
    /// Minutes after midnight when the quests are picked (the first time the app is opened that day).
    var minuteOfDay = 12 * 60
    var hasMaterial = true
    /// An exam is tomorrow: the day is for sleep, and has no quests.
    var examEve = false
    /// Studied questions whose recall is under 70% now.
    var fadingStars = 0
    /// Questions answered in your own words.
    var ownWordsItems = 0
    var openMixUps = 0
    /// Questions not yet seen.
    var newItems = 0
    /// Questions the app checks (everything but flashcards).
    var checkedItems = 0
    /// Questions an exam in the next month covers.
    var examItems = 0
    var eventActive = false
    /// Yesterday's picks, so a quest doesn't come two days running when another will do.
    var yesterday: [QuestKind] = []
}

/// Daily quests: one that every day has, and two the person can do today. Pure and seeded, so a day's picks are the same
/// on every device and can be tested. There is no currency: finishing 12 in a week lights a new sky (`SkyTheme`).
enum QuestEngine {
    /// Quests a day has, and so the most that count toward a week.
    static let perDay = 3
    /// Quests in a week that light a sky.
    static let weeklyGoal = 12
    static let beforeNoonPickedBefore = 10 * 60
    static let noon = 12 * 60
    /// Fading stars needed before "save 3" is offered, so it is always possible.
    static let fadingNeeded = 3

    /// Seeds the order, so it differs from day to day and never between devices.
    private static let seedID = UUID(uuidString: "5C0F5E57-9A1B-4C3D-8E2F-0B6A7D4C1E93")!

    // MARK: Picking

    static func isEligible(_ kind: QuestKind, _ context: QuestContext) -> Bool {
        guard context.hasMaterial, !context.examEve else { return false }
        switch kind {
        case .finishSession: return true
        case .rescueFading: return context.fadingStars >= fadingNeeded
        case .ownWords: return context.ownWordsItems >= kind.goal
        case .beforeNoon: return context.minuteOfDay < beforeNoonPickedBefore
        case .fixMixUp: return context.openMixUps >= 1
        case .learnNew: return context.newItems >= kind.goal
        case .rightInARow: return context.checkedItems >= kind.goal
        case .examTopic: return context.examItems >= kind.goal
        case .event: return context.eventActive
        }
    }

    /// The day's quests: `finishSession` first, then an event's quest when there is one, then the others the context
    /// allows, in a seeded order that puts yesterday's last. Nothing on exam eve, and nothing with no material.
    static func pick(day: Int, context: QuestContext) -> [QuestKind] {
        guard context.hasMaterial, !context.examEve else { return [] }
        var picks: [QuestKind] = [.finishSession]
        if isEligible(.event, context) { picks.append(.event) }
        let others = QuestKind.allCases.filter { $0 != .finishSession && $0 != .event && isEligible($0, context) }
        let ranked = others.sorted { a, b in
            let (ya, yb) = (context.yesterday.contains(a), context.yesterday.contains(b))
            if ya != yb { return !ya }
            return rank(a, day: day) < rank(b, day: day)
        }
        picks += ranked.prefix(max(0, perDay - picks.count))
        return picks
    }

    /// A hash of the day and the kind. The kind is mixed in after the day's seed, not folded into it (`seed`'s salt is XORed
    /// with the day, so small salts would only shuffle a day's low bits, and a week's picks would echo each other).
    private static func rank(_ kind: QuestKind, day: Int) -> UInt64 {
        StableRandom.mix(StableRandom.seed(seedID, day: day) ^ (UInt64(kind.rawValue + 1) &* 0x9E37_79B9_7F4A_7C15))
    }

    // MARK: Progress

    static func progress(_ kind: QuestKind, facts: QuestFacts) -> QuestProgress {
        let value: Int
        switch kind {
        case .finishSession: value = facts.sessionsFinished
        case .rescueFading: value = facts.saves
        case .ownWords: value = facts.ownWordsAnswers
        case .beforeNoon: value = (facts.firstFinishedMinute ?? Int.max) < noon ? 1 : 0
        case .fixMixUp: value = facts.mixUpsFixed
        case .learnNew: value = facts.newLearned
        case .rightInARow: value = facts.bestRun
        case .examTopic: value = facts.examAnswers
        case .event: value = facts.eventDone ? 1 : 0
        }
        return QuestProgress(done: min(max(0, value), kind.goal), goal: kind.goal)
    }

    /// The picks the day's facts have completed.
    static func completed(picks: [QuestKind], facts: QuestFacts) -> [QuestKind] {
        picks.filter { progress($0, facts: facts).isComplete }
    }

    // MARK: The week

    /// Quests a day's mask counts for: at most `perDay`, however many bits two devices together set.
    static func count(mask: Int) -> Int {
        min(perDay, QuestKind.kinds(inMask: mask).count)
    }

    /// The first day of the calendar week containing `day`, for a calendar whose weeks begin on `firstWeekday`
    /// (1 = Sunday … 7 = Saturday).
    static func weekStart(of day: Int, firstWeekday: Int) -> Int {
        day - (Calendar.weekday(dayNumber: day) - firstWeekday + 7) % 7
    }

    /// Quests done this calendar week, from each day's mask (by day number).
    static func weekCount(masks: [Int: Int], today: Int, firstWeekday: Int) -> Int {
        let start = weekStart(of: today, firstWeekday: firstWeekday)
        return (start...(start + 6)).reduce(0) { $0 + count(mask: masks[$1] ?? 0) }
    }
}
