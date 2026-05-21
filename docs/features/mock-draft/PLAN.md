# Plan: Rookie Mock Draft (Mocks tab)

**Status**: Draft
**Created**: 2026-05-21
**Last updated**: 2026-05-21

## Summary
A 5-round (60-pick) rookie mock draft that replaces the placeholder under
the existing `.mocks` tab on `DraftOrderView`. Uses the league's actual
2026 Sleeper draft slot order from `historyStore.upcomingDraft` and
renders picks chosen by five configurable "personalities" in two modes:
**Pure** (one mock per personality) and **Mixed** (per-team random
personality assignment, 3 mocks for variance). Success = on the Mocks
toggle, you see a scrollable list of mocks that "feel" different per
personality, anchored to FantasyCalc rookie values, with stochastic
outputs cached for the session so toggling/scrolling doesn't reshuffle.

## Goal & Scope
Ship a usable v1 of the mocks tab covering:
- 5 personalities (BPA, Team Fit, Wildcard, Win-Now, Hype Train) with
  finalized math.
- Pure mode (5 mocks, one per personality, all 12 teams behave the same).
- Mixed mode (3 mocks; each team gets a random personality per mock).
- Linear draft order pulled from `historyStore.upcomingDraft`.
- Skill positions only (QB/RB/WR/TE). No K/DEF.
- Session caching so randomized mocks stay stable between toggles.

Out of scope listed below.

## Decisions Resolved

### 1. Rookie pool definition
**Decision**: Take the intersection of
`PlayerStore.players[].yearsExp == 0`, `PlayerValuesStore.valuesById`
(has a non-zero dynasty value), and `position ∈ {QB, RB, WR, TE}`.

**Justification**: `Player.yearsExp: Int?` is decoded from the Sleeper
`years_exp` field (`Xomper/Core/Models/Player.swift:12,47,80`). After the
April 2026 NFL draft, Sleeper marks current rookies with `yearsExp == 0`
until Week 1 rolls them to 1. FantasyCalc dynasty values already exclude
non-fantasy-relevant rookies, so intersecting the two pools gives a
naturally-sized rookie pool (~50–80 names) with no manual maintenance.

**Fallback**: If the intersection yields fewer than `rounds × teams = 60`
players (extremely unlikely after a real NFL draft, but possible
mid-cycle), fall back to "top 60 by FantasyCalc value among players with
`yearsExp ∈ {0, 1}`". Surface a one-line warning in the header card when
the fallback triggers so we know the pool was widened.

**Manual QA**: Spot-check 3 known 2026 first-rounders (e.g. top QB, top
RB) once integrated — confirm they appear in the pool with `yearsExp == 0`.

### 2. needBoost formula (Team Fit)
**Decision**: For each (team, position), compute the team's season HPP
**at that position only** by summing the optimal-lineup contributions of
that position across regular-season weeks. Then:

```
teamPosHPP = sum over weeks of optimal points contributed by `pos` players for this roster
leagueAvgPosHPP = average of teamPosHPP across all 12 teams
needBoost = max(0.6, min(1.8, (leagueAvgPosHPP / max(teamPosHPP, 1)) ^ 0.6))
score = value * needBoost
```

**k = 0.6**. Justification: with k = 1.0, a team 2× below league average
at a position gets a 2× boost — so often pulls a #20 player over a #5
player, which is too aggressive. With k = 0.3, the boost barely budges
ordering. k = 0.6 lands roughly between (sqrt-ish, slightly steeper),
which in spreadsheet sketches with realistic 2025 HPP numbers turns "I
have a strong RB room" into ~0.85× RB scores and "I have nothing at TE"
into ~1.35× TE scores. The `max/min` clamp prevents pathological boosts
when `teamPosHPP` is near zero (e.g. a team with no TE on roster).

**Per-position HPP source**: extend (or wrap) `HighestPossibleCalculator`
with a per-position breakdown helper. Lightweight — reuse the same greedy
slot loop, just bucket the chosen player's contribution by their position.

### 3. Personality dials (final)
| Personality | Formula | Notes |
|---|---|---|
| BPA | `score = value` | Pure dynasty value. Deterministic. |
| Team Fit | `score = value * needBoost` (see §2) | k = 0.6 |
| Wildcard | uniform random among top **8** by value | N = 8. Wide enough to feel chaotic but still bounded to actual rookies. |
| Win-Now | `score = value * {RB: 1.30, WR: 1.20, TE: 1.00, QB: 0.85}` | Tightened QB down to 0.85 — in a 2QB league, QB value is already inflated, so a flat 0.9 multiplier still over-picks QBs. 0.85 nudges RB/WR ahead at borderlines. |
| Hype Train | `score = pow(value, 1.20)` then add `+1%` jitter (random in `[-0.01, +0.01]`) | Amplifies the top tier; jitter prevents identical ordering to BPA at the very top so it actually looks different. |

Tie-breaking: when two candidates score within 0.5%, break by FantasyCalc
value descending then by Sleeper `playerId` ascending so output is
deterministic given a seed.

### 4. Pick row rendering
Each row shows:
- **Pick number** (round.pickInRound, e.g. "1.07") and overall pick.
- **Team name** (from `historyStore.upcomingUsers`), highlight if mine.
- **Rookie full name** + **NFL team** abbreviation.
- **Position chip** (color-coded via `XomperColors` per existing pattern).
- **FantasyCalc value** (right-aligned, gold).
- **Score caption** (small, muted): for non-BPA personalities, show the
  effective score and what tipped it (e.g. "fit ×1.34 → 8,234").
- For personalities with randomness (Wildcard, Hype Train jitter),
  display a small dice glyph in the row corner.

Header card per mock:
- Personality name + one-line description.
- "Pure: every team picks via [personality]" vs. "Mixed: per-team personality assignments".
- Total picks (60) and number of unique players selected.

### 5. UI architecture
**Decision**: Single vertical `ScrollView` for the active mode, with each
mock as a collapsible `DisclosureGroup` (default expanded for the first
mock, collapsed for the rest). 5 × 60 = 300 rows total in Pure mode if
all expanded; collapsible avoids initial-render cost and lets the user
focus.

Inside the Mocks toggle, add a secondary **Pure / Mixed** segmented
control sitting just below the existing Live/Proposal/Mocks bar (same
visual treatment as the outer segmented bar to feel native).

A "Reshuffle" button (small, top-right of the Mocks content area)
triggers a fresh seed for stochastic mocks. Deterministic mocks
(BPA, Team Fit) are unaffected by reshuffle.

### 6. Caching
**Decision**: `MockDraftStore` holds:
- `pureMocks: [DraftPersonality: MockDraftResult]` — generated once per
  session, regenerated only on Reshuffle (re-shuffles Wildcard + Hype
  Train jitter; BPA + Team Fit + Win-Now are deterministic so no-op).
- `mixedMocks: [MockDraftResult]` — 3 entries, each with a seed +
  per-team personality map. Regenerated on Reshuffle.
- `currentSeed: UInt64` — incremented on Reshuffle, fed into a
  `SystemRandomNumberGenerator`-compatible seeded RNG so the same seed
  produces identical mocks (important for unit tests).
- Invalidated when `historyStore.upcomingDraft?.draftId` changes or when
  `PlayerValuesStore.lastLoadedAt` changes.

## Architecture

### New types
| Type | Location | Role |
|---|---|---|
| `DraftPersonality` (enum) | `Xomper/Features/DraftOrder/Mocks/DraftPersonality.swift` | Cases: `.bpa`, `.teamFit`, `.winNow`, `.hypeTrain`, `.wildcard`. Holds display name, blurb, color accent. |
| `MockedPick` (struct, Sendable) | `Xomper/Features/DraftOrder/Mocks/MockedPick.swift` | `pickNo`, `round`, `slot`, `rosterId/userId/teamName`, `playerId`, `playerName`, `position`, `nflTeam`, `value`, `score`, `personality`. |
| `MockDraftResult` (struct, Sendable) | `Xomper/Features/DraftOrder/Mocks/MockDraftResult.swift` | `mode: Mode`, `picks: [MockedPick]`, `personalityByRosterId: [Int: DraftPersonality]?`, `seed: UInt64`. |
| `MockDraftEngine` (pure-Swift) | `Xomper/Features/DraftOrder/Mocks/MockDraftEngine.swift` | `static func run(rookies:, slotOrder:, rounds:, perPickPersonality: (pickNo) -> DraftPersonality, teamContext: TeamContext, rng: inout SeededRNG) -> [MockedPick]`. Pure — no actors, no stores. Easy to unit-test. |
| `TeamContext` (struct, Sendable) | `Xomper/Features/DraftOrder/Mocks/TeamContext.swift` | Pre-computed snapshot: per-position HPP per roster, league averages, current roster composition for context. Built once on `MainActor`, passed into the engine. |
| `SeededRNG` (struct) | `Xomper/Features/DraftOrder/Mocks/SeededRNG.swift` | Tiny PCG/xorshift-style `RandomNumberGenerator` so we can reproduce mocks from a seed in tests. |
| `MockDraftStore` (`@Observable @MainActor`) | `Xomper/Core/Stores/MockDraftStore.swift` | Glues the stores together. Builds `TeamContext`, derives rookie pool, generates Pure + Mixed results, caches them, exposes loading/error/reshuffle. |
| `MockDraftView` | `Xomper/Features/DraftOrder/Mocks/MockDraftView.swift` | The view that lands in place of `mocksPlaceholder`. |
| `MockDraftCard` | `Xomper/Features/DraftOrder/Mocks/MockDraftCard.swift` | One mock's `DisclosureGroup` with header + picks. |
| `MockedPickRow` | `Xomper/Features/DraftOrder/Mocks/MockedPickRow.swift` | Single row. |

### Reuses
- `PlayerValuesStore.valuesById` / `positionsById` — rookie value + position.
- `PlayerStore.player(for:)` — full name, NFL team, `yearsExp`.
- `PlayerPointsStore.weeklyRosterPoints` — drives per-position HPP via the new helper.
- `HistoryStore.upcomingDraft` / `upcomingRosters` / `upcomingUsers` — slot order, teams, my-team highlight.
- `LeagueStore.myLeague?.rosterPositions` — feeds the per-position HPP calc.
- `HighestPossibleCalculator` — extended (new helper, not changed) with per-position attribution.

### Data flow
1. View appears → `MockDraftStore.ensureLoaded(...)` reads upcomingDraft / rosters / values / per-week points.
2. Store builds `TeamContext` once (per-roster per-position HPP + league averages).
3. Store builds rookie pool (intersection of yearsExp==0 + FantasyCalc).
4. For each personality in Pure mode, engine runs once. For Mixed, engine runs 3× with distinct seeds + random per-team personality maps.
5. Results land in `pureMocks` / `mixedMocks`, view re-renders.

### Wiring
`DraftOrderView` already receives the stores it needs. Pass them into
`MockDraftView` directly (no env injection). `MockDraftStore` is created
lazily as a `@State` inside `MockDraftView` (same lifetime as the screen).

## Affected Files / Components
| File / Component | Change | Why |
|---|---|---|
| `Xomper/Core/Models/HighestPossibleLineup.swift` | Add `optimalLineupPointsByPosition(...) -> [String: Double]` helper. | Powers per-position HPP without re-implementing the greedy slot loop. |
| `Xomper/Core/Stores/MockDraftStore.swift` | New file. | Cache + orchestration. |
| `Xomper/Features/DraftOrder/Mocks/DraftPersonality.swift` | New file. | Personality enum + display metadata. |
| `Xomper/Features/DraftOrder/Mocks/MockedPick.swift` | New file. | Pick model. |
| `Xomper/Features/DraftOrder/Mocks/MockDraftResult.swift` | New file. | Mock model. |
| `Xomper/Features/DraftOrder/Mocks/TeamContext.swift` | New file. | Per-roster snapshot for fit calc. |
| `Xomper/Features/DraftOrder/Mocks/SeededRNG.swift` | New file. | Reproducible randomness. |
| `Xomper/Features/DraftOrder/Mocks/MockDraftEngine.swift` | New file. | Pure draft simulation. |
| `Xomper/Features/DraftOrder/Mocks/MockDraftView.swift` | New file. | Root view of the Mocks tab. |
| `Xomper/Features/DraftOrder/Mocks/MockDraftCard.swift` | New file. | One mock per card. |
| `Xomper/Features/DraftOrder/Mocks/MockedPickRow.swift` | New file. | Row rendering. |
| `Xomper/Features/DraftOrder/DraftOrderView.swift` | Replace `mocksPlaceholder` with `MockDraftView(...)`; wire required stores. | Mount the new view. |
| `XomperTests/MockDraftEngineTests.swift` | New tests file. | Engine determinism, math sanity. |
| `XomperTests/HighestPossibleCalculatorTests.swift` | New tests file (or extend). | Per-position attribution helper. |

## Implementation Steps
*Order matters — pure layers first so each step compiles + tests on its own.*

- [ ] **1. Extend HPP calculator with per-position attribution.**
  In `HighestPossibleLineup.swift` add
  `static func optimalLineupPointsByPosition(playerPoints:rosterPositions:playerStore:) -> [String: Double]`
  that returns `{"QB": x, "RB": y, ...}` using the same greedy slot
  assignment. Existing `optimalLineupPoints` should remain unchanged
  (call from the new helper if convenient).
- [ ] **2. `xcodegen generate`** so the new file shows up in the project,
  then build to confirm green.
- [ ] **3. Add tests for the per-position helper** in
  `XomperTests/HighestPossibleCalculatorTests.swift`: known slot config
  + known player points → known per-position totals. Include a FLEX
  edge case where the chosen FLEX is a WR vs an RB.
- [ ] **4. Create `SeededRNG`** — small `RandomNumberGenerator`
  implementation (e.g. SplitMix64). Add a tiny test verifying same seed
  = same sequence.
- [ ] **5. Create `DraftPersonality` enum** with display name, blurb,
  accent color, and a `scoringMode` discriminator (deterministic vs
  stochastic) — useful when deciding whether reshuffle should re-run it.
- [ ] **6. Create `MockedPick` and `MockDraftResult` models** (Sendable).
- [ ] **7. Create `TeamContext`** with:
  - `rosterIds: [Int]`
  - `posHPPByRoster: [Int: [String: Double]]`
  - `leagueAvgByPos: [String: Double]`
  - Builder method `TeamContext.build(leagueStore:historyStore:playerStore:playerPointsStore:regularSeasonLastWeek:)` on `MainActor`. Falls back to "no need boost" (`leagueAvgByPos = teamPosHPP` for everyone) if `weeklyRosterPoints` is empty — Team Fit then degrades gracefully to ≈BPA.
- [ ] **8. Create `MockDraftEngine`** with:
  - `static func run(rookies:[RookieCandidate], slotOrder:[Int: SlotTeam], rounds:Int, teamContext: TeamContext, personality:(Int /*pickNo*/) -> DraftPersonality, rng: inout SeededRNG) -> [MockedPick]`
  - Maintains a `Set<String>` of taken playerIds.
  - For each pick (linear, slot 1 → slot N, repeated `rounds` times):
    1. Look up the picking team and its personality.
    2. Compute score for each remaining rookie per the personality formula.
    3. Wildcard: collect top 8 by raw value, pick uniformly at random via `rng`.
    4. Hype Train: apply jitter via `rng` to each candidate's score.
    5. Append a `MockedPick`.
  - All operations are pure functions of inputs + RNG state. No async, no actors.
- [ ] **9. Add `MockDraftEngineTests`:**
  - BPA on a fixed pool produces the value-descending sequence (deterministic).
  - Same seed + same inputs → identical Wildcard sequence; different seed → different sequence.
  - Team Fit: a team with `teamPosHPP = 0.5 × leagueAvg` at TE picks a TE earlier than BPA would.
  - Win-Now: with values tied, RB selected over QB at the same value.
  - Pool exhaustion: when fewer rookies than picks remain, engine returns the picks it could fill without crashing (define behavior: stop appending; surface in result metadata).
- [ ] **10. Create `MockDraftStore`** (`@Observable @MainActor`):
  - Properties listed in the Architecture section.
  - `func ensureLoaded(leagueStore: historyStore: playerStore: playerValuesStore: playerPointsStore: regularSeasonLastWeek:)` — idempotent.
  - `func reshuffle()` — bumps `currentSeed`, regenerates all stochastic mocks.
  - `func setMode(.pure | .mixed)` — sets the active mode.
  - Guards against missing upcomingDraft (returns `.pending`), missing values (`.pending`), missing draft order (`.pending`), and surfaces `.noRookiePool` when the pool is empty even after fallback.
- [ ] **11. `xcodegen generate`** for all new files (Models + Stores +
  Mocks/), then build green.
- [ ] **12. Build `MockedPickRow`** using the existing
  `XomperColors`/`XomperTheme.Spacing` patterns from `liveRow` in
  `DraftOrderView`. Match visual weight so live and mocks feel like
  siblings.
- [ ] **13. Build `MockDraftCard`** with the personality header card +
  `DisclosureGroup` wrapping a `LazyVStack` of rows. First card expanded,
  rest collapsed.
- [ ] **14. Build `MockDraftView`:**
  - Pure/Mixed inner segmented control (mirror outer bar styling).
  - `Reshuffle` button (top-right of content area). Icon: `arrow.triangle.2.circlepath`.
  - `ScrollView` listing all mocks for the active mode.
  - States: loading (`LoadingView`), pending (data still loading from
    other stores — `LoadingView` with appropriate message),
    empty (`EmptyStateView` for "no upcoming draft" or "no rookie pool"),
    ready.
- [ ] **15. Wire `MockDraftView` into `DraftOrderView`:**
  - Replace `mocksPlaceholder` with `MockDraftView(...)`.
  - Pass `leagueStore`, `historyStore`, `playerStore`, `playerValuesStore`,
    `playerPointsStore`, `userStore`.
  - In `.task(id: viewMode)`, when entering `.mocks`, call
    `await ensureLiveLoaded()` (so the draft order is fresh) plus the
    proposal's `ensureProposalLoaded()` (needed for per-position HPP).
  - Mocks branch in `.refreshable` should call
    `mockDraftStore.reshuffle()` after re-loading dependencies.
- [ ] **16. `xcodegen generate`**, then build green.
- [ ] **17. Confirm `PlayerValuesStore` is reachable** from the shell — if
  it's not yet passed through to `DraftOrderView`, thread it through the
  same way `playerPointsStore` is (likely already wired since trade
  analyzer uses it, but verify).
- [ ] **18. Verify Sleeper `draft.type`** for our league's rookie draft is
  `"linear"`. If `historyStore.upcomingDraft?.type == "snake"`, log a
  warning and continue assuming linear for v1 (snake support is deferred).
- [ ] **19. Run the test suite** end-to-end.
- [ ] **20. Manual QA pass** per checklist below.

## Test Plan

### Unit (XomperTests)
- `HighestPossibleCalculatorTests.optimalLineupPointsByPosition`
  - Standard slot config (QB/RB/RB/WR/WR/TE/FLEX/SF) with fixed points → exact per-position breakdown.
  - FLEX edge case: WR has 22, RB3 has 20 → FLEX = WR, attribution credits WR.
- `SeededRNGTests` — same seed reproduces sequence.
- `MockDraftEngineTests`
  - `bpa_isValueDescending`: BPA on a 10-rookie pool with distinct values picks in strict value-DESC order.
  - `wildcard_isDeterministicForSameSeed`: two runs with `seed = 42` produce identical pick lists.
  - `wildcard_variesAcrossSeeds`: two runs with different seeds differ in at least one pick.
  - `teamFit_boostsWeakPositions`: synthetic `TeamContext` where roster 5 has TE HPP = 0.5 × league avg → roster 5 picks a TE earlier than BPA would.
  - `winNow_prefersRBoverQB`: two candidates with same value, one RB / one QB → RB selected.
  - `hypeTrain_amplifiesTop`: with values [10000, 9900, 100, 50], pick #1 is always one of the top two (jitter can't swap top-two with bottom-two).
  - `poolExhaustion_doesNotCrash`: pool of 30 with 60-pick draft → engine returns 30 picks and signals exhaustion.

### Manual QA checklist
- [ ] Live tab still works (no regression in the existing screen).
- [ ] Proposal tab still works.
- [ ] Mocks tab loads the Pure mode by default with 5 cards.
- [ ] First card expanded, rest collapsed.
- [ ] Each Pure card has exactly 60 picks across 5 rounds.
- [ ] BPA mock matches FantasyCalc rookie value order for at least pick 1.01 (top rookie).
- [ ] Team Fit mock: pick 1.01 isn't necessarily the top rookie (depends on slot-1 team's needs).
- [ ] Wildcard mock: pick 1.01 is one of the top 8 by value — re-tap "Reshuffle" → ordering changes for Wildcard but BPA is unchanged.
- [ ] Switching to Mixed shows 3 cards, each with a per-team personality map visible in the card header.
- [ ] Reshuffle changes Mixed mocks but not BPA / Team Fit / Win-Now.
- [ ] My team's rows are highlighted (championGold) in every mock.
- [ ] No rookie appears twice within a single mock.
- [ ] Pull-to-refresh on Mocks tab keeps the screen responsive.
- [ ] Empty state appears when `historyStore.upcomingDraft == nil`.
- [ ] Empty state appears when `PlayerValuesStore.valuesById` is empty (e.g. FantasyCalc fetch failed).
- [ ] Visual styling consistent with Live tab (same cards, spacing, colors).

## Out of Scope (v1)
- User-editable personality weights (sliders for k, multipliers, top-N).
- Save / share / export mocks (image, text, link).
- Live "draft in progress" overlay during the actual July 6 draft.
- K / DEF positions in the pool.
- Snake draft support — linear only. Confirm `draft.type == "linear"` per step 18.
- Multi-round trade modeling (no swapping picks mid-mock).
- Persisting mocks across app launches.

## Risks / Tradeoffs
- **Sleeper `years_exp` not yet flipped to 0 for 2026 rookies at QA time**: mitigated by the fallback in §1 (widen to `yearsExp ∈ {0, 1}` if pool is too small).
- **Per-position HPP is approximate** (greedy attribution at FLEX assigns the chosen player's position, which is reasonable but can over-credit WR if FLEX preference is WR-heavy): accepted for v1; the needBoost only nudges ordering.
- **FantasyCalc lag**: FantasyCalc updates daily but not minute-to-minute. If a rookie's value lags reality, mocks will reflect that. Reasonable for v1.
- **Wildcard top-N = 8 is a judgment call**: if it feels too tame or too chaotic in QA, adjustable in one line. Document the chosen number in the personality blurb.
- **Render cost on 5 × 60 rows**: mitigated by `DisclosureGroup` collapsed-by-default and `LazyVStack` inside.
- **Mixed mode randomness on first appear can confuse users**: mitigated by Reshuffle button being visible + explanatory header text.

## Open Questions
- [ ] Should Mixed mode pin one personality to my team so I can compare consistent versions of "how others draft around me"? (Defer to v2 unless QA reveals it's needed.)
- [ ] Should pick-by-pick rationale be displayed inline ("filled TE need", "best available") or only on tap? (v1 inline caption; revisit if rows feel busy.)
- [ ] If `draft.type == "snake"` after step 18, do we ship linear-only with a banner or block the feature? Recommendation: ship linear with a visible banner — the league's rookie draft has been linear historically.

## Skills / Agents to Use
- **swiftui-builder**: for `MockDraftView`, `MockDraftCard`, `MockedPickRow` — keep them aligned with the existing `liveRow`/`row` styling in `DraftOrderView`.
- **swift-test-author**: for `MockDraftEngineTests` and the HPP per-position helper tests. Engine is pure Swift so this should be a clean unit-test pass.
- **xcodegen-runner** (or just remember manually): run `xcodegen generate` after each batch of new files (steps 2, 11, 16) before `xcodebuild`.
- **ios-build-runner**: invoke the project's `xcodebuild` command after step 16 and step 19.
