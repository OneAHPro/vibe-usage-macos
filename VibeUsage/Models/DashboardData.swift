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

enum FirstResponseTimeTier: Equatable {
    case fast
    case slow
    case critical
    case unavailable
}

struct UsageRecordRow: Identifiable, Equatable {
    let id: String
    let date: String
    let model: String
    let reasoningEffort: String
    let firstResponseTime: String
    let firstResponseTier: FirstResponseTimeTier
    let inputTokens: String
    let outputTokens: String
    let cachedTokens: String
    let estimatedCost: String

    init(bucket: UsageBucket) {
        id = bucket.id
        date = Formatters.formatDateTime(bucket.bucketStart)
        model = Self.displayValue(bucket.model)
        reasoningEffort = "—"
        firstResponseTime = "—"
        firstResponseTier = .unavailable
        inputTokens = Formatters.formatNumber(bucket.inputTokens)
        outputTokens = Formatters.formatNumber(bucket.outputTokens + bucket.reasoningOutputTokens)
        cachedTokens = Formatters.formatNumber(bucket.cachedInputTokens)
        estimatedCost = Formatters.formatCost(bucket.estimatedCost ?? 0)
    }

    init(record: UsageRequestRecord) {
        id = String(record.id)
        date = Formatters.formatDateTime(record.createdAt)
        model = Self.displayValue(record.model)
        reasoningEffort = Self.displayValue(record.reasoningEffort ?? "")
        (firstResponseTime, firstResponseTier) = Self.formatFirstResponseTime(
            milliseconds: record.firstResponseTimeMs
        )
        inputTokens = Formatters.formatNumber(record.inputTokens)
        outputTokens = Formatters.formatNumber(record.outputTokens + record.reasoningOutputTokens)
        cachedTokens = Formatters.formatNumber(record.cachedInputTokens)
        estimatedCost = Formatters.formatCost(record.estimatedCost ?? 0)
    }

    private static func displayValue(_ value: String) -> String {
        value.isEmpty ? "—" : value
    }

    private static func formatFirstResponseTime(
        milliseconds: Double?
    ) -> (String, FirstResponseTimeTier) {
        guard let milliseconds,
              milliseconds.isFinite,
              milliseconds > 0
        else {
            return ("—", .unavailable)
        }

        let seconds = milliseconds / 1_000
        let text = String(
            format: "%.1f s",
            locale: Locale(identifier: "en_US_POSIX"),
            seconds
        )
        if seconds < 3 {
            return (text, .fast)
        }
        if seconds < 10 {
            return (text, .slow)
        }
        return (text, .critical)
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
        recentRequests: [UsageRequestRecord]? = nil,
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
        if let recentRequests {
            let filteredRequests = recentRequests.filter { record in
                if let cutoff, let date = record.date, date < cutoff { return false }
                if !filters.sources.isEmpty && !filters.sources.contains(record.source) { return false }
                if !filters.models.isEmpty && !filters.models.contains(record.model) { return false }
                if !filters.projects.isEmpty && !filters.projects.contains(record.project) { return false }
                return true
            }
            self.recentRows = filteredRequests
                .sorted { $0.id > $1.id }
                .prefix(50)
                .map(UsageRecordRow.init)
        } else {
            self.recentRows = recentBuckets.map(UsageRecordRow.init)
        }

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

struct DailyActivityCell: Identifiable, Equatable {
    let dayKey: String
    let date: Date
    let value: Double
    let isInRequestedRange: Bool
    let weekdayIndex: Int
    let weekIndex: Int

    var id: String { dayKey }
}

struct DailyActivityHeatmap: Equatable {
    let cells: [DailyActivityCell]
    let weekCount: Int
    let maximum: Double
    private let values: [String: Double]

    init(
        buckets: [UsageBucket],
        metric: HeatmapMetric = .token,
        requestedStart: String?,
        requestedEnd: String?,
        calendar: Calendar = .current
    ) {
        var aggregated: [String: Double] = [:]
        for bucket in buckets {
            guard let dayKey = Self.dayKey(from: bucket.bucketStart) else { continue }
            aggregated[dayKey, default: 0] += Self.metricValue(bucket, metric: metric)
        }
        values = aggregated
        maximum = aggregated.values.max() ?? 0

        let availableKeys = aggregated.keys.sorted()
        let lowerKey = Self.dayKey(from: requestedStart) ?? availableKeys.first
        let upperKey = Self.dayKey(from: requestedEnd) ?? availableKeys.last
        guard let lowerKey,
              let upperKey,
              let lowerDate = Self.date(from: min(lowerKey, upperKey), calendar: calendar),
              let upperDate = Self.date(from: max(lowerKey, upperKey), calendar: calendar)
        else {
            cells = []
            weekCount = 0
            return
        }

        let requestedLowerKey = min(lowerKey, upperKey)
        let requestedUpperKey = max(lowerKey, upperKey)
        let lowerWeekday = Self.mondayFirstWeekdayIndex(for: lowerDate, calendar: calendar)
        let upperWeekday = Self.mondayFirstWeekdayIndex(for: upperDate, calendar: calendar)
        guard let gridStart = calendar.date(byAdding: .day, value: -lowerWeekday, to: lowerDate),
              let gridEnd = calendar.date(byAdding: .day, value: 6 - upperWeekday, to: upperDate)
        else {
            cells = []
            weekCount = 0
            return
        }

        let dayCount = max(calendar.dateComponents([.day], from: gridStart, to: gridEnd).day ?? 0, 0)
        var result: [DailyActivityCell] = []
        result.reserveCapacity(dayCount + 1)
        for offset in 0...dayCount {
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { continue }
            let dayKey = Self.dayKey(from: date, calendar: calendar)
            result.append(DailyActivityCell(
                dayKey: dayKey,
                date: date,
                value: aggregated[dayKey, default: 0],
                isInRequestedRange: dayKey >= requestedLowerKey && dayKey <= requestedUpperKey,
                weekdayIndex: Self.mondayFirstWeekdayIndex(for: date, calendar: calendar),
                weekIndex: offset / 7
            ))
        }
        cells = result
        weekCount = result.isEmpty ? 0 : (result.map(\.weekIndex).max() ?? 0) + 1
    }

    func value(dayKey: String) -> Double {
        values[dayKey, default: 0]
    }

    func intensity(dayKey: String) -> Double {
        guard maximum > 0 else { return 0 }
        return value(dayKey: dayKey) / maximum
    }

    func cell(weekdayIndex: Int, weekIndex: Int) -> DailyActivityCell? {
        cells.first { $0.weekdayIndex == weekdayIndex && $0.weekIndex == weekIndex }
    }

    func monthLabel(forWeekIndex weekIndex: Int) -> String? {
        let visibleWeekIndices = Set(
            cells.lazy.filter(\.isInRequestedRange).map(\.weekIndex)
        )
        guard visibleWeekIndices.contains(weekIndex),
              let month = ownershipMonth(forWeekIndex: weekIndex)
        else { return nil }

        if let previousWeek = visibleWeekIndices.filter({ $0 < weekIndex }).max(),
           ownershipMonth(forWeekIndex: previousWeek) == month {
            return nil
        }
        return "\(month)月"
    }

    private func ownershipMonth(forWeekIndex weekIndex: Int) -> Int? {
        guard let monday = cell(weekdayIndex: 0, weekIndex: weekIndex) else { return nil }
        return Int(monday.dayKey.dropFirst(5).prefix(2))
    }

    private static func dayKey(from value: String?) -> String? {
        guard let value, value.count >= 10 else { return nil }
        let key = String(value.prefix(10))
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              Int(parts[0]) != nil,
              Int(parts[1]) != nil,
              Int(parts[2]) != nil
        else { return nil }
        return key
    }

    private static func date(from dayKey: String, calendar: Calendar) -> Date? {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)
    }

    private static func dayKey(from date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            locale: Locale(identifier: "en_US_POSIX"),
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func mondayFirstWeekdayIndex(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    private static func metricValue(_ bucket: UsageBucket, metric: HeatmapMetric) -> Double {
        switch metric {
        case .token: Double(bucket.computedTotal)
        case .cost: bucket.estimatedCost ?? 0
        }
    }
}

struct MonthlyActivityValue: Identifiable, Equatable {
    let monthKey: String
    let value: Double

    var id: String { monthKey }
}

struct MonthlyActivityCell: Identifiable, Equatable {
    let year: Int
    let month: Int
    let monthKey: String
    let value: Double
    let hasData: Bool

    var id: String { monthKey }
}

struct MonthlyActivityYear: Identifiable, Equatable {
    let year: Int
    let months: [MonthlyActivityCell]

    var id: Int { year }
}

struct MonthlyActivityHeatmap: Equatable {
    let months: [MonthlyActivityValue]
    let years: [MonthlyActivityYear]
    let maximum: Double

    init(buckets: [UsageBucket], metric: HeatmapMetric = .token) {
        var aggregated: [String: Double] = [:]
        for bucket in buckets where bucket.bucketStart.count >= 7 {
            let monthKey = String(bucket.bucketStart.prefix(7))
            guard monthKey.count == 7, monthKey[monthKey.index(monthKey.startIndex, offsetBy: 4)] == "-" else {
                continue
            }
            switch metric {
            case .token:
                aggregated[monthKey, default: 0] += Double(bucket.computedTotal)
            case .cost:
                aggregated[monthKey, default: 0] += bucket.estimatedCost ?? 0
            }
        }
        months = aggregated.keys.sorted().map {
            MonthlyActivityValue(monthKey: $0, value: aggregated[$0, default: 0])
        }
        let activeValues = Dictionary(uniqueKeysWithValues: months.map {
            ($0.monthKey, $0.value)
        })
        years = Set(months.compactMap { Int($0.monthKey.prefix(4)) })
            .sorted()
            .map { year in
                MonthlyActivityYear(
                    year: year,
                    months: (1...12).map { month in
                        let monthKey = String(
                            format: "%04d-%02d",
                            locale: Locale(identifier: "en_US_POSIX"),
                            year,
                            month
                        )
                        return MonthlyActivityCell(
                            year: year,
                            month: month,
                            monthKey: monthKey,
                            value: activeValues[monthKey, default: 0],
                            hasData: activeValues[monthKey] != nil
                        )
                    }
                )
            }
        maximum = months.map(\.value).max() ?? 0
    }

    func intensity(monthKey: String) -> Double {
        guard maximum > 0,
              let value = months.first(where: { $0.monthKey == monthKey })?.value
        else { return 0 }
        return value / maximum
    }
}

enum ActivityPresentation: Equatable {
    case hourly(ActivityHeatmap)
    case daily(DailyActivityHeatmap)
    case monthly(MonthlyActivityHeatmap)
    case unavailable(String)

    var title: String {
        switch self {
        case .hourly: "分时活跃"
        case .daily: "每日活跃"
        case .monthly: "每月活跃"
        case .unavailable: "活跃分布"
        }
    }

    var unavailableMessage: String? {
        guard case .unavailable(let message) = self else { return nil }
        return message
    }

    static func make(
        buckets: [UsageBucket],
        coverage: UsageCoverage?,
        metric: HeatmapMetric = .token,
        calendar: Calendar = .current
    ) -> Self {
        switch coverage?.granularity {
        case .day:
            .daily(DailyActivityHeatmap(
                buckets: buckets,
                metric: metric,
                requestedStart: coverage?.requestedStart,
                requestedEnd: coverage?.requestedEnd,
                calendar: calendar
            ))
        case .month:
            .monthly(MonthlyActivityHeatmap(buckets: buckets, metric: metric))
        case .mixed:
            .unavailable("当前范围包含不同统计粒度")
        case .unknown(let value):
            .unavailable("暂不支持统计粒度：\(value)")
        case .hour, .none:
            .hourly(ActivityHeatmap(buckets: buckets, metric: metric, calendar: calendar))
        }
    }
}
