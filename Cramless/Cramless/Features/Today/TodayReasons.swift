import Foundation

/// "Why these?" on Today's card: why today's session holds what it holds, as at most three plain rows (`TodayReasons.make`, pure,
/// tested in `TodayReasonsTests`). Only what the card doesn't already say: the card names the exam, its day, its readiness and the
/// minutes, so the rows say how the session is shared, what is weakest, what is to review or new, and what waits. The sheet
/// (`TodayReasonsSheet`) draws them with "Study something else" (the courses, each with Practice) and "Got it".
enum TodayReasons {
    /// At most this many rows: the first ones in `make`'s order.
    static let maxRows = 3
    /// Readiness this thin is a guess: under this many questions in scope a row says what it rests on.
    static let fewQuestions = 15

    struct Row: Equatable, Sendable, Identifiable {
        var id: String
        var symbol: String
        var title: String
        var detail: String?
    }

    /// Another upcoming exam, as the reasons need it.
    struct Other: Equatable, Sendable {
        /// Its course's name ("Bio 101"), or its own title with no course.
        var name: String
        var daysLeft: Int
        /// Some of today's questions are for it.
        var inToday: Bool
        /// Today's planned seconds for it.
        var seconds: Double = 0
        /// Today's questions for it are all reviews (none is new).
        var due: Bool = true
    }

    /// Everything the rows say, as plain values.
    struct Input: Equatable, Sendable {
        /// The exam the session mostly serves.
        var examTitle: String?
        /// Days until it, and today's planned seconds for it.
        var daysLeft: Int?
        var focusSeconds: Double = 0
        /// The exam's weakest topic: its name, its readiness and how many of today's questions are on it.
        var weakestName: String?
        var weakestValue: Double = 0
        var weakestToday: Int = 0
        /// Today's questions to review, and its new questions (for the exam, or the whole session without one).
        var due: Int = 0
        var new: Int = 0
        /// The other upcoming exams, soonest first.
        var others: [Other] = []
        /// Questions in the exam's scope: under `fewQuestions` the readiness is a thin guess and a row says so.
        var scopeCount: Int = 0
        /// The session's questions in all, and how many of them are for the exam.
        var sessionTotal: Int = 0
        var examQuestions: Int = 0
    }

    /// The rows, most telling first, at most `maxRows`: how the session is shared (when the exam has only part of it) and which
    /// other courses are in it, the exam's weakest topic, what is to review, what is new, what waits, and how thin the readiness is.
    static func make(_ input: Input) -> [Row] {
        let shared = input.examTitle != nil && input.examQuestions < input.sessionTotal
        var rows: [Row] = []
        if shared, let exam = input.examTitle {
            rows.append(Row(id: "total", symbol: "list.bullet", title: String(localized: "About \(input.sessionTotal) questions today"),
                            detail: input.examQuestions > 0 ? String(localized: "\(input.examQuestions) are for \(exam).") : nil))
        }
        if input.examTitle != nil, let row = alsoIn(input) { rows.append(row) }
        if let weakest = input.weakestName {
            let detail = input.weakestToday > 0 ? String(localized: "\(input.weakestToday) of today's questions are on it.") : nil
            rows.append(Row(id: "weakest", symbol: "scope",
                            title: String(localized: "\(weakest) is the weakest: \(CLFormat.percent(input.weakestValue)) ready"),
                            detail: detail))
        }
        if input.due > 0 {
            rows.append(Row(id: "due", symbol: "clock.arrow.circlepath",
                            title: shared ? String(localized: "\(input.due) to review for this exam") : String(localized: "\(input.due) to review"),
                            detail: String(localized: "They come back just before you'd forget them.")))
        }
        if input.new > 0 {
            rows.append(Row(id: "new", symbol: "sparkles",
                            title: shared ? String(localized: "\(input.new) new questions for this exam") : String(localized: "\(input.new) new questions"),
                            detail: input.examTitle == nil ? String(localized: "A few at a time, so they stick.")
                                : String(localized: "A few at a time, so it's all in before the exam.")))
        }
        let waiting = input.others.filter { !$0.inToday }
        if !waiting.isEmpty {
            let names = unique(waiting.map(\.name))
            let distances = waiting.map { TodayCopy.distance(days: $0.daysLeft) }
            let detail = waiting.count == 1
                ? String(localized: "Its exam is \(distances[0]) away.")
                : String(localized: "Their exams are \(distances.formatted(.list(type: .and))) away.")
            rows.append(Row(id: "wait", symbol: "calendar", title: String(localized: "\(names.formatted(.list(type: .and))) can wait"),
                            detail: detail))
        }
        if let exam = input.examTitle, input.scopeCount > 0, input.scopeCount < fewQuestions {
            rows.append(Row(id: "few", symbol: "info.circle", title: String(localized: "\(exam) has \(input.scopeCount) questions so far"),
                            detail: String(localized: "Readiness is based on them. Add more material and it gets surer.")))
        }
        return Array(rows.prefix(maxRows))
    }

    /// The other exams with questions today. It says only what is true of all of them, in any order of exams: "a few" when each has
    /// less of today than the exam the session is for, "further off" when each is, "up for review" when none of them is new.
    private static func alsoIn(_ input: Input) -> Row? {
        let others = input.others.filter(\.inToday)
        guard !others.isEmpty else { return nil }
        let unique = unique(others.map(\.name))
        let names = unique.formatted(.list(type: .and))
        let few = others.allSatisfy { $0.seconds <= input.focusSeconds }
        let furtherOff = input.daysLeft.map { days in others.allSatisfy { $0.daysLeft > days } } ?? false
        let title = few ? String(localized: "A few \(names) questions are in too") : String(localized: "\(names) questions are in too")
        if few, furtherOff {
            return Row(id: "alsoIn", symbol: "plus.circle", title: title,
                       detail: unique.count == 1 ? String(localized: "Its exam is further off, so it gets a smaller share of today.")
                           : String(localized: "Their exams are further off, so they get a smaller share of today."))
        }
        var parts: [String] = []
        if others.allSatisfy(\.due) { parts.append(String(localized: "They're up for review.")) }
        if furtherOff {
            parts.append(unique.count == 1 ? String(localized: "Its exam is further off.") : String(localized: "Their exams are further off."))
        }
        return Row(id: "alsoIn", symbol: "plus.circle", title: title, detail: parts.isEmpty ? nil : parts.joined(separator: " "))
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}
