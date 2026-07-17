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
