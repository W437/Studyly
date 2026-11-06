#if DEBUG
import Foundation
import SwiftData

// Launch hooks for Cap's cards (DEBUG only). They shape the demo world so the real engines find each kind:
//
// - `CRAMLESS_NOTICES=mixup,lookalike,fading,back,mock,gap,lecturedate|all|none`: those kinds and no others. `gap`: the Bio midterm 12 days out, with its topics that
//   have no questions; `lecturedate`: Lecture 6 heard a date for a second quiz, two weeks off. `lookalike`: the Bio midterm 9 days out, with the
//   sample page's look-alikes. `fading`: the midterm 6 days out, and its questions 20 days overdue, with 30 more added, so that more of them than today's session
//   holds. `back`: 8 days without study after a 23-day run. `mock`: the midterm 5 days out. `mixup` needs nothing: the demo world has an open mix-up.
// - `CRAMLESS_NOTICES=tooeasy` (or `CRAMLESS_LADDER=offer`): one of the Bio midterm's questions has become too easy, with three real reviews
//   behind it, and the midterm is 20 days out.
// - `CRAMLESS_NOTICE_STATE=second|later|done|allLater`, once the deck is dealt: `second` the first card acted on, so "2 of N" shows; `later` the
//   first put off with "Later"; `done` "Fix my week" pressed on a fading card, or "Move them" on a long day ("Plan updated"); `allLater` all put off.
// - `CRAMLESS_NOTICES=busy`: the midterm 9 days out, and a demo calendar with a long day. `CRAMLESS_BUSY=<offset>[:<hours>]` says which (3 days ahead, 6 hours, by default);
//   `CRAMLESS_BUSY=ask` hasn't been asked yet ("Check my calendar" says yes, and the card follows), `=askno` answers no, `=denied` was refused long ago.
// - `CRAMLESS_NOTICE_TAP=<ms>` presses the button on the card that long after launch (`TodayView`).
// - `CRAMLESS_ROUTE=lookAlike` opens the sheet on the best pair; `CRAMLESS_LOOKALIKE=rules|cloud|writing` (`LookAlikeView`).
//
// `CRAMLESS_ROUTE=settings:notifications CRAMLESS_NOTICES=fading` shows the ping in the page's planned list.
extension AppModel {
    /// Called once at launch, after the demo world is seeded.
    func applyNoticeHarness() {
        guard config.isHarness,
              let raw = TestHarness.value("CRAMLESS_NOTICES") ?? (TestHarness.value("CRAMLESS_LADDER") == "offer" ? "tooeasy" : nil) else { return }
        let asked = Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let all = asked.contains("all")
        let kinds: [(String, NoticeKind)] = [("mixup", .mixUp), ("lookalike", .lookAlike), ("fading", .fading), ("back", .welcomeBack), ("mock", .mockOffer),
                                            ("gap", .gap), ("lecturedate", .lectureDate), ("tooeasy", .tooEasy), ("busy", .busyDay)]
        var off = Set<NoticeKind>()
        for (name, kind) in kinds where !all && !asked.contains(name) { off.insert(kind) }
        settings.notices.off = off
        guard !asked.contains("none") else { return }
        let midterm = upcomingExams().first { $0.title == "Bio 101 Midterm" }
        let chem = upcomingExams().first { $0.title == "Chem 110 Quiz" }
        if asked.contains("fading") || all {
            debugMoveExam(midterm, toDays: 6)
            // An exam two days out would make the session its own and take days from the plan: this is the midterm's week.
            debugMoveExam(chem, toDays: 40)
            debugMakeOverdue(course: midterm?.course)
        } else if asked.contains("lookalike") {
            debugMoveExam(midterm, toDays: 9)
            debugMoveExam(chem, toDays: 40)
            debugSoften(course: midterm?.course)
        } else if asked.contains("tooeasy") {
            debugMoveExam(midterm, toDays: 20)
            debugMoveExam(chem, toDays: 40)
            debugMakeTooEasy(course: midterm?.course)
        } else if asked.contains("mock") {
            debugMoveExam(midterm, toDays: 5)
            debugMoveExam(chem, toDays: 40)
        } else if asked.contains("gap") {
            debugMoveExam(midterm, toDays: 12)
            debugMoveExam(chem, toDays: 40)
        }
        if asked.contains("busy") {
            debugMoveExam(midterm, toDays: 9)
            debugMoveExam(chem, toDays: 40)
            debugFillCalendar()
        }
        if asked.contains("lecturedate") || all { debugHearExamDate("new") }
        if asked.contains("back") || all { debugWentAway() }
        save()
        applyNoticeState()
    }

    private func applyNoticeState() {
        guard let state = TestHarness.value("CRAMLESS_NOTICE_STATE") else { return }
        let deck = noticeDeck()
        switch state {
        case "second":
            if let first = deck.first { markNoticeActed(first.id) }
        case "later":
            if let first = deck.first { snoozeNotice(first.id) }
        case "allLater":
            for card in deck { snoozeNotice(card.id) }
        case "done":
            for card in deck {
                if case .fading(let rescue) = card.evidence { applyFadeRescue(rescue) }
                if case .busyDay(let move) = card.evidence { applyBusyMove(move) }
            }
        default:
            break
        }
    }

    /// A demo calendar with one long day (`CRAMLESS_BUSY`).
    private func debugFillCalendar() {
        let raw = TestHarness.value("CRAMLESS_BUSY") ?? ""
        let parts = raw.split(separator: ":").compactMap { Int($0) }
        let offset = parts.first ?? 3, hours = parts.count > 1 ? parts[1] : 6
        let day = calendar.adding(days: offset, to: calendar.startOfDay(for: now))
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        let blocks = [BusyBlock(start: start, end: start.addingTimeInterval(Double(hours) * 3600))]
        let access: CalendarAccess = switch raw {
        case "ask", "askno": .notAsked
        case "denied": .denied
        default: .granted
        }
        let demo = DemoBusyCalendar(access: access, answers: raw == "askno" ? .denied : .granted, blocks: blocks)
        busyCalendar = demo
        noticeCache.busyBlocks = demo.heldBlocks
    }

    /// The best pair, for `CRAMLESS_ROUTE=lookAlike`: every exam counted as 9 days off, and nothing already solid.
    func debugLookAlikePair() -> LookAlikePair? {
        let exams = examSnapshots(upcomingOnly: true).map { exam -> ExamSnapshot in
            var near = exam
            near.date = calendar.adding(days: 9, to: now)
            return near
        }
        let names = lookAlikeItems(courseIDs: Set(exams.compactMap(\.courseID))).map { item -> LookAlikeItem in
            var looser = item
            looser.studied = true
            looser.recall = min(item.recall, 0.8)
            return looser
        }
        return LookAlikeFinder(calendar: calendar, now: now).pairs(items: names, exams: exams, confusions: confusionSnapshots()).first
    }

    private func debugMoveExam(_ exam: Exam?, toDays days: Int) {
        guard let exam else { return }
        let hour = calendar.component(.hour, from: exam.date)
        exam.date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.adding(days: days, to: now)) ?? exam.date
        touch(exam)
    }

    /// Every question of the course studied 25 days ago with a memory that has long since gone: 20 days overdue. The demo course alone fits
    /// in one session, which would leave too few to fade, so it gets 30 slower own-words questions too, on the same topics and sources.
    private func debugMakeOverdue(course: Course?) {
        guard let course else { return }
        let existing = course.items.filter { $0.deletedAt == nil && $0.status == .active }.sorted { $0.id.uuidString < $1.id.uuidString }
        ModelID.seeded("notice-harness") {
            for index in 0..<30 where !existing.isEmpty {
                let like = existing[index % existing.count]
                let extra = StudyItem(course: course, topicID: like.topicID, kind: .recall, status: .active, origin: .person,
                                      prompt: "In your own words: \(like.prompt)", answer: like.answer, sourceRef: like.sourceRef, now: now)
                context.insert(extra)
                course.items.append(extra)
            }
        }
        let lastReview = calendar.adding(days: -25, to: now)
        let due = calendar.adding(days: -20, to: now)
        for item in course.items where item.deletedAt == nil && item.status == .active {
            var memory = item.memory
            memory.state = .review
            memory.stability = 2.2
            memory.difficulty = 5.5
            memory.lastReview = lastReview
            memory.due = due
            memory.reps = max(memory.reps, 2)
            item.memory = memory
            touch(item)
        }
    }

    /// Nothing in the course is solid yet: its look-alikes count.
    /// The course's first question with lines to write from and something harder to become: strong, with the reviews that make it so.
    private func debugMakeTooEasy(course: Course?) {
        guard let course, let item = course.items.filter({
            $0.deletedAt == nil && $0.status == .active && Ladder.next(after: $0.kind) != nil && reportSource(of: $0) != nil
        }).min(by: { $0.prompt < $1.prompt }) else { return }
        var memory = item.memory
        memory.state = .review
        memory.stability = 30
        memory.difficulty = max(memory.difficulty, 4)
        memory.lastReview = calendar.adding(days: -2, to: now)
        memory.due = calendar.adding(days: 25, to: now)
        memory.reps = max(memory.reps, 3)
        item.memory = memory
        ModelID.seeded("too-easy-harness") {
            for days in [2, 10, 20] {
                context.insert(ReviewLog(itemID: item.id, courseID: course.id, sessionID: nil, reviewedAt: calendar.adding(days: -days, to: now),
                                         rating: .good, gradedBy: "rules", durationMs: 4000, before: memory, after: memory, elapsedDays: 8, scheduledDays: 8))
            }
        }
    }

    private func debugSoften(course: Course?) {
        guard let course else { return }
        for item in course.items where item.deletedAt == nil && item.status == .active && item.stateRaw != CardState.new.rawValue {
            var memory = item.memory
            memory.stability = min(memory.stability, 3)
            memory.lastReview = calendar.adding(days: -4, to: now)
            memory.due = calendar.adding(days: 1, to: now)
            item.memory = memory
            touch(item)
        }
    }

    /// 8 days without study after a run of 23: nothing since, and the day before the run missed.
    private func debugWentAway() {
        for offset in 1...40 {
            let date = calendar.adding(days: -offset, to: now)
            let record = dayRecord(key: calendar.dayKey(for: date), date: date)
            let studied = offset >= 9 && offset < 9 + 23
            record.sessions = studied ? 1 : 0
            record.studySeconds = studied ? 15 * 60 : 0
            record.itemsReviewed = studied ? 18 : 0
            record.frozen = false
            record.repaired = false
            record.syncedAt = nil
        }
    }
}
#endif
