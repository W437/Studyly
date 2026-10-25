import Foundation
import StoreKit
import UIKit

/// StoreKit 2: products, purchases, restore and the plan every gate reads.
///
/// - `plan` (and `isPro`, `allows(_:)`) comes from `Transaction.currentEntitlements` through
///   `EntitlementResolver` (pure, tested), merged with a server grant (a friend's Squad seat), and replaced by
///   `CRAMLESS_PLAN=free|pro|squad|pass` in the DEBUG harness.
/// - Products load in the background with retries. Until they load, prices are the labelled fallback in
///   `PlanOption`; a purchase loads first and fails clearly if the App Store still can't be reached.
/// - After every change: the signed transactions go to `account.syncEntitlements(_:)`, and the trial reminder is
///   scheduled or removed (`TrialReminder`, identifiers `trial.…`).
@MainActor
@Observable
final class PurchaseStore {
    enum ProductsState: Equatable, Sendable { case idle, loading, loaded, unavailable }

    enum PurchaseOutcome: Equatable, Sendable {
        case purchased(PlanOption)
        /// Ask to Buy or a bank check. Pro unlocks when it's approved (it arrives on `Transaction.updates`).
        case pending
        case cancelled
        case failed(PurchaseFailure)
    }

    enum PurchaseFailure: Equatable, Sendable {
        case storeUnavailable, notAllowed, network, ineligibleForOffer, unverified, unknown

        /// What the paywall says. Plain, and never blames the person.
        var message: String {
            switch self {
            case .storeUnavailable: "The App Store isn't reachable right now. Try again in a moment."
            case .notAllowed: "Purchases are turned off on this iPhone. You can allow them in Settings, under Screen Time."
            case .network: "You're offline. Connect to the internet and try again."
            case .ineligibleForOffer: "The free week was already used on this Apple Account. You can still subscribe."
            case .unverified: "Apple couldn't verify that purchase, so nothing changed. Try again, or restore purchases."
            case .unknown: "The App Store couldn't finish the purchase. Try again in a moment."
            }
        }
    }

    enum RestoreOutcome: Equatable, Sendable { case restored(Plan), nothingToRestore, cancelled, failed }

    @ObservationIgnored weak var app: AppModel?

    /// What the person has: plan, product, expiry, trial.
    private(set) var entitlement: Entitlement = .free
    private(set) var productsState: ProductsState = .idle
    /// Localized prices for the products that loaded (`price(for:)` falls back per option).
    private(set) var prices: [PlanOption: PlanPrice] = [:]
    /// Whether the subscription group's free trial is still available to this Apple Account.
    private(set) var isTrialEligible = true
    /// The purchase in flight; the paywall disables its controls while it is set.
    private(set) var purchasing: PlanOption?

    /// The signed-in account's id (the Supabase user UUID). The Backend lane sets it when a session starts and
    /// clears it on sign-out; purchases carry it as `appAccountToken` so the server can tie App Store
    /// transactions to the account.
    var accountToken: UUID?

    /// Where signed transactions go after a change. Nil means `app.account.syncEntitlements(_:)`; tests capture.
    @ObservationIgnored var entitlementSink: (([String]) async -> Void)?

    @ObservationIgnored private var products: [String: Product] = [:]
    @ObservationIgnored private var storeEntitlement: Entitlement = .free
    @ObservationIgnored private var granted: Entitlement?
    @ObservationIgnored private var override: Plan?
    @ObservationIgnored private var lastSynced: [String]?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var started = false

    init(app: AppModel) {
        self.app = app
        #if DEBUG
        if app.config.isHarness, let raw = TestHarness.value("CRAMLESS_PLAN"), let plan = Plan(rawValue: raw) {
            override = plan
        }
        #endif
        recompute()
    }

    // MARK: Reading the plan

    var plan: Plan { entitlement.plan }
    var isPro: Bool { entitlement.plan.isPaid }

    /// The gate for a paid feature (`.squadSeats` needs the Squad purchase itself).
    func allows(_ feature: PaidFeature) -> Bool { entitlement.allows(feature) }

    /// The price to show for `option`: the App Store's when loaded, else the fallback.
    func price(for option: PlanOption) -> PlanPrice { prices[option] ?? .fallback(option) }

    /// Days of free trial this person would get with `option` (nil: none, or already used).
    func trialDays(for option: PlanOption) -> Int? {
        isTrialEligible ? price(for: option).trialDays : nil
    }

    /// When the trial reminder fires for a trial ending at `trialEnds` (the paywall's timeline and the
    /// celebration name this date).
    func reminderDate(forTrialEnding trialEnds: Date) -> Date? {
        guard let app else { return nil }
        let s = app.settings
        return TrialReminder.fireDate(trialEnds: trialEnds, reminderMinutes: s.reminderMinutes,
                                      quietStart: s.quietHoursStart, quietEnd: s.quietHoursEnd,
                                      now: app.now, calendar: app.calendar)
    }

    // MARK: Lifecycle

    /// Called once from `AppModel.start()`. Returns at once: StoreKit can take a long time to answer (or not
    /// answer at all in a simulator without a StoreKit configuration), and launch must never wait for it. The
    /// plan starts as the last-known free state and updates when the entitlements arrive.
    func start() async {
        guard !started else { return }
        started = true
        #if DEBUG
        // The screenshot harness never touches StoreKit: a simulator whose StoreKit state was left by purchase
        // tests asks for an Apple Account on launch, which covers every screen. Fallback prices and
        // CRAMLESS_PLAN stand in; CRAMLESS_STOREKIT=1 opts back in.
        if app?.config.isHarness == true, TestHarness.value("CRAMLESS_STOREKIT") != "1" {
            productsState = .unavailable
            return
        }
        #endif
        listenForTransactions()
        Task {
            await self.finishUnfinished()
            await self.refreshEntitlements()
        }
        Task { await self.loadProducts() }
    }

    /// Loads the products, retrying (2 s, then 6 s) while the App Store returns nothing.
    func loadProducts(retries: Int = 2) async {
        if productsState == .loaded { return }
        if let loadTask { await loadTask.value; return }
        let task = Task { await self.performLoad(retries: retries) }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad(retries: Int) async {
        productsState = .loading
        let ids = PlanOption.allCases.map(\.productID)
        let delays = [0, 2, 6].prefix(retries + 1)
        for delay in delays {
            if delay > 0 {
                do { try await Task.sleep(for: .seconds(delay)) } catch { break }
            }
            do {
                let loaded = try await Product.products(for: ids)
                if !loaded.isEmpty {
                    apply(loaded)
                    productsState = .loaded
                    await refreshTrialEligibility()
                    return
                }
            } catch {
                AppConfig.log.error("products: \(error.localizedDescription, privacy: .public)")
            }
        }
        productsState = .unavailable
        AppConfig.log.notice("products unavailable; the paywall shows fallback prices")
    }

    private func apply(_ loaded: [Product]) {
        var byID: [String: Product] = [:]
        var newPrices: [PlanOption: PlanPrice] = [:]
        for product in loaded {
            byID[product.id] = product
            guard let option = PlanOption(productID: product.id) else { continue }
            let style = product.priceFormatStyle
            newPrices[option] = PlanPrice(option: option, amount: product.price, display: product.displayPrice,
                                          currencyCode: style.currencyCode, locale: style.locale,
                                          trialDays: Self.trialDays(product), isFallback: false)
        }
        products = byID
        prices = newPrices
    }

    private static func trialDays(_ product: Product) -> Int? {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let unit: Int = switch offer.period.unit {
        case .day: 1
        case .week: 7
        case .month: 30
        case .year: 365
        @unknown default: 1
        }
        return offer.period.value * unit
    }

    private func refreshTrialEligibility() async {
        guard let subscription = products[PlanOption.yearly.productID]?.subscription else { return }
        isTrialEligible = await subscription.isEligibleForIntroOffer
    }

    private func listenForTransactions() {
        updatesTask = Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refreshEntitlements()
            }
        }
        // An Exam Pass or a subscription can run out while the app sleeps.
        activeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification) {
                await self?.refreshEntitlements()
            }
        }
    }

    private func finishUnfinished() async {
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result { await transaction.finish() }
        }
    }

    // MARK: Entitlements

    /// Recomputes the plan from the current entitlements, then syncs and updates the trial reminder. Calls that
    /// arrive while one is running wait for it, and it runs once more for them, so every caller returns with a
    /// refresh that started after it asked (and a StoreKit that never answers can't pile up stuck refreshes).
    func refreshEntitlements() async {
        if let refreshTask {
            refreshAgain = true
            await refreshTask.value
            return
        }
        let task = Task {
            repeat {
                refreshAgain = false
                await performRefresh()
            } while refreshAgain
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// Sends the current transactions again, for a session the server hasn't seen them with: signing in makes a
    /// new account, and this launch's sync went to the session before it. Does nothing when nothing was sent this
    /// launch (a free person, or StoreKit not read yet: the launch refresh sends them with the current session).
    func resyncEntitlements() async {
        guard let sent = lastSynced, !sent.isEmpty else { return }
        lastSynced = nil
        await refreshEntitlements()
    }

    private func performRefresh() async {
        var snapshots: [TransactionSnapshot] = []
        var signed: [String] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            snapshots.append(TransactionSnapshot(transaction))
            signed.append(result.jwsRepresentation)
        }
        let now = app?.now ?? Date()
        storeEntitlement = EntitlementResolver.resolve(snapshots, now: now, calendar: app?.calendar ?? .current)
        recompute()
        await updateTrialReminder()
        await sync(signed.sorted())
    }

    /// A plan the server granted (a seat on a friend's Squad). The Backend lane calls this after redeeming an
    /// invite or syncing; `nil` or `.free` clears it.
    func applyServerGrant(_ plan: Plan?, until: Date?) {
        granted = plan.map { Entitlement(plan: $0, option: nil, expiresAt: until, isFreeTrial: false,
                                         originalTransactionID: nil) }
        recompute()
    }

    private func recompute() {
        entitlement = EntitlementResolver.effective(store: storeEntitlement, granted: granted, override: override,
                                                    now: app?.now ?? Date())
    }

    private func sync(_ signed: [String]) async {
        guard signed != lastSynced else { return }
        // The first refresh of a free person has nothing to tell the server.
        if lastSynced == nil, signed.isEmpty { lastSynced = signed; return }
        lastSynced = signed
        if let entitlementSink {
            await entitlementSink(signed)
        } else if let app, app.sideEffectsEnabled {
            await app.account.syncEntitlements(signed)
        }
    }

    private func updateTrialReminder() async {
        guard let app, app.sideEffectsEnabled, override == nil else { return }
        let e = storeEntitlement
        guard e.isFreeTrial, let ends = e.expiresAt, let original = e.originalTransactionID,
              await willAutoRenew(e) != false else {
            await TrialReminder.schedule(identifier: nil, fireDate: nil, body: "", calendar: app.calendar)
            return
        }
        await TrialReminder.schedule(identifier: TrialReminder.identifier(originalTransactionID: original),
                                     fireDate: reminderDate(forTrialEnding: ends),
                                     body: TrialReminder.body(trialEnds: ends, plan: e.plan, calendar: app.calendar),
                                     calendar: app.calendar)
    }

    /// False when the person already turned off renewal (the reminder would be wrong); nil when unknown.
    private func willAutoRenew(_ e: Entitlement) async -> Bool? {
        guard let option = e.option, let subscription = products[option.productID]?.subscription,
              let statuses = try? await subscription.status else { return nil }
        for status in statuses {
            guard case .verified(let transaction) = status.transaction,
                  transaction.originalID == e.originalTransactionID,
                  case .verified(let info) = status.renewalInfo else { continue }
            return info.willAutoRenew
        }
        return nil
    }

    // MARK: Buying

    /// Buys `option`. Loads products first if they haven't loaded; carries `appAccountToken` when signed in.
    func purchase(_ option: PlanOption) async -> PurchaseOutcome {
        guard purchasing == nil else { return .cancelled }
        purchasing = option
        defer { purchasing = nil }
        if products[option.productID] == nil { await loadProducts(retries: 0) }
        guard let product = products[option.productID] else { return .failed(.storeUnavailable) }

        var options: Set<Product.PurchaseOption> = []
        if let token = appAccountToken { options.insert(.appAccountToken(token)) }
        do {
            // On iPhone this presents in the active scene. (The scene-confirming variant ignores StoreKit Testing's
            // `disableDialogs` and asks for an Apple Account in unit tests.)
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return .failed(.unverified) }
                await transaction.finish()
                await refreshEntitlements()
                return .purchased(option)
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed(.unknown)
            }
        } catch {
            AppConfig.log.error("purchase \(option.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            return Self.outcome(for: error)
        }
    }

    /// Restore purchases: `AppStore.sync()` (it may ask for the Apple Account password), then refresh.
    func restore() async -> RestoreOutcome {
        do {
            try await AppStore.sync()
        } catch {
            if let e = error as? StoreKitError, case .userCancelled = e { return .cancelled }
            AppConfig.log.error("restore: \(String(describing: error), privacy: .public)")
            return .failed
        }
        await refreshEntitlements()
        return plan.isPaid ? .restored(plan) : .nothingToRestore
    }

    private var appAccountToken: UUID? {
        (app?.account.isSignedIn ?? false) ? accountToken : nil
    }

    static func outcome(for error: Error) -> PurchaseOutcome {
        if let e = error as? StoreKitError {
            switch e {
            case .userCancelled: return .cancelled
            case .networkError: return .failed(.network)
            case .notAvailableInStorefront: return .failed(.storeUnavailable)
            default: return .failed(.unknown)
            }
        }
        if let e = error as? Product.PurchaseError {
            switch e {
            case .purchaseNotAllowed: return .failed(.notAllowed)
            case .ineligibleForOffer: return .failed(.ineligibleForOffer)
            case .productUnavailable: return .failed(.storeUnavailable)
            default: return .failed(.unknown)
            }
        }
        return .failed(.unknown)
    }
}

extension TransactionSnapshot {
    init(_ t: Transaction) {
        self.init(id: t.id, originalID: t.originalID, productID: t.productID, purchaseDate: t.purchaseDate,
                  expirationDate: t.expirationDate, revocationDate: t.revocationDate, isUpgraded: t.isUpgraded,
                  isFreeTrial: t.offer?.type == .introductory && t.offer?.paymentMode == .freeTrial)
    }
}
