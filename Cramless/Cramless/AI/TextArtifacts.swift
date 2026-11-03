import Foundation

/// A regular expression compiled once (ICU). Swift's `#/…/#` literal builds its matcher again each time the expression runs, which in
/// a debug build costs far more than the match: the checks in this file run on every sentence of a 5,000-word text.
struct Pattern: @unchecked Sendable {
    private let regex: NSRegularExpression

    init(_ pattern: String, ignoreCase: Bool = false) {
        regex = try! NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
    }

    private func range(of text: String) -> NSRange { NSRange(location: 0, length: text.utf16.count) }

    func matches(_ text: String) -> Bool { regex.firstMatch(in: text, options: [], range: range(of: text)) != nil }

    func count(in text: String) -> Int { regex.numberOfMatches(in: text, options: [], range: range(of: text)) }

    /// The text of the first match's capture group `group` (0 is the whole match), or nil.
    func capture(_ group: Int = 0, in text: String) -> String? {
        guard let m = regex.firstMatch(in: text, options: [], range: range(of: text)), group < m.numberOfRanges,
              let r = Range(m.range(at: group), in: text) else { return nil }
        return String(text[r])
    }

    func replacing(in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, options: [], range: range(of: text), withTemplate: template)
    }
}

/// What a web page, a printout or a PDF leaves in text that is not the lesson itself, and the shapes of "terms" that are not
/// terms: pure, language-free tests shared by `QuestionQuality` (what is shown) and `SourceHygiene` / `LocalGenerator` (what is
/// asked about). Each one is a rule that can be said in a sentence, and each is measured against the blind reviewers' ratings of
/// 290 offline and on-device questions (see `QuestionQuality`):
///
/// - markup left in the text ("## Statins", "[12]", a web address, a pronunciation guide);
/// - bibliography: a reference entry, a page reference, a sentence that stops on "p." or "v.";
/// - a figure, a graph or an equation the text lost ("Figure 4", "the graph below", "Equation 3");
/// - code and formulas (a pseudocode line, "CO + 2 H2 ⇌ CH3OH");
/// - a "term" that is a piece of a sentence ("Since it", "The presence of such cycles", "If the only concern").
enum TextArtifacts {

    // MARK: Markup

    private static let markdownMarker = Pattern(#"(?:^#{1,6}|\s#{2,6})\s+\S"#)

    /// "## Statins", "# Title": the markers of a Markdown heading, at the start of the text or fused into the middle of a
    /// sentence when the page's lines were joined.
    static func hasMarkdownMarker(_ text: String) -> Bool { markdownMarker.matches(text) }

    private static let webAddress = Pattern(
        #"https?://|\bwww\.|\bdoi:\s*10\.|\bdoi\.org|\bisbn\b|\bissn\b|\bpmid\b|\barxiv:|\b[a-z0-9\-]+\.(?:com|org|net|edu|gov|io|info)(?:/|\b)"#,
        ignoreCase: true)

    /// A web address, a DOI, an ISBN or the like: never part of a question.
    static func hasWebAddress(_ text: String) -> Bool { webAddress.matches(text) }

    private static let footnoteMarker = Pattern(
        #"\[(?:\d{1,3}|(?i:citation needed|clarification needed|when\?|who\?|note \d{1,3}|nb \d{1,3}))\]"#)
    private static let footnoteMarkerWithSpace = Pattern(
        #"\s*\[(?:\d{1,3}|(?i:citation needed|clarification needed|when\?|who\?|note \d{1,3}|nb \d{1,3}))\]"#)
    private static let pronunciation = Pattern(
        #"\s*\((?:[^()]*[ɐ-˿][^()]*|[^()]*/[^()/]{1,40}/[^()]*|(?i:[^()]*pronounced[^()]*))\)"#)

    /// "[1]", "[23]", "[citation needed]", "[note 3]": a footnote marker a web printout leaves behind.
    static func hasFootnoteMarker(_ text: String) -> Bool { footnoteMarker.matches(text) }

    /// The text without footnote markers ("[1]", "[citation needed]") and without a pronunciation guide in parentheses
    /// ("(/ˈdaɪk.strəz/, DYKE-strəz)", "(pronounced UK: /lə ʃæˈtɛljeɪ/)"). Code is left alone (`dist[2]` is an index).
    static func withoutMarkers(_ text: String) -> String {
        var t = text
        if !looksLikeCode(t) { t = footnoteMarkerWithSpace.replacing(in: t, with: "") }
        return pronunciation.replacing(in: t, with: "")
    }

    // MARK: Bibliography and citations

    /// Abbreviations a sentence cannot end on: the sentence splitter cut a citation or a name in two ("Paul v.", "Cooley on Torts
    /// [3d ed.], p.", "trans."). "etc." and "i.e." are left out: they do end sentences. Written in lower case; a capitalised form
    /// ("Co.", "Dr.") counts too, an all-capital one ("CO.", a chemical) does not.
    private static let citationAbbreviations: Set<String> = [
        "p", "pp", "ed", "eds", "vol", "vols", "no", "nos", "ch", "chap", "sec", "secs", "trans", "ff", "cf", "v", "vs", "co", "inc",
        "ltd", "corp", "al", "ibid", "op", "cit", "esp", "approx", "ca", "fig", "figs", "eq", "eqs", "st", "mr", "mrs", "ms", "dr",
        "prof", "jr", "sr", "gen", "col", "capt", "sgt", "rev", "hon", "messrs", "dept", "univ", "bros", "supra", "infra",
    ]

    /// True when the text stops on an abbreviation that cannot end a sentence.
    static func endsOnAbbreviation(_ text: String) -> Bool {
        var t = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        while let last = t.last, "\"'”’)]".contains(last) { t = t.dropLast() }
        guard t.last == "." else { return false }
        t = t.dropLast()
        let word = t.split(whereSeparator: { $0.isWhitespace || "([,;".contains($0) }).last.map(String.init) ?? ""
        guard !word.isEmpty, word.allSatisfy(\.isLetter) else { return false }
        return citationAbbreviations.contains(word)
            || (word.first?.isUppercase == true && citationAbbreviations.contains(word.lowercased()) && word.dropFirst().allSatisfy(\.isLowercase))
    }

    private static let pageReference = Pattern(#"\bpp?\.\s*\d"#, ignoreCase: true)
    private static let editionInBrackets = Pattern(#"\[\d{1,2}(?:st|nd|rd|th|d)\s+(?i:ed)\.?\]"#)
    private static let edition = Pattern(#"\b(?:\d{1,2}(?:st|nd|rd|th)|(?i:first|second|third|fourth|fifth))\s+(?:[A-Z][a-z]+\s+)?(?i:edition|ed\.)"#)
    private static let referenceWording = Pattern(#"\bRetrieved\s+(?:from|on|\d)|\bArchived\s+from\b|\bet al\.\s*\(|\b[Ii]bid\b|\bop\.\s*cit\b|\bsupra\b"#)
    private static let publisher = Pattern(#"\b[A-Z][A-Za-z\-]+:\s+[A-Z][\w\-& ]{2,40},\s+(?:1[5-9]|20)\d\d\b"#)
    private static let authorWithInitials = Pattern(#"\b[A-Z][a-z]+,\s+(?:[A-Z]\.\s?){1,3}"#)
    private static let yearInParentheses = Pattern(#"\((?:1[5-9]|20)\d\d[a-z]?\)"#)
    private static let volumeOrIssue = Pattern(#"\b(?:vol|no|issue)\.\s*\d"#, ignoreCase: true)
    private static let journalLocator = Pattern(#"\b\d{1,4}\s*\(\d{1,3}\)\s*:\s*\d"#)

    /// A reference entry or a piece of one: a web address, a page reference, an edition, a section sign, a publisher with its
    /// year, a list of authors with their initials, a journal's volume. Body text rarely has any of these; two of the weak ones
    /// together never are body text.
    static func looksLikeReference(_ text: String) -> Bool {
        if hasWebAddress(text) { return true }
        // Strong signs.
        if pageReference.matches(text) || editionInBrackets.matches(text) || edition.matches(text) || referenceWording.matches(text) { return true }
        if text.contains("§") { return true }                                                    // statute and section cites
        if publisher.matches(text) { return true }                                               // "New York: McGraw-Hill, 2011"
        // Weak signs, two of which are a bibliography entry.
        var weak = 0
        let authors = authorWithInitials.count(in: text)
        if authors >= 2 { weak += 2 } else if authors == 1 { weak += 1 }
        if yearInParentheses.matches(text) { weak += 1 }
        if volumeOrIssue.matches(text) { weak += 1 }
        if journalLocator.matches(text) { weak += 1 }
        return weak >= 2
    }

    // MARK: Figures and equations the text lost

    private static let figureMention = Pattern(
        #"\[figure\b|\bfigure\s*\d|\bfig\.\s*\d|\btable\s*\d|\bequations?\s*\(?\d+(?:\.\d+)?\)?(?![a-z\d])|\beqn?s?\.?\s*\(?\d+(?:\.\d+)?\)?(?![a-z\d])|\bformula\s*\(\d|\bdiagram\s*\d"#, ignoreCase: true)
    private static let figurePointer = Pattern(
        #"\b(?:figure|graph|diagram|table|chart|picture|image|illustration|plot|photo|map|sketch)\s+(?:above|below|on the (?:left|right)|at the (?:top|bottom))\b|\b(?:above|following|given|accompanying|attached|preceding|shown|pictured|illustrated|depicted)\s+(?:figure|graph|diagram|table|chart|picture|image|illustration|plot|map|sketch)\b|\b(?:as\s+)?(?:shown|seen|illustrated|depicted|plotted|drawn)\s+(?:in|on)\s+the\s+(?:figure|graph|diagram|table|chart|picture|image|illustration|plot|map)\b"#,
        ignoreCase: true)

    /// A caption or a pointer to a figure, graph, table or equation that is not in the text.
    static func refersToMissingFigure(_ text: String) -> Bool { figureMention.matches(text) || figurePointer.matches(text) }

    private static let listingPointer = Pattern(
        #"\blines?\s+\d+\b|\bsteps?\s+\d+\b|\b(?:pseudocode|the following (?:code|program|listing|algorithm|steps?|example|table|figure|equations?|diagram)|as follows|the code (?:below|above))\b|:\s*$"#,
        ignoreCase: true)
    private static let contextPointer = Pattern(
        #"\b(?:this|these)\s+(?:section|chapter|case|reason|way|approach|result|fact|point)\b|\b(?:the\s+)?(?:former|latter|aforementioned|above-mentioned|previous(?:ly)?|preceding|earlier)\b|\bas\s+(?:mentioned|noted|stated|discussed|described|shown)\b"#,
        ignoreCase: true)

    /// A sentence that leans on something that isn't on the card: a numbered line or step ("after line 10", "skipping to step 6"), a
    /// listing ("the following pseudocode", a colon that introduces nothing), or the text around it ("the former case", "as mentioned
    /// earlier"). Fine in a paragraph, not alone in a fill-in.
    static func leansOnItsSurroundings(_ text: String) -> Bool { listingPointer.matches(text) || contextPointer.matches(text) }

    /// "pressure–volume graph", "network diagram": a heading that names a picture, not a topic.
    static func endsWithFigureNoun(_ text: String) -> Bool {
        let last = Lexicon.fold(text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .split(whereSeparator: \.isWhitespace).last.map(String.init) ?? "")
        return ["graph", "diagram", "figure", "chart", "plot", "table", "illustration", "picture", "image", "drawing", "sketch", "photo", "photograph", "graphs", "diagrams", "figures", "charts", "plots", "tables"].contains(last)
    }

    /// Words that colour or dress a drawing: a "term" made of one of them and a thing in a drawing is a legend ("Red lines",
    /// "Filled nodes", "Blue arrows").
    private static let legendAdjectives: Set<String> = [
        "red", "blue", "green", "yellow", "orange", "purple", "pink", "brown", "black", "white", "gray", "grey", "cyan", "magenta",
        "golden", "silver", "filled", "unfilled", "shaded", "dashed", "dotted", "hollow", "bold", "highlighted", "colored", "coloured",
        "darker", "lighter", "thick", "thin", "dark", "light",
    ]
    private static let legendNouns: Set<String> = [
        "line", "lines", "node", "nodes", "arrow", "arrows", "dot", "dots", "circle", "circles", "box", "boxes", "point", "points",
        "bar", "bars", "curve", "curves", "edge", "edges", "area", "areas", "region", "regions", "square", "squares", "triangle",
        "triangles", "symbol", "symbols", "marker", "markers", "vertex", "vertices", "path", "paths", "segment", "segments", "ones",
    ]

    /// "Red lines", "Filled nodes": the key to a picture that isn't there.
    static func isFigureLegend(_ term: String) -> Bool {
        let words = Lexicon.fold(term).split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard (2...3).contains(words.count), let first = words.first, let last = words.last else { return false }
        return legendAdjectives.contains(first) && legendNouns.contains(last)
    }

    // MARK: Code and formulas

    private static let codeSymbols = Pattern("[←→⇌⇄⇒⇔↔≤≥≠≈∑∫∂√∈∀∃∧∨¬∝⊂⊆∪∩]")
    private static let indexedName = Pattern(#"\b[A-Za-z_]\w*\[[A-Za-z_][\w+\-*,. ]{0,10}\]"#)
    private static let methodCall = Pattern(#"\b[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+\("#)
    private static let snakeCall = Pattern(#"\b[a-z]+_[a-z_]+\("#)

    /// Symbols that are not words: arrows, assignment, comparison, set and logic operators. A line with one is code or a formula, not a
    /// sentence ("17 prev[v] ← u", "CO + 2 H2 ⇌ CH3OH", "alt ← dist[u] + Graph.Distance(u,v)").
    static func hasCodeSymbols(_ text: String) -> Bool {
        if codeSymbols.matches(text) { return true }
        if text.contains(":=") || text.contains("==") || text.contains("!=") || text.contains("<=") || text.contains(">=") || text.contains("=>") || text.contains("->") { return true }
        return text.contains(" = ") || text.contains("//")
    }

    /// Code's syntax: an indexed name with a letter inside ("dist[u]", not a footnote "principle[1]"), a method call, a snake_case call.
    static func hasCodeSyntax(_ text: String) -> Bool {
        indexedName.matches(text) || methodCall.matches(text) || snakeCall.matches(text)
    }

    /// A pseudocode line, an assignment, a chemical or mathematical formula. Language is made of words; these are made of symbols. (A
    /// sentence of a computer science text may mention `dist[v]`: use `hasCodeSymbols` for a sentence, this one for a heading or a term.)
    static func looksLikeCode(_ text: String) -> Bool { hasCodeSymbols(text) || hasCodeSyntax(text) }

    private static let lostSymbols = Pattern(#"\(\s*\)|,\s*,|:\s+(?:which|where|whence|then|hence|thus|is|are|was|were|has|have|can|will)\b|\b(?:denoted|written|given by|defined by|equal to)\s*[,;.)]"#)

    /// A formula the text lost leaves its frame behind: empty brackets, a double comma, "for a reversible process: which means the
    /// integral: is path-independent".
    static func hasLostSymbols(_ text: String) -> Bool { lostSymbols.matches(text) }

    // MARK: Roots and debris

    /// Two words from one root ("remote" / "remoteness", "equal" / "equality", "segregated" / "segregation"): the shorter is, but for
    /// an ending of a couple of letters, the start of the longer. A blank that shares its root with another word of the sentence is
    /// given away by it.
    static func sharesRoot(_ a: String, _ b: String) -> Bool {
        let x = Array(Lexicon.fold(a)), y = Array(Lexicon.fold(b))
        let shorter = min(x.count, y.count)
        guard shorter >= 4 else { return false }
        var common = 0
        while common < shorter, x[common] == y[common] { common += 1 }
        return common >= max(4, shorter - 2)
    }

    private static let scareQuotes = Pattern(#"(?<![A-Za-z0-9])['‘][A-Za-z][A-Za-z\- ]{1,24}['’](?![A-Za-z0-9])"#)
    private static let strayPunctuation = Pattern(#"\s[,;]\s|\(\s*[,;.]|[\[(]\s*$|\[\.|\.\[|\s\.\s|,\s*\.(?!\.)"#)
    private static let doubledFunctionWords = Pattern(
        #"\b(?:with|of|by|for|from|to|in|on|at|as)\s+(?:and|or)\s+(?:with|of|by|for|from|to|in|on|at|as|the|a)\b|\b(?:the|a|an)\s+(?:the|a|an)\b"#, ignoreCase: true)

    /// What a lost formula leaves in the words around it: words in single quotes standing in for symbols ("a change the 'response'",
    /// "the 'driving change'"), a comma or a bracket with nothing in it, two small words that never come together ("with and").
    static func hasDebris(_ text: String) -> Bool {
        scareQuotes.count(in: text) >= 2 || strayPunctuation.matches(text) || doubledFunctionWords.matches(text)
    }

    private static let fusedSentences = Pattern(#"[a-z]{3,}\s+(?:The|This|These|Those|It|They|We|He|She|There|Here|In|On|If|When|As|For|A|An)\s+[a-z]"#)

    /// Two sentences run together with no full stop between them ("… the 'index' response of interest The two ways of statement
    /// differ"): a line the text lost its punctuation on.
    static func hasFusedSentences(_ text: String) -> Bool { fusedSentences.matches(text) }

    private static let initials = Pattern(#"^(?:[A-Za-z]\.\s+){1,3}[A-Za-z]"#)

    /// "T. K. Abbott": a name written with initials is a person, not a topic. "U.S." has no space after its first dot.
    static func startsWithInitials(_ text: String) -> Bool { initials.matches(text) }

    // MARK: Terms

    /// Words that stand for something said before: a "term" with one of them points back at a sentence the card doesn't show.
    private static let anaphora: Set<String> = [
        "it", "its", "they", "them", "their", "theirs", "he", "him", "his", "she", "her", "hers", "this", "that", "these", "those",
        "such", "here", "there", "we", "us", "our", "you", "your",
    ]

    /// Words a term cannot start with: they begin a clause or a sentence ("If the only concern", "Since it", "Today it").
    private static let clauseStarters: Set<String> = [
        "if", "since", "because", "although", "though", "unless", "until", "while", "whereas", "when", "whenever", "where", "once",
        "so", "but", "and", "or", "nor", "yet", "then", "thus", "hence", "therefore", "however", "moreover", "furthermore", "also",
        "only", "even", "just", "still", "rather", "instead", "today", "now", "otherwise", "meanwhile", "finally", "first", "next",
        "later", "earlier", "often", "sometimes", "usually", "generally", "typically", "normally", "perhaps", "maybe", "indeed",
    ]

    /// Adverbs that only join sentences: a term never starts with one ("Now sequence S", "Then instead of").
    private static let discourseAdverbs: Set<String> = [
        "now", "then", "thus", "hence", "therefore", "however", "moreover", "furthermore", "also", "otherwise", "meanwhile", "finally",
        "today", "later", "earlier", "often", "sometimes", "usually", "generally", "typically", "normally", "perhaps", "maybe", "indeed",
        "instead", "consequently", "nevertheless", "nonetheless", "additionally", "similarly", "likewise",
    ]

    /// What follows a clause starter in a clause ("If the", "Since it"), unlike a title ("If statements", "Only child").
    private static let clauseFollowers: Set<String> = ["the", "a", "an", "it", "he", "she", "they", "we", "you", "i", "this", "that", "these", "those", "there", "some", "all", "no", "not", "to"]

    /// Prepositions that open a phrase of place or time, not a title ("Behind the cloud of words", "After the war"). The short ones ("in",
    /// "on", "for", "to", "of") open real titles ("On the Origin of Species") and are left out.
    private static let prepositionStarters: Set<String> = [
        "behind", "after", "before", "during", "under", "over", "between", "among", "within", "without", "upon", "onto", "into",
        "through", "against", "across", "beyond", "inside", "outside", "toward", "towards", "until", "around", "despite", "near",
    ]
    private static let determiners: Set<String> = ["the", "a", "an", "this", "that", "these", "those", "its", "their", "his", "her", "our", "your", "my", "such", "each", "every", "some", "any", "all", "no"]

    /// Words a term cannot end on.
    private static let danglingEnds: Set<String> = [
        "described", "shown", "given", "used", "called", "known", "mentioned", "discussed", "listed", "involved", "considered",
        "proposed", "stated", "noted", "defined", "said", "above", "below", "here", "there", "too", "also", "etc", "namely",
    ]

    /// Words with nothing in them: a "term" made only of these ("Key feature", "Main idea") is a label of the author's, not a
    /// thing in the subject.
    private static let emptyTermWords: Set<String> = [
        "key", "main", "major", "primary", "important", "central", "basic", "common", "typical", "general", "simple", "first",
        "second", "third", "last", "next", "final", "other", "another", "same", "different", "new", "old", "good", "best", "better",
        "idea", "feature", "point", "thing", "aspect", "factor", "reason", "result", "part", "way", "case", "example", "problem",
        "issue", "question", "answer", "step", "type", "kind", "form", "characteristic",
        "advantage", "benefit", "goal", "aim", "purpose", "use", "role", "fact", "note", "section",
        "chapter", "page", "item", "items", "one", "ones", "some", "many", "most", "more", "less", "few", "several", "various",
    ]

    /// Verbs that make a few words a clause.
    private static let clauseVerbs: Set<String> = [
        "is", "are", "was", "were", "has", "have", "had", "do", "does", "did", "can", "could", "will", "would",
        "should", "may", "might", "must", "means", "requires", "makes", "gives", "takes",
    ]

    /// Why a "term" isn't one, or nil. A term from a card's front or a blank of several words: not a pronoun-bearing piece of a
    /// sentence, not the start or the end of a clause, not a label ("Key feature"), not a legend ("Red lines").
    static func termProblem(_ term: String, maxWords: Int = 7) -> String? {
        let clean = term.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let words = clean.split(whereSeparator: { $0.isWhitespace }).map { Lexicon.fold(String($0)).trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard let first = words.first, let last = words.last else { return "no term" }
        if words.count > maxWords { return "a clause, not a term" }
        if isFigureLegend(clean) { return "the key to a picture" }
        if words.count >= 2 {
            if let pronoun = words.first(where: { anaphora.contains($0) }) { return "points back at something (\(pronoun))" }
            if discourseAdverbs.contains(first) { return "starts with a linking word" }
            if first == "to", words.count >= 3, !determiners.contains(words[1]) { return "an infinitive clause, not a term" }
            if clauseStarters.contains(first), words.count >= 4 || clauseFollowers.contains(words[1]) { return "starts a clause" }
            if prepositionStarters.contains(first), words.count >= 3, determiners.contains(words[1]) { return "starts a phrase" }
            if danglingEnds.contains(last) || (Lexicon.stopWords.contains(last) && !["one", "ones"].contains(last)) { return "stops on a function word" }
            if words.count >= 3, words.contains(where: { clauseVerbs.contains($0) }) { return "a clause, not a term" }
        } else if anaphora.contains(first) || clauseStarters.contains(first) {
            return "not a term"
        }
        let content = words.filter { !Lexicon.stopWords.contains($0) }
        if words.count >= 2, !content.isEmpty, content.allSatisfy({ emptyTermWords.contains($0) }) { return "a label, not a term" }
        return nil
    }

    /// Adjectives and quantifiers that say nothing alone: "The most common." is not a definition.
    private static let vagueWords: Set<String> = [
        "most", "more", "less", "least", "common", "many", "much", "such", "other", "same", "various", "several", "certain", "some",
        "any", "best", "better", "good", "great", "large", "small", "big", "high", "low", "new", "old", "only", "main", "major", "key",
        "very", "own", "first", "last", "next", "usual", "typical", "particular", "specific", "general",
    ]

    /// The meaning side of a definition has something in it: at least two content words that say something ("Hatred of reason." has two;
    /// "The most common." has none).
    static func hasSubstance(_ meaning: String) -> Bool {
        Lexicon.tokens(meaning).filter { $0.isContent && !$0.isNumber && $0.word.count >= 3 && !vagueWords.contains($0.word) }.count >= 2
    }

    // MARK: Prompts

    private static let chooseWithoutOptions = Pattern(
        #"\bwhich\s+(?:one\s+)?of\s+(?:the\s+)?(?:following|these|those|below|above)\b|\bchoose\s+the\s+(?:correct|right|best)\b|\ball\s+of\s+the\s+above\b|\bnone\s+of\s+the\s+above\b"#,
        ignoreCase: true)
    private static let label = Pattern(#"^(?:flash\s?card|question|term|front|card|prompt|answer|definition|q)\s*\d*\s*:\s*(\S.*)$|^(?:question|q)\s*\d+\s*[.)]\s*(\S.*)$"#, ignoreCase: true)
    private static let authorQuestion = Pattern(
        #"^\s*(?:what|how)\s+(?:does|did|do|is|was|are|were)\s+(?:the\s+)?(?:author|writer|text|passage|article|speaker|narrator)(?:'s|’s)?\s+(?:think|thought|say|said|opinion|view|views|position|stance|attitude|argue|believe|claim|suggest|feel|main|key|central)|^\s*what\s+(?:is|was|are)\s+(?:the\s+)?(?:key|main|central|major)\s+(?:idea|point|message|theme|argument)s?\s+(?:of|in)\s+(?:the\s+)?(?:text|passage|article|reading|chapter|excerpt|page)\b"#,
        ignoreCase: true)

    /// "Which of the following is true…" with no options to choose from: a question the person can't answer.
    static func asksToChooseWithoutOptions(_ prompt: String) -> Bool { chooseWithoutOptions.matches(prompt) }

    /// A label the model put in front of its own question ("Flashcard: What is …", "Term: Efficiency").
    static func modelLabel(in prompt: String) -> String? { label.capture(1, in: prompt) ?? label.capture(2, in: prompt) }

    /// What the model asks about the author's own mind ("What does the author think of reason?", "What is the key idea of the text?"):
    /// a short question with no claim in it, which a small model answers from a hypothetical or a quoted view as if it were the author's.
    static func asksAboutTheAuthor(_ prompt: String) -> Bool {
        guard prompt.split(whereSeparator: { $0.isWhitespace }).count <= 10 else { return false }
        return authorQuestion.matches(prompt)
    }
}
