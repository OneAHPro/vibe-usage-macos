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

    /// The new system is the source of truth for token normalization. Different
    /// providers account for cached and reasoning tokens differently, so the
    /// desktop must not reconstruct this value from individual fields.
    var computedTotal: Int {
        totalTokens
    }

    /// Date parsed from bucketStart ISO string
    var date: Date? {
        ISO8601Parser.date(from: bucketStart)
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

struct UsageRequestRecord: Codable, Identifiable, Equatable {
    let id: Int
    let createdAt: String
    let source: String
    let model: String
    let project: String
    let inputTokens: Int
    let outputTokens: Int
    let cachedInputTokens: Int
    let reasoningOutputTokens: Int
    let totalTokens: Int
    let estimatedCost: Double?
    let firstResponseTimeMs: Double?

    var date: Date? {
        ISO8601Parser.date(from: createdAt)
    }
}

struct UsageResponse: Codable {
    let buckets: [UsageBucket]
    let sessions: [UsageSession]?
    let recentRequests: [UsageRequestRecord]?
    let hasAnyData: Bool

    init(
        buckets: [UsageBucket],
        sessions: [UsageSession]?,
        recentRequests: [UsageRequestRecord]? = nil,
        hasAnyData: Bool
    ) {
        self.buckets = buckets
        self.sessions = sessions
        self.recentRequests = recentRequests
        self.hasAnyData = hasAnyData
    }
}
