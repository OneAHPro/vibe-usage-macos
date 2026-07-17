# Leaderboard Detail Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strengthen leaderboard section hierarchy and add comfortable horizontal breathing room inside every leaderboard table.

**Architecture:** Keep the existing 48-point block rhythm and 44-point table rows. Style only `usageSection` titles at 18 points with 16 points to their cards, and centralize a 20-point table content inset inside `LeaderboardBoardCard`.

**Tech Stack:** SwiftUI, Swift Testing, Swift Package Manager.

---

### Task 1: Lock the desired hierarchy and table inset with a failing test

**Files:**
- Modify: `Tests/VibeUsageTests/DashboardLayoutTests.swift`
- Modify: `VibeUsage/Views/LeaderboardView.swift`

- [ ] Add `leaderboardUsesReadableSectionTitlesAndTableInsets`, asserting source tokens for `leaderboardSectionTitleSize = 18`, `leaderboardTitleSpacing = 16`, and `leaderboardContentInset = 20`.
- [ ] Run the focused Swift test and confirm it fails because those tokens are absent.

### Task 2: Apply the minimal leaderboard-only polish

**Files:**
- Modify: `VibeUsage/Views/LeaderboardView.swift`

- [ ] Add three private constants to `LeaderboardView`/`LeaderboardBoardCard` with the exact values 18, 16, and 20.
- [ ] Render `usageSection` titles directly at 18-point bold while leaving `sectionTitle("我的排名")` at 14 points.
- [ ] Replace the three table `.padding(.horizontal, 12)` calls with the shared 20-point inset.
- [ ] Run the focused test, then the full Swift test suite.

### Task 3: Build and verify the real app

**Files:**
- Verify: `/Applications/Vibe Usage.app`

- [ ] Run `./scripts/build-app.sh` and confirm the Release build and signature verification succeed.
- [ ] Safely replace the installed app, launch the leaderboard, and visually verify the larger section titles/gaps plus inset rank and spend columns.
- [ ] Commit with `style: polish leaderboard hierarchy and insets` and push `codex/standard-window-macos`.
