# Wallet Subscription Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the native wallet page into a focused balance, subscription, recharge, and funding-record center backed by the existing new-system subscription APIs.

**Architecture:** Extend account DTOs and `AccountManagementClient` with subscription plans, user subscription state, billing preference, and subscription checkout. Keep the behavior in `WalletManagementStore`, lazy-load funding records, and compose the SwiftUI wallet page from a compact balance header plus three native sections.

**Tech Stack:** Swift 6, SwiftUI, Observation, Foundation URLSession, AppKit browser handoff, Swift Testing.

---

### Task 1: Subscription data and API contracts

**Files:**
- Modify: `VibeUsage/Models/AccountManagement.swift`
- Modify: `VibeUsage/Services/AccountManagementClient.swift`
- Modify: `Tests/VibeUsageTests/AccountManagementDataTests.swift`
- Modify: `Tests/VibeUsageTests/APIClientTests.swift`

- [ ] Add failing tests for production `plans` and `self` payload decoding, duration/reset/quota formatting, preference update, and Stripe/Creem/Epay subscription checkout paths.
- [ ] Run `./scripts/test.sh --filter 'AccountManagementDataTests|APIClientTests'` and verify the new tests fail because subscription types and client methods are absent.
- [ ] Add `SubscriptionPlan`, `UserSubscription`, `SubscriptionSummary`, `SubscriptionSelf`, `BillingPreference`, and `SubscriptionPaymentRequest`; add fetch/update/checkout methods to the protocol and API client.
- [ ] Re-run the filtered tests and verify they pass.

### Task 2: Wallet store state and low-load behavior

**Files:**
- Modify: `VibeUsage/Models/WalletManagementStore.swift`
- Modify: `Tests/VibeUsageTests/AccountManagementStoreTests.swift`

- [ ] Add failing tests proving initial load fetches overview/plans/subscriptions once, funding records remain lazy, record pagination does not refetch subscription data, and purchase/preference mutations cannot duplicate.
- [ ] Run `./scripts/test.sh --filter AccountManagementStoreTests` and verify the failures describe missing subscription behavior.
- [ ] Implement subscription state, section-specific refresh, lazy funding-record loading, preference update, subscription checkout, and reset behavior.
- [ ] Re-run store tests and verify they pass.

### Task 3: Native wallet subscription layout

**Files:**
- Modify: `VibeUsage/Views/WalletManagementView.swift`
- Create: `VibeUsage/Views/SubscriptionPurchaseSheet.swift`
- Modify: `Tests/VibeUsageTests/DashboardLayoutTests.swift`
- Modify: `Tests/VibeUsageTests/PerformanceHotPathTests.swift`

- [ ] Add failing source-contract tests requiring a compact balance header, “订阅套餐/余额充值/资金记录” sections, current subscription details and plan cards; forbid “历史消耗”, “请求次数”, WebView, Timer, and automatic record loading.
- [ ] Run `./scripts/test.sh --filter 'DashboardLayoutTests|PerformanceHotPathTests'` and verify RED.
- [ ] Implement the segmented layout, active-subscription view, pricing cards, purchase Sheet, existing recharge view, and lazy record view using `AppTheme`.
- [ ] Re-run the filtered tests and verify GREEN.

### Task 4: Product verification and delivery

**Files:**
- Verify all modified production and test files.

- [ ] Run `./scripts/test.sh`, `git diff --check`, `./scripts/build-app.sh`, and strict codesign verification.
- [ ] Back up and install `/Applications/Vibe Usage.app`.
- [ ] Verify subscription, recharge, and funding-record sections in the running app at wide and narrow window sizes without initiating a real purchase.
- [ ] Commit the implementation and push `codex/standard-window-macos`.
