# Native Leaderboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the browser-opening leaderboard links with a native authenticated leaderboard page backed by `GET /api/user/leaderboard`.

**Architecture:** Add focused response/presentation models, expose one authenticated APIClient request, cache leaderboard state in AppState, and render a dedicated SwiftUI page selected by DashboardShellView. The implementation uses only the server's existing today, yesterday, and cumulative data and deliberately omits all period/tool/model filters.

**Tech Stack:** Swift 6, SwiftUI, Observation, Foundation URLSession, Swift Testing, Swift Package Manager

---

## File Map

- Create `VibeUsage/Models/LeaderboardData.swift`: response models and deterministic presentation helpers.
- Modify `VibeUsage/Services/APIClient.swift`: authenticated leaderboard request.
- Modify `VibeUsage/Models/AppState.swift`: load/cache/error/update state.
- Create `VibeUsage/Views/LeaderboardView.swift`: complete native page.
- Modify `VibeUsage/Views/DashboardShellView.swift`: native navigation from both entry points.
- Create `Tests/VibeUsageTests/LeaderboardDataTests.swift`: decoding and presentation tests.
- Modify `Tests/VibeUsageTests/APIClientTests.swift`: request contract test.
- Modify `Tests/VibeUsageTests/AppStateRangeTests.swift`: state-application test.
- Modify `Tests/VibeUsageTests/DashboardLayoutTests.swift`: native navigation and forbidden-control regression tests.
- Modify `Tests/VibeUsageTests/FormattersTests.swift`: billion token compaction regression.

### Task 1: Response Models and Formatting

**Files:**
- Create: `Tests/VibeUsageTests/LeaderboardDataTests.swift`
- Modify: `Tests/VibeUsageTests/FormattersTests.swift`
- Create: `VibeUsage/Models/LeaderboardData.swift`
- Modify: `VibeUsage/Utils/Formatters.swift`

- [ ] **Step 1: Write failing model and formatter tests**

```swift
import Foundation
import Testing
@testable import VibeUsage

struct LeaderboardDataTests {
    @Test
    func decodesTheProductionLeaderboardShape() throws {
        let json = #"{"token_total_top":[{"user_id":1,"username":"a***e","display_name":"Alice","token_used":12900000000}],"token_daily_top":[],"quota_total_top":[{"user_id":2,"username":"b*b","quota":4041360000,"token_used":11100000000}],"quota_daily_top":[],"my_daily_quota_rank":{"rank":7,"quota":750000,"token_used":12345},"quota_yesterday_top":[],"my_yesterday_quota_rank":null,"invite_reward_top":[]}"#

        let data = try JSONDecoder().decode(LeaderboardData.self, from: Data(json.utf8))

        #expect(data.tokenTotalTop.first?.displayName == "Alice")
        #expect(data.quotaTotalTop.first?.quota == 4_041_360_000)
        #expect(data.myDailyQuotaRank?.rank == 7)
        #expect(data.myYesterdayQuotaRank == nil)
    }

    @Test
    func presentationUsesSafeNamesRanksAndQuotaConversion() {
        let named = LeaderboardRow(userID: 1, username: "masked", displayName: "Visible", avatarURL: nil, tokenUsed: 10, quota: nil)
        let fallback = LeaderboardRow(userID: 2, username: "masked", displayName: "   ", avatarURL: nil, tokenUsed: 10, quota: nil)

        #expect(named.preferredName == "Visible")
        #expect(fallback.preferredName == "masked")
        #expect(LeaderboardPresentation.rankLabel(nil) == "未上榜")
        #expect(LeaderboardPresentation.rankLabel(.init(rank: 7, quota: 750_000, tokenUsed: 12_345)) == "#7")
        #expect(LeaderboardPresentation.costLabel(quota: 750_000, quotaPerUnit: 500_000) == "$1.50")
    }
}
```

Append to `FormattersTests.swift`:

```swift
@Test
func formatsBillionScaleTokenCounts() {
    #expect(Formatters.formatNumber(12_900_000_000) == "12.9B")
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --filter LeaderboardDataTests
swift test --filter FormattersTests.formatsBillionScaleTokenCounts
```

Expected: compilation fails because the leaderboard types do not exist and the formatter returns million notation.

- [ ] **Step 3: Add the minimal response and presentation models**

Create `LeaderboardData.swift` with:

```swift
import Foundation

struct LeaderboardRow: Decodable, Equatable, Identifiable, Sendable {
    let userID: Int
    let username: String
    let displayName: String?
    let avatarURL: String?
    let tokenUsed: Int
    let quota: Int?

    var id: Int { userID }

    var preferredName: String {
        let display = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !display.isEmpty { return display }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return user.isEmpty ? "-" : user
    }

    enum CodingKeys: String, CodingKey {
        case username, quota
        case userID = "user_id"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case tokenUsed = "token_used"
    }
}

struct LeaderboardPersonalRank: Decodable, Equatable, Sendable {
    let rank: Int
    let quota: Int
    let tokenUsed: Int

    enum CodingKeys: String, CodingKey {
        case rank, quota
        case tokenUsed = "token_used"
    }
}

struct LeaderboardData: Decodable, Equatable, Sendable {
    let tokenTotalTop: [LeaderboardRow]
    let tokenDailyTop: [LeaderboardRow]
    let quotaTotalTop: [LeaderboardRow]
    let quotaDailyTop: [LeaderboardRow]
    let myDailyQuotaRank: LeaderboardPersonalRank?
    let quotaYesterdayTop: [LeaderboardRow]
    let myYesterdayQuotaRank: LeaderboardPersonalRank?

    enum CodingKeys: String, CodingKey {
        case tokenTotalTop = "token_total_top"
        case tokenDailyTop = "token_daily_top"
        case quotaTotalTop = "quota_total_top"
        case quotaDailyTop = "quota_daily_top"
        case myDailyQuotaRank = "my_daily_quota_rank"
        case quotaYesterdayTop = "quota_yesterday_top"
        case myYesterdayQuotaRank = "my_yesterday_quota_rank"
    }
}

enum LeaderboardPresentation {
    static func rankLabel(_ value: LeaderboardPersonalRank?) -> String {
        guard let value, value.rank > 0 else { return "未上榜" }
        return "#\(value.rank)"
    }

    static func costLabel(quota: Int, quotaPerUnit: Double) -> String {
        let divisor = quotaPerUnit > 0 ? quotaPerUnit : 500_000
        return Formatters.formatCost(Double(max(quota, 0)) / divisor)
    }
}
```

Add the billion branch before the million branch in `Formatters.formatNumber`:

```swift
if n >= 1_000_000_000 {
    return String(format: "%.1fB", Double(n) / 1_000_000_000.0)
}
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `swift test --filter LeaderboardDataTests && swift test --filter FormattersTests`

Expected: all focused tests pass.

- [ ] **Step 5: Commit the model layer**

```bash
git add VibeUsage/Models/LeaderboardData.swift VibeUsage/Utils/Formatters.swift Tests/VibeUsageTests/LeaderboardDataTests.swift Tests/VibeUsageTests/FormattersTests.swift
git commit -m "feat: add leaderboard response models"
```

### Task 2: Authenticated API Request

**Files:**
- Modify: `Tests/VibeUsageTests/APIClientTests.swift`
- Modify: `VibeUsage/Services/APIClient.swift`

- [ ] **Step 1: Write the failing request-contract test**

Add to `APIClientTests`:

```swift
@Test
func fetchLeaderboardUsesAuthenticatedNewSystemEndpoint() async throws {
    let session = makeSession { request in
        #expect(request.url?.path == "/api/user/leaderboard")
        #expect(request.value(forHTTPHeaderField: "New-Api-User") == "7")
        return response(
            for: request,
            body: #"{"success":true,"message":"","data":{"token_total_top":[],"token_daily_top":[],"quota_total_top":[],"quota_daily_top":[],"my_daily_quota_rank":null,"quota_yesterday_top":[],"my_yesterday_quota_rank":null,"invite_reward_top":[]}}"#
        )
    }
    let client = APIClient(baseURL: "https://api.anhepro.com", userID: 7, session: session)

    let leaderboard = try await client.fetchLeaderboard()

    #expect(leaderboard.tokenTotalTop.isEmpty)
}
```

- [ ] **Step 2: Run the test and verify RED**

Run: `swift test --filter APIClientTests.fetchLeaderboardUsesAuthenticatedNewSystemEndpoint`

Expected: compilation fails because `fetchLeaderboard()` does not exist.

- [ ] **Step 3: Implement the minimal API method**

Add to `APIClient` beside `fetchUsage`:

```swift
func fetchLeaderboard() async throws -> LeaderboardData {
    let envelope: APIEnvelope<LeaderboardData> = try await send(path: "/api/user/leaderboard")
    guard let data = envelope.data else { throw APIError.invalidResponse }
    return data
}
```

- [ ] **Step 4: Run API tests and verify GREEN**

Run: `swift test --filter APIClientTests`

Expected: all APIClient tests pass.

- [ ] **Step 5: Commit the API layer**

```bash
git add VibeUsage/Services/APIClient.swift Tests/VibeUsageTests/APIClientTests.swift
git commit -m "feat: fetch authenticated leaderboard data"
```

### Task 3: App State and Refresh Semantics

**Files:**
- Modify: `Tests/VibeUsageTests/AppStateRangeTests.swift`
- Modify: `VibeUsage/Models/AppState.swift`

- [ ] **Step 1: Write a failing state-application test**

Add to `AppStateRangeTests`:

```swift
@Test
func applyingLeaderboardDataClearsErrorsAndRecordsUpdateTime() {
    let state = AppState()
    let update = Date(timeIntervalSince1970: 1_700_000_000)
    let data = LeaderboardData(
        tokenTotalTop: [], tokenDailyTop: [], quotaTotalTop: [], quotaDailyTop: [],
        myDailyQuotaRank: nil, quotaYesterdayTop: [], myYesterdayQuotaRank: nil
    )
    state.leaderboardError = "old"

    state.applyLeaderboardData(data, updatedAt: update)

    #expect(state.leaderboardData == data)
    #expect(state.leaderboardUpdatedAt == update)
    #expect(state.leaderboardError == nil)
}
```

- [ ] **Step 2: Run the test and verify RED**

Run: `swift test --filter AppStateRangeTests.applyingLeaderboardDataClearsErrorsAndRecordsUpdateTime`

Expected: compilation fails because leaderboard state is missing.

- [ ] **Step 3: Add leaderboard state and loading behavior**

Add these properties near dashboard data:

```swift
var leaderboardData: LeaderboardData?
var leaderboardUpdatedAt: Date?
var leaderboardError: String?
var isLoadingLeaderboard = false
```

Add these methods near data fetching:

```swift
func fetchLeaderboard() async {
    guard let config, let userID = config.userID, !isLoadingLeaderboard else { return }
    isLoadingLeaderboard = true
    leaderboardError = nil
    defer { isLoadingLeaderboard = false }

    do {
        let client = APIClient(baseURL: config.apiUrl ?? AppConfig.defaultApiUrl, userID: userID)
        applyLeaderboardData(try await client.fetchLeaderboard())
    } catch {
        if let apiError = error as? APIClient.APIError, case .unauthorized = apiError {
            clearRemoteSession()
        } else {
            leaderboardError = error.localizedDescription
        }
    }
}

func applyLeaderboardData(_ data: LeaderboardData, updatedAt: Date = Date()) {
    leaderboardData = data
    leaderboardUpdatedAt = updatedAt
    leaderboardError = nil
}
```

Reset all four leaderboard properties in `clearRemoteSession()`.

- [ ] **Step 4: Run state tests and verify GREEN**

Run: `swift test --filter AppStateRangeTests`

Expected: all AppStateRangeTests pass.

- [ ] **Step 5: Commit state management**

```bash
git add VibeUsage/Models/AppState.swift Tests/VibeUsageTests/AppStateRangeTests.swift
git commit -m "feat: manage leaderboard refresh state"
```

### Task 4: Native Page and Navigation

**Files:**
- Modify: `Tests/VibeUsageTests/DashboardLayoutTests.swift`
- Create: `VibeUsage/Views/LeaderboardView.swift`
- Modify: `VibeUsage/Views/DashboardShellView.swift`

- [ ] **Step 1: Write failing navigation and forbidden-control tests**

Add these complete tests to `DashboardLayoutTests`:

```swift
@Test
func leaderboardUsesNativeNavigationFromBothEntryPoints() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let shell = try String(
        contentsOf: root.appendingPathComponent("VibeUsage/Views/DashboardShellView.swift"),
        encoding: .utf8
    )

    #expect(DashboardPage.leaderboard.title == "排行榜")
    #expect(shell.contains("selectedPage = .leaderboard"))
    #expect(shell.components(separatedBy: "selectedPage = .leaderboard").count - 1 == 2)
    #expect(shell.contains("LeaderboardView()"))
    #expect(!shell.contains("openURL(\"\\(AppConfig.defaultApiUrl)/rankings\")"))
}

@Test
func nativeLeaderboardOmitsUnsupportedFiltersAndUsesRealSections() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let view = try String(
        contentsOf: root.appendingPathComponent("VibeUsage/Views/LeaderboardView.swift"),
        encoding: .utf8
    )

    #expect(view.contains("今日消费排名"))
    #expect(view.contains("昨日消费排名"))
    #expect(view.contains("quotaDailyTop"))
    #expect(view.contains("quotaYesterdayTop"))
    #expect(view.contains("tokenTotalTop"))
    #expect(!view.contains("24H"))
    #expect(!view.contains("7D"))
    #expect(!view.contains("30D"))
    #expect(!view.contains("分工具榜"))
    #expect(!view.contains("分模型榜"))
}
```

- [ ] **Step 2: Run the source tests and verify RED**

Run: `swift test --filter DashboardLayoutTests`

Expected: assertions fail because the native page and navigation do not exist.

- [ ] **Step 3: Create the native page**

Create `LeaderboardView.swift` with the complete native hierarchy below:

```swift
import SwiftUI

struct LeaderboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DashboardLayout.contentSpacing) {
                statusStrip

                if appState.leaderboardData == nil && appState.isLoadingLeaderboard {
                    loadingState
                } else if let data = appState.leaderboardData {
                    personalRankSection(data)
                    usageSection(title: "今日榜") {
                        pairedBoards(
                            leftTitle: "预估消费",
                            leftRows: data.quotaDailyTop,
                            leftMetric: .cost,
                            rightTitle: "Token",
                            rightRows: data.tokenDailyTop,
                            rightMetric: .tokens
                        )
                    }
                    usageSection(title: "昨日榜") {
                        LeaderboardBoardCard(
                            title: "预估消费",
                            rows: data.quotaYesterdayTop,
                            metric: .cost,
                            quotaPerUnit: appState.quotaPerUnit
                        )
                    }
                    usageSection(title: "累计榜") {
                        pairedBoards(
                            leftTitle: "预估消费",
                            leftRows: data.quotaTotalTop,
                            leftMetric: .cost,
                            rightTitle: "Token",
                            rightRows: data.tokenTotalTop,
                            rightMetric: .tokens
                        )
                    }
                } else {
                    errorState
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            if appState.leaderboardData == nil {
                await appState.fetchLeaderboard()
            }
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(AppTheme.secondaryText)
            if let updatedAt = appState.leaderboardUpdatedAt {
                Text("更新于 \(updatedAt.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("new 系统实时榜单")
            }
            if appState.isLoadingLeaderboard {
                ProgressView().controlSize(.mini)
            }
            if appState.leaderboardData != nil, let error = appState.leaderboardError {
                Text(error).foregroundStyle(.red).lineLimit(1)
            }
            Spacer()
            Button {
                Task { await appState.fetchLeaderboard() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(appState.isLoadingLeaderboard)
        }
        .font(.system(size: 11))
        .foregroundStyle(AppTheme.secondaryText)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
    }

    private func personalRankSection(_ data: LeaderboardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("我的排名")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DashboardLayout.contentSpacing) {
                    PersonalRankCard(
                        title: "今日消费排名",
                        value: data.myDailyQuotaRank,
                        quotaPerUnit: appState.quotaPerUnit
                    )
                    PersonalRankCard(
                        title: "昨日消费排名",
                        value: data.myYesterdayQuotaRank,
                        quotaPerUnit: appState.quotaPerUnit
                    )
                }
                VStack(spacing: DashboardLayout.contentSpacing) {
                    PersonalRankCard(
                        title: "今日消费排名",
                        value: data.myDailyQuotaRank,
                        quotaPerUnit: appState.quotaPerUnit
                    )
                    PersonalRankCard(
                        title: "昨日消费排名",
                        value: data.myYesterdayQuotaRank,
                        quotaPerUnit: appState.quotaPerUnit
                    )
                }
            }
        }
    }

    private func pairedBoards(
        leftTitle: String,
        leftRows: [LeaderboardRow],
        leftMetric: LeaderboardMetric,
        rightTitle: String,
        rightRows: [LeaderboardRow],
        rightMetric: LeaderboardMetric
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DashboardLayout.contentSpacing) {
                LeaderboardBoardCard(
                    title: leftTitle,
                    rows: leftRows,
                    metric: leftMetric,
                    quotaPerUnit: appState.quotaPerUnit
                )
                .frame(minWidth: 340)
                LeaderboardBoardCard(
                    title: rightTitle,
                    rows: rightRows,
                    metric: rightMetric,
                    quotaPerUnit: appState.quotaPerUnit
                )
                .frame(minWidth: 340)
            }
            VStack(spacing: DashboardLayout.contentSpacing) {
                LeaderboardBoardCard(
                    title: leftTitle,
                    rows: leftRows,
                    metric: leftMetric,
                    quotaPerUnit: appState.quotaPerUnit
                )
                LeaderboardBoardCard(
                    title: rightTitle,
                    rows: rightRows,
                    metric: rightMetric,
                    quotaPerUnit: appState.quotaPerUnit
                )
            }
        }
    }

    private func usageSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            content()
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(AppTheme.primaryText)
    }

    private var loadingState: some View {
        VStack(spacing: DashboardLayout.contentSpacing) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 7)
                    .fill(AppTheme.surface)
                    .frame(height: 180)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
            }
        }
        .redacted(reason: .placeholder)
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.tertiaryText)
            Text("排行榜加载失败")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
            Text(appState.leaderboardError ?? "暂时无法读取 new 系统排行榜")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.tertiaryText)
            Button("重新加载") {
                Task { await appState.fetchLeaderboard() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
    }
}

private enum LeaderboardMetric: Equatable {
    case cost
    case tokens
}

private struct PersonalRankCard: View {
    let title: String
    let value: LeaderboardPersonalRank?
    let quotaPerUnit: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
            Text(LeaderboardPresentation.rankLabel(value))
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.primaryText)
            if let value {
                HStack(spacing: 14) {
                    Label(
                        LeaderboardPresentation.costLabel(
                            quota: value.quota,
                            quotaPerUnit: quotaPerUnit
                        ),
                        systemImage: "dollarsign.circle"
                    )
                    Label(Formatters.formatNumber(value.tokenUsed), systemImage: "number")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(AppTheme.secondaryText)
            } else {
                Text("暂无使用记录")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
    }
}

private struct LeaderboardBoardCard: View {
    let title: String
    let rows: [LeaderboardRow]
    let metric: LeaderboardMetric
    let quotaPerUnit: Double

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Text("用户")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)

            Divider().overlay(AppTheme.separator)

            if rows.isEmpty {
                Text("暂无排行数据")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 82)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    leaderboardRow(row, rank: index + 1)
                    if index < rows.count - 1 {
                        Divider().overlay(AppTheme.separator.opacity(0.7))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
    }

    private func leaderboardRow(_ row: LeaderboardRow, rank: Int) -> some View {
        HStack(spacing: 9) {
            Text("\(rank)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(rankColor(rank))
                .frame(width: 24, alignment: .leading)
            LeaderboardAvatar(row: row)
            Text(row.preferredName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(primaryValue(row))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.06, green: 0.73, blue: 0.51))
                if metric == .cost {
                    Text("\(Formatters.formatNumber(row.tokenUsed)) Token")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .contentShape(Rectangle())
    }

    private func primaryValue(_ row: LeaderboardRow) -> String {
        switch metric {
        case .cost:
            LeaderboardPresentation.costLabel(
                quota: row.quota ?? 0,
                quotaPerUnit: quotaPerUnit
            )
        case .tokens:
            Formatters.formatNumber(row.tokenUsed)
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: Color(red: 0.95, green: 0.70, blue: 0.20)
        case 2: Color(red: 0.68, green: 0.72, blue: 0.78)
        case 3: Color(red: 0.76, green: 0.48, blue: 0.28)
        default: AppTheme.tertiaryText
        }
    }
}

private struct LeaderboardAvatar: View {
    let row: LeaderboardRow

    var body: some View {
        Group {
            if let value = row.avatarURL, let url = URL(string: value) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialBadge
                }
            } else {
                initialBadge
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(Circle())
    }

    private var initialBadge: some View {
        ZStack {
            Circle().fill(badgeColor.opacity(0.18))
            Text(String(row.preferredName.prefix(1)).uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(badgeColor)
        }
    }

    private var badgeColor: Color {
        let palette: [Color] = [.blue, .cyan, .green, .indigo, .orange, .pink, .purple, .teal]
        let total = row.preferredName.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[abs(total) % palette.count]
    }
}
```

- [ ] **Step 4: Wire both native entry points**

Update `DashboardPage` exactly as follows:

```swift
enum DashboardPage: Equatable {
    case usage
    case leaderboard
    case settings

    var title: String {
        switch self {
        case .usage: "Vibe Usage"
        case .leaderboard: "排行榜"
        case .settings: "设置"
        }
    }

    var subtitle: String {
        switch self {
        case .usage: "AI 使用与成本仪表盘"
        case .leaderboard: "new 系统实时用量排名"
        case .settings: "账号、远程数据与应用偏好"
        }
    }
}
```

Replace the sidebar action with:

```swift
sidebarItem("排行榜", icon: "list.number", selected: selectedPage == .leaderboard) {
    selectedPage = .leaderboard
}
```

Add the native page to `mainContent`:

```swift
case .leaderboard:
    LeaderboardView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
```

Replace the dashboard header action with:

```swift
DashboardActionButton(title: "排行榜", icon: "list.number") {
    selectedPage = .leaderboard
}
```

- [ ] **Step 5: Run layout tests and compile the entire package**

Run:

```bash
swift test --filter DashboardLayoutTests
swift test
```

Expected: all tests pass with no compiler warnings.

- [ ] **Step 6: Commit the native UI**

```bash
git add VibeUsage/Views/LeaderboardView.swift VibeUsage/Views/DashboardShellView.swift Tests/VibeUsageTests/DashboardLayoutTests.swift
git commit -m "feat: add native leaderboard page"
```

### Task 5: Release Verification, Installation, and Push

**Files:**
- Verify all changed files and the built app.

- [ ] **Step 1: Run fresh complete verification**

Run:

```bash
swift test
git diff --check
./scripts/build-app.sh
codesign --verify --deep --strict dist/Vibe\ Usage.app
```

Expected: zero test failures, no whitespace errors, successful Release build, valid code signature.

- [ ] **Step 2: Install without losing the previous app on failure**

Run:

```bash
backup_dir=$(mktemp -d /tmp/vibe-usage-install.XXXXXX)
if [ -d "/Applications/Vibe Usage.app" ]; then
  mv "/Applications/Vibe Usage.app" "$backup_dir/Vibe Usage.app"
fi
if ! ditto "dist/Vibe Usage.app" "/Applications/Vibe Usage.app"; then
  rm -rf "/Applications/Vibe Usage.app"
  if [ -d "$backup_dir/Vibe Usage.app" ]; then
    mv "$backup_dir/Vibe Usage.app" "/Applications/Vibe Usage.app"
  fi
  exit 1
fi
codesign --verify --deep --strict "/Applications/Vibe Usage.app"
shasum -a 256 "dist/Vibe Usage.app/Contents/MacOS/VibeUsage" "/Applications/Vibe Usage.app/Contents/MacOS/VibeUsage"
open "/Applications/Vibe Usage.app"
```

Expected: both SHA-256 values match and the installed bundle passes code-sign validation.

- [ ] **Step 3: Perform real UI verification**

Verify with actual application clicks:

- Clicking the full sidebar **排行榜** row stays inside the app.
- The title changes to **排行榜** and the native page loads authenticated data.
- No 24H/7D/30D/tool/model controls exist.
- Today, yesterday, cumulative, and personal-rank sections render.
- Refresh retains rows and updates the timestamp.
- **返回仪表盘** returns to Vibe Usage.
- The dashboard header **排行榜** action opens the same native page.
- No visible scrollbar is shown while scrolling still works.

- [ ] **Step 4: Inspect final git state and push the existing branch**

Run:

```bash
git status --short --branch
git log -5 --oneline
git push origin codex/standard-window-macos
gh pr view 1 --repo OneAHPro/vibe-usage-macos --json url,state,isDraft,headRefName,baseRefName,title
```

Expected: clean branch, remote HEAD matches local HEAD, and PR #1 remains open and ready.
