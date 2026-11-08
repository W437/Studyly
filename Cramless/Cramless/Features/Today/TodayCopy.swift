import Foundation

/// Today's words, as pure functions of plain values (`TodayCopyTests`). Counts are one localized key each with its plural forms in
/// `docs/l10n/plurals.json`. Topic and course names are the person's own and are never lower-cased; lists are joined with "and" (the
/// session interleaves its topics, so nothing says "then" or "first"). The questions are "questions", never "cards", and what is due
/// is "to review".
enum TodayCopy {
    // MARK: The band

    /// "Good morning, Maya" (5 to 12), "Good afternoon" (12 to 17), "Good evening"; on the first day "Welcome, Maya".
    static func greeting(hour: Int, name: String, firstDay: Bool) -> String {
        let first = name.split(separator: " ").first.map(String.init) ?? ""
        if firstDay {
            return first.isEmpty ? String(localized: "Welcome") : String(localized: "Welcome, \(first)")
        }
        switch hour {
        case 5..<12: return first.isEmpty ? String(localized: "Good morning") : String(localized: "Good morning, \(first)")
        case 12..<17: return first.isEmpty ? String(localized: "Good afternoon") : String(localized: "Good afternoon, \(first)")
        default: return first.isEmpty ? String(localized: "Good evening") : String(localized: "Good evening, \(first)")
        }
    }

    /// The band's pill: "17 to review", or with nothing to review "63 stars".
    static func starsPill(stars: Int, toReview: Int) -> String {
        toReview > 0 ? String(localized: "\(toReview) to review") : String(localized: SkyCopy.stars(stars))
    }

    // MARK: When an exam is

    /// The day an exam is, short, for the day card's chip: "Today at 18:00", "Tomorrow at 10:00", "Tue" within the week, "29 Nov"
    /// after it. `spoken` gives the weekday in full, for VoiceOver ("Tuesday"). The dates and times are in the calendar's own locale.
    static func examDay(_ date: Date, now: Date, calendar: Calendar, spoken: Bool = false) -> String {
        let days = calendar.dayDistance(from: now, to: date)
        let locale = calendar.locale ?? .current
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                                   timeZone: calendar.timeZone))
        switch days {
        case ..<1: return String(localized: "Today at \(time)")
        case 1: return String(localized: "Tomorrow at \(time)")
        case 2...6: return date.formatted(style.weekday(spoken ? .wide : .abbreviated))
        default: return date.formatted(style.day().month(spoken ? .wide : .abbreviated))
        }
    }

    /// The chip: "Chem 110 Quiz · Tue".
    static func chip(_ title: String, day: String) -> String { "\(title) · \(day)" }

    /// "23 days", "6 months": how far away an exam is, for "can wait" lines.
    static func distance(days: Int) -> String {
        if days < 60 { return String(localized: "\(max(1, days)) days") }
        let months = max(2, Int((Double(days) / 30.44).rounded()))
        return String(localized: "\(months) months")
    }

    // MARK: The day card

    /// The card's title: up to two topics, the rest counted ("Limiting reagents and Stoichiometry", "Cell cycle, Meiosis, and 2 more").
    static func topics(_ names: [String], limit: Int = 2) -> String {
        let clean = names.filter { !$0.isEmpty }
        guard clean.count > limit else { return clean.formatted(.list(type: .and)) }
        let shown = Array(clean.prefix(limit)) + [String(localized: "\(clean.count - limit) more")]
        return shown.formatted(.list(type: .and))
    }

    /// The title when no one exam has half the session: its courses, soonest exam first, up to three ("Chem 110, Bio 101, and AP
    /// Psychology").
    static func courses(_ names: [String]) -> String { topics(names, limit: 3) }

    /// The ring's words: "41% ready".
    static func ready(_ value: Double) -> String { String(localized: "\(CLFormat.percent(value)) ready") }

    /// VoiceOver for the ring: "41 percent ready".
    static func readySpoken(_ value: Double) -> String {
        String(localized: "\(Int((max(0, min(1, value)) * 100).rounded())) percent ready")
    }

    /// "6 of 15 minutes done.", once part of the day's goal is done.
    static func partWay(done: Int, goal: Int) -> String { String(localized: "\(done) of \(goal) minutes done.") }

    /// Honest about a backlog, kind about the pace: "Catching up: about 4 days at 15 minutes a day." No count: the band's pill already
    /// says how many are to review, and a second, different number beside it would only confuse.
    static func catchUp(goal: Int, days: Int) -> String {
        String(localized: "Catching up: about \(max(1, days)) days at \(goal) minutes a day.")
    }

    /// The eve: "Limiting reagents and Stoichiometry, then sleep."
    static func eveLine(topics: [String]) -> String {
        guard !topics.isEmpty else { return String(localized: "Then sleep. That's the whole plan tonight.") }
        return String(localized: "\(Self.topics(topics)), then sleep.")
    }

    /// Under the eve's title once there is nothing left to do tonight.
    static let sleep = String(localized: "Sleep is part of studying.")

    /// The done card's line; in Quiet mode it says nothing about the streak.
    static func doneLine(quiet: Bool) -> String {
        quiet ? String(localized: "Back tomorrow.") : String(localized: "Back tomorrow. Your streak is safe.")
    }

    /// Under "All lit".
    static let allLit = String(localized: "Nothing to review right now.")

    /// Under the first day's title, and under "Add your first material".
    static let firstSet = String(localized: "Capling turns a page from class into questions.")
    static let firstMaterial = String(localized: "One page from class is enough to start.")

    // MARK: Quests

    /// The quests row: "0 of 3 quests".
    static func quests(done: Int, of total: Int) -> String { String(localized: "\(done) of \(total) quests") }

    // MARK: Cap

    /// The eve's quiet line in Cap's place: the other exams wait. `examTitle` names tonight's exams, all of them; `others` are the other
    /// courses, soonest first.
    static func quietLine(examTitle: String, others: [String]) -> String {
        let quiet = String(localized: "Cap is quiet today.")
        switch others.count {
        case 0: return quiet
        case 1, 2: return "\(quiet) \(String(localized: "\(others.formatted(.list(type: .and))) can wait until after \(examTitle)."))"
        default: return "\(quiet) \(String(localized: "Your other exams can wait until after \(examTitle)."))"
        }
    }
}
