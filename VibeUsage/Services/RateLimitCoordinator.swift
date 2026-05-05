import Foundation

/// Refreshes rate-limit snapshots on demand and pushes results into AppState.
///
/// All work is local: Codex reads files, Claude calls the OAuth usage API directly.
/// Nothing is uploaded to the Vibe Usage backend. There is no background timer —
/// Codex refreshes are driven by popover-open (with a short debounce), Claude
/// refreshes happen only on user-initiated actions because they cross the
/// keychain boundary and can re-prompt after re-signing.
@MainActor
final class RateLimitCoordinator {
    private weak var appState: AppState?
    private var lastCodexFetchAt: Date?

    init(appState: AppState) {
        self.appState = appState
    }

    /// Refresh Codex unconditionally. Free, file-based, no prompts.
    /// Used by the manual "更新数据" path; popover-open should prefer the
    /// debounced `refreshCodexIfNeeded` to avoid repeat work on rapid open/close.
    func refreshCodex() async {
        let codex = await Task.detached(priority: .userInitiated) {
            CodexRateLimitReader.read()
        }.value
        upsert(codex)
        lastCodexFetchAt = Date()
    }

    /// Refresh Codex only if we haven't refreshed within `maxAge` seconds.
    /// Mirrors `fetchUsageDataIfNeeded` so popover-open doesn't hammer the
    /// session-file walk when the user toggles the popover repeatedly.
    func refreshCodexIfNeeded(maxAge: TimeInterval = 60) async {
        if let last = lastCodexFetchAt, Date().timeIntervalSince(last) < maxAge {
            return
        }
        await refreshCodex()
    }

    /// Refresh only Claude. Triggers keychain read on first call after re-signing.
    /// Must be invoked from a user-initiated context. If the user has not enabled
    /// Claude monitoring yet, this is a no-op that surfaces the disabled placeholder.
    /// Records `claudeRateLimitHasSucceeded` on the first successful fetch so the
    /// UI can distinguish "first-time auth" from "auth invalidated, re-auth needed".
    func refreshClaude() async {
        let enabled = appState?.claudeRateLimitEnabled == true
        debugLog("[rate-limit] refreshClaude() entered, enabled=\(enabled)")
        guard enabled else {
            upsert(ProviderRateLimit(provider: .claudeCode, status: .disabled, fetchedAt: nil))
            return
        }
        let snapshot = await ClaudeRateLimitReader.read()
        debugLog("[rate-limit] refreshClaude() got snapshot status=\(snapshot.status)")
        upsert(snapshot)
        if case .ok = snapshot.status {
            appState?.claudeRateLimitHasSucceeded = true
        }
    }

    /// Refresh everything currently visible. Use sparingly — only from user-initiated
    /// actions that explicitly want Claude data (footer refresh, retry buttons).
    func refreshAll() async {
        await refreshCodex()
        await refreshClaude()
    }

    /// Ensure both providers have at least a placeholder entry so the UI renders
    /// the disabled / enable affordance for Claude on first launch.
    func seedPlaceholders() {
        if appState?.rateLimits.contains(where: { $0.provider == .codex }) != true {
            upsert(ProviderRateLimit(provider: .codex, status: .noData, fetchedAt: nil))
        }
        if appState?.rateLimits.contains(where: { $0.provider == .claudeCode }) != true {
            upsert(ProviderRateLimit(provider: .claudeCode, status: .disabled, fetchedAt: nil))
        }
    }

    private func upsert(_ snapshot: ProviderRateLimit) {
        guard let appState else { return }
        var current = appState.rateLimits
        if let i = current.firstIndex(where: { $0.provider == snapshot.provider }) {
            current[i] = snapshot
        } else {
            current.append(snapshot)
        }
        appState.rateLimits = current
    }
}
