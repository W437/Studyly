import Foundation

/// The App Group the app and the widget extension share.
enum CramlessAppGroup {
    static let identifier = "group.com.loopware.Capling"
}

/// What the widgets, the Live Activities and Siri read: a small, self-contained picture of the person's study
/// state. The app writes it after every change (`WidgetSync`, debounced behind `AppModel.save()`); the widget
/// extension, which can't see SwiftData or the engines, only ever reads it.
///
/// Rules:
/// - Plain values only (no model types), so the extension compiles it blind. Dates are absolute; "days left" and
///   "today" are worked out at display time with `rolled(to:calendar:)`, so a widget stays right across midnight
///   without the app running.
/// - Add fields with defaults; the app and the extension always ship together, but a snapshot written by the
///   previous build can still be on disk after an update.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Streak: Codable, Equatable, Sendable {
        /// Days in a row, today included once studied.
        var current: Int
        var studiedToday: Bool
        var freezes: Int
    }

    struct Today: Codable, Equatable, Sendable {
        /// The person's daily goal (settings).
        var goalMinutes: Int
        /// Minutes studied today so far.
        var doneMinutes: Int
        /// The size of today's session as built when the snapshot was written.
        var plannedMinutes: Int
        var reviews: Int
        var newItems: Int
        var weakSpots: Int
        /// Short names for today's weak spots ("Meiosis I vs II"), at most three.
        var weakChips: [String] = []
        /// There is something to study right now.
        var ready: Bool
        /// Set by `rolled(to:)` when the snapshot is from an earlier day: the counts are the last known ones, not
        /// today's, so views show the goal instead of them. Never stored.
        var carriedOver = false

        private enum CodingKeys: String, CodingKey {
            case goalMinutes, doneMinutes, plannedMinutes, reviews, newItems, weakSpots, weakChips, ready
        }

        init(goalMinutes: Int, doneMinutes: Int, plannedMinutes: Int, reviews: Int, newItems: Int, weakSpots: Int,
             weakChips: [String] = [], ready: Bool, carriedOver: Bool = false) {
            self.goalMinutes = goalMinutes
            self.doneMinutes = doneMinutes
            self.plannedMinutes = plannedMinutes
            self.reviews = reviews
            self.newItems = newItems
            self.weakSpots = weakSpots
            self.weakChips = weakChips
            self.ready = ready
            self.carriedOver = carriedOver
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            goalMinutes = try c.decodeIfPresent(Int.self, forKey: .goalMinutes) ?? 15
            doneMinutes = try c.decodeIfPresent(Int.self, forKey: .doneMinutes) ?? 0
            plannedMinutes = try c.decodeIfPresent(Int.self, forKey: .plannedMinutes) ?? 0
            reviews = try c.decodeIfPresent(Int.self, forKey: .reviews) ?? 0
            newItems = try c.decodeIfPresent(Int.self, forKey: .newItems) ?? 0
            weakSpots = try c.decodeIfPresent(Int.self, forKey: .weakSpots) ?? 0
            weakChips = try c.decodeIfPresent([String].self, forKey: .weakChips) ?? []
            ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
        }

        /// The minutes to show for today's session: the planned size, or the goal when nothing is planned.
        var sessionMinutes: Int { plannedMinutes > 0 && !carriedOver ? plannedMinutes : goalMinutes }

        /// Today's counts are known (written today) and there is at least one.
        var hasCounts: Bool { !carriedOver && (reviews + newItems + weakSpots) > 0 }
    }

    struct Exam: Codable, Equatable, Sendable, Identifiable {
        var id: UUID
        var title: String
        var courseName: String
        var color: CourseColor
        var date: Date
        /// Predicted recall over the exam's scope, 0…1.
        var readiness: Double
        /// Change in readiness over the last 7 days, -1…1.
        var delta: Double

        /// An exam stops being "upcoming" a few hours after it starts (exams carry a start time, not an end).
        func isOver(at date: Date) -> Bool { date >= self.date.addingTimeInterval(WidgetSnapshot.examLength) }

        /// The course name when it's short enough to read on a Lock Screen, else the exam title.
        var shortName: String { courseName.isEmpty ? title : courseName }
    }

    struct Course: Codable, Equatable, Sendable, Identifiable {
        var id: UUID
        var name: String
        var color: CourseColor
    }

    /// Bumped only for a change old readers can't decode; they then show their empty state until the app writes.
    var version = WidgetSnapshot.currentVersion
    var generatedAt: Date
    var streak: Streak
    var today: Today
    /// Upcoming exams, soonest first, at most three. The first one is the next exam.
    var exams: [Exam]
    var courses: [Course] = []
    /// Quiet mode is on: the Today widget says nothing about the streak (a Streak widget someone placed stays as it is). Optional, so a
    /// snapshot written before it existed still reads.
    var quiet: Bool? = nil

    static let currentVersion = 1
    static let maxExams = 3
    /// How long after its start time an exam still counts as upcoming.
    static let examLength: TimeInterval = 3 * 3600

    var nextExam: Exam? { exams.first }

    /// What the Today widget reads: with Quiet mode on, no streak to show.
    var forTodayWidget: WidgetSnapshot {
        guard quiet == true else { return self }
        var snapshot = self
        snapshot.streak.current = 0
        return snapshot
    }

    func color(ofCourseNamed name: String) -> CourseColor? {
        courses.first { $0.name == name }?.color
    }
}

// MARK: - Reading the snapshot at a later time

extension WidgetSnapshot {
    /// The snapshot as it should read at `date`, which may be days after it was written: exams that are over are
    /// dropped, and on a later day "today" starts empty and the streak is carried forward the way the app would
    /// count it (a missed day uses a freeze when one is left, else the streak ends). This is the widget's best guess
    /// until the app runs again and writes the real numbers.
    func rolled(to date: Date, calendar: Calendar) -> WidgetSnapshot {
        var s = self
        s.exams = exams.filter { !$0.isOver(at: date) }
        let days = WidgetCalendar.days(from: generatedAt, to: date, calendar: calendar)
        guard days > 0 else { return s }
        // Days with no known study between the snapshot's day and today: the snapshot's own day unless it was
        // studied, plus every whole day in between.
        let missed = days - (streak.studiedToday ? 1 : 0)
        if missed > 0 {
            if missed <= streak.freezes {
                s.streak.freezes -= missed
            } else {
                s.streak.current = 0
            }
        }
        s.streak.studiedToday = false
        s.today.doneMinutes = 0
        s.today.ready = today.ready || today.reviews + today.newItems > 0
        s.today.carriedOver = true
        return s
    }

    /// Days from `date`'s day to the exam's day: 0 on the day, 1 the day before.
    func daysLeft(to exam: Exam, from date: Date, calendar: Calendar) -> Int {
        WidgetCalendar.days(from: date, to: exam.date, calendar: calendar)
    }
}

/// Day arithmetic the extension can use (the app's `Calendar.dayDistance` lives in Model/, which the extension
/// can't see). Same rule: whole calendar days, so a 23- or 25-hour day still counts as one.
enum WidgetCalendar {
    static func days(from a: Date, to b: Date, calendar: Calendar) -> Int {
        let ca = calendar.dateComponents([.year, .month, .day], from: a)
        let cb = calendar.dateComponents([.year, .month, .day], from: b)
        guard let da = utc.date(from: ca), let db = utc.date(from: cb) else { return 0 }
        return Int((db.timeIntervalSince(da) / 86_400).rounded())
    }

    /// The start of the day after `date`.
    static func nextMidnight(after date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}

// MARK: - Storage

/// Reads and writes the snapshot as `widget-snapshot.json` in the App Group container.
///
/// The container can be missing: `scripts/xc.sh` builds with `CODE_SIGNING_ALLOWED=NO`, so simulator builds carry no
/// entitlements and may get no App Group container, and a device build whose provisioning profile lacks the group
/// gets none either. Then `directory` is nil, `write` does nothing and returns false, and `read` returns nil: the
/// app works as usual and the widgets show their empty state. Nothing here throws or traps.
struct WidgetSnapshotStore: Sendable {
    static let fileName = "widget-snapshot.json"

    /// The folder the snapshot lives in, or nil when there is none (see above).
    let directory: URL?

    /// The App Group container (nil when unavailable).
    static let shared = WidgetSnapshotStore(
        directory: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CramlessAppGroup.identifier))

    var fileURL: URL? { directory?.appending(path: Self.fileName, directoryHint: .notDirectory) }

    var isAvailable: Bool { directory != nil }

    func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let snapshot = try? Self.decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.version <= WidgetSnapshot.currentVersion else { return nil }
        return snapshot
    }

    /// Writes atomically (a reader never sees half a file), readable after first unlock so Lock Screen widgets
    /// can read it while the iPhone is locked. Returns false when there's no container or the write failed.
    @discardableResult
    func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = fileURL, let data = try? Self.encoder.encode(snapshot) else { return false }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    /// Removes the snapshot (account deletion, sign-out of a shared device).
    func remove() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

// MARK: - Sample

extension WidgetSnapshot {
    /// Believable values for widget placeholders, the widget gallery and the render tests: the demo world's
    /// Bio 101 midterm in 23 days at 64%, 15 minutes planned, 18 reviews, 6 new, 2 weak spots, a 12-day streak.
    static func sample(now: Date = .now, calendar: Calendar = .current) -> WidgetSnapshot {
        func day(_ offset: Int, hour: Int) -> Date {
            let start = calendar.startOfDay(for: now)
            let d = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: d) ?? d
        }
        let bio = Course(id: SampleID.bio, name: "Bio 101", color: .sky)
        let chem = Course(id: SampleID.chem, name: "Chem 110", color: .tangerine)
        let psych = Course(id: SampleID.psych, name: "AP Psychology", color: .mint)
        return WidgetSnapshot(
            generatedAt: now,
            streak: Streak(current: 12, studiedToday: false, freezes: 1),
            today: Today(goalMinutes: 15, doneMinutes: 0, plannedMinutes: 15, reviews: 18, newItems: 6, weakSpots: 2,
                         weakChips: ["Meiosis I vs II", "Chromosome number"], ready: true),
            exams: [
                Exam(id: SampleID.bioMidterm, title: "Bio 101 Midterm", courseName: bio.name, color: bio.color,
                     date: day(23, hour: 9), readiness: 0.64, delta: 0.05),
                Exam(id: SampleID.chemFinal, title: "Chem 110 Final", courseName: chem.name, color: chem.color,
                     date: day(37, hour: 10), readiness: 0.41, delta: 0.03),
                Exam(id: SampleID.psychExam, title: "AP Psych Exam", courseName: psych.name, color: psych.color,
                     date: day(196, hour: 8), readiness: 0.22, delta: 0.01),
            ],
            courses: [bio, chem, psych])
    }

    enum SampleID {
        static let bio = UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000001")!
        static let chem = UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000002")!
        static let psych = UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000003")!
        static let bioMidterm = UUID(uuidString: "C0FFEE00-0000-4000-8000-0000000000E1")!
        static let chemFinal = UUID(uuidString: "C0FFEE00-0000-4000-8000-0000000000E2")!
        static let psychExam = UUID(uuidString: "C0FFEE00-0000-4000-8000-0000000000E3")!
    }
}
