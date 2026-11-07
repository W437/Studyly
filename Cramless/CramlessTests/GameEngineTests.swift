import SwiftUI
import UIKit
import XCTest
@testable import Cramless

// The game loop's pure parts: the flame's stages and the milestones, the daily quests, the badges, when to ask for a
// rating, the skies and the icons.

// MARK: - Streak stages and milestones

final class StreakStageTests: XCTestCase {
    let cal = EngineTest.calendar()
    lazy var now = EngineTest.date(2026, 10, 22, 9, in: cal)

    /// Day records from a pattern, oldest first, ending `endingDaysAgo` days ago: "s" studied, "f" frozen, "r" repaired,
    /// "-" missed.
    private func records(_ pattern: String, endingDaysAgo: Int = 1) -> [DaySnapshot] {
        let chars = Array(pattern)
        var out: [DaySnapshot] = []
        for (i, ch) in chars.enumerated() {
            let back = endingDaysAgo + (chars.count - 1 - i)
            let day = cal.startOfDay(for: cal.adding(days: -back, to: now))
            let key = cal.dayKey(for: day.addingTimeInterval(12 * 3600))
            switch ch {
            case "s": out.append(DaySnapshot(dayKey: key, day: day, studySeconds: 720, itemsReviewed: 18, sessions: 1))
            case "f": out.append(DaySnapshot(dayKey: key, day: day, frozen: true))
            case "r": out.append(DaySnapshot(dayKey: key, day: day, repaired: true))
            default: break
            }
        }
        return out
    }

    private var engine: StreakEngine { StreakEngine(calendar: cal, now: now, dailyMinutes: 15) }

    func testTheStagesBeginWhereTheFlameChanges() {
        let expected: [(Int, StreakStage)] = [
            (-3, .none), (0, .none), (1, .spark), (6, .spark), (7, .week), (29, .week), (30, .month), (99, .month),
            (100, .hundred), (364, .hundred), (365, .year), (2000, .year),
        ]
        for (days, stage) in expected { XCTAssertEqual(StreakStage(days: days), stage, "\(days) days") }
        for stage in StreakStage.allCases where stage != .none {
            XCTAssertEqual(StreakStage(days: stage.firstDay), stage, "\(stage) begins on its first day")
            XCTAssertEqual(StreakStage(days: stage.firstDay - 1).rawValue, stage.rawValue - 1, "\(stage): the day before is the stage before")
        }
        XCTAssertEqual(StreakStage.allCases.sorted(), StreakStage.allCases, "the stages are in order")
    }

    func testEachStageGrowsIntoTheNextAndTheLastDoesNot() {
        XCTAssertEqual(StreakStage.none.next, .spark)
        XCTAssertEqual(StreakStage.spark.next, .week)
        XCTAssertEqual(StreakStage.hundred.next, .year)
        XCTAssertNil(StreakStage.year.next)
    }

    func testTheMilestonesAreTheStageStartsAndThreeDays() {
        XCTAssertEqual(StreakStage.milestones, [3, 7, 30, 100, 365])
        XCTAssertEqual(StreakEngine.milestones, StreakStage.milestones)
        for stage in StreakStage.allCases where stage >= .week {
            XCTAssertTrue(StreakStage.milestones.contains(stage.firstDay), "\(stage) starts on a milestone")
        }
        XCTAssertEqual(Set(CelebrationPolicy.streakMilestones.keys), Set(StreakStage.milestones),
                       "the celebration policy sizes exactly the milestones there are")
    }

    func testTheNextMilestone() {
        XCTAssertEqual(StreakStage.nextMilestone(after: 0), 3)
        XCTAssertEqual(StreakStage.nextMilestone(after: 2), 3)
        XCTAssertEqual(StreakStage.nextMilestone(after: 3), 7)
        XCTAssertEqual(StreakStage.nextMilestone(after: 29), 30)
        XCTAssertEqual(StreakStage.nextMilestone(after: 364), 365)
        XCTAssertNil(StreakStage.nextMilestone(after: 365))
        XCTAssertEqual(StreakEngine.nextMilestone(after: 12), 30)
    }

    func testAMilestoneIsCrossedGoingUpToOrPastIt() {
        XCTAssertNil(StreakEngine.milestoneCrossed(from: 0, to: 1))
        XCTAssertEqual(StreakEngine.milestoneCrossed(from: 2, to: 3), 3)
        XCTAssertEqual(StreakEngine.milestoneCrossed(from: 6, to: 7), 7)
        XCTAssertNil(StreakEngine.milestoneCrossed(from: 7, to: 8), "standing on one is not crossing it again")
        XCTAssertEqual(StreakEngine.milestoneCrossed(from: 29, to: 30), 30)
        XCTAssertEqual(StreakEngine.milestoneCrossed(from: 2, to: 9), 7, "a jump past two names the bigger")
        XCTAssertEqual(StreakEngine.milestoneCrossed(from: 99, to: 365), 365)
        XCTAssertNil(StreakEngine.milestoneCrossed(from: 5, to: 3), "going down crosses nothing")
        XCTAssertEqual(CelebrationPolicy.milestone(from: 28, to: 30), 30, "the celebration policy asks the same question")
    }

    func testAFreezeCountsAsADayWhenTheStreakCrossesAMilestone() {
        // Five studied days and a frozen one make 6; studying today makes 7.
        let before = engine.state(records("sssssf"))
        XCTAssertEqual(before.current, 6)
        let after = engine.state(records("sssssf") + records("s", endingDaysAgo: 0))
        XCTAssertEqual(after.current, 7)
        XCTAssertEqual(StreakEngine.milestoneCrossed(from: before.current, to: after.current), 7)
    }

    func testARepairJoinsTheStreakBackUpAndCanCrossAMilestone() {
        // Five days, a missed one, two more: the streak is 2. Repairing the missed day joins them: 8, and today makes 9.
        let before = engine.state(records("sssss-ss"))
        XCTAssertEqual(before.current, 2)
        let repaired = engine.state(records("sssssrss") + records("s", endingDaysAgo: 0))
        XCTAssertEqual(repaired.current, 9)
        XCTAssertEqual(StreakEngine.milestoneCrossed(from: before.current, to: repaired.current), 7)
    }
}

// MARK: - Daily quests

final class QuestEngineTests: XCTestCase {
    /// A day with plenty to do, at noon: every kind but "before noon" and the event's is eligible.
    private func full(_ change: (inout QuestContext) -> Void = { _ in }) -> QuestContext {
        var c = QuestContext()
        c.minuteOfDay = 12 * 60
        c.fadingStars = 10
        c.ownWordsItems = 10
        c.openMixUps = 2
        c.newItems = 20
        c.checkedItems = 30
        c.examItems = 12
        change(&c)
        return c
    }

    func testTheBitsNeverMove() {
        // Stored and synced: these numbers are a promise.
        XCTAssertEqual(QuestKind.allCases.map(\.rawValue), Array(0...8))
        XCTAssertEqual(QuestKind.finishSession.bit, 1)
        XCTAssertEqual(QuestKind.rescueFading.bit, 2)
        XCTAssertEqual(QuestKind.ownWords.bit, 4)
        XCTAssertEqual(QuestKind.beforeNoon.bit, 8)
        XCTAssertEqual(QuestKind.fixMixUp.bit, 16)
        XCTAssertEqual(QuestKind.learnNew.bit, 32)
        XCTAssertEqual(QuestKind.rightInARow.bit, 64)
        XCTAssertEqual(QuestKind.examTopic.bit, 128)
        XCTAssertEqual(QuestKind.event.bit, 256)
        XCTAssertLessThan(QuestKind.allCases.map(\.bit).reduce(0, |), 1024, "the column's check allows these bits")
    }

    func testWhatEachQuestAsksFor() {
        XCTAssertEqual(QuestKind.allCases.map(\.goal), [1, 3, 2, 1, 1, 5, 5, 5, 1])
    }

    func testAMaskNamesItsQuests() {
        XCTAssertEqual(QuestKind.kinds(inMask: 0), [])
        XCTAssertEqual(QuestKind.kinds(inMask: 0b101), [.finishSession, .ownWords])
        XCTAssertEqual(QuestKind.kinds(inMask: QuestKind.fixMixUp.bit | QuestKind.event.bit), [.fixMixUp, .event])
    }

    func testEveryDayHasTheCoreQuestAndTwoMoreOnADayWithPlentyToDo() {
        for day in 20_000..<20_050 {
            let picks = QuestEngine.pick(day: day, context: full())
            XCTAssertEqual(picks.count, 3, "day \(day)")
            XCTAssertEqual(picks.first, .finishSession)
            XCTAssertEqual(Set(picks).count, 3, "no quest twice")
            XCTAssertFalse(picks.contains(.beforeNoon), "it was picked at noon")
            XCTAssertFalse(picks.contains(.event))
        }
    }

    func testGoldenPicksAreTheSameOnEveryDeviceAndEveryRun() {
        // Worked out by an independent implementation of the seeded hash (the same on every platform), not by this one.
        let expected: [(Int, [QuestKind])] = [
            (20_000, [.rightInARow, .fixMixUp]), (20_001, [.learnNew, .examTopic]), (20_002, [.learnNew, .rightInARow]),
            (20_003, [.rightInARow, .rescueFading]), (20_004, [.ownWords, .examTopic]), (20_005, [.ownWords, .learnNew]),
            (20_006, [.fixMixUp, .ownWords]), (20_007, [.fixMixUp, .rescueFading]), (20_008, [.rightInARow, .rescueFading]),
            (20_009, [.rescueFading, .learnNew]),
        ]
        for (day, others) in expected {
            XCTAssertEqual(QuestEngine.pick(day: day, context: full()), [.finishSession] + others, "day \(day)")
        }
        // Opened early, "before noon" joins the pool.
        XCTAssertEqual(QuestEngine.pick(day: 20_004, context: full { $0.minuteOfDay = 8 * 60 }),
                       [.finishSession, .ownWords, .beforeNoon])
        XCTAssertEqual(QuestEngine.pick(day: 20_000, context: full { $0.minuteOfDay = 8 * 60 }),
                       [.finishSession, .rightInARow, .fixMixUp])
    }

    func testYesterdaysQuestsComeLastWhenAnotherWillDo() {
        // With yesterday's two out of the way: day 20,002 would have been learn-new and right-in-a-row.
        let picks = QuestEngine.pick(day: 20_002, context: full { $0.yesterday = [.learnNew, .examTopic] })
        XCTAssertEqual(picks, [.finishSession, .rightInARow, .fixMixUp])
        // ...but if nothing else is possible they are picked again rather than left out.
        let thin = full { c in
            c.fadingStars = 3; c.ownWordsItems = 0; c.openMixUps = 0; c.newItems = 0; c.checkedItems = 0; c.examItems = 0
            c.yesterday = [.rescueFading]
        }
        XCTAssertEqual(QuestEngine.pick(day: 20_000, context: thin), [.finishSession, .rescueFading])
    }

    func testNothingOnExamEveOrWithNoMaterial() {
        XCTAssertEqual(QuestEngine.pick(day: 20_000, context: full { $0.examEve = true }), [])
        XCTAssertEqual(QuestEngine.pick(day: 20_000, context: full { $0.hasMaterial = false }), [])
        for kind in QuestKind.allCases {
            XCTAssertFalse(QuestEngine.isEligible(kind, full { $0.examEve = true }), "\(kind) on exam eve")
        }
    }

    func testAQuestIsOnlyOfferedWhenItCanBeDone() {
        func eligible(_ kind: QuestKind, _ change: (inout QuestContext) -> Void) -> Bool {
            QuestEngine.isEligible(kind, full(change))
        }
        XCTAssertTrue(eligible(.finishSession) { _ in })
        XCTAssertFalse(eligible(.rescueFading) { $0.fadingStars = 2 }, "saving 3 needs 3 fading")
        XCTAssertTrue(eligible(.rescueFading) { $0.fadingStars = 3 })
        XCTAssertFalse(eligible(.ownWords) { $0.ownWordsItems = 1 })
        XCTAssertTrue(eligible(.ownWords) { $0.ownWordsItems = 2 })
        XCTAssertFalse(eligible(.fixMixUp) { $0.openMixUps = 0 })
        XCTAssertFalse(eligible(.learnNew) { $0.newItems = 4 })
        XCTAssertTrue(eligible(.learnNew) { $0.newItems = 5 })
        XCTAssertFalse(eligible(.rightInARow) { $0.checkedItems = 4 }, "flashcards don't build a run")
        XCTAssertFalse(eligible(.examTopic) { $0.examItems = 4 })
        XCTAssertFalse(eligible(.event) { _ in })
        XCTAssertTrue(eligible(.event) { $0.eventActive = true })
    }

    func testBeforeNoonOnlyIfTheDayWasOpenedBeforeTen() {
        XCTAssertTrue(QuestEngine.isEligible(.beforeNoon, full { $0.minuteOfDay = 9 * 60 + 59 }))
        XCTAssertFalse(QuestEngine.isEligible(.beforeNoon, full { $0.minuteOfDay = 10 * 60 }))
        XCTAssertFalse(QuestEngine.isEligible(.beforeNoon, full { $0.minuteOfDay = 14 * 60 }))
    }

    func testAnEventQuestIsAlwaysPickedWhenThereIsOne() {
        for day in 20_000..<20_020 {
            let picks = QuestEngine.pick(day: day, context: full { $0.eventActive = true })
            XCTAssertEqual(picks.prefix(2), [.finishSession, .event], "day \(day)")
            XCTAssertEqual(picks.count, 3)
        }
    }

    func testAThinDayStillHasTheCoreQuest() {
        var c = QuestContext()
        c.minuteOfDay = 12 * 60
        XCTAssertEqual(QuestEngine.pick(day: 20_000, context: c), [.finishSession])
    }

    func testProgressIsReadFromTheDaysFacts() {
        var f = QuestFacts()
        XCTAssertEqual(QuestEngine.progress(.finishSession, facts: f), QuestProgress(done: 0, goal: 1))
        f.sessionsFinished = 2
        XCTAssertEqual(QuestEngine.progress(.finishSession, facts: f), QuestProgress(done: 1, goal: 1), "never past the goal")
        f.saves = 2
        XCTAssertEqual(QuestEngine.progress(.rescueFading, facts: f), QuestProgress(done: 2, goal: 3))
        XCTAssertFalse(QuestEngine.progress(.rescueFading, facts: f).isComplete)
        f.saves = 3
        XCTAssertTrue(QuestEngine.progress(.rescueFading, facts: f).isComplete)
        f.ownWordsAnswers = 2
        f.newLearned = 4
        f.bestRun = 5
        f.examAnswers = 5
        f.mixUpsFixed = 1
        XCTAssertTrue(QuestEngine.progress(.ownWords, facts: f).isComplete)
        XCTAssertFalse(QuestEngine.progress(.learnNew, facts: f).isComplete)
        XCTAssertTrue(QuestEngine.progress(.rightInARow, facts: f).isComplete)
        XCTAssertTrue(QuestEngine.progress(.examTopic, facts: f).isComplete)
        XCTAssertTrue(QuestEngine.progress(.fixMixUp, facts: f).isComplete)
        XCTAssertFalse(QuestEngine.progress(.event, facts: f).isComplete)
        f.eventDone = true
        XCTAssertTrue(QuestEngine.progress(.event, facts: f).isComplete)
    }

    func testBeforeNoonLooksAtTheFirstSessionToFinish() {
        var f = QuestFacts()
        XCTAssertFalse(QuestEngine.progress(.beforeNoon, facts: f).isComplete, "no session yet")
        f.firstFinishedMinute = 11 * 60 + 59
        XCTAssertTrue(QuestEngine.progress(.beforeNoon, facts: f).isComplete)
        f.firstFinishedMinute = 12 * 60
        XCTAssertFalse(QuestEngine.progress(.beforeNoon, facts: f).isComplete, "at noon is not before it")
    }

    func testTheQuestsADayHasFinished() {
        var f = QuestFacts()
        f.sessionsFinished = 1
        f.saves = 3
        let picks: [QuestKind] = [.finishSession, .rescueFading, .ownWords]
        XCTAssertEqual(QuestEngine.completed(picks: picks, facts: f), [.finishSession, .rescueFading])
        XCTAssertEqual(QuestEngine.completed(picks: [], facts: f), [])
    }

    // MARK: The week

    func testAMasksCountIsCappedAtThreeADay() {
        XCTAssertEqual(QuestEngine.count(mask: 0), 0)
        XCTAssertEqual(QuestEngine.count(mask: 0b111), 3)
        XCTAssertEqual(QuestEngine.count(mask: 0b1111), 3, "two devices' picks together are still three quests")
        XCTAssertEqual(QuestEngine.count(mask: 0b1_1111_1111), 3)
    }

    func testTheWeekStartsOnTheCalendarsFirstWeekday() {
        for firstWeekday in 1...7 {
            for day in 20_000..<20_014 {
                let start = QuestEngine.weekStart(of: day, firstWeekday: firstWeekday)
                XCTAssertEqual(Calendar.weekday(dayNumber: start), firstWeekday, "day \(day), weeks begin on \(firstWeekday)")
                XCTAssertTrue((start...(start + 6)).contains(day), "day \(day) is in its own week")
            }
        }
    }

    func testTheWeekCountsThisCalendarWeekOnly() {
        // Sunday Oct 25 and the days before it, in a calendar whose weeks begin on Sunday (US) or Monday.
        for firstWeekday in [1, 2] {
            var cal = EngineTest.calendar()
            cal.firstWeekday = firstWeekday
            let sunday = cal.dayNumber(for: EngineTest.date(2026, 10, 25, 12, in: cal))
            XCTAssertEqual(Calendar.weekday(dayNumber: sunday), 1)
            // One quest on each of the six days before it, three on Sunday.
            var masks: [Int: Int] = [:]
            for back in 1...6 { masks[sunday - back] = 1 }
            masks[sunday] = 0b111
            let expected = firstWeekday == 1 ? 3 : 9   // Sunday-first: only Sunday itself; Monday-first: Monday to Sunday
            XCTAssertEqual(QuestEngine.weekCount(masks: masks, today: sunday, firstWeekday: firstWeekday), expected,
                           "weeks begin on \(firstWeekday)")
        }
    }

    func testAWeekAcrossTheClocksChangeStillHasSevenDays() {
        // The clocks went back on Sunday Nov 1, 2026, a 25-hour day. Sunday-first, the week of Nov 1 to 7.
        let cal = EngineTest.calendar()
        let sunday = cal.dayNumber(for: EngineTest.date(2026, 11, 1, 12, in: cal))
        var masks: [Int: Int] = [:]
        for offset in 0...6 { masks[sunday + offset] = 0b11 }   // two a day through the week
        masks[sunday - 1] = 0b111                                // Saturday before: another week
        masks[sunday + 7] = 0b111                                // Sunday after: another week
        XCTAssertEqual(QuestEngine.weekCount(masks: masks, today: sunday + 3, firstWeekday: 1), 14)
        XCTAssertEqual(QuestEngine.weekCount(masks: masks, today: sunday - 1, firstWeekday: 1), 3,
                       "the day before is in the week before")
        // Monday-first, that Sunday belongs to the week before it.
        XCTAssertEqual(QuestEngine.weekCount(masks: masks, today: sunday + 3, firstWeekday: 2),
                       2 * 6 + 3, "Monday Nov 2 to Sunday Nov 8: six days of two, and the Sunday after")
        // And the day numbers stay one apart over the 25-hour day.
        XCTAssertEqual(cal.dayNumber(for: EngineTest.date(2026, 11, 2, 0, 30, in: cal)) - sunday, 1)
    }

    func testTheWeeklyGoalIsTwelve() {
        XCTAssertEqual(QuestEngine.weeklyGoal, 12)
        XCTAssertEqual(QuestEngine.perDay, 3)
        XCTAssertGreaterThanOrEqual(QuestEngine.perDay * 7, QuestEngine.weeklyGoal, "a week can reach it")
    }
}

// MARK: - Badges

final class AchievementEngineTests: XCTestCase {
    private func earned(_ change: (inout AchievementFacts) -> Void) -> Set<Badge> {
        var f = AchievementFacts()
        change(&f)
        return AchievementEngine.earned(f)
    }

    func testNothingIsEarnedBeforeAnythingIsDone() {
        XCTAssertEqual(AchievementEngine.earned(AchievementFacts()), [])
    }

    func testEachBadgeIsEarnedAtItsTarget() {
        let cases: [(Badge, (inout AchievementFacts, Int) -> Void)] = [
            (.firstSession, { $0.sessionsFinished = $1 }),
            (.saves10, { $0.saves = $1 }),
            (.ownWords25, { $0.ownWordsAnswers = $1 }),
            (.firstFix, { $0.mixUpsFixed = $1 }),
            (.fifthFix, { $0.mixUpsFixed = $1 }),
            (.streak7, { $0.bestStreak = $1 }),
            (.streak30, { $0.bestStreak = $1 }),
            (.streak100, { $0.bestStreak = $1 }),
            (.streak365, { $0.bestStreak = $1 }),
            (.ready, { $0.readyExams = $1 }),
            (.calledIt, { $0.calledItExams = $1 }),
            (.thousand, { $0.answers = $1 }),
            (.comeback, { $0.repairedDays = $1 }),
        ]
        XCTAssertEqual(Set(cases.map(\.0)), Set(Badge.allCases), "every badge is tested")
        for (badge, set) in cases {
            XCTAssertFalse(earned { set(&$0, badge.target - 1) }.contains(badge), "\(badge) one short")
            XCTAssertTrue(earned { set(&$0, badge.target) }.contains(badge), "\(badge) at its target")
            XCTAssertTrue(earned { set(&$0, badge.target + 50) }.contains(badge), "\(badge) past its target")
        }
    }

    func testASaveBadgeSaysTheRealNumber() {
        XCTAssertEqual(String(localized: Badge.saves10.earned(saves: 10)), "You saved 10 stars that were fading.")
        XCTAssertEqual(String(localized: Badge.saves10.earned(saves: 12)), "You've saved 12 stars that were fading.", "never 10 above \"12 saved\"")
        XCTAssertEqual(String(localized: Badge.firstSession.earned(saves: 12)), String(localized: Badge.firstSession.blurb))
    }

    func testTargetsAreWhatTheBadgesSay() {
        XCTAssertEqual(Badge.saves10.target, 10)
        XCTAssertEqual(Badge.ownWords25.target, 25)
        XCTAssertEqual(Badge.fifthFix.target, 5)
        XCTAssertEqual([Badge.streak7, .streak30, .streak100, .streak365].map(\.target), [7, 30, 100, 365],
                       "the streak badges are the flame's stages")
        XCTAssertEqual(Badge.thousand.target, 1000)
    }

    func testBadgesOnlyEverGrowWithTheFacts() {
        // Every fact only grows, so a bigger history never loses a badge.
        var f = AchievementFacts()
        var before: Set<Badge> = []
        let steps: [(inout AchievementFacts) -> Void] = [
            { $0.sessionsFinished += 1 }, { $0.answers += 400 }, { $0.saves += 10 }, { $0.bestStreak = 7 },
            { $0.ownWordsAnswers += 25 }, { $0.mixUpsFixed += 1 }, { $0.readyExams += 1 }, { $0.bestStreak = 30 },
            { $0.answers += 600 }, { $0.mixUpsFixed += 4 }, { $0.repairedDays += 1 }, { $0.calledItExams += 1 },
            { $0.bestStreak = 365 },
        ]
        for step in steps {
            step(&f)
            let now = AchievementEngine.earned(f)
            XCTAssertTrue(before.isSubset(of: now), "a badge was lost")
            before = now
        }
        XCTAssertEqual(before, Set(Badge.allCases), "after all of that, every badge")
    }

    func testNewBadgesAreWhatTheSessionAdded() {
        let before: Set<Badge> = [.firstSession]
        let after: Set<Badge> = [.firstSession, .streak7, .saves10]
        XCTAssertEqual(AchievementEngine.newlyEarned(before: before, after: after), [.saves10, .streak7],
                       "in the catalog's order")
        XCTAssertEqual(AchievementEngine.newlyEarned(before: after, after: after), [])
        XCTAssertEqual(AchievementEngine.newlyEarned(before: after, after: before), [], "never a badge taken away")
    }

    func testProgressIsClampedAndGivesAFraction() {
        var f = AchievementFacts()
        f.saves = 4
        let p = AchievementEngine.progress(.saves10, f)
        XCTAssertEqual(p, BadgeProgress(value: 4, target: 10))
        XCTAssertEqual(p.fraction, 0.4, accuracy: 1e-9)
        XCTAssertFalse(p.isEarned)
        f.saves = 400
        XCTAssertEqual(AchievementEngine.progress(.saves10, f), BadgeProgress(value: 10, target: 10))
        XCTAssertEqual(AchievementEngine.progress(.saves10, f).fraction, 1)
    }

    func testReadyAndCalledItReadTheExamMorningNumbers() {
        XCTAssertEqual(AchievementFacts.readyAt, 0.8)
        XCTAssertEqual(AchievementFacts.calledItWithin, 0.05)
    }
}

final class BadgeSelectionTests: XCTestCase {
    private func status(_ badge: Badge, value: Int, earned date: Date? = nil) -> BadgeStatus {
        BadgeStatus(badge: badge, progress: BadgeProgress(value: min(value, badge.target), target: badge.target), earnedAt: date)
    }

    func testTheLatestEarnedComeFirstThenTheOnesNearestToBeingEarned() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let all = [
            status(.firstSession, value: 1, earned: day),
            status(.saves10, value: 8),
            status(.streak7, value: 7, earned: day.addingTimeInterval(86_400)),
            status(.ownWords25, value: 5),
            status(.thousand, value: 900),
            status(.comeback, value: 0),
        ]
        let shown = all.featured(limit: 4).map(\.badge)
        XCTAssertEqual(shown, [.streak7, .firstSession, .thousand, .saves10], "900 of 1000 is nearer than 8 of 10")
        XCTAssertEqual(all.featured(limit: 2).map(\.badge), [.streak7, .firstSession])
        XCTAssertEqual(all.featured(limit: 99).count, 6)
    }

    func testBadgesWithNoProgressComeLastInTheCatalogsOrder() {
        let all = [status(.ready, value: 0), status(.firstSession, value: 0), status(.comeback, value: 0)]
        XCTAssertEqual(all.featured(limit: 3).map(\.badge), [.ready, .firstSession, .comeback], "ties keep their order")
    }
}

// MARK: - When to ask for a rating

final class ReviewPromptPolicyTests: XCTestCase {
    private func facts(_ change: (inout ReviewPromptPolicy.Facts) -> Void = { _ in }) -> ReviewPromptPolicy.Facts {
        var f = ReviewPromptPolicy.Facts()
        f.answered = 8
        f.rightFirstTime = 8
        f.sessionsFinished = 6
        f.daysSinceInstall = 5
        change(&f)
        return f
    }

    func testAPerfectSessionOfEightIsAGoodMoment() {
        XCTAssertEqual(ReviewPromptPolicy.reason(facts()), .perfectSession)
        XCTAssertTrue(ReviewPromptPolicy.shouldAsk(facts()))
        XCTAssertNil(ReviewPromptPolicy.reason(facts { $0.rightFirstTime = 7 }), "one wrong is not perfect")
        XCTAssertNil(ReviewPromptPolicy.reason(facts { $0.answered = 7; $0.rightFirstTime = 7 }), "seven is too few")
    }

    func testTwoSavesAreAGoodMoment() {
        XCTAssertEqual(ReviewPromptPolicy.reason(facts { $0.rightFirstTime = 5; $0.saves = 2 }), .saves)
        XCTAssertNil(ReviewPromptPolicy.reason(facts { $0.rightFirstTime = 5; $0.saves = 1 }))
    }

    func testAMilestoneIsAGoodMomentAndTheFirstOne() {
        XCTAssertEqual(ReviewPromptPolicy.reason(facts { $0.streakMilestone = 30 }), .milestone)
        XCTAssertEqual(ReviewPromptPolicy.reason(facts { $0.rightFirstTime = 3; $0.streakMilestone = 7 }), .milestone)
    }

    func testNotInTheFirstDaysOrSessions() {
        XCTAssertFalse(ReviewPromptPolicy.shouldAsk(facts { $0.daysSinceInstall = 3 }))
        XCTAssertTrue(ReviewPromptPolicy.shouldAsk(facts { $0.daysSinceInstall = 4 }))
        XCTAssertFalse(ReviewPromptPolicy.shouldAsk(facts { $0.sessionsFinished = 4 }))
        XCTAssertTrue(ReviewPromptPolicy.shouldAsk(facts { $0.sessionsFinished = 5 }))
    }

    func testNeverOnExamEveInTheHarnessOrTwiceInAVersion() {
        XCTAssertFalse(ReviewPromptPolicy.shouldAsk(facts { $0.examEve = true }))
        XCTAssertFalse(ReviewPromptPolicy.shouldAsk(facts { $0.harness = true }))
        XCTAssertFalse(ReviewPromptPolicy.shouldAsk(facts { $0.promptedThisVersion = true }))
    }

    func testAtLeast120DaysApart() {
        XCTAssertFalse(ReviewPromptPolicy.shouldAsk(facts { $0.daysSincePrompt = 119 }))
        XCTAssertTrue(ReviewPromptPolicy.shouldAsk(facts { $0.daysSincePrompt = 120 }))
        XCTAssertTrue(ReviewPromptPolicy.shouldAsk(facts { $0.daysSincePrompt = nil }), "never asked")
    }

    func testNoGoodMomentNoPrompt() {
        XCTAssertFalse(ReviewPromptPolicy.shouldAsk(facts { $0.rightFirstTime = 4 }))
    }
}

// MARK: - Skies and icons

final class SkyThemeTests: XCTestCase {
    private func luminance(_ color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> Double { c <= 0.04045 ? Double(c) / 12.92 : pow((Double(c) + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    func testNightIsTheLookCaplingAlwaysHad() {
        let night = SkyTheme.night.palette
        XCTAssertEqual(night.top, Color(hex: 0x070D1B))
        XCTAssertEqual(night.bottom, Color(hex: 0x14213D))
        XCTAssertEqual(night.glowHigh, Color(hex: 0x6C46A8))
        XCTAssertEqual(night.glowMid, Color(hex: 0xE4708C))
        XCTAssertEqual(night.glowLow, Color(hex: 0xFFB070))
        XCTAssertEqual(night.farHills.top, Color(hex: 0x333E78))
        XCTAssertEqual(night.ground.bottom, Color(hex: 0x080E22))
        XCTAssertEqual(SkyRenderer.top, night.top, "the renderer's default is Night")
    }

    func testThereAreSixSkiesAndEachIsItsOwn() {
        XCTAssertEqual(SkyTheme.allCases.count, 6)
        let palettes = SkyTheme.allCases.map(\.palette)
        for (i, a) in palettes.enumerated() {
            for b in palettes[(i + 1)...] {
                XCTAssertNotEqual(a, b)
                XCTAssertNotEqual(a.top, b.top)
                XCTAssertNotEqual(a.glowMid, b.glowMid)
                XCTAssertNotEqual(a.farHills.top, b.farHills.top)
            }
        }
    }

    func testEverySkyIsDarkEnoughForWhiteTextOnItsTop() {
        for theme in SkyTheme.allCases {
            let p = theme.palette
            for color in [p.top, p.bottom] {
                // White on it is at least 7:1, the strictest of WCAG's text levels.
                let contrast = 1.05 / (luminance(color) + 0.05)
                XCTAssertGreaterThanOrEqual(contrast, 7, "\(theme): white on the sky")
            }
            XCTAssertLessThan(luminance(p.top), luminance(p.bottom) + 0.001, "\(theme): darkest at the top")
        }
    }

    func testSkiesLightOneAtATimeInOrder() {
        XCTAssertEqual(SkyTheme.unlocked(weeks: 0), [.night])
        XCTAssertEqual(SkyTheme.unlocked(weeks: 1), [.night, .dusk])
        XCTAssertEqual(SkyTheme.unlocked(weeks: 2), [.night, .dusk, .aurora])
        XCTAssertEqual(SkyTheme.unlocked(weeks: 5), SkyTheme.allCases)
        XCTAssertEqual(SkyTheme.unlocked(weeks: 40), SkyTheme.allCases)
        XCTAssertEqual(SkyTheme.unlocked(weeks: -2), [.night])
        XCTAssertEqual(SkyTheme.next(afterWeeks: 0), .dusk)
        XCTAssertEqual(SkyTheme.next(afterWeeks: 4), .glacier)
        XCTAssertNil(SkyTheme.next(afterWeeks: 5))
        XCTAssertEqual(SkyTheme.allCases.map(\.weekToUnlock), [0, 1, 2, 3, 4, 5])
    }

    func testAChosenSkyIsRememberedByName() throws {
        let data = try JSONEncoder().encode(SkyTheme.aurora)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"aurora\"")
        XCTAssertEqual(try JSONDecoder().decode(SkyTheme.self, from: data), .aurora)
    }
}

final class AppIconChoiceTests: XCTestCase {
    func testAStreakUnlocksIconsAtTheFlamesMilestones() {
        XCTAssertEqual(AppIconChoice.unlocked(best: 0), [.standard])
        XCTAssertEqual(AppIconChoice.unlocked(best: 6), [.standard])
        XCTAssertEqual(AppIconChoice.unlocked(best: 7), [.standard, .night])
        XCTAssertEqual(AppIconChoice.unlocked(best: 29), [.standard, .night])
        XCTAssertEqual(AppIconChoice.unlocked(best: 30), [.standard, .night, .ember])
        XCTAssertEqual(AppIconChoice.unlocked(best: 100), [.standard, .night, .ember, .gold])
        XCTAssertEqual(AppIconChoice.unlocked(best: 365), AppIconChoice.allCases)
        XCTAssertEqual(AppIconChoice.allCases.map(\.unlockDays), [0, 7, 30, 100, 365])
        for icon in AppIconChoice.allCases where icon != .standard {
            XCTAssertTrue(StreakStage.milestones.contains(icon.unlockDays), "\(icon) unlocks on a milestone")
        }
    }

    func testIconsAreNamedForTheSystemAndTheMainOneHasNone() {
        XCTAssertNil(AppIconChoice.standard.alternateName)
        XCTAssertEqual(AppIconChoice.gold.alternateName, "AppIcon-Gold")
        XCTAssertEqual(Set(AppIconChoice.allCases.compactMap(\.alternateName)).count, 4)
        for icon in AppIconChoice.allCases {
            XCTAssertEqual(AppIconChoice(alternateName: icon.alternateName), icon)
        }
        XCTAssertEqual(AppIconChoice(alternateName: "AppIcon-Unknown"), .standard)
        XCTAssertEqual(Set(AppIconChoice.allCases.map(\.previewName)).count, 5)
    }

    func testAnIconUnlockedIsNeverLostWhenTheStreakBreaks() {
        // `unlocked(best:)` reads the best streak, which only grows.
        XCTAssertTrue(AppIconChoice.ember.isUnlocked(best: 34))
        XCTAssertTrue(AppIconChoice.ember.isUnlocked(best: 34), "whatever the streak is now")
    }

    func testTheArtIsInTheAppAndNamedInItsInfo() {
        // Every icon has art in the asset catalog (the system's alternate icon sets, and a preview for the picker), and the
        // built Info.plist lists the alternates the system may switch to.
        let alternates = (Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])?["CFBundleAlternateIcons"] as? [String: Any]
        XCTAssertEqual(Set(alternates?.keys.map { $0 } ?? []), Set(AppIconChoice.allCases.compactMap(\.alternateName)))
        for icon in AppIconChoice.allCases {
            XCTAssertNotNil(UIImage(named: icon.previewName), "\(icon) has no preview image")
        }
    }
}

// MARK: - Copy and pictures

final class GameCopyTests: XCTestCase {
    func testEveryQuestHasWordsAndARealSymbol() {
        for kind in QuestKind.allCases {
            XCTAssertFalse(String(localized: kind.title).isEmpty, "\(kind)")
            XCTAssertNotNil(UIImage(systemName: kind.symbol), "\(kind): no symbol named \(kind.symbol)")
        }
        XCTAssertEqual(Set(QuestKind.allCases.map { String(localized: $0.title) }).count, QuestKind.allCases.count)
    }

    func testEveryBadgeHasWordsAndAGlyph() {
        for badge in Badge.allCases {
            XCTAssertFalse(String(localized: badge.title).isEmpty, "\(badge)")
            XCTAssertFalse(String(localized: badge.blurb).isEmpty, "\(badge)")
            if case .symbol(let name) = badge.glyph { XCTAssertNotNil(UIImage(systemName: name), "\(badge): \(name)") }
        }
        XCTAssertEqual(Set(Badge.allCases.map { String(localized: $0.title) }).count, Badge.allCases.count)
        // A streak badge wears the flame of its stage.
        XCTAssertEqual(Badge.streak30.glyph, .flame(.month))
        XCTAssertEqual(Badge.streak365.glyph, .flame(.year))
    }

    func testTheExamQuestNamesTheExam() {
        let row = QuestRow(kind: .examTopic, progress: QuestProgress(done: 2, goal: 5), isDone: false, subject: "Bio 101")
        XCTAssertEqual(String(localized: row.title), "Practise for Bio 101")
        XCTAssertEqual(String(localized: row.progressText ?? "none"), "2 of 5")
        let done = QuestRow(kind: .finishSession, progress: QuestProgress(done: 1, goal: 1), isDone: true, subject: nil)
        XCTAssertNil(done.progressText, "a single thing to do has no count")
        XCTAssertNil(QuestRow(kind: .rescueFading, progress: QuestProgress(done: 3, goal: 3), isDone: true, subject: nil).progressText)
    }

    func testEachMilestoneHasItsOwnLine() {
        let lines = StreakStage.milestones.map { String(localized: MilestoneCopy.line($0)) }
        XCTAssertEqual(Set(lines).count, StreakStage.milestones.count)
        XCTAssertEqual(String(localized: MilestoneCopy.title(30)), "30 days.")
        XCTAssertEqual(String(localized: MilestoneCopy.next(after: 12) ?? "none"), "Next: 30 days")
        XCTAssertNil(MilestoneCopy.next(after: 400))
    }

    func testSkiesAndIconsHaveNames() {
        XCTAssertEqual(SkyTheme.allCases.map { String(localized: $0.title) }, ["Night", "Dusk", "Aurora", "Ember", "Bloom", "Glacier"])
        XCTAssertEqual(String(localized: SkyTheme.dusk.lockedLine), "A week of 12 quests")
        XCTAssertEqual(String(localized: SkyTheme.glacier.lockedLine), "5 weeks of 12 quests")
        XCTAssertEqual(String(localized: AppIconChoice.gold.lockedLine), "At 100 days")
    }
}
