# Low-Load Snapshot Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Vibe Usage refresh only the currently visible snapshot-backed page, stop all analytics traffic while hidden, and permanently remove the raw-log pagination fallback.

**Architecture:** Replace the fixed background `SyncScheduler` with a main-actor `VisibleRefreshCoordinator` that receives window visibility and page-selection signals. `AppState` keeps per-range usage snapshots and the leaderboard snapshot, while `APIClient` performs one snapshot request per refresh and exposes rate-limit deadlines without constructing analytics from `/api/log/self`.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSWindowDelegate`, Foundation `URLSession`, Observation, Swift Testing, Swift Package Manager

---

## File Structure

- Create `VibeUsage/Services/NewSystemClient.swift`: protocol and injectable live dependencies used by `AppState` tests.
- Create `VibeUsage/Services/VisibleRefreshCoordinator.swift`: visibility-aware timer, jitter, freshness gate, manual cooldown, single-flight, and 429 cooldown.
- Create `Tests/VibeUsageTests/VisibleRefreshCoordinatorTests.swift`: deterministic coordinator behavior without real one-minute sleeps.
- Create `Tests/VibeUsageTests/AppStateRefreshTests.swift`: request separation, per-range cache, session restore, stale-data, and manual refresh behavior.
- Modify `VibeUsage/Services/APIClient.swift`: conform to the client protocol, remove raw-log fallback code, and parse `Retry-After`.
- Modify `Tests/VibeUsageTests/APIClientTests.swift`: replace fallback expectations with snapshot-only failure tests and add rate-limit tests.
- Modify `VibeUsage/Models/AppState.swift`: own refresh coordinator, caches, snapshot-only request methods, and one-time status loading.
- Modify `VibeUsage/Services/MainWindowController.swift`: report show, hide, minimize, and restore visibility.
- Modify `Tests/VibeUsageTests/MainWindowControllerTests.swift`: prove visibility transitions are reported.
- Modify `VibeUsage/Views/DashboardShellView.swift`: report the active page and use page-aware manual refresh.
- Modify `VibeUsage/Views/LeaderboardView.swift`: remove its independent load task and use the coordinated manual refresh.
- Modify `VibeUsage/Views/FilterTagsView.swift`: switch time ranges through the per-range cache API.
- Modify `VibeUsage/App/VibeUsageApp.swift`: stop the refresh coordinator during termination.
- Delete `VibeUsage/Services/SyncScheduler.swift`: fixed hidden-window background scheduling is no longer allowed.

### Task 1: Enforce snapshot-only API behavior

**Files:**
- Modify: `VibeUsage/Services/APIClient.swift`
- Modify: `Tests/VibeUsageTests/APIClientTests.swift`

- [ ] **Step 1: Replace the raw-log fallback test with a failing snapshot-only test**

Replace `missingDesktopEndpointFallsBackToExistingNewSystemLogs` with:

```swift
@Test
func missingDesktopSnapshotDoesNotRequestRawLogs() async throws {
    let session = makeSession { request in
        #expect(request.url?.path == "/api/desktop/usage")
        return response(
            for: request,
            body: #"{"error":{"message":"Invalid URL"}}"#,
            status: 404
        )
    }
    let client = APIClient(baseURL: "https://api.anhepro.com", userID: 7, session: session)

    do {
        _ = try await client.fetchUsage(range: .days(1))
        Issue.record("Expected the snapshot request to fail")
    } catch APIClient.APIError.httpError(let status) {
        #expect(status == 404)
    }
}
```

This handler fails immediately if production code attempts `/api/status` or `/api/log/self`.

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
./scripts/test.sh --filter APIClientTests.missingDesktopSnapshotDoesNotRequestRawLogs
```

Expected: FAIL because the existing client catches 404 and requests `/api/status` before raw log pages.

- [ ] **Step 3: Delete every raw-log analytics fallback path**

Remove these private APIClient-only types and methods:

```swift
RemoteUsagePage
RemoteUsageLog
RemoteUsageOther
RemoteUsageAggregateKey
RemoteUsageAggregate
fetchUsageFromExistingLogAPI(range:)
fetchRemoteUsagePage(page:interval:)
aggregateRemoteLogs(_:quotaPerUnit:hostname:)
```

Reduce `fetchUsage` to one request:

```swift
func fetchUsage(range: UsageQueryRange) async throws -> UsageResponse {
    guard var components = URLComponents(string: "\(baseURL)/api/desktop/usage") else {
        throw APIError.invalidURL
    }
    var queryItems = range.queryItems
    queryItems.append(URLQueryItem(name: "tz", value: TimeZone.current.identifier))
    components.queryItems = queryItems
    guard let url = components.url else { throw APIError.invalidURL }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 30
    if let userID {
        request.setValue(String(userID), forHTTPHeaderField: "New-Api-User")
    }

    let envelope: APIEnvelope<UsageResponse> = try await send(request: request)
    guard let usage = envelope.data else { throw APIError.invalidResponse }
    return usage
}
```

- [ ] **Step 4: Add a failing Retry-After decoding test**

Extend the response helper with headers and add:

```swift
private func response(
    for request: URLRequest,
    body: String,
    status: Int = 200,
    headers: [String: String] = [:]
) -> (HTTPURLResponse, Data) {
    var fields = headers
    fields["Content-Type"] = "application/json"
    let http = HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: nil,
        headerFields: fields
    )!
    return (http, Data(body.utf8))
}

@Test
func rateLimitCarriesRetryAfterDeadline() async throws {
    let before = Date()
    let session = makeSession { request in
        response(for: request, body: "{}", status: 429, headers: ["Retry-After": "90"])
    }
    let client = APIClient(baseURL: "https://api.anhepro.com", userID: 7, session: session)

    do {
        _ = try await client.fetchLeaderboard()
        Issue.record("Expected a rate-limit error")
    } catch APIClient.APIError.rateLimited(let retryAfter) {
        let deadline = try #require(retryAfter)
        #expect(deadline.timeIntervalSince(before) >= 89)
        #expect(deadline.timeIntervalSince(before) <= 91)
    }
}
```

- [ ] **Step 5: Implement dedicated 429 parsing**

Add the error case and parse both delta seconds and an HTTP date:

```swift
enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited(retryAfter: Date?)
    case httpError(Int)
    case server(String)
}

private static func retryAfterDate(
    from response: HTTPURLResponse,
    now: Date = Date()
) -> Date? {
    guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !raw.isEmpty
    else { return nil }
    if let seconds = TimeInterval(raw), seconds >= 0 {
        return now.addingTimeInterval(seconds)
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
    return formatter.date(from: raw)
}
```

In `send(request:)`, check 429 before the generic status guard:

```swift
if httpResponse.statusCode == 429 {
    throw APIError.rateLimited(retryAfter: Self.retryAfterDate(from: httpResponse))
}
```

Map the localized description to `请求过于频繁，请稍后再试`.

- [ ] **Step 6: Run API tests and commit**

Run:

```bash
./scripts/test.sh --filter APIClientTests
git diff --check
```

Expected: all `APIClientTests` pass and `rg -n "fetchUsageFromExistingLogAPI|/api/log/self" VibeUsage/Services/APIClient.swift` returns no matches.

Commit:

```bash
git add VibeUsage/Services/APIClient.swift Tests/VibeUsageTests/APIClientTests.swift
git commit -m "fix: keep desktop analytics snapshot only"
```

### Task 2: Build the visibility-aware refresh coordinator

**Files:**
- Create: `VibeUsage/Services/VisibleRefreshCoordinator.swift`
- Create: `Tests/VibeUsageTests/VisibleRefreshCoordinatorTests.swift`

- [ ] **Step 1: Write deterministic failing coordinator tests**

Create tests covering visibility, freshness, page targeting, single-flight, jitter, manual cooldown, and 429 cooldown. The core test harness is:

```swift
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
        let coordinator = VisibleRefreshCoordinator(
            now: { now },
            nextDelay: { 60 },
            sleep: { _ in throw CancellationError() },
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
        await Task.yield()
        #expect(calls == [.usage])
    }

    @Test
    func jitterIsAlwaysBetweenFiftyFiveAndSixtyFiveSeconds() {
        #expect(VisibleRefreshCoordinator.jitteredDelay(unit: 0) == 55)
        #expect(VisibleRefreshCoordinator.jitteredDelay(unit: 0.5) == 60)
        #expect(VisibleRefreshCoordinator.jitteredDelay(unit: 1) == 65)
    }
}
```

Use an injected sleeper that suspends until cancellation so no test waits for real time. Additional tests advance the injected `now` variable to prove a 60-second freshness window, 10-second manual cooldown, and `Retry-After` deadline.

- [ ] **Step 2: Run the coordinator tests and verify they fail to compile**

Run:

```bash
./scripts/test.sh --filter VisibleRefreshCoordinatorTests
```

Expected: FAIL because `RemoteRefreshTarget`, `SnapshotRefreshResult`, and `VisibleRefreshCoordinator` do not exist.

- [ ] **Step 3: Implement the coordinator**

Create these public-to-module types:

```swift
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
    private var windowVisible = false
    private var activeTarget: RemoteRefreshTarget = .none
    private var loopTask: Task<Void, Never>?
    private var inFlight: Set<RemoteRefreshTarget> = []
    private var manualAttemptAt: [RemoteRefreshTarget: Date] = [:]
    private var cooldownUntil: [RemoteRefreshTarget: Date] = [:]

    init(
        now: @escaping () -> Date = Date.init,
        nextDelay: @escaping () -> TimeInterval = {
            Self.jitteredDelay(unit: Double.random(in: 0...1))
        },
        sleep: @escaping Sleep = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        },
        lastSuccess: @escaping LastSuccess,
        refresh: @escaping Refresh
    ) {
        self.now = now
        self.nextDelay = nextDelay
        self.sleep = sleep
        self.lastSuccess = lastSuccess
        self.refresh = refresh
    }

    static func jitteredDelay(unit: Double) -> TimeInterval {
        55 + min(max(unit, 0), 1) * 10
    }
}
```

Implement:

```swift
func setWindowVisible(_ visible: Bool)
func setActiveTarget(_ target: RemoteRefreshTarget)
func requestManualRefresh(_ target: RemoteRefreshTarget) async
func stop()
func runAutomaticRefreshCycleForTesting() async
```

`perform(_:)` must reject `.none`, hidden automatic calls, fresh data newer than 60 seconds, active cooldowns, and targets already in `inFlight`. A missing Retry-After value sets `cooldownUntil[target]` to `now + 60`. `restartLoop()` cancels the old task, performs one eligibility check, then sleeps for `nextDelay()` before each later check.

- [ ] **Step 4: Run coordinator tests and commit**

Run:

```bash
./scripts/test.sh --filter VisibleRefreshCoordinatorTests
git diff --check
```

Expected: all coordinator tests pass without real-time sleeps.

Commit:

```bash
git add VibeUsage/Services/VisibleRefreshCoordinator.swift Tests/VibeUsageTests/VisibleRefreshCoordinatorTests.swift
git commit -m "feat: coordinate visible snapshot refreshes"
```

### Task 3: Separate AppState snapshot, account, and status requests

**Files:**
- Create: `VibeUsage/Services/NewSystemClient.swift`
- Create: `Tests/VibeUsageTests/AppStateRefreshTests.swift`
- Modify: `VibeUsage/Services/APIClient.swift`
- Modify: `VibeUsage/Models/AppState.swift`
- Modify: `Tests/VibeUsageTests/AppStateRangeTests.swift`

- [ ] **Step 1: Add a client protocol and live dependency container**

Create:

```swift
import Foundation

@MainActor
protocol NewSystemClient {
    func login(username: String, password: String) async throws -> LoginOutcome
    func verifyTwoFactor(code: String) async throws -> AuthenticatedUser
    func fetchCurrentUser() async throws -> AuthenticatedUser
    func logout() async throws
    func fetchLeaderboard() async throws -> LeaderboardData
    func fetchUsage(range: UsageQueryRange) async throws -> UsageResponse
    func fetchQuotaPerUnit() async -> Double
}

extension APIClient: NewSystemClient {}

@MainActor
struct AppStateDependencies {
    var loadConfig: () -> VibeUsageConfig?
    var saveConfig: (VibeUsageConfig) -> Void
    var clearConfig: () -> Void
    var makeClient: (_ baseURL: String, _ userID: Int?) -> any NewSystemClient
    var now: () -> Date

    static let live = AppStateDependencies(
        loadConfig: ConfigManager.load,
        saveConfig: ConfigManager.save,
        clearConfig: ConfigManager.clear,
        makeClient: { APIClient(baseURL: $0, userID: $1) },
        now: Date.init
    )
}
```

Use `AppState(dependencies: .live)` as the default initializer so existing call sites remain unchanged.

- [ ] **Step 2: Write failing AppState request-count tests**

Create a `MockNewSystemClient` that records method counts and returns fixed usage, user, status, and leaderboard values. Add tests with these assertions:

```swift
state.initialize()
await state.restoreSession()
#expect(mock.currentUserCalls == 1)
#expect(mock.usageCalls == 1)
#expect(mock.statusCalls == 1)

await state.refreshUsageSnapshot(for: .oneDay)
#expect(mock.usageCalls == 2)
#expect(mock.currentUserCalls == 1)
#expect(mock.statusCalls == 1)
```

Add cache tests:

```swift
await state.selectTimeRange(.sevenDays)
await state.selectTimeRange(.oneDay)
#expect(mock.requestedRanges == [.days(1), .days(7)])
```

The second selection restores the fresh one-day cache without a third request. Add a failure test that first loads data, makes the mock throw, refreshes again, and verifies the original buckets remain visible.

- [ ] **Step 3: Run AppState tests and verify failure**

Run:

```bash
./scripts/test.sh --filter AppStateRefreshTests
```

Expected: FAIL because the dependency container, per-range cache, and separated request methods are not implemented.

- [ ] **Step 4: Implement per-range cache and snapshot-only refresh methods**

Make `TimeRange` conform to `Hashable, Sendable`. Add:

```swift
private struct UsageSnapshotCacheEntry {
    let response: UsageResponse
    let updatedAt: Date
}

private let dependencies: AppStateDependencies
private var usageCache: [TimeRange: UsageSnapshotCacheEntry] = [:]
private var quotaPerUnitLoadedForSession = false

init(dependencies: AppStateDependencies = .live) {
    self.dependencies = dependencies
}
```

Split application and presentation:

```swift
func applyUsageResponse(
    _ response: UsageResponse,
    for range: TimeRange,
    updatedAt: Date? = nil
) {
    let date = updatedAt ?? dependencies.now()
    usageCache[range] = UsageSnapshotCacheEntry(response: response, updatedAt: date)
    presentUsageResponse(response, for: range)
}

func selectTimeRange(_ range: TimeRange) async {
    guard timeRange != range else { return }
    timeRange = range
    if let cached = usageCache[range] {
        presentUsageResponse(cached.response, for: range)
        if dependencies.now().timeIntervalSince(cached.updatedAt) <= 60 { return }
    }
    _ = await refreshUsageSnapshot(for: range)
}
```

Implement `refreshUsageSnapshot(for:) -> SnapshotRefreshResult` with the existing loading UI and authorization handling, but only call:

```swift
let response = try await client.fetchUsage(range: usageQueryRange(for: range))
```

Do not call `fetchCurrentUser` or `fetchQuotaPerUnit` in this method. Return `.rateLimited(until:)` for the dedicated API error, `.failure` for other errors, and `.success` only after caching the response.

- [ ] **Step 5: Load status once and remove duplicate session requests**

Add:

```swift
private func loadQuotaPerUnitOnce() async {
    guard !quotaPerUnitLoadedForSession, let client = authenticatedClient() else { return }
    quotaPerUnitLoadedForSession = true
    let value = await client.fetchQuotaPerUnit()
    if value > 0 { quotaPerUnit = value }
}
```

After successful login or session restoration, run one usage snapshot request and one status request. Session restoration must use the already returned `AuthenticatedUser` to populate account metrics and must not fetch `/api/user/self` again inside usage loading.

Reset `quotaPerUnitLoadedForSession`, caches, and refresh timestamps in `clearRemoteSession()`.

- [ ] **Step 6: Connect AppState to VisibleRefreshCoordinator**

Add an observation-ignored lazy coordinator:

```swift
@ObservationIgnored
private lazy var visibleRefreshCoordinator = VisibleRefreshCoordinator(
    lastSuccess: { [weak self] target in self?.lastSuccessfulRefresh(for: target) },
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
```

Expose only lifecycle methods:

```swift
func setMainWindowVisible(_ visible: Bool)
func setActiveRefreshTarget(_ target: RemoteRefreshTarget)
func refreshUsageManually() async
func refreshLeaderboardManually() async
func stopRemoteRefresh()
```

`triggerSync()` delegates to `refreshUsageManually()` so existing buttons keep their semantic meaning.

- [ ] **Step 7: Run AppState and range tests and commit**

Run:

```bash
./scripts/test.sh --filter AppStateRefreshTests
./scripts/test.sh --filter AppStateRangeTests
git diff --check
```

Expected: request counts, cache restoration, stale-data retention, and existing range rendering tests all pass.

Commit:

```bash
git add VibeUsage/Services/NewSystemClient.swift VibeUsage/Services/APIClient.swift VibeUsage/Models/AppState.swift Tests/VibeUsageTests/AppStateRefreshTests.swift Tests/VibeUsageTests/AppStateRangeTests.swift
git commit -m "refactor: separate snapshot refresh state"
```

### Task 4: Wire real window and page lifecycle signals

**Files:**
- Modify: `VibeUsage/Services/MainWindowController.swift`
- Modify: `Tests/VibeUsageTests/MainWindowControllerTests.swift`
- Modify: `VibeUsage/Views/DashboardShellView.swift`
- Modify: `VibeUsage/Views/LeaderboardView.swift`
- Modify: `VibeUsage/App/VibeUsageApp.swift`
- Delete: `VibeUsage/Services/SyncScheduler.swift`
- Modify: `VibeUsage/Models/AppState.swift`

- [ ] **Step 1: Write failing window visibility tests**

Add:

```swift
@Test
func reportsShowHideMinimizeAndRestoreVisibility() {
    var visibility: [Bool] = []
    let controller = MainWindowController(
        rootView: EmptyView(),
        onVisibilityChange: { visibility.append($0) }
    )
    let window = controller.makeWindowIfNeeded()

    controller.show()
    controller.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: window))
    controller.windowDidDeminiaturize(Notification(name: NSWindow.didDeminiaturizeNotification, object: window))
    _ = controller.windowShouldClose(window)

    #expect(visibility == [true, false, true, false])
}
```

- [ ] **Step 2: Run the focused window test and verify failure**

Run:

```bash
./scripts/test.sh --filter MainWindowControllerTests.reportsShowHideMinimizeAndRestoreVisibility
```

Expected: FAIL because `onVisibilityChange` and the delegate callbacks do not exist.

- [ ] **Step 3: Report real NSWindow lifecycle transitions**

Replace `onPresent` with:

```swift
private let onVisibilityChange: (Bool) -> Void
```

Call `onVisibilityChange(true)` after `makeKeyAndOrderFront`, and `false` before `orderOut` or close-to-hide. Implement:

```swift
func windowDidMiniaturize(_ notification: Notification) {
    onVisibilityChange(false)
}

func windowDidDeminiaturize(_ notification: Notification) {
    onVisibilityChange(true)
}
```

The `appState` convenience initializer passes `appState.setMainWindowVisible`.

- [ ] **Step 4: Report selected-page changes**

Add to `DashboardShellView`:

```swift
private var remoteRefreshTarget: RemoteRefreshTarget {
    switch selectedPage {
    case .usage: .usage
    case .leaderboard: .leaderboard
    case .settings: .none
    }
}
```

Attach:

```swift
.onAppear { appState.setActiveRefreshTarget(remoteRefreshTarget) }
.onChange(of: selectedPage) { _, _ in
    appState.setActiveRefreshTarget(remoteRefreshTarget)
}
.onDisappear { appState.setActiveRefreshTarget(.none) }
```

Remove `LeaderboardView`'s independent `.task`; page activation is now the single load trigger. Change its refresh button to `await appState.refreshLeaderboardManually()`.

- [ ] **Step 5: Remove fixed background scheduling**

Delete:

```swift
private var syncScheduler: SyncScheduler?
private func startScheduler()
```

Remove scheduler start/stop calls from authentication and logout. Delete `SyncScheduler.swift`. In `applicationWillTerminate`, call:

```swift
appState.stopRemoteRefresh()
```

- [ ] **Step 6: Run lifecycle tests and commit**

Run:

```bash
./scripts/test.sh --filter MainWindowControllerTests
rg -n "SyncScheduler|startScheduler" VibeUsage Tests
git diff --check
```

Expected: window tests pass and the search returns no matches.

Commit:

```bash
git add VibeUsage/Services/MainWindowController.swift Tests/VibeUsageTests/MainWindowControllerTests.swift VibeUsage/Views/DashboardShellView.swift VibeUsage/Views/LeaderboardView.swift VibeUsage/App/VibeUsageApp.swift VibeUsage/Models/AppState.swift VibeUsage/Services/SyncScheduler.swift
git commit -m "feat: refresh snapshots only while visible"
```

### Task 5: Route range selection and manual actions through the safety gates

**Files:**
- Modify: `VibeUsage/Views/FilterTagsView.swift`
- Modify: `VibeUsage/Views/DashboardShellView.swift`
- Modify: `VibeUsage/Views/LeaderboardView.swift`
- Modify: `Tests/VibeUsageTests/DashboardLayoutTests.swift`
- Modify: `Tests/VibeUsageTests/AppStateRefreshTests.swift`

- [ ] **Step 1: Add failing source-contract and cooldown tests**

Add source assertions:

```swift
#expect(filterTags.contains("await appState.selectTimeRange(range)"))
#expect(!filterTags.contains("await appState.fetchUsageData()"))
#expect(leaderboard.contains("await appState.refreshLeaderboardManually()"))
#expect(!leaderboard.contains(".task"))
```

Add an AppState/coordinator test that performs two manual usage refreshes at the same injected time and expects one call, advances time by 11 seconds, performs another, and expects two calls.

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
./scripts/test.sh --filter DashboardLayoutTests
./scripts/test.sh --filter AppStateRefreshTests
```

Expected: FAIL until the views use the coordinated APIs and the cooldown is connected.

- [ ] **Step 3: Update time-range and refresh actions**

Change the selector action to:

```swift
Button {
    guard !appState.isLoadingData, appState.timeRange != range else { return }
    Task { await appState.selectTimeRange(range) }
} label: {
    // existing label
}
```

Keep dashboard refresh buttons calling `triggerSync()`, whose implementation now passes through the coordinator's 10-second manual gate. The leaderboard button calls `refreshLeaderboardManually()`.

- [ ] **Step 4: Run UI contract tests and commit**

Run:

```bash
./scripts/test.sh --filter DashboardLayoutTests
./scripts/test.sh --filter AppStateRefreshTests
git diff --check
```

Expected: all focused tests pass.

Commit:

```bash
git add VibeUsage/Views/FilterTagsView.swift VibeUsage/Views/DashboardShellView.swift VibeUsage/Views/LeaderboardView.swift Tests/VibeUsageTests/DashboardLayoutTests.swift Tests/VibeUsageTests/AppStateRefreshTests.swift
git commit -m "fix: gate user-initiated snapshot refreshes"
```

### Task 6: Full verification, installation, and request-count audit

**Files:**
- Verify only; modify implementation or tests only if a verification step exposes a defect.

- [ ] **Step 1: Run static safety searches**

Run:

```bash
! rg -n "fetchUsageFromExistingLogAPI|fetchRemoteUsagePage|/api/log/self|SyncScheduler|startScheduler" VibeUsage
rg -n "fetchUsage\(|fetchLeaderboard\(|fetchCurrentUser\(|fetchQuotaPerUnit\(" VibeUsage/Models/AppState.swift
```

Expected: the forbidden search produces no matches. The second search shows snapshot requests in their dedicated methods, one account call in session restoration, and one session-scoped status loader.

- [ ] **Step 2: Run the complete test suite**

Run:

```bash
./scripts/test.sh
```

Expected: all Swift tests pass with zero failures.

- [ ] **Step 3: Build and sign the Release application**

Run:

```bash
./scripts/build-app.sh
codesign --verify --deep --strict "dist/Vibe Usage.app"
spctl -a -vv "dist/Vibe Usage.app" || true
```

Expected: Release build completes and `codesign` exits 0. `spctl` may report an ad-hoc local signature when the Developer ID is unavailable; record the exact result.

- [ ] **Step 4: Install the verified build**

Run:

```bash
osascript -e 'tell application "Vibe Usage" to quit' 2>/dev/null || true
rm -rf "/Applications/Vibe Usage.app"
ditto "dist/Vibe Usage.app" "/Applications/Vibe Usage.app"
open -a "/Applications/Vibe Usage.app"
```

Expected: the installed application launches and shows the existing dashboard without changing layout.

- [ ] **Step 5: Audit request counts with deterministic spies and live UI lifecycle**

First rerun the serialized request-count suites:

```bash
./scripts/test.sh --filter AppStateRefreshTests
./scripts/test.sh --filter VisibleRefreshCoordinatorTests
./scripts/test.sh --filter APIClientTests.missingDesktopSnapshotDoesNotRequestRawLogs
```

Then exercise the installed UI:

1. Open usage and confirm one refresh indicator, not account/status refresh fan-out.
2. Hide the window for at least 70 seconds and confirm no new refresh indicator appears when it is reopened with fresh data.
3. Leave usage visible for at least 70 seconds and confirm one automatic update.
4. Switch to leaderboard, wait at least 70 seconds, and confirm only its update timestamp changes.
5. Switch to settings, wait at least 70 seconds, and confirm neither analytics timestamp changes.

The automated spies are the authoritative endpoint-count proof; the installed UI pass validates that real lifecycle signals drive the tested coordinator.

- [ ] **Step 6: Inspect final repository state and push**

Run:

```bash
git status --short
git log --oneline --decorate -8
git diff origin/codex/standard-window-macos...HEAD --check
git push origin codex/standard-window-macos
```

Expected: the working tree is clean, all low-load commits are present, diff check passes, and the branch pushes successfully.
