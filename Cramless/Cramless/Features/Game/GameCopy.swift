import SwiftUI

// The words and pictures of the game loop: quests, badges, the flame's stages, the skies and the icons. Copy is short, warm
// and specific, and nothing says what was missed.

// MARK: - Quests

extension QuestKind {
    var title: LocalizedStringResource {
        switch self {
        case .finishSession: "Finish today's session"
        case .rescueFading: "Save 3 fading stars"
        case .ownWords: "Answer 2 in your own words"
        case .beforeNoon: "Study before noon"
        case .fixMixUp: "Fix a mix-up"
        case .learnNew: "Meet 5 new questions"
        case .rightInARow: "Get 5 right in a row"
        case .examTopic: "Practise for your exam"
        case .event: "Today's event"
        }
    }

    var symbol: String {
        switch self {
        case .finishSession: "sun.max.fill"
        case .rescueFading: "sparkles"
        case .ownWords: "pencil.line"
        case .beforeNoon: "sunrise.fill"
        case .fixMixUp: "arrow.triangle.merge"
        case .learnNew: "star.fill"
        case .rightInARow: "music.note"
        case .examTopic: "graduationcap.fill"
        case .event: "gift.fill"
        }
    }

    var tint: CourseColor {
        switch self {
        case .finishSession: .tangerine
        case .rescueFading: .sun
        case .ownWords: .sky
        case .beforeNoon: .rose
        case .fixMixUp: .mint
        case .learnNew: .mint
        case .rightInARow: .rose
        case .examTopic: .sky
        case .event: .sun
        }
    }
}

extension QuestRow {
    /// "Practise for Bio 101" for the exam quest, the kind's own words for the rest.
    var title: LocalizedStringResource {
        if kind == .examTopic, let subject { return "Practise for \(subject)" }
        return kind.title
    }

    /// "1 of 3" for a quest that counts, nothing for one that is a single thing to do.
    var progressText: LocalizedStringResource? {
        guard progress.goal > 1, !isDone else { return nil }
        return "\(progress.done) of \(progress.goal)"
    }
}

enum QuestCopy {
    /// "5 of 12 this week", on the card and in the summary.
    static func week(_ count: Int, of goal: Int) -> LocalizedStringResource {
        "\(count) of \(goal) this week"
    }

    /// What the week is working toward, said gently.
    static func skyLine(_ quests: QuestsToday) -> LocalizedStringResource {
        if quests.weekLit { return "This week lit a new sky" }
        guard let sky = quests.nextSky else { return "Every sky is lit" }
        return "\(sky.title) lights at \(quests.weekGoal)"
    }
}

// MARK: - The flame's stages

extension StreakStage {
    /// "A week", "A month": what the streak has grown into.
    var title: LocalizedStringResource {
        switch self {
        case .none: "No streak yet"
        case .spark: "A spark"
        case .week: "A week"
        case .month: "A month"
        case .hundred: "A hundred days"
        case .year: "A year"
        }
    }
}

enum MilestoneCopy {
    /// The summary's title on a milestone: "30 days."
    static func title(_ days: Int) -> LocalizedStringResource { "\(days) days." }

    /// One warm line for each milestone, about the memory, never about the number.
    static func line(_ days: Int) -> LocalizedStringResource {
        switch days {
        case ..<7: "Three days in a row. A habit is starting."
        case 7..<30: "A whole week. What you reviewed is holding."
        case 30..<100: "A month of showing up. Your sky is brighter for it."
        case 100..<365: "A hundred days. That is a lot of stars kept lit."
        default: "A year. Cap would like to say thank you."
        }
    }

    /// "Next: 30 days" on the streak screen, or nothing once every milestone is behind.
    static func next(after days: Int) -> LocalizedStringResource? {
        StreakStage.nextMilestone(after: days).map { "Next: \($0) days" }
    }
}

// MARK: - Badges

extension Badge {
    var title: LocalizedStringResource {
        switch self {
        case .firstSession: "First light"
        case .saves10: "Star saver"
        case .ownWords25: "In your words"
        case .firstFix: "Untangled"
        case .fifthFix: "Clear head"
        case .streak7: "A week"
        case .streak30: "A month"
        case .streak100: "A hundred"
        case .streak365: "A year"
        case .ready: "Ready"
        case .calledIt: "Called it"
        case .thousand: "A thousand"
        case .comeback: "Comeback"
        }
    }

    /// What earns it, in a sentence.
    var blurb: LocalizedStringResource {
        switch self {
        case .firstSession: "You finished your first session."
        case .saves10: "You saved 10 stars that were fading."
        case .ownWords25: "You answered 25 questions in your own words."
        case .firstFix: "You fixed a mix-up."
        case .fifthFix: "You fixed 5 mix-ups."
        case .streak7: "7 days in a row."
        case .streak30: "30 days in a row."
        case .streak100: "100 days in a row."
        case .streak365: "365 days in a row."
        case .ready: "You were 80% ready on the morning of an exam."
        case .calledIt: "Your grade landed within 5 points of your readiness."
        case .thousand: "1,000 answers."
        case .comeback: "You repaired a day you missed."
        }
    }

    /// What it says on the summary that earned it. A count it has passed reads as what's true: 12 saves never say "You saved 10".
    func earned(saves: Int) -> LocalizedStringResource {
        if self == .saves10, saves > target { return "You've saved \(saves) stars that were fading." }
        return blurb
    }

    /// What is on the medal. A streak badge shows the flame its stage has.
    enum Glyph: Equatable {
        case symbol(String)
        case flame(StreakStage)
    }

    var glyph: Glyph {
        switch self {
        case .firstSession: .symbol("sunrise.fill")
        case .saves10: .symbol("star.circle.fill")
        case .ownWords25: .symbol("text.bubble.fill")
        case .firstFix: .symbol("arrow.triangle.merge")
        case .fifthFix: .symbol("checkmark.seal.fill")
        case .streak7: .flame(.week)
        case .streak30: .flame(.month)
        case .streak100: .flame(.hundred)
        case .streak365: .flame(.year)
        case .ready: .symbol("target")
        case .calledIt: .symbol("scope")
        case .thousand: .symbol("number.circle.fill")
        case .comeback: .symbol("bandage.fill")
        }
    }

    /// The medal's metal: a light, a mid and a deep tone of one hue.
    var metal: (light: Color, mid: Color, deep: Color) {
        switch self {
        case .streak100, .streak365, .thousand:
            (Color(hex: 0xFFE9A3), Color(hex: 0xF5B320), Color(hex: 0xB8780A))
        case .firstSession, .streak7, .streak30, .comeback:
            (Color(hex: 0xFFC48A), Color(hex: 0xFF8A2A), Color(hex: 0xB8470A))
        case .saves10, .ready, .ownWords25:
            (Color(hex: 0xBFE6FF), Color(hex: 0x5AB4F0), Color(hex: 0x1F6AA8))
        case .firstFix, .fifthFix, .calledIt:
            (Color(hex: 0xA8F0D2), Color(hex: 0x22C38E), Color(hex: 0x0B7F5A))
        }
    }
}

enum BadgeCopy {
    static func earned(on date: Date, calendar: Calendar) -> LocalizedStringResource {
        "Earned \(date.formatted(LibraryFormat.dateStyle(calendar).month(.abbreviated).day()))"
    }

    static func progress(_ progress: BadgeProgress) -> LocalizedStringResource {
        "\(progress.value) of \(progress.target)"
    }

    static func count(earned: Int, of total: Int) -> LocalizedStringResource {
        "\(earned) of \(total) earned"
    }
}

// MARK: - Skies

extension SkyTheme {
    var title: LocalizedStringResource {
        switch self {
        case .night: "Night"
        case .dusk: "Dusk"
        case .aurora: "Aurora"
        case .ember: "Ember"
        case .bloom: "Bloom"
        case .glacier: "Glacier"
        }
    }

    /// What lights it, for the one that is still dark.
    var lockedLine: LocalizedStringResource {
        let weeks = weekToUnlock
        return weeks <= 1 ? "A week of 12 quests" : "\(weeks) weeks of 12 quests"
    }
}

// MARK: - Icons

extension AppIconChoice {
    var title: LocalizedStringResource {
        switch self {
        case .standard: "Cap"
        case .night: "Night"
        case .ember: "Ember"
        case .gold: "Gold"
        case .aurora: "Aurora"
        }
    }

    /// "At 30 days": what unlocks it, on the one that is still dark.
    var lockedLine: LocalizedStringResource { "At \(unlockDays) days" }
}
