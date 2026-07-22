# Leaderboard Table Readability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every native leaderboard board scan like the original website table by aligning rank, user, token, and estimated-cost values into explicit columns.

**Architecture:** Keep the existing endpoint, state, page sections, and adaptive paired-board composition. Replace only `LeaderboardBoardCard`'s avatar-led row presentation with a fixed-column table header and single-line rows; source-level layout regression tests protect the visual structure.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, Swift Package Manager

---

### Task 1: Lock the Table Contract

**Files:**
- Modify: `Tests/VibeUsageTests/DashboardLayoutTests.swift`

- [ ] **Step 1: Write the failing source regression test**

Add:

```swift
@Test
func nativeLeaderboardUsesAlignedTableColumns() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let view = try String(
        contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/LeaderboardView.swift"),
        encoding: .utf8
    )

    #expect(view.contains("private enum LeaderboardTableColumn"))
    #expect(view.contains("private var leaderboardColumns"))
    #expect(view.contains("private var leaderboardColumnHeader"))
    #expect(view.contains("case .rank: \"#\""))
    #expect(view.contains("case .user: \"用户\""))
    #expect(view.contains("case .tokens: \"Token\""))
    #expect(view.contains("case .cost: \"美金消耗\""))
    #expect(!view.contains("预估"))
    #expect(view.components(separatedBy: ".frame(width: 240)").count - 1 == 2)
    #expect(view.contains("private let leaderboardRowHeight: CGFloat = 44"))
    #expect(!view.contains("LeaderboardAvatar"))
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
DYLD_FRAMEWORK_PATH=/Library/Developer/CommandLineTools/Library/Developer/Frameworks DYLD_LIBRARY_PATH=/Library/Developer/CommandLineTools/Library/Developer/usr/lib swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks --filter DashboardLayoutTests.nativeLeaderboardUsesAlignedTableColumns
```

Expected: FAIL because the current view has no table header abstraction and still contains `LeaderboardAvatar`.

### Task 2: Replace Summary Rows with Table Rows

**Files:**
- Modify: `VibeUsage/Views/LeaderboardView.swift`

- [ ] **Step 1: Add explicit table columns**

Add the following private enum and board properties, then render `leaderboardColumnHeader` between the title divider and data rows:

```swift
private enum LeaderboardTableColumn: Hashable {
    case rank
    case user
    case tokens
    case cost

    var title: String {
        switch self {
        case .rank: "#"
        case .user: "用户"
        case .tokens: "Token"
        case .cost: "美金消耗"
        }
    }
}

private var leaderboardColumns: [LeaderboardTableColumn] {
    metric == .cost ? [.rank, .user, .tokens, .cost] : [.rank, .user, .cost, .tokens]
}

private var leaderboardColumnHeader: some View {
    HStack(spacing: 10) {
        ForEach(leaderboardColumns, id: \.self) { column in
            leaderboardCell(column: column, row: nil, rank: nil)
        }
    }
    .padding(.horizontal, 12)
    .frame(height: leaderboardRowHeight)
    .background(AppTheme.surface)
}
```

- [ ] **Step 2: Flatten each row**

Remove `LeaderboardAvatar` and the nested metric `VStack`. Use one `HStack` over `leaderboardColumns`; give rank a fixed 26-point width, both numeric columns a fixed 86-point width, and the user the remaining width. `primaryColumn` is `.cost` for spend boards and `.tokens` for token boards. When every token-ranked row lacks quota, omit the empty cost column instead of filling it with em dashes. Use `AppTheme.costAccent` only for the primary column. Keep board title, column header, and data rows at 44 points, increase the column-header font to 11 points, and use `AppTheme.surface` for every table row.

- [ ] **Step 3: Run the focused test and verify GREEN**

Run the focused command from Task 1. Expected: PASS.

### Task 3: Verify and Ship

**Files:**
- Modify: `docs/superpowers/specs/2026-07-17-native-leaderboard-design.md`

- [ ] **Step 1: Run all tests**

Run the full Swift test command with the local Testing framework paths. Expected: all tests pass.

- [ ] **Step 2: Build, sign, install, and inspect**

Run `./scripts/build-app.sh`, verify `dist/Vibe Usage.app` with `codesign --verify --deep --strict`, install it into `/Applications`, and visually verify aligned columns at the normal window size and after scrolling.

- [ ] **Step 3: Commit and push**

Stage only the leaderboard view, regression test, and related docs; commit the readability fix and push `codex/standard-window-macos` to update PR #1.
