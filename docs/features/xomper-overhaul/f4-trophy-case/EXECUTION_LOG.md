# F4 — Trophy Case Execution Log

**Branch**: `feature/trophy-case`
**Started**: 2026-04-28
**Completed**: 2026-04-28

## Step 1 — Create Championship model
- File: `Xomper/Core/Models/Championship.swift`
- Plain `Identifiable, Sendable, Hashable` struct.
- Fields: `season, leagueId, week, teamName, pointsFor, pointsAgainst, opponentTeamName`.
- `id = "\(leagueId)-\(season)-\(week)"`.
- No Codable — pure derived in-memory model, never serialized.

## Step 2 — Add `HistoryStore.championships(forUserId:)`
- File: `Xomper/Core/Stores/HistoryStore.swift`
- New "Championships (Trophy Case)" section above "Fetch Raw Matchups for Detail".
- Filters `matchupHistory` for `isChampionship == true` AND user as winner side.
- Maps each match to a `Championship`, picking user's side as `team`, opponent as `opponent`.
- Dedupes by `season`, preferring higher `week` (handles multi-week playoff schemas).
- Sorts descending by `season` (newest first).
- Pure sync function on `@MainActor` store — no concurrency warnings.

## Step 3 — Build TrophyCaseCard
- File: `Xomper/Features/Profile/TrophyCaseCard.swift`
- HStack: trophy icon (gold) + leading info column (title/team/opponent) + Spacer + trailing scores.
- `.xomperCard()` + `.overlay(RoundedRectangle.strokeBorder(championGold.opacity(0.35), lineWidth: 1))`.
- `accessibilityElement(children: .combine)` with composed label of season + team + score + opponent.
- Includes `#Preview` with two seeded championships.

## Step 4 — Build TrophyCaseSection
- File: `Xomper/Features/Profile/TrophyCaseSection.swift`
- Header: "Trophy Case" subheadline, semibold, `textSecondary`, padded `.leading` by `Spacing.xs` (mirrors My Leagues header).
- Body: derives `championships(forUserId:)`. Three branches:
  - Loading (history loading + matchupHistory empty): centered ProgressView in card.
  - Empty: trophy outline icon + "No championships yet — keep grinding." centered.
  - Populated: `ForEach(titles)` of `TrophyCaseCard`.
- `.task` calls `ensureHistoryLoaded()` — builds league chain via `leagueStore` if needed and triggers `historyStore.loadMatchupHistory(chain:)`. Bails silently if league not yet loaded.
- Takes `historyStore: HistoryStore`, `leagueStore: LeagueStore`, `userId: String`.

## Step 5 — Update MyProfileView
- File: `Xomper/Features/Profile/MyProfileView.swift`
- Added `var historyStore: HistoryStore` after `leagueStore`.
- Inserted `trophyCaseSection` between `sleeperLinkStatus` and `leagueSection`.
- New computed `@ViewBuilder var trophyCaseSection` renders `TrophyCaseSection` only when `authStore.isFullySetUp` and `sleeperUserId` is non-nil and non-empty (otherwise emits no view).
- `#Preview` updated to pass `HistoryStore()`.
- F3 dependencies (`navStore` param, no `.gearshape` toolbar, `navStore.select(.standings)` row tap) preserved.

## Step 6 — Wire historyStore into MainShell
- File: `Xomper/Features/Shell/MainShell.swift`
- `case .profile:` `MyProfileView(...)` initializer now passes `historyStore: historyStore`.
- (ContentView itself was untouched — F3 made it a thin pass-through; the dependency was already in scope on `MainShell`.)

## Step 7 — History loading
- Already covered by `TrophyCaseSection.task -> ensureHistoryLoaded()`. Re-uses existing `LeagueStore.loadLeagueChain(startingFrom:)` and `HistoryStore.loadMatchupHistory(chain:)` with their built-in caches.

## Step 8 — xcodegen + build
- `xcodegen generate` — clean.
- `xcodebuild -scheme Xomper -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` — `BUILD SUCCEEDED`.
- Only warning in output is the pre-existing `appintentsmetadataprocessor` "no AppIntents.framework dependency found" (unrelated to F4).
- Zero new Swift 6 strict-concurrency warnings.

## Simulator validation
- Booted iPhone 17 Pro (iOS 26.2), installed fresh build, launched.
- App reaches auth gate cleanly. Live profile validation past the auth gate requires real sign-in credentials and is left for manual QA per the test plan.

## Deviations from plan
- None functional. Minor: passed `leagueStore` directly into `TrophyCaseSection` for the in-section history bootstrap (the plan offered this as an explicit "resolved alternative" in step 7 — picked it because it keeps the section self-contained).
- ContentView call site (plan step 6) was not changed because F3 had already collapsed ContentView to a pure pass-through; the equivalent wiring lives on `MainShell.destinationRoot`'s `.profile` case (which the plan explicitly anticipated).

## Status
- Plan flipped to `Done`.
