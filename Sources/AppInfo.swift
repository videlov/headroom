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
}

enum Log {
    static let app = Logger(subsystem: "io.github.videlov.headroom", category: "app")
}
