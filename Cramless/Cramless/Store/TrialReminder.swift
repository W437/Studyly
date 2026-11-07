import Foundation
import UserNotifications

/// The reminder the paywall promises: two days before a free trial ends ("Day 5"), at the person's reminder time,
/// outside quiet hours. Requests use the `trial.` identifier prefix, which belongs to `PurchaseStore`:
/// `NotificationScheduler` never removes them, and nothing else schedules them.
enum TrialReminder {
    static let identifierPrefix = "trial."
    /// Used when the person has no daily reminder time.
    static let defaultMinutes = 19 * 60

    static func identifier(originalTransactionID: UInt64) -> String {
        "\(identifierPrefix)\(originalTransactionID)"
    }

    /// When to remind: `StoreCatalog.trialReminderLeadDays` calendar days before the day the trial ends, at the
    /// reminder time (7 PM when there is none, or when it falls inside quiet hours). Nil when that moment has
    /// passed or isn't before the trial ends.
    static func fireDate(trialEnds: Date, reminderMinutes: Int?, quietStart: Int, quietEnd: Int,
                         now: Date, calendar: Calendar) -> Date? {
        var minutes = reminderMinutes ?? defaultMinutes
        if isQuiet(minutes, start: quietStart, end: quietEnd) { minutes = defaultMinutes }
        if isQuiet(minutes, start: quietStart, end: quietEnd) { minutes = quietEnd }
        let endDay = calendar.startOfDay(for: trialEnds)
        guard let day = calendar.date(byAdding: .day, value: -StoreCatalog.trialReminderLeadDays, to: endDay),
              let fire = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
              fire > now, fire < trialEnds else { return nil }
        return fire
    }

    /// "Your free week ends Friday. Cancel in two taps, or do nothing to keep Pro."
    static func body(trialEnds: Date, plan: Plan, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        let weekday = formatter.string(from: trialEnds)
        return "Your free week ends \(weekday). Cancel in two taps, or do nothing to keep \(plan.displayName)."
    }

    /// Minutes after midnight inside the quiet window (which may wrap past midnight).
    static func isQuiet(_ minutes: Int, start: Int, end: Int) -> Bool {
        guard start != end else { return false }
        return start < end ? (minutes >= start && minutes < end) : (minutes >= start || minutes < end)
    }

    // MARK: Scheduling

    /// Replaces any trial reminder with one for `fireDate`, or removes them all when `fireDate` is nil.
    static func schedule(identifier: String?, fireDate: Date?, body: String, calendar: Calendar) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let stale = pending.filter { $0.hasPrefix(identifierPrefix) && $0 != identifier }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        guard let identifier, let fireDate else {
            if let identifier { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Capling"
        content.body = body
        content.sound = .default
        content.threadIdentifier = "trial"
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let request = UNNotificationRequest(identifier: identifier, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        do {
            try await center.add(request)
        } catch {
            AppConfig.log.error("trial reminder not scheduled: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Exam Pass is the downsell, offered only to free users and only while the soonest upcoming exam is 8 to 21 days away: early
/// enough for 30 days of Pro to be worth it, never in exam week, on the eve or on the day (`StoreCatalog.examPassQuietDays`).
/// Another exam closer than that keeps it quiet too, whichever exam the person is looking at. Settings ▸ Subscription lists it
/// at any time, as a catalogue the person opened.
enum ExamPassOffer {
    static func isEligible(plan: Plan, canBuyPro: Bool, examDates: [Date], now: Date, calendar: Calendar) -> Bool {
        guard canBuyPro, plan == .free, let soonest = examDates.filter({ $0 > now }).min() else { return false }
        let days = calendar.dayDistance(from: now, to: soonest)
        return days > StoreCatalog.examPassQuietDays && days <= StoreCatalog.examPassWindowDays
    }
}
