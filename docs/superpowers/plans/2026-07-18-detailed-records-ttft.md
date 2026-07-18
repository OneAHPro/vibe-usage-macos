# Detailed Records TTFT Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show real request-level TTFT in the macOS detailed-records table while removing terminal/tool columns and adding no network requests.

**Architecture:** Decode an optional bounded `recentRequests` collection from the existing desktop usage response, preserve nil-versus-empty rollout semantics in `AppState`, and derive table rows from requests when present. Keep aggregate rows only as an old-backend fallback with unavailable TTFT, and isolate TTFT formatting/classification from SwiftUI so boundary behavior is testable.

**Tech Stack:** Swift 6, SwiftUI, Foundation Codable, Observation, Swift Testing, Swift Package Manager

---

## File Structure

- Modify `VibeUsage/Models/UsageBucket.swift`: define the request-level response model and the optional response field.
- Modify `VibeUsage/Models/AppState.swift`: retain optional recent requests and pass them into derived dashboard data.
- Modify `VibeUsage/Models/DashboardData.swift`: filter request records, construct rows, and classify TTFT.
- Modify `VibeUsage/Views/DashboardLayout.swift`: define seven table columns and balanced widths.
- Modify `VibeUsage/Views/UsageRecordsView.swift`: remove terminal/tool cells and render the TTFT badge.
- Modify `Tests/VibeUsageTests/APIClientTests.swift`: prove response compatibility and request-record decoding.
- Modify `Tests/VibeUsageTests/DashboardDataTests.swift`: prove row selection, rollout fallback, and TTFT boundaries.
- Modify `Tests/VibeUsageTests/DashboardLayoutTests.swift`: prove the table exposes exactly the intended seven columns.

The private backend contract is documented separately and is not implemented in this repository.

### Task 1: Decode bounded request records without breaking old responses

**Files:**
- Modify: `VibeUsage/Models/UsageBucket.swift`
- Test: `Tests/VibeUsageTests/APIClientTests.swift`

- [ ] **Step 1: Extend the endpoint test with a request record**

Add `recentRequests` to the mocked `/api/desktop/usage` data and assert the decoded values:

```swift
#expect(usage.recentRequests?.count == 1)
let request = try #require(usage.recentRequests?.first)
#expect(request.id == 991)
#expect(request.model == "gpt-5.6-sol")
#expect(request.firstResponseTimeMs == 2_400)
#expect(request.outputTokens == 30)
```

Add a second decoding assertion to `allRangeRequestsTheUsersCompleteHistory`:

```swift
#expect(usage.recentRequests == nil)
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
./scripts/test.sh --filter APIClientTests.fetchUsageUsesDesktopEndpointAndUserHeader
```

Expected: compilation fails because `UsageResponse` has no `recentRequests` member.

- [ ] **Step 3: Add the request model and compatible response initializer**

Add to `UsageBucket.swift`:

```swift
struct UsageRequestRecord: Codable, Identifiable, Equatable {
    let id: Int
    let createdAt: String
    let source: String
    let model: String
    let project: String
    let inputTokens: Int
    let outputTokens: Int
    let cachedInputTokens: Int
    let reasoningOutputTokens: Int
    let totalTokens: Int
    let estimatedCost: Double?
    let firstResponseTimeMs: Double?

    var date: Date? {
        ISO8601Parser.date(from: createdAt)
    }
}

struct UsageResponse: Codable {
    let buckets: [UsageBucket]
    let sessions: [UsageSession]?
    let recentRequests: [UsageRequestRecord]?
    let hasAnyData: Bool

    init(
        buckets: [UsageBucket],
        sessions: [UsageSession]?,
        recentRequests: [UsageRequestRecord]? = nil,
        hasAnyData: Bool
    ) {
        self.buckets = buckets
        self.sessions = sessions
        self.recentRequests = recentRequests
        self.hasAnyData = hasAnyData
    }
}
```

- [ ] **Step 4: Run API tests**

Run:

```bash
./scripts/test.sh --filter APIClientTests
```

Expected: all API client tests pass, including an old response with no `recentRequests`.

### Task 2: Build request rows and classify TTFT

**Files:**
- Modify: `VibeUsage/Models/AppState.swift`
- Modify: `VibeUsage/Models/DashboardData.swift`
- Test: `Tests/VibeUsageTests/DashboardDataTests.swift`

- [ ] **Step 1: Add failing request-row and boundary tests**

Create request records for 2,900, 3,000, 9,900, and 10,000 milliseconds and initialize `DashboardData` with `recentRequests`. Assert:

```swift
#expect(data.recentRows.map(\.firstResponseTime) == ["10.0 s", "9.9 s", "3.0 s", "2.9 s"])
#expect(data.recentRows.map(\.firstResponseTier) == [.critical, .slow, .slow, .fast])
#expect(data.recentRows.allSatisfy { !$0.model.isEmpty })
```

Add an old-backend fallback test:

```swift
let data = DashboardData(
    buckets: [includedBucket],
    sessions: [],
    recentRequests: nil,
    cutoff: nil,
    filters: .init()
)
#expect(data.recentRows.first?.firstResponseTime == "—")
#expect(data.recentRows.first?.firstResponseTier == .unavailable)
```

Add an explicit-empty test proving `recentRequests: []` does not fall back to aggregate buckets.

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
./scripts/test.sh --filter DashboardDataTests
```

Expected: compilation fails on the new request and TTFT members.

- [ ] **Step 3: Add the row model and nil-versus-empty selection**

Replace terminal/tool row fields with:

```swift
enum FirstResponseTimeTier: Equatable {
    case fast
    case slow
    case critical
    case unavailable
}

struct UsageRecordRow: Identifiable, Equatable {
    let id: String
    let date: String
    let model: String
    let firstResponseTime: String
    let firstResponseTier: FirstResponseTimeTier
    let inputTokens: String
    let outputTokens: String
    let cachedTokens: String
    let estimatedCost: String
}
```

For valid positive milliseconds, format with a POSIX locale and classify exact new-system thresholds:

```swift
let seconds = milliseconds / 1_000
firstResponseTime = String(
    format: "%.1f s",
    locale: Locale(identifier: "en_US_POSIX"),
    seconds
)
if seconds < 3 {
    firstResponseTier = .fast
} else if seconds < 10 {
    firstResponseTier = .slow
} else {
    firstResponseTier = .critical
}
```

Missing, zero, negative, NaN, or infinite values produce `—` and `.unavailable`.

Extend `DashboardData.init` with `recentRequests: [UsageRequestRecord]? = nil`. Filter records by cutoff, source, model, and project. If the optional is non-nil, sort request records by `createdAt` descending and cap at 50; if it is nil, retain the aggregate-bucket fallback.

Add `var recentRequests: [UsageRequestRecord]?` to `AppState`, assign it in `presentUsageResponse`, and pass it into `DashboardData`.

- [ ] **Step 4: Run model tests**

Run:

```bash
./scripts/test.sh --filter DashboardDataTests
./scripts/test.sh --filter AppStateRangeTests
```

Expected: all selected tests pass.

### Task 3: Render the seven-column table

**Files:**
- Modify: `VibeUsage/Views/DashboardLayout.swift`
- Modify: `VibeUsage/Views/UsageRecordsView.swift`
- Test: `Tests/VibeUsageTests/DashboardLayoutTests.swift`

- [ ] **Step 1: Add a failing table-contract test**

Add:

```swift
@Test
func detailedRecordsUseSevenRequestColumns() throws {
    #expect(DashboardLayout.recordColumnTitles == [
        "日期", "模型", "首字", "输入 TOKEN", "输出 TOKEN", "缓存 TOKEN", "预估费用",
    ])
    #expect(DashboardLayout.recordColumnWidths(for: 820).count == 7)

    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let view = try String(
        contentsOf: root.appendingPathComponent("VibeUsage/Views/UsageRecordsView.swift"),
        encoding: .utf8
    )
    #expect(!view.contains("终端"))
    #expect(!view.contains("工具"))
    #expect(view.contains("首字"))
}
```

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```bash
./scripts/test.sh --filter DashboardLayoutTests.detailedRecordsUseSevenRequestColumns
```

Expected: FAIL because the layout still defines eight aggregate columns.

- [ ] **Step 3: Rebalance layout widths**

Use a minimum width of 820 points and seven columns whose bases total 820:

```swift
static let recordColumnTitles = [
    "日期", "模型", "首字", "输入 TOKEN", "输出 TOKEN", "缓存 TOKEN", "预估费用",
]
static let recordMinimumTableWidth: CGFloat = 820
private static let recordBaseColumnWidths: [CGFloat] = [135, 155, 85, 105, 110, 110, 120]
private static let recordExtraWidthWeights: [CGFloat] = [0.18, 0.26, 0.08, 0.10, 0.12, 0.12, 0.14]
```

- [ ] **Step 4: Replace terminal/tool cells with the TTFT badge**

Render the seven headers and values. Add a compact badge for TTFT with tier-specific colors:

```swift
private func firstResponseBadge(_ row: UsageRecordRow, width: CGFloat) -> some View {
    Text(row.firstResponseTime)
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(firstResponseForeground(row.firstResponseTier))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(firstResponseBackground(row.firstResponseTier))
        .clipShape(Capsule())
        .frame(width: width, alignment: .center)
}
```

Use green for `.fast`, light red/orange for `.slow`, deep red for `.critical`, and transparent neutral text for `.unavailable`.

- [ ] **Step 5: Run layout and full tests**

Run:

```bash
./scripts/test.sh --filter DashboardLayoutTests
./scripts/test.sh
git diff --check
```

Expected: the focused and full Swift suites pass and the diff has no whitespace errors.

### Task 4: Build, install, and visually verify

**Files:**
- No source changes expected.

- [ ] **Step 1: Build Release**

Run the repository's existing Release build/install workflow:

```bash
./scripts/build-app.sh
```

Expected: the app bundle builds successfully with no Swift compiler errors.

- [ ] **Step 2: Install the bundle**

Use the repository's existing installation script or copy the verified Release bundle to `/Applications/Vibe Usage.app`, preserving signing requirements.

- [ ] **Step 3: Verify behavior**

Open the app and confirm:

- terminal and tool columns are gone;
- the table has date, model, TTFT, three token columns, and cost;
- old production responses render `—` in TTFT until the backend field is deployed;
- a fixture or deployed response shows green, light-red/orange, and deep-red badges at the defined thresholds;
- light and dark appearances remain readable;
- dashboard refresh produces no extra request beyond `/api/desktop/usage`.

- [ ] **Step 4: Commit and push**

Run:

```bash
git add VibeUsage Tests docs/superpowers
git commit -m "feat: show request first-token latency"
git push
```

Expected: the working tree is clean and the current branch is present on the configured remote.
