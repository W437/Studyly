import SwiftUI

/// The top of Today: a short band of your memory sky (`HeroWorld`, `HeroWorldGeometry.band`), edge to edge and up behind the status
/// bar, with the date and a greeting ("Good afternoon, Maya"), the streak and your avatar on it, Cap standing on the shore at the
/// bottom left and "17 stars dimming" at the bottom right. Tap the band (or the pill) and the full sky opens; pull the page down
/// and the sky refreshes.
///
/// At the accessibility text sizes the band is low with only the streak and the avatar on it; the date and the greeting move
/// below it, and Cap steps out, so the words get the whole width.
///
/// VoiceOver reads the greeting, the streak, the avatar, then "Your memory sky" (which opens the sky and has a Refresh action).
struct TodaySkyHero: View {
    let snapshot: TodaySnapshot
    let content: TodayHeroContent
    /// Where everything sits for this screen (`HeroWorldGeometry`).
    let geometry: HeroWorldGeometry
    /// The page's pull, and the refresh it starts.
    let pull: HeroPullModel
    var onOpenSky: () -> Void
    var onStreak: () -> Void
    var onProfile: () -> Void

    @Environment(AppModel.self) private var app
    /// The pill says "Sky refreshed" for a moment after a refresh.
    @State private var showsFresh = false

    private var compact: Bool { geometry.compact }
    private var topInset: CGFloat { geometry.topInset }
    private var opensSky: Bool { content.sky != .outline && !snapshot.sky.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                HeroWorld(scene: snapshot.sky, mode: content.sky, ambient: content.twinkles, geometry: geometry,
                          cap: compact ? nil : content.cap, opensSky: opensSky, pull: pull, onOpenSky: onOpenSky)
                // VoiceOver reads the greeting and the streak first, then the sky.
                header.accessibilitySortPriority(1)
                if opensSky, !compact { starsPill }
            }
            .frame(height: geometry.height)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous))
            .overlay(alignment: .bottom) {
                // A hairline of light along the horizon, so the edge reads in dark mode too.
                UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous)
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

    /// "17 stars dimming ›": what is fading in the sky, and the cue that it opens. For a moment after a refresh it says so instead.
    private var starsPill: some View {
        // A finger opens the sky here; VoiceOver does it from the band itself, so the pill stays hidden from it.
        Button(action: onOpenSky) {
            HStack(spacing: 6) {
                Text(verbatim: showsFresh ? String(localized: "Sky refreshed")
                     : TodayCopy.starsPill(stars: snapshot.sky.starCount, dimming: snapshot.sky.dimCount))
                    .clFont(.footnoteEmphasis)
                    .lineLimit(1)
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
            .contentShape(Rectangle().inset(by: -6))   // a 44-pt target around the 32-pt capsule
        }
        .buttonStyle(.pressable)
        .environment(\.colorScheme, .dark)
        .padding(.trailing, CLSpace.gutter)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .accessibilityHidden(true)
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

    /// The date, and the greeting by the hour.
    private func titles(onSky: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            CLEyebrow(text: .verbatim(CLFormat.longDay(app.now)), color: onSky ? .white.opacity(0.72) : CLColor.ink3)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            Text(verbatim: snapshot.greeting)
                .clFont(.title2)
                .foregroundStyle(onSky ? Color.white : CLColor.ink)
                .lineLimit(onSky ? 2 : nil)
                .minimumScaleFactor(onSky ? 0.85 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
