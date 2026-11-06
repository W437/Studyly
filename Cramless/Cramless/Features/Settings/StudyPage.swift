import SwiftUI

/// Settings ▸ Study: minutes a day, the reminder, quiet hours, how sure Capling keeps you of each card (target
/// retention, 85–95%), and lighter days.
struct StudyPage: View {
    @Environment(AppModel.self) private var app
    /// The slider's value while it moves; written to the settings once it rests.
    @State private var retention: Double = 0.9

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

            SettingsGroup(title: "Reminder", footer: "Capling sends two notifications a day at most, counting exam countdowns, and none during quiet hours.") {
                SettingsToggleRow(title: "Daily reminder", subtitle: "A nudge at your time, when there's something to study",
                                  isOn: Binding(get: { app.settings.reminderMinutes != nil },
                                                set: { app.settings.reminderMinutes = $0 ? 19 * 60 : nil }),
                                  hintOn: "Turns on a daily reminder at 7 PM; you can change the time.",
                                  hintOff: "Turns the daily reminder off. Exam countdowns still come.")
                if let minutes = app.settings.reminderMinutes {
                    TimeRow(title: "Remind me at", minutes: minutes) { app.settings.reminderMinutes = $0 }
                }
            }

            SettingsGroup(title: "Quiet hours", footer: "Nothing arrives between these times. A reminder due then moves just outside them.") {
                TimeRow(title: "From", minutes: app.settings.quietHoursStart) { app.settings.quietHoursStart = $0 }
                TimeRow(title: "Until", minutes: app.settings.quietHoursEnd) { app.settings.quietHoursEnd = $0 }
            }

            CLSectionHeader(title: "How sure you'll be")
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Target").clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                    Spacer()
                    Text(CLFormat.percent(retention)).clFont(.number(22)).foregroundStyle(CLColor.ink)
                        .contentTransition(.numericText(value: retention))
                }
                Slider(value: $retention, in: 0.85...0.95, step: 0.01)
                .tint(CLColor.tangerine)
                // Written once the value rests (a drag or VoiceOver's adjust), so the plan is rebuilt once.
                .task(id: retention) {
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled else { return }
                    commitRetention()
                }
                .accessibilityLabel("Target")
                .accessibilityValue(Text(CLFormat.percent(retention)))
                HStack {
                    Text("Fewer reviews").clFont(.caption).foregroundStyle(CLColor.ink3)
                    Spacer()
                    Text("More reviews").clFont(.caption).foregroundStyle(CLColor.ink3)
                }
                .accessibilityHidden(true)
                Text(Self.retentionText(retention))
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(CLMotion.fade, value: Self.band(retention))
            }
            .clCard()

            CLSectionHeader(title: "Lighter days")
            VStack(alignment: .leading, spacing: 12) {
                EasyDaysPicker(selected: $app.settings.easyDays, calendar: app.calendar)
                Text("On these days, Cap keeps to reviews: no new material, and a shorter session.")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .clCard()

            SettingsGroup(title: "Cap noticed",
                          footer: "One note at a time on Today, three a day at most. Spotting them runs on this iPhone and uses no AI.") {
                ForEach(NoticeKind.live, id: \.self) { kind in
                    SettingsToggleRow(title: NoticeContent.switchTitle(kind),
                                      isOn: Binding(get: { app.settings.notices.allows(kind) },
                                                    set: { app.setNoticeKind(kind, on: $0) }))
                }
            }
        }
        .onAppear { retention = app.settings.targetRetention }
    }

    private func commitRetention() {
        let value = (retention * 100).rounded() / 100
        if value != app.settings.targetRetention { app.settings.targetRetention = value }
    }

    static func band(_ value: Double) -> Int { value < 0.885 ? 0 : value <= 0.915 ? 1 : 2 }

    /// The target in plain words.
    static func retentionText(_ value: Double) -> String {
        let percent = Int((value * 100).rounded())
        let base = "Each card comes back when you're about \(percent)% likely to still know it."
        switch band(value) {
        case 0: return base + " Fewer reviews each day, and you'll forget a little more in between."
        case 1: return base + " The sweet spot for most people: about 90%."
        default: return base + " More reviews each day for a little more certainty. Worth it in exam week."
        }
    }
}

/// A time of day, edited with the system's wheel or compact picker.
private struct TimeRow: View {
    let title: String
    let minutes: Int
    let onChange: (Int) -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        DatePicker(selection: Binding(get: { date }, set: { newValue in
            let parts = app.calendar.dateComponents([.hour, .minute], from: newValue)
            onChange((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }), displayedComponents: .hourAndMinute) {
            Text(title).clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
        }
        .tint(CLColor.tangerine)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: CLMetrics.rowMinHeight)
    }

    private var date: Date {
        app.calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: app.now) ?? app.now
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
