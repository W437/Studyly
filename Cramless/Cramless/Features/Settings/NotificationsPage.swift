import SwiftUI
import UserNotifications

/// Settings ▸ Notifications: whether Capling may notify (with a button to ask, or to open the iPhone's settings when it was turned off
/// there), the daily reminder and its time, quiet hours, and what else it sends. DEBUG builds list what's planned for the coming days.
///
/// Harness: `CRAMLESS_NOTIFY=on|off|ask` shows that permission state (an unsigned simulator build gets no answer
/// from the notification center, and the page then says it couldn't check).
struct NotificationsPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: UNAuthorizationStatus?
    @State private var couldNotCheck = false
    @State private var asking = false

    var body: some View {
        @Bindable var app = app
        let s = app.settings
        SettingsScroll(title: "Notifications") {
            permission
                .padding(.top, 14)

            SettingsGroup {
                SettingsToggleRow(title: "Daily reminder", subtitle: "When there's something to study",
                                  isOn: Binding(get: { app.settings.reminderMinutes != nil },
                                                set: { app.settings.reminderMinutes = $0 ? 19 * 60 : nil }),
                                  hintOn: "Turns on a daily reminder at 7 PM; you can change the time.",
                                  hintOff: "Turns the daily reminder off. Exam countdowns still come.")
                if let minutes = s.reminderMinutes {
                    TimeRow(title: "Remind me at", minutes: minutes) { app.settings.reminderMinutes = $0 }
                }
            }
            .padding(.top, 18)

            SettingsGroup(title: "Quiet hours", footer: "Nothing arrives between these times. A reminder due then moves just outside them.") {
                TimeRow(title: "From", minutes: s.quietHoursStart) { app.settings.quietHoursStart = $0 }
                TimeRow(title: "Until", minutes: s.quietHoursEnd) { app.settings.quietHoursEnd = $0 }
            }

            SettingsGroup(title: "Also sent",
                          footer: "Two a day at most, an hour apart. If you stop opening Capling, it stops after a week.") {
                kind("graduationcap", .sky, "Exam countdowns", "A week before an exam, and the night before")
                kind("flame", .rose, "Streak", s.quietMode ? "Off while Quiet mode is on"
                     : "At \(QuizContent.timeString(minutes: NotificationPlanner.streakMinutes)) when a streak of 3 days or more isn't done yet")
                kind("bell", .sun, "Free trial", "Two days before a free week ends, so you're never charged by surprise")
                SettingsToggleRow(title: "Cap noticed", subtitle: "In the week before an exam, one a day at most, instead of that day's reminder.",
                                  isOn: $app.settings.notices.notify)
            }
            #if DEBUG
            plannedList
            #endif
        }
        .task(id: scenePhase) { await refresh() }
    }

    // MARK: Parts

    private var permission: some View {
        let (title, detail, icon, tint): (String, String, String, CourseColor) = switch status {
        case .authorized, .provisional, .ephemeral:
            ("Notifications are on", "Capling can remind you and count down to your exams.", "bell.badge.fill", .mint)
        case .denied:
            ("Notifications are off", "They were turned off in your iPhone's settings. Turn them on there to get reminders.", "bell.slash.fill", .rose)
        case .notDetermined:
            ("Capling hasn't asked yet", "Allow notifications to get your reminder and exam countdowns.", "bell", .sun)
        default:
            couldNotCheck
                ? ("Couldn't check notifications", "Your iPhone didn't say whether Capling may notify. You can see it in the iPhone's Settings.", "bell", .sky)
                : ("Checking", "", "bell", .sky)
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                CLIconBadge(systemImage: icon, tint: tint, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).clFont(.headline).foregroundStyle(CLColor.ink)
                    if !detail.isEmpty {
                        Text(detail).clFont(.subheadline).foregroundStyle(CLColor.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            if status == .notDetermined {
                Button(action: ask) {
                    ZStack {
                        Text("Allow notifications").opacity(asking ? 0 : 1)
                        if asking { ProgressView().tint(CLColor.onFill) }
                    }
                }
                .buttonStyle(.cl(.primary, size: .medium))
                .disabled(asking)
            } else if status == .denied || couldNotCheck {
                Button("Open iPhone Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.cl(.soft, size: .medium))
            }
        }
        .clCard()
    }

    private func kind(_ icon: String, _ tint: CourseColor, _ title: LocalizedStringResource,
                      _ detail: LocalizedStringResource) -> some View {
        CLRow(icon: icon, tint: tint, title: title, subtitle: detail) { EmptyView() }
            .accessibilityElement(children: .combine)
    }

    #if DEBUG
    private var plannedList: some View {
        let plan = app.notifications.lastPlan
        return VStack(alignment: .leading, spacing: 0) {
            CLSectionHeader(title: "Planned (debug)")
            if plan.isEmpty {
                Text("Nothing planned. The plan is made at launch and after each change.")
                    .clFont(.footnote).foregroundStyle(CLColor.ink2)
            } else {
                CLList {
                    ForEach(plan) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.kind.rawValue).clFont(.eyebrow).foregroundStyle(CLColor.tangerineInk)
                                Spacer()
                                Text(item.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                                    .clFont(.caption).foregroundStyle(CLColor.ink3)
                            }
                            Text(item.body).clFont(.subheadline).foregroundStyle(CLColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }
    #endif

    // MARK: Actions

    /// Reads the permission. The notification center can fail to answer (an unsigned simulator build), so after a
    /// few seconds the page says it couldn't check instead of waiting forever.
    private func refresh() async {
        #if DEBUG
        if let hook = TestHarness.value("CRAMLESS_NOTIFY") {
            status = hook == "on" ? .authorized : hook == "off" ? .denied : .notDetermined
            return
        }
        #endif
        let answer = await withTaskGroup(of: UNAuthorizationStatus?.self) { group -> UNAuthorizationStatus? in
            group.addTask { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        status = answer
        couldNotCheck = answer == nil
    }

    private func ask() {
        asking = true
        Task {
            let granted = await app.notifications.requestAuthorization()
            await refresh()
            asking = false
            if granted { CLHaptics.success() }
        }
    }
}

/// A time of day, edited with the system's compact picker.
private struct TimeRow: View {
    let title: LocalizedStringResource
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
