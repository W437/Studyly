import Foundation

/// The offline grader (tier T0): instant, always available, never metered. It is the first grade the person sees
/// for every answer; a model may refine it afterwards.
///
/// Own words (recall, apply) are graded by key ideas: an idea counts when one of its terms is in the answer, as a
/// phrase (in order, at most one extra word between its words), after folding case and accents, dropping stop
/// words and stemming ("divides" meets "divide", "broke" meets "break"), with one typo forgiven in words of five
/// letters or more (two from nine). A term preceded by a negation in the same clause ("doesn't help it grow")
/// does not count. Marks are the exact character ranges of the matched words in the person's answer, so the
/// highlighter only ever marks what they wrote.
///
/// Fill-ins, choices and diagram labels are checked exactly, with the item's alternates, word forms and one typo.
enum LocalGrader {

    static let model = "rules"

    static func grade(_ subject: GradeSubject, answer: AnswerInput) -> GradeOutcome {
        switch (subject.kind, answer) {
        case (.mcq, .choice(let index)):
            return gradeChoice(subject, index: index)
        case (.mcq, .text(let text)):
            return gradeTypedChoice(subject, text)
        case (.cloze, .blanks(let blanks)):
            return gradeCloze(subject, blanks)
        case (.cloze, .text(let text)):
            return gradeCloze(subject, [text])
        case (.diagram, .labels(let labels)):
            return gradeLabels(subject, labels)
        case (.diagram, .text(let text)):
            return gradeLabels(subject, text.split(separator: ",").map(String.init))
        case (_, .text(let text)):
            return gradeOwnWords(subject, text)
        case (_, .blanks(let parts)), (_, .labels(let parts)):
            return gradeOwnWords(subject, parts.joined(separator: " "))
        case (_, .choice(let index)):
            return gradeChoice(subject, index: index)
        }
    }

    // MARK: - Own words

    static func gradeOwnWords(_ subject: GradeSubject, _ answer: String) -> GradeOutcome {
        // A calculation's answer is a number, and its key ideas describe the method a right number never states: when the person's number is
        // the model answer's, it is right (never the other way: a different number goes to the grading below, or to a model).
        if NumericAnswer.agrees(modelAnswer: subject.modelAnswer, typed: answer) {
            return outcome(score: 1, verdict: .correct, confidence: 0.95, marks: [], hit: subject.keyIdeas.map(\.id), missing: [],
                           feedback: "Right.", fix: "")
        }
        let tokens = Lexicon.tokens(answer)
        let content = tokens.filter(\.isContent)
        guard !content.isEmpty else {
            return outcome(score: 0, verdict: .incorrect, confidence: 0.95, marks: [], hit: [], missing: subject.keyIdeas,
                           feedback: "No answer yet.", fix: subject.modelAnswer.isEmpty ? "" : "A full answer: \(subject.modelAnswer)")
        }
        let ideas = subject.keyIdeas
        guard !ideas.isEmpty else { return gradeAgainstModelAnswer(subject, answer, tokens: tokens) }

        let promptStems = Set(Lexicon.contentStems(subject.prompt))
        var marks: [GradeMark] = []
        var hit: [String] = []
        var negatedOnly: [KeyIdea] = []
        var fuzzyIdeas = 0
        var nearMisses = 0

        for idea in ideas {
            var ranges: [Range<Int>] = []
            var negated = false
            var exactSeen = false
            for term in idea.terms {
                let termTokens = Lexicon.tokens(term)
                let termStems = termTokens.filter(\.isContent).map(\.stem)
                // A term that only repeats the question ("mitosis" for "Why does mitosis matter?") proves nothing.
                if !termStems.isEmpty, Set(termStems).isSubset(of: promptStems) { continue }
                // A term that is itself negative ("can't be pulled") needs the answer's negation; any other term
                // must not be negated, before it or inside the matched words ("are not pulled apart").
                let termIsNegative = termTokens.contains(where: \.isNegation)
                let found = Lexicon.find(termTokens, in: tokens)
                for match in found {
                    let first = match.tokenIndices[0], last = match.tokenIndices[match.tokenIndices.count - 1]
                    let inside = first < last && tokens[(first + 1)..<last].contains(where: \.isNegation)
                    let isNegated = inside || Lexicon.isNegated(at: first, in: tokens)
                    if isNegated != termIsNegative { if !termIsNegative { negated = true }; continue }
                    ranges.append(termIsNegative ? negatedRange(match, tokens: tokens) : match.range)
                    if match.kind == .exact { exactSeen = true }
                }
                if found.isEmpty, termStems.count >= 2 {
                    let present = termStems.filter { stem in content.contains { $0.stem == stem } }.count
                    if present * 2 >= termStems.count { nearMisses += 1 }
                }
            }
            if ranges.isEmpty {
                if negated { negatedOnly.append(idea) }
                continue
            }
            hit.append(idea.id)
            if !exactSeen { fuzzyIdeas += 1 }
            marks += merge(ranges, tokens: tokens, in: answer).map { GradeMark(ideaID: idea.id, range: $0) }
        }

        let missing = ideas.filter { !hit.contains($0.id) }
        let score = Double(hit.count) / Double(ideas.count)
        let verdict: GradeResponse.Verdict = hit.count == ideas.count ? .correct : hit.isEmpty ? .incorrect : .partial

        // How sure: high for a short answer matched word for word; lower for typos, long or hedged answers, a
        // negated idea, or an answer full of words the rules don't know (it may be right in other words).
        var confidence = 0.86
        confidence -= 0.06 * Double(min(3, fuzzyIdeas))
        if !negatedOnly.isEmpty { confidence -= 0.1 }
        if content.count > 45 { confidence -= 0.12 }
        if content.count > 90 { confidence -= 0.13 }
        if nearMisses > 0, !missing.isEmpty { confidence -= 0.05 }
        if isHedged(answer) { confidence -= 0.08 }
        let known = Set(Lexicon.contentStems([subject.prompt, subject.modelAnswer, subject.sourceExcerpt ?? "",
                                              ideas.flatMap(\.terms).joined(separator: " "),
                                              ideas.map(\.label).joined(separator: " ")].joined(separator: " ")))
        let unknownShare = Double(content.filter { !known.contains($0.stem) }.count) / Double(content.count)
        if !missing.isEmpty, unknownShare > 0.6, content.count >= 5 { confidence -= 0.15 }
        if hit.isEmpty, content.count >= 6 { confidence = min(confidence, 0.45) }
        confidence = min(0.95, max(0.2, confidence))

        let copy = ownWordsCopy(verdict: verdict, hit: hit, missing: missing, ideas: ideas,
                                modelAnswer: subject.modelAnswer, negatedOnly: negatedOnly)
        return outcome(score: score, verdict: verdict, confidence: confidence, marks: marks, hit: hit, missing: missing,
                       feedback: copy.feedback, fix: copy.fix)
    }

    /// The words for an own-words grade, from which ideas were hit and which are missing. Every grader (these rules,
    /// the on-device model, a merged grade) says it this way: a small model's own feedback was measured naming
    /// ideas by their internal numbers and praising wrong answers, so its prose is never shown.
    static func ownWordsCopy(verdict: GradeResponse.Verdict, hit: [String], missing: [KeyIdea], ideas: [KeyIdea],
                             modelAnswer: String, negatedOnly: [KeyIdea] = []) -> (feedback: String, fix: String) {
        switch verdict {
        case .correct:
            return (ideas.count == 1 ? "That's the key idea." : "Every key idea is there.", "")
        case .partial:
            let named = list(hit.compactMap { id in ideas.first { $0.id == id }?.label }.map(lowerFirst))
            let feedback = "Right so far: \(named)." + (negatedOnly.isEmpty ? "" : " One idea is there but negated, so it doesn't count.")
            return (feedback, fixLine(for: missing, modelAnswer: modelAnswer))
        case .incorrect:
            let feedback = negatedOnly.isEmpty
                ? "None of the key ideas are there yet."
                : "Careful: your answer says the opposite of \(lowerFirst(negatedOnly[0].label))."
            return (feedback, modelAnswer.isEmpty ? fixLine(for: missing, modelAnswer: "") : "A full answer: \(modelAnswer)")
        }
    }

    /// No key ideas (a card the person wrote): how much of the model answer the answer covers.
    private static func gradeAgainstModelAnswer(_ subject: GradeSubject, _ answer: String, tokens: [Lexicon.Token]) -> GradeOutcome {
        let reference = Lexicon.tokens(subject.modelAnswer).filter(\.isContent)
        guard !reference.isEmpty else {
            return outcome(score: 0, verdict: .partial, confidence: 0.3, marks: [], hit: [], missing: [],
                           feedback: "There's no model answer to compare with.", fix: "")
        }
        var covered = Set<String>()
        var ranges: [Range<Int>] = []
        for (i, token) in tokens.enumerated() where token.isContent {
            if let ref = reference.first(where: { Lexicon.match($0, token) != nil }), !Lexicon.isNegated(at: i, in: tokens) {
                covered.insert(ref.stem)
                ranges.append(token.range)
            }
        }
        let share = Double(covered.count) / Double(Set(reference.map(\.stem)).count)
        let verdict: GradeResponse.Verdict = share >= 0.6 ? .correct : share >= 0.3 ? .partial : .incorrect
        let marks = merge(ranges, tokens: tokens, in: answer).map { GradeMark(ideaID: "answer", range: $0) }
        return outcome(score: min(1, share / 0.6), verdict: verdict, confidence: 0.5, marks: marks,
                       hit: verdict == .incorrect ? [] : ["answer"], missing: [],
                       feedback: verdict == .correct ? "That matches the answer." : "Compare it with the answer below.",
                       fix: verdict == .correct ? "" : "A full answer: \(subject.modelAnswer)")
    }

    /// For a negative term, the mark starts at the answer's own negation ("can't be pulled"), so the highlight
    /// shows the words that make it negative.
    private static func negatedRange(_ match: Lexicon.PhraseMatch, tokens: [Lexicon.Token]) -> Range<Int> {
        var start = match.tokenIndices[0]
        var probe = start - 1
        while probe >= 0, start - probe <= 3, !tokens[probe].endsClause {
            if tokens[probe].isNegation { start = probe; break }
            probe -= 1
        }
        return tokens[start].range.lowerBound..<match.range.upperBound
    }

    /// Joins one idea's ranges where only small words sit between them ("grow and repair"), never across a
    /// sentence break.
    private static func merge(_ ranges: [Range<Int>], tokens: [Lexicon.Token], in text: String) -> [Range<Int>] {
        let chars = Array(text)
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var out: [Range<Int>] = []
        for r in sorted {
            guard let last = out.last else { out.append(r); continue }
            if r.lowerBound <= last.upperBound {
                out[out.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
                continue
            }
            let between = tokens.filter { $0.range.lowerBound >= last.upperBound && $0.range.upperBound <= r.lowerBound }
            let gap = chars[last.upperBound..<r.lowerBound]
            let smallWordsOnly = between.allSatisfy { $0.isStopWord } && between.count <= 2
            let sentenceBreak = gap.contains { ".;:!?\n".contains($0) }
            if smallWordsOnly, !sentenceBreak {
                out[out.count - 1] = last.lowerBound..<r.upperBound
            } else {
                out.append(r)
            }
        }
        return out
    }

    /// "Add this: making two genetically identical cells." when the model answer has the missing idea in a
    /// clause of its own; otherwise names what is missing.
    private static func fixLine(for missing: [KeyIdea], modelAnswer: String) -> String {
        guard let first = missing.first else { return "" }
        let clauses = modelAnswer.split(whereSeparator: { ",;".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }
        for clause in clauses {
            let clauseTokens = Lexicon.tokens(clause)
            if first.terms.contains(where: { !Lexicon.find(Lexicon.tokens($0), in: clauseTokens).isEmpty }) {
                var c = clause
                while let l = c.last, ".".contains(l) { c.removeLast() }
                return "Add this: \(lowerFirst(c))."
            }
        }
        return "Still missing: \(list(missing.map { lowerFirst($0.label) }))."
    }

    private static func isHedged(_ answer: String) -> Bool {
        let folded = Lexicon.fold(answer)
        return ["i think", "maybe", "not sure", "i guess", "probably", "i don't know", "idk"].contains { folded.contains($0) }
            || answer.contains("?")
    }

    // MARK: - Exact answers

    enum ExactMatch: Int, Comparable {
        case exact = 0, form, typo, wrong
        static func < (a: ExactMatch, b: ExactMatch) -> Bool { a.rawValue < b.rawValue }
    }

    /// Compares a typed answer with the accepted ones: the same words, the same words in another form
    /// ("chromosome" for "chromosomes"), or one forgiven typo per answer ("telophse").
    static func exactMatch(_ given: String, accepted: [String]) -> ExactMatch {
        let g = Lexicon.tokens(given)
        guard !g.isEmpty else { return .wrong }
        var best = ExactMatch.wrong
        for candidate in accepted {
            let a = Lexicon.tokens(candidate)
            guard !a.isEmpty else { continue }
            if g.map(\.word) == a.map(\.word) { return .exact }
            // Compare the words that matter; "the centromeres" and "centromeres" are the same answer.
            let gc = g.filter(\.isContent), ac = a.filter(\.isContent)
            let left = gc.isEmpty ? g : gc, right = ac.isEmpty ? a : ac
            guard left.count == right.count else { continue }
            var typos = 0
            var ok = true
            for (x, y) in zip(left, right) {
                switch Lexicon.match(x, y) {
                case .exact?: continue
                case .fuzzy?: typos += 1
                case nil: ok = false
                }
                if !ok { break }
            }
            guard ok else { continue }
            best = min(best, typos == 0 ? .form : (typos == 1 ? .typo : .wrong))
        }
        return best
    }

    static func gradeCloze(_ subject: GradeSubject, _ responses: [String]) -> GradeOutcome {
        let expected = subject.cloze?.answers ?? [subject.modelAnswer]
        guard !expected.isEmpty else { return gradeOwnWords(subject, responses.joined(separator: " ")) }
        var results: [Bool] = []
        var typos: [String] = []
        for (i, answer) in expected.enumerated() {
            let given = i < responses.count ? responses[i] : ""
            var accepted = [answer]
            if let alternates = subject.cloze?.alternates, i < alternates.count { accepted += alternates[i] }
            let match = exactMatch(given, accepted: accepted)
            results.append(match != .wrong)
            if match == .typo { typos.append(answer) }
        }
        let right = results.filter { $0 }.count
        let score = Double(right) / Double(expected.count)
        let verdict: GradeResponse.Verdict = right == expected.count ? .correct : right == 0 ? .incorrect : .partial
        let spelling = typos.isEmpty ? nil : "Check the spelling: \(typos.joined(separator: ", "))"
        let answerList = expected.joined(separator: ", ")
        var result = outcome(score: score, verdict: verdict, confidence: typos.isEmpty ? 0.97 : 0.85, marks: [],
                             hit: verdict == .incorrect ? [] : ["blank"], missing: [],
                             feedback: verdict == .correct ? (typos.isEmpty ? "Right." : "Right, with a small typo.") : "Not quite.",
                             fix: verdict == .correct ? "" : "The answer: \(answerList).")
        result.blankResults = results
        result.spellingNote = spelling
        return result
    }

    static func gradeChoice(_ subject: GradeSubject, index: Int) -> GradeOutcome {
        let correct = subject.choices.firstIndex { $0.correct }
        let chosen = subject.choices.indices.contains(index) ? subject.choices[index] : nil
        let isRight = chosen?.correct == true
        let rightText = correct.map { subject.choices[$0].text } ?? subject.modelAnswer
        let feedback = chosen?.why ?? (isRight ? "Right." : "Not quite.")
        return outcome(score: isRight ? 1 : 0, verdict: isRight ? .correct : .incorrect, confidence: 1, marks: [],
                       hit: isRight ? ["choice"] : [], missing: [], feedback: feedback,
                       fix: isRight ? "" : "The answer: \(rightText).")
    }

    static func gradeTypedChoice(_ subject: GradeSubject, _ text: String) -> GradeOutcome {
        let rightText = subject.choices.first { $0.correct }?.text ?? subject.modelAnswer
        let match = exactMatch(text, accepted: [rightText, subject.modelAnswer])
        let isRight = match != .wrong
        var result = outcome(score: isRight ? 1 : 0, verdict: isRight ? .correct : .incorrect,
                             confidence: match == .typo ? 0.85 : 0.97, marks: [], hit: isRight ? ["choice"] : [], missing: [],
                             feedback: isRight ? "Right." : "Not quite.", fix: isRight ? "" : "The answer: \(rightText).")
        if match == .typo { result.spellingNote = "Check the spelling: \(rightText)" }
        return result
    }

    static func gradeLabels(_ subject: GradeSubject, _ labels: [String]) -> GradeOutcome {
        let expected = subject.diagramLabels.isEmpty
            ? subject.modelAnswer.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            : subject.diagramLabels
        var results: [Bool] = []
        var typos: [String] = []
        for (i, label) in expected.enumerated() {
            let given = i < labels.count ? labels[i] : ""
            let match = exactMatch(given, accepted: [label])
            results.append(match != .wrong)
            if match == .typo { typos.append(label) }
        }
        let right = results.filter { $0 }.count
        let total = max(1, expected.count)
        let verdict: GradeResponse.Verdict = right == expected.count ? .correct : right == 0 ? .incorrect : .partial
        var result = outcome(score: Double(right) / Double(total), verdict: verdict, confidence: typos.isEmpty ? 0.97 : 0.85,
                             marks: [], hit: [], missing: [],
                             feedback: verdict == .correct ? "Every label is right." : "\(right) of \(expected.count) labels are right.",
                             fix: verdict == .correct ? "" : "The labels: \(expected.joined(separator: ", ")).")
        result.blankResults = results
        result.spellingNote = typos.isEmpty ? nil : "Check the spelling: \(typos.joined(separator: ", "))"
        return result
    }

    // MARK: - Helpers

    private static func outcome(score: Double, verdict: GradeResponse.Verdict, confidence: Double, marks: [GradeMark],
                                hit: [String], missing: [KeyIdea], feedback: String, fix: String) -> GradeOutcome {
        GradeOutcome(score: score, verdict: verdict, confidence: confidence, marks: marks, hitIdeaIDs: hit,
                     missing: missing.map { MissingIdea(id: $0.id, label: $0.label) }, feedback: feedback, fix: fix,
                     gradedBy: .rules, model: model)
    }

    static func lowerFirst(_ text: String) -> String {
        guard let first = text.split(separator: " ").first else { return text }
        if first.filter(\.isUppercase).count >= 2 { return text }
        return text.prefix(1).lowercased() + text.dropFirst()
    }

    /// "a", "a and b", "a, b and c".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}
