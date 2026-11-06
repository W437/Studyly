import Foundation

/// One question as Cap asks it: what he reads, the options in the order he reads them (the same order the screen would show today), and what
/// counts as its answer. A plain value, so the wording is tested without a store.
struct OutLoudQuestion: Equatable, Sendable, Identifiable {
    /// The session entry's id ("<item>#<attempt>").
    var id: String
    var itemID: UUID
    var kind: ItemKind
    var prompt: String
    /// What Cap reads: the prompt, a fill-in's "blank", a multiple choice's lettered options.
    var spoken: String
    /// The options as read, and where each one is in the item's own list.
    var options: [String] = []
    var optionIndexes: [Int] = []
    /// The right option's words, a fill-in's blank, or the model answer.
    var rightAnswer: String
    var ideas: [KeyIdea] = []

    /// What listening for this question is primed with and reads answers as.
    var expecting: SpokenAnswer.Expecting { kind == .mcq ? .choice(options: options) : .words }

    /// Primes the recogniser for what this question's answer sounds like. Never the right answer alone, which would tilt it towards hearing that.
    var terms: [String] { options + ["repeat", "skip", "stop", "I don't know", "got it"] }

    /// The place among the options as read of the right one.
    var rightPlace: Int? { kind == .mcq ? options.firstIndex(of: rightAnswer) : nil }

    static func make(id: String, itemID: UUID, kind: ItemKind, prompt: String, answer: String, ideas: [KeyIdea], choices: [Choice],
                     cloze: ClozeSpec?, day: Int) -> OutLoudQuestion {
        var question = OutLoudQuestion(id: id, itemID: itemID, kind: kind, prompt: prompt, spoken: "", rightAnswer: answer, ideas: ideas)
        if kind == .mcq {
            let order = ChoiceOrder.order(texts: choices.map(\.text), itemID: itemID, day: day)
            question.optionIndexes = order
            question.options = order.map { choices[$0].text }
            question.rightAnswer = choices.first(where: \.correct)?.text ?? answer
        } else if kind == .cloze, let first = cloze?.answers.first {
            question.rightAnswer = first
        }
        question.spoken = ReadAloud.spokenQuestion(kind: kind, prompt: prompt, choices: question.options, cloze: cloze)
        return question
    }
}
