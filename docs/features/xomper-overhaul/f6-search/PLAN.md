# Plan: F6 — Search Extension (Player Mode + Grouped Results)

**Status**: Done
**Parent epic**: [../PLAN.md](../PLAN.md)
**Feature ID**: F6
**Issue**: #2
**Created**: 2026-04-28
**Last updated**: 2026-04-28
**Phase**: 3 (Week 2-3)
**Scope**: M
**Dependencies**: F2 (player wiring — `PlayerStore.players` populated reliably; PR #23 in flight), F3 (tray-header magnifying-glass already wired to `.search` route in `HeaderBar`), F5 (soft — none required for v1)

## Goal

Extend the existing `SearchView` (Sleeper users + leagues, debounced) to add a **Player** mode backed by `PlayerStore.search`, extract the view-local search logic into a new `@Observable @MainActor SearchStore`, and render results as **grouped sections** (Users / Leagues / Players) with per-mode tap-through. Verify F3's tray-header search icon pushes `.search` and closes the drawer; do not re-wire it here.

Success: typing "jefferson" in player mode renders a Players section with player rows (avatar + name + position + team), tapping a row pushes `PlayerDetailView`, and existing user/league behavior is byte-identical to today.

## Approach

Three moves, in order:

1. **Lift state** out of `SearchView` into a new `SearchStore` `@Observable @MainActor`. Same fields (`query`, `mode`, `debouncedText`, `isSearching`, `errorMessage`, `hasSearched`) plus typed `results: SearchResults` (struct holding optional user/league + `[Player]` array). Debounce identical (500ms `Task.sleep`, cancellable). View becomes a thin observer.
2. **Add `.player` mode** to `SearchMode` enum. `SearchStore.performSearch()` switches on mode: user → `apiClient.fetchUser`, league → `apiClient.fetchLeague`, player → `playerStore.search(query:limit:)` (synchronous in-memory filter, no network). Player mode requires 2+ chars or returns empty.
3. **Group rendering**. Replace the single-result `switch` in `searchResultView` with a `SearchResultGroup` view that conditionally renders three sections (Users / Leagues / Players) — only the section matching the active mode is populated for v1, but the grouping infrastructure is in place for a future "search-all" mode. Empty section state is "hidden" (don't render the section header). Player rows tap → `router.navigate(to: .playerDetail(playerId:))` (new `AppRoute` case).

Tray-header magnifying-glass wiring is **inherited from F3** — see `HeaderBar.swift` in F3's spec. F6 verifies it works and that the drawer closes on push; no new code on the entry-point side.

## Affected files

| File | Change | Why |
|------|--------|-----|
| `Xomper/Features/Home/SearchView.swift` | Refactor to consume `SearchStore`. Remove all `@State` for query/mode/debounce/results. Switch result rendering to `SearchResultGroup`. Add player tap handler. | View becomes a thin observer; logic moves to store. |
| `Xomper/Navigation/AppRouter.swift` | Add `.playerDetail(playerId: String)` to `AppRoute` enum. Verify `.search` already present (it is, line 11). | Player taps need a destination. |
| `Xomper/Features/Shell/MainShell.swift` (from F3) | Add `.navigationDestination(for: AppRoute.self)` case for `.playerDetail` → resolve `Player` via `PlayerStore.player(for:)` and push `PlayerDetailView`. If F3 already centralizes route resolution elsewhere, add the case there. | Wires the new route. |
| `Xomper/Features/Shell/HeaderBar.swift` (from F3) | **Verify only** — magnifying-glass button calls `router.navigate(to: .search)` and `navStore.closeDrawer()`. No edits unless missing. | F3 owns this; F6 sanity-checks. |

## New files

All under `Xomper/`:

- **`Core/Stores/SearchStore.swift`** — `@Observable @MainActor final class SearchStore`. Owns `query: String`, `mode: SearchMode`, `debouncedText: String`, `isSearching: Bool`, `errorMessage: String?`, `hasSearched: Bool`, `results: SearchResults`. Methods: `setQuery(_:)` (triggers debounce), `setMode(_:)` (clears results), `performSearch() async`, `clear()`. Holds `apiClient: SleeperAPIClientProtocol` + weak ref / unowned access to `PlayerStore` (passed at init).
- **`Features/Home/SearchResults.swift`** — value type. `struct SearchResults { var user: SleeperUser?; var league: League?; var players: [Player] }`. `var isEmpty: Bool` computed (all three empty/nil). `static let empty: SearchResults`.
- **`Features/Home/SearchResultGroup.swift`** — view. Takes `results: SearchResults`, `mode: SearchMode`, plus tap closures (`onUserTap`, `onLeagueTap`, `onPlayerTap`). Renders `ScrollView { LazyVStack }` with three optional sections in fixed order: Users, Leagues, Players. Each section header is a `Text("USERS").font(.caption.weight(.semibold))` styled per Midnight Emerald. Sections with no content are not rendered (no empty section headers).
- **`Features/Home/PlayerResultRow.swift`** — view. `Player` row: `PlayerImageView(playerID: player.playerId, size: 48)` + name (`.headline`) + subtitle line (`displayPosition · displayTeam`) + chevron. Wrapped in `Button { onTap() }`. Uses `.xomperCard()` modifier matching `userResultCard`/`leagueResultCard`.

## Data flow / state

```
SearchView
  ├─ @State searchStore = SearchStore(playerStore: ..., apiClient: ...)   // view-local @State (see open Q6)
  ├─ TextField("...", text: Binding(get: { searchStore.query }, set: searchStore.setQuery))
  ├─ Picker mode → searchStore.setMode(_:)
  └─ resultArea
       └─ SearchResultGroup(
              results: searchStore.results,
              mode: searchStore.mode,
              onUserTap:    { router.navigate(to: .userProfile(userId: $0)) }
              onLeagueTap:  { Task { await leagueStore.switchToLeague(id: $0); navStore.select(.standings) } }
              onPlayerTap:  { router.navigate(to: .playerDetail(playerId: $0)) }
          )
```

`SearchStore` is constructed by `SearchView` in `@State` (per open Q6 resolution). `PlayerStore` is passed in from the env / parent (same way `LeagueStore` is passed today). `SearchStore` is **not** an env singleton — search state should not survive navigation away from search.

Debounce: `setQuery(_:)` cancels prior `Task` and schedules a 500ms sleep before assigning `debouncedText` and triggering `performSearch()`. Identical to current view-local logic, just relocated.

## Implementation steps

Each step compiles independently; commit per step is fine.

1. **Add `.playerDetail(playerId: String)` case to `AppRoute`** in `AppRouter.swift`. Build green — no consumers yet.
2. **Add `.player` case to `SearchMode` enum** (currently private inside `SearchView.swift` — promote to file-level or keep private during step 1). Add `title = "Player"`, `placeholder = "Search players by name..."`, `hint = "Find any NFL player by name"`. Build green — `SearchView` already iterates `allCases`.
3. **Create `SearchResults.swift`** with the struct + `isEmpty` + `.empty`. Pure value type, no logic.
4. **Create `SearchStore.swift`** — `@Observable @MainActor`. Port the eight `@State` props from `SearchView` to stored properties on the store. Port `scheduleDebounce`, `performSearch`, `searchUser`, `searchLeague`, `clearResults` verbatim, swapping `self.searchText` for `self.query`, etc. Add `searchPlayer(_ term: String)` that calls `playerStore.search(query: term, limit: 25)` and assigns to `results.players`. Init takes `playerStore: PlayerStore` and `apiClient: SleeperAPIClientProtocol = SleeperAPIClient()`.
5. **Wire `SearchStore.performSearch()`** to switch on `mode` and dispatch to the right helper. For player mode: no network, set `isSearching = false` immediately after the synchronous filter, set `hasSearched = true`. Player mode short-circuits if `term.count < 2` → empty results, no error.
6. **Create `PlayerResultRow.swift`** — mirrors `userResultCard` / `leagueResultCard` styling. `Button` wraps `HStack` with `PlayerImageView` (48pt) + `VStack` (name + "POS · TEAM") + `Spacer` + chevron. `.xomperCard()` modifier. Accessibility label: "View \(player.fullDisplayName), \(player.displayPosition), \(player.displayTeam)".
7. **Create `SearchResultGroup.swift`** — three optional sections (Users / Leagues / Players) inside `ScrollView { LazyVStack(spacing: Spacing.md) }`. Section header is a `Text` (uppercase, `.caption.weight(.semibold)`, `XomperColors.textMuted`) only rendered when that section has content. Move `userResultCard` and `leagueResultCard` from `SearchView` into `SearchResultGroup` (rename to `UserResultRow` / `LeagueResultRow` for consistency). Section rendering order: Users → Leagues → Players (fixed).
8. **Refactor `SearchView.swift`** — replace the eight `@State` with `@State private var searchStore: SearchStore` initialized in `init` with the passed `playerStore`. Replace `searchText` bindings with `Binding(get: { searchStore.query }, set: searchStore.setQuery)`. Replace `searchMode` reads with `searchStore.mode`, mode toggle calls `searchStore.setMode(_:)`. Replace `resultArea`'s `searchResultView` switch with `SearchResultGroup`. Pass tap handlers as closures. Delete the now-dead helper methods (`performSearch`, `searchUser`, etc.) — they live on the store.
9. **Update `SearchView` init signature** to accept `playerStore: PlayerStore`. Update call sites (search-route resolution in `MainShell` from F3) to pass `playerStore` from the env / parent shell.
10. **Wire `.playerDetail` route resolution** in `MainShell`'s `.navigationDestination(for: AppRoute.self)`. Resolve `Player` via `playerStore.player(for: playerId)`. If `nil` (shouldn't happen — player came from `playerStore.search`), render an `EmptyStateView` with "Player not found".
11. **Verify F3 tray-header search icon** — open `HeaderBar.swift`, confirm magnifying-glass `Button` action calls `router.navigate(to: .search)` AND `navStore.closeDrawer()` (in that order). If F3 only does the navigate without close, add the close call here. **No other tray edits.**
12. **Build + simulator validation** per Test plan section. Fix any Swift 6 strict concurrency warnings on `SearchStore` (likely none — `PlayerStore` is `@MainActor`, store is `@MainActor`).
13. **Update plan status to Done** after sim validation.

## View rendering spec

Concrete values for new components.

**Mode toggle (existing — unchanged styling)**
- Three buttons: User / League / Player
- Selected: `XomperColors.championGold` bg, `XomperColors.deepNavy` fg, `.semibold`
- Unselected: clear bg, `XomperColors.textSecondary` fg, `.regular`
- Container: `XomperColors.bgCard`, corner radius `XomperTheme.CornerRadius.md`

**`SearchResultGroup` container**
- `ScrollView` → `LazyVStack(alignment: .leading, spacing: XomperTheme.Spacing.md)`
- Padding: `XomperTheme.Spacing.md` on horizontal, `XomperTheme.Spacing.sm` top
- Background: inherits parent (`XomperColors.bgDark`)

**Section header (`Text`)**
- Style: `.caption.weight(.semibold)`, uppercase
- Color: `XomperColors.textMuted`
- Padding: `.horizontal 4`, `.bottom 4`
- Only rendered when section has ≥1 row

**`PlayerResultRow`**
- Wrapped in `Button { onTap(player.playerId) }.buttonStyle(.plain)`
- HStack spacing `XomperTheme.Spacing.md`
- `PlayerImageView(playerID: player.playerId, size: 48)`
- VStack(alignment: .leading, spacing: `Spacing.xs`):
  - Name: `Text(player.fullDisplayName).font(.headline).foregroundStyle(XomperColors.textPrimary).lineLimit(1)`
  - Subtitle: `Text("\(player.displayPosition) · \(player.displayTeam)").font(.caption).foregroundStyle(XomperColors.textSecondary)`
- Spacer
- Chevron: `Image(systemName: "chevron.right").font(.caption).foregroundStyle(XomperColors.textMuted)`
- `.xomperCard()` modifier
- Accessibility: label `"\(player.fullDisplayName), \(player.displayPosition), \(player.displayTeam)"`, hint `"Double tap to view player details"`

**Empty / prompt / error states**
- Reuse existing `noResultsView`, `searchErrorView`, `searchPromptView` — update prompt copy to handle player mode: `"Search for Sleeper users"` / `"Search for Sleeper leagues"` / `"Search for NFL players"`.
- "Try a different X" copy: add `case .player: "player name"`.

**Debounce timing**
- 500ms (unchanged, identical to current behavior).

**Player mode min query length**
- 2 characters. Below threshold → results empty, no spinner, no error, `hasSearched` stays whatever it was (don't flip to true on subkeystroke).

## Resolved open questions

1. **Mode toggle UX — segmented vs search-all?** → **Segmented (radio).** Three exclusive modes: User / League / Player. Search-all is overscope for v1; the grouped-section infrastructure leaves room to add it later by populating multiple sections at once. Default mode: `.user` (unchanged).
2. **Player tap destination?** → **Push `PlayerDetailView`** via new `.playerDetail(playerId:)` route. The detail view exists and is solid. Don't build a profile-image-card stub.
3. **Debounce — preserve 500ms across all modes?** → **Yes, 500ms across all modes.** Even though player mode is in-memory and could fire on every keystroke, the 500ms gives `LazyVStack` time to settle and matches user/league feel. Below 2 chars in player mode the search is a no-op anyway.
4. **`PlayerStore.search` query shape and result limit?** → Confirmed signature `search(query: String, limit: Int = 25) -> [Player]`. Filters on `searchFullName` / `firstName` / `lastName` (lowercased contains), prefix(25), sorted by `searchRank` ascending. **Use `limit: 25`** — same default — matches what feels reasonable on a phone screen.
5. **Empty per-section behavior?** → **Hide the section header** when that section has no rows. Show the single overall `noResultsView` only when ALL sections are empty AND `hasSearched`. Per-mode v1 only ever populates one section, so this is straightforward; built to scale.
6. **`SearchStore` ownership — view-local `@State` vs env singleton?** → **View-local `@State`.** Search is ephemeral — leaving and re-entering search should reset state, which mirrors current behavior. Env singleton would surprise users by preserving stale queries. Trade-off: typed query lost on push-then-pop, which matches the current `@State` view also losing it.
7. **Result row styling — three shapes vs polymorphic?** → **Three concrete row views** (`UserResultRow`, `LeagueResultRow`, `PlayerResultRow`). Each entity has different fields and tap semantics; a polymorphic `SearchResultRow` would either lose information or carry awkward optionals. Three views cost ~30 lines each and are clearer.
8. **F3 coordination — tray icon wiring?** → **F3 owns it.** Step 11 verifies the icon calls both `router.navigate(to: .search)` and `navStore.closeDrawer()`. If F3's `HeaderBar` is missing `closeDrawer()`, add the single line here — that's the only acceptable edit to the tray.

## Acceptance criteria

- Mode toggle shows three buttons: User / League / Player. Default `.user`.
- Switching modes clears prior results and `hasSearched` flag.
- Typing in **User** mode: 500ms debounce → `SleeperAPIClient.fetchUser` → renders `UserResultRow` in Users section. Tap → `router.navigate(to: .userProfile(userId:))`. **Identical to current behavior.**
- Typing in **League** mode: 500ms debounce → `SleeperAPIClient.fetchLeague` → renders `LeagueResultRow` in Leagues section. Tap → `leagueStore.switchToLeague(id:)` then `navStore.select(.standings)` (replacing today's `router.switchTab(.league)` which is gone post-F3). **Identical user-perceived behavior, updated mechanism.**
- Typing in **Player** mode (≥2 chars): 500ms debounce → `PlayerStore.search(query:limit: 25)` → renders `PlayerResultRow` rows in Players section. Tap → `router.navigate(to: .playerDetail(playerId:))` → pushes `PlayerDetailView`.
- Player results show: avatar (48pt) + full name + "POS · TEAM" + chevron. Sorted by `searchRank` ascending.
- Below 2 chars in player mode: no spinner, no error, prompt remains.
- Results render as grouped sections — header text uppercase, hidden when section empty.
- All-empty state shows the existing `noResultsView` with mode-aware "Try a different player name" copy.
- `SearchStore` is `@Observable @MainActor`. Debounce is 500ms. View has zero `@State` for search logic.
- Tray-header magnifying-glass pushes `.search` AND closes the drawer.
- Build clean with Swift 6 strict concurrency on `iPhone 17 Pro` simulator.
- No regressions in existing user/league search.

## Test plan

Simulator-first; no unit tests for this feature (search is mostly view + glue).

**Manual QA on `iPhone 17 Pro`**

1. Cold launch → open tray → tap magnifying-glass → `.search` pushes, drawer closes.
2. Default mode is User. Type "domgiordano" → after 500ms, user card appears. Tap → `userProfile` push.
3. Switch to League. Paste a known league ID → league card appears. Tap → switches league, navigates to Standings.
4. Switch to Player. Type "j" → no results section, prompt or empty UI (below threshold). Type "je" → players appear. Type "jefferson" → results refine, sorted by rank.
5. Tap a player row → `PlayerDetailView` pushes with full player data (header gradient, photo, info grid).
6. Pop back → search state preserved (since `SearchStore` is view `@State` and view didn't unload). Switch mode to User → results clear.
7. Pop search → re-enter → query field empty, mode reset to User.
8. Clear query button (X) clears `searchStore.query` and calls `clear()`.
9. Submit on keyboard (`.search` submitLabel) bypasses debounce — triggers immediate search.
10. Network error in User mode (airplane mode, search "asdf") → existing error UI; no crash.
11. Player mode with `PlayerStore.players` empty (force `playerStore = PlayerStore()` mid-test) → returns empty array, prompts "Try a different player name". No crash.

**Accessibility**
12. VoiceOver: mode toggle reads "User search, selected" / "Player search". Player row reads "Justin Jefferson, WR, MIN. Double tap to view player details".
13. Dynamic Type AX5: rows reflow, no truncation on name (lineLimit 1 is acceptable per design).

**Build validation**
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme Xomper -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
Must compile with zero new warnings. Swift 6 strict concurrency is on; `SearchStore` is `@MainActor` and only touches `@MainActor` types.

## Risks

- **`PlayerStore.players` not populated when player search runs.** F2 (PR #23) is in flight to fix this. If F2 lands cleanly, players load via `bootstrapPhase1` before user reaches search. **Mitigation**: player mode degrades gracefully — empty results, no crash. Sub-step 11 of test plan covers this.
- **`PlayerStore.search` is O(n) over ~10k players on every keystroke after debounce.** In practice runs in <30ms on device. **Mitigation**: 500ms debounce already there; if perf complaints surface, add a lowercase-name precomputed index later (out of scope for v1).
- **`router.switchTab(.league)` removed by F3** breaks current `navigateToLeague`. **Mitigation**: step 8 explicitly rewires to `navStore.select(.standings)`. F3's plan (line 85, step 15) already removed `switchTab` from `MyProfileView`; F6 carries that pattern into `SearchView`.
- **`AppRoute.playerDetail` collides with another team's pending route addition.** Low risk — only F6 touches `AppRoute` in this epic. **Mitigation**: add at the bottom of the enum to minimize merge conflicts.
- **F3 not yet merged when F6 starts.** F3 is in flight; F6 step 11 depends on `HeaderBar` existing. **Mitigation**: F6 sequencing is Week 2-3, after F3 (Week 1) lands. If F3 slips, F6 can still ship the `SearchStore` + grouped results refactor; the tray-icon verification step becomes a no-op until F3 merges.
- **`SearchStore` extraction subtly changes existing user/league search behavior.** Risk of state-init order or `Task` lifecycle differences. **Mitigation**: port logic verbatim (step 4), regression test steps 2 and 3 of QA cover identical-behavior assertion.

## Out of scope

- **No new player search backend.** Sleeper-direct only, via `PlayerStore.search` already-implemented in-memory filter. No `XomperAPIClient` work, no DynamoDB, no `/api/players/search`.
- **No "search-all" mode** that populates Users + Leagues + Players simultaneously. Grouped infrastructure supports it; v1 stays single-mode.
- **No global search bar inside the tray drawer.** Magnifying-glass icon push only — locked in F3.
- **No search history / recent searches.** Future polish.
- **No fuzzy matching beyond `contains`.** `PlayerStore.search` uses Sleeper's `searchFullName` lowercased contains; that's it.
- **No projected/actual fantasy points** in player results. Not in `Player` schema (per F2 audit + epic non-goals).
- **No team-grouped player results** (e.g., "all WRs from MIN"). Single flat list sorted by rank.
- **No deep-linking** into search with prefilled query.
- **No iPad-specific layout adjustments.** Same shell on iPhone + iPad per epic decision.

## Skills / Agents to use

- **`ios-specialist`** — primary executor. Owns SwiftUI, `@Observable`, Swift 6 concurrency, project conventions. Expected duration: ~1 day (M scope, mostly mechanical refactor + one new mode).

## Notes for the executor

- Build incrementally — after step 4 (`SearchStore` created but unused), `SearchView` still works on its `@State`. Step 8 does the swap.
- `xcodegen generate` once after step 3 (`SearchResults.swift` is the first new file) — Xcode picks up the rest automatically.
- Player mode's "below 2 chars" is the only place where debounced text deliberately produces no work — handle it inside `performSearch()`, not in the view, so the view stays dumb.
- The three row views (`UserResultRow`, `LeagueResultRow`, `PlayerResultRow`) can live as `private struct` inside `SearchResultGroup.swift` — no need for separate files unless they grow.
- For the autonomous run, single squashed commit is acceptable.
