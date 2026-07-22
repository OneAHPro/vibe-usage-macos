# VibeCafé Dashboard Redesign

## Goal

Rebuild the native macOS dashboard to closely match the supplied VibeCafé reference: a calm, wide desktop analytics workspace with a fixed navigation rail, compact actions, dense summary cards, chart grids, and a detailed usage table. Reuse the current SwiftUI views and data model rather than embedding the website or inventing disconnected placeholder features.

## Chosen Approach

Use a native SwiftUI desktop shell and reorganize the existing components inside it. Existing usage, filter, quota, sync, chart, distribution, settings, and external-link behavior remains the source of truth. Add only three presentation units that the current client does not have: the sidebar shell, an activity heatmap derived from `UsageSession`, and a detailed records grid derived from `UsageBucket`.

This is preferred over a superficial reskin, which would omit major visual landmarks from the reference, and over a WebView, which would abandon native components and make offline/background behavior less predictable.

## Window and Responsive Layout

- Default content size: 1280 × 820.
- Minimum content size: 1024 × 680.
- A new frame autosave name avoids restoring the old narrow window size.
- The sidebar is fixed at 188 points.
- The main content area has a compact top bar and one vertical scroll view.
- Summary cards use five columns when the main area is at least 900 points wide and two columns below that threshold.
- The trend and activity heatmap use two equal columns on wide windows and stack vertically on narrower windows.
- Distribution cards stay in a two-column grid.
- The detailed records grid has a minimum width and uses horizontal scrolling only when required.

## Visual System

- Continue using `AppTheme` so Light and Dark appearances follow macOS live.
- Use the reference's low-contrast neutral canvas, white/dark elevated cards, thin separators, 6–8 point corner radii, restrained shadows, and monospaced numeric values.
- Preserve green for cost/success, blue for active duration, orange/red for warnings, and the existing chart-series colors.
- Increase information density through smaller gaps and type scale, not by shrinking interactive controls below normal macOS targets.

## Component Architecture

### `DashboardShellView`

Owns the top-level `HStack`: `DashboardSidebarView` and `DashboardMainView`. It receives `AppState` through the existing environment and does not own data fetching.

### `DashboardSidebarView`

Shows the VibeCafé wordmark and real destinations/actions only:

- Vibe Usage (active dashboard)
- 排行榜 (existing web URL)
- 设置 (existing settings window)
- 同步数据 (existing sync and rate-limit refresh)
- bottom sync status, app version, and quit action

No decorative menu item is shown unless it has working behavior.

### `DashboardMainView`

Contains:

1. title and action buttons;
2. sync/status banner;
3. subscription quota cards;
4. existing filters;
5. expanded summary grid;
6. trend and activity heatmap row;
7. four existing distribution cards;
8. detailed usage records.

### `SummaryCardsView`

Expands from four to ten metrics using current data only:

- estimated cost;
- total tokens;
- input tokens;
- output plus reasoning tokens;
- cached input tokens;
- active duration;
- total session duration;
- session count;
- message count;
- user message count.

The aggregation logic moves into a small, testable `DashboardMetrics` value.

### `ActivityHeatmapView`

Groups filtered sessions by weekday and hour. Cell intensity is based on active seconds normalized to the maximum visible bucket. Empty cells remain visible as a subtle grid, matching the reference without fabricating activity.

### `UsageRecordsView`

Displays the most recent 50 filtered `UsageBucket` rows, sorted newest first. Columns are date, terminal, tool, model, project, input, output, cache, and estimated cost. The view uses the same active filters and time range as the cards and charts.

## Data Flow

`AppState` remains the sole state owner. A shared filtering helper produces filtered buckets and sessions so the summary, heatmap, distribution, trend, and records agree. UI actions call the existing `AppState` methods and existing settings controller. No API contract or synchronization behavior changes in this milestone.

## States and Error Handling

- Loading keeps the existing refresh overlay but confines it to the content canvas.
- Empty data keeps quota information and filters visible, then shows the existing empty state in the analytics region.
- Sync errors appear in the status banner and sidebar footer without resizing the dashboard.
- Narrow-window overflow is handled by responsive grids and the records horizontal scroller, not clipped content.

## Testing

- Window tests verify the new default/minimum size and frame autosave identity.
- Metrics tests verify all ten totals and preserve explicit zero values.
- Heatmap tests verify weekday/hour aggregation and normalization.
- Record tests verify filtering, descending order, and the 50-row cap.
- Existing rate-limit, theme, and window-lifecycle tests continue to pass.
- Release builds are installed and captured in both Light and Dark appearances for visual comparison with the supplied reference.

## Out of Scope

- New-system API integration.
- Website-only social, badge, club, achievement, or referral features that have no current client behavior.
- Pixel-identical browser typography; the macOS client keeps native text rendering and window controls.
