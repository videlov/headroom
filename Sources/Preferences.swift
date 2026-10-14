import Foundation
import ServiceManagement

/// UserDefaults keys.
enum DefaultsKey {
    static let usageNotifications = "usage_notifications_enabled"
    static let statusNotifications = "status_notifications_enabled"
    static let openAtLogin = "open_at_login"
    static let shortcutEnabled = "shortcut_enabled"
    static let refreshInterval = "refresh_interval_minutes"
    static let appearanceMode = "appearance_mode"
    static let lastNotifiedThreshold = "last_notified_threshold"
    static let trackedComponents = "tracked_component_ids"
    static let lastEffectiveIndicator = "last_effective_indicator"
    static let updateSeenVersion = "update_seen_version"
    static let updateSeenAt = "update_seen_at"
    static let messageSeenID = "message_seen_id"
    static let messageSeenAt = "message_seen_at"
    static let dismissedMessageID = "dismissed_message_id"
    static let dismissedUpdateVersion = "dismissed_update_version"
    static let lastNotifiedUpdateVersion = "last_notified_update_version"
    static let lastShownMessageID = "last_shown_message_id"
}

enum AppearanceMode: String {
    case system, dark, light
}

/// The settings in the popup's Settings panel. Changes are saved right away; the app
/// delegate applies the ones with side effects (timer, shortcut, appearance).
@MainActor
final class Preferences: ObservableObject {
    static let refreshIntervalChoices = [1, 2, 3, 5, 10, 15, 30, 60]

    @Published var usageNotificationsEnabled: Bool {
        didSet { defaults.set(usageNotificationsEnabled, forKey: DefaultsKey.usageNotifications) }
    }
    @Published var statusNotificationsEnabled: Bool {
        didSet { defaults.set(statusNotificationsEnabled, forKey: DefaultsKey.statusNotifications) }
    }
    @Published var shortcutEnabled: Bool {
        didSet { defaults.set(shortcutEnabled, forKey: DefaultsKey.shortcutEnabled) }
    }
    @Published var refreshIntervalMinutes: Int {
        didSet { defaults.set(refreshIntervalMinutes, forKey: DefaultsKey.refreshInterval) }
    }
    @Published var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: DefaultsKey.appearanceMode) }
    }
    /// Registers or removes the login item. At launch it reflects the real state in macOS.
    @Published var openAtLogin: Bool {
        didSet {
            guard openAtLogin != oldValue else { return }
            Self.setLoginItem(openAtLogin)
            defaults.set(openAtLogin, forKey: DefaultsKey.openAtLogin)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        usageNotificationsEnabled = defaults.object(forKey: DefaultsKey.usageNotifications) as? Bool ?? true
        statusNotificationsEnabled = defaults.object(forKey: DefaultsKey.statusNotifications) as? Bool ?? true
        shortcutEnabled = defaults.object(forKey: DefaultsKey.shortcutEnabled) as? Bool ?? true
        let interval = defaults.integer(forKey: DefaultsKey.refreshInterval)
        refreshIntervalMinutes = interval > 0 ? interval : 1
        appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: DefaultsKey.appearanceMode) ?? "") ?? .system
        if #available(macOS 13.0, *) {
            openAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            openAtLogin = defaults.bool(forKey: DefaultsKey.openAtLogin)
        }
    }

    static func setLoginItem(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}
