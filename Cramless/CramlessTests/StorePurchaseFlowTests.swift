import StoreKit
import StoreKitTest
import XCTest
@testable import Cramless

/// Real StoreKit purchase flows against `Cramless.storekit`, through `SKTestSession` (dialogs off). The test
/// session reads the configuration straight from the source tree, so the test target needs no copy of it.
///
/// Opt-in (`TEST_RUNNER_CRAMLESS_STOREKIT_TESTS=1` on the xcodebuild command line): on iOS 27 simulators a
/// purchase here can fall through to a real "Sign in to Apple Account" request, which then appears over every
/// app on that simulator until it is erased. Run them on a simulator of their own.
@MainActor
final class StorePurchaseFlowTests: XCTestCase {
    private var session: SKTestSession!
    private var app: AppModel!
    private var savedLive: AppModel?
    private var synced: [[String]] = []

    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["CRAMLESS_STOREKIT_TESTS"] == "1" else {
            throw XCTSkip("StoreKit purchase flows are opt-in: TEST_RUNNER_CRAMLESS_STOREKIT_TESTS=1")
        }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Cramless.storekit")
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        savedLive = AppModel.live
        let defaults = UserDefaults(suiteName: "store-flow-\(UUID().uuidString)")!
        app = AppModel(config: .resolve(), container: nil, defaults: defaults)
        synced = []
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        AppModel.live = savedLive
        app = nil
        session = nil
    }

    private func makeStore() -> PurchaseStore {
        let store = PurchaseStore(app: app)
        store.entitlementSink = { [weak self] signed in self?.synced.append(signed) }
        return store
    }

    /// Buys through the store, but never hangs the suite: when the simulator's StoreKit daemon hasn't attached
    /// the test session, StoreKit asks for a real Apple Account and the purchase never returns. That is the
    /// environment, not the app (a simulator reboot clears it), so the test is skipped with a note.
    private func buy(_ option: PlanOption, on store: PurchaseStore) async throws -> PurchaseStore.PurchaseOutcome {
        final class Once { var done = false }
        let once = Once()
        let outcome: PurchaseStore.PurchaseOutcome? = await withCheckedContinuation { continuation in
            Task { @MainActor in
                let result = await store.purchase(option)
                if !once.done { once.done = true; continuation.resume(returning: result) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                if !once.done { once.done = true; continuation.resume(returning: nil) }
            }
        }
        guard let outcome else {
            throw XCTSkip("StoreKit asked for an Apple Account instead of using the test session; reboot the simulator.")
        }
        return outcome
    }

    func testProductsLoadWithTheirOwnPricesAndTrials() async {
        let store = makeStore()
        await store.loadProducts(retries: 0)
        XCTAssertEqual(store.productsState, .loaded)
        let yearly = store.price(for: .yearly)
        XCTAssertFalse(yearly.isFallback)
        XCTAssertEqual(yearly.amount, Decimal(string: "49.99"))
        XCTAssertEqual(yearly.trialDays, 7)
        XCTAssertEqual(store.price(for: .squad).trialDays, 7)
        XCTAssertNil(store.price(for: .monthly).trialDays)
        XCTAssertEqual(store.price(for: .examPass).amount, Decimal(string: "14.99"))
        XCTAssertTrue(store.isTrialEligible)
        XCTAssertEqual(store.trialDays(for: .yearly), 7)
    }

    func testBuyingYearlyStartsAFreeWeekOfPro() async throws {
        let store = makeStore()
        let outcome = try await buy(.yearly, on: store)
        XCTAssertEqual(outcome, .purchased(.yearly))
        XCTAssertEqual(store.plan, .pro)
        XCTAssertTrue(store.isPro)
        XCTAssertTrue(store.entitlement.isFreeTrial)
        XCTAssertNotNil(store.entitlement.expiresAt)
        XCTAssertTrue(store.allows(.unlimitedCapture))
        XCTAssertFalse(store.allows(.squadSeats))
        XCTAssertEqual(synced.last?.count, 1, "the signed transaction went to the account service")
        XCTAssertNil(store.purchasing)
    }

    func testExamPassIsThirtyDaysAndNeverRenews() async throws {
        let store = makeStore()
        let outcome = try await buy(.examPass, on: store)
        XCTAssertEqual(outcome, .purchased(.examPass))
        XCTAssertEqual(store.plan, .pass)
        let expires = try XCTUnwrap(store.entitlement.expiresAt)
        let days = app.calendar.dayDistance(from: app.now, to: expires)
        XCTAssertEqual(days, StoreCatalog.examPassDays)
    }

    func testSquadOwnersCanInvite() async throws {
        let store = makeStore()
        _ = try await buy(.squad, on: store)
        XCTAssertEqual(store.plan, .squad)
        XCTAssertTrue(store.allows(.squadSeats))
    }

    func testRestoreFindsAnEarlierPurchase() async throws {
        try await session.buyProduct(identifier: PlanOption.monthly.productID)
        let store = makeStore()
        XCTAssertEqual(store.plan, .free, "a fresh store knows nothing yet")
        await store.refreshEntitlements()
        XCTAssertEqual(store.plan, .pro)
    }

    /// A refund revokes the purchase: back to free, and the server hears it. (Expiry itself is covered by the
    /// resolver's tests: under Xcode 27, `SKTestSession.expireSubscription` doesn't reach `currentEntitlements`
    /// in-process.)
    func testARefundFallsBackToFree() async throws {
        let store = makeStore()
        _ = try await buy(.monthly, on: store)
        XCTAssertEqual(store.plan, .pro)
        let bought = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == PlanOption.monthly.productID })
        try session.refundTransaction(identifier: bought.identifier)
        for _ in 0..<40 where store.plan != .free {
            try await Task.sleep(for: .milliseconds(250))
            await store.refreshEntitlements()
        }
        XCTAssertEqual(store.plan, .free)
        XCTAssertEqual(synced.last, [], "the server hears that it ended")
    }
}
