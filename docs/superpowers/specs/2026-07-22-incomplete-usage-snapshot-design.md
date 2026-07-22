# Incomplete Usage Snapshot Design

## Problem

`GET /api/desktop/usage` intentionally returns an empty payload with
`coverage.complete = false` when the Redis snapshot or historical archive is
warming or unavailable. The desktop currently treats every successful HTTP
response as authoritative, replaces a previously valid snapshot, and renders
`当前账号在这个时间范围内没有使用记录`.

## Decision

Coverage completeness controls whether a response is authoritative:

- `coverage == nil`: accept for compatibility with older servers.
- `coverage.complete == true`: accept, including a genuinely empty range.
- `coverage.complete == false` with usage content: accept it. The hot snapshot
  advances every 30 seconds, so a normal populated response can trail the
  request end by a few seconds without being an unavailable snapshot.
- `coverage.complete == false` with no buckets, sessions, recent requests, or
  `hasAnyData`: do not cache or present the response.

When an incomplete response arrives after a trusted snapshot, keep the trusted
snapshot visible and show a quiet status message that the latest statistics are
still being prepared. When no trusted snapshot exists, render a dedicated
`数据准备中` state instead of claiming the account has no records.

## Refresh and load behavior

- An incomplete empty response does not advance `lastSyncTime` and is not
  recorded as a successful snapshot.
- Automatic refresh records the last request attempt per target, so reopening
  the window or returning to the dashboard cannot retry a rejected snapshot
  inside 60 seconds. Manual refresh keeps its existing cooldown and range
  selection keeps its immediate load behavior. No retry loop or timer is added.
- If a newly selected range has no complete cache, the selector returns to the
  last presented range rather than showing mismatched or partial charts.
- A later complete response clears the preparing state and replaces the view.

## UI states

1. Complete response with data: normal dashboard.
2. Complete response without data: existing `暂无数据` state.
3. Incomplete empty response with trusted data: keep dashboard, status banner says
   `统计数据准备中，已保留上次结果`.
4. Incomplete empty response without trusted data: show `数据准备中` with a
   manual refresh action.

## Tests

- An incomplete response cannot replace a complete snapshot.
- An initial incomplete response does not set `lastSyncTime` and enters the
  preparing state.
- A range change without a complete snapshot returns to the last loaded range.
- A complete empty response remains a truthful empty state.
- A populated response remains displayable when its coverage end trails the
  requested current time.
- Existing refresh cooldown and server-load protections remain intact.
- Window visibility and page-target restarts cannot bypass the automatic
  60-second request gate after an incomplete response.
- Signing out clears synchronization labels and refresh cooldowns so another
  account cannot inherit stale status or rate-limit state.
- Session and request generations reject a response or error that returns after
  logout or account replacement. A late success cannot populate the new
  account's cache, and a late authorization error cannot log out the new
  account or change its loading state.
- Presentation derives the effective data-presence flag from both `hasAnyData`
  and the returned collections, preventing an inconsistent server boolean from
  hiding populated buckets.
