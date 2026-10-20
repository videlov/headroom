import Foundation

/// One usage limit: the 5-hour session or a weekly limit.
struct UsageWindow: Equatable {
    var percent: Int          // as claude.ai reports it, truncated to a whole percent
    var resetsAt: Date?

    var fraction: Double { Double(percent) / 100 }
}

/// The limits from claude.ai's /usage endpoint.
struct UsageSnapshot: Equatable {
    var session = UsageWindow(percent: 0)
    var weekly = UsageWindow(percent: 0)
    var weeklySonnet: UsageWindow?   // only on plans with a separate Sonnet limit
    var weeklyFable: UsageWindow?    // Fable is counted separately

    /// The fullest weekly limit (all models, Sonnet or Fable), which the menu bar shows as a ring.
    var fullestWeeklyPercent: Int {
        [weekly, weeklySonnet, weeklyFable].compactMap { $0?.percent }.max() ?? 0
    }

    /// The used-up limit that resets last, when the session or the weekly limit is used up:
    /// Claude works again once it has. The Sonnet and Fable limits stop only their model.
    var blockingLimit: (weekly: Bool, window: UsageWindow)? {
        [(weekly: false, window: session), (weekly: true, window: weekly)]
            .filter { $0.window.percent >= 100 }
            .max { ($0.window.resetsAt ?? .distantFuture) < ($1.window.resetsAt ?? .distantFuture) }
    }
}

/// How full a limit is. From 70 % the session turns the menu bar symbol yellow, a weekly limit
/// puts a ring around it and the bars turn orange; from 90 % all of them turn red.
enum UsageLevel: Equatable {
    case normal, high, critical

    static let highPercent = 70
    static let criticalPercent = 90

    /// Compares fractions, so a whole percentage is never multiplied back and truncated.
    init(fraction: Double) {
        if fraction >= Double(Self.criticalPercent) / 100 {
            self = .critical
        } else if fraction >= Double(Self.highPercent) / 100 {
            self = .high
        } else {
            self = .normal
        }
    }

    init(percent: Int) {
        self.init(fraction: Double(percent) / 100)
    }
}

extension UsageSnapshot {
    init(json: [String: Any]) {
        session = UsageWindow(json: json["five_hour"]) ?? UsageWindow(percent: 0)
        weekly = UsageWindow(json: json["seven_day"]) ?? UsageWindow(percent: 0)
        weeklySonnet = UsageWindow(json: json["seven_day_sonnet"])
        // Fable isn't a top-level key like seven_day_sonnet: it's a model-scoped weekly
        // limit in the `limits` array (scope.model.display_name == "Fable").
        let limits = json["limits"] as? [[String: Any]] ?? []
        weeklyFable = limits
            .first { entry in
                let model = (entry["scope"] as? [String: Any])?["model"] as? [String: Any]
                return model?["display_name"] as? String == "Fable"
            }
            .map { UsageWindow(percent: JSON.int($0["percent"]) ?? 0, resetsAt: JSON.date($0["resets_at"])) }
    }
}

extension UsageWindow {
    init?(json: Any?) {
        guard let window = json as? [String: Any] else { return nil }
        percent = JSON.int(window["utilization"]) ?? 0
        resetsAt = JSON.date(window["resets_at"])
    }
}

/// Extra usage: pay-as-you-go spend against the monthly limit (/overage_spend_limit).
struct ExtraUsage: Equatable {
    var isEnabled = false     // switched on in claude.ai's settings
    var spentMinor = 0        // in minor units (cents)
    var limitMinor = 0        // 0: no monthly limit
    var disabledUntil: Date?  // claude.ai doesn't charge extra usage before then
    var disabledReason: String?
    var currency = "USD"

    /// Whether claude.ai charges extra usage once a limit is used up: switched on, not
    /// paused and below its monthly limit.
    func isAvailable(now: Date = Date()) -> Bool {
        guard isEnabled, disabledReason == nil else { return false }
        if let disabledUntil, disabledUntil > now { return false }
        return limitMinor == 0 || spentMinor < limitMinor
    }
}

extension ExtraUsage {
    init(json: [String: Any]) {
        isEnabled = json["is_enabled"] as? Bool ?? false
        spentMinor = JSON.int(json["used_credits"]) ?? 0
        limitMinor = JSON.int(json["monthly_credit_limit"]) ?? 0
        disabledUntil = JSON.date(json["disabled_until"])
        disabledReason = json["disabled_reason"] as? String
        currency = json["currency"] as? String ?? "USD"
    }
}

/// Free or promotional credits left (/prepaid/credits).
struct FreeCredits: Equatable {
    var remainingMinor = 0
    var currency: String?
}

extension FreeCredits {
    init(json: [String: Any]) {
        if let amount = JSON.int(json["amount"]) {
            remainingMinor = amount   // the current balance
        } else {
            // Older payloads: add up what's left in each tranche.
            remainingMinor = ["tranches", "promo_tranches"]
                .flatMap { json[$0] as? [[String: Any]] ?? [] }
                .reduce(0) { $0 + (JSON.int($1["remaining_amount_minor_units"]) ?? 0) }
        }
        currency = json["currency"] as? String
    }
}

/// Usage-limit resets the account can still trigger on claude.ai. Read-only here.
struct LimitResets: Equatable {
    var count = 0
    var endsAt: Date?   // the earliest end among the usable grants
}

extension LimitResets {
    /// Counts the resets still usable across grants: not paused, inside their window.
    init(json: Any?, now: Date = Date()) {
        guard let object = json as? [String: Any], object["eligible"] as? Bool == true,
              let grants = object["grants"] as? [[String: Any]] else { return }
        for grant in grants {
            let left = JSON.int(grant["resets_left"]) ?? 0
            guard left > 0, grant["paused"] as? Bool != true,
                  let end = JSON.date(grant["ends_at"]), end > now else { continue }
            if let start = JSON.date(grant["starts_at"]), start > now { continue }
            count += left
            endsAt = min(endsAt ?? end, end)
        }
    }
}

/// Lenient readers for JSONSerialization output.
enum JSON {
    /// A whole number from an integer or a fractional JSON number (truncated).
    static func int(_ value: Any?) -> Int? {
        (value as? NSNumber).map { Int($0.doubleValue) }
    }

    /// An ISO 8601 date, with or without fractional seconds.
    static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return isoFractional.date(from: string) ?? iso.date(from: string)
    }

    private static let iso = ISO8601DateFormatter()
    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
