import AppKit
import UserNotifications

/// Schedules system notifications at each countdown's end date.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    struct Pending {
        var id: String
        var fireDate: Date
        var title: String
        var body: String
    }

    /// UNUserNotificationCenter crashes outside an app bundle (e.g. `swift run`), so skip it there.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func requestAuthorization() {
        guard let center else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Replaces any previously scheduled countdown notifications with these.
    func schedule(_ items: [Pending]) {
        guard let center else { return }
        // Every pending request is one of ours, and timer IDs change, so replace them all.
        center.removeAllPendingNotificationRequests()
        for item in items {
            let interval = item.fireDate.timeIntervalSinceNow
            guard interval > 0 else { continue }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            // The app plays its own chime, so the notification stays silent.
            content.sound = nil
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
