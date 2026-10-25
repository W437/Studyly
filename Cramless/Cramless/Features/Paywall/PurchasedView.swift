import SwiftUI
import UserNotifications

/// The moment a purchase lands: Cap celebrates once, a warm bloom behind, and the plain facts (when the free week
/// ends and when we'll remind). One celebration, no confetti. Also the "you're on Pro" state when a paid person
/// opens the paywall, with a way to manage the subscription.
struct PurchasedView: View {
    enum Mode: Equatable, Sendable {
        case purchased(PlanOption)
        case restored(Plan)
        /// Already paid when the paywall opened.
        case current
    }

    let mode: Mode
    let primaryTitle: String
    let onPrimary: () -> Void
    var onInvite: (() -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var notificationsOff = false

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content
                    // Centred when it fits; scrolls at the largest text sizes.
                    .frame(minHeight: geo.size.height * 0.9)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaBar(edge: .bottom) {
            Button(primaryTitle, action: onPrimary)
                .buttonStyle(.cl(.primary))
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 10)
        }
        .background(CLColor.background.ignoresSafeArea())
        .task {
            if reduceMotion { shown = true } else { withAnimation(CLMotion.pop.delay(0.08)) { shown = true } }
            await settleReminderPermission()
        }
    }

    private var content: some View {
            VStack(spacing: 0) {
                ZStack {
                    // Celebrate the crossing (a purchase, a restore), never the state: a paid person opening the
                    // paywall gets a calm wave, no bloom.
                    if celebrates {
                        Circle()
                            .fill(RadialGradient(colors: [CLColor.sun.opacity(0.5), CLColor.tangerine.opacity(0.14), .clear],
                                                 center: .center, startRadius: 4, endRadius: 150))
                            .frame(width: 300, height: 300)
                            .scaleEffect(shown ? 1 : 0.4)
                            .opacity(shown ? 1 : 0)
                    }
                    CapView(pose: celebrates ? .celebrate : .wave, size: 210, decorative: false)
                        .scaleEffect(shown || !celebrates ? 1 : 0.7, anchor: .bottom)
                        .offset(y: shown || !celebrates ? 0 : 24)
                        .opacity(shown || !celebrates ? 1 : 0)
                }
                .frame(height: 250)

                Text(title)
                    .clFont(.display(36))
                    .foregroundStyle(CLColor.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)
                Text(message)
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                if showsInvite, let onInvite {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Invite your squad").clFont(.title3).foregroundStyle(CLColor.ink)
                        Text("Three friends get Pro free. You'll see when they study.")
                            .clFont(.subheadline)
                            .foregroundStyle(CLColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(action: onInvite) {
                            Label("Invite friends", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(.cl(.soft, size: .medium))
                        .padding(.top, 8)
                    }
                    .clCard()
                    .padding(.top, 26)
                }

                if case .current = mode, app.purchases.entitlement.option?.isAutoRenewing == true {
                    ManageSubscriptionButton()
                        .clFont(.subheadlineEmphasis)
                        .foregroundStyle(CLColor.skyInk)
                        .buttonStyle(.plain)
                        .frame(minHeight: CLMetrics.minHitTarget)
                        .padding(.top, 18)
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
    }

    // MARK: Copy

    private var entitlement: Entitlement { app.purchases.entitlement }

    private var celebrates: Bool { mode != .current }

    private var title: String {
        switch mode {
        case .purchased(.examPass): "You're set for exam day."
        case .purchased: "You're in."
        case .restored: "Welcome back."
        case .current: "You're on \(entitlement.plan.displayName)."
        }
    }

    private var message: String {
        let short = Date.FormatStyle.dateTime.month(.abbreviated).day()
        let passLine = "Exam Pass is on: every Pro feature"
            + (passEnds.map { " until \($0.formatted(short))" } ?? " for 30 days") + ". It won't renew."
        switch mode {
        case .purchased(.examPass):
            return passLine
        case .current where entitlement.option == .examPass:
            return passLine
        case .purchased(let option):
            let name = option == .squad ? "Your Squad free week" : "Your free week"
            guard let ends = trialEnds else {
                return option == .squad ? "Squad is on. Invite your three friends." : "Capling Pro is on. Every feature, for every class."
            }
            if notificationsOff {
                return "\(name) has started and ends on \(ends.formatted(short)). Notifications are off, so keep that date in mind: you can cancel in two taps before then."
            }
            let remind = app.purchases.reminderDate(forTrialEnding: ends)
                ?? app.calendar.date(byAdding: .day, value: -StoreCatalog.trialReminderLeadDays, to: ends) ?? ends
            return "\(name) has started. We'll remind you on \(remind.formatted(short)), two days before it ends."
        case .restored(let plan):
            return "Your purchase is restored. \(plan == .pass ? "Exam Pass" : "Capling \(plan.displayName)") is on."
        case .current:
            guard let end = entitlement.expiresAt else { return "Every feature, for every class." }
            if entitlement.isFreeTrial { return "Your free week ends on \(end.formatted(short))." }
            return "Your plan renews on \(end.formatted(.dateTime.month(.abbreviated).day().year()))."
        }
    }

    private var showsInvite: Bool {
        switch mode {
        case .purchased(.squad): true
        case .current: entitlement.option == .squad
        default: false
        }
    }

    /// The trial's end: from the transaction, or (in the DEBUG harness, where the purchase is simulated) a week
    /// from now.
    private var trialEnds: Date? {
        if entitlement.isFreeTrial { return entitlement.expiresAt }
        #if DEBUG
        if app.config.isHarness, !app.purchases.isPro, case .purchased(let option) = mode,
           let days = app.purchases.trialDays(for: option) {
            return app.calendar.date(byAdding: .day, value: days, to: app.now)
        }
        #endif
        return nil
    }

    private var passEnds: Date? {
        if entitlement.option == .examPass { return entitlement.expiresAt }
        return app.calendar.date(byAdding: .day, value: StoreCatalog.examPassDays, to: app.now)
    }

    /// A free trial was promised a reminder: ask for notifications now if nobody has asked yet, then schedule.
    private func settleReminderPermission() async {
        guard entitlement.isFreeTrial, app.sideEffectsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = await app.notifications.requestAuthorization()
            await app.purchases.refreshEntitlements()
        }
        notificationsOff = await center.notificationSettings().authorizationStatus == .denied
    }
}
