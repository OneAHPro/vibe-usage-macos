import Foundation
import Testing
@testable import VibeUsage

struct LeaderboardDataTests {
    @Test
    func decodesTheProductionLeaderboardShape() throws {
        let json = #"{"token_total_top":[{"user_id":1,"username":"a***e","display_name":"Alice","token_used":12900000000}],"token_daily_top":[],"quota_total_top":[{"user_id":2,"username":"b*b","quota":4041360000,"token_used":11100000000}],"quota_daily_top":[],"my_daily_quota_rank":{"rank":7,"quota":750000,"token_used":12345},"quota_yesterday_top":[],"my_yesterday_quota_rank":null,"my_total_quota_rank":{"rank":12,"quota":4284378646,"token_used":10780223812},"invite_reward_top":[]}"#

        let data = try JSONDecoder().decode(LeaderboardData.self, from: Data(json.utf8))

        #expect(data.tokenTotalTop.first?.displayName == "Alice")
        #expect(data.quotaTotalTop.first?.quota == 4_041_360_000)
        #expect(data.myDailyQuotaRank?.rank == 7)
        #expect(data.myYesterdayQuotaRank == nil)
        #expect(data.myTotalQuotaRank?.rank == 12)
        #expect(data.myTotalQuotaRank?.quota == 4_284_378_646)
        #expect(data.myTotalQuotaRank?.tokenUsed == 10_780_223_812)
    }

    @Test
    func decodesNullTotalPersonalRank() throws {
        let json = #"{"token_total_top":[],"token_daily_top":[],"quota_total_top":[],"quota_daily_top":[],"my_daily_quota_rank":null,"quota_yesterday_top":[],"my_yesterday_quota_rank":null,"my_total_quota_rank":null}"#

        let data = try JSONDecoder().decode(LeaderboardData.self, from: Data(json.utf8))

        #expect(data.myTotalQuotaRank == nil)
    }

    @Test
    func presentationUsesSafeNamesRanksAndQuotaConversion() {
        let named = LeaderboardRow(
            userID: 1,
            username: "masked",
            displayName: "Visible",
            avatarURL: nil,
            tokenUsed: 10,
            quota: nil
        )
        let fallback = LeaderboardRow(
            userID: 2,
            username: "masked",
            displayName: "   ",
            avatarURL: nil,
            tokenUsed: 10,
            quota: nil
        )

        #expect(named.preferredName == "Visible")
        #expect(fallback.preferredName == "masked")
        #expect(LeaderboardPresentation.rankLabel(nil) == "未上榜")
        #expect(LeaderboardPresentation.rankLabel(
            .init(rank: 7, quota: 750_000, tokenUsed: 12_345)
        ) == "#7")
        #expect(LeaderboardPresentation.costLabel(
            quota: 750_000,
            quotaPerUnit: 500_000
        ) == "$1.50")
    }

    @Test
    func splitsRankingsIntoContinuationColumns() {
        let rows = (1...10).map { rank in
            LeaderboardRow(
                userID: rank,
                username: "user_\(rank)",
                displayName: nil,
                avatarURL: nil,
                tokenUsed: rank * 100,
                quota: rank * 1_000
            )
        }

        let segments = LeaderboardPresentation.splitRows(rows, firstCount: 5)

        #expect(segments.count == 2)
        #expect(segments[0].rows.map(\.userID) == [1, 2, 3, 4, 5])
        #expect(segments[0].rankOffset == 0)
        #expect(segments[1].rows.map(\.userID) == [6, 7, 8, 9, 10])
        #expect(segments[1].rankOffset == 5)
    }
}
