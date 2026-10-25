import SwiftUI

/// The top of Today: your memory sky as a world, edge to edge and up behind the status bar, with the date, "Today" and the
/// streak on it, and Cap standing in it (`HeroWorld`). Tap a constellation to look at it and relight it right here, tap the
/// empty sky and it ripples, tilt the phone to look around, pull the page down and the sky refreshes. What it says and offers each
/// day is `TodayHeroContent`.
///
/// At the accessibility text sizes the sky is a 180 pt band with only the streak and the avatar on it; the date and
/// "Today" move below it, and Cap steps out, so the words get the whole width.
struct TodaySkyHero: View {
    let snapshot: TodaySnapshot
    let content: TodayHeroContent
    /// Where everything sits for this screen (`HeroWorldGeometry`).
    let geometry: HeroWorldGeometry
    /// The page's pull, and the refresh it starts.
    let pull: HeroPullModel
    var onOpenSky: () -> Void
    var onRelight: (SkyLayout.Constellation) -> Void
    var onStreak: () -> Void
    var onProfile: () -> Void

    @Environment(AppModel.self) private var app
    @State private var focus: Int?
    /// The pill says "Sky refreshed" for a moment after a refresh.
    @State private var showsFresh = false

    private var compact: Bool { geometry.compact }
    private var topInset: CGFloat { geometry.topInset }
    private var opensSky: Bool { content.sky != .outline && !snapshot.sky.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                HeroWorld(scene: snapshot.sky, mode: content.sky, ambient: content.twinkles, geometry: geometry,
                          cap: compact ? nil : content.cap, opensSky: opensSky, pull: pull, focus: $focus, onOpenSky: onOpenSky,
                          onRelight: { index in
                              let constellations = snapshot.sky.layout.constellations
                              if constellations.indices.contains(index) { onRelight(constellations[index]) }
                          })
                // VoiceOver reads the title and the streak first, then the sky.
                header.accessibilitySortPriority(1)
                if opensSky, !compact, focus == nil { starsTag }
            }
            .frame(height: geometry.height)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34, style: .continuous))
            .overlay(alignment: .bottom) {
                // A hairline of light along the horizon, so the edge reads in dark mode too.
                UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34, style: .continuous)
                    .strokeBorder(.white.opacity(0.07), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            if compact { titles(onSky: false).padding(.horizontal, CLSpace.gutter).padding(.top, 14) }
        }
        .task(id: pull.finished) {
            guard pull.finished > 0, pull.outcome == .fresh else { return }
            // Cap says so himself when he talks; otherwise VoiceOver hears it from here.
            if compact || !CapTouch.shared.talks { AccessibilityNotification.Announcement(String(localized: "Sky refreshed")).post() }
            withAnimation(CLMotion.fade) { showsFresh = true }
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(CLMotion.fade) { showsFresh = false }
        }
    }

    /// "63 stars · 7 dim ›": what the sky holds, and the cue that it opens. For a moment after a refresh it says so instead.
    private var starsTag: some View {
        HStack(spacing: 6) {
            Text(verbatim: showsFresh ? String(localized: "Sky refreshed") : tagText)
                .clFont(.footnoteEmphasis)
                .contentTransition(.opacity)
            Image(systemName: showsFresh ? "sparkle" : "chevron.right")
                .font(.system(size: showsFresh ? 11 : 10, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
        }
        .animation(CLMotion.fade, value: showsFresh)
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .glassEffect(.regular, in: .capsule)
        .environment(\.colorScheme, .dark)
        .padding(.trailing, CLSpace.gutter)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var tagText: String {
        var parts = [String(localized: SkyCopy.stars(snapshot.sky.starCount))]
        if snapshot.sky.dimCount > 0 { parts.append(String(localized: SkyCopy.dim(snapshot.sky.dimCount))) }
        return parts.joined(separator: " · ")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            if !compact { titles(onSky: true) }
            Spacer(minLength: 8)
            pills
        }
        .padding(.horizontal, CLSpace.gutter)
        .padding(.top, topInset + 8)
    }

    private func titles(onSky: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            CLEyebrow(text: .verbatim(CLFormat.longDay(app.now)), color: onSky ? .white.opacity(0.72) : CLColor.ink3)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            Text("Today")
                .clFont(.largeTitle)
                .foregroundStyle(onSky ? Color.white : CLColor.ink)
                .accessibilityAddTraits(.isHeader)
        }
        .allowsHitTesting(false)
    }

    private var pills: some View {
        HStack(spacing: 8) {
            if snapshot.streak.current > 0 { TodayStreakPill(streak: snapshot.streak, onOpen: onStreak) }
            TodayAvatar(initials: snapshot.initials, onOpen: onProfile)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// Under the sky: the day's headline when there is one, its button, and one caption.
struct TodayHeroActions: View {
    let content: TodayHeroContent
    var perform: (TodayHeroContent.Action) -> Void

    /// The headline's mark grows with the text it sits beside.
    @ScaledMetric(relativeTo: .title3) private var symbolSize: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let headline = content.headline {
                HStack(spacing: 8) {
                    if let symbol = content.headlineSymbol {
                        Image(systemName: symbol)
                            .font(.system(size: symbolSize, weight: .semibold))
                            .foregroundStyle(CLColor.tangerineInk)
                            .accessibilityHidden(true)
                    }
                    Text(headline)
                        .clFont(.title3)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            ForEach(Array(content.actions.enumerated()), id: \.offset) { _, action in
                Button { perform(action) } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.cl(action.prominent ? .primary : .soft, size: action.prominent ? .regular : .medium))
            }
            Text(content.caption)
                .clFont(.callout)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 18)
    }
}
