# Total Personal Rank Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decode the production `my_total_quota_rank` payload and show it as a third fixed-width card in the native leaderboard's personal-rank row.

**Architecture:** Extend `LeaderboardData` with one optional field using the existing `LeaderboardPersonalRank` type. Reuse `PersonalRankCard` so total rank inherits the same rank, spend, token, and null-state presentation as today and yesterday.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, Swift Package Manager.

---

### Task 1: Lock the response contract and third-card composition

**Files:**
- Modify: `Tests/VibeUsageTests/LeaderboardDataTests.swift`
- Modify: `Tests/VibeUsageTests/DashboardLayoutTests.swift`

- [ ] **Step 1: Add failing coverage for the new field and card**

Add `my_total_quota_rank` to the production JSON fixture and assert rank, quota, and token values through `data.myTotalQuotaRank`. Add source assertions that `LeaderboardView` renders `总消费排名` with `data.myTotalQuotaRank` and contains three `.frame(width: 240)` personal-card frames.

- [ ] **Step 2: Run the focused tests and verify red**

Run:

```bash
swift test --filter LeaderboardDataTests.decodesTheProductionLeaderboardShape
swift test --filter DashboardLayoutTests.nativeLeaderboardShowsAllThreePersonalRanks
```

Expected: the model test cannot compile until `myTotalQuotaRank` exists, and the layout test fails because the third card is absent.

### Task 2: Decode and render total personal rank

**Files:**
- Modify: `VibeUsage/Models/LeaderboardData.swift`
- Modify: `VibeUsage/Views/LeaderboardView.swift`
- Modify: `Tests/VibeUsageTests/AppStateRangeTests.swift`

- [ ] **Step 1: Add the optional response property**

Add:

```swift
let myTotalQuotaRank: LeaderboardPersonalRank?
```

and map it with:

```swift
case myTotalQuotaRank = "my_total_quota_rank"
```

- [ ] **Step 2: Add the third fixed-width card**

Append this card to the existing personal-rank `HStack`:

```swift
PersonalRankCard(
    title: "总消费排名",
    value: data.myTotalQuotaRank,
    quotaPerUnit: appState.quotaPerUnit
)
.frame(width: 240)
```

Update direct `LeaderboardData` initializers in tests with `myTotalQuotaRank: nil`.

- [ ] **Step 3: Run focused and full verification**

Run the two focused tests, then:

```bash
git diff --check
swift test
./scripts/build-app.sh
```

Expected: all tests pass, Release build completes, and the app bundle passes code-sign verification.

### Task 3: Install and verify production data

**Files:**
- Verify: `/Applications/Vibe Usage.app`

- [ ] **Step 1: Safely replace and launch the installed app**

Quit the current process, preserve the installed bundle as a `/tmp` backup, move the newly built bundle into `/Applications`, and launch it.

- [ ] **Step 2: Verify the native leaderboard**

Open `排行榜` and confirm `我的排名` shows three fixed-width cards in this order: `今日消费排名`, `昨日消费排名`, `总消费排名`. Confirm the total card displays the authenticated production rank, spend, and tokens, or the existing null state when the account has no history.

- [ ] **Step 3: Commit and push**

```bash
git add VibeUsage Tests docs/superpowers
git commit -m "feat: show total personal leaderboard rank"
git push origin codex/standard-window-macos
```
