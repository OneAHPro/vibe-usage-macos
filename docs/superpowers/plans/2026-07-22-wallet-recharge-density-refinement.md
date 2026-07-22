# Wallet Recharge Density Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every preset amount and its real new-system discount the visual focus while shrinking the custom amount field and checkout button.

**Architecture:** Add a small pure presentation helper beside the decoded wallet data so discount rules are independently testable. Recompose only the standard recharge branch in `WalletManagementView`; payment request and checkout behavior remain unchanged.

**Tech Stack:** Swift 6, SwiftUI for macOS, Swift Testing, Swift Package Manager

---

### Task 1: Discount presentation

**Files:**
- Modify: `VibeUsage/Models/AccountManagement.swift`
- Test: `Tests/VibeUsageTests/AccountManagementDataTests.swift`

- [ ] **Step 1: Write the failing discount tests**

Add assertions proving `0.95` renders as `9.5 折`, `0.9` as `9 折`, and missing, non-finite, non-positive, or `>= 1` values return no label.

- [ ] **Step 2: Verify RED**

Run `./scripts/test.sh --filter AccountManagementDataTests` and confirm failure because the presentation API is absent.

- [ ] **Step 3: Add the pure helper**

Expose an internal `topUpDiscountPresentation(for:)` method that validates the exact configured rate and returns the compact Chinese label.

- [ ] **Step 4: Verify GREEN**

Run `./scripts/test.sh --filter AccountManagementDataTests` and confirm the focused suite passes.

### Task 2: Compact recharge composition

**Files:**
- Modify: `VibeUsage/Views/WalletManagementView.swift`
- Test: `Tests/VibeUsageTests/DashboardLayoutTests.swift`

- [ ] **Step 1: Write the failing UI contract test**

Require the source to contain `选择充值额度`, `自定义金额`, discount presentation, fixed input/button widths, four-column wrapping, all presets without prefix truncation, centered subscription empty state, and larger preset typography; reject a full-width CTA and the redundant QR footer.

- [ ] **Step 2: Verify RED**

Run `./scripts/test.sh --filter DashboardLayoutTests` and confirm the new contract fails.

- [ ] **Step 3: Recompose the recharge controls**

Render every preset first as larger four-column wrapping cards with discount badges, then place a compact custom field, selected discount note, and fixed-width checkout button in a restrained footer row. Center the subscription empty state in its content area.

- [ ] **Step 4: Verify GREEN**

Run `./scripts/test.sh --filter DashboardLayoutTests` and confirm the focused suite passes.

### Task 3: Release verification

**Files:**
- Verify all modified files

- [ ] **Step 1: Run complete checks**

Run `git diff --check && ./scripts/test.sh && ./scripts/build-app.sh` and require zero failures.

- [ ] **Step 2: Install and inspect**

Install the Release app, verify its signature and binary match, then inspect wallet layout at default and minimum widths without pressing checkout.

- [ ] **Step 3: Commit and push**

Commit the refinement on `codex/standard-window-macos` and push it to `origin` after verification.
