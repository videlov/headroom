import Foundation

/// Date, time and money text for the popup and the menu bar. The date formatters are
/// created once.
enum Format {
    /// "18:03", in the system's time style.
    static func time(_ date: Date) -> String {
        shortTime.string(from: date)
    }

    /// "at 21:09" for the session; "on 15 Oct 2026 at 03:59" for weekly limits.
    static func reset(_ date: Date, includeDate: Bool = false) -> String {
        includeDate ? "on \(dateAndTime.string(from: date))" : "at \(shortTime.string(from: date))"
    }

    /// "Oct 15".
    static func monthDay(_ date: Date) -> String {
        monthDayFormatter.string(from: date)
    }

    /// "2d 5h", "11h 20m" or "45m" until `date`, rounded up to the minute; at least "1m".
    static func countdown(to date: Date, now: Date = Date()) -> String {
        let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        let (d, h, m) = (minutes / 1440, minutes % 1440 / 60, minutes % 60)
        if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    /// "$4.64", or "EUR 4.64" for other currencies.
    static func money(_ minor: Int, currency: String) -> String {
        let value = Double(minor) / 100
        return currency == "USD"
            ? String(format: "$%.2f", value)
            : String(format: "%@ %.2f", currency, value)
    }

    /// "€4.64": the currency's symbol where it has one, for the menu bar.
    static func shortMoney(_ minor: Int, currency: String) -> String {
        let amount = String(format: "%.2f", Double(minor) / 100)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let symbol = formatter.currencySymbol ?? currency
        return symbol == currency ? "\(currency) \(amount)" : symbol + amount
    }

    /// "just now", "5 mins ago", "2 hours ago", "1 day ago".
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let elapsed = Int(now.timeIntervalSince(date))
        if elapsed < 60 { return "just now" }
        if elapsed < 3600 {
            let m = elapsed / 60
            return "\(m) min\(m == 1 ? "" : "s") ago"
        }
        if elapsed < 86_400 {
            let h = elapsed / 3600
            return "\(h) hour\(h == 1 ? "" : "s") ago"
        }
        let d = elapsed / 86_400
        return "\(d) day\(d == 1 ? "" : "s") ago"
    }

    private static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// The time follows the system's 12- or 24-hour setting, as in the session line.
    private static let dateAndTime: DateFormatter = {
        let formatter = DateFormatter()
        let time = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current) ?? "HH:mm"
        formatter.dateFormat = "d MMM yyyy 'at' \(time)"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}
