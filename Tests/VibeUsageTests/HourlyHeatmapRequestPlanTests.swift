import Foundation
import Testing
@testable import VibeUsage

struct HourlyHeatmapRequestPlanTests {
    @Test
    func thirtyDayHeatmapUsesThirtyHourlyDaySlices() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = try #require(ISO8601Parser.date(from: "2026-07-16T06:00:00Z"))

        let plan = HourlyHeatmapRequestPlan(
            timeRange: .thirtyDays,
            customFrom: now,
            customTo: now,
            now: now,
            calendar: calendar
        )

        #expect(plan.ranges.count == 30)
        for range in plan.ranges {
            let query = Dictionary(uniqueKeysWithValues: range.queryItems.map { ($0.name, $0.value ?? "") })
            #expect(query["from"]?.contains("T") == true)
            #expect(query["to"]?.contains("T") == true)
        }
    }

    @Test
    func oneDayHeatmapReusesTheMainHourlyResponse() {
        let now = Date(timeIntervalSince1970: 1_784_184_400)
        let plan = HourlyHeatmapRequestPlan(
            timeRange: .oneDay,
            customFrom: now,
            customTo: now,
            now: now
        )

        #expect(plan.ranges.isEmpty)
    }
}
