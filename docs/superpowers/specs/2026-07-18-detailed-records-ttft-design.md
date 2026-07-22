# Detailed Records TTFT Design

**Date:** 2026-07-18
**Status:** Approved for planning
**Scope:** Vibe Usage macOS client and the private new-system desktop usage response contract

## Goal

Replace the dashboard's hourly aggregate "detailed records" with a bounded list of real requests so every row can show the request's true time to first token (TTFT). Remove the terminal and tool columns while preserving token and cost information.

The feature must not add endpoint calls, polling, raw-log pagination, or database scans.

## Confirmed UI

The table columns are:

1. 日期
2. 模型
3. 首字
4. 输入 TOKEN
5. 输出 TOKEN
6. 缓存 TOKEN
7. 预估费用

TTFT is formatted to one decimal place in seconds. Missing or invalid values display `—`.

The colors match the existing new-system usage-log rules:

- below 3 seconds: green;
- 3 seconds through below 10 seconds: light red/orange;
- 10 seconds and above: deep red.

The TTFT value is rendered as a compact rounded badge. No total-duration or streaming-status badge is added.

## Backend Contract

Extend the existing `GET /api/desktop/usage` response with an optional `recentRequests` array. The client must not call a new endpoint for these records.

Each item contains:

```json
{
  "id": 123456,
  "createdAt": "2026-07-18T10:30:00+08:00",
  "source": "new-api",
  "model": "gpt-5.6-sol",
  "project": "default",
  "inputTokens": 100,
  "outputTokens": 50,
  "cachedInputTokens": 20,
  "reasoningOutputTokens": 0,
  "totalTokens": 170,
  "estimatedCost": 0.002,
  "firstResponseTimeMs": 2400
}
```

The backend builds this list from the existing Redis/in-memory `usageAnalyticsState.RecentByUser` snapshot. It must not query or page through the logs table when serving the request.

The snapshot already retains `LogID`, `CreatedAt`, `TokenName`, `ModelName`, `GroupName`, prompt/cache counts, and `FirstMs`. Its incremental log-consumer should retain the remaining completion, quota, and normalized token fields at write-processing time. The endpoint reads at most the newest 50 matching samples, filters them to the requested time range, sorts them by log ID descending, and returns an empty array while the snapshot is unavailable or warming.

No sensitive request body, response body, token key, IP address, channel credentials, or raw `other` JSON is included.

## Client Compatibility

`recentRequests` is optional when decoding so the app remains compatible during a staggered backend rollout.

- When the field exists, detailed rows come from real request records.
- When the field is absent, the existing aggregate rows remain visible with TTFT shown as `—`.
- The client never derives TTFT from the request date, bucket time, total duration, token count, or any other unrelated value.

Existing source, model, and project filters apply to request rows. The removed hostname filter does not affect the table because terminal information is intentionally no longer displayed.

## Load Safety

- The app continues to make one `/api/desktop/usage` request per eligible visible refresh.
- No additional request is made for detailed records.
- No code path calls `/api/log/self` as a fallback.
- The response contains at most 50 recent requests.
- Backend reads are snapshot lookups with bounded in-memory work.
- Hidden-window, freshness, cooldown, and single-flight behavior remains unchanged.

## Client Code Boundaries

- `UsageBucket.swift`: add the optional recent-request response model and response property.
- `DashboardData.swift`: build `UsageRecordRow` from request records, with aggregate fallback during rollout.
- `UsageRecordsView.swift`: remove terminal/tool columns and render the TTFT badge.
- `DashboardLayout.swift`: rebalance the seven remaining columns and reduce unnecessary horizontal overflow.
- Tests: cover decoding, TTFT formatting/color classification, row mapping, fallback behavior, and layout width allocation.

## Testing

Client tests must prove:

- responses without `recentRequests` still decode;
- real request rows preserve date, model, token, cost, and TTFT data;
- invalid or missing TTFT displays `—`;
- TTFT values at 2.9, 3.0, 9.9, and 10.0 seconds select the expected color tier;
- terminal and tool data are absent from the displayed row model;
- the detailed table has exactly seven columns;
- no request behavior or visible-refresh cadence changes.

Backend tests should prove:

- records come from the published analytics snapshot without a database fallback;
- at most 50 records are returned in descending request order;
- requested date bounds and user isolation are enforced;
- `firstResponseTimeMs` maps from `other.frt` exactly;
- token and cost fields match the incrementally processed log record;
- snapshot warming or unavailability returns an empty bounded list without scanning logs;
- the existing bucket/session response remains compatible.

Final client verification includes the full Swift test suite, Release build, installation into `/Applications/Vibe Usage.app`, and a visual check of the table in light and dark appearances.

## Rejected Alternatives

### Hourly average TTFT

An average or maximum attached to an aggregate bucket is not the TTFT of a specific request and would mislabel the data.

### Separate log endpoint request

Calling `/api/log/self` would add traffic and database work, violate the low-load requirement, and reintroduce the failure mode the snapshot architecture was created to remove.

### Client-side estimation

TTFT cannot be reconstructed from timestamps, total request duration, or token counts. Fabricated values are not acceptable.

## Acceptance Criteria

- The UI contains no terminal or tool column.
- Every real request with a valid TTFT shows the correct seconds and color tier.
- The app makes no additional request compared with the current dashboard refresh flow.
- Backend serving the detail list performs no live log-table scan.
- Older backend responses remain usable without crashes or decoding failures.
