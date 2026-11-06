import Foundation

/// Where a question came from, for "From Lecture 3".
struct FadeSource: Equatable, Sendable {
    var id: UUID
    var name: String
}

/// What "Fix my week" would do: a few more minutes on a few days, for the questions that would otherwise be dim on exam day. No memory
/// is written and no due date moves: it is minutes on the plan (`PlanBoost`), and the questions come first in those days' sessions
/// (`SessionSpec.focusItemIDs`).
struct FadeRescue: Equatable, Sendable, Hashable {
    /// One day of it.
    struct Day: Equatable, Sendable, Hashable {
        var dayKey: String
        /// Days from today (0 is today).
        var offset: Int
        var date: Date
        var itemIDs: [UUID]
    }

    /// Where most of the questions came from.
    enum Origin: Equatable, Sendable, Hashable {
        /// "From Lecture 3."
        case source(String)
        /// "Mostly Meiosis."
        case topic(String)

        var name: String {
            switch self {
            case .source(let name), .topic(let name): name
            }
        }
    }

    var noticeID: String
    var examID: UUID
    var examTitle: String
    var examDate: Date
    var daysLeft: Int
    /// Questions that will be under the dim line on exam day.
    var dimCount: Int
    /// Their share of the exam's questions.
    var dimShare: Double
    var days: [Day]
    /// The same on each day: the time the questions take, rounded up to whole minutes.
    var minutesPerDay: Int
    /// How many are over the line on exam day after their review.
    var kept: Int
    var origin: Origin?

    var itemIDs: [UUID] { days.flatMap(\.itemIDs) }
}

/// Finds overdue questions that will be under the sky's dim line on exam day (`ReviewOutcome.fadingRecall`), 3 to 14 days before an
/// exam, and works out what a few more minutes would keep. This rarely fires for someone who keeps up, by design: questions come due
/// long before they fall that low, and the last days before an exam pull in anything under its target. It is for a break, or a backlog
/// bigger than the daily goal.
///
/// A question counts when it is in the exam's scope, studied, overdue, under the line on the exam's date and not in today's session. So one
/// only on a finished exam never counts: only exams still to come are looked at.
/// It also has to be out of the plan's reach. The daily sessions ahead work through the overdue questions (the nearest exam's first, then the
/// lowest recall, as a catch-up session does), so a backlog that clears before the exam never goes dim and the card would be false beside
/// "cleared in 3 days". Only what is left after the days before the exam (`dailySeconds` each, half on a lighter day, the eve's own session on the eve) counts.
/// With at least 5, the rescue takes today (unless the goal is met), then the next days that aren't lighter days, an exam or an
/// exam's eve; 3 days at most, 10 minutes each at most, the dimmest questions first. It is offered only if at least 5 of them would be
/// over the line on exam day after their review (`ExpectedReview`).
struct FadeFinder: Sendable {
    static let examWindow = 3...14
    static let minimumQuestions = 5
    static let maximumDays = 3
    static let maximumMinutesPerDay = 10
    /// A name for the group needs this share of its questions.
    static let originShare = 0.6

    var fsrs: FSRS
    var calendar: Calendar
    var now: Date
    var easyDays: [Int] = []
    var goalMet = false
    /// The daily goal, in seconds: how far the sessions ahead reach.
    var dailySeconds: Double = 0

    private func isEasy(_ day: Int) -> Bool {
        !easyDays.isEmpty && easyDays.contains(Calendar.weekday(dayNumber: day))
    }

    /// The rescue a card would offer: for the exam with the most at stake (the card's own rank) among those with enough questions going
    /// dim and whose id `hidden` doesn't say is put away. One a day is all the deck can use, so the others aren't worked out.
    func rescues(items: [ItemSnapshot], exams: [ExamSnapshot], todayItems: Set<UUID>, boosted: Set<UUID>,
                 sources: [UUID: FadeSource], topicNames: [UUID: String], hidden: (String) -> Bool = { _ in false }) -> [FadeRescue] {
        let upcoming = exams.filter { $0.date > now }
        let inWindow = upcoming.filter { Self.examWindow.contains(calendar.dayDistance(from: now, to: $0.date)) }
        guard !inWindow.isEmpty else { return [] }
        // Overdue studied questions, once.
        let overdue = items.filter { item in
            guard item.isActive, item.isStudied, let due = item.memory.due, due < now else { return false }
            return !todayItems.contains(item.id) && !boosted.contains(item.id)
        }
        guard overdue.count >= Self.minimumQuestions else { return [] }
        let today = calendar.dayNumber(for: now)
        let key = calendar.dayKey(for: now)
        let examDays = upcoming.map { calendar.dayNumber(for: $0.date) }
        let busy = Set(examDays + examDays.map { $0 - 1 })
        let queue = sessionOrder(overdue, exams: upcoming)
        // Who's going dim, per exam.
        var going: [(exam: ExamSnapshot, dim: [(item: ItemSnapshot, recall: Double)], share: Double, days: Int)] = []
        for exam in inWindow where !hidden(Self.noticeID(exam, dayKey: key)) {
            var dim: [(item: ItemSnapshot, recall: Double)] = []
            for item in outOfReach(queue, before: exam, today: today) where exam.covers(item) {
                guard let last = item.memory.lastReview else { continue }
                let recall = fsrs.forecastRecall(stability: item.memory.stability, last: last, at: exam.date)
                if recall < ReviewOutcome.fadingRecall { dim.append((item, recall)) }
            }
            guard dim.count >= Self.minimumQuestions else { continue }
            let scope = items.reduce(0) { $0 + ($1.isActive && exam.covers($1) ? 1 : 0) }
            going.append((exam, dim, Double(dim.count) / Double(max(1, scope)), calendar.dayNumber(for: exam.date) - today))
        }
        let ordered = going.sorted { a, b in
            let ra = NoticeEngine.Rank.fading(dimShare: a.share, daysLeft: a.days), rb = NoticeEngine.Rank.fading(dimShare: b.share, daysLeft: b.days)
            return ra != rb ? ra > rb : a.exam.id < b.exam.id
        }
        for entry in ordered {
            if let rescue = rescue(for: entry.exam, dim: entry.dim, share: entry.share, today: today, busy: busy, sources: sources, topicNames: topicNames) {
                return [rescue]
            }
        }
        return []
    }

    /// The overdue questions in the order sessions reach them: the nearest exam's first, then the lowest recall.
    private func sessionOrder(_ overdue: [ItemSnapshot], exams: [ExamSnapshot]) -> [ItemSnapshot] {
        guard dailySeconds > 0 else { return overdue }
        let index = ExamIndex(exams, after: now, calendar: calendar)
        return overdue.map { item in
            (item: item, days: index.soonest(covering: item).flatMap { index.daysLeft[$0.id] } ?? Int.max,
             recall: fsrs.retrievability(of: item.memory, at: now))
        }.sorted { a, b in
            if a.days != b.days { return a.days < b.days }
            return a.recall != b.recall ? a.recall < b.recall : a.item.id < b.item.id
        }.map(\.item)
    }

    /// What is left of the queue after the sessions from tomorrow to the exam's eve. Today's are already out of it.
    private func outOfReach(_ queue: [ItemSnapshot], before exam: ExamSnapshot, today: Int) -> ArraySlice<ItemSnapshot> {
        guard dailySeconds > 0 else { return queue[...] }
        let examDay = calendar.dayNumber(for: exam.date)
        var left = 0.0
        for day in stride(from: today + 1, to: examDay, by: 1) {
            if day == examDay - 1 {
                left += min(dailySeconds, PlanBuilder.examEveSeconds)
            } else {
                left += isEasy(day) ? dailySeconds * StudyScheduler.easyDayCapacity : dailySeconds
            }
        }
        var reached = 0
        for item in queue {
            left -= item.kind.typicalSeconds
            if left < 0 { break }
            reached += 1
        }
        return queue[reached...]
    }

    static func noticeID(_ exam: ExamSnapshot, dayKey: String) -> String { "fade-\(exam.id.uuidString)-\(dayKey)" }

    private func rescue(for exam: ExamSnapshot, dim unsorted: [(item: ItemSnapshot, recall: Double)], share: Double, today: Int, busy: Set<Int>,
                        sources: [UUID: FadeSource], topicNames: [UUID: String]) -> FadeRescue? {
        let dim = unsorted.sorted { $0.recall != $1.recall ? $0.recall < $1.recall : $0.item.id < $1.item.id }

        // The days it can use.
        let examDay = calendar.dayNumber(for: exam.date)
        var open: [Int] = []
        for day in today..<examDay where open.count < Self.maximumDays {
            if day == today, goalMet { continue }
            if isEasy(day) || busy.contains(day) { continue }
            open.append(day)
        }
        guard !open.isEmpty else { return nil }

        // As few days as the questions need, the same minutes on each.
        let total = dim.reduce(0.0) { $0 + $1.item.kind.typicalSeconds }
        let limit = Double(Self.maximumMinutesPerDay * 60)
        let used = min(open.count, max(1, Int((total / limit).rounded(.up))))
        let minutes = min(Self.maximumMinutesPerDay, max(1, Int((total / Double(used) / 60).rounded(.up))))
        let dayKeys = open.prefix(used)
        var queue = dim[...]
        var days: [FadeRescue.Day] = []
        var kept = 0
        for day in dayKeys {
            let start = calendar.startOfDay(dayNumber: day)
            var when = start.addingTimeInterval(PlanBuilder.reviewHour * 3600)
            if day == today { when = max(now, when) }
            var seconds = 0.0
            var ids: [UUID] = []
            while let next = queue.first, seconds + next.item.kind.typicalSeconds <= Double(minutes * 60) {
                queue = queue.dropFirst()
                seconds += next.item.kind.typicalSeconds
                ids.append(next.item.id)
                if let step = fsrs.expectedReview(of: next.item.memory, at: when),
                   step.recall(at: exam.date, fsrs: fsrs) >= ReviewOutcome.fadingRecall {
                    kept += 1
                }
            }
            if !ids.isEmpty {
                days.append(.init(dayKey: calendar.dayKey(for: start.addingTimeInterval(12 * 3600)), offset: day - today, date: start, itemIDs: ids))
            }
        }
        guard kept >= Self.minimumQuestions else { return nil }
        return FadeRescue(noticeID: Self.noticeID(exam, dayKey: calendar.dayKey(for: now)), examID: exam.id, examTitle: exam.title,
                          examDate: exam.date, daysLeft: examDay - today, dimCount: dim.count, dimShare: share, days: days, minutesPerDay: minutes,
                          kept: kept, origin: origin(of: dim.map(\.item), sources: sources, topicNames: topicNames))
    }

    /// "From Lecture 3" when most of them share a source, else "Mostly Meiosis" when most share a topic, else nothing.
    private func origin(of items: [ItemSnapshot], sources: [UUID: FadeSource], topicNames: [UUID: String]) -> FadeRescue.Origin? {
        let needed = Self.originShare * Double(items.count)
        func top<K: Hashable>(_ keys: [K]) -> K? {
            var counts: [K: Int] = [:]
            for key in keys { counts[key, default: 0] += 1 }
            return counts.filter { Double($0.value) >= needed }.max { $0.value < $1.value }?.key
        }
        if let id = top(items.compactMap { sources[$0.id]?.id }), let name = items.lazy.compactMap({ sources[$0.id] }).first(where: { $0.id == id })?.name {
            return .source(name)
        }
        if let id = top(items.compactMap(\.topicID)), let name = topicNames[id] { return .topic(name) }
        return nil
    }
}
