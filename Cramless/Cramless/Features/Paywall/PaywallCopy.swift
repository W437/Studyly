import Foundation

/// The paywall's words, as pure functions of the option, its price and the trial, so they stay honest and are
/// tested in one place.
enum PaywallCopy {
    static let headline = "Sleep the night before. You'll be ready."

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

    /// What every account keeps without paying, shown above the prices ("Always free"). A feature joins here when it ships free. The
    /// last row is the free AI allowance, in the relay's numbers (`AIFreeLimits`; a test keeps them in step).
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

    /// The line under the headline, by context.
    static func subline(for context: PaywallContext) -> String {
        switch context {
        case .onboarding(let planLine): planLine
        case .feature(let line): line
        case .settings: "Pro lifts the AI limits, for every class and every exam."
        }
    }

    /// "Your Bio 101 plan is set: 15 minutes a day until Nov 14." The plan step can say it better; this is what
    /// the onboarding paywall says when it hasn't.
    static func planLine(courseName: String?, minutes: Int, examDate: Date?, now: Date) -> String {
        let subject = courseName.map { "Your \($0) plan is set" } ?? "Your plan is set"
        guard let examDate, examDate > now else { return "\(subject): \(minutes) minutes a day." }
        let date = examDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(subject): \(minutes) minutes a day until \(date)."
    }

    /// The small flag on a plan card: "7 days free · Best value".
    static func flag(for option: PlanOption, trialDays: Int?) -> String? {
        let tag: String? = switch option {
        case .yearly: "Best value"
        case .squad: "Study together"
        case .monthly, .examPass: nil
        }
        guard let tag else { return nil }
        guard let trialDays else { return tag }
        return "\(trialDays) days free · \(tag)"
    }

    /// The line under a plan's name: "$0.96 a week", "Cancel anytime", "You + 3 friends · $2.08 each a month".
    static func detail(for option: PlanOption, price: PlanPrice) -> String {
        switch option {
        case .yearly: "\(price.perWeek) a week"
        case .monthly: "Cancel anytime"
        case .squad: "You + \(StoreCatalog.squadSeats - 1) friends · \(price.perSeatPerMonth) each a month"
        case .examPass: "30 days, one time"
        }
    }

    /// The button.
    static func cta(for option: PlanOption, price: PlanPrice, trialDays: Int?) -> String {
        switch option {
        case .yearly:
            guard let trialDays else { return "Subscribe for \(price.display)/year" }
            return trialDays == 7 ? "Start my free week" : "Start my \(trialDays)-day free trial"
        case .squad:
            guard let trialDays else { return "Subscribe for \(price.display)/year" }
            return trialDays == 7 ? "Start the Squad free week" : "Start the Squad \(trialDays)-day trial"
        case .monthly:
            return "Subscribe for \(price.display)/month"
        case .examPass:
            return "Get Exam Pass for \(price.display)"
        }
    }

    /// The terms beside the button: what it costs, when, and how to stop it. (The trial timeline says when the
    /// reminder comes.)
    static func terms(for option: PlanOption, price: PlanPrice, trialDays: Int?) -> String {
        let billing: String
        switch option {
        case .yearly, .squad:
            if let trialDays {
                billing = "Free for \(trialDays) days, then \(price.display) a year. Cancel anytime in two taps."
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

    /// "Unlimited" on the benefit rows means no count of scans, answers or lectures, not no ceiling: a day with a lot of Cloud AI (a cram night
    /// of dozens of questions) pauses it until midnight (the relay's cost caps), so the fine print says so.
    static let fairUse = "Fair use applies."

    /// The trial timeline: Today, the reminder, the first charge. Day numbers count from today.
    struct TimelineStep: Equatable {
        var symbol: String
        var title: String
        var detail: String
    }

    static func timeline(trialDays: Int, price: PlanPrice, now: Date, reminder: Date?, calendar: Calendar)
        -> [TimelineStep] {
        let end = calendar.date(byAdding: .day, value: trialDays, to: now) ?? now
        let remind = reminder ?? calendar.date(byAdding: .day, value: -StoreCatalog.trialReminderLeadDays, to: end) ?? end
        let short = Date.FormatStyle.dateTime.month(.abbreviated).day()
        let remindDay = calendar.dayDistance(from: now, to: remind)
        let endDay = calendar.dayDistance(from: now, to: end)
        return [
            TimelineStep(symbol: "lock.open", title: "Today",
                         detail: "Every Pro feature unlocks."),
            TimelineStep(symbol: "bell", title: "Day \(remindDay)",
                         detail: "We remind you on \(remind.formatted(short)) that the trial is ending."),
            TimelineStep(symbol: "calendar.badge.checkmark", title: "Day \(endDay)",
                         detail: "Billing starts on \(end.formatted(short)) at \(price.display), unless you cancel before."),
        ]
    }
}
