import StoreKit
import SwiftUI

/// What the paywall reports when it closes, so the place that opened it decides what comes next.
enum PaywallOutcome: Equatable, Sendable {
    case declined
    case purchased(PlanOption)
}

/// Set by a host that embeds the paywall (onboarding) instead of presenting it as a sheet. Without one, the
/// paywall dismisses itself, and a decline 8 to 21 days before the next exam opens the Exam Pass offer (`ExamPassOffer`).
struct PaywallFinishAction {
    let handler: @MainActor (PaywallOutcome) -> Void
    @MainActor func callAsFunction(_ outcome: PaywallOutcome) { handler(outcome) }
}

extension EnvironmentValues {
    @Entry var paywallFinish: PaywallFinishAction?
}

// MARK: - Nothing to buy

/// What an account under 13 sees wherever Pro would be offered (`AppSettings.canBuyPro`): the plain reason, what stays free, and Restore. No prices and
/// no purchase. A restore that finds one turns the paywall into the purchased screen, which says what Pro can't do here.
struct NoPurchaseView: View {
    var primaryTitle: LocalizedStringResource = "Done"
    let onPrimary: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CapView(pose: .wave, size: 170, decorative: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                Text(PaywallCopy.noPurchaseTitle)
                    .clFont(.brandTitle(30))
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 16)
                Text(PaywallCopy.noPurchaseDetail)
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                AlwaysFreeCard()
                    .padding(.top, 20)
                SettingsGroup { RestorePurchasesRow() }
                    .padding(.top, 8)
                HelpLink(alignment: .center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 12)
            .frame(maxWidth: CLMetrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaBar(edge: .bottom) {
            Button(action: onPrimary) { Text(primaryTitle) }
                .buttonStyle(.cl(.primary))
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 10)
        }
        .background(CLColor.background.ignoresSafeArea())
    }
}

/// The line under Pro's rows, and on the purchased screen, when Pro can't do its work as things stand (`PaywallCopy.proCaveat`).
struct ProCaveatLine: View {
    let text: LocalizedStringResource

    var body: some View {
        Label { Text(text) } icon: { Image(systemName: "info.circle") }
            .clFont(.footnoteEmphasis)
            .foregroundStyle(CLColor.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Hero

/// The night hero: stars, Cap asleep on a stack of index cards, and the close button. It stretches when the
/// page is pulled down.
struct PaywallHero: View {
    var height: CGFloat = 200
    /// The safe area above the hero when the paywall runs edge to edge (onboarding); 0 in a sheet.
    var topInset: CGFloat = 0
    var closeLabel: String
    var onClose: () -> Void

    var body: some View {
        GeometryReader { geo in
            let stretch = max(0, geo.frame(in: .scrollView).minY)
            ZStack(alignment: .bottom) {
                CLColor.night
                NightSky(count: 14)
                CapView(pose: .sleep, size: 210, idle: .doze)
                    .offset(y: 10)
            }
            .frame(width: geo.size.width, height: geo.size.height + stretch)
            .offset(y: -stretch)
        }
        .frame(height: height + topInset)
        .overlay(alignment: .topLeading) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(closeLabel)
            .padding(.top, topInset + 8)
            .padding(.leading, 14)
        }
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Bottom bar

extension View {
    /// The pinned purchase bar's ground: opaque behind the controls, fading in over the last few points so the
    /// plans scroll away under it cleanly (the system edge blur lets coloured cards smudge through the terms).
    func paywallBarBackground() -> some View {
        background {
            LinearGradient(stops: [.init(color: CLColor.background.opacity(0), location: 0),
                                   .init(color: CLColor.background, location: 0.16)],
                           startPoint: .top, endPoint: .bottom)
                .padding(.top, -18)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - Benefits

struct PaywallBenefitRow: View {
    let symbol: String
    let text: LocalizedStringResource

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CLColor.tangerineInk)
                .frame(width: 32, height: 32)
                .background(CLColor.tangerineSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            Text(text)
                .clFont(.bodyEmphasis)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Plan card

/// One of the three plans: a radio, the name and its detail line, the price, and an optional flag on the edge.
struct PlanCard: View {
    let option: PlanOption
    let price: PlanPrice
    let trialDays: Int?
    let selected: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The price grows with Dynamic Type like the words around it.
    @ScaledMetric(relativeTo: .title3) private var priceSize: CGFloat = 19

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 16)
                .padding(.top, flag == nil ? 16 : 20)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CLColor.surface, in: shape)
                .overlay(shape.strokeBorder(selected ? CLColor.tangerine : CLColor.surface3, lineWidth: 2.5))
                .overlay(alignment: .topLeading) { flagView.offset(x: 18, y: -11) }
                .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 24, style: .continuous) }

    private var flag: String? { PaywallCopy.flag(for: option, trialDays: trialDays) }

    @ViewBuilder private var content: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        layout {
            HStack(spacing: 14) {
                radio
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title).clFont(.headline).foregroundStyle(CLColor.ink)
                    Text(PaywallCopy.detail(for: option, price: price))
                        .clFont(.footnote)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                Text(price.display).clFont(.number(priceSize, .heavy)).foregroundStyle(CLColor.ink)
                Text(option.unitLabel).clFont(.caption).fontWeight(.semibold).foregroundStyle(CLColor.ink2)
            }
            .padding(.leading, typeSize.isAccessibilitySize ? 38 : 0)
        }
    }

    private var radio: some View {
        ZStack {
            Circle().strokeBorder(selected ? CLColor.tangerine : CLColor.surface3, lineWidth: 2.5)
            Circle().fill(CLColor.tangerine).padding(6).scaleEffect(selected ? 1 : 0.2).opacity(selected ? 1 : 0)
        }
        .frame(width: 24, height: 24)
        .animation(CLMotion.pop, value: selected)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var flagView: some View {
        if let flag {
            Text(flag)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CLColor.onFill)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(option == .squad ? CLColor.sky : CLColor.tangerine, in: Capsule())
                .lineLimit(1)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityText: String {
        var parts = [option.title, "\(price.display) \(option.unitLabel)", PaywallCopy.detail(for: option, price: price)]
        if let flag { parts.append(flag) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Trial timeline

/// Today, the reminder, the first charge: an honest timeline for a free trial.
struct TrialTimeline: View {
    let steps: [PaywallCopy.TimelineStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 14) {
                    node(index: index, symbol: step.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title).clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink)
                        Text(step.detail)
                            .clFont(.subheadline)
                            .foregroundStyle(CLColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, index == steps.count - 1 ? 0 : 16)
                }
                .background(alignment: .topLeading) {
                    if index < steps.count - 1 {
                        Rectangle().fill(CLColor.surface3).frame(width: 2).padding(.top, 30).padding(.leading, 14)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: CLRadius.card, style: .continuous))
    }

    private func node(index: Int, symbol: String) -> some View {
        let fill: Color = [CLColor.tangerine, CLColor.sun, CLColor.sky][min(index, 2)]
        return Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(CLColor.onFill)
            .frame(width: 30, height: 30)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Manage subscription

/// "Manage subscription": the App Store's own sheet. The Settings lane can drop this into the Subscription page.
struct ManageSubscriptionButton: View {
    var title = "Manage subscription"
    @State private var showing = false

    var body: some View {
        Button(title) { showing = true }
            .manageSubscriptionsSheet(isPresented: $showing)
    }
}
