import Foundation

enum RemoteRefreshTarget: Hashable, Sendable {
    case none
    case usage
    case leaderboard
}

enum SnapshotRefreshResult: Equatable, Sendable {
    case success
    case failure
    case rateLimited(until: Date?)
}

@MainActor
final class VisibleRefreshCoordinator {
    typealias Sleep = @Sendable (TimeInterval) async throws -> Void
    typealias LastSuccess = @MainActor (RemoteRefreshTarget) -> Date?
    typealias Refresh = @MainActor (RemoteRefreshTarget) async -> SnapshotRefreshResult

    private let now: () -> Date
    private let nextDelay: () -> TimeInterval
    private let sleep: Sleep
    private let lastSuccess: LastSuccess
    private let refresh: Refresh
    private let automaticallySchedules: Bool

    private var windowVisible = false
    private var activeTarget: RemoteRefreshTarget = .none
    private var loopTask: Task<Void, Never>?
    private var inFlight: Set<RemoteRefreshTarget> = []
    private var manualAttemptAt: [RemoteRefreshTarget: Date] = [:]
    private var cooldownUntil: [RemoteRefreshTarget: Date] = [:]

    init(
        now: @escaping () -> Date = Date.init,
        nextDelay: @escaping () -> TimeInterval = {
            VisibleRefreshCoordinator.jitteredDelay(unit: Double.random(in: 0...1))
        },
        sleep: @escaping Sleep = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        },
        lastSuccess: @escaping LastSuccess,
        refresh: @escaping Refresh,
        automaticallySchedules: Bool = true
    ) {
        self.now = now
        self.nextDelay = nextDelay
        self.sleep = sleep
        self.lastSuccess = lastSuccess
        self.refresh = refresh
        self.automaticallySchedules = automaticallySchedules
    }

    static func jitteredDelay(unit: Double) -> TimeInterval {
        55 + min(max(unit, 0), 1) * 10
    }

    func setWindowVisible(_ visible: Bool) {
        guard windowVisible != visible else { return }
        windowVisible = visible
        restartLoop()
    }

    func setActiveTarget(_ target: RemoteRefreshTarget) {
        guard activeTarget != target else { return }
        activeTarget = target
        restartLoop()
    }

    func requestManualRefresh(_ target: RemoteRefreshTarget) async {
        guard target != .none else { return }
        let current = now()
        guard !isCoolingDown(target, at: current) else { return }
        if let lastAttempt = manualAttemptAt[target],
           current.timeIntervalSince(lastAttempt) < 10
        {
            return
        }
        manualAttemptAt[target] = current
        await perform(target)
    }

    func stop() {
        windowVisible = false
        loopTask?.cancel()
        loopTask = nil
    }

    func runAutomaticRefreshCycleForTesting() async {
        await runAutomaticRefreshCycle()
    }

    private func restartLoop() {
        loopTask?.cancel()
        loopTask = nil
        guard automaticallySchedules, windowVisible, activeTarget != .none else { return }

        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.runAutomaticRefreshCycle()
                do {
                    try await self.sleep(self.nextDelay())
                } catch {
                    return
                }
            }
        }
    }

    private func runAutomaticRefreshCycle() async {
        guard windowVisible, activeTarget != .none else { return }
        let target = activeTarget
        let current = now()
        guard !isCoolingDown(target, at: current) else { return }
        if let refreshedAt = lastSuccess(target),
           current.timeIntervalSince(refreshedAt) < 60
        {
            return
        }
        await perform(target)
    }

    private func perform(_ target: RemoteRefreshTarget) async {
        guard !inFlight.contains(target) else { return }
        inFlight.insert(target)
        let result = await refresh(target)
        inFlight.remove(target)

        switch result {
        case .success:
            cooldownUntil.removeValue(forKey: target)
        case .failure:
            break
        case .rateLimited(let deadline):
            cooldownUntil[target] = deadline ?? now().addingTimeInterval(60)
        }
    }

    private func isCoolingDown(_ target: RemoteRefreshTarget, at date: Date) -> Bool {
        guard let deadline = cooldownUntil[target] else { return false }
        if deadline > date { return true }
        cooldownUntil.removeValue(forKey: target)
        return false
    }
}
