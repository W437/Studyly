import Foundation

/// Mistake patterns by the offline rules (tier T0). Two patterns plain code can see:
///
/// - **a swap**: the answer given to one item is the expected answer of another ("telophase" for the anaphase
///   question, "anaphase" for the telophase one). Named "Anaphase vs telophase" when the answers are terms (when they are
///   sentences there is no honest name, and the screens say how many misses on how many questions), with a two-line lesson from
///   the two expected answers and a choice question for each item between the two confused answers;
/// - **a weak topic**: two or more items of one topic missed three or more times between them.
///
/// It can't explain *why* two ideas get mixed up; the cloud does that when allowed.
enum LocalConfusions {

    static func find(_ mistakes: [MistakeInput]) -> [ConfusionOut] {
        var out: [ConfusionOut] = []
        var used = Set<String>()

        // Swaps.
        for a in mistakes where !used.contains(a.itemId) {
            guard let b = mistakes.first(where: { b in
                b.itemId != a.itemId && !used.contains(b.itemId) && same(a.given, b.expected)
            }) else { continue }
            used.formUnion([a.itemId, b.itemId])
            let first = Lexicon.trimmedSentence(b.expected), second = Lexicon.trimmedSentence(a.expected)
            // Two terms swapped are named for what they are ("Anaphase vs telophase"); two sentences are not, and the screens say how
            // many misses on how many questions instead.
            let named = ConfusionFinder.isTerm(first) && ConfusionFinder.isTerm(second)
            let name = named ? "\(Lexicon.capitalizedFirst(first)) vs \(LocalGrader.lowerFirst(second))" : ConfusionCandidate.unnamed
            let lesson = "For “\(Lexicon.trimmedSentence(a.prompt))”, the answer is \(LocalGrader.lowerFirst(second)). "
                + "For “\(Lexicon.trimmedSentence(b.prompt))”, it's \(LocalGrader.lowerFirst(first))."
            let questions = [a, b].enumerated().map { n, m -> GeneratedItem in
                let other = m.itemId == a.itemId ? b.expected : a.expected
                return GeneratedItem(id: "x\(out.count + 1)-\(n + 1)", kind: .mcq, topic: m.topic, prompt: m.prompt,
                                     answer: m.expected, explanation: "",
                                     choices: [Choice(text: m.expected, correct: true), Choice(text: other, correct: false)],
                                     anchors: [], difficulty: 0.4)
            }
            let explanation = named
                ? "You've answered \(LocalGrader.lowerFirst(first)) where it was \(LocalGrader.lowerFirst(second)), and the other way round."
                : ConfusionFinder.description(misses: a.misses + b.misses, questions: 2)
            out.append(ConfusionOut(name: name, explanation: explanation,
                                    itemIds: [a.itemId, b.itemId], lesson: lesson, questions: questions))
        }

        // Weak topics.
        let byTopic = Dictionary(grouping: mistakes.filter { !used.contains($0.itemId) && !$0.topic.isEmpty }, by: \.topic)
        for (topic, items) in byTopic.sorted(by: { $0.key < $1.key }) {
            let misses = items.reduce(0) { $0 + $1.misses }
            guard items.count >= 2, misses >= 3 else { continue }
            let lesson = items.prefix(3).map { "\(Lexicon.trimmedSentence($0.prompt)): \(Lexicon.trimmedSentence($0.expected))." }
                .joined(separator: " ")
            out.append(ConfusionOut(name: topic,
                                    explanation: "You've missed \(items.count) questions on \(LocalGrader.lowerFirst(topic)), \(misses) times between them.",
                                    itemIds: items.map(\.itemId), lesson: lesson, questions: []))
        }
        return out
    }

    /// One question missed: there's no pattern to explain and the relay would write nothing, so the rules say what the answer is. When the wrong answer is short
    /// enough to set beside the right one, a two-choice question between them; otherwise the fix drills the question itself.
    static func recap(_ mistake: MistakeInput, name: String, explanation: String) -> ConfusionOut {
        let prompt = Lexicon.trimmedSentence(mistake.prompt), answer = Lexicon.trimmedSentence(mistake.expected)
        let given = Lexicon.trimmedSentence(mistake.given)
        let beside = !given.isEmpty && !same(mistake.given, mistake.expected) && given.count <= recapChoiceLength
        let lesson: String
        if !ConfusionFinder.isTerm(answer) {
            lesson = String(localized: "For “\(prompt)”, the answer: \(answer).")
        } else if beside, ConfusionFinder.isTerm(given) {
            lesson = String(localized: "For “\(prompt)”, the answer is \(LocalGrader.lowerFirst(answer)), not \(LocalGrader.lowerFirst(given)).")
        } else {
            lesson = String(localized: "For “\(prompt)”, the answer is \(LocalGrader.lowerFirst(answer)).")
        }
        let question = GeneratedItem(id: "r1", kind: .mcq, topic: mistake.topic, prompt: mistake.prompt, answer: mistake.expected, explanation: "",
                                     choices: [Choice(text: mistake.expected, correct: true), Choice(text: mistake.given, correct: false)],
                                     anchors: [], difficulty: 0.4)
        return ConfusionOut(name: name, explanation: explanation, itemIds: [mistake.itemId], lesson: lesson, questions: beside ? [question] : [])
    }

    /// The longest wrong answer a two-choice question sets beside the right one.
    private static let recapChoiceLength = 80

    /// Two look-alikes side by side, before any mistake: each one with what tells it apart, and a two-choice question for each. What the
    /// sheet shows when Cloud AI isn't asked.
    static func sideBySide(_ a: LookAlikeSide, _ b: LookAlikeSide) -> ConfusionOut {
        // A clue is often the question itself, which has its own full stop.
        func sentence(_ text: String) -> String {
            let trimmed = Lexicon.trimmedSentence(text)
            return trimmed.hasSuffix("?") || trimmed.hasSuffix("!") ? trimmed : trimmed + "."
        }
        func line(_ side: LookAlikeSide) -> String {
            "\(Lexicon.capitalizedFirst(side.term)): \(sentence(side.clue))"
        }
        func question(_ side: LookAlikeSide, _ other: LookAlikeSide, _ n: Int) -> GeneratedItem {
            let isOwnPrompt = ConfusionFinder.normalize(side.term) == ConfusionFinder.normalize(side.answer)
            let prompt = isOwnPrompt ? side.prompt : String(localized: "Which one is this? \(sentence(side.clue))")
            return GeneratedItem(id: "l\(n)", kind: .mcq, topic: side.topic, prompt: prompt, answer: side.term, explanation: line(side),
                                 choices: [Choice(text: side.term, correct: true), Choice(text: other.term, correct: false)],
                                 anchors: [], difficulty: 0.4)
        }
        return ConfusionOut(name: ConfusionFinder.joinNames([a.term, b.term]),
                            explanation: String(localized: "They look alike. One thing tells them apart."),
                            itemIds: [a.itemID.uuidString, b.itemID.uuidString], lesson: "\(line(a)) \(line(b))",
                            questions: [question(a, b, 1), question(b, a, 2)])
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        let x = Lexicon.normalizedAnswer(a), y = Lexicon.normalizedAnswer(b)
        return !x.isEmpty && (x == y || LocalGrader.exactMatch(a, accepted: [b]) != .wrong)
    }
}

/// Flashcards from a tutor chat by the offline rules (tier T0): definitions stated in Cap's answers, and the
/// person's question with the first sentences of the answer. Drafts only: the person picks which to keep.
enum LocalCardsFromChat {

    static func cards(messages: [TutorMessage], maxItems: Int) -> [GeneratedItem] {
        var out: [GeneratedItem] = []
        var seen = Set<String>()
        func add(_ front: String, _ back: String) {
            let key = Lexicon.normalizedAnswer(front)
            guard !key.isEmpty, !back.isEmpty, out.count < maxItems, seen.insert(key).inserted else { return }
            out.append(GeneratedItem(id: "m\(out.count + 1)", kind: .flashcard, topic: "", prompt: front, answer: back,
                                     difficulty: 0.3))
        }
        for (i, message) in messages.enumerated() where message.role == .assistant {
            let sentences = Lexicon.sentences(message.text).filter { !$0.hasSuffix("?") && !$0.lowercased().hasPrefix("quick check") }
            for sentence in sentences {
                if let d = PageStructure.sentenceDefinition(sentence) {
                    add(d.term, Lexicon.capitalizedFirst(d.meaning) + ".")
                } else if let d = PageStructure.lineDefinition(sentence) {
                    add(d.term, Lexicon.capitalizedFirst(d.meaning) + ".")
                }
            }
            if let question = messages[..<i].last(where: { $0.role == .user }), !sentences.isEmpty {
                let front = Lexicon.trimmedSentence(question.text)
                guard front.split(separator: " ").count <= 16 else { continue }
                let back = sentences.prefix(2).joined(separator: " ")
                add(front.hasSuffix("?") ? front : front + "?", back)
            }
        }
        return out
    }
}
