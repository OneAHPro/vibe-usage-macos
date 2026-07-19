import Foundation

enum UsageGranularity: Equatable, Sendable, Codable {
    case hour
    case day
    case month
    case mixed
    case unknown(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "hour": self = .hour
        case "day": self = .day
        case "month": self = .month
        case "mixed": self = .mixed
        default: self = .unknown(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        let value: String
        switch self {
        case .hour: value = "hour"
        case .day: value = "day"
        case .month: value = "month"
        case .mixed: value = "mixed"
        case .unknown(let rawValue): value = rawValue
        }
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct UsageCoverage: Codable, Equatable, Sendable {
    let requestedStart: String?
    let requestedEnd: String?
    let dataStart: String?
    let dataEnd: String?
    let complete: Bool
    let granularity: UsageGranularity
}

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
    let coverage: UsageCoverage?
    let hasAnyData: Bool

    init(
        buckets: [UsageBucket],
        sessions: [UsageSession]?,
        recentRequests: [UsageRequestRecord]? = nil,
        coverage: UsageCoverage? = nil,
        hasAnyData: Bool
    ) {
        self.buckets = buckets
        self.sessions = sessions
        self.recentRequests = recentRequests
        self.coverage = coverage
        self.hasAnyData = hasAnyData
    }
}
