# Filter Row Selection Visual Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep every filter option row background transparent while retaining checkbox-only selected and mixed-state coloring.

**Architecture:** Make one presentation-only change in `FilterPanelView.checkRowContent`; state mutation, full-row hit testing, grouping, and overlay placement remain untouched. Lock the behavior with the existing source-ownership regression-test pattern because the package has no SwiftUI snapshot-test target.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, macOS Accessibility, CoreGraphics mouse events

---

### Task 1: Constrain Selection Color to the Checkbox

**Files:**
- Modify: `Tests/VibeUsageTests/DashboardLayoutTests.swift:111-130`
- Modify: `VibeUsage/Views/FilterTagsView.swift:399-443`

- [ ] **Step 1: Write the failing regression test**

Add this test to `DashboardLayoutTests`:

```swift
@Test
func filterSelectionColorIsConfinedToTheCheckbox() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let filterSource = try String(
        contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/FilterTagsView.swift"),
        encoding: .utf8
    )

    #expect(filterSource.contains(".contentShape(Rectangle())"))
    #expect(filterSource.contains(".fill(isSelected || isMixed ? AppTheme.primaryText : Color.clear)"))
    #expect(!filterSource.contains(".background(isSelected || isMixed ? AppTheme.selectionBackground : Color.clear)"))
}
```

- [ ] **Step 2: Run the regression test and verify RED**

Run:

```bash
./scripts/test.sh --filter DashboardLayoutTests.filterSelectionColorIsConfinedToTheCheckbox
```

Expected: FAIL only on the negative expectation because `checkRowContent` still applies `AppTheme.selectionBackground` to selected and mixed rows.

- [ ] **Step 3: Apply the minimal presentation fix**

Change the end of `checkRowContent` to:

```swift
        .frame(height: FilterPanelLayout.rowHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
```

Do not alter `checkbox`, `optionRow`, filter state, row dimensions, or hit testing.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
./scripts/test.sh --filter DashboardLayoutTests.filterSelectionColorIsConfinedToTheCheckbox
```

Expected: 1 test passes with 0 issues.

- [ ] **Step 5: Run the full test suite**

Run:

```bash
./scripts/test.sh
```

Expected: all 43 existing tests plus the new regression test pass.

### Task 2: Build and Install the Corrected App

**Files:**
- Generated: `dist/Vibe Usage.app`
- Replace installed bundle: `/Applications/Vibe Usage.app`

- [ ] **Step 1: Build the Release app**

Run:

```bash
./scripts/build-app.sh
```

Expected: production build completes, the app bundle is generated, and ad-hoc signing completes when no Developer ID is available.

- [ ] **Step 2: Back up and replace the installed bundle**

Run the existing safe-install sequence: quit `VibeUsage`, move `/Applications/Vibe Usage.app` into a new `/tmp/vibe-usage-install.XXXXXX` directory, copy the Release bundle with `ditto`, and reopen it.

- [ ] **Step 3: Verify signature and executable identity**

Run:

```bash
codesign --verify --deep --strict "dist/Vibe Usage.app"
codesign --verify --deep --strict "/Applications/Vibe Usage.app"
shasum -a 256 "dist/Vibe Usage.app/Contents/MacOS/VibeUsage"
shasum -a 256 "/Applications/Vibe Usage.app/Contents/MacOS/VibeUsage"
```

Expected: both signature checks exit successfully and both SHA-256 values match.

### Task 3: Verify the Installed Visual Behavior

**Files:**
- Inspect only: installed `/Applications/Vibe Usage.app`

- [ ] **Step 1: Reproduce selection with real mouse events**

Open the model filter, expand the GPT family, and click a model row using `CGEvent` mouse move/down/up events rather than Accessibility activation.

- [ ] **Step 2: Capture and inspect the selected state**

Capture the installed app window after selection. Verify that the selected model shows a filled checkbox and checkmark, the partially selected family shows a filled checkbox and minus symbol, and both row backgrounds match neighboring unselected rows.

- [ ] **Step 3: Verify full-row hit testing remains intact**

Click the text area near the right side of a model row with a real mouse event. Verify the checkbox toggles even though only the checkbox changes color.

- [ ] **Step 4: Restore clean UI state and perform final checks**

Clear filters, close the menu, run `./scripts/test.sh` again, run `git diff --check` for the two modified source/test files, and confirm `VibeUsage` is running from `/Applications/Vibe Usage.app`.

## Working Tree Safety

The worktree already contains broad uncommitted changes, including both implementation files. Do not stage or commit implementation changes from this plan, because doing so would also capture unrelated existing hunks. Preserve all pre-existing modifications.
