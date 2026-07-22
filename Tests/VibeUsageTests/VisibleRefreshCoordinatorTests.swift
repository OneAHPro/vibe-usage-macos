import Foundation
import Testing
@testable import VibeUsage

@Suite(.serialized)
@MainActor
struct VisibleRefreshCoordinatorTests {
    @Test
    func hiddenWindowDoesNotRefreshAndVisibleWindowRefreshesOnlyItsTarget() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var calls: [RemoteRefreshTarget] = []
        let coordinator = makeCoordinator(
            now: { now },
            lastSuccess: { _ in nil },
            refresh: { target in
                calls.append(target)
                return .success
            }
        )

        coordinator.setActiveTarget(.usage)
        await coordinator.runAutomaticRefreshCycleForTesting()
        #expect(calls.isEmpty)

        coordinator.setWindowVisible(true)
        await coordinator.runAutomaticRefreshCycleForTesting()
        #expect(calls == [.usage])

        coordinator.setActiveTarget(.leaderboard)
        await coordinator.runAutomaticRefreshCycleForTesting()
        #expect(calls == [.usage, .leaderboard])
    }

    @Test
    func freshSnapshotSkipsAutomaticRefreshUntilSixtySecondsOld() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let refreshedAt = now
        var calls = 0
        let coordinator = makeCoordinator(
            now: { now },
            lastSuccess: { _ in refreshedAt },
            refresh: { _ in
                calls += 1
                return .success
            }
        )
        coordinator.setActiveTarget(.usage)
        coordinator.setWindowVisible(true)

        now = refreshedAt.addingTimeInterval(59)
        await coordinator.runAutomaticRefreshCycleForTesting()
        #expect(calls == 0)

        now = refreshedAt.addingTimeInterval(61)
        await coordinator.runAutomaticRefreshCycleForTesting()
        #expect(calls == 1)
    }

    @Test
    func jitterIsAlwaysBetweenFiftyFiveAndSixtyFiveSeconds() {
        #expect(VisibleRefreshCoordinator.jitteredDelay(unit: -1) == 55)
        #expect(VisibleRefreshCoordinator.jitteredDelay(unit: 0) == 55)
        #expect(VisibleRefreshCoordinator.jitteredDelay(unit: 0.5) == 60)
        #expect(VisibleRefreshCoordinator.jitteredDelay(unit: 1) == 65)
        #expect(VisibleRefreshCoordinator.jitteredDelay(unit: 2) == 65)
    }

    @Test
    func manualRefreshHasTenSecondPerTargetCooldown() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var calls: [RemoteRefreshTarget] = []
        let coordinator = makeCoordinator(
            now: { now },
            lastSuccess: { _ in now },
            refresh: { target in
                calls.append(target)
                return .success
            }
        )

        await coordinator.requestManualRefresh(.usage)
        await coordinator.requestManualRefresh(.usage)
        #expect(calls == [.usage])

        await coordinator.requestManualRefresh(.leaderboard)
        #expect(calls == [.usage, .leaderboard])

        now = now.addingTimeInterval(11)
        await coordinator.requestManualRefresh(.usage)
        #expect(calls == [.usage, .leaderboard, .usage])
    }

    @Test
    func missingRetryAfterCreatesSixtySecondTargetCooldown() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var results: [SnapshotRefreshResult] = [.rateLimited(until: nil), .success]
        var calls = 0
        let coordinator = makeCoordinator(
            now: { now },
            lastSuccess: { _ in nil },
            refresh: { _ in
                calls += 1
                return results.removeFirst()
            }
        )
        coordinator.setActiveTarget(.usage)
        coordinator.setWindowVisible(true)

        await coordinator.runAutomaticRefreshCycleForTesting()
        #expect(calls == 1)

        now = now.addingTimeInterval(59)
        await coordinator.runAutomaticRefreshCycleForTesting()
        #expect(calls == 1)

        now = now.addingTimeInterval(2)
        await coordinator.runAutomaticRefreshCycleForTesting()
        #expect(calls == 2)
    }

    @Test
    func failedAutomaticAttemptStillPreventsRestartRequestsForSixtySeconds() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let firstAttempt = now
        var calls = 0
        let coordinator = makeCoordinator(
            now: { now },
            lastSuccess: { _ in nil },
            refresh: { _ in
                calls += 1
                return .failure
            }
        )
        coordinator.setActiveTarget(.usage)
        coordinator.setWindowVisible(true)

        await coordinator.runAutomaticRefreshCycleForTesting()
        #expect(calls == 1)

        coordinator.setWindowVisible(false)
        now = firstAttempt.addingTimeInterval(59)
        coordinator.setWindowVisible(true)
        await coordinator.runAutomaticRefreshCycleForTesting()
        #expect(calls == 1)

        now = firstAttempt.addingTimeInterval(61)
        await coordinator.runAutomaticRefreshCycleForTesting()
        #expect(calls == 2)
    }

    @Test
    func resettingSessionClearsRateLimitAndAttemptState() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var results: [SnapshotRefreshResult] = [.rateLimited(until: nil), .success]
        var calls = 0
        let coordinator = makeCoordinator(
            now: { now },
            lastSuccess: { _ in nil },
            refresh: { _ in
                calls += 1
                return results.removeFirst()
            }
        )
        coordinator.setActiveTarget(.usage)
        coordinator.setWindowVisible(true)

        await coordinator.requestImmediateRefresh(.usage)
        coordinator.resetSession()
        await coordinator.runAutomaticRefreshCycleForTesting()

        #expect(calls == 2)
    }

    @Test
    func immediateRefreshRecordsAndHonorsRateLimitCooldown() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var results: [SnapshotRefreshResult] = [.rateLimited(until: nil), .success]
        var calls = 0
        let coordinator = makeCoordinator(
            now: { now },
            lastSuccess: { _ in nil },
            refresh: { _ in
                calls += 1
                return results.removeFirst()
            }
        )

        await coordinator.requestImmediateRefresh(.usage)
        #expect(calls == 1)

        now = now.addingTimeInterval(59)
        await coordinator.requestImmediateRefresh(.usage)
        #expect(calls == 1)

        now = now.addingTimeInterval(2)
        await coordinator.requestImmediateRefresh(.usage)
        #expect(calls == 2)
    }

    @Test
    func overlappingCyclesProduceOnlyOneRequest() async {
        let probe = SuspendedRefreshProbe()
        let coordinator = makeCoordinator(
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            lastSuccess: { _ in nil },
            refresh: { target in await probe.call(target) }
        )
        coordinator.setActiveTarget(.usage)
        coordinator.setWindowVisible(true)

        let first = Task { await coordinator.runAutomaticRefreshCycleForTesting() }
        await Task.yield()
        let second = Task { await coordinator.runAutomaticRefreshCycleForTesting() }
        await Task.yield()

        #expect(probe.calls == [.usage])
        probe.finish()
        await first.value
        await second.value
    }

    private func makeCoordinator(
        now: @escaping () -> Date,
        lastSuccess: @escaping VisibleRefreshCoordinator.LastSuccess,
        refresh: @escaping VisibleRefreshCoordinator.Refresh
    ) -> VisibleRefreshCoordinator {
        VisibleRefreshCoordinator(
            now: now,
            nextDelay: { 60 },
            sleep: { _ in throw CancellationError() },
            lastSuccess: lastSuccess,
            refresh: refresh,
            automaticallySchedules: false
        )
    }
}

@MainActor
private final class SuspendedRefreshProbe {
    private(set) var calls: [RemoteRefreshTarget] = []
    private var continuation: CheckedContinuation<SnapshotRefreshResult, Never>?

    func call(_ target: RemoteRefreshTarget) async -> SnapshotRefreshResult {
        calls.append(target)
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        continuation?.resume(returning: .success)
        continuation = nil
    }
}
