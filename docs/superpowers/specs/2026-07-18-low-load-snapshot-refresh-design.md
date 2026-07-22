# Low-Load Snapshot Refresh Design

**Date:** 2026-07-18
**Status:** Approved for planning
**Scope:** Vibe Usage macOS app only

## Goal

Make the macOS client consume the new system's precomputed Redis-backed snapshots without creating avoidable API traffic or any fallback path that can scan database-backed logs.

The app should stay fresh while the user is actively viewing it, become network-idle as soon as the window is hidden, and keep the last successful snapshot visible when a refresh fails.

## Backend Contract

This design assumes the production new system now incrementally updates usage statistics when logs are written, stores the real-time result in Redis, serves analytics endpoints from precomputed snapshots, and persists summaries to MySQL separately.

The client must preserve that low-load architecture:

- Dashboard data comes only from `GET /api/desktop/usage`.
- Leaderboard data comes only from `GET /api/user/leaderboard`.
- The client never reconstructs analytics by paging through `GET /api/log/self`.
- A snapshot endpoint failure is an error, not permission to fall back to raw logs.
- Database implementation details remain a backend concern; the client only consumes published snapshots.

## Considered Approaches

### 1. Page-aware visible refresh — selected

Refresh only the currently visible data page approximately once per minute. Stop the refresh loop when the window is hidden, closed, or minimized. This gives active users fresh data while keeping inactive clients network-idle.

### 2. Open and manual refresh only

This creates the least traffic but leaves a continuously open dashboard stale until the user clicks refresh. It does not satisfy the agreed near-real-time experience.

### 3. Refresh all remote state once per minute

This is simple but repeatedly requests usage, account, status, and leaderboard data even when most of it is not visible. It wastes server capacity and is rejected.

## Confirmed Product Decisions

- While the main window is visible, refresh the active data page about every 60 seconds.
- Add a randomized interval between 55 and 65 seconds so many installed clients do not synchronize their requests.
- When the window becomes hidden, closed, or minimized, stop scheduling refreshes immediately.
- When the window becomes visible, refresh the active page only if its cached data is older than 60 seconds.
- The usage page refreshes only the selected time range through `/api/desktop/usage`.
- The leaderboard page refreshes only `/api/user/leaderboard`.
- The settings page has no periodic analytics refresh.
- Manual refresh remains available, is single-flight, and has a 10-second endpoint-specific cooldown.
- Failed refreshes keep the last successful data on screen.
- No code path may call `/api/log/self` as an analytics fallback.

## Refresh Architecture

Introduce one main-actor `VisibleRefreshCoordinator` owned by `AppState`. It has one responsibility: decide whether the active remote page is eligible for an automatic refresh.

The coordinator tracks:

- whether the main window is visible and not minimized;
- the active refresh target: usage, leaderboard, or none;
- the last successful refresh time for the leaderboard and for each usage time range;
- any endpoint cooldown caused by HTTP 429;
- one cancellable timer task;
- whether a request for the target is already in flight.

`MainWindowController` reports window presentation, hiding, minimization, restoration, and close-to-hide transitions. `DashboardShellView` reports changes to the selected page. The coordinator starts a loop only when both window visibility and a remote target are present.

Each loop iteration checks freshness and cooldown before calling `AppState`. After the check completes, it waits for a randomly selected 55-to-65-second delay. Replacing the fixed `SyncScheduler` removes hidden-window background synchronization and avoids synchronized client bursts.

The coordinator does not own response data, authentication, formatting, or views. Those responsibilities remain in `AppState`, `APIClient`, and SwiftUI views.

## Request and Cache Policy

### Usage dashboard

Usage snapshots are cached in memory by `TimeRange`. Each cache entry contains the response and its last successful update time.

- Selecting an uncached range requests it once.
- Returning to a range whose cache is at most 60 seconds old restores it immediately without a request.
- Returning to a stale cached range keeps the cached content visible while one refresh runs.
- An automatic usage refresh calls only `/api/desktop/usage`.
- `fetchUsageData` no longer bundles `/api/user/self` or `/api/status` into every analytics refresh.

The `all` range may call the backend snapshot endpoint, but it must never fall back to raw log pagination. The backend remains responsible for serving a bounded or pre-aggregated historical snapshot.

### Leaderboard

The existing leaderboard response remains cached in `AppState` with its successful update time.

- Entering the leaderboard refreshes only if the cached response is missing or older than 60 seconds.
- The visible refresh loop requests only `/api/user/leaderboard`.
- Leaving the leaderboard stops leaderboard refreshes even if the application window remains visible.

### Account and status

`/api/user/self` is used for login, session restoration, and an explicit account refresh. It is not part of the minute analytics loop.

`/api/status` supplies slowly changing public configuration such as `quota_per_unit`. The value is loaded once per authenticated application session and cached. A safe existing fallback may be used when status loading fails, but the app must not retry it every minute.

### Manual refresh

Manual refresh bypasses the 60-second freshness rule but not request safety:

- one request per endpoint at a time;
- repeated manual clicks within 10 seconds are ignored;
- usage refreshes only the selected range;
- leaderboard refreshes only the leaderboard snapshot.

## Lifecycle Rules

- Launch and successful session restoration may perform one account request, one status request, and one usage snapshot request.
- Repeated application activation must not create duplicate refresh tasks.
- Reopening a hidden window inside the 60-second freshness window performs no request.
- Hiding or minimizing the window cancels the scheduled loop. A request already accepted by the server may finish, but no follow-up request is scheduled.
- Restoring the window reuses the same coordinator and cache.
- Quitting cancels the coordinator before application teardown.

## Error and Rate-Limit Handling

- `401` retains the existing expired-session behavior.
- `404`, `400`, timeouts, decoding failures, and server errors keep stale data visible and expose the existing compact error state.
- No error triggers `/api/log/self` or any other analytics fallback.
- `429` is represented as a dedicated API error carrying the parsed `Retry-After` deadline when available.
- The affected target remains in cooldown until that deadline. If the header is absent, use a conservative 60-second cooldown.
- Automatic refresh does not immediately retry a failure; it waits for the next eligible loop iteration.

## Code Boundaries

- `VisibleRefreshCoordinator.swift`: visibility, active target, jittered scheduling, freshness, cooldown, and single-flight decisions.
- `MainWindowController.swift`: reports real window visibility and minimization changes.
- `DashboardShellView.swift`: reports the selected refresh target.
- `AppState.swift`: owns usage caches, leaderboard cache, request state, and application of successful responses.
- `APIClient.swift`: performs snapshot requests, removes the raw-log fallback, and parses rate-limit responses.
- `SyncScheduler.swift`: removed once no production code depends on it.

No backend source or deployment configuration is changed by this work.

## Testing

Automated tests must prove:

- a visible usage page schedules only usage snapshot requests;
- a visible leaderboard schedules only leaderboard snapshot requests;
- settings and hidden or minimized windows schedule no analytics requests;
- reopening within 60 seconds performs no request;
- stale data causes one request and never overlapping requests;
- jittered scheduling remains within 55 to 65 seconds using injected deterministic timing;
- rapid manual refresh attempts produce at most one request per 10 seconds;
- range caches prevent a fresh range from being fetched twice;
- a 404 or 400 from `/api/desktop/usage` never calls `/api/log/self`;
- a 429 pauses only the affected target until `Retry-After` expires;
- failed refreshes retain the last successful usage or leaderboard snapshot;
- session restoration does not request `/api/user/self` twice;
- a periodic usage refresh does not request `/api/user/self` or `/api/status`.

Final verification includes the full Swift test suite, Release build, signature validation, installation into `/Applications/Vibe Usage.app`, and an observed request-count check for visible, hidden, page-switching, manual-refresh, and endpoint-failure scenarios.

## Acceptance Criteria

- Hidden or minimized for ten minutes: zero analytics requests.
- Reopened with data less than 60 seconds old: zero analytics requests.
- Visible usage page for five minutes: at most six successful usage snapshot requests, including a possible initial stale-data request, and no leaderboard, account, status, or log-list requests from the timer.
- Visible leaderboard for five minutes: at most six leaderboard snapshot requests, including a possible initial stale-data request, and no usage or log-list requests from the timer.
- One automatic refresh produces one snapshot request.
- Snapshot endpoint failure produces no raw-log requests.
- No two requests for the same target overlap.
- Database scans cannot be initiated by a client fallback path.
- The last successful data remains usable during refreshes and transient failures.

## Non-Goals

- Changing new system analytics storage, Redis, MySQL persistence, or snapshot generation.
- Adding push notifications, WebSockets, or server-sent events.
- Persisting full analytics snapshots across application launches.
- Changing dashboard visuals, leaderboard layout, or ranking semantics.
