import Foundation
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

enum TimeRange: String, CaseIterable {
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
    // MARK: - Sync State
    var syncStatus: SyncStatus = .idle
    var lastSyncTime: Date?
    var lastSyncMessage: String?
    private var lastFetchTime: Date?

    // MARK: - Dashboard Data
    var buckets: [UsageBucket] = []
    var heatmapBuckets: [UsageBucket] = []
    var sessions: [UsageSession] = []
    var hasAnyData: Bool = false
    var isLoadingData: Bool = false
    var hasLoadedUsageData: Bool = false
    var isLoadingHeatmap: Bool = false
    var dashboardRenderGeneration: Int = 0

    var isInitialDataLoad: Bool {
        isLoadingData && !hasLoadedUsageData && buckets.isEmpty
    }

    var isRefreshingData: Bool {
        isLoadingData && hasLoadedUsageData
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

    var dashboardData: DashboardData {
        DashboardData(
            buckets: buckets,
            sessions: sessions,
            cutoff: presentedTimeRange.startCutoff,
            filters: filters
        )
    }

    var filteredSessions: [UsageSession] {
        dashboardData.sessions
    }

    var filteredHeatmapBuckets: [UsageBucket] {
        DashboardData(
            buckets: heatmapBuckets,
            sessions: [],
            cutoff: presentedTimeRange.startCutoff,
            filters: filters
        ).buckets
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
    private var syncScheduler: SyncScheduler?
    private var rateLimitCoordinator: RateLimitCoordinator?
    private var config: VibeUsageConfig?

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

        let loadedConfig = ConfigManager.load()
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
            let client = APIClient(baseURL: config.apiUrl ?? AppConfig.defaultApiUrl, userID: userID)
            let user = try await client.fetchCurrentUser()
            finishAuthentication(user, apiURL: config.apiUrl ?? AppConfig.defaultApiUrl)
            await fetchUsageData()
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
            let client = APIClient(baseURL: AppConfig.defaultApiUrl)
            switch try await client.login(username: username, password: password) {
            case .requiresTwoFactor:
                accountUsername = username
                requiresTwoFactor = true
            case .authenticated(let user):
                finishAuthentication(user, apiURL: AppConfig.defaultApiUrl)
                await fetchUsageData()
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
            let client = APIClient(baseURL: AppConfig.defaultApiUrl)
            let user = try await client.verifyTwoFactor(code: code)
            finishAuthentication(user, apiURL: AppConfig.defaultApiUrl)
            await fetchUsageData()
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
            let client = APIClient(baseURL: config.apiUrl ?? AppConfig.defaultApiUrl, userID: userID)
            try? await client.logout()
        }
        clearRemoteSession()
    }

    // MARK: - Sync

    func triggerSync() async {
        guard syncStatus != .syncing else { return }
        syncStatus = .syncing
        await fetchUsageData()
        guard isConfigured else { return }
        if case .error = syncStatus { return }

        syncStatus = .success
        lastSyncTime = Date()
        lastSyncMessage = "new 系统数据已更新"
        try? await Task.sleep(for: .seconds(3))
        if syncStatus == .success {
            syncStatus = .idle
        }
    }

    // MARK: - Data Fetching

    func fetchUsageData() async {
        guard let config, let userID = config.userID else { return }
        guard !isLoadingData else { return }
        isLoadingData = true
        defer {
            lastFetchTime = Date()
            hasLoadedUsageData = true
            isLoadingData = false
        }
        await Task.yield()

        let apiUrl = config.apiUrl ?? AppConfig.defaultApiUrl
        let client = APIClient(baseURL: apiUrl, userID: userID)
        isLoadingHeatmap = true
        let requestedTimeRange = timeRange
        let requestedQueryRange = usageQueryRange(for: requestedTimeRange)

        do {
            async let usageRequest = client.fetchUsage(range: requestedQueryRange)
            async let accountRequest = client.fetchCurrentUser()
            async let quotaRequest = client.fetchQuotaPerUnit()

            let response = try await usageRequest
            let refreshedUser = try? await accountRequest
            let refreshedQuotaPerUnit = await quotaRequest
            applyUsageResponse(response, for: requestedTimeRange)
            if let refreshedUser {
                updateAccountMetrics(from: refreshedUser)
            }
            if refreshedQuotaPerUnit > 0 {
                quotaPerUnit = refreshedQuotaPerUnit
            }
            syncStatus = syncStatus == .syncing ? .syncing : .idle
            lastSyncTime = Date()
            lastSyncMessage = "new 系统数据已更新"
            isLoadingHeatmap = false
            authenticationError = nil
        } catch {
            isLoadingHeatmap = false
            timeRange = loadedTimeRange
            if let apiError = error as? APIClient.APIError, case .unauthorized = apiError {
                clearRemoteSession()
            } else {
                syncStatus = .error(error.localizedDescription)
                lastSyncMessage = error.localizedDescription
            }
        }
    }

    func applyUsageResponse(_ response: UsageResponse, for range: TimeRange) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            buckets = response.buckets
            sessions = response.sessions ?? []
            hasAnyData = response.hasAnyData
            heatmapBuckets = response.buckets
            loadedTimeRange = range
            dashboardRenderGeneration &+= 1
        }
    }

    /// Fetch dashboard data unless we already fetched within the last 60s.
    /// Used by popover open to avoid hammering /api/usage on rapid open/close.
    func fetchUsageDataIfNeeded() async {
        if let last = lastFetchTime, Date().timeIntervalSince(last) < 60 {
            return
        }
        await fetchUsageData()
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

    private func startScheduler() {
        syncScheduler?.stop()
        syncScheduler = SyncScheduler(interval: 1800) { [weak self] in
            await self?.triggerSync()
        }
        syncScheduler?.start()
    }

    private func finishAuthentication(
        _ user: AuthenticatedUser,
        apiURL: String
    ) {
        let config = VibeUsageConfig(
            apiKey: nil,
            apiUrl: apiURL,
            lastSync: nil,
            userID: user.id,
            username: user.username
        )
        ConfigManager.save(config)
        self.config = config
        accountUsername = user.displayName?.isEmpty == false ? user.displayName : user.username
        updateAccountMetrics(from: user)
        isConfigured = true
        isCheckingSession = false
        requiresTwoFactor = false
        authenticationError = nil
        startScheduler()
    }

    private func clearRemoteSession() {
        let apiURL = config?.apiUrl ?? AppConfig.defaultApiUrl
        if let url = URL(string: apiURL), let cookies = HTTPCookieStorage.shared.cookies(for: url) {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }

        syncScheduler?.stop()
        syncScheduler = nil
        ConfigManager.clear()
        config = nil
        isConfigured = false
        isCheckingSession = false
        isAuthenticating = false
        requiresTwoFactor = false
        accountUsername = nil
        accountUsedQuota = 0
        accountRequestCount = 0
        quotaPerUnit = 500_000
        authenticationError = nil
        buckets = []
        heatmapBuckets = []
        sessions = []
        timeRange = .oneDay
        loadedTimeRange = .oneDay
        hasAnyData = false
        hasLoadedUsageData = false
        isLoadingData = false
        isLoadingHeatmap = false
        syncStatus = .idle
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
