# Compact Personal Rank Label Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display `100+` for every personal leaderboard rank above 100 while preserving exact labels through rank 100.

**Architecture:** Keep the server's real rank unchanged in `LeaderboardPersonalRank`. Apply the compact threshold only inside the existing `LeaderboardPresentation.rankLabel` formatter so all three personal-rank cards share one deterministic rule.

**Tech Stack:** Swift 6, Swift Testing, Swift Package Manager, SwiftUI.

---

### Task 1: Define and implement the rank threshold

**Files:**
- Modify: `Tests/VibeUsageTests/LeaderboardDataTests.swift`
- Modify: `VibeUsage/Models/LeaderboardData.swift`

- [ ] **Step 1: Write the failing boundary test**

Add:

```swift
@Test
func personalRanksAboveOneHundredUseCompactLabel() {
    #expect(LeaderboardPresentation.rankLabel(
        .init(rank: 100, quota: 1, tokenUsed: 1)
    ) == "#100")
    #expect(LeaderboardPresentation.rankLabel(
        .init(rank: 101, quota: 1, tokenUsed: 1)
    ) == "100+")
    #expect(LeaderboardPresentation.rankLabel(
        .init(rank: 151, quota: 1, tokenUsed: 1)
    ) == "100+")
}
```

- [ ] **Step 2: Run the focused test and verify red**

Run `swift test --filter LeaderboardDataTests.personalRanksAboveOneHundredUseCompactLabel` with the repository's CommandLineTools framework environment. Expected: rank 101 and 151 still render as `#101` and `#151`.

- [ ] **Step 3: Add the minimal formatter branch**

Implement:

```swift
static func rankLabel(_ value: LeaderboardPersonalRank?) -> String {
    guard let value, value.rank > 0 else { return "未上榜" }
    if value.rank > 100 { return "100+" }
    return "#\(value.rank)"
}
```

- [ ] **Step 4: Verify focused and full tests**

Run the focused test, `git diff --check`, and the complete Swift test suite. Expected: all boundary and regression tests pass.

### Task 2: Build, install, and verify the real interface

**Files:**
- Verify: `/Applications/Vibe Usage.app`

- [ ] **Step 1: Build and install**

Run `./scripts/build-app.sh`, verify the generated bundle signature, preserve the old installed bundle in `/tmp`, and safely replace `/Applications/Vibe Usage.app`.

- [ ] **Step 2: Verify production ranks**

Open the native leaderboard and confirm the current ranks `115` and `151` display as `100+`, while the total rank `12` remains `#12`. Confirm all three cards still show their real spend and Token values.

- [ ] **Step 3: Commit and push**

```bash
git add VibeUsage/Models/LeaderboardData.swift Tests/VibeUsageTests/LeaderboardDataTests.swift docs/superpowers
git commit -m "style: compact personal ranks above one hundred"
git push origin codex/standard-window-macos
```
