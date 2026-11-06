import XCTest
@testable import Cramless

/// The trial reminder the paywall promises, and when the Exam Pass is offered.
final class StoreReminderAndOfferTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // Trial started Thu Oct 22, 2026 at 10:00; it ends Thu Oct 29 at 10:00.
    private lazy var start = date(2026, 10, 22, 10)
    private lazy var ends = date(2026, 10, 29, 10)

    func testReminderComesTwoDaysBeforeAtTheReminderTime() {
        let fire = TrialReminder.fireDate(trialEnds: ends, reminderMinutes: 19 * 60 + 30, quietStart: 22 * 60,
                                          quietEnd: 7 * 60, now: start, calendar: calendar)
        XCTAssertEqual(fire, date(2026, 10, 27, 19, 30), "Day 5: Tuesday evening")
        XCTAssertEqual(calendar.dayDistance(from: start, to: fire!), 5)
    }

    func testNoReminderTimeMeansSevenPM() {
        let fire = TrialReminder.fireDate(trialEnds: ends, reminderMinutes: nil, quietStart: 22 * 60, quietEnd: 7 * 60,
                                          now: start, calendar: calendar)
        XCTAssertEqual(fire, date(2026, 10, 27, 19))
    }

    func testAReminderTimeInQuietHoursMovesToSevenPM() {
        let fire = TrialReminder.fireDate(trialEnds: ends, reminderMinutes: 23 * 60, quietStart: 22 * 60,
                                          quietEnd: 7 * 60, now: start, calendar: calendar)
        XCTAssertEqual(fire, date(2026, 10, 27, 19))
    }

    func testNoReminderOnceItsMomentHasPassed() {
        let late = date(2026, 10, 27, 20)
        XCTAssertNil(TrialReminder.fireDate(trialEnds: ends, reminderMinutes: 19 * 60, quietStart: 22 * 60,
                                            quietEnd: 7 * 60, now: late, calendar: calendar))
    }

    func testQuietHoursWrapPastMidnight() {
        XCTAssertTrue(TrialReminder.isQuiet(23 * 60, start: 22 * 60, end: 7 * 60))
        XCTAssertTrue(TrialReminder.isQuiet(3 * 60, start: 22 * 60, end: 7 * 60))
        XCTAssertFalse(TrialReminder.isQuiet(19 * 60, start: 22 * 60, end: 7 * 60))
        XCTAssertTrue(TrialReminder.isQuiet(13 * 60, start: 12 * 60, end: 14 * 60))
        XCTAssertFalse(TrialReminder.isQuiet(13 * 60, start: 9 * 60, end: 9 * 60), "an empty window is never quiet")
    }

    func testReminderCopyNamesTheDayAndThePlan() {
        XCTAssertEqual(TrialReminder.body(trialEnds: date(2026, 10, 30, 10), plan: .pro, calendar: calendar),
                       "Your free week ends Friday. Cancel in two taps, or do nothing to keep Pro.")
        XCTAssertEqual(TrialReminder.body(trialEnds: date(2026, 10, 30, 10), plan: .squad, calendar: calendar),
                       "Your free week ends Friday. Cancel in two taps, or do nothing to keep Squad.")
    }

    func testReminderIdentifiersCarryTheTrialPrefix() {
        XCTAssertEqual(TrialReminder.identifier(originalTransactionID: 2000000123), "trial.2000000123")
        XCTAssertTrue(TrialReminder.identifier(originalTransactionID: 1).hasPrefix(TrialReminder.identifierPrefix))
    }

    // MARK: Exam Pass offer

    private func offered(_ exams: [Date], plan: Plan = .free, now: Date) -> Bool {
        ExamPassOffer.isEligible(plan: plan, examDates: exams, now: now, calendar: calendar)
    }

    func testExamPassIsOfferedOnlyEightToTwentyOneDaysBeforeTheNextExam() {
        let now = date(2026, 10, 22, 9)
        XCTAssertTrue(offered([date(2026, 11, 12, 9)], now: now), "21 days out")
        XCTAssertTrue(offered([date(2026, 10, 30, 9)], now: now), "8 days out")
        XCTAssertFalse(offered([date(2026, 11, 13, 9)], now: now), "22 days out is too early")
        XCTAssertFalse(offered([date(2026, 10, 29, 9)], now: now), "7 days out is exam week")
        XCTAssertFalse(offered([date(2026, 10, 25, 9)], now: now), "3 days out")
        XCTAssertFalse(offered([date(2026, 10, 23, 9)], now: now), "the eve")
        XCTAssertFalse(offered([date(2026, 10, 22, 15)], now: now), "the day")
        XCTAssertFalse(offered([date(2026, 10, 21, 9)], now: now), "a past exam")
        XCTAssertFalse(offered([], now: now))
        for paid in [Plan.pro, .squad, .pass] {
            XCTAssertFalse(offered([date(2026, 11, 5, 9)], plan: paid, now: now))
        }
    }

    func testAnotherExamInExamWeekKeepsTheOfferQuiet() {
        let now = date(2026, 10, 22, 9)
        XCTAssertFalse(offered([date(2026, 11, 6, 9), date(2026, 10, 25, 9)], now: now),
                       "an exam in 15 days with another in 3: the soonest decides")
        XCTAssertTrue(offered([date(2026, 11, 6, 9), date(2026, 10, 20, 9)], now: now), "a past exam doesn't count")
        XCTAssertTrue(offered([date(2026, 11, 6, 9), date(2026, 12, 20, 9)], now: now), "a far exam doesn't either")
    }
}
