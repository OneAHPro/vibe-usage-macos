import Foundation

enum ISO8601Parser {
    private static let fractionalStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let standardStyle = Date.ISO8601FormatStyle()

    static func date(from value: String) -> Date? {
        (try? fractionalStyle.parse(value)) ?? (try? standardStyle.parse(value))
    }

    static func utcHourKey(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let hour = components.hour else {
            return ""
        }
        return String(format: "%04d-%02d-%02dT%02d", year, month, day, hour)
    }
}
