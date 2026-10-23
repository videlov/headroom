import Foundation

struct BannerButton: Equatable {
    let label: String
    let url: URL?          // opened when clicked; https on github.com only
    let dismisses: Bool    // "action": "dismiss" closes the banner
    let isPrimary: Bool    // "style": "primary"
}

struct AvailableUpdate: Equatable {
    let version: String
    let title: String
    let body: String
    let buttons: [BannerButton]
}

/// A free-form message from the feed's `message` object. It's keyed on `id`, not on the
/// version, so it can go out without a release.
struct Announcement: Equatable {
    let id: String
    let heading: String?
    let title: String
    let body: String
    let buttons: [BannerButton]
    let notify: Bool
    let notificationTitle: String
    let notificationBody: String
}

/// New versions and announcements from the update feed (latest.json in this repository).
@MainActor
final class UpdateStore: ObservableObject {
    enum Banner { case none, message, update }

    @Published private(set) var available: AvailableUpdate?
    @Published private(set) var announcement: Announcement?

    private let defaults: UserDefaults
    private let notify: (_ title: String, _ body: String) -> Void
    private let session: URLSession

    /// `defaults`, `notify` and `session` replace UserDefaults.standard, the notifications and
    /// the network in tests.
    init(defaults: UserDefaults = .standard,
         notify: @escaping (_ title: String, _ body: String) -> Void = Notifier.post(title:body:),
         session: URLSession = HTTP.session) {
        self.defaults = defaults
        self.notify = notify
        self.session = session
    }

    func refresh() {
        Task { await fetch() }
    }

    func fetch() async {
        let request = URLRequest(url: AppInfo.updateFeedURL, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 15)
        guard let (data, _) = try? await session.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Log.app.notice("Update feed unavailable")
            return
        }
        apply(feed: json)
    }

    func apply(feed json: [String: Any]) {
        let now = Date().timeIntervalSince1970

        // Version channel: version, title and description at the top level.
        if let version = json["version"] as? String, let title = json["title"] as? String,
           let body = json["description"] as? String, Self.isNewer(version, than: AppInfo.version) {
            // First-seen times decide which banner wins when both are live.
            if defaults.string(forKey: DefaultsKey.updateSeenVersion) != version {
                defaults.set(version, forKey: DefaultsKey.updateSeenVersion)
                defaults.set(now, forKey: DefaultsKey.updateSeenAt)
            }
            available = AvailableUpdate(version: version, title: title, body: body, buttons: Self.buttons(in: json))
            if defaults.string(forKey: DefaultsKey.lastNotifiedUpdateVersion) != version {
                notify("\(AppInfo.name) \(version) is available", title)
                defaults.set(version, forKey: DefaultsKey.lastNotifiedUpdateVersion)
            }
        } else {
            available = nil
        }

        // Message channel: one notification per id. The very first message seen is only
        // recorded, so installing the app doesn't announce a message that's already old.
        if let message = Self.announcement(in: json) {
            if defaults.string(forKey: DefaultsKey.messageSeenID) != message.id {
                defaults.set(message.id, forKey: DefaultsKey.messageSeenID)
                defaults.set(now, forKey: DefaultsKey.messageSeenAt)
            }
            announcement = defaults.string(forKey: DefaultsKey.dismissedMessageID) == message.id ? nil : message
            let lastShown = defaults.string(forKey: DefaultsKey.lastShownMessageID)
            if lastShown != message.id {
                if lastShown != nil, message.notify {
                    notify(message.notificationTitle, message.notificationBody)
                }
                defaults.set(message.id, forKey: DefaultsKey.lastShownMessageID)
            }
        } else {
            announcement = nil
        }
    }

    /// With a message and an update both live, show the one first seen most recently;
    /// ties go to the update.
    var visibleBanner: Banner {
        let hasUpdate = available != nil && !isUpdateDismissed
        switch (announcement != nil, hasUpdate) {
        case (false, false): return .none
        case (true, false): return .message
        case (false, true): return .update
        case (true, true):
            let updateSeenAt = defaults.double(forKey: DefaultsKey.updateSeenAt)
            return updateSeenAt >= defaults.double(forKey: DefaultsKey.messageSeenAt) ? .update : .message
        }
    }

    /// Dismisses the banner on screen; the other one, if any, shows next.
    func dismissCurrent() {
        if visibleBanner == .message, let id = announcement?.id {
            defaults.set(id, forKey: DefaultsKey.dismissedMessageID)
            announcement = nil
            return
        }
        if let version = available?.version {
            defaults.set(version, forKey: DefaultsKey.dismissedUpdateVersion)
        }
        available = nil
    }

    private var isUpdateDismissed: Bool {
        guard let version = available?.version else { return false }
        return defaults.string(forKey: DefaultsKey.dismissedUpdateVersion) == version
    }

    // MARK: Parsing

    private static func buttons(in json: [String: Any]) -> [BannerButton] {
        if let raw = json["buttons"] as? [[String: Any]] {
            return raw.compactMap { button in
                guard let label = button["label"] as? String, !label.isEmpty else { return nil }
                let url = (button["url"] as? String).flatMap { URL(string: $0) }
                if let url, !isAllowed(url) { return nil }
                return BannerButton(label: label, url: url,
                                    dismisses: button["action"] as? String == "dismiss",
                                    isPrimary: button["style"] as? String == "primary")
            }
        }
        // Older schema: a single download_url gives Download + Later.
        if let url = (json["download_url"] as? String).flatMap({ URL(string: $0) }), isAllowed(url) {
            return [BannerButton(label: "Download", url: url, dismisses: false, isPrimary: true),
                    BannerButton(label: "Later", url: nil, dismisses: true, isPrimary: false)]
        }
        return []
    }

    /// Banner links may only open https pages on github.com.
    nonisolated static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com")
    }

    private static func announcement(in json: [String: Any]) -> Announcement? {
        guard let message = json["message"] as? [String: Any],
              let id = message["id"] as? String, !id.isEmpty else { return nil }
        let title = message["title"] as? String ?? ""
        let body = message["body"] as? String ?? ""
        let notification = message["notification"] as? [String: Any]
        return Announcement(
            id: id,
            heading: message["heading"] as? String,
            title: title,
            body: body,
            buttons: buttons(in: message),
            notify: message["notify"] as? Bool ?? true,
            notificationTitle: notification?["title"] as? String ?? (title.isEmpty ? AppInfo.name : title),
            notificationBody: notification?["body"] as? String ?? body)
    }

    /// Compares dotted version numbers numerically: "1.10" is newer than "1.9".
    nonisolated static func isNewer(_ remote: String, than current: String) -> Bool {
        let r = remote.split(separator: ".").map { Int($0) ?? 0 }
        let c = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(r.count, c.count) {
            let a = i < r.count ? r[i] : 0
            let b = i < c.count ? c[i] : 0
            if a != b { return a > b }
        }
        return false
    }
}
