import Foundation

/// The Study screens' words, in one place: intervals, verdicts, mix-ups, session titles. Pure, so the tests read
/// exactly what a person reads. One word for one thing: a fix is "Fix it" wherever it shows, the eve is "Night before".
enum SessionCopy {

    // MARK: Sessions

    /// The Live Activity's and the context line's name for a session.
    static func title(for kind: SessionKind) -> String {
        switch kind {
        case .daily: "Today's session"
        case .catchUp: "Catch-up session"
        case .examEve: "Night before"
        case .fix: "Fix it"
        case .practice: "Practice"
        case .quickCheck: "Quick check"
        case .mock: "Mock exam"
        }
    }

    /// The Live Activity's and the context line's name for a session limited to one course: "Study · Bio 101".
    static func studyCourse(_ name: String) -> String { String(localized: "Study · \(name)") }

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

    // MARK: The flashcard swipe

    /// A choice's word, the stamp on a dragged card, and what VoiceOver's action says. Hard counts as "Got it" on the swipe's side.
    /// No interval: the Undo pill says when the question comes back.
    static func swipeWord(_ rating: Rating) -> LocalizedStringResource {
        rating == .again ? "Again" : "Got it"
    }

    /// "Swipe right if you got it, left if not": shown on a student's first few flashcards ever, then never.
    static let swipeHint: LocalizedStringResource = "Swipe right if you got it, left if not"

    // MARK: Undo

    /// The Undo pill: "Easy · back in 4 weeks".
    static func undoLine(rating: Rating, days: Double) -> LocalizedStringResource {
        "\(rating.title) · back in \(interval(days: days))"
    }

    /// What VoiceOver reads for the pill's button.
    static func undoAccessibility(rating: Rating) -> LocalizedStringResource { "Undo \(rating.title)" }

    /// What VoiceOver says when a rating is held: "Got it. Undo is at the bottom."
    static func undoAnnouncement(rating: Rating) -> LocalizedStringResource {
        "\(rating.title). Undo is at the bottom."
    }

    // MARK: Grades

    /// The answer panel's headline: "Nice!", "Almost.", "Not yet.", "Here's the answer." (nothing was answered), or
    /// "Just in time!" (right on a memory that was fading: a save).
    static func headline(_ outcome: SessionRunner.Outcome, answered: Bool = true, saved: Bool = false) -> LocalizedStringResource {
        guard answered else { return "Here's the answer." }
        if saved, outcome == .right { return "Just in time!" }
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

    // MARK: Marking it yourself

    /// The panel's headline while the person compares their answer with the model answer: no verdict before they have marked.
    static var selfCheckHeadline: LocalizedStringResource { "Compare with the answer." }

    /// The pill over the person's answer.
    static var selfCheckPill: String { String(localized: "Check it yourself") }

    /// Why a model didn't grade this one, in plain words, from what the route knew.
    static func selfCheckLine(_ reason: SelfCheckReason?) -> String {
        switch reason {
        case .cloudOff: String(localized: "Cloud AI is off, so you mark this one.")
        case .freeLimit: String(localized: "You've used today's free AI checks, so you mark this one.")
        case .offline: String(localized: "No connection, so you mark this one.")
        case .unreachable: String(localized: "Cloud AI couldn't be reached, so you mark this one.")
        case .deviceUnavailable, nil: String(localized: "Your iPhone's AI is off or unavailable, so you mark this one.")
        }
    }

    /// The line once they have changed a tick.
    static var markedByYou: String { String(localized: "Marked by you") }

    /// What a self-check says to VoiceOver when it lands.
    static func selfCheckAnnouncement(ticked: Int, total: Int) -> String {
        String(localized: "Compare your answer with the model answer, then tick the key ideas you had. Ticked: \(ticked) of \(total).")
    }

    // MARK: Free checks left

    /// A quiet line under the answer box once the free Cloud AI checks for the day run low (5 or fewer, and at least one): the
    /// iPhone's own AI and the person's marks carry on after them.
    static func freeChecksLeft(_ left: Int?) -> String? {
        guard let left, (1...5).contains(left) else { return nil }
        return left == 1 ? "1 free Cloud AI check left today" : "\(left) free Cloud AI checks left today"
    }

    /// The same for Ask's tutor: 3 or fewer free answers left today.
    static func freeAnswersLeft(_ left: Int?) -> String? {
        guard let left, (1...3).contains(left) else { return nil }
        return left == 1 ? "1 free answer left today" : "\(left) free answers left today"
    }

    // MARK: Mix-ups

    /// Cap's line about a confusion: "You keep mixing up anaphase and telophase." A topic-shaped one ("Mendelian
    /// genetics") reads "Mendelian genetics: still tripping you up." A topic's name can be singular or plural, and the line reads either way.
    static func mixUpLine(_ name: String, questions: Int = 2) -> String {
        // A mix-up the rules couldn't name says what it is, with no made-up name in front of the verb.
        if name == ConfusionCandidate.unnamed {
            return questions == 1 ? String(localized: "This question keeps tripping you up.") : String(localized: "These questions keep tripping you up.")
        }
        let parts = name.components(separatedBy: " vs ")
        guard parts.count == 2 else { return String(localized: "\(name): still tripping you up.") }
        let pair = casedPair(parts[0], parts[1])
        return "You keep mixing up \(pair.0) and \(pair.1)."
    }

    /// Two terms inside a sentence, lower case unless they're names: a second term that starts with a capital ("Darcy vs Bingley", "PTR vs A") says the first keeps its capital too.
    private static func casedPair(_ first: String, _ second: String) -> (String, String) {
        second.first?.isUppercase == true ? (first, second) : (lowerFirst(first), second)
    }

    /// The same mix-up when its last answer came right: it isn't tripping them up just now.
    static func mixUpComingAlong(_ name: String, questions: Int = 2) -> String {
        if name == ConfusionCandidate.unnamed {
            return questions == 1 ? String(localized: "This question is coming along.") : String(localized: "These questions are coming along.")
        }
        let parts = name.components(separatedBy: " vs ")
        guard parts.count == 2 else { return String(localized: "\(name): coming along.") }
        let pair = casedPair(parts[0], parts[1])
        return String(localized: "\(Lexicon.capitalizedFirst(pair.0)) and \(pair.1) are coming along.")
    }

    /// "anaphase and telophase" for a summary or a fix ("You told anaphase and telophase apart").
    static func mixUpPair(_ name: String) -> String {
        if name == ConfusionCandidate.unnamed { return String(localized: "them") }
        let parts = name.components(separatedBy: " vs ")
        guard parts.count == 2 else { return lowerFirst(name) }
        let pair = casedPair(parts[0], parts[1])
        return "\(pair.0) and \(pair.1)"
    }

    /// A fix's one name, on its button, its session and its summary, whatever its size: "Fix it". What comes is a short lesson and the
    /// questions. (`questions` is kept for the callers that pass it; a fix of one question is a fix too.)
    static func fixTitle(questions: Int = 2) -> String { String(localized: "Fix it") }

    /// "Missed 3 of the last 4 times." The button beside it ("Fix it") is the offer, so the line doesn't ask.
    static func missLine(_ note: ConfusionNote) -> String {
        if note.rightRun >= 1, note.missCount > 0 { return String(localized: "You got the last one right.") }
        if note.recentAnswers >= 3, note.recentMisses >= 2 {
            return String(localized: "Missed \(note.recentMisses) of the last \(note.recentAnswers) times.")
        }
        if note.missCount > 1 { return String(localized: "Missed \(note.missCount) times lately.") }
        // An adopted look-alike: nothing has been missed yet.
        if note.missCount == 0 { return String(localized: "Spotted before any mix-up.") }
        return String(localized: "Missed it lately.")
    }

    /// The end of a fix: "Anaphase vs telophase: 5 of 5 right." (the pair by its name; one the rules couldn't name, just the count).
    static func fixResult(_ name: String?, right: Int, of total: Int) -> String {
        let count = String(localized: "\(right) of \(total) right.")
        guard let name, !name.isEmpty, name != ConfusionCandidate.unnamed else { return count }
        return "\(name): \(count)"
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

    /// The session's pill: "41 left", counting down as questions are answered.
    static func left(_ n: Int) -> LocalizedStringResource { "\(n) left" }

    /// What VoiceOver reads for it: "41 questions left".
    static func leftSpoken(_ n: Int) -> LocalizedStringResource { "\(n) questions left" }

    /// The summary's line: "6 of 9 right first time · 3 min".
    static func summaryLine(right: Int, of total: Int, minutes: Int) -> String {
        "\(String(localized: "\(right) of \(total) right first time")) · \(String(localized: "\(max(1, minutes)) min"))"
    }

    /// "Another session: 5 questions". What the button starts is a fresh short session of that size, not what's left of this one.
    static func anotherSession(_ n: Int) -> String { String(localized: "Another session: \(questions(n))") }

    /// The summary's readiness: "41% → 69% ready".
    static func readinessChange(before: Double, after: Double) -> String {
        String(localized: "\(CLFormat.percent(before)) → \(CLFormat.percent(after)) ready")
    }

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
