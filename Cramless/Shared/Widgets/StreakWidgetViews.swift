import SwiftUI
import WidgetKit

/// The streak widget: the Lock Screen inline line ("12-day streak · 15 min today") and a circular flame with the
/// count inside today's progress.
struct StreakWidgetView: View {
    var family: WidgetFamily
    var snapshot: WidgetSnapshot?

    var body: some View {
        switch family {
        case .accessoryCircular:
            StreakCircularView(snapshot: snapshot)
        default:
            StreakInlineView(snapshot: snapshot)
        }
    }

    static let url = CramlessLink.streak
}

/// One line of text with a symbol; the system draws it beside the clock.
struct StreakInlineView: View {
    var snapshot: WidgetSnapshot?

    var body: some View {
        let streak = snapshot?.streak.current ?? 0
        Label {
            Text(WidgetCopy.inline(snapshot))
        } icon: {
            Image(systemName: streak > 0 ? "flame" : "sun.max")
        }
    }
}

/// A flame and the streak count inside a ring that fills with today's minutes.
struct StreakCircularView: View {
    var snapshot: WidgetSnapshot?

    var body: some View {
        let s = snapshot
        let goal = max(1, s?.today.goalMinutes ?? 15)
        let done = s?.streak.studiedToday == true ? goal : min(goal, s?.today.doneMinutes ?? 0)
        let count = s?.streak.current ?? 0
        ZStack {
            AccessoryWidgetBackground()
            WidgetRing(value: Double(done) / Double(goal), lineWidth: 5, tint: .primary,
                       track: Color.primary.opacity(0.22))
                .padding(2)
            if count > 0 {
                VStack(spacing: -2) {
                    Image(systemName: s?.streak.studiedToday == true ? "flame.fill" : "flame")
                        .font(.system(size: 13, weight: .bold))
                    Text("\(count)")
                        .font(WidgetFont.number(count > 99 ? 16 : 20))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .widgetAccentable()
                }
                .padding(.horizontal, 8)
            } else {
                Image(systemName: s?.streak.studiedToday == true ? "flame.fill" : "flame")
                    .font(.system(size: 22, weight: .semibold))
                    .widgetAccentable()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(count > 0 ? "\(count)-day streak" : "No streak yet"))
        .accessibilityValue(Text(s?.streak.studiedToday == true ? "Studied today" : "\(done) of \(goal) minutes today"))
    }
}
