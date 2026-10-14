import Foundation

/// Date and time text for the popup. The formatters are created once.
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
