import Foundation

/// A StoreKit transaction reduced to the values the plan depends on, so the plan can be computed (and tested)
/// without StoreKit. `PurchaseStore` builds these from `Transaction.currentEntitlements`.
struct TransactionSnapshot: Hashable, Sendable {
    var id: UInt64
    var originalID: UInt64
    var productID: String
    var purchaseDate: Date
    /// Auto-renewing subscriptions only: the end of the current period (the end of the trial, during one).
    var expirationDate: Date?
    var revocationDate: Date?
    /// Superseded by a higher-level subscription in the same group.
    var isUpgraded: Bool = false
    /// The current period is an introductory free trial.
    var isFreeTrial: Bool = false
}

/// What the person has, and until when.
struct Entitlement: Equatable, Sendable {
    var plan: Plan
    var option: PlanOption?
    /// When access ends unless it renews (nil for free).
    var expiresAt: Date?
    var isFreeTrial: Bool
    var originalTransactionID: UInt64?

    static let free = Entitlement(plan: .free, option: nil, expiresAt: nil, isFreeTrial: false, originalTransactionID: nil)
}

/// The plan, as a pure function of transaction snapshots and the clock.
///
/// - Revoked (refunded) and upgraded transactions don't count; unknown products are ignored.
/// - Auto-renewing subscriptions count until their expiration date.
/// - Exam Pass is non-renewing: StoreKit keeps every pass in `currentEntitlements` forever, so the app decides.
///   A pass lasts 30 days from its purchase date; a pass bought while another is running starts when that one
///   ends, so two passes make 60 days.
/// - Squad beats Pro beats Exam Pass beats Free; between equals, the later expiry wins.
enum EntitlementResolver {
    static func resolve(_ transactions: [TransactionSnapshot], now: Date, calendar: Calendar) -> Entitlement {
        let valid = transactions.filter { $0.revocationDate == nil && !$0.isUpgraded }
        var candidates: [Entitlement] = []

        for t in valid {
            guard let option = PlanOption(productID: t.productID), option.isAutoRenewing else { continue }
            if let end = t.expirationDate, end <= now { continue }
            candidates.append(Entitlement(plan: option.plan, option: option, expiresAt: t.expirationDate,
                                          isFreeTrial: t.isFreeTrial, originalTransactionID: t.originalID))
        }

        let passes = valid.filter { PlanOption(productID: $0.productID) == .examPass }
        if let window = examPassWindow(passes, calendar: calendar), window.start <= now, now < window.end {
            candidates.append(Entitlement(plan: .pass, option: .examPass, expiresAt: window.end, isFreeTrial: false,
                                          originalTransactionID: window.originalID))
        }

        return candidates.max { a, b in
            if a.plan.rank != b.plan.rank { return a.plan.rank < b.plan.rank }
            return (a.expiresAt ?? .distantFuture) < (b.expiresAt ?? .distantFuture)
        } ?? .free
    }

    /// The stretch of time the person's Exam Passes cover, each one starting when the one before it ends.
    /// Returns the span of the latest unbroken run of passes (a pass bought after a gap starts a new run).
    static func examPassWindow(_ passes: [TransactionSnapshot], calendar: Calendar)
        -> (start: Date, end: Date, originalID: UInt64)? {
        var window: (start: Date, end: Date, originalID: UInt64)?
        for pass in passes.sorted(by: { $0.purchaseDate < $1.purchaseDate }) {
            if let current = window, pass.purchaseDate < current.end {
                // Bought while a pass is running: it extends the run.
                let end = calendar.date(byAdding: .day, value: StoreCatalog.examPassDays, to: current.end) ?? current.end
                window = (current.start, end, pass.originalID)
            } else {
                let end = calendar.date(byAdding: .day, value: StoreCatalog.examPassDays, to: pass.purchaseDate)
                    ?? pass.purchaseDate
                window = (pass.purchaseDate, end, pass.originalID)
            }
        }
        return window
    }

    /// The plan the app acts on: the harness override when set, else the better of what StoreKit says and what
    /// the server granted (a Squad member's seat), ignoring a grant that has run out.
    static func effective(store: Entitlement, granted: Entitlement?, override: Plan?, now: Date) -> Entitlement {
        if let override {
            return Entitlement(plan: override, option: override.defaultOption, expiresAt: nil, isFreeTrial: false,
                               originalTransactionID: nil)
        }
        guard let granted, granted.plan != .free, (granted.expiresAt ?? .distantFuture) > now,
              granted.plan.rank > store.plan.rank else { return store }
        return granted
    }
}

extension Plan {
    /// The product that grants this plan, for display (the harness override, a server grant).
    var defaultOption: PlanOption? {
        switch self {
        case .free: nil
        case .pro: .yearly
        case .squad: .squad
        case .pass: .examPass
        }
    }
}

/// Yes/no gates for paid features. The free plan's limits (3 scans a week, 20 graded answers a day, 10 tutor
/// messages a day, AI notes for 1 lecture a week) are quota meters the relay counts; these are the switches.
enum PaidFeature: String, CaseIterable, Sendable {
    /// Scans, PDFs and lectures past the free meters.
    case unlimitedCapture
    /// Own-words grading past the free meter.
    case unlimitedGrading
    /// The tutor past the free meter.
    case unlimitedTutor
    /// AI notes for every lecture.
    case lectureNotes
    /// More than one exam plan at a time.
    case multipleExamPlans
    /// Practice tests in the teacher's format.
    case practiceTests
    /// The projected grade on an exam.
    case projectedGrade
    /// Inviting three friends: Squad owners only.
    case squadSeats

    /// For a paywall opened by a gate: "Unlimited scans are part of Pro."
    var paywallLine: String {
        switch self {
        case .unlimitedCapture: "Unlimited scans, PDFs and lectures are part of Pro."
        case .unlimitedGrading: "Unlimited graded answers are part of Pro."
        case .unlimitedTutor: "Unlimited questions for Cap are part of Pro."
        case .lectureNotes: "AI notes for every lecture are part of Pro."
        case .multipleExamPlans: "A plan for every exam is part of Pro."
        case .practiceTests: "Practice tests in your teacher's format are part of Pro."
        case .projectedGrade: "Your projected grade is part of Pro."
        case .squadSeats: "Studying with three friends is part of Squad."
        }
    }
}

extension Entitlement {
    /// Whether this entitlement unlocks `feature`. Pro, Squad and Exam Pass unlock everything; inviting friends
    /// needs the Squad purchase itself (a friend on someone else's Squad can't invite more).
    func allows(_ feature: PaidFeature) -> Bool {
        switch feature {
        case .squadSeats: option == .squad
        default: plan.isPaid
        }
    }
}
