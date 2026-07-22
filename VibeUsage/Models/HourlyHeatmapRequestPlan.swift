import Foundation

struct HourlyHeatmapRequestPlan {
    let ranges: [UsageQueryRange]

    init(
        timeRange: TimeRange,
        customFrom: Date,
        customTo: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard !timeRange.isHourly else {
            ranges = []
            return
        }

        guard timeRange != .all else {
            ranges = []
            return
        }

        let end = now
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(
            byAdding: .day,
            value: -(timeRange.fixedDayCount - 1),
            to: today
        ) ?? today
        let bounds = (from: start, to: end)

        var slices: [UsageQueryRange] = []
        var cursor = calendar.startOfDay(for: bounds.from)
        while cursor <= bounds.to {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            let sliceStart = max(cursor, bounds.from)
            let sliceEnd = min(nextDay.addingTimeInterval(-0.001), bounds.to)
            if sliceStart <= sliceEnd {
                slices.append(.exact(from: sliceStart, to: sliceEnd))
            }
            cursor = nextDay
        }
        ranges = slices
    }
}
