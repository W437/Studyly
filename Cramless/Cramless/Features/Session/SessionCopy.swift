import Foundation

/// The Study screens' words, in one place: intervals, verdicts, mix-ups, session titles. Pure, so the tests read
/// exactly what a person reads.
enum SessionCopy {

    // MARK: Sessions

    /// The Live Activity's and the context line's name for a session.
    static func title(for kind: SessionKind) -> String {
        switch kind {
        case .daily: "Today's session"
        case .catchUp: "Catch-up session"
        case .examEve: "Exam eve"
        case .fix: "2-minute fix"
        case .practice: "Bonus round"
        case .quickCheck: "Quick check"
        }
    }

    // MARK: Intervals

    /// A rating's next interval on its button: "10 min", "1 day", "4 days", "3 weeks", "2 months", "1 year".
    static func interval(days: Double) -> String {
        let minutes = days * 24 * 60
        if minutes < 59.5 { return "\(max(1, Int(minutes.rounded()))) min" }
        if days < 0.98 { return "\(max(1, Int((minutes / 60).rounded()))) h" }
        let d = max(1, Int(days.rounded()))
        if d < 21 { return d == 1 ? "1 day" : "\(d) days" }
        if d < 60 { return "\(Int((Double(d) / 7).rounded())) weeks" }
        if d < 365 { return "\(Int((Double(d) / 30.4).rounded())) months" }
        let years = Int((Double(d) / 365).rounded())
        return years == 1 ? "1 year" : "\(years) years"
    }

    /// The same interval in a sentence: "in 10 minutes", "tomorrow", "in 4 days".
    static func inInterval(days: Double) -> String {
        let minutes = days * 24 * 60
        if minutes < 59.5 {
            let m = max(1, Int(minutes.rounded()))
            return m == 1 ? "in a minute" : "in \(m) minutes"
        }
        if days < 0.98 {
            let h = max(1, Int((minutes / 60).rounded()))
            return h == 1 ? "in an hour" : "in \(h) hours"
        }
        let d = max(1, Int(days.rounded()))
        if d == 1 { return "tomorrow" }
        let text = interval(days: days)
        return "in \(text)"
    }

    // MARK: Grades

    /// The answer panel's headline: "Nice!", "Almost.", "Not yet.", "Here's the answer." (nothing was answered), or
    /// "Saved it." (right on a memory that was fading).
    static func headline(_ outcome: SessionRunner.Outcome, answered: Bool = true, saved: Bool = false) -> LocalizedStringResource {
        guard answered else { return "Here's the answer." }
        if saved, outcome == .right { return "Saved it." }
        switch outcome {
        case .right: return "Nice!"
        case .partial: return "Almost."
        case .wrong: return "Not yet."
        }
    }

    /// The score pill: "2 of 3 key ideas", or a word for answers graded without key ideas.
    static func scoreLine(hits: Int, total: Int, verdict: GradeResponse.Verdict) -> String {
        if total > 0 { return "\(hits) of \(total) key idea\(total == 1 ? "" : "s")" }
        switch verdict {
        case .correct: return "Matches"
        case .partial: return "Partly"
        case .incorrect: return "Not yet"
        }
    }

    /// Who graded it, for the line under the feedback.
    static func gradedBy(_ origin: ItemOrigin) -> String {
        switch origin {
        case .cloud: "Checked with Cloud AI"
        default: "Checked on your iPhone"
        }
    }

    // MARK: Mix-ups

    /// Cap's line about a confusion: "You keep mixing up anaphase and telophase." A topic-shaped one ("Mendelian
    /// genetics") reads "Mendelian genetics keeps tripping you up."
    static func mixUpLine(_ name: String) -> String {
        let parts = name.components(separatedBy: " vs ")
        guard parts.count == 2 else { return "\(name) keeps tripping you up." }
        return "You keep mixing up \(lowerFirst(parts[0])) and \(lowerFirst(parts[1]))."
    }

    /// "anaphase and telophase" for a summary or a fix ("You told anaphase and telophase apart").
    static func mixUpPair(_ name: String) -> String {
        let parts = name.components(separatedBy: " vs ")
        guard parts.count == 2 else { return lowerFirst(name) }
        return "\(lowerFirst(parts[0])) and \(lowerFirst(parts[1]))"
    }

    /// "Missed 3 of the last 4 times. Want a 2-minute fix?"
    static func missLine(_ note: ConfusionNote) -> String {
        let lead: String
        if note.recentAnswers >= 3, note.recentMisses >= 2 {
            lead = "Missed \(note.recentMisses) of the last \(note.recentAnswers) times."
        } else if note.missCount > 1 {
            lead = "Missed \(note.missCount) times lately."
        } else {
            lead = "Missed it lately."
        }
        return lead + " Want a 2-minute fix?"
    }

    /// Lower-cases the first letter unless the first word looks like an acronym or a name with capitals inside
    /// ("DNA", "mRNA").
    static func lowerFirst(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let firstWord = trimmed.split(separator: " ").first, firstWord.count > 1 else { return trimmed }
        if firstWord.dropFirst().contains(where: \.isUppercase) { return trimmed }
        return trimmed.prefix(1).lowercased() + trimmed.dropFirst()
    }

    // MARK: Counting

    static func questions(_ n: Int) -> String { n == 1 ? "1 question" : "\(n) questions" }

    /// "5 more questions".
    static func moreQuestions(_ n: Int) -> String { n == 1 ? "1 more question" : "\(n) more questions" }

    /// A phrase that mustn't break across lines ("Bio 101 exam", "23 days left"): spaces become non-breaking when
    /// it's short enough to fit a line.
    static func unbroken(_ text: String) -> String {
        text.count <= 24 ? text.replacingOccurrences(of: " ", with: "\u{00A0}") : text
    }

    static func minutes(_ n: Int) -> String { n == 1 ? "1 minute" : "\(n) minutes" }

    /// "18 reviews · 6 new · 2 weak spots" (parts with a zero are left out).
    static func sessionMix(reviews: Int, new: Int, weak: Int) -> String {
        // Each part stays on one line, and a line never starts with the dot.
        var parts: [String] = []
        if reviews > 0 { parts.append(reviews == 1 ? "1\u{00A0}review" : "\(reviews)\u{00A0}reviews") }
        if new > 0 { parts.append("\(new)\u{00A0}new") }
        if weak > 0 { parts.append(weak == 1 ? "1\u{00A0}weak\u{00A0}spot" : "\(weak)\u{00A0}weak\u{00A0}spots") }
        return parts.isEmpty ? "A short review" : parts.joined(separator: "\u{00A0}· ")
    }
}
