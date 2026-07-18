import Foundation
import Testing
@testable import VibeUsage

@Suite(.serialized)
@MainActor
struct AppStateRefreshTests {
    @Test
    func sessionRestoreRequestsAccountStatusAndUsageExactlyOnce() async {
        let harness = makeHarness()
        harness.state.initialize()

        await harness.state.restoreSession()

        #expect(harness.client.currentUserCalls == 1)
        #expect(harness.client.statusCalls == 1)
        #expect(harness.client.usageCalls == 1)
        #expect(harness.client.requestedRanges == ["days=1"])
    }

    @Test
    func periodicUsageRefreshDoesNotRequestAccountOrStatus() async {
        let harness = makeHarness()
        harness.state.initialize()
        await harness.state.restoreSession()

        _ = await harness.state.refreshUsageSnapshot(for: .oneDay)

        #expect(harness.client.currentUserCalls == 1)
        #expect(harness.client.statusCalls == 1)
        #expect(harness.client.usageCalls == 2)
    }

    @Test
    func freshTimeRangeCacheAvoidsDuplicateSnapshotRequest() async {
        let harness = makeHarness()
        harness.state.initialize()
        await harness.state.restoreSession()

        await harness.state.selectTimeRange(.sevenDays)
        await harness.state.selectTimeRange(.oneDay)

        #expect(harness.client.requestedRanges == ["days=1", "days=7"])
        #expect(harness.state.loadedTimeRange == .oneDay)
    }

    @Test
    func staleTimeRangeCacheRefreshesAfterRestoringItsVisibleData() async {
        let harness = makeHarness()
        harness.state.initialize()
        await harness.state.restoreSession()

        await harness.state.selectTimeRange(.sevenDays)
        harness.clock.now = harness.clock.now.addingTimeInterval(61)
        await harness.state.selectTimeRange(.oneDay)

        #expect(harness.client.requestedRanges == ["days=1", "days=7", "days=1"])
        #expect(harness.state.loadedTimeRange == .oneDay)
    }

    @Test
    func failedRefreshKeepsLastSuccessfulSnapshotVisible() async {
        let harness = makeHarness()
        harness.state.initialize()
        await harness.state.restoreSession()
        let originalBuckets = harness.state.buckets
        harness.client.usageError = APIClient.APIError.httpError(500)

        let result = await harness.state.refreshUsageSnapshot(for: .oneDay)

        #expect(result == .failure)
        #expect(harness.state.buckets == originalBuckets)
        #expect(harness.state.hasAnyData)
    }

    @Test
    func rateLimitedSnapshotReturnsCoordinatorDeadlineAndKeepsData() async {
        let harness = makeHarness()
        harness.state.initialize()
        await harness.state.restoreSession()
        let originalBuckets = harness.state.buckets
        let deadline = harness.clock.now.addingTimeInterval(120)
        harness.client.usageError = APIClient.APIError.rateLimited(retryAfter: deadline)

        let result = await harness.state.refreshUsageSnapshot(for: .oneDay)

        #expect(result == .rateLimited(until: deadline))
        #expect(harness.state.buckets == originalBuckets)
    }

    @Test
    func manualUsageRefreshUsesTheCoordinatorCooldown() async {
        let harness = makeHarness()
        harness.state.initialize()
        await harness.state.restoreSession()

        await harness.state.refreshUsageManually()
        await harness.state.refreshUsageManually()
        #expect(harness.client.usageCalls == 2)

        harness.clock.now = harness.clock.now.addingTimeInterval(11)
        await harness.state.refreshUsageManually()
        #expect(harness.client.usageCalls == 3)
    }

    @Test
    func initialRateLimitPreventsImmediateManualRetry() async {
        let harness = makeHarness()
        harness.client.usageError = APIClient.APIError.rateLimited(retryAfter: nil)
        harness.state.initialize()
        await harness.state.restoreSession()
        #expect(harness.client.usageCalls == 1)

        harness.client.usageError = nil
        await harness.state.refreshUsageManually()
        #expect(harness.client.usageCalls == 1)

        harness.clock.now = harness.clock.now.addingTimeInterval(61)
        await harness.state.refreshUsageManually()
        #expect(harness.client.usageCalls == 2)
    }

    @Test
    func timeRangeSelectionHonorsExistingUsageRateLimit() async {
        let harness = makeHarness()
        harness.state.initialize()
        await harness.state.restoreSession()

        harness.client.usageError = APIClient.APIError.rateLimited(retryAfter: nil)
        await harness.state.selectTimeRange(.sevenDays)
        #expect(harness.client.usageCalls == 2)
        #expect(harness.state.timeRange == .oneDay)

        harness.client.usageError = nil
        await harness.state.selectTimeRange(.sevenDays)
        #expect(harness.client.usageCalls == 2)
        #expect(harness.state.timeRange == .oneDay)

        harness.clock.now = harness.clock.now.addingTimeInterval(61)
        await harness.state.selectTimeRange(.sevenDays)
        #expect(harness.client.usageCalls == 3)
        #expect(harness.state.timeRange == .sevenDays)
    }

    @Test
    func unauthorizedInitialSnapshotDoesNotRestoreConfiguredState() async {
        let harness = makeHarness()
        harness.client.usageError = APIClient.APIError.unauthorized
        harness.state.initialize()

        await harness.state.restoreSession()

        #expect(!harness.state.isConfigured)
        #expect(harness.state.buckets.isEmpty)
    }

    private func makeHarness() -> RefreshHarness {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        let client = MockNewSystemClient()
        let config = VibeUsageConfig(
            apiKey: nil,
            apiUrl: "https://api.anhepro.com",
            lastSync: nil,
            userID: 7,
            username: "xuande"
        )
        let dependencies = AppStateDependencies(
            loadConfig: { config },
            saveConfig: { _ in },
            clearConfig: {},
            makeClient: { _, _ in client },
            now: { clock.now }
        )
        return RefreshHarness(
            state: AppState(dependencies: dependencies),
            client: client,
            clock: clock
        )
    }
}

@MainActor
private struct RefreshHarness {
    let state: AppState
    let client: MockNewSystemClient
    let clock: TestClock
}

@MainActor
private final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

@MainActor
private final class MockNewSystemClient: NewSystemClient {
    var currentUserCalls = 0
    var statusCalls = 0
    var usageCalls = 0
    var leaderboardCalls = 0
    var requestedRanges: [String] = []
    var usageError: Error?

    func login(username: String, password: String) async throws -> LoginOutcome {
        .authenticated(Self.user)
    }

    func verifyTwoFactor(code: String) async throws -> AuthenticatedUser {
        Self.user
    }

    func fetchCurrentUser() async throws -> AuthenticatedUser {
        currentUserCalls += 1
        return Self.user
    }

    func logout() async throws {}

    func fetchLeaderboard() async throws -> LeaderboardData {
        leaderboardCalls += 1
        return LeaderboardData(
            tokenTotalTop: [],
            tokenDailyTop: [],
            quotaTotalTop: [],
            quotaDailyTop: [],
            myDailyQuotaRank: nil,
            quotaYesterdayTop: [],
            myYesterdayQuotaRank: nil,
            myTotalQuotaRank: nil
        )
    }

    func fetchUsage(range: UsageQueryRange) async throws -> UsageResponse {
        usageCalls += 1
        requestedRanges.append(
            range.queryItems
                .map { "\($0.name)=\($0.value ?? "")" }
                .sorted()
                .joined(separator: "&")
        )
        if let usageError { throw usageError }
        return Self.usage
    }

    func fetchQuotaPerUnit() async -> Double {
        statusCalls += 1
        return 500_000
    }

    private static let user = AuthenticatedUser(
        id: 7,
        username: "xuande",
        displayName: "徐安",
        role: 1,
        status: 1,
        group: "pro",
        usedQuota: 750_000,
        requestCount: 321
    )

    private static let usage = UsageResponse(
        buckets: [
            UsageBucket(
                source: "new-api",
                model: "gpt-5.6-sol",
                project: "pro",
                hostname: "api.anhepro.com",
                bucketStart: "2026-07-18T01:00:00Z",
                inputTokens: 100,
                outputTokens: 20,
                cacheCreationInputTokens: 0,
                cachedInputTokens: 10,
                reasoningOutputTokens: 0,
                totalTokens: 130,
                estimatedCost: 1.5
            ),
        ],
        sessions: [],
        hasAnyData: true
    )
}
