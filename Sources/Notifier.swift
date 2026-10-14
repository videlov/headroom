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

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
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
