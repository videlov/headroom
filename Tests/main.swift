import AppKit
import SwiftUI

// Self-tests for the logic behind the popup and the menu bar. scripts/test.sh compiles
// them with Sources/ (without HeadroomApp.swift, which has @main) and runs them. They
// use a preferences domain of their own and never touch the network or the Keychain.

var checks = 0
var failures = 0

func check(_ condition: Bool, _ what: String, line: Int = #line) {
    checks += 1
    if !condition {
        failures += 1
        print("✗ line \(line): \(what)")
    }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ what: String, line: Int = #line) {
    checks += 1
    if actual != expected {
        failures += 1
        print("✗ line \(line): \(what): got \(actual), expected \(expected)")
    }
}

let suiteName = "io.github.videlov.headroom.tests"

/// The tests' own preferences domain, emptied.
func freshDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

func json(_ text: String) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
}

/// A whole-second date as claude.ai writes dates: "2027-01-15T08:00:00.000000+00:00".
func iso(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date).replacingOccurrences(of: "Z", with: "000+00:00")
}

func makeSnapshot(session: Int, weekly: Int, sessionResets: Date? = nil, weeklyResets: Date? = nil) -> UsageSnapshot {
    UsageSnapshot(session: UsageWindow(percent: session, resetsAt: sessionResets),
                  weekly: UsageWindow(percent: weekly, resetsAt: weeklyResets))
}

/// Collects the notifications a store posts.
final class Inbox {
    private var items: [String] = []

    func post(_ title: String, _ body: String) {
        items.append("\(title) | \(body)")
    }

    /// The notifications since the last call.
    func take() -> [String] {
        defer { items = [] }
        return items
    }
}

let now = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 08:00:00 UTC

@MainActor func testFormatting() {
    checkEqual(Format.countdown(to: now + 90, now: now), "2m", "countdown rounds up to the minute")
    checkEqual(Format.countdown(to: now - 30, now: now), "1m", "countdown is at least 1m")
    checkEqual(Format.countdown(to: now + 45 * 60, now: now), "45m", "minutes")
    checkEqual(Format.countdown(to: now + 3600, now: now), "1h", "whole hours")
    checkEqual(Format.countdown(to: now + 11 * 3600 + 20 * 60, now: now), "11h 20m", "hours and minutes")
    checkEqual(Format.countdown(to: now + 2 * 86400 + 5 * 3600 + 59, now: now), "2d 5h", "days and hours")
    checkEqual(Format.countdown(to: now + 2 * 86400, now: now), "2d", "whole days")
    checkEqual(Format.money(464, currency: "EUR"), "EUR 4.64", "money in euros")
    checkEqual(Format.money(464, currency: "USD"), "$4.64", "money in dollars")
    checkEqual(Format.shortMoney(464, currency: "EUR"), "€4.64", "short money uses the symbol")
    checkEqual(Format.shortMoney(1000, currency: "USD"), "$10.00", "short money in dollars")
    checkEqual(Format.shortMoney(464, currency: "CHF"), "CHF 4.64", "short money without a symbol")
    checkEqual(Format.relative(now - 30, now: now), "just now", "relative: seconds")
    checkEqual(Format.relative(now - 60, now: now), "1 min ago", "relative: one minute")
    checkEqual(Format.relative(now - 300, now: now), "5 mins ago", "relative: minutes")
    checkEqual(Format.relative(now - 7200, now: now), "2 hours ago", "relative: hours")
    checkEqual(Format.relative(now - 86400, now: now), "1 day ago", "relative: a day")
    check(Format.reset(now).hasPrefix("at "), "session resets: a time")
    check(Format.reset(now, includeDate: true).hasPrefix("on "), "weekly resets: a date")
}

@MainActor func testParsing() {
    checkEqual(JSON.int(NSNumber(value: 42.9)), 42, "fractional numbers truncate")
    checkEqual(JSON.int(NSNumber(value: 7)), 7, "integers stay")
    checkEqual(JSON.int("7"), nil, "strings aren't numbers")
    checkEqual(JSON.date("2027-01-15T08:00:00.466682+00:00").map { Int($0.timeIntervalSince1970) }, 1_800_000_000,
               "six fractional digits, as claude.ai writes them")
    checkEqual(JSON.date("2027-01-15T08:00:00Z"), now, "no fractional seconds")
    checkEqual(JSON.date("tomorrow"), nil, "not a date")

    // /usage?cedar_ember=1&skip_spend=1, shaped like claude.ai's answer
    let usage = json("""
    {"five_hour": {"utilization": 6.0, "resets_at": "\(iso(now + 7980))"},
     "seven_day": {"utilization": 85.4, "resets_at": "\(iso(now + 86400))"},
     "seven_day_sonnet": null,
     "limits": [{"kind": "session", "percent": 6, "scope": null},
                {"kind": "weekly_scoped", "percent": 92, "resets_at": "\(iso(now + 3600))",
                 "scope": {"model": {"display_name": "Fable"}}}],
     "cedar_ember": {"eligible": true, "grants": [
        {"resets_left": 2, "paused": false, "starts_at": "\(iso(now - 3600))", "ends_at": "\(iso(now + 5 * 86400))"},
        {"resets_left": 1, "paused": true, "ends_at": "\(iso(now + 86400))"},
        {"resets_left": 3, "starts_at": "\(iso(now + 3600))", "ends_at": "\(iso(now + 86400))"},
        {"resets_left": 4, "ends_at": "\(iso(now - 60))"},
        {"resets_left": 1, "ends_at": "\(iso(now + 2 * 86400))"}]}}
    """)
    let snapshot = UsageSnapshot(json: usage)
    checkEqual(snapshot.session, UsageWindow(percent: 6, resetsAt: now + 7980), "session")
    checkEqual(snapshot.weekly.percent, 85, "weekly truncates 85.4")
    checkEqual(snapshot.weeklySonnet, nil, "no Sonnet limit")
    checkEqual(snapshot.weeklyFable, UsageWindow(percent: 92, resetsAt: now + 3600), "Fable from the limits array")
    checkEqual(snapshot.fullestWeeklyPercent, 92, "fullest weekly limit: Fable")
    check(snapshot.blockingLimit == nil, "nothing used up")

    let resets = LimitResets(json: usage["cedar_ember"], now: now)
    checkEqual(resets.count, 3, "resets: only usable grants (2 + 1)")
    checkEqual(resets.endsAt, now + 2 * 86400, "resets: the earliest end")
    checkEqual(LimitResets(json: json(#"{"eligible": false, "grants": []}"#), now: now).count, 0, "resets: not eligible")

    // /overage_spend_limit with extra usage switched off, as on 2026-10-15
    let off = ExtraUsage(json: json(#"""
    {"is_enabled": false, "used_credits": 464, "monthly_credit_limit": 1000, "currency": "EUR",
     "disabled_reason": null, "disabled_until": null, "out_of_credits": true}
    """#))
    checkEqual(off.spentMinor, 464, "spend while off")
    checkEqual(off.limitMinor, 1000, "cap while off")
    checkEqual(off.currency, "EUR", "currency")
    check(!off.isAvailable(now: now), "switched off: not available")
    var on = off
    on.isEnabled = true
    check(on.isAvailable(now: now), "on and below the cap: available, whatever out_of_credits says")
    on.spentMinor = 1000
    check(!on.isAvailable(now: now), "at the cap: not available")
    on.spentMinor = 464
    on.disabledUntil = now + 60
    check(!on.isAvailable(now: now), "disabled until later: not available")
    on.disabledUntil = now - 60
    check(on.isAvailable(now: now), "disabled until earlier: available")
    on.disabledReason = "overage_disabled"
    check(!on.isAvailable(now: now), "a disabled reason: not available")
    check(ExtraUsage(isEnabled: true, spentMinor: 5000).isAvailable(now: now), "no cap: available")

    checkEqual(FreeCredits(json: json(#"{"amount": 250, "currency": "EUR"}"#)).remainingMinor, 250, "credits: the balance")
    checkEqual(FreeCredits(json: json(#"""
    {"tranches": [{"remaining_amount_minor_units": 100}], "promo_tranches": [{"remaining_amount_minor_units": 50}]}
    """#)).remainingMinor, 150, "credits: older payloads add up the tranches")
}

@MainActor func testLevels() {
    checkEqual(UsageLevel(percent: 69), .normal, "69 %")
    checkEqual(UsageLevel(percent: 70), .high, "70 %")
    checkEqual(UsageLevel(percent: 89), .high, "89 %")
    checkEqual(UsageLevel(percent: 90), .critical, "90 %")
    checkEqual(UsageLevel(fraction: 1.4), .critical, "over the cap")
    let wrong = (0...100).filter { percent -> Bool in
        let expected: UsageLevel = percent >= 90 ? .critical : percent >= 70 ? .high : .normal
        return UsageLevel(percent: percent) != expected
    }
    checkEqual(wrong, [], "every whole percentage, 29, 57 and 58 included")
    check(MenuBarIcon.color(forPercent: 69) == MenuBarIcon.color(forPercent: 0), "menu bar: green below 70")
    check(MenuBarIcon.color(forPercent: 70) != MenuBarIcon.color(forPercent: 69), "menu bar: yellow from 70")
    check(MenuBarIcon.color(forPercent: 90) != MenuBarIcon.color(forPercent: 89), "menu bar: red from 90")
    let mismatched = (0...100).filter { percent -> Bool in
        Color.usage(Double(percent) / 100) != Color(nsColor: MenuBarIcon.color(forPercent: percent))
    }
    checkEqual(mismatched, [], "popup and menu bar: the same color at every whole percentage")
}

@MainActor func testMenuBar() {
    let defaults = freshDefaults()
    let store = UsageStore(prefs: Preferences(defaults: defaults), defaults: defaults,
                           cookie: "a=1; sessionKey=sk-ant-sid01-abcdefghijWXYZ; b=2", notify: { _, _ in })
    checkEqual(store.menuBarState(now: now), .noData, "nothing fetched yet")
    checkEqual(store.tooltip(now: now), "Fetching your usage…", "tooltip before the first answer")
    checkEqual(store.savedCookieHint, "…WXYZ", "cookie hint: the end of sessionKey")
    checkEqual(UsageStore(prefs: Preferences(defaults: defaults), defaults: defaults, cookie: "a=1",
                          notify: { _, _ in }).savedCookieHint, nil, "cookie hint: no sessionKey")

    store.apply(usage: .success(makeSnapshot(session: 6, weekly: 69)), extra: nil, credits: nil, resets: nil, now: now)
    checkEqual(store.menuBarState(now: now), .current(percent: 6, weekly: nil), "no ring below 70 %")
    store.apply(usage: .success(makeSnapshot(session: 6, weekly: 85)), extra: nil, credits: nil, resets: nil, now: now)
    checkEqual(store.menuBarState(now: now), .current(percent: 6, weekly: 85), "weekly ring from 70 %")

    // Stale: the last fetch failed and the data is older than two intervals (1 minute here).
    store.apply(usage: .failure(ClaudeAPI.Failure.network), extra: nil, credits: nil, resets: nil, now: now + 60)
    checkEqual(store.problem, .unreachable, "no connection")
    check(store.problem?.message(dataTime: now).hasPrefix("Can't reach claude.ai. Showing data from ") == true,
          "the problem says which data is on screen")
    checkEqual(store.menuBarState(now: now + 60), .current(percent: 6, weekly: 85), "not stale yet")
    checkEqual(store.menuBarState(now: now + 121), .stale(percent: 6), "stale after two intervals")

    // The session used up, with and without extra usage.
    let extra = ExtraUsage(isEnabled: true, spentMinor: 464, limitMinor: 1000, currency: "EUR")
    let sessionUsedUp = makeSnapshot(session: 100, weekly: 85, sessionResets: now + 7980)
    store.apply(usage: .success(sessionUsedUp), extra: extra, credits: nil, resets: nil, now: now)
    checkEqual(store.menuBarState(now: now), .extraUsage(spent: "€4.64", weekly: 85), "extra usage covers the session")
    var extraOff = extra
    extraOff.isEnabled = false
    store.apply(usage: .success(sessionUsedUp), extra: extraOff, credits: nil, resets: nil, now: now)
    checkEqual(store.menuBarState(now: now), .waiting(timeLeft: "2h 13m", weekly: 85), "session used up, waiting")
    let tooltip = store.tooltip(now: now)
    check(tooltip.hasPrefix("Session limit reached: Claude works again in 2h 13m.\nSession (5 hour): 100% used"),
          "tooltip: what happens, then the limits: \(tooltip)")
    check(tooltip.hasSuffix("\nExtra usage (off): EUR 4.64 of EUR 10.00 this month"), "tooltip: extra usage off")

    // Both used up: the weekly limit resets last.
    store.apply(usage: .success(makeSnapshot(session: 100, weekly: 100, sessionResets: now + 7980, weeklyResets: now + 40800)),
                extra: extraOff, credits: nil, resets: nil, now: now)
    checkEqual(store.menuBarState(now: now), .waiting(timeLeft: "11h 20m", weekly: 100), "weekly used up, waiting")
    check(store.tooltip(now: now).hasPrefix("Session and weekly limits reached: Claude works again in 11h 20m."),
          "tooltip: both limits")

    // A used-up Sonnet limit stops only Sonnet.
    var sonnet = makeSnapshot(session: 10, weekly: 40)
    sonnet.weeklySonnet = UsageWindow(percent: 100)
    store.apply(usage: .success(sonnet), extra: extraOff, credits: nil, resets: nil, now: now)
    checkEqual(store.menuBarState(now: now), .current(percent: 10, weekly: 100), "Sonnet used up doesn't block")

    store.apply(usage: .failure(ClaudeAPI.Failure.sessionEnded), extra: nil, credits: nil, resets: nil, now: now)
    checkEqual(store.menuBarState(now: now), .cookieRejected, "session ended")
    check(store.tooltip(now: now).hasPrefix("claude.ai no longer accepts your session cookie."), "tooltip: session ended")

    let button = NSButton(title: "", target: nil, action: nil)
    let states: [MenuBarState] = [.noData, .cookieRejected, .stale(percent: 6), .current(percent: 6, weekly: 85),
                                  .extraUsage(spent: "€4.64", weekly: nil), .waiting(timeLeft: "11h 20m", weekly: 100)]
    var titles: [String] = []
    var iconWidths: [CGFloat] = []
    for state in states {
        MenuBarController.show(state, on: button)
        titles.append(button.title)
        iconWidths.append(button.image?.size.width ?? 0)
    }
    checkEqual(titles, ["", " !", " 6%", " 6%", " €4.64", " 11h 20m"], "menu bar texts")
    checkEqual(iconWidths, [18, 18, 18, 20, 18, 20], "the weekly ring widens the icon")
}

@MainActor func testAlerts() {
    let inbox = Inbox()
    let defaults = freshDefaults()
    let prefs = Preferences(defaults: defaults)
    var store = UsageStore(prefs: prefs, defaults: defaults, cookie: "sessionKey=x", notify: inbox.post)
    func refresh(_ session: Int, _ weekly: Int, extra: ExtraUsage? = nil, weeklyResets: Date? = nil) {
        store.apply(usage: .success(makeSnapshot(session: session, weekly: weekly, weeklyResets: weeklyResets)),
                    extra: extra, credits: nil, resets: nil, now: now)
    }
    let session30 = "Claude Usage Alert | You've reached 30% of your 5-hour session limit"

    refresh(30, 10)
    checkEqual(inbox.take(), [session30], "session passes 25 %")
    refresh(40, 10)
    checkEqual(inbox.take(), [], "no second alert below 50 %")
    refresh(95, 10)
    checkEqual(inbox.take(), ["Claude Usage Alert | You've reached 95% of your 5-hour session limit"],
               "one alert for 95 %, not one per threshold")
    refresh(5, 10)
    refresh(30, 10)
    checkEqual(inbox.take(), [session30], "re-armed after the session reset")

    // Weekly 90 % and 100 %, then a restart doesn't repeat them.
    let resets = now + 40800
    refresh(30, 91, weeklyResets: resets)
    let weekly90 = inbox.take()
    check(weekly90.count == 1 && weekly90[0].hasPrefix("Claude Usage Alert | You've reached 91% of your weekly limit. It resets on "),
          "weekly passes 90 %: \(weekly90)")
    refresh(30, 100, weeklyResets: resets)
    let weekly100 = inbox.take()
    check(weekly100.count == 1 && weekly100[0].hasPrefix("Weekly limit reached | Claude works again in 11h 20m, on "),
          "weekly used up without extra usage: \(weekly100)")
    store = UsageStore(prefs: prefs, defaults: defaults, cookie: "sessionKey=x", notify: inbox.post)   // a restart
    refresh(30, 100, weeklyResets: resets)
    checkEqual(inbox.take(), [], "no repeats after a restart")

    // Extra usage charged while a limit is used up: once, again only after no limit was used up.
    var extra = ExtraUsage(isEnabled: true, spentMinor: 100, limitMinor: 1000, currency: "EUR")
    refresh(30, 100, extra: extra, weeklyResets: resets)
    checkEqual(inbox.take(), [], "the first spend reading has nothing to compare with")
    extra.spentMinor = 150
    refresh(30, 100, extra: extra, weeklyResets: resets)
    checkEqual(inbox.take(), ["Extra usage is being charged | EUR 1.50 of EUR 10.00 spent this month."], "spend rose while used up")
    extra.spentMinor = 200
    refresh(30, 100, extra: extra, weeklyResets: resets)
    checkEqual(inbox.take(), [], "only once")
    refresh(30, 20, extra: extra)
    checkEqual(inbox.take(), [], "the weekly reset is quiet")
    extra.spentMinor = 250
    refresh(100, 20, extra: extra)
    checkEqual(inbox.take(), ["Claude Usage Alert | You've reached 100% of your 5-hour session limit",
                              "Extra usage is being charged | EUR 2.50 of EUR 10.00 spent this month."],
               "re-armed once no limit was used up")

    // Weekly used up while extra usage covers it.
    let covered = freshDefaults()
    let coveredStore = UsageStore(prefs: Preferences(defaults: covered), defaults: covered, cookie: "sessionKey=x", notify: inbox.post)
    coveredStore.apply(usage: .success(makeSnapshot(session: 10, weekly: 100, weeklyResets: resets)), extra: extra,
                       credits: nil, resets: nil, now: now)
    let coveredAlert = inbox.take()
    check(coveredAlert.count == 1 && coveredAlert[0].hasPrefix(
        "Weekly limit reached | Claude now runs on extra usage: EUR 2.50 of EUR 10.00 spent this month. The limit resets on "),
          "weekly used up with extra usage: \(coveredAlert)")

    prefs.usageNotificationsEnabled = false
    refresh(5, 5)
    refresh(80, 95)
    checkEqual(inbox.take(), [], "usage notifications off")
    prefs.usageNotificationsEnabled = true
    store.apply(usage: .failure(ClaudeAPI.Failure.sessionEnded), extra: nil, credits: nil, resets: nil, now: now)
    store.apply(usage: .failure(ClaudeAPI.Failure.sessionEnded), extra: nil, credits: nil, resets: nil, now: now)
    checkEqual(inbox.take(), ["Your claude.ai session expired | Paste a fresh session cookie in Headroom to see your usage again."],
               "one notice when the session ends")
}

@MainActor func testFailures() {
    let defaults = freshDefaults()
    let store = UsageStore(prefs: Preferences(defaults: defaults), defaults: defaults, cookie: "sessionKey=x", notify: { _, _ in })
    func fail(_ error: Error) {
        store.apply(usage: .failure(error), extra: nil, credits: nil, resets: nil, now: now)
    }
    fail(ClaudeAPI.Failure.rateLimited(retryAfter: nil))
    checkEqual(store.problem, .rateLimited(until: now + 120), "429: wait two intervals")
    fail(ClaudeAPI.Failure.rateLimited(retryAfter: nil))
    checkEqual(store.problem, .rateLimited(until: now + 240), "429 again: twice as long")
    fail(ClaudeAPI.Failure.rateLimited(retryAfter: 900))
    checkEqual(store.problem, .rateLimited(until: now + 900), "a longer Retry-After wins")
    fail(ClaudeAPI.Failure.http(500))
    checkEqual(store.problem, .failed("claude.ai answered with HTTP 500."), "another status")
    fail(ClaudeAPI.Failure.http(403))
    checkEqual(store.problem, .failed("claude.ai answered with HTTP 403."), "a 403 without claude.ai's error isn't a session end")
    fail(URLError(.timedOut))
    checkEqual(store.problem, .unreachable, "other errors count as no connection")

    let claudeError = Data(#"""
    {"type":"error","error":{"type":"permission_error","message":"Invalid authorization","details":{"error_code":"account_session_invalid"}}}
    """#.utf8)
    checkEqual(ClaudeAPI.failure(status: 200, body: Data()), nil, "200 is no failure")
    checkEqual(ClaudeAPI.failure(status: 401, body: Data()), .sessionEnded, "401")
    checkEqual(ClaudeAPI.failure(status: 403, body: claudeError), .sessionEnded, "403 from claude.ai")
    checkEqual(ClaudeAPI.failure(status: 403, body: Data("<!DOCTYPE html><title>Just a moment...</title>".utf8)), .http(403),
               "403 from Cloudflare")
    checkEqual(ClaudeAPI.failure(status: 429, body: Data(), retryAfter: "30"), .rateLimited(retryAfter: 30), "429 with Retry-After")
    checkEqual(ClaudeAPI.failure(status: 429, body: Data()), .rateLimited(retryAfter: nil), "429 without")
    checkEqual(ClaudeAPI.failure(status: 503, body: Data()), .http(503), "503")
    checkEqual(ClaudeAPI.cookieValue(named: "lastActiveOrg", in: "a=1; lastActiveOrg=org-1; b=2"), "org-1", "a cookie from the header")
    checkEqual(ClaudeAPI.cookieValue(named: "sessionKey", in: "sessionKeyV3=v3; sessionKey=v1"), "v1", "names match whole")
    checkEqual(ClaudeAPI.cookieValue(named: "missing", in: "a=1"), nil, "a missing cookie")
}

@MainActor func testHTTP() {
    let config = HTTP.session.configuration
    check(config.httpCookieStorage == nil, "no cookie storage")
    check(config.urlCache == nil, "no URL cache")
    check(!config.httpShouldSetCookies, "no stored cookies added to requests")
}

@MainActor func testStatus() {
    let inbox = Inbox()
    let defaults = freshDefaults()
    let status = StatusStore(prefs: Preferences(defaults: defaults), defaults: defaults, notify: inbox.post)
    check(status.isTracked("c-claude-ai") && !status.isTracked("c-claude-gov"), "before the first fetch: all but Government")
    func summary(_ description: String, claudeAI: String) -> [String: Any] {
        json("""
        {"status": {"indicator": "x", "description": "\(description)"},
         "components": [{"id": "ai", "name": "claude.ai", "status": "\(claudeAI)"},
                        {"id": "gov", "name": "Claude for Government", "status": "major_outage"}],
         "incidents": []}
        """)
    }
    status.apply(summary: summary("All Systems Operational", claudeAI: "operational"))
    check(status.isTracked("ai") && !status.isTracked("gov"), "the first real list: all but Government")
    checkEqual(status.effectiveIndicator, .operational, "an untracked outage doesn't count")
    checkEqual(inbox.take(), [], "no notification on the first fetch")
    status.apply(summary: summary("Partial System Outage", claudeAI: "partial_outage"))
    checkEqual(status.effectiveIndicator, .major, "a tracked partial outage")
    checkEqual(status.affectedComponents.map(\.id), ["ai"], "affected services")
    checkEqual(inbox.take(), ["Claude status: Partial System Outage | Visit status.claude.com for details"], "outage notification")
    status.apply(summary: summary("All Systems Operational", claudeAI: "operational"))
    checkEqual(inbox.take(), ["Claude is back online | All systems operational"], "back online")
    check(StatusIndicator.operational < .minor && StatusIndicator.minor < .major && StatusIndicator.major < .critical,
          "indicators by severity")
    checkEqual(StatusComponent(id: "x", name: "x", status: "under_maintenance").indicator, .minor, "maintenance counts as minor")
}

@MainActor func testUpdates() {
    check(UpdateStore.isNewer("2.0.1", than: "2.0.0"), "2.0.1 is newer")
    check(!UpdateStore.isNewer("2.0.0", than: "2.0.0"), "the same version")
    check(UpdateStore.isNewer("1.10", than: "1.9"), "numeric, not alphabetic")
    check(!UpdateStore.isNewer("2", than: "2.0.1"), "missing parts count as 0")
    check(UpdateStore.isAllowed(URL(string: "https://github.com/videlov/headroom/releases")!), "github.com")
    check(UpdateStore.isAllowed(URL(string: "https://objects.github.com/x")!), "a github.com subdomain")
    check(!UpdateStore.isAllowed(URL(string: "http://github.com/x")!), "not https")
    check(!UpdateStore.isAllowed(URL(string: "https://notgithub.com/x")!), "a look-alike host")

    let inbox = Inbox()
    let updates = UpdateStore(defaults: freshDefaults(), notify: inbox.post)
    let feed = json(#"""
    {"version": "9.0.0", "title": "Headroom 9.0.0", "description": "New",
     "buttons": [{"label": "Download", "url": "https://github.com/videlov/headroom/releases/latest/download/Headroom.dmg",
                  "style": "primary"},
                 {"label": "Elsewhere", "url": "https://example.com"}]}
    """#)
    updates.apply(feed: feed)
    updates.apply(feed: feed)
    checkEqual(updates.available?.version, "9.0.0", "an update")
    checkEqual(updates.available?.buttons.map(\.label), ["Download"], "links outside github.com are dropped")
    checkEqual(inbox.take(), ["Headroom 9.0.0 is available | Headroom 9.0.0"], "one notification per version")
    checkEqual(updates.visibleBanner, .update, "the update banner")
    updates.dismissCurrent()
    checkEqual(updates.visibleBanner, .none, "dismissed")

    updates.apply(feed: json(#"{"message": {"id": "m1", "title": "Hello", "body": "First"}}"#))
    checkEqual(inbox.take(), [], "the first message seen is only recorded")
    checkEqual(updates.visibleBanner, .message, "but it shows")
    updates.apply(feed: json(#"{"message": {"id": "m2", "title": "News", "body": "Second"}}"#))
    checkEqual(inbox.take(), ["News | Second"], "a new message notifies")
}

Task { @MainActor in
    _ = NSApplication.shared
    testFormatting()
    testParsing()
    testLevels()
    testMenuBar()
    testAlerts()
    testFailures()
    testHTTP()
    testStatus()
    testUpdates()
    UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
    print(failures == 0 ? "✅ \(checks) checks passed" : "❌ \(failures) of \(checks) checks failed")
    exit(failures == 0 ? 0 : 1)
}
dispatchMain()
