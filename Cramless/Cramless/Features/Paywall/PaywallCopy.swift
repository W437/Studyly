import Foundation

/// The paywall's words, as pure functions of the option, its price and the trial, so they stay honest and are
/// tested in one place.
enum PaywallCopy {
    static let headline = "Sleep the night before. You'll know where you stand."

    /// One row of a list on the paywall: a symbol and its words.
    struct Row: Identifiable {
        var symbol: String
        var text: LocalizedStringResource
        var id: String { symbol }
    }

    /// What Pro adds: the AI work, and nothing the free plan already has (plans, readiness and reviews are free). Web research is
    /// left out for an account under 18, which never has it.
    static func benefits(isMinor: Bool) -> [Row] {
        var rows = [
            Row(symbol: "doc.viewfinder", text: "AI scans, PDFs and lecture notes, no weekly limit"),
            Row(symbol: "checkmark.seal", text: "Answers in your own words graded by Cloud AI"),
            Row(symbol: "bubble.left.and.text.bubble.right", text: "Cap's answers and drafts, no daily limit"),
        ]
        if !isMinor { rows.append(Row(symbol: "globe", text: "Web research from trusted sites")) }
        return rows
    }

    /// What every account keeps without paying ("Always free", `AlwaysFreeCard`: what an account under 13 sees instead of a price). A
    /// feature joins here when it ships free. The last row is the free AI allowance, in the relay's numbers (`AIFreeLimits`; a test keeps
    /// them in step). The paywall says it in one line (`staysFree`).
    static let alwaysFree: [Row] = [
        Row(symbol: "rectangle.stack", text: "Reviews and flashcards, as many as you like"),
        Row(symbol: "target", text: "A plan and readiness for every exam"),
        Row(symbol: "timer", text: "Mock exams"),
        Row(symbol: "flame", text: "Your streak, quests and the sky"),
        Row(symbol: "square.and.arrow.down", text: "Quizlet and Anki imports"),
        Row(symbol: "sparkles", text: "Each week 3 AI scans and notes for 1 lecture; each day 20 graded answers and 10 questions for Cap"),
    ]

    /// `alwaysFree` for this account: an account under 13 has no AI allowance to keep, since Cloud AI never runs for it.
    static func alwaysFree(canBuyPro: Bool) -> [Row] {
        canBuyPro ? alwaysFree : alwaysFree.filter { $0.symbol != "sparkles" }
    }

    /// Pro's rows are all Cloud AI's work: what's true when that won't happen as things stand. Nil when Pro has nothing in its way.
    static func proCaveat(canBuyPro: Bool, cloudAvailable: Bool, cloudAllowed: Bool) -> LocalizedStringResource? {
        if !canBuyPro { return "Cloud AI isn't available for accounts under 13, so Pro has nothing to do here." }
        return cloudAvailable && !cloudAllowed ? "Pro works once you turn on Cloud AI in Settings." : nil
    }

    /// An account under 13, wherever Pro would be offered (`NoPurchaseView`).
    static let noPurchaseTitle: LocalizedStringResource = "Capling is free for you"
    static let noPurchaseDetail: LocalizedStringResource = "Pro is Cloud AI's work, and Cloud AI isn't available for accounts under 13. So there's nothing here to buy."

    /// The one line under Pro's rows: what nobody pays for, said once (the full list is `alwaysFree`, for an account under 13).
    static let staysFree: LocalizedStringResource = "Reviews, plans, readiness and mock exams stay free."

    /// The line under the headline: what Pro adds, or, when a gate opened the paywall, that gate's own line.
    static func subline(for context: PaywallContext) -> String {
        switch context {
        case .feature(let line): line
        case .onboarding, .settings: "Pro lifts the AI limits."
        }
    }

    /// The line under a plan's name: "7 days free" while the free week is on offer, else nothing.
    static func detail(for option: PlanOption, trialDays: Int?) -> String? {
        guard option.isAutoRenewing, let trialDays else { return nil }
        return "\(trialDays) days free"
    }

    /// The button.
    static func cta(for option: PlanOption, price: PlanPrice, trialDays: Int?) -> String {
        switch option {
        case .yearly:
            guard let trialDays else { return "Subscribe for \(price.display)/year" }
            return trialDays == 7 ? "Start my free week" : "Start my \(trialDays)-day free trial"
        case .squad:
            guard let trialDays else { return "Get Squad" }
            return "Try \(trialDays) days free"
        case .monthly:
            return "Subscribe for \(price.display)/month"
        case .examPass:
            return "Get Exam Pass for \(price.display)"
        }
    }

    /// The terms beside the button: what it costs, when, the reminder before the first charge, and how to stop it.
    static func terms(for option: PlanOption, price: PlanPrice, trialDays: Int?) -> String {
        let billing: String
        switch option {
        case .yearly, .squad:
            if let trialDays {
                billing = "Free for \(trialDays) days, then \(price.display) a year. "
                    + "We'll remind you \(StoreCatalog.trialReminderLeadDays) days before the first charge. Cancel anytime in two taps."
            } else {
                billing = "Renews at \(price.display) a year. Cancel anytime in two taps."
            }
        case .monthly:
            billing = "Renews at \(price.display) a month. Cancel anytime in two taps."
        case .examPass:
            billing = "\(price.display) for \(StoreCatalog.examPassDays) days, one time. Doesn't renew."
        }
        return "\(billing) \(fairUse)"
    }

    /// The paywall's way to Exam Pass, shown only while it is offered (`ExamPassOffer`): "Just one exam? Exam Pass, $14.99".
    static func examPassLink(price: PlanPrice) -> String {
        "Just one exam? Exam Pass, \(price.display)"
    }

    /// "Unlimited" on the benefit rows means no count of scans, answers or lectures, not no ceiling: a day with a lot of Cloud AI (a cram night
    /// of dozens of questions) pauses it until midnight (the relay's cost caps), so the fine print says so.
    static let fairUse = "Fair use applies."
}
