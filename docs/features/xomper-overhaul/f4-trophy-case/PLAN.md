# Plan: Xomper Overhaul — F4: Profile Creative Section v1 (Trophy Case)

**Status**: Draft
**Parent epic**: [../PLAN.md](../PLAN.md)
**Feature ID**: F4
**Issue**: #3b
**Created**: 2026-04-28
**Phase**: 1.5 (Week 1.5)
**Scope**: S
**Dependencies**: F3 (profile is now a tray-header push, not a tab)

## Summary

Add a Trophy Case section to `MyProfileView` showing championships won by the signed-in user across the league chain. Renders before "My Leagues". Pluggable structure so Top Performers (deferred F7) can slot in later.

## Files touched

- `Xomper/Features/Profile/MyProfileView.swift` — add Trophy Case section between header and league section
- `Xomper/Features/Profile/TrophyCaseCard.swift` (new) — renders championships from `HistoryStore`
- `Xomper/Core/Stores/HistoryStore.swift` — possibly add a derived computed `championships(forUserId:) -> [Championship]` if not already present

## Acceptance criteria

- Trophy Case shows championships won by the signed-in user across the league chain.
- Empty state: "No championships yet — keep grinding."
- Renders before "My Leagues" section.
- Uses existing `HistoryStore.matchupHistory` data — no new API calls.
- Pluggable structure: section is its own view, easy to add Top Performers later (F4-style hook).

## Open questions (for /plan to drill into)

- Exact `Championship` derivation logic from history
- Whether `HistoryStore` exposes a helper or `MyProfileView` derives in-line
- Visual treatment (medal icons, year badges)

## Recommended specialist agent

- `ios-specialist` (note: epic plan listed `swift-ios-dev` which does not exist in this project — corrected to `ios-specialist`)
