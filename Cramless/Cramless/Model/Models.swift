import Foundation
import SwiftData

// The SwiftData models. Rules (they cost hours when broken):
// - Never add a stored `isDeleted`: it collides with SwiftData's own. Soft deletes are `deletedAt != nil`.
// - Structured values are Codable blobs (`…Data`) behind typed computed accessors. Reading a blob on a model
//   that was deleted traps, so views holding a model check `modelContext != nil` / `isAlive` first.
// - Every synced model carries `updatedAt`, `syncedAt` and `deletedAt`. Mutations go through AppModel, which
//   stamps `updatedAt`; the sync engine pushes rows where `syncedAt == nil || updatedAt > syncedAt`.
// - ReviewLog is append-only.

@Model
final class Course {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorRaw: String
    var symbol: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Source.course) var sources: [Source] = []
    @Relationship(deleteRule: .cascade, inverse: \Topic.course) var topics: [Topic] = []
    @Relationship(deleteRule: .cascade, inverse: \StudyItem.course) var items: [StudyItem] = []
    @Relationship(deleteRule: .cascade, inverse: \Exam.course) var exams: [Exam] = []
    @Relationship(deleteRule: .cascade, inverse: \Confusion.course) var confusions: [Confusion] = []

    init(id: UUID = ModelID.make(), name: String, color: CourseColor = .sky, symbol: String = "book.closed",
         sortOrder: Int = 0, now: Date = .now) {
        self.id = id
        self.name = name
        self.colorRaw = color.rawValue
        self.symbol = symbol
        self.sortOrder = sortOrder
        self.createdAt = now
        self.updatedAt = now
    }

    var color: CourseColor {
        get { CourseColor(rawValue: colorRaw) ?? .sky }
        set { colorRaw = newValue.rawValue }
    }

    var isTrashed: Bool { deletedAt != nil }
    var liveItems: [StudyItem] { items.filter { $0.deletedAt == nil } }
    var activeItems: [StudyItem] { items.filter { $0.deletedAt == nil && $0.status == .active } }
    var liveSources: [Source] { sources.filter { $0.deletedAt == nil } }
    var liveTopics: [Topic] { topics.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder } }
    var liveExams: [Exam] { exams.filter { $0.deletedAt == nil }.sorted { $0.date < $1.date } }
}

@Model
final class Source {
    @Attribute(.unique) var id: UUID
    var course: Course?
    var kindRaw: String
    var statusRaw: String
    var title: String
    /// The original file kept on device (PDF, audio, imported deck), relative to `FileStore.root`.
    var fileName: String?
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var deletedAt: Date?

    // Lecture-only
    var duration: Double = 0
    var segmentsData: Data?
    var flagsData: Data?
    var notesData: Data?

    @Relationship(deleteRule: .cascade, inverse: \SourcePage.source) var pages: [SourcePage] = []

    init(id: UUID = ModelID.make(), course: Course?, kind: SourceKind, title: String, status: SourceStatus = .captured,
         now: Date = .now) {
        self.id = id
        self.course = course
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.title = title
        self.createdAt = now
        self.updatedAt = now
    }

    var kind: SourceKind {
        get { SourceKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    var status: SourceStatus {
        get { SourceStatus(rawValue: statusRaw) ?? .captured }
        set { statusRaw = newValue.rawValue }
    }

    var segments: [TranscriptSegment] {
        get { decodeBlob([TranscriptSegment].self, from: segmentsData, default: []) }
        set { segmentsData = encodeBlob(newValue) }
    }

    var flags: [ExamFlag] {
        get { decodeBlob([ExamFlag].self, from: flagsData, default: []) }
        set { flagsData = encodeBlob(newValue) }
    }

    var notes: LectureNotes? {
        get { notesData.flatMap { try? JSONDecoder.cramless.decode(LectureNotes.self, from: $0) } }
        set { notesData = newValue.flatMap(encodeBlob) }
    }

    var sortedPages: [SourcePage] { pages.sorted { $0.pageIndex < $1.pageIndex } }
}

@Model
final class SourcePage {
    @Attribute(.unique) var id: UUID
    var source: Source?
    /// 0-based position in the source.
    var pageIndex: Int
    /// What the page calls itself: the printed number if one was found ("87"), else the position ("1").
    var label: String
    /// All recognised text, lines joined with newlines.
    var text: String
    var linesData: Data?
    /// The page image kept on device, relative to `FileStore.root`. Nil for text-only sources.
    var imageFileName: String?
    var width: Double
    var height: Double
    /// How the text was read and how far to trust it (`read`, a `PageRead`). Nil until the page is read.
    var readData: Data?

    init(id: UUID = ModelID.make(), source: Source?, pageIndex: Int, label: String, text: String, lines: [TextLine],
         imageFileName: String? = nil, width: Double = 0, height: Double = 0) {
        self.id = id
        self.source = source
        self.pageIndex = pageIndex
        self.label = label
        self.text = text
        self.linesData = encodeBlob(lines)
        self.imageFileName = imageFileName
        self.width = width
        self.height = height
    }

    var lines: [TextLine] {
        get { decodeBlob([TextLine].self, from: linesData, default: []) }
        set { linesData = encodeBlob(newValue) }
    }
}

@Model
final class Topic {
    @Attribute(.unique) var id: UUID
    var course: Course?
    var name: String
    var summary: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var deletedAt: Date?

    init(id: UUID = ModelID.make(), course: Course?, name: String, summary: String = "", sortOrder: Int = 0, now: Date = .now) {
        self.id = id
        self.course = course
        self.name = name
        self.summary = summary
        self.sortOrder = sortOrder
        self.createdAt = now
        self.updatedAt = now
    }
}

@Model
final class StudyItem {
    @Attribute(.unique) var id: UUID
    var course: Course?
    /// The topic's id; a plain value so deleting a topic never cascades into items.
    var topicID: UUID?
    var kindRaw: String
    var statusRaw: String
    var originRaw: String
    /// The question (a flashcard's front).
    var prompt: String
    /// The model answer (a flashcard's back).
    var answer: String
    /// Shown after answering: why, in a sentence or two.
    var explanation: String
    var keyIdeasData: Data?
    var choicesData: Data?
    var clozeData: Data?
    var diagramData: Data?
    var sourceRefData: Data?
    /// When the source check confirmed the item against its source. Nil for unchecked items.
    var checkedAt: Date?
    /// The generator's own difficulty guess, 0 (easy) … 1 (hard).
    var difficultyHint: Double
    /// The person reported a problem with this item.
    var reported: Bool = false
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var deletedAt: Date?

    // Memory (FSRS), flattened. Read and write through `memory`.
    var stateRaw: Int = 0
    var stability: Double = 0
    var difficulty: Double = 0
    var due: Date?
    var lastReview: Date?
    var reps: Int = 0
    var lapses: Int = 0
    var step: Int = 0

    init(id: UUID = ModelID.make(), course: Course?, topicID: UUID? = nil, kind: ItemKind, status: ItemStatus = .draft,
         origin: ItemOrigin, prompt: String, answer: String, explanation: String = "", keyIdeas: [KeyIdea] = [],
         choices: [Choice] = [], cloze: ClozeSpec? = nil, diagram: DiagramSpec? = nil, sourceRef: SourceRef? = nil,
         difficultyHint: Double = 0.5, now: Date = .now) {
        self.id = id
        self.course = course
        self.topicID = topicID
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.originRaw = origin.rawValue
        self.prompt = prompt
        self.answer = answer
        self.explanation = explanation
        self.keyIdeasData = keyIdeas.isEmpty ? nil : encodeBlob(keyIdeas)
        self.choicesData = choices.isEmpty ? nil : encodeBlob(choices)
        self.clozeData = cloze.flatMap(encodeBlob)
        self.diagramData = diagram.flatMap(encodeBlob)
        self.sourceRefData = sourceRef.flatMap(encodeBlob)
        self.difficultyHint = difficultyHint
        self.createdAt = now
        self.updatedAt = now
    }

    var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw) ?? .flashcard }
        set { kindRaw = newValue.rawValue }
    }

    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var origin: ItemOrigin {
        get { ItemOrigin(rawValue: originRaw) ?? .person }
        set { originRaw = newValue.rawValue }
    }

    var keyIdeas: [KeyIdea] {
        get { decodeBlob([KeyIdea].self, from: keyIdeasData, default: []) }
        set { keyIdeasData = newValue.isEmpty ? nil : encodeBlob(newValue) }
    }

    var choices: [Choice] {
        get { decodeBlob([Choice].self, from: choicesData, default: []) }
        set { choicesData = newValue.isEmpty ? nil : encodeBlob(newValue) }
    }

    var cloze: ClozeSpec? {
        get { clozeData.flatMap { try? JSONDecoder.cramless.decode(ClozeSpec.self, from: $0) } }
        set { clozeData = newValue.flatMap(encodeBlob) }
    }

    var diagram: DiagramSpec? {
        get { diagramData.flatMap { try? JSONDecoder.cramless.decode(DiagramSpec.self, from: $0) } }
        set { diagramData = newValue.flatMap(encodeBlob) }
    }

    var sourceRef: SourceRef? {
        get { sourceRefData.flatMap { try? JSONDecoder.cramless.decode(SourceRef.self, from: $0) } }
        set { sourceRefData = newValue.flatMap(encodeBlob) }
    }

    var memory: MemoryState {
        get {
            MemoryState(state: CardState(rawValue: stateRaw) ?? .new, stability: stability, difficulty: difficulty,
                        due: due, lastReview: lastReview, reps: reps, lapses: lapses, step: step)
        }
        set {
            stateRaw = newValue.state.rawValue
            stability = newValue.stability
            difficulty = newValue.difficulty
            due = newValue.due
            lastReview = newValue.lastReview
            reps = newValue.reps
            lapses = newValue.lapses
            step = newValue.step
        }
    }

    var isLive: Bool { deletedAt == nil && status == .active }
}

/// One answer to one item. Append-only; it is the history FSRS and readiness are computed from.
@Model
final class ReviewLog {
    @Attribute(.unique) var id: UUID
    var itemID: UUID
    var courseID: UUID?
    var sessionID: UUID?
    var reviewedAt: Date
    var ratingRaw: Int
    /// The grade for an own-words or typed answer, 0…1; -1 when not graded (flashcards, choices).
    var score: Double
    /// What the person typed, when they typed.
    var answer: String?
    /// "rules", "onDevice", "cloud", "person" (self-rated, or a rating the person gave over the grade's), "self" (an own-words answer
    /// the person marked against the model answer because no model graded it). Nothing reads it back for a decision.
    var gradedBy: String
    var durationMs: Int
    var stateBeforeRaw: Int
    var stabilityBefore: Double
    var difficultyBefore: Double
    var elapsedDays: Double
    var scheduledDays: Double
    var stabilityAfter: Double
    var difficultyAfter: Double
    var syncedAt: Date?

    init(id: UUID = ModelID.make(), itemID: UUID, courseID: UUID?, sessionID: UUID?, reviewedAt: Date, rating: Rating,
         score: Double = -1, answer: String? = nil, gradedBy: String, durationMs: Int, before: MemoryState,
         after: MemoryState, elapsedDays: Double, scheduledDays: Double) {
        self.id = id
        self.itemID = itemID
        self.courseID = courseID
        self.sessionID = sessionID
        self.reviewedAt = reviewedAt
        self.ratingRaw = rating.rawValue
        self.score = score
        self.answer = answer
        self.gradedBy = gradedBy
        self.durationMs = durationMs
        self.stateBeforeRaw = before.state.rawValue
        self.stabilityBefore = before.stability
        self.difficultyBefore = before.difficulty
        self.elapsedDays = elapsedDays
        self.scheduledDays = scheduledDays
        self.stabilityAfter = after.stability
        self.difficultyAfter = after.difficulty
    }

    var rating: Rating { Rating(rawValue: ratingRaw) ?? .good }
    var wasCorrect: Bool { ratingRaw >= Rating.hard.rawValue && (score < 0 || score >= 0.6) }
}

@Model
final class Exam {
    @Attribute(.unique) var id: UUID
    var course: Course?
    var title: String
    var date: Date
    /// Topic ids in scope; empty means the whole course.
    var scopeData: Data?
    var formatData: Data?
    /// The readiness the plan aims for, 0…1.
    var targetReadiness: Double
    /// The grade the person logged afterwards, 0…1.
    var resultScore: Double?
    var resultLoggedAt: Date?
    /// Readiness on the morning of the exam, kept to calibrate projections against the logged grade.
    var readinessAtExam: Double?
    /// The share of the exam's material its questions reached when it started (0...1), kept with `readinessAtExam`: the projection
    /// is made from the readiness with the coverage taken into account, so what is projected "after the exam" and what a calibrated
    /// line is fitted to are that, not the ring's raw value. Nil when it couldn't be told, and for an exam that started before it was
    /// kept. Local to this iPhone: the sync has no column for it, so another device reads the exam as if no coverage were known.
    var coverageAtExam: Double?
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var deletedAt: Date?

    init(id: UUID = ModelID.make(), course: Course?, title: String, date: Date, scope: [UUID] = [],
         format: ExamFormat = ExamFormat(), targetReadiness: Double = 0.9, now: Date = .now) {
        self.id = id
        self.course = course
        self.title = title
        self.date = date
        self.scopeData = scope.isEmpty ? nil : encodeBlob(scope)
        self.formatData = encodeBlob(format)
        self.targetReadiness = targetReadiness
        self.createdAt = now
        self.updatedAt = now
    }

    var scope: [UUID] {
        get { decodeBlob([UUID].self, from: scopeData, default: []) }
        set { scopeData = newValue.isEmpty ? nil : encodeBlob(newValue) }
    }

    var format: ExamFormat {
        get { decodeBlob(ExamFormat.self, from: formatData, default: ExamFormat()) }
        set { formatData = encodeBlob(newValue) }
    }
}

@Model
final class StudySession {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var startedAt: Date
    var endedAt: Date?
    var plannedSeconds: Double
    var activeSeconds: Double
    var itemCount: Int
    var correctCount: Int
    var courseID: UUID?
    var examID: UUID?
    var confusionID: UUID?
    var readinessBefore: Double?
    var readinessAfter: Double?
    var syncedAt: Date?

    init(id: UUID = ModelID.make(), kind: SessionKind, startedAt: Date, plannedSeconds: Double, courseID: UUID? = nil,
         examID: UUID? = nil, confusionID: UUID? = nil) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.startedAt = startedAt
        self.plannedSeconds = plannedSeconds
        self.activeSeconds = 0
        self.itemCount = 0
        self.correctCount = 0
        self.courseID = courseID
        self.examID = examID
        self.confusionID = confusionID
    }

    var kind: SessionKind { SessionKind(rawValue: kindRaw) ?? .daily }
}

/// One local day of studying: what the streak, the heatmap and the widget read.
@Model
final class DayRecord {
    /// "yyyy-MM-dd" in the person's calendar on the day it was written.
    @Attribute(.unique) var dayKey: String
    var day: Date
    var studySeconds: Double
    var itemsReviewed: Int
    var sessions: Int
    /// A streak freeze covered this day.
    var frozen: Bool
    /// The day was repaired after the fact (a double session within two days).
    var repaired: Bool
    /// The daily quests finished, one bit for each `QuestKind`. Bits are only ever added, so two devices' masks join by OR.
    /// (The default is what lets a store from before quests open: SwiftData fills it in.)
    var questMask: Int = 0
    var syncedAt: Date?

    init(dayKey: String, day: Date, studySeconds: Double = 0, itemsReviewed: Int = 0, sessions: Int = 0,
         frozen: Bool = false, repaired: Bool = false, questMask: Int = 0) {
        self.dayKey = dayKey
        self.day = day
        self.studySeconds = studySeconds
        self.itemsReviewed = itemsReviewed
        self.sessions = sessions
        self.frozen = frozen
        self.repaired = repaired
        self.questMask = questMask
    }

    /// The day counts for the streak.
    var counts: Bool { sessions > 0 || frozen || repaired }
}

/// A named mix-up ("anaphase I vs anaphase II") built from repeated wrong answers.
@Model
final class Confusion {
    @Attribute(.unique) var id: UUID
    var course: Course?
    var name: String
    var explanation: String
    var itemIDsData: Data?
    var fixData: Data?
    var statusRaw: String
    var missCount: Int
    var createdAt: Date
    var updatedAt: Date
    var lastSeenAt: Date
    var syncedAt: Date?
    var deletedAt: Date?

    init(id: UUID = ModelID.make(), course: Course?, name: String, explanation: String, itemIDs: [UUID], fix: ConfusionFix? = nil,
         missCount: Int, now: Date = .now) {
        self.id = id
        self.course = course
        self.name = name
        self.explanation = explanation
        self.itemIDsData = encodeBlob(itemIDs)
        self.fixData = fix.flatMap(encodeBlob)
        self.statusRaw = ConfusionStatus.open.rawValue
        self.missCount = missCount
        self.createdAt = now
        self.updatedAt = now
        self.lastSeenAt = now
    }

    var itemIDs: [UUID] {
        get { decodeBlob([UUID].self, from: itemIDsData, default: []) }
        set { itemIDsData = encodeBlob(newValue) }
    }

    var fix: ConfusionFix? {
        get { fixData.flatMap { try? JSONDecoder.cramless.decode(ConfusionFix.self, from: $0) } }
        set { fixData = newValue.flatMap(encodeBlob) }
    }

    var status: ConfusionStatus {
        get { ConfusionStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class ChatThread {
    @Attribute(.unique) var id: UUID
    var courseID: UUID?
    var title: String
    var modeRaw: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.thread) var messages: [ChatMessage] = []

    init(id: UUID = ModelID.make(), courseID: UUID?, title: String, mode: TutorMode, now: Date = .now) {
        self.id = id
        self.courseID = courseID
        self.title = title
        self.modeRaw = mode.rawValue
        self.createdAt = now
        self.updatedAt = now
    }

    var mode: TutorMode {
        get { TutorMode(rawValue: modeRaw) ?? .hints }
        set { modeRaw = newValue.rawValue }
    }

    var sortedMessages: [ChatMessage] { messages.sorted { $0.createdAt < $1.createdAt } }
}

@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var thread: ChatThread?
    var roleRaw: String
    var text: String
    var citationsData: Data?
    /// "cloud", "onDevice" or "rules" for Cap's messages.
    var origin: String?
    /// The item a "Explain my mistake" chat started from.
    var contextItemID: UUID?
    var createdAt: Date
    /// What Cap's assistant did in this reply (`AssistantStep`s), kept so a draft can still be added, changed or taken back.
    /// Chats stay on this iPhone, so this never syncs.
    var actionsData: Data?

    init(id: UUID = ModelID.make(), thread: ChatThread?, role: ChatRole, text: String, citations: [Citation] = [],
         origin: String? = nil, contextItemID: UUID? = nil, steps: [AssistantStep] = [], now: Date = .now) {
        self.id = id
        self.thread = thread
        self.roleRaw = role.rawValue
        self.text = text
        self.citationsData = citations.isEmpty ? nil : encodeBlob(citations)
        self.origin = origin
        self.contextItemID = contextItemID
        self.createdAt = now
        self.actionsData = steps.isEmpty ? nil : encodeBlob(steps)
    }

    var role: ChatRole { ChatRole(rawValue: roleRaw) ?? .assistant }

    var steps: [AssistantStep] {
        get { decodeBlob([AssistantStep].self, from: actionsData, default: []) }
        set { actionsData = newValue.isEmpty ? nil : encodeBlob(newValue) }
    }

    var citations: [Citation] {
        get { decodeBlob([Citation].self, from: citationsData, default: []) }
        set { citationsData = newValue.isEmpty ? nil : encodeBlob(newValue) }
    }
}
