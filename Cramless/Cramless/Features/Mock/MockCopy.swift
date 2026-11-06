import Foundation

/// A mock exam's words, in one place, as pure functions of its numbers: the tests read exactly what a person reads.
enum MockCopy {
    static let title: LocalizedStringResource = "Mock exam"

    /// "20 questions like the real one · 25 min".
    static func cardLine(questions: Int, minutes: Int) -> String {
        String(localized: "\(String(localized: "\(questions) questions")) like the real one · \(minutes) min")
    }

    /// "Matches your exam: 15 multiple choice and 5 short answers. Only this exam's topics."
    static func mixLine(multiple: Int, short: Int, essay: Int) -> String {
        var parts: [String] = []
        if multiple > 0 { parts.append(String(localized: "\(multiple) multiple choice")) }
        if short > 0 { parts.append(String(localized: "\(short) short answers")) }
        if essay > 0 { parts.append(String(localized: "\(essay) essay questions")) }
        return String(localized: "Matches your exam: \(ListFormatter.localizedString(byJoining: parts)). Only this exam's topics.")
    }

    /// "Last mock: 72% on Nov 3".
    static func lastLine(score: Double, date: Date, calendar: Calendar) -> String {
        String(localized: "Last mock: \(CLFormat.percent(score)) on \(LibraryFormat.shortDate(date, calendar: calendar))")
    }

    /// "A mock needs 8 questions on this exam's topics. You have 3."
    static func tooFew(have: Int) -> String {
        String(localized: "A mock needs \(MockExamBuilder.minimumQuestions) questions on this exam's topics. You have \(have).")
    }

    /// "3 of 20".
    static func position(_ index: Int, of total: Int) -> String { String(localized: "\(index) of \(total)") }

    /// "17 answered · 2 flagged".
    static func tally(answered: Int, flagged: Int) -> String {
        String(localized: "\(answered) answered · \(flagged) flagged")
    }

    /// "3 left blank. They stay out of your score."
    static func blanksLine(_ blanks: Int) -> String? {
        blanks > 0 ? String(localized: "\(blanks) left blank. They stay out of your score.") : nil
    }

    /// "You answered 17 of 20. Finish the rest without the clock, or see your score now."
    static func timeUpLine(answered: Int, total: Int) -> String {
        String(localized: "You answered \(answered) of \(total). Finish the rest without the clock, or see your score now.")
    }

    /// "4 of 6 short answers marked".
    static func markingLine(done: Int, total: Int) -> String {
        String(localized: "\(done) of \(total) short answers marked")
    }

    /// The summary's headline.
    static func scored(_ score: Double) -> String { String(localized: "You scored \(CLFormat.percent(score)).") }

    static func predicted(_ expected: Double) -> String { String(localized: "Cap predicted \(CLFormat.percent(expected)).") }

    static func verdictLine(_ verdict: MockResult.Verdict) -> String {
        switch verdict {
        case .asExpected: String(localized: "Right where Cap expected.")
        case .better: String(localized: "Better than Cap expected.")
        case .below: String(localized: "Below what Cap expected. The topics below are why.")
        }
    }

    /// What the score rests on, when it isn't the whole mock: "You answered 17 of 20 in time." / "Scored on the 12 of 20 you answered."
    static func scopeLine(counted: Int, total: Int, inTime: Int?) -> String? {
        if let inTime { return String(localized: "You answered \(inTime) of \(total) in time.") }
        guard counted < total else { return nil }
        return String(localized: "Scored on the \(counted) of \(total) you answered.")
    }

    /// "Mark 3 answers yourself".
    static func markYourself(_ count: Int) -> String { String(localized: "Mark \(count) answers yourself") }

    static let tomorrow = String(localized: "The ones you missed come back in tomorrow's session.")
}
