import Foundation

// "Looks wrong?": what a student's report holds, the day's limit on "my answer should count", and what a re-check's verdict does to the
// question. Pure; `AppModel+Report` keeps the ledger in UserDefaults (on this iPhone: `StudyItem.reported` is what syncs) and applies the change.

/// What the student said about one question.
struct ItemReport: Codable, Equatable, Sendable {
    var reason: CheckReport.Reason
    /// The answer they gave, if any.
    var given: String?
    /// Their own words ("Something else").
    var note: String?
    var at: Date
}

/// The reports still waiting for Cap, and how many "my answer should count" the day has used.
struct ReportLedger: Codable, Equatable, Sendable {
    static let defaultsKey = "capling.reports.ledger"
    /// "My answer should count" is the one report that can change a grade, so it's limited.
    static let myAnswerPerDay = 3

    /// By item id.
    var pending: [String: ItemReport] = [:]
    var myAnswerDay: String?
    var myAnswerCount = 0

    func report(for id: UUID) -> ItemReport? { pending[id.uuidString] }

    func myAnswerLeft(on dayKey: String) -> Int {
        myAnswerDay == dayKey ? max(0, Self.myAnswerPerDay - myAnswerCount) : Self.myAnswerPerDay
    }

    /// Takes one of the day's "my answer should count". False when they are used up.
    mutating func spendMyAnswer(on dayKey: String) -> Bool {
        guard myAnswerLeft(on: dayKey) > 0 else { return false }
        if myAnswerDay != dayKey {
            myAnswerDay = dayKey
            myAnswerCount = 0
        }
        myAnswerCount += 1
        return true
    }
}

/// How a report came out, for the sheet and the open question.
enum RecheckResult: Equatable, Sendable {
    /// The page settled it and the question was corrected. In a session, the answer counts as right.
    case fixed
    /// The page agrees with the question. The grade stands.
    case stands
    /// The page doesn't back the question: it's out of sessions.
    case retired
    /// The page says otherwise, but this format can't be corrected by replacing its answer: out of sessions until the student edits it.
    case needsEdit
    /// Not checked yet (offline, no consent). It leaves this session and counts for nothing.
    case queued
    /// "My answer should count" on an own-words answer: it goes back to the grader.
    case regrade
}

/// What a verdict does to the question.
enum RecheckChange: Equatable, Sendable {
    case stands
    case replace(answer: String, choices: [Choice]?)
    case retire
    case needsEdit

    static func from(_ verdict: CheckVerdict, kind: ItemKind, choices: [Choice]) -> RecheckChange {
        switch verdict.verdict {
        case .supported: return .stands
        case .unsupported: return .retire
        case .fixed: break
        }
        let answer = verdict.fixedAnswer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch kind {
        case .cloze, .diagram:
            // A fill-in's blanks and a diagram's labels aren't its answer's text alone.
            return .needsEdit
        case .mcq:
            if let fixed = verdict.fixedChoices, fixed.count >= 2, fixed.filter(\.correct).count == 1,
               let right = fixed.first(where: \.correct) {
                return .replace(answer: right.text, choices: fixed)
            }
            // Only a new right answer: it has to be one of the options.
            let matched = choices.first { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(answer) == .orderedSame }
            guard let matched else { return .needsEdit }
            return .replace(answer: matched.text, choices: choices.map { Choice(text: $0.text, correct: $0.text == matched.text, why: $0.why) })
        case .flashcard, .recall, .apply:
            return answer.isEmpty ? .needsEdit : .replace(answer: answer, choices: nil)
        }
    }
}
