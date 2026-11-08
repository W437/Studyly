import SwiftUI

/// Settings ▸ Subscription: the plan and when it renews or ends, the App Store's own manage sheet (cancel in two
/// taps), the plans: Pro, Squad (its own page), Exam Pass (listed here at any time: a catalogue the person opened, unlike the offer
/// elsewhere, which waits for 8 to 21 days before an exam), and restore. An account under 13 is sold nothing; one already on a Squad keeps
/// its way to it.
struct SubscriptionPage: View {
    @Environment(AppModel.self) private var app

    private var store: PurchaseStore { app.purchases }

    var body: some View {
        let e = store.entitlement
        SettingsScroll(title: "Subscription") {
            planCard(e)
                .padding(.top, 14)
            if e.option?.isAutoRenewing == true {
                VStack(alignment: .leading, spacing: 8) {
                    ManageSubscriptionButton(title: "Manage or cancel subscription")
                        .buttonStyle(.cl(.soft))
                    Text("Opens the App Store's own page. Cancelling takes two taps and keeps \(e.plan.displayName) until the end of the period you paid for.")
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }
                .padding(.top, 16)
            }
            SettingsGroup(title: app.settings.canBuyPro ? "Plans" : nil) {
                if app.settings.canBuyPro {
                    NavigationLinkRow(icon: "sparkles", tint: .tangerine, title: e.plan == .free ? "See Pro" : "See the plans",
                                      subtitle: e.plan == .free ? .verbatim(yearlyLine) : nil) {
                        app.router.present(.paywall(.settings))
                    }
                }
                if app.settings.canBuyPro || e.plan != .free {
                    NavigationLink(value: Route.squad) {
                        CLRow(icon: "person.3.fill", tint: .mint, title: "Squad", subtitle: .verbatim(SettingsSummary.squadLine(app: app)))
                    }
                    .buttonStyle(.pressable)
                }
                if app.settings.canBuyPro, e.plan == .free || e.plan == .pass {
                    NavigationLinkRow(icon: "graduationcap", tint: .sun, title: "Exam Pass",
                                      subtitle: "\(store.price(for: .examPass).display) for 30 days of Pro. Doesn't renew.") {
                        app.router.present(.examPass(examID: app.upcomingExams().first?.id))
                    }
                }
                RestorePurchasesRow()
            }
            HelpLink()
                .padding(.top, 6)
                .padding(.horizontal, 6)
        }
        .task { await store.loadProducts() }
    }

    private func planCard(_ e: Entitlement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CLEyebrow(text: "Your plan", color: CLColor.tangerineInk)
            Text(planName(e)).clFont(.brandTitle(30)).foregroundStyle(CLColor.ink)
            Text(planDetail(e))
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if let reminder = trialReminder(e) {
                Label(reminder, systemImage: "bell")
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CLColor.sunSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 4)
            }
        }
        .clCard()
        .accessibilityElement(children: .combine)
    }

    /// "7 days free, then $49.99 a year", or just the price once the free week was used.
    private var yearlyLine: String {
        let price = store.price(for: .yearly).display
        guard let days = store.trialDays(for: .yearly) else { return "\(price) a year" }
        return "\(days) days free, then \(price) a year"
    }

    private func planName(_ e: Entitlement) -> String {
        switch e.plan {
        case .free: "Free"
        case .pro: "Capling Pro"
        case .squad: "Squad"
        case .pass: "Exam Pass"
        }
    }

    private func planDetail(_ e: Entitlement) -> String {
        let long = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        switch e.plan {
        case .free:
            guard app.settings.canBuyPro else { return String(localized: PaywallCopy.noPurchaseDetail) }
            return "Unlimited reviews and cards you make yourself, with free AI limits each day and week."
        case .pass:
            guard let end = e.expiresAt else { return "Every Pro feature for 30 days. It doesn't renew." }
            return "Every Pro feature until \(end.formatted(long)). It doesn't renew, so there's nothing to cancel."
        case .pro, .squad:
            let who = e.plan == .squad && e.option != .squad ? "On a friend's Squad: every Pro feature." : "Every feature, for every class."
            guard let end = e.expiresAt else { return who }
            if e.isFreeTrial { return "\(who) Your free week ends on \(end.formatted(long))." }
            if e.option == nil { return "\(who) Your seat runs until \(end.formatted(long))." }
            return "\(who) The current period ends on \(end.formatted(long)), and renews then unless you cancel."
        }
    }

    private func trialReminder(_ e: Entitlement) -> String? {
        guard e.isFreeTrial, let end = e.expiresAt, let when = store.reminderDate(forTrialEnding: end) else { return nil }
        return "We'll remind you on \(when.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())), before you're charged."
    }
}

/// A row that opens something (a sheet or a page): an icon, a title, a line, a chevron.
struct NavigationLinkRow: View {
    let icon: String
    var tint: CourseColor = .sky
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?
    let action: () -> Void

    var body: some View {
        Button {
            CLHaptics.tap()
            action()
        } label: {
            CLRow(icon: icon, tint: tint, title: title, subtitle: subtitle)
        }
        .buttonStyle(.pressable)
    }
}
