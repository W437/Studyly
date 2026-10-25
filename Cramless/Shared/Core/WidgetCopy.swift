import Foundation

/// The words the widgets, the Live Activities and Siri use, built from snapshot values. Pure and tested
/// (`CramlessTests/WidgetSnapshotTests.swift`). Voice: short, specific, calm, sentence case; never guilt.
enum WidgetCopy {
    /// 0…1 → 0…100, rounded.
    static func percent(_ value: Double) -> Int {
        Int((max(0, min(1, value)) * 100).rounded())
    }

    /// A count of days as a label: "Today", "Tomorrow", "2 days", "23 days".
    static func days(_ n: Int) -> String {
        switch n {
        case ..<1: "Today"
        case 1: "Tomorrow"
        default: "\(n) days"
        }
    }

    /// Compact days for tight spots: "Today", "1d", "23d".
    static func daysShort(_ n: Int) -> String {
        n < 1 ? "Today" : "\(n)d"
    }

    /// "+5% this week", "−3% this week"; nil when readiness moved less than a point.
    static func delta(_ d: Double) -> String? {
        let points = Int((d * 100).rounded())
        guard points != 0 else { return nil }
        return points > 0 ? "+\(points)% this week" : "−\(abs(points))% this week"
    }

    static func plural(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }

    /// "18 reviews · 6 new · 2 weak spots", leaving out the zeros. Nil when there's nothing to count (or the counts
    /// are from an earlier day).
    /// Each part keeps its number and words together (no-break spaces), so a line wraps between parts, never
    /// inside "2 weak spots".
    static func sessionCounts(_ today: WidgetSnapshot.Today) -> String? {
        guard today.hasCounts else { return nil }
        var parts: [String] = []
        if today.reviews > 0 { parts.append(plural(today.reviews, "review", "reviews")) }
        if today.newItems > 0 { parts.append("\(today.newItems) new") }
        if today.weakSpots > 0 { parts.append(plural(today.weakSpots, "weak spot", "weak spots")) }
        return parts.map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }.joined(separator: " · ")
    }

    /// "Weak spots: Meiosis I vs II, Chromosome number", or with `maxNames: 1` "Weak spots: Meiosis I vs II +1";
    /// nil without names.
    static func weakSpotsLine(_ today: WidgetSnapshot.Today, maxNames: Int = 2) -> String? {
        let all = today.weakChips.filter { !$0.isEmpty }
        let names = all.prefix(max(1, maxNames))
        guard !names.isEmpty else { return nil }
        let more = all.count - names.count
        return "\(all.count == 1 ? "Weak spot" : "Weak spots"): \(names.joined(separator: ", "))\(more > 0 ? " +\(more)" : "")"
    }

    /// Where today stands, for the end of a line: "15 min today", "6 of 15 min", "done today".
    static func todayProgress(_ s: WidgetSnapshot) -> String {
        if s.streak.studiedToday { return "done today" }
        if s.today.doneMinutes > 0 { return "\(s.today.doneMinutes) of \(s.today.goalMinutes) min" }
        return "\(s.today.sessionMinutes) min today"
    }

    /// The Lock Screen inline line: "12-day streak · 15 min today".
    static func inline(_ s: WidgetSnapshot?) -> String {
        guard let s else { return "Open Capling to start" }
        let streak = s.streak.current
        if s.streak.studiedToday {
            return streak > 0 ? "\(streak)-day streak · done today" : "Done for today"
        }
        let progress = todayProgress(s)
        return streak > 0 ? "\(streak)-day streak · \(progress)" : sentenceCase(progress)
    }

    /// The Lock Screen "today" widget: a big headline and a line under it ("18 due" / "15 min keeps your streak").
    static func todayGlance(_ s: WidgetSnapshot?) -> (headline: String, detail: String) {
        guard let s else { return ("Get started", "Open the app to set up") }
        let streak = s.streak.current
        let minutes = s.today.sessionMinutes
        if s.streak.studiedToday {
            return ("Done", streak > 1 ? "\(streak)-day streak" : "See you tomorrow")
        }
        let detail = streak > 1 ? "\(minutes) min keeps your streak" : "\(minutes) min today"
        if s.today.hasCounts, s.today.reviews > 0 { return ("\(s.today.reviews) due", detail) }
        if s.today.hasCounts, s.today.newItems > 0 { return ("\(s.today.newItems) new", detail) }
        return ("\(minutes) min", streak > 1 ? "Keeps your \(streak)-day streak" : "Today's session")
    }

    /// Siri's answer to "How ready am I?": "64% ready for Bio 101 Midterm, 23 days to go." Mentions the exam after
    /// it when that one is within a month too.
    static func readinessAnswer(_ s: WidgetSnapshot?, now: Date, calendar: Calendar) -> String {
        guard let s else { return "Open Capling once and I can tell you how ready you are." }
        let exams = s.exams.filter { !$0.isOver(at: now) }
        guard let first = exams.first else {
            return "You haven't added an exam yet. Add one in Capling and it will track how ready you are."
        }
        let d = WidgetCalendar.days(from: now, to: first.date, calendar: calendar)
        let p = percent(first.readiness)
        var text: String
        if p < 5 {
            text = "You're just getting started on \(first.title)"
            text += d < 1 ? ", and it's today." : d == 1 ? ", and it's tomorrow." : ": \(d) days to go."
        } else {
            text = "\(p)% ready for \(first.title)"
            text += d < 1 ? ". It's today." : d == 1 ? ". It's tomorrow." : ", \(d) days to go."
        }
        let points = Int((first.delta * 100).rounded())
        if points > 0, d > 1 { text += " Up \(plural(points, "point", "points")) this week." }
        if exams.count > 1 {
            let second = exams[1]
            let d2 = WidgetCalendar.days(from: now, to: second.date, calendar: calendar)
            if d2 <= 30 {
                let when = d2 < 1 ? "today" : d2 == 1 ? "tomorrow" : "in \(d2) days"
                text += " Next: \(second.title) \(when), \(percent(second.readiness))% ready."
            }
        }
        return text
    }

    /// VoiceOver for the exam widgets: "Bio 101 Midterm, 64 percent ready, 23 days left".
    static func examAccessibility(_ exam: WidgetSnapshot.Exam, daysLeft: Int) -> String {
        let when = daysLeft < 1 ? "today" : daysLeft == 1 ? "tomorrow" : "\(daysLeft) days left"
        var text = "\(exam.title), \(percent(exam.readiness)) percent ready, \(when)"
        if let delta = delta(exam.delta) { text += ", \(delta.replacingOccurrences(of: "%", with: " percent"))" }
        return text
    }

    /// "done today" → "Done today".
    static func sentenceCase(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}
