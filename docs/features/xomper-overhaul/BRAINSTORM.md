# Brainstorm: Xomper Overhaul Epic

Date: 2026-04-28
Updated: 2026-04-28 (post sibling-repo audit — see Phase 2.5)
Scope: Six features bundled — league nav tray, profile refactor, season switcher, player data unification, search, World Cup clinch logic.

> **Update note**: After the initial brainstorm, audited `../xomper-back-end`, `../xomper-front-end`, and `../xomify-ios` to answer open questions. Findings shifted scope on three features and produced a revised recommendation. See **Phase 2.5 — Audit findings** and **Phase 3 (revised)**.

---

## Premise check (before exploring)

A few things to flag before listing options, because they shape every option:

1. **`Player` model has no fantasy-relevant fields.** `Xomper/Core/Models/Player.swift` only carries Sleeper's static metadata (name, team, position, search rank). There is no `points`, no `weekly_points`, no `xomper_rank`, no projected/actual scoring. The user says "name, position, rank, points, picture, team" should flow through — but the current data shape can't carry points. This is not a wiring bug; it is a missing schema. Whatever lives on the Xomper backend must add fields, and the iOS `Player` struct must extend (or split into `PlayerStatic` + `PlayerStats`).
2. **`XomperAPIClient` does not fetch player data today.** It only sends emails and registers devices. The "shared backend" the user describes for player data does not yet exist on the iOS side. Feature #4 is partly a backend feature (or a stub of one).
3. **"Players don't load" likely means players load but views don't render them.** `PlayerStore.loadPlayers()` is wired into `bootstrapPhase1` and uses ETag + disk cache. The map populates fine. The bug is more likely (a) consumers looking up by wrong key, (b) `points`/`rank` being nil because they don't exist on Player, or (c) views hardcoded to `XomperAPIClient` paths that 404. Audit must verify which.
4. **Clinch math is structurally wrong, not a math edge case.** `WorldCupStore.swift` line 181-182 unconditionally marks top 2 as qualified. There is no "games remaining" or "is mathematically eliminated" logic anywhere. The fix is not tweaking — it is adding clinch math, period.
5. **Search already exists and partially works.** `SearchView.swift` searches Sleeper users and leagues via direct API. It does not search players. No store, no result grouping, no `userIds` cache lookup. Building the "search" feature is mostly extending what exists, not greenfield.
6. **Profile-on-tray collides with the current tab structure.** Right now `AppTab` has `.home / .league / .profile` and `LeagueDashboardView` is *inside* the league tab. If profile becomes a tray icon and the tray is the league shell, then either (a) league becomes the only post-auth surface and home + profile fold into it, or (b) the tray lives at the root above tabs. The user implies (a). Worth confirming.
7. **Season switcher already exists for matchup history.** `HistoryStore.availableMatchupSeasons` is a thing. The work is generalizing it past matchup history into Standings (current-season Sleeper data) and World Cup (already aggregates seasons but doesn't filter by selection).

---

## Phase 1 — Explore (broad list)

### Tray / shell ideas
- Permanent left-aligned tray in `NavigationSplitView` sidebar — already adaptive on iPad, collapses on iPhone
- Bottom sheet tray with `presentationDetents` (medium/large) — pull up to access sections, Apple-native feel
- Fixed left rail with icon-only section toggles (Slack-style)
- Top hamburger drawer with grouped sections (Material-style — usually wrong on iOS)
- Composable `TraySection` + `TrayItem` view models, render tray view from a flat config
- Tray as a bound store (`NavigationStore`) so deep-linking and back-stack are testable
- Tray as a single view with hardcoded sections — fastest path
- Sticky tray header containing profile avatar + season selector + search icon
- Floating profile FAB (avatar bubble) that opens profile sheet — least invasive
- Profile pinned as the first row of every tray section list
- Profile as a dedicated cell *inside* the tray header band, separated by a divider
- Replace the entire `TabView` with a single `LeagueShellView` that owns the tray

### Sequencing ideas
- Land player unification first because search and profile-creative both depend on it
- Land tray shell first because every other UI feature lives inside it
- Land season switcher second — it changes store APIs, so it should land before tray content is finalized
- World Cup clinch fix first — pure math, no UI impact, ships in a day, removes wrong info immediately
- Search last — needs both unified player data and the tray to give it a home
- Build feature flags so tray can ship behind a toggle while old shell stays

### Season switcher patterns
- Global `@Environment(\.season)` value, default to current, override per-screen
- A `SeasonContext` singleton store that views observe
- Per-store `selectedSeason: String` published property, view binds to it
- Router-driven: `AppRoute.standings(season: String)` carries season in URL
- Fully derived: views accept `season` as a constructor arg
- Only generalize what's actually season-scoped — Standings is *not*, it's always current-week derived from Sleeper rosters

### Player data ideas
- Sleeper stays the source for static (name, position, team, picture, jersey)
- Xomper backend owns `xomperRank`, `weeklyPoints`, `seasonPoints`
- Hybrid `PlayerView` model that joins both at the store layer, never at the view
- Drop Sleeper entirely, mirror everything to Xomper backend (over-scope)
- Add a `/players/sync` endpoint to XomperAPIClient that returns `[player_id: PlayerStats]` keyed off Sleeper IDs
- Skip the backend for now, compute "rank" client-side from search_rank
- Fix the wiring bug first, ship the data unification as a follow-on
- Audit, then decide — don't commit to a backend shape until we know what's broken

### Search ideas
- Add a `PlayerSearchResult` case to existing `SearchResult` enum
- Build a `SearchStore` with debounce, source-toggling (user/league/player), result grouping
- Single search bar in the tray header, opens a sheet with grouped results
- Keep `SearchView` as a route, just extend it
- Two search modes: "global" (everything) vs "in-league" (current league users only)
- Search players by typing — uses existing `PlayerStore.search`
- Search users in current league (not just Sleeper-wide) — new path

### Clinch logic ideas
- Simple fix: compute `gamesRemaining` per division, mark `qualified = true` only when 2nd place's max-possible-wins < 1st place's current wins (and analogous for 2nd/3rd)
- Use `nflStateStore.nflState.week` to figure out remaining weeks
- Hardcode "6 games remaining" as a constant for this last season
- Build a proper `ClinchCalculator` since this is sunsetting and we want it correct on the way out
- Add an `eliminated` state alongside `qualified` for divisions where 5th/6th can't catch up

### Cross-cutting
- Move all season-scoped fetches to take `season: String` param
- Add a `ProfileSection` enum to make the "creative section" pluggable later
- Top performers idea for creative section — needs player points (#4)
- "Most improved" / "biggest blowout" ideas — need history records (already have)
- Personal trophy case (championships from history chain) — already have data, just render
- Defer profile creative section until #4 lands

---

## Phase 2 — Converge

Three viable epic-level options. They differ on **what foundation to lay first** and **how aggressive the structural rewrite is**.

---

### Option 1: Foundation First (data → shell → features)

**What**: Land player data unification (#4) and World Cup clinch fix (#6) before touching the UI shell. Then do the tray + profile refactor as one PR. Then layer season switcher and search on top.

**How it works**:
1. **Phase A (data)** — Audit player flow, extend `Player` model with optional `xomperRank`/`weeklyPoints`/`seasonPoints`, add `XomperAPIClient.fetchPlayerStats(season:)` returning `[playerId: PlayerStats]`. `PlayerStore` merges Sleeper + Xomper sources. Fix whatever is broken in current consumers.
2. **Phase A.5 (clinch)** — Add `ClinchCalculator` that takes division standings + games-remaining and returns `.clinched / .alive / .eliminated` per team. Wire into `WorldCupStore`. ~50 lines, pure logic.
3. **Phase B (shell)** — Replace `LeagueDashboardView` with a Xomify-styled tray. Profile becomes tray-header avatar (tap → sheet with `MyProfileView`). Drop `.profile` from `AppTab`. Tray sections: Overview, Compete (Standings/Matchups/Playoffs), History (Drafts/Matchups), Roster (Team/TaxiSquad), Meta (World Cup/Rules).
4. **Phase C (cross-cutting)** — `@Environment(\.selectedSeason)` + `SeasonStore`. Stores that need it (`HistoryStore`, `WorldCupStore`) accept season filter. Standings stays current-season-only.
5. **Phase D (search)** — `SearchStore` with three modes (users / leagues / players). Tray header gets a search icon → sheet. Extend `SearchView` to render grouped results.

**Sequencing & scope**:
- #4 player unification — **L** (touches Player model, store, backend, all consumers)
- #6 World Cup clinch — **S** (one file, pure math)
- #1 + #2 tray + profile — **L** (new shell, deletes old tab view)
- #3 season switcher — **M** (env value + 2-3 store changes)
- #5 search — **M** (store + view extension, depends on #4 for player results)

**Pros**:
- Most correct order: foundation before UI prevents rework
- Player data lands before search needs it — no awkward stub
- Clinch fix ships independently and immediately
- Each phase reviewable in isolation

**Cons / Risks**:
- Player unification (#4) is the longest pole and may not have a clear backend story yet — could block everything
- User sees no visual progress for a week or more
- Backend shape for player stats is a decision the user hasn't made — risks designing in the dark

**Best if**: The Xomper backend already has player stats endpoints (or the user is happy to design them now), and shipping correctness > shipping visible progress.

---

### Option 2: Shell First (tray → features → data last)

**What**: Build the tray + profile UI with current data sources first. Add season switcher inside the new shell. Fix clinch surgically. Defer player data unification + search to a follow-up because they share the missing player schema.

**How it works**:
1. **Phase A (clinch fix)** — Surgical: 30-line fix in `WorldCupStore` to compare wins + games-remaining. Ship same day.
2. **Phase B (shell)** — New `LeagueShellView` with tray, profile-as-tray-header avatar, drop profile tab. Tray renders existing sub-views unchanged. Reuses current stores.
3. **Phase C (season switcher)** — `@Environment(\.selectedSeason)` env value, plumbed into `MatchupsView` (already has it, generalize) and `WorldCupView`. Standings stays current-only because Sleeper rosters are current-only.
4. **Phase D (player audit + unification)** — Separate effort: figure out what's broken in player display, decide backend shape, extend model. Treat as its own mini-epic.
5. **Phase E (search)** — After D lands, extend `SearchView` with player mode + result grouping.

**Sequencing & scope**:
- #6 clinch fix — **S** (ships day 1, removes user-facing wrong info)
- #1 + #2 tray + profile — **L**
- #3 season switcher — **M**
- #4 player unification — **L** (deferred, treated as separate)
- #5 search — **M** (deferred until #4)

**Pros**:
- Visible progress fast — tray ships in a few days
- Avoids designing the backend in the dark; player audit can be done thoroughly
- Clinch fix unblocks a user-visible wrong-info bug immediately
- Smaller, tighter PRs

**Cons / Risks**:
- Player unification (#4) and search (#5) ship later — user wanted them in this epic
- Risk: tray gets built around current player gaps, then needs touch-up when #4 lands
- "Profile creative section" stays a stub because it needs #4

**Best if**: User wants visible UI progress fast, and is OK with #4 + #5 trailing as a follow-on. Also best if backend shape for player stats isn't decided yet — gives time to design.

---

### Option 3: Two Parallel Tracks (UI + data simultaneously)

**What**: Split the work into two independent tracks. Track A (UI) does tray + profile + season switcher with current data. Track B (data) audits player flow, designs backend, extends model. They merge at the end when search needs both.

**How it works**:
- **Track A (UI shell)**: clinch fix → tray shell → profile-on-tray → season switcher. Lands without touching player code.
- **Track B (data)**: player audit → backend design → model extension → consumer rewrite. Lands without touching navigation code.
- **Merge**: search is built last, needs both. Profile creative section is built last, needs both.
- The two tracks must not collide. Tray work touches `LeagueDashboardView`, `AppRouter`, `AppTab`, `ContentView`. Player work touches `Player`, `PlayerStore`, `XomperAPIClient`, and any view that reads `Player` fields. The overlap is small.

**Sequencing & scope**:
- Track A: clinch (S) → tray (L) → season switcher (M). ~3 PRs.
- Track B: audit (S) → schema (M) → wiring (M). ~3 PRs.
- Merge: search (M) + creative section (S). 1-2 PRs.

**Pros**:
- Maximum parallelism
- Each track has a single owner-mental-model
- Search and creative section lift naturally at the merge
- User sees progress on both fronts

**Cons / Risks**:
- Requires actual parallelism — if it's just one engineer, this is identical to Option 2 with more bookkeeping
- Merge conflicts if both tracks touch `MyProfileView` (they will, for the league list and creative section)
- Hard to know "done" — two definitions of done, two integration points

**Best if**: There are actually two streams of work running (e.g., user pairs with Claude on UI while doing player backend solo, or vice versa). Less compelling for solo work.

---

## Phase 2.5 — Audit findings (2026-04-28)

Audited the three sibling repos to answer the open questions. The findings change the scope of three features.

### Backend (`../xomper-back-end`)

**Bottom line: zero player endpoints exist today.**

- Stack: Python 3.10 on AWS Lambda, DynamoDB, JWT-authorized API Gateway. Auto-deploys on `master` push via GitHub Actions.
- Total surface: 6 endpoints. 4 email notifications (`/email/rule-proposal`, `/email/rule-accept`, `/email/rule-deny`, `/email/taxi`) + 2 device registration (`/api/register-device`, `/api/unregister-device`).
- DynamoDB tables: only `xomper-device-tokens`. No player cache, no stats tables, no league mirror.
- `sleeper_helper.py` *has* `fetch_nfl_players()` plus user/league/roster fetchers, but **none are exposed as REST endpoints** — they're internal helpers used by email handlers.
- No fantasy points, projections, ranks, or stats tracked anywhere.
- iOS `XomperAPIClient` calls exactly the 6 backend endpoints — no mismatch, no missing wiring.

**Implication**: There is no "shared backend" for player data to align with. Adding one is net-new backend work. iOS and web are both Sleeper-direct for player data today.

### Web (`../xomper-front-end`)

**Bottom line: web is Sleeper-only for player data, no fantasy stats.**

- Stack: Angular 18 with RxJS.
- `Player` interface at `src/app/models/player.interface.ts` — 27 fields, all Sleeper static metadata. **No `points`, `rank`, `projection`, or fantasy fields.**
- `player.service.ts:24` calls `GET https://api.sleeper.app/v1/players/nfl` directly, caches with `shareReplay(1)`.
- Player avatar URL pattern: `https://sleepercdn.com/content/nfl/players/{player_id}.jpg` (full) or `/thumb/{player_id}.jpg` (thumb). Team logo: `/images/team_logos/nfl/{team_lower}.png`.
- No backend join, no stats merge, no custom rank.
- Web search (`search.component.ts`) searches users + leagues only. Player search is incidental (used to populate roster/taxi modals on tap).

**Implication**: iOS `Player` model already matches web's shape. The "players don't load" bug is **wiring**, not schema. No model extension needed for parity. Adding fantasy stats would be net-new on both web and iOS.

### Xomify iOS tray (`../xomify-ios`)

**Bottom line: slide-in left drawer + `NavigationStore`, profile-card header, flat list. Translates well, needs sectioning for our scale.**

- Pattern: custom slide-in left panel, NOT `NavigationSplitView`/sheet/`TabView`.
- Trigger: edge drag (>30pt from left) or avatar tap in `HeaderBar`.
- Animation: `withAnimation(.easeInOut(duration: 0.25))`, offset-based show/hide.
- Width: `min(screenWidth * 0.82, 320)`.
- Scrim: `Color.black.opacity(0.45)` full-screen overlay, tap to close.
- State: a `NavigationStore` `@Observable` owns `isDrawerOpen` + selected destination.
- Header: gradient profile card (avatar 44pt + display name + email + chevron), tap → push profile.
- Body: flat `ForEach(primaryEntries)` of 13 destinations (Feed, Search, Likes, etc.).
- Footer: pinned Settings, separated by Divider.
- Selection state: icon color toggles (green → white), text weight (regular → semibold), chevron appears, background gradient on selected row.
- Theme: `xomifyDark` (#0A0A14) drawer bg, `xomifyPurple` (#9C0ABF) and `xomifyGreen` (#1BDC6F) accents. We'd substitute Midnight Emerald.
- Adaptivity: fixed layout, same drawer iPhone + iPad.
- Reusability: monolithic. `DrawerEntry` is private, `drawerRow` is a private method. Would extract `TraySection` + `TrayItem` for xomper.

**Implication**: Adopt the slide-in drawer + `NavigationStore` skeleton + profile-card header. Adapt: add named sections (we have ~10+ destinations grouped by domain, Xomify's flat list won't scale), extract reusable `TraySection`/`TrayItem`, swap theme to Midnight Emerald.

### Net scope change

| Feature | Original estimate | Revised estimate | Reason |
|---|---|---|---|
| #1 League nav tray | L | L | Same — drawer pattern clear, sectioning is the new work |
| #2 Search | M | S | `SearchView` already does users + leagues; just add player mode |
| #3 Profile refactor | L | M | Drawer header card pattern is borrowable |
| #4 Player wiring | L | S/M | No backend work needed; fix iOS consumer |
| #5 World Cup clinch | S | S | Unchanged — pure logic |
| #6 Season switcher | M | M | Unchanged |
| **3b Trophy Case** | — | S | New — uses existing history data |
| **3c Top performers** | — | M+ | Needs Sleeper matchup `players_points`; defer to phase 2 |

**Total epic scope dropped from ~4-6 weeks to ~2-3 weeks.** The "shared backend" myth was the largest cost driver.

### Open questions — now answered

1. ✅ Backend has player stats? **No** — zero player endpoints. Sleeper-only on iOS + web today.
2. ✅ Web shape to mirror? **Identical to current iOS Player model.** No changes for parity. Stats would be net-new everywhere.
3. ✅ Creative section direction? User answered "maybe both" — Trophy Case ships now (existing data), top performers is its own follow-up phase.
4. ✅ Xomify tray reference? Audited — slide-in drawer + `NavigationStore` + profile-card header. Sections need to be added for xomper.
5. ✅ "6 division games remaining" — user confirmed 6.

---

## Phase 3 (revised) — Recommendation

**Hybrid Option 1 — Foundation First, accelerated.**

Reasoning has shifted: with #4 (player wiring) reduced to S/M and no backend dependency, the foundation phase is now days, not weeks. Original Option 2 was about avoiding a long backend detour — that detour doesn't exist. Foundation-first is now the cleanest path.

**Sequencing**:

1. **Day 1 — parallel S fixes**
   - World Cup clinch fix (#5): add `ClinchCalculator` using `nflStateStore.week` + 6-game-remaining constant (last season). Replace `WorldCupStore.swift:181-182` unconditional qualification.
   - Player wiring audit (#4): trace why players don't render. Likely a consumer-key bug or a view expecting non-existent fields. Fix in place — no schema change.

2. **Week 1 — tray shell with sections (#1 + #3a)**
   - Build `LeagueShellView` mirroring Xomify `DrawerView`: slide-in panel, `NavigationStore` `@Observable`, edge-swipe + avatar-tap, scrim, profile-card header.
   - Extract reusable `TraySection { TrayItem }` (we have more destinations than Xomify; sectioning is required).
   - Sections: **Compete** (Standings, Matchups, Playoff Bracket), **History** (Drafts, Matchups), **Roster** (Team, Taxi Squad), **Meta** (World Cup, Rules).
   - Drop `AppTab.profile`, clean up `ContentView` switch. Profile becomes a tray-header push to `MyProfileView`.
   - Theme: Midnight Emerald via `XomperColors`/`XomperTheme`.

3. **Week 1.5 — profile creative section v1 (#3b)**
   - Trophy Case card: render championships from `HistoryStore` (data exists). Done. Defer top performers to phase 2.
   - Profile shows: avatar header, "My Leagues" quick-nav list (currently single league, but ready for plural), Trophy Case, Settings link.

4. **Week 2 — season switcher (#6)**
   - `@Environment(\.selectedSeason)` env value + `SeasonStore` `@Observable`.
   - Plumb into `WorldCupStore` (already aggregates seasons), `HistoryStore` (already has `availableMatchupSeasons`), `MatchupsView` (already has picker — generalize).
   - Standings stays current-season-only (Sleeper rosters are current-only).

5. **Week 2-3 — search (#2)**
   - Build `SearchStore` extending current `SearchView` (Sleeper user/league already work).
   - Add player mode: search by name → `PlayerStore.search` (already exists).
   - Result grouping by entity type. Tap-through to user profile / league / player detail.
   - Add tray-header search icon → push `.search` route.

6. **Phase 2 (separate epic)** — Top performers
   - Wire Sleeper matchup `players_points` endpoint (`/league/{id}/matchups/{week}`).
   - Build per-player season aggregation.
   - Add "Top Performers" card to profile creative section.
   - Likely requires a `PlayerStatsStore` (new) that aggregates matchup data weekly.

**Specific design calls** (unchanged from initial recommendation):

- **Tray pattern**: Composable `TraySection { TrayItem }`. Slide-in drawer over `NavigationStore`. Not a sheet, not `presentationDetents` — primary nav, not modal.
- **Profile placement**: Tray header card (Xomify pattern). Tap pushes `MyProfileView`. Not a tab, not an FAB.
- **Season switcher**: `@Environment(\.selectedSeason)` + `SeasonStore`. View-state, not navigation-state.
- **Search**: Keep `.search` route. Tray-header search icon pushes it. No global search bar in tray header (Xomify doesn't have one and crowding is real).
- **Clinch**: Surgical — `ClinchCalculator.calculate(division:gamesRemaining:) -> [TeamId: ClinchStatus]`. 6 games hardcoded for last season; pull from `NflStateStore.week` for sanity.
- **Player wiring**: Audit-then-fix. No schema extension. Match web's behavior: Sleeper-direct, static-only, no stats.

**What's deferred to phase 2** (NOT in this epic):
- Top performers creative section (needs new data infra)
- Per-player fantasy stats (web doesn't have them either; punt until needed)
- Backend player endpoints (no current consumer needs them)

---

## Phase 3 (original) — Recommendation [superseded]

**Recommend Option 2 — Shell First.**

Reasoning:
- The user explicitly said "players don't load" — that is a bug, not a feature, and bugs deserve a focused audit *before* a backend redesign. Option 1 forces the backend redesign before the audit. Option 2 lets you audit first, then decide.
- Tray + profile + season switcher are tightly coupled UI work. They want to be one mental model. Doing them after a long player-data detour means context-switching costs.
- Clinch fix in any option ships first because it's a one-day correctness win and removes user-visible wrong info. Don't sit on it.
- The "profile creative section" depending on player data is the only real cross-track coupling, and the user said they're open to ideas — ship the profile shell with a placeholder creative section (e.g. "Trophy Case" using existing history data), and add top performers when #4 lands.
- Option 3 only wins with parallel work streams. For a solo engineer + Claude, it's Option 2 with overhead.

**Caveat — this changes if any of these are true**:
- The Xomper backend already has player stats endpoints ready to consume → Option 1 becomes equally fast and more correct.
- The user wants every feature in this epic shipped in one merge train (no follow-up epic) → Option 1, accept the slow start.
- The "players don't load" bug is actually deep and needs a full schema rewrite to fix → it dominates anyway, so Option 1.

**Specific design calls inside Option 2**:
- **Tray pattern**: Composable. `TraySection { TrayItem }` with a config array. Not a monolith. Not a sheet — it's the primary navigation, not a modal.
- **Profile placement**: Tray header cell (top of the scroll, separated by divider). Not a FAB (too floaty for primary nav). Not a sheet trigger from elsewhere — tap avatar → push `MyProfileView` onto the stack.
- **Season switcher**: `@Environment(\.selectedSeason)` value with a `SeasonStore` in the env. Stores that need it read from the env or accept a `season` param. Don't put it in the router — season is a view-state concern, not a navigation concern.
- **Search**: Keep the existing `.search` route. Build a `SearchStore`. Extend modes to include players (after #4). Tray header gets a search icon that pushes `.search`. No global search bar in the tray itself — too crowded for the scope.
- **Clinch**: Surgical. `ClinchCalculator.calculate(division: WorldCupDivision, gamesRemaining: Int) -> [TeamId: ClinchStatus]`. Use `nflStateStore` for current week. Last-year-of-feature, no need to over-engineer for future seasons.

**Recommended PR sequence**:
1. Clinch fix (S) — ships day 1
2. `LeagueShellView` + tray scaffolding, with profile-as-header (L) — drops `.profile` tab
3. Move existing sub-views into tray sections (M) — no behavior change, just relocation
4. Season switcher env + plumb into history-backed views (M)
5. Player data audit + fix (S-M) — audit first, decide if a real schema extension is needed
6. (If needed) Player schema extension + Xomper backend work (M-L)
7. Search store + player search mode (M)
8. Profile creative section v1 — Trophy Case from history, then top performers if #4 enabled

---

## Phase 4 — Open questions for the user [resolved]

All five resolved during 2026-04-28 audit pass. See **Phase 2.5 — Open questions answered** above.

1. ✅ Backend has player stats endpoints? **No.**
2. ✅ Web schema to mirror? **Identical to current iOS — Sleeper static metadata only.**
3. ✅ Trophy Case vs. top performers for creative section? **Both — Trophy Case in this epic (uses existing history), top performers as phase-2 follow-on.**
4. ✅ Xomify iOS tray reference? **Slide-in drawer + `NavigationStore` + profile-card header. Adapt with sections.**
5. ✅ World Cup "6 games remaining"? **Confirmed 6.**

## Phase 5 — Ready for `/plan`

This brainstorm has converged. Ready to produce an epic plan doc.

Suggested next: `/plan xomper-overhaul` — produce `docs/features/xomper-overhaul/PLAN.md`, then `/orchestrate` to break into 6 sub-feature plans matching the sequencing in Phase 3 (revised).
