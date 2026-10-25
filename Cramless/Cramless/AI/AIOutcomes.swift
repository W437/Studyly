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

// MARK: - Tutor

/// One source of the person's material the tutor may retrieve from.
struct TutorMaterial: Hashable, Sendable {
    var sourceID: UUID
    var title: String
    var kind: SourceKind
    var pages: [PageText] = []
    var segments: [TranscriptSegment] = []
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
    var maxItems: Int = 8
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
