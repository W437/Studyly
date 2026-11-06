import Foundation
import SwiftData

// Studying: building and running sessions, recording answers through the scheduler, the daily rollover
// (streak freezes, readiness on exam morning) and suspending items. Every mutation stamps with `touch` (synced
// models with `updatedAt`) or clears `syncedAt` (StudySession, DayRecord), then calls `save()`.
//
// A session from the view's side:
//
//     let built = app.buildSession(request)          // preview: entries, counts, weak spots
//     let session = app.startSession(built)          // the StudySession row; readiness before
//     var queue = SessionQueue(built)
//     // for each queue.current: show it, grade it, then
//     let outcome = app.recordReview(itemID: entry.itemID, rating: rating, score: score, answer: typed,
//                                    gradedBy: "cloud", durationMs: ms, sessionID: session.id)
//     queue.advance(rating: rating, memoryAfter: outcome!.after)
//     // when queue.isFinished (or the person stops):
//     let summary = app.finishSession(session)
extension AppModel {
    /// Deterministic fuzz and load balancing. Tests that compare exact intervals turn it off and back on.
    nonisolated(unsafe) static var schedulerFuzz = true

    var studyScheduler: StudyScheduler {
        StudyScheduler(settings: settings, calendar: calendar, fuzz: AppModel.schedulerFuzz)
    }

    // MARK: Building

    func sessionSpec(for request: SessionRequest) -> SessionSpec {
        var minutes = request.minutes
        if minutes == nil, request.kind == .daily || request.kind == .catchUp { minutes = dailyBudgetMinutes() }
        return SessionSpec(id: request.id, kind: request.kind, minutes: minutes, courseID: request.courseID,
                           topicID: request.topicID, examID: request.examID, confusionID: request.confusionID,
                           itemIDs: request.itemIDs)
    }

    /// The session for a request, built from the store as it is now. Cheap enough to call for a preview.
    func buildSession(_ request: SessionRequest) -> BuiltSession {
        let spec = sessionSpec(for: request)
        let items: [ItemSnapshot]
        if request.kind == .quickCheck || (request.kind == .practice && !request.itemIDs.isEmpty) {
            items = itemSnapshots(ids: request.itemIDs)
        } else {
            items = itemSnapshots()
        }
        return SessionBuilder(settings: settings, calendar: calendar, now: now).build(
            spec, items: items, exams: examSnapshots(), confusions: confusionSnapshots(), topicNames: topicNames())
    }

    /// Starts a session: inserts its StudySession (with readiness before, for the exam it counts toward) and
    /// readies the due-load cache the scheduler balances against.
    @discardableResult
    func startSession(_ built: BuiltSession) -> StudySession {
        let exam = trackedExam(for: built)
        let session = StudySession(kind: built.kind, startedAt: now, plannedSeconds: built.plannedSeconds,
                                   courseID: built.courseID, examID: exam?.id, confusionID: built.confusionID)
        session.readinessBefore = exam.map { readinessValue(of: $0) }
        context.insert(session)
        StudyRuntime.setLoad(currentDueLoad(), for: session.id)
        save()
        return session
    }

    /// Builds and starts in one go.
    @discardableResult
    func startSession(_ request: SessionRequest) -> (session: StudySession, built: BuiltSession) {
        let built = buildSession(request)
        return (startSession(built), built)
    }

    /// The exam a session's readiness before and after is for: its own exam, else the exam it serves (`SessionFocus`: the
    /// one Today's card names), else the soonest exam among the session's courses, else the soonest exam.
    func trackedExam(for built: BuiltSession) -> ExamSnapshot? {
        let exams = examSnapshots(upcomingOnly: true)
        if let id = built.examID, let exam = exams.first(where: { $0.id == id }) { return exam }
        if let id = SessionFocus.make(built, exams: exams, now: now, calendar: calendar).examID, let exam = exams.first(where: { $0.id == id }) { return exam }
        let courses = Set(built.entries.compactMap(\.courseID))
        return exams.first { $0.courseID.map(courses.contains) ?? false } ?? exams.first
    }

    // MARK: Answers

    /// Records one answer: schedules the item (FSRS with fuzz, load balancing, easy days and exam capping),
    /// writes the review log with the state before and after, and updates the session and today's record.
    /// `score` is the 0…1 grade for a graded answer (-1 when not graded); `answer` is what the person typed or
    /// the text of the option they picked (it lets swapped answers be spotted); `gradedBy` is "rules",
    /// "onDevice", "cloud", "person" or "self" (an answer the person marked themselves). Returns nil when the item no longer exists.
    ///
    /// An answer given elsewhere and applied later (a widget, the Watch) passes when it happened: `at` schedules it
    /// and dates its log, `dayKey` is the day it counts for (the day it was given, wherever the clock is now), and
    /// `reviewID` becomes the log's id, so applying the same answer twice records it once (nil the second time).
    @discardableResult
    func recordReview(itemID: UUID, rating: Rating, score: Double = -1, answer: String? = nil,
                      gradedBy: String = "person", durationMs: Int = 0, sessionID: UUID? = nil,
                      at answeredAt: Date? = nil, dayKey: String? = nil, reviewID: UUID? = nil) -> ReviewOutcome? {
        guard let item = item(itemID), item.deletedAt == nil else { return nil }
        if let reviewID {
            let existing = fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.id == reviewID }))
            guard existing.isEmpty else { return nil }
        }
        let now = answeredAt ?? self.now
        let before = item.memory
        let courseID = item.course?.id
        let scheduled = scheduledAnswer(to: item, rating: rating, at: now, sessionID: sessionID)
        let result = scheduled.result
        var load = scheduled.load
        let oldDay = before.state == .review ? before.due.map { calendar.dayNumber(for: $0) } : nil
        let newDay = result.memory.state == .review ? result.memory.due.map { calendar.dayNumber(for: $0) } : nil
        load.move(from: oldDay, to: newDay)
        StudyRuntime.setLoad(load, for: sessionID)

        item.memory = result.memory
        touch(item)
        let log = ReviewLog(id: reviewID ?? ModelID.make(), itemID: itemID, courseID: courseID, sessionID: sessionID,
                            reviewedAt: now, rating: rating, score: score, answer: answer, gradedBy: gradedBy,
                            durationMs: max(0, durationMs), before: before, after: result.memory,
                            elapsedDays: result.elapsedDays, scheduledDays: result.scheduledDays)
        context.insert(log)

        let seconds = Double(max(0, durationMs)) / 1000
        var firstInSession = false
        if let sessionID, let session = studySession(sessionID) {
            firstInSession = session.itemCount == 0
            session.itemCount += 1
            if log.wasCorrect { session.correctCount += 1 }
            session.activeSeconds += seconds
            session.syncedAt = nil
        }
        let record = dayRecord(key: dayKey ?? calendar.dayKey(for: now), date: now)
        record.itemsReviewed += 1
        record.studySeconds += seconds
        if firstInSession || record.sessions == 0 { record.sessions += 1 }
        record.syncedAt = nil

        if !log.wasCorrect {
            for confusion in fetch(FetchDescriptor<Confusion>(predicate: #Predicate { $0.deletedAt == nil }))
            where confusion.status == .open && confusion.itemIDs.contains(itemID) {
                confusion.missCount += 1
                confusion.lastSeenAt = now
                touch(confusion)
            }
        }
        save()
        return ReviewOutcome(itemID: itemID, rating: rating, before: before, after: result.memory,
                             wasCorrect: log.wasCorrect, scheduledDays: result.scheduledDays,
                             adjustment: result.adjustment, logID: log.id, recallBefore: result.retrievability)
    }

    /// What `recordReview` would return for this answer, with nothing written: the rating a session holds for its Undo window
    /// (`SessionRunner.PendingGrade`). The same scheduling, the same due load and a deterministic fuzz, so recording it with the same
    /// `at` and `reviewID` gives this very outcome. Nil when the item no longer exists.
    func previewReview(itemID: UUID, rating: Rating, score: Double = -1, sessionID: UUID? = nil, at answeredAt: Date? = nil,
                       reviewID: UUID) -> ReviewOutcome? {
        guard let item = item(itemID), item.deletedAt == nil else { return nil }
        let result = scheduledAnswer(to: item, rating: rating, at: answeredAt ?? now, sessionID: sessionID).result
        return ReviewOutcome(itemID: itemID, rating: rating, before: item.memory, after: result.memory,
                             wasCorrect: ReviewLog.wasCorrect(ratingRaw: rating.rawValue, score: score), scheduledDays: result.scheduledDays,
                             adjustment: result.adjustment, logID: reviewID, recallBefore: result.retrievability)
    }

    /// One answer through the scheduler, against the session's due load (the one piece `recordReview` and `previewReview` share).
    private func scheduledAnswer(to item: StudyItem, rating: Rating, at now: Date,
                                 sessionID: UUID?) -> (result: ScheduledReview, load: DueLoad) {
        let snapshot = ItemSnapshot(item, courseID: item.course?.id)
        let load = StudyRuntime.load(for: sessionID) ?? currentDueLoad()
        let result = studyScheduler.schedule(snapshot, rating: rating, at: now, load: load,
                                             exams: examSnapshots(upcomingOnly: true))
        return (result, load)
    }

    /// The rating for a 0…1 grade (see `Grading` for the thresholds: under 0.6 Again, under 0.8 Hard, else Good;
    /// 0.95+ answered quickly is Easy).
    nonisolated static func rating(forScore score: Double, kind: ItemKind? = nil, durationMs: Int? = nil) -> Rating {
        Grading.rating(forScore: score, kind: kind, durationMs: durationMs)
    }

    // MARK: Finishing

    /// Ends a session (idempotent): stamps the end, tops today's minutes up to the session's wall time (capped
    /// at twice the plan, so a session left open doesn't count), records readiness after, repairs a missed day
    /// when today was a double session, and returns the summary. `wallStart`: where the wall time counts from when it isn't the
    /// session's start (a session picked up after iOS closed the app counts only the time it was on screen).
    @discardableResult
    func finishSession(_ session: StudySession, wallStart: Date? = nil) -> SessionSummary {
        let now = self.now
        let sid: UUID? = session.id
        let logs = fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.sessionID == sid },
                                                    sortBy: [SortDescriptor(\.reviewedAt)]))
        if session.endedAt == nil {
            session.endedAt = now
            let wall = max(0, now.timeIntervalSince(wallStart ?? session.startedAt))
            let cap = max(session.plannedSeconds * 2, session.activeSeconds, 60)
            let extra = max(0, min(wall, cap) - session.activeSeconds)
            if extra > 0, !logs.isEmpty {
                let record = dayRecord(for: now)
                record.studySeconds += extra
                record.syncedAt = nil
                session.activeSeconds += extra
            }
            session.syncedAt = nil
        }

        var firstTry: [UUID: Bool] = [:]
        var newItems = Set<UUID>()
        for log in logs where firstTry[log.itemID] == nil {
            firstTry[log.itemID] = log.wasCorrect
            if log.stateBeforeRaw == CardState.new.rawValue { newItems.insert(log.itemID) }
        }
        let exam = session.examID.flatMap { id in examSnapshots().first { $0.id == id } }
        if let exam { session.readinessAfter = readinessValue(of: exam) }

        // Repair a missed day with a double session today.
        let engine = StreakEngine(calendar: calendar, now: now, dailyMinutes: settings.dailyMinutes)
        var repairedDay: Date?
        let todaySeconds = dayRecordSnapshot(for: now)?.studySeconds ?? 0
        if let day = engine.state(daySnapshots()).repairableDay, engine.repairQualifies(todaySeconds: todaySeconds) {
            let record = dayRecord(for: day.addingTimeInterval(12 * 3600))
            record.repaired = true
            record.syncedAt = nil
            repairedDay = day
        }
        save()
        StudyRuntime.end(session.id)

        let startOfToday = calendar.startOfDay(for: now)
        let earlierToday = fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.reviewedAt >= startOfToday }))
            .contains { $0.sessionID != session.id }
        let correct = firstTry.values.filter { $0 }.count

        // What the session did to the sky. The recall at each answer is worked out again from the log (whole days
        // since the previous review and the stability then), which is what the scheduler used, so "saved" here is
        // the "Saved it." the person saw.
        let fsrs = self.fsrs
        let relight = SkyEngine.relights(logs.map { log in
            let wasNew = log.stateBeforeRaw == CardState.new.rawValue
            let recall = wasNew ? 0 : fsrs.retrievability(elapsedDays: log.elapsedDays, stability: log.stabilityBefore)
            return SkyReview(itemID: log.itemID, wasCorrect: log.wasCorrect, wasNew: wasNew, recallBefore: recall,
                             isRight: log.ratingRaw >= Rating.good.rawValue)
        })
        noteSkyRelight(relight)

        return SessionSummary(sessionID: session.id, kind: session.kind, answers: logs.count,
                              itemsReviewed: firstTry.count, correctFirstTry: correct,
                              accuracy: firstTry.isEmpty ? 0 : Double(correct) / Double(firstTry.count),
                              newLearned: newItems.count, minutes: Int((session.activeSeconds / 60).rounded()),
                              examID: exam?.id, examTitle: exam?.title, readinessBefore: session.readinessBefore,
                              readinessAfter: session.readinessAfter, streak: streak(),
                              streakExtended: !logs.isEmpty && !earlierToday && logs.contains { $0.reviewedAt >= startOfToday },
                              repairedDay: repairedDay, stopNow: session.kind == .examEve,
                              starsRelit: relight.relit.count, starsSaved: relight.saved.count)
    }

    @discardableResult
    func finishSession(id: UUID) -> SessionSummary? {
        studySession(id).map { finishSession($0) }
    }

    // MARK: Rollover

    /// Run on launch and whenever the app comes to the foreground (idempotent): freezes yesterday when it is a
    /// single missed day and a freeze is held, and keeps readiness (and the coverage behind its projection) on the morning of each
    /// exam that has started (for calibrating projections against logged grades).
    func applyDailyRollover() {
        var changed = false
        let engine = StreakEngine(calendar: calendar, now: now, dailyMinutes: settings.dailyMinutes)
        if let day = engine.freezeToApply(daySnapshots()) {
            let record = dayRecord(for: day.addingTimeInterval(12 * 3600))
            if !record.frozen {
                record.frozen = true
                record.syncedAt = nil
                changed = true
            }
        }
        let cutoff = now
        let started = fetch(FetchDescriptor<Exam>(predicate: #Predicate {
            $0.deletedAt == nil && $0.readinessAtExam == nil && $0.date <= cutoff
        }))
        for exam in started where exam.createdAt < exam.date {
            let snapshot = ExamSnapshot(exam)
            let engineR = ReadinessEngine(fsrs: fsrs, calendar: calendar, now: now)
            let logs = ReadinessEngine.byItem(reviewSnapshots(courseID: exam.course?.id))
            exam.readinessAtExam = engineR.value(of: snapshot, items: itemSnapshots(in: exam.course), at: exam.date,
                                                 logsByItem: logs)
            // With how much of the material the questions reached, as it stands now (the first launch after the exam started): the
            // projection after the exam, and the line later projections are fitted to, are made from the two together.
            exam.coverageAtExam = coverage(for: exam)?.share
            touch(exam)
            changed = true
        }
        if changed { save() }

        // The game loop: the badges already earned are noted (so a session's are new), a day the app wasn't opened after is
        // settled with its own quests, today gets its quests, and a sky that another device's week lit says so.
        baselineBadges()
        if let sky = settleQuests().skyLit {
            if !settings.quietMode { router.toast("A new sky is lit", systemImage: "sparkles", tone: .success) }
            AppConfig.log.notice("sky lit at rollover: \(sky.rawValue, privacy: .public)")
        }
    }

    // MARK: Suspending

    func suspend(_ item: StudyItem) { setSuspended([item.id], true) }
    func unsuspend(_ item: StudyItem) { setSuspended([item.id], false) }

    /// Suspended items stay out of sessions and readiness until unsuspended; their memory is kept.
    func setSuspended(_ ids: [UUID], _ suspended: Bool) {
        var changed = false
        for id in ids {
            guard let item = item(id), item.deletedAt == nil else { continue }
            if suspended, item.status == .active {
                item.status = .suspended
                touch(item)
                changed = true
            } else if !suspended, item.status == .suspended {
                item.status = .active
                touch(item)
                changed = true
            }
        }
        if changed { save() }
    }

    // MARK: Helpers

    func studySession(_ id: UUID) -> StudySession? {
        fetch(FetchDescriptor<StudySession>(predicate: #Predicate { $0.id == id })).first
    }

    /// Today's (or `date`'s) record, created when missing.
    func dayRecord(for date: Date) -> DayRecord {
        dayRecord(key: calendar.dayKey(for: date), date: date)
    }

    /// The record for `key` ("yyyy-MM-dd"), created when missing; `date` is a moment of that day.
    func dayRecord(key: String, date: Date) -> DayRecord {
        if let existing = dayRecord(key: key) { return existing }
        let record = DayRecord(dayKey: key, day: calendar.startOfDay(for: date))
        context.insert(record)
        return record
    }

    /// Items due per day, for the scheduler's load balancing.
    func currentDueLoad() -> DueLoad {
        DueLoad(items: itemSnapshots(), grid: DayGrid(calendar: calendar, from: now, count: 400))
    }
}

/// Session-scoped caches: the due load a session's answers are balanced against, kept up to date answer by
/// answer instead of refetched. Keyed by session id; dropped when the session finishes.
@MainActor
enum StudyRuntime {
    private static var loads: [UUID: DueLoad] = [:]
    private static var order: [UUID] = []

    static func load(for id: UUID?) -> DueLoad? {
        guard let id else { return nil }
        return loads[id]
    }

    static func setLoad(_ load: DueLoad, for id: UUID?) {
        guard let id else { return }
        if loads[id] == nil {
            order.append(id)
            // Sessions abandoned without finishing: keep only the latest few.
            while order.count > 4 { loads[order.removeFirst()] = nil }
        }
        loads[id] = load
    }

    static func end(_ id: UUID) {
        loads[id] = nil
        order.removeAll { $0 == id }
    }
}
