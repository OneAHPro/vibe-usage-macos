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

    @Test
    func formatsBillionScaleTokenCounts() {
        #expect(Formatters.formatNumber(12_900_000_000) == "12.9B")
    }

    @Test
    func formatsUnixAccountDatesWithoutDateFormatterAllocation() throws {
        let timezone = try #require(TimeZone(identifier: "Asia/Shanghai"))

        #expect(Formatters.formatUnixDate(0, timeZone: timezone) == "1970-01-01")
        #expect(Formatters.formatUnixDateTime(0, timeZone: timezone) == "1970-01-01 08:00")
    }

    @Test
    func formatsPaymentMoneyUsingItsRealCurrency() {
        #expect(Formatters.formatMoney(12.5, currency: "USD") == "$12.50")
        #expect(Formatters.formatMoney(12.5, currency: "EUR") == "€12.50")
        #expect(Formatters.formatMoney(12.5, currency: "JPY") == "JPY 12.50")
    }
}
