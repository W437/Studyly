import SwiftUI

/// The day's one card under the band (`TodayHeroContent` says what it holds): the exam it is for and its day as a chip that opens the
/// exam ("Chem 110 Quiz · Tue ›"), with its readiness beside it as one ring ("41% ready"); the title; at most one short line; the
/// day's one button; and "Why these?", with "Study out loud" beside it on a day with something to study: a quiet way into the same
/// session, not a second job.
///
/// - Large text or a small phone: the ring goes under the chip when the row won't hold both, the chip wraps rather than cutting its
///   words, and a long practice button shortens to "Practice · 5 min".
/// - VoiceOver: the chip (a button: "Chem 110 Quiz, Tuesday", "Opens the exam"), "41 percent ready", the title (a header), the line,
///   the button, "Why these?".
struct TodayDayCard: View {
    let content: TodayHeroContent
    var perform: (TodayHeroContent.Action) -> Void
    var onWhy: () -> Void
    /// A tap on the chip: the exam's page, or a new exam.
    var onChip: (TodayHeroContent.Chip.Link) -> Void = { _ in }
    /// Study out loud, on a day that has a session to say. Nil: no link.
    var onOutLoud: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The title's mark and the ring grow with the text they sit beside.
    @ScaledMetric(relativeTo: .title2) private var symbolSize: CGFloat = 19
    @ScaledMetric(relativeTo: .subheadline) private var ringSize: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if content.chip != nil || content.readiness != nil { chipRow }
            VStack(alignment: .leading, spacing: 6) {
                title
                if let line = content.line {
                    Text(verbatim: line)
                        .clFont(.callout)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            buttons
        }
        .clCard()
        .accessibilityElement(children: .contain)
    }

    // MARK: The chip and the ring

    /// The chip and the ring on one row (on a small phone with the ring's words a size smaller), or the ring under the chip when one
    /// row won't hold them.
    @ViewBuilder private var chipRow: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) { chipRowParts(spaced: false) }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 6) { chipRowParts(spaced: true) }
                HStack(alignment: .center, spacing: 6) { chipRowParts(spaced: true, small: true) }
                VStack(alignment: .leading, spacing: 10) { chipRowParts(spaced: false) }
            }
        }
    }

    @ViewBuilder private func chipRowParts(spaced: Bool, small: Bool = false) -> some View {
        if let chip = content.chip { TodayChip(chip: chip, onTap: onChip) }
        if spaced { Spacer(minLength: 4) }
        if let readiness = content.readiness { ring(readiness, small: small) }
    }

    /// One ring and "41% ready": the chip's exam, as of now.
    private func ring(_ value: Double, small: Bool = false) -> some View {
        HStack(spacing: small ? 5 : 7) {
            ReadinessRing(value: value, size: small ? ringSize * 0.85 : ringSize, lineWidth: max(4, ringSize / 6), showsLabel: false)
            Text(verbatim: TodayCopy.ready(value))
                .clFont(small ? .footnoteEmphasis : .subheadlineEmphasis)
                .foregroundStyle(CLColor.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: TodayCopy.readySpoken(value)))
    }

    // MARK: The title and the buttons

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

    private var buttons: some View {
        VStack(spacing: 4) {
            ForEach(Array(content.actions.enumerated()), id: \.offset) { _, action in
                Button { perform(action) } label: {
                    if let short = action.shortTitle {
                        FittingLabel(titles: [String(localized: action.title), String(localized: short)], systemImage: action.systemImage)
                    } else {
                        Label(action.title, systemImage: action.systemImage)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
                .buttonStyle(.cl(action.prominent ? .primary : .soft, size: action.prominent ? .regular : .medium))
                .accessibilityLabel(action.spoken.map { Text($0) } ?? Text(action.title))
                .padding(.bottom, 4)
            }
            if content.showsWhy {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { quietLinks }
                    VStack(spacing: 0) { quietLinks }
                }
                .padding(.top, -4)
                .padding(.bottom, -8)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder private var quietLinks: some View {
        Button(action: onWhy) {
            Text("Why these?")
                .clFont(.subheadlineEmphasis)
                .foregroundStyle(CLColor.skyInk)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Says why today's questions were picked")
        if let onOutLoud {
            Button(action: onOutLoud) {
                Label { Text(OutLoudCopy.title).lineLimit(1) } icon: { Image(systemName: "waveform") }
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.skyInk)
                    .frame(maxWidth: .infinity, minHeight: CLMetrics.minHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Cap asks today's questions out loud and you answer with your voice")
        }
    }
}

/// The day card's chip: a soft pill with its mark, its words and, when it leads somewhere, a small chevron. A 44-point target around a
/// 30-point pill; at the large text sizes it wraps rather than cutting the exam's name.
struct TodayChip: View {
    let chip: TodayHeroContent.Chip
    var onTap: (TodayHeroContent.Chip.Link) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The mark and the chevron grow with the words.
    @ScaledMetric(relativeTo: .footnote) private var markSize: CGFloat = 11
    @ScaledMetric(relativeTo: .footnote) private var chevronSize: CGFloat = 9

    var body: some View {
        if let link = chip.link {
            Button { onTap(link) } label: { pill }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text(verbatim: chip.spoken ?? chip.text))
                .accessibilityHint(link == .addExam ? Text("Adds the date of your next exam") : Text("Opens the exam"))
        } else {
            pill.accessibilityElement(children: .combine)
        }
    }

    private var pill: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: chip.symbol)
                .font(.system(size: markSize, weight: .bold))
                .accessibilityHidden(true)
            // "Quiz · Tue" holds together, so a wrapped chip never starts or ends a line on the dot.
            Text(verbatim: chip.text.replacingOccurrences(of: " · ", with: "\u{00A0}·\u{00A0}"))
                .clFont(.footnoteEmphasis)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
            if chip.link != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: chevronSize, weight: .bold))
                    .opacity(0.7)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .frame(minHeight: 30)
        .foregroundStyle(chip.tone == .eve ? CLColor.sunInk : CLColor.skyInk)
        .background(chip.tone == .eve ? CLColor.sunSoft : CLColor.skySoft, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        // A 44-point target that doesn't make the row taller.
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .padding(.vertical, -7)
    }
}
