import Foundation
import Testing
@testable import VibeUsage

struct DashboardDataTests {
    @Test
    func filtersAndCalculatesAllDashboardMetrics() {
        let includedBucket = bucket(
            source: "codex",
            project: "radar",
            bucketStart: "2026-07-16T09:00:00Z",
            input: 30,
            output: 10,
            reasoning: 5,
            cached: 180,
            cost: 3.5
        )
        let excludedBucket = bucket(
            source: "claude",
            project: "other",
            bucketStart: "2026-07-16T10:00:00Z",
            input: 900,
            output: 900,
            reasoning: 0,
            cached: 0,
            cost: 99
        )
        let includedSession = session(
            source: "codex",
            project: "radar",
            firstMessageAt: "2026-07-16T09:10:00Z",
            duration: 300,
            active: 120,
            messages: 8,
            userMessages: 3
        )
        let excludedSession = session(
            source: "claude",
            project: "other",
            firstMessageAt: "2026-07-16T10:10:00Z",
            duration: 999,
            active: 999,
            messages: 99,
            userMessages: 50
        )

        let data = DashboardData(
            buckets: [includedBucket, excludedBucket],
            sessions: [includedSession, excludedSession],
            cutoff: nil,
            filters: FilterState(sources: ["codex"], models: [], projects: [], hostnames: [])
        )

        #expect(data.buckets == [includedBucket])
        #expect(data.sessions == [includedSession])
        #expect(data.metrics.estimatedCost == 3.5)
        #expect(data.metrics.totalTokens == 225)
        #expect(data.metrics.inputTokens == 30)
        #expect(data.metrics.outputTokens == 15)
        #expect(data.metrics.cachedTokens == 180)
        #expect(data.metrics.activeSeconds == 120)
        #expect(data.metrics.durationSeconds == 300)
        #expect(data.metrics.sessionCount == 1)
        #expect(data.metrics.messageCount == 8)
        #expect(data.metrics.userMessageCount == 3)
        #expect(data.metrics.projectCount == 1)
    }

    @Test
    func recentBucketsAreNewestFirstAndCappedAtFifty() {
        let formatter = ISO8601DateFormatter()
        let start = formatter.date(from: "2026-07-01T00:00:00Z")!
        let buckets = (0..<55).map { offset in
            bucket(
                source: "codex",
                project: "radar",
                bucketStart: formatter.string(from: start.addingTimeInterval(TimeInterval(offset))),
                input: offset,
                output: 0,
                reasoning: 0,
                cached: 0,
                cost: 0
            )
        }

        let data = DashboardData(buckets: buckets, sessions: [], cutoff: nil, filters: .init())

        #expect(data.recentBuckets.count == 50)
        #expect(data.recentBuckets.map(\.bucketStart) == data.recentBuckets.map(\.bucketStart).sorted(by: >))
        #expect(data.recentBuckets.first?.inputTokens == 54)
        #expect(data.recentBuckets.last?.inputTokens == 5)
    }

    @Test
    func heatmapAggregatesSessionsByWeekdayAndHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sessions = [
            session(
                source: "codex",
                project: "radar",
                firstMessageAt: "2026-07-13T09:10:00Z",
                duration: 180,
                active: 120,
                messages: 2,
                userMessages: 1
            ),
            session(
                source: "codex",
                project: "radar",
                firstMessageAt: "2026-07-13T09:50:00Z",
                duration: 60,
                active: 60,
                messages: 1,
                userMessages: 1
            ),
            session(
                source: "codex",
                project: "radar",
                firstMessageAt: "2026-07-13T10:05:00Z",
                duration: 60,
                active: 60,
                messages: 1,
                userMessages: 1
            ),
        ]

        let heatmap = ActivityHeatmap(sessions: sessions, calendar: calendar)

        #expect(heatmap.value(weekday: 2, hour: 9) == 180)
        #expect(heatmap.value(weekday: 2, hour: 10) == 60)
        #expect(heatmap.maximum == 180)
        #expect(heatmap.intensity(weekday: 2, hour: 9) == 1)
        #expect(abs(heatmap.intensity(weekday: 2, hour: 10) - (1.0 / 3.0)) < 0.000_001)
    }

    private func bucket(
        source: String,
        project: String,
        bucketStart: String,
        input: Int,
        output: Int,
        reasoning: Int,
        cached: Int,
        cost: Double
    ) -> UsageBucket {
        UsageBucket(
            source: source,
            model: "gpt-test",
            project: project,
            hostname: "studio",
            bucketStart: bucketStart,
            inputTokens: input,
            outputTokens: output,
            cacheCreationInputTokens: nil,
            cachedInputTokens: cached,
            reasoningOutputTokens: reasoning,
            totalTokens: input + output + reasoning + cached,
            estimatedCost: cost
        )
    }

    private func session(
        source: String,
        project: String,
        firstMessageAt: String,
        duration: Int,
        active: Int,
        messages: Int,
        userMessages: Int
    ) -> UsageSession {
        UsageSession(
            source: source,
            project: project,
            hostname: "studio",
            firstMessageAt: firstMessageAt,
            lastMessageAt: firstMessageAt,
            durationSeconds: duration,
            activeSeconds: active,
            messageCount: messages,
            userMessageCount: userMessages
        )
    }
}
