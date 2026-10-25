import Foundation

/// Everything Capling sells. Product IDs match `Cramless.storekit` (the local test store) and App Store Connect.
enum PlanOption: String, CaseIterable, Identifiable, Hashable, Sendable {
    case yearly, monthly, squad, examPass

    var id: String { rawValue }

    /// The paywall's three options, in display order. Exam Pass is a separate downsell (`ExamPassView`).
    static let paywallOptions: [PlanOption] = [.yearly, .monthly, .squad]

    var productID: String {
        switch self {
        case .yearly: "com.loopware.Capling.pro.yearly"
        case .monthly: "com.loopware.Capling.pro.monthly"
        case .squad: "com.loopware.Capling.squad.yearly"
        case .examPass: "com.loopware.Capling.exampass"
        }
    }

    init?(productID: String) {
        guard let match = Self.allCases.first(where: { $0.productID == productID }) else { return nil }
        self = match
    }

    /// The plan a purchase of this product grants.
    var plan: Plan {
        switch self {
        case .yearly, .monthly: .pro
        case .squad: .squad
        case .examPass: .pass
        }
    }

    /// Auto-renewing (the subscription group). Exam Pass is a non-renewing 30-day pass.
    var isAutoRenewing: Bool { self != .examPass }

    var title: String {
        switch self {
        case .yearly: "Yearly"
        case .monthly: "Monthly"
        case .squad: "Squad"
        case .examPass: "Exam Pass"
        }
    }

    /// "per year" under the price.
    var unitLabel: String {
        switch self {
        case .yearly, .squad: "per year"
        case .monthly: "per month"
        case .examPass: "for 30 days"
        }
    }

    // MARK: Fallback prices

    /// FALLBACK PRICES. Shown only when StoreKit products have not loaded: `simctl launch` runs without the
    /// `.storekit` configuration (Xcode attaches it only on Run), and a device can be offline or between
    /// storefronts. They mirror `Cramless.storekit` and App Store Connect in US dollars. Whenever a product has
    /// loaded, its localized price wins, and a purchase is only ever made against a loaded product.
    var fallbackPrice: Decimal {
        switch self {
        case .yearly: Decimal(string: "49.99")!
        case .monthly: Decimal(string: "9.99")!
        case .squad: Decimal(string: "99.99")!
        case .examPass: Decimal(string: "14.99")!
        }
    }

    /// FALLBACK: the free trial in days when products have not loaded (Yearly and Squad have a 7-day trial).
    var fallbackTrialDays: Int? {
        switch self {
        case .yearly, .squad: 7
        case .monthly, .examPass: nil
        }
    }
}

enum StoreCatalog {
    /// Exam Pass lasts this many days from its purchase date and never renews.
    static let examPassDays = 30
    /// Squad: the owner plus three friends.
    static let squadSeats = 4
    /// Exam Pass is offered to free users who decline the paywall this close to an exam.
    static let examPassWindowDays = 21
    /// The trial reminder fires this many days before the trial ends ("Day 5" of a 7-day trial).
    static let trialReminderLeadDays = 2

    /// Terms of Use and Privacy Policy. Nil until the owner provides the real pages: the paywall shows a link only
    /// when one exists, and nobody invents a URL. (App Review needs both before a subscription ships.)
    static let termsURL: URL? = nil
    static let privacyURL: URL? = nil

    /// What the free plan keeps, as the paywall says it. The meters themselves live in the relay's quota.
    static let freePlanLine = "Free includes unlimited flashcard reviews, 3 scans a week and 20 graded answers a day."
}

/// A price as the paywall shows it: from the StoreKit product when it has loaded, else the labelled fallback.
struct PlanPrice: Equatable, Sendable {
    var option: PlanOption
    var amount: Decimal
    /// The App Store's own string ("$49.99"), or the fallback amount formatted in US dollars.
    var display: String
    var currencyCode: String
    var locale: Locale
    /// Days of free trial the product offers (nil: none). Eligibility is a separate question.
    var trialDays: Int?
    /// True when no product has loaded and these are the fallback numbers.
    var isFallback: Bool

    static func fallback(_ option: PlanOption) -> PlanPrice {
        let locale = Locale(identifier: "en_US")
        let amount = option.fallbackPrice
        return PlanPrice(option: option, amount: amount,
                         display: amount.formatted(.currency(code: "USD").locale(locale)),
                         currencyCode: "USD", locale: locale, trialDays: option.fallbackTrialDays, isFallback: true)
    }

    /// Formats any amount in this price's currency and locale.
    func format(_ value: Decimal) -> String {
        value.formatted(.currency(code: currencyCode).locale(locale))
    }

    /// "$0.96" for $49.99 a year.
    var perWeek: String { format(Self.divide(amount, by: 52)) }

    /// "$2.08" for Squad: $99.99 a year shared by four, per person per month.
    var perSeatPerMonth: String { format(Self.divide(amount, by: StoreCatalog.squadSeats * 12)) }

    private static func divide(_ value: Decimal, by count: Int) -> Decimal {
        var result = value / Decimal(count)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &result, 2, .plain)
        return rounded
    }
}

extension Plan {
    /// Squad beats Pro beats Exam Pass beats Free.
    var rank: Int {
        switch self {
        case .free: 0
        case .pass: 1
        case .pro: 2
        case .squad: 3
        }
    }

    /// "Pro", "Squad", "Exam Pass", "Free": the name copy uses ("do nothing to keep Pro").
    var displayName: String {
        switch self {
        case .free: "Free"
        case .pro: "Pro"
        case .squad: "Squad"
        case .pass: "Exam Pass"
        }
    }
}
