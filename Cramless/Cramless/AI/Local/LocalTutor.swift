import Foundation

/// What Cap will and won't do, for every tier: no essay writing and no "humanizing" text to hide AI, no doing an exam, a
/// quiz or homework for the student, for anyone. Also what Cap leaves to the notes' own words: small talk and
/// everyday questions get a short line instead of a search, and a line in the student's notes that is written to an
/// assistant is recognised so that it is never taken as an order.
///
/// A decline is a decision made without asking any model, so it is made only for a clear request: the student asks Cap to DO
/// the graded work for them ("do my homework", "write my lab report", "take this exam for me", "give me the answers to the
/// exam"). A question about how to prepare, how to write, or any study question that merely has these words in it
/// ("How do I ace the midterm?", "How do I write a good thesis statement?", "I'm trying to do my homework: what is
/// anaphase?") goes through. The cloud's prompt declines what slips past, in a sentence of its own.
enum TutorPolicy {

    // MARK: Requests Cap declines

    /// What a student says before the request itself ("ok so can you please …"). A request is read at the start of a clause, after
    /// this: "I'm trying to do my homework" and "how do I write my essay" are not requests to do it.
    private static let frame = #"(?:(?:ok|okay|so|hey|hi|hello|yo|cap|please|pls|plz|just|now|then|and|also|well|um|uh|oh|alright|anyway|can you|could you|would you|will you|can u|could u|would u|can ya|you can|you could|you should|you need to|you have to|you must|i need you to|i want you to|i'd like you to|i would like you to|i need u to|i want u to|go ahead and|do you mind|would you mind|why don't you|why dont you|how about you|maybe you can|maybe you could)\s+)*"#

    /// Up to three words between "write my" and the noun ("write my whole lab report"), none of them a word that starts another thing
    /// ("write me a quiz on the report").
    private static let modifiers = #"(?:(?!(?:on|about|for|of|from|to|with|in|at|by|and|or|that|which|because|quiz|quizzes|questions?|outline|summary|notes?|cards?|flashcards?|plan|list|guide|checklist|template|examples?|prompts?|rubric|tips|ideas|topics?)\b)[a-z0-9'-]+\s+){0,3}"#

    /// What Cap would be writing.
    private static let written = #"(?:essay|paper|report|assignment|coursework|homework|hw|thesis|dissertation|reflection|irac|case brief)s?\b"#

    /// What Cap would be doing.
    private static let graded = #"(?:exams?|tests?|quizz?(?:es)?|midterms?|finals|final exams?|final tests?|assessments?|take.?homes?|homework|hw|assignments?|coursework|problem sets?|worksheets?)\b"#

    /// Words after it that make it getting ready for the work, or doing it together, not having it done ("my exam prep").
    private static let notDoneForThem = #"(?!\s+(?:with (?:me|us)|together|review|prep|preparation|revision|practice|study|studying|notes|topics?|material|materials|guide|schedule|plan|dates?|format|content|tips|strateg(?:y|ies)|anxiety|results?|grades?|syllabus|outline|sessions?|room|day|time|location|policy|rules))"#

    private static let writing = [
        // "write me an essay", "write us a 500 word report"
        #"(?:write|draft|compose|generate|produce|type up|put together)\s+(?:me|us)\s+(?:(?:an?|the|my|our|this|that|some|up)\s+)?\#(modifiers)\#(written)"#,
        // "write my lab report"
        #"(?:write|draft|compose|generate|produce|type up)\s+(?:my|our)\s+\#(modifiers)\#(written)"#,
        // "write the report for me", "write an essay that I can submit"
        #"(?:write|draft|compose|generate|produce|type up)\s+(?:an?|the|this|that|these|those)\s+\#(modifiers)\#(written).{0,80}\b(?:for (?:me|us)|(?:i|we) can (?:submit|turn|hand))\b"#,
        // "write me a full IRAC answer … that I can submit"
        #"(?:write|draft|compose|generate|produce|give me|make me)\b.{0,100}\b(?:i|we) can (?:submit|turn (?:it |this |that |them )?in|hand (?:it |this |that |them )?in)\b"#,
        // The same request in the languages the app is used in: "Schreib mir bitte meinen Aufsatz", "escríbeme mi ensayo",
        // "écris-moi ma dissertation", "scrivimi il mio saggio". Folded, so without accents.
        #"(?:schreib|schreibe|verfass|verfasse|formulier|formuliere|erstell|erstelle)\s+(?:(?:mir|uns|bitte|doch|mal|schnell)\s+)*(?:mein(?:en|e|em)?|ein(?:en|e|em)?|den|die|das|unseren|unsere)\s+(?:[a-z0-9-]+\s+){0,3}(?:aufsatz|essay|hausarbeit|referat|facharbeit|bericht|erorterung|abhandlung|seminararbeit)s?\b"#,
        #"(?:escribe|escribeme|redacta|redactame|hazme|escribenos)\s+(?:(?:me|nos|por favor)\s+)*(?:mi|mis|un|una|el|la)\s+(?:[a-z0-9-]+\s+){0,3}(?:ensayo|redaccion|trabajo|informe|monografia|composicion)s?\b"#,
        #"(?:ecris|ecrivez|redige|redigez)(?:-moi)?\s+(?:(?:moi|s'il te plait|s'il vous plait)\s+)*(?:mon|ma|mes|un|une|le|la)\s+(?:[a-z0-9-]+\s+){0,3}(?:dissertation|redaction|essai|devoir|rapport|memoire|expose)s?\b"#,
        #"(?:scrivi|scrivimi|redigi|redigimi)\s+(?:(?:mi|per favore)\s+)*(?:il mio|la mia|i miei|le mie|un|una|il|la)\s+(?:[a-z0-9-]+\s+){0,3}(?:saggio|tema|tesina|relazione|elaborato|compito)\b"#,
    ]

    private static let doing = [
        // "do my homework", "answer my take-home", "take my online quiz", "finish my problem set", "do my essay"
        #"(?:do|finish|complete|solve|answer|take|sit)\s+(?:all of\s+)?(?:my|our)\s+(?:[a-z0-9'-]+\s+){0,2}?(?:\#(graded)|\#(written))\#(notDoneForThem)"#,
        // "do the assignment for me", "take this exam for me", "solve the quiz for me"
        #"(?:do|finish|complete|solve|answer|take|sit)\s+(?:all of\s+)?(?:the|this|that|these|those)\s+(?:[a-z0-9'-]+\s+){0,2}?\#(graded).{0,40}\bfor (?:me|us)\b"#,
        // "solve the take-home midterm": a take-home is graded work whoever's it is
        #"(?:do|finish|complete|solve|answer|take)\s+(?:the|this|that|my|our)\s+(?:[a-z0-9'-]+\s+){0,2}?take.?home\b"#,
        // "give me the answers to the exam", "can you just send us the answer key for the quiz"
        #"(?:give|send|tell|show|get|have|text|dm)\s+(?:me|us)\s+(?:all\s+)?(?:the\s+)?(?:answers?|solutions?|answer keys?)\s+(?:to|for|of|on)\s+(?:(?:the|my|this|that|our|these|today's)\s+)?(?:[a-z0-9'-]+\s+){0,2}?\#(graded)\#(notDoneForThem)"#,
        // "what are the answers to the exam", "I need the answers to the quiz"
        #"(?:what (?:are|is)|where (?:are|is|can i (?:find|get))|i need|do you have)\s+(?:the\s+)?(?:answers?|solutions?|answer keys?)\s+(?:to|for|of|on)\s+(?:(?:the|my|this|that|our)\s+)?(?:[a-z0-9'-]+\s+){0,2}?\#(graded)\#(notDoneForThem)"#,
    ]

    /// Requests for the answers to numbered items, or for a solution to hand in, that are about graded work only when the message says
    /// so elsewhere ("my friend sent me a photo of tomorrow's exam. just give me the answers to questions 3 to 7"; "this is problem 3 from
    /// my take-home quiz, give me the full pseudocode solution so I can paste it in"). Used with `gradedWork`.
    private static let numberedSolutions = [
        #"(?:give|send|tell|show|get|have|text|dm)\s+(?:me|us)\s+(?:just\s+)?(?:all\s+)?(?:the\s+)?(?:(?:full|complete|whole|final|worked|correct)\s+)?(?:[a-z-]+\s+){0,2}?(?:answers?|solutions?)\s+(?:to|for|of|on)\s+(?:the\s+)?(?:questions?|problems?|exercises?|tasks?|items?)\s+#?\d"#,
        #"(?:give|send|tell|show|get|write)\s+(?:me|us)\s+(?:just\s+)?(?:the\s+|a\s+)?(?:(?:full|complete|whole|final|worked|correct)\s+)?(?:[a-z-]+\s+){0,2}?(?:answers?|solutions?|code|pseudocode|proof|derivation|program|script)\b.{0,60}\b(?:so|and|then)\s+(?:that\s+)?(?:i|we)\s+can\s+(?:just\s+)?(?:paste|copy|submit|turn|hand|send|upload)\b"#,
    ]

    /// A mention of graded work anywhere in the message.
    private static let gradedWork = #"\b(?:exams?|quizz?(?:es)?|tests?|midterms?|finals?|take.?homes?|homework|hw|assignments?|worksheets?|problem sets?)\b"#

    /// Asking for help to cheat, in the first person ("help me cheat on my test"). A question about cheating isn't one.
    private static let cheating = [
        #"\b(?:help|let|teach|show) (?:me|us) (?:how to |to )?cheat\b"#,
        #"\bhow (?:do|can|could|would|should) (?:i|we) cheat\b"#,
        #"\b(?:i|we) (?:want|need|plan|wanna|am going|'m going|are going) (?:to )?cheat\b"#,
        #"\bcheat (?:on|in|for) (?:my|our) \b"#,
    ]

    /// The clauses of a message, folded to lower case: a request starts one ("hey cap, do my homework: problems 1 to 10").
    private static func clauses(_ question: String) -> [String] {
        Lexicon.fold(question)
            .components(separatedBy: CharacterSet(charactersIn: ".!?;:,\n\r\u{2014}\u{2013}"))
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
    }

    private static func asks(_ question: String, _ requests: [String]) -> Bool {
        clauses(question).contains { clause in
            requests.contains { clause.range(of: "^" + frame + $0, options: .regularExpression) != nil }
        }
    }

    /// A request to write an essay or a report for the student, or to rewrite text so it passes as theirs.
    static func isRefused(_ question: String) -> Bool {
        if asks(question, writing) { return true }
        let q = Lexicon.fold(question)
        let evading = [
            #"\bhumani[sz]e\b"#, #"\bhumani[sz]er\b"#,
            #"\b(sound|seem|look) (more )?(human|like i wrote|like me)\b"#,
            #"\b(bypass|beat|avoid|get past|fool) (the |an |ai |gpt )*(detector|detection|turnitin|gptzero)\b"#,
            #"\bundetectable\b"#,
        ]
        return evading.contains { q.range(of: $0, options: .regularExpression) != nil }
    }

    /// A request to do an exam, a quiz or homework for the student, or to hand over the answers to one that is graded.
    /// Practice papers and past papers are for studying, so they are not this; nor is help with one's own work ("help me
    /// finish my assignment"), getting ready for an exam ("the test review"), or a question about doing well in one.
    static func isCheating(_ question: String) -> Bool {
        let q = Lexicon.fold(question)
        if q.range(of: #"\b(practice|sample|mock|revision|past paper|old paper)\b"#, options: .regularExpression) != nil { return false }
        if asks(question, doing) { return true }
        if q.range(of: gradedWork, options: .regularExpression) != nil, asks(question, numberedSolutions) { return true }
        return cheating.contains { q.range(of: $0, options: .regularExpression) != nil }
    }

    static let refusal = "I can't write essays or rewrite text to pass as your own. I can help you plan one from your notes, or quiz you on them."
    static let cheatRefusal = "I can't do an exam, a quiz or homework for you, but I can quiz you on your notes so you're ready for it."

    /// Cap's words for a request it declines; nil when Cap helps.
    static func decline(for question: String) -> String? {
        if isRefused(question) { return refusal }
        if isCheating(question) { return cheatRefusal }
        return nil
    }

    /// One of the lines above, as it was saved in a chat.
    static func isDecline(_ text: String) -> Bool { text == refusal || text == cheatRefusal }

    // MARK: Everyday questions

    /// A question about something other than studying: sport, who runs a country, a joke, Cap himself. Only a hint, from the
    /// words: `LocalTutor.reply` also needs the notes to share (nearly) nothing with it before it answers with a redirect.
    static func isOffTopic(_ question: String) -> Bool {
        let q = Lexicon.fold(question)
        let cues = [
            #"\b(world cup|super bowl|nba|nfl|nhl|mlb|premier league|champions league|olympics|wimbledon|final score)\b"#,
            #"\b(who is|who's|who was) the (current |new |first |last )?(president|prime minister|king|queen|chancellor|pope|mayor|governor)\b"#,
            #"\bcapital (city )?of\b"#,
            #"\bmeaning of life\b"#,
            #"\b(tell me a joke|knock knock|sing me|sing a song)\b"#,
            #"\b(weather|forecast|recipe|pizza|burger|restaurant|horoscope|zodiac|lottery|bitcoin|crypto|stock price)\b"#,
            #"\b(movie|movies|netflix|tiktok|instagram|snapchat|youtube|spotify|playlist|fortnite|minecraft|roblox|video game|xbox|playstation)\b"#,
            #"\b(girlfriend|boyfriend|my crush|dating|my ex)\b"#,
            #"\b(who are you|what are you|what is your name|what's your name|how old are you)\b"#,
            #"\bare you (a |an )?(real|human|person|robot|bot|ai)\b"#,
        ]
        return cues.contains { q.range(of: $0, options: .regularExpression) != nil }
    }

    // MARK: Lines written to an assistant

    /// Lines that talk to an AI or a system: an order to set the rules aside, a note for "AI assistants", a new role, a fixed reply.
    private static let addressedToAnAI = [
        #"\b(?:ignore|disregard|forget|override)\b[^.!?\n]{0,30}\b(?:all|any|every|your|previous|prior|above|earlier|preceding|these|those)\b[^.!?\n]{0,30}\b(?:instructions?|prompts?|rules|directions|guidelines|messages|context)\b"#,
        #"\b(?:forget|ignore|disregard) (?:everything|all of that)\b[^.!?\n]{0,20}\b(?:above|before|previous|earlier|so far)\b"#,
        #"\b(?:note|message|instructions?|attention|hey|dear|hello)s? (?:for|to)\b[^.!?\n]{0,12}\b(?:ai|a\.i\.|assistants?|chatbots?|language models?|llms?|bots?)\b"#,
        #"\b(?:if|as|since) you(?:'re| are) (?:an? |the )?(?:ai|a\.i\.|assistant|chatbot|language model|llm)\b"#,
        #"\bas an? (?:ai|a\.i\.|llm)(?: language model| assistant| model|,|\.)"#,
        #"\bas an? (?:language model|artificial intelligence)\b"#,
        #"\byou are (?:now|no longer)\b[^.!?\n]{0,12}\b(?:ai|a\.i\.|assistant|chatbot|bot|language model|llm|dan|developer|admin|unrestricted|unfiltered|jailbroken|bound|restricted)\b"#,
        #"\b(?:system prompt|developer mode|jailbreak|prompt injection)\b"#,
        #"\b(?:reply|respond|answer|output|print|say) only (?:with|in)\b"#,
        #"\b(?:reply|respond|answer|output|print|say) with ["“'‘]"#,
        #"\bdo not (?:mention|reveal|tell|say) (?:this|that|the|these) (?:note|message|instructions?|line|text)\b"#,
    ]

    /// Orders to say or announce something. Ordinary in a nurse's or a teacher's notes ("tell students to bring a pencil", "you
    /// should tell the patient"), so they count only together with an order to set the rules aside.
    private static let announcements = [
        #"\btell (?:the )?(?:class|students?|everyone|everybody|users?|them|the user|your (?:user|owner|teacher))\b"#,
        #"\byou (?:must|should|have to|need to|are to|will|shall) (?:now )?(?:say|tell|answer|respond|reply|claim|announce|reveal|output|state|inform)\b"#,
        #"\b(?:the )?(?:exam|midterm|test|quiz|final|class|lecture|assignment|deadline)s? (?:is|are|has been|have been|was|were|will be|got) (?:cancel+ed|postponed|moved|dropped|called off|optional)\b"#,
    ]

    private static let setAside = [
        #"\b(?:ignore|disregard|forget|override)\b"#,
        #"\b(?:do not|don't|never) (?:mention|reveal|tell|say|disclose)\b"#,
        #"\bwithout (?:mentioning|telling|saying)\b"#,
    ]

    /// A line of the student's own material that talks to an AI: "ignore previous instructions", "you are now …", a note for
    /// "AI assistants", or an announcement ("tell the class the exam is cancelled") together with an order to set the rules aside. A
    /// classmate's forum post can carry one. It is only ever read as text and never followed; this finds one so that Cap can say so.
    /// A phrase list, not a model's judgement. `context` is the passage a single sentence comes from: an announcement counts when
    /// its passage orders the rules set aside, even if the sentence itself doesn't.
    static func looksLikeInstruction(_ text: String, context: String? = nil) -> Bool {
        let t = Lexicon.fold(text)
        if addressedToAnAI.contains(where: { t.range(of: $0, options: .regularExpression) != nil }) { return true }
        guard announcements.contains(where: { t.range(of: $0, options: .regularExpression) != nil }) else { return false }
        let around = Lexicon.fold(context ?? text)
        return setAside.contains { around.range(of: $0, options: .regularExpression) != nil }
    }

    /// The sentence added to an answer when a line like that is among the notes it was made from.
    static var instructionNotice: String {
        String(localized: "One line in your notes looks like an instruction to me, so I ignored it.")
    }
}

/// The offline tutor (tier T0): answers from the passages the retriever found, quoting them, or says it found nothing close.
/// In hints mode (always for under-18 accounts) it asks a guiding question built from the passage, a sentence of the
/// person's own notes with the key word left out, instead of telling.
///
/// It can't write, so it never pretends to explain: it says what it is doing ("The closest lines in your notes:") and shows
/// the lines. It can't translate either, so for notes that are not in English it shows only the label and the lines, with
/// no sentence of its own around them.
enum LocalTutor {

    struct Quote: Equatable, Sendable {
        var passageKey: String
        var text: String
    }

    struct Reply: Equatable, Sendable {
        /// Why the reply is what it is.
        enum Kind: Equatable, Sendable {
            /// Lines of the notes that answer, or a hint to find them.
            case answer
            /// The keywords found nothing close. A model may still know better.
            case notCovered
            /// An essay, a report, an exam or homework: Cap declined.
            case refused
            case smallTalk
            /// Not about studying, and nothing in the notes about it.
            case offTopic
            /// Nothing has been added yet.
            case noMaterial
        }

        var text: String
        var quotes: [Quote]
        /// False when the notes don't cover the question (or Cap declined it).
        var grounded: Bool
        var kind: Kind

        init(text: String, quotes: [Quote], grounded: Bool, kind: Kind? = nil) {
            self.text = text
            self.quotes = quotes
            self.grounded = grounded
            self.kind = kind ?? (grounded ? .answer : .notCovered)
        }

        /// A cloud model is worth asking: the question is about the notes, and only the keywords are unsure. A decline,
        /// small talk, a redirect and an empty library are answered without one.
        var asksAModel: Bool { kind == .answer || kind == .notCovered }
    }

    /// What the offline rules say when their keywords place nothing. They match words, not meaning ("expecting" is not "pregnant"), so
    /// "your notes don't cover that" would often be false: it says what happened here and who can look again.
    static let notCovered = "I couldn't find that in your notes on this iPhone. Cloud AI reads everything you've added, so it can look again when it's on."
    static let smallTalk = "Ask me anything about your notes and I'll answer from them."
    static let noMaterial = "You haven't added any notes yet. Add a page or a lecture and I'll answer from it."
    /// A problem from a photo that Cloud AI read the notes for and could not place, or placed with no quote that is really in them.
    static var snapNotCovered: String {
        String(localized: "I couldn't find this topic in your notes, so I won't guess. Add the chapter it's from and snap it again.")
    }
    /// A later turn of that chat whose reply came with no quote that is really in the notes.
    static var snapUnverified: String {
        String(localized: "I can't point to that in your notes, so I won't guess. Tell me which step you're on.")
    }

    /// Cap's words when the notes don't answer: the offline tutor's, or the cloud's in either wording of the relay ("Your
    /// material doesn't cover …" before, "I couldn't find that in what you've added." now). Case and the shape of the
    /// apostrophe don't matter, and neither does what comes first: the relay may name what it looked through before it says so
    /// ("I looked through Cardiac cycle (6 pages). I couldn't find that in what you've added."), and a sentence about a line of the
    /// notes may come before that. So it is looked for in the opening of the reply, the first `openingLength` characters, and not
    /// in a count of sentences: a source's name can end a sentence for the tokenizer ("Marbury v. Madison (6 pages). I couldn't
    /// find that …" splits after "v. "), and a notice plus "I looked through" is already three. The Ask screen mutes such a reply
    /// and offers to add notes.
    static func isNotCoveredReply(_ text: String) -> Bool {
        if text == notCovered || text == noMaterial || text == snapNotCovered { return true }
        let patterns = [
            #"\byour (?:material|notes) (?:doesn't|does not|doesnt|don't|do not|dont) cover\b"#,
            #"\bi (?:couldn't|could not|couldnt|can't|cannot|cant|did not|didn't|didnt) find (?:that|it|this|anything|an answer)\b"#,
        ]
        let opening = Lexicon.fold(String(text.prefix(openingLength)))
        return patterns.contains { opening.range(of: $0, options: .regularExpression) != nil }
    }

    /// How much of a reply's start is read for the not-found sentence: a notice, the sources it looked through (a long name or two)
    /// and the sentence fit in it; the explanation of an answer that goes on past it does not.
    private static let openingLength = 320

    /// The least share of the question's words the best passage must contain to count as covering it.
    static let minimumCoverage = 0.34

    /// A question with this much of its words in the best passage is about the notes, whatever else it mentions.
    private static let strongCoverage = 0.75

    /// - Parameters:
    ///   - terms: the question's words as the retriever matched them (typos mapped to the material's words), with how telling
    ///     each is (`LocalRetriever.weightedTerms`); the question's own words when nil.
    ///   - hasMaterial: the student has added something Cap can read. Without it nothing can be searched.
    ///   - topic: what to point the student back to when the question is not about their notes: the course, or a source's name.
    ///   - limitReached: today's free answers are used up. Say so, and show the closest lines instead of "not covered".
    ///   - ranking: the sentences that answer the question and whether the best is convincing (`LocalRetriever.rankSentences`). Without
    ///     it the sentences of the first three `hits` are ranked by the words they share with the question, as this always did.
    static func reply(question: String, mode: TutorMode, hits: [LocalRetriever.Hit], context: TutorContext?,
                      terms: [String: Double]? = nil, hasMaterial: Bool = true, topic: String? = nil,
                      limitReached: Bool = false, ranking: OfflineRanking? = nil, fromPhoto: Bool = false) -> Reply {
        // The words of a photo are a problem, whatever they look like: a header like "Homework 3" is no request to do it, and a formula has no
        // words for the small-talk and off-topic checks to read.
        if !fromPhoto {
            if let decline = TutorPolicy.decline(for: question) { return Reply(text: decline, quotes: [], grounded: false, kind: .refused) }
            if context == nil, isSmallTalk(question) { return Reply(text: smallTalk, quotes: [], grounded: false, kind: .smallTalk) }
        }
        let asked = context.map { "\($0.itemPrompt) \($0.expected)" } ?? question
        let weights = terms ?? Dictionary(Lexicon.contentStems(asked).map { ($0, 1.0) }, uniquingKeysWith: { a, _ in a })
        let questionStems = Set(weights.keys)
        if questionStems.isEmpty, context == nil, !fromPhoto { return Reply(text: smallTalk, quotes: [], grounded: false, kind: .smallTalk) }
        if !hasMaterial { return Reply(text: noMaterial, quotes: [], grounded: false, kind: .noMaterial) }
        if context == nil, !fromPhoto, TutorPolicy.isOffTopic(question) {
            let about = hits.first.map { $0.coverage >= strongCoverage || $0.matched.count >= 3 } ?? false
            if !about { return Reply(text: redirect(topic: topic), quotes: [], grounded: false, kind: .offTopic) }
        }
        let ranked = ranking ?? rankFromHits(hits, weights: weights, questionStems: questionStems)
        guard ranked.isConvincing, let first = ranked.candidates.first else { return nothingClose(limitReached: limitReached) }
        let passage = first.passage
        let label = passage.label
        let english = isEnglish([question, passage.text])

        switch mode {
        case .explain:
            var lines = first.lines
            var shown = lines.map(\.text).joined(separator: " ")
            // Two places in the notes that the search cannot tell apart are both shown, each under its own label.
            var also: Quote?
            var alsoLabel = ""
            if let other = ranked.alsoClose, !lines.contains(where: { $0.text == other.sentence }) {
                also = Quote(passageKey: other.passage.key, text: other.sentence)
                alsoLabel = other.passage.label
            }
            if let also {
                lines.append(also)
                shown = alsoLabel == label ? "\(shown)\n\n\(also.text)" : "\(label): \(shown)\n\n\(alsoLabel): \(also.text)"
            }
            guard english else { return Reply(text: also == nil || alsoLabel == label ? "\(label): \(shown)" : shown, quotes: lines, grounded: true) }
            let lead: String
            if limitReached {
                lead = String(localized: "You've used today's free answers. These are the closest lines in your notes:")
            } else if let context {
                lead = "You wrote “\(context.given)”, but the answer is “\(context.expected)”. Your notes say:"
            } else {
                lead = "The closest lines in your notes:"
            }
            var text = "\(lead)\n\n\(shown)"
            // A check question belongs to practice, not to every answer.
            if !limitReached, context == nil, isPracticeRequest(question) {
                text += " Quick check: can you say it back in your own words?"
            }
            return Reply(text: text, quotes: lines, grounded: true)

        case .hints:
            // A hint is built on a sentence with something to leave out: of the best three, the first with six words or more.
            let first = ranked.candidates.prefix(3).first { Lexicon.wordCount($0.sentence) >= 6 } ?? first
            let passage = first.passage
            let label = passage.label
            // The second sentence: the line right after the first when it carries on ("This is the division of …"), otherwise the best
            // other sentence of the same passage that adds a word of the question.
            var second: (sentence: String, key: String)?
            if let at = first.lines.firstIndex(where: { $0.text == first.sentence }), at + 1 < first.lines.count {
                let next = first.lines[at + 1]
                let firstWord = Lexicon.fold(String(next.text.split(separator: " ").first ?? ""))
                let carriesOn = ["this", "it", "they", "these", "that", "each", "then"].contains(firstWord)
                    || !Set(Lexicon.contentStems(next.text)).isDisjoint(with: Set(Lexicon.contentStems(first.sentence)).subtracting(questionStems))
                if carriesOn, !next.text.hasSuffix("?"), !TutorPolicy.looksLikeInstruction(next.text, context: passage.text) {
                    second = (next.text, next.passageKey)
                }
            }
            if second == nil, let other = ranked.candidates.dropFirst().first(where: { c in
                c.passage.key == passage.key && c.sentence != first.sentence
                    && !Set(Lexicon.contentStems(c.sentence)).intersection(questionStems).isSubset(of: Set(Lexicon.contentStems(first.sentence)))
            }) {
                second = (other.sentence, other.passage.key)
            }
            // The person's own sentence with its key word left out: they find the word on their page.
            var options: [(shown: String, quote: Quote)] = []
            if let second, second.key == passage.key, let gapped = gap(second.sentence, avoiding: questionStems) {
                options.append(("\(first.sentence) \(gapped)", Quote(passageKey: passage.key, text: "\(first.sentence) \(second.sentence)")))
            }
            if let gapped = gap(first.sentence, avoiding: questionStems) {
                options.append((gapped, Quote(passageKey: passage.key, text: first.sentence)))
            }
            if let pick = options.first {
                guard english else { return Reply(text: "\(label): “\(pick.shown)”", quotes: [pick.quote], grounded: true) }
                let opener: String
                if limitReached {
                    opener = String(localized: "You've used today's free answers. Here's a hint from your notes instead. ")
                } else {
                    opener = context.map { "You wrote “\($0.given)”. Have another look: " } ?? "Let's work it out from your notes. "
                }
                return Reply(text: "\(opener)\(label) says: “\(pick.shown)” What goes in the gap?", quotes: [pick.quote], grounded: true)
            }
            let quote = Quote(passageKey: passage.key, text: first.sentence)
            guard english else { return Reply(text: label, quotes: [quote], grounded: true) }
            // No word of the sentence can be left out (every long word is the question's own): point at the lines. At the free
            // limit the reply still says why it is a hint and not an answer.
            let lead = limitReached ? String(localized: "You've used today's free answers. Here's a hint from your notes instead. ") : ""
            let text = lead + (context.map { "You wrote “\($0.given)”. " } ?? "")
                + "Have a look at \(label). What does it say about \(focus(of: questionStems, in: first.sentence))?"
            return Reply(text: text, quotes: [quote], grounded: true)
        }
    }

    /// The keywords found nothing close. With today's free answers used up, that is the reason to give, not "not covered".
    private static func nothingClose(limitReached: Bool) -> Reply {
        guard limitReached else { return Reply(text: notCovered, quotes: [], grounded: false, kind: .notCovered) }
        let text = String(localized: "You've used today's free answers, and I couldn't find a close match in your notes. They start again at midnight.")
        return Reply(text: text, quotes: [], grounded: false, kind: .notCovered)
    }

    /// The ranking this tutor always made when it was not given one: the sentences of the first three hits, by the weight of the
    /// question's words they share, headings and bare lists last. Convincing when the best hit has a third of the question's words or
    /// two of them.
    private static func rankFromHits(_ hits: [LocalRetriever.Hit], weights: [String: Double], questionStems: Set<String>) -> OfflineRanking {
        var out = OfflineRanking()
        var candidates: [OfflineRanking.Candidate] = []
        for (rank, hit) in hits.prefix(3).enumerated() {
            for (index, sentence) in units(of: hit.passage).enumerated() where !sentence.hasSuffix("?") {
                let words = Lexicon.wordCount(sentence)
                guard words >= 4, !TutorPolicy.looksLikeInstruction(sentence, context: hit.passage.text) else { continue }
                let stems = Set(Lexicon.contentStems(sentence))
                let shared = stems.intersection(questionStems)
                guard !shared.isEmpty else { continue }
                let weight = shared.reduce(0) { $0 + (weights[$1] ?? 1) }
                let commas = sentence.filter { $0 == "," }.count
                let listPenalty = commas >= 2 && words <= commas * 3 + 4 ? 1.5 : 0
                candidates.append(OfflineRanking.Candidate(passage: hit.passage, sentence: sentence,
                                                           score: weight - Double(rank) * 0.5 + min(0.4, Double(stems.count) / 30) - listPenalty,
                                                           lines: closestLines(around: index, in: hit.passage)))
            }
        }
        candidates.sort { $0.score > $1.score }
        out.candidates = candidates
        let strong = hits.first.map { $0.coverage >= minimumCoverage || $0.matched.count >= 2 } ?? false
        out.verdict = strong ? .convincing : .weak("the first hit shares too few of the question's words")
        return out
    }

    /// A question that leans on the one before it ("and how is that different from a pen?", "und was hat er gemacht?", "why?"): it
    /// opens with a connective, or refers back with a pronoun and has few words of its own, or has none. A question with a subject of
    /// its own ("what is entropy?") is not one, whatever came before. The earlier question's words are searched with a follow-up.
    static func isFollowUp(_ question: String) -> Bool {
        let folded = Lexicon.fold(question).trimmingCharacters(in: .whitespacesAndNewlines)
        let opening = #"^(and|but|also|then|or|what about|how about|und|aber|pero|mais|et)\b"#
        if folded.range(of: opening, options: .regularExpression) != nil { return true }
        let tokens = Lexicon.tokens(question)
        let own = tokens.filter { $0.isContent && !$0.isNumber && !LocalGenerator.genericStems.contains($0.stem)
                                  && !LocalRetriever.questionWords.contains($0.stem) && !LocalRetriever.chatShorthand.contains($0.word) }
        let refers: Set<String> = ["it", "its", "that", "this", "they", "them", "those", "these", "he", "him", "his", "she", "her",
                                   "er", "sie", "es", "ihn", "ihm", "dies", "diese", "dieser"]
        if tokens.contains(where: { refers.contains($0.word) }), own.count <= 3 { return true }
        return own.isEmpty
    }

    /// "That's outside your notes. Ask me about Bio 101."
    private static func redirect(topic: String?) -> String {
        let name = topic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty
            ? String(localized: "That's outside your notes. Ask me about what you've added.")
            : String(localized: "That's outside your notes. Ask me about \(name).")
    }

    // MARK: Lines

    /// The sentences of a passage; a card of a deck is one.
    static func units(of passage: LocalRetriever.Passage) -> [String] {
        passage.isCard ? [passage.text] : Lexicon.sentences(passage.text)
    }

    /// The matching sentence with the one before and the one after, so the answer is read in its place. Questions, fragments and lines
    /// written to an assistant are left out. (The sentence search has the page's own order to read these from: `OfflineRanking.Candidate`.)
    private static func closestLines(around index: Int, in passage: LocalRetriever.Passage) -> [Quote] {
        let sentences = units(of: passage)
        return (max(0, index - 1)...min(sentences.count - 1, index + 1)).compactMap { i in
            let s = sentences[i]
            guard i == index || (!s.hasSuffix("?") && Lexicon.wordCount(s) >= 3
                                 && !TutorPolicy.looksLikeInstruction(s, context: passage.text)) else { return nil }
            return Quote(passageKey: passage.key, text: s)
        }
    }

    /// The text is English, so the words around a passage can be English too.
    static func isEnglish(_ texts: [String]) -> Bool {
        LocalGenerator.dominantLanguage(texts.joined(separator: " ")) == "en"
    }

    /// A request for a question to answer, which a closing check question suits.
    static func isPracticeRequest(_ question: String) -> Bool {
        let q = Lexicon.fold(question)
        let patterns = [#"\b(quiz|test|drill|examine) me\b"#, #"\bpractice (question|problem|quiz)s?\b"#, #"\bask me\b"#,
                        #"\bcheck my understanding\b"#, #"\bgive me a (question|quiz|problem)\b"#]
        return patterns.contains { q.range(of: $0, options: .regularExpression) != nil }
    }

    // MARK: Small talk

    /// A greeting, thanks, "how are you": a few words, none of them about a subject. A follow-up like "why?" or "how?" is not.
    static func isSmallTalk(_ text: String) -> Bool {
        let words = Lexicon.tokens(text).map(\.word)
        guard !words.isEmpty else { return true }
        guard words.count <= 8 else { return false }
        let chat: Set<String> = ["hi", "hello", "hey", "hiya", "yo", "sup", "thanks", "thank", "thx", "ty", "ok", "okay", "cool",
                                 "great", "nice", "bye", "goodbye", "yes", "no", "yep", "nope", "sure", "lol", "morning",
                                 "afternoon", "evening", "night", "good", "awesome", "perfect", "got", "cap", "much", "up",
                                 "whats", "doing", "going", "today", "helps", "helped", "help", "love", "meet", "bored",
                                 "tired", "sleepy", "again"]
        let filler: Set<String> = ["how", "are", "you", "is", "it", "it's", "what's", "that", "that's", "this", "so", "very",
                                   "really", "to", "see", "do", "i", "i'm", "am", "your", "you're"]
        guard words.allSatisfy({ chat.contains($0) || filler.contains($0) }) else { return false }
        let howAreYou = #"\b(how are you|how's it going|how are things|how have you been|how do you do|what's up)\b"#
        return words.contains(where: chat.contains) || Lexicon.fold(text).range(of: howAreYou, options: .regularExpression) != nil
    }

    // MARK: Hints

    /// The sentence with its most telling word (not in the question, not a small word) replaced by "____".
    static func gap(_ sentence: String, avoiding questionStems: Set<String>) -> String? {
        let tokens = Lexicon.tokens(sentence)
        let chars = Array(sentence)
        let candidates = tokens.filter { t in
            t.isContent && !t.isNumber && t.word.count >= 4 && !questionStems.contains(t.stem)
                && !LocalGenerator.genericStems.contains(t.stem)
        }
        guard let pick = candidates.max(by: { $0.word.count < $1.word.count }) else { return nil }
        return String(chars[..<pick.range.lowerBound]) + "____" + String(chars[pick.range.upperBound...])
    }

    /// A word of the question the sentence also uses, for "what does it say about …".
    private static func focus(of questionStems: Set<String>, in sentence: String) -> String {
        let tokens = Lexicon.tokens(sentence)
        let chars = Array(sentence)
        if let t = tokens.first(where: { $0.isContent && questionStems.contains($0.stem) }) {
            return String(chars[t.range]).lowercased()
        }
        return "it"
    }
}
