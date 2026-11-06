import Foundation
import SwiftData

// What the Study screens need beyond the engine's own API (`AppModel+Study`, `AppModel+Insights`): previews of
// each rating's next interval, the confusion workflow (adopt a mix-up found in a session, snooze it, fix it), and
// the onboarding steps' exam and quick check. Mutations stamp with `touch` and end in `save()`, like every other
// AppModel extension; the read helpers fetch once per call.
extension AppModel {

    // MARK: - Rating previews

    /// What each rating would schedule for an item right now, in days (fractional for a learning step: 10
    /// minutes is 0.0069). Nothing is written. Pass the session id so the preview uses the session's due load.
    func intervalPreview(itemID: UUID, sessionID: UUID? = nil) -> [Rating: Double] {
        guard let item = item(itemID), item.deletedAt == nil else { return [:] }
        let snapshot = ItemSnapshot(item, courseID: item.course?.id)
        let load = StudyRuntime.load(for: sessionID) ?? currentDueLoad()
        let exams = examSnapshots(upcomingOnly: true)
        let scheduler = studyScheduler
        var out: [Rating: Double] = [:]
        for rating in Rating.allCases {
            out[rating] = scheduler.schedule(snapshot, rating: rating, at: now, load: load, exams: exams).scheduledDays
        }
        return out
    }

    // MARK: - Today

    /// A finished session of this kind today (with at least one answer), optionally for one exam.
    func finishedSessionToday(kind: SessionKind, examID: UUID? = nil) -> Bool {
        let start = calendar.startOfDay(for: now)
        let raw = kind.rawValue
        return fetch(FetchDescriptor<StudySession>(predicate: #Predicate { $0.startedAt >= start && $0.kindRaw == raw }))
            .contains { $0.endedAt != nil && $0.itemCount > 0 && (examID == nil || $0.examID == examID) }
    }

    /// Tonight's session is done, for any of the exams sharing the evening (it is one session, whichever page started it).
    func eveSessionDone(_ summary: TodaySummary) -> Bool {
        summary.examEveExamIDs.contains { finishedSessionToday(kind: .examEve, examID: $0) }
    }

    /// Answers recorded today.
    func answersToday() -> Int {
        dayRecordSnapshot(for: now)?.itemsReviewed ?? 0
    }

    /// Any question to study at all (an active item in a live course).
    func hasActiveItems() -> Bool {
        let active = ItemStatus.active.rawValue
        var d = FetchDescriptor<StudyItem>(predicate: #Predicate { $0.deletedAt == nil && $0.statusRaw == active })
        d.fetchLimit = 8
        return fetch(d).contains { $0.course?.deletedAt == nil }
    }

    /// Cap's note on Today: the open confusion with the most misses (most recent first on a tie), unless the
    /// person said "Later" to it today.
    func todayConfusionNote() -> ConfusionNote? {
        openConfusionNotes().first { !isConfusionSnoozed($0.id) }
    }

    /// Open mix-ups in live courses, the most missed first (the most recent first on a tie), each with its recent answers: what the
    /// mix-up cards are made from.
    func openConfusionNotes(limit: Int = 5) -> [ConfusionNote] {
        openConfusions().prefix(limit).map(confusionNote)
    }

    func openConfusions() -> [Confusion] {
        fetch(FetchDescriptor<Confusion>(predicate: #Predicate { $0.deletedAt == nil }))
            .filter { $0.status == .open && $0.course?.deletedAt == nil }
            .sorted { ($0.missCount, $0.lastSeenAt) > ($1.missCount, $1.lastSeenAt) }
    }

    func confusionNote(_ confusion: Confusion) -> ConfusionNote {
        let recent = recentAnswers(itemIDs: confusion.itemIDs, limit: 4)
        return ConfusionNote(id: confusion.id, name: confusion.name, missCount: confusion.missCount,
                             recentMisses: recent.filter { !$0.wasCorrect }.count, recentAnswers: recent.count)
    }

    /// The latest answers to these items, newest first.
    func recentAnswers(itemIDs: [UUID], limit: Int) -> [ReviewSnapshot] {
        var logs: [ReviewLog] = []
        for id in Set(itemIDs) {
            var d = FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.itemID == id },
                                               sortBy: [SortDescriptor(\.reviewedAt, order: .reverse)])
            d.fetchLimit = limit
            logs += fetch(d)
        }
        return logs.sorted { $0.reviewedAt > $1.reviewedAt }.prefix(limit).map(ReviewSnapshot.init)
    }

    /// The last wrong answer the person typed or picked for an item ("telophase"), if any.
    func lastWrongAnswer(itemID: UUID) -> String? {
        var d = FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.itemID == itemID },
                                           sortBy: [SortDescriptor(\.reviewedAt, order: .reverse)])
        d.fetchLimit = 12
        return fetch(d).first { !$0.wasCorrect && !($0.answer ?? "").trimmingCharacters(in: .whitespaces).isEmpty }?.answer
    }

    // MARK: - Confusions

    /// "Later" on Cap's note: the confusion stays open and comes back tomorrow.
    func snoozeConfusion(_ id: UUID) {
        snoozeNotice(NoticeEngine.mixUpID(id))
    }

    func isConfusionSnoozed(_ id: UUID) -> Bool {
        noticeLedger.snoozed.contains(NoticeEngine.mixUpID(id))
    }

    /// "Not a mix-up": it isn't offered again (the finder skips dismissed groups).
    func dismissConfusion(_ id: UUID) {
        guard let confusion = confusion(id), confusion.deletedAt == nil, confusion.status != .dismissed else { return }
        confusion.status = .dismissed
        touch(confusion)
        save()
    }

    /// Readies a confusion's 2-minute fix: its own questions that are still drafts become active (starting the
    /// fix is the person's yes to them). Returns the session to present.
    @discardableResult
    func prepareFix(_ id: UUID) -> SessionRequest? {
        guard let confusion = confusion(id), confusion.deletedAt == nil else { return nil }
        var changed = false
        for itemID in confusion.fix?.itemIDs ?? [] {
            guard let item = item(itemID), item.deletedAt == nil, item.status == .draft else { continue }
            item.status = .active
            touch(item)
            changed = true
        }
        if changed { save() }
        return SessionRequest(kind: .fix, courseID: confusion.course?.id, confusionID: id)
    }

    /// After a fix drill: the confusion counts as fixed when most answers were right the first time. Returns
    /// whether it is fixed now.
    @discardableResult
    func resolveFix(confusionID: UUID, summary: SessionSummary) -> Bool {
        guard let confusion = confusion(confusionID), confusion.deletedAt == nil else { return false }
        if confusion.status == .fixed { return true }
        guard summary.itemsReviewed > 0, summary.accuracy >= Self.fixedAccuracy else { return false }
        confusion.status = .fixed
        touch(confusion)
        save()
        return true
    }

    /// The share of first-try answers a fix drill needs for the mix-up to count as fixed.
    static let fixedAccuracy = 0.75

    /// A mix-up the person made in this session that isn't a named confusion yet.
    func confusionCandidate(forSession sessionID: UUID) -> ConfusionCandidate? {
        let sid: UUID? = sessionID
        let logs = fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.sessionID == sid }))
        let missed = Set(logs.filter { !$0.wasCorrect }.map(\.itemID))
        guard !missed.isEmpty else { return nil }
        return confusionCandidates().first { !missed.isDisjoint(with: $0.itemIDs) }
    }

    /// The candidate's mistakes as the confusions job reads them.
    func mistakeInputs(for candidate: ConfusionCandidate) -> [MistakeInput] {
        let names = topicNames()
        return candidate.mistakes.map { m in
            MistakeInput(itemId: m.itemID.uuidString, topic: item(m.itemID)?.topicID.flatMap { names[$0] } ?? "",
                         prompt: m.prompt, expected: m.expected, given: m.given, misses: m.misses)
        }
    }

    /// Names and explains a candidate by the offline rules alone, at once. What the summary shows before any tap: no AI is asked.
    func explainByRules(_ candidate: ConfusionCandidate) -> (explained: ConfusionOut?, origin: ItemOrigin) {
        let ids = Set(candidate.itemIDs.map(\.uuidString))
        return (LocalConfusions.find(mistakeInputs(for: candidate)).first { !ids.isDisjoint(with: $0.itemIds) }, .rules)
    }

    /// Names and explains a candidate (Cloud AI when allowed, else the rules). Runs only after "Fix it now", and gives up on the cloud
    /// after `AppModel.lessonWait`. Nothing is saved.
    func explainConfusion(_ candidate: ConfusionCandidate) async -> (explained: ConfusionOut?, origin: ItemOrigin) {
        let inputs = mistakeInputs(for: candidate)
        guard !inputs.isEmpty else { return (nil, .rules) }
        let course = course(candidate.courseID)?.name ?? ""
        let anchors = anchorTexts(for: candidate)
        let outcome = await Self.withinLessonWait(fallback: ConfusionsOutcome(confusions: LocalConfusions.find(inputs), origin: .rules, model: LocalGrader.model)) {
            await self.ai.confusions(course: course, mistakes: inputs, anchorTexts: anchors)
        }
        let ids = Set(candidate.itemIDs.map(\.uuidString))
        return (outcome.confusions.first { !ids.isDisjoint(with: $0.itemIds) }, outcome.origin)
    }

    /// The lines of the page the candidate's first item came from, so fix questions can be checked against it.
    private func anchorTexts(for candidate: ConfusionCandidate) -> [String: String]? {
        guard let page = sourcePage(for: candidate) else { return nil }
        return Dictionary(page.lines.map { ($0.id, $0.text) }, uniquingKeysWith: { a, _ in a })
    }

    private func sourcePage(for candidate: ConfusionCandidate) -> SourcePage? {
        for id in candidate.itemIDs {
            guard let ref = item(id)?.sourceRef, let source = source(ref.sourceID), source.kind != .lecture else { continue }
            if let page = source.sortedPages.first(where: { $0.pageIndex == (ref.pageIndex ?? 0) }) { return page }
        }
        return nil
    }

    /// Names a mix-up found in a session as an open confusion. With `withFixQuestions` (the person tapped "Fix it
    /// now"), the explanation's questions become active items of the fix; otherwise the fix drills the mixed-up
    /// items themselves. An open confusion over the same items is returned instead of a second one.
    @discardableResult
    func adoptConfusion(_ candidate: ConfusionCandidate, explained: ConfusionOut?, origin: ItemOrigin = .rules,
                        withFixQuestions: Bool) -> Confusion {
        let wanted = Set(candidate.itemIDs)
        if let existing = fetch(FetchDescriptor<Confusion>(predicate: #Predicate { $0.deletedAt == nil }))
            .first(where: { $0.status == .open && Set($0.itemIDs) == wanted }) {
            return existing
        }
        let course = course(candidate.courseID)
        var fixIDs: [UUID] = []
        if withFixQuestions, let explained, let course {
            let page = sourcePage(for: candidate)
            let source = page?.source
            for question in explained.questions where !question.prompt.isEmpty && !question.answer.isEmpty {
                let topic = ItemFactory.topic(named: question.topic, in: course, now: now)
                let made = ItemFactory.makeItem(from: question, course: course, topicID: topic?.id ?? candidate.topicID,
                                                source: source, page: page, origin: origin, status: .active, now: now)
                made.checkedAt = origin == .cloud ? now : nil
                context.insert(made)
                course.items.append(made)
                touch(made)
                fixIDs.append(made.id)
            }
        }
        let explanation = explained?.explanation ?? candidate.defaultExplanation
        let confusion = Confusion(course: course, name: explained?.name ?? candidate.name, explanation: explanation,
                                  itemIDs: candidate.itemIDs,
                                  fix: ConfusionFix(lesson: explained?.lesson ?? "", itemIDs: fixIDs),
                                  missCount: candidate.missCount, now: now)
        confusion.lastSeenAt = candidate.lastMissAt
        context.insert(confusion)
        course?.confusions.append(confusion)
        touch(confusion)
        save()
        return confusion
    }

    // MARK: - Onboarding

    /// The course an onboarding step works on: the one it was given, else the first.
    func onboardingCourse(_ id: UUID?) -> Course? {
        if let course = course(id), course.deletedAt == nil { return course }
        return courses.first
    }

    /// The onboarding quick check: one multiple choice and one own-words question, the easiest of each from the
    /// set just made (the course's newest source), multiple choice first. Falls back to other formats when a set
    /// has no question of a kind.
    func quickCheckItemIDs(courseID: UUID?) -> [UUID] {
        guard let course = onboardingCourse(courseID) else { return [] }
        let usable = course.items.filter { $0.deletedAt == nil && ($0.status == .active || $0.status == .draft) }
        let newest = usable.compactMap { $0.sourceRef?.sourceID }.compactMap { source($0) }
            .max { $0.createdAt < $1.createdAt }
        let pool = newest.map { s in usable.filter { $0.sourceRef?.sourceID == s.id } } ?? usable
        func easiest(_ kinds: [ItemKind], in list: [StudyItem], where ok: (StudyItem) -> Bool = { _ in true }) -> StudyItem? {
            list.filter { kinds.contains($0.kind) && ok($0) }
                .min { ($0.difficultyHint, $0.createdAt) < ($1.difficultyHint, $1.createdAt) }
        }
        var picks: [StudyItem] = []
        if let choice = easiest([.mcq], in: pool) ?? easiest([.mcq], in: usable) { picks.append(choice) }
        let words = easiest([.recall], in: pool, where: { !$0.keyIdeas.isEmpty })
            ?? easiest([.recall, .apply], in: pool) ?? easiest([.recall, .apply], in: usable)
        if let words { picks.append(words) }
        for kinds in [[ItemKind.cloze], [.flashcard], [.diagram], ItemKind.allCases] where picks.count < 2 {
            if let extra = easiest(kinds, in: pool, where: { item in !picks.contains { $0.id == item.id } }) {
                picks.append(extra)
            }
        }
        return Array(picks.prefix(2).map(\.id))
    }

    /// Onboarding's readiness step: the course's next exam, or one made now from the date the person gave in the
    /// quiz (`settings.nextExamDate`) when they have no exam yet. The title comes from the course ("Bio 101
    /// exam"); the person can rename it later. Nil without a date (the step shows mastery instead).
    @discardableResult
    func ensureOnboardingExam(courseID: UUID?) -> Exam? {
        guard let course = onboardingCourse(courseID) else { return nil }
        if let existing = course.liveExams.first(where: { $0.date > now }) { return existing }
        guard let date = settings.nextExamDate, date > now else { return nil }
        // An exam already planned for that day (in any course) is the person's exam: never a second one.
        if let same = upcomingExams().first(where: { calendar.isDate($0.date, inSameDayAs: date) }) { return same }
        let exam = Exam(course: course, title: "\(course.name) exam", date: date, now: now)
        context.insert(exam)
        course.exams.append(exam)
        touch(exam)
        save()
        return exam
    }

    // MARK: - DEBUG

    #if DEBUG
    /// The world an onboarding step expects (`CRAMLESS_STEP`, with `CRAMLESS_SEED=0`): a course with the sample
    /// page's checked questions, an exam date 23 days out (none with `CRAMLESS_STEP_NODATE=1`), and (`answered`) the quick check
    /// already taken.
    func debugPrepareOnboardingWorld(answered: Bool) {
        if courses.isEmpty {
            let course = Course(name: "Bio 101", color: .sky, symbol: "leaf", now: now)
            context.insert(course)
            let source = SamplePage.makeSource(in: course, context: context, now: now)
            source.status = .ready
            let page = source.sortedPages.first
            for generated in SamplePage.checkedItems().items {
                let topic = ItemFactory.topic(named: generated.topic, in: course, now: now)
                let item = ItemFactory.makeItem(from: generated, course: course, topicID: topic?.id, source: source,
                                                page: page, origin: .sample, status: .active, now: now)
                context.insert(item)
                course.items.append(item)
            }
            var s = settings
            s.nextExamDate = TestHarness.value("CRAMLESS_STEP_NODATE") == "1"
                ? nil : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: calendar.adding(days: 23, to: now))
            s.dailyMinutes = 15
            settings = s
            save()
        }
        guard answered, let course = courses.first, fetch(FetchDescriptor<ReviewLog>()).isEmpty else { return }
        let ids = quickCheckItemIDs(courseID: course.id)
        let (session, _) = startSession(SessionRequest(kind: .quickCheck, courseID: course.id, itemIDs: ids))
        for id in ids {
            recordReview(itemID: id, rating: .good, score: 1, answer: nil, gradedBy: "rules", durationMs: 14_000,
                         sessionID: session.id)
        }
        finishSession(session)
    }
    #endif
}
