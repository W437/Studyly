import StoreKit
import SwiftUI

/// The paywall: the headline, what Pro adds (four rows, then one line on what stays free), and two plans, Yearly (picked, with its free
/// week) and Monthly. `context` says why it opened: a gate names its limit; onboarding and Settings say what Pro does.
///
/// Squad is bought on its own page (`SquadView`). While Exam Pass is offered (8 to 21 days before the next exam, `ExamPassOffer`) a link
/// under the plans opens it over the paywall; "Continue free" never opens another offer. "Continue free" is always on screen (in the
/// bottom bar beside the button), the terms say the price, the reminder before the first charge and how to cancel, the footer has a way
/// to reach a real person, and Terms and Privacy appear only once real URLs exist. An account under 13 is sold nothing (`NoPurchaseView`).
///
/// DEBUG hooks, read once: `CRAMLESS_PAYWALL_PLAN=yearly|monthly` preselects a plan;
/// `CRAMLESS_PAYWALL_STATE=purchasing|pending|cancelled|failed|purchased|restored` shows that state;
/// `CRAMLESS_PAYWALL_TRIAL=0` draws it as if the free week were already used; `CRAMLESS_PAYWALL_SCROLL=plans` scrolls to the plans;
/// `CRAMLESS_PAYWALL_EXAMPASS=link|open` draws the Exam Pass link as if it were offered today (`open`: and opens it).
struct PaywallView: View {
    let context: PaywallContext

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.paywallFinish) private var finish
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var selected: PlanOption = .yearly
    @State private var done: PurchasedView.Mode?
    @State private var note: Note?
    @State private var restoring = false
    @State private var simulatedPurchasing = false
    @State private var trialUsed = false
    /// Exam Pass, opened over the paywall from its link.
    @State private var showsExamPass = false
    /// What Exam Pass ended with, acted on once its sheet has gone.
    @State private var examPassOutcome: PaywallOutcome?
    /// DEBUG: draws the Exam Pass link whatever the exams say.
    @State private var forcesExamPassLink = false
    /// DEBUG: scrolls to "plans" for screenshots.
    @State private var scrollTarget: String?

    struct Note: Equatable {
        enum Tone { case neutral, warning }
        var text: String
        var tone: Tone
    }

    private var store: PurchaseStore { app.purchases }

    var body: some View {
        GeometryReader { outer in
            ZStack {
                if let done {
                    PurchasedView(mode: done, primaryTitle: finish == nil ? "Done" : "Start studying",
                                  onPrimary: { close(after: done) })
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else if store.isPro {
                    PurchasedView(mode: .current, primaryTitle: finish == nil ? "Done" : "Continue",
                                  onPrimary: { close(after: .current) }, onInvite: nil)
                } else if !app.settings.canBuyPro {
                    NoPurchaseView(primaryTitle: finish == nil ? "Done" : "Continue", onPrimary: { close(after: .current) })
                } else {
                    offer(topInset: outer.safeAreaInsets.top)
                        .transition(.opacity)
                }
            }
            .animation(CLMotion.settle, value: done)
        }
        .background(CLColor.background.ignoresSafeArea())
        .task {
            applyDebugHooks()
            await store.loadProducts()
        }
        .sheet(isPresented: $showsExamPass, onDismiss: examPassClosed) {
            ExamPassView(examID: app.upcomingExams().first?.id)
                .environment(\.paywallFinish, PaywallFinishAction { outcome in
                    examPassOutcome = outcome
                    showsExamPass = false
                })
        }
    }

    // MARK: The offer

    private func offer(topInset: CGFloat) -> some View {
        ScrollViewReader { proxy in
            offerScroll(topInset: topInset)
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(CLMotion.settle) { proxy.scrollTo(target, anchor: .top) }
                }
        }
    }

    private func offerScroll(topInset: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                PaywallHero(topInset: topInset, closeLabel: "Continue free", onClose: decline)
                VStack(alignment: .leading, spacing: 0) {
                    Text(PaywallCopy.headline)
                        .clFont(.brandTitle(30))
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 22)
                    Text(PaywallCopy.subline(for: context))
                        .clFont(.callout)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    VStack(alignment: .leading, spacing: 11) {
                        CLEyebrow(text: "With Pro", color: CLColor.tangerineInk)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(PaywallCopy.benefits(isMinor: app.settings.isMinor)) {
                            PaywallBenefitRow(symbol: $0.symbol, text: $0.text)
                        }
                        if let caveat { ProCaveatLine(text: caveat) }
                        StaysFreeLine()
                            .padding(.top, 5)
                    }
                    .padding(.top, 20)
                    VStack(spacing: 16) {
                        ForEach(PlanOption.paywallOptions) { option in
                            PlanCard(option: option, price: store.price(for: option), trialDays: trialDays(for: option),
                                     selected: option == selected) { select(option) }
                                .disabled(isBusy)
                        }
                    }
                    .padding(.top, 26)
                    .id("plans")
                    if offersExamPass {
                        ExamPassLink(price: store.price(for: .examPass)) {
                            CLHaptics.tap()
                            showsExamPass = true
                        }
                        .disabled(isBusy)
                        .padding(.top, 6)
                    }
                    if typeSize.isAccessibilitySize {
                        termsText.padding(.top, 18)
                    }
                    footer.padding(.top, 20)
                }
                .padding(.horizontal, CLSpace.gutter)
                .padding(.bottom, 12)
                .animation(CLMotion.settle, value: selected)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectHidden(true, for: .bottom)
        .safeAreaBar(edge: .bottom) { bottomBar }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            HelpLink(alignment: .center)
            HStack(spacing: 6) {
                Button(restoring ? "Restoring…" : "Restore purchases") { restore() }
                    .disabled(isBusy)
                if let url = StoreCatalog.termsURL {
                    Text("·").accessibilityHidden(true)
                    Link("Terms", destination: url)
                }
                if let url = StoreCatalog.privacyURL {
                    Text("·").accessibilityHidden(true)
                    Link("Privacy", destination: url)
                }
            }
            .clFont(.footnoteEmphasis)
            .foregroundStyle(CLColor.ink2)
            .buttonStyle(.plain)
            .frame(minHeight: CLMetrics.minHitTarget)
        }
        .frame(maxWidth: .infinity)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if let note {
                Label(note.text, systemImage: note.tone == .warning ? "exclamationmark.circle.fill" : "info.circle.fill")
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(note.tone == .warning ? CLColor.roseInk : CLColor.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Button(action: buy) {
                ZStack {
                    Text(cta)
                        // The shared style keeps buttons to one line; the biggest text sizes need two.
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, typeSize.isAccessibilitySize ? 8 : 0)
                        .opacity(isPurchasing ? 0 : 1)
                    if isPurchasing { ProgressView().tint(CLColor.onFill) }
                }
            }
            .buttonStyle(.cl(.primary))
            // Busy, the button stays solid (a faded one shows the plans scrolling underneath) and ignores taps.
            .allowsHitTesting(!isBusy)
            .accessibilityLabel(isPurchasing ? Text("Purchasing") : Text(cta))
            if !typeSize.isAccessibilitySize {
                termsText
            }
            Button("Continue free", action: decline)
                .buttonStyle(.cl(.ghost, size: .small))
                .disabled(isPurchasing)
        }
        .padding(.horizontal, CLSpace.gutter)
        .padding(.top, 10)
        .paywallBarBackground()
        .animation(CLMotion.settle, value: note)
    }

    private var termsText: some View {
        Text(PaywallCopy.terms(for: selected, price: store.price(for: selected), trialDays: trialDays(for: selected)))
            .clFont(.caption)
            .foregroundStyle(CLColor.ink3)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .contentTransition(.opacity)
    }

    // MARK: State

    private var caveat: LocalizedStringResource? {
        PaywallCopy.proCaveat(canBuyPro: app.settings.canBuyPro, cloudAvailable: app.ai.cloudAvailableInThisBuild, cloudAllowed: app.hasCloudConsent)
    }

    /// Exam Pass is offered today (`ExamPassOffer`): a free person 8 to 21 days before the next exam. In onboarding the person's own
    /// answer counts as an exam.
    private var offersExamPass: Bool {
        if forcesExamPassLink { return app.settings.canBuyPro && store.plan == .free }
        var dates = app.upcomingExams().map(\.date)
        if case .onboarding = context, let answered = app.settings.nextExamDate { dates.append(answered) }
        return ExamPassOffer.isEligible(plan: store.plan, canBuyPro: app.settings.canBuyPro, examDates: dates, now: app.now,
                                        calendar: app.calendar)
    }

    private var isPurchasing: Bool { store.purchasing != nil || simulatedPurchasing }
    private var isBusy: Bool { isPurchasing || restoring }

    private var cta: String {
        PaywallCopy.cta(for: selected, price: store.price(for: selected), trialDays: trialDays(for: selected))
    }

    private func trialDays(for option: PlanOption) -> Int? {
        trialUsed ? nil : store.trialDays(for: option)
    }

    // MARK: Actions

    private func select(_ option: PlanOption) {
        guard option != selected else { return }
        CLHaptics.select()
        selected = option
        note = nil
    }

    private func buy() {
        guard !isBusy else { return }
        note = nil
        let option = selected
        Task {
            let outcome = await store.purchase(option)
            switch outcome {
            case .purchased(let option):
                CLHaptics.success()
                done = .purchased(option)
            case .pending:
                note = Note(text: "Waiting for approval. Pro unlocks as soon as it's approved.", tone: .neutral)
            case .cancelled:
                note = Note(text: "No charge. You can start whenever you're ready.", tone: .neutral)
            case .failed(let failure):
                note = Note(text: failure.message, tone: .warning)
            }
        }
    }

    private func restore() {
        note = nil
        restoring = true
        Task {
            let outcome = await store.restore()
            restoring = false
            switch outcome {
            case .restored(let plan):
                CLHaptics.success()
                done = .restored(plan)
            case .nothingToRestore:
                note = Note(text: "No purchases to restore on this Apple Account.", tone: .neutral)
            case .cancelled:
                break
            case .failed:
                note = Note(text: "Couldn't reach the App Store. Try again in a moment.", tone: .warning)
            }
        }
    }

    /// "Continue free" and the close button: embedded (onboarding), the host goes on; as a sheet, it closes. Never another offer.
    private func decline() {
        if let finish { finish(.declined) } else { dismiss() }
    }

    /// Exam Pass's sheet has gone. A pass bought there is celebrated here; "Continue free" there is "Continue free" here too; a swipe
    /// down comes back to the plans.
    private func examPassClosed() {
        guard let outcome = examPassOutcome else { return }
        examPassOutcome = nil
        switch outcome {
        case .purchased(let option): done = .purchased(option)
        case .declined: decline()
        }
    }

    private func close(after mode: PurchasedView.Mode) {
        if let finish {
            if case .purchased(let option) = mode { finish(.purchased(option)) } else { finish(.declined) }
        } else {
            dismiss()
        }
    }

    // MARK: DEBUG

    private func applyDebugHooks() {
        #if DEBUG
        if let raw = TestHarness.once("CRAMLESS_PAYWALL_PLAN"), let option = PlanOption(rawValue: raw), PlanOption.paywallOptions.contains(option) {
            selected = option
        }
        if TestHarness.value("CRAMLESS_PAYWALL_TRIAL") == "0" { trialUsed = true }
        switch TestHarness.once("CRAMLESS_PAYWALL_STATE") {
        case "purchasing": simulatedPurchasing = true
        case "pending": note = Note(text: "Waiting for approval. Pro unlocks as soon as it's approved.", tone: .neutral)
        case "cancelled": note = Note(text: "No charge. You can start whenever you're ready.", tone: .neutral)
        case "failed": note = Note(text: PurchaseStore.PurchaseFailure.network.message, tone: .warning)
        case "purchased": done = .purchased(selected)
        case "restored": done = .restored(selected.plan)
        default: break
        }
        switch TestHarness.once("CRAMLESS_PAYWALL_EXAMPASS") {
        case "link": forcesExamPassLink = true
        case "open":
            forcesExamPassLink = true
            Task {
                try? await nap(900)
                showsExamPass = true
            }
        default: break
        }
        if let target = TestHarness.once("CRAMLESS_PAYWALL_SCROLL") {
            Task {
                try? await nap(600)
                scrollTarget = target
            }
        }
        #endif
    }
}
