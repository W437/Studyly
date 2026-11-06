import Foundation

/// Which exam a built session is for, read from the session itself: each question carries the soonest upcoming exam that covers it
/// (`SessionEntry.examID`). An exam within a week that holds at least 20% of the session's planned seconds is its focus (the soonest
/// of them), so a small quiz two days away isn't hidden by a big midterm further off; otherwise the exam holding at least 40% (the
/// most seconds; a tie goes to the sooner exam). Today's card names it ("For Chem 110 Quiz"), the summary's ring follows it
/// (`AppModel.trackedExam`) and "about N% after today" is forecast for it. Pure.
struct SessionFocus: Sendable, Equatable {
    /// The exam the session serves; nil when no exam qualifies (or it has no questions for any exam).
    var examID: UUID?
    /// The topics the session works on for that exam: weak-spot topics first, then by planned seconds, only topics in the exam's
    /// scope. With no focus exam, every topic in the session in the same order.
    var topicIDs: [UUID]
    /// Due and exam-priority reviews for the focus exam (the whole session's without one).
    var dueCount: Int
    /// New questions for the focus exam (the whole session's without one).
    var newCount: Int
    /// Weak-spot questions for the focus exam (the whole session's without one).
    var weakCount: Int
    /// The other upcoming exams, each getting under 10% of the session's seconds (none at all included), soonest first.
    var otherExamIDs: [UUID]
    /// Planned seconds per exam.
    var secondsByExam: [UUID: Double]
    /// The session's planned seconds.
    var totalSeconds: Double

    /// The share of the session an exam needs to be its focus.
    static let focusShare = 0.4
    /// An exam this many days away or nearer needs only `nearShare` of the session.
    static let nearDays = SessionBuilder.examFocusDays
    static let nearShare = 0.2
    /// Under this share, an exam waits ("can wait until after…").
    static let minorShare = 0.1

    /// The focus exam's planned seconds (0 without one): "About 4 of the 15 minutes are for this exam."
    var focusSeconds: Double { examID.flatMap { secondsByExam[$0] } ?? 0 }

    /// `topicIDs` weakest first, by readiness for the focus exam (`AppModel.topicReadiness`), so the card's title and "Why these?" agree.
    /// Ties keep their order; a topic with no number yet comes after the ones that have one.
    func topicsWeakestFirst(readiness: [UUID: Double]) -> [UUID] {
        topicIDs.enumerated().sorted { a, b in
            switch (readiness[a.element], readiness[b.element]) {
            case let (x?, y?): return abs(x - y) > 1e-9 ? x < y : a.offset < b.offset
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// The session's focus. `exams`: the upcoming exams (their dates pick the near one and break ties, their scopes limit the topics).
    static func make(_ session: BuiltSession, exams: [ExamSnapshot], now: Date, calendar: Calendar) -> SessionFocus {
        let byID = Dictionary(exams.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seconds: [UUID: Double] = [:]
        var total = 0.0
        for entry in session.entries {
            total += entry.estimatedSeconds
            if let id = entry.examID { seconds[id, default: 0] += entry.estimatedSeconds }
        }

        func date(_ id: UUID) -> Date { byID[id]?.date ?? .distantFuture }
        // An exam this week with a real share of today, the soonest first (then the most seconds, then the id for a stable answer).
        let near = seconds.filter { id, share in
            guard let exam = byID[id], total > 0, share >= nearShare * total - 1e-9 else { return false }
            return (0...nearDays).contains(calendar.dayDistance(from: now, to: exam.date))
        }.min { a, b in
            if date(a.key) != date(b.key) { return date(a.key) < date(b.key) }
            if a.value != b.value { return a.value > b.value }
            return a.key.uuidString < b.key.uuidString
        }
        // Otherwise the most seconds, then the sooner exam (an exam not in the list counts as last), then the id.
        let best = seconds.max { a, b in
            if a.value != b.value { return a.value < b.value }
            if date(a.key) != date(b.key) { return date(a.key) > date(b.key) }
            return a.key.uuidString > b.key.uuidString
        }
        var focus = near?.key
        if focus == nil, let best, total > 0, best.value >= focusShare * total - 1e-9 { focus = best.key }

        let mine = session.entries.filter { focus == nil || $0.examID == focus }
        let exam = focus.flatMap { byID[$0] }
        // Each topic's course, from the session's own questions (for the scope check).
        var courseOf: [UUID: UUID] = [:]
        for entry in session.entries { if let t = entry.topicID, let c = entry.courseID { courseOf[t] = c } }
        func inScope(_ topic: UUID) -> Bool {
            guard focus != nil else { return true }
            guard let exam else { return mine.contains { $0.topicID == topic } }
            return exam.covers(topic: topic, course: courseOf[topic])
        }

        var topics: [UUID] = []
        func add(_ topic: UUID?) {
            guard let topic, !topics.contains(topic), inScope(topic) else { return }
            topics.append(topic)
        }
        // Weak spots first, in the session's order: a weak topic, or the topics of a mix-up's questions.
        let topicOfItem = Dictionary(session.entries.compactMap { e in e.topicID.map { (e.itemID, $0) } }, uniquingKeysWith: { a, _ in a })
        for spot in session.weakSpots {
            switch spot.source {
            case .topic: add(spot.id)
            case .confusion: for id in spot.itemIDs { add(topicOfItem[id]) }
            }
        }
        // Then by planned seconds (ties: the order they first come up).
        var topicSeconds: [UUID: Double] = [:]
        var firstSeen: [UUID: Int] = [:]
        for (i, entry) in mine.enumerated() {
            guard let t = entry.topicID else { continue }
            topicSeconds[t, default: 0] += entry.estimatedSeconds
            if firstSeen[t] == nil { firstSeen[t] = i }
        }
        let rest = topicSeconds.keys.sorted { a, b in
            topicSeconds[a]! != topicSeconds[b]! ? topicSeconds[a]! > topicSeconds[b]! : firstSeen[a]! < firstSeen[b]!
        }
        for t in rest { add(t) }

        let others = exams.filter { $0.id != focus }
            .filter { total <= 0 || (seconds[$0.id] ?? 0) < minorShare * total }
            .sorted { $0.date < $1.date }
            .map(\.id)
        return SessionFocus(examID: focus, topicIDs: topics,
                            dueCount: mine.filter { $0.reason == .due || $0.reason == .examPriority }.count,
                            newCount: mine.filter { $0.reason == .new }.count,
                            weakCount: mine.filter { $0.reason == .weak }.count,
                            otherExamIDs: others, secondsByExam: seconds, totalSeconds: total)
    }
}
