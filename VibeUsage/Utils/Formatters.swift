import Foundation

enum Formatters {
    /// Format an exact integer with grouping separators for hover details.
    static func formatExactNumber(_ n: Int) -> String {
        groupedDecimal(n)
    }

    /// Format large numbers with compact notation: 1234 → "1,234", 45200 → "45.2K"
    static func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000_000 {
            let value = Double(n) / 1_000_000_000.0
            return String(format: "%.1fB", value)
        }
        if n >= 1_000_000 {
            let value = Double(n) / 1_000_000.0
            return String(format: "%.1fM", value)
        }
        if n >= 10_000 {
            let value = Double(n) / 1_000.0
            return String(format: "%.1fK", value)
        }
        return groupedDecimal(n)
    }

    /// Format cost: $0.00, $12.34, or $0.0012 for very small values
    static func formatCost(_ cost: Double) -> String {
        if cost == 0 { return "$0.00" }
        if cost < 0.01 { return String(format: "$%.4f", cost) }
        return String(format: "$%.2f", cost)
    }

    /// Match the new system dashboard's average TPM/RPM precision.
    static func formatRate(_ rate: Double) -> String {
        guard rate.isFinite else { return "0.000" }
        return String(format: "%.3f", max(rate, 0))
    }

    /// Format date for chart axis: "2/25"
    static func formatDateShort(_ dateString: String) -> String {
        let parts = String(dateString.prefix(10)).split(separator: "-")
        if parts.count >= 3 {
            let month = Int(parts[1]) ?? 0
            let day = Int(parts[2]) ?? 0
            return "\(month)/\(day)"
        }
        return dateString
    }

    /// Format relative time: "刚刚", "3 分钟前", "1 小时前"
    static func formatRelativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        return "\(Int(interval / 86400)) 天前"
    }

    /// Format hour key for chart axis: "yyyy-MM-ddTHH" (UTC) → local "15:00"
    static func formatHourShort(_ hourKey: String) -> String {
        let normalized = "\(hourKey.prefix(13)):00:00Z"
        if let date = ISO8601Parser.date(from: normalized) {
            let hour = Calendar.current.component(.hour, from: date)
            return String(format: "%02d:00", hour)
        }
        return hourKey
    }

    /// Format a server UTC timestamp for detailed records in the user's local
    /// timezone. Keeping this conversion at the presentation edge prevents
    /// eight-hour offsets from leaking into the macOS UI.
    static func formatDateTime(_ value: String, timeZone: TimeZone = .current) -> String {
        guard let date = ISO8601Parser.date(from: value) else {
            return String(value.prefix(16)).replacingOccurrences(of: "T", with: " ")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let hour = components.hour,
              let minute = components.minute else {
            return String(value.prefix(16)).replacingOccurrences(of: "T", with: " ")
        }
        return String(format: "%04d-%02d-%02d %02d:%02d", year, month, day, hour, minute)
    }

    /// Format duration in seconds: 90 → "1m", 3661 → "1h 1m", 86400+ → "1d 2h"
    static func formatDuration(_ seconds: Int) -> String {
        if seconds <= 0 { return "0m" }
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(max(minutes, 1))m"
    }

    /// Parse "yyyy-MM-dd" to Date
    static func dateFromDayKey(_ key: String) -> Date? {
        let parts = String(key.prefix(10)).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Format the gap between now and a future date: "12m", "2h 14m", "4d 18h", "已重置"
    static func formatTimeUntil(_ date: Date) -> String {
        let interval = Int(date.timeIntervalSinceNow)
        if interval <= 0 { return "已重置" }
        return formatDuration(interval)
    }

    static func dayKey(from date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func groupedDecimal(_ n: Int) -> String {
        let digits = String(n.magnitude)
        var groups: [Substring] = []
        var end = digits.endIndex

        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            groups.append(digits[start..<end])
            end = start
        }

        let value = groups.reversed().joined(separator: ",")
        return n < 0 ? "-\(value)" : value
    }
}
