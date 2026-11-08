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

    func testPerSeatIsComputedFromThePrice() {
        XCTAssertEqual(squad.perSeatPerMonth, "$2.08")
        var euro = squad
        euro.amount = Decimal(string: "119.99")!
        euro.currencyCode = "EUR"
        euro.locale = Locale(identifier: "de_DE")
        XCTAssertTrue(euro.perSeatPerMonth.hasPrefix("2,50"), euro.perSeatPerMonth)
        XCTAssertTrue(euro.perSeatPerMonth.hasSuffix("€"), euro.perSeatPerMonth)
    }

    /// Two plans, and only the free week under a name: no weekly price, no flag.
    func testPlanCardLines() {
        XCTAssertEqual(PlanOption.paywallOptions, [.yearly, .monthly], "Squad has its own page; Exam Pass is a link")
        XCTAssertEqual(PaywallCopy.detail(for: .yearly, trialDays: 7), "7 days free")
        XCTAssertNil(PaywallCopy.detail(for: .yearly, trialDays: nil), "no trial promised once it's used")
        XCTAssertNil(PaywallCopy.detail(for: .monthly, trialDays: nil))
        XCTAssertNil(PaywallCopy.detail(for: .examPass, trialDays: 7), "a pass has no trial")
        XCTAssertEqual(PaywallCopy.examPassLink(price: pass), "Just one exam? Exam Pass, $14.99")
    }

    func testButtonsAndTerms() {
        XCTAssertEqual(PaywallCopy.cta(for: .yearly, price: yearly, trialDays: 7), "Start my free week")
        XCTAssertEqual(PaywallCopy.cta(for: .squad, price: squad, trialDays: 7), "Try 7 days free")
        XCTAssertEqual(PaywallCopy.cta(for: .squad, price: squad, trialDays: nil), "Get Squad")
        XCTAssertEqual(PaywallCopy.cta(for: .monthly, price: monthly, trialDays: nil), "Subscribe for $9.99/month")
        XCTAssertEqual(PaywallCopy.cta(for: .yearly, price: yearly, trialDays: nil), "Subscribe for $49.99/year")
        XCTAssertEqual(PaywallCopy.cta(for: .examPass, price: pass, trialDays: nil), "Get Exam Pass for $14.99")

        XCTAssertEqual(PaywallCopy.terms(for: .yearly, price: yearly, trialDays: 7),
                       "Free for 7 days, then $49.99 a year. We'll remind you 2 days before the first charge. Cancel anytime in two taps. Fair use applies.")
        XCTAssertEqual(PaywallCopy.terms(for: .squad, price: squad, trialDays: 7),
                       "Free for 7 days, then $99.99 a year. We'll remind you 2 days before the first charge. Cancel anytime in two taps. Fair use applies.")
        XCTAssertEqual(PaywallCopy.terms(for: .yearly, price: yearly, trialDays: nil),
                       "Renews at $49.99 a year. Cancel anytime in two taps. Fair use applies.")
        XCTAssertEqual(PaywallCopy.terms(for: .monthly, price: monthly, trialDays: nil),
                       "Renews at $9.99 a month. Cancel anytime in two taps. Fair use applies.")
        XCTAssertEqual(PaywallCopy.terms(for: .examPass, price: pass, trialDays: nil),
                       "$14.99 for 30 days, one time. Doesn't renew. Fair use applies.")
    }

    /// The reminder the terms promise is the one `TrialReminder` schedules: the same number of days before the trial ends.
    func testTheTermsPromiseTheReminderTheStoreSchedules() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 10))!
        let ends = calendar.date(byAdding: .day, value: 7, to: now)!
        let reminder = try XCTUnwrap(TrialReminder.fireDate(trialEnds: ends, reminderMinutes: 19 * 60, quietStart: 22 * 60,
                                                            quietEnd: 7 * 60, now: now, calendar: calendar))
        XCTAssertEqual(calendar.dayDistance(from: reminder, to: ends), StoreCatalog.trialReminderLeadDays)
        XCTAssertTrue(PaywallCopy.terms(for: .yearly, price: yearly, trialDays: 7)
            .contains("remind you \(StoreCatalog.trialReminderLeadDays) days before the first charge"))
    }

    /// Onboarding and Settings say what Pro adds (the plan was said on the screen before); a gate keeps its own line.
    func testSublineByContext() {
        XCTAssertEqual(PaywallCopy.subline(for: .onboarding), "Pro lifts the AI limits.")
        XCTAssertEqual(PaywallCopy.subline(for: .settings), "Pro lifts the AI limits.")
        XCTAssertEqual(PaywallCopy.subline(for: .feature("Web research is part of Capling Pro.")), "Web research is part of Capling Pro.")
    }

    // MARK: What Pro adds, and what is always free

    private func words(_ rows: [PaywallCopy.Row]) -> [String] { rows.map { String(localized: $0.text) } }

    func testProIsTheAIWorkAndNothingTheFreePlanHas() {
        XCTAssertEqual(words(PaywallCopy.benefits(isMinor: false)), [
            "AI scans, PDFs and lecture notes, no weekly limit",
            "Answers in your own words graded by Cloud AI",
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

    /// Multiple choice and fill-ins never go to Cloud AI, so "every answer" wouldn't be true.
    func testTheGradingRowSaysWhichAnswersCloudAIGrades() {
        let rows = words(PaywallCopy.benefits(isMinor: false))
        XCTAssertTrue(rows.contains("Answers in your own words graded by Cloud AI"), "\(rows)")
        XCTAssertFalse(rows.contains { $0.localizedCaseInsensitiveContains("every answer") })
    }

    /// Pro is Cloud AI's work: until it's on, Pro does nothing, and the paywall and the purchased screen say so.
    func testProSaysWhatItNeeds() throws {
        func caveat(canBuyPro: Bool = true, available: Bool = true, allowed: Bool) -> String? {
            PaywallCopy.proCaveat(canBuyPro: canBuyPro, cloudAvailable: available, cloudAllowed: allowed).map { String(localized: $0) }
        }
        XCTAssertEqual(caveat(allowed: false), "Pro works once you turn on Cloud AI in Settings.")
        XCTAssertNil(caveat(allowed: true), "nothing in its way")
        XCTAssertNil(caveat(available: false, allowed: false), "a build with no relay has no switch to turn on")
        XCTAssertEqual(caveat(canBuyPro: false, allowed: true), "Cloud AI isn't available for accounts under 13, so Pro has nothing to do here.")
    }

    /// An account under 13 keeps everything that's free and has no AI allowance to keep.
    func testAnAccountUnder13KeepsTheFreeRowsWithoutTheAllowance() {
        let free = words(PaywallCopy.alwaysFree(canBuyPro: false))
        XCTAssertEqual(free.count, PaywallCopy.alwaysFree.count - 1)
        XCTAssertFalse(free.contains { $0.contains("AI") })
        XCTAssertEqual(words(PaywallCopy.alwaysFree(canBuyPro: true)), words(PaywallCopy.alwaysFree))
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

    /// What stays free is one line on the paywall, and it names mock exams, readiness and plans: Pro never sells them.
    func testTheStaysFreeLineNamesWhatNobodyPaysFor() {
        let line = String(localized: PaywallCopy.staysFree)
        XCTAssertEqual(line, "Reviews, plans, readiness and mock exams stay free.")
        for free in ["Reviews", "plans", "readiness", "mock exams"] { XCTAssertTrue(line.contains(free), free) }
    }

    /// The paywall reads top to bottom: Pro's rows, the line on what stays free, then the two plans and the Exam Pass link. Read from its
    /// source, since the order is the promise: no price shows before the person has read what stays free. "Continue free" never opens a
    /// second offer.
    func testThePaywallSaysWhatStaysFreeBeforeThePlans() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Cramless/Features/Paywall/PaywallView.swift"), encoding: .utf8)
        let benefits = try XCTUnwrap(source.range(of: "PaywallCopy.benefits(")).lowerBound
        let free = try XCTUnwrap(source.range(of: "StaysFreeLine()")).lowerBound
        let plans = try XCTUnwrap(source.range(of: "PlanOption.paywallOptions")).lowerBound
        let pass = try XCTUnwrap(source.range(of: "ExamPassLink(")).lowerBound
        XCTAssertLessThan(benefits, free)
        XCTAssertLessThan(free, plans)
        XCTAssertLessThan(plans, pass)
        XCTAssertFalse(source.contains("AlwaysFreeCard()"), "one line, not the six-row card")
        XCTAssertFalse(source.contains("TrialTimeline"), "the reminder is in the terms")
        XCTAssertTrue(source.contains("HelpLink("), "the footer has a way to reach a real person")
        let decline = try XCTUnwrap(source.range(of: "private func decline()"))
        let body = source[decline.upperBound...].prefix(260)
        XCTAssertFalse(body.contains(".examPass"), "\"Continue free\" just closes")
        let onboarding = try String(contentsOf: root.appendingPathComponent("Cramless/Features/Onboarding/OnboardingFlow.swift"), encoding: .utf8)
        XCTAssertFalse(onboarding.contains("ExamPassView"), "onboarding's \"Continue free\" goes straight to Today")
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
