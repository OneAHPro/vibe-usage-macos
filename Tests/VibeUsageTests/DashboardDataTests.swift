import Foundation
import Testing
@testable import VibeUsage

struct DashboardDataTests {
    @Test
    func firstSummaryCardUsesStatisticalConsumptionLabel() {
        #expect(SummaryCardLabels.statisticalConsumption == "统计消耗")
    }

    @Test
    func filtersAndCalculatesAllDashboardMetrics() {
        let includedBucket = bucket(
            source: "codex",
            project: "radar",
            bucketStart: "2026-07-16T09:00:00Z",
            input: 30,
            output: 10,
            reasoning: 5,
            cached: 180,
            cost: 3.5
        )
        let excludedBucket = bucket(
            source: "claude",
            project: "other",
            bucketStart: "2026-07-16T10:00:00Z",
            input: 900,
            output: 900,
            reasoning: 0,
            cached: 0,
            cost: 99
        )
        let includedSession = session(
            source: "codex",
            project: "radar",
            firstMessageAt: "2026-07-16T09:10:00Z",
            duration: 300,
            active: 120,
            messages: 8,
            userMessages: 3
        )
        let excludedSession = session(
            source: "claude",
            project: "other",
            firstMessageAt: "2026-07-16T10:10:00Z",
            duration: 999,
            active: 999,
            messages: 99,
            userMessages: 50
        )

        let data = DashboardData(
            buckets: [includedBucket, excludedBucket],
            sessions: [includedSession, excludedSession],
            cutoff: nil,
            filters: FilterState(sources: ["codex"], models: [], projects: [], hostnames: [])
        )

        #expect(data.buckets == [includedBucket])
        #expect(data.sessions == [includedSession])
        #expect(data.metrics.estimatedCost == 3.5)
        #expect(data.metrics.totalTokens == 225)
        #expect(data.metrics.inputTokens == 30)
        #expect(data.metrics.outputTokens == 15)
        #expect(data.metrics.cachedTokens == 180)
        #expect(data.metrics.activeSeconds == 120)
        #expect(data.metrics.durationSeconds == 300)
        #expect(data.metrics.sessionCount == 1)
        #expect(data.metrics.messageCount == 8)
        #expect(data.metrics.userMessageCount == 3)
        #expect(data.metrics.projectCount == 1)
    }

    @Test
    func recentBucketsAreNewestFirstAndCappedAtFifty() {
        let formatter = ISO8601DateFormatter()
        let start = formatter.date(from: "2026-07-01T00:00:00Z")!
        let buckets = (0..<55).map { offset in
            bucket(
                source: "codex",
                project: "radar",
                bucketStart: formatter.string(from: start.addingTimeInterval(TimeInterval(offset))),
                input: offset,
                output: 0,
                reasoning: 0,
                cached: 0,
                cost: 1.25
            )
        }

        let data = DashboardData(buckets: buckets, sessions: [], cutoff: nil, filters: .init())

        #expect(data.recentBuckets.count == 50)
        #expect(data.recentBuckets.map(\.bucketStart) == data.recentBuckets.map(\.bucketStart).sorted(by: >))
        #expect(data.recentBuckets.first?.inputTokens == 54)
        #expect(data.recentBuckets.last?.inputTokens == 5)
        #expect(data.recentRows.count == 50)
        #expect(data.recentRows.first?.inputTokens == "54")
        #expect(data.recentRows.first?.estimatedCost == "$1.25")
    }

    @Test
    func requestRecordsUseExactFirstResponseThresholds() {
        let records = [
            request(id: 1, createdAt: "2026-07-18T10:00:01Z", firstResponseTimeMs: 2_900),
            request(id: 2, createdAt: "2026-07-18T10:00:02Z", firstResponseTimeMs: 3_000),
            request(id: 3, createdAt: "2026-07-18T10:00:03Z", firstResponseTimeMs: 9_900),
            request(id: 4, createdAt: "2026-07-18T10:00:04Z", firstResponseTimeMs: 10_000),
        ]

        let data = DashboardData(
            buckets: [],
            sessions: [],
            recentRequests: records,
            cutoff: nil,
            filters: .init()
        )

        #expect(data.recentRows.map(\.firstResponseTime) == ["10.0 s", "9.9 s", "3.0 s", "2.9 s"])
        #expect(data.recentRows.map(\.firstResponseTier) == [.critical, .slow, .slow, .fast])
        #expect(data.recentRows.allSatisfy { $0.model == "gpt-test" })
        #expect(data.recentRows.first?.outputTokens == "30")
        #expect(data.recentRows.first?.cachedTokens == "40")
        #expect(data.recentRows.first?.estimatedCost == "$0.02")
    }

    @Test
    func absentRequestCollectionFallsBackToAggregateRowsWithUnavailableTTFT() {
        let fallback = bucket(
            source: "codex",
            project: "radar",
            bucketStart: "2026-07-18T10:00:00Z",
            input: 10,
            output: 5,
            reasoning: 0,
            cached: 2,
            cost: 0.01
        )

        let data = DashboardData(
            buckets: [fallback],
            sessions: [],
            recentRequests: nil,
            cutoff: nil,
            filters: .init()
        )

        #expect(data.recentRows.count == 1)
        #expect(data.recentRows.first?.firstResponseTime == "—")
        #expect(data.recentRows.first?.firstResponseTier == .unavailable)
    }

    @Test
    func explicitEmptyRequestCollectionDoesNotShowAggregateRows() {
        let fallback = bucket(
            source: "codex",
            project: "radar",
            bucketStart: "2026-07-18T10:00:00Z",
            input: 10,
            output: 5,
            reasoning: 0,
            cached: 2,
            cost: 0.01
        )

        let data = DashboardData(
            buckets: [fallback],
            sessions: [],
            recentRequests: [],
            cutoff: nil,
            filters: .init()
        )

        #expect(data.recentRows.isEmpty)
    }

    @Test
    func requestRecordsRespectFiltersAndRemainCappedAtFifty() {
        var records = (0..<55).map { index in
            request(
                id: index,
                createdAt: "2026-07-18T10:00:00Z",
                firstResponseTimeMs: 1_000
            )
        }
        records.append(request(
            id: 100,
            createdAt: "2026-07-18T10:00:00Z",
            firstResponseTimeMs: 1_000,
            source: "filtered-out"
        ))

        let data = DashboardData(
            buckets: [],
            sessions: [],
            recentRequests: records,
            cutoff: nil,
            filters: FilterState(
                sources: ["new-api"],
                models: ["gpt-test"],
                projects: ["radar"],
                hostnames: []
            )
        )

        #expect(data.recentRows.count == 50)
        #expect(data.recentRows.first?.id == "54")
        #expect(data.recentRows.last?.id == "5")
    }

    @Test
    func invalidFirstResponseTimeIsUnavailable() {
        let invalidValues: [Double?] = [nil, 0, -1, .infinity, .nan]

        for (index, value) in invalidValues.enumerated() {
            let row = UsageRecordRow(record: request(
                id: index,
                createdAt: "2026-07-18T10:00:00Z",
                firstResponseTimeMs: value
            ))
            #expect(row.firstResponseTime == "—")
            #expect(row.firstResponseTier == .unavailable)
        }
    }

    @Test
    func heatmapAggregatesTokensByWeekdayAndHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let buckets = [
            bucket(
                source: "codex",
                project: "radar",
                bucketStart: "2026-07-13T09:10:00Z",
                input: 120,
                output: 0,
                reasoning: 0,
                cached: 0,
                cost: 1.25
            ),
            bucket(
                source: "codex",
                project: "radar",
                bucketStart: "2026-07-13T09:50:00Z",
                input: 60,
                output: 0,
                reasoning: 0,
                cached: 0,
                cost: 0.75
            ),
            bucket(
                source: "codex",
                project: "radar",
                bucketStart: "2026-07-13T10:05:00Z",
                input: 60,
                output: 0,
                reasoning: 0,
                cached: 0,
                cost: 0.5
            ),
        ]

        let heatmap = ActivityHeatmap(buckets: buckets, calendar: calendar)

        #expect(heatmap.value(weekday: 2, hour: 9) == 180)
        #expect(heatmap.value(weekday: 2, hour: 10) == 60)
        #expect(heatmap.maximum == 180)
        #expect(heatmap.intensity(weekday: 2, hour: 9) == 1)
        #expect(abs(heatmap.intensity(weekday: 2, hour: 10) - (1.0 / 3.0)) < 0.000_001)

        let costHeatmap = ActivityHeatmap(buckets: buckets, metric: .cost, calendar: calendar)
        #expect(costHeatmap.value(weekday: 2, hour: 9) == 2)
        #expect(costHeatmap.value(weekday: 2, hour: 10) == 0.5)
        #expect(costHeatmap.intensity(weekday: 2, hour: 10) == 0.25)
        #expect(HeatmapMetric.allCases.map(\.label) == ["Token", "费用"])
    }

    @Test
    func dailyActivityUsesBackendDayKeyWithoutInventingAnHour() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let buckets = [
            bucket(
                source: "codex",
                project: "radar",
                bucketStart: "2026-07-01T00:00:00Z",
                input: 100,
                output: 0,
                reasoning: 0,
                cached: 0,
                cost: 1
            ),
            bucket(
                source: "claude",
                project: "radar",
                bucketStart: "2026-07-01T00:00:00Z",
                input: 50,
                output: 0,
                reasoning: 0,
                cached: 0,
                cost: 0.5
            ),
            bucket(
                source: "codex",
                project: "radar",
                bucketStart: "2026-07-02T00:00:00Z",
                input: 25,
                output: 0,
                reasoning: 0,
                cached: 0,
                cost: 0.25
            ),
        ]

        let tokenHeatmap = DailyActivityHeatmap(
            buckets: buckets,
            requestedStart: "2026-06-30T12:00:00Z",
            requestedEnd: "2026-07-03T12:00:00Z",
            calendar: calendar
        )
        let costHeatmap = DailyActivityHeatmap(
            buckets: buckets,
            metric: .cost,
            requestedStart: "2026-06-30T12:00:00Z",
            requestedEnd: "2026-07-03T12:00:00Z",
            calendar: calendar
        )

        #expect(tokenHeatmap.value(dayKey: "2026-07-01") == 150)
        #expect(tokenHeatmap.value(dayKey: "2026-07-02") == 25)
        #expect(tokenHeatmap.maximum == 150)
        #expect(costHeatmap.value(dayKey: "2026-07-01") == 1.5)
        #expect(tokenHeatmap.cells.contains {
            $0.dayKey == "2026-07-01" && $0.isInRequestedRange
        })
    }

    @Test
    func dailyActivityUsesMondayFirstCalendarPositions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let heatmap = DailyActivityHeatmap(
            buckets: [],
            requestedStart: "2026-07-06T00:00:00Z",
            requestedEnd: "2026-07-12T23:59:59Z",
            calendar: calendar
        )
        let monday = try #require(heatmap.cells.first { $0.dayKey == "2026-07-06" })
        let sunday = try #require(heatmap.cells.first { $0.dayKey == "2026-07-12" })

        #expect(monday.weekdayIndex == 0)
        #expect(monday.weekIndex == 0)
        #expect(sunday.weekdayIndex == 6)
        #expect(sunday.weekIndex == 0)
        #expect(heatmap.weekCount == 1)
    }

    @Test
    func dailyActivityMonthLabelsBelongToTheWeekStartMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let heatmap = DailyActivityHeatmap(
            buckets: [],
            requestedStart: "2026-04-20T00:00:00Z",
            requestedEnd: "2026-05-10T23:59:59Z",
            calendar: calendar
        )

        #expect(heatmap.monthLabel(forWeekIndex: 0) == "4月")
        #expect(heatmap.monthLabel(forWeekIndex: 1) == nil)
        #expect(heatmap.monthLabel(forWeekIndex: 2) == "5月")
    }

    @Test
    func dailyActivityPartialFirstWeekStillUsesItsMondayMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let heatmap = DailyActivityHeatmap(
            buckets: [],
            requestedStart: "2026-05-01T00:00:00Z",
            requestedEnd: "2026-05-10T23:59:59Z",
            calendar: calendar
        )

        #expect(heatmap.monthLabel(forWeekIndex: 0) == "4月")
        #expect(heatmap.monthLabel(forWeekIndex: 1) == "5月")
    }

    @Test
    func monthlyActivityCombinesBucketsByBackendMonthKey() {
        let heatmap = MonthlyActivityHeatmap(buckets: [
            bucket(
                source: "codex",
                project: "radar",
                bucketStart: "2026-06-01T00:00:00Z",
                input: 100,
                output: 0,
                reasoning: 0,
                cached: 0,
                cost: 1
            ),
            bucket(
                source: "claude",
                project: "radar",
                bucketStart: "2026-06-01T00:00:00Z",
                input: 50,
                output: 0,
                reasoning: 0,
                cached: 0,
                cost: 0.5
            ),
            bucket(
                source: "codex",
                project: "radar",
                bucketStart: "2026-07-01T00:00:00Z",
                input: 25,
                output: 0,
                reasoning: 0,
                cached: 0,
                cost: 0.25
            ),
        ])

        #expect(heatmap.months.map(\.monthKey) == ["2026-06", "2026-07"])
        #expect(heatmap.months[0].value == 150)
        #expect(heatmap.maximum == 150)
    }

    @Test
    func monthlyActivityBuildsTwelveMonthRowsForEachYear() throws {
        let heatmap = MonthlyActivityHeatmap(buckets: [
            bucket(
                source: "codex",
                project: "radar",
                bucketStart: "2026-03-01T00:00:00Z",
                input: 30,
                output: 0,
                reasoning: 0,
                cached: 0,
                cost: 0.3
            ),
            bucket(
                source: "codex",
                project: "radar",
                bucketStart: "2026-07-01T00:00:00Z",
                input: 70,
                output: 0,
                reasoning: 0,
                cached: 0,
                cost: 0.7
            ),
        ])

        let year = try #require(heatmap.years.first)
        #expect(heatmap.years.count == 1)
        #expect(year.year == 2026)
        #expect(year.months.map(\.month) == Array(1...12))
        #expect(year.months[0].hasData == false)
        #expect(year.months[2].monthKey == "2026-03")
        #expect(year.months[2].value == 30)
        #expect(year.months[2].hasData)
        #expect(year.months[6].monthKey == "2026-07")
        #expect(year.months[6].value == 70)
        #expect(year.months[7].hasData == false)
    }

    @Test
    func activityPresentationMatchesTheBackendGranularity() {
        let buckets = [bucket(
            source: "codex",
            project: "radar",
            bucketStart: "2026-07-01T00:00:00Z",
            input: 25,
            output: 0,
            reasoning: 0,
            cached: 0,
            cost: 0.25
        )]

        let legacy = ActivityPresentation.make(buckets: buckets, coverage: nil)
        let daily = ActivityPresentation.make(
            buckets: buckets,
            coverage: coverage(.day)
        )
        let monthly = ActivityPresentation.make(
            buckets: buckets,
            coverage: coverage(.month)
        )
        let mixed = ActivityPresentation.make(
            buckets: buckets,
            coverage: coverage(.mixed)
        )

        #expect(legacy.title == "分时活跃")
        #expect(daily.title == "每日活跃")
        #expect(monthly.title == "每月活跃")
        #expect(mixed.title == "活跃分布")
        #expect(mixed.unavailableMessage == "当前范围包含不同统计粒度")
    }

    @Test
    func parsesFractionalSecondTimestampsReturnedByUsageAPI() {
        let apiSession = session(
            source: "codex",
            project: "radar",
            firstMessageAt: "2026-07-15T10:44:39.051Z",
            duration: 1_485,
            active: 1_485,
            messages: 2,
            userMessages: 1
        )
        let apiBucket = bucket(
            source: "codex",
            project: "radar",
            bucketStart: "2026-07-15T10:00:00.000Z",
            input: 1,
            output: 1,
            reasoning: 0,
            cached: 0,
            cost: 0
        )

        #expect(apiSession.date != nil)
        #expect(apiBucket.date != nil)
    }

    @Test
    func secondaryCardsMatchNewSystemMetricSemantics() {
        let metrics = SecondaryDashboardMetrics(
            accountUsedQuota: 750_000,
            accountRequestCount: 321,
            quotaPerUnit: 500_000,
            statisticalTokens: 120_000,
            selectedRequestCount: 60,
            selectedRangeMinutes: 120
        )

        #expect(metrics.historicalConsumption == 1.5)
        #expect(metrics.requestCount == 321)
        #expect(metrics.statisticalTokens == 120_000)
        #expect(metrics.averageTPM == 1_000)
        #expect(metrics.averageRPM == 0.5)
    }

    @Test
    func secondaryCardsAvoidDivisionByZero() {
        let metrics = SecondaryDashboardMetrics(
            accountUsedQuota: 1,
            accountRequestCount: 2,
            quotaPerUnit: 0,
            statisticalTokens: 3,
            selectedRequestCount: 4,
            selectedRangeMinutes: 0
        )

        #expect(metrics.historicalConsumption == 0)
        #expect(metrics.averageTPM == 0)
        #expect(metrics.averageRPM == 0)
    }

    private func bucket(
        source: String,
        project: String,
        bucketStart: String,
        input: Int,
        output: Int,
        reasoning: Int,
        cached: Int,
        cost: Double
    ) -> UsageBucket {
        UsageBucket(
            source: source,
            model: "gpt-test",
            project: project,
            hostname: "studio",
            bucketStart: bucketStart,
            inputTokens: input,
            outputTokens: output,
            cacheCreationInputTokens: nil,
            cachedInputTokens: cached,
            reasoningOutputTokens: reasoning,
            totalTokens: input + output + reasoning + cached,
            estimatedCost: cost
        )
    }

    private func coverage(_ granularity: UsageGranularity) -> UsageCoverage {
        UsageCoverage(
            requestedStart: "2026-06-01T00:00:00Z",
            requestedEnd: "2026-07-31T23:59:59Z",
            dataStart: nil,
            dataEnd: nil,
            complete: true,
            granularity: granularity
        )
    }

    private func session(
        source: String,
        project: String,
        firstMessageAt: String,
        duration: Int,
        active: Int,
        messages: Int,
        userMessages: Int
    ) -> UsageSession {
        UsageSession(
            source: source,
            project: project,
            hostname: "studio",
            firstMessageAt: firstMessageAt,
            lastMessageAt: firstMessageAt,
            durationSeconds: duration,
            activeSeconds: active,
            messageCount: messages,
            userMessageCount: userMessages
        )
    }

    private func request(
        id: Int,
        createdAt: String,
        firstResponseTimeMs: Double?,
        source: String = "new-api",
        model: String = "gpt-test",
        project: String = "radar"
    ) -> UsageRequestRecord {
        UsageRequestRecord(
            id: id,
            createdAt: createdAt,
            source: source,
            model: model,
            project: project,
            inputTokens: 20,
            outputTokens: 30,
            cachedInputTokens: 40,
            reasoningOutputTokens: 0,
            totalTokens: 90,
            estimatedCost: 0.02,
            firstResponseTimeMs: firstResponseTimeMs
        )
    }
}
