# Wallet Single-Page Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show subscription and recharge content together on one continuous wallet page without increasing backend load.

**Architecture:** Remove the segmented wallet state from `WalletManagementView`, compose current subscription and recharge cards in an adaptive grid, then render plans and lazy funding history below. Keep all API and store contracts unchanged except that the page-level refresh always requests the complete wallet overview.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing.

---

### Task 1: Define the single-page source contract

**Files:**
- Modify: `Tests/VibeUsageTests/DashboardLayoutTests.swift`

- [ ] Require `walletOverviewGrid`, current subscription, recharge, plan and history cards in one view hierarchy.
- [ ] Forbid `selectedSection`, `sectionPicker`, segmented picker styling and the `WalletSection` enum.
- [ ] Require funding history to retain `loadFundingRecordsIfNeeded` lifecycle loading.
- [ ] Run `./scripts/test.sh --filter walletManagementUsesNativeSubscriptionRechargeAndFundingSections` and verify RED.

### Task 2: Implement the continuous adaptive layout

**Files:**
- Modify: `VibeUsage/Views/WalletManagementView.swift`

- [ ] Remove segmented state, picker, switch and section-change task.
- [ ] Add an adaptive `LazyVGrid` containing current-subscription and recharge cards.
- [ ] Render available plans and funding history below the grid.
- [ ] Attach the existing lazy history request to the history card lifecycle.
- [ ] Make the page refresh use `.subscriptions`, which already loads balance, recharge configuration, plans and subscriptions.
- [ ] Re-run the focused test and verify GREEN.

### Task 3: Verify and deliver

**Files:**
- Verify all modified source, tests and docs.

- [ ] Run `./scripts/test.sh`, `git diff --check`, `./scripts/build-app.sh` and strict codesign verification.
- [ ] Review the diff for regressions and fix every Critical/Important finding.
- [ ] Back up and install `/Applications/Vibe Usage.app`.
- [ ] Verify the continuous page at wide and narrow window sizes without initiating payment.
- [ ] Commit and push `codex/standard-window-macos`.
