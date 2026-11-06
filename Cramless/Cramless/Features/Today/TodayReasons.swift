import Foundation

/// "Why these?" on Today's card: why today's session holds what it holds, as a few plain rows (`TodayReasons.make`, pure, tested in
/// `TodayReasonsTests`). The sheet (`TodayReasonsSheet`) draws them with "Study something else" (the sky as a list) and "Got it".
enum TodayReasons {
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
        /// The exam the session mostly serves, and when it is ("Sun · in 2 days").
        var examTitle: String?
        var when: String?
        /// Days until it, and today's planned seconds for it.
        var daysLeft: Int?
        var focusSeconds: Double = 0
        /// The exam's topics by name, or empty when it covers its whole course (`courseName`).
        var scopeTopics: [String] = []
        var courseName: String = ""
        /// The exam's weakest topic: its name, its readiness and how many of today's questions are on it.
        var weakestName: String?
        var weakestValue: Double = 0
        var weakestToday: Int = 0
        /// Today's reviews about to be forgotten, and its new questions (for the exam, or the whole session without one).
        var due: Int = 0
        var new: Int = 0
        /// The other upcoming exams, soonest first.
        var others: [Other] = []
        /// Questions in the exam's scope: under `TodayCopy.fewQuestions` the readiness is a thin guess and a row says so.
        var scopeCount: Int = 0
    }

    static func make(_ input: Input) -> [Row] {
        var rows: [Row] = []
        if let exam = input.examTitle {
            let covers = input.scopeTopics.isEmpty
                ? String(localized: "It covers all of \(input.courseName).")
                : String(localized: "It covers \(input.scopeTopics.formatted(.list(type: .and))).")
            let title = input.when.map { "\(exam) · \($0)" } ?? exam
            rows.append(Row(id: "exam", symbol: "graduationcap.fill", title: title, detail: input.courseName.isEmpty && input.scopeTopics.isEmpty ? nil : covers))
        }
        if let weakest = input.weakestName {
            let detail = input.weakestToday > 0 ? String(localized: "\(input.weakestToday) of today's questions are on it.") : nil
            rows.append(Row(id: "weakest", symbol: "scope",
                            title: String(localized: "\(weakest) is the weakest: \(CLFormat.percent(input.weakestValue)) ready"),
                            detail: detail))
        }
        if input.due > 0 {
            rows.append(Row(id: "due", symbol: "clock.arrow.circlepath", title: String(localized: "\(input.due) questions are due"),
                            detail: String(localized: "You're about to forget them, so they come back now.")))
        }
        if input.new > 0 {
            rows.append(Row(id: "new", symbol: "sparkles", title: String(localized: "\(input.new) new questions"),
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
        if let row = alsoIn(input) { rows.append(row) }
        if let exam = input.examTitle, input.scopeCount > 0, input.scopeCount < TodayCopy.fewQuestions {
            rows.append(Row(id: "few", symbol: "info.circle", title: String(localized: "\(exam) has \(input.scopeCount) questions so far"),
                            detail: String(localized: "Readiness is based on them. Add more material and it gets surer.")))
        }
        return rows
    }

    /// The other exams with questions today. It says only what is true of all of them, in any order of exams: "a few" when each has
    /// less of today than the exam the session is for, "further off" when each is, "because they're due" when none of them is new.
    private static func alsoIn(_ input: Input) -> Row? {
        let others = input.others.filter(\.inToday)
        guard !others.isEmpty else { return nil }
        let unique = unique(others.map(\.name))
        let names = unique.formatted(.list(type: .and))
        let few = others.allSatisfy { $0.seconds <= input.focusSeconds }
        let furtherOff = input.daysLeft.map { days in others.allSatisfy { $0.daysLeft > days } } ?? false
        let title: String
        var detail: String?
        if few, furtherOff {
            title = String(localized: "A few \(names) questions are in too")
            detail = unique.count == 1 ? String(localized: "Its exam is further off, so it gets a smaller share of today.")
                : String(localized: "Their exams are further off, so they get a smaller share of today.")
        } else {
            if others.allSatisfy(\.due) {
                title = few ? String(localized: "A few \(names) questions are in too, because they're due.")
                    : String(localized: "\(names) questions are in too, because they're due.")
            } else {
                title = few ? String(localized: "A few \(names) questions are in too") : String(localized: "\(names) questions are in too")
            }
            if furtherOff {
                detail = unique.count == 1 ? String(localized: "Its exam is further off.") : String(localized: "Their exams are further off.")
            }
        }
        return Row(id: "alsoIn", symbol: "plus.circle", title: title, detail: detail)
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}
