# Plan: Xomper Overhaul — F3: League Nav Tray + Profile-on-Tray-Header

**Status**: Draft
**Parent epic**: [../PLAN.md](../PLAN.md)
**Feature ID**: F3
**Issues**: #1, #3a
**Created**: 2026-04-28
**Phase**: 1 (Week 1)
**Scope**: L
**Dependencies**: F1, F2 (clean baseline before structural rewrite — not a hard dep, but desirable)

## Summary

Replace the `TabView` shell with a Xomify-style slide-in left drawer owned by a new `NavigationStore`. Sectioned tray (Compete / History / Roster / Meta + pinned Settings footer). Profile becomes a tray-header card (avatar + name + chevron). `AppTab.home` and `AppTab.profile` go away.

## Files touched

- `Xomper/App/ContentView.swift` — replace `TabView` body with `LeagueShellView`
- `Xomper/Navigation/AppTab.swift` — delete enum (or shrink to a single `.shell` placeholder during migration; resolve in sub-plan)
- `Xomper/Navigation/AppRouter.swift` — remove `selectedTab`, `switchTab` API; keep `path` + `navigate`
- `Xomper/Navigation/NavigationStore.swift` (new) — `@Observable @MainActor`, owns `isDrawerOpen`, `selectedDestination`
- `Xomper/Features/Shell/LeagueShellView.swift` (new) — root shell with drawer + content area
- `Xomper/Features/Shell/TrayView.swift` (new) — drawer container with header + sections + footer
- `Xomper/Features/Shell/TraySection.swift` (new) — section + item view models
- `Xomper/Features/Shell/TrayHeaderView.swift` (new) — profile card + search icon
- `Xomper/Features/League/LeagueDashboardView.swift` — strip outer wrapper; tray now drives destination, but inner tab content (StandingsView, MatchupsView, etc.) gets rendered directly. Resolve in sub-plan: delete `LeagueDashboardView` entirely vs. keep as a destination wrapper.
- `Xomper/Features/Home/HomeView.swift` — fold into tray header / Compete section, then delete (or repurpose; resolve in sub-plan)
- `Project.yml` — none needed (xcodegen picks up new files under `Xomper/`)

## Acceptance criteria

- Edge drag from left or tap on tray-header avatar opens the drawer.
- Drawer width: `min(screenWidth * 0.82, 320)`; scrim: `Color.black.opacity(0.45)`; animation: `.easeInOut(duration: 0.25)`.
- Sections render: Compete, History, Roster, Meta. Settings pinned at footer.
- Selected destination shows visual selection state (icon tint, weight, chevron, gradient bg) per Xomify pattern.
- Profile card in header: avatar + display name + chevron. Tap pushes `MyProfileView` and closes drawer.
- Drop `AppTab` cleanly — no dead code, no orphaned routes.
- Simulator validation: iPhone 17 Pro AND iPad (one of the available iPad simulators). Drawer behaves identically on both per Xomify (no adaptive split).
- Dark mode only, Midnight Emerald palette, 8pt spacing, Dynamic Type.
- Swift 6 strict concurrency — no warnings.

## Open questions (for /plan to drill into)

- Exact destination list and order
- What happens to `AppTab` (delete vs. trivial enum)
- What happens to `HomeView` content
- Edge-drag gesture conflict with `NavigationStack` swipe-to-pop
- iPad-specific layout decisions

## Recommended specialist agent

- `ios-specialist` (note: epic plan listed `swift-ios-dev` which does not exist in this project — corrected to `ios-specialist`)
