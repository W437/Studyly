import Foundation
import SwiftData

// Cap's cards on Today ("Cap noticed"). `NoticeEngine` decides, `NoticeContent` says it, and this is where they meet the store: it
// gathers what the engine reads, keeps the ledger (in UserDefaults, on this phone only) and makes the changes. Every mutation ends in
// `save()`, so Today, the plan and the notifications follow.
extension AppModel {
    static let noticeLedgerKey = "capling.notices.v1"
    /// Before the ledger, "Later" lived here (confusion id → day key). Read once, then gone.
    private static let oldSnoozeKey = "capling.study.confusionSnooze"

    // MARK: Today's cards

    /// Today's cards, the first one on screen. `session`: today's daily session, when the caller already built it.
    func todayNotices(session: BuiltSession? = nil) -> [CapNotice] {
        guard hasActiveItems() else { return [] }
        var cards = noticeDeck(session: session).map {
            NoticeContent.card($0, firstName: settings.firstName, now: now, calendar: calendar)
        }
        let ledger = noticeLedger
        if let id = ledger.confirming,
           let confirmation = NoticeContent.confirmation(boosts: ledger.boosts.filter { $0.noticeID == id }, now: now, calendar: calendar) {
            cards.insert(confirmation, at: 0)
        }
        return cards
    }

    /// The cards still to show today, dealing the day's deck if it hasn't been (a card that turned up since joins it, while there's room).
    func noticeDeck(session: BuiltSession? = nil) -> [Notice] {
        let inputs = noticeInputs(session: session)
        let engine = NoticeEngine(inputs)
        let candidates = noticeCandidates(engine)
        let dealt = engine.dealt(candidates)
        if dealt != inputs.ledger { storeLedger(dealt) }
        return engine.deck(candidates, ledger: dealt)
    }

    /// What Cap has noticed, worked out once per change of the store, the settings or the day.
    private func noticeCandidates(_ engine: NoticeEngine) -> [Notice] {
        let key = NoticeCache.Key(revision: revision, day: calendar.dayKey(for: now), settings: settings)
        if let cached = noticeCache.candidates, cached.key == key { return cached.cards }
        let cards = engine.candidates()
        noticeCache.candidates = (key, cards)
        return cards
    }

    // MARK: Notifications

    /// The notifications Cap may send, for today and tomorrow (`NotificationPlanner.Input.notices`).
    func noticePings() -> [NoticePing] {
        guard hasActiveItems() else { return [] }
        let engine = NoticeEngine(noticeInputs())
        return engine.pings(noticeCandidates(engine)).compactMap { ping in
            guard let date = ping.notice.examDate, let body = NoticeContent.pingBody(ping.notice) else { return nil }
            return NoticePing(linkID: ping.notice.linkID, kind: ping.notice.kind, examDate: date, dayOffset: ping.dayOffset, body: body)
        }
    }

    /// Remembers which pings the plan kept, and when they go out: once that time has passed, the card has had its one notification.
    func noteNoticePings(_ pings: [NoticePing], planned: [NotificationPlanner.Planned]) {
        var ledger = noticeLedger
        let now = self.now
        // Whatever hasn't gone out yet is planned afresh below.
        ledger.pinged = ledger.pinged.filter { $0.value <= now }
        for ping in pings {
            let url = CramlessLink.today(notice: ping.linkID)
            if let planned = planned.first(where: { $0.kind == .notice && $0.url == url }) { ledger.pinged[ping.linkID] = planned.date }
        }
        if ledger != noticeLedger { storeLedger(ledger) }
    }

    /// A notification opened this card: Today shows it first.
    func bringNoticeToFront(_ id: String) {
        updateLedger { $0.front = id }
        save()
    }

    // MARK: Changes

    /// A topic was just explained to Cap: he doesn't bring it up again for a while.
    func noteTopicTaught(_ topicID: UUID) {
        updateLedger { $0.taught[topicID.uuidString] = now }
        save()
    }

    /// "Later": the card waits until tomorrow.
    func snoozeNotice(_ id: String) {
        updateLedger { ledger in
            ledger.snoozed.insert(id)
            if ledger.front == id { ledger.front = nil }
        }
        save()
    }

    /// The card has been on screen today: no notification about it today, and "welcome back" counts the day.
    func noteNoticeShown(_ id: String) {
        let key = calendar.dayKey(for: now)
        guard !noticeLedger.wasSeen(id, on: key) else { return }
        updateLedger { $0.seen[id, default: []].append(key) }
        // A moment later, not in the frame the card scrolled into view.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.notifications.reschedule()
        }
    }

    /// The card was acted on: away for 7 days.
    func markNoticeActed(_ id: String) {
        let key = calendar.dayKey(for: now)
        updateLedger { $0.acted[id] = key }
        save()
    }

    /// A kind's switch in Settings (and "Don't show these" on a card).
    func setNoticeKind(_ kind: NoticeKind, on: Bool) {
        if on { settings.notices.off.remove(kind) } else { settings.notices.off.insert(kind) }
        save()
    }

    /// Runs a card's action: readies what it needs and presents it. Returns the session it opened, if it opened one.
    @discardableResult
    func perform(_ action: CapNotice.Action) -> SessionRequest? {
        let request: SessionRequest?
        switch action.run {
        case .fixMixUp(let id):
            markNoticeActed(NoticeEngine.mixUpID(id))
            request = prepareFix(id)
        case .session(let kind, let minutes, let courseID, let topicID, let examID):
            request = SessionRequest(kind: kind, courseID: courseID, examID: examID, minutes: minutes, topicID: topicID)
        case .showLookAlike(let pair):
            // Closing the sheet counts as having seen to it: the card stays away for its 7 days.
            markNoticeActed(pair.id)
            router.present(.lookAlike(a: pair.a, b: pair.b, examID: pair.examID))
            return nil
        case .fixMyWeek(let rescue):
            applyFadeRescue(rescue)
            return nil
        case .undoFixMyWeek(let id):
            undoFadeRescue(id)
            return nil
        case .takeMock(let examID):
            markNoticeActed(NoticeEngine.mockOfferID(examID))
            router.present(.mockExam(examID: examID))
            return nil
        case .fillGap(let examID):
            // Like a look-alike: opening the sheet has seen to it, and the exam page still says so until it's filled.
            markNoticeActed(NoticeEngine.gapID(examID))
            router.present(.fillGap(examID: examID, topicID: nil))
            return nil
        case .openHeardDate(let sourceID, let noticeID):
            markNoticeActed(noticeID)
            router.push(.lectureNotes(sourceID))
            return nil
        case .raiseQuestion(let itemID):
            markNoticeActed(NoticeEngine.tooEasyID(itemID))
            router.present(.ladder(parentID: itemID))
            return nil
        case .askCalendar:
            Task { await askForCalendar() }
            return nil
        case .moveBusyDay(let move):
            applyBusyMove(move)
            return nil
        case .teach(let topicID):
            markNoticeActed(NoticeEngine.teachID(topicID))
            router.present(.teach(topicID: topicID))
            return nil
        }
        if let request { router.present(.session(request)) }
        return request
    }

    // MARK: Fix my week

    /// Adds the rescue's minutes to its days and puts its questions first in them. Nothing else changes: no question's memory, no due
    /// date. The slot says "Plan updated", with Undo.
    func applyFadeRescue(_ rescue: FadeRescue) {
        let key = calendar.dayKey(for: now)
        updateLedger { ledger in
            ledger.boosts.removeAll { $0.noticeID == rescue.noticeID }
            ledger.boosts += rescue.days.map {
                PlanBoost(noticeID: rescue.noticeID, examID: rescue.examID, examTitle: rescue.examTitle, origin: rescue.origin?.name,
                          dayKey: $0.dayKey, minutes: rescue.minutesPerDay, itemIDs: $0.itemIDs)
            }
            ledger.acted[rescue.noticeID] = key
            ledger.confirming = rescue.noticeID
        }
        save()
    }

    /// Undo: the minutes go back as they were and the card comes back.
    func undoFadeRescue(_ noticeID: String) {
        updateLedger { ledger in
            ledger.boosts.removeAll { $0.noticeID == noticeID }
            ledger.acted[noticeID] = nil
            if ledger.confirming == noticeID { ledger.confirming = nil }
        }
        save()
    }

    // MARK: Busy days

    /// "Check my calendar": iOS asks (once, ever). Yes: the calendar is read and a long day's card follows if there is one. No: that's the end of it.
    func askForCalendar() async {
        // The question has had its answer: its place in today's deck is free for the long day it may find.
        updateLedger { ledger in
            ledger.acted[NoticeEngine.busyAskID] = calendar.dayKey(for: now)
            ledger.dealt.removeAll { $0.id == NoticeEngine.busyAskID }
        }
        let access = await busyCalendar.requestAccess()
        guard access == .granted else {
            router.toast("Okay. Cap won't look at your calendar.", systemImage: "checkmark.circle.fill", tone: .neutral)
            save()
            return
        }
        await refreshBusyBlocks()
        save()
        if !noticeDeck().contains(where: { $0.kind == .busyDay }) {
            router.toast("Nothing long this week. Cap will keep an eye out.", systemImage: "calendar", tone: .neutral)
        }
    }

    /// What the calendar says about the days ahead, read off the main thread and held in memory only. A quiet job for launch and for coming back: it reads only with the switch on,
    /// the access given and an exam near enough for a long day to matter.
    func refreshBusyBlocks() async {
        let near = examSnapshots(upcomingOnly: true).contains { calendar.dayDistance(from: now, to: $0.date) <= BusyDayFinder.examWithinDays }
        guard settings.notices.allows(.busyDay), busyCalendar.access == .granted, near else {
            if !noticeCache.busyBlocks.isEmpty {
                noticeCache.busyBlocks = []
                save()
            }
            return
        }
        let start = calendar.startOfDay(for: now)
        let blocks = await busyCalendar.busyBlocks(from: start, to: calendar.adding(days: BusyDayFinder.readDays, to: start))
        guard blocks != noticeCache.busyBlocks else { return }
        noticeCache.busyBlocks = blocks
        save()
    }

    /// "Move them": the minutes leave the long day and go to the days around it, on the plan and nowhere else. The slot says "Plan updated", with Undo (`undoFadeRescue`).
    func applyBusyMove(_ move: BusyMove) {
        let key = calendar.dayKey(for: now)
        updateLedger { ledger in
            ledger.boosts.removeAll { $0.noticeID == move.noticeID }
            func boost(_ day: BusyMove.Day, minutes: Int) -> PlanBoost {
                PlanBoost(noticeID: move.noticeID, examID: move.examID, examTitle: move.examTitle, origin: nil, dayKey: day.dayKey, minutes: minutes, itemIDs: [])
            }
            ledger.boosts.append(boost(move.busy, minutes: -move.minutes))
            ledger.boosts += move.to.map { boost($0, minutes: $0.minutes) }
            ledger.acted[move.noticeID] = key
            ledger.confirming = move.noticeID
        }
        save()
    }

    /// "OK" on "Plan updated": the slot moves on to the next card.
    func dismissNoticeConfirmation() {
        updateLedger { $0.confirming = nil }
        save()
    }

    /// Minutes "Fix my week" added to today.
    func boostMinutesToday() -> Int { noticeLedger.boostMinutes(on: calendar.dayKey(for: now)) }

    /// The questions "Fix my week" put first in today's session.
    func boostedItemsToday() -> [UUID] {
        let key = calendar.dayKey(for: now)
        return noticeLedger.boosts.filter { $0.dayKey == key }.flatMap(\.itemIDs)
    }

    /// Minutes added (or, on a long day, taken off) per day, by day offset from today, for `PlanBuilder.boosts`. A later day's boost for questions goes once all of them have
    /// been reviewed early.
    func planBoosts() -> (minutes: [Int: Int], pinned: [UUID: Int]) {
        let boosts = noticeLedger.boosts
        guard !boosts.isEmpty else { return ([:], [:]) }
        let today = calendar.dayNumber(for: now)
        var minutes: [Int: Int] = [:]
        var pinned: [UUID: Int] = [:]
        var memory: [UUID: MemoryState]?
        for boost in boosts {
            guard let day = calendar.dayNumber(forKey: boost.dayKey), day >= today else { continue }
            let offset = day - today
            if offset > 0, !boost.itemIDs.isEmpty {
                if memory == nil {
                    let wanted = Set(boosts.flatMap(\.itemIDs))
                    memory = Dictionary(itemSnapshots().filter { wanted.contains($0.id) }.map { ($0.id, $0.memory) }, uniquingKeysWith: { a, _ in a })
                }
                let left = boost.itemIDs.filter { id in (memory?[id]?.due).map { $0 < now } ?? false }
                if left.isEmpty { continue }
                for id in left { pinned[id] = offset }
            } else {
                for id in boost.itemIDs { pinned[id] = 0 }
            }
            minutes[offset, default: 0] += boost.minutes
        }
        return (minutes, pinned)
    }

    // MARK: Look-alikes

    /// A look-alike pair as its sheet shows it: the two sides, and the lesson by the rules, which is there at once and costs nothing.
    func lookAlikeDraft(a: UUID, b: UUID) -> LookAlikeDraft? {
        guard let first = item(a), let second = item(b), first.deletedAt == nil, second.deletedAt == nil,
              let left = lookAlikeSide(first), let right = lookAlikeSide(second) else { return nil }
        return LookAlikeDraft(a: left, b: right, courseID: first.course?.id, courseName: first.course?.name ?? "",
                              topicID: first.topicID == second.topicID ? first.topicID : nil,
                              rules: LocalConfusions.sideBySide(left, right))
    }

    private func lookAlikeSide(_ item: StudyItem) -> LookAlikeSide? {
        guard let term = LookAlikeItem.term(kind: item.kind, prompt: item.prompt, answer: item.answer) else { return nil }
        let termIsAnswer = ConfusionFinder.normalize(term) == ConfusionFinder.normalize(item.answer)
        let topic = item.topicID.flatMap { topicNames()[$0] } ?? ""
        return LookAlikeSide(itemID: item.id, term: term, clue: termIsAnswer ? item.prompt : item.answer, topic: topic, prompt: item.prompt,
                             answer: item.answer, sourceLabel: item.sourceRef?.label)
    }

    /// The lesson Cap writes for the pair: Cloud AI when allowed (on the relay's `extras` meter, and only after "Show me"), else the rules.
    func lookAlikeLesson(_ draft: LookAlikeDraft) async -> (lesson: ConfusionOut, origin: ItemOrigin) {
        let fallback = ConfusionsOutcome(confusions: [draft.rules], origin: .rules, model: LocalGrader.model)
        let outcome = await Self.withinLessonWait(fallback: fallback) {
            await self.ai.lookAlikeLesson(course: draft.courseName, draft.a, draft.b)
        }
        return (outcome.confusions.first ?? draft.rules, outcome.origin)
    }

    /// "Try 2 questions": the pair becomes an open mix-up with no misses, its questions the fix, and the drill starts.
    @discardableResult
    func tryLookAlike(_ draft: LookAlikeDraft, lesson: ConfusionOut, origin: ItemOrigin) -> SessionRequest? {
        let confusion = adoptConfusion(lookAlikeCandidate(draft, name: lesson.name), explained: lesson, origin: origin, withFixQuestions: true)
        guard var request = prepareFix(confusion.id) else { return nil }
        request.lessonSeen = true
        router.present(.session(request))
        return request
    }

    /// "Don't bring this up again": remembered as a dismissed mix-up, which syncs, and neither finder offers it again.
    func rejectLookAlike(_ draft: LookAlikeDraft) {
        let course = course(draft.courseID)
        let confusion = Confusion(course: course, name: draft.rules.name, explanation: "", itemIDs: [draft.a.itemID, draft.b.itemID],
                                  missCount: 0, now: now)
        confusion.status = .dismissed
        context.insert(confusion)
        course?.confusions.append(confusion)
        touch(confusion)
        save()
    }

    private func lookAlikeCandidate(_ draft: LookAlikeDraft, name: String) -> ConfusionCandidate {
        let ids = [draft.a.itemID, draft.b.itemID]
        return ConfusionCandidate(id: ConfusionFinder.stableID("pair", ids), courseID: draft.courseID, topicID: draft.topicID, name: name,
                                  reason: .lookAlike, itemIDs: ids, missCount: 0, lastMissAt: now,
                                  mistakes: [draft.a, draft.b].map { .init(itemID: $0.itemID, prompt: $0.prompt, expected: $0.answer, given: "", misses: 0) })
    }

    /// How long a lesson may keep a sheet or a button waiting before the rules' answer is used.
    nonisolated static let lessonWait: Duration = .seconds(10)

    /// `work`, or `fallback` once `lessonWait` is up (the work is cancelled).
    nonisolated static func withinLessonWait<T: Sendable>(fallback: T, _ work: @escaping @MainActor @Sendable () async -> T) async -> T {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: lessonWait)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? fallback
        }
    }

    // MARK: The ledger

    /// Today's ledger: rolled over to today (and once, what the old "Later" store still held for today).
    var noticeLedger: NoticeLedger {
        let key = calendar.dayKey(for: now)
        if let ledger = noticeCache.ledger, ledger.day == key { return ledger }
        var ledger = noticeCache.ledger ?? loadLedger()
        ledger = ledger.rolled(to: key, now: now, calendar: calendar)
        if let old = defaults.dictionary(forKey: Self.oldSnoozeKey) as? [String: String] {
            for (id, day) in old where day == key {
                if let uuid = UUID(uuidString: id) { ledger.snoozed.insert(NoticeEngine.mixUpID(uuid)) }
            }
            defaults.removeObject(forKey: Self.oldSnoozeKey)
        }
        storeLedger(ledger)
        return ledger
    }

    /// Everything about Cap's cards, for a local wipe.
    func clearNoticeLedger() {
        noticeCache.ledger = nil
        noticeCache.candidates = nil
        noticeCache.lookAlikes = nil
        noticeCache.lookAlikesWorking = nil
        noticeCache.sourceIDs = [:]
        noticeCache.busyBlocks = []
        defaults.removeObject(forKey: Self.noticeLedgerKey)
    }

    private func loadLedger() -> NoticeLedger {
        guard let data = defaults.data(forKey: Self.noticeLedgerKey),
              let ledger = try? JSONDecoder.cramless.decode(NoticeLedger.self, from: data) else { return NoticeLedger() }
        return ledger
    }

    private func updateLedger(_ change: (inout NoticeLedger) -> Void) {
        var ledger = noticeLedger
        change(&ledger)
        storeLedger(ledger)
    }

    private func storeLedger(_ ledger: NoticeLedger) {
        noticeCache.ledger = ledger
        if let data = try? JSONEncoder.cramless.encode(ledger) { defaults.set(data, forKey: Self.noticeLedgerKey) }
    }

    // MARK: What the engine reads

    private func noticeBaseInputs() -> NoticeInputs {
        NoticeInputs(now: now, calendar: calendar, fsrs: fsrs, settings: settings.notices, ledger: noticeLedger, easyDays: settings.easyDays)
    }

    func noticeInputs(session: BuiltSession? = nil) -> NoticeInputs {
        var inputs = noticeBaseInputs()
        let key = NoticeCache.Key(revision: revision, day: calendar.dayKey(for: now), settings: settings)
        // The candidates are kept per revision: nothing more to read while they're good.
        if let cached = noticeCache.candidates, cached.key == key { return inputs }
        let items = itemSnapshots()
        let exams = examSnapshots(upcomingOnly: true)
        // An exam that was deleted or has passed takes its boosts with it.
        let examIDs = Set(exams.map(\.id))
        if inputs.ledger.boosts.contains(where: { !examIDs.contains($0.examID) }) {
            updateLedger { $0.boosts.removeAll { !examIDs.contains($0.examID) } }
            inputs.ledger = noticeLedger
        }
        let built = session ?? todayBuiltSession()
        let minutesDone = Int((dayRecordSnapshot(for: now)?.studySeconds ?? 0) / 60)
        inputs.items = items
        inputs.exams = exams
        inputs.finishedExams = examSnapshots().filter { $0.date <= now }
        // Only five are read, and mix-ups on finished exams go last, so they can't crowd out the ones that matter next.
        let index = ExamIndex(exams + inputs.finishedExams, after: now)
        let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let open = openConfusions()
        let isBehind = { (confusion: Confusion) in
            NoticeEngine.isBehindTheStudent(confusion.itemIDs.compactMap { itemsByID[$0] }, index: index)
        }
        inputs.mixUps = (open.filter { !isBehind($0) } + open.filter(isBehind)).prefix(5).map { confusion in
            NoticeMixUp(note: confusionNote(confusion), itemIDs: confusion.itemIDs, courseID: confusion.course?.id,
                        courseName: confusion.course?.name ?? "")
        }
        inputs.lookAlikes = lookAlikePairs(items: items, exams: exams)
        inputs.days = daySnapshots()
        // Quiet mode hides the flame, so Welcome back doesn't name the streak or promise to light it.
        inputs.bestStreak = settings.quietMode ? 0 : streak().best
        inputs.todayItems = Set(built.entries.map(\.itemID))
        inputs.goalMet = minutesDone >= settings.dailyMinutes + boostMinutesToday()
        inputs.dailyMinutes = settings.dailyMinutes
        inputs.sources = fadeSources(items: items, exams: exams)
        inputs.topicNames = topicNames()
        inputs.cloudLessons = ai.route(.confusions).usesCloud
        inputs.mockOffers = noticeMockOffers()
        inputs.gaps = noticeGaps(items: items)
        inputs.heardDates = noticeHeardDates()
        inputs.tooEasy = ladderOffers(items: items, exams: exams).map {
            NoticeTooEasy(itemID: $0.itemID, next: $0.next, topicName: $0.topicName)
        }
        inputs.calendarAccess = settings.notices.allows(.busyDay) ? busyCalendar.access : .denied
        inputs.busyBlocks = noticeCache.busyBlocks
        inputs.teachOffers = teachOffers(items: items, exams: exams)
        return inputs
    }

    /// The upcoming exams a mock is due for, with the mock's size. Only exams in the mock's window are read.
    private func noticeMockOffers() -> [NoticeMockOffer] {
        upcomingExams().compactMap { exam in
            guard MockSuggestion.days.contains(calendar.dayDistance(from: now, to: exam.date)), mockIsDue(for: exam),
                  case .ready(let plan) = mockOffer(for: exam) else { return nil }
            return NoticeMockOffer(examID: exam.id, examTitle: exam.title, examDate: exam.date, questions: plan.entries.count, minutes: plan.minutes,
                                   realQuestions: exam.format.questionCount)
        }
    }

    /// The pairs for the exams ahead. They change slowly and reading every question's words isn't free, so they are worked out once a day
    /// and again when the questions or the mix-ups change in number or state, away from the main thread: until the answer is in, this
    /// returns the last one, and the answer's arrival (`save()`) lets a new pair join the deck.
    private func lookAlikePairs(items: [ItemSnapshot], exams: [ExamSnapshot]) -> [LookAlikePair] {
        let window = exams.filter { calendar.dayDistance(from: now, to: $0.date) <= LookAlikeFinder.examDays }
        guard !window.isEmpty else { return [] }
        let confusions = confusionSnapshots()
        let stamp = [calendar.dayKey(for: now), String(items.count), confusions.map { "\($0.id)\($0.status.rawValue)" }.sorted().joined(),
                     window.map { "\($0.id)\($0.date.timeIntervalSinceReferenceDate)" }.joined()].joined(separator: "|")
        if let cached = noticeCache.lookAlikes, cached.key == stamp { return cached.pairs }
        let courseIDs = Set(window.compactMap(\.courseID))
        let finder = LookAlikeFinder(calendar: calendar, now: now)
        // Tests and the harness want the answer now, and their worlds are small.
        guard sideEffectsEnabled, !config.isHarness else {
            let pairs = finder.pairs(items: lookAlikeItems(courseIDs: courseIDs), exams: exams, confusions: confusions)
            noticeCache.lookAlikes = (stamp, pairs)
            return pairs
        }
        if noticeCache.lookAlikesWorking != stamp {
            noticeCache.lookAlikesWorking = stamp
            Task { [weak self] in
                guard let self else { return }
                let words = await self.lookAlikeWords(courseIDs: courseIDs)
                let pairs = await Task.detached(priority: .utility) {
                    finder.pairs(items: words.map(\.item), exams: exams, confusions: confusions)
                }.value
                guard self.noticeCache.lookAlikesWorking == stamp else { return }
                let changed = pairs != (self.noticeCache.lookAlikes?.pairs ?? [])
                self.noticeCache.lookAlikes = (stamp, pairs)
                if changed { self.save() }
            }
        }
        return noticeCache.lookAlikes?.pairs ?? []
    }

    /// A question's words as they are stored, read on the main actor; `item` puts them in comparable form anywhere.
    struct LookAlikeWords: Sendable {
        var id: UUID
        var courseID: UUID
        var topicID: UUID?
        var kind: ItemKind
        var prompt: String
        var answer: String
        var choicesData: Data?
        var clozeData: Data?
        var studied: Bool
        var recall: Double

        var item: LookAlikeItem {
            let choices = choicesData.flatMap { try? JSONDecoder.cramless.decode([Choice].self, from: $0) } ?? []
            let cloze = clozeData.flatMap { try? JSONDecoder.cramless.decode(ClozeSpec.self, from: $0) }
            let accepted = [answer] + choices.filter(\.correct).map(\.text) + (cloze?.answers ?? []) + (cloze?.alternates.flatMap { $0 } ?? [])
            return LookAlikeItem(id: id, courseID: courseID, topicID: topicID, kind: kind, prompt: prompt, answer: answer, accepted: accepted,
                                 distractors: kind == .mcq ? choices.filter { !$0.correct }.map(\.text) : [], studied: studied, recall: recall)
        }
    }

    /// The words of these courses' active questions, a batch per turn of the main actor, so it never holds up a frame.
    private func lookAlikeWords(courseIDs: Set<UUID>) async -> [LookAlikeWords] {
        var out: [LookAlikeWords] = []
        var sinceYield = 0
        for course in courses where courseIDs.contains(course.id) {
            let courseID = course.id
            for item in course.items where item.deletedAt == nil && item.status == .active {
                out.append(lookAlikeWords(item, courseID: courseID))
                sinceYield += 1
                if sinceYield == 200 {
                    sinceYield = 0
                    await Task.yield()
                }
            }
        }
        return out
    }

    private func lookAlikeWords(_ item: StudyItem, courseID: UUID) -> LookAlikeWords {
        LookAlikeWords(id: item.id, courseID: courseID, topicID: item.topicID, kind: item.kind, prompt: item.prompt, answer: item.answer,
                       choicesData: item.choicesData, clozeData: item.clozeData, studied: ItemSnapshot(item, courseID: courseID).isStudied,
                       recall: fsrs.retrievability(of: item.memory, at: now))
    }

    /// These courses' active questions, as the look-alike finder reads them.
    func lookAlikeItems(courseIDs: Set<UUID>) -> [LookAlikeItem] {
        courses.filter { courseIDs.contains($0.id) }.flatMap { course in
            let courseID = course.id
            return course.items.filter { $0.deletedAt == nil && $0.status == .active }.map { lookAlikeWords($0, courseID: courseID).item }
        }
    }

    /// Where the overdue questions of the exams in fading's window came from. A question's source doesn't change, so each is read once.
    private func fadeSources(items: [ItemSnapshot], exams: [ExamSnapshot]) -> [UUID: FadeSource] {
        let window = exams.filter { FadeFinder.examWindow.contains(calendar.dayDistance(from: now, to: $0.date)) }
        guard !window.isEmpty else { return [:] }
        let overdue = Set(items.filter { $0.isStudied && ($0.memory.due ?? .distantFuture) < now }.map(\.id))
        guard overdue.count >= FadeFinder.minimumQuestions else { return [:] }
        var out: [UUID: FadeSource] = [:]
        var names: [UUID: String] = [:]
        let courseIDs = Set(window.compactMap(\.courseID))
        for course in courses where courseIDs.contains(course.id) {
            for item in course.items where overdue.contains(item.id) {
                let id: UUID?
                if let known = noticeCache.sourceIDs[item.id] {
                    id = known
                } else {
                    id = item.sourceRef?.sourceID
                    noticeCache.sourceIDs[item.id] = .some(id)
                }
                guard let id else { continue }
                if names[id] == nil { names[id] = source(id)?.title }
                if let name = names[id] { out[item.id] = FadeSource(id: id, name: name) }
            }
        }
        return out
    }
}

/// What Cap's cards keep between reads: the ledger, and what is worked out once per change (`AppModel.noticeCandidates`).
final class NoticeCache {
    struct Key: Equatable {
        var revision: Int
        var day: String
        var settings: AppSettings
    }

    var ledger: NoticeLedger?
    var candidates: (key: Key, cards: [Notice])?
    var lookAlikes: (key: String, pairs: [LookAlikePair])?
    /// The stamp the look-alike finder is working on, or last finished.
    var lookAlikesWorking: String?
    /// Each question's source, once read.
    var sourceIDs: [UUID: UUID?] = [:]
    /// What the calendar says about the days ahead. Never stored and never sent.
    var busyBlocks: [BusyBlock] = []
}

/// One side of a look-alike pair.
struct LookAlikeSide: Equatable, Sendable {
    var itemID: UUID
    /// "Metaphase".
    var term: String
    /// What tells it apart: the question it answers, or a flashcard's back.
    var clue: String
    var topic: String
    var prompt: String
    var answer: String
    var sourceLabel: String? = nil
}

/// A look-alike pair as its sheet shows it, before anything is saved.
struct LookAlikeDraft: Equatable, Sendable {
    var a: LookAlikeSide
    var b: LookAlikeSide
    var courseID: UUID?
    var courseName: String
    var topicID: UUID?
    /// The lesson by the rules.
    var rules: ConfusionOut
}

#if DEBUG
/// `CRAMLESS_TODAY_NOTICES=<n>`: the demo world has one open mix-up; these stand in for more, so "1 of 3" and "Later" can be seen.
@MainActor
enum TodayNoticesDemo {
    static func notices(base: [CapNotice]) -> [CapNotice] {
        let fixID = base.compactMap { notice -> UUID? in
            if case .fixMixUp(let id)? = notice.action?.run { return id }
            return nil
        }.first
        let extras = [("Meiosis vs mitosis", 4, 3), ("Moles vs molar mass", 3, 2)].enumerated().map { index, demo -> CapNotice in
            var card = NoticeContent.card(for: ConfusionNote(id: fixID ?? StableRandom.uuid("demo-notice-\(index)"), name: demo.0,
                                                             missCount: demo.1, recentMisses: demo.2, recentAnswers: 4))
            card.id = "mix-demo-\(index)"
            return card
        }
        return base + extras
    }
}
#endif
