# Native Leaderboard Design

**Date:** 2026-07-17
**Status:** Approved for planning
**Scope:** Vibe Usage macOS app only

## Goal

Replace every leaderboard link that opens the browser with a native SwiftUI page inside the existing desktop shell. The page must read the authenticated leaderboard data already exposed by the production new system and must not invent filters or rankings the server does not provide.

## Confirmed Product Decisions

- The sidebar **排行榜** row opens the native leaderboard page.
- The dashboard header **排行榜** action opens the same native page.
- The app no longer opens `/rankings` in a browser from either entry point.
- Do not show `24H`, `7D`, `30D`, tool, or model controls.
- Do not add new backend endpoints or extend the production leaderboard schema.
- Preserve server-provided masked usernames, display names, and sanitized avatar URLs.
- Do not display the invitation reward leaderboard because it is unrelated to usage ranking.

## Existing Data Source

The page calls authenticated `GET /api/user/leaderboard` through the existing `APIClient`. Authentication continues to use the URLSession-owned HttpOnly cookie and the saved `New-Api-User` header.

The response fields used by the app are:

- `quota_daily_top`: today's US-dollar-spend leaderboard, ten rows.
- `token_daily_top`: today's token leaderboard, five rows.
- `quota_yesterday_top`: yesterday's estimated-spend leaderboard, twenty rows.
- `quota_total_top`: total US-dollar-spend leaderboard, up to twenty rows.
- `token_total_top`: total token leaderboard, up to twenty rows.
- `my_daily_quota_rank`: the signed-in user's rank, spend, and tokens for today.
- `my_yesterday_quota_rank`: the signed-in user's rank, spend, and tokens for yesterday.

The app must not label the quota-based personal rank as an independent token rank. The token value in a personal-rank payload is supporting usage data for that same quota ranking.

## Navigation

Add `.leaderboard` to `DashboardPage` with title `排行榜` and subtitle `new 系统实时用量排名`.

Both leaderboard entry points set `selectedPage = .leaderboard`. The shell renders `LeaderboardView` in its content area. The existing header behavior for non-dashboard pages remains available, including **返回仪表盘**.

## Page Structure

The leaderboard page is a single scrollable native view with hidden scroll indicators:

1. **Status strip**
   - Shows `更新于 HH:mm` after a successful fetch.
   - Provides a native **刷新** action.
   - Keeps the last successful data visible during refresh.

2. **我的排名**
   - Two fixed-width, left-aligned compact cards: `今日消费排名` and `昨日消费排名`; they do not stretch to fill the window.
   - Each card shows the rank, US-dollar spend, and token usage returned for that quota rank.
   - A missing personal rank is shown as `未上榜`, not `0` and not a fabricated `100+`.

3. **今日榜**
   - One ten-row `美金消耗` ranking is split into two equal-width cards: ranks 1–5 on the left and 6–10 on the right.
   - Both cards use columns `#`, `用户`, `Token`, `美金消耗`; a separate token-ranked card is intentionally omitted because the spend rows already include token usage.

4. **昨日榜**
   - The twenty-row `美金消耗` ranking is split into ranks 1–10 on the left and 11–20 on the right.

5. **总排行**
   - The twenty-row `美金消耗` ranking is split into ranks 1–10 on the left and 11–20 on the right.
   - The independent `token_total_top` card is not rendered because `quota_total_top` already carries token usage.

The right-hand card keeps the original rank sequence instead of restarting at 1.

On a narrow window, paired cards stack vertically. No horizontal scrolling is required.

## Visual Direction

The page follows the app's existing restrained desktop system rather than copying the light website canvas:

- **Canvas:** existing `AppTheme.canvas` and `AppTheme.subtleSurface`.
- **Cards:** existing `AppTheme.surface`, one-pixel separator, seven-pixel corner radius.
- **Leaderboard rows:** board title, column header, and data rows all use the same 44-point height and the same `AppTheme.surface`; no gray header fill is used.
- **Vertical rhythm:** the personal-rank block and the three leaderboard blocks use 48-point section spacing to match the official page's large category breaks, while each section title remains 8 points from its cards.
- **Primary text:** existing `AppTheme.primaryText`.
- **Secondary text:** existing `AppTheme.secondaryText` and `AppTheme.tertiaryText`.
- **Usage accent:** the app's existing mint-green success color for monetary and token highlights.
- **Typography:** system text for labels and monospaced system text for ranks and numeric values.

The signature element is a compact rank rail: rank numbers form a fixed-width leading column so rows read like a live terminal scoreboard while still matching the current application shell. User, token, and spend columns remain aligned from row to row. Column labels use a readable 11-point weight rather than caption-sized text. Leaderboard avatars are omitted because they consume horizontal space without helping comparison. Top-three ranks receive only a restrained text tint; the rest of the page remains neutral.

## Formatting Rules

- Estimated spend is calculated as `quota / quota_per_unit`, using the same server status value already loaded by the app and a safe fallback of `500_000`.
- Currency uses the app's existing US-dollar formatter: two decimals normally and four decimals for sub-cent values.
- Token counts use the existing compact formatter (`12.9B`, `11.1M`, and similar).
- User display priority is `display_name`, then `username`, then `-`.
- Avatar URLs are optional. When unavailable, show a deterministic initial badge without making another request.

## Loading, Error, and Empty States

- Initial load uses stable skeleton cards that preserve the final page layout.
- Refresh keeps existing rows visible and shows a small progress indicator in the status strip.
- A failed first load shows the server error and a **重新加载** button.
- A failed refresh keeps stale data visible and shows a compact error message.
- Empty arrays render `暂无排行数据` within their corresponding section.
- A `401` uses the existing authenticated-session failure behavior; the page must not silently open a browser.

## Code Boundaries

- `LeaderboardData.swift` owns response models and display-safe helpers.
- `APIClient.swift` owns the authenticated leaderboard request.
- `AppState.swift` owns leaderboard loading, cached data, refresh state, error text, and update time because it already owns authenticated remote dashboard state.
- `LeaderboardView.swift` owns only native page composition and presentation.
- `DashboardShellView.swift` owns navigation into and out of the page.

No leaderboard view code is added to `DashboardShellView` beyond navigation and page selection.

## Testing

Automated tests must prove:

- `APIClient` requests `/api/user/leaderboard` with `New-Api-User` and decodes all used fields.
- Quota-to-USD, token compaction, display-name fallback, and missing-rank presentation are deterministic.
- Both leaderboard entry points switch to `.leaderboard` and no leaderboard action calls `NSWorkspace.open`.
- The page source contains no `24H`, `7D`, `30D`, tool, or model filter controls.
- Loading, populated, empty, and error states compile and render through the native view hierarchy.

Final verification includes the full Swift test suite, Release build, code-sign validation, installation into `/Applications/Vibe Usage.app`, and real UI clicks on both leaderboard entry points.
