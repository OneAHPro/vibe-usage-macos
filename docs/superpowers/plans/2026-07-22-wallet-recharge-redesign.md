# Wallet Recharge Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the exposed payment-calculation step with a single “立即充值” action, redesign the recharge card around the amount and primary action, and make the subscription/recharge overview cards truly equal-height.

**Architecture:** Keep the existing payment API contract but move amount calculation inside a new store-level checkout preparation operation. The view receives one result containing both the checkout URL/form and the final amount, then presents the existing native QR sheet. The custom two-column layout remains responsible for row measurement while both card roots become vertically flexible and share one minimum-height token.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing, Swift Package Manager

---

### Task 1: Specify one-action checkout behavior

**Files:**
- Modify: `Tests/VibeUsageTests/AccountManagementStoreTests.swift`
- Modify: `VibeUsage/Models/WalletManagementStore.swift`

- [ ] **Step 1: Write failing store tests**

Add tests that call `prepareCheckout(_:knownAmount:client:)` and verify:

```swift
let prepared = await store.prepareCheckout(.stripe(amount: 20), client: client)
#expect(prepared?.amount == 10)
#expect(prepared?.checkout == .url(URL(string: "https://pay.example.com")!))
#expect(client.paymentAmountCalls == 1)
#expect(client.paymentCheckoutCalls == 1)
```

Add a failure test where `paymentAmountError` is set and assert `paymentCheckoutCalls == 0`. Add a known-price test for `.creem(productID:)` and assert `paymentAmountCalls == 0` while the checkout is created once.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
./scripts/test.sh --filter AccountManagementStoreTests
```

Expected: compilation failure because `prepareCheckout`, `PreparedPaymentCheckout`, and the fake-client counters do not exist.

- [ ] **Step 3: Implement the store operation**

Add:

```swift
struct PreparedPaymentCheckout: Equatable, Sendable {
    let checkout: PaymentCheckout
    let amount: Double
}
```

Replace the public estimate state and the estimate-guarded `createCheckout` path with:

```swift
func prepareCheckout(
    _ request: PaymentRequest,
    knownAmount: Double? = nil,
    client: any AccountManagementClient
) async -> PreparedPaymentCheckout? {
    guard !isMutating else { return nil }
    let operationGeneration = generation
    isMutating = true
    defer {
        if generation == operationGeneration { isMutating = false }
    }
    do {
        let amount = if let knownAmount {
            knownAmount
        } else {
            try await client.fetchPaymentAmount(request)
        }
        guard amount.isFinite, amount >= 0, generation == operationGeneration else { return nil }
        let checkout = try await client.createPaymentCheckout(request)
        guard generation == operationGeneration else { return nil }
        errorMessage = nil
        checkoutMessage = "支付完成后请刷新余额与账单"
        return PreparedPaymentCheckout(checkout: checkout, amount: amount)
    } catch {
        guard generation == operationGeneration else { return nil }
        record(error)
        return nil
    }
}
```

Remove `estimatedPaymentAmount`, `estimatedPaymentRequest`, `estimatePayment`, `setLocalPaymentEstimate`, `clearPaymentEstimate`, and their reset/load call sites. Update the existing payment-completion test to use `prepareCheckout`.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run `./scripts/test.sh --filter AccountManagementStoreTests`.

Expected: all `AccountManagementStoreTests` pass with no compiler warnings introduced by this change.

### Task 2: Specify the redesigned recharge card and equal-height contract

**Files:**
- Modify: `Tests/VibeUsageTests/DashboardLayoutTests.swift`
- Modify: `VibeUsage/Views/DashboardLayout.swift`
- Modify: `VibeUsage/Views/WalletManagementView.swift`

- [ ] **Step 1: Replace obsolete source assertions with the new UI contract**

Update the wallet view source test to require:

```swift
#expect(view.contains("立即充值"))
#expect(view.contains("正在创建支付订单"))
#expect(view.contains("下一步直接显示支付二维码"))
#expect(!view.contains("预计支付金额"))
#expect(!view.contains("请先计算"))
#expect(!view.contains("计算实付"))
#expect(!view.contains("calculatePaymentAmount"))
#expect(view.contains("prepareCheckout"))
#expect(view.contains("walletOverviewCardMinimumHeight"))
#expect(view.components(separatedBy: "maxHeight: .infinity").count - 1 >= 2)
```

Also assert `DashboardLayout.walletOverviewCardMinimumHeight >= 220`.

- [ ] **Step 2: Run the focused layout test and verify RED**

Run:

```bash
./scripts/test.sh --filter DashboardLayoutTests.walletManagementUsesNativeSubscriptionRechargeAndFundingSections
```

Expected: failure because the old calculation copy and controls still exist and the new height token is absent.

- [ ] **Step 3: Implement the layout token and flexible card roots**

In `DashboardLayout`, add:

```swift
static let walletOverviewCardMinimumHeight: CGFloat = 250
```

Before applying each card background, add:

```swift
.frame(
    maxWidth: .infinity,
    minHeight: DashboardLayout.walletOverviewCardMinimumHeight,
    maxHeight: .infinity,
    alignment: .topLeading
)
```

Make the empty subscription state use `frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)` so it fills the card without vertically stretching its labels.

- [ ] **Step 4: Recompose the recharge card**

Keep the existing channel and Creem selection behavior, but restructure the card into:

```text
余额充值                         支付方式
下一步直接显示支付二维码          [微信 ▾]

充值金额
┌──────────────────────────────┐
│ ¥ 20                         │
└──────────────────────────────┘
[100] [200] [400] [800] [1200]

[              立即充值              ]
支付二维码将在软件内显示，不会打开浏览器
```

Use a large monospaced amount field, selected-state shortcut buttons, and one full-width `.borderedProminent` action. Disable all payment inputs while `store.isMutating`.

- [ ] **Step 5: Make the button prepare and present checkout in one action**

Replace `calculatePaymentAmount` and the old `beginCheckout` body with a single task:

```swift
let knownAmount = selectedPaymentID == "creem" ? selectedCreemProduct?.price : nil
let productCurrency = selectedPaymentID == "creem" ? selectedCreemProduct?.currency : nil
Task {
    guard let prepared = await store.prepareCheckout(
        request,
        knownAmount: knownAmount,
        client: client
    ) else { return }
    guard prepared.checkout.qrCodeURL != nil else {
        store.errorMessage = "支付地址无效，请重新创建订单"
        return
    }
    let amount = productCurrency.map {
        Formatters.formatMoney(prepared.amount, currency: $0)
    } ?? Formatters.formatCost(prepared.amount)
    paymentQRCode = PaymentQRCodePresentation(
        checkout: prepared.checkout,
        title: "余额充值",
        paymentMethod: presentationPaymentMethod,
        amount: amount
    )
}
```

- [ ] **Step 6: Run focused tests and verify GREEN**

Run:

```bash
./scripts/test.sh --filter DashboardLayoutTests
./scripts/test.sh --filter AccountManagementStoreTests
./scripts/test.sh --filter PaymentQRCodeTests
```

Expected: all focused tests pass.

### Task 3: Verify, review, build, and install

**Files:**
- Verify all modified files
- Build output: `dist/Vibe Usage.app`

- [ ] **Step 1: Run formatting and diff checks**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only the planned source, test, and plan files are modified.

- [ ] **Step 2: Run the complete test suite**

Run `./scripts/test.sh`.

Expected: zero failed tests.

- [ ] **Step 3: Build the signed Release application**

Run:

```bash
./scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 "dist/Vibe Usage.app"
```

Expected: both commands exit 0 and codesign reports the bundle is valid on disk.

- [ ] **Step 4: Inspect the rendered wallet page**

Install the built app using the repository's existing safe replacement procedure, open the wallet page, and verify at default width:

- current subscription and recharge cards have equal outer height;
- no calculation copy or calculation button remains;
- one click on “立即充值” produces the in-app QR sheet;
- controls remain usable at the minimum window width;
- no browser opens and no payment-status timer is introduced.

- [ ] **Step 5: Commit and push**

Run:

```bash
git add VibeUsage/Models/WalletManagementStore.swift \
  VibeUsage/Views/DashboardLayout.swift \
  VibeUsage/Views/WalletManagementView.swift \
  Tests/VibeUsageTests/AccountManagementStoreTests.swift \
  Tests/VibeUsageTests/DashboardLayoutTests.swift \
  docs/superpowers/plans/2026-07-22-wallet-recharge-redesign.md
git commit -m "feat: streamline wallet recharge"
git push origin codex/standard-window-macos
```

Expected: local and remote branch tips match the new implementation commit.
