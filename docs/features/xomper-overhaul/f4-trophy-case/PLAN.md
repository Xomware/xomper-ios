# Plan: F4 — Profile Creative Section v1 (Trophy Case)

**Status**: Done
**Parent epic**: [../PLAN.md](../PLAN.md)
**Feature ID**: F4
**Issue**: #3b
**Created**: 2026-04-28
**Last updated**: 2026-04-28
**Phase**: 1.5 (Week 1.5)
**Scope**: S
**Dependencies**: F3 (`MyProfileView` is now a tray-header push, not a tab; `.gearshape` toolbar removed; league row taps go through `navStore.select(.standings)`)

## Goal

Add a "Trophy Case" section to `MyProfileView` that surfaces every championship the signed-in user has won across the league chain. Renders between the profile header (and Sleeper-link status) and "My Leagues". Uses `HistoryStore.matchupHistory` exclusively — no new API calls, no schema changes, no backend work. The section is an extracted, self-contained view (`TrophyCaseSection`) so the F7 follow-up can drop a Top Performers card next to it without surgery on `MyProfileView`. Empty state ships with copy: "No championships yet — keep grinding."

## Approach

`MatchupHistoryRecord` already carries `isChampionship: Bool` (set by `HistoryStore` at `convertMatchupResults` based on `week == 16 || week == 17`) and `winnerRosterId: Int?`. That's enough — championship derivation is **flag-based**, not a derived "highest week per season" heuristic. For each matchup where `isChampionship == true` and the signed-in user's `userId` matches the winning side (i.e., `teamAUserId == myUserId && winnerRosterId == teamARosterId`, or the team-B mirror), emit one `Championship` per season. De-duplicate by season (a season can have at most one champ; if both week 16 and week 17 records appear with this user as winner, take the later week — typically the actual title game).

`HistoryStore` gets a small derived helper:

```swift
func championships(forUserId userId: String) -> [Championship]
```

Pure, in-memory, returns chronological newest-first. Returns empty when `matchupHistory` is empty or the user has no titles.

`MyProfileView` injects `HistoryStore` (currently it doesn't — it'll be added to the initializer alongside `authStore`/`userStore`/`leagueStore`/`router`). The new `TrophyCaseSection` view consumes `historyStore` and `authStore.sleeperUserId`, and renders one `TrophyCaseCard` per championship in a vertical stack. Tapping a card is a **noop in v1** — drill-in to matchup history is deferred (logged in Open Questions for F7 / future iteration). Section stays visible even when empty so the "keep grinding" copy is discoverable; we render it only when the user is fully set up (`authStore.isFullySetUp`).

Visual treatment: vertical stack of compact "trophy bar" cards (not large medallions). Each card shows a trophy SF Symbol (`trophy.fill`) tinted `XomperColors.championGold`, the season ("2024 Champion"), the winning team name (from `teamATeamName` / `teamBTeamName` depending on side), and the championship score (e.g. "127.4 – 119.8"). Card surface uses the existing `.xomperCard()` modifier with a thin `championGold` accent stroke (`Color.championGold.opacity(0.35)`, 1pt) to differentiate from generic cards without screaming. Section header label "Trophy Case" matches the typographic treatment of the existing "My Leagues" header.

## Affected files

| File | Change | Why |
|------|--------|-----|
| `Xomper/Features/Profile/MyProfileView.swift` | Add `historyStore: HistoryStore` to init. Insert `TrophyCaseSection(...)` between `sleeperLinkStatus` and `leagueSection`. Update `#Preview` to pass `HistoryStore()`. | Section placement per epic; reuse existing scroll/`VStack(spacing: lg)` layout. |
| `Xomper/Core/Stores/HistoryStore.swift` | Add `func championships(forUserId:) -> [Championship]` derived helper. | Centralize derivation; keep view dumb. Pure read of `matchupHistory`. |
| `Xomper/App/ContentView.swift` | Pass `historyStore` into `MyProfileView(...)` at the call site (line 67). | Wire the new dependency. |

## New files

All under `Xomper/Features/Profile/`:

- `TrophyCaseSection.swift` — section container. Header label + content. Renders empty state, list of `TrophyCaseCard`s, or hides when not signed in / no Sleeper user. Takes `historyStore: HistoryStore` and `userId: String`.
- `TrophyCaseCard.swift` — compact bar card view rendering one `Championship`. Trophy icon + season + team name + score. `.xomperCard()` + gold accent stroke. Tap = noop (v1).
- `Championship.swift` (under `Xomper/Core/Models/`) — `struct Championship: Identifiable, Sendable, Hashable` carrying `season: String`, `leagueId: String`, `week: Int`, `teamName: String`, `pointsFor: Double`, `pointsAgainst: Double`, `opponentTeamName: String`. `id = "\(leagueId)-\(season)-\(week)"`.

## Implementation steps

1. **Create `Championship` model** at `Xomper/Core/Models/Championship.swift`. Plain struct, `Sendable`, `Identifiable`, `Hashable`. Fields per spec above. No Codable needed (derived in-memory, never serialized).
2. **Add `HistoryStore.championships(forUserId:)`** in `HistoryStore.swift` after the existing matchup helpers. Filter `matchupHistory` where `isChampionship == true` AND user is on the winning side. For matchups where both week 16 and 17 contain the same season+leagueId+user as winner, keep only the entry with the higher `week` value (de-dup by `season`, prefer later week). Sort descending by season. Pure function — no side effects, no async.
3. **Build `TrophyCaseCard.swift`**. Static layout: `HStack(spacing: Spacing.md)` of (icon column 32pt) + (`VStack(alignment: .leading)` with season title + team name + opponent line) + spacer + score block right-aligned. Trophy icon: `Image(systemName: "trophy.fill").font(.title2).foregroundStyle(championGold)`. Title: `"\(season) Champion"` `.headline` `.semibold` `textPrimary`. Subtitle: `championship.teamName` `.subheadline` `textSecondary` `lineLimit(1)`. Score: `String(format: "%.1f – %.1f", pointsFor, pointsAgainst)` `.caption` `textMuted` `monospacedDigit()`. Opponent line: `"vs \(opponentTeamName)"` `.caption` `textMuted` `lineLimit(1)`. Wrap in `.xomperCard()`, then overlay `RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg).strokeBorder(XomperColors.championGold.opacity(0.35), lineWidth: 1)`. `accessibilityElement(children: .combine)` + `accessibilityLabel` describing season/team/score.
4. **Build `TrophyCaseSection.swift`**. Header: `Text("Trophy Case").font(.subheadline).fontWeight(.semibold).foregroundStyle(textSecondary).padding(.leading, Spacing.xs)` (mirrors `leagueSection`'s "My Leagues" header). Body: derives `let titles = historyStore.championships(forUserId: userId)`. If `titles.isEmpty` → render empty-state card (single `.xomperCard()` with dimmed trophy icon + "No championships yet — keep grinding." `.subheadline` `textSecondary` centered). Else → `ForEach(titles)` of `TrophyCaseCard(championship:)`. Section is a `VStack(alignment: .leading, spacing: Spacing.sm)` matching league section pattern.
5. **Update `MyProfileView`**:
   - Add `var historyStore: HistoryStore` property after `leagueStore`.
   - In `body`'s root `VStack`, insert `trophyCaseSection` between `sleeperLinkStatus` and `leagueSection`.
   - Add private computed `@ViewBuilder var trophyCaseSection: some View` that renders `TrophyCaseSection(historyStore: historyStore, userId: authStore.sleeperUserId ?? "")` when `authStore.isFullySetUp` and `!authStore.sleeperUserId.isNilOrEmpty`. Otherwise emits `EmptyView()`.
   - Update `#Preview` to construct `HistoryStore()` and pass it.
6. **Wire `ContentView.swift`** at the `.profile` case (line 67) to pass `historyStore: historyStore` into the `MyProfileView` initializer. (After F3 lands and `AppTab.profile` is gone, this call site moves to `MainShell.destinationRoot`'s profile case — the dependency carries over identically.)
7. **Verify history is loaded before the section renders.** `HistoryStore.loadMatchupHistory(chain:)` is invoked from `MatchupHistoryView.onAppear` and `WorldCupStore` flows today. For the Trophy Case to render on a cold visit to Profile, history must already be in memory or load lazily. Add a single `.task` on `TrophyCaseSection` that calls `await ensureHistoryLoaded()` — implemented inline as: if `historyStore.matchupHistory.isEmpty && !historyStore.isLoadingMatchups`, build the league chain via `leagueStore` and call `loadMatchupHistory(chain:)`. **Resolved alternative**: pass `leagueStore` into the section and guard there. Keep this localized — do NOT add a global bootstrap-phase change in this feature.
8. **xcodegen + build**. Run `xcodegen generate` (new files auto-pick-up, but regenerate to be safe). Build with the project sim command. Fix any Swift 6 strict concurrency warnings in `championships(forUserId:)` (should be none — pure sync function on `@MainActor` store).

## View rendering spec

Concrete values, no improvising at execution time.

**Section container**
- Layout: `VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm)`
- Outer padding: none — inherits `MyProfileView`'s `.padding(Spacing.md)` on the scroll content
- Header: `Text("Trophy Case").font(.subheadline).fontWeight(.semibold).foregroundStyle(XomperColors.textSecondary).padding(.leading, Spacing.xs)`

**TrophyCaseCard (populated)**
- Outer modifier: `.xomperCard()` then `.overlay(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg).strokeBorder(XomperColors.championGold.opacity(0.35), lineWidth: 1))`
- Inner: `HStack(spacing: XomperTheme.Spacing.md)`
  - Icon column: `Image(systemName: "trophy.fill").font(.title2).foregroundStyle(XomperColors.championGold).frame(width: 32, alignment: .center).accessibilityHidden(true)`
  - Center `VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs)`:
    - `Text("\(season) Champion").font(.headline).foregroundStyle(XomperColors.textPrimary).lineLimit(1)`
    - `Text(teamName).font(.subheadline).foregroundStyle(XomperColors.textSecondary).lineLimit(1)`
    - `Text("vs \(opponentTeamName)").font(.caption).foregroundStyle(XomperColors.textMuted).lineLimit(1)`
  - Spacer
  - Trailing `VStack(alignment: .trailing, spacing: XomperTheme.Spacing.xs)`:
    - `Text(String(format: "%.1f", pointsFor)).font(.subheadline).fontWeight(.semibold).foregroundStyle(XomperColors.championGold).monospacedDigit()`
    - `Text(String(format: "%.1f", pointsAgainst)).font(.caption).foregroundStyle(XomperColors.textMuted).monospacedDigit()`

**Empty state card**
- Single `.xomperCard()` (no gold stroke — keep dimmed)
- Inner: `VStack(spacing: Spacing.sm)` centered:
  - `Image(systemName: "trophy").font(.title2).foregroundStyle(XomperColors.textMuted)`
  - `Text("No championships yet — keep grinding.").font(.subheadline).foregroundStyle(XomperColors.textSecondary).multilineTextAlignment(.center)`
- `.frame(maxWidth: .infinity)` and vertical padding inherited from `xomperCard`
- Hidden when `!authStore.isFullySetUp` or `sleeperUserId` is nil (section emits `EmptyView()` then)

**Loading state**
- If `historyStore.isLoadingMatchups && historyStore.matchupHistory.isEmpty`, swap the empty-state body for a `ProgressView().tint(championGold)` inside the same card frame. No skeleton shimmer — overkill for v1.

**Accessibility**
- `TrophyCaseCard`: `.accessibilityElement(children: .combine)` + `.accessibilityLabel("\(season) champion. \(teamName), \(pointsFor) to \(pointsAgainst), versus \(opponentTeamName).")`
- Empty card: `.accessibilityLabel("Trophy Case empty. No championships yet.")`
- Tap: not a button in v1 (noop). No tap accessibility traits.

## Resolved open questions

1. **Championship derivation: explicit flag vs. "highest week per season"** → **Use the existing `isChampionship: Bool` flag.** It's already populated by `HistoryStore.convertMatchupResults` (`week == 16 || week == 17`). De-duplicate by `season` preferring the later week to handle multi-week playoff schemas. Heuristic-from-week is unnecessary — flag exists.
2. **Multiple championships: chronological order** → **Newest first** (descending by `season`). Vertical stack, one card per title.
3. **Multiple championships: visual treatment** → **Compact list of bar cards**, NOT large medallions. Scales gracefully if a user has 3+ titles. Medallion treatment was considered for the F7 "Hall of Champions" follow-up, not v1.
4. **Empty state copy** → `"No championships yet — keep grinding."` Confirmed verbatim from epic.
5. **Section placement** → Between `sleeperLinkStatus` and `leagueSection`. Header → Sleeper-link → Trophy Case → My Leagues → Sign Out.
6. **Year/season label** → `"\(season) Champion"` (e.g. "2024 Champion"). Sleeper season strings are 4-digit years; no formatting needed.
7. **Visual treatment** → `XomperColors.championGold` on trophy icon and 0.35-opacity stroke. Score uses `championGold` for `pointsFor`, `textMuted` for `pointsAgainst`. Card surface stays `.xomperCard()` (Midnight Emerald default) — gold accents only.
8. **Tap behavior** → **Noop in v1.** No drill-in. Logged for F7. The card is rendered as a static `HStack`, not a `Button` — keeps it simple and avoids dead tap targets.
9. **Pluggability for F7 Top Performers** → Section is a self-contained view with `historyStore` + `userId` inputs. F7 adds a sibling `TopPerformersSection` view next to it in `MyProfileView`'s VStack. No shared abstraction needed yet — premature factoring. If a third creative section appears, *then* extract a `ProfileCreativeSection` enum.
10. **History loading** → `TrophyCaseSection` triggers `loadMatchupHistory(chain:)` via `.task` if `matchupHistory.isEmpty && !isLoadingMatchups`. Builds the chain from `leagueStore` (already a dep). Doesn't re-trigger when history is already cached. No global bootstrap change.

## Acceptance criteria

- Trophy Case section renders between Sleeper-link status and "My Leagues" in `MyProfileView`.
- For a user with 1+ championships: one card per title, newest season at top, each showing trophy icon + "{season} Champion" + winning team name + opponent + score. Gold accent stroke visible.
- For a user with 0 championships: single empty-state card with trophy outline + "No championships yet — keep grinding."
- For a not-fully-set-up user (no `sleeperUserId`): section is hidden entirely (no header, no card).
- For a fully-set-up user with no history loaded yet: section header renders, body shows `ProgressView` until history loads, then re-renders with results.
- No new API calls beyond what `HistoryStore.loadMatchupHistory` already does. No backend, no Supabase, no schema changes.
- Build clean with Swift 6 strict concurrency on `iPhone 17 Pro` simulator.
- Always-dark mode preserved. Dynamic Type AX5 reflows without truncation cutting off the season label.
- VoiceOver: each card announced as a single combined element with full season/team/score context.
- `TrophyCaseSection` is a self-contained file — adding F7's Top Performers card later requires a single insertion in `MyProfileView`'s `VStack`, no refactoring.

## Test plan

Simulator-first manual QA. No unit test target exists yet; the new helper is small enough that integration testing in the simulator suffices.

**iPhone 17 Pro simulator**
1. Cold launch → sign in → tap avatar in tray header (post-F3) → MyProfileView opens.
2. Section renders between Sleeper-link card and "My Leagues".
3. With current league chain loaded, signed-in user (Dom) should show 0+ championships per actual league history. Confirm card content matches manually-verified Sleeper data for the displayed season.
4. Force empty state: temporarily clear `historyStore.matchupHistory` via `historyStore.reset()` debug action OR sign in as a known non-champion whitelisted user. Verify "No championships yet — keep grinding." renders.
5. Force loading state: clear caches, cold-load profile. Verify spinner appears and resolves.
6. Toggle Dynamic Type to AX5 in simulator → all card text reflows, no truncation on season title.
7. VoiceOver on → swipe through Trophy Case cards. Verify combined accessibility label reads naturally.
8. Sign out → re-login as same user → Trophy Case re-populates correctly.

**Build validation**
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme Xomper -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
Must compile clean, zero new Swift 6 concurrency warnings.

**Manual data spot-check**
- Run app, navigate to Matchup History for season 2024 (or current chain's most recent completed season).
- Confirm the championship game's winner (week 16 or 17) matches what Trophy Case shows for that season.
- If signed-in user did NOT win: Trophy Case should NOT include that season.
- If signed-in user DID win: Trophy Case shows exactly one card for that season with matching team name + scores.

## Risks

- **Risk**: `isChampionship` flag is set on both week 16 AND week 17 records — could double-count.
  **Mitigation**: De-dup by `season` in `championships(forUserId:)`, preferring higher `week`. Implementation step 2 covers this.
- **Risk**: `HistoryStore.matchupHistory` is empty on first profile visit because no other view has triggered `loadMatchupHistory`.
  **Mitigation**: `TrophyCaseSection.task` triggers load if needed. Spinner shown during load.
- **Risk**: League chain isn't built yet when section appears (early in app lifecycle).
  **Mitigation**: Pass `leagueStore` to the section; if chain isn't ready, show empty state silently — don't crash, don't error. Reload-on-appear handles late-arriving data.
- **Risk**: `winnerRosterId` is nil for tied games — championship game with a tie wouldn't qualify.
  **Mitigation**: Acceptable. A tied championship game is theoretically possible but unprecedented in this league. Document as known edge case.
- **Risk**: User changed Sleeper username/userId mid-chain — historical `teamAUserId` may not match current `authStore.sleeperUserId`.
  **Mitigation**: Out of scope for v1. League chain in this app already assumes stable user identity; if it breaks, it breaks elsewhere first. Log as known limitation.
- **Risk**: Theme stroke overlay may visually compete with `.xomperCard()`'s existing border.
  **Mitigation**: Spec uses `0.35` opacity gold stroke; verify in simulator step 6. If too loud, drop to `0.25` or remove and use a left-edge accent bar instead. Visual tweak, not structural.
- **Risk**: Adding `historyStore` to `MyProfileView`'s init breaks the F3 call site if F3 lands first.
  **Mitigation**: F3's MainShell `destinationRoot` for `.profile` already has all stores in scope. Update at the same time as the F3 PR, or rebase F4 onto F3 before opening PR. Step 6 is explicit about this.

## Out of scope

- **Top Performers card** — F7, separate epic. Needs Sleeper matchup `players_points` + `PlayerStatsStore`.
- **Drill-in tap** on a Trophy Case card → matchup history of that championship game. Logged for F7 / future iteration.
- **Large-medallion visual treatment** — bar cards in v1. Medallion gallery is a "Hall of Champions" follow-up.
- **Aggregate stats** ("3-time champion" badge, total titles count, win streak). v1 just lists.
- **Per-season runner-up / playoff appearance badges**. v1 only renders championships.
- **Animation on appear** (gold shimmer, count-up). Static for v1.
- **Caching `championships(forUserId:)` results** — pure derived computation on already-cached `matchupHistory`. No need.
- **Backend persistence of championships**. Not durable; recompute from `matchupHistory` every render.
- **Light mode treatment**. Always dark per project constraints.
- **iPad-specific layout adjustments**. Same VStack scales fine.

## Skills / Agents to use

- **`ios-specialist`** — primary executor. Owns SwiftUI, `@Observable`, Swift 6 strict concurrency, project conventions. Expected duration: 2–4 hours including simulator validation.

## Notes for the executor

- F3 must land before this. `MyProfileView` no longer has the `.gearshape` toolbar (removed in F3) and the league row tap routes via `navStore.select(.standings)` (also F3). Don't reintroduce either.
- The new `Championship` model lives under `Core/Models/` per project structure. Keep it pure — no Codable, no init from `MatchupHistoryRecord` (do that conversion inline in the store helper for clarity).
- Use `.xomperCard()` consistently — don't reinvent the card surface. The gold stroke is an `.overlay` on top of `.xomperCard()`, not a replacement.
- `xcodegen generate` once after step 1 to register the new model file. New files under `Xomper/Features/` are picked up automatically; new files under `Xomper/Core/Models/` are too — but regenerate to be sure.
- Single squashed commit acceptable for autonomous run.
