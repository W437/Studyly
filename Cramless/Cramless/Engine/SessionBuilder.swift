import Foundation

// MARK: - Values

/// What to build: the engine's version of `SessionRequest`.
struct SessionSpec: Sendable, Equatable {
    var id = UUID()
    var kind: SessionKind
    /// The time budget. Nil: the kind's default (daily, catch-up and practice: the daily goal; exam eve: 10;
    /// fix and quick check: no limit, every listed item).
    var minutes: Int?
    var courseID: UUID?
    var topicID: UUID?
    var examID: UUID?
    var confusionID: UUID?
    /// Explicit items (quick check, a fix drill, a hand-picked practice set), in order.
    var itemIDs: [UUID] = []
}

/// One question in a session.
struct SessionEntry: Sendable, Hashable, Identifiable {
    enum Reason: String, Sendable, Codable, CaseIterable {
        /// FSRS says it's due (or a learning step is due).
        case due
        /// Never studied: introduced today.
        case new
        /// Part of a weak spot: an open confusion or a weak topic.
        case weak
        /// Not due, but an upcoming exam needs it reviewed before exam day.
        case examPriority
        /// Extra practice in a practice session (not due, not weak).
        case practice
    }

    var itemID: UUID
    var reason: Reason
    var kind: ItemKind
    var topicID: UUID?
    var courseID: UUID?
    /// Expected seconds, from `ItemKind.typicalSeconds`; a new item counts twice (the first look and one
    /// learning step later in the session).
    var estimatedSeconds: Double
    /// 0 the first time in a session; 1, 2 for re-queued repeats.
    var attempt: Int = 0
    /// The soonest upcoming exam that covers the question (the exam an eve session is for): what `SessionFocus` reads. Set when the
    /// session is built; never stored.
    var examID: UUID? = nil

    var id: String { "\(itemID.uuidString)#\(attempt)" }
}

/// A named weak spot a session works on: an open confusion or a weak topic.
struct WeakSpot: Sendable, Hashable, Identifiable {
    enum Source: String, Sendable { case confusion, topic }
    var id: UUID
    var name: String
    var source: Source
    var courseID: UUID?
    /// This spot's items in the session.
    var itemIDs: [UUID]
}

/// A backlog too big for one day, spread over the next days.
struct CatchUpInfo: Sendable, Equatable {
    /// Items due now.
    var backlog: Int
    var backlogMinutes: Int
    /// Days at the current daily minutes to clear it.
    var daysToClear: Int
}

/// A built session: the ordered questions plus what the Today card and the session intro show.
struct BuiltSession: Sendable, Equatable, Identifiable {
    var id: UUID
    var kind: SessionKind
    var entries: [SessionEntry]
    var budgetSeconds: Double
    var courseID: UUID?
    var topicID: UUID?
    var examID: UUID?
    var confusionID: UUID?
    var weakSpots: [WeakSpot] = []
    /// Set when the daily session runs in catch-up mode.
    var catchUp: CatchUpInfo?
    /// Everything due right now, including what didn't fit in this session.
    var dueTotal: Int = 0
    /// Exam eve: after the last entry the session ends with "stop and sleep", no "keep going".
    var stopsAfter = false

    var plannedSeconds: Double { entries.reduce(0) { $0 + $1.estimatedSeconds } }
    var plannedMinutes: Int { entries.isEmpty ? 0 : max(1, Int((plannedSeconds / 60).rounded(.up))) }
    /// An eve session's minutes as its button and the plan's "Tonight" say them: rounded up, at most the eve's limit; 0 with nothing to review.
    var tonightMinutes: Int { min(plannedMinutes, SessionBuilder.examEveMinutes) }
    /// Due and exam-priority reviews ("18 reviews").
    var reviewCount: Int { entries.filter { $0.reason == .due || $0.reason == .examPriority }.count }
    var newCount: Int { entries.filter { $0.reason == .new }.count }
    var weakCount: Int { entries.filter { $0.reason == .weak }.count }
    var weakChips: [String] { weakSpots.map(\.name) }
    var isEmpty: Bool { entries.isEmpty }
}

// MARK: - Exams by course

/// Upcoming exams by course, soonest first, with their day counts worked out once (calendar calls are the slow
/// part of building a session over thousands of items).
struct ExamIndex: Sendable {
    private var byCourse: [UUID: [ExamSnapshot]] = [:]
    let all: [ExamSnapshot]
    /// Calendar days from now to each exam.
    private(set) var daysLeft: [UUID: Int] = [:]
    /// Each exam's day number.
    private(set) var dayNumber: [UUID: Int] = [:]

    init(_ exams: [ExamSnapshot], after now: Date, calendar: Calendar? = nil) {
        all = exams.filter { $0.date > now }.sorted { $0.date < $1.date }
        for exam in all {
            if let calendar {
                daysLeft[exam.id] = calendar.dayDistance(from: now, to: exam.date)
                dayNumber[exam.id] = calendar.dayNumber(for: exam.date)
            }
            guard let c = exam.courseID else { continue }
            byCourse[c, default: []].append(exam)
        }
    }

    func soonest(covering item: ItemSnapshot) -> ExamSnapshot? {
        guard let c = item.courseID else { return nil }
        return byCourse[c]?.first { $0.covers(item) }
    }

    func soonest(topic: UUID?, course: UUID?) -> ExamSnapshot? {
        guard let course else { return nil }
        return byCourse[course]?.first { $0.covers(topic: topic, course: course) }
    }
}

// MARK: - Builder

/// Builds study sessions from item snapshots. Pure: `now`, the calendar and the settings are inputs.
///
/// The daily session, in order of claim on the budget:
/// 1. learning steps due now (within 20 minutes);
/// 2. due reviews, items for an exam in the next 7 days first, then lowest recall;
/// 3. exam priority: not-due items whose recall on an exam 1–3 days away would be under the exam's target;
/// 4. new items: the exam plans' share for today (all new material in by ~3 days before each exam), at least
///    `budget / 3 min`, at most 40% of the budget;
/// 5. weak spots: up to two (open confusions first, then the weakest topics, nearer exams first), three items
///    each, about 15% of the budget.
/// A backlog over twice the daily budget switches to catch-up: no weak spots, new items only for an exam within
/// a week, reviews by exam proximity then lowest recall, the rest spread over the next days.
/// Then the order: the easiest due review opens (never the hardest item), new items are spread through the
/// first three quarters, and formats and topics are interleaved (no topic twice in a row when avoidable).
struct SessionBuilder: Sendable {
    var fsrs: FSRS
    var calendar: Calendar
    var now: Date
    var settings: AppSettings

    static let learnAhead: TimeInterval = 20 * 60
    static let examEveMinutes = 10
    /// Reviews for an exam this close go first.
    static let examFocusDays = 7
    /// Exam-priority items are pulled in this many days before the exam (the scheduler's capping window).
    static let examPriorityDays = 3
    static let weakSpotsPerSession = 2
    static let weakItemsPerSpot = 3
    /// A topic whose current recall is under this is a weak spot.
    static let weakTopicMastery = 0.7
    static let catchUpFactor = 2.0
    static let newShare = 0.4
    static let weakShare = 0.15
    static let interleaveWindow = 6

    init(fsrs: FSRS, calendar: Calendar, now: Date, settings: AppSettings) {
        self.fsrs = fsrs
        self.calendar = calendar
        self.now = now
        self.settings = settings
    }

    init(settings: AppSettings, calendar: Calendar, now: Date) {
        self.init(fsrs: FSRS(desiredRetention: settings.targetRetention), calendar: calendar, now: now,
                  settings: settings)
    }

    /// One item with what the builder needs to rank it, computed once.
    struct Candidate {
        var item: ItemSnapshot
        var recall: Double
        var exam: ExamSnapshot?
        var examDays: Int?
        var examRecall: Double?
        var cost: Double
    }

    func build(_ spec: SessionSpec, items: [ItemSnapshot], exams: [ExamSnapshot] = [],
               confusions: [ConfusionSnapshot] = [], topicNames: [UUID: String] = [:]) -> BuiltSession {
        var session = BuiltSession(id: spec.id, kind: spec.kind, entries: [], budgetSeconds: 0,
                                   courseID: spec.courseID, topicID: spec.topicID, examID: spec.examID,
                                   confusionID: spec.confusionID)
        let index = ExamIndex(exams, after: now, calendar: calendar)
        switch spec.kind {
        case .daily, .catchUp:
            buildDaily(spec, items: items, index: index, confusions: confusions, topicNames: topicNames,
                       into: &session)
        case .examEve:
            buildExamEve(spec, items: items, index: index, confusions: confusions, into: &session)
        case .fix:
            buildFix(spec, items: items, index: index, confusions: confusions, into: &session)
        case .quickCheck:
            buildExplicit(spec.itemIDs, items: items, index: index, into: &session)
        case .practice:
            buildPractice(spec, items: items, index: index, into: &session)
        }
        return session
    }

    // MARK: Helpers

    private var today: Int { calendar.dayNumber(for: now) }

    private var startOfTomorrow: Date {
        calendar.startOfDay(for: calendar.adding(days: 1, to: calendar.startOfDay(for: now).addingTimeInterval(12 * 3600)))
    }

    func cost(of item: ItemSnapshot) -> Double {
        item.isStudied ? item.kind.typicalSeconds : item.kind.typicalSeconds * 2
    }

    private func candidate(_ item: ItemSnapshot, index: ExamIndex) -> Candidate {
        let recall = fsrs.retrievability(of: item.memory, at: now)
        var c = Candidate(item: item, recall: recall, exam: nil, examDays: nil, examRecall: nil, cost: cost(of: item))
        if let exam = index.soonest(covering: item) {
            c.exam = exam
            c.examDays = index.daysLeft[exam.id] ?? calendar.dayDistance(from: now, to: exam.date)
            c.examRecall = examRecall(item.memory, on: exam.date)
        }
        return c
    }

    /// Recall on an exam's date, forecast in hours (`FSRS.forecastRecall`), as readiness counts it.
    func examRecall(_ memory: MemoryState, on date: Date) -> Double {
        guard memory.state != .new, let last = memory.lastReview, memory.stability > 0 else { return 0 }
        return fsrs.forecastRecall(stability: memory.stability, last: last, at: date)
    }

    private func entry(_ c: Candidate, _ reason: SessionEntry.Reason) -> SessionEntry {
        SessionEntry(itemID: c.item.id, reason: reason, kind: c.item.kind, topicID: c.item.topicID,
                     courseID: c.item.courseID, estimatedSeconds: c.cost, examID: c.exam?.id)
    }

    // MARK: Daily and catch-up

    private func buildDaily(_ spec: SessionSpec, items: [ItemSnapshot], index: ExamIndex,
                            confusions: [ConfusionSnapshot], topicNames: [UUID: String],
                            into session: inout BuiltSession) {
        let budget = Double(max(0, spec.minutes ?? settings.dailyMinutes)) * 60
        session.budgetSeconds = budget
        let tomorrow = startOfTomorrow
        let learnUntil = now.addingTimeInterval(Self.learnAhead)

        var learning: [Candidate] = []
        var due: [Candidate] = []
        var fresh: [Candidate] = []
        var notDue: [Candidate] = []
        var byTopic: [UUID: [Candidate]] = [:]
        var byID: [UUID: Candidate] = [:]
        for item in items where item.isActive {
            if let course = spec.courseID, item.courseID != course { continue }
            let c = candidate(item, index: index)
            byID[item.id] = c
            switch item.memory.state {
            case .new:
                fresh.append(c)
            case .learning, .relearning:
                if (item.memory.due ?? now) <= learnUntil { learning.append(c) }
            case .review:
                if (item.memory.due ?? now) < tomorrow { due.append(c) } else { notDue.append(c) }
            }
            if let t = item.topicID, item.isStudied { byTopic[t, default: []].append(c) }
        }

        let dueSeconds = (learning + due).reduce(0) { $0 + $1.cost }
        session.dueTotal = learning.count + due.count
        let catchUp = spec.kind == .catchUp || (budget > 0 && dueSeconds > Self.catchUpFactor * budget)
        if catchUp {
            session.catchUp = CatchUpInfo(backlog: session.dueTotal, backlogMinutes: Int((dueSeconds / 60).rounded(.up)),
                                          daysToClear: budget > 0 ? max(1, Int((dueSeconds / budget).rounded(.up))) : 0)
        }

        // Ranking.
        learning.sort { ($0.item.memory.due ?? now) < ($1.item.memory.due ?? now) }
        if catchUp {
            due.sort { a, b in
                let ea = a.examDays ?? Int.max, eb = b.examDays ?? Int.max
                return ea != eb ? ea < eb : a.recall < b.recall
            }
        } else {
            due.sort { a, b in
                let fa = (a.examDays ?? Int.max) <= Self.examFocusDays, fb = (b.examDays ?? Int.max) <= Self.examFocusDays
                return fa != fb ? fa : a.recall < b.recall
            }
        }
        // Not due before the exam (its due day is on or after the exam day) and under target on exam day.
        let examStarts = Dictionary(index.all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            .mapValues { calendar.startOfDay(for: $0.date) }
        let priority = notDue.filter { c in
            guard let exam = c.exam, let days = c.examDays, let r = c.examRecall, days > 0,
                  days <= Self.examPriorityDays, r < exam.target, let d = c.item.memory.due,
                  let examStart = examStarts[exam.id] else { return false }
            return d >= examStart
        }.sorted { a, b in
            a.examDays != b.examDays ? (a.examDays ?? 0) < (b.examDays ?? 0) : (a.examRecall ?? 0) < (b.examRecall ?? 0)
        }

        // New items: the exam plans' share for today first, then the default quota.
        fresh.sort { a, b in
            let da = a.exam?.date ?? .distantFuture, db = b.exam?.date ?? .distantFuture
            if da != db { return da < db }
            if a.item.createdAt != b.item.createdAt { return a.item.createdAt < b.item.createdAt }
            return a.item.difficultyHint < b.item.difficultyHint
        }
        // At least budget / 3 min new items (5 for 15 minutes); half that on an easy day; none in catch-up.
        let baseNew = max(3, Int(budget / 180))
        let defaultNew = catchUp ? 0 : (isEasyDay(today) ? max(1, baseNew / 2) : baseNew)
        var planned: [UUID: Int] = [:]
        var unseenByExam: [UUID: Int] = [:]
        for c in fresh { if let e = c.exam { unseenByExam[e.id, default: 0] += 1 } }
        for exam in index.all {
            guard let unseen = unseenByExam[exam.id], unseen > 0 else { continue }
            let days = index.daysLeft[exam.id] ?? calendar.dayDistance(from: now, to: exam.date)
            if catchUp && days > Self.examFocusDays { continue }
            planned[exam.id] = PlanMath.newItemsToday(unseen: unseen, today: today, examDay: today + days,
                                                      isEasyDay: isEasyDay)
        }
        var newPicks: [Candidate] = []
        var leftover = defaultNew
        var takenByExam: [UUID: Int] = [:]
        for c in fresh {
            if let e = c.exam, let quota = planned[e.id], takenByExam[e.id, default: 0] < quota {
                takenByExam[e.id, default: 0] += 1
                newPicks.append(c)
            }
        }
        let pickedNew = Set(newPicks.map(\.item.id))
        leftover = max(0, defaultNew - newPicks.count)
        for c in fresh where leftover > 0 && !pickedNew.contains(c.item.id) {
            newPicks.append(c)
            leftover -= 1
        }

        // Weak spots.
        let spots = catchUp ? [] : weakSpotCandidates(byID: byID, byTopic: byTopic, confusions: confusions,
                                                      topicNames: topicNames, index: index)

        // Fill the budget.
        var picked: [SessionEntry] = []
        var ids = Set<UUID>()
        var used = 0.0
        @discardableResult
        func take(_ c: Candidate, _ reason: SessionEntry.Reason, limit: Double) -> Bool {
            guard !ids.contains(c.item.id), used + c.cost <= limit else { return false }
            ids.insert(c.item.id)
            used += c.cost
            picked.append(entry(c, reason))
            return true
        }
        func fill(_ list: [Candidate], _ reason: SessionEntry.Reason, limit: Double) {
            var misses = 0
            for c in list {
                if take(c, reason, limit: limit) { misses = 0 } else if !ids.contains(c.item.id) {
                    misses += 1
                    if misses > 24 || used >= limit - 8 { break }
                }
            }
        }

        let newCost = newPicks.reduce(0) { $0 + $1.cost }
        let newReserve = min(newCost, budget * Self.newShare)
        let weakReserve = spots.isEmpty ? 0 : budget * Self.weakShare
        let reviewLimit = max(budget - newReserve - weakReserve, budget * 0.5)

        fill(learning, .due, limit: budget)
        fill(due, .due, limit: reviewLimit)
        fill(priority, .examPriority, limit: reviewLimit)
        fill(newPicks, .new, limit: budget - weakReserve)
        var chosenSpots: [WeakSpot] = []
        for spot in spots where chosenSpots.count < Self.weakSpotsPerSession {
            var inSession = spot.members.filter { ids.contains($0.item.id) }.map(\.item.id)
            var added = 0
            for c in spot.members where added < Self.weakItemsPerSpot {
                if take(c, .weak, limit: budget) {
                    inSession.append(c.item.id)
                    added += 1
                }
            }
            if !inSession.isEmpty {
                chosenSpots.append(WeakSpot(id: spot.id, name: spot.name, source: spot.source,
                                            courseID: spot.courseID, itemIDs: inSession))
            }
        }
        // Time left over: more due reviews, then more exam priority, then more of the chosen weak spots.
        fill(due, .due, limit: budget)
        fill(priority, .examPriority, limit: budget)
        if !catchUp {
            for (i, spot) in chosenSpots.enumerated() {
                guard let source = spots.first(where: { $0.id == spot.id }) else { continue }
                for c in source.members where take(c, .weak, limit: budget) {
                    chosenSpots[i].itemIDs.append(c.item.id)
                }
            }
        }
        session.weakSpots = chosenSpots
        session.entries = arrange(picked, byID: byID)
    }

    /// A weak spot before it is chosen: its name and its members, weakest first.
    struct SpotCandidate {
        var id: UUID
        var name: String
        var source: WeakSpot.Source
        var courseID: UUID?
        var members: [Candidate]
        var examDays: Int
        var mastery: Double
    }

    private func weakSpotCandidates(byID: [UUID: Candidate], byTopic: [UUID: [Candidate]],
                                    confusions: [ConfusionSnapshot], topicNames: [UUID: String],
                                    index: ExamIndex) -> [SpotCandidate] {
        var out: [SpotCandidate] = []
        var confusionTopics = Set<UUID>()
        for confusion in confusions where confusion.status == .open {
            let members = (confusion.itemIDs + confusion.fixItemIDs).compactMap { byID[$0] }
            guard !members.isEmpty else { continue }
            let sorted = members.sorted { $0.recall < $1.recall }
            let days = members.compactMap(\.examDays).min() ?? Int.max
            for m in members { if let t = m.item.topicID { confusionTopics.insert(t) } }
            out.append(SpotCandidate(id: confusion.id, name: confusion.name, source: .confusion,
                                     courseID: confusion.courseID, members: sorted, examDays: days,
                                     mastery: sorted.map(\.recall).reduce(0, +) / Double(sorted.count)))
        }
        out.sort { $0.examDays != $1.examDays ? $0.examDays < $1.examDays : $0.mastery < $1.mastery }
        var topics: [SpotCandidate] = []
        for (topic, members) in byTopic {
            let mastery = members.map(\.recall).reduce(0, +) / Double(members.count)
            guard mastery < Self.weakTopicMastery, let name = topicNames[topic] else { continue }
            let days = index.soonest(topic: topic, course: members.first?.item.courseID)
                .map { index.daysLeft[$0.id] ?? calendar.dayDistance(from: now, to: $0.date) } ?? Int.max
            topics.append(SpotCandidate(id: topic, name: name, source: .topic, courseID: members.first?.item.courseID,
                                        members: members.sorted { $0.recall < $1.recall }, examDays: days,
                                        mastery: mastery))
        }
        // Topics for an exam in the next month first (nearest exam first), then the weakest.
        topics.sort { a, b in
            let na = a.examDays <= 30, nb = b.examDays <= 30
            if na != nb { return na }
            if na && a.examDays != b.examDays { return a.examDays < b.examDays }
            if a.mastery != b.mastery { return a.mastery < b.mastery }
            return a.name < b.name
        }
        out += topics.filter { !confusionTopics.contains($0.id) }
        return out
    }

    private func isEasyDay(_ day: Int) -> Bool {
        !settings.easyDays.isEmpty && settings.easyDays.contains(Calendar.weekday(dayNumber: day))
    }

    // MARK: Exam eve

    private func buildExamEve(_ spec: SessionSpec, items: [ItemSnapshot], index: ExamIndex,
                              confusions: [ConfusionSnapshot], into session: inout BuiltSession) {
        session.stopsAfter = true
        let budget = Double(min(spec.minutes ?? Self.examEveMinutes, Self.examEveMinutes)) * 60
        session.budgetSeconds = budget
        let exam = index.all.first { $0.id == spec.examID } ?? index.all.first
        guard let exam else { return }
        session.examID = exam.id
        session.courseID = exam.courseID
        // Weak spots in scope: studied items under the exam's target on exam day, confusion items first.
        let confused = Set(confusions.filter { $0.status == .open }.flatMap(\.itemIDs))
        var weak: [Candidate] = []
        var byID: [UUID: Candidate] = [:]
        for item in items where item.isActive && item.isStudied && exam.covers(item) {
            var c = candidate(item, index: index)
            c.exam = exam
            c.examRecall = examRecall(item.memory, on: exam.date)
            byID[item.id] = c
            if confused.contains(item.id) || (c.examRecall ?? 0) < exam.target { weak.append(c) }
        }
        weak.sort { a, b in
            let ca = confused.contains(a.item.id), cb = confused.contains(b.item.id)
            return ca != cb ? ca : (a.examRecall ?? 0) < (b.examRecall ?? 0)
        }
        var used = 0.0
        var picked: [SessionEntry] = []
        for c in weak where used + c.cost <= budget {
            used += c.cost
            picked.append(entry(c, .weak))
        }
        session.dueTotal = weak.count
        session.entries = arrange(picked, byID: byID, openerKey: { $0.examRecall ?? $0.recall })
    }

    // MARK: Fix

    private func buildFix(_ spec: SessionSpec, items: [ItemSnapshot], index: ExamIndex,
                          confusions: [ConfusionSnapshot], into session: inout BuiltSession) {
        let byID = Dictionary(items.filter(\.isActive).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var order: [UUID] = spec.itemIDs
        if let confusion = confusions.first(where: { $0.id == spec.confusionID }) {
            session.courseID = session.courseID ?? confusion.courseID
            // The fix's own questions first (they teach the difference), then the items that were mixed up.
            order = confusion.fixItemIDs + confusion.itemIDs + spec.itemIDs
            session.weakSpots = [WeakSpot(id: confusion.id, name: confusion.name, source: .confusion,
                                          courseID: confusion.courseID, itemIDs: [])]
        }
        var seen = Set<UUID>()
        var fixEntries: [SessionEntry] = []
        for id in order where !seen.contains(id) {
            guard let item = byID[id] else { continue }
            seen.insert(id)
            fixEntries.append(entry(candidate(item, index: index), .weak))
        }
        if !session.weakSpots.isEmpty { session.weakSpots[0].itemIDs = fixEntries.map(\.itemID) }
        session.entries = fixEntries
        session.budgetSeconds = Double(spec.minutes ?? 0) * 60
    }

    // MARK: Quick check and practice

    private func buildExplicit(_ ids: [UUID], items: [ItemSnapshot], index: ExamIndex,
                               into session: inout BuiltSession) {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<UUID>()
        for id in ids where !seen.contains(id) {
            guard let item = byID[id], item.status != .rejected else { continue }
            seen.insert(id)
            let c = candidate(item, index: index)
            session.entries.append(entry(c, item.isStudied ? .due : .new))
        }
    }

    private func buildPractice(_ spec: SessionSpec, items: [ItemSnapshot], index: ExamIndex,
                               into session: inout BuiltSession) {
        let budget = Double(max(1, spec.minutes ?? settings.dailyMinutes)) * 60
        session.budgetSeconds = budget
        let explicit = Set(spec.itemIDs)
        let tomorrow = startOfTomorrow
        var due: [Candidate] = [], extra: [Candidate] = [], fresh: [Candidate] = []
        var byID: [UUID: Candidate] = [:]
        for item in items where item.isActive {
            if !explicit.isEmpty {
                guard explicit.contains(item.id) else { continue }
            } else {
                if let course = spec.courseID, item.courseID != course { continue }
                if let topic = spec.topicID, item.topicID != topic { continue }
            }
            let c = candidate(item, index: index)
            byID[item.id] = c
            switch item.memory.state {
            case .new: fresh.append(c)
            case .learning, .relearning: due.append(c)
            case .review: if (item.memory.due ?? now) < tomorrow { due.append(c) } else { extra.append(c) }
            }
        }
        session.dueTotal = due.count
        due.sort { $0.recall < $1.recall }
        extra.sort { $0.recall < $1.recall }
        fresh.sort { $0.item.createdAt != $1.item.createdAt ? $0.item.createdAt < $1.item.createdAt
            : $0.item.difficultyHint < $1.item.difficultyHint }
        var used = 0.0
        var picked: [SessionEntry] = []
        let newLimit = max(3, Int(budget / 180))
        var newTaken = 0
        for c in due where used + c.cost <= budget { used += c.cost; picked.append(entry(c, .due)) }
        for c in fresh where newTaken < newLimit && used + c.cost <= budget {
            used += c.cost
            newTaken += 1
            picked.append(entry(c, .new))
        }
        for c in extra where used + c.cost <= budget { used += c.cost; picked.append(entry(c, .practice)) }
        session.entries = arrange(picked, byID: byID)
    }

    // MARK: Order

    /// Opens with the easiest due review (never the hardest item), spreads new items through the first three
    /// quarters, then interleaves topics and formats.
    func arrange(_ picked: [SessionEntry], byID: [UUID: Candidate],
                 openerKey: ((Candidate) -> Double)? = nil) -> [SessionEntry] {
        guard picked.count > 1 else { return picked }
        let key = openerKey ?? { $0.recall }
        var rest = picked
        // The opener: the most recallable studied item (quick formats break ties); else the easiest new one.
        var openerIndex = 0
        var best: (Double, Double)? = nil
        for (i, e) in rest.enumerated() {
            guard let c = byID[e.itemID], c.item.isStudied else { continue }
            let score = (key(c), -e.kind.typicalSeconds)
            if best == nil || score > best! { best = score; openerIndex = i }
        }
        if best == nil {
            var easiest = Double.infinity
            for (i, e) in rest.enumerated() {
                let h = byID[e.itemID]?.item.difficultyHint ?? 0.5
                if h < easiest { easiest = h; openerIndex = i }
            }
        }
        let opener = rest.remove(at: openerIndex)

        // New items spread evenly through the first three quarters of the rest.
        let news = rest.filter { $0.reason == .new }
        var others = rest.filter { $0.reason != .new }
        if !news.isEmpty {
            let total = others.count + news.count
            let span = max(1.0, Double(total) * 0.75)
            for (k, e) in news.enumerated() {
                let pos = Int(((Double(k) + 0.5) * span / Double(news.count)).rounded(.down))
                others.insert(e, at: min(pos, others.count))
            }
        }
        return [opener] + Self.interleave(others, after: opener, window: Self.interleaveWindow)
    }

    /// Interleaving with a short look-ahead that keeps priority order where it can: the next entry is the first
    /// in the window whose topic differs from the previous entry's (better still, whose format differs too) and
    /// which leaves the rest arrangeable without a repeat (no topic holding more than half of what's left). When
    /// the window has no such entry, the first one further on is taken. The same topic twice in a row only
    /// happens when it can't be avoided.
    static func interleave(_ entries: [SessionEntry], after first: SessionEntry? = nil,
                           window: Int = 6) -> [SessionEntry] {
        var remaining = entries
        var out: [SessionEntry] = []
        out.reserveCapacity(entries.count)
        var counts: [UUID: Int] = [:]
        for e in entries { if let t = e.topicID { counts[t, default: 0] += 1 } }
        var last = first

        /// After taking `e`, can the rest follow it with no topic twice in a row?
        func feasible(_ e: SessionEntry) -> Bool {
            let rest = remaining.count - 1
            var own = 0
            var maxOther = 0
            for (t, c) in counts {
                if t == e.topicID { own = c - 1 } else { maxOther = max(maxOther, c) }
            }
            return own <= rest / 2 && maxOther <= (rest + 1) / 2
        }

        while !remaining.isEmpty {
            let limit = min(window, remaining.count)
            var pick = 0
            var best = -1
            for i in 0..<limit {
                let e = remaining[i]
                let sameTopic = last.map { e.topicID != nil && e.topicID == $0.topicID } ?? false
                let score = (sameTopic ? 0 : 4) + (feasible(e) ? 2 : 0) + (last.map { e.kind == $0.kind } ?? false ? 0 : 1)
                if score > best {
                    best = score
                    pick = i
                    if score == 7 { break }
                }
            }
            if best < 6, let j = remaining.indices.first(where: { i in
                let e = remaining[i]
                let sameTopic = last.map { e.topicID != nil && e.topicID == $0.topicID } ?? false
                return !sameTopic && feasible(e)
            }) {
                pick = j
            }
            let e = remaining.remove(at: pick)
            if let t = e.topicID {
                counts[t, default: 1] -= 1
                if counts[t] == 0 { counts[t] = nil }
            }
            out.append(e)
            last = e
        }
        return out
    }
}

// MARK: - The live queue

/// A session in progress: the entries left, and the re-queueing of answers that leave an item in a learning
/// step (an Again comes back `againGap` entries later; a passing step `stepGap` later). Hold it in the session
/// view's state; feed it each `ReviewOutcome`.
struct SessionQueue: Sendable, Equatable {
    private(set) var entries: [SessionEntry]
    private(set) var position = 0
    private var repeats: [UUID: Int] = [:]

    static let againGap = 3
    static let stepGap = 5
    /// Repeats of one item inside one session.
    static let maxRepeats = 2

    init(entries: [SessionEntry]) { self.entries = entries }
    init(_ session: BuiltSession) { self.init(entries: session.entries) }

    var current: SessionEntry? { position < entries.count ? entries[position] : nil }
    var upcoming: ArraySlice<SessionEntry> { entries[min(position + 1, entries.count)...] }
    var answered: Int { position }
    var count: Int { entries.count }
    var isFinished: Bool { position >= entries.count }
    var progress: Double { entries.isEmpty ? 1 : Double(position) / Double(entries.count) }

    /// Moves past the current entry after its answer. Re-queues it when `memoryAfter` is still in a (re)learning
    /// step and another entry is left to put between. Returns the index it was re-queued at.
    @discardableResult
    mutating func advance(rating: Rating, memoryAfter: MemoryState) -> Int? {
        guard let entry = current else { return nil }
        position += 1
        let stillLearning = memoryAfter.state == .learning || memoryAfter.state == .relearning
        let done = repeats[entry.itemID, default: 0]
        guard stillLearning, done < Self.maxRepeats, position < entries.count else { return nil }
        repeats[entry.itemID] = done + 1
        var again = entry
        again.attempt = entry.attempt + 1
        again.estimatedSeconds = entry.kind.typicalSeconds
        let gap = rating == .again ? Self.againGap : Self.stepGap
        let at = min(position + gap, entries.count)
        entries.insert(again, at: at)
        return at
    }

    /// Moves past the current entry without an answer.
    mutating func skip() {
        if position < entries.count { position += 1 }
    }
}
