import Foundation
import SwiftData
import XCTest
@testable import Cramless

/// A stand-in for the system's icon switcher.
@MainActor
final class FakeIconSwitcher: AppIconSwitching {
    var supportsAlternates = true
    var current = AppIconChoice.standard
    var failNext = false
    var applied: [AppIconChoice] = []

    func apply(_ icon: AppIconChoice) async throws {
        if failNext {
            failNext = false
            throw NSError(domain: "icon", code: 1)
        }
        applied.append(icon)
        current = icon
    }
}

/// Quests, the week's sky, badges, icons and skies, on a real store.
@MainActor
final class GameAppModelTests: XCTestCase {
    let cal = EngineTest.calendar()
    var clock: TestClock!
    var app: AppModel!
    var previousLive: AppModel?

    override func setUp() async throws {
        previousLive = AppModel.live
        // Thursday Oct 22, 2026, 18:00, in a week that begins on Sunday (Oct 18 to 24).
        clock = TestClock(EngineTest.date(2026, 10, 22, 18, in: cal))
        app = try StudyTestApp.make(clock: clock, calendar: cal)
        AppModel.schedulerFuzz = false
    }

    override func tearDown() async throws {
        AppModel.schedulerFuzz = true
        AppModel.live = previousLive
        app = nil
    }

    // MARK: A world

    @discardableResult
    private func makeCourse(_ name: String = "Bio 101") -> Course {
        let course = Course(name: name, now: clock.now)
        app.context.insert(course)
        return course
    }

    @discardableResult
    private func makeItem(in course: Course, kind: ItemKind = .flashcard, memory: MemoryState? = nil) -> StudyItem {
        let item = StudyItem(course: course, kind: kind, status: .active, origin: .person, prompt: "Question?",
                             answer: "Answer", now: clock.now)
        if let memory { item.memory = memory }
        app.context.insert(item)
        course.items.append(item)
        return item
    }

    /// A memory studied nine days ago whose recall is about half now: answering it right is a save.
    private var fading: MemoryState {
        let fsrs = app.fsrs
        let stability = fsrs.factor * 9 / (pow(0.5, 1 / fsrs.decay) - 1)
        return MemoryState(state: .review, stability: stability, difficulty: 5, due: clock.now,
                           lastReview: cal.adding(days: -9, to: clock.now), reps: 3)
    }

    /// Answers `items` right in one finished session.
    @discardableResult
    private func study(_ items: [StudyItem], rating: Rating = .good) -> StudySession {
        app.save()
        let session = app.startSession(app.buildSession(SessionRequest(kind: .daily)))
        for item in items {
            XCTAssertNotNil(app.recordReview(itemID: item.id, rating: rating, durationMs: 5000, sessionID: session.id))
        }
        app.finishSession(session)
        return session
    }

    private func addDays(_ pattern: String, endingDaysAgo: Int = 1) {
        let chars = Array(pattern)
        for (i, ch) in chars.enumerated() where ch != "-" {
            let at = cal.adding(days: -(endingDaysAgo + (chars.count - 1 - i)), to: clock.now)
            app.context.insert(DayRecord(dayKey: cal.dayKey(for: at), day: cal.startOfDay(for: at),
                                         studySeconds: 600, itemsReviewed: 12, sessions: 1))
        }
        app.save()
    }

    /// A week of quests already done: `masks` for the days (back from today) that have one.
    private func setQuestMasks(_ masks: [Int: Int]) {
        for (back, mask) in masks {
            let at = cal.adding(days: -back, to: clock.now)
            let record = app.dayRecord(key: cal.dayKey(for: at), date: at)
            record.questMask = mask
        }
        app.save()
    }

    // MARK: Picking

    func testTodaysQuestsArePickedOnceAndKeptForTheDay() throws {
        let course = makeCourse()
        for _ in 0..<8 { makeItem(in: course) }
        app.save()
        XCTAssertNil(app.settings.questDay)

        app.ensureQuestPicks()
        let stored = try XCTUnwrap(app.settings.questDay)
        XCTAssertEqual(stored.dayKey, "2026-10-22")
        XCTAssertEqual(stored.kinds, [.finishSession, .learnNew], "only a new-questions quest fits eight new flashcards")

        // The material changes during the day; the day's quests don't.
        for _ in 0..<30 { makeItem(in: course, kind: .mcq) }
        app.save()
        XCTAssertEqual(app.todayQuestKinds(), stored.kinds)
        app.ensureQuestPicks()
        XCTAssertEqual(app.settings.questDay, stored)

        // The next day is picked afresh.
        clock.advance(86_400)
        XCTAssertNotEqual(app.todayQuestKinds(), stored.kinds, "it would pick again, with the new material")
        app.ensureQuestPicks()
        XCTAssertEqual(app.settings.questDay?.dayKey, "2026-10-23")
    }

    func testNothingIsPickedOnExamEveOrWithNothingToStudy() {
        app.ensureQuestPicks()
        XCTAssertNil(app.settings.questDay, "no material")

        let course = makeCourse()
        for _ in 0..<8 { makeItem(in: course) }
        app.context.insert(Exam(course: course, title: "Quiz", date: cal.adding(days: 1, to: clock.now), now: clock.now))
        app.save()
        XCTAssertEqual(app.todayQuestKinds(), [])
        app.ensureQuestPicks()
        XCTAssertNil(app.settings.questDay, "exam eve is for sleep")
    }

    func testQuestsAreHiddenOnTodayUntilTheFirstSessionIsDone() {
        let course = makeCourse()
        let items = (0..<8).map { _ in makeItem(in: course) }
        app.save()
        XCTAssertTrue(TodaySnapshot.make(app: app).quests.isEmpty, "a new person meets Today without a quest")
        study(Array(items.prefix(5)))
        let snapshot = TodaySnapshot.make(app: app)
        XCTAssertFalse(snapshot.quests.isEmpty)
        XCTAssertEqual(snapshot.quests.rows.first?.kind, .finishSession)
    }

    // MARK: Settling

    func testAFinishedSessionTicksOffTheQuestsItCompleted() throws {
        let course = makeCourse()
        let items = (0..<8).map { _ in makeItem(in: course) }
        app.save()
        app.ensureQuestPicks()
        XCTAssertEqual(app.todayQuestKinds(), [.finishSession, .learnNew])
        XCTAssertEqual(app.questsToday().done, 0)
        XCTAssertEqual(app.questsToday().week, 0)

        study(Array(items.prefix(5)))
        let before = app.questsToday()
        XCTAssertEqual(before.done, 2, "the card reads the day's answers at once")
        XCTAssertNil(app.dayRecord(key: "2026-10-22")?.questMask.nonZero, "…before anything is written")

        let outcome = app.settleQuests()
        XCTAssertEqual(outcome.questsDone, [.finishSession, .learnNew])
        XCTAssertEqual(outcome.weekBefore, 0)
        XCTAssertEqual(outcome.weekAfter, 2)
        XCTAssertNil(outcome.skyLit)
        let record = try XCTUnwrap(app.dayRecord(key: "2026-10-22"))
        XCTAssertEqual(record.questMask, QuestKind.finishSession.bit | QuestKind.learnNew.bit)
        XCTAssertNil(record.syncedAt, "the day goes up again")

        let again = app.settleQuests()
        XCTAssertEqual(again.questsDone, [], "settling twice finishes nothing twice")
        XCTAssertEqual(record.questMask, QuestKind.finishSession.bit | QuestKind.learnNew.bit)
        XCTAssertEqual(app.questsToday().week, 2)
    }

    func testAQuestFinishedStaysFinishedWhateverTheLogSaysLater() throws {
        let course = makeCourse()
        let items = (0..<8).map { _ in makeItem(in: course) }
        app.save()
        study(Array(items.prefix(5)))
        app.settleQuests()
        let mask = try XCTUnwrap(app.dayRecord(key: "2026-10-22")).questMask
        XCTAssertNotEqual(mask, 0)

        for log in app.fetch(FetchDescriptor<ReviewLog>()) { app.context.delete(log) }
        app.save()
        XCTAssertEqual(app.questFacts(forDay: "2026-10-22").newLearned, 0, "the answers are gone")
        let rows = app.questsToday().rows
        XCTAssertTrue(rows.allSatisfy(\.isDone), "…but the quests were done")
        app.settleQuests()
        XCTAssertEqual(try XCTUnwrap(app.dayRecord(key: "2026-10-22")).questMask, mask, "a mask only grows")
    }

    func testSavingFadingStarsIsWhatTheRescueQuestCounts() throws {
        let course = makeCourse()
        let stars = (0..<4).map { _ in makeItem(in: course, memory: fading) }
        app.save()
        app.ensureQuestPicks()
        XCTAssertEqual(app.todayQuestKinds(), [.finishSession, .rescueFading])

        study(Array(stars.prefix(2)))
        var facts = app.questFacts(forDay: "2026-10-22")
        XCTAssertEqual(facts.saves, 2)
        XCTAssertEqual(app.questsToday().rows.last?.progress, QuestProgress(done: 2, goal: 3))
        XCTAssertFalse(app.questsToday().rows.last?.isDone ?? true)

        // A third, in a second session the same day.
        let more = app.startSession(app.buildSession(SessionRequest(kind: .daily)))
        XCTAssertNotNil(app.recordReview(itemID: stars[2].id, rating: .good, durationMs: 4000, sessionID: more.id))
        app.finishSession(more)
        facts = app.questFacts(forDay: "2026-10-22")
        XCTAssertEqual(facts.saves, 3)
        XCTAssertEqual(app.settleQuests().questsDone, [.finishSession, .rescueFading])
    }

    func testAWrongOrFirstTimeAnswerIsNotASave() {
        let course = makeCourse()
        let star = makeItem(in: course, memory: fading)
        let fresh = makeItem(in: course)
        app.save()
        study([star], rating: .again)
        XCTAssertEqual(app.questFacts(forDay: "2026-10-22").saves, 0, "wrong")
        study([fresh])
        XCTAssertEqual(app.questFacts(forDay: "2026-10-22").saves, 0, "a first look is never a save")
    }

    func testARunOfRightAnswersIsCountedPerSessionAndFlashcardsNeitherBuildNorBreakIt() {
        let course = makeCourse()
        let checked = (0..<6).map { _ in makeItem(in: course, kind: .cloze) }
        let cards = (0..<3).map { _ in makeItem(in: course) }
        app.save()
        let session = app.startSession(app.buildSession(SessionRequest(kind: .daily)))
        // Two right, a flashcard rated Again (it does not break the run), three right, a wrong one, one right.
        let plan: [(StudyItem, Rating)] = [
            (checked[0], .good), (checked[1], .good), (cards[0], .again), (checked[2], .good), (checked[3], .easy),
            (checked[4], .good), (cards[1], .good), (checked[5], .again), (checked[0], .good),
        ]
        for (item, rating) in plan {
            app.recordReview(itemID: item.id, rating: rating, durationMs: 4000, sessionID: session.id)
        }
        app.finishSession(session)
        XCTAssertEqual(app.questFacts(forDay: "2026-10-22").bestRun, 5, "five checked answers right in a row")
    }

    func testOwnWordsAnswersAreCountedWhateverTheirGrade() {
        let course = makeCourse()
        let words = (0..<2).map { _ in makeItem(in: course, kind: .recall) }
        let card = makeItem(in: course)
        app.save()
        study([words[0], words[1], card], rating: .again)
        XCTAssertEqual(app.questFacts(forDay: "2026-10-22").ownWordsAnswers, 2)
    }

    func testBeforeNoonLooksAtWhenTheFirstSessionFinished() {
        let course = makeCourse()
        let items = (0..<3).map { _ in makeItem(in: course) }
        app.save()
        clock.now = EngineTest.date(2026, 10, 22, 8, 30, in: cal)
        study([items[0]])
        XCTAssertEqual(app.questFacts(forDay: "2026-10-22").firstFinishedMinute, 8 * 60 + 30)
        XCTAssertTrue(QuestEngine.progress(.beforeNoon, facts: app.questFacts(forDay: "2026-10-22")).isComplete)
        clock.now = EngineTest.date(2026, 10, 22, 18, in: cal)
        study([items[1]])
        XCTAssertEqual(app.questFacts(forDay: "2026-10-22").firstFinishedMinute, 8 * 60 + 30, "the first one counts")
    }

    func testAMixUpFixedTodayIsAFixQuestDone() {
        let course = makeCourse()
        let a = makeItem(in: course), b = makeItem(in: course)
        let confusion = Confusion(course: course, name: "A vs B", explanation: "", itemIDs: [a.id, b.id], missCount: 3, now: clock.now)
        app.context.insert(confusion)
        app.save()
        XCTAssertEqual(app.questFacts(forDay: "2026-10-22").mixUpsFixed, 0)
        confusion.status = .fixed
        app.touch(confusion)
        app.save()
        XCTAssertEqual(app.questFacts(forDay: "2026-10-22").mixUpsFixed, 1)
        XCTAssertEqual(app.questFacts(forDay: "2026-10-21").mixUpsFixed, 0, "yesterday didn't")
    }

    func testAPastDaysQuestsAreSettledAtTheNextRollover() throws {
        let course = makeCourse()
        let items = (0..<8).map { _ in makeItem(in: course) }
        app.save()
        app.applyDailyRollover()
        XCTAssertEqual(app.settings.questDay?.dayKey, "2026-10-22", "the rollover picks the day's quests")
        study(Array(items.prefix(5)))
        XCTAssertNil(app.dayRecord(key: "2026-10-22")?.questMask.nonZero, "the summary never settled it")

        clock.advance(86_400)
        app.applyDailyRollover()
        let yesterday = try XCTUnwrap(app.dayRecord(key: "2026-10-22"))
        XCTAssertEqual(yesterday.questMask, QuestKind.finishSession.bit | QuestKind.learnNew.bit)
        XCTAssertEqual(app.settings.questDay?.dayKey, "2026-10-23")
    }

    // MARK: The week and its sky

    func testAWeekOfTwelveQuestsLightsTheNextSkyOnce() {
        addDays("ssss", endingDaysAgo: 1)
        // Sunday to Wednesday of this week (4 days back to 1 day back), three quests each.
        setQuestMasks([1: 0b111, 2: 0b111, 3: 0b111, 4: 0b111])
        XCTAssertEqual(app.questWeek(), 12)

        let first = app.settleQuests()
        XCTAssertEqual(first.skyLit, .dusk)
        XCTAssertEqual(app.settings.litWeeks, 1)
        XCTAssertEqual(app.settings.lastLitWeek, "2026-10-18")
        XCTAssertEqual(app.unlockedSkies, [.night, .dusk])
        XCTAssertNil(app.settleQuests().skyLit, "one sky for one week")
        XCTAssertEqual(app.settings.litWeeks, 1)
        XCTAssertTrue(app.questsToday().weekLit)
        XCTAssertNil(app.questsToday().nextSky, "this week is done")

        // Next week, the next sky.
        clock.advance(7 * 86_400)
        XCTAssertEqual(app.questWeek(), 0, "a new week")
        XCTAssertEqual(app.questsToday().nextSky, .aurora)
        setQuestMasks([1: 0b111, 2: 0b111, 3: 0b111, 4: 0b111])
        XCTAssertEqual(app.settleQuests().skyLit, .aurora)
        XCTAssertEqual(app.settings.litWeeks, 2)
    }

    func testElevenQuestsLightNothingAndEveryWeekAfterTheLastSkyIsJustAWeek() {
        setQuestMasks([1: 0b111, 2: 0b111, 3: 0b111, 4: 0b11])
        XCTAssertEqual(app.questWeek(), 11)
        XCTAssertNil(app.settleQuests().skyLit)
        XCTAssertEqual(app.settings.litWeeks, 0)

        app.settings.litWeeks = SkyTheme.unlockOrder.count
        setQuestMasks([4: 0b111])
        XCTAssertEqual(app.questWeek(), 12)
        XCTAssertNil(app.settleQuests().skyLit, "every sky is lit already")
        XCTAssertEqual(app.settings.litWeeks, SkyTheme.unlockOrder.count)
        XCTAssertNil(app.questsToday().nextSky)
    }

    func testTheWeekFollowsTheCalendarsFirstWeekday() {
        // Thursday: Monday-first, the week is Oct 19 to 25, so Sunday Oct 18's quests are last week's.
        setQuestMasks([4: 0b111, 3: 0b1])
        XCTAssertEqual(app.questWeek(), 4, "Sunday-first: Sunday and Monday are both this week")
        app.calendar.firstWeekday = 2
        XCTAssertEqual(app.questWeek(), 1, "Monday-first: only Monday's")
    }

    func testTodaysFinishedButUnwrittenQuestsCountTowardTheWeek() {
        let course = makeCourse()
        let items = (0..<8).map { _ in makeItem(in: course) }
        app.save()
        app.ensureQuestPicks()
        setQuestMasks([1: 0b111])
        study(Array(items.prefix(5)))
        XCTAssertEqual(app.questWeek(), 3, "stored: only the days written")
        XCTAssertEqual(app.questsToday().week, 5, "the card adds what today's answers have already finished")
    }

    // MARK: Badges

    func testAFirstLaunchNotesWhatIsAlreadyEarnedWithoutAFuss() {
        let course = makeCourse()
        let items = (0..<3).map { _ in makeItem(in: course) }
        app.save()
        addDays("sssssss")
        study([items[0]])
        XCTAssertNil(app.settings.badges)
        app.baselineBadges()
        let known = Set((app.settings.badges ?? [:]).keys)
        XCTAssertTrue(known.contains(Badge.firstSession.rawValue))
        XCTAssertTrue(known.contains(Badge.streak7.rawValue))
        XCTAssertEqual(app.settleBadges(), [], "nothing is new")
        let date = app.settings.badges?[Badge.firstSession.rawValue]
        app.baselineBadges()
        XCTAssertEqual(app.settings.badges?[Badge.firstSession.rawValue], date, "noted once")
    }

    func testASessionEarnsABadgeOnceAndThePersonIsToldOnce() throws {
        let course = makeCourse()
        let items = (0..<3).map { _ in makeItem(in: course) }
        app.save()
        app.applyDailyRollover()
        XCTAssertNotNil(app.settings.badges)
        XCTAssertEqual(app.settings.badges?.count, 0, "a new install has earned nothing")
        study([items[0]])
        XCTAssertEqual(app.settleBadges(), [.firstSession])
        XCTAssertEqual(app.settleBadges(), [], "told once")
        let status = try XCTUnwrap(app.badgeStatuses().first { $0.badge == .firstSession })
        XCTAssertTrue(status.isEarned)
        XCTAssertEqual(status.earnedAt, clock.now)
        XCTAssertFalse(try XCTUnwrap(app.badgeStatuses().first { $0.badge == .thousand }).isEarned)
        XCTAssertEqual(app.badgeStatuses().map(\.badge), Badge.allCases)
    }

    func testABadgeEarnedIsKeptWhenTheHistoryThatEarnedItIsGone() {
        let course = makeCourse()
        let items = (0..<3).map { _ in makeItem(in: course) }
        app.save()
        app.applyDailyRollover()
        study([items[0]])
        app.settleBadges()
        for session in app.fetch(FetchDescriptor<StudySession>()) { app.context.delete(session) }
        for log in app.fetch(FetchDescriptor<ReviewLog>()) { app.context.delete(log) }
        app.save()
        XCTAssertEqual(app.achievementFacts().sessionsFinished, 0)
        XCTAssertTrue(app.earnedBadges().contains(.firstSession), "never taken away")
        XCTAssertTrue(app.badgeStatuses().first { $0.badge == .firstSession }?.isEarned ?? false)
    }

    func testSavesAndOwnWordsAndLongStreaksEarnTheirBadges() {
        let course = makeCourse()
        let stars = (0..<10).map { _ in makeItem(in: course, memory: fading) }
        let words = (0..<25).map { _ in makeItem(in: course, kind: .recall) }
        app.save()
        addDays(String(repeating: "s", count: 30))
        app.applyDailyRollover()
        let earnedBefore = app.earnedBadges()
        XCTAssertTrue(earnedBefore.isSuperset(of: [.streak7, .streak30]))
        XCTAssertFalse(earnedBefore.contains(.saves10))
        study(stars + words)
        let facts = app.achievementFacts()
        XCTAssertEqual(facts.saves, 10)
        XCTAssertEqual(facts.ownWordsAnswers, 25)
        XCTAssertEqual(facts.answers, 35)
        XCTAssertEqual(facts.bestStreak, 31, "thirty days and today")
        XCTAssertEqual(Set(app.settleBadges()), [.firstSession, .saves10, .ownWords25])
    }

    func testAnExamMorningThatWasReadyAndAGradeThatCalledIt() {
        let course = makeCourse()
        let exam = Exam(course: course, title: "Midterm", date: cal.adding(days: -2, to: clock.now), now: cal.adding(days: -20, to: clock.now))
        exam.readinessAtExam = 0.83
        exam.resultScore = 0.86
        app.context.insert(exam)
        let other = Exam(course: course, title: "Quiz", date: cal.adding(days: -4, to: clock.now), now: cal.adding(days: -20, to: clock.now))
        other.readinessAtExam = 0.6
        other.resultScore = 0.8
        app.context.insert(other)
        app.save()
        let facts = app.achievementFacts()
        XCTAssertEqual(facts.readyExams, 1, "only the 83% morning was ready")
        XCTAssertEqual(facts.calledItExams, 1, "86 against 83 is within 5 points; 80 against 60 is not")
        XCTAssertTrue(app.earnedBadges().isSuperset(of: [.ready, .calledIt]))
    }

    func testARepairedDayEarnsTheComebackBadge() {
        let day = cal.adding(days: -3, to: clock.now)
        app.context.insert(DayRecord(dayKey: cal.dayKey(for: day), day: cal.startOfDay(for: day), repaired: true))
        app.save()
        XCTAssertEqual(app.achievementFacts().repairedDays, 1)
        XCTAssertTrue(app.earnedBadges().contains(.comeback))
    }

    func testTheFactsAreWorkedOutOncePerRevision() {
        let course = makeCourse()
        makeItem(in: course)
        app.save()
        let first = app.achievementFacts()
        XCTAssertNotNil(app.gameCache.facts)
        XCTAssertEqual(app.gameCache.facts?.revision, app.revision)
        XCTAssertEqual(app.achievementFacts(), first)
        app.save()
        XCTAssertNotEqual(app.gameCache.facts?.revision, app.revision, "a save makes the cache stale")
    }

    // MARK: Icons and skies

    func testAnIconIsOnlyChosenOnceItsStreakHasUnlockedIt() async {
        let switcher = FakeIconSwitcher()
        app.iconSwitcher = switcher
        let locked = await app.setAppIcon(.night)
        XCTAssertFalse(locked)
        XCTAssertEqual(switcher.applied, [])
        XCTAssertEqual(app.settings.appIcon, .standard)

        addDays("sssssss")
        XCTAssertEqual(app.unlockedIcons, [.standard, .night])
        let ok = await app.setAppIcon(.night)
        XCTAssertTrue(ok)
        XCTAssertEqual(switcher.applied, [.night])
        XCTAssertEqual(app.settings.appIcon, .night)
        let ember = await app.setAppIcon(.ember)
        XCTAssertFalse(ember)

        // The streak breaks: the icon stays unlocked (the best streak is what counts).
        clock.advance(10 * 86_400)
        XCTAssertEqual(app.streak().current, 0)
        XCTAssertEqual(app.unlockedIcons, [.standard, .night])
    }

    func testAFailedIconChangeLeavesTheChoiceAlone() async {
        let switcher = FakeIconSwitcher()
        app.iconSwitcher = switcher
        addDays("sssssss")
        _ = await app.setAppIcon(.night)
        switcher.failNext = true
        let ok = await app.setAppIcon(.standard)
        XCTAssertFalse(ok)
        XCTAssertEqual(app.settings.appIcon, .night)
        switcher.supportsAlternates = false
        let none = await app.setAppIcon(.standard)
        XCTAssertFalse(none, "where the system has no alternate icons")
    }

    func testASkyIsOnlyChosenOnceAWeekOfQuestsHasLitIt() {
        XCTAssertFalse(app.setSkyTheme(.aurora))
        XCTAssertEqual(app.skyTheme, .night)
        app.settings.litWeeks = 2
        XCTAssertTrue(app.setSkyTheme(.aurora))
        XCTAssertEqual(app.skyTheme, .aurora)
        XCTAssertFalse(app.setSkyTheme(.ember))
        // A sky that isn't unlocked shows as Night, whatever is stored.
        app.settings.skyTheme = .glacier
        XCTAssertEqual(app.skyTheme, .night)
    }

    func testEverythingUnlocksForAFilm() {
        app.debugUnlockAll = true
        XCTAssertEqual(app.unlockedIcons, AppIconChoice.allCases)
        XCTAssertEqual(app.unlockedSkies, SkyTheme.allCases)
        app.settings.skyTheme = .glacier
        XCTAssertEqual(app.skyTheme, .glacier)
    }

    // MARK: Cost

    /// A heavy history (a few years of studying) must not make the badges a cost anyone can feel: the facts are worked out
    /// once per revision, and a revision with no new answers costs a count, not a scan.
    func testTheBadgeFactsOfAHugeHistoryAreCheapToKeepUpToDate() throws {
        let course = makeCourse()
        let items = (0..<300).map { _ in makeItem(in: course, kind: .recall) }
        let session = UUID()
        for i in 0..<20_000 {
            let item = items[i % items.count]
            let at = cal.adding(days: -(i / 30), to: clock.now)
            app.context.insert(ReviewLog(itemID: item.id, courseID: course.id, sessionID: session, reviewedAt: at,
                                         rating: i % 5 == 0 ? .again : .good, gradedBy: "rules", durationMs: 5000,
                                         before: .new, after: .new, elapsedDays: 4, scheduledDays: 4))
        }
        app.save()
        var started = ContinuousClock.now
        let first = app.achievementFacts()
        let firstTime = ContinuousClock.now - started
        XCTAssertEqual(first.answers, 20_000)
        XCTAssertEqual(first.ownWordsAnswers, 20_000)
        // The same revision: nothing is worked out again.
        started = ContinuousClock.now
        _ = app.achievementFacts()
        let again = ContinuousClock.now - started
        // One more answer, a moment later: the facts move on without scanning the log again.
        clock.advance(1)
        app.recordReview(itemID: items[0].id, rating: .good, durationMs: 4000)
        started = ContinuousClock.now
        let next = app.achievementFacts()
        let incremental = ContinuousClock.now - started
        XCTAssertEqual(next.answers, 20_001)
        XCTAssertEqual(next.ownWordsAnswers, 20_001)
        print("badge facts, 20,000 answers: first \(firstTime), same revision \(again), one more answer \(incremental)")
        XCTAssertLessThan(again, .milliseconds(5))
        XCTAssertLessThan(incremental, .milliseconds(60), "a new answer is not a rescan of the log")
    }

    // MARK: Asking for a rating

    func testTheRatingPromptNeverComesInTests() {
        let summary = SessionSummary(sessionID: UUID(), kind: .daily, answers: 9, itemsReviewed: 8, correctFirstTry: 8, accuracy: 1,
                                     newLearned: 0, minutes: 9, streak: StreakState(), streakExtended: true, stopNow: false,
                                     starsRelit: 3, starsSaved: 2)
        let facts = app.reviewPromptFacts(for: summary, milestone: 7)
        XCTAssertEqual(facts.answered, 8)
        XCTAssertEqual(facts.rightFirstTime, 8)
        XCTAssertEqual(facts.saves, 2)
        XCTAssertEqual(facts.streakMilestone, 7)
        XCTAssertTrue(facts.harness)
        XCTAssertFalse(ReviewPromptPolicy.shouldAsk(facts))
        XCTAssertFalse(facts.promptedThisVersion)
        app.noteReviewPrompted()
        XCTAssertEqual(app.settings.reviewPromptedAt, clock.now)
        let after = app.reviewPromptFacts(for: summary, milestone: nil)
        XCTAssertTrue(after.promptedThisVersion)
        XCTAssertEqual(after.daysSincePrompt, 0)
    }

    // MARK: Stored settings

    func testSettingsFromBeforeTheGameLoopOpenWithEveryDefault() throws {
        let old = try JSONDecoder.cramless.decode(AppSettings.self, from: Data(#"{"firstName":"Maya"}"#.utf8))
        XCTAssertEqual(old.firstName, "Maya")
        XCTAssertNil(old.questDay)
        XCTAssertEqual(old.litWeeks, 0)
        XCTAssertEqual(old.skyTheme, .night)
        XCTAssertEqual(old.appIcon, .standard)
        XCTAssertNil(old.badges)
        XCTAssertNil(old.reviewPromptedAt)
    }

    func testASkyOrIconThisVersionDoesntKnowFallsBackToTheDefault() throws {
        let json = #"{"skyTheme":"supernova","appIcon":"platinum","litWeeks":3}"#
        let s = try JSONDecoder.cramless.decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.skyTheme, .night)
        XCTAssertEqual(s.appIcon, .standard)
        XCTAssertEqual(s.litWeeks, 3, "what it does know is kept")
    }

    func testTheGameLoopSettingsRoundTrip() throws {
        var s = AppSettings()
        s.questDay = .init(dayKey: "2026-10-22", kinds: [.finishSession, .rescueFading])
        s.litWeeks = 2
        s.lastLitWeek = "2026-10-18"
        s.skyTheme = .aurora
        s.appIcon = .gold
        s.badges = [Badge.firstSession.rawValue: clock.now]
        s.reviewPromptedVersion = "1.0"
        let data = try JSONEncoder.cramless.encode(s)
        XCTAssertEqual(try JSONDecoder.cramless.decode(AppSettings.self, from: data), s)
    }

    // MARK: The harness

    #if DEBUG
    func testTheStreakScenarioMakesAStreakOfExactlyThatLength() {
        for days in [3, 29, 99, 364] {
            app.applyStreakScenario(days)
            let streak = app.streak()
            XCTAssertEqual(streak.current, days)
            XCTAssertFalse(streak.studiedToday)
        }
        app.applyStreakScenario(29)
        XCTAssertEqual(StreakEngine.milestoneCrossed(from: app.streak().current, to: app.streak().current + 1), 30)
    }

    func testTheQuestScenariosLeaveTheWeekWhereTheyPromise() {
        let course = makeCourse()
        for _ in 0..<12 { makeItem(in: course, kind: .recall) }
        for _ in 0..<12 { makeItem(in: course, kind: .cloze) }
        for _ in 0..<12 { makeItem(in: course) }
        app.save()
        for (mode, done, week) in [("start", 0, 7), ("partial", 1, 5), ("done", 3, 8), ("weekFull", 2, 11)] {
            // A fresh day each time, so each scenario starts from nothing.
            clock.advance(14 * 86_400)
            app.applyQuestScenario(mode)
            XCTAssertEqual(app.questsToday().done, done, mode)
            XCTAssertEqual(app.questsToday().week, week, mode)
        }
        // One more quest and the week is 12: the sky lights.
        XCTAssertEqual(app.questsToday().rows.first { !$0.isDone }?.kind, .finishSession)
    }
    #endif
}

private extension Int {
    /// nil for zero, so a test can say "nothing written".
    var nonZero: Int? { self == 0 ? nil : self }
}

// MARK: - Sync

final class QuestMaskSyncTests: XCTestCase {
    private let day = EngineTest.date(2026, 10, 22, 12)

    func testTheMaskGoesUpAsQuestMask() {
        let record = DayRecord(dayKey: "2026-10-22", day: day, sessions: 1, questMask: 0b101)
        let row = SyncRecords.row(record, now: day)
        XCTAssertEqual(row.int("quest_mask"), 5)
        XCTAssertEqual(SyncRecords.makeDay(row)?.questMask, 5)
    }

    func testARowFromBeforeQuestsHasNoMask() {
        var row = SyncRecords.row(DayRecord(dayKey: "2026-10-22", day: day, sessions: 1), now: day)
        row["quest_mask"] = nil
        XCTAssertEqual(SyncRecords.makeDay(row)?.questMask, 0)
    }

    func testTwoDevicesMasksJoinByOr() {
        let local = DayRecord(dayKey: "2026-10-22", day: day, sessions: 1, questMask: 0b0011)
        var row = SyncRecords.row(local, now: day)
        row["quest_mask"] = .integer(0b0110)
        XCTAssertTrue(SyncRecords.merge(local, with: row))
        XCTAssertEqual(local.questMask, 0b0111)
        XCTAssertFalse(SyncRecords.merge(local, with: row), "merging again changes nothing")
        XCTAssertEqual(local.questMask, 0b0111)
    }

    func testAMaskTheServerLacksBitsOfGoesUpAgain() {
        let local = DayRecord(dayKey: "2026-10-22", day: day, sessions: 1, questMask: 0b111)
        var row = SyncRecords.row(local, now: day)
        XCTAssertFalse(SyncRecords.serverIsBehind(local, row))
        row["quest_mask"] = .integer(0b001)
        XCTAssertTrue(SyncRecords.serverIsBehind(local, row))
        SyncRecords.merge(local, with: row)
        XCTAssertEqual(local.questMask, 0b111, "the server's mask never takes bits away")
        XCTAssertTrue(SyncRecords.serverIsBehind(local, row), "…and it is still behind")
    }

    func testTheStreakEngineJoinsTheMasksOfTwoRecordsForTheSameDay() {
        let a = DaySnapshot(dayKey: "2026-10-22", day: day, sessions: 1, questMask: 0b01)
        let b = DaySnapshot(dayKey: "2026-10-22", day: day, sessions: 1, questMask: 0b10)
        let engine = StreakEngine(calendar: EngineTest.calendar(), now: day, dailyMinutes: 15)
        let merged = engine.index([a, b])
        XCTAssertEqual(merged.values.first?.questMask, 0b11)
    }
}
