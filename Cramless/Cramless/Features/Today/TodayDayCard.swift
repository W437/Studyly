import SwiftUI

/// The day's one card under the band (`TodayHeroContent` says what it holds): who today is for ("For Chem 110 Quiz", "Sun · in 2
/// days"), the topics, why, readiness now and about where today takes it (the dashed ring is a projection), the day's one button and
/// "Why these?".
///
/// - Large text: the rings sit above their words, and the chip wraps.
/// - Differentiate Without Color: the projection ring is dashed, the done card's change has an arrow, every chip has a symbol.
/// - VoiceOver: the chip, the title (a header), the reason, the rings as one sentence ("42 percent ready now, about 52 percent after
///   today, projected"), the button, "Why these?".
struct TodayDayCard: View {
    let content: TodayHeroContent
    var perform: (TodayHeroContent.Action) -> Void
    var onWhy: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The title's mark grows with the text it sits beside.
    @ScaledMetric(relativeTo: .title2) private var symbolSize: CGFloat = 19

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if content.chip != nil || content.when != nil { chipRow }
            VStack(alignment: .leading, spacing: 6) {
                title
                Text(verbatim: content.reason)
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let rings = content.rings { ringsRow(rings) }
            if let line = content.ringLine { ringLine(line) }
            buttons
        }
        .clCard()
        .accessibilityElement(children: .contain)
    }

    // MARK: Pieces

    private var chipRow: some View {
        ReflowStack(verticalAlignment: .center, spacing: 8) {
            if let chip = content.chip {
                ReflowPill(text: .verbatim(chip.text), tone: tone(chip.tone), systemImage: chip.symbol)
            }
            if let when = content.when {
                Text(verbatim: when)
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let symbol = content.titleSymbol {
                Image(systemName: symbol)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(CLColor.tangerineInk)
                    .accessibilityHidden(true)
            }
            Text(verbatim: content.title)
                .clFont(.title2)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// Readiness now, solid, and about where today's session takes it, dashed; at the large text sizes the rings sit above the words.
    private func ringsRow(_ rings: TodayHeroContent.Rings) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ReflowStack(verticalAlignment: .center, spacing: 12) {
                HStack(spacing: 6) {
                    ReadinessRing(value: rings.now, size: 34, lineWidth: 5, showsLabel: false)
                    if let after = rings.after {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CLColor.ink3)
                        ReadinessRing(value: after, size: 34, lineWidth: 5, showsLabel: false, style: .projection)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: TodayCopy.readyNow(rings.now))
                        .clFont(.subheadlineEmphasis)
                        .foregroundStyle(CLColor.ink)
                    if let after = rings.after {
                        Text(verbatim: TodayCopy.afterToday(after))
                            .clFont(.subheadline)
                            .foregroundStyle(CLColor.ink2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if let footnote = rings.footnote {
                Text(verbatim: footnote)
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: TodayCopy.ringsSpoken(now: rings.now, after: rings.after)))
        .accessibilityValue(Text(verbatim: rings.footnote ?? ""))
    }

    /// The done card's exam: "Chem 110 Quiz: 52% ready", "+10% today · 2 days to go".
    private func ringLine(_ line: TodayHeroContent.RingLine) -> some View {
        ReflowStack(verticalAlignment: .center, spacing: 12) {
            ReadinessRing(value: line.value, size: 40, lineWidth: 5, showsLabel: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: line.title)
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.ink)
                let points = Int((line.change * 100).rounded())
                Label {
                    Text(verbatim: line.detail)
                } icon: {
                    Image(systemName: points > 0 ? "arrow.up.right" : points < 0 ? "arrow.down.right" : "minus")
                        .font(.system(size: 11, weight: .bold))
                }
                .labelStyle(.titleAndIcon)
                .clFont(.subheadline)
                .foregroundStyle(points > 0 ? CLColor.mintInk : CLColor.ink2)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        VStack(spacing: 4) {
            ForEach(Array(content.actions.enumerated()), id: \.offset) { _, action in
                Button { perform(action) } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.cl(action.prominent ? .primary : .soft, size: action.prominent ? .regular : .medium))
                .accessibilityLabel(action.spoken.map { Text($0) } ?? Text(action.title))
                .padding(.bottom, 4)
            }
            if content.showsWhy {
                Button(action: onWhy) {
                    Text("Why these?")
                        .clFont(.subheadlineEmphasis)
                        .foregroundStyle(CLColor.skyInk)
                        .frame(maxWidth: .infinity, minHeight: CLMetrics.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Says why today's questions were picked")
                .padding(.top, -4)
                .padding(.bottom, -8)
            }
        }
        .padding(.top, 2)
    }

    private func tone(_ tone: TodayHeroContent.Chip.Tone) -> CLPill.Tone {
        switch tone {
        case .exam: .sky
        case .eve: .sun
        case .done: .mint
        }
    }
}
