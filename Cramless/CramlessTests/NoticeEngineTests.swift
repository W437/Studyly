import Foundation
import XCTest
@testable import Cramless

/// Cap's cards: the deck, each kind, the notifications and the words. Pure: `NoticeInputs` in, values out.
final class NoticeEngineTests: XCTestCase {
    let cal = EngineTest.calendar()
    lazy var now = EngineTest.date(2026, 10, 22, 16, in: cal)   // A Thursday.
    let course = UUID()

    private func inputs(_ change: (inout NoticeInputs) -> Void = { _ in }) -> NoticeInputs {
        var i = NoticeInputs(now: now, calendar: cal, fsrs: FSRS())
        i.ledger.day = cal.dayKey(for: now)
        change(&i)
        return i
    }

    private func mixUp(_ name: String = "Anaphase vs telophase", misses: Int = 3, id: UUID = UUID(), items: [UUID] = []) -> NoticeMixUp {
        NoticeMixUp(note: ConfusionNote(id: id, name: name, missCount: misses, recentMisses: misses, recentAnswers: 4), itemIDs: items, courseID: course)
    }

    private func exam(in days: Int, title: String = "Bio 101 Midterm", hour: Int = 9) -> ExamSnapshot {
        let date = cal.date(bySettingHour: hour, minute: 0, second: 0, of: cal.adding(days: days, to: now))!
        return ExamSnapshot(courseID: course, title: title, date: date)
    }

    private func pair(in days: Int = 9, exam examID: UUID = UUID(), similarity: Double = 0.67, linked: Bool = true) -> LookAlikePair {
        LookAlikePair(id: "pair-\(UUID().uuidString)", a: UUID(), b: UUID(), termA: "Metaphase", termB: "Telophase", courseID: course, topicID: nil,
                      examID: examID, examTitle: "Bio 101 Midterm", examDate: cal.adding(days: days, to: now), daysLeft: days, similarity: similarity, linked: linked)
    }

    /// `count` overdue questions with low exam-day recall on `exam`.
    private func faded(_ count: Int, on exam: ExamSnapshot, topic: UUID? = nil, kind: ItemKind = .flashcard) -> [ItemSnapshot] {
        (0..<count).map { _ in
            let last = cal.adding(days: -25, to: now)
            let memory = MemoryState(state: .review, stability: 1.4, difficulty: 5, due: cal.adding(days: -20, to: now), lastReview: last, reps: 3)
            return ItemSnapshot(kind: kind, topicID: topic, courseID: exam.courseID, memory: memory, createdAt: last)
        }
    }

    private func days(_ back: ClosedRange<Int>) -> [DaySnapshot] {
        back.map { offset in
            let day = cal.adding(days: -offset, to: cal.startOfDay(for: now))
            return DaySnapshot(dayKey: cal.dayKey(for: day), day: day, studySeconds: 900, itemsReviewed: 18, sessions: 1)
        }
    }

    private func deal(_ i: NoticeInputs) -> (deck: [Notice], ledger: NoticeLedger, engine: NoticeEngine) {
        let engine = NoticeEngine(i)
        let cards = engine.candidates()
        let ledger = engine.dealt(cards)
        return (engine.deck(cards, ledger: ledger), ledger, engine)
    }

    // MARK: The deck

    func testRanksComeOutAsPlanned() {
        let midterm = exam(in: 9)
        let i = inputs {
            $0.exams = [midterm]
            $0.mixUps = [mixUp(misses: 3)]
            $0.lookAlikes = [pair(in: 9, exam: midterm.id)]
            $0.items = faded(8, on: midterm)
            $0.days = days(9...14)
            $0.bestStreak = 6
        }
        XCTAssertEqual(deal(i).deck.map(\.kind), [.welcomeBack, .fading, .mixUp], "highest rank first, at most three")
        XCTAssertEqual(NoticeEngine.Rank.welcomeBack, 1000)
        XCTAssertEqual(NoticeEngine.Rank.mixUp(misses: 3), 460)
        XCTAssertEqual(NoticeEngine.Rank.mixUp(misses: 40), 600, "misses count up to 10")
        XCTAssertEqual(NoticeEngine.Rank.fading(dimShare: 0.5, daysLeft: 6), 540)
        XCTAssertEqual(NoticeEngine.Rank.lookAlike(similarity: 0.5, linked: true, daysLeft: 9), 310)
    }

    func testTheDeckIsTheSameEveryTimeAndOneCardPerKind() {
        let i = inputs { $0.mixUps = [mixUp(id: UUID()), mixUp("Moles vs molar mass", misses: 9), mixUp("Limiting vs excess", misses: 1)] }
        let first = deal(i), again = deal(i)
        XCTAssertEqual(first.deck, again.deck)
        XCTAssertEqual(first.deck.count, 1, "one card per kind")
        XCTAssertEqual(first.deck.first?.title(), "Moles vs molar mass", "the most missed")
    }

    func testAtMostThreeAreDealtAndCardsThatTurnUpLaterJoinWhileThereIsRoom() {
        let midterm = exam(in: 9)
        var i = inputs { $0.mixUps = [mixUp()] }
        var round = deal(i)
        XCTAssertEqual(round.deck.map(\.kind), [.mixUp])
        // Later the same day, a higher-ranked card turns up: it joins behind what was already dealt.
        i.ledger = round.ledger
        i.exams = [midterm]
        i.items = faded(8, on: midterm)
        round = deal(i)
        XCTAssertEqual(round.deck.map(\.kind), [.mixUp, .fading], "what's dealt stays in its place")
        i.ledger = round.ledger
        i.lookAlikes = [pair(in: 9, exam: midterm.id)]
        round = deal(i)
        XCTAssertEqual(round.deck.map(\.kind), [.mixUp, .fading, .lookAlike])
        i.ledger = round.ledger
        i.days = days(9...14)
        round = deal(i)
        XCTAssertEqual(round.deck.count, 3, "no fourth card, whatever its rank")
        XCTAssertFalse(round.deck.contains { $0.kind == .welcomeBack })
    }

    func testLaterHidesACardUntilTomorrowEvenAfterARelaunch() throws {
        var i = inputs { $0.mixUps = [mixUp()] }
        var round = deal(i)
        let id = try XCTUnwrap(round.deck.first?.id)
        round.ledger.snoozed.insert(id)
        // A relaunch reads the ledger back.
        let stored = try JSONDecoder.cramless.decode(NoticeLedger.self, from: JSONEncoder.cramless.encode(round.ledger))
        i.ledger = stored
        XCTAssertTrue(deal(i).deck.isEmpty, "hidden the rest of the day")
        // Tomorrow.
        now = cal.adding(days: 1, to: now)
        i.now = now
        i.ledger = stored.rolled(to: cal.dayKey(for: now), now: now, calendar: cal)
        XCTAssertEqual(deal(i).deck.first?.id, id, "and back")
    }

    func testActingOnACardKeepsItAwayForSevenDays() throws {
        var i = inputs { $0.mixUps = [mixUp()] }
        let round = deal(i)
        let id = try XCTUnwrap(round.deck.first?.id)
        var ledger = round.ledger
        ledger.acted[id] = cal.dayKey(for: now)
        for day in 1...7 {
            now = cal.adding(days: 1, to: now)
            i.now = now
            ledger = ledger.rolled(to: cal.dayKey(for: now), now: now, calendar: cal)
            i.ledger = ledger
            XCTAssertEqual(deal(i).deck.isEmpty, day < 7, "day \(day)")
        }
    }

    func testAResolvedCardDropsWithoutAWord() {
        var i = inputs { $0.mixUps = [mixUp()] }
        let round = deal(i)
        i.ledger = round.ledger
        i.mixUps = []
        XCTAssertTrue(deal(i).deck.isEmpty)
    }

    func testASwitchedOffKindNeverShows() {
        let midterm = exam(in: 9)
        let i = inputs {
            $0.settings.off = [.mixUp, .fading]
            $0.exams = [midterm]
            $0.mixUps = [mixUp()]
            $0.items = faded(8, on: midterm)
            $0.lookAlikes = [pair(in: 9, exam: midterm.id)]
        }
        XCTAssertEqual(deal(i).deck.map(\.kind), [.lookAlike])
    }

    func testNoCardsWhenAnyExamIsTomorrow() {
        let i = inputs {
            $0.exams = [exam(in: 1, title: "Chem quiz"), exam(in: 9)]
            $0.mixUps = [mixUp()]
            $0.days = days(9...14)
        }
        XCTAssertTrue(NoticeEngine(i).candidates().isEmpty)
    }

    func testPlaceCountsTheOnesAlreadySeenTo() throws {
        let midterm = exam(in: 9)
        var i = inputs {
            $0.exams = [midterm]
            $0.mixUps = [mixUp()]
            $0.lookAlikes = [pair(in: 9, exam: midterm.id)]
            $0.items = faded(8, on: midterm)
        }
        let round = deal(i)
        var slot = try XCTUnwrap(round.engine.slot(round.deck, ledger: round.ledger))
        XCTAssertEqual([slot.position, slot.count], [1, 3])
        var ledger = round.ledger
        ledger.snoozed.insert(slot.notice.id)
        i.ledger = ledger
        let next = deal(i)
        slot = try XCTUnwrap(next.engine.slot(next.deck, ledger: next.ledger))
        XCTAssertEqual([slot.position, slot.count], [2, 3], "after Later on the first of three")
        ledger = next.ledger
        ledger.acted[slot.notice.id] = cal.dayKey(for: now)
        i.ledger = ledger
        let last = deal(i)
        slot = try XCTUnwrap(last.engine.slot(last.deck, ledger: last.ledger))
        XCTAssertEqual([slot.position, slot.count], [3, 3])
    }

    func testACardANotificationOpenedShowsFirst() throws {
        let midterm = exam(in: 9)
        var i = inputs {
            $0.exams = [midterm]
            $0.mixUps = [mixUp()]
            $0.lookAlikes = [pair(in: 9, exam: midterm.id)]
            $0.items = faded(8, on: midterm)
        }
        let round = deal(i)
        XCTAssertEqual(round.deck.map(\.kind), [.fading, .mixUp, .lookAlike])
        var ledger = round.ledger
        ledger.front = try XCTUnwrap(round.deck.last?.linkID)
        i.ledger = ledger
        XCTAssertEqual(deal(i).deck.map(\.kind), [.lookAlike, .fading, .mixUp])
        // A fading card's link has no day in it: the card with today's id is the one it names.
        ledger.front = "fade-\(midterm.id.uuidString)"
        i.ledger = ledger
        XCTAssertEqual(deal(i).deck.first?.kind, .fading)
    }

    func testANewDayStartsOverAndOldRecordsGo() {
        var ledger = NoticeLedger()
        ledger.day = cal.dayKey(for: now)
        ledger.dealt = [.init(id: "x", kind: .mixUp)]
        ledger.snoozed = ["x"]
        ledger.acted = ["old": cal.dayKey(for: cal.adding(days: -40, to: now)), "recent": cal.dayKey(for: now)]
        ledger.seen = ["old": [cal.dayKey(for: cal.adding(days: -40, to: now))]]
        ledger.boosts = [PlanBoost(noticeID: "f", examID: UUID(), examTitle: "E", dayKey: cal.dayKey(for: now), minutes: 6, itemIDs: []),
                         PlanBoost(noticeID: "f", examID: UUID(), examTitle: "E", dayKey: cal.dayKey(for: cal.adding(days: 1, to: now)), minutes: 6, itemIDs: [])]
        let next = ledger.rolled(to: cal.dayKey(for: cal.adding(days: 1, to: now)), now: cal.adding(days: 1, to: now), calendar: cal)
        XCTAssertTrue(next.dealt.isEmpty)
        XCTAssertTrue(next.snoozed.isEmpty)
        XCTAssertEqual(next.acted.keys.sorted(), ["recent"])
        XCTAssertTrue(next.seen.isEmpty)
        XCTAssertEqual(next.boosts.count, 1, "yesterday's boost is over")
    }

    func testALedgerFromAnOlderVersionStillOpens() throws {
        let ledger = try JSONDecoder.cramless.decode(NoticeLedger.self, from: Data(#"{"day":"2026-10-22"}"#.utf8))
        XCTAssertEqual(ledger.day, "2026-10-22")
        XCTAssertTrue(ledger.boosts.isEmpty)
    }

    func testAddingAKindKeepsStoredSwitches() throws {
        let settings = try JSONDecoder.cramless.decode(NoticeSettings.self, from: Data(#"{"off":["mixUp","fromTheFuture"],"notify":false}"#.utf8))
        XCTAssertEqual(settings.off, [.mixUp], "an unknown kind is dropped")
        XCTAssertFalse(settings.notify)
        XCTAssertTrue(settings.allows(.mockOffer), "a new kind starts on")
        let empty = try JSONDecoder.cramless.decode(NoticeSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, NoticeSettings())
        XCTAssertEqual(NoticeKind.live, [.mixUp, .lookAlike, .fading, .welcomeBack, .mockOffer, .gap, .lectureDate, .tooEasy, .teachBack, .busyDay])
        for kind in ["gap", "lectureDate", "busyDay", "tooEasy", "teachBack", "sameIdea"] {
            XCTAssertNotNil(NoticeKind(rawValue: kind), "\(kind) is reserved")
        }
    }

    // MARK: Fading

    private func finder(goalMet: Bool = false, easyDays: [Int] = []) -> FadeFinder {
        FadeFinder(fsrs: FSRS(), calendar: cal, now: now, easyDays: easyDays, goalMet: goalMet)
    }

    private func rescues(_ items: [ItemSnapshot], _ exams: [ExamSnapshot], using finder: FadeFinder? = nil, today: Set<UUID> = [], boosted: Set<UUID> = [],
                         sources: [UUID: FadeSource] = [:], topics: [UUID: String] = [:]) -> [FadeRescue] {
        (finder ?? self.finder()).rescues(items: items, exams: exams, todayItems: today, boosted: boosted, sources: sources, topicNames: topics)
    }

    func testFadingCountsOnlyOverdueQuestionsUnderTheDimLine() throws {
        let midterm = exam(in: 6)
        let dim = faded(6, on: midterm)
        // Not overdue: due tomorrow, however low its forecast.
        var notDue = faded(1, on: midterm)[0]
        notDue.memory.due = cal.adding(days: 1, to: now)
        // Overdue but over the line on exam day: a solid memory.
        var solid = faded(1, on: midterm)[0]
        solid.memory.stability = 400
        // Never studied.
        let fresh = ItemSnapshot(courseID: course)
        // Another course.
        let other = faded(1, on: ExamSnapshot(courseID: UUID(), date: midterm.date))[0]
        let rescue = try XCTUnwrap(rescues(dim + [notDue, solid, fresh, other], [midterm]).first)
        XCTAssertEqual(rescue.dimCount, 6)
        XCTAssertEqual(ReviewOutcome.fadingRecall, 0.7, "the sky's dim line, not the exam's target")
    }

    func testFadingLeavesOutQuestionsOnlyOnAFinishedExam() throws {
        let over = UUID(), ahead = UUID()
        var past = exam(in: -3)
        past.scope = [over]
        var midterm = exam(in: 6)
        midterm.scope = [ahead]
        let done = faded(20, on: past, topic: over)
        let coming = faded(6, on: midterm, topic: ahead)
        let i = inputs {
            $0.items = done + coming
            $0.exams = [midterm]
            $0.finishedExams = [past]
        }
        let card = try XCTUnwrap(NoticeEngine(i).candidates().first { $0.kind == .fading })
        guard case .fading(let rescue) = card.evidence else { return XCTFail("a fading card") }
        XCTAssertEqual(rescue.dimCount, 6, "not the 20 from the exam that's over")
    }

    func testFadingLeavesOutTodaysSessionAndWhatsAlreadyBoosted() {
        let midterm = exam(in: 6)
        let items = faded(7, on: midterm)
        XCTAssertEqual(rescues(items, [midterm]).first?.dimCount, 7)
        XCTAssertEqual(rescues(items, [midterm], today: [items[0].id]).first?.dimCount, 6)
        XCTAssertTrue(rescues(items, [midterm], today: Set(items.prefix(3).map(\.id))).isEmpty, "4 left: fewer than 5")
        XCTAssertTrue(rescues(items, [midterm], boosted: Set(items.prefix(3).map(\.id))).isEmpty, "boosted ones don't fire again")
    }

    func testFadingNeedsAtLeastFiveAndAnExam3To14DaysAway() {
        XCTAssertTrue(rescues(faded(4, on: exam(in: 6)), [exam(in: 6)]).isEmpty)
        for (days, fires) in [(2, false), (3, true), (14, true), (15, false)] {
            let e = exam(in: days)
            XCTAssertEqual(!rescues(faded(6, on: e), [e]).isEmpty, fires, "\(days) days out")
        }
    }

    /// "88 reviews, cleared in 3 days" beside "34 questions will be dim" was false: what the sessions before the exam reach doesn't go dim.
    func testFadingCountsOnlyWhatTheSessionsBeforeTheExamCantReach() throws {
        let midterm = exam(in: 6)
        let goal = FadeFinder(fsrs: FSRS(), calendar: cal, now: now, dailySeconds: 15 * 60)
        // Tomorrow to Monday is 4 days of 15 minutes, and Tuesday the eve's 10: 70 minutes.
        let reach = 70.0 * 60
        let seconds = ItemKind.recall.typicalSeconds
        let cleared = faded(Int(reach / seconds), on: midterm, kind: .recall)
        XCTAssertTrue(rescues(cleared, [midterm], using: goal).isEmpty, "it all clears before the exam: no card")
        XCTAssertEqual(rescues(cleared, [midterm]).first?.dimCount, cleared.count, "with no goal to reach them, they all count")

        let tooMany = faded(Int(reach / seconds) + 20, on: midterm, kind: .recall)
        XCTAssertEqual(rescues(tooMany, [midterm], using: goal).first?.dimCount, 20, "only what is left after those days")
        XCTAssertTrue(rescues(faded(Int(reach / seconds) + 4, on: midterm, kind: .recall), [midterm], using: goal).isEmpty, "4 left: fewer than 5")
    }

    func testTheReachIsSharedWithTheNearerExamAndShrinksOnLighterDays() throws {
        let midterm = exam(in: 6)
        var quiz = exam(in: 3, title: "Chem quiz")
        quiz.courseID = UUID()
        let seconds = ItemKind.recall.typicalSeconds
        let reach = 70.0 * 60
        let mine = faded(Int(reach / seconds), on: midterm, kind: .recall)
        // The quiz's own 30 go first, so 30 of the midterm's are left over.
        let theirs = faded(30, on: quiz, kind: .recall)
        let goal = FadeFinder(fsrs: FSRS(), calendar: cal, now: now, dailySeconds: 15 * 60)
        XCTAssertEqual(rescues(mine + theirs, [midterm, quiz], using: goal).first?.examID, midterm.id)
        XCTAssertEqual(rescues(mine + theirs, [midterm, quiz], using: goal).first?.dimCount, 30)
        // A lighter day holds half the goal: tomorrow's 7.5 minutes less reach, 9 own-words questions at 50 seconds.
        let friday = Calendar.weekday(dayNumber: cal.dayNumber(for: now) + 1)
        let lighter = FadeFinder(fsrs: FSRS(), calendar: cal, now: now, easyDays: [friday], dailySeconds: 15 * 60)
        XCTAssertEqual(rescues(faded(Int(reach / seconds) + 1, on: midterm, kind: .recall), [midterm], using: lighter).first?.dimCount,
                       Int((7.5 * 60 / seconds).rounded(.up)) + 1)
    }

    func testFixMyWeekSkipsLighterDaysAndEves() throws {
        // Thursday: an exam the Wednesday after (6 days), another on Sunday (its eve is Saturday, its day Sunday), Fridays lighter.
        let midterm = exam(in: 6)
        let sunday = exam(in: 3, title: "Chem quiz")
        var chemCourse = sunday
        chemCourse.courseID = UUID()
        let friday = Calendar.weekday(dayNumber: cal.dayNumber(for: now) + 1)
        // 20 own-words questions at 50 seconds: over 16 minutes, so it wants two days.
        let items = faded(20, on: midterm, kind: .recall)
        let rescue = try XCTUnwrap(rescues(items, [midterm, chemCourse], using: finder(easyDays: [friday])).first)
        XCTAssertEqual(rescue.days.map(\.offset), [0, 4], "today, then past the lighter Friday, the Saturday eve and the Sunday exam")
    }

    func testFixMyWeekSkipsTodayOnceTheGoalIsMet() throws {
        let midterm = exam(in: 6)
        let rescue = try XCTUnwrap(rescues(faded(10, on: midterm), [midterm], using: finder(goalMet: true)).first)
        XCTAssertEqual(rescue.days.first?.offset, 1)
    }

    func testFixMyWeekNeverUsesTheExamsEve() throws {
        let midterm = exam(in: 3)
        let rescue = try XCTUnwrap(rescues(faded(200, on: midterm, kind: .recall), [midterm]).first)
        XCTAssertEqual(rescue.days.map(\.offset), [0, 1], "day 2 is the eve")
    }

    func testMinutesAddUpAtMostTenADayOnAtMostThreeDays() throws {
        let midterm = exam(in: 9)
        let seconds = ItemKind.flashcard.typicalSeconds
        let count = 18
        let rescue = try XCTUnwrap(rescues(faded(count, on: midterm), [midterm]).first)
        let total = Double(count) * seconds
        XCTAssertEqual(rescue.days.count, max(1, Int((total / 600).rounded(.up))))
        XCTAssertEqual(rescue.minutesPerDay, Int((total / Double(rescue.days.count) / 60).rounded(.up)))
        XCTAssertEqual(rescue.itemIDs.count, count)
        // Far more than fits: 3 days of 10 minutes, the rest left out.
        let huge = try XCTUnwrap(rescues(faded(400, on: midterm, kind: .recall), [midterm]).first)
        XCTAssertEqual(huge.days.count, 3)
        XCTAssertEqual(huge.minutesPerDay, 10)
        XCTAssertEqual(huge.dimCount, 400)
        XCTAssertLessThan(huge.itemIDs.count, 400)
        XCTAssertEqual(huge.itemIDs.count, Int(30 * 60 / ItemKind.recall.typicalSeconds))
    }

    func testTheDimmestComeFirst() throws {
        let midterm = exam(in: 9)
        var items = faded(40, on: midterm)
        items[17].memory.stability = 0.4
        let rescue = try XCTUnwrap(rescues(items, [midterm]).first)
        XCTAssertEqual(rescue.days.first?.itemIDs.first, items[17].id)
    }

    func testKeptCountsWhatIsOverTheLineOnExamDayAfterItsReview() throws {
        let midterm = exam(in: 6)
        let fsrs = FSRS()
        let items = faded(9, on: midterm)
        let rescue = try XCTUnwrap(rescues(items, [midterm]).first)
        // Every question reviewed today, so the expectation is easy to work out here too.
        let expected = items.filter { item in
            let step = fsrs.expectedReview(of: item.memory, at: max(now, cal.startOfDay(for: now).addingTimeInterval(18 * 3600)))!
            return step.recall(at: midterm.date, fsrs: fsrs) >= ReviewOutcome.fadingRecall
        }.count
        XCTAssertEqual(rescue.kept, expected)
        XCTAssertGreaterThanOrEqual(rescue.kept, FadeFinder.minimumQuestions)
    }

    func testTheCardNamesWhereTheQuestionsCameFrom() throws {
        let midterm = exam(in: 9)
        let topicA = UUID(), topicB = UUID()
        let items = faded(6, on: midterm, topic: topicA) + faded(4, on: midterm, topic: topicB)
        let lecture = FadeSource(id: UUID(), name: "Lecture 3"), page = FadeSource(id: UUID(), name: "Textbook")
        var sources: [UUID: FadeSource] = [:]
        for (index, item) in items.enumerated() { sources[item.id] = index < 7 ? lecture : page }
        XCTAssertEqual(rescues(items, [midterm], sources: sources).first?.origin, .source("Lecture 3"), "70% share a source")
        XCTAssertEqual(rescues(items, [midterm], topics: [topicA: "Meiosis"]).first?.origin, .topic("Meiosis"), "60% share a topic")
        let even = faded(5, on: midterm, topic: topicA) + faded(5, on: midterm, topic: topicB)
        XCTAssertNil(rescues(even, [midterm], topics: [topicA: "Meiosis", topicB: "Genetics"]).first?.origin, "half isn't most")
    }

    // MARK: Welcome back

    private func welcomed(lastStudied back: Int, studyDays: Int = 5, seen: [String] = []) -> Notice? {
        let id = "back-\(cal.dayKey(for: cal.adding(days: -back, to: cal.startOfDay(for: now))))"
        let i = inputs {
            $0.items = [ItemSnapshot(courseID: course)]
            $0.days = days(back...(back + studyDays - 1))
            $0.bestStreak = 23
            $0.ledger.seen[id] = seen
        }
        return NoticeEngine(i).candidates().first { $0.kind == .welcomeBack }
    }

    func testWelcomeBackAfterAWeekAway() {
        XCTAssertNil(welcomed(lastStudied: 6), "6 days: no")
        XCTAssertEqual(welcomed(lastStudied: 7)?.rank, 1000, "7 days: yes, first")
        XCTAssertNil(welcomed(lastStudied: 0), "studied today")
    }

    func testWelcomeBackIsNeverForSomeoneNew() {
        XCTAssertNil(welcomed(lastStudied: 8, studyDays: 2))
        XCTAssertNotNil(welcomed(lastStudied: 8, studyDays: 3))
    }

    func testWelcomeBackShowsOnTwoDaysOfAnAbsence() {
        let today = cal.dayKey(for: now)
        let earlier = cal.dayKey(for: cal.adding(days: -1, to: now)), earliest = cal.dayKey(for: cal.adding(days: -2, to: now))
        XCTAssertNotNil(welcomed(lastStudied: 9, seen: [earlier]))
        XCTAssertNotNil(welcomed(lastStudied: 9, seen: [earlier, today]), "still today")
        XCTAssertNil(welcomed(lastStudied: 9, seen: [earliest, earlier]), "two days already")
    }

    func testWelcomeBackIsNeverSentAsANotification() throws {
        XCTAssertEqual(welcomed(lastStudied: 8)?.notifiable, false)
    }

    func testWelcomeBackPromisesOnlyWhatIsTrue() throws {
        let card = NoticeContent.card(try XCTUnwrap(welcomed(lastStudied: 8)), firstName: "Maya", now: now, calendar: cal)
        XCTAssertEqual(card.title, "Welcome back, Maya")
        XCTAssertEqual(card.detail, "Your best streak, 23 days, is still yours.", "the button says the 5 minutes")
        XCTAssertEqual(card.action?.title, "Start 5 min")
        XCTAssertNil(card.cost, "no AI: no cost word")
        if case .session(let kind, let minutes, _, _, _)? = card.action?.run {
            XCTAssertEqual(kind, .daily)
            XCTAssertEqual(minutes, 5)
        } else { XCTFail("a 5-minute session") }
        XCTAssertEqual(NoticeContent.welcomeBackDetail(best: 1), "Your stars waited for you.")
        for word in ["restore", "back to", "lost"] { XCTAssertFalse(card.detail.lowercased().contains(word), word) }
    }

    // MARK: Mock exams

    private func mockOffer(for exam: ExamSnapshot, questions: Int = 20) -> NoticeMockOffer {
        NoticeMockOffer(examID: exam.id, examTitle: exam.title, examDate: exam.date, questions: questions, minutes: 25)
    }

    func testAMockIsOfferedTwoToSevenDaysBeforeItsExamAndNeverOnTheEveOrTheDay() {
        for (days, shown) in [(0, false), (1, false), (2, true), (7, true), (8, false)] {
            let midterm = exam(in: days)
            let deck = deal(inputs {
                $0.exams = [midterm]
                $0.mockOffers = [mockOffer(for: midterm)]
            }).deck
            XCTAssertEqual(deck.contains { $0.kind == .mockOffer }, shown, "\(days) days out")
        }
    }

    func testAnotherExamsEveSilencesTheMockToo() {
        let midterm = exam(in: 5), quiz = exam(in: 1)
        XCTAssertTrue(deal(inputs {
            $0.exams = [midterm, quiz]
            $0.mockOffers = [mockOffer(for: midterm)]
        }).deck.isEmpty)
    }

    func testTheNearestExamsMockIsTheOneDealt() throws {
        let later = exam(in: 7), sooner = exam(in: 3)
        let deck = deal(inputs {
            $0.exams = [later, sooner]
            $0.mockOffers = [mockOffer(for: later), mockOffer(for: sooner)]
        }).deck
        XCTAssertEqual(deck.count, 1, "one card per kind")
        XCTAssertEqual(try XCTUnwrap(deck.first).examID, sooner.id)
        XCTAssertGreaterThan(NoticeEngine.Rank.mockOffer(daysLeft: 2), NoticeEngine.Rank.mockOffer(daysLeft: 7))
    }

    func testAMockCardSaysItsSizeAndOpensTheMock() throws {
        let midterm = exam(in: 5)
        let i = inputs {
            $0.exams = [midterm]
            $0.mockOffers = [mockOffer(for: midterm)]
        }
        let notice = try XCTUnwrap(deal(i).deck.first)
        let card = NoticeContent.card(notice, firstName: "Maya", now: now, calendar: cal)
        XCTAssertEqual(card.title, "A mock exam for your \(midterm.title)")
        XCTAssertEqual(card.detail, "20 questions like the real one · 25 min")
        XCTAssertEqual(card.action?.title, "Take it")
        XCTAssertEqual(card.action?.run, .takeMock(examID: midterm.id))
        XCTAssertEqual(card.link, .exam(midterm.id))
        XCTAssertNil(card.cost, "its short answers may use AI, so it can't say No AI, and there's no cost word")
    }

    func testAMockCardIsNeverSentAndHasASwitch() {
        let midterm = exam(in: 5)
        let i = inputs {
            $0.exams = [midterm]
            $0.mockOffers = [mockOffer(for: midterm)]
        }
        let engine = NoticeEngine(i)
        XCTAssertTrue(engine.pings(engine.candidates()).isEmpty)
        XCTAssertNil(NoticeContent.pingBody(Notice(id: "o", kind: .mockOffer, rank: 0, evidence: .mockOffer(mockOffer(for: midterm)))))
        var off = i
        off.settings.off = [.mockOffer]
        XCTAssertTrue(NoticeEngine(off).candidates().isEmpty)
    }

    // MARK: Mix-ups

    func testAMixUpSpottedBeforeAnyMissSaysSo() {
        let note = ConfusionNote(id: UUID(), name: "Metaphase vs telophase", missCount: 0, recentMisses: 0, recentAnswers: 0)
        let card = NoticeContent.card(for: note)
        XCTAssertEqual(card.title, "Metaphase vs telophase", "named by its pair")
        XCTAssertEqual(card.detail, "Spotted before any mix-up.")
        XCTAssertEqual(card.action?.title, "Fix it · 2 min")
        let missed = ConfusionNote(id: UUID(), name: "Metaphase vs telophase", missCount: 1, recentMisses: 1, recentAnswers: 1)
        XCTAssertEqual(NoticeContent.card(for: missed).title, "Metaphase vs telophase")
        XCTAssertEqual(NoticeContent.card(for: missed).detail, "Missed it lately.", "no question over \"Fix it\"")
        var one = missed
        one.questions = 1
        XCTAssertEqual(NoticeContent.card(for: one).action?.title, "Fix it · 1 min")
        // A pair's names keep their capitals; a topic-shaped one, or one with no name, says its own line.
        XCTAssertEqual(NoticeContent.card(for: ConfusionNote(id: UUID(), name: "Darcy vs Bingley", missCount: 2, recentMisses: 0, recentAnswers: 0)).title,
                       "Darcy vs Bingley")
        XCTAssertEqual(NoticeContent.card(for: ConfusionNote(id: UUID(), name: "Mendelian genetics", missCount: 2, recentMisses: 0, recentAnswers: 0)).title,
                       "Mendelian genetics: still tripping you up.")
    }

    /// A course whose finished exam covers its questions, and an exam still to come in another course (or none).
    private func finishedMixUp(misses: Int = 4, another: Bool = true) throws -> Notice {
        let item = ItemSnapshot(courseID: course)
        var past = exam(in: -3)
        past.courseID = course
        var next = exam(in: 12, title: "Chem 110 Quiz")
        next.courseID = UUID()
        return try XCTUnwrap(NoticeEngine(inputs {
            $0.items = [item]
            $0.exams = another ? [next] : []
            $0.finishedExams = [past]
            $0.mixUps = [mixUp(misses: misses, items: [item.id])]
        }).candidates().first)
    }

    func testAMixUpOnAFinishedExamWaitsBehindEverythingForTheNextExam() throws {
        let card = try finishedMixUp(misses: 10)
        XCTAssertEqual(card.rank, NoticeEngine.Rank.finishedMixUp(misses: 10))
        XCTAssertFalse(card.notifiable)
        XCTAssertNil(card.examID)
        // The lowest anything for an exam can reach: a barely alike pair, three weeks out.
        let lowest = NoticeEngine.Rank.lookAlike(similarity: 0.45, linked: false, daysLeft: LookAlikeFinder.examDays)
        XCTAssertLessThan(card.rank, lowest)
    }

    func testAMixUpKeepsItsPlaceWithNoExamToCome() throws {
        XCTAssertEqual(try finishedMixUp(misses: 4, another: false).rank, NoticeEngine.Rank.mixUp(misses: 4), "nothing to wait for")
    }

    func testAMixUpInACourseThatNeverHadAnExamKeepsItsPlace() throws {
        let item = ItemSnapshot(courseID: course)
        var next = exam(in: 12, title: "Chem 110 Quiz")
        next.courseID = UUID()
        let card = try XCTUnwrap(NoticeEngine(inputs {
            $0.items = [item]
            $0.exams = [next]
            $0.mixUps = [mixUp(items: [item.id])]
        }).candidates().first)
        XCTAssertEqual(card.rank, NoticeEngine.Rank.mixUp(misses: mixUp().note.missCount))
    }

    func testAMixUpStillOnAnExamToComeIsntBehindTheStudent() throws {
        let item = ItemSnapshot(courseID: course)
        var past = exam(in: -3)
        past.courseID = course
        let midterm = exam(in: 6)
        let card = try XCTUnwrap(NoticeEngine(inputs {
            $0.items = [item]
            $0.exams = [midterm]
            $0.finishedExams = [past]
            $0.mixUps = [mixUp(items: [item.id])]
        }).candidates().first)
        XCTAssertEqual(card.rank, NoticeEngine.Rank.mixUp(misses: mixUp().note.missCount))
        XCTAssertEqual(card.examID, midterm.id)
    }

    func testAMixUpMayNotifyOnlyWithAnExamInAWeek() throws {
        let item = ItemSnapshot(courseID: course)
        func card(_ days: Int) throws -> Notice {
            try XCTUnwrap(NoticeEngine(inputs {
                $0.items = [item]
                $0.exams = [exam(in: days)]
                $0.mixUps = [mixUp(items: [item.id])]
            }).candidates().first)
        }
        XCTAssertTrue(try card(7).notifiable)
        XCTAssertFalse(try card(8).notifiable)
    }

    // MARK: Look-alikes

    private struct Corpus: Decodable {
        struct Course: Decodable {
            var name: String
            var items: [[RawValue]]
            var lookAlikes: [[String]]
            var never: [[String]]
            var heldOut: Bool?
        }
        enum RawValue: Decodable {
            case text(String), list([String])
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) { self = .text(s) } else { self = .list(try c.decode([String].self)) }
            }
            var text: String { if case .text(let s) = self { return s } else { return "" } }
            var list: [String] { if case .list(let l) = self { return l } else { return [] } }
        }
        var courses: [Course]
    }

    private func corpus() throws -> Corpus {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/lookalike-corpus.json")
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }

    /// What the finder reports on one of the corpus's courses, as term pairs.
    private func found(in c: Corpus.Course) -> [String] {
        let courseID = UUID()
        var topics: [String: UUID] = [:]
        let items = c.items.map { row -> LookAlikeItem in
            let topic = row[1].text
            let id = topics[topic] ?? UUID()
            topics[topic] = id
            let answer = row[4].text
            return LookAlikeItem(id: UUID(), courseID: courseID, topicID: id, kind: ItemKind(rawValue: row[2].text)!, prompt: row[3].text, answer: answer,
                                 accepted: [answer], distractors: row[5].list, studied: true, recall: 0.6)
        }
        let exam = ExamSnapshot(courseID: courseID, title: c.name, date: cal.adding(days: 10, to: now))
        return LookAlikeFinder(calendar: cal, now: now).pairs(items: items, exams: [exam], confusions: [])
            .map { Self.label(ConfusionFinder.normalize($0.termA), ConfusionFinder.normalize($0.termB)) }
    }

    private static func label(_ a: String, _ b: String) -> String { a < b ? "\(a) | \(b)" : "\(b) | \(a)" }

    /// The gate on the finder: on decks labelled by hand, at least 90% of what it reports is a real look-alike, and it never reports a trap.
    /// It may miss pairs (that only means one card fewer), so what it finds is reported here, not held to a number as tight.
    func testTheCorpusPrecisionIsAtLeastNinetyPercent() throws {
        var reported = 0, right = 0, labelled = 0, heldOutReported = 0, heldOutRight = 0
        var wrong: [String] = []
        for course in try corpus().courses {
            let truth = Set(course.lookAlikes.map { Self.label($0[0], $0[1]) })
            let traps = Set(course.never.map { Self.label($0[0], $0[1]) })
            labelled += truth.count
            // A label names real terms of the deck, or it would never match.
            let terms = Set(course.items.compactMap { row -> String? in
                LookAlikeItem.term(kind: ItemKind(rawValue: row[2].text)!, prompt: row[3].text, answer: row[4].text).map(ConfusionFinder.normalize)
            })
            for name in course.lookAlikes.joined() { XCTAssertTrue(terms.contains(name), "\(course.name): \(name) isn't a term of the deck") }
            for pair in found(in: course) {
                reported += 1
                if course.heldOut == true { heldOutReported += 1 }
                XCTAssertFalse(traps.contains(pair), "\(course.name): \(pair) is a trap")
                if truth.contains(pair) {
                    right += 1
                    if course.heldOut == true { heldOutRight += 1 }
                } else {
                    wrong.append("\(course.name): \(pair)")
                }
            }
        }
        let precision = Double(right) / Double(max(1, reported))
        print("LookAlikeFinder corpus: \(reported) reported, \(right) right, \(labelled) labelled; precision \(precision), recall \(Double(right) / Double(max(1, labelled)))")
        print("Held-out decks: \(heldOutReported) reported, \(heldOutRight) right")
        print("Not labelled look-alikes: \(wrong)")
        XCTAssertGreaterThanOrEqual(reported, 30, "it finds a good number")
        XCTAssertGreaterThanOrEqual(precision, 0.9, "wrong: \(wrong)")
        XCTAssertGreaterThanOrEqual(Double(heldOutRight) / Double(max(1, heldOutReported)), 0.9, "on the decks the rules weren't tuned on")
    }

    private func look(_ id: UUID = UUID(), term: String, topic: UUID? = nil, kind: ItemKind = .flashcard, prompt: String? = nil, answer: String? = nil,
                      wrong: [String] = [], studied: Bool = true, recall: Double = 0.6, courseID: UUID? = nil) -> LookAlikeItem {
        LookAlikeItem(id: id, courseID: courseID ?? course, topicID: topic, kind: kind, prompt: prompt ?? term, answer: answer ?? "What \(term) means, at some length.",
                      accepted: [], distractors: wrong, studied: studied, recall: recall)
    }

    private func pairs(_ items: [LookAlikeItem], days: Int = 9, confusions: [ConfusionSnapshot] = []) -> [LookAlikePair] {
        LookAlikeFinder(calendar: cal, now: now).pairs(items: items, exams: [exam(in: days)], confusions: confusions)
    }

    func testThePairsIDDoesntDependOnOrder() {
        let topic = UUID()
        let a = look(term: "Mitosis", topic: topic), b = look(term: "Meiosis", topic: topic)
        XCTAssertEqual(pairs([a, b]).first?.id, pairs([b, a]).first?.id)
        XCTAssertEqual(pairs([a, b]).first?.termA, "Meiosis", "named in alphabetical order")
    }

    func testLinksRankFirst() {
        let topic = UUID()
        let found = pairs([look(term: "Mitosis", topic: topic), look(term: "Meiosis", topic: topic),
                           look(term: "Prophase", topic: topic, kind: .mcq, prompt: "First phase?", answer: "Prophase", wrong: ["Cytokinesis"]),
                           look(term: "Cytokinesis", topic: topic, kind: .mcq, prompt: "Last step?", answer: "Cytokinesis", wrong: ["Prophase"])])
        XCTAssertEqual(found.first?.termA, "Cytokinesis")
        XCTAssertEqual(found.first?.linked, true)
        XCTAssertEqual(found.count, 2)
    }

    func testALinkBothWaysIsEnoughAndOneWayNeedsMore() {
        let cells = UUID(), proteins = UUID()
        func mcq(_ answer: String, _ wrong: String, topic: UUID, prompt: String) -> LookAlikeItem {
            look(term: answer, topic: topic, kind: .mcq, prompt: prompt, answer: answer, wrong: [wrong])
        }
        // Both ways round: enough, even across topics.
        XCTAssertEqual(pairs([mcq("Mitochondria", "Ribosome", topic: cells, prompt: "What makes ATP?"),
                              mcq("Ribosome", "Mitochondria", topic: proteins, prompt: "Where are proteins built?")]).first?.linked, true)
        // One way, however much the writer meant it: not on its own.
        let ribosome = look(term: "Ribosome", topic: cells)
        XCTAssertTrue(pairs([mcq("Mitochondria", "Ribosome", topic: cells, prompt: "What makes ATP?"), ribosome]).isEmpty)
        // One way with alike prompts in one topic: yes. Across topics: no.
        let arteries = mcq("Arteries", "Veins", topic: cells, prompt: "Which vessels carry blood away from the heart?")
        let veins = { (t: UUID) in mcq("Veins", "Capillaries", topic: t, prompt: "Which vessels carry blood back to the heart?") }
        XCTAssertEqual(pairs([arteries, veins(cells)]).count, 1)
        XCTAssertTrue(pairs([arteries, veins(proteins)]).isEmpty)
    }

    func testTwoKindsOfOneThingAreAlikeButOneWordInCommonIsnt() {
        let topic = UUID()
        func found(_ a: String, _ b: String) -> Bool { !pairs([look(term: a, topic: topic), look(term: b, topic: topic)]).isEmpty }
        XCTAssertTrue(found("Classical conditioning", "Operant conditioning"))
        XCTAssertTrue(found("Positive reinforcement", "Negative reinforcement"))
        XCTAssertFalse(found("Cell wall", "Cell cycle"), "a shared first word says nothing")
        XCTAssertTrue(found("Andrew Jackson", "Andrew Johnson"), "what differs is alike")
        XCTAssertTrue(found("la casa", "la cosa"))
        XCTAssertFalse(found("la nota", "la tarea"))
        XCTAssertFalse(found("la casa", "la mesa"))
        XCTAssertTrue(found("el gato", "el pato"))
        XCTAssertTrue(found("la madre", "el padre"), "little words at the start don't count")
    }

    func testAPairNeedsAnExamInThreeWeeksWithBothOnIt() {
        let topic = UUID()
        let a = look(term: "Mitosis", topic: topic), b = look(term: "Meiosis", topic: topic)
        XCTAssertEqual(pairs([a, b], days: 21).count, 1)
        XCTAssertTrue(pairs([a, b], days: 22).isEmpty)
        var scoped = exam(in: 9)
        scoped.scope = [UUID()]
        XCTAssertTrue(LookAlikeFinder(calendar: cal, now: now).pairs(items: [a, b], exams: [scoped], confusions: []).isEmpty, "not in the exam's scope")
    }

    func testAPairNeedsSomethingStudiedAndNotAllSolid() {
        let topic = UUID()
        XCTAssertTrue(pairs([look(term: "Mitosis", topic: topic, studied: false), look(term: "Meiosis", topic: topic, studied: false)]).isEmpty)
        XCTAssertEqual(pairs([look(term: "Mitosis", topic: topic, studied: false), look(term: "Meiosis", topic: topic)]).count, 1)
        XCTAssertTrue(pairs([look(term: "Mitosis", topic: topic, recall: 0.95), look(term: "Meiosis", topic: topic, recall: 0.95)]).isEmpty)
    }

    func testAPairIsSkippedOnceItsQuestionsAreInAMixUpOrRefused() {
        let topic = UUID()
        let a = look(term: "Mitosis", topic: topic), b = look(term: "Meiosis", topic: topic)
        let other = look(term: "Meiosis", topic: topic, kind: .flashcard, prompt: "Meiosis")
        let open = ConfusionSnapshot(id: UUID(), courseID: course, name: "x", itemIDs: [a.id, UUID()], status: .open)
        XCTAssertTrue(pairs([a, b], confusions: [open]).isEmpty, "one of them is in an open mix-up")
        for status in [ConfusionStatus.dismissed, .fixed] {
            let known = ConfusionSnapshot(id: UUID(), courseID: course, name: "x", itemIDs: [a.id, b.id], status: status)
            XCTAssertTrue(pairs([a, b], confusions: [known]).isEmpty, "\(status)")
            XCTAssertTrue(pairs([a, b, other], confusions: [known]).isEmpty, "another question with the same name is the same pair")
        }
    }

    func testTheSameWordInAnotherFormIsNoPair() {
        for (x, y) in [("chromosome", "chromosomes"), ("mitochondrion", "mitochondria"), ("fibre", "fiber"), ("colour", "color"), ("bacterium", "bacteria")] {
            XCTAssertTrue(LookAlikeFinder.sameWord(x, y), "\(x), \(y)")
        }
        for (x, y) in [("chromatid", "chromatin"), ("mitosis", "meiosis"), ("repression", "regression")] {
            XCTAssertFalse(LookAlikeFinder.sameWord(x, y), "\(x), \(y)")
        }
    }

    func testTermsAreNamesNotSentencesNumbersOrWordsThatNameNothing() {
        XCTAssertEqual(LookAlikeItem.term(kind: .mcq, prompt: "Which?", answer: "Metaphase."), "Metaphase")
        XCTAssertEqual(LookAlikeItem.term(kind: .flashcard, prompt: "Genotype", answer: "The alleles an organism has."), "Genotype")
        XCTAssertEqual(LookAlikeItem.term(kind: .flashcard, prompt: "la casa", answer: "the house"), "la casa", "a card's front names it")
        XCTAssertNil(LookAlikeItem.term(kind: .recall, prompt: "Mitosis", answer: "It makes two identical cells from one."))
        for answer in ["True", "No", "Increases", "All of the above", "Group 2", "1848", "pH"] {
            XCTAssertNil(LookAlikeItem.term(kind: .mcq, prompt: "Which?", answer: answer), answer)
        }
        XCTAssertNil(LookAlikeItem.term(kind: .flashcard, prompt: "What is it?", answer: "It makes two identical cells from one."))
    }

    func testTheRulesLessonSetsTheTwoSideBySide() {
        let a = LookAlikeSide(itemID: UUID(), term: "Metaphase", clue: "In which phase do chromosomes line up?", topic: "Phases", prompt: "In which phase do chromosomes line up?", answer: "Metaphase")
        let b = LookAlikeSide(itemID: UUID(), term: "Telophase", clue: "New nuclear envelopes form around each set.", topic: "Phases", prompt: "Telophase", answer: "New nuclear envelopes form around each set.")
        let out = LocalConfusions.sideBySide(a, b)
        XCTAssertEqual(out.name, "Metaphase vs telophase")
        XCTAssertEqual(Set(out.itemIds), [a.itemID.uuidString, b.itemID.uuidString])
        XCTAssertEqual(out.questions.count, 2)
        XCTAssertTrue(out.lesson.contains("Metaphase"))
        XCTAssertTrue(out.lesson.contains("New nuclear envelopes"))
        XCTAssertFalse(out.lesson.contains("?."), "a question keeps its own mark")
        for question in out.questions {
            XCTAssertEqual(question.kind, .mcq)
            XCTAssertEqual(Set(question.choices.map(\.text)), ["Metaphase", "Telophase"])
            XCTAssertEqual(question.choices.filter(\.correct).map(\.text), [question.answer])
            XCTAssertFalse(question.prompt.isEmpty)
        }
        XCTAssertEqual(out.questions[0].prompt, "In which phase do chromosomes line up?")
        XCTAssertTrue(out.questions[1].prompt.contains("New nuclear envelopes"), "a card's front would give it away, so its back is asked")
    }

    // MARK: Cost

    func testCostLabelsFollowTheRoute() throws {
        let midterm = exam(in: 9)
        func card(cloud: Bool) throws -> CapNotice {
            let i = inputs {
                $0.exams = [midterm]
                $0.lookAlikes = [pair(in: 9, exam: midterm.id)]
                $0.cloudLessons = cloud
            }
            return NoticeContent.card(try XCTUnwrap(NoticeEngine(i).candidates().first), firstName: "", now: now, calendar: cal)
        }
        XCTAssertEqual(try card(cloud: true).cost, "Uses Cloud AI")
        XCTAssertNil(try card(cloud: false).cost, "no AI: no cost word")
        XCTAssertNil(NoticeContent.costLine(.none))
        XCTAssertEqual(NoticeContent.costLine(.drafts(1)), "Uses Cloud AI")

        // A mix-up's fix opens on a lesson Cloud AI writes when it may; one question's recap is the rules'.
        func fixCard(cloud: Bool, questions: Int) throws -> CapNotice {
            var one = mixUp()
            one.note.questions = questions
            let i = inputs {
                $0.mixUps = [one]
                $0.cloudLessons = cloud
            }
            return NoticeContent.card(try XCTUnwrap(NoticeEngine(i).candidates().first), firstName: "", now: now, calendar: cal)
        }
        XCTAssertEqual(try fixCard(cloud: true, questions: 2).cost, "Uses Cloud AI")
        XCTAssertNil(try fixCard(cloud: false, questions: 2).cost)
        XCTAssertNil(try fixCard(cloud: true, questions: 1).cost)
        XCTAssertNil(NoticeContent.costLine(.free))
    }

    /// What the look-alike's card says it costs comes from the route: a person under 13 never reaches the cloud, whatever else is true.
    func testCloudLessonsFollowTheRouteAndTheUnder13Rule() {
        func route(age: AIAgeGate, consent: Bool = true) -> AIRoute {
            AIRouting.route(AIRouteContext(job: .confusions, mode: .relay, consent: consent, sendPhotos: false, onDevice: .available, quota: .unmetered, plan: .free, age: age))
        }
        XCTAssertTrue(route(age: .adult).usesCloud)
        XCTAssertTrue(route(age: .minor).usesCloud)
        XCTAssertFalse(route(age: .child).usesCloud)
        XCTAssertFalse(route(age: .adult, consent: false).usesCloud)
    }

    // MARK: Pings

    private func pingInputs(examIn days: Int, _ change: (inout NoticeInputs) -> Void = { _ in }) -> NoticeInputs {
        let midterm = exam(in: days)
        return inputs {
            $0.exams = [midterm]
            $0.lookAlikes = [pair(in: days, exam: midterm.id)]
            change(&$0)
        }
    }

    private func pings(_ i: NoticeInputs) -> [(notice: Notice, dayOffset: Int)] {
        let engine = NoticeEngine(i)
        return engine.pings(engine.candidates())
    }

    func testPingsOnlyInTheWeekBeforeTheExam() {
        for (days, offsets) in [(7, [1]), (6, [0, 1]), (3, [0, 1]), (2, [0]), (1, [])] as [(Int, [Int])] {
            // One candidate: tomorrow's is the same card, for when today's time has passed (the planner sends it once).
            let found = pings(pingInputs(examIn: days)).map(\.dayOffset)
            XCTAssertEqual(found, offsets, "\(days) days out")
        }
    }

    func testPingsOnlyForCardsThatMayNotify() {
        let i = inputs {
            $0.items = [ItemSnapshot(courseID: course)]
            $0.days = days(9...14)
            $0.exams = [exam(in: 5)]
        }
        XCTAssertEqual(NoticeEngine(i).candidates().first?.kind, .welcomeBack)
        XCTAssertTrue(pings(i).isEmpty, "welcome back never notifies")
    }

    func testAPingRespectsTheSwitch() {
        XCTAssertFalse(pings(pingInputs(examIn: 5)).isEmpty)
        XCTAssertTrue(pings(pingInputs(examIn: 5) { $0.settings.notify = false }).isEmpty)
        XCTAssertTrue(pings(pingInputs(examIn: 5) { $0.settings.off = [.lookAlike] }).isEmpty)
    }

    func testACardSeenTodayIsntSentToday() throws {
        let base = pingInputs(examIn: 5)
        let id = try XCTUnwrap(NoticeEngine(base).candidates().first?.id)
        let found = pings(pingInputs(examIn: 5) {
            $0.lookAlikes = base.lookAlikes
            $0.ledger.seen[id] = [self.cal.dayKey(for: self.now)]
        })
        XCTAssertEqual(found.map(\.dayOffset), [1], "tomorrow, then")
    }

    func testLaterMakesItTomorrowsCandidate() throws {
        let base = pingInputs(examIn: 5)
        let id = try XCTUnwrap(NoticeEngine(base).candidates().first?.id)
        let found = pings(pingInputs(examIn: 5) {
            $0.lookAlikes = base.lookAlikes
            $0.ledger.snoozed = [id]
        })
        XCTAssertEqual(found.map(\.dayOffset), [1])
    }

    func testEachCardIsSentOnce() throws {
        let base = pingInputs(examIn: 5)
        let card = try XCTUnwrap(NoticeEngine(base).candidates().first)
        let sent = pings(pingInputs(examIn: 5) {
            $0.lookAlikes = base.lookAlikes
            $0.ledger.pinged[card.linkID] = self.now.addingTimeInterval(-3600)
        })
        XCTAssertTrue(sent.isEmpty, "already went out")
        let planned = pings(pingInputs(examIn: 5) {
            $0.lookAlikes = base.lookAlikes
            $0.ledger.pinged[card.linkID] = self.now.addingTimeInterval(3600)
        })
        XCTAssertEqual(Set(planned.map(\.notice.linkID)), [card.linkID], "planned for later today: it can be planned again")
    }

    // MARK: A mix-up that's getting better

    private func note(right: Int, later: Int, misses: Int = 3) -> ConfusionNote {
        ConfusionNote(id: UUID(), name: "Anaphase vs telophase", missCount: misses, recentMisses: 4 - right, recentAnswers: 4, rightRun: right, laterRight: later)
    }

    func testTheRunCountsOnlyRightAnswersOnALaterDayThanTheLastMiss() {
        let day = { (back: Int) in self.cal.adding(days: -back, to: self.now) }
        var run = ConfusionNote.run(of: [(true, day(0)), (true, day(1)), (false, day(1)), (true, day(3))], calendar: cal)
        XCTAssertEqual(run.right, 2)
        XCTAssertEqual(run.later, 1, "the one right after the miss, the same day, doesn't show it has stuck")
        run = ConfusionNote.run(of: [(false, day(0)), (true, day(1))], calendar: cal)
        XCTAssertEqual(run.right, 0)
        run = ConfusionNote.run(of: [(true, day(0)), (true, day(1))], calendar: cal)
        XCTAssertEqual(run.later, 2, "no miss in sight")
    }

    func testRecentRightAnswersQuietAMixUpCardAndNotificationAndChangeItsWords() throws {
        func cards(_ note: ConfusionNote) -> [Notice] {
            let midterm = exam(in: 5)
            let item = ItemSnapshot(id: UUID(), kind: .mcq, topicID: nil, courseID: course, memory: .new, status: .active, createdAt: now, addedAt: now, difficultyHint: 0.5, reported: false)
            return inputs { $0.exams = [midterm]; $0.items = [item]; $0.mixUps = [NoticeMixUp(note: note, itemIDs: [item.id], courseID: course)] }
                .engineCandidates.filter { $0.kind == .mixUp }
        }
        XCTAssertTrue(cards(note(right: 2, later: 1)).isEmpty, "two right, one on a later day: nothing to say")
        XCTAssertEqual(cards(note(right: 2, later: 0)).count, 1, "the same sitting isn't recovery")
        XCTAssertEqual(cards(note(right: 3, later: 2, misses: 0)).count, 1, "a look-alike has nothing to recover from")

        let one = try XCTUnwrap(cards(note(right: 1, later: 1)).first)
        XCTAssertFalse(one.notifiable, "no notification on the strength of an answer that came right")
        let card = NoticeContent.card(one, firstName: "", now: now, calendar: cal)
        XCTAssertEqual(card.title, "Anaphase vs telophase")
        XCTAssertEqual(card.detail, "You got the last one right.")
        XCTAssertTrue(try XCTUnwrap(cards(note(right: 0, later: 0)).first).notifiable)
    }

    func testAMixUpCloses_OnlyWhenItHasRecovered() {
        XCTAssertFalse(note(right: 2, later: 1).hasRecovered)
        XCTAssertTrue(note(right: 3, later: 1).hasRecovered)
        XCTAssertFalse(note(right: 3, later: 0).hasRecovered)
        XCTAssertFalse(note(right: 3, later: 3, misses: 0).hasRecovered)
    }

    // MARK: A mix-up on its exam's day

    func testNoFixIsOfferedForAnExamsMaterialOnItsDay() {
        let item = ItemSnapshot(id: UUID(), kind: .mcq, topicID: nil, courseID: course, memory: .new, status: .active, createdAt: now, addedAt: now, difficultyHint: 0.5, reported: false)
        func cards(hour: Int, finished: Bool, days: Int = 0) -> [Notice] {
            var today = exam(in: days, hour: hour)
            if finished { today.readinessAtExam = 0.6 }
            return inputs {
                if finished { $0.finishedExams = [today] } else { $0.exams = [today] }
                $0.items = [item]
                $0.mixUps = [NoticeMixUp(note: mixUp().note, itemIDs: [item.id], courseID: course)]
            }.engineCandidates.filter { $0.kind == .mixUp }
        }
        XCTAssertTrue(cards(hour: 23, finished: false).isEmpty, "before the exam")
        XCTAssertTrue(cards(hour: 1, finished: true).isEmpty, "after it")
        XCTAssertEqual(cards(hour: 9, finished: false, days: 2).count, 1, "another day is fine")
    }

    // MARK: How often a mix-up notifies

    func testOnlyOneMixUpNotificationAWeek() {
        let midterm = exam(in: 5)
        let items = (0..<2).map { _ in ItemSnapshot(id: UUID(), kind: .mcq, topicID: nil, courseID: course, memory: .new, status: .active, createdAt: now, addedAt: now, difficultyHint: 0.5, reported: false) }
        let first = NoticeMixUp(note: mixUp().note, itemIDs: [items[0].id], courseID: course)
        let second = NoticeMixUp(note: mixUp("Mitosis vs meiosis").note, itemIDs: [items[1].id], courseID: course)
        var i = inputs {
            $0.exams = [midterm]
            $0.items = items
            $0.mixUps = [first, second]
        }
        var engine = NoticeEngine(i)
        var pings = engine.pings(engine.candidates()).map(\.notice.linkID)
        XCTAssertEqual(Set(pings).count, 1, "today's and tomorrow's aren't two mix-ups with the same words")

        i.ledger.pinged[NoticeEngine.mixUpID(first.note.id)] = cal.adding(days: -3, to: now)
        engine = NoticeEngine(i)
        pings = engine.pings(engine.candidates()).map(\.notice.linkID)
        XCTAssertTrue(pings.isEmpty, "another went out three days ago")

        i.ledger.pinged[NoticeEngine.mixUpID(first.note.id)] = cal.adding(days: -7, to: now)
        engine = NoticeEngine(i)
        XCTAssertEqual(engine.pings(engine.candidates()).first?.notice.linkID, NoticeEngine.mixUpID(second.note.id), "a week on")
    }

    // MARK: How often a mock is offered

    func testAMockCardShowsOnceThenRests() {
        let midterm = exam(in: 7)
        func shown(seenDaysAgo: Int?) -> Bool {
            inputs {
                $0.exams = [midterm]
                $0.mockOffers = [mockOffer(for: midterm)]
                if let seenDaysAgo { $0.ledger.seen[NoticeEngine.mockOfferID(midterm.id)] = [cal.dayKey(for: cal.adding(days: -seenDaysAgo, to: now))] }
            }.engineCandidates.contains { $0.kind == .mockOffer }
        }
        XCTAssertTrue(shown(seenDaysAgo: nil))
        XCTAssertTrue(shown(seenDaysAgo: 0), "it stays for the day it was seen")
        XCTAssertFalse(shown(seenDaysAgo: 1))
        XCTAssertFalse(shown(seenDaysAgo: 3))
        XCTAssertTrue(shown(seenDaysAgo: 4))
    }

    func testPingWordsHaveNoCounts() {
        let midterm = exam(in: 5)
        let rescue = FadeRescue(noticeID: "fade", examID: midterm.id, examTitle: midterm.title, examDate: midterm.date, daysLeft: 5, dimCount: 18, dimShare: 0.5,
                                days: [], minutesPerDay: 6, kept: 18, origin: .source("Lecture 3"))
        let fading = Notice(id: "f", kind: .fading, rank: 0, evidence: .fading(rescue))
        XCTAssertEqual(NoticeContent.pingBody(fading), "Some Lecture 3 questions need a review before your Bio 101 Midterm. A few extra minutes covers them.")
        let pairCard = Notice(id: "p", kind: .lookAlike, rank: 0, evidence: .lookAlike(pair()))
        XCTAssertEqual(NoticeContent.pingBody(pairCard), "Metaphase vs telophase: they look alike, and both are on your Bio 101 Midterm. Cap can show you the difference.")
        let mix = Notice(id: "m", kind: .mixUp, rank: 0, evidence: .mixUp(mixUp().note))
        XCTAssertEqual(NoticeContent.pingBody(mix), "Anaphase vs telophase: still mixing them up? Fix it in 2 minutes.")
        // A name keeps its capitals, a topic isn't a pair, and one question takes a minute.
        let topic = Notice(id: "t", kind: .mixUp, rank: 0, evidence: .mixUp(mixUp("TCP segment structure").note))
        XCTAssertEqual(NoticeContent.pingBody(topic), "TCP segment structure: still tripping you up. Fix it in 2 minutes.")
        let named = Notice(id: "n", kind: .mixUp, rank: 0, evidence: .mixUp(mixUp("Longbourn vs Netherfield").note))
        XCTAssertEqual(NoticeContent.pingBody(named), "Longbourn vs Netherfield: still mixing them up? Fix it in 2 minutes.")
        var slip = mixUp("Water availability").note
        slip.questions = 1
        XCTAssertEqual(NoticeContent.pingBody(Notice(id: "s", kind: .mixUp, rank: 0, evidence: .mixUp(slip))), "Water availability: still tripping you up. Fix it in a minute.")
        slip.name = ConfusionCandidate.unnamed
        XCTAssertEqual(NoticeContent.pingBody(Notice(id: "s", kind: .mixUp, rank: 0, evidence: .mixUp(slip))), "Still tripping on the same question? Fix it in a minute.")
        XCTAssertEqual(SessionCopy.mixUpLine(ConfusionCandidate.unnamed, questions: 1), "This question keeps tripping you up.")
        XCTAssertEqual(SessionCopy.mixUpComingAlong(ConfusionCandidate.unnamed, questions: 1), "This question is coming along.")
        XCTAssertNil(NoticeContent.pingBody(Notice(id: "b", kind: .welcomeBack, rank: 0, evidence: .welcomeBack(best: 3))))
    }

    // MARK: Words

    func testFadingWords() {
        let midterm = exam(in: 6)
        func rescue(_ offsets: [Int], kept: Int, origin: FadeRescue.Origin?) -> FadeRescue {
            FadeRescue(noticeID: "fade", examID: midterm.id, examTitle: midterm.title, examDate: midterm.date, daysLeft: 6, dimCount: 18, dimShare: 0.5,
                       days: offsets.map { .init(dayKey: "", offset: $0, date: cal.adding(days: $0, to: cal.startOfDay(for: now)), itemIDs: []) },
                       minutesPerDay: 6, kept: kept, origin: origin)
        }
        XCTAssertEqual(NoticeContent.fadingDetail(rescue([0, 1], kept: 18, origin: .source("Lecture 3")), now: now, calendar: cal),
                       "From Lecture 3, for your Bio 101 Midterm. 6 more minutes today and tomorrow covers them.")
        XCTAssertEqual(NoticeContent.fadingDetail(rescue([0, 1], kept: 15, origin: .topic("Meiosis")), now: now, calendar: cal),
                       "Mostly Meiosis, for your Bio 101 Midterm. 6 more minutes today and tomorrow covers 15 of them.")
        XCTAssertEqual(NoticeContent.fadingDetail(rescue([1, 4], kept: 18, origin: nil), now: now, calendar: cal),
                       "For your Bio 101 Midterm. 6 more minutes tomorrow and Monday covers them.")
        XCTAssertEqual(NoticeContent.dayWords([cal.adding(days: 1, to: now), cal.adding(days: 5, to: now)], now: now, calendar: cal), "tomorrow and Tuesday")
        XCTAssertEqual(NoticeContent.dayWords([cal.adding(days: 2, to: now), cal.adding(days: 5, to: now)], now: now, calendar: cal), "on Saturday and Tuesday")
        let card = NoticeContent.card(Notice(id: "f", kind: .fading, rank: 0, evidence: .fading(rescue([0], kept: 18, origin: nil))), firstName: "", now: now, calendar: cal)
        XCTAssertEqual(card.title, "18 more to review before exam day")
        XCTAssertEqual(card.action?.title, "Fix my week")
        XCTAssertNil(card.cost)
        XCTAssertEqual(card.link, .exam(midterm.id))
        var one = rescue([0], kept: 1, origin: nil)
        one.dimCount = 1
        XCTAssertEqual(NoticeContent.card(Notice(id: "f", kind: .fading, rank: 0, evidence: .fading(one)), firstName: "", now: now, calendar: cal).title,
                       "1 more to review before exam day")
    }

    func testPlanUpdatedSaysWhatChanged() throws {
        let keys = [0, 1].map { cal.dayKey(for: cal.adding(days: $0, to: now)) }
        let boosts = keys.map { PlanBoost(noticeID: "fade", examID: UUID(), examTitle: "Bio 101 Midterm", origin: "Lecture 3", dayKey: $0, minutes: 6, itemIDs: []) }
        let card = try XCTUnwrap(NoticeContent.confirmation(boosts: boosts, now: now, calendar: cal))
        XCTAssertEqual(card.title, "Plan updated")
        XCTAssertEqual(card.detail, "6 more minutes today and tomorrow for Lecture 3.")
        XCTAssertEqual(card.action?.title, "Undo")
        XCTAssertTrue(card.isConfirmation)
        XCTAssertNil(NoticeContent.confirmation(boosts: [], now: now, calendar: cal))
    }

    func testLookAlikeWords() {
        let soon = pair(in: 5)
        XCTAssertEqual(NoticeContent.pairTitle(soon.termA, soon.termB), "Metaphase vs telophase")
        XCTAssertEqual(NoticeContent.pairTitle("DNA", "mRNA"), "DNA vs mRNA")
        XCTAssertEqual(NoticeContent.lookAlikeDetail(soon, now: now, calendar: cal), "They look alike, and both are on Tuesday's Bio 101 Midterm.")
        XCTAssertEqual(NoticeContent.lookAlikeDetail(pair(in: 12), now: now, calendar: cal), "They look alike, and both are on your Bio 101 Midterm.")
        let card = NoticeContent.card(Notice(id: "p", kind: .lookAlike, rank: 0, evidence: .lookAlike(soon), cost: .cloud), firstName: "", now: now, calendar: cal)
        XCTAssertEqual(card.title, "Metaphase vs telophase")
        XCTAssertEqual(card.action?.title, "See the difference")
        XCTAssertEqual(card.cost, "Uses Cloud AI")
    }

    /// No card shows a percentage or an emoji, or calls a question a card.
    func testNoCardBreaksTheRulesOfTheWords() {
        let midterm = exam(in: 6)
        let rescue = FadeRescue(noticeID: "fade", examID: midterm.id, examTitle: midterm.title, examDate: midterm.date, daysLeft: 6, dimCount: 18, dimShare: 0.5,
                                days: [.init(dayKey: "", offset: 0, date: now, itemIDs: [])], minutesPerDay: 6, kept: 18, origin: .source("Lecture 3"))
        let notices: [Notice] = [
            Notice(id: "a", kind: .mixUp, rank: 0, evidence: .mixUp(mixUp().note)),
            Notice(id: "b", kind: .lookAlike, rank: 0, evidence: .lookAlike(pair()), cost: .cloud),
            Notice(id: "c", kind: .fading, rank: 0, evidence: .fading(rescue)),
            Notice(id: "d", kind: .welcomeBack, rank: 0, evidence: .welcomeBack(best: 23)),
            Notice(id: "e", kind: .mockOffer, rank: 0, evidence: .mockOffer(mockOffer(for: midterm)), cost: .free),
        ]
        for notice in notices {
            let card = NoticeContent.card(notice, firstName: "Maya", now: now, calendar: cal)
            let words = [card.title, card.detail, card.action?.title ?? "", card.cost ?? "", NoticeContent.pingBody(notice) ?? ""].joined(separator: " ")
            XCTAssertFalse(words.contains("%"), words)
            XCTAssertFalse(words.lowercased().contains("card"), words)
            XCTAssertFalse(words.unicodeScalars.contains { $0.properties.isEmojiPresentation }, words)
            XCTAssertNotNil(card.action)
            XCTAssertFalse(card.detail.hasSuffix("?"), "no question over a button that answers it: \(notice.id)")
            XCTAssertFalse(words.contains("No AI"), words)
            XCTAssertFalse(words.contains("fading") || words.contains("go dim") || words.contains("2-minute"), words)
            let cloud: Bool
            switch notice.cost {
            case .cloud, .drafts: cloud = true
            case .none, .free: cloud = false
            }
            XCTAssertEqual(card.cost != nil, cloud, "a cost word only where Cloud AI is used: \(notice.id)")
        }
        for kind in NoticeKind.allCases {
            XCTAssertFalse(String(localized: NoticeContent.switchTitle(kind)).isEmpty, kind.rawValue)
        }
    }

    // MARK: Speed

    /// 5,000 questions in one course of 40 topics, with several exams, a mix of formats, terms that share their endings the way a science
    /// course's do, wrong options drawn from other questions and a real backlog, in a Debug build on a busy Mac. The deck is what runs on
    /// the main thread as Today is built. The look-alike finder runs away from it, once a day (`AppModel.lookAlikePairs`).
    func testTheDeckIsWorkedOutUnderFiftyMillisecondsWithFiveThousandQuestions() {
        let first = ["ba", "cor", "dem", "fi", "gal", "hep", "in", "jor", "kal", "lum", "mer", "nor", "ox", "pel", "quin", "ros", "sul", "tra", "ul", "ven"]
        let middle = ["ca", "do", "fe", "gi", "lo", "mu", "ni", "po", "ra", "si", "te", "vu"]
        let ends = ["sis", "phase", "tion", "gen", "ase", "mer", "cyte", "lysis", "plasm", "ide", "ism", "oma"]
        func term(_ index: Int) -> String {
            let a = first[index % first.count], b = middle[(index / 3) % middle.count], c = first[(index / 7) % first.count]
            return "\(a)\(b)\(c)\(ends[(index / 2) % ends.count])"
        }
        let topics = (0..<40).map { _ in UUID() }
        let exams = [exam(in: 6), exam(in: 10, title: "Quiz"), exam(in: 18, title: "Final")]
        var items: [ItemSnapshot] = []
        var names: [LookAlikeItem] = []
        let last = cal.adding(days: -25, to: now)
        let kinds: [ItemKind] = [.flashcard, .mcq, .recall, .cloze]
        for index in 0..<5000 {
            let topic = topics[index % topics.count]
            let kind = kinds[index % kinds.count]
            let memory = MemoryState(state: .review, stability: 1 + Double(index % 40), difficulty: 5, due: cal.adding(days: index % 50 - 25, to: now), lastReview: last, reps: 3)
            let id = UUID()
            items.append(ItemSnapshot(id: id, kind: kind, topicID: topic, courseID: course, memory: memory, createdAt: last))
            names.append(LookAlikeItem(id: id, courseID: course, topicID: topic, kind: kind, prompt: kind == .flashcard ? term(index) : "What is the name of this thing number \(index)?",
                                       answer: kind == .recall ? "A sentence that explains the thing in enough words to not be a term." : term(index), accepted: [],
                                       distractors: kind == .mcq ? [term(index + 40), term(index + 80), term(index * 3 + 11)] : [], studied: true, recall: 0.6))
        }
        let days = self.days(1...365)
        func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }
        var deck = Double.infinity, finder = Double.infinity
        var found: [LookAlikePair] = []
        for _ in 0..<5 {
            var started = ContinuousClock.now
            found = LookAlikeFinder(calendar: cal, now: now).pairs(items: names, exams: exams, confusions: [])
            finder = min(finder, ms(ContinuousClock.now - started))
            var i = inputs()
            i.items = items
            i.exams = exams
            i.lookAlikes = found
            i.days = days
            i.mixUps = (0..<5).map { _ in mixUp(items: [items[0].id, items[1].id]) }
            started = ContinuousClock.now
            let engine = NoticeEngine(i)
            let cards = engine.candidates()
            let ledger = engine.dealt(cards)
            _ = engine.deck(cards, ledger: ledger)
            _ = engine.pings(cards)
            deck = min(deck, ms(ContinuousClock.now - started))
            XCTAssertFalse(cards.isEmpty)
        }
        print("NoticeEngine with 5,000 questions: the deck \(deck) ms; the look-alike finder \(finder) ms, \(found.count) pairs")
        XCTAssertFalse(found.isEmpty)
        XCTAssertLessThan(deck, 50, "what runs on the main thread as Today is built")
        XCTAssertLessThan(finder, 1500, "away from the main thread, once a day; all pairs of 3,750 terms would take many seconds")
    }
}

private extension Notice {
    /// The mix-up's name, for reading a test.
    func title() -> String? {
        if case .mixUp(let note) = evidence { return note.name }
        return nil
    }
}

extension NoticeEngineTests {
    // MARK: Gaps

    private func gap(in days: Int = 9, names: [String] = ["Meiosis", "Genetics"], exam: ExamSnapshot? = nil) -> ExamGap {
        let e = exam ?? self.exam(in: days)
        return ExamGap(examID: e.id, examTitle: e.title, examDate: e.date, daysLeft: days, topics: names.map { .init(id: UUID(), name: $0) }, waiting: [])
    }

    func testAGapCardSaysWhichTopicsAndOpensTheSheet() throws {
        let midterm = exam(in: 9)
        let i = inputs {
            $0.exams = [midterm]
            $0.gaps = [gap(exam: midterm)]
        }
        let card = try XCTUnwrap(deal(i).deck.first)
        XCTAssertEqual(card.kind, .gap)
        XCTAssertEqual(card.id, NoticeEngine.gapID(midterm.id))
        XCTAssertEqual(card.rank, NoticeEngine.Rank.gap(daysLeft: 9))
        XCTAssertEqual(card.examID, midterm.id)
        XCTAssertTrue(card.notifiable)
        let words = NoticeContent.card(card, firstName: "Maya", now: now, calendar: cal)
        XCTAssertEqual(words.title, "2 topics on your Bio 101 Midterm have no notes")
        XCTAssertEqual(words.detail, "Meiosis and Genetics.", "\"Fill the gap\" says what Cap offers")
        XCTAssertEqual(words.action?.title, "Fill the gap")
        XCTAssertEqual(words.action?.run, .fillGap(examID: midterm.id))
        XCTAssertEqual(words.link, .exam(midterm.id))
        XCTAssertNil(words.cost)
        XCTAssertEqual(NoticeContent.pingBody(card), "Some topics on your Bio 101 Midterm have no notes yet. Cap can help you fill them in.")
    }

    func testAGapCardWaitsForItsWindowAndARealGap() {
        let midterm = exam(in: 40)
        XCTAssertTrue(deal(inputs {
            $0.exams = [midterm]
            $0.gaps = [gap(in: 40, exam: midterm)]
        }).deck.isEmpty, "too far off")
        let near = exam(in: 9)
        var waiting = gap(names: [], exam: near)
        waiting.waiting = [.init(id: UUID(), name: "Meiosis")]
        XCTAssertTrue(deal(inputs {
            $0.exams = [near]
            $0.gaps = [waiting]
        }).deck.isEmpty, "drafts waiting aren't a gap")
        XCTAssertTrue(deal(inputs {
            $0.exams = [near, exam(in: 1, title: "Quiz")]
            $0.gaps = [gap(exam: near)]
        }).deck.isEmpty, "Cap is quiet on an eve")
    }

    func testTheNearestExamsGapRanksFirstAndOneCardShows() {
        let soon = exam(in: 5, title: "Quiz"), later = exam(in: 20)
        let i = inputs {
            $0.exams = [soon, later]
            $0.gaps = [gap(in: 20, exam: later), gap(in: 5, exam: soon)]
        }
        let deck = deal(i).deck
        XCTAssertEqual(deck.map(\.examID), [soon.id], "one card per kind")
    }

    func testAGapCardRespectsItsSwitchAndPutsItselfOffUntilTomorrow() {
        let midterm = exam(in: 9)
        XCTAssertTrue(deal(inputs {
            $0.exams = [midterm]
            $0.gaps = [gap(exam: midterm)]
            $0.settings.off = [.gap]
        }).deck.isEmpty)
        XCTAssertTrue(deal(inputs {
            $0.exams = [midterm]
            $0.gaps = [gap(exam: midterm)]
            $0.ledger.snoozed = [NoticeEngine.gapID(midterm.id)]
        }).deck.isEmpty)
        XCTAssertTrue(NoticeKind.live.contains(.gap))
        XCTAssertEqual(String(localized: NoticeContent.switchTitle(.gap)), "Gaps in your notes")
    }

    // MARK: Dates heard in a lecture

    private func heard(in days: Int = 14) -> NoticeHeardDate {
        NoticeHeardDate(sourceID: UUID(), lectureTitle: "Lecture 6", mentionID: "s7-2026-11-05", quote: "The quiz is on November 5th.",
                        date: cal.adding(days: days, to: now), title: "Quiz")
    }

    func testAHeardDateCardShowsTheWordsAndLeadsToTheLecture() throws {
        let date = heard()
        let i = inputs { $0.heardDates = [date] }
        let card = try XCTUnwrap(deal(i).deck.first)
        XCTAssertEqual(card.kind, .lectureDate)
        XCTAssertEqual(card.rank, NoticeEngine.Rank.lectureDate)
        XCTAssertFalse(card.notifiable, "a date that may be misheard is never sent")
        XCTAssertNil(NoticeContent.pingBody(card))
        let words = NoticeContent.card(card, firstName: "", now: now, calendar: cal)
        XCTAssertEqual(words.title, "Cap heard an exam date")
        XCTAssertEqual(words.detail, "“The quiz is on November 5th.” From Lecture 6.")
        XCTAssertEqual(words.action?.title, "See it")
        XCTAssertEqual(words.action?.run, .openHeardDate(sourceID: date.sourceID, noticeID: card.id))
    }

    func testADateGoneByIsNoCardAndAnExamInThePlanComesFirstOnlyAfterWelcomeBack() {
        XCTAssertTrue(deal(inputs { $0.heardDates = [heard(in: -1)] }).deck.isEmpty)
        let midterm = exam(in: 9)
        let i = inputs {
            $0.exams = [midterm]
            $0.mixUps = [mixUp(misses: 3)]
            $0.heardDates = [heard()]
            $0.days = days(9...14)
            $0.items = faded(1, on: midterm)
        }
        XCTAssertEqual(deal(i).deck.map(\.kind), [.welcomeBack, .lectureDate, .mixUp])
    }

    func testOldSettingsStillDecodeWithTheNewKindsOn() throws {
        let old = try JSONDecoder.cramless.decode(NoticeSettings.self, from: Data(#"{"off":["mixUp","someKindFromLater"],"notify":false}"#.utf8))
        XCTAssertEqual(old.off, [.mixUp])
        XCTAssertTrue(old.allows(.gap))
        XCTAssertTrue(old.allows(.lectureDate))
    }

    // MARK: Busy days

    /// A stretch on the day `offset` days from now, between these hours.
    private func block(_ offset: Int, _ from: Int, _ to: Int, minutes: Int = 0) -> BusyBlock {
        let day = cal.adding(days: offset, to: cal.startOfDay(for: now))
        return BusyBlock(start: cal.date(bySettingHour: from, minute: 0, second: 0, of: day)!,
                         end: cal.date(bySettingHour: to, minute: minutes, second: 0, of: day)!)
    }

    private func busyFinder(goal: Int = 15, easy: [Int] = [], goalMet: Bool = false) -> BusyDayFinder {
        BusyDayFinder(calendar: cal, now: now, dailyMinutes: goal, easyDays: easy, goalMet: goalMet)
    }

    func testALongDayIsLongBlocksNotABusyAfternoon() {
        let f = busyFinder(), day = cal.dayNumber(for: now) + 3
        XCTAssertEqual(f.busyHours(on: day, blocks: [block(3, 9, 15)]), 6)
        // A lunch and two meetings: nothing long, however full.
        XCTAssertEqual(f.busyHours(on: day, blocks: [block(3, 9, 10), block(3, 11, 12), block(3, 13, 14), block(3, 15, 16)]), 0)
        // Back-to-back classes are one block; a real gap isn't.
        XCTAssertEqual(f.busyHours(on: day, blocks: [block(3, 9, 11), block(3, 11, 13), block(3, 13, 14)]), 5)
        XCTAssertEqual(f.busyHours(on: day, blocks: [block(3, 9, 11), block(3, 12, 14)]), 0)
        // Only waking hours count, and only this day's part of a stretch.
        XCTAssertEqual(f.busyHours(on: day, blocks: [block(3, 0, 8)]), 0)
        XCTAssertEqual(f.busyHours(on: day, blocks: [BusyBlock(start: block(2, 20, 21).start, end: block(4, 10, 11).end)]), 14)
    }

    func testMinutesLeaveALongDayForTheDaysAroundIt() throws {
        let midterm = exam(in: 9)
        // Thursday 22 Oct: Sunday is long.
        let move = try XCTUnwrap(busyFinder().move(blocks: [block(3, 9, 15)], exams: [midterm]))
        XCTAssertEqual(move.busy.offset, 3)
        XCTAssertEqual(move.hours, 6)
        XCTAssertEqual(move.minutes, 10, "it keeps 5 of its 15")
        XCTAssertEqual(move.busy.minutes, 10)
        XCTAssertEqual(move.to.map(\.offset), [2, 4], "the day before and the day after")
        XCTAssertEqual(move.to.map(\.minutes), [5, 5])
        XCTAssertEqual(move.examID, midterm.id)
        XCTAssertEqual(move.noticeID, "busy-\(cal.dayKey(for: cal.adding(days: 3, to: now)))")
    }

    func testAMoveIsAddedUpInWholeMinutesAndWithinWhatADayCanTake() throws {
        let midterm = exam(in: 9)
        let odd = try XCTUnwrap(busyFinder(goal: 20).move(blocks: [block(3, 9, 15)], exams: [midterm]))
        XCTAssertEqual(odd.minutes, 15)
        XCTAssertEqual(odd.to.map(\.minutes), [8, 7])
        // One day can take it: at most 10 more.
        let lone = try XCTUnwrap(busyFinder(goal: 30).move(blocks: [block(3, 9, 15), block(4, 9, 15), block(1, 9, 15), block(2, 9, 15), block(5, 9, 15)],
                                                       exams: [midterm]))
        XCTAssertEqual(lone.busy.offset, 1, "the first long day")
        XCTAssertEqual(lone.to.map(\.offset), [0])
        XCTAssertEqual(lone.minutes, 10)
    }

    func testAShortGoalHasNothingToMove() {
        XCTAssertNil(busyFinder(goal: 5).move(blocks: [block(3, 9, 15)], exams: [exam(in: 9)]))
        XCTAssertNil(busyFinder(goal: 8).move(blocks: [block(3, 9, 15)], exams: [exam(in: 9)]))
        XCTAssertNotNil(busyFinder(goal: 10).move(blocks: [block(3, 9, 15)], exams: [exam(in: 9)]))
    }

    func testTheMoveKeepsAwayFromExamsEvesLighterDaysAndOtherLongDays() throws {
        // The exam is in 5 days: its eve is day 4 and can't take minutes, and a long day on the eve itself isn't offered.
        let soon = exam(in: 5)
        let move = try XCTUnwrap(busyFinder().move(blocks: [block(3, 9, 15)], exams: [soon]))
        XCTAssertEqual(move.to.map(\.offset), [1, 2], "the eve doesn't take any, and no day after the exam")
        XCTAssertNil(busyFinder().move(blocks: [block(4, 9, 15)], exams: [soon]), "the eve")
        XCTAssertNil(busyFinder().move(blocks: [block(5, 9, 15)], exams: [soon]), "the exam's day")
        // No exam ahead of the long day, or none near enough: nothing to protect.
        XCTAssertNil(busyFinder().move(blocks: [block(6, 9, 15)], exams: [exam(in: 5)]))
        XCTAssertNil(busyFinder().move(blocks: [block(3, 9, 15)], exams: [exam(in: 15)]))
        XCTAssertNil(busyFinder().move(blocks: [block(3, 9, 15)], exams: []))
        // Today's goal is met: today takes nothing.
        let tomorrow = try XCTUnwrap(busyFinder(goalMet: true).move(blocks: [block(1, 9, 15)], exams: [exam(in: 9)]))
        XCTAssertEqual(tomorrow.to.map(\.offset), [2, 3])
        let open = try XCTUnwrap(busyFinder().move(blocks: [block(1, 9, 15)], exams: [exam(in: 9)]))
        XCTAssertEqual(open.to.map(\.offset), [0, 2])
        // A lighter day takes none.
        let weekdays = cal.dayNumber(for: now) + 2
        let light = try XCTUnwrap(busyFinder(easy: [Calendar.weekday(dayNumber: weekdays)]).move(blocks: [block(3, 9, 15)], exams: [exam(in: 9)]))
        XCTAssertEqual(light.to.map(\.offset), [1, 4])
        // Another long day takes none.
        let two = try XCTUnwrap(busyFinder().move(blocks: [block(3, 9, 15), block(4, 9, 15)], exams: [exam(in: 9)]))
        XCTAssertEqual(two.to.map(\.offset), [1, 2])
    }

    private func busyInputs(_ change: (inout NoticeInputs) -> Void = { _ in }) -> NoticeInputs {
        inputs {
            $0.exams = [exam(in: 9)]
            $0.dailyMinutes = 15
            $0.days = days(1...3)
            $0.calendarAccess = .granted
            $0.busyBlocks = [block(3, 9, 15)]
            change(&$0)
        }
    }

    func testTheBusyCardIsOneMoreOfCapsCards() throws {
        let dealt = deal(busyInputs())
        let card = try XCTUnwrap(dealt.deck.first)
        XCTAssertEqual(card.kind, .busyDay)
        XCTAssertEqual(card.rank, NoticeEngine.Rank.busyDay(daysAway: 3))
        XCTAssertFalse(card.notifiable, "no notification: nothing is at risk")
        XCTAssertEqual(card.cost, .none)
        XCTAssertNil(NoticeContent.pingBody(card))
        let words = NoticeContent.card(card, firstName: "Maya", now: now, calendar: cal)
        XCTAssertEqual(words.title, "Sunday looks busy")
        XCTAssertEqual(words.detail, "About 6 hours in your calendar. Cap can move 10 minutes to Saturday and Monday.")
        XCTAssertEqual(words.action?.title, "Move them")
        XCTAssertNil(words.cost)
        guard case .moveBusyDay(let move)? = words.action?.run else { return XCTFail("the button moves them") }
        XCTAssertEqual(move.noticeID, card.id)
        // Later and acted on keep it away, as any card; switched off it never shows, and without the calendar there's nothing to go on.
        XCTAssertTrue(deal(busyInputs { $0.ledger.snoozed = [card.id] }).deck.isEmpty)
        XCTAssertTrue(deal(busyInputs { $0.ledger.acted[card.id] = cal.dayKey(for: now) }).deck.isEmpty)
        XCTAssertTrue(deal(busyInputs { $0.settings.off = [.busyDay] }).deck.isEmpty)
        XCTAssertTrue(deal(busyInputs { $0.calendarAccess = .denied }).deck.isEmpty)
        // Quiet on an eve, like every other card.
        XCTAssertTrue(deal(busyInputs { $0.exams = [exam(in: 1), exam(in: 9)] }).deck.isEmpty)
    }

    func testTomorrowAndTodayInTheBusyWords() throws {
        let move = try XCTUnwrap(busyFinder().move(blocks: [block(1, 9, 15)], exams: [exam(in: 9)]))
        XCTAssertEqual(NoticeContent.busyTitle(move, calendar: cal), "Tomorrow looks busy")
        XCTAssertEqual(NoticeContent.busyDetail(move, now: now, calendar: cal), "About 6 hours in your calendar. Cap can move 10 minutes to today and Saturday.")
    }

    func testTheConfirmationSaysWhatMovedAndCanBeUndone() throws {
        let key = { (days: Int) in self.cal.dayKey(for: self.cal.adding(days: days, to: self.now)) }
        func boost(_ day: Int, _ minutes: Int) -> PlanBoost {
            PlanBoost(noticeID: "busy-x", examID: UUID(), examTitle: "Midterm", origin: nil, dayKey: key(day), minutes: minutes, itemIDs: [])
        }
        let card = try XCTUnwrap(NoticeContent.confirmation(boosts: [boost(3, -10), boost(2, 5), boost(4, 5)], now: now, calendar: cal))
        XCTAssertEqual(card.kind, .busyDay)
        XCTAssertTrue(card.isConfirmation)
        XCTAssertEqual(card.title, "Plan updated")
        XCTAssertEqual(card.detail, "10 minutes moved from Sunday to Saturday and Monday.")
        XCTAssertEqual(card.action?.run, .undoFixMyWeek(noticeID: "busy-x"))
        let near = try XCTUnwrap(NoticeContent.confirmation(boosts: [boost(1, -10), boost(0, 5), boost(2, 5)], now: now, calendar: cal))
        XCTAssertEqual(near.detail, "10 minutes moved from tomorrow to today and Saturday.")
    }

    func testTheOfferToLookComesOnceAnExamIsNearAndNotOnDayOne() throws {
        func ask(_ change: (inout NoticeInputs) -> Void = { _ in }) -> NoticeInputs { busyInputs { $0.calendarAccess = .notAsked; change(&$0) } }
        let card = try XCTUnwrap(deal(ask()).deck.first)
        XCTAssertEqual(card.id, NoticeEngine.busyAskID)
        XCTAssertEqual(card.rank, NoticeEngine.Rank.busyAsk)
        let words = NoticeContent.card(card, firstName: "", now: now, calendar: cal)
        XCTAssertEqual(words.title, "Cap can plan around your long days")
        XCTAssertEqual(words.action?.run, .askCalendar)
        XCTAssertNil(words.cost)
        XCTAssertTrue(words.detail.contains("only their times"), "says what it reads")
        XCTAssertTrue(words.detail.contains("Nothing leaves"), "and that it stays here")
        XCTAssertTrue(deal(ask { $0.exams = [exam(in: 15)] }).deck.isEmpty, "no exam near")
        XCTAssertTrue(deal(ask { $0.days = days(1...1) }).deck.isEmpty, "too soon to ask")
        // Put off, it comes back the next day; after two days of being shown, it stops asking.
        let today = cal.dayKey(for: now)
        XCTAssertFalse(deal(ask { $0.ledger.seen[NoticeEngine.busyAskID] = ["2026-10-20"] }).deck.isEmpty)
        XCTAssertFalse(deal(ask { $0.ledger.seen[NoticeEngine.busyAskID] = ["2026-10-20", today] }).deck.isEmpty, "it stays for the rest of its second day")
        XCTAssertTrue(deal(ask { $0.ledger.seen[NoticeEngine.busyAskID] = ["2026-10-19", "2026-10-20"] }).deck.isEmpty)
    }

    func testOtherCardsStillComeFirst() {
        let dealt = deal(busyInputs {
            $0.mixUps = [mixUp()]
        })
        XCTAssertEqual(dealt.deck.map(\.kind), [.mixUp, .busyDay])
    }

    func testTheCalendarSwitchSaysWhatItReads() {
        XCTAssertEqual(NoticeContent.switchTitle(.busyDay).key, "Busy days")
        XCTAssertNotNil(NoticeContent.switchNote(.busyDay))
        XCTAssertNil(NoticeContent.switchNote(.mixUp))
    }
}

private extension NoticeInputs {
    var engineCandidates: [Notice] { NoticeEngine(self).candidates() }
}
