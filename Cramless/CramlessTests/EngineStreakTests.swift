import Foundation
import XCTest
@testable import Cramless

final class EngineStreakTests: XCTestCase {
    let cal = EngineTest.calendar()
    lazy var now = EngineTest.date(2026, 10, 22, 9, in: cal)

    /// Day records from a pattern, oldest first, ending yesterday: "s" studied, "f" frozen, "r" repaired,
    /// "-" missed (no record).
    func records(_ pattern: String, endingDaysAgo: Int = 1, minutes: Int = 12) -> [DaySnapshot] {
        let chars = Array(pattern)
        var out: [DaySnapshot] = []
        for (i, ch) in chars.enumerated() {
            let back = endingDaysAgo + (chars.count - 1 - i)
            let day = cal.startOfDay(for: cal.adding(days: -back, to: now))
            let key = cal.dayKey(for: day.addingTimeInterval(12 * 3600))
            switch ch {
            case "s": out.append(DaySnapshot(dayKey: key, day: day, studySeconds: Double(minutes * 60), itemsReviewed: 20, sessions: 1))
            case "f": out.append(DaySnapshot(dayKey: key, day: day, frozen: true))
            case "r": out.append(DaySnapshot(dayKey: key, day: day, repaired: true))
            default: break
            }
        }
        return out
    }

    func engine(at date: Date? = nil) -> StreakEngine { StreakEngine(calendar: cal, now: date ?? now, dailyMinutes: 15) }

    func testTheDemoShape() {
        // 17 studied, one missed, 6 studied, a frozen day, 5 studied up to yesterday.
        let state = engine().state(records(String(repeating: "s", count: 17) + "-" + "ssssss" + "f" + "sssss"))
        XCTAssertEqual(state.current, 12)
        XCTAssertEqual(state.best, 17)
        XCTAssertFalse(state.studiedToday)
        XCTAssertEqual(state.freezesAvailable, 2)
        XCTAssertEqual(state.frozenDays, [cal.startOfDay(for: cal.adding(days: -6, to: now))])
        XCTAssertNil(state.repairableDay)
    }

    func testAliveThroughTodayOnlyIfYesterdayCounted() {
        XCTAssertEqual(engine().state(records("sss")).current, 3)
        XCTAssertEqual(engine().state(records("sss", endingDaysAgo: 2)).current, 0)
        var withToday = records("sss")
        withToday += records("s", endingDaysAgo: 0)
        let state = engine().state(withToday)
        XCTAssertEqual(state.current, 4)
        XCTAssertTrue(state.studiedToday)
    }

    func testFreezesAreEarnedEverySevenDaysAndCappedAtTwo() {
        XCTAssertEqual(engine().state(records("ssssss")).freezesAvailable, 0)
        XCTAssertEqual(engine().state(records("sssssss")).freezesAvailable, 1)
        XCTAssertEqual(engine().state(records(String(repeating: "s", count: 14))).freezesAvailable, 2)
        XCTAssertEqual(engine().state(records(String(repeating: "s", count: 30))).freezesAvailable, 2)
        // A missed day resets the run; frozen days spend.
        XCTAssertEqual(engine().state(records("ssssss-ssssss")).freezesAvailable, 0)
        XCTAssertEqual(engine().state(records("sssssssfs")).freezesAvailable, 0)
    }

    func testAFreezeCoversASingleMissedDay() {
        // Studied 7 days, missed yesterday: the read model applies the freeze before the rollover writes it.
        let recs = records("sssssss", endingDaysAgo: 2)
        let state = engine().state(recs)
        XCTAssertEqual(state.current, 8, "seven studied plus yesterday frozen")
        XCTAssertEqual(state.freezesAvailable, 0)
        XCTAssertEqual(state.frozenDays.first, cal.startOfDay(for: cal.adding(days: -1, to: now)))
        XCTAssertEqual(engine().freezeToApply(recs), cal.startOfDay(for: cal.adding(days: -1, to: now)))
        // Without a freeze held the streak breaks, and the day can be repaired.
        let none = engine().state(records("ssss", endingDaysAgo: 2))
        XCTAssertEqual(none.current, 0)
        XCTAssertEqual(none.repairableDay, cal.startOfDay(for: cal.adding(days: -1, to: now)))
    }

    func testAFreezeNeverCoversTwoDaysInARow() {
        let recs = records(String(repeating: "s", count: 14), endingDaysAgo: 3)
        XCTAssertNil(engine().freezeToApply(recs))
        XCTAssertEqual(engine().state(recs).current, 0)
        // After a frozen day, another missed day isn't frozen.
        XCTAssertNil(engine().freezeToApply(records(String(repeating: "s", count: 14) + "f", endingDaysAgo: 2)))
    }

    func testRepairWithinTwoDays() {
        // Missed the day before yesterday, studied yesterday: repairable.
        let recs = records("sssss-s")
        let state = engine().state(recs)
        XCTAssertEqual(state.repairableDay, cal.startOfDay(for: cal.adding(days: -2, to: now)))
        XCTAssertEqual(state.current, 1)
        // Repaired, the streak joins up.
        var repaired = recs
        let missed = cal.startOfDay(for: cal.adding(days: -2, to: now))
        repaired.append(DaySnapshot(dayKey: cal.dayKey(for: missed.addingTimeInterval(12 * 3600)), day: missed, repaired: true))
        XCTAssertEqual(engine().state(repaired).current, 7)
        // Too long ago: not repairable.
        XCTAssertNil(engine().state(records("sssss-ss")).repairableDay)
        XCTAssertTrue(engine().repairQualifies(todaySeconds: 30 * 60))
        XCTAssertFalse(engine().repairQualifies(todaySeconds: 29 * 60))
    }

    /// Across the end of US daylight saving (Sunday, Nov 1, 2026: a 25-hour day) and its start (Sunday, Mar 8,
    /// 2026: 23 hours), every day still counts once.
    func testStreaksAcrossDaylightSavingChanges() {
        for now in [EngineTest.date(2026, 11, 8, 20, in: cal), EngineTest.date(2026, 3, 15, 0, 30, in: cal)] {
            var recs: [DaySnapshot] = []
            for back in 1...14 {
                // Records written at different times of day, as they would be.
                let at = cal.adding(days: -back, to: now)
                let day = cal.startOfDay(for: at)
                recs.append(DaySnapshot(dayKey: cal.dayKey(for: at), day: day, studySeconds: 600, sessions: 1))
            }
            let e = StreakEngine(calendar: cal, now: now, dailyMinutes: 15)
            let state = e.state(recs)
            XCTAssertEqual(state.current, 14, "\(now)")
            XCTAssertEqual(state.best, 14)
            XCTAssertEqual(state.freezesAvailable, 2)
            let cells = e.heatmap(recs, weeks: 12)
            XCTAssertEqual(cells.count, 84)
            XCTAssertEqual(Set(cells.map(\.dayKey)).count, 84)
            XCTAssertEqual(cells.filter { $0.minutes == 10 }.count, 14)
            XCTAssertEqual(cells.filter(\.isToday).count, 1)
        }
    }

    func testHeatmapIsWholeWeeks() {
        let e = engine()
        let cells = e.heatmap(records("ssfs-s", minutes: 30), weeks: 12)
        XCTAssertEqual(cells.count, 84)
        XCTAssertEqual(cal.component(.weekday, from: cells[0].date), cal.firstWeekday)
        XCTAssertTrue(cells.filter(\.isFuture).allSatisfy { $0.date > now })
        XCTAssertEqual(cells.filter { $0.frozen }.count, 1)
        XCTAssertEqual(cells.first { $0.minutes == 30 }?.level, 4)
        XCTAssertEqual(e.level(minutes: 5, studied: true), 1)
        XCTAssertEqual(e.level(minutes: 10, studied: true), 2)
        XCTAssertEqual(e.level(minutes: 15, studied: true), 3)
        XCTAssertEqual(e.level(minutes: 0, studied: false), 0)
    }

    func testWeeklyStats() {
        // Thursday Oct 22, weeks start Sunday: Sun–Wed this week, plus last week.
        let stats = engine().weekly(records("sssssss-sss", minutes: 10))
        XCTAssertEqual(stats.days.count, 7)
        XCTAssertEqual(cal.component(.weekday, from: stats.days[0].date), 1)
        XCTAssertEqual(stats.days.filter(\.isToday).count, 1)
        XCTAssertEqual(stats.totalMinutes, 30, "Mon–Wed this week (Sunday missed)")
        XCTAssertEqual(stats.activeDays, 3)
        XCTAssertEqual(stats.previousWeekMinutes, 70)
        XCTAssertEqual(stats.goalMinutes, 105)
    }
}

final class EngineConfusionTests: XCTestCase {
    let cal = EngineTest.calendar()
    lazy var now = EngineTest.date(2026, 10, 22, 9, in: cal)
    let course = UUID(), topic = UUID()

    func info(_ answer: String, accepted: [String] = []) -> ItemAnswerInfo {
        ItemAnswerInfo(id: UUID(), courseID: course, topicID: topic, prompt: "Which phase?", expected: answer,
                       accepted: [answer] + accepted)
    }

    func miss(_ item: ItemAnswerInfo, given: String?, daysAgo: Int) -> ReviewSnapshot {
        ReviewSnapshot(itemID: item.id, courseID: course, reviewedAt: cal.adding(days: -daysAgo, to: now), rating: .again,
                       answer: given, stabilityAfter: 1)
    }

    func testSwappedAnswersMakeANamedCandidate() {
        let anaphase = info("Anaphase"), telophase = info("telophase"), other = info("Metaphase")
        let logs = [miss(anaphase, given: "Telophase.", daysAgo: 3), miss(telophase, given: "anaphase", daysAgo: 2),
                    miss(other, given: "I don't know", daysAgo: 1)]
        let found = ConfusionFinder(calendar: cal, now: now).candidates(items: [anaphase, telophase, other], logs: logs)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].name, "Anaphase vs telophase")
        XCTAssertEqual(found[0].reason, .swappedAnswers)
        XCTAssertEqual(Set(found[0].itemIDs), [anaphase.id, telophase.id])
        XCTAssertEqual(found[0].missCount, 2)
        XCTAssertEqual(found[0].mistakes.first { $0.itemID == anaphase.id }?.given, "Telophase.")
        // Stable id for the same items.
        let again = ConfusionFinder(calendar: cal, now: now).candidates(items: [anaphase, telophase, other], logs: logs)
        XCTAssertEqual(again[0].id, found[0].id)
    }

    func testOneSwapIsNotEnough() {
        let a = info("Anaphase"), b = info("Telophase")
        XCTAssertTrue(ConfusionFinder(calendar: cal, now: now).candidates(items: [a, b], logs: [miss(a, given: "telophase", daysAgo: 1)]).isEmpty)
    }

    func testRepeatedMissesAreGroupedByTopic() {
        let a = info("Homologous pairs"), b = info("Sister chromatids"), c = info("Gametes")
        let logs = (1...3).map { miss(a, given: nil, daysAgo: $0) } + (1...4).map { miss(b, given: "", daysAgo: $0) }
            + [miss(c, given: nil, daysAgo: 1), miss(c, given: nil, daysAgo: 20), miss(c, given: nil, daysAgo: 21)]
        let found = ConfusionFinder(calendar: cal, now: now).candidates(items: [a, b, c], logs: logs, topicNames: [topic: "Meiosis"])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].name, "Meiosis")
        XCTAssertEqual(found[0].reason, .repeatedMisses)
        XCTAssertEqual(Set(found[0].itemIDs), [a.id, b.id], "c's old misses are outside the 14 days")
        XCTAssertEqual(found[0].missCount, 7)
    }

    func testItemsInAnOpenConfusionAreLeftOut() {
        let a = info("Anaphase"), b = info("Telophase")
        let logs = [miss(a, given: "telophase", daysAgo: 3), miss(b, given: "anaphase", daysAgo: 2)]
        let open = ConfusionSnapshot(id: UUID(), courseID: course, name: "Anaphase vs telophase", itemIDs: [a.id, b.id])
        XCTAssertTrue(ConfusionFinder(calendar: cal, now: now).candidates(items: [a, b], logs: logs, existing: [open]).isEmpty)
        var dismissed = open
        dismissed.status = .dismissed
        XCTAssertTrue(ConfusionFinder(calendar: cal, now: now).candidates(items: [a, b], logs: logs, existing: [dismissed]).isEmpty)
    }

    func testCorrectAnswersAndOwnAnswersAreNotSwaps() {
        let a = info("Anaphase", accepted: ["anaphase I"]), b = info("Anaphase I")
        // The given answer is also one of a's own answers: not a swap.
        let logs = [miss(a, given: "Anaphase I", daysAgo: 1), miss(a, given: "anaphase i", daysAgo: 2)]
        XCTAssertTrue(ConfusionFinder(calendar: cal, now: now).candidates(items: [a, b], logs: logs).isEmpty)
        XCTAssertEqual(ConfusionFinder.normalize("  Téléphase,  I! "), "telephase i")
        XCTAssertEqual(ConfusionFinder.joinNames(["anaphase", "DNA polymerase", "Telophase"]), "Anaphase, DNA polymerase and telophase")
    }
}
