import Testing
import Foundation
@testable import VibeUsage

struct FormattersTests {
    @Test
    func formatsExactTokenCountForTooltip() {
        #expect(Formatters.formatExactNumber(29_821_518) == "29,821,518")
    }

    @Test
    func formatsRecordTimestampInTheUsersTimezone() throws {
        let timezone = try #require(TimeZone(identifier: "Asia/Shanghai"))

        let value = Formatters.formatDateTime("2026-07-16T01:00:00Z", timeZone: timezone)

        #expect(value == "2026-07-16 09:00")
    }

    @Test
    func formatsAverageRatesLikeTheNewSystemDashboard() {
        #expect(Formatters.formatRate(1_000) == "1000.000")
        #expect(Formatters.formatRate(0.5) == "0.500")
    }
}
