import Foundation

/// What Cap says after an answer, when nobody is looking at the screen: the verdict in the session's own words ("Nice!", "Almost.", "Not yet."),
/// which ideas were hit and missed, and the answer when it's needed. Pure, from the grade. Only ideas the grade names are said, and
/// an answer the rules can't judge has no verdict at all: Cap gives the answer and asks how it went (`GradeMode.selfCheck`).
enum SpokenVerdict {
    /// Ideas named one by one; the rest are counted.
    static let namedIdeas = 2

    /// After an own-words answer. `saved`: a right answer that rescued a fading memory.
    static func ownWords(_ grade: GradeOutcome, ideas: [KeyIdea], modelAnswer: String, saved: Bool = false) -> String {
        switch grade.verdict {
        case .correct:
            let opening = saved ? String(localized: "Saved it.") : String(localized: "Nice!")
            if ideas.count > 1 { return String(localized: "\(opening) You got every key idea.") }
            return opening
        case .partial:
            let hit = ideas.filter { grade.hitIdeaIDs.contains($0.id) }.map(\.label)
            let missed = grade.missing.map(\.label)
            var parts = [String(localized: "Almost.")]
            if !hit.isEmpty { parts.append(String(localized: "You got: \(named(hit)).")) }
            if !missed.isEmpty { parts.append(String(localized: "Still missing: \(named(missed)).")) }
            return parts.joined(separator: " ")
        case .incorrect:
            return String(localized: "Not yet. Here's the answer: \(sentence(modelAnswer))")
        }
    }

    /// After a question with one right answer (multiple choice, a fill-in).
    static func exact(_ grade: GradeOutcome, rightAnswer: String, saved: Bool = false) -> String {
        if grade.verdict == .correct { return saved ? String(localized: "Saved it.") : String(localized: "Nice!") }
        return String(localized: "Not yet. The answer is \(sentence(rightAnswer))")
    }

    /// "I don't know": the answer, and no verdict.
    static func dontKnow(answer: String) -> String {
        String(localized: "Here's the answer: \(sentence(answer))")
    }

    /// A flashcard's answer, or an answer no one can grade: the answer, then how it went is the person's to say.
    static func howDidItGo(answer: String) -> String {
        String(localized: "Here's the answer: \(sentence(answer)) Did you have it? Say got it, or again.")
    }

    /// A flashcard rating was heard.
    static func rated(_ rating: Rating, saved: Bool) -> String {
        if saved { return String(localized: "Saved it.") }
        switch rating {
        case .again: return String(localized: "Okay, it'll come back.")
        case .hard, .good, .easy: return String(localized: "Got it.")
        }
    }

    /// The end of a session.
    static func summary(answered: Int, right: Int) -> String {
        guard answered > 0 else { return String(localized: "Okay. We'll stop here.") }
        return String(localized: "That's it. \(right) of \(answered) right the first time.")
    }

    /// "Spindle fibres and anaphase", "A, B and 2 more": two named, the others counted, joined with "and".
    static func named(_ labels: [String]) -> String {
        let lowered = labels.map(SessionCopy.lowerFirst)
        switch lowered.count {
        case 0: return ""
        case 1: return lowered[0]
        case 2: return String(localized: "\(lowered[0]) and \(lowered[1])")
        default:
            let shown = lowered.prefix(namedIdeas).joined(separator: ", ")
            return String(localized: "\(shown) and \(lowered.count - namedIdeas) more")
        }
    }

    /// Ends with a stop, so the voice settles before what comes next.
    private static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, !".?!".contains(last) else { return trimmed }
        return trimmed + "."
    }
}
