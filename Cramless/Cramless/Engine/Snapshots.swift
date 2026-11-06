import Foundation

// The values the engines take: plain copies of what they need from the store, built once per call by
// AppModel+Insights.swift (`AppModel.itemSnapshots()` and friends). Engines never see a @Model.

/// One study item as the engines see it.
struct ItemSnapshot: Sendable, Hashable, Identifiable {
    var id: UUID
    var kind: ItemKind
    var topicID: UUID?
    var courseID: UUID?
    var memory: MemoryState
    var status: ItemStatus
    var createdAt: Date
    /// The generator's difficulty guess, 0 (easy) … 1 (hard).
    var difficultyHint: Double
    /// It comes from a moment of a lecture marked for the exam: first among ties in a session. Readiness doesn't read it.
    var examFlagged = false
    /// The student said it looks wrong and Cap hasn't settled it: out of sessions, still in readiness.
    var reported: Bool

    init(id: UUID = UUID(), kind: ItemKind = .flashcard, topicID: UUID? = nil, courseID: UUID? = nil,
         memory: MemoryState = .new, status: ItemStatus = .active, createdAt: Date = .distantPast,
         difficultyHint: Double = 0.5, examFlagged: Bool = false, reported: Bool = false) {
        self.id = id
        self.kind = kind
        self.topicID = topicID
        self.courseID = courseID
        self.memory = memory
        self.status = status
        self.createdAt = createdAt
        self.difficultyHint = difficultyHint
        self.examFlagged = examFlagged
        self.reported = reported
    }

    var lapses: Int { memory.lapses }
    /// Studied at least once (it has a memory to predict from).
    var isStudied: Bool { memory.state != .new && memory.lastReview != nil && memory.stability > 0 }
    var isActive: Bool { status == .active }
}

/// An exam and its scope.
struct ExamSnapshot: Sendable, Hashable, Identifiable {
    var id: UUID
    var courseID: UUID?
    var title: String
    var date: Date
    /// Topic ids in scope; empty means the whole course.
    var scope: Set<UUID>
    /// The readiness the plan aims for, 0…1.
    var target: Double
    var format: ExamFormat
    var readinessAtExam: Double?
    /// The share of the exam's material its questions reached when the exam started, kept with `readinessAtExam` (nil when it
    /// couldn't be told, and for an exam that started before it was kept).
    var coverageAtExam: Double?
    var resultScore: Double?

    init(id: UUID = UUID(), courseID: UUID?, title: String = "Exam", date: Date, scope: Set<UUID> = [],
         target: Double = 0.9, format: ExamFormat = ExamFormat(), readinessAtExam: Double? = nil,
         resultScore: Double? = nil, coverageAtExam: Double? = nil) {
        self.id = id
        self.courseID = courseID
        self.title = title
        self.date = date
        self.scope = scope
        self.target = target
        self.format = format
        self.readinessAtExam = readinessAtExam
        self.coverageAtExam = coverageAtExam
        self.resultScore = resultScore
    }

    var wholeCourse: Bool { scope.isEmpty }

    /// The readiness the grade was projected from on exam morning: the ring's value with the coverage taken into account
    /// (`GradeModel.adjusted`). What a calibrated line is fitted to, and what "Capling projected" reads after the exam.
    var adjustedReadinessAtExam: Double? {
        readinessAtExam.map { GradeModel.adjusted(readiness: $0, coverage: coverageAtExam) }
    }

    /// The item is part of what this exam covers.
    func covers(_ item: ItemSnapshot) -> Bool {
        guard let courseID, item.courseID == courseID else { return false }
        if scope.isEmpty { return true }
        guard let topic = item.topicID else { return false }
        return scope.contains(topic)
    }

    func covers(topic: UUID?, course: UUID?) -> Bool {
        guard let courseID, course == courseID else { return false }
        if scope.isEmpty { return true }
        guard let topic else { return false }
        return scope.contains(topic)
    }
}

struct TopicSnapshot: Sendable, Hashable, Identifiable {
    var id: UUID
    var courseID: UUID?
    var name: String
    var sortOrder: Int = 0
}

struct ConfusionSnapshot: Sendable, Hashable, Identifiable {
    var id: UUID
    var courseID: UUID?
    var name: String
    /// The items the person mixes up.
    var itemIDs: [UUID]
    /// The fix's own questions.
    var fixItemIDs: [UUID] = []
    var status: ConfusionStatus = .open
    var missCount: Int = 0
    var lastSeenAt: Date = .distantPast
}

/// One answer from the review log.
struct ReviewSnapshot: Sendable, Hashable {
    var itemID: UUID
    var courseID: UUID?
    var sessionID: UUID?
    var reviewedAt: Date
    var rating: Rating
    /// 0…1 for graded answers, -1 when not graded.
    var score: Double = -1
    var answer: String?
    var stateBefore: CardState = .new
    var stabilityAfter: Double
    var difficultyAfter: Double = 5
    var durationMs: Int = 0

    /// The same rule as `ReviewLog.wasCorrect`.
    var wasCorrect: Bool { rating.rawValue >= Rating.hard.rawValue && (score < 0 || score >= 0.6) }
}

/// One local day of studying.
struct DaySnapshot: Sendable, Hashable {
    var dayKey: String
    var day: Date
    var studySeconds: Double = 0
    var itemsReviewed: Int = 0
    var sessions: Int = 0
    var frozen = false
    var repaired = false
    /// The quests finished that day (`DayRecord.questMask`).
    var questMask = 0

    /// Counts for the streak (the same rule as `DayRecord.counts`).
    var counts: Bool { sessions > 0 || frozen || repaired }
    /// Studied (or made up by a repair), as opposed to only frozen.
    var studied: Bool { sessions > 0 || repaired }
}

/// Answer texts of an item, for spotting swapped answers (confusion candidates).
struct ItemAnswerInfo: Sendable, Hashable {
    var id: UUID
    var courseID: UUID?
    var topicID: UUID?
    var prompt: String
    /// The model answer as shown.
    var expected: String
    /// Every answer that counts as this item's answer (the answer, the correct choice, cloze blanks).
    var accepted: [String]
}

// MARK: - Deterministic randomness

/// A stable pseudo-random number from a seed, the same on every device and every launch (unlike `Hasher`).
enum StableRandom {
    /// FNV-1a over the UUID's bytes and a day number, finished with SplitMix64.
    static func seed(_ id: UUID, day: Int, salt: UInt64 = 0) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01b3
        withUnsafeBytes(of: id.uuid) { bytes in
            for b in bytes { h = (h ^ UInt64(b)) &* prime }
        }
        var d = UInt64(bitPattern: Int64(day)) ^ salt
        for _ in 0..<8 {
            h = (h ^ (d & 0xff)) &* prime
            d >>= 8
        }
        return mix(h)
    }

    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9e37_79b9_7f4a_7c15
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }

    /// A number in [0, 1).
    static func unit(_ id: UUID, day: Int, salt: UInt64 = 0) -> Double {
        Double(seed(id, day: day, salt: salt) >> 11) * 0x1.0p-53
    }

    /// The same UUID for the same name, every time (a version 4 layout over two FNV-1a hashes of the name).
    static func uuid(_ name: String) -> UUID {
        var high: UInt64 = 0xcbf2_9ce4_8422_2325
        var low: UInt64 = 0x8422_2325_cbf2_9ce4
        let prime: UInt64 = 0x0000_0100_0000_01b3
        for byte in name.utf8 {
            high = (high ^ UInt64(byte)) &* prime
            low = (low ^ UInt64(byte)) &* prime &+ 0x9e37
        }
        high = mix(high)
        low = mix(low ^ high)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: high >> (56 - 8 * UInt64(i)))
            bytes[8 + i] = UInt8(truncatingIfNeeded: low >> (56 - 8 * UInt64(i)))
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
