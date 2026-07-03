import Foundation

struct UsageBucket: Codable, Identifiable, Equatable {
    var id: String {
        "\(bucketStart)-\(source)-\(model)-\(project)-\(hostname)"
    }

    let source: String
    let model: String
    let project: String
    let hostname: String
    let bucketStart: String
    let inputTokens: Int
    let outputTokens: Int
    /// Not yet emitted by the sync pipeline (collector and server track only
    /// cache reads); optional so decoding keeps working once it appears.
    let cacheCreationInputTokens: Int?
    let cachedInputTokens: Int
    let reasoningOutputTokens: Int
    let totalTokens: Int
    let estimatedCost: Double?

    /// Total token volume, matching the web dashboard and ccusage-style totals:
    /// input + output + reasoning + cached input.
    var computedTotal: Int {
        inputTokens + outputTokens + reasoningOutputTokens + cachedInputTokens
    }

    /// Date parsed from bucketStart ISO string
    var date: Date? {
        ISO8601DateFormatter().date(from: bucketStart)
    }

    /// Day string (yyyy-MM-dd) for grouping
    var dayKey: String {
        String(bucketStart.prefix(10))
    }

    /// Hour string (yyyy-MM-ddTHH) for hourly grouping
    var hourKey: String {
        String(bucketStart.prefix(13))
    }
}

struct UsageResponse: Codable {
    let buckets: [UsageBucket]
    let sessions: [UsageSession]?
    let hasAnyData: Bool
}
