import Foundation

/// The filter every on-device and offline question passes before it is shown, so a set doesn't carry the junk that
/// headings, citations and a small model's slips turn into questions. Measured on the 14-day user test: 37% of this
/// iPhone's questions had a zero somewhere in the blind ratings, among them a card whose front is the word "Term",
/// "Describe j.) in your own words.", "What happens during the" (cut off) and a blank whose answer is "Next".
///
/// It drops, silently (the person never saw them, so the review's "Left out" list doesn't mention them):
/// - a prompt that is too short to be a question (under four words; a plain question word with a "?" may have three);
/// - a prompt with an unmatched bracket or parenthesis;
/// - "Describe <heading> in your own words." when the heading isn't a thing to describe (a list marker, a time stamp, a
///   sentence's wrapped half, a generic label such as "Description"); a short real term stays: "DNA", "ATP", "for loops";
/// - a card whose front is a bare generic word ("Term", "Definition");
/// - a fill-in whose blank isn't a content word ("Next", "The", a number alone);
/// - a prompt that stops mid-sentence ("What happens during the");
/// - an answer that is only a citation tail or starts mid-sentence;
/// - a repeat of an earlier question (compared normalised);
/// - what a printout leaves in the text (a Markdown "##", a web address, a footnote number, a reference entry, a sentence cut at
///   "p." or "v."), and a question about a figure, graph or equation the text lost (`TextArtifacts`);
/// - a "term" that is a piece of a sentence ("Since it", "The presence of such cycles"), a label ("Key feature"), the key to a
///   picture ("Red lines"), a pseudocode line or a formula;
/// - a fill-in whose blank is given away by the rest of the sentence, a possessive, an adverb or a generic word, or whose sentence is
///   mostly a formula, starts with a page number, carries on from the sentence before or leaves too little around the blank;
/// - "Which of the following…" with nothing to choose from, a multiple-choice question with fewer than three options, a question about
///   "what the author thinks", and a label the model wrote in front of its own question ("Flashcard: …").
///
/// Measured against the blind ratings of 290 offline and on-device questions (nine texts), the rules above, applied to what the app
/// produced, remove 83% of the offline questions and 79% of the on-device ones that had a zero somewhere, and keep 92% and 100% of
/// those rated good. `filter` also drops a question that asks the fact an earlier one asked, in another format or in other words
/// (`isNearDuplicate`); the generator and the on-device merge use the same test.
///
/// Cloud AI's questions don't pass through here: the relay writes and checks those.
enum QuestionQuality {

    /// Why the question isn't worth showing, or nil. (For tests and the user-test harness; nothing shows the reason.)
    static func problem(with item: GeneratedItem) -> String? {
        let prompt = item.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return "no question" }

        // Brackets: a cloze's own blanks are written {{like this}}, so they don't count.
        let bracketed = item.kind == .cloze ? (item.cloze?.text ?? prompt).replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: "") : prompt
        if !bracketsMatch(bracketed) { return "unmatched bracket" }

        let words = prompt.split(whereSeparator: \.isWhitespace)
        let isQuestion: Bool = item.kind == .recall || item.kind == .apply || item.kind == .mcq
        if isQuestion {
            let plainQuestion = prompt.hasSuffix("?") && questionWords.contains(Lexicon.fold(String(words.first ?? "")).trimmingCharacters(in: .punctuationCharacters))
            if words.count < (plainQuestion ? 3 : 4) { return "too short" }
            if endsMidSentence(prompt) { return "ends mid-sentence" }
        }
        if item.kind == .recall || item.kind == .apply, let heading = describedHeading(in: prompt), isWeakHeading(heading) {
            return "describes a heading that isn't a topic"
        }
        if isGenericFront(prompt) { return "generic front" }

        if item.kind == .cloze {
            let answers = item.cloze?.answers ?? [item.answer]
            if answers.isEmpty || answers.contains(where: { !isContentBlank($0) }) { return "blank isn't a content word" }
        } else if item.kind != .diagram {
            let answer = item.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = answer.first, ",;.:)]".contains(first) { return "answer starts mid-sentence" }
            if looksLikeCitation(answer) || looksLikeCitation(prompt) { return "citation tail" }
        }
        return textProblem(with: item, prompt: prompt)
    }

    // MARK: What a printout leaves, what a picture takes

    /// The checks that read what the person reads: the question, the answer and a fill-in's sentence.
    private static func textProblem(with item: GeneratedItem, prompt: String) -> String? {
        let isCloze = item.kind == .cloze
        let answer = item.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = isCloze ? sentence(of: item) : ""
        let shown = isCloze ? [prompt, body] : [prompt, answer]

        for text in shown {
            if TextArtifacts.hasMarkdownMarker(text) { return "markup left in the text" }
            if TextArtifacts.hasWebAddress(text) { return "web address in the text" }
            if TextArtifacts.hasFootnoteMarker(text) { return "footnote marker in the text" }
            if TextArtifacts.looksLikeReference(text) { return "reference entry" }
            if TextArtifacts.endsOnAbbreviation(text) { return "cut off at an abbreviation" }
            if TextArtifacts.hasDebris(text) { return "what a lost formula leaves" }
        }
        // A question about a picture or an equation the text doesn't have.
        if TextArtifacts.refersToMissingFigure(prompt) || (isCloze && TextArtifacts.refersToMissingFigure(body)) {
            return "needs a figure the text doesn't have"
        }
        if item.kind != .mcq, TextArtifacts.asksToChooseWithoutOptions(prompt) { return "asks to choose from options it doesn't show" }
        if item.kind == .mcq, !hasUsableOptions(item) { return "choices that don't make a question" }

        switch item.kind {
        case .flashcard, .recall, .apply:
            if TextArtifacts.modelLabel(in: prompt) != nil { return "a label in front of the question" }
            if TextArtifacts.asksAboutTheAuthor(prompt) { return "asks what the author thinks" }
            if item.kind != .recall || describedHeading(in: prompt) == nil, isCircular(prompt: prompt, answer: answer) { return "the answer is in the question" }
            if item.kind == .recall, let heading = describedHeading(in: prompt), !answerTalksAbout(heading, answer: answer) {
                return "the answer doesn't talk about the heading"
            }
            if item.kind == .flashcard, !quotesMatch(answer) { return "unmatched quotation mark" }
            if item.kind == .flashcard, !prompt.hasSuffix("?") {
                if let why = frontProblem(prompt) { return why }
                if !TextArtifacts.hasSubstance(answer) { return "nothing to learn in the answer" }
            }
        case .cloze:
            return clozeProblem(item, body: body)
        default:
            break
        }
        return nil
    }

    /// A prose answer (25 words or more) to "Describe <heading>" says something with the heading's own words in it: at least half of the
    /// heading's content stems are in it (a list under a heading — "Symptoms": fever, cough — is not prose and needs none).
    static func answerTalksAbout(_ heading: String, answer: String) -> Bool {
        guard answer.split(whereSeparator: { $0.isWhitespace }).count >= 25 else { return true }
        let withoutBrackets = heading.replacing(headingAside, with: " ")
        let stems = Set(Lexicon.contentStems(withoutBrackets))
        guard !stems.isEmpty else { return true }
        // A heading that names a summary ("Syllabus", "Overview") is answered by the summary, which doesn't repeat the name.
        if stems.allSatisfy({ summaryWords.contains($0) }) { return true }
        let answerStems = Set(Lexicon.contentStems(answer))
        let shared = stems.filter { stem in answerStems.contains(stem) || answerStems.contains { $0.hasPrefix(stem) || stem.hasPrefix($0) && $0.count >= 5 } }.count
        return Double(shared) / Double(stems.count) >= 0.5
    }

    private static let summaryWords: Set<String> = Set(["syllabus", "summary", "overview", "abstract", "synopsis", "introduction", "conclusion", "recap", "review"].map(Lexicon.stem))

    /// "(Warren, C.J.)", "(the Reporter's summary)": a heading's aside.
    private static let headingAside = #/\([^)]*\)/#

    /// A card's front that isn't a question is a term: not a line of code, not a picture's legend, not a piece of a sentence.
    private static func frontProblem(_ front: String) -> String? {
        if TextArtifacts.looksLikeCode(front) { return "a line of code or a formula" }
        if TextArtifacts.endsWithFigureNoun(front) { return "names a picture" }
        if let why = TextArtifacts.termProblem(front, maxWords: 12) { return "front is \(why)" }
        return nil
    }

    /// A fill-in's own checks: a sentence that stands alone, and a blank worth recalling that the rest doesn't give away.
    private static func clozeProblem(_ item: GeneratedItem, body: String) -> String? {
        if !quotesMatch(body) { return "unmatched quotation mark" }
        if isQuotedTitle(body) { return "a quoted title" }
        if startsWithStructure(body) { return "starts with a page number or a list marker" }
        if startsWithConjunction(body) { return "carries on from the sentence before" }
        if TextArtifacts.hasCodeSymbols(body) || isMostlyFormula(body) { return "a line of code or a formula" }
        let blanks = item.cloze?.answers ?? [item.answer]
        let visible = visibleText(of: item)
        let visibleStems = Set(Lexicon.contentStems(visible))
        let visibleWords = Lexicon.tokens(visible).filter(\.isContent).map(\.word)
        for blank in blanks {
            let text = blank.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = text.split(whereSeparator: \.isWhitespace)
            if words.count >= 2, let why = TextArtifacts.termProblem(text) { return "blank is \(why)" }
            if words.count == 1 {
                let word = String(words[0])
                if isPossessive(word) { return "blank is only a possessive" }
                if isAdverb(word) { return "blank is an adverb" }
                // (A defined term is a fine blank whatever it is: "Fill in the key term.")
                if !item.prompt.localizedCaseInsensitiveContains("key"), LocalGenerator.genericStems.contains(Lexicon.stem(Lexicon.fold(word))) {
                    return "blank is too generic"
                }
            }
            // Nothing to go on: "{{OSPF and IS-IS}} are the most common."
            if !TextArtifacts.hasSubstance(visible) { return "too little around the blank" }
            // The rest of the sentence gives the blank away when it uses a word from the same root ("too remote" / "remoteness").
            if let longest = Lexicon.tokens(text).filter(\.isContent).max(by: { $0.word.count < $1.word.count }),
               visibleWords.contains(where: { TextArtifacts.sharesRoot($0, longest.word) }) { return "the sentence gives the blank away" }
            // The rest of the sentence gives the blank away when it uses the same word.
            let stems = Set(Lexicon.contentStems(text))
            if !stems.isEmpty, Double(stems.intersection(visibleStems).count) / Double(stems.count) >= 0.5 { return "the sentence gives the blank away" }
        }
        return nil
    }

    /// The whole sentence is one quoted string: the title of a cited work.
    static func isQuotedTitle(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.first, "\"\u{201C}".contains(first) else { return false }
        let stripped = t.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:\"\u{201D}\u{2019}) "))
        return !stripped.contains("\"") && !stripped.contains("\u{201C}") && t.dropFirst().contains(where: { "\"\u{201D}".contains($0) })
    }

    /// "492-493. (c) Where a State …", "12. …": the start of a syllabus or a list, joined into the sentence.
    static func startsWithStructure(_ text: String) -> Bool {
        listStart.matches(text)
    }

    /// "But not merely …", "Rather, a …": a sentence that carries on from the one before it.
    static func startsWithConjunction(_ text: String) -> Bool {
        conjunctionStart.matches(text)
    }

    /// A fill-in's sentence as the person reads it, the blank included: "During {{telophase}}, …" → "During telophase, …".
    static func sentence(of item: GeneratedItem) -> String {
        (item.cloze?.text ?? item.prompt).replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: "")
    }

    /// A fill-in's sentence with its blanks taken out: what the person sees.
    static func visibleText(of item: GeneratedItem) -> String {
        guard let text = item.cloze?.text else { return item.prompt }
        return blankSpan.replacing(in: text, with: " ")
    }

    private static let blankSpan = Pattern(#"\{\{.*?\}\}"#)
    private static let listStart = Pattern(#"^\s*(?:\d{1,4}\s*[-–]\s*\d{1,4}\b\.?|\(?[A-Za-z]{1,2}\)|\d{1,3}[.)])\s"#)
    private static let conjunctionStart = Pattern(#"^\s*(?:and|but|or|nor|yet|so|rather|instead)\b"#, ignoreCase: true)
    private static let subscriptName = Pattern(#"\b[A-Za-zΘ]_\w{1,3}\b"#)
    private static let siteTitle = Pattern(#"\s[-–—|]\s*(?:wikipedia|britannica|wikibooks|wikisource|youtube|quizlet|chegg|studocu)\b"#, ignoreCase: true)

    /// Straight double quotes pair up, and so do English curly ones: a sentence cut inside a quotation has one over. (A German or French
    /// quotation uses other marks and is left alone.)
    static func quotesMatch(_ text: String) -> Bool {
        let straight = text.filter { $0 == "\"" }.count
        guard straight % 2 == 0 else { return false }
        if text.contains("\u{201E}") || text.contains("\u{00AB}") { return true }
        return text.filter { $0 == "\u{201C}" }.count == text.filter { $0 == "\u{201D}" }.count
    }

    /// Most of the sentence is a formula whose symbols the text may have lost: "Θ(|E| ⋅ T_dk + |V| ⋅ T_em)". A formula in passing ("ran in
    /// Θ(|V|^2) time", "O(|E| + |V|C)") is fine, and so is a name like extract_min.
    static func isMostlyFormula(_ text: String) -> Bool {
        let marks: Set<Character> = ["⋅", "·", "×", "÷", "±", "∑", "∏", "∞", "Θ", "^", "|", "+", "=", "<", ">"]
        var formula = 0, words = 0
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            let isFormula = word.contains(where: { marks.contains($0) }) || subscriptName.matches(String(word))
            if isFormula { formula += word.count; words += 1 }
        }
        return words >= 5 && Double(formula) / Double(max(1, text.count)) >= 0.1
    }

    /// "plaintiff's", "Dijkstra's": the owner of something, not an idea, and a blank the learner can't spell the same way twice.
    static func isPossessive(_ word: String) -> Bool {
        word.hasSuffix("'s") || word.hasSuffix("\u{2019}s") || word.hasSuffix("s'") || word.hasSuffix("s\u{2019}")
    }

    private static let lyNouns: Set<String> = ["assembly", "anomaly", "monopoly", "butterfly", "multiply", "dragonfly", "family", "supply", "homily", "melancholy"]

    /// "negligently", "substantially": how, not what.
    static func isAdverb(_ word: String) -> Bool {
        let w = Lexicon.fold(word)
        return w.count >= 8 && w.hasSuffix("ly") && !lyNouns.contains(w)
    }

    /// The answer is already in the question: every content word of it is one of the prompt's, or the prompt's word with a negating prefix
    /// ("What is an indirect inclination?" / "An inclination that is not direct."). A heading to describe is not a question, so
    /// "Describe X" is left alone.
    static func isCircular(prompt: String, answer: String) -> Bool {
        let answerStems = Set(Lexicon.contentStems(answer))
        guard !answerStems.isEmpty, answerStems.count <= 8 else { return false }
        let promptStems = Set(Lexicon.contentStems(prompt))
        func covered(_ stem: String) -> Bool {
            promptStems.contains(stem) || ["in", "un", "non", "im", "ir", "il", "dis"].contains { promptStems.contains($0 + stem) }
        }
        return answerStems.allSatisfy(covered)
    }

    /// A multiple-choice question needs a stem, one right option and at least two wrong ones that aren't the right one.
    static func hasUsableOptions(_ item: GeneratedItem) -> Bool {
        let texts = item.choices.map { Lexicon.normalizedAnswer($0.text) }
        return item.choices.count >= 3 && item.choices.filter(\.correct).count == 1 && Set(texts).count == texts.count
    }

    /// The questions worth showing, in order, the first of each repeat kept: the same question again, and one that asks the same fact in
    /// other words or in another format (a card and a fill-in of one definition).
    static func filter(_ items: [GeneratedItem]) -> [GeneratedItem] {
        var seen = Set<String>()
        var out: [GeneratedItem] = []
        for item in items where problem(with: item) == nil {
            guard seen.insert(duplicateKey(item)).inserted, !out.contains(where: { isNearDuplicate($0, item) }) else { continue }
            out.append(item)
        }
        return out
    }

    /// The content words of what a question asks and answers: a fill-in's sentence, a card's front and back, an own-words question's
    /// prompt and answer.
    static func factStems(of item: GeneratedItem) -> Set<String> {
        item.kind == .cloze ? Set(Lexicon.contentStems(sentence(of: item))) : Set(Lexicon.contentStems(item.prompt + " " + item.answer))
    }

    /// Two questions that ask the same fact: a card and a fill-in of one definition, a sentence blanked twice, an own-words question asked
    /// in other words. Compared by the share of the smaller one's content words the other has (80% for cards and fill-ins, 70% for
    /// own-words questions); a card whose words (five or more) are 85% inside an own-words question and its answer is that answer asked
    /// again. A choice question and a card are left alone, and a short one (under three content words) is never a duplicate by overlap.
    static func isNearDuplicate(_ a: GeneratedItem, _ b: GeneratedItem) -> Bool {
        isNearDuplicate(kind: a.kind, stems: factStems(of: a), kind: b.kind, stems: factStems(of: b))
    }

    /// The same, for questions whose `factStems` are already known.
    static func isNearDuplicate(kind a: ItemKind, stems x: Set<String>, kind b: ItemKind, stems y: Set<String>) -> Bool {
        func family(_ kind: ItemKind) -> Int {
            switch kind {
            case .flashcard, .cloze: return 0
            case .recall, .apply: return 1
            case .mcq: return 2
            case .diagram: return 3
            }
        }
        if (family(a) == 0 && family(b) == 1) || (family(a) == 1 && family(b) == 0) {
            // A card made from sentences that an own-words answer already holds is that answer again. (A fill-in of one of them asks for
            // a word of it, not for the answer, and stays.)
            let (cardKind, small, big) = family(a) == 0 ? (a, x, y) : (b, y, x)
            return cardKind == .flashcard && small.count >= 5 && Double(small.intersection(big).count) / Double(small.count) >= 0.85
        }
        guard family(a) == family(b), family(a) != 3 else { return false }
        let smaller = min(x.count, y.count)
        guard smaller >= 3 else { return false }
        return Double(x.intersection(y).count) / Double(smaller) >= (family(a) == 1 ? 0.7 : 0.8)
    }

    /// What makes two questions the same question once case, accents and punctuation are set aside.
    static func duplicateKey(_ item: GeneratedItem) -> String {
        if item.kind == .cloze, let text = item.cloze?.text {
            return "cloze|" + Lexicon.normalizedAnswer(text.replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: ""))
        }
        return Lexicon.normalizedAnswer(item.prompt)
    }

    // MARK: Pieces

    private static let questionWords: Set<String> = ["what", "who", "whom", "whose", "where", "when", "why", "how", "which"]

    /// Words a question can't end on: it stopped before it said anything ("What happens during the"). Only words that never
    /// end a question: a sentence can end on a stranded preposition ("What is it made of?", "Which phase is the cell in?",
    /// "What does ATP stand for?"), a demonstrative ("What is this?") or a main verb ("What do they do?"), so those are
    /// not here.
    private static let dangling: Set<String> = [
        "the", "a", "an", "its", "their", "our", "your", "my", "and", "or", "but", "nor", "because", "if", "although", "while",
        "than", "whose", "which", "will", "would", "can", "could", "should", "may", "might", "must", "during", "between",
        "among", "into", "onto", "through", "against", "across", "within", "without", "upon",
    ]

    /// A front that names nothing: the header of a "Term / Definition" table read as a card.
    private static let genericFronts: Set<String> = [
        "term", "terms", "definition", "definitions", "word", "words", "concept", "concepts", "key term", "key terms",
        "vocabulary", "meaning", "meanings", "answer", "question", "item", "items", "topic", "topics", "name", "names",
        "heading", "title", "example", "examples", "note", "notes", "front", "back",
    ]

    /// Section labels nobody studies: "Describe description in your own words."
    private static let genericHeadings: Set<String> = [
        "description", "overview", "introduction", "intro", "summary", "abstract", "contents", "notes", "references",
        "bibliography", "appendix", "preface", "conclusion", "conclusions", "review", "questions", "exercises", "index",
        "glossary", "term", "terms", "definition", "definitions", "example", "examples", "figure", "table", "page", "chapter",
        "section", "see also", "further reading", "external links",
    ]

    /// Words that start a sentence, not a title: the wrapped second half of one ("nor do I comment on …"). A preposition or a
    /// conjunction like "for", "if", "in", "on", "to", "as", "by" does start real titles ("For loops", "If statements", "In vitro
    /// fertilization"), so those are not here.
    private static let sentenceStarters: Set<String> = [
        "nor", "and", "or", "but", "so", "yet", "that", "which", "who", "whom", "whose", "because", "although", "though", "while",
        "whereas", "than", "he", "she", "they", "we", "it", "i", "is", "are", "was", "were", "this", "these", "those",
    ]

    private static let documentPartHeads: Set<String> = [
        "opinion", "opinions", "dissent", "dissenting", "concurring", "concurrence", "headnote", "headnotes", "preface", "foreword",
        "prologue", "epilogue", "appendix", "appendices", "acknowledgements", "acknowledgments", "colophon",
    ]
    private static let documentParts: Set<String> = documentPartHeads.union([
        "court", "supreme", "majority", "minority", "reporter", "reporter's", "statement", "case", "judge", "justice", "chief", "per",
        "curiam", "part", "section", "authors", "author", "editor", "editors", "note", "notes",
    ])

    /// Words that point at something else: a heading that opens with one ("Other statements", "The following") isn't a topic by itself.
    private static let headingOpeners: Set<String> = ["other", "another", "such", "same", "following", "above", "below", "next", "previous", "various", "several"]

    /// A verb or pronoun of its own makes a long "heading" a clause, not a topic ("glycolysis is the metabolic pathway that …",
    /// "for present purposes it sufficiently describes …").
    private static let clauseWords: Set<String> = [
        "is", "are", "was", "were", "can", "do", "does", "did", "has", "have", "will", "would", "could", "should", "it", "he", "she",
        "they", "we", "i", "you",
    ]

    /// Blanks that give nothing to recall ("Next", "Following") on top of the stop words and numbers.
    private static let weakBlanks: Set<String> = [
        "next", "previous", "following", "above", "below", "first", "second", "third", "last", "then", "other", "another",
        "same", "many", "most", "more", "less", "either", "neither", "yes", "no", "now", "only", "even", "thing", "things",
        "one", "two", "three", "new", "old", "etc",
        // A blank is a thing, not a connective or a filler.
        "supposing", "assuming", "provided", "considering", "regarding", "concerning", "including", "excluding", "according",
        "depending", "whereas", "whereby", "thereby", "therefore", "hence", "thus", "whether", "otherwise", "moreover", "however",
        "term", "terms", "word", "words", "phrase", "sentence", "statement", "question", "answer", "such", "being", "having",
        "everyone", "everybody", "everything", "someone", "somebody", "something", "anyone", "anybody", "anything", "nobody", "nothing",
        "themselves", "himself", "herself", "itself", "oneself", "whatever", "whoever", "whichever", "wherever", "whenever",
    ]

    static func bracketsMatch(_ text: String) -> Bool {
        var stack: [Character] = []
        let opener: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        for c in text {
            switch c {
            case "(", "[", "{": stack.append(c)
            case ")", "]", "}":
                guard stack.last == opener[c] else { return false }
                stack.removeLast()
            default: break
            }
        }
        return stack.isEmpty
    }

    /// The last word is one a sentence can't stop on.
    static func endsMidSentence(_ prompt: String) -> Bool {
        let stripped = prompt.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard let last = stripped.split(whereSeparator: \.isWhitespace).last else { return true }
        return dangling.contains(Lexicon.fold(String(last)))
    }

    /// "Describe X in your own words." → X.
    static func describedHeading(in prompt: String) -> String? {
        guard let match = prompt.firstMatch(of: #/^(?i:describe)\s+(?<x>.+?)\s+(?i:in your own words)\.?$/#) else { return nil }
        return String(match.x)
    }

    /// A heading that isn't a topic to describe: a list marker or time stamp ("j.)", "60.)", "0:32"), the wrapped half of a
    /// sentence ("nor do I comment on the word …"), a clause with its own verb, a footnote tail, or a generic label. A short real
    /// term stays: "DNA", "ATP", "GDP", "pH", "for loops", "if statements", "in vitro fertilization".
    ///
    /// The prompt only has the heading with its first letter lowercased (`LocalGenerator` does that for everything but an
    /// acronym), so nothing here relies on its case; `LocalGenerator` also asks with the heading as printed and, when the heading
    /// is a sentence's first half, the line that follows it. `next` is that line: one that carries on in lower case means the
    /// "heading" is the start of a sentence.
    static func isWeakHeading(_ heading: String, next: String? = nil) -> Bool {
        let text = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = text.filter(\.isLetter).count
        let digits = text.filter(\.isNumber).count
        if letters < 2 || digits >= letters { return true }
        if isListMarker(text) || !bracketsMatch(text) { return true }
        if text.range(of: #"\.\(\d+\)|\(\d+\)$"#, options: .regularExpression) != nil { return true }
        // Code, a formula, a name written with initials, a picture, a web page's title bar: not topics.
        if TextArtifacts.looksLikeCode(text) || TextArtifacts.startsWithInitials(text) || TextArtifacts.endsWithFigureNoun(text) { return true }
        if siteTitle.matches(text) { return true }
        let tokens = Lexicon.tokens(text)
        guard let first = tokens.first else { return true }
        if genericHeadings.contains(tokens.map(\.word).joined(separator: " ")) { return true }
        // Only small words ("for the", "of the", "in") name nothing; an acronym in capitals is a word of its own ("IT").
        let characters = Array(text)
        let hasContent = tokens.contains { token in
            if token.isContent { return true }
            guard token.range.upperBound <= characters.count else { return false }
            let original = characters[token.range]
            return original.filter(\.isLetter).count >= 2 && original.allSatisfy { $0.isUppercase || $0.isNumber }
        }
        if !hasContent { return true }
        if tokens.count >= 2, headingOpeners.contains(first.word) { return true }
        if let next, next.trimmingCharacters(in: .whitespacesAndNewlines).first?.isLowercase == true { return true }
        if tokens.count >= 4, sentenceStarters.contains(first.word) { return true }
        // "Opinion of the Court (Warren, C.J.)", "Dissenting opinion", "Foreword": a part of the document, not a thing it teaches.
        let asideless = text.replacing(headingAside, with: " ")
        let named = Lexicon.tokens(asideless).filter(\.isContent).map(\.word)
        if !named.isEmpty, named.allSatisfy({ documentParts.contains($0) }), named.contains(where: { documentPartHeads.contains($0) }) { return true }
        // "As a macroscopic construct": a role the subject plays, with no subject.
        if tokens.count >= 4, first.word == "as", ["a", "an", "the"].contains(tokens[1].word) { return true }
        if tokens.count >= 5, tokens.contains(where: { clauseWords.contains($0.word) }) { return true }
        return false
    }

    /// "j.)", "(b)", "iv.", "12.", "60.)", or a Roman numeral alone: how a list or an outline numbers its lines.
    static func isListMarker(_ text: String) -> Bool {
        if text.range(of: #"^[\(\[]?[A-Za-z0-9]{1,3}[\.\)\]:]+$"#, options: .regularExpression) != nil { return true }
        return text.range(of: #"^(?=[ivxIVX]+$)X{0,3}(IX|IV|V?I{0,3})$|^(?=[ivx]+$)x{0,3}(ix|iv|v?i{0,3})$"#, options: .regularExpression) != nil
    }

    static func isGenericFront(_ prompt: String) -> Bool {
        genericFronts.contains(Lexicon.normalizedAnswer(prompt))
    }

    /// A blank that is a content word: a word that isn't a stop word, a negation, a filler, or a number alone (a year or
    /// another number of three digits or more is a fact worth recalling).
    static func isContentBlank(_ answer: String) -> Bool {
        let tokens = Lexicon.tokens(answer)
        guard !tokens.isEmpty else { return false }
        if tokens.allSatisfy(\.isNumber) { return tokens.contains { $0.word.count >= 3 } }
        return tokens.contains { $0.isContent && !$0.isNumber && !weakBlanks.contains($0.word) }
    }

    /// A law-report citation: a volume, the reporter's abbreviation, a first page ("260 N.Y. 99", "9 Ex. 341", "56 L. Ed. 2d 200",
    /// "9 Exch 341"). The abbreviation has a full stop in it or is one of the few reporters written without; a date is not one
    /// ("1 September 1939", "2 Sept. 1945").
    private static let reporterCitation =
        #/\b\d{1,4}\s+(?!(?:Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\.)(?:(?:[A-Z][A-Za-z]{0,6}\.\s?){1,3}(?:\d[a-z]{1,2}\.?\s?)?|(?:Exch|ER|WLR|QB|KB|AC|Cranch|UKHL|EWCA|EWHC)\s)\d{1,4}\b/#

    /// "248 N.Y. 339; 162 N.E. 99": two or more reporter citations, or text that is mostly numbers.
    static func looksLikeCitation(_ text: String) -> Bool {
        if text.matches(of: reporterCitation).count >= 2 { return true }
        let tokens = Lexicon.tokens(text)
        guard tokens.count >= 6 else { return false }
        return Double(tokens.filter(\.isNumber).count) / Double(tokens.count) >= 0.6
    }
}
