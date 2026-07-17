# Leaderboard Section Spacing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Match the official leaderboard's large category breaks by separating the personal, today, yesterday, and total blocks with 48 points of vertical space.

**Architecture:** Add one leaderboard-specific layout token to `DashboardLayout`. Compose populated leaderboard content inside a dedicated stack that uses the token, leaving the status strip, card internals, row heights, and other dashboard pages unchanged.

**Tech Stack:** SwiftUI, Swift Testing, Swift Package Manager.

---

### Task 1: Define and apply the section-spacing token

**Files:**
- Modify: `VibeUsage/Views/DashboardLayout.swift`
- Modify: `VibeUsage/Views/LeaderboardView.swift`
- Test: `Tests/VibeUsageTests/DashboardLayoutTests.swift`

- [ ] **Step 1: Write the failing layout assertions**

Add assertions that `DashboardLayout.leaderboardSectionSpacing` equals `48` and that `LeaderboardView` uses it for the populated leaderboard stack.

- [ ] **Step 2: Run the focused test to verify RED**

Run:

```bash
DYLD_FRAMEWORK_PATH=/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
DYLD_LIBRARY_PATH=/Library/Developer/CommandLineTools/Library/Developer/usr/lib \
swift test -Xswiftc -F \
  -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  --filter DashboardLayoutTests.leaderboardUsesOfficialSectionSpacing
```

Expected: compilation fails because `leaderboardSectionSpacing` does not exist.

- [ ] **Step 3: Add the minimal layout token and populated-content stack**

Add:

```swift
static let leaderboardSectionSpacing: CGFloat = 48
```

Move the personal, today, yesterday, and total sections into a `VStack` using that token. Keep each `usageSection` title-to-card spacing at `8`.

- [ ] **Step 4: Verify the focused and full test suites**

Run the focused command again, then run the complete `swift test` command with the same framework environment. Expected: all tests pass.

- [ ] **Step 5: Build, install, and visually verify**

Run `./scripts/build-app.sh`, safely replace `/Applications/Vibe Usage.app`, relaunch it, and capture the populated leaderboard. Verify larger gaps above 今日榜、昨日榜、总排行 without changing table row height.

- [ ] **Step 6: Commit and push**

```bash
git add VibeUsage/Views/DashboardLayout.swift \
  VibeUsage/Views/LeaderboardView.swift \
  Tests/VibeUsageTests/DashboardLayoutTests.swift \
  docs/superpowers/specs/2026-07-17-native-leaderboard-design.md \
  docs/superpowers/plans/2026-07-17-leaderboard-section-spacing.md
git commit -m "style: increase leaderboard section spacing"
git push origin codex/standard-window-macos
```
