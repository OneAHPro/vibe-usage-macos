import Foundation
import Observation
import SwiftUI

/// Sync status for menu bar icon display
enum SyncStatus: Equatable {
    case idle
    case syncing
    case success
    case error(String)
}

enum ChartMode: String, CaseIterable {
    case token = "Token"
    case cost = "\u{8D39}\u{7528}"
    case activeTime = "\u{6D3B}\u{8DC3}"
}

enum TimeRange: String, CaseIterable, Hashable, Sendable {
    /// Local midnight → now. Fixed start, only grows as the day progresses.
    /// Split out from `.oneDay` per vibe-cafe@f5f022b — the rolling-24h
    /// window confused users who read it as "today's spend" but watched the
    /// number shrink as the earliest hour rolled off. UI label: "今天".
    case today = "today"
    /// Rolling last 24 hours. UI label is "24H" (former "1D"); raw value
    /// stays "1D" for state stability across upgrades.
    case oneDay = "1D"
    case sevenDays = "7D"
    case thirtyDays = "30D"
    case ninetyDays = "90D"
    case all = "all"

    var fixedDayCount: Int {
        switch self {
        case .today, .oneDay: 1
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .all: 1
        }
    }

    /// Trend chart bucket granularity. Hour-granularity for both today and the
    /// rolling 24h; day-granularity for the longer ranges.
    var isHourly: Bool { self == .today || self == .oneDay }

    var displayLabel: String {
        switch self {
        case .today: "今天"
        case .oneDay: "24H"
        case .all: "全部"
        default: rawValue
        }
    }

    /// Inclusive lower bound on bucket / session timestamps when this range is
    /// active. nil means "show all fetched data" (which already matches the
    /// requested window for the day-granularity ranges). Currently only
    /// `.today` tightens the client-side window below what the API returned.
    var startCutoff: Date? {
        switch self {
        case .today: return Calendar.current.startOfDay(for: Date())
        default: return nil
        }
    }
}

/// Active filter selections
struct FilterState: Equatable {
    var sources: Set<String> = []
    var models: Set<String> = []
    var projects: Set<String> = []
    var hostnames: Set<String> = []

    var isEmpty: Bool {
        sources.isEmpty && models.isEmpty && projects.isEmpty && hostnames.isEmpty
    }

    mutating func clear() {
        sources.removeAll()
        models.removeAll()
        projects.removeAll()
        hostnames.removeAll()
    }
}

@Observable
@MainActor
final class AppState {
    private struct UsageSnapshotCacheEntry {
        let response: UsageResponse
        let updatedAt: Date
    }

    private struct DashboardDerivedDataKey: Equatable {
        let generation: Int
        let range: TimeRange
        let filters: FilterState
        let cutoff: Date?
    }

    private struct ActivityHeatmapCacheKey: Equatable {
        let dashboard: DashboardDerivedDataKey
        let metric: HeatmapMetric
        let granularity: UsageGranularity?
    }

    // MARK: - Sync State
    var syncStatus: SyncStatus = .idle
    var lastSyncTime: Date?
    var lastSyncMessage: String?

    // MARK: - Dashboard Data
    var buckets: [UsageBucket] = []
    var heatmapBuckets: [UsageBucket] = []
    var sessions: [UsageSession] = []
    var recentRequests: [UsageRequestRecord]?
    var usageCoverage: UsageCoverage?
    var hasAnyData: Bool = false
    var isUsageSnapshotPreparing: Bool = false
    var isLoadingData: Bool = false
    var hasLoadedUsageData: Bool = false
    var isLoadingHeatmap: Bool = false
    var dashboardRenderGeneration: Int = 0
    var leaderboardData: LeaderboardData?
    var leaderboardUpdatedAt: Date?
    var leaderboardError: String?
    var isLoadingLeaderboard: Bool = false

    var isInitialDataLoad: Bool {
        isLoadingData && !hasLoadedUsageData && buckets.isEmpty
    }

    var isRefreshingData: Bool {
        isLoadingData && hasLoadedUsageData
    }

    var hasTrustedUsageSnapshot: Bool {
        usageCache[loadedTimeRange] != nil
    }

    var usageLoadingMessage: String {
        timeRange == .all ? "正在加载全部数据…" : "加载中"
    }

    // MARK: - Dashboard Controls
    var timeRange: TimeRange = .oneDay
    var loadedTimeRange: TimeRange = .oneDay
    var chartMode: ChartMode = .token
    var filters: FilterState = .init()

    var presentedTimeRange: TimeRange { loadedTimeRange }

    var currentQueryRange: UsageQueryRange {
        usageQueryRange(for: timeRange)
    }

    func usageQueryRange(for range: TimeRange) -> UsageQueryRange {
        switch range {
        case .today:
            return .from(Calendar.current.startOfDay(for: Date()))
        case .oneDay:
            return .days(1)
        case .sevenDays:
            return .days(7)
        case .thirtyDays:
            return .days(30)
        case .ninetyDays:
            return .days(90)
        case .all:
            return .all
        }
    }

    var selectedRangeMinutes: Double {
        let now = Date()
        if presentedTimeRange == .all {
            let firstDate = buckets.compactMap(\.date).min() ?? now
            return max(now.timeIntervalSince(firstDate) / 60, 0)
        }
        return max(usageQueryRange(for: presentedTimeRange).dateInterval(now: now).duration / 60, 0)
    }

    var visibleDayCount: Int {
        guard presentedTimeRange == .all else { return presentedTimeRange.fixedDayCount }
        let calendar = Calendar.current
        let to = calendar.startOfDay(for: Date())
        let from = buckets.compactMap(\.date).min().map { calendar.startOfDay(for: $0) } ?? to
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        return max(days + 1, 1)
    }

    private var dashboardDerivedDataKey: DashboardDerivedDataKey {
        DashboardDerivedDataKey(
            generation: dashboardRenderGeneration,
            range: presentedTimeRange,
            filters: filters,
            cutoff: presentedTimeRange.startCutoff
        )
    }

    var dashboardData: DashboardData {
        let key = dashboardDerivedDataKey
        return dashboardDataMemoizer.value(for: key) {
            DashboardData(
                buckets: buckets,
                sessions: sessions,
                recentRequests: recentRequests,
                cutoff: key.cutoff,
                filters: key.filters
            )
        }
    }

    var filteredSessions: [UsageSession] {
        dashboardData.sessions
    }

    func activityPresentation(for metric: HeatmapMetric) -> ActivityPresentation {
        let dashboardKey = dashboardDerivedDataKey
        let key = ActivityHeatmapCacheKey(
            dashboard: dashboardKey,
            metric: metric,
            granularity: usageCoverage?.granularity
        )
        return activityHeatmapMemoizer.value(for: key) {
            ActivityPresentation.make(
                buckets: dashboardData.buckets,
                coverage: usageCoverage,
                metric: metric
            )
        }
    }

    // MARK: - Config
    var isConfigured: Bool = false
    var runtimeAvailable: Bool = false
    var isCheckingSession: Bool = false
    var isAuthenticating: Bool = false
    var requiresTwoFactor: Bool = false
    var authenticationError: String?
    var accountUsername: String?
    var accountUsedQuota: Int = 0
    var accountRequestCount: Int = 0
    var quotaPerUnit: Double = 500_000

    // MARK: - Rate Limits (subscription quota for Claude + Codex)
    var codexRateLimitEnabled: Bool = false {
        didSet { UserDefaults.standard.set(codexRateLimitEnabled, forKey: "codexRateLimitEnabled") }
    }
    var rateLimits: [ProviderRateLimit] = []

    /// Enabling Claude rate-limit monitoring installs a wrapper into Claude
    /// Code's `statusLine.command` (see `StatuslineHook`). Because that edits
    /// the user's Claude settings, we gate it behind an explicit opt-in click.
    /// Persisted across launches. Once enabled, reads are auth-free local-file
    /// reads — no keychain, no network.
    var claudeRateLimitEnabled: Bool = false {
        didSet { UserDefaults.standard.set(claudeRateLimitEnabled, forKey: "claudeRateLimitEnabled") }
    }

    // MARK: - Menu Bar Display Prefs
    var showCostInMenuBar: Bool = true {
        didSet { UserDefaults.standard.set(showCostInMenuBar, forKey: "showCostInMenuBar") }
    }
    var showTokensInMenuBar: Bool = false {
        didSet { UserDefaults.standard.set(showTokensInMenuBar, forKey: "showTokensInMenuBar") }
    }

    // MARK: - Menu Bar Stats (matches current time range, no filters)

    /// Buckets within the active range's window. `.today` and `.oneDay` both
    /// fetch `days=1`, so `buckets` is identical for both — the only thing that
    /// distinguishes them is the client-side `startCutoff`. The popover views
    /// apply that cutoff; the menu bar must too, or toggling 今天 ↔ 24H leaves
    /// the menu bar stuck on the full-24h total (see vibe-cafe@f5f022b).
    private var menuBarBuckets: [UsageBucket] {
        guard let cutoff = presentedTimeRange.startCutoff else { return buckets }
        return buckets.filter { bucket in
            guard let date = bucket.date else { return true }
            return date >= cutoff
        }
    }

    var menuBarCost: Double {
        menuBarBuckets.reduce(0) { $0 + ($1.estimatedCost ?? 0) }
    }

    var menuBarTokens: Int {
        menuBarBuckets.reduce(0) { $0 + $1.computedTotal }
    }
    // MARK: - Services (initialized after launch)
    private var rateLimitCoordinator: RateLimitCoordinator?
    private var config: VibeUsageConfig?
    private let dependencies: AppStateDependencies
    private var usageCache: [TimeRange: UsageSnapshotCacheEntry] = [:]
    private var quotaPerUnitLoadedForSession = false
    private var remoteSessionGeneration: UInt = 0
    private var activeUsageRefreshID: UUID?

    @ObservationIgnored
    private let dashboardDataMemoizer = SingleEntryMemoizer<DashboardDerivedDataKey, DashboardData>()

    @ObservationIgnored
    private let activityHeatmapMemoizer = SingleEntryMemoizer<ActivityHeatmapCacheKey, ActivityPresentation>()

    @ObservationIgnored
    private lazy var visibleRefreshCoordinator = VisibleRefreshCoordinator(
        now: dependencies.now,
        lastSuccess: { [weak self] target in
            self?.lastSuccessfulRefresh(for: target)
        },
        refresh: { [weak self] target in
            guard let self else { return .failure }
            switch target {
            case .usage:
                return await self.refreshUsageSnapshot(for: self.timeRange)
            case .leaderboard:
                return await self.refreshLeaderboardSnapshot()
            case .none:
                return .failure
            }
        }
    )

    init(dependencies: AppStateDependencies = .live) {
        self.dependencies = dependencies
    }

    // MARK: - Lifecycle

    func initialize() {
        // Load menu bar prefs
        self.showCostInMenuBar = UserDefaults.standard.object(forKey: "showCostInMenuBar") as? Bool ?? true
        self.showTokensInMenuBar = UserDefaults.standard.object(forKey: "showTokensInMenuBar") as? Bool ?? false
        self.codexRateLimitEnabled = false
        self.claudeRateLimitEnabled = false
        UserDefaults.standard.set(false, forKey: "codexRateLimitEnabled")
        UserDefaults.standard.set(false, forKey: "claudeRateLimitEnabled")
        _ = StatuslineHook.uninstall()

        let loadedConfig = dependencies.loadConfig()
        self.config = loadedConfig
        self.isConfigured = loadedConfig?.isRemoteAccountConfigured == true
        self.accountUsername = loadedConfig?.username
        self.isCheckingSession = isConfigured

    }

    func restoreSession() async {
        guard let config, let userID = config.userID else {
            isCheckingSession = false
            return
        }
        isCheckingSession = true
        defer { isCheckingSession = false }

        do {
            let client = dependencies.makeClient(
                config.apiUrl ?? AppConfig.defaultApiUrl,
                userID
            )
            let user = try await client.fetchCurrentUser()
            await finishAuthentication(user, apiURL: config.apiUrl ?? AppConfig.defaultApiUrl)
        } catch {
            clearRemoteSession()
        }
    }

    func login(username: String, password: String) async {
        guard !isAuthenticating else { return }
        authenticationError = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let client = dependencies.makeClient(AppConfig.defaultApiUrl, nil)
            switch try await client.login(username: username, password: password) {
            case .requiresTwoFactor:
                accountUsername = username
                requiresTwoFactor = true
            case .authenticated(let user):
                await finishAuthentication(user, apiURL: AppConfig.defaultApiUrl)
            }
        } catch {
            authenticationError = error.localizedDescription
        }
    }

    func verifyTwoFactor(code: String) async {
        guard !isAuthenticating else { return }
        authenticationError = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let client = dependencies.makeClient(AppConfig.defaultApiUrl, nil)
            let user = try await client.verifyTwoFactor(code: code)
            await finishAuthentication(user, apiURL: AppConfig.defaultApiUrl)
        } catch {
            authenticationError = error.localizedDescription
        }
    }

    func cancelTwoFactor() {
        requiresTwoFactor = false
        authenticationError = nil
    }

    func logout() async {
        if let config, let userID = config.userID {
            let client = dependencies.makeClient(
                config.apiUrl ?? AppConfig.defaultApiUrl,
                userID
            )
            try? await client.logout()
        }
        clearRemoteSession()
    }

    func accountManagementClient() -> (any AccountManagementClient)? {
        guard let config, let userID = config.userID else { return nil }
        return APIClient(
            baseURL: config.apiUrl ?? AppConfig.defaultApiUrl,
            userID: userID
        )
    }

    func handleAccountAuthenticationFailure() {
        clearRemoteSession()
    }

    // MARK: - Sync

    func triggerSync() async {
        await refreshUsageManually()
    }

    // MARK: - Data Fetching

    func refreshLeaderboardSnapshot() async -> SnapshotRefreshResult {
        guard let client = authenticatedClient() else { return .failure }
        guard !isLoadingLeaderboard else { return .failure }
        isLoadingLeaderboard = true
        leaderboardError = nil
        defer { isLoadingLeaderboard = false }

        do {
            applyLeaderboardData(try await client.fetchLeaderboard())
            return .success
        } catch {
            if let apiError = error as? APIClient.APIError,
               case .unauthorized = apiError
            {
                clearRemoteSession()
            } else if let apiError = error as? APIClient.APIError,
                      case .rateLimited(let retryAfter) = apiError
            {
                leaderboardError = error.localizedDescription
                return .rateLimited(until: retryAfter)
            } else {
                leaderboardError = error.localizedDescription
            }
            return .failure
        }
    }

    func applyLeaderboardData(
        _ data: LeaderboardData,
        updatedAt: Date? = nil
    ) {
        leaderboardData = data
        leaderboardUpdatedAt = updatedAt ?? dependencies.now()
        leaderboardError = nil
    }

    func refreshUsageSnapshot(for range: TimeRange) async -> SnapshotRefreshResult {
        guard let client = authenticatedClient() else { return .failure }
        guard let requestedUserID = config?.userID else { return .failure }
        guard !isLoadingData else { return .failure }
        let requestedSessionGeneration = remoteSessionGeneration
        let refreshID = UUID()
        activeUsageRefreshID = refreshID
        isLoadingData = true
        defer {
            if activeUsageRefreshID == refreshID {
                activeUsageRefreshID = nil
                hasLoadedUsageData = true
                isLoadingData = false
            }
        }
        await Task.yield()

        isLoadingHeatmap = true
        let requestedQueryRange = usageQueryRange(for: range)

        do {
            let response = try await client.fetchUsage(range: requestedQueryRange)
            guard requestedSessionGeneration == remoteSessionGeneration,
                  config?.userID == requestedUserID
            else {
                return .failure
            }
            guard applyUsageResponse(response, for: range) else {
                syncStatus = .idle
                lastSyncMessage = "new 系统正在准备统计快照"
                isLoadingHeatmap = false
                authenticationError = nil
                return .failure
            }
            syncStatus = syncStatus == .syncing ? .syncing : .idle
            lastSyncTime = dependencies.now()
            lastSyncMessage = "new 系统数据已更新"
            isLoadingHeatmap = false
            authenticationError = nil
            return .success
        } catch {
            guard requestedSessionGeneration == remoteSessionGeneration,
                  config?.userID == requestedUserID
            else {
                return .failure
            }
            isLoadingHeatmap = false
            if usageCache[range] == nil {
                timeRange = loadedTimeRange
            }
            if let apiError = error as? APIClient.APIError, case .unauthorized = apiError {
                clearRemoteSession()
            } else if let apiError = error as? APIClient.APIError,
                      case .rateLimited(let retryAfter) = apiError
            {
                syncStatus = .error(error.localizedDescription)
                lastSyncMessage = error.localizedDescription
                return .rateLimited(until: retryAfter)
            } else {
                syncStatus = .error(error.localizedDescription)
                lastSyncMessage = error.localizedDescription
            }
            return .failure
        }
    }

    @discardableResult
    func applyUsageResponse(
        _ response: UsageResponse,
        for range: TimeRange,
        updatedAt: Date? = nil
    ) -> Bool {
        let containsUsage = usageResponseContainsUsage(response)
        guard response.coverage?.complete != false || containsUsage else {
            isUsageSnapshotPreparing = true
            return false
        }
        isUsageSnapshotPreparing = false
        usageCache[range] = UsageSnapshotCacheEntry(
            response: response,
            updatedAt: updatedAt ?? dependencies.now()
        )
        presentUsageResponse(response, for: range)
        return true
    }

    func selectTimeRange(_ range: TimeRange) async {
        guard timeRange != range else { return }
        timeRange = range
        if let cached = usageCache[range] {
            presentUsageResponse(cached.response, for: range)
            if dependencies.now().timeIntervalSince(cached.updatedAt) <= 60 {
                return
            }
        }
        await visibleRefreshCoordinator.requestImmediateRefresh(.usage)
        if usageCache[range] == nil {
            timeRange = loadedTimeRange
        }
    }

    private func presentUsageResponse(_ response: UsageResponse, for range: TimeRange) {
        isUsageSnapshotPreparing = false
        withAnimation(.easeInOut(duration: 0.22)) {
            buckets = response.buckets
            sessions = response.sessions ?? []
            recentRequests = response.recentRequests
            usageCoverage = response.coverage
            hasAnyData = usageResponseContainsUsage(response)
            heatmapBuckets = response.buckets
            loadedTimeRange = range
            dashboardRenderGeneration &+= 1
        }
    }

    func setMainWindowVisible(_ visible: Bool) {
        visibleRefreshCoordinator.setWindowVisible(visible)
    }

    func setActiveRefreshTarget(_ target: RemoteRefreshTarget) {
        visibleRefreshCoordinator.setActiveTarget(target)
    }

    func refreshUsageManually() async {
        await visibleRefreshCoordinator.requestManualRefresh(.usage)
    }

    func refreshLeaderboardManually() async {
        await visibleRefreshCoordinator.requestManualRefresh(.leaderboard)
    }

    func stopRemoteRefresh() {
        visibleRefreshCoordinator.stop()
    }

    /// Toggle Codex quota monitoring. Codex is read-only, so disabling just
    /// stops scans and hides its snapshot.
    func setCodexRateLimitEnabled(_ enabled: Bool) async {
        guard codexRateLimitEnabled != enabled else { return }
        codexRateLimitEnabled = enabled

        if enabled {
            if rateLimitCoordinator == nil { startRateLimitCoordinator() }
            await refreshCodexRateLimit()
        } else {
            removeRateLimit(for: .codex)
        }
    }

    /// Toggle Claude quota monitoring. Only flips persisted state after the
    /// hook operation succeeds; failures leave the toggle reflecting reality.
    func setClaudeRateLimitEnabled(_ enabled: Bool) async {
        guard claudeRateLimitEnabled != enabled else { return }
        claudeRateLimitInstallError = nil

        if enabled {
            if rateLimitCoordinator == nil { startRateLimitCoordinator() }
            await enableClaudeRateLimit()
        } else {
            switch StatuslineHook.uninstall() {
            case .success:
                claudeRateLimitEnabled = false
                removeRateLimit(for: .claudeCode)
                debugLog("[rate-limit] statusline hook uninstalled; original command restored")
            case .failure(let error):
                debugLog("[rate-limit] statusline uninstall failed: \(error)")
                claudeRateLimitInstallError = error.localizedDescription
            }
        }
    }

    /// Refresh Codex rate limits unconditionally. Safe — no keychain prompts.
    /// Used by the manual "更新数据" / retry paths.
    func refreshCodexRateLimit() async {
        guard codexRateLimitEnabled else { return }
        await rateLimitCoordinator?.refreshCodex()
    }

    /// Refresh Codex rate limits only if the last fetch was over a minute ago.
    /// Used by popover-open so toggling the menu bar doesn't re-walk the
    /// Codex session tree on every click.
    func refreshCodexRateLimitIfNeeded() async {
        guard codexRateLimitEnabled else { return }
        await rateLimitCoordinator?.refreshCodexIfNeeded()
    }

    /// Refresh Claude rate limits on popover-open (debounced). Cheap local-file
    /// read now — safe to fire automatically, no prompts.
    func refreshClaudeRateLimitIfNeeded() async {
        guard claudeRateLimitEnabled else { return }
        await rateLimitCoordinator?.refreshClaudeIfNeeded()
    }

    /// Refresh both Codex and Claude. Both are auth-free local-file reads now,
    /// so this is cheap and safe to call from any user-initiated path.
    func refreshAllRateLimits() async {
        await rateLimitCoordinator?.refreshAll()
    }

    /// Enable Claude rate-limit monitoring: install the statusline wrapper into
    /// Claude Code's settings, then read whatever it has captured so far.
    /// Surfaces an install failure via the Claude card's error state.
    ///
    /// On a *fresh* enable the capture file doesn't exist yet — Claude Code only
    /// writes it on its next statusline render (typically within ~1s of any
    /// activity). So after a successful install we poll briefly and re-read, so
    /// a single 启用 click populates the card on its own instead of leaving it
    /// stuck on "disabled" until the user pokes it again.
    func enableClaudeRateLimit() async {
        debugLog("[rate-limit] enableClaudeRateLimit() called")
        switch StatuslineHook.install() {
        case .success:
            claudeRateLimitInstallError = nil
            claudeRateLimitEnabled = true
            await rateLimitCoordinator?.refreshClaude()
            debugLog("[rate-limit] statusline hook installed; Claude capture enabled")

            // Card is .disabled/.noData until Claude Code renders a statusline
            // and the wrapper writes the file. Poll up to ~6s; stop early once
            // a real snapshot lands. No-op if it was already captured.
            for attempt in 1...6 {
                if claudeRateLimitSnapshot?.status == .ok { break }
                try? await Task.sleep(for: .seconds(1))
                debugLog("[rate-limit] post-install poll attempt \(attempt)")
                await rateLimitCoordinator?.refreshClaude()
            }
        case .failure(let error):
            debugLog("[rate-limit] statusline install failed: \(error)")
            claudeRateLimitInstallError = error.localizedDescription
        }
    }

    /// Current Claude snapshot in `rateLimits` (nil before the first read).
    private var claudeRateLimitSnapshot: ProviderRateLimit? {
        rateLimits.first { $0.provider == .claudeCode }
    }

    /// Last statusline-install failure message, surfaced in the Claude card.
    /// Cleared on the next successful enable.
    var claudeRateLimitInstallError: String?

    // MARK: - Private

    private func removeRateLimit(for provider: ProviderRateLimit.Provider) {
        rateLimits.removeAll { $0.provider == provider }
    }

    private func startRateLimitCoordinator() {
        let coord = RateLimitCoordinator(appState: self)
        coord.seedPlaceholders()
        // No background loop — Codex refreshes on popover open (debounced),
        // Claude only on user-initiated actions.
        self.rateLimitCoordinator = coord
    }

    private func authenticatedClient() -> (any NewSystemClient)? {
        guard let config, let userID = config.userID else { return nil }
        return dependencies.makeClient(
            config.apiUrl ?? AppConfig.defaultApiUrl,
            userID
        )
    }

    private func loadQuotaPerUnitOnce() async {
        guard !quotaPerUnitLoadedForSession,
              let client = authenticatedClient()
        else { return }

        quotaPerUnitLoadedForSession = true
        let value = await client.fetchQuotaPerUnit()
        if value > 0 {
            quotaPerUnit = value
        }
    }

    private func lastSuccessfulRefresh(for target: RemoteRefreshTarget) -> Date? {
        switch target {
        case .none:
            return nil
        case .usage:
            return usageCache[timeRange]?.updatedAt
        case .leaderboard:
            return leaderboardUpdatedAt
        }
    }

    private func finishAuthentication(
        _ user: AuthenticatedUser,
        apiURL: String
    ) async {
        remoteSessionGeneration &+= 1
        activeUsageRefreshID = nil
        isLoadingData = false
        visibleRefreshCoordinator.resetSession()
        let config = VibeUsageConfig(
            apiKey: nil,
            apiUrl: apiURL,
            lastSync: nil,
            userID: user.id,
            username: user.username
        )
        dependencies.saveConfig(config)
        self.config = config
        accountUsername = user.displayName?.isEmpty == false ? user.displayName : user.username
        updateAccountMetrics(from: user)
        requiresTwoFactor = false
        authenticationError = nil
        await loadQuotaPerUnitOnce()
        _ = await visibleRefreshCoordinator.requestImmediateRefresh(.usage)
        guard self.config != nil else { return }
        isConfigured = true
        isCheckingSession = false
    }

    private func clearRemoteSession() {
        remoteSessionGeneration &+= 1
        activeUsageRefreshID = nil
        let apiURL = config?.apiUrl ?? AppConfig.defaultApiUrl
        if let url = URL(string: apiURL), let cookies = HTTPCookieStorage.shared.cookies(for: url) {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }

        dependencies.clearConfig()
        config = nil
        isConfigured = false
        isCheckingSession = false
        isAuthenticating = false
        requiresTwoFactor = false
        accountUsername = nil
        accountUsedQuota = 0
        accountRequestCount = 0
        quotaPerUnit = 500_000
        quotaPerUnitLoadedForSession = false
        authenticationError = nil
        buckets = []
        heatmapBuckets = []
        sessions = []
        recentRequests = nil
        usageCoverage = nil
        timeRange = .oneDay
        loadedTimeRange = .oneDay
        hasAnyData = false
        isUsageSnapshotPreparing = false
        hasLoadedUsageData = false
        isLoadingData = false
        isLoadingHeatmap = false
        leaderboardData = nil
        leaderboardUpdatedAt = nil
        leaderboardError = nil
        isLoadingLeaderboard = false
        usageCache.removeAll()
        dashboardDataMemoizer.removeAll()
        activityHeatmapMemoizer.removeAll()
        visibleRefreshCoordinator.stop()
        visibleRefreshCoordinator.resetSession()
        syncStatus = .idle
        lastSyncTime = nil
        lastSyncMessage = nil
    }

    private func usageResponseContainsUsage(_ response: UsageResponse) -> Bool {
        response.hasAnyData
            || !response.buckets.isEmpty
            || !(response.sessions?.isEmpty ?? true)
            || !(response.recentRequests?.isEmpty ?? true)
    }

    private func updateAccountMetrics(from user: AuthenticatedUser) {
        if let usedQuota = user.usedQuota {
            accountUsedQuota = max(usedQuota, 0)
        }
        if let requestCount = user.requestCount {
            accountRequestCount = max(requestCount, 0)
        }
    }
}
