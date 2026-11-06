import Foundation

/// Which questions can be asked out loud, and how long that takes. Own words and flashcards always; multiple choice up to four options
/// (more can't be held in the head); fill-ins with one blank; never a diagram (it is something to look at). Pure.
enum OutLoudPolicy {
    static let kinds: Set<ItemKind> = [.recall, .apply, .flashcard, .mcq, .cloze]
    static let maxOptions = 4

    static func canAsk(kind: ItemKind, options: Int, blanks: Int) -> Bool {
        guard kinds.contains(kind) else { return false }
        switch kind {
        case .mcq: return options >= 2 && options <= maxOptions
        case .cloze: return blanks == 1
        default: return true
        }
    }

    /// Seconds a question takes when both sides are spoken (Cap reads it, the person answers, Cap says how it went).
    static func spokenSeconds(_ kind: ItemKind) -> Double {
        switch kind {
        case .recall: 60
        case .apply: 75
        case .mcq: 35
        case .cloze: 25
        case .flashcard: 22
        case .diagram: 0
        }
    }
}
