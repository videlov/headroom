import Foundation

struct StatusIncident: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String          // investigating | identified | monitoring
    let latestUpdate: String
    let updatedAt: Date?
    let componentIDs: [String]
}

struct StatusComponent: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String          // operational | degraded_performance | partial_outage | major_outage | under_maintenance

    /// What this status adds to the overall indicator.
    var indicator: StatusIndicator {
        switch status {
        case "under_maintenance", "degraded_performance": return .minor
        case "partial_outage": return .major
        case "major_outage": return .critical
        default: return .operational
        }
    }
}

/// How bad things are, mildest first. The raw values are status.claude.com's indicator names.
enum StatusIndicator: String, CaseIterable, Comparable {
    case operational = "none", minor, major, critical

    static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// Claude's service status from status.claude.com, narrowed to the services the user tracks.
@MainActor
final class StatusStore: ObservableObject {
    @Published private(set) var statusDescription = "All systems operational"
    @Published private(set) var incidents: [StatusIncident] = []
    @Published private(set) var components = StatusStore.defaultComponents
    @Published private(set) var trackedIDs: Set<String>
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var hasFetched = false

    private let prefs: Preferences
    private let defaults: UserDefaults
    private let notify: (_ title: String, _ body: String) -> Void
    private let session: URLSession

    /// Shown until the first fetch. Claude for Government isn't tracked by default.
    static let defaultComponents = [
        StatusComponent(id: "c-claude-ai", name: "claude.ai", status: "operational"),
        StatusComponent(id: "c-claude-console", name: "Claude Console (platform.claude.com)", status: "operational"),
        StatusComponent(id: "c-claude-api", name: "Claude API (api.anthropic.com)", status: "operational"),
        StatusComponent(id: "c-claude-code", name: "Claude Code", status: "operational"),
        StatusComponent(id: "c-claude-cowork", name: "Claude Cowork", status: "operational"),
        StatusComponent(id: "c-claude-gov", name: "Claude for Government", status: "operational"),
    ]

    /// `defaults`, `notify` and `session` replace UserDefaults.standard, the notifications and
    /// the network in tests.
    init(prefs: Preferences, defaults: UserDefaults = .standard,
         notify: @escaping (_ title: String, _ body: String) -> Void = Notifier.post(title:body:),
         session: URLSession = HTTP.session) {
        self.prefs = prefs
        self.defaults = defaults
        self.notify = notify
        self.session = session
        if let saved = defaults.array(forKey: DefaultsKey.trackedComponents) as? [String] {
            trackedIDs = Set(saved)
        } else {
            trackedIDs = Set(Self.defaultComponents.map(\.id).filter { $0 != "c-claude-gov" })
        }
    }

    func isTracked(_ id: String) -> Bool {
        trackedIDs.contains(id)
    }

    func toggleTracking(_ id: String) {
        if trackedIDs.contains(id) {
            trackedIDs.remove(id)
        } else {
            trackedIDs.insert(id)
        }
        defaults.set(Array(trackedIDs), forKey: DefaultsKey.trackedComponents)
    }

    var trackedComponents: [StatusComponent] {
        components.filter { trackedIDs.contains($0.id) }
    }

    var affectedComponents: [StatusComponent] {
        trackedComponents.filter { $0.status != "operational" }
    }

    /// Incidents that touch a tracked service, or no service in particular.
    var filteredIncidents: [StatusIncident] {
        incidents.filter { $0.componentIDs.isEmpty || $0.componentIDs.contains(where: trackedIDs.contains) }
    }

    /// The worst status among the tracked services.
    var effectiveIndicator: StatusIndicator {
        trackedComponents.map(\.indicator).max() ?? .operational
    }

    // MARK: Fetch

    func refresh() {
        Task { await fetch() }
    }

    func fetch() async {
        let request = URLRequest(url: AppInfo.statusSummaryURL, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 15)
        guard let (data, _) = try? await session.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        apply(summary: json)
    }

    func apply(summary json: [String: Any]) {
        guard let status = json["status"] as? [String: Any],
              let description = status["description"] as? String else { return }
        let isFirstFetch = !hasFetched

        statusDescription = description
        incidents = (json["incidents"] as? [[String: Any]] ?? []).compactMap(Self.incident)
        let fetched = (json["components"] as? [[String: Any]] ?? []).compactMap(Self.component)
        if !fetched.isEmpty {
            components = fetched
            // First real list: track everything except Claude for Government.
            if defaults.array(forKey: DefaultsKey.trackedComponents) == nil {
                trackedIDs = Set(fetched.filter { !$0.name.localizedCaseInsensitiveContains("Government") }.map(\.id))
                defaults.set(Array(trackedIDs), forKey: DefaultsKey.trackedComponents)
            }
        }
        lastUpdated = Date()
        hasFetched = true

        // Notify when the tracked services' overall status changes, not on the first fetch.
        let effective = effectiveIndicator
        let previous = defaults.string(forKey: DefaultsKey.lastEffectiveIndicator).flatMap(StatusIndicator.init(rawValue:))
        if !isFirstFetch, let previous, previous != effective, prefs.statusNotificationsEnabled {
            if effective == .operational {
                notify("Claude is back online", "All systems operational")
            } else {
                notify("Claude status: \(description)", "Visit status.claude.com for details")
            }
        }
        defaults.set(effective.rawValue, forKey: DefaultsKey.lastEffectiveIndicator)
    }

    private static func incident(_ raw: [String: Any]) -> StatusIncident? {
        guard let id = raw["id"] as? String, let name = raw["name"] as? String,
              let status = raw["status"] as? String,
              status != "resolved", status != "postmortem" else { return nil }
        let latest = (raw["incident_updates"] as? [[String: Any]])?.first
        return StatusIncident(
            id: id,
            name: name,
            status: status,
            latestUpdate: latest?["body"] as? String ?? "",
            updatedAt: JSON.date(latest?["created_at"]) ?? JSON.date(raw["updated_at"]),
            componentIDs: (raw["components"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
    }

    private static func component(_ raw: [String: Any]) -> StatusComponent? {
        guard let id = raw["id"] as? String, let name = raw["name"] as? String,
              let status = raw["status"] as? String else { return nil }
        return StatusComponent(id: id, name: name, status: status)
    }
}
