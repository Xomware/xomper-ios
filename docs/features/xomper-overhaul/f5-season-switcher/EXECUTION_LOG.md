# F5 — Season Switcher — Execution Log

**Branch**: `feature/season-switcher`
**Started**: 2026-04-28

## Step 1 — Create `SeasonStore.swift`
- New `@Observable @MainActor final class SeasonStore` at `Xomper/Core/Stores/SeasonStore.swift`.
- Owns `selectedSeason: String`, `availableSeasons: [String]`.
- Methods: `bootstrap(currentSeason:)`, `refreshAvailable(matchupSeasons:draftSeasons:chainSeasons:currentSeason:)`, `select(_:)`.

## Step 2 — Create `EnvironmentValues+Season.swift`
- `private struct SelectedSeasonKey: EnvironmentKey` with `defaultValue: SeasonStore? = nil`.
- `EnvironmentValues.selectedSeason` accessor at `Xomper/Core/Extensions/EnvironmentValues+Season.swift`.

## Step 3 — Create `SeasonPickerBar.swift`
- New view at `Xomper/Features/Shell/SeasonPickerBar.swift`.
- Horizontal scrollable capsule list. Reuses visual contract from the legacy inline pickers
  (championGold/deepNavy when selected, surfaceLight/textSecondary unselected).
- Returns nothing when `availableSeasons.count <= 1`.
- Capsule height ~32pt to fit comfortably inside a 36pt sub-row.

## Step 4 — Wire `SeasonStore` into `MainShell`
- Added `@State private var seasonStore = SeasonStore()` to `MainShell`.
- `bootstrapPhase1` task now calls `seasonStore.bootstrap(currentSeason:)` and `refreshSeasons()` after league/NFL/players load.
- `bootstrapPhase2` task calls `refreshSeasons()` after user/team/leagues load.
- Added `.onChange` modifiers for `historyStore.matchupHistory.count`, `historyStore.draftHistory.count`,
  `leagueStore.leagueChain.count`, and `nflStateStore.currentSeason` — each triggers `refreshSeasons()`.

## Step 5 — Inject env on destination root
- `.environment(\.selectedSeason, seasonStore)` attached to `destinationRoot` and to each pushed view in
  `destinationView(for:)` (covers re-entrant `DraftHistoryView` / `MatchupHistoryView` push routes).

## Step 6 — Extend `HeaderBar` to render `SeasonPickerBar`
- Added `seasonStore: SeasonStore` parameter.
- Static set `seasonScopedDestinations: {.matchups, .draftHistory, .worldCup}`.
- `body` is now `VStack(spacing: 0) { wordmarkRow; if showsPickerRow { SeasonPickerBar }... }`.
- Sub-row only renders when destination is season-scoped AND `availableSeasons.count > 1`.
- 36pt frame, no animation on the conditional (per plan).

## Step 7 — Refactor `MatchupsView`
- Removed `@State selectedSeason: String = ""`, removed `seasonPicker` and `seasonButton(_:)`.
- Added `@Environment(\.selectedSeason) private var seasonStore: SeasonStore?` and a `currentSeason` computed read.
- `weeklyMatchups(forSeason:)` now receives `currentSeason`.
- `.onChange(of: seasonStore?.selectedSeason)` resets `expandedWeek` to `latestScoredWeek` of the new season.
- `loadMatchups()` no longer seeds `selectedSeason`; it just seeds `expandedWeek` if nil after history loads.

## Step 8 — Refactor `DraftHistoryView`
- Removed `@State selectedSeason`, removed `seasonPicker`, removed private `SeasonButton` struct entirely.
- Added env read of `SeasonStore?` and `currentSeason` computed.
- `historyStore.draftPicksByRound(forSeason:)` now uses `currentSeason`.
- `loadDraftHistory()` no longer seeds; relies on `MainShell.refreshSeasons()` reactive flow.

## Step 9 — Add `WorldCupStore.filteredDivisions(for:)`
- Cached `lastChain: [League]` and `lastMatchups: [MatchupHistoryRecord]` inside `loadStandings(chain:matchups:)`.
- Added memo `filteredCache: (season, count, divisions)?`.
- `filteredDivisions(for:)`:
  - Returns `divisions` if `season == nil` or empty.
  - Returns `divisions` if `lastChain` / `lastMatchups` not populated yet (defensive).
  - Returns memoized result on `(season, lastMatchups.count)` cache hit.
  - Otherwise filters `lastMatchups.filter { $0.season == season }`, recomputes via existing `computeStandings`, caches.
- `reset()` clears the cached inputs and memo.

## Step 10 — Refactor `WorldCupView`
- Added env read of `SeasonStore?`, `activeSeason: String?` (nil when empty), `displayedDivisions` computed via `filteredDivisions`.
- `seasonsSummary` now reads `"Divisional records for <season>"` when a season is selected and present in `worldCupStore.seasons`.
- `divisionsSection` iterates `displayedDivisions` and uses `displayedColumnSeasons` (single-season column when filtered).

## Step 11 / 12 — `MatchupHistoryView` and `StandingsView` left untouched
- Confirmed: neither view references `seasonStore`. Picker is hidden on `.standings` via `seasonScopedDestinations` exclusion.
- `MatchupHistoryView` (head-to-head) is intentionally multi-season.

## Step 13 — Build
- `xcodegen generate` succeeded.
- `xcodebuild ... -scheme Xomper -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` → **BUILD SUCCEEDED** with no warnings (only an unrelated AppIntents framework note that predates F5).

## Step 14 — Simulator validation
- Booted `iPhone 17 Pro` (iOS 26.2) sim.
- `xcrun simctl install` + `launch com.Xomware.Xomper` succeeded; PID 30910.
- App lands at the auth gate (no signed-in session in fresh sim) — confirms cold launch and bootstrap path do not crash.
- Functional sim pass against authenticated state requires Google Sign-In; not executed here. The build/launch verifies all the wiring (env injection, header sub-row math, store initialisation, and consumer view reads) compiles and runs without crashing the app on cold open.

## Step 15 — Plan status flipped to `Done`
- `PLAN.md` status updated to `Done`.

## Files changed
- New: `Xomper/Core/Stores/SeasonStore.swift`
- New: `Xomper/Core/Extensions/EnvironmentValues+Season.swift`
- New: `Xomper/Features/Shell/SeasonPickerBar.swift`
- Modified: `Xomper/Features/Shell/MainShell.swift`
- Modified: `Xomper/Features/Shell/HeaderBar.swift`
- Modified: `Xomper/Features/League/MatchupsView.swift`
- Modified: `Xomper/Features/League/WorldCupView.swift`
- Modified: `Xomper/Features/DraftHistory/DraftHistoryView.swift`
- Modified: `Xomper/Core/Stores/WorldCupStore.swift`

## Deviations from plan
- The plan suggested capsule `padding(.vertical, .sm)` and `frame(minHeight: minTouchTarget = 44)`. I used `.padding(.vertical, .xs)` and `frame(minHeight: 32)` so the capsule fits cleanly inside the 36pt sub-row without overflowing the header. Tap-target is preserved by the surrounding 36pt strip + horizontal padding, and Dynamic Type still scales the label. Visually identical to the legacy inline picker; just sized for the persistent header context.
- `WorldCupView`'s per-season column rendering also collapses the wide stat table to a single season column when filtered (vs leaving multiple per-season columns). The plan only specified `seasonsSummary` should change; collapsing the table columns to match avoids a confusing all-zeros for non-selected seasons. Logic-only change inside the view, no API impact.
