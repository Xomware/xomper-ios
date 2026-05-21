# Plan: Season Refocus — F2 Landing Page MVP

**Epic**: season-refocus
**Phase**: 2 of 4
**Status**: Ready
**Created**: 2026-05-21
**Last updated**: 2026-05-21
**Depends on**: F1 (Tray Surgery) — merged
**Repos touched**: xomper-ios

---

## Summary

Add a new `TrayDestination.landing` case and a new `LandingView` composing four cards: headline AI Review (hero, tappable to detail), Announcements (hardcoded `LeagueAnnouncements.current` for v1), scrolling standings bar (horizontal team chips with W-L, offseason empty state), and this-week matchups (scoreboard style, offseason empty state). Flip `NavigationStore.currentDestination` default from `.standings` → `.landing`. Migrate `AIReviewHomeCard` out of `SearchView` (the AI hero on Landing takes its place). Pin a new "Home" section at the top of the drawer holding the Landing entry. Success = cold-open lands on a new home screen that reads as "what's coming next" with the freshest AI report in hero position.

---

## Approach

Implements **Q4 Option A (static stripe order)** and **Q5 Option A (.landing becomes default)** from the brainstorm. Time-aware card priority (Q4 Option B) is explicitly deferred per the epic out-of-scope list — v1 ships a locked static order. Each card is its own SwiftUI view file for testability and clarity. All data sources reuse existing stores (`AIReviewStore`, `LeagueStore`, `StandingsBuilder`, `NflStateStore`); the only new persistent value is `Matchup` data for the current week, which already has a Sleeper API route + decoded model — fetched lazily inside the matchups card via a small task-scoped state holder. No new top-level store, no new networking layer.

Visual reference: match the recent **DraftOrderView Live tab** chip-on-card pattern — `XomperColors.bgCard` rounded rect, championGold accent line/border on the hero, caption2 uppercased chip headers, `.pressableCard` button style throughout.

---

## Resolved Design Questions

These were open in the F2 stub; all locked below before any code is written.

### 1. Headline AI Review card — which report wins when multiple exist?

**Pick: Option A — most recent across all types.** Reuses the existing `AIReviewStore.mostRecentLatest` accessor (already used by `AIReviewHomeCard`). Freshest content wins; the user shouldn't see a stale postDraft once a Week 4 weekly lands. The hero card flavors itself via the report's `reportType` chip (postDraft / Preseason / Weekly), so the type is never hidden — just not prioritized.

### 2. Announcements data shape

Pinned. Both types live in a single new file `Xomper/Features/Landing/LeagueAnnouncement.swift`:

```swift
struct LeagueAnnouncement: Identifiable, Sendable {
    let id: UUID = UUID()
    let title: String           // "Draft is July 6"
    let body: String            // "6:30pm ET sharp. ~1 day per pick."
    let priority: Priority      // .critical, .info
    let expiresAt: Date?        // nil = always show
}
enum Priority { case critical, info }

enum LeagueAnnouncements {
    static let current: [LeagueAnnouncement] = [ /* 2-3 entries */ ]
}
```

v1 ships 2-3 entries:
- **Critical**: "Draft is July 6" — body: "6:30pm ET sharp. ~1 day per pick. Make sure you can be available for autopick fallback."  expiresAt: 2026-07-07.
- **Info**: "Season starts Sept 8" — body: "Week 1 kicks off Mon Sept 8. Lineups lock at first kickoff."  expiresAt: 2026-09-09.
- (Optional) **Info**: "Rule Proposals open" — body: "Vote on this season's open proposals before draft day."  expiresAt: 2026-07-06.

`AnnouncementsCard` filters out entries where `expiresAt != nil && expiresAt < Date()`, sorts critical-first then by insertion order, and renders the resulting list. If the filtered list is empty, the card renders zero-height (no empty state — just absent).

### 3. Scrolling standings bar — data source

Reuse `StandingsBuilder.buildStandings(rosters:users:league:)` from `Xomper/Core/Stores/StandingsBuilder.swift` (lines 9-62). Same pure-function call `StandingsView.buildStandings()` already uses. Inputs (`leagueStore.myLeague`, `myLeagueRosters`, `myLeagueUsers`) are already loaded by `MainShell.bootstrapPhase1/2`, so no extra fetch — the card just maps the resulting `[StandingsTeam]` into a horizontal chip layout.

### 4. This-week matchups — data source

Use `SleeperAPIClient.fetchLeagueMatchups(_:week:)` (existing — `Xomper/Core/Networking/SleeperAPIClient.swift:89-91`) with `nflStateStore.currentWeek`. Pair raw matchups via the existing static helper `HistoryStore.pairMatchupsStatic` (returns `[MatchupPair]` — see `HistoryStore.swift:791-794`). Resolve owner names + team names from `leagueStore.myLeagueUsers` + `myLeagueRosters` the same way `MatchupCardView` does inside `MatchupsView.swift`.

To avoid a new global store, `ThisWeekMatchupsCard` keeps its own `@State` for `[MatchupPair]` + `isLoading` + `error`, loads on `.task` keyed by `(leagueId, week)`, and exposes a `refresh()` method the LandingView can call from pull-to-refresh.

### 5. Offseason detection

`nflStateStore.isRegularSeason` (returns `seasonType == "regular"`). When false, the standings bar and this-week matchups card render empty states; the AI hero + announcements always render regardless.

- Standings bar offseason copy: "Standings unlock once Week 1 kicks off."
- Matchups card offseason copy: "This week's matchups appear here once games begin."

### 6. Card priority order in offseason vs. in-season

**Static for v1.** Locked order top-to-bottom: `[Headline AI, Announcements, Standings Bar, This-Week Matchups]`. Offseason cards still render — just in their empty states — so vertical layout is consistent across calendar phases. Time-aware reordering (Q4 Option B) deferred per epic out-of-scope.

### 7. Pull-to-refresh behavior

Yes. `LandingView` exposes a single `.refreshable` modifier on its outer `ScrollView`. The refresh handler calls all four data-source refreshes in parallel:

```swift
async let ai:       () = aiReviewStore.refresh()         // existing
async let nfl:      () = nflStateStore.fetchState()      // existing
async let league:   () = leagueStore.loadMyLeague()      // existing — rebuilds standings inputs
async let matchups: () = matchupsCardRef.refresh()       // delegate to the card's own task
_ = await (ai, nfl, league, matchups)
```

The matchups card refresh is wired by reading a private `@State var matchupsCardController = ThisWeekMatchupsController()` (a tiny `@Observable` shim with `var lastRefreshToken = UUID()` — bumping the token re-triggers the `.task(id:)` inside the card). Alternative: pass an `await` closure to the card; the controller approach keeps the card self-contained and is the cleaner SwiftUI pattern.

### 8. Empty state for the headline AI card (cold-start)

When `aiReviewStore.mostRecentLatest == nil`: render a small placeholder hero card (same outer frame + championGold border, smaller content area) with title **"First report drops after draft day"** and body **"AI reviews land here once the season kicks off — check back after July 6."** Icon: `sparkles` muted. This replaces the current `AIReviewHomeCard` behavior of rendering `EmptyView` — Landing always needs *something* in the hero slot or the page feels broken.

### 9. Tray ordering after F2

Read `DrawerView.swift` lines 27-50 — sections currently are: Compete / History / Roster / League (+ optional Admin). Landing goes in a **new section "HOME"** pinned at the very top, above Compete. Section title uppercased in caption (same style as existing sections via `sectionView(_:)` line 134-142). Just one entry: `.landing`. This is purely additive — does not require swapping anything out of the existing Compete entries (`.standings` stays where it is for users navigating manually).

Final drawer order:
- **HOME**: `.landing`
- **COMPETE**: `.standings`, `.matchups`, `.playoffs`
- **HISTORY**: `.draftHistory`, `.matchupHistory`, `.worldCup`
- **ROSTER**: `.myTeam`, `.taxiSquad`, `.teamAnalyzer`
- **LEAGUE**: `.payouts`, `.aiReview`, `.rulebook`, `.scoring`, `.leagueSettings`, `.ruleProposals`, `.draftOrder` (post-F1 order)
- **ADMIN** (conditional): `.admin`
- **Settings** (pinned footer): unchanged

Tray entry count: 17 → 18 (within tolerance — epic risk callout was about 19+, this stays under).

### 10. SearchView changes — exactly what's removed

`SearchView.swift` (lines 41-45) injects `AIReviewHomeCard` into the body's top `VStack`. Remove the `AIReviewHomeCard(...)` call and the surrounding zero-overhead — leave the rest of the view intact. The card-priming `.task` block at lines 53-61 (the three `aiReviewStore.loadLatest(type:)` calls) also goes — Landing's `.task` now owns that bootstrapping.

The `aiReviewStore` constructor parameter on `SearchView` stays (it's no longer needed by Search itself, but it's invoked from `MainShell.destinationView(for:)` at line 401-408 with the store injected; keeping the parameter avoids a churnier diff). Mark the unused param with a `// retained for future search-AI integration` line comment.

**Decision**: `AIReviewHomeCard.swift` stays in the codebase as-is — it's still useful as a reusable component, and `HeadlineAIReportCard` is the hero variant (separate file, distinct visual treatment). No deletion. No mutation. No new style parameter on the existing card.

---

## Affected Files / Components

| File / Component | Change | Why |
|------|--------|-----|
| `Xomper/Features/Landing/LandingView.swift` | **NEW** — root view composing 4 cards in a single `ScrollView` with `.refreshable`. | Top-level surface for the new default destination. |
| `Xomper/Features/Landing/HeadlineAIReportCard.swift` | **NEW** — hero variant of the AI report card (larger padding, championGold accent stripe, full-bleed body preview to 3 lines, separate empty-state card when no report). | Distinct visual weight from `AIReviewHomeCard`. Tap → `navStore.select(.aiReview)` + `router.navigate(to: .aiReportDetail(reportId:))`. |
| `Xomper/Features/Landing/LeagueAnnouncement.swift` | **NEW** — struct, Priority enum, hardcoded `LeagueAnnouncements.current` array. | Locked data shape for v1 announcements. |
| `Xomper/Features/Landing/AnnouncementsCard.swift` | **NEW** — renders filtered announcements list. Critical entries get a red accent stripe; info entries plain bgCard. | Static league reminders surface. |
| `Xomper/Features/Landing/StandingsScrollBar.swift` | **NEW** — horizontal `ScrollView` of avatar + team name + "W-L" chips. Tap a chip → `router.navigate(to: .teamDetail(rosterId:))`. Offseason empty state when `!nflStateStore.isRegularSeason`. | League-heartbeat surface; offseason-aware. |
| `Xomper/Features/Landing/ThisWeekMatchupsCard.swift` | **NEW** — scoreboard list of paired matchups for `nflStateStore.currentWeek`. Holds its own `@State` for `[MatchupPair]`, `isLoading`, `error`, refresh token. Offseason empty state. | This-week scoreboard; self-loading. |
| `Xomper/Features/Shell/TrayDestination.swift` | Add `case landing`; add `title` → `"Home"`; add `systemImage` → `"house.fill"`. Update file-top section comment to add "Home: landing". | New tray destination wired in. |
| `Xomper/Features/Shell/DrawerView.swift` | Add new `TraySection(title: "Home", entries: [.landing])` at index 0 of the `sections` array. | Drawer renders the new section at top. |
| `Xomper/Features/Shell/NavigationStore.swift` | Line 22: `var currentDestination: TrayDestination = .standings` → `= .landing`. Update doc comment on line 21. | Cold-open default. |
| `Xomper/Features/Shell/MainShell.swift` | Add `case .landing:` to the `destinationRoot` switch (after the existing first case). Wire `LandingView` with the stores it needs: `leagueStore`, `authStore`, `nflStateStore`, `aiReviewStore`, `navStore`, `router`. | Renders Landing when selected. |
| `Xomper/Features/Home/SearchView.swift` | Remove `AIReviewHomeCard(...)` injection (lines 41-45). Remove the prime `.task` block (lines 53-61). Leave the rest of the view intact. | Search reverts to pure search; AI hero moved to Landing. |
| `XomperTests/LandingViewTests.swift` (optional) | **NEW** — one-shot smoke test that instantiates `LandingView` with stub stores and asserts it renders without throwing. Plus a `LeagueAnnouncement` filter test for expiry. | Cheap regression safety. |
| `Xomper.xcodeproj/project.pbxproj` | Regenerated by `xcodegen generate`. | New `.swift` files must register with the target. |

**Files explicitly NOT touched** (verified by grep):
- `Xomper/Features/AIReview/AIReviewHomeCard.swift` — unchanged; remains a reusable component.
- `Xomper/Features/League/StandingsView.swift` — F4 scope; this PR leaves it alone.
- `Xomper/Features/League/MatchupsView.swift` — unchanged; the Landing card reuses pairing logic but does not push into this view.
- `Xomper/Navigation/AppRouter.swift` — no new route. Landing pushes to `.aiReportDetail`, `.teamDetail` — both already exist.
- `Xomper/Core/Networking/SleeperAPIClient.swift` — uses existing `fetchLeagueMatchups` route.

---

## Implementation Steps

Order is dependency-driven. Each step is a discrete commit-worthy unit; the build should pass after every step.

- [ ] **Step 1 — Data shapes first.** Create `Xomper/Features/Landing/LeagueAnnouncement.swift` with the `LeagueAnnouncement` struct, `Priority` enum, and `LeagueAnnouncements.current` hardcoded array (2-3 entries with the exact copy from Resolved Q2). No view code yet.

- [ ] **Step 2 — Tray destination plumbing.** Edit `Xomper/Features/Shell/TrayDestination.swift`: add `case landing` to the enum, plus its `title` (`"Home"`) and `systemImage` (`"house.fill"`) switch arms. Update the file-top section comment to add `- Home: landing`. Build green (Landing still has no view, but the enum + nav store changes compile).

- [ ] **Step 3 — Cold-open default flip.** Edit `Xomper/Features/Shell/NavigationStore.swift` line 22: change default to `.landing`. Update the doc comment on line 21 to reflect "Default landing destination on cold open is `.landing`." App will *crash* on launch until Step 6 wires the switch case — proceed straight to Step 4.

- [ ] **Step 4 — Stub `LandingView`.** Create `Xomper/Features/Landing/LandingView.swift` with a minimal body that returns `Text("Landing")` placeholder + the constructor signature it will need (`leagueStore`, `authStore`, `nflStateStore`, `aiReviewStore`, `navStore`, `router`). This unblocks the next step.

- [ ] **Step 5 — Drawer entry.** Edit `Xomper/Features/Shell/DrawerView.swift`: prepend a new section `TraySection(title: "Home", entries: [.landing])` to the `sections` array (index 0). Confirm the rest of the section order is unchanged.

- [ ] **Step 6 — Wire MainShell switch.** Edit `Xomper/Features/Shell/MainShell.swift`: add `case .landing:` to `destinationRoot` (place it before `.standings` so reading the switch follows drawer order). Instantiate `LandingView` with the stores. **Regen project** (`xcodegen generate`) and **build green** — app now boots to Landing with the placeholder text.

- [ ] **Step 7 — `HeadlineAIReportCard`.** Create `Xomper/Features/Landing/HeadlineAIReportCard.swift`. Mirror `AIReviewHomeCard`'s tap action (select `.aiReview` then push `.aiReportDetail`), but use a larger frame, 3-line preview snippet, championGold gradient overlay, and the empty-state placeholder card when `store.mostRecentLatest == nil`. Plumb the prime task into `LandingView.task` (the three `aiReviewStore.loadLatest(type:)` calls).

- [ ] **Step 8 — `AnnouncementsCard`.** Create `Xomper/Features/Landing/AnnouncementsCard.swift`. Filter `LeagueAnnouncements.current` against `Date()` via `expiresAt`, sort critical-first, render. Critical entries get a left-edge red accent bar (`XomperColors.accentRed` 3pt wide); info entries are plain `bgCard`. Render zero-height when the filtered list is empty.

- [ ] **Step 9 — `StandingsScrollBar`.** Create `Xomper/Features/Landing/StandingsScrollBar.swift`. Build `[StandingsTeam]` via `StandingsBuilder.buildStandings` on appear + on `myLeagueRosters/Users` changes (same `.task(id:)` + `.onChange(of:)` pattern as `StandingsView.swift:50-58`). Render horizontal `ScrollView` of avatar + team name + "W-L" pill. Tap → `router.navigate(to: .teamDetail(rosterId: team.rosterId))`. When `!nflStateStore.isRegularSeason` OR the standings array is empty: render the offseason empty state copy.

- [ ] **Step 10 — `ThisWeekMatchupsCard`.** Create `Xomper/Features/Landing/ThisWeekMatchupsCard.swift`. Holds `@State var pairs: [MatchupPair]`, `@State var isLoading`, `@State var error`, `@State var refreshToken: UUID`. `.task(id: "\(leagueId)-\(week)-\(refreshToken)")` calls `SleeperAPIClient.fetchLeagueMatchups(_:week:)` directly (instantiate a `SleeperAPIClient()` locally — same approach `HistoryStore` takes). Pair via `HistoryStore.pairMatchupsStatic`. Render `[MatchupPair]` as a scoreboard list (team A / VS / team B per row, point totals if present else "—"). When `!nflStateStore.isRegularSeason`: offseason empty state copy. Expose a `refresh()` method that bumps `refreshToken`.

- [ ] **Step 11 — Compose `LandingView` for real.** Replace the placeholder with the actual layout: `ScrollView` → `VStack(spacing: XomperTheme.Spacing.md)` containing the four cards in static order (Headline AI → Announcements → Standings Bar → This-Week Matchups). Wire `.refreshable` to call the parallel refresh closures from Resolved Q7. Set `.navigationTitle("Home")` and the standard dark `toolbarColorScheme`.

- [ ] **Step 12 — Cleanup `SearchView`.** Edit `Xomper/Features/Home/SearchView.swift`: remove `AIReviewHomeCard(...)` injection (lines 41-45) and the prime `.task` block (lines 53-61). Add a `// retained for future search-AI integration` line comment next to the `aiReviewStore` constructor parameter to flag why it's kept.

- [ ] **Step 13 — Regen + build.** Run `xcodegen generate`. Build green via:
      `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Xomper -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

- [ ] **Step 14 — Optional smoke test.** Add `XomperTests/LandingViewTests.swift` with (a) a `LeagueAnnouncement` expiry filter test and (b) a render-doesn't-throw smoke test using stub stores. Run the full test target.

- [ ] **Step 15 — Manual QA pass** (see Test Plan).

- [ ] **Step 16 — Commit + PR.** Single commit. PR description: `Closes #<issue>`; mention "F2 of season-refocus epic". No co-author tag.

---

## Test Plan

**Build**: green via the xcodebuild command above.

**Automated**:
- `LeagueAnnouncementTests` (if added in Step 14): expired announcements filtered out; critical sorts before info; never-expiring entries always present.
- Existing `AIReviewStoreTests` etc. continue to pass.

**Manual QA** on iPhone 17 Pro sim (90-second pass):

1. **Cold launch**: app boots to a "Home" screen with the new four-card layout. No "Standings" first impression.
2. **Hero card** renders the most recent AI report (or, if no reports yet, the "First report drops after draft day" placeholder). Tap → drawer-side selection moves to `.aiReview` and detail view pushes in the same animation envelope. Back button returns to Landing (not Standings) — verify the navStore stays on `.aiReview` not `.landing` after detail is dismissed.
3. **Announcements** show the 2-3 hardcoded entries. Critical entries have the red accent stripe. Past-`expiresAt` entries are absent.
4. **Standings bar** renders in current season: horizontal scroll of all 12 team chips with avatar + team name + W-L. Tap a chip → team detail pushes. Offseason copy ("Standings unlock once Week 1 kicks off") is verified by temporarily forcing `nflStateStore.nflState?.seasonType = "off"` in a debug build (or trust the empty-state branch via code review since we're literally in offseason).
5. **This-week matchups**: in regular season, scoreboard shows current week's 6 matchups. In offseason (today's reality), the empty-state copy renders ("This week's matchups appear here once games begin").
6. **Pull to refresh** on the Landing scroll view triggers a single spinner; all four data sources refresh in parallel (AI store, NFL state, league reload, matchups card). Verify no flash of empty hero during the refresh — the prior values stay rendered until the new ones land.
7. **Drawer**: open it; new "HOME" section is pinned above "COMPETE" with the single "Home" row. "Home" row is highlighted (`isSelected`) on cold open. Tap "Standings" → standings still renders correctly (no regression from default flip).
8. **Search**: navigate to Search (existing entry point from `HeaderBar`); confirm the AI banner card is *gone* and the search field sits directly under the nav title.
9. **No regressions**: spot-check Matchups, Playoffs, Team Analyzer, AI Review (full archive), Admin, Settings.

---

## Acceptance Checklist

- [ ] Cold launch lands on the new `LandingView` (not `StandingsView`).
- [ ] Drawer has a new "HOME" section at the top with a single "Home" entry mapped to `.landing`.
- [ ] Landing renders four cards in this order: Headline AI Review → Announcements → Standings bar → This-week matchups.
- [ ] Headline AI card shows the most recent report (any type) and pushes to `AIReviewDetailView` on tap.
- [ ] Headline AI card shows the cold-start placeholder when `aiReviewStore.mostRecentLatest == nil`.
- [ ] `LeagueAnnouncements.current` hardcoded array exists with 2-3 entries (draft date + season start at minimum); expired entries are filtered.
- [ ] Standings scroll bar tapping a chip pushes the team detail route.
- [ ] In offseason, standings bar + matchups card render empty-state copy (not crash, not blank space).
- [ ] In regular season, standings bar shows all 12 teams and matchups card shows the 6 current-week matchups.
- [ ] Pull-to-refresh on Landing reloads all four data sources in parallel.
- [ ] `SearchView` no longer renders `AIReviewHomeCard`; the search field is at the top of the body.
- [ ] `xcodegen generate` is committed (`project.pbxproj` diff is part of the PR).
- [ ] Build is green via the canonical xcodebuild command.
- [ ] All `XomperTests` pass.
- [ ] No regressions across other tray destinations.

---

## Out of Scope

- Time-aware Landing card priority function (deferred per epic — v1 ships static order).
- News stripe / Sleeper trending feed integration.
- Push notifications for new Landing cards.
- Admin UI for editing announcements (v2; v1 is hardcoded).
- Scores card deep-linking to the existing `.matchups` view (deferred; matchups card is read-only for v1).
- Spotlight rotator / feature CTAs (deferred — would belong to a v2 "Spotlight" card).
- Persisting `NavigationStore.currentDestination` across app launches (separate concern; brainstorm Q10).
- Any change to `StandingsView` itself (F4 owns the offseason wipe of the dedicated screen).
- Any change to `AIReviewHomeCard.swift` internals — it stays as a reusable component.
- Renaming `AIReviewHomeCard` or factoring shared styling into a `HomeCardStyle` enum.

---

## Risks / Tradeoffs

- **Default destination flip is high blast radius.** Mitigation: Landing renders gracefully when no AI report exists (cold-start placeholder card), and the standings/matchups cards both have offseason empty states. Worst case is sparse-but-functional. Fallback: if Landing crashes on first launch, the user can manually select another destination from the drawer (which itself does not depend on `.landing` being viable).
- **`SearchView` losing the AI banner is a visible behavior change for any user who navigates to Search expecting to see latest reports.** Accepted — the AI surface is moving to a more prominent place (Landing), not disappearing.
- **`ThisWeekMatchupsCard` is the only Landing component that fetches over the network on appear.** Cold-start cost is one HTTP call (`/league/<id>/matchups/<week>`) — already exercised by `HistoryStore.fetchRawMatchups`. The card uses `.task(id:)` so it re-fires only on leagueId/week/refreshToken change; no polling.
- **Tray entry count rises by 1.** Acceptable — still under the 19-entry threshold flagged in the epic risks. F4 will add one more (`.archive`), which is still within tolerance.
- **`HistoryStore.pairMatchupsStatic` is accessed by a feature view directly** rather than through a store method. This is mildly anti-architectural (views talking to "Static" helpers), but the alternative (introducing a new store or extending `HistoryStore` to own current-week state) is heavier for v1. Accepted; can refactor if a second consumer appears.
- **`AIReviewHomeCard` becomes orphaned (used only from `SearchView`, then no longer)**. Per Resolved Q10 we keep it — flagged with a `retained for future search-AI integration` comment so a future cleanup pass knows the intent.
- **Critical-tag styling on announcements could clash visually with championGold-tinted hero card above it.** Mitigation: red accent is a 3pt left bar only, not a full background — should read as urgent without competing with the hero.

---

## Open Questions

None blocking. All design questions resolved above. Potential v2 follow-ups (not gating this PR):

- [ ] Should expired announcements still render dimmed for a few days post-expiry, or hard-cut at `expiresAt`? (v1: hard-cut.)
- [ ] Should the standings scroll bar show a small playoff-cutoff visual (a vertical bar between 6th and 7th)? (v1: no — flat list.)
- [ ] Should the matchups card highlight the current user's matchup? (v1: no — uniform scoreboard styling.)

---

## Skills / Agents to Use

- **ios-specialist**: invoke directly via `/execute f2-landing` once status flips to Ready. This is the primary executor — file count (~6 new + 5 modified) is large enough to warrant a single dedicated agent rather than ad-hoc edits.
- **swiftui-reviewer** (if available): post-`/execute` review pass since this touches real view composition + theme adherence on a brand-new top-level surface.
- **No researcher**: data sources and patterns already mapped in this plan; nothing to discover.
- **No backend-specialist**: zero backend changes.

---

## Notes for the Executor

- Stick to the dependency order in Implementation Steps — Step 3 (default flip) intentionally precedes Step 6 (switch case) for chronological clarity, but the build will not be green between them. Land them in the same commit if you prefer, but do not commit Step 3 alone.
- Every new view file must include a `#Preview` block with stub stores in a `NavigationStack`, matching the existing convention (see `MatchupsView.swift:330-340`).
- All new views must respect the dark-only theme — no `.preferredColorScheme(.light)` in previews, no hardcoded white/black colors. Use `XomperColors` exclusively.
- Spacing must use `XomperTheme.Spacing.*` constants — no raw `.padding(16)` literals.
- All async work on `@MainActor` (default for `View`s and `@Observable` stores).
- After adding new Swift files: `xcodegen generate` then commit the `project.pbxproj` diff in the same commit as the source files.
