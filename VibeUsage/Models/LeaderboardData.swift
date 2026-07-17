import Foundation

struct LeaderboardRow: Decodable, Equatable, Identifiable, Sendable {
    let userID: Int
    let username: String
    let displayName: String?
    let avatarURL: String?
    let tokenUsed: Int
    let quota: Int?

    var id: Int { userID }

    var preferredName: String {
        let display = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !display.isEmpty { return display }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return user.isEmpty ? "-" : user
    }

    enum CodingKeys: String, CodingKey {
        case username, quota
        case userID = "user_id"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case tokenUsed = "token_used"
    }
}

struct LeaderboardPersonalRank: Decodable, Equatable, Sendable {
    let rank: Int
    let quota: Int
    let tokenUsed: Int

    enum CodingKeys: String, CodingKey {
        case rank, quota
        case tokenUsed = "token_used"
    }
}

struct LeaderboardData: Decodable, Equatable, Sendable {
    let tokenTotalTop: [LeaderboardRow]
    let tokenDailyTop: [LeaderboardRow]
    let quotaTotalTop: [LeaderboardRow]
    let quotaDailyTop: [LeaderboardRow]
    let myDailyQuotaRank: LeaderboardPersonalRank?
    let quotaYesterdayTop: [LeaderboardRow]
    let myYesterdayQuotaRank: LeaderboardPersonalRank?

    enum CodingKeys: String, CodingKey {
        case tokenTotalTop = "token_total_top"
        case tokenDailyTop = "token_daily_top"
        case quotaTotalTop = "quota_total_top"
        case quotaDailyTop = "quota_daily_top"
        case myDailyQuotaRank = "my_daily_quota_rank"
        case quotaYesterdayTop = "quota_yesterday_top"
        case myYesterdayQuotaRank = "my_yesterday_quota_rank"
    }
}

enum LeaderboardPresentation {
    static func rankLabel(_ value: LeaderboardPersonalRank?) -> String {
        guard let value, value.rank > 0 else { return "未上榜" }
        return "#\(value.rank)"
    }

    static func costLabel(quota: Int, quotaPerUnit: Double) -> String {
        let divisor = quotaPerUnit > 0 ? quotaPerUnit : 500_000
        return Formatters.formatCost(Double(max(quota, 0)) / divisor)
    }
}
