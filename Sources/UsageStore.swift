import Foundation

/// Why the latest usage fetch failed.
enum UsageProblem: Equatable {
    case cookieRejected               // claude.ai answered 401 or 403: the session has ended
    case rateLimited(until: Date)     // claude.ai answered 429; automatic refreshes wait until then
    case unreachable                  // no connection or a timeout
    case failed(String)               // anything else, as a sentence for the popup
}

/// What the menu bar item shows.
enum MenuBarState: Equatable {
    case noData                       // gray symbol, no number: no cookie yet, or no answer yet
    case cookieRejected               // gray symbol and "!"
    case stale(percent: Int)          // gray symbol and the last known session percentage
    case current(percent: Int, fullest: Int)   // session percentage, colored by the fullest limit
}

/// Claude usage for the popup and the menu bar, refreshed from claude.ai.
@MainActor
final class UsageStore: ObservableObject {
    /// nil until the first successful fetch.
    @Published private(set) var usage: UsageSnapshot?
    @Published private(set) var extra = ExtraUsage()
    @Published private(set) var freeCreditsMinor = 0
    @Published private(set) var currency = "USD"
    @Published private(set) var limitResets = LimitResets()
    @Published private(set) var lastUpdated = Date()
    @Published private(set) var cookie: String
    /// Why the latest fetch failed; nil after a success.
    @Published private(set) var problem: UsageProblem?
    /// A short note about the cookie panel, such as "Cookie saved, fetching...".
    @Published var notice: String?

    var hasCookie: Bool { !cookie.isEmpty }
    var hasCreditUsage: Bool { extra.spentMinor > 0 }

    private let prefs: Preferences
    private var organization: (cookie: String, id: String)?   // so /api/bootstrap runs once per cookie
    private var refreshTask: Task<Void, Never>?
    private var refreshID = 0
    private var backoffMinutes = 0
    private var lastAlertThreshold: Int

    private static let alertThresholds = [25, 50, 75, 90]

    /// `cookie` overrides the Keychain, for tests.
    init(prefs: Preferences, cookie: String? = nil) {
        self.prefs = prefs
        self.cookie = cookie ?? CookieStore.read() ?? ""
        lastAlertThreshold = UserDefaults.standard.integer(forKey: DefaultsKey.lastNotifiedThreshold)
    }

    // MARK: State

    /// The last fetch failed and the data is older than two refresh intervals.
    func isStale(now: Date = Date()) -> Bool {
        guard usage != nil, problem != nil else { return false }
        return now.timeIntervalSince(lastUpdated) > 2 * 60 * Double(prefs.refreshIntervalMinutes)
    }

    func menuBarState(now: Date = Date()) -> MenuBarState {
        if problem == .cookieRejected { return .cookieRejected }
        guard let usage else { return .noData }
        if isStale(now: now) { return .stale(percent: usage.session.percent) }
        return .current(percent: usage.session.percent, fullest: usage.fullestPercent)
    }

    // MARK: Refresh

    /// Fetches usage unless a fetch is already running. Timers don't fetch while claude.ai
    /// rejects the cookie or asks to slow down; `force` (Refresh, a new cookie) does.
    func refresh(force: Bool = false) {
        guard refreshTask == nil else { return }
        if !force {
            if problem == .cookieRejected { return }
            if case .rateLimited(let until)? = problem, Date() < until { return }
        }
        refreshID += 1
        let id = refreshID
        refreshTask = Task { [weak self] in
            await self?.performRefresh()
            if self?.refreshID == id { self?.refreshTask = nil }
        }
    }

    private func restartRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        refresh(force: true)
    }

    private func performRefresh() async {
        guard hasCookie else { return }   // the popup asks for one
        let api = ClaudeAPI(cookie: cookie)
        let org: String
        do {
            org = try await organizationID(api)
        } catch {
            if !Task.isCancelled { fail(error) }
            return
        }
        // Four independent requests; only /usage decides between data and a problem.
        async let usage = Self.capture { try await api.usage(org: org) }
        async let extra = try? api.extraUsage(org: org)
        async let credits = try? api.freeCredits(org: org)
        async let resets = try? api.limitResets(org: org)
        let results = await (usage, extra, credits, resets)
        guard !Task.isCancelled else { return }
        apply(usage: results.0, extra: results.1, credits: results.2, resets: results.3)
    }

    private func organizationID(_ api: ClaudeAPI) async throws -> String {
        if let organization, organization.cookie == api.cookie { return organization.id }
        let id = try await api.organizationID()
        organization = (api.cookie, id)
        return id
    }

    private static func capture<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    /// Applies one refresh. Extra usage, credits and limit resets can each fail on their
    /// own and keep their last values.
    func apply(usage outcome: Result<UsageSnapshot, Error>, extra: ExtraUsage?,
               credits: FreeCredits?, resets: LimitResets?, now: Date = Date()) {
        if let extra {
            self.extra = extra
            currency = extra.currency
        }
        if let credits {
            freeCreditsMinor = credits.remainingMinor
            if let code = credits.currency { currency = code }
        }
        if let resets {
            limitResets = resets
        }
        switch outcome {
        case .success(let snapshot):
            usage = snapshot
            lastUpdated = now
            problem = nil
            notice = nil
            backoffMinutes = 0
            checkAlertThresholds(percent: snapshot.session.percent)
        case .failure(let error):
            fail(error, now: now)
        }
    }

    private func fail(_ error: Error, now: Date = Date()) {
        notice = nil
        switch error as? ClaudeAPI.Failure ?? .network {
        case .http(401), .http(403):
            if problem != .cookieRejected, prefs.usageNotificationsEnabled {
                Notifier.post(title: "Your claude.ai session expired",
                              body: "Paste a fresh session cookie in Headroom to see your usage again.")
            }
            problem = .cookieRejected
        case .rateLimited(let retryAfter):
            // Wait twice the interval, doubling on each 429 up to 30 minutes.
            backoffMinutes = min(max(backoffMinutes * 2, prefs.refreshIntervalMinutes * 2), 30)
            let wait = max(TimeInterval(backoffMinutes * 60), retryAfter ?? 0)
            problem = .rateLimited(until: now.addingTimeInterval(wait))
        case .network:
            problem = .unreachable
        case .http(let status):
            problem = .failed("claude.ai answered with HTTP \(status).")
        case .invalidResponse:
            problem = .failed("claude.ai sent an unexpected answer.")
        case .noOrganization:
            problem = .failed("Couldn't find your claude.ai organization in the cookie.")
        }
    }

    // MARK: Cookie

    func saveCookie(_ value: String) {
        let cookie = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cookie.isEmpty else {
            notice = "Cookie field is empty!"
            return
        }
        CookieStore.save(cookie)
        self.cookie = cookie
        organization = nil
        problem = nil
        backoffMinutes = 0
        restartRefresh()
        notice = "Cookie saved, fetching..."
    }

    func clearCookie() {
        refreshTask?.cancel()
        refreshTask = nil
        CookieStore.delete()
        cookie = ""
        organization = nil
        usage = nil
        extra = ExtraUsage()
        freeCreditsMinor = 0
        limitResets = LimitResets()
        problem = nil
        notice = nil
        backoffMinutes = 0
        setAlertThreshold(0)
    }

    // MARK: Alerts

    /// One alert each time the session passes 25, 50, 75 or 90 %. Lower thresholds re-arm
    /// once usage drops, for example when the 5-hour window resets.
    private func checkAlertThresholds(percent: Int) {
        let reached = Self.alertThresholds.last { $0 <= percent } ?? 0
        if reached > lastAlertThreshold, prefs.usageNotificationsEnabled {
            Notifier.post(title: "Claude Usage Alert",
                          body: "You've reached \(percent)% of your 5-hour session limit")
        }
        setAlertThreshold(reached)
    }

    private func setAlertThreshold(_ value: Int) {
        guard value != lastAlertThreshold else { return }
        lastAlertThreshold = value
        UserDefaults.standard.set(value, forKey: DefaultsKey.lastNotifiedThreshold)
    }

    func sendTestNotification() {
        Notifier.post(title: "Claude Usage Alert",
                      body: "Test notification - You've reached 75% of your 5-hour session limit")
    }
}
