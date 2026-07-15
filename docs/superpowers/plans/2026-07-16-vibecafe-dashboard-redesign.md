# VibeCafé Dashboard Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the native macOS dashboard into the wide sidebar-and-analytics layout shown in the supplied VibeCafé reference while preserving current data and actions.

**Architecture:** Pure data helpers produce filtered buckets, sessions, metrics, heatmap cells, and record rows. Existing SwiftUI analytics views consume those helpers inside a new responsive `DashboardShellView`; only sidebar, heatmap, and records are new presentation components. `AppState` remains the sole state owner.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, Swift Package Manager

---

### Task 1: Widen the standard macOS window

**Files:**
- Modify: `Tests/VibeUsageTests/MainWindowControllerTests.swift`
- Modify: `VibeUsage/Services/MainWindowController.swift`

- [ ] **Step 1: Write the failing configuration expectations**

```swift
#expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 1280, height: 820))
#expect(window.contentMinSize == NSSize(width: 1024, height: 680))
#expect(MainWindowConfiguration.standard.frameAutosaveName == "VibeUsageDashboardWindowV2")
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
./scripts/test.sh --filter MainWindowControllerTests.createsAStandardResizableMacWindow
```

Expected: the old 960 × 720 and 760 × 560 values fail.

- [ ] **Step 3: Update `MainWindowConfiguration.standard`**

```swift
static let standard = MainWindowConfiguration(
    title: "Vibe Usage",
    defaultContentSize: NSSize(width: 1280, height: 820),
    minimumContentSize: NSSize(width: 1024, height: 680),
    frameAutosaveName: "VibeUsageDashboardWindowV2"
)
```

- [ ] **Step 4: Run the focused test and commit**

```bash
./scripts/test.sh --filter MainWindowControllerTests.createsAStandardResizableMacWindow
git add Tests/VibeUsageTests/MainWindowControllerTests.swift VibeUsage/Services/MainWindowController.swift
git commit -m "feat: size window for desktop dashboard"
```

### Task 2: Centralize filtering, metrics, and recent records

**Files:**
- Create: `VibeUsage/Models/DashboardData.swift`
- Create: `Tests/VibeUsageTests/DashboardDataTests.swift`
- Modify: `VibeUsage/Models/AppState.swift`

- [ ] **Step 1: Write failing data tests**

Create representative buckets and sessions, then assert the intended API:

```swift
let data = DashboardData(
    buckets: buckets,
    sessions: sessions,
    cutoff: nil,
    filters: FilterState(sources: ["codex"], models: [], projects: [], hostnames: [])
)

#expect(data.metrics.estimatedCost == 3.5)
#expect(data.metrics.totalTokens == 225)
#expect(data.metrics.inputTokens == 30)
#expect(data.metrics.outputTokens == 15)
#expect(data.metrics.cachedTokens == 180)
#expect(data.metrics.activeSeconds == 120)
#expect(data.metrics.durationSeconds == 300)
#expect(data.metrics.sessionCount == 1)
#expect(data.metrics.messageCount == 8)
#expect(data.metrics.projectCount == 1)
#expect(data.recentBuckets.map(\.bucketStart) == data.recentBuckets.map(\.bucketStart).sorted(by: >))
```

Add a second test with 55 buckets and assert `recentBuckets.count == 50`.

- [ ] **Step 2: Run tests and verify RED**

```bash
./scripts/test.sh --filter DashboardDataTests
```

Expected: build failure because `DashboardData` does not exist.

- [ ] **Step 3: Implement pure dashboard data types**

```swift
struct DashboardMetrics: Equatable {
    let estimatedCost: Double
    let totalTokens: Int
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let activeSeconds: Int
    let durationSeconds: Int
    let sessionCount: Int
    let messageCount: Int
    let projectCount: Int
}

struct DashboardData {
    let buckets: [UsageBucket]
    let sessions: [UsageSession]
    let metrics: DashboardMetrics
    let recentBuckets: [UsageBucket]

    init(buckets: [UsageBucket], sessions: [UsageSession], cutoff: Date?, filters: FilterState) {
        // Filter by cutoff and active dimensions, calculate all totals, sort
        // `bucketStart` descending, and keep the first 50 records.
    }
}
```

Expose `AppState.dashboardData` using `timeRange.startCutoff` and `filters`, and make `filteredSessions` delegate to it.

- [ ] **Step 4: Run tests and commit**

```bash
./scripts/test.sh --filter DashboardDataTests
./scripts/test.sh
git add VibeUsage/Models/DashboardData.swift VibeUsage/Models/AppState.swift Tests/VibeUsageTests/DashboardDataTests.swift
git commit -m "feat: centralize dashboard analytics data"
```

### Task 3: Build deterministic heatmap data

**Files:**
- Modify: `VibeUsage/Models/DashboardData.swift`
- Modify: `Tests/VibeUsageTests/DashboardDataTests.swift`

- [ ] **Step 1: Write failing heatmap tests**

```swift
let heatmap = ActivityHeatmap(sessions: sessions, calendar: utcCalendar)
#expect(heatmap.value(weekday: 2, hour: 9) == 180)
#expect(heatmap.value(weekday: 2, hour: 10) == 60)
#expect(heatmap.maximum == 180)
#expect(heatmap.intensity(weekday: 2, hour: 9) == 1)
#expect(heatmap.intensity(weekday: 2, hour: 10) == 1.0 / 3.0)
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
./scripts/test.sh --filter DashboardDataTests
```

Expected: build failure because `ActivityHeatmap` does not exist.

- [ ] **Step 3: Implement `ActivityHeatmap`**

```swift
struct ActivityHeatmap: Equatable {
    private let values: [Int: Int]
    let maximum: Int

    init(sessions: [UsageSession], calendar: Calendar = .current) {
        // Key = weekday * 24 + hour; value = summed active seconds.
    }

    func value(weekday: Int, hour: Int) -> Int
    func intensity(weekday: Int, hour: Int) -> Double
}
```

- [ ] **Step 4: Run tests and commit**

```bash
./scripts/test.sh --filter DashboardDataTests
git add VibeUsage/Models/DashboardData.swift Tests/VibeUsageTests/DashboardDataTests.swift
git commit -m "feat: aggregate activity heatmap data"
```

### Task 4: Add responsive layout rules and ten summary cards

**Files:**
- Create: `VibeUsage/Views/DashboardLayout.swift`
- Create: `Tests/VibeUsageTests/DashboardLayoutTests.swift`
- Modify: `VibeUsage/Views/SummaryCardsView.swift`

- [ ] **Step 1: Write failing responsive-layout tests**

```swift
#expect(DashboardLayout.summaryColumnCount(for: 920) == 5)
#expect(DashboardLayout.summaryColumnCount(for: 760) == 2)
#expect(DashboardLayout.analyticsColumnCount(for: 920) == 2)
#expect(DashboardLayout.analyticsColumnCount(for: 760) == 1)
#expect(DashboardLayout.sidebarWidth == 188)
```

- [ ] **Step 2: Run tests and verify RED**

```bash
./scripts/test.sh --filter DashboardLayoutTests
```

Expected: build failure because `DashboardLayout` does not exist.

- [ ] **Step 3: Implement layout rules and summary grid**

```swift
enum DashboardLayout {
    static let sidebarWidth: CGFloat = 188
    static func summaryColumnCount(for width: CGFloat) -> Int { width >= 900 ? 5 : 2 }
    static func analyticsColumnCount(for width: CGFloat) -> Int { width >= 900 ? 2 : 1 }
}
```

Use `GeometryReader` and `LazyVGrid` in `SummaryCardsView`. Render the ten `DashboardMetrics` fields with the existing `StatCard` presentation, 8-point gaps, 7-point corners, 14-point labels, and monospaced values.

- [ ] **Step 4: Run tests and commit**

```bash
./scripts/test.sh --filter DashboardLayoutTests
./scripts/test.sh
git add VibeUsage/Views/DashboardLayout.swift VibeUsage/Views/SummaryCardsView.swift Tests/VibeUsageTests/DashboardLayoutTests.swift
git commit -m "feat: add responsive dashboard metric grid"
```

### Task 5: Add the activity heatmap and records grid

**Files:**
- Create: `VibeUsage/Views/ActivityHeatmapView.swift`
- Create: `VibeUsage/Views/UsageRecordsView.swift`

- [ ] **Step 1: Implement `ActivityHeatmapView` from tested data**

Render seven weekday rows and 24 hourly columns. Each rounded cell uses the existing blue series color with opacity `0.08 + intensity * 0.82`; label every third hour and include a low-to-high legend. Wrap it in the same themed card chrome used by `BarChartView`.

- [ ] **Step 2: Implement `UsageRecordsView` from `recentBuckets`**

Create a fixed column grid with headers `日期`, `终端`, `工具`, `模型`, `项目`, `输入 Token`, `输出 Token`, `缓存 Token`, and `预估费用`. Use monospaced numbers, alternating subtle row fill, green cost text, and a horizontal scroller with a 940-point minimum table width.

- [ ] **Step 3: Compile and commit**

```bash
./scripts/test.sh
git add VibeUsage/Views/ActivityHeatmapView.swift VibeUsage/Views/UsageRecordsView.swift
git commit -m "feat: add heatmap and usage records views"
```

### Task 6: Compose the VibeCafé sidebar dashboard shell

**Files:**
- Create: `VibeUsage/Views/DashboardShellView.swift`
- Modify: `VibeUsage/Views/PopoverView.swift`
- Modify: `VibeUsage/Views/BarChartView.swift`
- Modify: `VibeUsage/Views/DistributionChartsView.swift`
- Modify: `VibeUsage/Theme/AppTheme.swift`

- [ ] **Step 1: Create the working sidebar**

Build a fixed-width sidebar with the VibeCafé wordmark, active Vibe Usage item, rank link, settings action, sync action, last-sync status, version, and quit. Use only current URLs/controllers/actions.

- [ ] **Step 2: Create the main analytics canvas**

Move the title, action buttons, sync banner, quota section, filters, summaries, charts, distributions, and records into `DashboardShellView`. Use `DashboardLayout.analyticsColumnCount` to place `BarChartView` beside `ActivityHeatmapView` on wide windows.

- [ ] **Step 3: Make `PopoverView` host the new shell**

Keep the existing unconfigured/login flow unchanged. Replace only the configured dashboard branch with:

```swift
DashboardShellView()
    .environment(appState)
```

- [ ] **Step 4: Align existing card chrome with the reference**

Use 7-point card corners, 14–16 point interior padding, thin `AppTheme.separator` borders, compact segmented controls, and a quiet `AppTheme.subtleSurface` page canvas. Add any needed semantic surface token to `AppTheme`; do not introduce fixed light-only colors.

- [ ] **Step 5: Run the full suite and commit**

```bash
./scripts/test.sh
git diff --check
git add VibeUsage/Views/DashboardShellView.swift VibeUsage/Views/PopoverView.swift VibeUsage/Views/BarChartView.swift VibeUsage/Views/DistributionChartsView.swift VibeUsage/Theme/AppTheme.swift
git commit -m "feat: compose VibeCafe desktop dashboard"
```

### Task 7: Build, install, compare, and publish

**Files:**
- Build output: `dist/Vibe Usage.app`
- Install output: `/Applications/Vibe Usage.app`

- [ ] **Step 1: Run release verification**

```bash
./scripts/test.sh
./scripts/check-version.sh
./scripts/build-app.sh
codesign --verify --deep --strict "dist/Vibe Usage.app"
git diff --check
```

- [ ] **Step 2: Install and launch**

```bash
pkill -x VibeUsage 2>/dev/null || true
rm -rf "/Applications/Vibe Usage.app"
ditto "dist/Vibe Usage.app" "/Applications/Vibe Usage.app"
open "/Applications/Vibe Usage.app"
```

- [ ] **Step 3: Perform visual acceptance**

Capture the installed 1280 × 820 window. Compare sidebar width, header density, two-row metrics, chart grid, four distribution cards, record columns, scrolling, Light appearance, and Dark appearance with the supplied reference. Correct only observed discrepancies, rerun tests, rebuild, and reinstall.

- [ ] **Step 4: Verify lifecycle and push**

Confirm switching apps does not hide the window, close keeps the process running, and the menu-bar item reopens it. Push the clean branch and `main` to `origin` only after all checks pass.
