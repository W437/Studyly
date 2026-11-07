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

    /// Why this mock is shorter than the real exam. Nil when it isn't. "That's every question you have for it so far, with the time scaled to match."
    static func whyShorter(questions: Int, format: ExamFormat) -> String? {
        guard let real = format.questionCount, real > questions else { return nil }
        let scaled = format.minutes != nil
        if questions >= MockExamBuilder.maximumSize {
            return scaled ? String(localized: "A mock stops at \(MockExamBuilder.maximumSize) questions, with the time scaled to match.")
                : String(localized: "A mock stops at \(MockExamBuilder.maximumSize) questions.")
        }
        return scaled ? String(localized: "That's every question you have for it so far, with the time scaled to match.")
            : String(localized: "That's every question you have for it so far.")
    }

    /// "Matches your exam: 15 multiple choice, 2 fill-ins and 3 short answers. Only this exam's topics." With `format` it says only what's true of that
    /// exam: fill-ins it doesn't name stand in for short answers, and a mix it can't hold at this size is the real one's "as far as your questions go".
    static func mixLine(multiple: Int, fillIns: Int = 0, short: Int, essay: Int, format: ExamFormat? = nil, holdsMix: Bool = true) -> String {
        let standsIn = fillIns > 0 && format?.shortAnswer == true
        var parts: [String] = []
        if multiple > 0 { parts.append(String(localized: "\(multiple) multiple choice")) }
        if fillIns > 0, !standsIn { parts.append(String(localized: "\(fillIns) fill-ins")) }
        if short > 0 { parts.append(String(localized: "\(short) short answers")) }
        if essay > 0 { parts.append(String(localized: "\(essay) essay questions")) }
        let list = ListFormatter.localizedString(byJoining: parts)
        if standsIn {
            let spare = parts.isEmpty ? String(localized: "\(fillIns) fill-ins, standing in for short answers you don't have yet.")
                : String(localized: "\(list), with \(String(localized: "\(fillIns) fill-ins")) standing in for short answers you don't have yet.")
            return "\(spare) \(String(localized: "Only this exam's topics."))"
        }
        if !holdsMix { return String(localized: "\(list): the real one's mix, as far as your questions go. Only this exam's topics.") }
        return String(localized: "Matches your exam: \(list). Only this exam's topics.")
    }

    /// The card's and the intro's two lines for this mock of this exam.
    static func offer(_ plan: MockPlan, format: ExamFormat) -> (line: String, mix: String) {
        let questions = plan.entries.count
        let mix = mixLine(multiple: plan.multipleChoiceCount, fillIns: plan.fillInCount, short: plan.shortCount, essay: plan.essayCount, format: format,
                          holdsMix: plan.holdsMix(of: format))
        return (cardLine(questions: questions, minutes: plan.minutes, realQuestions: format.questionCount),
                [whyShorter(questions: questions, format: format), mix].compactMap { $0 }.joined(separator: " "))
    }

    /// "Last mock: 72% on Nov 3".
    static func lastLine(score: Double, date: Date, calendar: Calendar) -> String {
        String(localized: "Last mock: \(CLFormat.percent(score)) on \(LibraryFormat.shortDate(date, calendar: calendar))")
    }

    /// Why there's no mock yet, in the exam's own terms, because other screens count every question: "This exam is multiple choice. A mock
    /// needs 8 of those, and you have 2." With no format ticked a mock asks anything but flashcards and diagrams.
    static func tooFew(have: Int, format: ExamFormat) -> String {
        var kinds: [String] = []
        if format.multipleChoice { kinds.append(String(localized: "multiple choice")) }
        if format.shortAnswer { kinds.append(String(localized: "short answer")) }
        if format.essay { kinds.append(String(localized: "essay questions")) }
        let need = MockExamBuilder.minimum(for: format)
        guard !kinds.isEmpty else {
            return String(localized: "A mock needs \(need) multiple-choice or written questions, and you have \(have).")
        }
        return String(localized: "This exam is \(ListFormatter.localizedString(byJoining: kinds)). A mock needs \(need) of those, and you have \(have).")
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

    static func predicted(_ expected: Double) -> String { String(localized: "Cap predicted \(CLFormat.percent(expected)).") }

    /// Why the prediction isn't the exam page's readiness.
    static let predictionNote = String(localized: "Cap's prediction is for this mock, today. Readiness is what you'd remember on exam day.")

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
