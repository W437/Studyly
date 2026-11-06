import StoreKit
import XCTest
@testable import Cramless

/// The paywall's numbers and words: computed from the price, honest about the trial, the same everywhere.
@MainActor
final class PaywallCopyTests: XCTestCase {
    private let yearly = PlanPrice.fallback(.yearly)
    private let monthly = PlanPrice.fallback(.monthly)
    private let squad = PlanPrice.fallback(.squad)
    private let pass = PlanPrice.fallback(.examPass)

    func testFallbackPricesMirrorTheStoreKitFile() throws {
        XCTAssertEqual(yearly.display, "$49.99")
        XCTAssertEqual(monthly.display, "$9.99")
        XCTAssertEqual(squad.display, "$99.99")
        XCTAssertEqual(pass.display, "$14.99")
        XCTAssertTrue(yearly.isFallback)
        XCTAssertEqual(yearly.trialDays, 7)
        XCTAssertEqual(squad.trialDays, 7)
        XCTAssertNil(monthly.trialDays)
        XCTAssertNil(pass.trialDays)

        // Every fallback matches Cramless.storekit, so the labelled fallback never shows a price that isn't real.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Cramless.storekit")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var prices: [String: String] = [:]
        var trials: Set<String> = []
        for group in json["subscriptionGroups"] as? [[String: Any]] ?? [] {
            for sub in group["subscriptions"] as? [[String: Any]] ?? [] {
                prices[sub["productID"] as! String] = sub["displayPrice"] as? String
                if let offer = sub["introductoryOffer"] as? [String: Any], offer["paymentMode"] as? String == "free",
                   offer["subscriptionPeriod"] as? String == "P1W" {
                    trials.insert(sub["productID"] as! String)
                }
            }
        }
        for product in json["nonRenewingSubscriptions"] as? [[String: Any]] ?? [] {
            prices[product["productID"] as! String] = product["displayPrice"] as? String
        }
        for option in PlanOption.allCases {
            XCTAssertEqual(prices[option.productID].flatMap { Decimal(string: $0) }, option.fallbackPrice, option.rawValue)
            XCTAssertEqual(trials.contains(option.productID), option.fallbackTrialDays == 7, option.rawValue)
        }
    }

    func testPerWeekAndPerSeatAreComputedFromThePrice() {
        XCTAssertEqual(yearly.perWeek, "$0.96")
        XCTAssertEqual(squad.perSeatPerMonth, "$2.08")
        var euro = yearly
        euro.amount = Decimal(string: "59.99")!
        euro.currencyCode = "EUR"
        euro.locale = Locale(identifier: "de_DE")
        XCTAssertTrue(euro.perWeek.hasPrefix("1,15"), euro.perWeek)
        XCTAssertTrue(euro.perWeek.hasSuffix("€"), euro.perWeek)
    }

    func testPlanCardLines() {
        XCTAssertEqual(PaywallCopy.flag(for: .yearly, trialDays: 7), "7 days free · Best value")
        XCTAssertEqual(PaywallCopy.flag(for: .squad, trialDays: 7), "7 days free · Study together")
        XCTAssertEqual(PaywallCopy.flag(for: .yearly, trialDays: nil), "Best value", "no trial promised once it's used")
        XCTAssertNil(PaywallCopy.flag(for: .monthly, trialDays: nil))
        XCTAssertEqual(PaywallCopy.detail(for: .yearly, price: yearly), "$0.96 a week")
        XCTAssertEqual(PaywallCopy.detail(for: .monthly, price: monthly), "Cancel anytime")
        XCTAssertEqual(PaywallCopy.detail(for: .squad, price: squad), "You + 3 friends · $2.08 each a month")
    }

    func testButtonsAndTerms() {
        XCTAssertEqual(PaywallCopy.cta(for: .yearly, price: yearly, trialDays: 7), "Start my free week")
        XCTAssertEqual(PaywallCopy.cta(for: .squad, price: squad, trialDays: 7), "Start the Squad free week")
        XCTAssertEqual(PaywallCopy.cta(for: .monthly, price: monthly, trialDays: nil), "Subscribe for $9.99/month")
        XCTAssertEqual(PaywallCopy.cta(for: .yearly, price: yearly, trialDays: nil), "Subscribe for $49.99/year")
        XCTAssertEqual(PaywallCopy.cta(for: .examPass, price: pass, trialDays: nil), "Get Exam Pass for $14.99")

        XCTAssertEqual(PaywallCopy.terms(for: .yearly, price: yearly, trialDays: 7),
                       "Free for 7 days, then $49.99 a year. Cancel anytime in two taps. Fair use applies.")
        XCTAssertEqual(PaywallCopy.terms(for: .monthly, price: monthly, trialDays: nil),
                       "Renews at $9.99 a month. Cancel anytime in two taps. Fair use applies.")
        XCTAssertEqual(PaywallCopy.terms(for: .examPass, price: pass, trialDays: nil),
                       "$14.99 for 30 days, one time. Doesn't renew. Fair use applies.")
    }

    func testTimelineIsTodayThenTheReminderThenTheCharge() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 10))!
        let ends = calendar.date(byAdding: .day, value: 7, to: now)!
        let reminder = TrialReminder.fireDate(trialEnds: ends, reminderMinutes: 19 * 60, quietStart: 22 * 60,
                                              quietEnd: 7 * 60, now: now, calendar: calendar)
        let steps = PaywallCopy.timeline(trialDays: 7, price: yearly, now: now, reminder: reminder, calendar: calendar)
        XCTAssertEqual(steps.map(\.title), ["Today", "Day 5", "Day 7"])
        XCTAssertEqual(steps[0].detail, "Everything unlocks. Your plan starts.")
        XCTAssertTrue(steps[1].detail.hasPrefix("We remind you on "))
        XCTAssertTrue(steps[2].detail.contains("$49.99"))
        XCTAssertTrue(steps[2].detail.hasSuffix("unless you cancel before."))
    }

    func testPlanLineNamesThePlan() {
        let now = ISO8601DateFormatter().date(from: "2026-10-22T14:00:00Z")!
        let exam = ISO8601DateFormatter().date(from: "2026-11-14T14:00:00Z")!
        let line = PaywallCopy.planLine(courseName: "Bio 101", minutes: 15, examDate: exam, now: now)
        XCTAssertTrue(line.hasPrefix("Your Bio 101 plan is set: 15 minutes a day until "), line)
        XCTAssertEqual(PaywallCopy.planLine(courseName: nil, minutes: 10, examDate: nil, now: now),
                       "Your plan is set: 10 minutes a day.")
        XCTAssertEqual(PaywallCopy.planLine(courseName: "Chem 110", minutes: 20, examDate: now.addingTimeInterval(-86_400), now: now),
                       "Your Chem 110 plan is set: 20 minutes a day.", "a past exam isn't named")
    }

    func testSublineByContext() {
        XCTAssertEqual(PaywallCopy.subline(for: .onboarding(planLine: "Your Bio 101 plan is set.")), "Your Bio 101 plan is set.")
        XCTAssertEqual(PaywallCopy.subline(for: .feature(PaidFeature.unlimitedTutor.paywallLine)),
                       "Unlimited questions for Cap are part of Pro.")
        XCTAssertFalse(PaywallCopy.subline(for: .settings).isEmpty)
    }

    // MARK: What Pro adds, and what is always free

    private func words(_ rows: [PaywallCopy.Row]) -> [String] { rows.map { String(localized: $0.text) } }

    func testProIsTheAIWorkAndNothingTheFreePlanHas() {
        XCTAssertEqual(words(PaywallCopy.benefits(isMinor: false)), [
            "AI scans, PDFs and lecture notes, no weekly limit",
            "Every answer graded by Cloud AI",
            "Cap's answers and drafts, no daily limit",
            "Web research from trusted sites",
        ])
        let everything = (words(PaywallCopy.benefits(isMinor: false)) + [PaywallCopy.subline(for: .settings)])
            .joined(separator: " ").lowercased()
        for promise in ["practice test", "readiness", "exam plan", "unlimited"] {
            XCTAssertFalse(everything.contains(promise), "Pro doesn't sell \(promise)")
        }
        XCTAssertEqual(Set(PaywallCopy.benefits(isMinor: false).map(\.id)).count, 4, "each row has its own symbol")
    }

    func testAnAccountUnder18IsNeverSoldWebResearch() {
        let rows = words(PaywallCopy.benefits(isMinor: true))
        XCTAssertEqual(rows.count, 3)
        XCTAssertFalse(rows.contains { $0.contains("research") })
    }

    func testTheAlwaysFreeCardSaysWhatNobodyPaysFor() {
        XCTAssertEqual(words(PaywallCopy.alwaysFree), [
            "Reviews and flashcards, as many as you like",
            "A plan and readiness for every exam",
            "Mock exams",
            "Your streak, quests and the sky",
            "Quizlet and Anki imports",
            "Each week 3 AI scans and notes for 1 lecture; each day 20 graded answers and 10 questions for Cap",
        ])
        // The allowance row says the relay's own numbers.
        let allowance = words(PaywallCopy.alwaysFree).last ?? ""
        XCTAssertTrue(allowance.contains("\(AIFreeLimits.limit(.scans)) AI scans"))
        XCTAssertTrue(allowance.contains("notes for \(AIFreeLimits.limit(.lectures)) lecture"))
        XCTAssertTrue(allowance.contains("\(AIFreeLimits.limit(.grades)) graded answers"))
        XCTAssertTrue(allowance.contains("\(AIFreeLimits.limit(.tutor)) questions for Cap"))
        XCTAssertEqual(AIFreeLimits.period(.scans), .week)
        XCTAssertEqual(AIFreeLimits.period(.lectures), .week)
        XCTAssertEqual(AIFreeLimits.period(.grades), .day)
        XCTAssertEqual(AIFreeLimits.period(.tutor), .day)
    }

    /// The paywall reads top to bottom: Pro's rows, then "Always free", then the prices. Read from its source, since the order is the
    /// promise: no price shows before the person has seen what stays free.
    func testTheFreeCardSitsBetweenProsRowsAndThePlans() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Cramless/Features/Paywall/PaywallView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let benefits = try XCTUnwrap(source.range(of: "PaywallCopy.benefits(")).lowerBound
        let free = try XCTUnwrap(source.range(of: "AlwaysFreeCard()")).lowerBound
        let plans = try XCTUnwrap(source.range(of: "PlanOption.paywallOptions")).lowerBound
        XCTAssertLessThan(benefits, free)
        XCTAssertLessThan(free, plans)
        XCTAssertTrue(source.contains(".id(\"free\")"), "CRAMLESS_PAYWALL_SCROLL=free scrolls to it")
        XCTAssertFalse(source.contains("freePlanLine"), "the old footer line is gone")
        XCTAssertTrue(source.contains("HelpLink("), "the footer has a way to reach a real person")
    }

    func testFairUseStaysInTheTerms() {
        for option in PlanOption.allCases {
            XCTAssertTrue(PaywallCopy.terms(for: option, price: .fallback(option), trialDays: nil).hasSuffix("Fair use applies."))
        }
    }

    func testFailureMessagesAreClearAndNeverBlame() {
        for failure: PurchaseStore.PurchaseFailure in [.storeUnavailable, .notAllowed, .network, .ineligibleForOffer,
                                                      .unverified, .unknown] {
            XCTAssertFalse(failure.message.isEmpty)
            XCTAssertFalse(failure.message.lowercased().contains("you failed"))
            XCTAssertTrue(failure.message.hasSuffix("."))
        }
        XCTAssertEqual(PurchaseStore.outcome(for: StoreKitError.userCancelled), .cancelled)
        XCTAssertEqual(PurchaseStore.outcome(for: StoreKitError.networkError(URLError(.notConnectedToInternet))),
                       .failed(.network))
        XCTAssertEqual(PurchaseStore.outcome(for: Product.PurchaseError.purchaseNotAllowed), .failed(.notAllowed))
        XCTAssertEqual(PurchaseStore.outcome(for: Product.PurchaseError.ineligibleForOffer), .failed(.ineligibleForOffer))
        XCTAssertEqual(PurchaseStore.outcome(for: URLError(.timedOut)), .failed(.unknown))
    }
}
