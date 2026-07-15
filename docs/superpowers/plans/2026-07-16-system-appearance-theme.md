# System Appearance Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the installed macOS client automatically use a readable Light or Dark interface according to the current macOS appearance.

**Architecture:** A focused `AppTheme` type exposes semantic SwiftUI colors backed by dynamic AppKit system colors. Dashboard views consume those roles instead of fixed grayscale literals, while data/status colors remain explicit. `MainWindowController` no longer overrides the system appearance.

**Tech Stack:** Swift 6, SwiftUI, AppKit semantic `NSColor`, Swift Testing, Swift Package Manager

---

### Task 1: Let the standard window inherit system appearance

**Files:**
- Modify: `Tests/VibeUsageTests/MainWindowControllerTests.swift`
- Modify: `VibeUsage/Services/MainWindowController.swift`

- [ ] **Step 1: Write the failing window inheritance test**

Replace the existing dark-appearance expectation with:

```swift
#expect(window.appearance == nil)
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
./scripts/test.sh --filter MainWindowControllerTests.createsAStandardResizableMacWindow
```

Expected: FAIL because the window currently assigns `NSAppearance(named: .darkAqua)`.

- [ ] **Step 3: Remove the window appearance override**

Delete this line from `makeWindowIfNeeded()`:

```swift
window.appearance = NSAppearance(named: .darkAqua)
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the same focused command. Expected: one test passes.

- [ ] **Step 5: Commit**

```bash
git add Tests/VibeUsageTests/MainWindowControllerTests.swift VibeUsage/Services/MainWindowController.swift
git commit -m "feat: inherit macOS window appearance"
```

### Task 2: Add a semantic dynamic theme palette

**Files:**
- Create: `VibeUsage/Theme/AppTheme.swift`
- Create: `Tests/VibeUsageTests/AppThemeTests.swift`

- [ ] **Step 1: Write failing palette tests**

Create tests that ask the intended API to resolve representative background and text tokens under Aqua and Dark Aqua:

```swift
import AppKit
import Testing
@testable import VibeUsage

struct AppThemeTests {
    @Test
    func backgroundsFollowTheRequestedSystemAppearance() {
        let light = AppTheme.resolvedSRGB(.windowBackground, appearance: .aqua)
        let dark = AppTheme.resolvedSRGB(.windowBackground, appearance: .darkAqua)
        #expect(luminance(light) > luminance(dark))
    }

    @Test
    func primaryTextKeepsReadableContrastInBothAppearances() {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let background = AppTheme.resolvedSRGB(.windowBackground, appearance: appearance)
            let text = AppTheme.resolvedSRGB(.primaryText, appearance: appearance)
            #expect(contrast(background, text) >= 4.5)
        }
    }
}
```

The test file also defines local WCAG luminance and contrast helpers using the returned sRGB components.

- [ ] **Step 2: Run palette tests and verify RED**

```bash
./scripts/test.sh --filter AppThemeTests
```

Expected: build failure because `AppTheme` does not exist.

- [ ] **Step 3: Implement the semantic palette**

Create `AppTheme` with these tokens and system mappings:

```swift
enum AppTheme {
    enum Token {
        case windowBackground, surface, raisedSurface, subtleSurface
        case separator, primaryText, secondaryText, tertiaryText
        case selectionBackground, tooltipBackground
    }

    static func nsColor(_ token: Token) -> NSColor {
        switch token {
        case .windowBackground: return .windowBackgroundColor
        case .surface: return .controlBackgroundColor
        case .raisedSurface: return .textBackgroundColor
        case .subtleSurface: return .underPageBackgroundColor
        case .separator: return .separatorColor
        case .primaryText: return .labelColor
        case .secondaryText: return .secondaryLabelColor
        case .tertiaryText: return .tertiaryLabelColor
        case .selectionBackground: return .unemphasizedSelectedContentBackgroundColor
        case .tooltipBackground: return .controlBackgroundColor
        }
    }
}
```

Expose a SwiftUI `Color` property for every token and `resolvedSRGB(_:appearance:)` for deterministic tests.

- [ ] **Step 4: Run palette and full tests**

```bash
./scripts/test.sh --filter AppThemeTests
./scripts/test.sh
```

Expected: palette tests and the full suite pass.

- [ ] **Step 5: Commit**

```bash
git add VibeUsage/Theme/AppTheme.swift Tests/VibeUsageTests/AppThemeTests.swift
git commit -m "feat: add dynamic semantic app theme"
```

### Task 3: Migrate the dashboard shell and summary cards

**Files:**
- Modify: `VibeUsage/Views/PopoverView.swift`
- Modify: `VibeUsage/Views/SummaryCardsView.swift`
- Modify: `VibeUsage/Views/SettingsView.swift`

- [ ] **Step 1: Replace shell neutral colors**

Use the following role mapping throughout the three files:

```swift
Color(white: 0.04)  -> AppTheme.windowBackground
Color(white: 0.06)  -> AppTheme.subtleSurface
Color(white: 0.09)  -> AppTheme.surface
Color(white: 0.12)  -> AppTheme.raisedSurface
Color(white: 0.16)  -> AppTheme.separator
.white primary text -> AppTheme.primaryText
0.5...0.7 gray text -> AppTheme.secondaryText
0.3...0.45 gray text -> AppTheme.tertiaryText
```

Keep explicit success, warning, error, activity, and cost colors. Keep black text only when it sits on an explicit white/accent button background.

- [ ] **Step 2: Compile and run tests**

```bash
./scripts/test.sh
```

Expected: all tests pass with no compiler errors.

- [ ] **Step 3: Commit**

```bash
git add VibeUsage/Views/PopoverView.swift VibeUsage/Views/SummaryCardsView.swift VibeUsage/Views/SettingsView.swift
git commit -m "feat: theme dashboard shell for system appearance"
```

### Task 4: Migrate charts, filters, quota cards, and tooltips

**Files:**
- Modify: `VibeUsage/Views/BarChartView.swift`
- Modify: `VibeUsage/Views/DistributionChartsView.swift`
- Modify: `VibeUsage/Views/FilterTagsView.swift`
- Modify: `VibeUsage/Views/RateLimitCardView.swift`

- [ ] **Step 1: Replace chart and card surfaces**

Cards use `AppTheme.surface`, borders use `AppTheme.separator`, chart labels use the three text roles, selected segments use `AppTheme.selectionBackground`, and tooltips use `AppTheme.tooltipBackground`. Neutral chart marks use `AppTheme.primaryText`, `secondaryText`, or `tertiaryText`; semantic green/blue/orange/red series remain explicit.

- [ ] **Step 2: Replace filter and quota surfaces**

Filter popovers and quota tooltips use semantic surfaces and text. Selected checkmarks use `AppTheme.primaryText` on `AppTheme.selectionBackground`; disabled and hint labels use secondary or tertiary text. Progress-track backgrounds use the separator token and the neutral progress fill uses primary text.

- [ ] **Step 3: Confirm no dashboard-only fixed neutral palette remains**

```bash
rg -n "Color\(white:|Color\.black|Color\.white" VibeUsage/Views
```

Review every remaining match. It must be an intentional semantic data mark or explicit high-contrast control, not a background/card/text neutral.

- [ ] **Step 4: Run the full test suite**

```bash
./scripts/test.sh
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add VibeUsage/Views/BarChartView.swift VibeUsage/Views/DistributionChartsView.swift VibeUsage/Views/FilterTagsView.swift VibeUsage/Views/RateLimitCardView.swift
git commit -m "feat: theme charts filters and quota cards"
```

### Task 5: Build, install, and verify both appearance paths

**Files:**
- Build output: `dist/Vibe Usage.app`
- Install output: `/Applications/Vibe Usage.app`

- [ ] **Step 1: Run release verification**

```bash
./scripts/test.sh
./scripts/check-version.sh
./scripts/build-app.sh
codesign --verify --deep --strict "dist/Vibe Usage.app"
git diff --check
```

Expected: all tests pass, version is synchronized, release build and signature verification succeed, and Git reports no whitespace errors.

- [ ] **Step 2: Replace the installed app and launch it**

```bash
pkill -x VibeUsage 2>/dev/null || true
rm -rf "/Applications/Vibe Usage.app"
ditto "dist/Vibe Usage.app" "/Applications/Vibe Usage.app"
open "/Applications/Vibe Usage.app"
```

- [ ] **Step 3: Verify runtime behavior**

Confirm the installed bundle identifier is `com.codsexradar.vibe-usage`, the process runs from `/Applications`, the main window remains a standard 960-by-720 content window, closing keeps the process alive, and the menu-bar item reopens it.

- [ ] **Step 4: Verify appearance behavior**

Capture the installed window in the computer's current system appearance. In tests, resolve all representative tokens under both Aqua and Dark Aqua and verify readable contrast. Confirm no persisted theme preference or forced `NSAppearance` exists.

- [ ] **Step 5: Keep the branch for repository publication**

Keep `codex/standard-window-macos` and its clean working tree intact. Do not push, merge, or create a remote until the user explicitly authorizes the external repository operation.
