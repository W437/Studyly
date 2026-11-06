import Foundation

/// A stretch of time the calendar says is taken. Its times only: a title or a place never gets this far, and nothing about it is stored or sent.
struct BusyBlock: Equatable, Sendable, Hashable {
    var start: Date
    var end: Date
}

/// What Cap may read of the calendar.
enum CalendarAccess: Equatable, Sendable {
    /// iOS hasn't asked yet: the card can.
    case notAsked
    case granted
    /// Refused, restricted or write-only: nothing is read and the card doesn't come back.
    case denied
}

/// "Monday looks busy": minutes taken off a long day and given to the days around it. No memory is written and no due date moves: it is minutes on the plan (`PlanBoost`: negative on
/// the busy day), and Undo takes it all back.
struct BusyMove: Equatable, Sendable, Hashable {
    struct Day: Equatable, Sendable, Hashable {
        var dayKey: String
        /// Days from today (0 is today).
        var offset: Int
        var date: Date
        var minutes: Int
    }

    var noticeID: String
    var examID: UUID
    var examTitle: String
    /// The long day, with the minutes that leave it.
    var busy: Day
    /// About how many hours it has in long blocks.
    var hours: Int
    /// The days that take them.
    var to: [Day]

    var minutes: Int { busy.minutes }
}

/// Finds a day this week that the calendar says is long, ahead of an exam, and works out where its minutes could go. Pure: the blocks come in as values.
///
/// A day is long when its long busy blocks come to at least 5 waking hours. A block is what's marked busy, joined with whatever follows it within 15 minutes (back-to-back classes are one
/// block) and cut to 08:00 to 22:00; it counts from 3 hours. So a lunch and two meetings never make a day look busy.
///
/// It looks 1 to 6 days ahead, at the first long day before an exam within 14 days, never an exam's day or its eve (they have their own rules). The day keeps 5 minutes. What leaves it goes to
/// the nearest two days that can take it (the day before first, then the day after): not today once the goal is met, not a lighter day, an exam's day or eve, or another long day, and always
/// before the exam; 10 more minutes a day at most. With fewer than 5 minutes to move, there is nothing to say.
struct BusyDayFinder: Sendable {
    static let longBlockHours = 3.0
    static let busyDayHours = 5.0
    static let wakingHours = (start: 8, end: 22)
    static let joinsWithinMinutes = 15.0
    static let lookAhead = 1...6
    /// How far off the exam may be.
    static let examWithinDays = 14
    /// A long day still has this many.
    static let keepsMinutes = 5
    static let smallestMove = 5
    static let maximumDays = 2
    static let maximumAddedPerDay = 10
    /// How far from the long day its minutes may go.
    static let reachDays = 3
    /// How many days ahead the calendar is read: as far as any day a move could touch.
    static var readDays: Int { lookAhead.upperBound + reachDays + 1 }

    var calendar: Calendar
    var now: Date
    var dailyMinutes: Int
    var easyDays: [Int] = []
    var goalMet = false

    static func noticeID(dayKey: String) -> String { "busy-\(dayKey)" }

    private func isEasy(_ day: Int) -> Bool { !easyDays.isEmpty && easyDays.contains(Calendar.weekday(dayNumber: day)) }

    /// How long a day's long blocks are, in hours.
    func busyHours(on day: Int, blocks: [BusyBlock]) -> Double {
        let start = calendar.startOfDay(dayNumber: day)
        guard let from = calendar.date(bySettingHour: Self.wakingHours.start, minute: 0, second: 0, of: start),
              let until = calendar.date(bySettingHour: Self.wakingHours.end, minute: 0, second: 0, of: start) else { return 0 }
        let clipped = blocks.compactMap { block -> BusyBlock? in
            let a = max(block.start, from), b = min(block.end, until)
            return a < b ? BusyBlock(start: a, end: b) : nil
        }.sorted { $0.start < $1.start }
        var merged: [BusyBlock] = []
        for block in clipped {
            if let last = merged.last, block.start.timeIntervalSince(last.end) <= Self.joinsWithinMinutes * 60 {
                merged[merged.count - 1].end = max(last.end, block.end)
            } else {
                merged.append(block)
            }
        }
        let long = merged.map { $0.end.timeIntervalSince($0.start) / 3600 }.filter { $0 >= Self.longBlockHours }
        return long.reduce(0, +)
    }

    /// The move for the first long day whose id `hidden` doesn't say is put away.
    func move(blocks: [BusyBlock], exams: [ExamSnapshot], hidden: (String) -> Bool = { _ in false }) -> BusyMove? {
        guard !blocks.isEmpty, dailyMinutes > 0 else { return nil }
        let today = calendar.dayNumber(for: now)
        let upcoming = exams.filter { $0.date > now }.sorted { $0.date < $1.date }
        let examDays = upcoming.map { calendar.dayNumber(for: $0.date) }
        let taken = Set(examDays + examDays.map { $0 - 1 })
        func isLong(_ day: Int) -> Bool { busyHours(on: day, blocks: blocks) >= Self.busyDayHours }
        for offset in Self.lookAhead {
            let day = today + offset
            guard !taken.contains(day), isLong(day),
                  let exam = upcoming.first(where: { calendar.dayNumber(for: $0.date) > day }) else { continue }
            let examDay = calendar.dayNumber(for: exam.date)
            guard examDay - today <= Self.examWithinDays else { continue }
            let goal = isEasy(day) ? Int((Double(dailyMinutes) * StudyScheduler.easyDayCapacity).rounded()) : dailyMinutes
            let spare = goal - Self.keepsMinutes
            guard spare >= Self.smallestMove else { continue }
            let key = calendar.dayKey(for: calendar.startOfDay(dayNumber: day))
            let id = Self.noticeID(dayKey: key)
            guard !hidden(id) else { continue }

            var takers: [Int] = []
            for distance in 1...Self.reachDays {
                for candidate in [day - distance, day + distance] where takers.count < Self.maximumDays {
                    guard candidate >= today, candidate < examDay, !taken.contains(candidate), !isEasy(candidate), !isLong(candidate) else { continue }
                    if candidate == today, goalMet { continue }
                    takers.append(candidate)
                }
            }
            guard !takers.isEmpty else { continue }
            let moved = min(spare, takers.count * Self.maximumAddedPerDay)
            guard moved >= Self.smallestMove else { continue }
            let hours = busyHours(on: day, blocks: blocks)
            let share = moved / takers.count
            let extra = moved % takers.count
            let to = takers.enumerated().map { index, number -> BusyMove.Day in
                let date = calendar.startOfDay(dayNumber: number)
                return BusyMove.Day(dayKey: calendar.dayKey(for: date), offset: number - today, date: date, minutes: share + (index < extra ? 1 : 0))
            }.sorted { $0.offset < $1.offset }
            return BusyMove(noticeID: id, examID: exam.id, examTitle: exam.title,
                            busy: BusyMove.Day(dayKey: key, offset: offset, date: calendar.startOfDay(dayNumber: day), minutes: moved),
                            hours: Int(hours.rounded()), to: to)
        }
        return nil
    }
}
