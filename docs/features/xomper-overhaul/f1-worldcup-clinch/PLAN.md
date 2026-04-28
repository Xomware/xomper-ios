# Plan: Xomper Overhaul — F1: World Cup Clinch Fix

**Status**: Done
**Parent epic**: [../PLAN.md](../PLAN.md)
**Feature ID**: F1
**Issue**: #5
**Created**: 2026-04-28
**Last updated**: 2026-04-28 (executed)
**Phase**: 0 (Day 1)
**Scope**: S
**Dependencies**: none — pure logic, ships independently
**Recommended specialist agent**: `ios-specialist`

---

## Domain context (confirmed with user 2026-04-28)

The "World Cup" is a 3-year format ending this season:
- 6 divisional games per team per season → **18 total division games across the era**.
- Top 2 cumulative W/L records per division qualify for an in-season tournament for cash.
- This is **year 3 — the final year**. ~6 division games remaining as of plan date.
- **Tiebreaker**: total points scored in division games (across all 3 seasons combined).
- Post-this-season the format ends; following season runs the tournament-of-top-teams; year-after introduces new divisions.

Implication: clinch math is on cross-season aggregate W/L, not single-season. v1 conservative math (no tiebreaker simulation) is acceptable because clinch is only declared when wins-mathematically-impossible-to-tie; ties at the cutoff stay `.alive`. PF (points for) tiebreaker is left to season-end resolution.

---

## Goal

Replace the unconditional "top-2 = qualified" branding at `WorldCupStore.swift:181-182` with real clinch math. Introduce a pure-logic `ClinchCalculator` that returns `.clinched / .alive / .eliminated` per team given the current aggregated standings + a `gamesRemaining` constant (6 for the final season). Wire into `WorldCupView` so each row visibly reflects its qualification status. Ship unit tests against the pure calculator. No new networking, no schema for stats, no changes to standings aggregation.

---

## Approach (locked)

Surgical addition. The aggregation logic in `WorldCupStore.computeStandings(...)` stays untouched — it already produces an aggregated cross-season W/L per user per division, sorted wins-DESC then PF-DESC. We swap the final pass:

```diff
- if teams.count >= 1 { teams[0].qualified = true }
- if teams.count >= 2 { teams[1].qualified = true }
+ let statuses = ClinchCalculator.calculate(teams: teams, gamesRemaining: 6)
+ for i in teams.indices { teams[i].clinchStatus = statuses[teams[i].userId] ?? .alive }
```

`ClinchCalculator` is a pure `enum` namespace with one entry point. No state, no actor isolation, no async. Testable in isolation.

`qualified: Bool` is **replaced** by `clinchStatus: ClinchStatus`. The only consumer is `WorldCupView.swift` — no other file reads `qualified`. (Verified by reading all current consumers; if a stale reference is found during execution, replace with `clinchStatus != .eliminated` or specific case as appropriate.)

`gamesRemaining` is **hardcoded `6`** as a `static let` on `ClinchCalculator` (with doc-comment explaining it is the count for the final regular-season slate). `NflStateStore.currentWeek` is NOT consulted. Rationale below in Open Questions.

---

## Affected files

| File | Change | Why |
|------|--------|-----|
| `Xomper/Core/Stores/ClinchCalculator.swift` (new) | Pure-logic `enum ClinchCalculator` with `calculate(teams:gamesRemaining:) -> [String: ClinchStatus]`. Includes `static let defaultGamesRemaining = 6`. | The math, isolated and testable. |
| `Xomper/Core/Models/WorldCup.swift` | Add `enum ClinchStatus: Sendable { case clinched, alive, eliminated }`. Replace `var qualified: Bool` with `var clinchStatus: ClinchStatus` on `WorldCupTeamRecord`. Add a computed `var qualifiedForBracket: Bool { clinchStatus == .clinched }` for legible call-sites. | Three-state model, single source of truth. |
| `Xomper/Core/Stores/WorldCupStore.swift` | Replace lines 181-182 with a `ClinchCalculator.calculate(...)` call and per-team assignment. Initialize `WorldCupTeamRecord` with `.alive` instead of `qualified: false`. | The point of the feature. |
| `Xomper/Features/League/WorldCupView.swift` | Render three states: `.clinched` → gold "CLINCHED" badge + gold-tinted row + trophy icon; `.alive` → existing neutral styling; `.eliminated` → dim row (opacity 0.4) + strikethrough team name + small "OUT" pill in muted red. Update `accessibilityDescription`. Update `qualifiedBadge` and `rowBackground`/`opacity` logic. Replace the static "Top 2 in each division qualify" subtitle with a dynamic line that still explains the rule but reads "Top 2 per division qualify · 6 games left" or similar. Update the divider + cutoff visual: still placed after rank 2, but the divider label changes from "QUALIFIED" to "QUALIFICATION LINE" since not everyone above is necessarily clinched. | Surface the new states to the user. |
| `XomperTests/ClinchCalculatorTests.swift` (new) | Unit tests for `ClinchCalculator`. See Test Plan below. | Pure logic deserves tests; this is the only piece of the epic that does. |
| `Project.yml` | Add a `XomperTests` test target (Swift unit tests, depends on `Xomper`). Minimal config — no UI tests, no host app launch arg twiddling. | No test target exists today; adding one is unavoidable for F1's "unit-testable" acceptance criterion. |

---

## Algorithm — `ClinchCalculator.calculate`

Inputs:
- `teams: [WorldCupTeamRecord]` — already sorted wins-DESC then PF-DESC by the caller. Single division.
- `gamesRemaining: Int` — defaults to `6`.

Definitions:
- `currentWins(t)` = `t.wins`.
- `maxPossibleWins(t)` = `t.wins + gamesRemaining`. (We assume any remaining game *could* be a divisional game. This over-estimates for v1 — see Open Questions / Math precision.)
- `qualificationCutoffRank` = 2 (top 2 per division).

Per team `t` at index `i` (0-based) within its sorted division:

1. **`.clinched`** — even if every team currently below `t` wins all `gamesRemaining`, they still cannot reach `t.wins`. Concretely: for every `other` with `other.wins < t.wins` and `other` is currently outside the top-2 (i.e. ranked 3rd or below), `other.wins + gamesRemaining < t.wins`. Additionally, if `t` is currently in the top-2 AND `gamesRemaining == 0`, `t` is `.clinched` regardless.
   - **Tie note**: ties (`other.wins == t.wins`) do NOT count as caught for `.clinched`, since the existing tiebreaker is PF-DESC and a team currently ahead on PF stays ahead on PF if they tie in wins. v1 treats current PF as locked; that's a simplification, see Out of Scope.
2. **`.eliminated`** — `t.wins + gamesRemaining < secondPlaceCurrentWins`. I.e., even winning out, `t` cannot reach the team currently sitting in the 2nd seed by wins. Edge: if `t` IS currently 1st or 2nd (index 0 or 1), they are not eliminated by definition.
3. **`.alive`** — otherwise.

Returns `[userId: ClinchStatus]`. Caller maps back onto teams.

Pseudocode:

```swift
enum ClinchCalculator {
    static let defaultGamesRemaining = 6

    static func calculate(
        teams: [WorldCupTeamRecord],
        gamesRemaining: Int = defaultGamesRemaining
    ) -> [String: ClinchStatus] {
        guard !teams.isEmpty else { return [:] }
        // teams already sorted wins DESC, PF DESC
        let cutoffIndex = 1  // 0-based — the 2nd seed
        let cutoffWins = teams.indices.contains(cutoffIndex) ? teams[cutoffIndex].wins : teams[0].wins

        var result: [String: ClinchStatus] = [:]
        for (index, team) in teams.enumerated() {
            if index <= cutoffIndex {
                // Sitting in a qualifying seat — eligible to clinch
                let chasers = teams.dropFirst(cutoffIndex + 1)
                let canBeCaught = chasers.contains { $0.wins + gamesRemaining >= team.wins }
                result[team.userId] = canBeCaught ? .alive : .clinched
            } else {
                // Sitting outside qualifying seats — eligible to be eliminated
                let maxPossible = team.wins + gamesRemaining
                result[team.userId] = (maxPossible < cutoffWins) ? .eliminated : .alive
            }
        }
        return result
    }
}
```

Edge cases handled:
- `teams.empty` → empty result.
- `teams.count == 1` → that team is `.clinched` (no one to catch them, `gamesRemaining` irrelevant).
- `gamesRemaining == 0` → top-2 are `.clinched`, anyone with strictly fewer wins than 2nd seed is `.eliminated`, exact ties at the cutoff line stay `.alive` (simplification: PF tiebreaker decides at season end, but v1 doesn't model it).
- Everyone has 0 games played (preseason) → `gamesRemaining = 6`, every chaser can match top-2, so everyone is `.alive`. Correct.

---

## Implementation steps

Each step is independently buildable; `xcodebuild` should pass after every commit.

- [x] **Step 1 — Add `ClinchStatus` enum + extend model.**
- [x] **Step 2 — Update `WorldCupStore.swift` callsite.**
- [x] **Step 3 — Add `ClinchCalculator.swift`.**
- [x] **Step 4 — Wire calculator into store.**
- [x] **Step 5 — Update `WorldCupView.swift` rendering.**
- [x] **Step 6 — Add test target to `Project.yml`.**
- [x] **Step 7 — Run `xcodegen generate`.**
- [x] **Step 8 — Add `ClinchCalculatorTests.swift`.**
- [x] **Step 9 — Run tests + simulator validation.**
- [x] **Step 10 — Manual QA pass (build clean, 0 warnings).**

---

## View rendering — concrete visual treatment

Three distinct states, all in Midnight Emerald palette via `XomperColors`:

| State | Row background | Row opacity | Team-name decoration | Inline badge | Rank cell color |
|------|---------------|-------------|---------------------|--------------|-----------------|
| `.clinched` | `XomperColors.championGold.opacity(0.14)` | 1.0 | bold, gold | `Image(systemName: "trophy.fill")` 12pt + "CLINCHED" caps caption2 in `championGold` | `championGold` |
| `.alive` | `XomperColors.bgCard.opacity(0.3)` (current) | 1.0 | normal | (none) | rank-based (existing logic) |
| `.eliminated` | `XomperColors.bgCard.opacity(0.15)` | 0.4 | `.strikethrough()`, `textMuted` | "OUT" caption2 caps in `XomperColors.accentRed.opacity(0.7)` pill | `textMuted` |

`qualifiedBadge` (the green "Q") is removed — superseded by the inline CLINCHED label which is more honest (a top-2 team that has not mathematically clinched gets no badge; previously they all did).

Divider/cutoff label: change "QUALIFIED" to "QUALIFICATION LINE" with the same gold styling. Still rendered after rank 2 if there are more than 2 teams.

Header subtitle: replace `"Top 2 in each division qualify"` with `"Top 2 per division qualify · \(gamesRemaining) games remaining"` — drives the message home that clinch math is live. Pull `gamesRemaining` from `ClinchCalculator.defaultGamesRemaining`.

Accessibility: `accessibilityDescription` on each row appends the clinch state — "Clinched", "Eliminated from contention", or omits for `.alive`. The `qualifiedBadge` accessibility label of "Qualified" goes away with the badge.

---

## Open questions — resolved

### 1. `ClinchStatus` shape
**Resolved: 3-case `.clinched / .alive / .eliminated`.** Rejected 4-case `.locked` (1st-seed-locked) because there is no meaningful UI distinction between "1st seed clinched" and "2nd seed clinched" — both qualify for the bracket, both already show CLINCHED. Adding `.locked` introduces decision overhead without user-facing value. Rejected carrying scoring details (max-possible-wins-of-trailing-team, etc.) on the enum because the calculator is the only consumer of those intermediates and they don't surface in the view.

### 2. Backwards compat for `qualified: Bool`
**Resolved: replace entirely, no shim.** Verified `qualified` is only read in `WorldCupView.swift` (4 call sites: `opacity` on row, badge presence, row background tint, accessibility description). No other consumer in the codebase references it. A `var qualifiedForBracket: Bool { clinchStatus == .clinched }` computed property on the model gives any future caller a one-liner equivalent. Cleaner and forces all view sites to consider all three states.

### 3. View rendering of three states
**Resolved: see "View rendering" table above.** Gold-trophy CLINCHED for clinched teams, dim+strikethrough+OUT pill for eliminated, current neutral styling for alive. Removes the misleading green "Q" badge that previously implied math when there was none.

### 4. `gamesRemaining` source — hardcoded `6` vs. derived from `NflStateStore.week`
**Resolved: hardcoded `6`** as `ClinchCalculator.defaultGamesRemaining`. Tradeoffs:
- **For hardcoding**: this is the league's last season; `NflStateStore.currentWeek` doesn't know how many *division* games are left (the league plays a custom division schedule); nothing in the codebase maps NFL week → remaining division games. Hardcoded `6` is unambiguous, matches the user's stated value, and avoids a subtle divide-by-something-undefined bug.
- **Against**: as the season progresses through these final 6 games, the constant becomes wrong and someone has to remember to decrement it. That's a one-line PR per game-week and fits the "feature is sunsetting" framing.
- **Mitigation**: doc-comment on `defaultGamesRemaining` says `"Decrement by 1 each completed regular-season week. Final season: starts at 6, ends at 0."` Plus the calculator accepts `gamesRemaining` as a parameter, so a future consumer can derive it from `NflStateStore` without touching the calculator.

### 5. Math precision — tiebreakers
**Resolved: simplified "max possible wins" model for v1, no tiebreaker simulation.** Tradeoffs:
- **Actual tiebreaker rule** (per user 2026-04-28): total points scored in division games across all 3 seasons. NOT head-to-head. NOT divisional sub-records. Single tiebreaker, easy to understand.
- The richer math would parse `MatchupHistoryRecord`s for cumulative divisional games + projected points-scored swings on the remaining 6 games, then apply the points tiebreaker. The data is available (`MatchupHistoryRecord` has `season + week + isPlayoff + division + winnerRosterId` and a points field).
- Cost: ~150 additional lines of points-projection logic + a new acceptance test surface. Real risk of bugs in the projection step (e.g., what's a "reasonable" point total for a remaining game — average? high-water mark? — none are right).
- v1 approach: assume any of `gamesRemaining` could be a win for any team, ignore points. This produces strictly conservative `.clinched` calls (a team marked clinched truly cannot be caught on wins) and strictly conservative `.eliminated` calls. Some teams that are *actually* clinched/eliminated under tiebreaker math will read as `.alive` in v1 — that's acceptable understatement.
- **Points-tiebreaker simplification**: equal-wins ties at the qualification line stay `.alive` even at `gamesRemaining == 0`. Points can swing in the final game. v1 does not lock based on points.
- Documented as v1 limitation in the calculator's doc-comment. Future enhancement (post-final-season) hook: pass `divisionPoints: [String: Double]` alongside `teams` and resolve ties when wins are mathematically tied.

---

## Acceptance criteria

(Inherited from epic plan, plus F1-specific test criteria.)

- A team is marked `.clinched` only when no team currently below the qualification cutoff (rank 3+) can reach the clinching team's current win count even by winning all `gamesRemaining`.
- A team is marked `.eliminated` when their current wins + `gamesRemaining` is strictly less than the 2nd-seed's current wins.
- Otherwise `.alive`.
- `gamesRemaining` defaults to `6` and is configurable as a parameter to `ClinchCalculator.calculate`.
- `ClinchCalculator` is a pure `enum` with no side effects, no actor isolation, no async work.
- `WorldCupView` visibly distinguishes all three states (badge, color, opacity, accessibility label).
- Manual QA in iPhone 17 Pro simulator: standings render with mathematically defensible clinch states across all 4 divisions, spot-check confirms a non-trivial case.
- **Unit tests pass** for the seven scenarios in Test Plan below.
- Build is clean under Swift 6 strict concurrency — no warnings.
- No regressions in existing `WorldCupView` rendering (rank cells, season breakdowns, division grouping all unchanged).

---

## Test plan

`ClinchCalculator` is pure → unit tests are required. New file `XomperTests/ClinchCalculatorTests.swift`. Each test constructs `[WorldCupTeamRecord]` fixtures and asserts the returned `[String: ClinchStatus]` map.

Helper: a `makeTeam(id:wins:losses:pointsFor:division:)` factory that fills a `WorldCupTeamRecord` with sensible defaults (`losses = 0`, `ties = 0`, `pointsFor = Double(wins) * 100`, `seasonBreakdown = []`, `clinchStatus = .alive`, `divisionName = "Test"`).

Required cases:

1. **`testTopTwoBothAlive_whenChasersCanCatchUp`** — 4-team division: 8-2, 7-3, 6-4, 5-5. `gamesRemaining = 6`. Expect: all four `.alive` (rank-3 with 6+6=12 wins exceeds rank-1's 8; rank-4 with 5+6=11 ≥ 7 second-place's wins).
2. **`testFirstSeedClinched_whenChasersCannotCatch`** — 4-team division: 12-0, 8-4, 5-7, 3-9. `gamesRemaining = 2`. Expect: `.clinched, .clinched, .alive, .eliminated`. (Rank-3: 5+2=7 < rank-2's 8 wins → eliminated wait, 7 < 8 yes eliminated. Rank-4: 3+2=5 < 8 → eliminated. Wait rank-3: 5+2=7 vs cutoff=8 → 7 < 8 → eliminated. Recompute test: prefer 12-0, 8-4, 6-6, 3-9, gamesRemaining=2 → rank-3: 6+2=8 = cutoff 8, NOT strictly less → `.alive`. Rank-4: 3+2=5 < 8 → `.eliminated`. Rank-1: chasers max = max(rank3, rank4) + 2 = 8 — NOT ≥ 12 → `.clinched`. Rank-2: chasers max = 8 — NOT ≥ 8 (need strict greater? Re-read calc: `chasers.contains { $0.wins + gamesRemaining >= team.wins }`. 8 >= 8 is true → `.alive`. So rank-2 is `.alive`. Adjust expected.)
   - Final fixture: 12-0, 8-4, 6-6, 3-9, `gamesRemaining = 2`. Expected: rank-1 `.clinched`, rank-2 `.alive`, rank-3 `.alive`, rank-4 `.eliminated`.
3. **`testSecondSeedClinched_whenAllChasersFarBack`** — 12-0, 10-2, 3-9, 2-10, `gamesRemaining = 6`. Expected: rank-1 `.clinched` (chasers max 9 < 12), rank-2 `.clinched` (chasers max 9 < 10), rank-3 `.eliminated` (3+6=9 < 10), rank-4 `.eliminated`.
4. **`testFifthEliminated_inSixTeamDivision`** — 6-team division: 9-1, 8-2, 7-3, 6-4, 1-9, 0-10. `gamesRemaining = 2`. Expected: rank-1 `.alive` (rank-3: 7+2=9, ≥9 → can catch → alive), rank-2 `.alive`, rank-3 `.alive` (3-seed outside cutoff: 7+2=9 ≥ cutoff 8 → alive), rank-4 `.alive` (6+2=8 = cutoff → alive), rank-5 `.eliminated` (1+2=3 < 8), rank-6 `.eliminated`.
5. **`testTiesAtCutoff_bothAlive`** — 7-3, 7-3, 7-3, 7-3, `gamesRemaining = 1`. All four tied. Expected: all `.alive`. (Rank-1 chasers max = 8 ≥ 7 → alive. Rank-3 max = 8 ≥ cutoff 7 → alive.)
6. **`testZeroGamesPlayed_everyoneAlive`** — 4-team division all 0-0, `gamesRemaining = 6`. Expected: all `.alive`. (Chasers can all match top-2 by going 6-0.)
7. **`testSeasonOver_zeroGamesRemaining`** — 4-team division 8-2, 7-3, 6-4, 5-5, `gamesRemaining = 0`. Expected: rank-1 `.clinched`, rank-2 `.clinched` (6+0=6 < 7), rank-3 `.eliminated` (6+0=6 < 7), rank-4 `.eliminated` (5+0=5 < 7).
8. **`testEmptyDivision_returnsEmptyMap`** — `teams = []`. Expected: `[:]`.
9. **`testSingleTeamDivision_clinched`** — `teams = [makeTeam(id: "u1", wins: 0, losses: 0)]`, `gamesRemaining = 6`. Expected: `["u1": .clinched]`.

Manual QA (post-tests):
- Run `WorldCupView` in iPhone 17 Pro simulator with live league data. Confirm at least one division shows a CLINCHED row, at least one shows an OUT row (if math agrees), and the qualification divider still renders after rank 2.
- Toggle `gamesRemaining` to `0` via a temporary debug override (or just bump `defaultGamesRemaining`) and confirm the view updates as expected. Revert.
- VoiceOver pass: each row reads its rank, name, record, and clinch state.

Build validation:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme Xomper -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

---

## Risks / tradeoffs

- **Adding a test target is net-new infra.** Epic plan listed test infra as out-of-scope, but F1's "unit-testable" criterion forces it. Mitigation: keep the target minimal — XCTest only, no UI tests, no host-launch flags. Future features can reuse the target without re-paying setup cost. Net-positive even if F1 is the only beneficiary day-1.
- **v1 math undercounts H2H-clinched/eliminated cases.** A team that is clinched under Sleeper's tiebreakers but tied in wins with a chaser will read `.alive`. Documented in the calculator and acceptance criteria. Acceptable for a sunsetting feature; not acceptable if a user is explicitly told "you're clinched" by the league commissioner and the app says otherwise — the v1 logic is conservative in both directions, so that mismatch is "app says alive, league says clinched", which is the safer wrong answer.
- **Hardcoded `gamesRemaining = 6` decays week-over-week.** Mitigation: param-able function, doc-commented decrement plan, and the season is short (6 weeks). If a manual decrement is missed, the calculator reads as if more games are left → fewer `.clinched` calls, never false `.clinched` calls. Safe direction.
- **Removing the "Q" badge changes a familiar visual.** Mitigation: replaced with a more informative CLINCHED badge that conveys actual math. The qualification-line divider survives and still anchors the "top 2" mental model.
- **Strikethrough on eliminated team names may look harsh.** Tradeoff accepted — eliminated is a fact; the visual should not euphemize. If user feedback rejects it, one-line revert to opacity-only.
- **Aggregated cross-season W/L is the qualification basis, not single-season.** This is a pre-existing decision in `WorldCupStore.computeStandings`, not something F1 changes. Confirmed against `WorldCupView.seasonsSummary` text "across N seasons". Documented here so the next reader doesn't re-litigate it.

---

## Out of scope

- UI redesign of `WorldCupView` beyond the per-row state badges and the cutoff-divider relabel. No new sections, no new screens, no chart additions.
- Clinch logic for non-divisional standings. Standings (overall league) and Playoff Bracket are not touched.
- Head-to-head tiebreaker math, divisional-only fixture projection, points-tiebreaker simulation.
- Deriving `gamesRemaining` from `NflStateStore` or any league schedule endpoint.
- Backfilling `qualified` for archive views or analytics — `qualified` is fully removed.
- Snapshot tests of `WorldCupView` (no snapshot infra exists; not adding it for F1).
- Refactoring `WorldCupStore.computeStandings` aggregation logic.

---

## Open questions

(None remaining — all five from the stub are resolved above. If execution surfaces a sixth, append it here before flipping status to Ready.)

---

## Skills / Agents to use

- **`ios-specialist` agent**: primary executor. Knows SwiftUI, `@Observable`, Swift 6 strict concurrency, project conventions. Owns Steps 1-10.
- **xcodegen** (CLI): invoked at Step 7 after `Project.yml` test-target addition. Confirm `Xomper.xcodeproj` regenerates cleanly.

---

## Sequencing note

F1 is Phase 0, Day 1 of the epic. Ships independently — no dependencies on F2-F6. F1 can land before, in parallel with, or after F2. Do not flip status to **Ready** until the user confirms the resolved Open Questions above are acceptable.
