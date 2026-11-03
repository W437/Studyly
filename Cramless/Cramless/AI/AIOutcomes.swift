import Foundation

// What the screens hand `AIRouter` and what they get back. Plain values: no model objects, no transport types
// beyond the contract's own. `AppModel+AI.swift` builds the inputs from the store.
//
// Every outcome says who made it (`origin` / `gradedBy`), whether a better tier was tried and fell back
// (`fellBack`), what the UI may offer instead (`suggestion`: the consent sheet or the paywall), and whether a free
// limit stopped a model tier (`limitReached`, which the UI turns into the paywall). An outcome is always usable:
// when nothing better is allowed or reachable, it is the offline rules' answer.

// MARK: - Shared

/// Something the UI can offer after a job, because a better path exists but isn't allowed yet.
enum AISuggestion: Hashable, Sendable {
    /// Cloud AI would do this job better and the person hasn't allowed it. Present `.consent(.cloudAI(feature:))`.
    case allowCloud(feature: String)
    /// The job needs page photos sent and that switch is off. Present `.consent(.photos)`.
    case allowPhotos
    /// A free limit was reached. Present the paywall (`.paywall(.feature(message))`).
    case upgrade(QuotaMeter.Key, message: String)

    /// The sheet that acts on the suggestion.
    var sheet: AppSheet {
        switch self {
        case .allowCloud(let feature): .consent(.cloudAI(feature: feature))
        case .allowPhotos: .consent(.photos)
        case .upgrade(_, let message): .paywall(.feature(message))
        }
    }
}

/// One page of material as the AI jobs read it.
struct PageText: Hashable, Sendable {
    var index: Int
    /// What the page calls itself: "87".
    var label: String
    var lines: [TextLine]
    /// The page photo on disk. Read, downscaled and sent only when "Send page photos" is on at the moment the
    /// request is built.
    var imageURL: URL?

    init(index: Int, label: String, lines: [TextLine], imageURL: URL? = nil) {
        self.index = index
        self.label = label
        self.lines = lines
        self.imageURL = imageURL
    }
}

/// An item the check took out, with the reason the person can read in review ("p. 87 never mentions sex cells").
struct DroppedItem: Hashable, Sendable {
    var item: GeneratedItem
    var reason: String
}

// MARK: - Generate a set

struct GenerationInput: Hashable, Sendable {
    var course: String
    var sourceTitle: String
    /// `AppSettings.Level.rawValue`.
    var level: String?
    var pages: [PageText]
    var formats: [ItemKind] = ItemKind.allCases
    var maxItems: Int = 16
    /// The language the student's other sources in the course are written in, when they agree (`AppModel.courseLanguage`): what the
    /// page's language falls back to when its own words don't say (an equation sheet), before the device's.
    var courseLanguage: String? = nil
}

/// The processing screen's four steps, in order. Every run passes through all of them, and never goes back: when a
/// tier falls back to the next, `GenerationProgress.origin` changes and the phase carries on from where it was.
enum GenerationPhase: Int, CaseIterable, Comparable, Sendable {
    case reading, findingKeyIdeas, writingQuestions, checking

    var title: String {
        switch self {
        case .reading: "Reading the page"
        case .findingKeyIdeas: "Finding the key ideas"
        case .writingQuestions: "Writing questions"
        case .checking: "Checking each one against your page"
        }
    }

    static func < (lhs: GenerationPhase, rhs: GenerationPhase) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct GenerationProgress: Equatable, Sendable {
    var phase: GenerationPhase
    /// Topic names found so far (the chips under "Finding the key ideas").
    var topics: [String] = []
    /// Questions written so far.
    var written: Int = 0
    /// Questions checked so far, and how many passed.
    var checked: Int = 0
    var kept: Int = 0
    /// Who is doing the work: shown as "on your iPhone" or "with Cloud AI".
    var origin: ItemOrigin = .rules
    /// The step's second line: "On your iPhone", "So nothing made up gets through", "14 of 14 match the page".
    var detail: String = ""
    /// A long reading goes to Cloud AI in parts that fit one scan: the part under way and how many there are
    /// (1 of 1 when it fits). `detail` says "Part 2 of 2" while there is more than one.
    var part: Int = 1
    var parts: Int = 1
}

enum GenerationUpdate: Equatable, Sendable {
    case progress(GenerationProgress)
    case finished(GenerationOutcome)
}

struct GenerationOutcome: Equatable, Sendable {
    var title: String
    var topics: [GeneratedTopic]
    /// Drafts for review. Nothing is saved until the person approves them.
    var items: [GeneratedItem]
    var dropped: [DroppedItem]
    var origin: ItemOrigin
    /// The model's name as the relay reported it, "on-device" or "rules".
    var model: String
    /// Who checked the items against the page: the cloud check, or the grounding check on this iPhone.
    var checkedBy: ItemOrigin
    /// An honest line for the review screen when the result is basic.
    var note: String?
    var suggestion: AISuggestion?
    var limitReached: QuotaMeter.Key?
    /// A better tier was tried and didn't answer; this is the next one down.
    var fellBack: Bool
    /// How a long reading was cut into parts for Cloud AI and how each went. One entry when it fitted a single scan;
    /// empty when the cloud was never asked or never answered.
    var parts: [GenerationPartReport] = []
    /// Why Cloud AI, tried first, gave no set, when this iPhone's model or the rules wrote this one instead (nil: it was not
    /// asked, or a free limit was the reason: `limitReached`). The review of a set written again says it when it keeps the earlier
    /// questions (`AIRouter.keptNote`).
    var cloudFailure: AIRouter.CloudFailure? = nil

    /// The source pages the parts that were read covered. Nil when the parts weren't tracked (this iPhone's model or the offline
    /// rules wrote the set from every page it was given), so every page counts.
    var pagesRead: Set<Int>? {
        guard !parts.isEmpty else { return nil }
        return Set(parts.filter { $0.status == .read }.flatMap(\.pageIndexes))
    }
}

extension ItemOrigin {
    /// How good a set from this tier is expected to be: Cloud AI's, then this iPhone's model's, then the offline rules'. Nil for what
    /// no tier wrote (a person's own cards, an import, the sample).
    var tierRank: Int? {
        switch self {
        case .cloud: 3
        case .onDevice: 2
        case .rules: 1
        case .person, .quizlet, .anki, .csv, .sample: nil
        }
    }

    /// A set from `self` may replace one from `earlier`: the same tier or a better one. A weaker set never replaces a stronger one (Cloud AI
    /// didn't answer this time): that would throw the better questions away.
    func mayReplace(_ earlier: ItemOrigin) -> Bool {
        guard let mine = tierRank, let theirs = earlier.tierRank else { return true }
        return mine >= theirs
    }
}

/// One part of a long reading sent to Cloud AI as its own scan.
struct GenerationPartReport: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// Written and checked.
        case read
        /// Asked and not answered (or nothing usable came back).
        case failed
        /// Never asked: the free scans ran out first.
        case notStarted
    }

    var number: Int
    /// The labels of its first and last page ("1", "7").
    var firstPage: String
    var lastPage: String
    var pageCount: Int
    /// The source's own page indexes (`PageText.index`) of the pages it covers, for the drafts of a page it didn't read.
    var pageIndexes: [Int] = []
    var status: Status
    /// Questions kept after both checks.
    var kept: Int = 0
}

// MARK: - Grade an answer

/// What the person gave.
enum AnswerInput: Hashable, Sendable {
    /// Own words (recall, apply), or a typed answer to anything else.
    case text(String)
    /// One answer per blank of a fill-in, in blank order.
    case blanks([String])
    /// The index of the chosen option.
    case choice(Int)
    /// One label per diagram target, in target order.
    case labels([String])

    var displayText: String {
        switch self {
        case .text(let t): t
        case .blanks(let b): b.joined(separator: " / ")
        case .choice(let i): "#\(i)"
        case .labels(let l): l.joined(separator: ", ")
        }
    }
}

/// The question as the grader needs it.
struct GradeSubject: Hashable, Sendable {
    var kind: ItemKind
    var prompt: String
    var modelAnswer: String
    var keyIdeas: [KeyIdea] = []
    var choices: [Choice] = []
    var cloze: ClozeSpec?
    /// The expected label of each diagram target, in order.
    var diagramLabels: [String] = []
    /// The lines the item came from, for the cloud grader's context.
    var sourceExcerpt: String?
    var level: String?

    init(kind: ItemKind, prompt: String, modelAnswer: String, keyIdeas: [KeyIdea] = [], choices: [Choice] = [],
         cloze: ClozeSpec? = nil, diagramLabels: [String] = [], sourceExcerpt: String? = nil, level: String? = nil) {
        self.kind = kind
        self.prompt = prompt
        self.modelAnswer = modelAnswer
        self.keyIdeas = keyIdeas
        self.choices = choices
        self.cloze = cloze
        self.diagramLabels = diagramLabels
        self.sourceExcerpt = sourceExcerpt
        self.level = level
    }

    init(item: GeneratedItem, sourceExcerpt: String? = nil, level: String? = nil) {
        self.init(kind: item.kind, prompt: item.prompt, modelAnswer: item.answer, keyIdeas: item.keyIdeas,
                  choices: item.choices, cloze: item.cloze, diagramLabels: [], sourceExcerpt: sourceExcerpt, level: level)
    }
}

/// A key idea the answer hit, marked on the person's own words. `range` is in `Character` offsets of the answer.
struct GradeMark: Hashable, Sendable {
    var ideaID: String
    var range: Range<Int>
}

struct MissingIdea: Hashable, Sendable {
    var id: String
    var label: String
}

/// How final a grade is.
enum GradeMode: String, Hashable, Sendable {
    /// Final: an exact check, a model's grade, or the rules' verdict where they can be trusted (an empty answer, an "I don't
    /// know", an answer with nothing to do with the question, an answer the rules call correct).
    case verdict
    /// The rules' verdict, shown while a model that is allowed is still working on it ("Double-checking…"). The model's grade
    /// replaces it; if there is none, the grade becomes `.selfCheck`.
    case provisional
    /// No model will grade this own-words answer, and the rules' verdict is not one to show: measured on 276 graded answers, the
    /// rules said "partly" and were right 19% of the time, "not yet" and were right 45% of the time. The person compares their
    /// answer with the model answer and ticks the key ideas they had (`SelfCheck`).
    case selfCheck
}

/// Why no model graded an answer the person has to mark themselves. It picks the line under the answer
/// (`SessionCopy.selfCheckLine`).
enum SelfCheckReason: String, Hashable, Sendable {
    /// Cloud AI is off, and this iPhone's own AI isn't there to take over.
    case cloudOff
    /// The free Cloud AI checks for the day are used, and this iPhone's own AI isn't there to take over.
    case freeLimit
    /// Cloud AI would have, but there was no connection.
    case offline
    /// Cloud AI would have, but it didn't answer (the server, or a request that was cancelled).
    case unreachable
    /// Cloud AI isn't offered here (a build with no relay, a child's account), and this iPhone's AI is off, unavailable or can't
    /// read this answer.
    case deviceUnavailable
}

struct GradeOutcome: Equatable, Sendable {
    /// 0…1.
    var score: Double
    var verdict: GradeResponse.Verdict
    /// 0…1. Below 0.6 the UI offers "Grade again" prominently (`needsSecondLook`).
    var confidence: Double
    /// Only words found verbatim in the answer are ever marked.
    var marks: [GradeMark]
    var hitIdeaIDs: [String]
    var missing: [MissingIdea]
    var feedback: String
    /// One sentence that would complete the answer; empty when nothing is missing.
    var fix: String
    /// `.rules`, `.onDevice` or `.cloud`; its `rawValue` is what `ReviewLog.gradedBy` stores.
    var gradedBy: ItemOrigin
    var model: String
    /// False for the instant offline grade; true once a model refined it.
    var isRefined: Bool = false
    /// Fill-ins and diagrams: right or wrong per blank, in order.
    var blankResults: [Bool] = []
    /// A typo the grader forgave, to point out: "Check the spelling: telophase".
    var spellingNote: String?
    /// "Grade again": whether the second look agrees with the first.
    var agreesWithPrevious: Bool?
    var suggestion: AISuggestion?
    var limitReached: QuotaMeter.Key?
    var fellBack: Bool = false
    /// How final this grade is. Everything but an own-words answer the rules graded alone is `.verdict`.
    var mode: GradeMode = .verdict
    /// With `.selfCheck`: why no model graded it.
    var selfCheckReason: SelfCheckReason?

    var needsSecondLook: Bool { confidence < 0.6 }
    var isCorrect: Bool { verdict == .correct }

    /// The marks for `HighlightedText`, merged where they touch.
    var highlightMarks: [HighlightMark] {
        let sorted = marks.map(\.range).sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<Int>] = []
        for r in sorted {
            if let last = merged.last, r.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                merged.append(r)
            }
        }
        return merged.map { HighlightMark(range: $0, tone: .hit) }
    }
}

/// Marking an own-words answer yourself, for when no model grades it.
///
/// The rules are right when they call an answer correct (88% of the time) and when the answer is nothing to mark (empty, an "I
/// don't know", off the subject). What they say about a paraphrase, a terse answer or a partly right one is a guess (right 19% of
/// the time for "partly", 45% for "not yet"), so it is not shown as a verdict: the person sees the model answer and ticks the key
/// ideas they had, starting from the ones the rules found in their own words. What the ticks come to is the answer's score.
enum SelfCheck {

    /// How long a person waits for a model to look at an answer the rules have only graded provisionally. Past it the model is let go
    /// and the answer is settled without one (the person's to mark, or the rules' verdict where it can be trusted), so a slow
    /// connection never holds up the next question.
    static let modelWait: Duration = .seconds(8)

    /// The rules' grade can stand without a model: it says correct, or the answer is nothing to mark.
    static func trustsRules(_ rules: GradeOutcome, subject: GradeSubject, answer: String) -> Bool {
        if rules.verdict == .correct { return true }
        let given = Set(Lexicon.contentStems(answer))
        if given.isEmpty || isDontKnow(answer) { return true }
        // Nothing in common with the question, its answer or its key ideas: not an attempt at this question. (Their vocabulary
        // is counted, so a paraphrase that reuses any of it is still the person's to mark.) That holds for an answer the rules can
        // read: one in another language shares no word with an English question whatever it says, so it is the person's to mark.
        var known = Set(Lexicon.contentStems([subject.prompt, subject.modelAnswer, subject.sourceExcerpt ?? ""].joined(separator: " ")))
        for idea in subject.keyIdeas { known.formUnion(Lexicon.contentStems(([idea.label] + idea.terms).joined(separator: " "))) }
        return given.isDisjoint(with: known) && readsAsEnglish(answer)
    }

    /// The rules can read this answer: it is not in another script or a language the recogniser is sure is not English (the same
    /// gate that keeps this iPhone's model away from them).
    static func readsAsEnglish(_ answer: String) -> Bool {
        switch OnDeviceLanguageGate.verdict(for: answer, supportsLocale: { _ in true }) {
        case .supported, .tooShort: true
        case .foreignScript, .notEnglish, .unsupportedByModel: false
        }
    }

    /// An explicit "I don't know" ("idk", "no idea, sorry", "I don't know what mitosis is"): one of the phrases below, and at most one
    /// other word that carries meaning. A hedge with an attempt in it ("maybe growth, I don't know") is not one.
    static func isDontKnow(_ answer: String) -> Bool {
        var rest = Lexicon.tokens(answer).map(\.word)
        guard !rest.isEmpty else { return false }
        var found = false
        for phrase in dontKnowPhrases {
            while let at = firstIndex(of: phrase, in: rest) {
                rest.removeSubrange(at..<(at + phrase.count))
                found = true
            }
        }
        guard found else { return false }
        let meaningful = rest.filter { !Lexicon.stopWords.contains($0) && !Lexicon.isNegationWord($0) && !fillers.contains($0) }
        return meaningful.count <= 1
    }

    /// The key ideas that start ticked: the ones the rules found in the person's own words (their highlight stays).
    static func startingTicks(of outcome: GradeOutcome, ideas: [KeyIdea]) -> Set<String> {
        Set(ideas.map(\.id)).intersection(outcome.hitIdeaIDs)
    }

    /// Continue may be pressed on a self-check: the person has marked something (changed a tick or chosen "None of these"), or the rules
    /// found at least one idea in their words, so the ticks they start from are something to agree with. With nothing found and
    /// nothing touched there is no mark, and an unmarked answer must not be logged as a deliberate "I had none".
    static func canContinue(changedByPerson: Bool, rulesFoundIdeas: Bool) -> Bool { changedByPerson || rulesFoundIdeas }

    /// What the ticks come to, 0…1: the ticked ideas over all of them (0 with none).
    static func score(ticked: Set<String>, of ideas: [KeyIdea]) -> Double {
        guard !ideas.isEmpty else { return 0 }
        return Double(ideas.filter { ticked.contains($0.id) }.count) / Double(ideas.count)
    }

    /// The rules' grade of an own-words answer with its mode set. `modelAllowed`: a model tier is on the route, so the grade is
    /// provisional (an "I don't know" needs no second opinion and stays as it is). Otherwise it is final where the rules can be
    /// trusted, and the person's to mark where they can't, for the reason `why` gives.
    static func settled(_ rules: GradeOutcome, subject: GradeSubject, answer: String, modelAllowed: Bool,
                        why: SelfCheckReason?) -> GradeOutcome {
        var outcome = rules
        if modelAllowed {
            outcome.mode = isDontKnow(answer) ? .verdict : .provisional
        } else if trustsRules(rules, subject: subject, answer: answer) {
            outcome.mode = .verdict
        } else {
            outcome.mode = .selfCheck
            outcome.selfCheckReason = why ?? .deviceUnavailable
        }
        return outcome
    }

    private static let dontKnowPhrases: [[String]] = [
        ["i", "don't", "know"], ["i", "dont", "know"], ["i", "do", "not", "know"], ["don't", "know"], ["dont", "know"],
        ["no", "idea"], ["no", "clue"], ["idk"], ["dunno"], ["i", "forgot"], ["don't", "remember"], ["dont", "remember"],
        ["can't", "remember"], ["cant", "remember"], ["give", "up"], ["no", "answer"],
    ]

    /// Words around an "I don't know" that say nothing about the subject.
    private static let fillers: Set<String> = [
        "sorry", "please", "yet", "answer", "question", "honestly", "lol", "sure", "really", "sir", "now", "anything", "thanks",
    ]

    private static func firstIndex(of phrase: [String], in words: [String]) -> Int? {
        guard !phrase.isEmpty, words.count >= phrase.count else { return nil }
        for start in 0...(words.count - phrase.count) where Array(words[start..<(start + phrase.count)]) == phrase { return start }
        return nil
    }
}

// MARK: - Tutor

/// One source of the person's material the tutor may retrieve from: pages, a lecture's segments, or an imported
/// deck's cards (`TutorMaterial.deck`).
struct TutorMaterial: Hashable, Sendable {
    var sourceID: UUID
    var title: String
    var kind: SourceKind
    var pages: [PageText] = []
    var segments: [TranscriptSegment] = []
    var cards: [TutorCard] = []
}

struct TutorInput: Hashable, Sendable {
    /// The chat so far; the last user message is the question.
    var messages: [TutorMessage]
    var course: String?
    var material: [TutorMaterial]
    /// Set when the chat starts from a wrong answer ("Explain my mistake").
    var context: TutorContext?
}

enum TutorUpdate: Equatable, Sendable {
    /// The tier that is answering, sent once with its first words.
    case started(origin: ItemOrigin)
    case text(String)
    case citation(Citation)
    case finished(TutorOutcome)
}

struct TutorOutcome: Equatable, Sendable {
    var text: String
    var citations: [Citation]
    var origin: ItemOrigin
    var model: String
    var mode: TutorMode
    /// False when the person's material doesn't cover the question and Cap said so.
    var grounded: Bool
    /// The answer stopped part way (the connection dropped); `text` is what arrived.
    var interrupted: Bool = false
    var note: String?
    var suggestion: AISuggestion?
    var limitReached: QuotaMeter.Key?
    var fellBack: Bool = false
}

// MARK: - Confusions, lectures, cards, transcription

struct ConfusionsOutcome: Equatable, Sendable {
    var confusions: [ConfusionOut]
    var origin: ItemOrigin
    var model: String
    var suggestion: AISuggestion?
    var fellBack: Bool = false
}

struct LectureInput: Hashable, Sendable {
    var course: String
    var title: String
    var segments: [TranscriptSegment]
    var flags: [ExamFlag]
    var maxItems: Int = AIFreeLimits.lectureQuestions
}

struct LectureOutcome: Equatable, Sendable {
    var title: String
    var notes: LectureNotes
    var examFlags: [LectureExamFlag]
    /// Drafts for review, anchored to segment ids.
    var items: [GeneratedItem]
    var dropped: [DroppedItem]
    var origin: ItemOrigin
    var model: String
    var note: String?
    var suggestion: AISuggestion?
    var limitReached: QuotaMeter.Key?
    var fellBack: Bool = false
    /// Cloud AI's count of exam-relevant ideas the notes didn't turn into questions (the question cap was reached).
    var leftOut: Int?
    /// The offline rules couldn't make notes worth keeping from this transcript (their section titles were junk), so
    /// none were made: `notes` is empty, `note` says so, and `suggestion` is the way to Cloud AI when consent is what's
    /// missing. Callers keep the lecture without notes (the "Make notes" button stays) instead of saving an empty set.
    var needsCloud: Bool = false
}

struct CardsOutcome: Equatable, Sendable {
    /// Drafts for review: nothing is added until the person picks them.
    var items: [GeneratedItem]
    var origin: ItemOrigin
    var model: String
    var suggestion: AISuggestion?
    var fellBack: Bool = false
}

enum TranscriptionResult: Equatable, Sendable {
    /// Cloud transcription has no geometry: the lines can be cited and searched, never boxed on the page.
    case lines([TextLine], model: String)
    /// Not allowed right now; the suggestion says what would allow it (nil when nothing can, e.g. no relay).
    case notAllowed(AISuggestion?)
    case failed(String)
}
