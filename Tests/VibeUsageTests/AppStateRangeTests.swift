import Foundation
import Testing
@testable import VibeUsage

@MainActor
struct AppStateRangeTests {
    @Test
    func rangeSelectorLabelsTheCompleteHistoryOptionAsAll() {
        #expect(TimeRange.allCases.last == .all)
        #expect(TimeRange.all.displayLabel == "全部")
    }

    @Test
    func chartsKeepUsingTheLoadedRangeUntilNewDataIsCommitted() {
        let state = AppState()
        state.loadedTimeRange = .ninetyDays
        state.timeRange = .sevenDays

        #expect(state.presentedTimeRange == .ninetyDays)

        state.applyUsageResponse(
            UsageResponse(buckets: [], sessions: [], hasAnyData: false),
            for: .sevenDays
        )

        #expect(state.presentedTimeRange == .sevenDays)
    }

    @Test
    func committingNewRangeInvalidatesTheDashboardRenderTree() {
        let state = AppState()
        let generation = state.dashboardRenderGeneration

        state.applyUsageResponse(
            UsageResponse(buckets: [], sessions: [], hasAnyData: false),
            for: .oneDay
        )

        #expect(state.dashboardRenderGeneration == generation + 1)
    }

    @Test
    func committingUsageResponsePreservesRequestRecords() {
        let request = UsageRequestRecord(
            id: 91,
            createdAt: "2026-07-18T10:00:00Z",
            source: "new-api",
            model: "gpt-5.6-sol",
            project: "pro",
            inputTokens: 10,
            outputTokens: 20,
            cachedInputTokens: 30,
            reasoningOutputTokens: 0,
            totalTokens: 60,
            estimatedCost: 0.01,
            firstResponseTimeMs: 2_400,
            reasoningEffort: "High"
        )
        let state = AppState()

        state.applyUsageResponse(
            UsageResponse(
                buckets: [],
                sessions: [],
                recentRequests: [request],
                hasAnyData: true
            ),
            for: .oneDay
        )

        #expect(state.recentRequests == [request])
        #expect(state.dashboardData.recentRows.first?.reasoningEffort == "High")
        #expect(state.dashboardData.recentRows.first?.firstResponseTime == "2.4 s")
    }

    @Test
    func applyingCoverageChangesActivityPresentation() {
        let state = AppState()
        let hourlyCoverage = UsageCoverage(
            requestedStart: "2026-07-12T00:00:00Z",
            requestedEnd: "2026-07-19T00:00:00Z",
            dataStart: nil,
            dataEnd: nil,
            complete: true,
            granularity: .hour
        )
        let dailyCoverage = UsageCoverage(
            requestedStart: "2026-06-19T00:00:00Z",
            requestedEnd: "2026-07-19T00:00:00Z",
            dataStart: nil,
            dataEnd: nil,
            complete: true,
            granularity: .day
        )

        state.applyUsageResponse(
            UsageResponse(
                buckets: [],
                sessions: [],
                coverage: hourlyCoverage,
                hasAnyData: false
            ),
            for: .sevenDays
        )
        #expect(state.activityPresentation(for: .token).title == "分时活跃")

        state.applyUsageResponse(
            UsageResponse(
                buckets: [],
                sessions: [],
                coverage: dailyCoverage,
                hasAnyData: false
            ),
            for: .thirtyDays
        )
        #expect(state.activityPresentation(for: .token).title == "每日活跃")
        #expect(state.usageCoverage == dailyCoverage)
    }

    @Test
    func incompleteSnapshotDoesNotReplaceLastCompleteUsage() {
        let state = AppState()
        let bucket = UsageBucket(
            source: "new-api",
            model: "gpt-5.6-sol",
            project: "pro",
            hostname: "api.anhepro.com",
            bucketStart: "2026-07-22T08:00:00Z",
            inputTokens: 100,
            outputTokens: 20,
            cacheCreationInputTokens: 0,
            cachedInputTokens: 10,
            reasoningOutputTokens: 0,
            totalTokens: 130,
            estimatedCost: 0.25
        )
        let completeCoverage = UsageCoverage(
            requestedStart: "2026-07-21T09:00:00Z",
            requestedEnd: "2026-07-22T09:00:00Z",
            dataStart: "2026-07-21T09:00:00Z",
            dataEnd: "2026-07-22T09:00:00Z",
            complete: true,
            granularity: .hour
        )
        state.applyUsageResponse(
            UsageResponse(
                buckets: [bucket],
                sessions: [],
                coverage: completeCoverage,
                hasAnyData: true
            ),
            for: .oneDay
        )
        let committedGeneration = state.dashboardRenderGeneration

        state.applyUsageResponse(
            UsageResponse(
                buckets: [],
                sessions: [],
                coverage: UsageCoverage(
                    requestedStart: completeCoverage.requestedStart,
                    requestedEnd: completeCoverage.requestedEnd,
                    dataStart: nil,
                    dataEnd: nil,
                    complete: false,
                    granularity: .hour
                ),
                hasAnyData: false
            ),
            for: .oneDay
        )

        #expect(state.buckets == [bucket])
        #expect(state.hasAnyData)
        #expect(state.usageCoverage == completeCoverage)
        #expect(state.dashboardRenderGeneration == committedGeneration)
        #expect(state.isUsageSnapshotPreparing)
        #expect(state.hasTrustedUsageSnapshot)
    }

    @Test
    func completeEmptySnapshotClearsPreparingAndRemainsTruthfulEmpty() {
        let state = AppState()
        let incompleteCoverage = UsageCoverage(
            requestedStart: "2026-07-21T09:00:00Z",
            requestedEnd: "2026-07-22T09:00:00Z",
            dataStart: nil,
            dataEnd: nil,
            complete: false,
            granularity: .hour
        )
        state.applyUsageResponse(
            UsageResponse(
                buckets: [],
                sessions: [],
                coverage: incompleteCoverage,
                hasAnyData: false
            ),
            for: .oneDay
        )
        #expect(state.isUsageSnapshotPreparing)

        let completeCoverage = UsageCoverage(
            requestedStart: incompleteCoverage.requestedStart,
            requestedEnd: incompleteCoverage.requestedEnd,
            dataStart: nil,
            dataEnd: nil,
            complete: true,
            granularity: .hour
        )
        state.applyUsageResponse(
            UsageResponse(
                buckets: [],
                sessions: [],
                coverage: completeCoverage,
                hasAnyData: false
            ),
            for: .oneDay
        )

        #expect(!state.isUsageSnapshotPreparing)
        #expect(state.hasTrustedUsageSnapshot)
        #expect(!state.hasAnyData)
        #expect(state.usageCoverage == completeCoverage)
    }

    @Test
    func incompleteSnapshotWithUsageRemainsDisplayable() {
        let state = AppState()
        let bucket = UsageBucket(
            source: "new-api",
            model: "gpt-5.6-sol",
            project: "pro",
            hostname: "api.anhepro.com",
            bucketStart: "2026-07-22T09:00:00Z",
            inputTokens: 100,
            outputTokens: 20,
            cacheCreationInputTokens: 0,
            cachedInputTokens: 10,
            reasoningOutputTokens: 0,
            totalTokens: 130,
            estimatedCost: 0.25
        )
        let incompleteCoverage = UsageCoverage(
            requestedStart: "2026-07-21T09:00:00Z",
            requestedEnd: "2026-07-22T09:00:30Z",
            dataStart: "2026-07-22T09:00:00Z",
            dataEnd: "2026-07-22T09:00:00Z",
            complete: false,
            granularity: .hour
        )

        let accepted = state.applyUsageResponse(
            UsageResponse(
                buckets: [bucket],
                sessions: [],
                coverage: incompleteCoverage,
                hasAnyData: false
            ),
            for: .oneDay
        )

        #expect(accepted)
        #expect(state.buckets == [bucket])
        #expect(state.hasAnyData)
        #expect(!state.isUsageSnapshotPreparing)
        #expect(state.hasTrustedUsageSnapshot)
    }

    @Test
    func allHistoryUsesExplicitLoadingCopy() {
        let state = AppState()
        state.timeRange = .all

        #expect(state.usageLoadingMessage == "正在加载全部数据…")
    }

    @Test
    func applyingLeaderboardDataClearsErrorsAndRecordsUpdateTime() {
        let state = AppState()
        let update = Date(timeIntervalSince1970: 1_700_000_000)
        let data = LeaderboardData(
            tokenTotalTop: [],
            tokenDailyTop: [],
            quotaTotalTop: [],
            quotaDailyTop: [],
            myDailyQuotaRank: nil,
            quotaYesterdayTop: [],
            myYesterdayQuotaRank: nil,
            myTotalQuotaRank: nil
        )
        state.leaderboardError = "old"

        state.applyLeaderboardData(data, updatedAt: update)

        #expect(state.leaderboardData == data)
        #expect(state.leaderboardUpdatedAt == update)
        #expect(state.leaderboardError == nil)
    }
}
