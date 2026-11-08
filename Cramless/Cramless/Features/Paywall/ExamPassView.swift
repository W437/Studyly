import SwiftUI

/// Exam Pass: every Pro feature for 30 days, one payment, nothing to cancel. Opened from the paywall's link while it is offered (8 to 21
/// days before the next exam, `ExamPassOffer`), from Settings ▸ Subscription and from an exam's page; never after "Continue free".
/// `examID` names the exam (nil: the soonest upcoming one, else the date onboarding was given).
///
/// Opened from the paywall (a `paywallFinish` action is set), it hands a purchase straight back and the paywall celebrates it; on its
/// own it shows `PurchasedView` itself.
struct ExamPassView: View {
    let examID: UUID?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.paywallFinish) private var finish
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var purchased = false
    @State private var note: String?

    private var store: PurchaseStore { app.purchases }
    private var price: PlanPrice { store.price(for: .examPass) }

    var body: some View {
        ZStack {
            if purchased {
                PurchasedView(mode: .purchased(.examPass), primaryTitle: "Done", onPrimary: { close(.purchased(.examPass)) })
                    .transition(.opacity)
            } else if !app.settings.canBuyPro {
                NoPurchaseView(primaryTitle: "Done", onPrimary: { close(.declined) })
            } else {
                offer
            }
        }
        .animation(CLMotion.settle, value: purchased)
        .background(CLColor.background.ignoresSafeArea())
        .task { await store.loadProducts() }
    }

    private var offer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                Text("Exam Pass")
                    .clFont(.brandTitle(28))
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 22)
                Text(subtitle)
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(price.display)
                        .clFont(.number(40, .heavy))
                        .foregroundStyle(CLColor.ink)
                    Text("One time. Doesn't renew, so there's nothing to cancel.")
                        .clFont(.subheadlineEmphasis)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(CLColor.tangerine, lineWidth: 2.5))
                .accessibilityElement(children: .combine)
                .padding(.top, 22)

                VStack(alignment: .leading, spacing: 11) {
                    ForEach(PaywallCopy.benefits(isMinor: app.settings.isMinor).prefix(3)) {
                        PaywallBenefitRow(symbol: $0.symbol, text: $0.text)
                    }
                    if let caveat = PaywallCopy.proCaveat(canBuyPro: app.settings.canBuyPro, cloudAvailable: app.ai.cloudAvailableInThisBuild,
                                                          cloudAllowed: app.hasCloudConsent) {
                        ProCaveatLine(text: caveat)
                    }
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 6) {
                if let note {
                    Label(note, systemImage: "exclamationmark.circle.fill")
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.roseInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                }
                Button(action: buy) {
                    ZStack {
                        Text(PaywallCopy.cta(for: .examPass, price: price, trialDays: nil))
                            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, typeSize.isAccessibilitySize ? 8 : 0)
                            .opacity(store.purchasing == nil ? 1 : 0)
                        if store.purchasing != nil { ProgressView().tint(CLColor.onFill) }
                    }
                }
                .buttonStyle(.cl(.primary))
                .allowsHitTesting(store.purchasing == nil)
                Text(PaywallCopy.fairUse)
                    .clFont(.caption)
                    .foregroundStyle(CLColor.ink3)
                Button("Continue free") { close(.declined) }
                    .buttonStyle(.cl(.ghost, size: .small))
                    .disabled(store.purchasing != nil)
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 10)
            .paywallBarBackground()
        }
        .scrollEdgeEffectHidden(true, for: .bottom)
    }

    /// Cap studying, with the exam the pass is for (its name and day on the chip).
    private var hero: some View {
        ZStack(alignment: .bottom) {
            // Sun on paper in light; a yellow tint over navy turns olive, so dark gets a plain raised surface.
            RoundedRectangle(cornerRadius: CLRadius.card, style: .continuous)
                .fill(scheme == .dark ? CLColor.surface2 : CLColor.sunSoft)
            CapView(pose: .study, size: 170)
                .offset(y: 6)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: CLRadius.card, style: .continuous))
        .overlay(alignment: .topLeading) {
            if let chip = examChip {
                CLPill(text: .verbatim(chip), tone: .tangerine, systemImage: "calendar")
                    .padding(14)
            }
        }
        .padding(.top, 20)
    }

    // MARK: Copy

    private var exam: Exam? {
        if let examID, let exam = app.exam(examID) { return exam }
        return app.upcomingExams().first
    }

    private var examDate: Date? { exam?.date ?? app.settings.nextExamDate }

    private var subtitle: String {
        let through = app.calendar.date(byAdding: .day, value: StoreCatalog.examPassDays, to: app.now) ?? app.now
        return "Every Pro feature for \(StoreCatalog.examPassDays) days, through \(through.formatted(.dateTime.month(.abbreviated).day()))."
    }

    private var examChip: String? {
        guard let examDate else { return nil }
        let day = examDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return exam.map { "\($0.title) · \(day)" } ?? day
    }

    // MARK: Actions

    private func buy() {
        note = nil
        Task {
            switch await store.purchase(.examPass) {
            case .purchased:
                CLHaptics.success()
                // From the paywall, the paywall celebrates it.
                if let finish { finish(.purchased(.examPass)) } else { purchased = true }
            case .pending:
                note = "Waiting for approval. Exam Pass unlocks as soon as it's approved."
            case .cancelled:
                break
            case .failed(let failure):
                note = failure.message
            }
        }
    }

    private func close(_ outcome: PaywallOutcome) {
        if let finish { finish(outcome) } else { dismiss() }
    }
}
