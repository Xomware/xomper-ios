# Plan: Xomper Overhaul (Epic)

**Status**: Ready
**Created**: 2026-04-28
**Last updated**: 2026-04-28
**Type**: Epic — splits into 6 sub-feature plans via `/orchestrate`

## Goal

Replace the current `TabView` shell with a Xomify-style slide-in tray, fix two user-visible correctness bugs (World Cup clinch math, player wiring), generalize the season switcher into an environment value, and extend search to include players. Six features, ~2-3 weeks, no backend work — iOS goes Sleeper-direct, matching the web app. Outcome: a single `LeagueShellView` with sectioned navigation and a profile-as-tray-header pattern, with correct standings and clean season filtering across history-backed views.

## Non-goals

- **Top performers profile section (#3c)** — needs Sleeper matchup `players_points` integration + a new `PlayerStatsStore`. Deferred to a separate follow-up epic.
- **Backend player endpoints** — `xomper-back-end` has zero player endpoints today; web doesn't use any either. Not adding them in this epic.
- **Fantasy stats schema** (points, projections, custom rank) — web `Player` model is identical to current iOS `Player`. No schema work.
- **Light mode support** — always-dark per project constraints.
- **Replacing `LeagueDashboardView`'s internal sub-tab picker** — only replacing the outer `TabView` shell. The inner segmented picker can collapse naturally as tray sections render destinations directly, but full removal is a side effect, not a goal.
- **Swift 6 concurrency hardening of unrelated stores** — only stores touched by these features.

## Architectural decisions

These are locked in. Sub-plans inherit them; do not re-litigate.

- **Tray pattern**: custom slide-in left drawer (Xomify-style), NOT `NavigationSplitView`, NOT a sheet. Width `min(screenWidth * 0.82, 320)`. Trigger: edge drag (>30pt from left) or avatar tap. Owned by a new `@Observable @MainActor NavigationStore`.
- **Tray sectioning**: composable `TraySection { TrayItem }` view models. We have ~10 destinations, Xomify's flat 13-item list won't scale. Sections: **Compete** (Standings, Matchups, Playoffs), **History** (Drafts, Matchups), **Roster** (Team, Taxi Squad), **Meta** (World Cup, Rules). Settings stays pinned in a footer (Xomify pattern).
- **Profile placement**: tray-header card (avatar + display name + chevron). Tap pushes `MyProfileView`. Drop `AppTab.profile` entirely.
- **Shell collapses to single surface**: post-auth, `LeagueShellView` is the only top-level view. `AppTab.home` and `AppTab.profile` go away. Home content (the league switcher / quick stats) folds into the tray header or the Compete section's first row.
- **Season switcher**: `@Environment(\.selectedSeason)` env value backed by a new `@Observable @MainActor SeasonStore`. View-state, not navigation-state. Standings stays current-season-only (Sleeper rosters are current-only). World Cup, History (matchups + drafts), Matchups read from env.
- **Search**: keep the existing `.search` route. Extract a `SearchStore`, add `player` mode, group results by entity type. Tray header gets a search icon → `.search` push. No global search bar inside the tray.
- **Clinch logic**: surgical. New `ClinchCalculator` enum/struct returns `[userId: ClinchStatus]` per division. Replaces the unconditional top-2-qualified at `WorldCupStore.swift:181-182`. 6 division games remaining is a constant for this last season; sanity-check against `nflStateStore.nflState.week` if available.
- **Player wiring**: audit-then-fix. No schema extension. Match web's behavior: Sleeper-direct, static metadata only.
- **Theme**: Midnight Emerald via `XomperColors`/`XomperTheme`. 8pt grid. Dynamic Type only.

## Feature breakdown

Six features. Each maps 1:1 to a sub-plan stub spawned by `/orchestrate`. Sequencing in dependency order.

---

### F1 — World Cup Clinch Fix (issue #5)

- **Phase**: 0 (Day 1)
- **Scope**: S
- **Dependencies**: none — pure logic, ships independently
- **Files touched**:
  - `Xomper/Core/Stores/WorldCupStore.swift` — replace lines 181-182 unconditional qualification
  - `Xomper/Core/Stores/ClinchCalculator.swift` (new) — pure-logic helper
  - `Xomper/Core/Models/WorldCupTeamRecord.swift` (or wherever the model lives) — possibly add `ClinchStatus` enum (`.clinched` / `.alive` / `.eliminated`) alongside or replacing `qualified: Bool`
  - `Xomper/Features/League/WorldCupView.swift` — render new states (clinched badge, eliminated dim/strike)
- **Acceptance criteria**:
  - A team is marked `.clinched` only when even with `gamesRemaining` wins, no team below them can catch their current win count (factor in head-to-head only if needed for parity — confirm scope in sub-plan).
  - A team is marked `.eliminated` when even with `gamesRemaining` wins, they cannot reach the win count of the 2nd-place team in their division.
  - Otherwise `.alive`.
  - Manually verified against current league standings: the actual 2026 division leaders match the visualization only when math says so.
  - `gamesRemaining` is configurable but defaults to `6` for the current season.
  - Unit-testable: `ClinchCalculator` is pure and takes inputs + returns outputs, no side effects.
- **Sub-plan should drill into**: exact `ClinchStatus` enum shape, whether to keep `qualified: Bool` for backwards compat, view-side rendering of the three states, and whether `gamesRemaining` derives from `nflStateStore.week` or stays a constant.

---

### F2 — Player Wiring Audit & Fix (issue #4)

- **Phase**: 0 (Day 1, parallel with F1)
- **Scope**: S/M (audit-driven; could grow if the bug is deeper)
- **Dependencies**: none
- **Files touched (predicted; audit may find more)**:
  - `Xomper/Core/Stores/PlayerStore.swift` — verify load + lookup
  - `Xomper/Features/Team/TeamView.swift` — likely consumer
  - `Xomper/Features/League/TaxiSquadView.swift` — likely consumer
  - `Xomper/Features/League/DraftHistoryView.swift` — likely consumer
  - `Xomper/Core/Networking/SleeperAPIClient.swift` — verify `fetchAllPlayersRaw` is reachable
- **Acceptance criteria**:
  - Audit doc lives at top of the sub-plan: which views call what, what data flows where, where it breaks.
  - All views that display players show: name, position, team, picture, jersey number, search rank — when present in Sleeper data.
  - Missing fields render gracefully (no crashes, sensible fallbacks).
  - Manual QA in simulator: open Team view, Taxi Squad view, Draft History view — all show player rows correctly with avatars loading from `sleepercdn.com`.
  - No `Player` model schema changes. No new `XomperAPIClient` endpoints.
- **Sub-plan should drill into**: the audit results first, then the actual fix list. Plan-output should NOT pre-commit to a fix before audit.

---

### F3 — League Nav Tray + Profile-on-Tray-Header (issues #1, #3a)

- **Phase**: 1 (Week 1)
- **Scope**: L
- **Dependencies**: F1, F2 (clean baseline before structural rewrite — not a hard dep, but desirable)
- **Files touched**:
  - `Xomper/App/ContentView.swift` — replace `TabView` body with `LeagueShellView`
  - `Xomper/Navigation/AppTab.swift` — delete enum (or shrink to a single `.shell` placeholder during migration; resolve in sub-plan)
  - `Xomper/Navigation/AppRouter.swift` — remove `selectedTab`, `switchTab` API; keep `path` + `navigate`
  - `Xomper/Navigation/NavigationStore.swift` (new) — `@Observable @MainActor`, owns `isDrawerOpen`, `selectedDestination`
  - `Xomper/Features/Shell/LeagueShellView.swift` (new) — root shell with drawer + content area
  - `Xomper/Features/Shell/TrayView.swift` (new) — drawer container with header + sections + footer
  - `Xomper/Features/Shell/TraySection.swift` (new) — section + item view models
  - `Xomper/Features/Shell/TrayHeaderView.swift` (new) — profile card + search icon
  - `Xomper/Features/League/LeagueDashboardView.swift` — strip outer wrapper; tray now drives destination, but inner tab content (StandingsView, MatchupsView, etc.) gets rendered directly. Resolve in sub-plan: delete `LeagueDashboardView` entirely vs. keep as a destination wrapper.
  - `Xomper/Features/Home/HomeView.swift` — fold into tray header / Compete section, then delete (or repurpose; resolve in sub-plan)
  - `Project.yml` — none needed (xcodegen picks up new files under `Xomper/`)
- **Acceptance criteria**:
  - Edge drag from left or tap on tray-header avatar opens the drawer.
  - Drawer width: `min(screenWidth * 0.82, 320)`; scrim: `Color.black.opacity(0.45)`; animation: `.easeInOut(duration: 0.25)`.
  - Sections render: Compete, History, Roster, Meta. Settings pinned at footer.
  - Selected destination shows visual selection state (icon tint, weight, chevron, gradient bg) per Xomify pattern.
  - Profile card in header: avatar + display name + chevron. Tap pushes `MyProfileView` and closes drawer.
  - Drop `AppTab` cleanly — no dead code, no orphaned routes.
  - Simulator validation: iPhone 17 Pro AND iPad (one of the available iPad simulators). Drawer behaves identically on both per Xomify (no adaptive split).
  - Dark mode only, Midnight Emerald palette, 8pt spacing, Dynamic Type.
  - Swift 6 strict concurrency — no warnings.
- **Sub-plan should drill into**: exact destination list and order, what happens to `AppTab` (delete vs. trivial enum), what happens to `HomeView` content, edge-drag gesture conflict with `NavigationStack` swipe-to-pop, and iPad-specific layout decisions.

---

### F4 — Profile Creative Section v1 (Trophy Case) (issue #3b)

- **Phase**: 1.5 (Week 1.5)
- **Scope**: S
- **Dependencies**: F3 (profile is now a tray-header push, not a tab)
- **Files touched**:
  - `Xomper/Features/Profile/MyProfileView.swift` — add Trophy Case section between header and league section
  - `Xomper/Features/Profile/TrophyCaseCard.swift` (new) — renders championships from `HistoryStore`
  - `Xomper/Core/Stores/HistoryStore.swift` — possibly add a derived computed `championships(forUserId:) -> [Championship]` if not already present
- **Acceptance criteria**:
  - Trophy Case shows championships won by the signed-in user across the league chain.
  - Empty state: "No championships yet — keep grinding."
  - Renders before "My Leagues" section.
  - Uses existing `HistoryStore.matchupHistory` data — no new API calls.
  - Pluggable structure: section is its own view, easy to add Top Performers later (F4-style hook).
- **Sub-plan should drill into**: exact `Championship` derivation logic from history, whether `HistoryStore` exposes a helper or `MyProfileView` derives in-line, visual treatment (medal icons, year badges).

---

### F5 — Season Switcher (issue #6)

- **Phase**: 2 (Week 2)
- **Scope**: M
- **Dependencies**: F3 (tray must be in place — season switcher likely lives in tray header or per-destination toolbar; sub-plan decides)
- **Files touched**:
  - `Xomper/Core/Stores/SeasonStore.swift` (new) — `@Observable @MainActor`, owns `selectedSeason: String`, `availableSeasons: [String]`
  - `Xomper/Core/Extensions/EnvironmentValues+Season.swift` (new) — `@Environment(\.selectedSeason)` key
  - `Xomper/App/XomperApp.swift` — inject `SeasonStore` into env at root
  - `Xomper/Features/League/MatchupsView.swift` — replace local `selectedSeason` `@State` with env read; delete inline picker (or keep as fallback during migration)
  - `Xomper/Features/League/WorldCupView.swift` — accept env season, filter `WorldCupStore.divisions` by season (if multi-season aggregation should respect filter — confirm in sub-plan)
  - `Xomper/Features/Profile/MatchupHistoryView.swift` — read season from env
  - `Xomper/Features/Profile/DraftHistoryView.swift` — read season from env
  - Season picker UI: lives in tray header OR per-destination toolbar. Sub-plan decides.
- **Acceptance criteria**:
  - Changing season in one place updates all consumer views simultaneously.
  - `SeasonStore.availableSeasons` derives from `HistoryStore.availableMatchupSeasons` ∪ league chain seasons.
  - Default `selectedSeason` = current NFL season from `NflStateStore`.
  - Standings does NOT subscribe (current-only by design).
  - Simulator validation: pick 2024, all history-backed views show 2024 data; pick current, they show current.
  - No regressions in `MatchupsView` — week scrolling and expansion still work.
- **Sub-plan should drill into**: where the picker UI lives (tray header vs. per-view toolbar), whether `WorldCupStore` filters its existing aggregation or recomputes, exact env-key vs. store-injection trade-off, and whether `MatchupsView`'s `expandedWeek` reset behavior on season change is preserved.

---

### F6 — Search Extension (Player Mode + Grouped Results) (issue #2)

- **Phase**: 3 (Week 2-3)
- **Scope**: M
- **Dependencies**: F2 (player wiring must be solid before player search uses it), F3 (tray header search icon entry point), F5 (loosely — search results may want to respect season context for player matches; defer if not needed)
- **Files touched**:
  - `Xomper/Features/Home/SearchView.swift` — refactor to consume new `SearchStore`, add player mode
  - `Xomper/Core/Stores/SearchStore.swift` (new) — `@Observable @MainActor`, owns query, mode, debouncedText, results, errors. Extracts current view-local logic.
  - `Xomper/Features/Home/SearchResultGroup.swift` (new) — grouped result rendering (Users / Leagues / Players sections)
  - `Xomper/Features/Shell/TrayHeaderView.swift` — search icon button → `router.navigate(to: .search)`
  - `Xomper/Core/Stores/PlayerStore.swift` — verify `search(query:limit:)` is sufficient; no changes expected
- **Acceptance criteria**:
  - Mode toggle: User / League / Player. Default User.
  - Player mode: typing 2+ chars filters via `PlayerStore.search`, results show name + position + team + thumbnail.
  - User and League modes: identical behavior to current.
  - Results render as grouped sections when present.
  - Tap player → opens player detail OR (if no detail view exists) profile-image-card view (sub-plan decides based on what exists).
  - Tap user → push `.userProfile`. Tap league → switch league.
  - Tray header search icon pushes `.search` route, drawer closes.
  - `SearchStore` is `@MainActor`, debounce logic preserved (500ms).
  - Existing user/league search behavior unchanged.
- **Sub-plan should drill into**: whether a player detail view needs to be built or if grouped result row is the destination, what happens on no-results in one section but results in another, and whether mode is exclusive (radio) or inclusive (search-all).

---

## Cross-cutting concerns

- **NavigationStore ownership**: lives at `Xomper/Navigation/NavigationStore.swift`, injected into `LeagueShellView`. Distinct from `AppRouter` — `AppRouter` continues to own `NavigationPath`, `NavigationStore` owns drawer state. Sub-plan F3 may merge them; resolve there.
- **SeasonStore location**: `Xomper/Core/Stores/SeasonStore.swift`. Injected via env at app root in `XomperApp.swift`. Stores that need it accept env or take it as init arg — sub-plan F5 picks one and applies consistently.
- **Theme tokens**: all new views must use `XomperColors` + `XomperTheme.Spacing` + Dynamic Type. No hardcoded colors or font sizes. Tray drawer bg uses `XomperColors.bgDark` (or a new `bgDrawer` token if needed; resolve in F3).
- **Accessibility**: every new tappable element gets `accessibilityLabel`. Drawer open/close exposes correct traits. Selected tray item exposes `.isSelected`. Min touch target `XomperTheme.minTouchTarget`.
- **Swift 6 strict concurrency**: every new `@Observable` store is `@MainActor`. Async work uses `Task { await ... }` from `@MainActor` contexts. No `@preconcurrency` shortcuts unless absolutely required and called out.
- **xcodegen**: new files under `Xomper/` are picked up automatically. No `Project.yml` edits expected. Run `xcodegen generate` after each PR's file additions.

## Risks & mitigations

- **Risk**: Tray edge-drag gesture conflicts with `NavigationStack` swipe-to-pop on iPhone.
  **Mitigation**: F3 sub-plan must validate gesture ordering. Likely solution: only enable edge drag when `path.isEmpty` (root of stack), or require an explicit drag-handle visible at root.
- **Risk**: iPad layout looks cramped with a 320pt drawer over a wide canvas.
  **Mitigation**: F3 sub-plan validates iPad simulator. Xomify ships flat layout on both — accept that and revisit only if visibly broken. Do NOT branch into `NavigationSplitView` for iPad; that re-introduces the complexity we're removing.
- **Risk**: Deleting `AppTab.profile` breaks a deep link or external entry point.
  **Mitigation**: F3 sub-plan greps for all `AppTab.profile`, `selectedTab = .profile`, and any push-notification routing. Confirm no external surface depends on it. (Quick check: `PushNotificationManager` doesn't appear to set tab selection, but verify.)
- **Risk**: Player wiring bug is deeper than expected (e.g., `PlayerStore` not bootstrapped before consumers, or Sleeper API rate-limited).
  **Mitigation**: F2 sub-plan starts with audit, NOT fix. If audit reveals deep issue, scope can grow to M without surprising us. If it grows to L, reschedule and notify before continuing.
- **Risk**: `SeasonStore` env injection forces signature changes across many stores → noisy diff.
  **Mitigation**: F5 prefers env-read in views, NOT store init args. Stores stay decoupled; views pass `season` to store calls explicitly. If a store needs reactive season, it gets `SeasonStore` injected directly (sub-plan resolves).
- **Risk**: Search store extraction could regress current user/league search behavior.
  **Mitigation**: F6 acceptance criteria explicitly preserves current behavior. Manual simulator regression test required before merge.
- **Risk**: Profile creative section design (Trophy Case) doesn't match user's mental model and gets rejected.
  **Mitigation**: F4 is S-scope. Easy to redo. Lock it in as v1, iterate post-epic if needed.
- **Risk**: Bootstrap ordering — `LeagueShellView` replacing `ContentView`'s `TabView` may shuffle when `bootstrapPhase1`/`Phase2` run.
  **Mitigation**: F3 sub-plan preserves `.task` modifiers verbatim on the new shell root.

## Test plan

UI testing in SwiftUI is hard. Lean on simulator validation per project rule.

**Per-feature manual QA**:
- **F1 (clinch)**: World Cup view shows correct clinched/alive/eliminated states for all 4 divisions. Spot-check one team where math is non-obvious.
- **F2 (player wiring)**: Open Team, Taxi Squad, Draft History — all player rows render with avatars, position, team, name. No empty rows.
- **F3 (tray)**: Edge-drag opens drawer. Avatar tap opens drawer. All 4 sections render. Tapping each item navigates correctly. Selection state visible. Profile push from header works. Test on iPhone 17 Pro AND one iPad simulator.
- **F4 (Trophy Case)**: Profile shows Trophy Case section. Empty state renders if user has no championships.
- **F5 (season switcher)**: Pick 2024 → matchup history, draft history, World Cup all show 2024. Pick current → all show current. Standings unaffected.
- **F6 (search)**: Tray header search icon opens search. Mode toggle works. Player mode returns results. User and league modes still work.

**Build validation per PR**:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme Xomper -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
Must compile clean with Swift 6 strict concurrency, no new warnings.

**Unit tests**:
- F1's `ClinchCalculator` is pure — must have unit tests covering: top-2 alive, 1st clinched, 2nd clinched, 5th eliminated, ties.
- Other features have minimal unit-testable surface.

## Sequencing & dependencies

```
Day 1:    F1 ──┐
              ├──> F3 ──┬──> F4 ──> (next phase entry)
Day 1:    F2 ──┘        │
                         ├──> F5
                         │
                         └──> F6 (waits on F2 + F3, soft dep on F5)

Deferred: F7 Top Performers (separate epic, NOT spawned by /orchestrate)
```

Linear order if working solo:
1. **F1** (Day 1, ships immediately)
2. **F2** (Day 1, ships independently)
3. **F3** (Week 1)
4. **F4** (Week 1.5)
5. **F5** (Week 2)
6. **F6** (Week 2-3)

F1 and F2 can interleave on Day 1 — neither blocks the other. F3 should start after both land to avoid touching the same views twice. F4, F5, F6 are sequential after F3.

## Out of scope (do NOT spawn sub-plans for these)

- Top performers profile section (F7 — separate epic)
- Sleeper matchup `players_points` integration
- New `PlayerStatsStore`
- Backend player endpoints in `xomper-back-end`
- Fantasy stats schema on `Player`
- Light mode support
- iPad-specific `NavigationSplitView` reintroduction
- `PushNotificationManager` changes
- Supabase auth changes
- Test infrastructure (unit test target, snapshot testing, etc.)

## Skills / Agents to Use

- **swift-ios-dev agent**: primary executor for all six features. Knows SwiftUI, `@Observable`, Swift 6 concurrency, project conventions.
- **codebase-auditor agent**: F2 only — drives the audit-first phase before any fix code lands.
- **xcodegen skill**: invoke after any sub-plan adds new files to verify `xcodeproj` regenerates cleanly.
- **simulator-validator skill** (if exists): F3, F5, F6 require multi-device simulator runs. If no skill exists, manual checklist suffices.
- **No new agents needed** — this epic is execution-heavy, not exploration-heavy.
