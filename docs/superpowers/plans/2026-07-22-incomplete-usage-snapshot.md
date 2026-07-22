# Incomplete Usage Snapshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent warming or incomplete server snapshots from erasing trusted usage data or producing a false no-records message.

**Architecture:** `AppState` is the single acceptance boundary for usage snapshots. It rejects only empty responses whose `coverage.complete == false`, records a presentation-only preparing flag, and accepts populated, complete, or legacy responses. `DashboardShellView` renders the new preparing state without scheduling additional work.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing

---

### Task 1: Snapshot acceptance regression tests

**Files:**
- Modify: `Tests/VibeUsageTests/AppStateRangeTests.swift`
- Modify: `Tests/VibeUsageTests/AppStateRefreshTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests that apply a complete populated response followed by an incomplete
empty response and expect the populated buckets to remain. Add refresh tests for
initial incomplete responses and uncached range changes.

```swift
state.applyUsageResponse(completeUsage, for: .oneDay)
state.applyUsageResponse(incompleteUsage, for: .oneDay)
#expect(state.buckets == completeUsage.buckets)
#expect(state.hasAnyData)
#expect(state.isUsageSnapshotPreparing)

harness.client.usageResponse = incompleteUsage
await harness.state.selectTimeRange(.thirtyDays)
#expect(harness.state.timeRange == .oneDay)
#expect(harness.state.loadedTimeRange == .oneDay)
```

- [ ] **Step 2: Verify RED**

Run:

```bash
./scripts/test.sh --filter incompleteSnapshot --filter incompleteInitialSnapshot --filter incompleteUncachedRange
```

Expected: failures because the current implementation replaces the trusted
snapshot and advances synchronization state.

### Task 2: Authoritative snapshot boundary

**Files:**
- Modify: `VibeUsage/Models/AppState.swift:109-135`
- Modify: `VibeUsage/Models/AppState.swift:470-552`
- Modify: `VibeUsage/Services/VisibleRefreshCoordinator.swift`
- Modify: `Tests/VibeUsageTests/VisibleRefreshCoordinatorTests.swift`

- [ ] **Step 1: Implement minimal acceptance rule**

Add `isUsageSnapshotPreparing`. Make `applyUsageResponse` return `false` without
caching or presenting when `response.coverage?.complete == false` and the
response contains no usage; accept populated incomplete responses because the
hot snapshot can legitimately lag the requested current time by one worker
cycle. Accept `nil` coverage for compatibility. Do not update `lastSyncTime` for
rejected snapshots.

```swift
@discardableResult
func applyUsageResponse(_ response: UsageResponse, for range: TimeRange) -> Bool {
    let containsUsage = response.hasAnyData
        || !response.buckets.isEmpty
        || !(response.sessions?.isEmpty ?? true)
        || !(response.recentRequests?.isEmpty ?? true)
    guard response.coverage?.complete != false || containsUsage else {
        isUsageSnapshotPreparing = true
        return false
    }
    isUsageSnapshotPreparing = false
    usageCache[range] = UsageSnapshotCacheEntry(response: response, updatedAt: dependencies.now())
    presentUsageResponse(response, for: range)
    return true
}
```

- [ ] **Step 2: Keep range selection consistent**

After an immediate range refresh, restore `timeRange = loadedTimeRange` when the
requested range still has no trusted cache.

```swift
_ = await visibleRefreshCoordinator.requestImmediateRefresh(.usage)
if usageCache[range] == nil {
    timeRange = loadedTimeRange
}
```

- [ ] **Step 3: Gate automatic refresh restarts**

Record the actual attempt time per target before invoking the refresh closure.
Automatic cycles use the newer of the last successful snapshot and last attempt
to enforce the 60-second gate even after a failed or incomplete response.
Session reset clears attempts and rate-limit deadlines without changing manual
or immediate refresh behavior.

Capture the account id, session generation, and request id before awaiting the
network. Apply the result and finish loading state only if those identifiers
still belong to the active session. The coordinator similarly tags in-flight
operations so a reset permits the new account to load immediately while a late
old success or error is ignored.

- [ ] **Step 4: Verify GREEN**

Run the Task 1 command. Expected: all selected tests pass.

### Task 3: Preparing presentation

**Files:**
- Modify: `VibeUsage/Views/DashboardShellView.swift:268-520`
- Modify: `Tests/VibeUsageTests/DashboardLayoutTests.swift`

- [ ] **Step 1: Add a failing source/UI-state assertion**

Require the dashboard to branch on `isUsageSnapshotPreparing` before the true
empty state and include `数据准备中` copy.

```swift
#expect(view.contains("appState.isUsageSnapshotPreparing"))
#expect(view.contains("数据准备中"))
```

- [ ] **Step 2: Implement the preparing state**

Show a dedicated preparing card when no trusted data exists. When trusted data
exists, retain the dashboard and change the status banner copy and icon only.

```swift
} else if appState.isUsageSnapshotPreparing && !appState.hasAnyData {
    preparingState
} else if !appState.hasAnyData {
    emptyState
}
```

- [ ] **Step 3: Run focused tests**

```bash
./scripts/test.sh --filter DashboardLayoutTests --filter AppStateRangeTests --filter AppStateRefreshTests
```

Expected: all selected suites pass.

### Task 4: Verification and delivery

**Files:**
- No additional source files.

- [ ] **Step 1: Run full verification**

```bash
./scripts/test.sh
git diff --check
./scripts/build-app.sh
codesign --verify --deep --strict 'dist/Vibe Usage.app'
```

Expected: zero test failures, clean diff, successful Release build and signature
verification.

- [ ] **Step 2: Install and verify binary identity**

Install `dist/Vibe Usage.app` to `/Applications`, preserve the previous bundle,
and confirm installed and built executable SHA-256 hashes match.

- [ ] **Step 3: Commit and push**

```bash
git add docs Tests VibeUsage
git commit -m 'fix: preserve usage during snapshot warming'
git push origin codex/standard-window-macos
```
