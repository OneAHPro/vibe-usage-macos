# Leaderboard Total Top 20 Implementation Plan

**Goal:** Render non-duplicated spend rankings in two continuation columns: today top 10, yesterday top 20, and total top 20.

**Architecture:** The authenticated Go endpoint remains the single source of truth. Daily spend expands to 10 rows and total spend remains capped at 20. The macOS client splits each spend list into two segments while carrying a rank offset into the common white, fixed-height table.

**Tech Stack:** Go, Gin, GORM, XCTest-style Swift Testing, SwiftUI.

### Task 1: Prove and change the API limit

- Extend `controller/leaderboard_test.go` with 21 ranked users and assert that `token_total_top` and `quota_total_top` each return 20 ordered rows.
- Run the focused test and confirm the existing 3-row limit fails it.
- Replace the total leaderboard limit in `model/leaderboard.go` with 20 and use it for both total queries.
- Update the six-user regression expectation and rerun all leaderboard model/controller tests.

### Task 2: Split the native spend rankings

- Add a model test proving that ten rows split into ranks 1–5 and 6–10 with a continuation offset.
- Add source assertions for today 5/5, yesterday 10/10, total 10/10, and the absence of independent token cards.
- Add the reusable split helper and pass its rank offset into `LeaderboardBoardCard`.
- Increase the server's daily quota leaderboard limit from 5 to 10 and cover it with an 11-user endpoint test.

### Task 3: Verify and deliver

- Run the full Swift test suite and relevant Go test packages.
- Build the release app, install it safely, launch it, and inspect the real leaderboard screen.
- Commit and push the isolated backend branch and the existing macOS feature branch.
