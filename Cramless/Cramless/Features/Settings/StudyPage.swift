import SwiftUI

/// Settings ▸ Study: minutes a day, lighter days and Quiet mode. "Hidden tips" shows only while a kind of Cap's card is switched off (the
/// cards themselves have "Don't show these"). The reminder and quiet hours are in Notifications; how sure you'll be is under More.
struct StudyPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        SettingsScroll(title: "Study") {
            SettingsGroup(title: "Each day",
                          footer: "Cap fits each day's session to this. Near an exam, the plan may ask for a few minutes more.") {
                Stepper(value: $app.settings.dailyMinutes, in: 5...60, step: 5) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily goal").clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                        Text("\(app.settings.dailyMinutes) minutes").clFont(.footnote).foregroundStyle(CLColor.ink2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: CLMetrics.rowMinHeight)
                .accessibilityValue(Text("\(app.settings.dailyMinutes) minutes a day"))
            }

            CLSectionHeader(title: "Lighter days")
            VStack(alignment: .leading, spacing: 12) {
                EasyDaysPicker(selected: $app.settings.easyDays, calendar: app.calendar)
                Text("On these days, Cap keeps to reviews: no new material, and a shorter session.")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .clCard()

            SettingsGroup(title: "Streaks and quests") {
                SettingsToggleRow(title: "Quiet mode",
                                  subtitle: "Hides the flame, quests and badges, and turns sounds off. Your plan, stars and readiness stay.",
                                  isOn: $app.settings.quietMode,
                                  hintOn: "Hides the flame, quests and badges, and turns sounds off.",
                                  hintOff: "Shows the flame, quests and badges again.")
            }

            if !HiddenTipsPage.hidden(app.settings).isEmpty {
                SettingsLinkList(pages: [.hiddenTips])
                    .padding(.top, 18)
            }
        }
    }
}

/// The seven weekdays as round toggles, in the person's week order.
private struct EasyDaysPicker: View {
    @Binding var selected: [Int]
    let calendar: Calendar

    var body: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let names = calendar.standaloneWeekdaySymbols
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { day in
                let on = selected.contains(day)
                Button {
                    CLHaptics.select()
                    if on { selected.removeAll { $0 == day } } else { selected = (selected + [day]).sorted() }
                } label: {
                    Text(symbols[day - 1])
                        .font(.system(.callout, design: .rounded, weight: .bold))
                        .foregroundStyle(on ? CLColor.onFill : CLColor.ink2)
                        .frame(maxWidth: .infinity, minHeight: CLMetrics.minHitTarget)
                        .background(on ? CLColor.mint : CLColor.surface2, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                .animation(CLMotion.pop, value: on)
                .accessibilityLabel(Text(names[day - 1]))
                .accessibilityValue(Text(on ? "Lighter day" : "Normal day"))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
