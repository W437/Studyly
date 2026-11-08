import Foundation

/// A mock exam's words, in one place, as pure functions of its numbers: the tests read exactly what a person reads.
enum MockCopy {
    static let title: LocalizedStringResource = "Mock exam"

    /// "20 questions like the real one · 25 min". `realQuestions`: the real exam's size, when it's known and this mock isn't that size: "13 of the real
    /// 40 questions · 30 min", and when the real one is smaller than a mock can be, no comparison at all.
    static func cardLine(questions: Int, minutes: Int, realQuestions: Int? = nil) -> String {
        if let real = realQuestions, real != questions {
            return real > questions ? String(localized: "\(questions) of the real \(real) questions · \(minutes) min")
                : String(localized: "\(String(localized: "\(questions) questions")) · \(minutes) min")
        }
        return String(localized: "\(String(localized: "\(questions) questions")) like the real one · \(minutes) min")
    }

    /// The start screen's second line, under `cardLine`: where the questions come from and when they're marked.
    static let startLine = String(localized: "From this exam's topics. Marked at the end.")

    /// Why there's no mock yet and what to do about it, in the exam's own terms, because other screens count every question: "This exam is multiple choice. A mock
    /// needs 8 of those, and you have 2. Add a page or paste your notes, and Cap writes more." With no format ticked a mock asks anything but flashcards and diagrams.
    static func tooFew(have: Int, format: ExamFormat) -> String {
        var kinds: [String] = []
        if format.multipleChoice { kinds.append(String(localized: "multiple choice")) }
        if format.shortAnswer { kinds.append(String(localized: "short answer")) }
        if format.essay { kinds.append(String(localized: "essay questions")) }
        let need = MockExamBuilder.minimum(for: format)
        guard !kinds.isEmpty else {
            return String(localized: "A mock needs \(need) multiple-choice or written questions, and you have \(have). Add a page or paste your notes, and Cap writes more.")
        }
        return String(localized: "This exam is \(ListFormatter.localizedString(byJoining: kinds)). A mock needs \(need) of those, and you have \(have). Add a page or paste your notes, and Cap writes more.")
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

    /// "4 of 6 short answers marked" ("written answers" when essays are among them): the same words as the intro's mix. Fill-ins don't wait for this.
    static func markingLine(done: Int, total: Int, hasEssays: Bool = false) -> String {
        hasEssays ? String(localized: "\(done) of \(total) written answers marked") : String(localized: "\(done) of \(total) short answers marked")
    }

    /// The summary's headline.
    static func scored(_ score: Double) -> String { String(localized: "You scored \(CLFormat.percent(score)).") }

    /// The line under the score: what Cap expected for these questions today.
    static func expected(_ expected: Double) -> String { String(localized: "Cap expected \(CLFormat.percent(expected)).") }

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
