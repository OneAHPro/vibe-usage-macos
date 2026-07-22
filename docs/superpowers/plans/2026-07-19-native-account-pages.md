# Native Account Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add native token management, wallet management, and activity center pages to the macOS sidebar while reusing the authenticated new-system session and the app's current UI language.

**Architecture:** Add focused account-domain DTOs plus separate token and wallet stores. Extend `APIClient` through a small account-management protocol, keep each page's state outside `DashboardShellView`, and use a dedicated external-payment launcher for browser handoff. Navigation owns the stores and loads them only when their page becomes visible; no page joins the automatic usage/leaderboard refresh coordinator.

**Tech Stack:** Swift 6, SwiftUI, Observation, Foundation URLSession, AppKit, Swift Testing, existing `AppTheme` and dashboard layout components.

---

### Task 1: Add native navigation and the activity-center empty state

**Files:**
- Modify: `VibeUsage/Views/DashboardShellView.swift`
- Create: `VibeUsage/Views/TokenManagementView.swift`
- Create: `VibeUsage/Views/WalletManagementView.swift`
- Create: `VibeUsage/Views/ActivityCenterView.swift`
- Modify: `Tests/VibeUsageTests/DashboardLayoutTests.swift`

- [ ] **Step 1: Write the failing navigation test**

Add expectations proving `DashboardPage` exposes `.tokens`, `.wallet`, and `.activity`, that their titles are correct, that the shell maps each case to a native view, and that the three sidebar actions assign the selected page. Also assert `ActivityCenterView.swift` contains “暂无活动” and contains no `APIClient`, `.task`, or timer.

```swift
#expect(DashboardPage.tokens.title == "令牌管理")
#expect(DashboardPage.wallet.title == "钱包管理")
#expect(DashboardPage.activity.title == "活动中心")
#expect(shell.contains("TokenManagementView()"))
#expect(shell.contains("WalletManagementView()"))
#expect(shell.contains("ActivityCenterView()"))
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
./scripts/test.sh --filter DashboardLayoutTests/sidebarPagesProvideInlineNavigationTitles
```

Expected: FAIL because the three page cases and views do not exist.

- [ ] **Step 3: Implement the navigation skeleton**

Add page cases with these subtitles:

```swift
case .tokens: "创建、限制和保护 API 令牌"
case .wallet: "余额、充值与账单记录"
case .activity: "查看当前可参与的账户活动"
```

Insert a “账户” sidebar section between “数据” and “应用”, using `key.horizontal`, `wallet.pass`, and `gift`. Set `openFilter = nil` before switching. Extend `remoteRefreshTarget` so all three cases return `.none`.

Create lightweight native placeholders for `TokenManagementView` and `WalletManagementView` so navigation remains buildable before their account stores land. Create `ActivityCenterView` as a scroll-free native empty-state card using `AppTheme.surface`, a 7pt rounded rectangle, the `gift` symbol, “暂无活动”, and “新活动上线后会在这里显示”.

- [ ] **Step 4: Run the navigation test and verify GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit the navigation skeleton**

```bash
git add VibeUsage/Views/DashboardShellView.swift VibeUsage/Views/TokenManagementView.swift VibeUsage/Views/WalletManagementView.swift VibeUsage/Views/ActivityCenterView.swift Tests/VibeUsageTests/DashboardLayoutTests.swift
git commit -m "feat: add native account page navigation"
```

### Task 2: Define account DTOs and formatting behavior

**Files:**
- Create: `VibeUsage/Models/AccountManagement.swift`
- Modify: `VibeUsage/Services/APIClient.swift`
- Modify: `Tests/VibeUsageTests/APIClientTests.swift`
- Create: `Tests/VibeUsageTests/AccountManagementDataTests.swift`

- [ ] **Step 1: Write failing decoding and formatting tests**

Cover the production snake-case payloads for `TokenRecord`, `TopUpInfo`, and `TopUpRecord`. Verify token status labels, unlimited quota, never-expiring time, wallet order status labels, and safe masked keys.

```swift
#expect(token.statusLabel == "已启用")
#expect(token.quotaLabel(quotaPerUnit: 500_000) == "$2.00")
#expect(token.expirationLabel == "永不过期")
#expect(topUp.statusLabel == "成功")
```

Extend `AuthenticatedUser` with optional `quota`, decoded from `quota`, and verify `/api/user/self` returns it.

- [ ] **Step 2: Run the data tests and verify RED**

```bash
./scripts/test.sh --filter 'AccountManagementDataTests|APIClientTests/currentUserUsesSavedUserHeader'
```

Expected: FAIL because the account DTOs and `AuthenticatedUser.quota` do not exist.

- [ ] **Step 3: Implement the DTOs**

Define:

```swift
struct TokenRecord: Codable, Identifiable, Equatable, Sendable { /* production token fields */ }
struct TokenPage: Decodable, Equatable, Sendable { let page: Int; let pageSize: Int; let total: Int; let items: [TokenRecord] }
struct TokenMutation: Encodable, Equatable, Sendable { /* name, quota, expiry, model/IP/group fields */ }
struct TopUpInfo: Decodable, Equatable, Sendable { /* enabled providers, minima, presets, pay methods */ }
struct TopUpRecord: Decodable, Identifiable, Equatable, Sendable { /* order fields */ }
struct TopUpPage: Decodable, Equatable, Sendable { let page: Int; let pageSize: Int; let total: Int; let items: [TopUpRecord] }
enum PaymentCheckout: Equatable, Sendable { case url(URL); case form(action: URL, fields: [String: String]) }
```

Use explicit `CodingKeys` for every snake-case property. Keep full keys out of `TokenRecord`; the list only contains the server-masked key.

- [ ] **Step 4: Run the data tests and verify GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit the account models**

```bash
git add VibeUsage/Models/AccountManagement.swift VibeUsage/Services/APIClient.swift Tests/VibeUsageTests/APIClientTests.swift Tests/VibeUsageTests/AccountManagementDataTests.swift
git commit -m "feat: add account management models"
```

### Task 3: Add authenticated token and wallet API methods

**Files:**
- Modify: `VibeUsage/Services/APIClient.swift`
- Create: `VibeUsage/Services/AccountManagementClient.swift`
- Modify: `Tests/VibeUsageTests/APIClientTests.swift`

- [ ] **Step 1: Write failing request-contract tests**

Use `MockURLProtocol` to verify method, path, query, `New-Api-User`, and JSON body for:

```text
GET    /api/token/?p=1&size=20
GET    /api/token/search?keyword=...&p=1&size=20
POST   /api/token/
PUT    /api/token/
PUT    /api/token/?status_only=true
DELETE /api/token/{id}
POST   /api/token/{id}/key
GET    /api/user/topup/info
GET    /api/user/topup/self?p=1&page_size=20
```

Verify the key endpoint returns only a local `String` and that no debug path contains a body.

- [ ] **Step 2: Run API tests and verify RED**

```bash
./scripts/test.sh --filter APIClientTests
```

Expected: FAIL because account methods are absent.

- [ ] **Step 3: Implement the account client protocol and API extension**

Create `AccountManagementClient` with async methods for listing/searching/creating/updating/toggling/deleting/revealing tokens, fetching the wallet snapshot, and creating payment checkout. Make `APIEnvelope` and the low-level `send` helpers internal so the extension can reuse the existing authentication, timeout, 401, and 429 handling.

For payments, map backend responses as follows:

```swift
stripe/creem/waffo URL payload -> .url(validatedHTTPSURL)
epay { url, data } payload      -> .form(action: validatedHTTPSURL, fields: stringFields)
```

Reject non-HTTP(S) checkout URLs with `APIError.invalidResponse`.

- [ ] **Step 4: Run API tests and verify GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit the account API layer**

```bash
git add VibeUsage/Services/APIClient.swift VibeUsage/Services/AccountManagementClient.swift Tests/VibeUsageTests/APIClientTests.swift
git commit -m "feat: add account management API client"
```

### Task 4: Add page stores with request deduplication

**Files:**
- Create: `VibeUsage/Models/TokenManagementStore.swift`
- Create: `VibeUsage/Models/WalletManagementStore.swift`
- Create: `Tests/VibeUsageTests/AccountManagementStoreTests.swift`

- [ ] **Step 1: Write failing store tests with a fake account client**

Cover:

- first load runs once and a second appearance does not refetch;
- manual refresh does refetch;
- search only runs on explicit submit;
- mutations disable duplicate submission and refresh the current page;
- failed refresh keeps old rows and exposes an inline error;
- revealed full key is passed directly to a callback and never assigned to a store property;
- wallet load fetches user, top-up info, and history once;
- activity center owns no store.

```swift
await store.loadIfNeeded(client: fake)
await store.loadIfNeeded(client: fake)
#expect(fake.tokenPageCalls == 1)
```

- [ ] **Step 2: Run store tests and verify RED**

```bash
./scripts/test.sh --filter AccountManagementStoreTests
```

Expected: FAIL because stores do not exist.

- [ ] **Step 3: Implement stores**

Both stores are `@MainActor @Observable final class` values. Use `isLoading`, `isMutating`, `hasLoaded`, `errorMessage`, page state, and a monotonically increasing load generation to ignore obsolete responses. Never create a Timer. Provide `loadIfNeeded`, `refresh`, pagination, and mutation methods. Token reveal accepts `(String) -> Void` so the full key remains stack-local.

- [ ] **Step 4: Run store tests and verify GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit stores**

```bash
git add VibeUsage/Models/TokenManagementStore.swift VibeUsage/Models/WalletManagementStore.swift Tests/VibeUsageTests/AccountManagementStoreTests.swift
git commit -m "feat: add account page state stores"
```

### Task 5: Build the native token-management UI

**Files:**
- Create: `VibeUsage/Views/AccountPageComponents.swift`
- Modify: `VibeUsage/Views/TokenManagementView.swift`
- Create: `VibeUsage/Views/TokenEditorSheet.swift`
- Modify: `VibeUsage/Views/DashboardShellView.swift`
- Modify: `Tests/VibeUsageTests/DashboardLayoutTests.swift`

- [ ] **Step 1: Write failing UI contract tests**

Assert the token page contains summary cards, an explicit-submit search field, refresh/new buttons, masked-key table columns, pagination, an editor sheet, status toggle, copy and delete actions. Assert there is no `Timer`, no `onChange` network search, and no stored `fullKey` property.

- [ ] **Step 2: Run UI tests and verify RED**

```bash
./scripts/test.sh --filter DashboardLayoutTests
```

Expected: FAIL because the token page is still a placeholder.

- [ ] **Step 3: Implement the token page**

Use the existing 20pt page inset, 12pt section spacing, 7pt cards, monospaced numeric values, and `AppTheme` colors. Keep a minimum table width with horizontal scrolling. Use `confirmationDialog` for deletion and `TokenEditorSheet` for create/edit. Copy the full key with:

```swift
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(key, forType: .string)
```

Immediately return from the reveal callback without assigning `key` to view or store state.

- [ ] **Step 4: Run UI and store tests and verify GREEN**

```bash
./scripts/test.sh --filter 'DashboardLayoutTests|AccountManagementStoreTests'
```

Expected: PASS.

- [ ] **Step 5: Commit the token UI**

```bash
git add VibeUsage/Views/AccountPageComponents.swift VibeUsage/Views/TokenManagementView.swift VibeUsage/Views/TokenEditorSheet.swift VibeUsage/Views/DashboardShellView.swift Tests/VibeUsageTests/DashboardLayoutTests.swift
git commit -m "feat: add native token management page"
```

### Task 6: Build wallet UI and secure browser checkout

**Files:**
- Create: `VibeUsage/Services/ExternalPaymentLauncher.swift`
- Modify: `VibeUsage/Views/WalletManagementView.swift`
- Modify: `VibeUsage/Views/DashboardShellView.swift`
- Create: `Tests/VibeUsageTests/ExternalPaymentLauncherTests.swift`
- Modify: `Tests/VibeUsageTests/DashboardLayoutTests.swift`

- [ ] **Step 1: Write failing wallet and launcher tests**

Verify wallet source contains current balance, historical consumption, request count, recharge controls, history table and manual refresh. Test that URL checkout accepts only HTTP(S), form checkout escapes field names/values, writes a user-private temporary file, opens it, and schedules deletion. Assert no payment fields are logged.

- [ ] **Step 2: Run tests and verify RED**

```bash
./scripts/test.sh --filter 'ExternalPaymentLauncherTests|DashboardLayoutTests'
```

Expected: FAIL because wallet UI and launcher do not exist.

- [ ] **Step 3: Implement checkout launcher and wallet page**

`ExternalPaymentLauncher` receives injected open/write/remove closures for testing. Form HTML must HTML-escape action, keys, and values, use `method="POST"`, contain no analytics scripts, and write with POSIX `0600` permissions. Direct URL checkout calls `NSWorkspace.shared.open`.

Wallet UI uses three summary cards, a restrained native recharge card, and a white/dark adaptive history table. Disable checkout during order creation. After browser launch, show “支付完成后请刷新余额与账单” and leave final status to the server.

- [ ] **Step 4: Run wallet tests and verify GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit wallet UI**

```bash
git add VibeUsage/Services/ExternalPaymentLauncher.swift VibeUsage/Views/WalletManagementView.swift VibeUsage/Views/DashboardShellView.swift Tests/VibeUsageTests/ExternalPaymentLauncherTests.swift Tests/VibeUsageTests/DashboardLayoutTests.swift
git commit -m "feat: add native wallet management page"
```

### Task 7: Integrate authentication handling and verify the product

**Files:**
- Modify: `VibeUsage/Models/AppState.swift`
- Modify: `Tests/VibeUsageTests/AppStateRefreshTests.swift`
- Modify: `Tests/VibeUsageTests/PerformanceHotPathTests.swift`

- [ ] **Step 1: Write failing integration tests**

Verify account pages receive the authenticated account client, unauthorized responses clear the remote session, account pages are excluded from `VisibleRefreshCoordinator`, and none of the new sources contains `Timer.publish`, a repeating `Task.sleep` loop, or body/key logging.

- [ ] **Step 2: Run integration tests and verify RED**

```bash
./scripts/test.sh --filter 'AppStateRefreshTests|PerformanceHotPathTests'
```

Expected: FAIL until AppState exposes the scoped account client and unauthorized handler.

- [ ] **Step 3: Complete integration**

Expose only an internal authenticated `AccountManagementClient` factory and an account-error handler from AppState. Keep cookie/session clearing centralized. On logout, reset both page stores so another user cannot see cached rows from the prior account.

- [ ] **Step 4: Run full verification**

```bash
./scripts/test.sh
git diff --check
./scripts/build-app.sh
codesign --verify --deep --strict "dist/Vibe Usage.app"
```

Expected: all tests pass, diff check is clean, release build succeeds, and signature verification exits 0.

- [ ] **Step 5: Install and visually verify**

Back up the existing `/Applications/Vibe Usage.app`, install the newly built bundle, then verify:

- all three sidebar rows are fully clickable;
- token table, sheets and confirmation UI match the existing app;
- wallet summary/recharge/history use native app styling;
- activity center shows only the approved empty state;
- resize and scrolling remain smooth;
- opening pages does not create repeated network requests.

- [ ] **Step 6: Commit and push final integration**

```bash
git add VibeUsage Tests
git commit -m "feat: add native account management pages"
git push origin codex/standard-window-macos
```

Verify local and remote branch SHAs match and the worktree is clean.
