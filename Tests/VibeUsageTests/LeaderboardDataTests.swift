import Foundation
import Testing
@testable import VibeUsage

struct LeaderboardDataTests {
    @Test
    func decodesTheProductionLeaderboardShape() throws {
        let json = #"{"token_total_top":[{"user_id":1,"username":"a***e","display_name":"Alice","token_used":12900000000}],"token_daily_top":[],"quota_total_top":[{"user_id":2,"username":"b*b","quota":4041360000,"token_used":11100000000}],"quota_daily_top":[],"my_daily_quota_rank":{"rank":7,"quota":750000,"token_used":12345},"quota_yesterday_top":[],"my_yesterday_quota_rank":null,"invite_reward_top":[]}"#

        let data = try JSONDecoder().decode(LeaderboardData.self, from: Data(json.utf8))

        #expect(data.tokenTotalTop.first?.displayName == "Alice")
        #expect(data.quotaTotalTop.first?.quota == 4_041_360_000)
        #expect(data.myDailyQuotaRank?.rank == 7)
        #expect(data.myYesterdayQuotaRank == nil)
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
}
