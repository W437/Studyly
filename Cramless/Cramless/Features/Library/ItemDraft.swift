import Foundation

/// What the question editor edits: one question's fields as plain values. `problem` says in plain words what still
/// stops it from being saved; `normalized` is what `AppModel.createItem` / `updateItem` store (trimmed, empty rows
/// dropped, the answer derived for choices and fill-ins). Cards the person makes are free and unlimited: no AI.
struct ItemDraft: Equatable, Sendable {
    /// A key idea as typed: its name and other ways of saying it, comma-separated.
    struct Idea: Equatable, Sendable, Identifiable {
        var id: String
        var label: String
        var phrasings: String
    }

    /// A multiple-choice option as typed.
    struct Option: Equatable, Sendable, Identifiable {
        var id = UUID()
        var text: String
        var correct: Bool
        var why: String = ""
    }

    /// The stored form.
    struct Normalized: Equatable, Sendable {
        var prompt: String
        var answer: String
        var explanation: String
        var keyIdeas: [KeyIdea]
        var choices: [Choice]
        var cloze: ClozeSpec?
    }

    var kind: ItemKind = .flashcard
    var prompt = ""
    var answer = ""
    var explanation = ""
    var ideas: [Idea] = []
    var options: [Option] = []
    var clozeText = ""
    /// Other accepted answers for each blank, comma-separated, in blank order.
    var clozeAlternates: [String] = []
    var topicID: UUID?
    var suspended = false

    /// The formats a person writes by hand. A diagram needs a page with recognised labels, so it is only edited.
    static let writableKinds: [ItemKind] = [.flashcard, .recall, .apply, .mcq, .cloze]

    /// The prompt a fill-in gets when the person leaves it blank.
    static let defaultClozePrompt = "Fill in the blank."

    /// A new question of `kind`, with the rows its format starts with.
    static func blank(kind: ItemKind = .flashcard, topicID: UUID? = nil) -> ItemDraft {
        var draft = ItemDraft(kind: kind, topicID: topicID)
        draft.prepareRows()
        return draft
    }

    /// Adds the empty rows a format needs to be edited (two choices, one key idea), keeping what's there.
    mutating func prepareRows() {
        switch kind {
        case .mcq:
            while options.count < 2 { options.append(Option(text: "", correct: options.isEmpty)) }
        case .recall, .apply:
            if ideas.isEmpty { ideas.append(Idea(id: Self.nextIdeaID(after: ideas), label: "", phrasings: "")) }
        default:
            break
        }
    }

    mutating func addIdea() {
        ideas.append(Idea(id: Self.nextIdeaID(after: ideas), label: "", phrasings: ""))
    }

    mutating func addOption() {
        options.append(Option(text: "", correct: options.allSatisfy { !$0.correct }))
    }

    /// Marks one option as the right answer (exactly one is).
    mutating func markCorrect(_ id: UUID) {
        for index in options.indices { options[index].correct = options[index].id == id }
    }

    static func nextIdeaID(after ideas: [Idea]) -> String {
        let used = Set(ideas.map(\.id))
        var n = ideas.count + 1
        while used.contains("k\(n)") { n += 1 }
        return "k\(n)"
    }

    // MARK: Reading and checking

    /// The blanks in the fill-in text, in order ("{{telophase}}" → "telophase"), trimmed.
    var blanks: [String] {
        ClozeSpec(text: clozeText).answers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// What still stops the draft from being saved, said plainly; nil when it's ready.
    var problem: String? {
        let prompt = prompt.clTrimmed
        let answer = answer.clTrimmed
        switch kind {
        case .flashcard:
            if prompt.isEmpty { return "Write the front of the card." }
            if answer.isEmpty { return "Write the back of the card." }
        case .recall, .apply:
            if prompt.isEmpty { return "Write the question." }
            if answer.isEmpty { return "Write a model answer." }
            if !ideas.contains(where: { !$0.label.clTrimmed.isEmpty }) {
                return "Add a key idea, so answers in your own words can be graded."
            }
        case .mcq:
            if prompt.isEmpty { return "Write the question." }
            let filled = options.filter { !$0.text.clTrimmed.isEmpty }
            if filled.count < 2 { return "Add at least two choices." }
            if filled.filter(\.correct).count != 1 { return "Mark the one right answer." }
        case .cloze:
            let blanks = self.blanks
            if blanks.isEmpty { return "Put {{double braces}} around the words to hide." }
            if blanks.contains(where: \.isEmpty) { return "One of the blanks is empty." }
        case .diagram:
            if prompt.isEmpty { return "Write the question." }
        }
        return nil
    }

    var normalized: Normalized {
        let explanation = explanation.clTrimmed
        switch kind {
        case .flashcard, .diagram:
            return Normalized(prompt: prompt.clTrimmed, answer: answer.clTrimmed, explanation: explanation, keyIdeas: [],
                              choices: [], cloze: nil)
        case .recall, .apply:
            var seenIDs: Set<String> = []
            let keyIdeas = ideas.compactMap { idea -> KeyIdea? in
                let label = idea.label.clTrimmed
                guard !label.isEmpty else { return nil }
                var id = idea.id.isEmpty ? "k" : idea.id
                while !seenIDs.insert(id).inserted { id += "'" }
                return KeyIdea(id: id, label: label, terms: Self.terms(label: label, phrasings: idea.phrasings))
            }
            return Normalized(prompt: prompt.clTrimmed, answer: answer.clTrimmed, explanation: explanation,
                              keyIdeas: keyIdeas, choices: [], cloze: nil)
        case .mcq:
            let choices = options.compactMap { option -> Choice? in
                let text = option.text.clTrimmed
                guard !text.isEmpty else { return nil }
                let why = option.why.clTrimmed
                return Choice(text: text, correct: option.correct, why: why.isEmpty ? nil : why)
            }
            let right = choices.first(where: \.correct)?.text ?? ""
            return Normalized(prompt: prompt.clTrimmed, answer: right, explanation: explanation, keyIdeas: [],
                              choices: choices, cloze: nil)
        case .cloze:
            let text = clozeText.clTrimmed
            let blanks = self.blanks
            let alternates = blanks.indices.map { index -> [String] in
                guard clozeAlternates.indices.contains(index) else { return [] }
                return Self.split(clozeAlternates[index]).filter { $0.caseInsensitiveCompare(blanks[index]) != .orderedSame }
            }
            let hasAlternates = alternates.contains { !$0.isEmpty }
            let prompt = self.prompt.clTrimmed
            return Normalized(prompt: prompt.isEmpty ? Self.defaultClozePrompt : prompt,
                              answer: blanks.joined(separator: ", "), explanation: explanation, keyIdeas: [],
                              choices: [], cloze: ClozeSpec(text: text, alternates: hasAlternates ? alternates : []))
        }
    }

    /// A key idea's accepted phrasings: its name, then the other ways of saying it, lowercase and without repeats.
    static func terms(label: String, phrasings: String) -> [String] {
        var seen: Set<String> = []
        return ([label] + split(phrasings)).map { $0.lowercased() }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// "high to low, down the gradient" → ["high to low", "down the gradient"].
    static func split(_ list: String) -> [String] {
        list.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { String($0).clTrimmed }
            .filter { !$0.isEmpty }
    }
}

extension ItemDraft {
    /// The draft for editing an existing question.
    init(item: StudyItem) {
        self.init()
        kind = item.kind
        prompt = item.prompt
        answer = item.answer
        explanation = item.explanation
        topicID = item.topicID
        suspended = item.status == .suspended
        ideas = item.keyIdeas.map { idea in
            let others = idea.terms.filter { $0.caseInsensitiveCompare(idea.label) != .orderedSame }
            return Idea(id: idea.id, label: idea.label, phrasings: others.joined(separator: ", "))
        }
        options = item.choices.map { Option(text: $0.text, correct: $0.correct, why: $0.why ?? "") }
        if let cloze = item.cloze {
            clozeText = cloze.text
            clozeAlternates = cloze.alternates.map { $0.joined(separator: ", ") }
            if prompt == Self.defaultClozePrompt { prompt = "" }
        }
        prepareRows()
    }
}

extension String {
    var clTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
