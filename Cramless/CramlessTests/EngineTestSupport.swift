import Foundation
import XCTest
@testable import Cramless

/// Shared helpers for the engine tests: fixed calendars and clocks, item builders.
enum EngineTest {
    static func calendar(_ zone: String = "America/New_York", firstWeekday: Int = 1) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        c.firstWeekday = firstWeekday
        return c
    }

    /// A local wall-clock time in the calendar's zone.
    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0, in cal: Calendar = calendar()) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    /// A studied review item whose recall now is `recall`, last reviewed `daysAgo` days before `now`.
    static func studied(_ id: UUID = UUID(), kind: ItemKind = .flashcard, topic: UUID? = nil, course: UUID? = nil,
                        recall: Double, daysAgo: Int, difficulty: Double = 5, now: Date, cal: Calendar = calendar(),
                        lapses: Int = 0, createdDaysAgo: Int = 30) -> ItemSnapshot {
        let fsrs = FSRS()
        let elapsed = Double(daysAgo)
        // Solve R(elapsed) = recall for stability.
        let s = max(0.01, fsrs.factor * elapsed / (pow(recall, 1 / fsrs.decay) - 1))
        let last = cal.adding(days: -daysAgo, to: now).addingTimeInterval(-60)
        let due = cal.adding(days: fsrs.nextInterval(stability: s), to: last)
        let memory = MemoryState(state: .review, stability: s, difficulty: difficulty, due: due, lastReview: last,
                                 reps: 3, lapses: lapses, step: 0)
        return ItemSnapshot(id: id, kind: kind, topicID: topic, courseID: course, memory: memory,
                            createdAt: cal.adding(days: -createdDaysAgo, to: now), difficultyHint: 0.5)
    }

    static func fresh(_ id: UUID = UUID(), kind: ItemKind = .flashcard, topic: UUID? = nil, course: UUID? = nil,
                      createdAt: Date = .distantPast, hint: Double = 0.5) -> ItemSnapshot {
        ItemSnapshot(id: id, kind: kind, topicID: topic, courseID: course, memory: .new, createdAt: createdAt,
                     difficultyHint: hint)
    }

    /// A review item with an explicit memory.
    static func item(_ memory: MemoryState, kind: ItemKind = .flashcard, topic: UUID? = nil, course: UUID? = nil)
        -> ItemSnapshot {
        ItemSnapshot(kind: kind, topicID: topic, courseID: course, memory: memory, createdAt: .distantPast)
    }

    static func settings(dailyMinutes: Int = 15, easyDays: [Int] = [], retention: Double = 0.9) -> AppSettings {
        var s = AppSettings()
        s.dailyMinutes = dailyMinutes
        s.easyDays = easyDays
        s.targetRetention = retention
        return s
    }
}
