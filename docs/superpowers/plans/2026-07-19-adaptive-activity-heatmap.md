# Adaptive Activity Heatmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render hourly, daily-calendar, or monthly activity visualizations according to the backend's declared bucket granularity, eliminating the false 08:00 column for 30D/90D.

**Architecture:** Decode the optional `coverage.granularity` contract into a typed model, retain it in `AppState`, and build one of three immutable activity presentations through the existing memoized derivation path. SwiftUI selects a dedicated grid for each presentation; existing responses without coverage continue to use the hourly heatmap.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing, Swift Package Manager

---

## File structure

- Modify `VibeUsage/Models/UsageBucket.swift`: decode optional response coverage and its forward-compatible granularity.
- Modify `VibeUsage/Models/DashboardData.swift`: add daily/monthly activity aggregation and a presentation enum while preserving the existing hourly aggregator.
- Modify `VibeUsage/Models/AppState.swift`: store response coverage and memoize the adaptive presentation with granularity in the cache key.
- Modify `VibeUsage/Views/ActivityHeatmapView.swift`: render hourly, daily-calendar, monthly, or unavailable states from the adaptive presentation.
- Modify `Tests/VibeUsageTests/APIClientTests.swift`: cover production coverage decoding and legacy compatibility.
- Modify `Tests/VibeUsageTests/DashboardDataTests.swift`: cover UTC day keys, daily aggregation, calendar placement, monthly aggregation, and presentation selection.
- Modify `Tests/VibeUsageTests/AppStateRangeTests.swift`: prove applying a new response changes the active granularity and invalidates the derived presentation.

### Task 1: Decode the backend coverage contract

**Files:**
- Modify: `VibeUsage/Models/UsageBucket.swift`
- Test: `Tests/VibeUsageTests/APIClientTests.swift`

- [ ] **Step 1: Write failing API decoding tests**

Add a production-shape response containing `coverage` and assert every field and the `day` granularity:

```swift
@Test
func fetchUsageDecodesCoverageGranularity() async throws {
    let session = makeSession { request in
        response(
            for: request,
            body: #"{"success":true,"message":"","data":{"buckets":[],"sessions":[],"recentRequests":[],"summary":{"estimatedCost":0,"inputTokens":0,"outputTokens":0,"cachedInputTokens":0,"cacheCreationInputTokens":0,"reasoningOutputTokens":0,"totalTokens":0,"requestCount":0},"coverage":{"requestedStart":"2026-06-19T00:38:47Z","requestedEnd":"2026-07-19T00:38:47Z","dataStart":"2026-06-20T11:34:18Z","dataEnd":"2026-07-19T00:37:00Z","complete":false,"granularity":"day"},"hasAnyData":false}}"#
        )
    }
    let usage = try await APIClient(
        baseURL: "https://api.anhepro.com",
        userID: 7,
        session: session
    ).fetchUsage(range: .days(30))

    #expect(usage.coverage?.granularity == .day)
    #expect(usage.coverage?.complete == false)
    #expect(usage.coverage?.requestedStart == "2026-06-19T00:38:47Z")
    #expect(usage.coverage?.dataStart == "2026-06-20T11:34:18Z")
}
```

Extend the existing legacy response test with:

```swift
#expect(usage.coverage == nil)
```

Add a direct decoder test proving an unknown future value does not fail the whole response:

```swift
#expect(usage.coverage?.granularity == .unknown("quarter"))
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
./scripts/test.sh --filter APIClientTests
```

Expected: compilation fails because `UsageResponse.coverage`, `UsageCoverage`, and `UsageGranularity` do not exist.

- [ ] **Step 3: Implement minimal forward-compatible models**

In `UsageBucket.swift`, add:

```swift
enum UsageGranularity: Equatable, Sendable, Codable {
    case hour
    case day
    case month
    case mixed
    case unknown(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "hour": self = .hour
        case "day": self = .day
        case "month": self = .month
        case "mixed": self = .mixed
        default: self = .unknown(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        let value: String
        switch self {
        case .hour: value = "hour"
        case .day: value = "day"
        case .month: value = "month"
        case .mixed: value = "mixed"
        case .unknown(let raw): value = raw
        }
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct UsageCoverage: Codable, Equatable, Sendable {
    let requestedStart: String?
    let requestedEnd: String?
    let dataStart: String?
    let dataEnd: String?
    let complete: Bool
    let granularity: UsageGranularity
}
```

Add `let coverage: UsageCoverage?` to `UsageResponse`, add an initializer parameter with default `nil`, and assign it. Do not make legacy payloads require the field.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
./scripts/test.sh --filter APIClientTests
```

Expected: all API client tests pass.

- [ ] **Step 5: Commit the contract change**

```bash
git add VibeUsage/Models/UsageBucket.swift Tests/VibeUsageTests/APIClientTests.swift
git commit -m "feat: decode usage bucket granularity"
```

### Task 2: Add daily and monthly aggregation models

**Files:**
- Modify: `VibeUsage/Models/DashboardData.swift`
- Test: `Tests/VibeUsageTests/DashboardDataTests.swift`

- [ ] **Step 1: Write failing daily aggregation tests**

Add tests using an Asia/Shanghai Gregorian calendar. Construct multiple buckets at `2026-07-01T00:00:00Z` and one at `2026-07-02T00:00:00Z`. Assert that the first two combine under the literal backend day key rather than the local 08:00 hour:

```swift
@Test
func dailyActivityUsesBackendDayKeyWithoutInventingAnHour() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let buckets = [
        bucket(source: "a", project: "p", bucketStart: "2026-07-01T00:00:00Z", input: 100, output: 0, reasoning: 0, cached: 0, cost: 1),
        bucket(source: "b", project: "p", bucketStart: "2026-07-01T00:00:00Z", input: 50, output: 0, reasoning: 0, cached: 0, cost: 0.5),
        bucket(source: "a", project: "p", bucketStart: "2026-07-02T00:00:00Z", input: 25, output: 0, reasoning: 0, cached: 0, cost: 0.25),
    ]
    let heatmap = DailyActivityHeatmap(
        buckets: buckets,
        requestedStart: "2026-06-30T12:00:00Z",
        requestedEnd: "2026-07-03T12:00:00Z",
        calendar: calendar
    )

    #expect(heatmap.value(dayKey: "2026-07-01") == 150)
    #expect(heatmap.value(dayKey: "2026-07-02") == 25)
    #expect(heatmap.maximum == 150)
    #expect(heatmap.cells.contains { $0.dayKey == "2026-07-01" && $0.isInRequestedRange })
}
```

Add a cost-mode assertion that July 1 totals `1.5`.

- [ ] **Step 2: Write failing month aggregation and presentation tests**

Add:

```swift
@Test
func monthlyActivityCombinesBucketsByBackendMonthKey() {
    let heatmap = MonthlyActivityHeatmap(
        buckets: [
            bucket(source: "a", project: "p", bucketStart: "2026-06-01T00:00:00Z", input: 100, output: 0, reasoning: 0, cached: 0, cost: 1),
            bucket(source: "b", project: "p", bucketStart: "2026-06-01T00:00:00Z", input: 50, output: 0, reasoning: 0, cached: 0, cost: 0.5),
            bucket(source: "a", project: "p", bucketStart: "2026-07-01T00:00:00Z", input: 25, output: 0, reasoning: 0, cached: 0, cost: 0.25),
        ]
    )

    #expect(heatmap.months.map(\.monthKey) == ["2026-06", "2026-07"])
    #expect(heatmap.months[0].value == 150)
    #expect(heatmap.maximum == 150)
}
```

Test the selector:

```swift
#expect(ActivityPresentation.make(buckets: buckets, coverage: nil).title == "分时活跃")
#expect(ActivityPresentation.make(buckets: buckets, coverage: dayCoverage).title == "每日活跃")
#expect(ActivityPresentation.make(buckets: buckets, coverage: monthCoverage).title == "每月活跃")
#expect(ActivityPresentation.make(buckets: buckets, coverage: mixedCoverage).isUnavailable)
```

- [ ] **Step 3: Run focused tests and verify RED**

Run:

```bash
./scripts/test.sh --filter DashboardDataTests
```

Expected: compilation fails because the daily/monthly models and adaptive presentation do not exist.

- [ ] **Step 4: Implement the aggregation types**

Add focused types below the existing `ActivityHeatmap`:

```swift
struct DailyActivityCell: Identifiable, Equatable {
    let dayKey: String
    let date: Date
    let value: Double
    let isInRequestedRange: Bool
    var id: String { dayKey }
}

struct DailyActivityHeatmap: Equatable {
    let cells: [DailyActivityCell]
    let weekCount: Int
    let maximum: Double
    private let values: [String: Double]

    init(
        buckets: [UsageBucket],
        metric: HeatmapMetric = .token,
        requestedStart: String?,
        requestedEnd: String?,
        calendar: Calendar = .current
    ) {
        // Sum by String(bucketStart.prefix(10)); never derive the day key by
        // converting the midnight-Z bucket to local hour.
        // Build a Monday-first rectangular date interval from requestedStart
        // through requestedEnd so inactive days remain visible.
    }

    func value(dayKey: String) -> Double { values[dayKey, default: 0] }
    func intensity(dayKey: String) -> Double {
        maximum > 0 ? value(dayKey: dayKey) / maximum : 0
    }
}

struct MonthlyActivityValue: Identifiable, Equatable {
    let monthKey: String
    let value: Double
    var id: String { monthKey }
}

struct MonthlyActivityHeatmap: Equatable {
    let months: [MonthlyActivityValue]
    let maximum: Double
    // Sum by String(bucketStart.prefix(7)) and sort ascending.
}

enum ActivityPresentation: Equatable {
    case hourly(ActivityHeatmap)
    case daily(DailyActivityHeatmap)
    case monthly(MonthlyActivityHeatmap)
    case unavailable(String)

    var title: String {
        switch self {
        case .hourly: "分时活跃"
        case .daily: "每日活跃"
        case .monthly: "每月活跃"
        case .unavailable: "活跃分布"
        }
    }

    static func make(
        buckets: [UsageBucket],
        coverage: UsageCoverage?,
        metric: HeatmapMetric = .token,
        calendar: Calendar = .current
    ) -> Self {
        switch coverage?.granularity {
        case .day:
            .daily(DailyActivityHeatmap(
                buckets: buckets,
                metric: metric,
                requestedStart: coverage?.requestedStart,
                requestedEnd: coverage?.requestedEnd,
                calendar: calendar
            ))
        case .month:
            .monthly(MonthlyActivityHeatmap(buckets: buckets, metric: metric))
        case .mixed:
            .unavailable("当前范围包含不同统计粒度")
        case .unknown(let value):
            .unavailable("暂不支持统计粒度：\(value)")
        case .hour, .none:
            .hourly(ActivityHeatmap(buckets: buckets, metric: metric, calendar: calendar))
        }
    }
}
```

Implement the omitted daily date-range loop with `Calendar.date(byAdding:.day,value:to:)`, Monday-first week boundaries, and a stable POSIX `yyyy-MM-dd` formatter bound to the supplied calendar time zone. Do not parse the bucket day through `UsageBucket.date`.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```bash
./scripts/test.sh --filter DashboardDataTests
```

Expected: all dashboard-data tests pass, including the original hourly test.

- [ ] **Step 6: Commit aggregation behavior**

```bash
git add VibeUsage/Models/DashboardData.swift Tests/VibeUsageTests/DashboardDataTests.swift
git commit -m "feat: aggregate activity by response granularity"
```

### Task 3: Propagate coverage through AppState and cache keys

**Files:**
- Modify: `VibeUsage/Models/AppState.swift`
- Test: `Tests/VibeUsageTests/AppStateRangeTests.swift`

- [ ] **Step 1: Write a failing state transition test**

Apply an hour response and then a day response with identical buckets. Assert the presentation changes even though the bucket data does not:

```swift
@Test @MainActor
func applyingCoverageChangesActivityPresentation() {
    let state = AppState(dependencies: .test)
    let buckets = [Self.bucket]

    state.applyUsageResponse(
        UsageResponse(buckets: buckets, sessions: [], coverage: Self.coverage(.hour), hasAnyData: true),
        for: .sevenDays
    )
    #expect(state.activityPresentation(for: .token).title == "分时活跃")

    state.applyUsageResponse(
        UsageResponse(buckets: buckets, sessions: [], coverage: Self.coverage(.day), hasAnyData: true),
        for: .thirtyDays
    )
    #expect(state.activityPresentation(for: .token).title == "每日活跃")
}
```

Use the existing test dependency factory and bucket helpers rather than introducing network mocks.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
./scripts/test.sh --filter AppStateRangeTests
```

Expected: compilation fails because AppState does not retain coverage or expose `activityPresentation`.

- [ ] **Step 3: Implement coverage state and adaptive memoization**

In `AppState`:

```swift
var usageCoverage: UsageCoverage?
```

Change the activity cache value to `ActivityPresentation`, include `UsageGranularity?` in `ActivityHeatmapCacheKey`, and replace the current method with:

```swift
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
```

Assign `usageCoverage = response.coverage` inside `presentUsageResponse`, and clear it in `clearRemoteSession`. Because cached `UsageResponse` already retains coverage, switching ranges restores the correct presentation automatically.

- [ ] **Step 4: Run focused state tests and verify GREEN**

Run:

```bash
./scripts/test.sh --filter AppStateRangeTests
```

Expected: all range/state tests pass.

- [ ] **Step 5: Commit state plumbing**

```bash
git add VibeUsage/Models/AppState.swift Tests/VibeUsageTests/AppStateRangeTests.swift
git commit -m "feat: retain usage coverage in dashboard state"
```

### Task 4: Render adaptive activity views

**Files:**
- Modify: `VibeUsage/Views/ActivityHeatmapView.swift`
- Test: `Tests/VibeUsageTests/DashboardDataTests.swift`

- [ ] **Step 1: Add failing view-contract assertions**

Keep visual geometry out of brittle screenshot tests. Add pure assertions to the presentation tests:

```swift
#expect(hourPresentation.title == "分时活跃")
#expect(dayPresentation.title == "每日活跃")
#expect(monthPresentation.title == "每月活跃")
#expect(mixedPresentation.unavailableMessage == "当前范围包含不同统计粒度")
```

Add daily cell-position assertions for a Monday and Sunday in the same week, proving the model exposes Monday-first row indexes and stable week-column indexes.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
./scripts/test.sh --filter DashboardDataTests
```

Expected: the new row/column and unavailable-message accessors are missing.

- [ ] **Step 3: Add the minimal layout accessors**

Extend `DailyActivityCell` with `weekdayIndex` (`Monday == 0`, `Sunday == 6`) and `weekIndex`, computed during construction. Extend `ActivityPresentation` with an optional `unavailableMessage` accessor. Run the focused test until green before changing the view.

- [ ] **Step 4: Switch the SwiftUI card by presentation**

In `ActivityHeatmapView`:

```swift
let presentation = appState.activityPresentation(for: metric)
Text(presentation.title)

Group {
    switch presentation {
    case .hourly(let heatmap):
        HeatmapGrid(heatmap: heatmap, metric: metric, weekdays: weekdays)
    case .daily(let heatmap):
        DailyCalendarHeatmapGrid(heatmap: heatmap, metric: metric, weekdays: weekdays)
    case .monthly(let heatmap):
        MonthlyActivityHeatmapGrid(heatmap: heatmap, metric: metric)
    case .unavailable(let message):
        ActivityUnavailableView(message: message)
    }
}
.frame(height: 154)
```

Create private focused subviews in the same file:

- `DailyCalendarHeatmapGrid`: 7 rows, `weekCount` columns, centered cells capped at 22 points, abbreviated month/day labels below the first cell of each month, hover tooltip with `yyyy-MM-dd` and the selected metric.
- `MonthlyActivityHeatmapGrid`: ascending month cells in a horizontally scrollable row, capped at 24 points, every third month labeled, hover tooltip with `yyyy-MM` and the selected metric.
- `ActivityUnavailableView`: centered icon plus message; no legend values are fabricated.

Extract the duplicated Token/fee tooltip formatting and intensity color into private file-level helpers so all three grids use the same semantics. Preserve the existing `ScrollWatcher` hover suppression for the hourly grid; daily/monthly grids may use `onContinuousHover` without adding timers or animation layers.

- [ ] **Step 5: Run focused and full tests**

Run:

```bash
./scripts/test.sh --filter DashboardDataTests
./scripts/test.sh
```

Expected: all tests pass with no warnings or failures.

- [ ] **Step 6: Commit adaptive rendering**

```bash
git add VibeUsage/Views/ActivityHeatmapView.swift VibeUsage/Models/DashboardData.swift Tests/VibeUsageTests/DashboardDataTests.swift
git commit -m "fix: adapt activity heatmap to bucket granularity"
```

### Task 5: Release build, installation, and visual verification

**Files:**
- Inspect: `dist/Vibe Usage.app`
- Replace: `/Applications/Vibe Usage.app`

- [ ] **Step 1: Run final source verification**

```bash
git diff --check
./scripts/test.sh
```

Expected: no whitespace errors and the complete Swift test suite passes.

- [ ] **Step 2: Build and verify the Release bundle**

```bash
./scripts/build-app.sh
codesign --verify --deep --strict "dist/Vibe Usage.app"
```

Expected: Release build succeeds and deep signature verification exits 0.

- [ ] **Step 3: Safely install the new application**

Quit the running `VibeUsage` process, move the existing installed bundle into a new `/tmp/vibe-usage-install.XXXXXX` backup directory, copy `dist/Vibe Usage.app` to `/Applications`, verify its signature, and launch it. Never delete the previous bundle before the replacement has been verified.

- [ ] **Step 4: Visually verify real production data**

With the installed app and current authenticated account:

- Today and 24H show `分时活跃` with 00–23 hour labels.
- 7D uses the backend-declared presentation and does not regress.
- 30D and 90D show `每日活跃`, with activity distributed across calendar dates instead of a single 08:00 column.
- Token and fee modes change cell intensity and tooltip values correctly.
- Light and dark appearances preserve readable empty, active, and legend cells.
- Window resizing remains smooth and does not introduce horizontal clipping.

- [ ] **Step 5: Compare installed and built executables**

```bash
shasum -a 256 "dist/Vibe Usage.app/Contents/MacOS/VibeUsage"
shasum -a 256 "/Applications/Vibe Usage.app/Contents/MacOS/VibeUsage"
```

Expected: SHA-256 values match.

- [ ] **Step 6: Commit any verification-only corrections and push**

If visual inspection exposed a narrowly scoped defect, add a failing model/layout test before correcting it, rerun the complete verification, then commit. Finally push `codex/standard-window-macos` to origin and confirm local HEAD equals the remote branch HEAD.
