import SwiftUI

/// "Always free": what every account keeps without paying (`PaywallCopy.alwaysFree`), so a price is never read as the price of
/// studying. On the paywall it sits between Pro's rows and the plans; Settings ▸ Subscription and Help show the same card.
struct AlwaysFreeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CLEyebrow(text: "Always free", color: CLColor.mintInk)
                .accessibilityAddTraits(.isHeader)
            ForEach(PaywallCopy.alwaysFree) { row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CLColor.mintInk)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text(row.text)
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CLColor.mintSoft, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(CLColor.mint.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
