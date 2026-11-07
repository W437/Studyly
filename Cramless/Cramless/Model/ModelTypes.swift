import Foundation

// Value types stored inside the SwiftData models (as Codable blobs or raw values) and passed to the engines.
// Engines never see a @Model: they take these values and snapshots, so they stay pure and testable off-device.
//
// Compatibility: every type here is persisted. Add fields as optionals (or with decodeIfPresent defaults);
// never rename a case's raw value.

// MARK: - Items

/// The six question formats.
enum ItemKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// "In your own words": a free answer graded by key ideas.
    case recall
    /// "Apply it": a scenario answered in own words, graded by key ideas.
    case apply
    case mcq
    /// Fill in the blank.
    case cloze
    /// Label a diagram on the source page.
    case diagram
    case flashcard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recall: "In your own words"
        case .apply: "Apply it"
        case .mcq: "Multiple choice"
        case .cloze: "Fill in"
        case .diagram: "Diagram"
        case .flashcard: "Flashcard"
        }
    }

    /// Graded by key ideas (free text), as opposed to a single right answer.
    var isOwnWords: Bool { self == .recall || self == .apply }

    /// Typical seconds to answer, for sizing sessions.
    var typicalSeconds: Double {
        switch self {
        case .recall: 50
        case .apply: 65
        case .mcq: 16
        case .cloze: 20
        case .diagram: 25
        case .flashcard: 9
        }
    }
}

enum ItemOrigin: String, Codable, Sendable {
    /// Written by the cloud model through the relay.
    case cloud
    /// Written by the on-device model.
    case onDevice
    /// Made by the offline rules (no model).
    case rules
    /// Written by the person.
    case person
    case quizlet, anki, csv
    /// The curated sample set that ships with the app.
    case sample
}

/// Where an item is in its life. Never call this "deleted": SwiftData owns `isDeleted`.
enum ItemStatus: String, Codable, Sendable {
    /// Generated, waiting for the person's approval in the review screen.
    case draft
    case active
    /// Paused by the person; kept out of sessions.
    case suspended
    /// Unticked in review or dropped by the source check. Kept for the check's statistics, never shown.
    case rejected
}

/// One idea a good own-words answer contains, with the phrasings that count as hitting it.
/// `terms` are lowercase phrases (not regexes); the local grader matches them with stemming and fuzz.
struct KeyIdea: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var label: String
    var terms: [String]
}

struct Choice: Codable, Hashable, Sendable {
    var text: String
    var correct: Bool
    /// Why this option is right or wrong; shown after answering.
    var why: String?
}

/// A fill-in-the-blank. `text` holds the sentence with `{{…}}` around each blank's answer:
/// "During {{telophase}}, the chromatids reach opposite poles."
struct ClozeSpec: Codable, Hashable, Sendable {
    var text: String
    /// Extra accepted spellings for each blank, in blank order.
    var alternates: [[String]] = []

    init(text: String, alternates: [[String]] = []) {
        self.text = text
        self.alternates = alternates
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        alternates = try c.decodeIfPresent([[String]].self, forKey: .alternates) ?? []
    }

    /// The sentence with its blanks filled.
    var filled: String { text.replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: "") }

    /// The sentence with a line in each blank.
    var blanked: String { text.replacingOccurrences(of: #"\{\{.*?\}\}"#, with: "____", options: .regularExpression) }

    /// The blanks' answers, in order.
    var answers: [String] {
        var out: [String] = []
        var rest = Substring(text)
        while let open = rest.range(of: "{{"), let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) {
            out.append(String(rest[open.upperBound..<close.lowerBound]))
            rest = rest[close.upperBound...]
        }
        return out
    }
}

/// A diagram question: label boxes on a source page image. Boxes come from text recognition (anchors), never
/// from a model's coordinates.
struct DiagramSpec: Codable, Hashable, Sendable {
    var sourceID: UUID
    var pageIndex: Int
    var targets: [DiagramTarget]
}

struct DiagramTarget: Codable, Hashable, Sendable, Identifiable {
    var id: String { anchorID }
    /// The recognised line on the page this label sits on.
    var anchorID: String
    var label: String
    var box: NormRect
}

/// A rectangle in a page's unit space: origin top-left, 0…1 on both axes.
struct NormRect: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    static let zero = NormRect(x: 0, y: 0, w: 0, h: 0)
}

/// Where an item came from: a page and its lines, or a moment in a lecture.
struct SourceRef: Codable, Hashable, Sendable {
    var sourceID: UUID
    var pageIndex: Int?
    var anchorIDs: [String] = []
    /// Lecture time range in seconds.
    var start: Double?
    var end: Double?
    /// "p. 87 · Anaphase", "Lecture 6 · 12:05".
    var label: String
}

// MARK: - Memory (FSRS)

enum CardState: Int, Codable, Sendable {
    case new = 0, learning = 1, review = 2, relearning = 3
}

enum Rating: Int, Codable, CaseIterable, Sendable, Identifiable {
    case again = 1, hard = 2, good = 3, easy = 4

    var id: Int { rawValue }

    /// What the student reads. Good is "Got it", on the swipe, the tiles, Undo and for VoiceOver alike.
    var title: String {
        switch self {
        case .again: String(localized: "Again")
        case .hard: String(localized: "Hard")
        case .good: String(localized: "Got it")
        case .easy: String(localized: "Easy")
        }
    }
}

/// An item's memory state, as FSRS keeps it. Stored flattened on `StudyItem`; the engines take and return this.
struct MemoryState: Codable, Hashable, Sendable {
    var state: CardState = .new
    /// Days until recall probability falls to 90%. 0 for a new item.
    var stability: Double = 0
    /// 1…10.
    var difficulty: Double = 0
    var due: Date?
    var lastReview: Date?
    var reps: Int = 0
    var lapses: Int = 0
    /// Index into the learning or relearning steps.
    var step: Int = 0

    static let new = MemoryState()
}

// MARK: - Sources

enum SourceKind: String, Codable, Sendable {
    case scan, photo, pdf, text, lecture, quizlet, anki, csv, chat, sample

    /// An imported deck: cards instead of pages.
    var isDeck: Bool { self == .quizlet || self == .anki || self == .csv }

    var systemImage: String {
        switch self {
        case .scan, .photo, .sample: "doc.viewfinder"
        case .pdf: "doc.richtext"
        case .text: "text.alignleft"
        case .lecture: "mic"
        case .quizlet, .anki, .csv: "rectangle.stack"
        case .chat: "bubble.left.and.text.bubble.right"
        }
    }
}

enum SourceStatus: String, Codable, Sendable {
    /// Pages captured, text not read yet.
    case captured
    /// Text recognised; ready to generate.
    case read
    /// Questions generated and waiting for review.
    case drafted
    /// Approved into the course.
    case ready
    case failed
}

/// One recognised line of a page, with its box. The id is the anchor everything points at: "p0.l12".
struct TextLine: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var text: String
    /// Nil for text with no geometry (typed, pasted, PDF text, cloud vision transcription).
    var box: NormRect?
}

/// One timed piece of a lecture transcript.
struct TranscriptSegment: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var start: Double
    var end: Double
    var text: String
}

/// A moment in a lecture worth flagging: tapped by the person, or a phrase like "this will be on the exam".
struct ExamFlag: Codable, Hashable, Sendable, Identifiable {
    enum Reason: String, Codable, Sendable { case tapped, phrase }
    var id: String
    var time: Double
    var reason: Reason
    var text: String
}

/// Structured lecture notes.
struct LectureNotes: Codable, Hashable, Sendable {
    struct Section: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var title: String
        var start: Double
        var end: Double
        var bullets: [String]
    }

    var summary: String
    var sections: [Section]
    var keyTerms: [String] = []
    /// Who wrote them: "cloud", "onDevice" or "rules".
    var origin: String
}

// MARK: - Exams

struct ExamFormat: Codable, Hashable, Sendable {
    var multipleChoice = true
    var shortAnswer = true
    var essay = false
    var notes: String = ""
    /// How many questions the real exam has, when known: a mock takes its size and pace from it. Optional, so blobs written before it
    /// decode.
    var questionCount: Int? = nil
    /// How long the real exam is, in minutes, when known.
    var minutes: Int? = nil
    /// How many of each kind the real exam has, when its page says ("30 multiple choice and 10 short answers"): a mock follows this mix.
    var multipleChoiceCount: Int? = nil
    var shortAnswerCount: Int? = nil
    var essayCount: Int? = nil

    /// The real exam's stated mix, in the kinds ticked. A ticked kind with no number takes what the exam's size leaves ("40 questions: 30
    /// multiple choice", short answer ticked: 10). Nil when nothing is stated, or when the numbers can't say how the places divide.
    var statedMix: (multiple: Int, short: Int, essay: Int)? {
        let named = [multipleChoice ? multipleChoiceCount : nil, shortAnswer ? shortAnswerCount : nil, essay ? essayCount : nil]
        guard named.contains(where: { $0 != nil }) else { return nil }
        let ticked = [multipleChoice, shortAnswer, essay]
        let unnamed = (0..<3).filter { ticked[$0] && named[$0] == nil }
        let said = named.compactMap { $0 }.reduce(0, +)
        var counts = named.map { $0 ?? 0 }
        if !unnamed.isEmpty {
            guard let size = questionCount, size > said else { return nil }
            for (order, kind) in unnamed.enumerated() {
                counts[kind] = (size - said) / unnamed.count + (order < (size - said) % unnamed.count ? 1 : 0)
            }
        }
        guard counts.reduce(0, +) > 0 else { return nil }
        return (counts[0], counts[1], counts[2])
    }

    var summary: String {
        var parts: [String] = []
        if multipleChoice { parts.append("Multiple choice") }
        if shortAnswer { parts.append("short answer") }
        if essay { parts.append("essay") }
        return parts.isEmpty ? "Format not set" : parts.joined(separator: " + ")
    }
}

// MARK: - Sessions

enum SessionKind: String, Codable, Sendable {
    /// Today's session.
    case daily
    /// A 2-minute fix for one confusion.
    case fix
    /// The night before: weak spots only, then stop.
    case examEve
    /// A backlog spread out.
    case catchUp
    /// The two-question check in onboarding.
    case quickCheck
    /// The person chose a course or topic to practise.
    case practice
    /// A timed practice exam built from the exam's own questions (`MockExamBuilder`); its answers are recorded when it is handed in.
    case mock
}

// MARK: - Chat

enum ChatRole: String, Codable, Sendable { case user, assistant }

enum TutorMode: String, Codable, Sendable, CaseIterable {
    /// Cap asks before it tells. Always on for under-18 accounts.
    case hints
    /// Cap explains straight away.
    case explain
}

/// A citation in a tutor answer, pointing back at the person's material.
struct Citation: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var sourceID: UUID?
    var pageIndex: Int?
    var start: Double?
    /// The words quoted from the source.
    var quote: String
    /// "Textbook p. 87", "Lecture 6 · 03:12".
    var label: String
}

// MARK: - Confusions

enum ConfusionStatus: String, Codable, Sendable { case open, fixed, dismissed }

/// The 2-minute fix for a confusion: a short lesson and a few questions.
struct ConfusionFix: Codable, Hashable, Sendable {
    var lesson: String
    var itemIDs: [UUID]
    /// Cloud AI has been asked for this fix's lesson and questions, however it answered: a call is spent once.
    var asked = false

    init(lesson: String, itemIDs: [UUID], asked: Bool = false) {
        self.lesson = lesson
        self.itemIDs = itemIDs
        self.asked = asked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lesson = try container.decode(String.self, forKey: .lesson)
        itemIDs = try container.decode([UUID].self, forKey: .itemIDs)
        asked = try container.decodeIfPresent(Bool.self, forKey: .asked) ?? false
    }
}

// MARK: - Helpers

extension JSONEncoder {
    static let cramless: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let cramless: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// Encodes a Codable value for a `Data` attribute; nil on failure (never traps inside a model setter).
func encodeBlob<T: Encodable>(_ value: T) -> Data? {
    try? JSONEncoder.cramless.encode(value)
}

/// Decodes a `Data` attribute, with a fallback for missing or unreadable data.
func decodeBlob<T: Decodable>(_ type: T.Type, from data: Data?, default fallback: T) -> T {
    guard let data, let value = try? JSONDecoder.cramless.decode(type, from: data) else { return fallback }
    return value
}
