import SwiftUI

// The band's header pieces (`TodaySkyHero`): the streak pill and the avatar. Below the band are `TodayDayCard`, `TodayQuestsRow`
// and `TodayNoticeCard`.

// MARK: - Header pieces

/// The streak in a glass pill: the flame and the days. Hidden until there's a streak to show.
struct TodayStreakPill: View {
    let streak: StreakState
    let onOpen: () -> Void

    @Environment(\.clReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 5) {
                // The flame has the stage the streak has grown to, and bounces once when the streak grows.
                StreakFlame(stage: StreakStage(days: streak.current), size: 22, bounce: reduceMotion ? nil : streak.current)
                Text("\(streak.current)")
                    .clFont(.number(17, .heavy))
                if streak.freezesAvailable > 0 {
                    Image(systemName: "snowflake")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CLColor.skyInk)
                        .padding(.leading, 3)
                }
            }
            .foregroundStyle(CLColor.tangerineInk)
            .padding(.horizontal, 13)
            .frame(minHeight: 38)
            .glassEffect(.regular.interactive(), in: Capsule())
            .frame(minHeight: CLMetrics.minHitTarget)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(streak.current)-day streak")
        .accessibilityValue(streak.freezesAvailable > 0
            ? "\(streak.freezesAvailable) streak freeze\(streak.freezesAvailable == 1 ? "" : "s") saved" : "")
        .accessibilityHint("Opens your streak")
    }
}

/// The person's initials on tangerine (Night ink: brand fills never take white); opens Settings.
struct TodayAvatar: View {
    let initials: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                Circle().fill(CLColor.tangerine)
                if initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .semibold))
                } else {
                    Text(initials)
                        .clFont(.number(15, .bold))
                }
            }
            .foregroundStyle(CLColor.onFill)
            .frame(width: 38, height: 38)
            .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
            .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Profile and settings")
    }
}
