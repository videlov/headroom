import Foundation
import UserNotifications

/// Local notifications: usage alerts, status changes and new versions.
enum Notifier {
    private static let presenter = Presenter()

    /// Asks for permission once; macOS remembers the answer.
    static func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = presenter
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if !granted {
                Log.app.notice("Notifications not allowed: \(error?.localizedDescription ?? "denied", privacy: .public)")
            }
        }
    }

    /// Whether macOS shows Headroom's notifications. After a dismissed or denied request it
    /// doesn't ask again; only System Settings turns them on.
    static func isAllowed() async -> Bool {
        // A command-line tool, such as the previews, has no notification center.
        guard Bundle.main.bundleIdentifier != nil else { return true }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
            if let error {
                Log.app.notice("Notification not shown: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Shows banners even while the popover, and so the app, is active.
    private final class Presenter: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .sound])
        }
    }
}
