import Foundation

/// One question of a topic, as Teach Cap reads it.
struct TeachItem: Sendable, Equatable {
    var id: UUID
    var kind: ItemKind
    var prompt: String
    /// The right option's words, a fill-in's blank, or the model answer.
    var answer: String
    var ideas: [KeyIdea] = []
    /// Chance of recall now; nil when it has never been studied.
    var recall: Double? = nil
    /// A fill-in's sentence, with `{{…}}` around its blanks.
    var cloze: ClozeSpec? = nil
    /// What the question says about its answer: the right option's reason, or its explanation.
    var explanation: String = ""
}

/// One idea Cap hopes to hear, and the question behind it.
struct TeachIdea: Sendable, Equatable, Identifiable {
    /// "t1"…: unique in the plan (two questions can each have a "k1").
    var idea: KeyIdea
    var itemID: UUID
    /// A whole statement made from the question, not key ideas with terms someone chose: the rules read all of it (`GradeSubject.wholeIdeas`).
    var isStatement = false
    var id: String { idea.id }
    var label: String { idea.label }
    /// The words the speech recogniser is primed with: a statement's longest ones, since nobody says all of it in order.
    var hearingTerms: [String] { isStatement ? TeachPlanner.terms(of: label) : idea.terms }
}

/// What explaining a topic to Cap is checked against.
struct TeachPlan: Sendable, Equatable {
    var topicID: UUID
    var topicName: String
    var courseID: UUID?
    var ideas: [TeachIdea]

    /// The grader's view of it: a question that isn't in the student's library, whose key ideas are the plan's. Goes through the same grade path
    /// as any own-words answer, so the relay needs nothing new (it takes up to 12 ideas; this has at most 6).
    func subject(level: String?) -> GradeSubject {
        let answer = ideas.map { $0.label.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.joined(separator: ". ")
        return GradeSubject(kind: .recall, prompt: "Explain \(topicName)", modelAnswer: answer, keyIdeas: ideas.map(\.idea), level: level,
                            wholeIdeas: Set(ideas.filter(\.isStatement).map(\.id)))
    }

    /// The first idea of these that wasn't covered, in the plan's order: weakest first.
    func firstMissing(covered: Set<String>) -> TeachIdea? {
        ideas.first { !covered.contains($0.id) }
    }
}

/// A topic the student knows well enough to be offered Teach Cap.
struct NoticeTeachBack: Equatable, Sendable {
    var topicID: UUID
    var topicName: String
    var courseID: UUID?
}

/// What Teach Cap asks about, and when Cap offers it. Pure.
///
/// A plan is up to six ideas, weakest first: a question's key ideas, or when it has none one whole statement made from it, one idea from each question
/// before a second from any. Questions never studied come last: nobody should be marked down for what they haven't met yet.
///
/// The offer ("You know \(topic). Can you teach it?") reads topic recall (`ReadinessEngine.topicMastery`), which no screen shows as a number. It
/// wants most of the topic studied and well remembered, an exam a week or more away (closer than that, reviews matter more), no exam on it in the last few days (it's fresh, and they've
/// earned a rest), no teaching of it in the last 14 days, and a name that reads as a topic.
enum TeachPlanner {
    static let maxIdeas = 6
    static let minIdeas = 2
    /// How well a topic has to be remembered for Cap to say "you know it".
    static let offerRecall = 0.85
    static let offerMinStudied = 3
    static let offerStudiedShare = 0.6
    static let offerExamDays = 7
    /// Days after an exam that Cap doesn't ask to teach what was on it.
    static let offerAfterExamDays = 3
    static let offerQuietDays = 14
    /// The fewest words an answer needs to say something by itself. "Metaphase" and "The centromeres" don't; "The part of interphase when DNA is replicated" does.
    static let statementWords = 4

    static func plan(topicID: UUID, topicName: String, courseID: UUID?, items: [TeachItem]) -> TeachPlan? {
        // The weakest first; the never studied after every studied one; ties in a fixed order.
        let ordered = items.sorted { a, b in
            switch (a.recall, b.recall) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.id.uuidString < b.id.uuidString
            }
        }
        let topicStems = Set(Lexicon.contentStems(topicName))
        // An idea that only says the topic's name has nothing in it to explain.
        let perItem = ordered.map { item in
            (item: item, ideas: ideas(of: item).filter { !item.ideas.isEmpty || !Set(Lexicon.contentStems($0.label)).isSubset(of: topicStems) })
        }
        var chosen: [TeachIdea] = []
        var seen = Set<String>()
        var round = 0
        while chosen.count < maxIdeas, perItem.contains(where: { round < $0.ideas.count }) {
            for entry in perItem where round < entry.ideas.count && chosen.count < maxIdeas {
                let idea = entry.ideas[round]
                guard seen.insert(normal(idea.label)).inserted else { continue }
                chosen.append(TeachIdea(idea: KeyIdea(id: "t\(chosen.count + 1)", label: idea.label, terms: idea.terms), itemID: entry.item.id,
                                        isStatement: entry.item.ideas.isEmpty))
            }
            round += 1
        }
        guard chosen.count >= minIdeas else { return nil }
        return TeachPlan(topicID: topicID, topicName: topicName, courseID: courseID, ideas: chosen)
    }

    /// A question's ideas: its own, or one whole statement made from it. A key idea of a word or two reads beside its question, as a short answer does: "Anaphase is blocked" says
    /// nothing by itself.
    static func ideas(of item: TeachItem) -> [KeyIdea] {
        if !item.ideas.isEmpty {
            let prompt = item.prompt.clTrimmed
            return item.ideas.filter { !$0.label.isEmpty }.map { idea in
                guard prompt.hasSuffix("?"), Lexicon.wordCount(idea.label) < statementWords else { return idea }
                var whole = idea
                whole.label = closed("\(prompt) \(Lexicon.capitalizedFirst(idea.label))")
                return whole
            }
        }
        guard let statement = statement(of: item) else { return [] }
        // What a model is told to listen for: a short answer, or the statement. The rules read the statement's words instead (`GradeSubject.wholeIdeas`).
        let short = item.cloze == nil && !item.answer.clTrimmed.isEmpty && Lexicon.wordCount(item.answer) < statementWords
        return [KeyIdea(id: "a", label: statement, terms: [(short ? item.answer.clTrimmed : statement).lowercased()])]
    }

    /// What a question with no key ideas says, as something a person could explain. A fill-in's sentence, with its blank filled. An answer that says something by itself, after its
    /// term when the question is only a term ("S phase: the part of interphase when DNA is replicated."). A short answer needs more: the sentence of its explanation that names it,
    /// else its question beside it ("Which phase lines the chromosomes up? Metaphase."). Nil when there's nothing to explain: a sum, or an answer that only repeats its question.
    static func statement(of item: TeachItem) -> String? {
        let prompt = item.prompt.clTrimmed, answer = item.answer.clTrimmed
        if let cloze = item.cloze {
            let sentence = cloze.filled.clTrimmed
            return Lexicon.wordCount(sentence) >= statementWords ? sentence : nil
        }
        guard !answer.isEmpty, !repeatsItself(prompt: prompt, answer: answer) else { return nil }
        if Lexicon.wordCount(answer) >= statementWords {
            return isBareTerm(prompt) ? closed("\(prompt): \(SessionCopy.lowerFirst(answer))") : answer
        }
        let stems = Set(Lexicon.contentStems(answer))
        if !stems.isEmpty, let said = Lexicon.sentences(item.explanation).first, Lexicon.wordCount(said) >= statementWords,
           stems.isSubset(of: Set(Lexicon.contentStems(said))) {
            return said
        }
        // A sum's answer says nothing beside it; a number that answers a question in words does.
        let questionWords = Lexicon.tokens(prompt).filter { $0.isContent && !$0.isNumber }.count
        guard questionWords >= (answer.contains(where: \.isLetter) ? 1 : 2) else { return nil }
        return prompt.hasSuffix("?") ? closed("\(prompt) \(Lexicon.capitalizedFirst(answer))") : closed("\(prompt): \(SessionCopy.lowerFirst(answer))")
    }

    /// What the follow-up asks: the question as it stands, a fill-in's sentence with its blank, or for a question that's only a term, a real question.
    static func followUpPrompt(of item: TeachItem) -> String {
        if let cloze = item.cloze { return cloze.blanked }
        return isBareTerm(item.prompt.clTrimmed) ? TeachCopy.explainTerm(item.prompt.clTrimmed) : item.prompt
    }

    /// The question a missed idea becomes. A key idea is asked by name and answered by its question's answer; a statement asks what its question asked. Nil when the answer would
    /// only repeat the question: there's nothing to practise in "Explain in your own words: Metaphase." answered "Metaphase".
    static func addedQuestion(for idea: TeachIdea, from item: TeachItem) -> (prompt: String, answer: String, idea: KeyIdea)? {
        // A short key idea already reads beside its question: that's the question.
        let besideQuestion = !idea.isStatement && idea.label.hasPrefix(item.prompt.clTrimmed) && item.prompt.clTrimmed.hasSuffix("?")
        let prompt = idea.isStatement || besideQuestion ? followUpPrompt(of: item) : TeachCopy.questionFor(idea: idea.label)
        let answer = item.answer.clTrimmed
        guard !answer.isEmpty, !repeatsItself(prompt: prompt, answer: answer) else { return nil }
        if idea.isStatement { return (prompt, answer, KeyIdea(id: "k1", label: answer, terms: terms(of: answer))) }
        let label = besideQuestion ? String(idea.label.dropFirst(item.prompt.clTrimmed.count)).clTrimmed : idea.label
        return (prompt, answer, KeyIdea(id: "k1", label: label, terms: idea.idea.terms))
    }

    /// A short answer is its own term; in a long one nobody says every word in order, so its longest words count too.
    static func terms(of answer: String) -> [String] {
        let words = answer.split(whereSeparator: \.isWhitespace).map { $0.trimmingCharacters(in: .punctuationCharacters) }
        guard words.count > 4 else { return [answer.lowercased()] }
        let long = words.filter { $0.count >= 6 }.sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }.prefix(3)
        return [answer.lowercased()] + long.map { $0.lowercased() }
    }

    /// The grader's view of the question behind a missed idea, whatever its kind: the follow-up is answered in the person's own words, without its options.
    static func followUpSubject(_ item: TeachItem, level: String?) -> GradeSubject {
        let ideas = ideas(of: item)
        return GradeSubject(kind: .recall, prompt: followUpPrompt(of: item), modelAnswer: item.answer, keyIdeas: ideas, level: level,
                            wholeIdeas: item.ideas.isEmpty ? Set(ideas.map(\.id)) : [])
    }

    /// The topics to offer, the best remembered first. `mastery`: `ReadinessEngine.topicMastery` of each course. `taught`: when each topic (its uuidString)
    /// was last taught.
    static func offers(mastery: [TopicReadiness], courseOf: [UUID: UUID], items: [ItemSnapshot], exams: [ExamSnapshot], taught: [String: Date], now: Date,
                       calendar: Calendar) -> [NoticeTeachBack] {
        let index = ExamIndex(exams, after: now, calendar: calendar)
        let justSat = exams.filter { $0.date <= now && calendar.dayDistance(from: $0.date, to: now) < offerAfterExamDays }
        var byTopic: [UUID: [ItemSnapshot]] = [:]
        for item in items where item.isActive {
            if let topic = item.topicID { byTopic[topic, default: []].append(item) }
        }
        let good = mastery.compactMap { topic -> (NoticeTeachBack, Double)? in
            guard let recall = topic.value, recall >= offerRecall, let its = byTopic[topic.id], readsAsATopic(topic.name) else { return nil }
            if its.contains(where: { item in justSat.contains { $0.covers(item) } }) { return nil }
            let studied = its.filter(\.isStudied).count
            guard studied >= offerMinStudied, Double(studied) / Double(its.count) >= offerStudiedShare else { return nil }
            if let date = taught[topic.id.uuidString], calendar.dayDistance(from: date, to: now) < offerQuietDays { return nil }
            let days = its.compactMap { index.soonest(covering: $0) }.compactMap { index.daysLeft[$0.id] }.min()
            if let days, days < offerExamDays { return nil }
            return (NoticeTeachBack(topicID: topic.id, topicName: topic.name, courseID: courseOf[topic.id]), recall)
        }
        return good.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.topicName < $1.0.topicName }.map(\.0)
    }

    /// Words that can't follow "You know": what was left of a heading, a question or a sentence, filed as a topic's name.
    private static let notANameWords: Set<String> = ["first", "second", "third", "fourth", "last", "next", "other", "others", "dear", "misc", "general", "notes", "more", "part", "section", "intro"]
    private static let openers: Set<String> = ["what", "why", "how", "when", "where", "who", "which", "whose", "whom", "do", "does", "did", "is", "are", "was", "were", "can", "could", "should", "would",
                                               "in", "on", "at", "by", "for", "from", "to", "with", "and", "or", "but", "if", "because", "that", "this", "these", "those", "he", "she", "they", "it", "we", "you"]

    /// A name Cap can say a sentence about: not one word like "First", not a question, not a sentence.
    static func readsAsATopic(_ name: String) -> Bool {
        let trimmed = name.clTrimmed
        guard !trimmed.isEmpty, !trimmed.hasSuffix("."), !trimmed.hasSuffix("?"), !trimmed.hasSuffix("!") else { return false }
        let words = Lexicon.tokens(trimmed).map(\.word)
        guard let first = words.first else { return false }
        if words.count == 1, notANameWords.contains(first) { return false }
        return !openers.contains(first)
    }

    /// A flashcard's front, not a question: a few words with no question mark or full stop.
    private static func isBareTerm(_ prompt: String) -> Bool {
        !prompt.isEmpty && Lexicon.wordCount(prompt) <= 3 && !prompt.hasSuffix("?") && !prompt.hasSuffix(".")
    }

    /// Every word of the answer is already in the question.
    private static func repeatsItself(prompt: String, answer: String) -> Bool {
        let stems = Set(Lexicon.contentStems(answer))
        return !stems.isEmpty && stems.isSubset(of: Set(Lexicon.contentStems(prompt)))
    }

    private static func closed(_ text: String) -> String {
        text.last.map { ".?!".contains($0) } == true ? text : text + "."
    }

    private static func normal(_ label: String) -> String {
        label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
