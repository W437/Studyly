import Foundation
import OSLog
import UserNotifications

/// Schedules the daily reminder, exam countdowns and the streak nudge (`NotificationPlanner` decides what and when;
/// this applies it to the notification center). `AppModel` calls `reschedule()` at launch, after saves (debounced)
/// and when the reminder settings change; onboarding's reminder step calls `requestAuthorization()`.
///
/// Shared rule with the Store lane: requests whose identifier starts with "trial." belong to PurchaseStore and are
/// never removed here; this only ever touches identifiers starting with "capling.".
@MainActor
final class NotificationScheduler {
    weak var app: AppModel?

    /// The last plan applied (the debug settings page can list it).
    private(set) var lastPlan: [NotificationPlanner.Planned] = []
    private var queue: Task<Void, Never>?
    private static var categoriesRegistered = false

    init(app: AppModel) {
        self.app = app
    }

    /// Plans from the current state and replaces our pending requests with the plan. Cheap; runs in the
    /// background of the main actor, one apply at a time. Inert in unit tests.
    func reschedule() {
        guard let app, app.sideEffectsEnabled else { return }
        let input = planInput(for: app)
        let plan = NotificationPlanner.plan(input, calendar: app.calendar)
        lastPlan = plan
        app.noteNoticePings(input.notices, planned: plan)
        let calendar = app.calendar
        let previous = queue
        queue = Task { @MainActor in
            await previous?.value
            await Self.apply(plan, calendar: calendar)
        }
    }

    /// Asks for permission at a moment that makes sense (onboarding's reminder step). Returns whether granted.
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        await Self.registerCategories()
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.log.notice("notification authorization failed: \(error.localizedDescription, privacy: .public)")
            granted = false
        }
        if granted { reschedule() }
        return granted
    }

    func planInput(for app: AppModel) -> NotificationPlanner.Input {
        NotificationPlanner.Input(now: app.now, reminderMinutes: app.settings.reminderMinutes,
                                  quietStart: app.settings.quietHoursStart, quietEnd: app.settings.quietHoursEnd,
                                  goalMinutes: app.settings.dailyMinutes, today: app.todaySummary(),
                                  streak: app.streak(), exams: app.notificationExams(), quiet: app.settings.quietMode,
                                  notices: app.noticePings())
    }

    // MARK: Applying

    private static func apply(_ plan: [NotificationPlanner.Planned], calendar: Calendar) async {
        let center = UNUserNotificationCenter.current()
        await registerCategories()
        let settings = await center.notificationSettings()
        let allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let stale = NotificationPlanner.staleIdentifiers(pending: pending, planned: allowed ? plan : [])
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        guard allowed else { return }
        for item in plan {
            let content = UNMutableNotificationContent()
            content.body = item.body
            content.sound = .default
            content.categoryIdentifier = item.category
            content.threadIdentifier = item.thread
            content.userInfo = ["url": item.url.absoluteString]
            content.relevanceScore = item.kind.relevance
            content.interruptionLevel = .active
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            do {
                // Adding with an existing identifier replaces that request.
                try await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
            } catch {
                log.notice("notification not scheduled: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The study and exam categories with their one action each. Registered once, merged with whatever else is
    /// registered (PurchaseStore's trial category), since registering replaces the app's whole set.
    static func registerCategories() async {
        guard !categoriesRegistered else { return }
        categoriesRegistered = true
        let start = UNNotificationAction(identifier: startAction, title: "Start session", options: [.foreground],
                                         icon: UNNotificationActionIcon(systemImageName: "play.fill"))
        let plan = UNNotificationAction(identifier: openExamAction, title: "See the plan", options: [.foreground],
                                        icon: UNNotificationActionIcon(systemImageName: "calendar"))
        let ours: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: NotificationPlanner.studyCategory, actions: [start], intentIdentifiers: []),
            UNNotificationCategory(identifier: NotificationPlanner.examCategory, actions: [plan], intentIdentifiers: []),
            UNNotificationCategory(identifier: NotificationPlanner.noticeCategory, actions: [], intentIdentifiers: []),
        ]
        let center = UNUserNotificationCenter.current()
        let existing = await center.notificationCategories()
        let ids = Set(ours.map(\.identifier))
        center.setNotificationCategories(existing.filter { !ids.contains($0.identifier) }.union(ours))
    }

    static let startAction = "capling.start"
    static let openExamAction = "capling.openExam"

    static let log = Logger(subsystem: "com.loopware.Capling", category: "notifications")
}
