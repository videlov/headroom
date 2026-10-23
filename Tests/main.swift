import AppKit
import SwiftUI

// Self-tests for the logic behind the popup and the menu bar. scripts/test.sh compiles
// them with Sources/ (without HeadroomApp.swift, which has @main) and runs them. They
// use a preferences domain of their own and never touch the Keychain or the network:
// the stores' requests go to StubProtocol.

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

/// Answers the requests of `stubSession` without the network and records them.
final class StubProtocol: URLProtocol {
    struct Answer {
        var status = 200
        var headers: [String: String] = [:]
        var body = "{}"
    }

    private static let lock = NSLock()
    private static var answer: (URLRequest) -> Answer? = { _ in nil }
    private static var requests: [URLRequest] = []

    /// Answers with `answer` from now on; nil fails a request as if offline.
    static func stub(_ answer: @escaping (URLRequest) -> Answer?) {
        lock.lock()
        defer { lock.unlock() }
        self.answer = answer
        requests = []
    }

    /// The requests since the last call.
    static func takeRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        let taken = requests
        requests = []
        return taken
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let answer = Self.answer(request)
        Self.lock.unlock()
        guard let answer, let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1",
                                             headerFields: answer.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Configured like HTTP.session, but answered by StubProtocol.
let stubSession: URLSession = {
    let config = HTTP.session.configuration
    config.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: config)
}()

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
    // scripts/test.sh runs the tests in en_DE and Berlin time, where now is Friday 09:00.
    checkEqual(Format.reset(now), "at 09:00", "session resets: the time")
    checkEqual(Format.reset(now, includeDate: true), "on 15 Jan 2027 at 09:00", "weekly resets: date and time")
    checkEqual(Format.resetShort(now + 2 * 3600, now: now), "11:00", "popup: a reset today shows the time")
    checkEqual(Format.resetShort(now + 15 * 3600, now: now), "Sat 00:00", "popup: after midnight, the weekday")
    checkEqual(Format.resetShort(now + 6 * 86400 - 60, now: now), "Thu 08:59", "popup: the weekday within six days")
    checkEqual(Format.resetShort(now + 6 * 86400, now: now), "21. Jan at 09:00",
               "popup: the date from six days on, so a weekday never means two dates")
    checkEqual(Format.monthDay(now), "Jan 15", "month and day")
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

/// Draws `image` at 2x into an sRGB bitmap. The result gives the color at a point (in points,
/// from the top left) as [red, green, blue, alpha] from 0 to 1, not premultiplied.
func pixels(of image: NSImage) -> (_ x: Double, _ y: Double) -> [Double] {
    let width = Int(image.size.width) * 2, height = Int(image.size.height) * 2
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: 2, y: 2)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()
    let bytes = Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self),
                                          count: width * height * 4))
    return { x, y in
        let i = (Int(y * 2) * width + Int(x * 2)) * 4   // the first row is the top
        let alpha = Double(bytes[i + 3]) / 255
        guard alpha > 0 else { return [0, 0, 0, 0] }
        return (0..<3).map { Double(bytes[i + $0]) / 255 / alpha } + [alpha]
    }
}

/// Whether two colors from `pixels(of:)` match, give or take rounding.
func matches(_ actual: [Double], _ expected: NSColor) -> Bool {
    let c = expected.usingColorSpace(.sRGB)!
    let rgba = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map(Double.init)
    return zip(actual, rgba).allSatisfy { abs($0 - $1) < 0.06 }
}

@MainActor func testMenuBarIcon() {
    // The SVG path parser, on small paths.
    func bounds(_ d: String) -> [Double] {
        let r = NSBezierPath(svgPathData: d).bounds
        return [r.minX, r.minY, r.width, r.height].map { (Double($0) * 100).rounded() / 100 }
    }
    checkEqual(bounds("M0 0L10 0L10 10Z"), [0, 0, 10, 10], "path: absolute lines")
    checkEqual(bounds("m1 1h2v2h-2z"), [1, 1, 2, 2], "path: relative lines")
    checkEqual(bounds("M0 0 10 0 10 10z"), [0, 0, 10, 10], "path: pairs after M are lines")
    checkEqual(bounds("M.5.5L1.5-.5"), [0.5, -0.5, 1, 1], "path: packed numbers")
    checkEqual(bounds("M0 0C0 10 10 10 10 0"), [0, 0, 10, 7.5], "path: curves")

    // The weekly ring at 85 % starts at 12 o'clock and runs clockwise in the weekly level's
    // color, the rest is white at 35 %, and the symbol inside has the session's color.
    let red = MenuBarIcon.color(forPercent: 95), yellow = MenuBarIcon.color(forPercent: 85)
    let ring = pixels(of: MenuBarIcon.image(color: red, weeklyPercent: 85))
    check(matches(ring(10.5, 1), yellow), "ring: starts at 12 o'clock")
    check(matches(ring(19, 10), yellow) && matches(ring(1, 10), yellow), "ring: clockwise, past 9 o'clock")
    check(matches(ring(5.5, 2.2), NSColor(white: 1, alpha: 0.35)), "ring: the rest in white at 35 %")
    check(matches(ring(10, 10), red), "ring: the symbol in the session's color")
    let plain = pixels(of: MenuBarIcon.image(color: red))
    check(matches(plain(9, 9), red) && plain(0.5, 0.5)[3] == 0, "no ring: just the symbol")
}

@MainActor func testTooltip() {
    let defaults = freshDefaults()
    let prefs = Preferences(defaults: defaults)
    checkEqual(UsageStore(prefs: prefs, defaults: defaults, cookie: "", notify: { _, _ in }).tooltip(now: now),
               "Set your claude.ai session cookie to see your usage.", "no cookie yet")
    let store = UsageStore(prefs: prefs, defaults: defaults, cookie: "sessionKey=x", notify: { _, _ in })
    store.apply(usage: .failure(ClaudeAPI.Failure.network), extra: nil, credits: nil, resets: nil, now: now)
    checkEqual(store.tooltip(now: now), "Can't reach claude.ai.", "a problem before the first numbers")

    var snapshot = makeSnapshot(session: 42, weekly: 76, sessionResets: now + 3600, weeklyResets: now + 86400)
    snapshot.weeklySonnet = UsageWindow(percent: 40)
    snapshot.weeklyFable = UsageWindow(percent: 0)
    store.apply(usage: .success(snapshot), extra: ExtraUsage(isEnabled: true, spentMinor: 464, currency: "EUR"),
                credits: nil, resets: nil, now: now)
    checkEqual(store.tooltip(now: now), """
        Session (5 hour): 42% used · resets at 10:00
        Weekly (7 day): 76% used · resets on 16 Jan 2027 at 09:00
        Weekly Sonnet (7 day): 40% used
        Extra usage: EUR 4.64 this month
        """, "every limit, Fable only while in use, extra usage without a monthly limit")
    store.apply(usage: .failure(ClaudeAPI.Failure.network), extra: nil, credits: nil, resets: nil, now: now + 60)
    check(store.tooltip(now: now + 60).hasPrefix("Can't reach claude.ai. Showing data from 09:00.\nSession (5 hour): 42% used"),
          "the problem first, then the numbers still on screen")

    store.apply(usage: .success(makeSnapshot(session: 100, weekly: 50)), extra: nil, credits: nil, resets: nil, now: now)
    check(store.tooltip(now: now).hasPrefix("Session limit reached: Claude now runs on extra usage.\n"), "extra usage covers it")
    store.apply(usage: .success(makeSnapshot(session: 50, weekly: 100)), extra: ExtraUsage(), credits: nil, resets: nil, now: now)
    check(store.tooltip(now: now).hasPrefix("Weekly limit reached.\n"), "used up, no reset time")

    store.apply(usage: .success(makeSnapshot(session: 1, weekly: 1)), extra: nil,
                credits: FreeCredits(remainingMinor: 250, currency: "CHF"),
                resets: LimitResets(count: 2, endsAt: now + 86400), now: now)
    checkEqual(store.freeCreditsMinor, 250, "free credits")
    checkEqual(store.currency, "CHF", "the credits' currency")
    checkEqual(store.limitResets, LimitResets(count: 2, endsAt: now + 86400), "limit resets")
    checkEqual(UsageProblem.rateLimited(until: now + 120).message(dataTime: now),
               "claude.ai is limiting requests. Trying again at 09:02. Showing data from 09:00.", "rate limited")
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

/// claude.ai's answers for the organization org-1, by path; other paths get a 404.
func claudeAI(_ changes: [String: StubProtocol.Answer] = [:]) -> (URLRequest) -> StubProtocol.Answer? {
    let answers = [
        "/api/bootstrap": StubProtocol.Answer(body: #"{"account": {"lastActiveOrgId": "org-1"}}"#),
        "/api/organizations/org-1/usage": StubProtocol.Answer(body: """
            {"five_hour": {"utilization": 42.0, "resets_at": "\(iso(now + 3600))"},
             "seven_day": {"utilization": 76.0, "resets_at": "\(iso(now + 86400))"},
             "cedar_ember": {"eligible": true, "grants": [{"resets_left": 2, "ends_at": "\(iso(now + 5 * 86400))"}]}}
            """),
        "/api/organizations/org-1/overage_spend_limit": StubProtocol.Answer(body: #"""
            {"is_enabled": true, "used_credits": 464, "monthly_credit_limit": 2000, "currency": "EUR"}
            """#),
        "/api/organizations/org-1/prepaid/credits": StubProtocol.Answer(body: #"{"amount": 250, "currency": "EUR"}"#),
    ].merging(changes) { $1 }
    return { request in answers[request.url?.path ?? ""] ?? StubProtocol.Answer(status: 404) }
}

@MainActor func testRefresh() async {
    let defaults = freshDefaults()
    let prefs = Preferences(defaults: defaults)
    func makeStore(cookie: String) -> UsageStore {
        UsageStore(prefs: prefs, defaults: defaults, cookie: cookie, notify: { _, _ in }, session: stubSession)
    }
    func refresh(_ store: UsageStore, force: Bool = false) async {
        store.refresh(force: force)
        await store.refreshTask?.value
    }
    func paths() -> [String] {
        StubProtocol.takeRequests().compactMap(\.url?.path).sorted()
    }
    let three = ["/api/organizations/org-1/overage_spend_limit", "/api/organizations/org-1/prepaid/credits",
                 "/api/organizations/org-1/usage"]

    StubProtocol.stub(claudeAI())
    let store = makeStore(cookie: "sessionKey=sk-1")
    await refresh(store)
    checkEqual(paths(), ["/api/bootstrap"] + three, "the first refresh asks for the organization, then three requests")
    checkEqual(store.usage?.session, UsageWindow(percent: 42, resetsAt: now + 3600), "the session")
    checkEqual(store.usage?.weekly.percent, 76, "the weekly limit")
    checkEqual(store.extra.spentMinor, 464, "extra usage")
    checkEqual(store.freeCreditsMinor, 250, "free credits")
    checkEqual(store.currency, "EUR", "the currency")
    checkEqual(store.limitResets.count, 2, "the limit resets come with the usage")
    checkEqual(store.problem, nil, "no problem")

    await refresh(store)
    let requests = StubProtocol.takeRequests()
    checkEqual(requests.compactMap(\.url?.path).sorted(), three, "later refreshes: three requests, the organization is kept")
    let usageRequest = requests.first { $0.url?.path == "/api/organizations/org-1/usage" }
    checkEqual(usageRequest?.url?.query, "cedar_ember=1&skip_spend=1", "the limits and the resets in one answer")
    checkEqual(usageRequest?.value(forHTTPHeaderField: "Cookie"), "sessionKey=sk-1", "the cookie goes along")

    await refresh(makeStore(cookie: "sessionKey=sk-1; lastActiveOrg=org-1"))
    checkEqual(paths(), three, "lastActiveOrg in the cookie: no /api/bootstrap")
    await refresh(makeStore(cookie: ""))
    checkEqual(paths(), [], "no cookie: no requests")

    StubProtocol.stub(claudeAI(["/api/organizations/org-1/overage_spend_limit": .init(status: 500)]))
    await refresh(store)
    checkEqual(store.extra.spentMinor, 464, "a failed extra usage request keeps the last values")
    checkEqual(store.problem, nil, "only /usage decides whether there's a problem")

    StubProtocol.stub(claudeAI(["/api/organizations/org-1/usage": .init(status: 429, headers: ["Retry-After": "900"])]))
    await refresh(store)
    if case .rateLimited(let until)? = store.problem {
        check(abs(until.timeIntervalSinceNow - 900) < 60, "429: waits as long as Retry-After asks")
    } else {
        check(false, "429: rate limited, got \(String(describing: store.problem))")
    }
    store.refresh()
    check(store.refreshTask == nil, "timers don't fetch while rate limited")

    StubProtocol.stub(claudeAI(["/api/organizations/org-1/usage":
        .init(status: 403, body: #"{"type": "error", "error": {"type": "permission_error"}}"#)]))
    await refresh(store, force: true)
    checkEqual(store.problem, .cookieRejected, "403 from claude.ai: the session ended")
    _ = StubProtocol.takeRequests()
    store.refresh()
    check(store.refreshTask == nil, "timers don't fetch while the cookie is rejected")
    await refresh(store, force: true)
    checkEqual(paths(), three, "Refresh does")

    StubProtocol.stub(claudeAI(["/api/organizations/org-1/usage": .init(body: "<!DOCTYPE html>")]))
    await refresh(store, force: true)
    checkEqual(store.problem, .failed("claude.ai sent an unexpected answer."), "an answer that isn't JSON")
    StubProtocol.stub { _ in nil }
    await refresh(store, force: true)
    checkEqual(store.problem, .unreachable, "no connection")
    checkEqual(store.usage?.session.percent, 42, "the last numbers stay")

    StubProtocol.stub(claudeAI(["/api/bootstrap": .init(body: #"{"account": {}}"#)]))
    let noOrganization = makeStore(cookie: "sessionKey=sk-2")
    await refresh(noOrganization)
    checkEqual(noOrganization.problem, .failed("Couldn't find your claude.ai organization in the session cookie."),
               "no organization")
    checkEqual(paths(), ["/api/bootstrap"], "nothing more is asked without one")
}

@MainActor func testStatusFetch() async {
    let defaults = freshDefaults()
    let status = StatusStore(prefs: Preferences(defaults: defaults), defaults: defaults, notify: { _, _ in },
                             session: stubSession)
    StubProtocol.stub { request in
        guard request.url == AppInfo.statusSummaryURL else { return StubProtocol.Answer(status: 404) }
        return StubProtocol.Answer(body: """
            {"status": {"indicator": "minor", "description": "Minor Service Outage"},
             "components": [{"id": "ai", "name": "claude.ai", "status": "degraded_performance"},
                            {"id": "code", "name": "Claude Code", "status": "operational"},
                            {"id": "gov", "name": "Claude for Government", "status": "operational"}],
             "incidents": [
                {"id": "i1", "name": "Slow chats", "status": "identified", "updated_at": "\(iso(now - 600))",
                 "incident_updates": [{"body": "We found the cause.", "created_at": "\(iso(now - 300))"},
                                      {"body": "Looking into it.", "created_at": "\(iso(now - 900))"}],
                 "components": [{"id": "ai"}]},
                {"id": "i2", "name": "Login trouble", "status": "investigating", "updated_at": "\(iso(now - 60))",
                 "components": [{"id": "gov"}]},
                {"id": "i3", "name": "Elevated errors", "status": "monitoring", "updated_at": "\(iso(now - 60))"},
                {"id": "i4", "name": "Over", "status": "resolved"},
                {"id": "i5", "name": "Explained", "status": "postmortem"}]}
            """)
    }
    await status.fetch()
    checkEqual(StubProtocol.takeRequests().compactMap(\.url), [AppInfo.statusSummaryURL], "one request to status.claude.com")
    checkEqual(status.statusDescription, "Minor Service Outage", "the status line")
    checkEqual(status.incidents.map(\.id), ["i1", "i2", "i3"], "resolved incidents and postmortems are left out")
    checkEqual(status.incidents.first, StatusIncident(id: "i1", name: "Slow chats", status: "identified",
                                                      latestUpdate: "We found the cause.", updatedAt: now - 300,
                                                      componentIDs: ["ai"]), "an incident and its latest update")
    checkEqual(status.incidents.last?.updatedAt, now - 60, "without updates: the incident's own time")
    checkEqual(status.filteredIncidents.map(\.id), ["i1", "i3"], "incidents of tracked services, or of none in particular")
    checkEqual(status.effectiveIndicator, .minor, "degraded performance counts as minor")

    status.toggleTracking("gov")
    checkEqual(status.filteredIncidents.map(\.id), ["i1", "i2", "i3"], "tracking Government shows its incident")
    status.toggleTracking("ai")
    checkEqual(status.effectiveIndicator, .operational, "an untracked service doesn't count")
    let reopened = StatusStore(prefs: Preferences(defaults: defaults), defaults: defaults, notify: { _, _ in })
    check(reopened.isTracked("gov") && !reopened.isTracked("ai") && reopened.isTracked("code"), "the choice is saved")

    StubProtocol.stub { _ in nil }
    await status.fetch()
    checkEqual(status.statusDescription, "Minor Service Outage", "no connection: the last status stays")
}

@MainActor func testUpdateFeed() async {
    let inbox = Inbox()
    let defaults = freshDefaults()
    let updates = UpdateStore(defaults: defaults, notify: inbox.post, session: stubSession)
    StubProtocol.stub { request in
        guard request.url == AppInfo.updateFeedURL else { return StubProtocol.Answer(status: 404) }
        return StubProtocol.Answer(body: #"""
            {"version": "9.0.1", "title": "Headroom 9.0.1", "description": "Fixes",
             "download_url": "https://github.com/videlov/headroom/releases",
             "message": {"id": "m1", "title": "Hello", "body": "First"}}
            """#)
    }
    await updates.fetch()
    checkEqual(StubProtocol.takeRequests().compactMap(\.url), [AppInfo.updateFeedURL], "one request to the feed")
    checkEqual(updates.available?.version, "9.0.1", "the update")
    checkEqual(updates.available?.buttons.map(\.label), ["Download", "Later"], "older feeds: download_url gives Download and Later")
    checkEqual(inbox.take(), ["Headroom 9.0.1 is available | Headroom 9.0.1"], "the update notifies, the first message doesn't")

    // Both live: the one first seen last shows; a tie goes to the update.
    defaults.set(100.0, forKey: DefaultsKey.updateSeenAt)
    defaults.set(200.0, forKey: DefaultsKey.messageSeenAt)
    checkEqual(updates.visibleBanner, .message, "the message, seen after the update")
    defaults.set(200.0, forKey: DefaultsKey.updateSeenAt)
    checkEqual(updates.visibleBanner, .update, "a tie goes to the update")
    defaults.set(100.0, forKey: DefaultsKey.updateSeenAt)
    updates.dismissCurrent()
    checkEqual(updates.visibleBanner, .update, "dismissing the message shows the update")
    await updates.fetch()
    checkEqual(updates.announcement, nil, "a dismissed message stays away")

    updates.apply(feed: json(#"""
    {"message": {"id": "m2", "title": "News", "body": "Long text", "notification": {"title": "Short", "body": "Text"}}}
    """#))
    checkEqual(inbox.take(), ["Short | Text"], "a message's own notification text")
    checkEqual(updates.available, nil, "no version in the feed: no update")
    updates.apply(feed: json(#"{"message": {"id": "m3", "title": "Quiet", "body": "News", "notify": false}}"#))
    checkEqual(inbox.take(), [], "notify false: it only shows")
    updates.apply(feed: json(#"""
    {"version": "9.0.2", "title": "Headroom 9.0.2", "description": "More", "download_url": "https://example.com/Headroom.dmg"}
    """#))
    checkEqual(updates.available?.buttons, [], "a download_url outside github.com gives no buttons")

    StubProtocol.stub { _ in nil }
    await updates.fetch()
    checkEqual(updates.available?.version, "9.0.2", "no connection: the last answer stays")
}

Task { @MainActor in
    _ = NSApplication.shared
    testFormatting()
    testParsing()
    testLevels()
    testMenuBar()
    testMenuBarIcon()
    testTooltip()
    testAlerts()
    testFailures()
    testHTTP()
    testStatus()
    testUpdates()
    await testRefresh()
    await testStatusFetch()
    await testUpdateFeed()
    UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
    print(failures == 0 ? "✅ \(checks) checks passed" : "❌ \(failures) of \(checks) checks failed")
    exit(failures == 0 ? 0 : 1)
}
dispatchMain()
