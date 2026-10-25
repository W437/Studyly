import UIKit
import UserNotifications

/// The app delegate, for the two things that must be in place before launch finishes: the notification delegate
/// (so a tap on a notification that launched the app isn't lost) and the bridge that routes App Intent links
/// (Control Center, Siri) into the app. Attached in `CramlessApp` with `@UIApplicationDelegateAdaptor`.
final class CramlessAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        DeepLinks.installIntentBridge()
        return true
    }

    /// A tap on one of our notifications, or its action button: open its link.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier,
              let raw = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: raw) else { return }
        await MainActor.run {
            DeepLinks.installIntentBridge()
            CramlessIntentBridge.open(url)
        }
    }

    /// In the foreground our reminders go to Notification Center quietly (the person is already in the app);
    /// anything else (PurchaseStore's trial reminder) shows as usual.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.identifier.hasPrefix(NotificationPlanner.prefix) ? [.list] : [.banner, .list, .sound]
    }
}
