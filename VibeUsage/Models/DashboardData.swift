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

struct DashboardData {
    let buckets: [UsageBucket]
    let sessions: [UsageSession]
    let metrics: DashboardMetrics
    let recentBuckets: [UsageBucket]

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
        self.recentBuckets = Array(filteredBuckets.sorted { $0.bucketStart > $1.bucketStart }.prefix(50))

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
