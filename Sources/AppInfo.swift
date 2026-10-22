import Foundation
import os

enum AppInfo {
    static let name = "Headroom"

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// The update feed: latest.json in this repository, served by GitHub.
    static let updateFeedURL = URL(string: "https://raw.githubusercontent.com/videlov/headroom/main/latest.json")!
    static let statusSummaryURL = URL(string: "https://status.claude.com/api/v2/summary.json")!
    static let statusPageURL = URL(string: "https://status.claude.com")!
    static let usageSettingsURL = URL(string: "https://claude.ai/new#settings/usage")!
    /// The page the session cookie steps start from.
    static let usagePageURL = URL(string: "https://claude.ai/settings/usage")!
    /// System Settings → Notifications, with Headroom selected.
    static let notificationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=io.github.videlov.headroom")!
}

enum Log {
    static let app = Logger(subsystem: "io.github.videlov.headroom", category: "app")
}
