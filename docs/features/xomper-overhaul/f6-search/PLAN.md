# Plan: Xomper Overhaul — F6: Search Extension (Player Mode + Grouped Results)

**Status**: Draft
**Parent epic**: [../PLAN.md](../PLAN.md)
**Feature ID**: F6
**Issue**: #2
**Created**: 2026-04-28
**Phase**: 3 (Week 2-3)
**Scope**: M
**Dependencies**: F2 (player wiring must be solid before player search uses it), F3 (tray header search icon entry point), F5 (loosely — search results may want to respect season context for player matches; defer if not needed)

## Summary

Extract `SearchStore` from view-local logic in `SearchView`, add a player search mode, and render grouped results (Users / Leagues / Players). Tray header gets a search icon that pushes the existing `.search` route.

## Files touched

- `Xomper/Features/Home/SearchView.swift` — refactor to consume new `SearchStore`, add player mode
- `Xomper/Core/Stores/SearchStore.swift` (new) — `@Observable @MainActor`, owns query, mode, debouncedText, results, errors. Extracts current view-local logic.
- `Xomper/Features/Home/SearchResultGroup.swift` (new) — grouped result rendering (Users / Leagues / Players sections)
- `Xomper/Features/Shell/TrayHeaderView.swift` — search icon button → `router.navigate(to: .search)`
- `Xomper/Core/Stores/PlayerStore.swift` — verify `search(query:limit:)` is sufficient; no changes expected

## Acceptance criteria

- Mode toggle: User / League / Player. Default User.
- Player mode: typing 2+ chars filters via `PlayerStore.search`, results show name + position + team + thumbnail.
- User and League modes: identical behavior to current.
- Results render as grouped sections when present.
- Tap player → opens player detail OR (if no detail view exists) profile-image-card view (sub-plan decides based on what exists).
- Tap user → push `.userProfile`. Tap league → switch league.
- Tray header search icon pushes `.search` route, drawer closes.
- `SearchStore` is `@MainActor`, debounce logic preserved (500ms).
- Existing user/league search behavior unchanged.

## Open questions (for /plan to drill into)

- Whether a player detail view needs to be built or if grouped result row is the destination
- What happens on no-results in one section but results in another
- Whether mode is exclusive (radio) or inclusive (search-all)

## Recommended specialist agent

- `ios-specialist` (note: epic plan listed `swift-ios-dev` which does not exist in this project — corrected to `ios-specialist`)
