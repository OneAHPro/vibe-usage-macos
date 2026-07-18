import Foundation

struct DashboardMetrics: Equatable {
    let estimatedCost: Double
    let totalTokens: Int
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let activeSeconds: Int
    let durationSeconds: Int
    let sessionCount: Int
    let messageCount: Int
    let userMessageCount: Int
    let projectCount: Int
}

/// Metrics shown in the dashboard's second card row. The new system keeps
/// account totals (consumption and request count) separate from the selected
/// time-range statistics used by Tokens, TPM, and RPM.
struct SecondaryDashboardMetrics: Equatable {
    let historicalConsumption: Double
    let requestCount: Int
    let statisticalTokens: Int
    let averageTPM: Double
    let averageRPM: Double

    init(
        accountUsedQuota: Int,
        accountRequestCount: Int,
        quotaPerUnit: Double,
        statisticalTokens: Int,
        selectedRequestCount: Int,
        selectedRangeMinutes: Double
    ) {
        historicalConsumption = quotaPerUnit > 0
            ? Double(max(accountUsedQuota, 0)) / quotaPerUnit
            : 0
        requestCount = max(accountRequestCount, 0)
        self.statisticalTokens = max(statisticalTokens, 0)
        averageTPM = selectedRangeMinutes > 0
            ? Double(max(statisticalTokens, 0)) / selectedRangeMinutes
            : 0
        averageRPM = selectedRangeMinutes > 0
            ? Double(max(selectedRequestCount, 0)) / selectedRangeMinutes
            : 0
    }
}

struct UsageRecordRow: Identifiable, Equatable {
    let id: String
    let date: String
    let hostname: String
    let source: String
    let model: String
    let inputTokens: String
    let outputTokens: String
    let cachedTokens: String
    let estimatedCost: String

    init(bucket: UsageBucket) {
        id = bucket.id
        date = Formatters.formatDateTime(bucket.bucketStart)
        hostname = Self.displayValue(bucket.hostname)
        source = Self.displayValue(bucket.source)
        model = Self.displayValue(bucket.model)
        inputTokens = Formatters.formatNumber(bucket.inputTokens)
        outputTokens = Formatters.formatNumber(bucket.outputTokens + bucket.reasoningOutputTokens)
        cachedTokens = Formatters.formatNumber(bucket.cachedInputTokens)
        estimatedCost = Formatters.formatCost(bucket.estimatedCost ?? 0)
    }

    private static func displayValue(_ value: String) -> String {
        value.isEmpty ? "—" : value
    }
}

struct DashboardData {
    let buckets: [UsageBucket]
    let sessions: [UsageSession]
    let metrics: DashboardMetrics
    let recentBuckets: [UsageBucket]
    let recentRows: [UsageRecordRow]

    init(
        buckets: [UsageBucket],
        sessions: [UsageSession],
        cutoff: Date?,
        filters: FilterState
    ) {
        let filteredBuckets = buckets.filter { bucket in
            if let cutoff, let date = bucket.date, date < cutoff { return false }
            if !filters.sources.isEmpty && !filters.sources.contains(bucket.source) { return false }
            if !filters.models.isEmpty && !filters.models.contains(bucket.model) { return false }
            if !filters.projects.isEmpty && !filters.projects.contains(bucket.project) { return false }
            if !filters.hostnames.isEmpty && !filters.hostnames.contains(bucket.hostname) { return false }
            return true
        }

        let filteredSessions = sessions.filter { session in
            if let cutoff, let date = session.date, date < cutoff { return false }
            if !filters.sources.isEmpty && !filters.sources.contains(session.source) { return false }
            if !filters.projects.isEmpty && !filters.projects.contains(session.project) { return false }
            if !filters.hostnames.isEmpty && !filters.hostnames.contains(session.hostname) { return false }
            return true
        }

        self.buckets = filteredBuckets
        self.sessions = filteredSessions
        let recentBuckets = Array(filteredBuckets.sorted { $0.bucketStart > $1.bucketStart }.prefix(50))
        self.recentBuckets = recentBuckets
        self.recentRows = recentBuckets.map(UsageRecordRow.init)

        let projects = Set(
            filteredBuckets.map(\.project).filter { !$0.isEmpty }
                + filteredSessions.map(\.project).filter { !$0.isEmpty }
        )
        self.metrics = DashboardMetrics(
            estimatedCost: filteredBuckets.reduce(0) { $0 + ($1.estimatedCost ?? 0) },
            totalTokens: filteredBuckets.reduce(0) { $0 + $1.computedTotal },
            inputTokens: filteredBuckets.reduce(0) { $0 + $1.inputTokens },
            outputTokens: filteredBuckets.reduce(0) { $0 + $1.outputTokens + $1.reasoningOutputTokens },
            cachedTokens: filteredBuckets.reduce(0) { $0 + $1.cachedInputTokens },
            activeSeconds: filteredSessions.reduce(0) { $0 + $1.activeSeconds },
            durationSeconds: filteredSessions.reduce(0) { $0 + $1.durationSeconds },
            sessionCount: filteredSessions.count,
            messageCount: filteredSessions.reduce(0) { $0 + $1.messageCount },
            userMessageCount: filteredSessions.reduce(0) { $0 + $1.userMessageCount },
            projectCount: projects.count
        )
    }
}

enum HeatmapMetric: String, CaseIterable, Equatable {
    case token
    case cost

    var label: String {
        switch self {
        case .token: "Token"
        case .cost: "费用"
        }
    }
}

struct ActivityHeatmap: Equatable {
    private let values: [Int: Double]
    let maximum: Double

    init(
        buckets: [UsageBucket],
        metric: HeatmapMetric = .token,
        calendar: Calendar = .current
    ) {
        var values: [Int: Double] = [:]
        for bucket in buckets {
            guard let date = bucket.date else { continue }
            let components = calendar.dateComponents([.weekday, .hour], from: date)
            guard let weekday = components.weekday, let hour = components.hour else { continue }
            let key = Self.key(weekday: weekday, hour: hour)
            switch metric {
            case .token:
                values[key, default: 0] += Double(bucket.computedTotal)
            case .cost:
                values[key, default: 0] += bucket.estimatedCost ?? 0
            }
        }
        self.values = values
        self.maximum = values.values.max() ?? 0
    }

    func value(weekday: Int, hour: Int) -> Double {
        values[Self.key(weekday: weekday, hour: hour), default: 0]
    }

    func intensity(weekday: Int, hour: Int) -> Double {
        guard maximum > 0 else { return 0 }
        return value(weekday: weekday, hour: hour) / maximum
    }

    private static func key(weekday: Int, hour: Int) -> Int {
        weekday * 24 + hour
    }
}
