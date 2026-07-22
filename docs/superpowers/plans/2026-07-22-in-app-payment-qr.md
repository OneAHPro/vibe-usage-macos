# In-App Payment QR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace automatic browser payment launches with a reusable in-app QR-code checkout sheet for wallet top-ups and subscriptions.

**Architecture:** Convert every validated `PaymentCheckout` into a scannable HTTPS URL, render it with Core Image in a dedicated SwiftUI sheet, and present the same sheet from wallet and subscription flows. Payment completion remains user-triggered and refreshes wallet data once without polling.

**Tech Stack:** Swift 6, SwiftUI, Core Image, AppKit, Observation, Swift Testing.

---

### Task 1: Define checkout URL and QR contracts

**Files:**
- Create: `Tests/VibeUsageTests/PaymentQRCodeTests.swift`
- Modify: `Tests/VibeUsageTests/DashboardLayoutTests.swift`

- [ ] Add a test that converts `.form` action and signed fields into a valid HTTPS URL while preserving existing query items.
- [ ] Add a test that rejects non-web QR targets and renders a non-empty QR image for a valid URL.
- [ ] Require wallet and subscription sources to use `PaymentQRCodeSheet` and forbid `ExternalPaymentLauncher` in their primary checkout functions.
- [ ] Run `./scripts/test.sh --filter PaymentQRCodeTests` and verify RED because the QR conversion and renderer do not exist.

### Task 2: Implement the reusable QR sheet

**Files:**
- Create: `VibeUsage/Views/PaymentQRCodeSheet.swift`
- Modify: `VibeUsage/Models/AccountManagement.swift`

- [ ] Add validated `PaymentCheckout.qrCodeURL` conversion for direct URLs and signed form fields.
- [ ] Add a Core Image QR renderer with no image interpolation.
- [ ] Build a compact native sheet with method, amount, QR image, copy-link fallback, cancel, and one-shot completion refresh actions.
- [ ] Re-run `./scripts/test.sh --filter PaymentQRCodeTests` and verify GREEN.

### Task 3: Connect wallet and subscription payment flows

**Files:**
- Modify: `VibeUsage/Views/WalletManagementView.swift`
- Modify: `VibeUsage/Views/SubscriptionPurchaseSheet.swift`
- Modify: `VibeUsage/Models/WalletManagementStore.swift`
- Modify: `Tests/VibeUsageTests/AccountManagementStoreTests.swift`

- [ ] Add a failing counter-based test proving completion refresh loads overview once and reloads records only when records were previously visible.
- [ ] Add `refreshAfterPayment` with no timer, polling, or retry loop.
- [ ] Replace automatic browser launch with QR-sheet state in both payment entry points.
- [ ] Rename actions and helper text to describe scanning instead of browser navigation.
- [ ] Run focused store and layout tests and verify GREEN.

### Task 4: Verify and deliver

**Files:**
- Verify all modified production, test, and documentation files.

- [ ] Run `./scripts/test.sh`, `git diff --check`, `./scripts/build-app.sh`, and strict codesign verification.
- [ ] Review all changed code and fix every Critical/Important finding.
- [ ] Back up and install `/Applications/Vibe Usage.app`.
- [ ] Verify wallet and subscription QR sheets without completing a real payment.
- [ ] Commit and push `codex/standard-window-macos`.
