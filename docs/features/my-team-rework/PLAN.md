# Plan: My Team Rework

**Status**: Ready
**Created**: 2026-06-03
**Last updated**: 2026-06-03 (Phase 0a + 0b complete; 0c pending PR #138 review)
**Brainstorm**: [BRAINSTORM.md](./BRAINSTORM.md)

## TL;DR

Implement **Option B** from the brainstorm: rework `TeamView` into a 3-tab page (Roster / Strengths / Trades) with a sticky Quick Hitters strip on top. Zero backend work — reuses `TeamAnalysisBuilder`, `HexagonChartView`, and `RecommendedTradeBuilder` already in production inside `TeamAnalyzerView`.

## Approach

Single-feature scope (not an epic). Phase 0 lifts two view-builders out of `TeamAnalyzerView` into shared components AND hoists the Trade Analyzer's trade-builder `@State` into a new `@Observable TradeAnalyzerController`. The controller pays off the moment a second consumer (My Team's Trades tab) needs to seed a preloaded trade, and unlocks future deep-link sources (announcement cards, suggested-partner DMs, etc.) at zero marginal cost. **No button-launch fallback** — Branch A (controller-hoisted preload) is the only path forward per the locked decision.

## Scope

**In**:
- 3-tab `TeamView`: `.roster` (today's content) / `.strengths` (hex + breakdown) / `.trades` (recommendation list + deep-link to Analyzer)
- Sticky `QuickHittersStrip` above the picker — **6 stats**: record, league rank, total dynasty value, weakness chip, total FPTS (season-to-date), best position chip. Horizontal scroll on phone; fits without scroll on iPad.
- Extract `breakdownGrid` + `breakdownRow` into a shared `PositionBreakdownCard` view
- Extract `recommendedTradeRow` into a shared `RecommendedTradeCard` view
- `TeamAnalyzerView` refactored to use both extracted components (lossless — same rendering)
- Update both `TeamView` call sites in `MainShell` to pass any new dependencies

**Out**:
- New analytics / metrics — Quick Hitters use existing fields (`StandingsTeam.wins/losses/streak/leagueRank`, `TeamAnalysis.totalValue`, `leagueAverageAxes`, `PlayerPointsStore` for season FPTS sum)
- Changes to `RecommendedTradeBuilder` algorithm — render as-is
- Theme / palette changes — Midnight Emerald sweep handled by the parity epic
- Backend / Supabase / Sleeper API work — purely client-side IA reshuffle
- Weekly form / recent points (deferred from brainstorm's "missing" audit)

## Phase 0 Pre-work

Must complete before any visible TeamView change lands:

1. **Open GitHub issue**: `feat: My Team rework — tabs, quick hitters, embedded analyzer`. Use that number for the branch (`feat/<n>-my-team-rework`) and commit prefixes.
2. **Hoist trade-builder state into `@Observable TradeAnalyzerController`** — locked decision (long-term right call per user 2026-06-03): pull `tradePartnerRosterId`, `tradeSideAPlayerIds`, `tradeSideBPlayerIds` out of `TeamAnalyzerView` into a new `@Observable @MainActor final class TradeAnalyzerController` in `Xomper/Core/Stores/`. Instantiate once at `MainShell` (alongside the other stores), inject into `TeamAnalyzerView`, expose a `func preload(_ rec: RecommendedTrade)` that seeds the three fields atomically. The controller pays for itself the moment the Trades tab needs to seed a preloaded trade, and unlocks future deep-link sources (announcement cards, suggested-partner DMs) at zero marginal cost. **No time-box, no fallback** — this is the only path.
3. **Lossless refactor PR (separate commit, can land first)**:
   - Create `Xomper/Features/Shared/PositionBreakdownCard.swift` exposing `init(my: TeamAnalysis, opp: TeamAnalysis?, averages: [TeamAnalysis.HexAxis], maxes: [String: Int])`. Body is the existing `breakdownGrid` + `breakdownRow` verbatim (privatize the `deltaColor` helper into the file).
   - Create `Xomper/Features/Shared/RecommendedTradeCard.swift` exposing `init(_ rec: RecommendedTrade)`. Body is the existing `recommendedTradeRow` verbatim.
   - Update `TeamAnalyzerView` to consume both. Confirm the Compare tab and the Trades section still render identically (manual diff on simulator).

## Affected Files / Components

| File / Component | Change | Why |
|------------------|--------|-----|
| `Xomper/Features/Shared/PositionBreakdownCard.swift` | NEW | Hoist breakdown grid out of TeamAnalyzerView for reuse on Strengths tab |
| `Xomper/Features/Shared/RecommendedTradeCard.swift` | NEW | Hoist recommended-trade row out of TeamAnalyzerView for reuse on Trades tab |
| `Xomper/Features/TeamAnalyzer/TeamAnalyzerView.swift` | EDIT | Replace inline `breakdownGrid` / `recommendedTradeRow` with shared components; (conditional on Phase 0 result) accept optional `preloadedTrade` init param |
| `Xomper/Features/Team/TeamView.swift` | EDIT | Add `TeamSection` enum, `@State activeSection`, segmented `Picker`, `QuickHittersStrip`, three section bodies, `task`/`refreshable` plumbing for `valuesStore` |
| `Xomper/Features/Team/QuickHittersStrip.swift` | NEW | 4-tile horizontal summary (record, rank, value, weakness) — pure presentation, takes a `QuickHittersData` struct |
| `Xomper/Features/Shell/MainShell.swift` | EDIT | Pass `leagueStore`, `valuesStore`, `authStore`, `router` into both `TeamView(...)` call sites (`myTeamRoot` + `.teamDetail` push) |
| `Xomper/Navigation/AppRouter.swift` | EDIT (conditional) | If preload branch wins Phase 0: no change (use existing `teamAnalyzer` tray destination switch + a transient preload via shared store). If a new route case is cleaner, add `case teamAnalyzerWithTrade(RecommendedTrade)` — decided in Phase 0. |
| `Xomper/Features/Team/PlayerDetailView.swift` | NO CHANGE | Sheet presentation stays as-is |

## Implementation Steps

- [ ] **Step 1 — Phase 0**: Open issue, run trade-preload investigation, land lossless extraction PR (`PositionBreakdownCard` + `RecommendedTradeCard`). Confirm Analyzer renders unchanged on iPhone 17 Pro sim.
- [ ] **Step 2 — TeamSection scaffold**: In `TeamView.swift`, add `private enum TeamSection: String, CaseIterable { case roster, strengths, trades }`. Add `@State private var activeSection: TeamSection = .roster`. Insert a `Picker("Section", selection: $activeSection)` with `.pickerStyle(.segmented)` directly below the Quick Hitters strip placeholder. Wrap the existing roster body (`startersSection` / `benchSection` / `taxiSection` / `irSection`) in `case .roster:`.
- [ ] **Step 3 — QuickHittersStrip component**: Create `QuickHittersStrip.swift` rendering 4 horizontal tiles:
  - **Record**: `team.wins-team.losses` + `team.streak.displayString` chip (data already on `StandingsTeam`)
  - **League rank**: `team.leagueRank` with ordinal suffix (existing `ordinalSuffix` helper — move to extension)
  - **Total value**: `myAnalysis.totalValue` with delta vs league avg (sum of `leagueAverageAxes` / 6 × 6, i.e. compare to mean of `analyses.map(\.totalValue)`)
  - **Weakness**: axis label where `myAnalysis.hexAxes[i].value / leagueAverages[i].value` is smallest; tappable → sets `activeSection = .strengths`
  - **Total FPTS**: sum of `playerPointsStore.points(for: playerId)` across `roster.starters` (starter PF — matches the league standings PF column). Decide on starters-only vs full-roster sum during impl; default to starters.
  - **Best position**: axis label where `myAnalysis.hexAxes[i].value / leagueAverages[i].value` is largest; tappable → sets `activeSection = .strengths`.
  - Layout: horizontal `ScrollView(.horizontal, showsIndicators: false)` of `xomperCard()` tiles on phone — six tiles won't fit at default Dynamic Type on iPhone 17 Pro without scroll. Each tile snaps to a fixed min-width so labels read consistently. iPad gets a non-scrolling `LazyHStack`.
- [ ] **Step 4 — Strengths tab**: `case .strengths:` body renders:
  - `HexagonChartView(primary: myAnalysis.hexAxes, comparison: nil, leagueAverage: leagueAverages, axisMaxes: axisMaxes)`
  - `PositionBreakdownCard(my: myAnalysis, opp: nil, averages: leagueAverages, maxes: axisMaxes)`
- [ ] **Step 5 — Trades tab**: `case .trades:` body:
  - Compute `recs = RecommendedTradeBuilder.recommend(myAnalysis: ..., analyses: ..., rosters: leagueStore.myLeagueRosters, playerStore:, valuesStore:)`
  - Empty state when `recs.isEmpty` — reuse the same copy from TeamAnalyzerView's recommended-trades section.
  - `ForEach(recs) { rec in Button { ... } label: { RecommendedTradeCard(rec) } }`.
  - **Button action**: `tradeController.preload(rec)` then `navigationStore.select(.teamAnalyzer)`. The controller persists across the tray switch; `TeamAnalyzerView` reads from it on appear, so the partner + both sides are populated before the user sees the screen. No fallback path — the controller hoist landed in Phase 0.
- [ ] **Step 6 — Wire data dependencies**: `TeamView` needs `leagueStore: LeagueStore`, `valuesStore: PlayerValuesStore`, `authStore: AuthStore`, `playerPointsStore: PlayerPointsStore` (for FPTS tile), `tradeController: TradeAnalyzerController` (for Trades-tab preload). Add as `let` props. Compute `analyses` / `axisMaxes` / `leagueAverages` / `myAnalysis` once at the top of `body` (before the `switch`), exactly mirroring `TeamAnalyzerView.content`. Add `await valuesStore.loadValues()` to the existing `.task`. Add `await valuesStore.loadValues(forceRefresh: true)` to `.refreshable`.
- [ ] **Step 7 — Update call sites**: In `MainShell.swift` lines 344 and 406, pass the new dependencies. Both call sites already have access to `leagueStore`, `authStore`, and `valuesStore` (used elsewhere in MainShell for `TeamAnalyzerView` — line 228). Update the preview block in `TeamView.swift` accordingly.
- [ ] **Step 8 — Sticky behavior**: Try `safeAreaInset(edge: .top)` for the Quick Hitters strip so it stays pinned during scroll of the section content. **Risk gate**: if iPhone 17 Pro shows strip + picker eating > 30% of viewport before content shows, drop sticky and let it scroll with the page. Decide on-device.
- [ ] **Step 9 — Build + manual verify**: `xcodegen generate` then the standard build command. On iPhone 17 Pro sim verify:
  - Roster tab matches today's UI pixel-for-pixel.
  - Strengths tab renders hex chart + breakdown grid, no missing axes.
  - Trades tab lists recommendations (or empty state) and deep-links correctly.
  - No double-push when tapping a trade card (Branch A) or a nav-stack glitch (Branch B).
  - Pull-to-refresh on each tab re-loads both player data and values without thrash.
- [ ] **Step 10 — Commit + PR**: Branch `feat/<n>-my-team-rework`. Commit message prefix `#<n>`. PR description includes `Closes #<n>`. No Co-Authored-By lines.

## Data Flow

```
TeamView.body
 ├── Inputs: team (StandingsTeam), roster (Roster), league, playerStore, leagueStore, valuesStore, authStore
 ├── analyses = TeamAnalysisBuilder.build(rosters: leagueStore.myLeagueRosters, users: leagueStore.myLeagueUsers, playerStore, valuesStore)
 ├── myAnalysis = analyses.first { $0.userId == authStore.sleeperUserId } ?? analyses.first
 ├── axisMaxes = TeamAnalysisBuilder.axisMaxes(analyses)
 ├── leagueAverages = TeamAnalysisBuilder.leagueAverageAxes(analyses)
 │
 ├── QuickHittersStrip
 │    ├── record    ← team.wins / team.losses / team.streak
 │    ├── rank      ← team.leagueRank
 │    ├── value     ← myAnalysis.totalValue (+ delta vs mean(analyses.totalValue))
 │    └── weakness  ← argmin(myAnalysis.hexAxes[i] / leagueAverages[i])
 │
 ├── Picker(activeSection)
 │
 └── switch activeSection
      ├── .roster    → existing starters/bench/taxi/IR sections
      ├── .strengths → HexagonChartView(myAnalysis, nil, leagueAverages, axisMaxes) + PositionBreakdownCard
      └── .trades    → ForEach(RecommendedTradeBuilder.recommend(...)) → RecommendedTradeCard
                       Tap → preload or button-launch (Phase 0 decision)
```

Quick Hitters' record + rank source: `StandingsTeam` (already passed into `TeamView` — `team.wins`, `team.losses`, `team.streak`, `team.leagueRank`). No new `LeagueStore` field needed; the `StandingsBuilder` ran upstream during bootstrap.

## Risks / Tradeoffs

- **NavigationStack double-push (Trades deep-link)**: If we wire the trade card button to `router.navigate(to: .teamAnalyzerWithTrade)` from inside the in-page tab, and the user is already on the My Team tray destination, that pushes onto My Team's stack — not the Team Analyzer's. *Mitigation*: route via `navigationStore.select(.teamAnalyzer)` (drawer-level switch) plus a handoff store, not a stack push. Confirm during Step 5.
- **TeamAnalysis recompute on every render**: 12 rosters × ~25 players × dict lookups runs on every body invocation. *Accepted* — same pattern Analyzer uses, no measured perf issue today. If profiling shows otherwise, memoize behind a computed-once `let` outside the `switch` (already covered in Step 6).
- **Compact iPhones (vertical-space crunch)**: Sticky strip + segmented picker + hex chart on Strengths tab risks zero scroll room on iPhone 16e / SE-class. *Mitigation*: Step 8 risk gate — drop sticky if it eats more than ~30% viewport. Acceptable simpler fallback: strip scrolls with the page.
- **PlayerValuesStore cold load**: User lands on Strengths/Trades before values have ever loaded → empty axes. *Mitigation*: explicit loading view when `!valuesStore.hasValues`, gated identically to TeamAnalyzerView.
- **Roster tab regression risk**: This is the highest-traffic surface in the app. *Mitigation*: lift-and-shift the four section view-builders inside `case .roster:` without altering their bodies. Manual diff on sim.
- **Phase 0 fallback churn**: If trade-preload investigation fails, Branch B (button-launch) is a degraded experience. *Accepted* — the brainstorm flagged Option C as the fallback explicitly.

## Decisions (locked 2026-06-03)

- [x] **D-1: Trades-tab UX → Branch A (controller-hoisted preload).** Long-term right call. New `@Observable TradeAnalyzerController` owns the trade-builder state; injected at `MainShell`; both `TeamAnalyzerView` and the My Team Trades-tab card buttons consume it. No button-launch fallback. Pays off the moment a second deep-link source needs preloading.
- [x] **D-2: Quick Hitters → 6 stats.** Record / rank / total dynasty value / weakness / total FPTS / best position. Horizontal scroll on phone (six tiles don't fit unscrolled at default Dynamic Type); non-scrolling LazyHStack on iPad.
- [x] **D-3: Issue naming → `feat: My Team rework — tabs, quick hitters, embedded analyzer`.** Standalone; no parity-epic prefix.
- [x] **D-4: Tab order → Roster / Strengths / Trades.** Roster leads because it's the highest-traffic surface; Strengths and Trades follow in dependency order (Strengths reads the data Trades acts on).
- [ ] **D-5 (deferred to Step 8): Sticky vs scrolling Quick Hitters.** Final call made on-device — drop sticky if it eats > 30% viewport on iPhone 17 Pro.

## Success Criteria

- Roster tab is visually identical to today's My Team page (no regressions in slot ordering, badges, or sheet presentation).
- Strengths tab renders the same hex chart + per-position breakdown as the Analyzer's Compare tab (sans opponent column), seeded from existing stores with no new data loaders.
- Trades tab lists up to 5 ranked `RecommendedTrade`s (or the documented empty-state copy) and tapping one either preloads the Analyzer's builder (Branch A) or opens the Analyzer tray (Branch B) without nav-stack glitches.
- Quick Hitters strip surfaces record / rank / total value / weakness, updates on pull-to-refresh, and the weakness chip jumps to the Strengths tab on tap.
- Build succeeds (`xcodebuild` command from CLAUDE.md), no new warnings, manual smoke test on iPhone 17 Pro sim passes the Step 9 checklist.

## Skills / Agents to Use

- **planner**: this doc (done).
- **swiftui-builder** (or general implementation agent): Steps 2–8 — straightforward SwiftUI refactor, well-scoped.
- **xcode-build-verify** (or shell-runner): Step 9 — runs `xcodegen generate` and the build command, surfaces errors.

## Next Step

Plan is `Ready`. Next command:

```
/execute my-team-rework
```

Phase 0 prereqs (open issue, hoist `TradeAnalyzerController`, extract `PositionBreakdownCard` + `RecommendedTradeCard`) ship as their own commit/PR before the visible TeamView changes land.
