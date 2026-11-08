import Foundation

// What Ask Cap's assistant does, as plain values. A reply holds steps, one for each tool the model called. A step is
// shown in the chat as a card that works, then proposes (or, with "Let Cap do it" on, has already done it), and is kept in
// the chat message (`ChatMessage.steps`) so it survives leaving the screen. Nothing here touches the store: the pure rules
// (reading the model's arguments, checking its quotes) live in `AssistantDrafts`, the changes in `AppModel+Assistant`.

// MARK: - Where a drafted item comes from

/// A stretch of the student's own material that backs a card or a question. The model claims it; the app checks it.
struct Evidence: Codable, Hashable, Sendable {
    var quote: String
    var sourceID: UUID?
    var pageIndex: Int?
    /// Seconds into a lecture.
    var start: Double?
    /// "Textbook p. 87", "Lecture 6 · 03:12".
    var label: String
    /// The line or segment ids the quote sits on.
    var anchorIDs: [String]
}

enum DraftBasis: Codable, Hashable, Sendable {
    /// Still being checked (the card has just been written).
    case checking
    /// The quote is really in the notes.
    case notes(Evidence)
    /// Nothing in the notes backs it: Cap's own words, marked as such and left for the student to judge.
    case own

    var isFromNotes: Bool { if case .notes = self { true } else { false } }

    var evidence: Evidence? { if case .notes(let e) = self { e } else { nil } }
}

struct CardDraft: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var front: String
    var back: String
    var basis: DraftBasis = .checking
    var kept = true
    /// The course already has this card: it is left out unless the student ticks it.
    var isDuplicate = false
}

struct QuestionDraft: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case multipleChoice, shortAnswer, fillBlank

        var title: String {
            switch self {
            case .multipleChoice: "Pick one"
            case .shortAnswer: "In your words"
            case .fillBlank: "Fill in the blank"
            }
        }
    }

    var id: UUID
    var kind: Kind
    /// The question. For a fill-in, the sentence with the blank as {{answer}}.
    var prompt: String
    var answer: String
    var choices: [String] = []
    var correctIndex: Int?
    var keyIdeas: [String] = []
    var explanation = ""
    var basis: DraftBasis = .checking
    var kept = true
    var isDuplicate = false
}

struct NoteDraft: Codable, Hashable, Sendable {
    var title: String
    var body: String
}

struct ExamPlanDraft: Codable, Hashable, Sendable {
    var title: String
    var date: Date
    /// False when the student gave a day and no time (the exam then starts at 9:00).
    var hasTime: Bool
    var topicIDs: [UUID]
    var topicNames: [String]
    /// The course already has an exam that day.
    var isDuplicate = false
}

/// A button the student taps: a practice session.
struct PracticeOffer: Codable, Hashable, Sendable {
    var courseID: UUID?
    var topicID: UUID?
    var minutes: Int
    var label: String
}

/// A button the student taps: a screen of the app.
struct OpenOffer: Codable, Hashable, Sendable {
    enum Screen: String, Codable, Sendable { case today, library, progress, sky, course, exam }

    var screen: Screen
    var id: UUID?
    var label: String
}

/// Passages found in the student's notes for a lookup.
struct NotesLookup: Codable, Hashable, Sendable {
    struct Hit: Codable, Hashable, Sendable {
        var label: String
        var preview: String
    }

    var query: String
    var hits: [Hit]
}

struct WebSource: Codable, Hashable, Sendable {
    var url: String
    var domain: String
    var title: String?
}

struct ResearchResult: Codable, Hashable, Sendable {
    enum Phase: String, Codable, Sendable { case starting, searching, reading, writing, done }

    var topic: String
    var phase: Phase = .starting
    /// What was searched, in plain words.
    var queries: [String] = []
    /// The pages found, then (once the summary cites them) the ones it rests on come first.
    var sources: [WebSource] = []
    /// The pages the summary cites.
    var cited: [WebSource] = []
    var text = ""
    /// The note made from it, once saved.
    var savedSourceID: UUID?
}

// MARK: - A step

enum AssistantPayload: Codable, Hashable, Sendable {
    case none
    case lookup(NotesLookup)
    case cards([CardDraft])
    case questions([QuestionDraft])
    case note(NoteDraft)
    case exam(ExamPlanDraft)
    case practice(PracticeOffer)
    case open(OpenOffer)
    case research(ResearchResult)
}

struct AssistantStep: Codable, Hashable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        /// The model is writing it, or the web is being read.
        case working
        /// Waiting for the student: add, change or skip.
        case proposed
        /// Added to the student's library (by them, or by "Let Cap do it").
        case applied
        case skipped
        /// Added, then taken back.
        case undone
        case failed
        /// A lookup that is finished, nothing to decide.
        case done
        /// A button for the student to tap (practice, a screen).
        case offered
    }

    var id: String
    var tool: AssistantToolName
    var status: Status
    var courseID: UUID?
    var courseName = ""
    var topicName: String?
    /// "6 flashcards on Mitosis".
    var title: String
    /// A failure, a limit, or an aside, in words for the student.
    var detail: String?
    var payload: AssistantPayload
    /// What adding it made, so it can be taken back.
    var createdIDs: [UUID] = []
    var appliedAt: Date?
    /// Added by "Let Cap do it", not by a tap.
    var auto = false
    /// Failed because it needs Capling Pro: the card offers the paywall.
    var needsPro = false
    /// The model has finished writing the drafts and the app is checking each one against the notes, one at a time. Nil while
    /// the model is still writing, and once the step has settled.
    var checking: Bool?

    var isFinished: Bool { status != .working }

    /// A number that changes whenever the card's layout may have grown (a card written or checked, more of a note, a page found),
    /// so the chat can follow a reply down as it is made.
    var growth: Int {
        let phase: Int
        switch status {
        case .working: phase = 0
        case .proposed: phase = 1
        default: phase = 2
        }
        var weight = 0
        switch payload {
        case .cards(let c): weight = c.count * 4 + c.filter { $0.basis != .checking }.count
        case .questions(let q): weight = q.count * 4 + q.filter { $0.basis != .checking }.count
        case .note(let n): weight = n.body.count / 50
        case .research(let r): weight = r.queries.count + r.sources.count * 2 + r.cited.count * 3 + r.text.count / 60
        case .lookup(let l): weight = l.hits.count
        default: break
        }
        return phase * 10_000 + weight + (checking == true ? 1 : 0)
    }

    /// The student still has to decide.
    var isOpen: Bool { status == .proposed }
}

// MARK: - The kinds a student can hand over

/// What "Let Cap do it" can be switched on for. Deleting or changing something that exists always asks.
enum AssistantAutoKind: String, Codable, CaseIterable, Sendable {
    case cards, notes, exams

    init?(tool: AssistantToolName) {
        switch tool {
        case .createFlashcards, .createQuizQuestions: self = .cards
        case .createNote: self = .notes
        case .createExam: self = .exams
        default: return nil
        }
    }
}

/// The student's choices about what Cap may do on its own. Everything is ask-first until they say otherwise, and
/// accounts under 18 cannot say otherwise.
struct AssistantSettings: Codable, Equatable, Sendable {
    var auto: Set<AssistantAutoKind> = []
    /// Web research (Pro): Cap may look things up on trusted study sites when asked.
    var webResearch = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        auto = Set((try c.decodeIfPresent([String].self, forKey: .auto) ?? []).compactMap(AssistantAutoKind.init(rawValue:)))
        webResearch = try c.decodeIfPresent(Bool.self, forKey: .webResearch) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(auto.map(\.rawValue).sorted(), forKey: .auto)
        try c.encode(webResearch, forKey: .webResearch)
    }

    private enum CodingKeys: String, CodingKey { case auto, webResearch }
}
