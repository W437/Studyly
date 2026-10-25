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

    func testExamPassIsOfferedToFreePeopleWithinThreeWeeks() {
        let now = date(2026, 10, 22, 9)
        XCTAssertTrue(ExamPassOffer.isEligible(plan: .free, examDate: date(2026, 11, 12, 9), now: now, calendar: calendar))
        XCTAssertTrue(ExamPassOffer.isEligible(plan: .free, examDate: date(2026, 10, 22, 15), now: now, calendar: calendar),
                      "later today still counts")
        XCTAssertFalse(ExamPassOffer.isEligible(plan: .free, examDate: date(2026, 11, 13, 9), now: now, calendar: calendar),
                       "22 days out is too early")
        XCTAssertFalse(ExamPassOffer.isEligible(plan: .free, examDate: date(2026, 10, 21, 9), now: now, calendar: calendar),
                       "a past exam")
        XCTAssertFalse(ExamPassOffer.isEligible(plan: .free, examDate: nil, now: now, calendar: calendar))
        for paid in [Plan.pro, .squad, .pass] {
            XCTAssertFalse(ExamPassOffer.isEligible(plan: paid, examDate: date(2026, 10, 30, 9), now: now, calendar: calendar))
        }
    }
}
