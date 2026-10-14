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

    /// The fullest limit, which decides the menu bar color.
    var fullestPercent: Int {
        [session, weekly, weeklySonnet, weeklyFable].compactMap { $0?.percent }.max() ?? 0
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
    var spentMinor = 0        // in minor units (cents)
    var limitMinor = 0
    var resetsAt: Date?
    var currency = "USD"
}

extension ExtraUsage {
    init(json: [String: Any]) {
        spentMinor = JSON.int(json["used_credits"]) ?? 0
        limitMinor = JSON.int(json["monthly_credit_limit"]) ?? 0
        resetsAt = JSON.date(json["disabled_until"])
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
