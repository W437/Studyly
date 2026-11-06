import Foundation

/// Today's words, as pure functions of plain values (`TodayCopyTests`). Counts are one localized key each with its plural forms in
/// `docs/l10n/plurals.json`. Topic names are the person's own and are never lower-cased; lists are joined with "and" (the session
/// interleaves its topics, so nothing says "then" or "first"). The questions are "questions", never "cards".
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

    /// The band's pill: "17 stars dimming", or with none dimming "63 stars".
    static func starsPill(stars: Int, dimming: Int) -> String {
        dimming > 0 ? String(localized: "\(dimming) stars dimming") : String(localized: SkyCopy.stars(stars))
    }

    // MARK: When an exam is

    /// "Today · 10:00", "Tomorrow · 10:00", "Sun · in 2 days", "29 Nov · in 23 days", and from two months away just "21 May". The
    /// dates and times are in the calendar's own locale; the words around them are localized.
    static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dayDistance(from: now, to: date)
        let locale = calendar.locale ?? .current
        func style() -> Date.FormatStyle {
            Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        }
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                                   timeZone: calendar.timeZone))
        switch days {
        case ..<1: return String(localized: "Today · \(time)")
        case 1: return String(localized: "Tomorrow · \(time)")
        case 2...6:
            let weekday = date.formatted(style().weekday(.abbreviated))
            return "\(weekday) · \(inDays(days))"
        case 7..<60:
            let day = date.formatted(style().day().month(.abbreviated))
            return "\(day) · \(inDays(days))"
        default:
            return date.formatted(style().day().month(.abbreviated))
        }
    }

    /// "in 23 days".
    static func inDays(_ days: Int) -> String { String(localized: "in \(days) days") }

    /// "23 days", "6 months": how far away an exam is, for "can wait" lines.
    static func distance(days: Int) -> String {
        if days < 60 { return String(localized: "\(max(1, days)) days") }
        let months = max(2, Int((Double(days) / 30.44).rounded()))
        return String(localized: "\(months) months")
    }

    // MARK: The day card

    /// The card's title: up to two topics, the rest counted ("Limiting reagents and Stoichiometry", "Cell cycle, Meiosis and 2 more").
    static func topics(_ names: [String], limit: Int = 2) -> String {
        let clean = names.filter { !$0.isEmpty }
        guard clean.count > limit else { return clean.formatted(.list(type: .and)) }
        let shown = Array(clean.prefix(limit)) + [String(localized: "\(clean.count - limit) more")]
        return shown.formatted(.list(type: .and))
    }

    /// Why today holds what it holds, in one sentence. `forExam`: the session mostly serves one exam.
    static func reason(weak: Bool, due: Int, new: Int, forExam: Bool) -> String {
        switch (weak, due > 0, new > 0) {
        case (true, true, _):
            return forExam ? String(localized: "The weakest topics for this exam, plus \(due) questions you're about to forget.")
                : String(localized: "Your weakest topics, plus \(due) questions you're about to forget.")
        case (true, false, true):
            return forExam ? String(localized: "The weakest topics for this exam, plus \(new) new questions.")
                : String(localized: "Your weakest topics, plus \(new) new questions.")
        case (true, false, false):
            return forExam ? String(localized: "The weakest topics for this exam.") : String(localized: "Your weakest topics.")
        case (false, true, true):
            return String(localized: "\(due) questions you're about to forget, and \(new) new ones.")
        case (false, true, false):
            return String(localized: "\(due) questions you're about to forget.")
        case (false, false, true):
            return forExam ? String(localized: "\(new) new questions, so it's all in before the exam.")
                : String(localized: "\(new) new questions.")
        case (false, false, false):
            return String(localized: "A short review of what you know.")
        }
    }

    /// "6 of 15 minutes done.", once part of the day's goal is done.
    static func partWay(done: Int, goal: Int) -> String { String(localized: "\(done) of \(goal) minutes done.") }

    /// Honest about a backlog, kind about the pace.
    static func catchUp(due: Int, goal: Int, days: Int) -> String {
        let piled = String(localized: "\(due) reviews piled up.")
        let pace = String(localized: "At \(goal) minutes a day they're cleared in \(max(1, days)) days, starting with what you're closest to forgetting.")
        return "\(piled) \(pace)"
    }

    /// "42% ready now".
    static func readyNow(_ value: Double) -> String { String(localized: "\(CLFormat.percent(value)) ready now") }

    /// "about 52% after today": a projection, and it says so.
    static func afterToday(_ value: Double) -> String { String(localized: "about \(CLFormat.percent(value)) after today") }

    /// VoiceOver for the rings: "42 percent ready now, about 52 percent after today, projected".
    static func ringsSpoken(now: Double, after: Double?) -> String {
        let percentNow = Int((max(0, min(1, now)) * 100).rounded())
        guard let after else { return String(localized: "\(percentNow) percent ready now") }
        let percentAfter = Int((max(0, min(1, after)) * 100).rounded())
        return String(localized: "\(percentNow) percent ready now, about \(percentAfter) percent after today, projected")
    }

    /// Under the rings when an exam has few questions yet: "Based on 7 questions so far."
    static func basedOn(_ questions: Int) -> String { String(localized: "Based on \(questions) questions so far.") }

    /// Readiness this thin is a guess: under this many questions in scope the card says what it is based on.
    static let fewQuestions = 15

    /// The eve: "10 minutes on Limiting reagents and Stoichiometry, then sleep. That's the whole plan tonight."
    static func eveReason(topics: [String]) -> String {
        guard !topics.isEmpty else {
            return String(localized: "10 minutes on your weak spots, then sleep. That's the whole plan tonight.")
        }
        return String(localized: "10 minutes on \(Self.topics(topics)), then sleep. That's the whole plan tonight.")
    }

    /// "Chem 110 Quiz is tomorrow. Sleep is part of studying." (with its time once tonight's session is done).
    static func eveRest(title: String, time: String?) -> String {
        guard let time else { return String(localized: "\(title) is tomorrow. Sleep is part of studying.") }
        return String(localized: "\(title) is tomorrow at \(time). Sleep is part of studying.")
    }

    /// The done card's line: "15 min · 24 answers".
    static func doneLine(minutes: Int, answers: Int) -> String { String(localized: "\(minutes) min · \(answers) answers") }

    /// "Chem 110 Quiz: 52% ready".
    static func doneRing(title: String, value: Double) -> String { String(localized: "\(title): \(CLFormat.percent(value)) ready") }

    /// "+10% today · 2 days to go"; "Steady today" with no change; the days left only while the exam is still ahead.
    static func doneDelta(_ delta: Double, daysLeft: Int) -> String {
        let points = Int((delta * 100).rounded())
        let change = points == 0 ? String(localized: "Steady today") : String(localized: "\(CLFormat.delta(delta)) today")
        guard daysLeft > 0 else { return change }
        return "\(change) · \(String(localized: "\(daysLeft) days to go"))"
    }

    // MARK: Your plan

    /// What a day of the strip says under its mark: "15m", "10m", "Exam", "Done".
    static func stripCaption(_ day: TodayPlanDay) -> String {
        switch day.mark {
        case .studied, .frozen, .missed: return ""
        case .done: return String(localized: "Done")
        case .minutes(let m), .eve(let m): return String(localized: "\(m)m")
        case .exam: return String(localized: "Exam")
        }
    }

    /// One day of the strip in words, for VoiceOver and the large text sizes: "Saturday: the night before Chem 110 Quiz, 10 minutes".
    static func stripDay(_ day: TodayPlanDay, calendar: Calendar) -> String {
        let name = day.isToday ? String(localized: "Today")
            : day.date.formatted(Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar,
                                                  timeZone: calendar.timeZone).weekday(.wide))
        let what: String
        switch day.mark {
        case .studied: what = String(localized: "studied")
        case .frozen: what = String(localized: "covered by a freeze")
        case .missed: what = String(localized: "not studied")
        case .done: what = String(localized: "done")
        case .minutes(let m): what = String(localized: "\(m) minutes planned")
        case .eve(let m):
            what = String(localized: "the night before \(day.examTitles.formatted(.list(type: .and))), \(m) minutes")
        case .exam: what = day.examTitles.formatted(.list(type: .and))
        }
        return "\(name): \(what)"
    }

    /// The whole strip for VoiceOver, one day after another.
    static func stripSpoken(_ days: [TodayPlanDay], calendar: Calendar) -> String {
        days.map { stripDay($0, calendar: calendar) }.joined(separator: ". ") + "."
    }

    /// "0 of 3 quests today · 5 of 12 this week".
    static func questsLine(done: Int, of total: Int, week: Int, weekGoal: Int) -> String {
        "\(String(localized: "\(done) of \(total) quests today")) · \(String(localized: QuestCopy.week(week, of: weekGoal)))"
    }

    // MARK: Cap noticed

    /// "1 of 2" over Cap's card.
    static func noticeCount(_ index: Int, of total: Int) -> String { String(localized: "\(index) of \(total)") }

    /// The eve's quiet line in Cap's place: the other exams wait. `others` are the other courses, soonest first.
    static func quietLine(examTitle: String, others: [String]) -> String {
        let quiet = String(localized: "Cap is quiet tonight.")
        switch others.count {
        case 0: return quiet
        case 1, 2: return "\(quiet) \(String(localized: "\(others.formatted(.list(type: .and))) can wait until after \(examTitle)."))"
        default: return "\(quiet) \(String(localized: "Your other exams can wait until after \(examTitle)."))"
        }
    }

    // MARK: Exams

    /// The card in the exams' place when there is material and no exam yet.
    static let addExamTitle: LocalizedStringResource = "When is your next exam?"
    static let addExamDetail: LocalizedStringResource = "Add the date and every day's plan aims at it."
}
