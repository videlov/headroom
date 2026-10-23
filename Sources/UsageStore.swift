import Foundation

/// Why the latest usage fetch failed.
enum UsageProblem: Equatable {
    case cookieRejected               // claude.ai answered 401 or 403: the session has ended
    case rateLimited(until: Date)     // claude.ai answered 429; automatic refreshes wait until then
    case unreachable                  // no connection or a timeout
    case failed(String)               // anything else, as a sentence for the popup
}

extension UsageProblem {
    /// In plain words, for the popup and the tooltip. `dataTime` is when the data still on
    /// screen was fetched.
    func message(dataTime: Date?) -> String {
        let showing = dataTime.map { " Showing data from \(Format.time($0))." } ?? ""
        switch self {
        case .cookieRejected:
            return "claude.ai no longer accepts your session cookie. Copy a fresh one from claude.ai."
        case .rateLimited(let until):
            return "claude.ai is limiting requests. Trying again at \(Format.time(until))." + showing
        case .unreachable:
            return "Can't reach claude.ai." + showing
        case .failed(let sentence):
            return sentence + showing
        }
    }
}

/// What the menu bar item shows. While the numbers are current, the fullest weekly limit from
/// 70 % shows as a ring around the symbol (`weekly`, its percentage).
enum MenuBarState: Equatable {
    case noData                       // gray symbol, no number: no cookie yet, or no answer yet
    case cookieRejected               // gray symbol and "!"
    case stale(percent: Int)          // gray symbol and the last known session percentage
    /// The session percentage, in a symbol colored by the session: "6%".
    case current(percent: Int, weekly: Int?)
    /// A limit is used up and extra usage covers it: red symbol and this month's spend.
    case extraUsage(spent: String, weekly: Int?)
    /// A limit is used up and nothing covers it: red symbol and the time until it resets,
    /// "11h 20m"; nil without a reset time. A used-up weekly limit fills the ring in red.
    case waiting(timeLeft: String?, weekly: Int?)
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
    /// A short note about the cookie panel, such as "Session cookie saved, fetching...".
    @Published var notice: String?

    var hasCookie: Bool { !cookie.isEmpty }
    var hasCreditUsage: Bool { extra.spentMinor > 0 }

    /// The end of the saved sessionKey, "…x7Qw": which cookie is saved, without showing it.
    var savedCookieHint: String? {
        guard let key = ClaudeAPI.cookieValue(named: "sessionKey", in: cookie), key.count > 8 else { return nil }
        return "…" + key.suffix(4)
    }

    private let prefs: Preferences
    private let defaults: UserDefaults
    private let notify: (_ title: String, _ body: String) -> Void
    private let session: URLSession
    private var organization: (cookie: String, id: String)?   // so /api/bootstrap runs once per cookie
    private(set) var refreshTask: Task<Void, Never>?   // tests await it
    private var refreshID = 0
    private var backoffMinutes = 0
    private var lastSpentMinor: Int?  // extra usage spend at the last refresh

    // What has been announced, kept across launches.
    private var lastAlertThreshold: Int {
        didSet { save(lastAlertThreshold, was: oldValue, as: DefaultsKey.lastNotifiedThreshold) }
    }
    private var lastWeeklyAlertThreshold: Int {
        didSet { save(lastWeeklyAlertThreshold, was: oldValue, as: DefaultsKey.lastNotifiedWeeklyThreshold) }
    }
    private var chargeAlerted: Bool {   // extra usage charges, while a limit is used up
        didSet { save(chargeAlerted, was: oldValue, as: DefaultsKey.extraChargeNotified) }
    }

    private static let alertThresholds = [25, 50, 75, 90]
    private static let weeklyAlertThresholds = [90, 100]

    /// `defaults`, `cookie`, `notify` and `session` replace UserDefaults.standard, the Keychain,
    /// the notifications and the network in tests.
    init(prefs: Preferences, defaults: UserDefaults = .standard, cookie: String? = nil,
         notify: @escaping (_ title: String, _ body: String) -> Void = Notifier.post(title:body:),
         session: URLSession = HTTP.session) {
        self.prefs = prefs
        self.defaults = defaults
        self.notify = notify
        self.session = session
        self.cookie = cookie ?? CookieStore.read() ?? ""
        lastAlertThreshold = defaults.integer(forKey: DefaultsKey.lastNotifiedThreshold)
        lastWeeklyAlertThreshold = defaults.integer(forKey: DefaultsKey.lastNotifiedWeeklyThreshold)
        chargeAlerted = defaults.bool(forKey: DefaultsKey.extraChargeNotified)
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
        // The ring, from where a limit counts as high.
        let fullestWeekly = usage.fullestWeeklyPercent
        let weekly = fullestWeekly >= UsageLevel.highPercent ? fullestWeekly : nil
        if let blocking = usage.blockingLimit {
            if extra.isAvailable(now: now) {
                return .extraUsage(spent: Format.shortMoney(extra.spentMinor, currency: currency), weekly: weekly)
            }
            let timeLeft = blocking.window.resetsAt.map { Format.countdown(to: $0, now: now) }
            return .waiting(timeLeft: timeLeft, weekly: weekly)
        }
        return .current(percent: usage.session.percent, weekly: weekly)
    }

    /// The menu bar tooltip: what the menu bar shows, in words, then the limits as in the popup.
    func tooltip(now: Date = Date()) -> String {
        guard let usage, problem != .cookieRejected else {
            if let problem { return problem.message(dataTime: nil) }
            return hasCookie ? "Fetching your usage…" : "Set your claude.ai session cookie to see your usage."
        }
        var lines: [String] = []
        if let problem {
            lines.append(problem.message(dataTime: lastUpdated))
        }
        if let blocking = usage.blockingLimit {
            let limits = usage.session.percent >= 100 && usage.weekly.percent >= 100
                ? "Session and weekly limits" : blocking.weekly ? "Weekly limit" : "Session limit"
            if extra.isAvailable(now: now) {
                lines.append("\(limits) reached: Claude now runs on extra usage.")
            } else if let resetsAt = blocking.window.resetsAt {
                lines.append("\(limits) reached: Claude works again in \(Format.countdown(to: resetsAt, now: now)).")
            } else {
                lines.append("\(limits) reached.")
            }
        }
        lines.append(Self.limitLine("Session (5 hour)", usage.session, includeDate: false))
        lines.append(Self.limitLine("Weekly (7 day)", usage.weekly, includeDate: true))
        // The same limits as the popup: Fable only while it's in use.
        if let sonnet = usage.weeklySonnet {
            lines.append(Self.limitLine("Weekly Sonnet (7 day)", sonnet, includeDate: true))
        }
        if let fable = usage.weeklyFable, fable.percent >= 1 {
            lines.append(Self.limitLine("Weekly Fable (7 day)", fable, includeDate: true))
        }
        if extra.isEnabled || hasCreditUsage {
            lines.append("Extra usage\(extra.isEnabled ? "" : " (off)"): \(extraSpend) this month")
        }
        return lines.joined(separator: "\n")
    }

    /// "Weekly (7 day): 85% used · resets on 15 Oct 2026 at 03:59".
    private static func limitLine(_ title: String, _ window: UsageWindow, includeDate: Bool) -> String {
        let resets = window.resetsAt.map { " · resets \(Format.reset($0, includeDate: includeDate))" } ?? ""
        return "\(title): \(window.percent)% used\(resets)"
    }

    /// "EUR 4.64 of EUR 10.00", or "EUR 4.64" without a monthly limit.
    private var extraSpend: String {
        let spent = Format.money(extra.spentMinor, currency: currency)
        return extra.limitMinor > 0 ? "\(spent) of \(Format.money(extra.limitMinor, currency: currency))" : spent
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
        let api = ClaudeAPI(cookie: cookie, session: session)
        let org: String
        do {
            org = try await organizationID(api)
        } catch {
            if !Task.isCancelled { fail(error) }
            return
        }
        // Three independent requests; only /usage decides between data and a problem.
        async let usage = Self.capture { try await api.usage(org: org) }
        async let extra = try? api.extraUsage(org: org)
        async let credits = try? api.freeCredits(org: org)
        let (reply, extraUsage, freeCredits) = await (usage, extra, credits)
        guard !Task.isCancelled else { return }
        apply(usage: reply.map { $0.snapshot }, extra: extraUsage, credits: freeCredits,
              resets: try? reply.get().resets)
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

    /// Applies one refresh. Extra usage and credits can each fail on their own and keep
    /// their last values; the limit resets come with the usage.
    func apply(usage outcome: Result<UsageSnapshot, Error>, extra: ExtraUsage?,
               credits: FreeCredits?, resets: LimitResets?, now: Date = Date()) {
        var charged = false   // the extra usage spend went up since the last refresh
        if let extra {
            charged = lastSpentMinor.map { extra.spentMinor > $0 } ?? false
            lastSpentMinor = extra.spentMinor
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
            checkWeeklyAlerts(snapshot.weekly, now: now)
            checkExtraCharges(snapshot, charged: charged)
        case .failure(let error):
            fail(error, now: now)
        }
    }

    private func fail(_ error: Error, now: Date = Date()) {
        notice = nil
        switch error as? ClaudeAPI.Failure ?? .network {
        case .sessionEnded:
            if problem != .cookieRejected, prefs.usageNotificationsEnabled {
                notify("Your claude.ai session expired",
                       "Paste a fresh session cookie in Headroom to see your usage again.")
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
            problem = .failed("Couldn't find your claude.ai organization in the session cookie.")
        }
    }

    // MARK: Cookie

    /// Saves a pasted cookie and fetches with it; false when the text is empty.
    @discardableResult
    func saveCookie(_ value: String) -> Bool {
        let cookie = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cookie.isEmpty else {
            notice = "Session cookie field is empty!"
            return false
        }
        CookieStore.save(cookie)
        self.cookie = cookie
        organization = nil
        problem = nil
        backoffMinutes = 0
        restartRefresh()
        notice = "Session cookie saved, fetching..."
        return true
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
        lastSpentMinor = nil
        lastAlertThreshold = 0
        lastWeeklyAlertThreshold = 0
        chargeAlerted = false
    }

    // MARK: Alerts

    /// One alert each time the session passes 25, 50, 75 or 90 %. Lower thresholds re-arm
    /// once usage drops, for example when the 5-hour window resets.
    private func checkAlertThresholds(percent: Int) {
        let reached = Self.alertThresholds.last { $0 <= percent } ?? 0
        if reached > lastAlertThreshold, prefs.usageNotificationsEnabled {
            notify("Claude Usage Alert", "You've reached \(percent)% of your 5-hour session limit")
        }
        lastAlertThreshold = reached
    }

    /// One alert when the weekly limit passes 90 % and one when it's used up, saying what
    /// happens until it resets. Both re-arm once it has reset.
    private func checkWeeklyAlerts(_ weekly: UsageWindow, now: Date) {
        let reached = Self.weeklyAlertThresholds.last { $0 <= weekly.percent } ?? 0
        if reached > lastWeeklyAlertThreshold, prefs.usageNotificationsEnabled {
            let resets = weekly.resetsAt.map { Format.reset($0, includeDate: true) }
            if reached < 100 {
                notify("Claude Usage Alert", "You've reached \(weekly.percent)% of your weekly limit."
                       + (resets.map { " It resets \($0)." } ?? ""))
            } else if extra.isAvailable(now: now) {
                notify("Weekly limit reached", "Claude now runs on extra usage: \(extraSpend) spent this month."
                       + (resets.map { " The limit resets \($0)." } ?? ""))
            } else {
                let again = weekly.resetsAt.map { "in \(Format.countdown(to: $0, now: now)), \(Format.reset($0, includeDate: true))" }
                notify("Weekly limit reached", "Claude works again \(again ?? "once it resets").")
            }
        }
        lastWeeklyAlertThreshold = reached
    }

    /// One alert when extra usage starts being charged while a limit is used up. It re-arms
    /// once no limit is used up.
    private func checkExtraCharges(_ snapshot: UsageSnapshot, charged: Bool) {
        guard snapshot.blockingLimit != nil else {
            chargeAlerted = false
            return
        }
        guard charged, !chargeAlerted else { return }
        if prefs.usageNotificationsEnabled {
            notify("Extra usage is being charged", "\(extraSpend) spent this month.")
        }
        chargeAlerted = true
    }

    /// Writes an alert state only when it changes, not on every refresh.
    private func save<T: Equatable>(_ value: T, was old: T, as key: String) {
        if value != old { defaults.set(value, forKey: key) }
    }

    func sendTestNotification() {
        notify("Claude Usage Alert", "Test notification - You've reached 75% of your 5-hour session limit")
    }
}
