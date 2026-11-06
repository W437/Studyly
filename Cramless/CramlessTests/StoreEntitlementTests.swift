import XCTest
@testable import Cramless

/// The plan as a pure function of transaction snapshots: what counts, what doesn't, and who wins.
final class StoreEntitlementTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    private let now = ISO8601DateFormatter().date(from: "2026-10-22T14:00:00Z")!

    private func days(_ n: Int, from date: Date? = nil) -> Date {
        calendar.date(byAdding: .day, value: n, to: date ?? now)!
    }

    private func tx(_ option: PlanOption, id: UInt64 = 1, purchased: Date? = nil, expires: Date? = nil,
                    revoked: Date? = nil, upgraded: Bool = false, trial: Bool = false) -> TransactionSnapshot {
        TransactionSnapshot(id: id, originalID: id, productID: option.productID, purchaseDate: purchased ?? days(-1),
                            expirationDate: expires, revocationDate: revoked, isUpgraded: upgraded, isFreeTrial: trial)
    }

    private func resolve(_ txs: [TransactionSnapshot]) -> Entitlement {
        EntitlementResolver.resolve(txs, now: now, calendar: calendar)
    }

    func testNothingIsFree() {
        XCTAssertEqual(resolve([]), .free)
    }

    func testActiveYearlyIsPro() {
        let e = resolve([tx(.yearly, expires: days(300))])
        XCTAssertEqual(e.plan, .pro)
        XCTAssertEqual(e.option, .yearly)
        XCTAssertEqual(e.expiresAt, days(300))
    }

    func testMonthlyIsPro() {
        XCTAssertEqual(resolve([tx(.monthly, expires: days(20))]).plan, .pro)
    }

    func testExpiredSubscriptionIsFree() {
        XCTAssertEqual(resolve([tx(.yearly, expires: days(-1))]).plan, .free)
        XCTAssertEqual(resolve([tx(.yearly, expires: now)]).plan, .free, "the expiry moment itself is over")
    }

    func testRevokedAndUpgradedDontCount() {
        XCTAssertEqual(resolve([tx(.yearly, expires: days(300), revoked: days(-1))]).plan, .free)
        XCTAssertEqual(resolve([tx(.yearly, expires: days(300), upgraded: true)]).plan, .free)
    }

    func testUnknownProductsAreIgnored() {
        let stray = TransactionSnapshot(id: 9, originalID: 9, productID: "com.example.other", purchaseDate: days(-1),
                                        expirationDate: days(30))
        XCTAssertEqual(resolve([stray]).plan, .free)
    }

    func testTrialIsCarried() {
        let e = resolve([tx(.yearly, id: 42, purchased: now, expires: days(7), trial: true)])
        XCTAssertEqual(e.plan, .pro)
        XCTAssertTrue(e.isFreeTrial)
        XCTAssertEqual(e.originalTransactionID, 42)
    }

    func testSquadBeatsProBeatsPass() {
        let all = [tx(.examPass, id: 1, purchased: days(-2)), tx(.yearly, id: 2, expires: days(300)),
                   tx(.squad, id: 3, expires: days(200))]
        XCTAssertEqual(resolve(all).plan, .squad)
        XCTAssertEqual(resolve(Array(all.prefix(2))).plan, .pro)
        XCTAssertEqual(resolve([all[0]]).plan, .pass)
    }

    func testBetweenEqualsTheLaterExpiryWins() {
        let e = resolve([tx(.monthly, id: 1, expires: days(10)), tx(.yearly, id: 2, expires: days(200))])
        XCTAssertEqual(e.option, .yearly)
    }

    // MARK: Exam Pass (non-renewing)

    func testExamPassLastsThirtyDaysFromPurchase() {
        let bought = days(-10)
        let e = resolve([tx(.examPass, purchased: bought)])
        XCTAssertEqual(e.plan, .pass)
        XCTAssertEqual(e.expiresAt, days(30, from: bought))
    }

    func testExamPassRunsOut() {
        XCTAssertEqual(resolve([tx(.examPass, purchased: days(-30))]).plan, .free, "day 30 is the end")
        XCTAssertEqual(resolve([tx(.examPass, purchased: days(-45))]).plan, .free)
    }

    func testASecondPassBoughtDuringTheFirstExtendsIt() {
        let first = days(-20), second = days(-5)
        let e = resolve([tx(.examPass, id: 1, purchased: first), tx(.examPass, id: 2, purchased: second)])
        XCTAssertEqual(e.plan, .pass)
        XCTAssertEqual(e.expiresAt, days(60, from: first), "the second pass starts when the first ends")
    }

    func testAPassBoughtAfterAGapStartsFresh() {
        let old = days(-90), fresh = days(-3)
        let e = resolve([tx(.examPass, id: 1, purchased: old), tx(.examPass, id: 2, purchased: fresh)])
        XCTAssertEqual(e.expiresAt, days(30, from: fresh))
    }

    func testThirtyDaysAreCalendarDaysAcrossDaylightSaving() {
        // Nov 1, 2026 is the end of daylight saving in New York: a 30-day pass still ends at the same wall time.
        let bought = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 21))!
        let window = EntitlementResolver.examPassWindow([tx(.examPass, purchased: bought)], calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: window!.end), 21)
        XCTAssertEqual(calendar.dateComponents([.month, .day], from: window!.end), DateComponents(month: 11, day: 19))
    }

    // MARK: Effective plan

    func testHarnessOverrideWins() {
        let e = EntitlementResolver.effective(store: .free, granted: nil, override: .squad, now: now)
        XCTAssertEqual(e.plan, .squad)
        XCTAssertTrue(e.allows(.squadSeats))
    }

    func testAServerGrantLiftsAFreePersonUntilItRunsOut() {
        let grant = Entitlement(plan: .squad, option: nil, expiresAt: days(30), isFreeTrial: false, originalTransactionID: nil)
        let e = EntitlementResolver.effective(store: .free, granted: grant, override: nil, now: now)
        XCTAssertEqual(e.plan, .squad)
        XCTAssertFalse(e.allows(.squadSeats), "a friend on someone's Squad can't invite more")
        XCTAssertTrue(e.allows(.unlimitedCapture))
        let lapsed = Entitlement(plan: .squad, option: nil, expiresAt: days(-1), isFreeTrial: false, originalTransactionID: nil)
        XCTAssertEqual(EntitlementResolver.effective(store: .free, granted: lapsed, override: nil, now: now).plan, .free)
    }

    func testAGrantNeverLowersWhatThePersonBought() {
        let bought = resolve([tx(.squad, expires: days(200))])
        let grant = Entitlement(plan: .pro, option: nil, expiresAt: nil, isFreeTrial: false, originalTransactionID: nil)
        XCTAssertEqual(EntitlementResolver.effective(store: bought, granted: grant, override: nil, now: now), bought)
    }

    // MARK: Gates

    func testGates() {
        XCTAssertFalse(Entitlement.free.allows(.unlimitedCapture))
        XCTAssertFalse(Entitlement.free.allows(.squadSeats))
        let pro = resolve([tx(.yearly, expires: days(300))])
        XCTAssertTrue(PaidFeature.allCases.filter { $0 != .squadSeats }.allSatisfy(pro.allows))
        XCTAssertFalse(pro.allows(.squadSeats))
        let pass = resolve([tx(.examPass, purchased: days(-1))])
        XCTAssertTrue(pass.allows(.unlimitedCapture))
        XCTAssertTrue(pass.allows(.lectureNotes))
        XCTAssertFalse(pass.allows(.squadSeats))
        // Pro is the AI work: plans, readiness, practice and projections are free for everyone, so nothing gates them.
        XCTAssertEqual(Set(PaidFeature.allCases.map(\.rawValue)),
                       ["unlimitedCapture", "unlimitedGrading", "unlimitedTutor", "lectureNotes", "squadSeats"])
        XCTAssertTrue(resolve([tx(.squad, expires: days(300))]).allows(.squadSeats))
    }

    func testProductIDsRoundTrip() {
        for option in PlanOption.allCases {
            XCTAssertEqual(PlanOption(productID: option.productID), option)
        }
        XCTAssertEqual(PlanOption.paywallOptions, [.yearly, .monthly, .squad])
    }
}
