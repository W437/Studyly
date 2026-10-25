import SwiftUI

/// The Exam Pass downsell: offered to a free person who declines the paywall within three weeks of an exam.
/// Every Pro feature for 30 days, one payment, nothing to cancel. `examID` names the exam (nil: the soonest
/// upcoming one, or onboarding's answer to "When's your next big exam?").
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
                PurchasedView(mode: .purchased(.examPass), primaryTitle: finish == nil ? "Done" : "Start studying",
                              onPrimary: { close(.purchased(.examPass)) })
                    .transition(.opacity)
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
                CLEyebrow(text: "Exam Pass", color: CLColor.tangerineInk)
                    .padding(.top, 22)
                Text(title)
                    .clFont(.brandTitle(28))
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 6)
                Text(subtitle)
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(price.display)
                        .clFont(.number(40, .heavy))
                        .foregroundStyle(CLColor.ink)
                    Text("for \(StoreCatalog.examPassDays) days, one time. Doesn't renew.")
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
                    ForEach(PaywallCopy.benefits.prefix(3), id: \.text) {
                        PaywallBenefitRow(symbol: $0.symbol, text: $0.text)
                    }
                }
                .padding(.top, 22)

                Text("Not a subscription, so there's nothing to cancel. Free stays free after the 30 days.")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
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
                        Text("Get Exam Pass for \(price.display)")
                            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, typeSize.isAccessibilitySize ? 8 : 0)
                            .opacity(store.purchasing == nil ? 1 : 0)
                        if store.purchasing != nil { ProgressView().tint(CLColor.onFill) }
                    }
                }
                .buttonStyle(.cl(.primary))
                .allowsHitTesting(store.purchasing == nil)
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

    /// Cap studying, with the exam the pass is for.
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
        if let examID { return app.exam(examID) }
        // Inside onboarding (the host set a finish action) the person's own answer is the exam that matters.
        if finish != nil, app.settings.nextExamDate != nil { return nil }
        return app.upcomingExams().first
    }

    private var examDate: Date? { exam?.date ?? app.settings.nextExamDate }

    private var title: String {
        // The exam's name never breaks across lines ("Chem 110 Quiz", not "Chem / 110 Quiz").
        if let exam { return "Just need it for the \(exam.title.replacingOccurrences(of: " ", with: "\u{00A0}"))?" }
        return examDate == nil ? "Just need it for one exam?" : "Just need it for this exam?"
    }

    private var subtitle: String {
        let through = app.calendar.date(byAdding: .day, value: StoreCatalog.examPassDays, to: app.now) ?? app.now
        var line = "Every Pro feature for \(StoreCatalog.examPassDays) days, through "
            + "\(through.formatted(.dateTime.month(.abbreviated).day()))."
        if let examDate {
            let days = app.calendar.dayDistance(from: app.now, to: examDate)
            if days > 1 { line += " Your exam is in \(days) days." }
        }
        return line
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
                purchased = true
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
