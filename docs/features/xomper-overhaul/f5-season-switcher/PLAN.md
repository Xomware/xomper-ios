# Plan: F5 — Season Switcher

**Status**: Done
**Parent epic**: [../PLAN.md](../PLAN.md)
**Feature ID**: F5
**Issue**: #6
**Created**: 2026-04-28
**Last updated**: 2026-04-28
**Phase**: 2 (Week 2)
**Scope**: M (1 day for an `ios-specialist`)
**Dependencies**: F3 (tray + `MainShell` must be merged — picker lives in tray header)

## Goal

Generalize the per-view season `@State` pattern (currently duplicated in `MatchupsView` lines 71-106 and `DraftHistoryView` lines 65-84) into a single `@Observable @MainActor SeasonStore` exposed via `@Environment(\.selectedSeason)`. Three history-backed destinations (`MatchupsView`, `DraftHistoryView`, `WorldCupView`) read the env value and update in lockstep when the user changes seasons. The picker lives in `HeaderBar` (tray header) on those three destinations only — invisible elsewhere. Standings stays current-season-only (Sleeper rosters are inherently current). `MatchupHistoryView` (head-to-head) stays multi-season — it's not a season-scoped view.

## Approach

Two-part change:

1. **State**: New `SeasonStore` owns `selectedSeason: String` and a derived `availableSeasons: [String]` union of `HistoryStore.availableMatchupSeasons` and `HistoryStore.availableDraftSeasons` plus the league chain seasons (`leagueStore.leagueChain.map(\.season)`). Default = `nflStateStore.currentSeason`. Exposed via a new `EnvironmentKey`. Injected once in `MainShell` (F3) into the env at the root of the destination tree.
2. **UI**: A new `SeasonPickerBar` view — same horizontal capsule list pattern as the existing `MatchupsView.seasonButton` and `DraftHistoryView.SeasonButton`, factored into a shared component. Rendered inside `HeaderBar` *only* when the current `TrayDestination` is one of `{ .matchups, .draftHistory, .worldCup }`. The bar slots between the wordmark row and the destination's content (a second 36pt strip below the 44pt header).

Per-view changes: each consumer drops its local `@State selectedSeason` + inline picker, and instead reads `@Environment(\.selectedSeason) private var seasonStore` (full store reference, not bare String — see resolved Q3 below). `MatchupsView` keeps its `expandedWeek` reset behavior by observing season changes via `.onChange(of: seasonStore.selectedSeason)`.

`WorldCupStore` gains a non-destructive filter: keep `divisions` (full multi-season aggregation) intact for its current callers, add a derived `filteredDivisions(for season: String?) -> [WorldCupDivision]` that recomputes records using only matchups from `season` (or returns `divisions` unchanged when `season == nil` or `season == "All"`). View renders `filteredDivisions(for: seasonStore.selectedSeason)`. No re-fetch — pure recompute over already-cached `historyStore.matchupHistory`.

## Affected files

| File | Change | Why |
|------|--------|-----|
| `Xomper/Core/Stores/SeasonStore.swift` (new) | `@Observable @MainActor final class`. Owns `selectedSeason: String`, computed `availableSeasons` derived from injected sources, `select(_:)` setter, `refreshAvailable(history:chain:)`. | Single source of truth for season selection. |
| `Xomper/Core/Extensions/EnvironmentValues+Season.swift` (new) | `private struct SelectedSeasonKey: EnvironmentKey { static let defaultValue: SeasonStore? = nil }` + `EnvironmentValues.selectedSeason` accessor. | Makes the store reachable from any descendant view without prop-drilling. |
| `Xomper/Features/Shell/MainShell.swift` (F3) | Add `@State private var seasonStore = SeasonStore()`. After bootstrap, call `seasonStore.bootstrap(currentSeason: nflStateStore.currentSeason)` and re-call `seasonStore.refreshAvailable(history: historyStore, chain: leagueStore.leagueChain)` whenever those sources change. Inject via `.environment(\.selectedSeason, seasonStore)` on the destination root. Pass `seasonStore` down to `HeaderBar`. | Root-level injection so all destinations see the same store. |
| `Xomper/Features/Shell/HeaderBar.swift` (F3) | Add a 36pt sub-row below the wordmark that renders `SeasonPickerBar(seasonStore: ...)` only when `navStore.currentDestination` is in `seasonScopedDestinations`. Total header height grows from 44pt to 80pt on those destinations, stays 44pt elsewhere. | Picker must be persistent + visible across the three season-scoped destinations. |
| `Xomper/Features/Shell/SeasonPickerBar.swift` (new) | Reusable horizontal capsule list. Reads `seasonStore.availableSeasons`. Tap → `seasonStore.select(season)`. Renders nothing if `availableSeasons.count <= 1`. | Centralizes the existing `MatchupsView`/`DraftHistoryView` picker visuals. |
| `Xomper/Features/League/MatchupsView.swift` | Delete `@State private var selectedSeason: String = ""`, delete `seasonPicker` (lines 71-82) and `seasonButton(_:)` (lines 84-106). Read `@Environment(\.selectedSeason) private var seasonStore: SeasonStore?`. Use `seasonStore?.selectedSeason ?? ""` in `weeklyMatchups(forSeason:)`. Add `.onChange(of: seasonStore?.selectedSeason)` to reset `expandedWeek = historyStore.latestScoredWeek(forSeason: newValue)`. Remove default-season seeding from `loadMatchups()`. | Inline picker is replaced by header bar; selection is centralized. |
| `Xomper/Features/League/WorldCupView.swift` | Read `@Environment(\.selectedSeason) private var seasonStore: SeasonStore?`. Replace `worldCupStore.divisions` reference with `worldCupStore.filteredDivisions(for: seasonStore?.selectedSeason)`. Update `seasonsSummary` to reflect filtered scope (single season vs. all). | Filter aggregation by selected season. |
| `Xomper/Features/DraftHistory/DraftHistoryView.swift` | Delete `@State private var selectedSeason: String = ""`, delete `seasonPicker` (lines 65-84) and the private `SeasonButton` struct (lines 204-229). Read `@Environment(\.selectedSeason) private var seasonStore: SeasonStore?`. Use `seasonStore?.selectedSeason ?? ""` in `historyStore.draftPicksByRound(forSeason:)`. Remove default-season seeding from `loadDraftHistory()`. | Inline picker replaced; selection centralized. |
| `Xomper/Core/Stores/WorldCupStore.swift` | Add `func filteredDivisions(for season: String?) -> [WorldCupDivision]`. When `season == nil`, return `divisions`. Otherwise, recompute via the existing `computeStandings` algorithm with `matchups.filter { $0.season == season }`. Memoize last-result for `(matchupCount, season)` key. | Filter without losing existing aggregate. |

## New files

```
Xomper/Core/Stores/SeasonStore.swift
Xomper/Core/Extensions/EnvironmentValues+Season.swift
Xomper/Features/Shell/SeasonPickerBar.swift
```

No `Project.yml` changes — xcodegen picks up new files under `Xomper/`.

## Data flow / state

```
XomperApp
  └─ AuthGateView
       └─ ContentView
            └─ MainShell (F3)
                 ├─ @State seasonStore = SeasonStore()
                 ├─ .task → seasonStore.bootstrap(currentSeason: nflStateStore.currentSeason)
                 ├─ .onChange(historyStore.matchupHistory.count) → seasonStore.refreshAvailable(...)
                 ├─ .onChange(historyStore.draftHistory.count)   → seasonStore.refreshAvailable(...)
                 ├─ .onChange(leagueStore.leagueChain.count)     → seasonStore.refreshAvailable(...)
                 │
                 ├─ HeaderBar(seasonStore, navStore, router)
                 │    ├─ wordmark row (44pt)
                 │    └─ if isSeasonScopedDestination:
                 │         SeasonPickerBar(seasonStore)  // 36pt
                 │
                 └─ NavigationStack
                      └─ destinationRoot
                           .environment(\.selectedSeason, seasonStore)
                           ├─ MatchupsView      → reads env, uses seasonStore.selectedSeason
                           ├─ WorldCupView      → reads env, uses seasonStore.selectedSeason
                           ├─ DraftHistoryView  → reads env, uses seasonStore.selectedSeason
                           ├─ MatchupHistoryView → ignores env (multi-season H2H)
                           └─ StandingsView     → ignores env (current-season-only)
```

State ownership:
- **`SeasonStore`** (single instance owned by `MainShell`): authoritative `selectedSeason`. All consumers either read via env (views) or take it as a method arg (stores like `WorldCupStore.filteredDivisions(for:)`).
- **`HistoryStore` / `LeagueStore`**: unchanged. Continue to expose raw data; `SeasonStore` derives `availableSeasons` from them.
- **No store-to-store injection**: `WorldCupStore` does NOT receive `SeasonStore`. View passes the season as a method arg. Keeps stores decoupled (epic risk-mitigation note).

## Implementation steps

Each step independently buildable.

1. **Create `SeasonStore.swift`.** `@Observable @MainActor final class SeasonStore`. Properties: `private(set) var selectedSeason: String = ""`, `private(set) var availableSeasons: [String] = []`. Methods:
   - `func bootstrap(currentSeason: String)` — sets `selectedSeason = currentSeason` if currently empty.
   - `func refreshAvailable(matchupSeasons: [String], draftSeasons: [String], chainSeasons: [String], currentSeason: String)` — union, dedupe, sort descending by Int. If `selectedSeason` not in result, fall back to `currentSeason` if present, else first element.
   - `func select(_ season: String)` — guards membership in `availableSeasons`, sets `selectedSeason`.
2. **Create `EnvironmentValues+Season.swift`.** Standard `EnvironmentKey` pattern. Default value `nil` (optional `SeasonStore?`).
3. **Create `SeasonPickerBar.swift`.** Horizontal `ScrollView(.horizontal, showsIndicators: false)` of capsule buttons. Visual contract identical to existing `MatchupsView.seasonButton` (reuse colors/spacing). Renders nothing when `availableSeasons.count <= 1`. Selected button: `XomperColors.championGold` bg, `.deepNavy` text, `.semibold`. Unselected: `XomperColors.surfaceLight` bg, `.textSecondary` text, `.regular`. Haptic `.light` on tap. Wraps in `withAnimation(XomperTheme.defaultAnimation)`.
4. **Wire `SeasonStore` into `MainShell`.** Add `@State private var seasonStore = SeasonStore()`. In existing bootstrap `.task`, after `nflStateStore.fetchState()` resolves, call `seasonStore.bootstrap(currentSeason: nflStateStore.currentSeason)`. Add four `.onChange` modifiers on the destination root for `historyStore.matchupHistory.count`, `historyStore.draftHistory.count`, `leagueStore.leagueChain.count`, `nflStateStore.currentSeason` — each calls `seasonStore.refreshAvailable(...)` with the latest data.
5. **Inject env on destination root.** In `MainShell`'s `NavigationStack { destinationRoot(...) }`, attach `.environment(\.selectedSeason, seasonStore)` on `destinationRoot`. Verify the env value flows into pushed views via the standard SwiftUI propagation.
6. **Extend `HeaderBar` to render `SeasonPickerBar`.** Add `var seasonStore: SeasonStore` parameter. Add `private static let seasonScopedDestinations: Set<TrayDestination> = [.matchups, .draftHistory, .worldCup]`. Body becomes `VStack(spacing: 0) { wordmarkRow; if seasonScopedDestinations.contains(navStore.currentDestination) { SeasonPickerBar(seasonStore: seasonStore).frame(height: 36).padding(.horizontal, XomperTheme.Spacing.sm).background(XomperColors.bgDark) } }`. No `.animation` on the conditional — appearance is per-destination, not animated.
7. **Refactor `MatchupsView`.**
   - Delete `@State private var selectedSeason: String = ""` (line 9).
   - Delete `seasonPicker` and `seasonButton(_:)` (lines 70-106).
   - Remove `seasonPicker` from `matchupsContent`'s `VStack`.
   - Add `@Environment(\.selectedSeason) private var seasonStore: SeasonStore?` near top.
   - Replace `historyStore.weeklyMatchups(forSeason: selectedSeason)` with `historyStore.weeklyMatchups(forSeason: seasonStore?.selectedSeason ?? "")`.
   - Add `.onChange(of: seasonStore?.selectedSeason) { _, newSeason in withAnimation(XomperTheme.defaultAnimation) { expandedWeek = historyStore.latestScoredWeek(forSeason: newSeason ?? "") } }` on `matchupsContent`.
   - In `loadMatchups()`, delete the trailing default-season seeding block (lines 203-207). Replace with: after `historyStore.loadMatchupHistory(...)` returns, call `seasonStore?.refreshAvailable(...)` (forwarding latest data) and seed `expandedWeek = historyStore.latestScoredWeek(forSeason: seasonStore?.selectedSeason ?? "")` on first load only.
8. **Refactor `DraftHistoryView`.**
   - Delete `@State private var selectedSeason: String = ""` (line 9).
   - Delete `seasonPicker` (lines 65-84) and the private `SeasonButton` struct (lines 204-229).
   - Remove `seasonPicker` call from `draftContent`'s `VStack`.
   - Add `@Environment(\.selectedSeason) private var seasonStore: SeasonStore?`.
   - Replace `historyStore.draftPicksByRound(forSeason: selectedSeason)` in `filteredRounds` with the env value.
   - In `loadDraftHistory()`, delete the trailing default-season seeding block (lines 156-158). Call `seasonStore?.refreshAvailable(...)` after history loads.
9. **Add `WorldCupStore.filteredDivisions(for:)`.**
   ```swift
   func filteredDivisions(for season: String?) -> [WorldCupDivision] {
       guard let season, !season.isEmpty else { return divisions }
       guard let cachedChain = lastChain else { return divisions }
       let filtered = lastMatchups.filter { $0.season == season }
       return (try? computeStandings(chain: cachedChain, matchups: filtered)) ?? []
   }
   ```
   - Cache `lastChain: [League]?` and `lastMatchups: [MatchupHistoryRecord]` inside `loadStandings(chain:matchups:)` so the filter can recompute without re-fetching.
   - Memoize last filter result keyed by `(season, lastMatchups.count)`.
10. **Refactor `WorldCupView`.**
    - Add `@Environment(\.selectedSeason) private var seasonStore: SeasonStore?`.
    - Replace `worldCupStore.divisions` reference at line 81 with a computed `private var displayedDivisions: [WorldCupDivision] { worldCupStore.filteredDivisions(for: seasonStore?.selectedSeason) }`.
    - Update `seasonsSummary` (line 70-75): when `seasonStore?.selectedSeason` is set and matches one of `worldCupStore.seasons`, show `"Divisional records for \(season)"`. When unset (or "All"), keep current multi-season string.
    - Header `Text("Top 2 per division qualify · \(ClinchCalculator.defaultGamesRemaining) games remaining")` stays unchanged.
11. **Verify `MatchupHistoryView` is untouched.** It is H2H between two specific users across all seasons — explicitly NOT season-scoped. Confirm no env subscription added.
12. **Verify `StandingsView` is untouched.** Sleeper rosters are current-season-only. Confirm no env subscription. The `seasonScopedDestinations` set in `HeaderBar` excludes `.standings`, so the picker is invisible there.
13. **Run `xcodegen generate`** then build for `iPhone 17 Pro`. Resolve any Swift 6 strict-concurrency warnings (expect none — all touched stores already `@MainActor`).
14. **Simulator validation pass.** See Test plan below.
15. **Mark plan Done** after build + sim validation pass.

## Picker UI spec

**Placement**: Tray header (`HeaderBar`), as a 36pt strip below the 44pt wordmark/avatar/search row. Visible only when `navStore.currentDestination ∈ { .matchups, .draftHistory, .worldCup }`.

**Why header-bar (not per-view toolbar, not nav-title pull-down)**:
- Per-view toolbar means re-implementing in three views with three slightly-different `@State` integrations — defeats the unification goal.
- Nav-title pull-down (`Menu` in `.navigationTitle` toolbar) is fine for occasional use but hides the active season behind a tap; we want it always visible since season context is non-obvious.
- Header bar already exists from F3, gets one extra row, costs no per-view duplication.

**Visual** (matches existing `MatchupsView.seasonButton`):
- Height: 36pt strip, padded `.horizontal Spacing.sm` (8pt).
- Background: `XomperColors.bgDark` (continuous with header).
- Capsule button: `padding(.horizontal Spacing.md, .vertical Spacing.sm)`, `frame(minHeight: 36)`.
- Selected: bg `XomperColors.championGold`, fg `XomperColors.deepNavy`, weight `.semibold`.
- Unselected: bg `XomperColors.surfaceLight`, fg `XomperColors.textSecondary`, weight `.regular`.
- Spacing between capsules: `XomperTheme.Spacing.sm`.
- Horizontal scroll, no scroll indicators.
- Haptic `.light` on selection.
- Animation: `withAnimation(XomperTheme.defaultAnimation)`.

**Hidden-state behavior**: When `availableSeasons.count <= 1`, `SeasonPickerBar` returns `EmptyView()`. The 36pt strip in `HeaderBar` collapses (HeaderBar conditional renders the row only when seasons > 1 AND destination is season-scoped).

**Accessibility**:
- Each capsule: `.accessibilityLabel("Season \(season)")`, `.accessibilityAddTraits(isSelected ? .isSelected : [])`.
- Strip exposes as a list (`.accessibilityElement(children: .contain)`).

## Resolved open questions

1. **Picker UI location** → **Tray header (`HeaderBar`), 36pt sub-row.** Single source of truth, no per-view duplication, always visible. Per-view toolbar and nav-title pull-down rejected (see UI spec rationale).
2. **`SeasonStore` location and inject point** → **`Xomper/Core/Stores/SeasonStore.swift`, instantiated in `MainShell`** (the F3 root shell), injected via `.environment(\.selectedSeason, seasonStore)` on the destination root. NOT `XomperApp` — `MainShell` owns it because that's where bootstrap lives and where the destination tree begins.
3. **Env-key (just String) vs. full store injection** → **Full `SeasonStore?` reference in env.** A bare String would require views to call back into something to mutate it; passing the store keeps the picker callable from anywhere (including future destinations) and matches the F3 pattern of passing observable stores in env. `Optional` type lets previews/tests skip injection.
4. **`WorldCupStore` filter behavior** → **Recompute filtered aggregates on demand via `filteredDivisions(for:)`, do not mutate `divisions`.** Keeps existing callers (currently none external, but futureproof) unaffected. View pulls filtered result. Memoized to avoid recompute on scroll.
5. **`MatchupsView` inline picker** → **Delete entirely.** Replaced by header-bar picker. No fallback (avoids dual sources of truth).
6. **Default `selectedSeason` source** → **`nflStateStore.currentSeason`.** Falls back to `String(Calendar.current.component(.year, from: Date()))` via `NflStateStore`'s existing fallback. If `currentSeason` is not in `availableSeasons` (e.g., chain hasn't loaded yet), `refreshAvailable` picks the first available season instead.
7. **`MatchupsView.expandedWeek` reset** → **Preserved.** Implemented via `.onChange(of: seasonStore?.selectedSeason)` that recomputes `expandedWeek = historyStore.latestScoredWeek(forSeason:)`. Identical UX to the inline picker today.
8. **Standings exclusion** → **Confirmed.** Sleeper rosters are current-only; there is no historical roster API path. `StandingsView` does not subscribe to env. Picker hidden via `seasonScopedDestinations` exclusion.

## Acceptance criteria

- A new `SeasonStore` lives at `Xomper/Core/Stores/SeasonStore.swift`, `@Observable @MainActor`, injected into env at `MainShell`'s destination root.
- `seasonStore.availableSeasons` is the descending-sorted union of `historyStore.availableMatchupSeasons`, `historyStore.availableDraftSeasons`, and `leagueStore.leagueChain.map(\.season)`. Refreshes whenever any source changes.
- Default `selectedSeason` on cold open = `nflStateStore.currentSeason`. If unavailable, first element of `availableSeasons`.
- Header-bar picker visible only on `.matchups`, `.draftHistory`, `.worldCup` destinations. Hidden on Standings, Profile, Settings, etc.
- Picker hidden when `availableSeasons.count <= 1`.
- Tapping a season in the header picker:
  - Updates `MatchupsView` weeks list immediately.
  - Updates `MatchupsView.expandedWeek` to `historyStore.latestScoredWeek(forSeason: newSeason)`.
  - Updates `DraftHistoryView` rounds list immediately.
  - Updates `WorldCupView` divisions to filtered aggregates.
- `MatchupsView` no longer contains `seasonPicker` / `seasonButton(_:)` / `@State selectedSeason`.
- `DraftHistoryView` no longer contains `seasonPicker` / private `SeasonButton` struct / `@State selectedSeason`.
- `WorldCupStore.divisions` is unchanged for callers; new `filteredDivisions(for:)` returns the season-filtered recompute.
- `StandingsView` is untouched and continues to render current-season Sleeper data.
- `MatchupHistoryView` (H2H) is untouched and continues to span all seasons.
- Build clean with Swift 6 strict concurrency on iPhone 17 Pro simulator. No new warnings.
- Always-dark mode, Midnight Emerald palette, Dynamic Type — no hardcoded colors or font sizes.

## Test plan

Simulator-first per project rule.

**Build validation**:
```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme Xomper -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
Must compile clean with Swift 6 strict concurrency.

**Functional simulator pass (`iPhone 17 Pro`)**:
1. Cold launch → lands on Standings. **Header picker NOT visible.**
2. Open tray → tap **Matchups**. Header picker appears with seasons (e.g., `2026 2025 2024 2023`). Current season selected by default (`championGold` capsule).
3. Tap `2024` capsule. Capsule selection animates. `MatchupsView` weeks list refreshes to 2024 matchups. `expandedWeek` jumps to latest scored week of 2024.
4. Open tray → tap **Draft History**. Header picker still shows, **same selection (`2024`) persists**. Draft rounds list shows 2024 picks.
5. Tap `2023` in picker. Draft rounds refresh to 2023.
6. Open tray → tap **World Cup**. Picker still visible, `2023` still selected. Standings show 2023-only divisional records (filtered aggregate, not all-time). Header subtitle reads `"Divisional records for 2023"`.
7. Tap current season in picker. All three views (Matchups / Draft / World Cup) reflect current season on revisit.
8. Open tray → tap **Standings**. **Header picker hidden.** StandingsView shows current-season Sleeper data.
9. Open tray → tap **Profile**. Header picker hidden.
10. Open tray → return to Matchups. Picker reappears with previously-selected season intact.
11. Pull to refresh on Matchups → `historyStore.reset()` runs → `availableSeasons` recomputes; previous selection preserved if still available, else falls back to current season.
12. Sign out → re-login → cold open → lands on Standings, picker not visible. Default season re-seeded to current.

**Cross-cutting**:
- Dynamic Type AX5 → picker capsules wrap horizontally without truncating; horizontal scroll works.
- VoiceOver on picker: "Season 2024, selected, button" / "Season 2023, button".
- Edge-drag still opens drawer over the season picker bar (gesture priority unchanged from F3).

**Regression checks**:
- `MatchupsView` week expansion still toggles on tap.
- `DraftHistoryView` filter toggle (All / My Picks) still works.
- `WorldCupView` clinch states still render correctly for the selected season's filtered records.
- `MatchupHistoryView` (H2H) still spans all seasons (open from a profile context, verify it shows multi-year record).

## Risks & mitigations

- **Risk: `WorldCupStore.filteredDivisions` recomputes on every scroll tick.** Mitigated by memoizing keyed on `(season, lastMatchups.count)`. Recompute is O(matchups) over a single-season subset — fast even unmemoized for 12 teams × 14 weeks × 4 seasons. If profiling shows hot path, escalate to invalidation-only-on-source-change.
- **Risk: `availableSeasons` flickers during bootstrap.** First the chain loads (1 season), then matchup history loads (4 seasons). Picker would briefly hide then show. Mitigated by `refreshAvailable` only running once both `historyStore.matchupHistory` and `leagueStore.leagueChain` are non-empty (guard inside the method, or `.onChange` of both counts).
- **Risk: Selected season disappears after refresh** (e.g., user pulled-to-refresh and `historyStore.reset()` cleared `availableSeasons` momentarily). Mitigated by `refreshAvailable` preserving `selectedSeason` if still in the new set; otherwise falling back to `currentSeason`.
- **Risk: Header bar height growth (44pt → 80pt) causes layout jank when navigating between season-scoped and non-season-scoped destinations.** Mitigated by NOT animating the conditional row — appearance/disappearance is instant, matching destination switch.
- **Risk: Optional `SeasonStore?` in env makes every consumer write `seasonStore?.selectedSeason ?? ""` — easy to forget the empty-string fallback and crash on lookup.** Mitigated by all `historyStore` season-filter methods returning empty arrays for empty/unknown seasons (already true today). Worst case is "no data shown until env hooks up" — not a crash.
- **Risk: F3 isn't merged when F5 starts.** Hard dependency. Confirm F3 status in `../f3-tray-shell/PLAN.md` before opening F5 branch.
- **Risk: `WorldCupStore.computeStandings` is private.** Step 9 either makes it `fileprivate` to allow `filteredDivisions` to call it, OR keeps it private and inlines the filter inside `computeStandings(chain:matchups:)` — both fine. Pick the smaller diff at execution time.

## Out of scope

- **Standings season switcher.** Sleeper rosters are current-only. No historical-roster path on Sleeper. Not in this epic, not ever (until Sleeper exposes one).
- **`MatchupHistoryView` (H2H) season filter.** Multi-season is the point of H2H; filtering it would gut the feature.
- **"All seasons" virtual option in picker** (e.g., World Cup all-time view as a picker entry). Today's `WorldCupView` default is all-time when `selectedSeason` is unset; we just preserve that. Not adding an explicit "All" capsule.
- **Persisting `selectedSeason` across app launches.** Resets to current season on cold launch — matches existing behavior.
- **Per-week picker.** Out of scope; weeks come from `expandedWeek` UX in `MatchupsView`.
- **Season picker in deep-pushed views** (e.g., `MatchupDetailView` sheet, `TeamView`). They inherit env but don't render the picker — picker stays in `HeaderBar`.
- **Refactoring `DraftHistoryView`'s private `SeasonButton`/`FilterButton` into a shared component beyond `SeasonPickerBar`.** `FilterButton` (All / My Picks) stays as-is.
- **Backend changes.** None.
- **`HistoryStore` API changes.** Existing `weeklyMatchups(forSeason:)`, `draftPicksByRound(forSeason:)`, `availableMatchupSeasons`, `availableDraftSeasons` are sufficient.
- **Animated transitions between season picker rows.** No fade/slide on appearance — keep it instant.

## Skills / Agents to use

- **`ios-specialist`** — primary executor. SwiftUI, `@Observable`, `EnvironmentKey`, Swift 6 strict concurrency, `@MainActor`. Expected duration: 1 day.

## Notes for the executor

- Build incrementally. After step 6 you should have a header picker that updates `seasonStore.selectedSeason` but no consumer reads it yet — verify the picker visually in the simulator before touching consumer views.
- Steps 7, 8, 10 are independent — pick whichever order is most convenient. Each is a clean swap of `@State selectedSeason` for env read.
- Step 9 (`WorldCupStore.filteredDivisions`) is the only non-trivial logic change. Keep `computeStandings` pure; pass filtered matchups in. Memoize at the `filteredDivisions` boundary, not inside `computeStandings`.
- Run `xcodegen generate` once at the start; new files auto-pick up.
- For this autonomous run, single squashed commit at the end is acceptable.
