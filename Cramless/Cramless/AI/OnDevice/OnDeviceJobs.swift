import Foundation

// The on-device jobs: what each call tells the model, and how its answer becomes the contract's values. The model
// only proposes. Every mapping re-checks: line references must be lines of the page (the grounding check runs
// after), a choice question needs one right and two or more wrong options, a fill-in needs its blank, a grade's
// quote must be in the person's answer to be marked, a tutor quote must be in the passage it cites. Whatever fails
// is dropped, and a job that ends with nothing usable returns nil (the router keeps the offline answer).

// MARK: - Generate (one page, or a piece of one)

struct OnDevicePageCall: OnDeviceCall {
    typealias Output = FMPageQuestions
    static let kind = OnDeviceCallKind.generate
    static let schemaTokens = 520
    static let responseTokens = 1400
    static let timeout = Duration.seconds(25)
    static let temperature = 0.2
    static let instructions = """
    You write study questions for a student from the numbered lines of their own notes. Use only those lines and \
    never add facts that are not in them. Every question must be answerable from the lines alone, its answer must \
    answer exactly that question, and its lines must list the numbers of the lines its answer comes from. Skip page \
    numbers and headers. Write plain, short sentences. Never ask a question with NOT, EXCEPT or "which is false". \
    Mix the kinds: recall (answered in the student's own words, with one to three key ideas), multipleChoice (one \
    right answer and three wrong answers of the same kind, each clearly wrong according to the lines), fillIn (a \
    sentence from the lines with one important word replaced by ____), flashcard (a term on the front and its \
    meaning as the answer). A key idea is a phrase of two to six words that states one fact from the answer, for \
    example "chromatids pulled to opposite poles"; its terms are the few words a student would use for it.
    """

    /// "L1" → the page's line id.
    let refs: [(ref: String, line: TextLine)]
    let maxQuestions: Int

    init(lines: [TextLine], maxQuestions: Int) {
        self.refs = lines.enumerated().map { ("L\($0.offset + 1)", $0.element) }
        self.maxQuestions = maxQuestions
    }

    var prompt: String {
        "Lines:\n" + refs.map { "\($0.ref): \($0.line.text)" }.joined(separator: "\n")
            + "\n\nWrite up to \(maxQuestions) questions."
    }

    static func render(_ line: TextLine) -> String { "L000: \(line.text)" }
}

enum OnDeviceGeneration {
    /// The model's questions as generated items (ids "d1", "d2", …), with line references turned back into the
    /// page's line ids. A reference the model made up is kept as written, so the grounding check drops the item
    /// with a reason. Shapes that can't be a valid item are left out here.
    static func items(from output: FMPageQuestions, call: OnDevicePageCall, startingAt first: Int) -> (topics: [String], items: [GeneratedItem]) {
        let byRef = Dictionary(call.refs.map { ($0.ref.uppercased(), $0.line.id) }, uniquingKeysWith: { a, _ in a })
        let topics = output.topics.map(clean).filter { !$0.isEmpty }
        var items: [GeneratedItem] = []
        var n = first
        var seenPrompts: Set<String> = []
        for q in output.questions {
            // A footnote number or a pronunciation guide the model copied from a printout is taken out before anything is judged.
            let prompt = TextArtifacts.withoutMarkers(clean(q.prompt)), answer = TextArtifacts.withoutMarkers(clean(q.answer))
            guard !prompt.isEmpty, !answer.isEmpty else { continue }
            // Measured: the model sometimes writes the same question several times, and sometimes one whose
            // answer is already in it ("a key term for growth and development? → Growth and Development").
            guard seenPrompts.insert(Lexicon.normalizedAnswer(prompt)).inserted else { continue }
            let answerStems = Set(Lexicon.contentStems(answer))
            if q.kind != "fillIn", !answerStems.isEmpty, answerStems.isSubset(of: Set(Lexicon.contentStems(prompt))) { continue }
            // A negative stem ("Which is NOT a phase…") is where a small model was measured marking a true option
            // as the answer; nothing can check it, so such questions are left out.
            guard !hasNegativeStem(prompt) else { continue }
            let anchors = q.lines.map { ref -> String in
                let r = ref.trimmingCharacters(in: .whitespaces).uppercased()
                let key = r.allSatisfy(\.isNumber) ? "L\(r)" : r
                return byRef[key] ?? ref
            }
            let topic = clean(q.topic).isEmpty ? (topics.first ?? "") : clean(q.topic)
            var item = GeneratedItem(id: "d\(n)", kind: .recall, topic: topic, prompt: prompt, answer: answer,
                                     anchors: anchors, difficulty: 0.5)
            switch q.kind {
            case "multipleChoice":
                // Measured: the on-device model's wrong options were often true per the page ("to repair damaged
                // cells" as a wrong purpose of mitosis), and nothing can check that. Multiple choice comes from the
                // rules (parallel headings) or the cloud's checked set instead; the question is kept as a flashcard
                // when its answer is short enough to be one.
                guard answer.split(whereSeparator: \.isWhitespace).count <= 12 else { continue }
                item.kind = .flashcard
                item.difficulty = 0.3
            case "fillIn":
                // The model often puts the whole sentence as the answer: the blank is then the answer's words that
                // the cloze sentence leaves out ("During prophase, chromosomes ____." + "Chromosomes condense
                // during prophase." → "condense").
                let sentence = TextArtifacts.withoutMarkers(clean(q.clozeSentence))
                let blank = blankWord(sentence: sentence, answer: answer) ?? answer
                guard let cloze = clozeText(sentence: sentence, answer: blank) else { continue }
                item.answer = blank
                // The model's question for a fill-in often asks about something else; the sentence is the question.
                item.prompt = "Fill in the blank."
                item.kind = .cloze
                item.cloze = ClozeSpec(text: cloze)
                item.difficulty = 0.35
            case "flashcard":
                item.kind = .flashcard
                item.difficulty = 0.25
            default:
                let ideas = q.keyIdeas.enumerated().compactMap { i, idea -> KeyIdea? in
                    let label = clean(idea.label)
                    var terms = uniqued(idea.terms.map { clean($0).lowercased() }.filter { !$0.isEmpty })
                    if terms.isEmpty, !label.isEmpty { terms = [label.lowercased()] }
                    return label.isEmpty ? nil : KeyIdea(id: "k\(i + 1)", label: label, terms: terms)
                }
                let usable = groundedIdeas(ideas, answer: answer, prompt: prompt)
                guard !usable.isEmpty else { continue }
                item.kind = .recall
                item.keyIdeas = usable
                item.difficulty = min(0.7, 0.4 + 0.08 * Double(usable.count))
            }
            // Measured: 37% of this model's questions had a zero in the blind ratings (a "Term" card, a cut-off prompt, a
            // blank that is "Next"). The shared filter keeps those from being shown.
            guard QuestionQuality.problem(with: item) == nil else { continue }
            // Nor the same fact twice in other words (a card and a fill-in of one sentence).
            guard !items.contains(where: { QuestionQuality.isNearDuplicate($0, item) }) else { continue }
            items.append(item)
            n += 1
        }
        return (topics, items)
    }

    /// The answer's words missing from a cloze sentence that has a blank: the word that goes in the blank.
    static func blankWord(sentence: String, answer: String) -> String? {
        guard sentence.range(of: #"_{2,}"#, options: .regularExpression) != nil else { return nil }
        let present = Set(Lexicon.tokens(sentence).map(\.word))
        let missing = Lexicon.tokens(answer).filter { !present.contains($0.word) && !$0.isStopWord }.map(\.word)
        guard (1...3).contains(missing.count) else { return nil }
        let chars = Array(answer)
        let first = Lexicon.tokens(answer).first { $0.word == missing.first }
        let last = Lexicon.tokens(answer).last { $0.word == missing.last }
        guard let first, let last, first.range.lowerBound < last.range.upperBound else { return missing.joined(separator: " ") }
        return String(chars[first.range.lowerBound..<last.range.upperBound])
    }

    /// "Which of these is NOT…", "…except…", "Which is false…".
    static func hasNegativeStem(_ prompt: String) -> Bool {
        prompt.range(of: #"\b(not|except|false|never|isn't|aren't|doesn't|don't)\b"#,
                     options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Key ideas the answer backs. A small model was measured labelling ideas "Purpose" or "Role": a label of one
    /// word, or one whose words and terms appear nowhere in the answer, can't grade anything. Usable ideas are kept
    /// (renumbered); when none is usable they are rebuilt from the answer itself, one per clause (at most three),
    /// with the clause's content words as terms in pairs, so a grade still rests on the answer's own facts.
    static func groundedIdeas(_ ideas: [KeyIdea], answer: String, prompt: String = "") -> [KeyIdea] {
        // What the answer adds beyond the question: an idea that only restates the question
        // ("The four main phases of mitosis" for "What are the four main phases of mitosis?") grades nothing.
        let promptStems = Set(Lexicon.contentStems(prompt))
        let newStems = Set(Lexicon.contentStems(answer)).subtracting(promptStems)
        let usable = ideas.filter { idea in
            let stems = Lexicon.contentStems(idea.label) + idea.terms.flatMap { Lexicon.contentStems($0) }
            let words = idea.label.split(whereSeparator: \.isWhitespace).count
            let isTerm = words == 1 && newStems.contains(Lexicon.contentStems(idea.label).first ?? "")
            return (words >= 2 || isTerm) && stems.contains(where: newStems.contains)
        }
        if !usable.isEmpty {
            return usable.prefix(4).enumerated().map { i, idea in KeyIdea(id: "k\(i + 1)", label: idea.label, terms: idea.terms) }
        }
        let body = answer.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // A list ("…are prophase, metaphase, anaphase, and telophase"): one idea per item.
        let parts = body.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }
        let items = parts.map { part -> String in
            // The tail of the first part ("…are prophase") is the first item.
            let words = Lexicon.tokens(part).filter { $0.isContent && !promptStems.contains($0.stem) }.map(\.word)
            return words.joined(separator: " ")
        }.filter { !$0.isEmpty && $0.split(separator: " ").count <= 3 }
        if items.count >= 3 {
            return items.prefix(4).enumerated().map { i, item in KeyIdea(id: "k\(i + 1)", label: item, terms: [item]) }
        }
        // Otherwise one idea per clause (at most three), its terms the clause's new words in pairs.
        var clauses = body.split(whereSeparator: { ",;".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { Lexicon.contentStems($0).count >= 2 }
        if clauses.isEmpty { clauses = [body] }
        return clauses.prefix(3).enumerated().compactMap { i, clause in
            let words = Lexicon.tokens(clause).filter { $0.isContent && !promptStems.contains($0.stem) }.map(\.word)
            guard !words.isEmpty else { return nil }
            var terms = zip(words, words.dropFirst()).map { "\($0) \($1)" }
            if let longest = words.max(by: { $0.count < $1.count }), longest.count >= 6 { terms.append(longest) }
            if terms.isEmpty { terms = words }
            let label = clause.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ")
            return KeyIdea(id: "k\(i + 1)", label: label, terms: Array(Set(terms)).sorted())
        }
    }

    /// "During ____, the envelopes re-form." + "telophase" → "During {{telophase}}, the envelopes re-form."; a
    /// sentence without a blank but with the answer in it gets the answer wrapped.
    static func clozeText(sentence: String, answer: String) -> String? {
        guard !sentence.isEmpty else { return nil }
        // The blank is a word or a short term, and the sentence around it has to give something away: a blank that
        // is the whole sentence (measured) tests nothing.
        let blankWords = answer.split(whereSeparator: \.isWhitespace).count
        guard blankWords <= 4, Double(answer.count) < Double(sentence.count) * 0.6 else { return nil }
        if let blank = sentence.range(of: #"_{2,}"#, options: .regularExpression) {
            return sentence.replacingCharacters(in: blank, with: "{{\(answer)}}")
        }
        if let found = sentence.range(of: answer, options: [.caseInsensitive, .diacriticInsensitive]) {
            return sentence.replacingCharacters(in: found, with: "{{\(sentence[found])}}")
        }
        return nil
    }
}

// MARK: - Grade

struct OnDeviceGradeCall: OnDeviceCall {
    typealias Output = FMGrade
    static let kind = OnDeviceCallKind.grade
    static let schemaTokens = 260
    static let responseTokens = 420
    static let timeout = Duration.seconds(10)
    static let instructions = """
    You check a student's short answer against the key ideas of a model answer. For each key idea, decide whether \
    the answer clearly states it, in any words: different wording that means the same counts, the idea said as its \
    opposite does not. For each idea that is present, copy the exact words from the answer that state it. Then \
    write one short, kind sentence about what the answer got right, and one sentence that would complete it (empty \
    if nothing is missing). Use only facts from the model answer.
    """

    let subject: GradeSubject
    let answer: String

    var prompt: String {
        var lines = ["Question: \(subject.prompt)", "Model answer: \(subject.modelAnswer)", "Key ideas:"]
        for (i, idea) in subject.keyIdeas.enumerated() { lines.append("K\(i + 1): \(idea.label)") }
        lines.append("Student's answer: \(answer)")
        return lines.joined(separator: "\n")
    }
}

enum OnDeviceGrading {
    /// The model's check as a grade. Ideas are matched by their number; a quote marks the answer only if it is
    /// in it word for word (else the offline grader's own range for that idea is used, if it found one). The
    /// confidence comes from agreement with the offline grade. Nil when the answer doesn't cover the ideas.
    static func outcome(from output: FMGrade, subject: GradeSubject, answer: String, local: GradeOutcome) -> GradeOutcome? {
        let ideas = subject.keyIdeas
        guard !ideas.isEmpty, !output.ideas.isEmpty else { return nil }
        var present: [String: String] = [:]
        for check in output.ideas {
            let digits = check.id.filter(\.isNumber)
            guard let n = Int(digits), (1...ideas.count).contains(n) else { continue }
            if check.present { present[ideas[n - 1].id] = check.quote }
        }
        // An idea counts when someone can point at the person's own words for it: the model's quote found in the
        // answer word for word, or the rules' match. Measured on paraphrased answers, the model and the rules each
        // missed a different idea; the evidence-backed union got both. A claim with no such words doesn't count.
        var marks: [GradeMark] = []
        var hitSet: Set<String> = []
        var unbacked = 0
        var modelBacked: Set<String> = []
        for idea in ideas {
            if let quote = present[idea.id], let range = HighlightMark.locate(quote, in: answer) {
                marks.append(GradeMark(ideaID: idea.id, range: range))
                hitSet.insert(idea.id)
                modelBacked.insert(idea.id)
            } else if local.hitIdeaIDs.contains(idea.id) {
                marks += local.marks.filter { $0.ideaID == idea.id }
                hitSet.insert(idea.id)
                if present[idea.id] != nil { modelBacked.insert(idea.id) }
            } else if present[idea.id] != nil {
                unbacked += 1
            }
        }
        let hit = ideas.map(\.id).filter(hitSet.contains)
        let missingIdeas = ideas.filter { !hitSet.contains($0.id) }
        let disagreements = modelBacked.symmetricDifference(Set(local.hitIdeaIDs)).count
        var confidence = disagreements == 0 ? 0.86 : disagreements == 1 ? 0.74 : 0.62
        confidence -= 0.06 * Double(unbacked)
        let verdict: GradeResponse.Verdict = hit.count == ideas.count ? .correct : hit.isEmpty ? .incorrect : .partial
        // The words come from the hits, never from the model's prose (see LocalGrader.ownWordsCopy).
        let copy = LocalGrader.ownWordsCopy(verdict: verdict, hit: hit, missing: missingIdeas, ideas: ideas,
                                            modelAnswer: subject.modelAnswer)
        return GradeOutcome(score: Double(hit.count) / Double(ideas.count), verdict: verdict,
                            confidence: max(0.3, min(0.9, confidence)), marks: marks, hitIdeaIDs: hit,
                            missing: missingIdeas.map { MissingIdea(id: $0.id, label: $0.label) },
                            feedback: copy.feedback, fix: copy.fix, gradedBy: .onDevice, model: "on-device", isRefined: true)
    }
}

// MARK: - Tutor (short replies)

struct OnDeviceTutorCall: OnDeviceCall {
    typealias Output = FMTutorReply
    static let kind = OnDeviceCallKind.tutor
    static let schemaTokens = 220
    static let responseTokens = 450
    static let timeout = Duration.seconds(14)
    static let instructions = """
    You are Cap, a calm study helper. Answer only from the numbered passages of the student's own notes. If they \
    don't answer the question, set covered to false and say briefly that the notes don't cover it. Keep the reply \
    under four short sentences. Copy the one or two sentences you used, exactly, into quotes, and list the passage \
    numbers. Never write essays or homework for the student, and never rewrite text to hide that it was written by AI.
    """

    let question: String
    let mode: TutorMode
    let passages: [TutorSource]
    let context: TutorContext?

    var prompt: String {
        var lines: [String] = []
        switch mode {
        case .hints: lines.append("Mode: hints first. When a passage holds the answer, set covered to true, copy that sentence into quotes and list its number, then as the reply ask one short guiding question that points the student at it without giving the answer away.")
        case .explain: lines.append("Mode: explain. Answer directly in plain words, then ask one short check question.")
        }
        lines.append("Passages:")
        for (i, p) in passages.enumerated() { lines.append("[\(i + 1)] (\(p.label)) \(p.text)") }
        if let context {
            lines.append("The student answered \"\(context.given)\" to \"\(context.itemPrompt)\"; the expected answer is \"\(context.expected)\".")
        }
        lines.append("Question: \(question)")
        return lines.joined(separator: "\n")
    }
}

/// Which of the sentences the offline search ranks best answers the question. The search has the line that answers a question among its best eight for
/// 45% of the questions and puts it first for 18%; this iPhone's model reading the eight chooses it for 69% of those. Its answer is a number, so what is
/// shown is always the notes' own sentence: nothing it writes reaches the student, and it needs no "covered" flag (which this iPhone's model sets false
/// on every reply on iOS 27). It cannot be trusted to say that none of the sentences answers (it said so once in 148 questions), so whether the notes
/// cover the question stays with the search's gate.
struct OnDevicePickCall: OnDeviceCall {
    typealias Output = FMPick
    static let kind = OnDeviceCallKind.pick
    static let schemaTokens = 60
    static let responseTokens = 12
    static let timeout = Duration.seconds(8)
    static let instructions = """
    You choose which sentence of a student's class notes answers a question. Reply with the number of the one sentence that answers it. \
    If none of the sentences answers it, reply 0.
    """

    let question: String
    /// What the student asked just before, for a question that leans on it ("and when did it end?").
    var earlier: String?
    let sentences: [String]

    var prompt: String {
        var lines: [String] = []
        if let earlier, !earlier.isEmpty { lines.append("Earlier question: \(earlier)") }
        lines.append("Question: \(question)")
        lines.append("")
        lines.append("Sentences:")
        lines += sentences.enumerated().map { "[\($0.offset + 1)] \($0.element)" }
        return lines.joined(separator: "\n")
    }
}

enum OnDeviceTutoring {
    /// How much of the question's weight a passage must carry for a quote from it to stand as support.
    static let minimumRelation = 0.4

    /// The model's reply with its quotes checked against the passages: a quote counts only if it is in one of the
    /// passages sent (the ones it cites first; case aside), and, given the question's `terms` (`LocalRetriever.weightedTerms`),
    /// only if that passage carries at least 40% of their weight: this iPhone's model has offered a real sentence about
    /// "the violence of factions" as the cause of the French Revolution. A reply with no checked quote is not grounded and
    /// is dropped (nil), and the offline tutor answers.
    ///
    /// `closest` are the sentences the offline search itself takes for the answer (`OnDeviceWindow.closest`): its best and a second that is nearly
    /// as good. A quote that is one of them is about the question whatever words it uses: a question put in other words than the notes'
    /// ("which religious teaching sums up the ethics?") shares few of them with the passage that answers it ("the golden rule of Jesus of
    /// Nazareth"), and the share of words alone threw out replies that were right (10 of 29 with the answering line in front of the model, in the user tests).
    static func reply(from output: FMTutorReply, passages: [TutorSource], terms: [String: Double]? = nil,
                      closest: [String] = []) -> (text: String, quotes: [(source: TutorSource, quote: String)])? {
        guard output.covered else { return nil }
        let text = output.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let cited = output.passages.compactMap { n in passages.indices.contains(n - 1) ? passages[n - 1] : nil }
        var quotes: [(source: TutorSource, quote: String)] = []
        for quote in output.quotes {
            let q = quote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q.count >= 8 else { continue }
            let pool = cited + passages.filter { p in !cited.contains { $0.id == p.id } }
            guard let source = pool.first(where: { HighlightMark.locate(q, in: $0.text) != nil }) else { continue }
            if let terms, !terms.isEmpty, LocalRetriever.share(of: terms, in: source.text) < minimumRelation,
               !closest.contains(where: { HighlightMark.locate(q, in: $0) != nil || HighlightMark.locate($0, in: q) != nil }) { continue }
            quotes.append((source: source, quote: q))
        }
        guard !quotes.isEmpty else { return nil }
        return (text: text, quotes: quotes)
    }
}

// MARK: - Lecture notes (one section at a time)

struct OnDeviceLectureSectionCall: OnDeviceCall {
    typealias Output = FMLectureSection
    static let kind = OnDeviceCallKind.lectureSection
    static let schemaTokens = 160
    static let responseTokens = 360
    static let timeout = Duration.seconds(12)
    static let instructions = """
    You turn part of a lecture transcript into study notes. Give it a short title and one to three notes, each one \
    plain sentence, using only what the lecturer said. Leave out filler and asides.
    """

    let text: String
    var prompt: String { "Transcript:\n\(text)" }
}

enum OnDeviceLectureNotes {
    /// The model's section with each note checked against the transcript it came from; nil when nothing survives.
    static func section(from output: FMLectureSection, transcript: String) -> (title: String, bullets: [String])? {
        let title = output.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bullets = output.bullets.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.split(separator: " ").count <= 30 && Lexicon.overlap(of: $0, with: transcript) >= 0.5 }
        guard !bullets.isEmpty else { return nil }
        let titleWords = title.split(separator: " ").count
        return (titleWords >= 1 && titleWords <= 7 ? title : "", bullets)
    }
}

// MARK: - Cards from a chat

struct OnDeviceCardsCall: OnDeviceCall {
    typealias Output = FMCards
    static let kind = OnDeviceCallKind.cards
    static let schemaTokens = 160
    static let responseTokens = 600
    static let timeout = Duration.seconds(14)
    static let instructions = """
    You make flashcards from a study conversation. Each card is one fact the conversation states, with a short \
    front and a one-sentence back in the conversation's words. Never add facts the conversation doesn't state.
    """

    let transcript: String
    let maxCards: Int
    var prompt: String { "Conversation:\n\(transcript)\n\nMake up to \(maxCards) flashcards." }
}

enum OnDeviceCards {
    static func items(from output: FMCards, transcript: String, maxItems: Int) -> [GeneratedItem] {
        output.cards.prefix(maxItems).enumerated().compactMap { i, card in
            let front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = card.back.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty, Lexicon.overlap(of: back, with: transcript) >= 0.5 else { return nil }
            return GeneratedItem(id: "m\(i + 1)", kind: .flashcard, topic: "", prompt: front, answer: back, difficulty: 0.3)
        }
    }
}

// MARK: - Helpers

private func clean(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

private func uniqued(_ items: [String]) -> [String] {
    var seen = Set<String>()
    return items.filter { seen.insert(Lexicon.normalizedAnswer($0)).inserted }
}

