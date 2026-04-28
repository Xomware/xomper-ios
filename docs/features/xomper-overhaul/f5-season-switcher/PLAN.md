# Plan: Xomper Overhaul — F5: Season Switcher

**Status**: Draft
**Parent epic**: [../PLAN.md](../PLAN.md)
**Feature ID**: F5
**Issue**: #6
**Created**: 2026-04-28
**Phase**: 2 (Week 2)
**Scope**: M
**Dependencies**: F3 (tray must be in place — season switcher likely lives in tray header or per-destination toolbar; sub-plan decides)

## Summary

Generalize the existing per-view season `@State` into a `SeasonStore` exposed via `@Environment(\.selectedSeason)`. History-backed views (Matchups, Matchup History, Draft History, World Cup) read from env. Standings stays current-only by design.

## Files touched

- `Xomper/Core/Stores/SeasonStore.swift` (new) — `@Observable @MainActor`, owns `selectedSeason: String`, `availableSeasons: [String]`
- `Xomper/Core/Extensions/EnvironmentValues+Season.swift` (new) — `@Environment(\.selectedSeason)` key
- `Xomper/App/XomperApp.swift` — inject `SeasonStore` into env at root
- `Xomper/Features/League/MatchupsView.swift` — replace local `selectedSeason` `@State` with env read; delete inline picker (or keep as fallback during migration)
- `Xomper/Features/League/WorldCupView.swift` — accept env season, filter `WorldCupStore.divisions` by season (if multi-season aggregation should respect filter — confirm in sub-plan)
- `Xomper/Features/Profile/MatchupHistoryView.swift` — read season from env
- `Xomper/Features/Profile/DraftHistoryView.swift` — read season from env
- Season picker UI: lives in tray header OR per-destination toolbar. Sub-plan decides.

## Acceptance criteria

- Changing season in one place updates all consumer views simultaneously.
- `SeasonStore.availableSeasons` derives from `HistoryStore.availableMatchupSeasons` ∪ league chain seasons.
- Default `selectedSeason` = current NFL season from `NflStateStore`.
- Standings does NOT subscribe (current-only by design).
- Simulator validation: pick 2024, all history-backed views show 2024 data; pick current, they show current.
- No regressions in `MatchupsView` — week scrolling and expansion still work.

## Open questions (for /plan to drill into)

- Where the picker UI lives (tray header vs. per-view toolbar)
- Whether `WorldCupStore` filters its existing aggregation or recomputes
- Exact env-key vs. store-injection trade-off
- Whether `MatchupsView`'s `expandedWeek` reset behavior on season change is preserved

## Recommended specialist agent

- `ios-specialist` (note: epic plan listed `swift-ios-dev` which does not exist in this project — corrected to `ios-specialist`)
