# Epic Plan: Season Refocus + Landing Page

**Status**: Ready
**Created**: 2026-05-21
**Last updated**: 2026-05-21
**Brainstorm**: `docs/features/season-refocus/BRAINSTORM.md`
**Related epic**: `docs/features/ai-review/` (F0/F1/F2/F3 shipping in parallel)

---

## Orchestration

Strict sequential — F1 → F2 → F3 → F4. Each sub-feature gets its own `/plan` pass before `/execute`.

```
F1 (Tray Surgery, S)
  │  docs/features/season-refocus/f1-tray-surgery/PLAN.md
  ▼
F2 (Landing Page MVP, M-L)
  │  docs/features/season-refocus/f2-landing/PLAN.md
  ▼
F3 (Draft Tab Restructure, M)
  │  docs/features/season-refocus/f3-draft-tab/PLAN.md
  ▼
F4 (Standings Wipe + Archive, M)
     docs/features/season-refocus/f4-standings-archive/PLAN.md
```

All 4 sub-feature stubs are `Status: Draft`. Run `/plan f<n>-<name>` against each in order to flesh out scope, architecture, file-by-file steps, and test plan, then flip to `Ready` before `/execute`.

---

## Summary

It's offseason May 2026. The app still looks like mid-2025 — Standings shows stale final records, Draft History conflates last year with the upcoming July 6 draft, Reverse-HPP sits in League nav as if it were a committed feature, and AI Reviews (the big new content investment) get a 60pt strip above the search box.

This epic refocuses the app forward into the 2026 season: a new Landing Page becomes the default destination with AI Reviews as headline news, the Draft tab gets per-year sub-tabs, Standings goes live-only with an offseason countdown, and historical content moves into a new Archive section. Success = on cold open, the app feels like *what's coming next* rather than *what just happened*.

---

## Approach

Phased sub-features under one epic — orchestrate-friendly. Four sub-features, sequenced strictly smallest-first. Each gets its own `/plan` pass before `/execute`. F1 ships in a day to clear tray clutter, F2 delivers the headline UX win, F3 restructures Draft once Landing exists to reference it, F4 wipes Standings and adds Archive last (depends on focus already having shifted away from Standings via F2).

User picks from this session (locked, not relitigated):

- Single combined epic (Season Refocus + Landing Page together).
- Landing Page = new default destination, headline AI report card.
- Standings = wipe / live-only with offseason empty state.
- Draft History → renamed "Draft", per-year sub-tabs with Live/Mocks (this year only) + Recap (all years).
- Draft Order Proposal demoted to **bottom of League section** (lighter option) — NOT folded into Rule Proposals, NOT hidden in Rulebook.
- 2024 + 2025 AI report backfill is in flight separately — treat archive as eventually-full.

---

## Sub-Feature Breakdown

### F1 — Tray Surgery (S)

**Path**: `docs/features/season-refocus/f1-tray-surgery/`
**Effort**: S (1-file PR, mostly label + ordering tweaks)
**Blast radius**: Minimal

Scope:
- Relabel the existing `.draftHistory` tray destination to "Draft" (enum case stays as `.draftHistory` for backward-compat — only the user-facing label changes).
- Reorder `.draftOrder` to the bottom of the League section in `DrawerView.swift`.
- "Draft Order Proposal" remains the screen title on `DraftOrderView` — it's an honest description of what the screen is.

Out of scope for F1: any change to `DraftHistoryView` or `DraftOrderView` internals. This is pure tray/label surgery.

### F2 — Landing Page MVP (M-L)

**Path**: `docs/features/season-refocus/f2-landing/`
**Effort**: M-L (new top-level view, several card components, default destination flip)
**Blast radius**: High — first-load behavior changes for all users

Scope:
- Add `TrayDestination.landing` case.
- New `Xomper/Features/Landing/LandingView.swift` composing cards:
  - Headline AI Review card (latest report across all types; tap → detail).
  - Announcements card (hardcoded `LeagueAnnouncements.current` for v1).
  - Scrolling standings bar (horizontal scroll, empty-state copy in offseason).
  - This-week matchups card (scoreboard-style during games, empty when offseason).
- Flip `NavigationStore.swift:22` default `currentDestination` from `.standings` → `.landing`.
- Remove `AIReviewHomeCard` injection from `SearchView` (it now lives on Landing as the hero).
- Add a "Home" tray slot pointing at `.landing` at the top of the tray.

Out of scope for F2: time-aware card priority function (defer to v2 if needed; v1 ships with static order locked at `/plan` time), news stripe, scores deep-link work, spotlight rotator.

### F3 — Draft Tab Restructure (M)

**Path**: `docs/features/season-refocus/f3-draft-tab/`
**Effort**: M (refactor + sub-tab control + recap wiring)
**Blast radius**: Medium — touches existing Draft surfaces

Scope:
- Reuse existing `HeaderBar` season chip + `SeasonStore` for year switching (no new picker chrome).
- When viewing 2026 (current season): show 3 sub-tabs — **Live order**, **Mocks**, **Recap** (Recap loads AIReport `type=postDraft` for that year).
- When viewing past year (2024, 2025): show 2 sub-tabs — **Picks**, **Recap**.
- Move `DraftOrderView`'s `.mocks` content into the Mocks sub-tab.
- Move `DraftOrderView`'s `.live` content into the Live sub-tab.
- After this refactor, `DraftOrderView` only renders the reverse-HPP Proposal — single view, no internal tabs.

Out of scope for F3: building per-year picker chips (reusing HeaderBar chip is the call), backfilling reports.

### F4 — Standings Wipe + Archive (M)

**Path**: `docs/features/season-refocus/f4-standings-archive/`
**Effort**: M (offseason-aware Standings + new Archive section)
**Blast radius**: Medium — historical drilldowns move to a new home

Scope:
- `StandingsView` becomes live-only — shows current-season standings during regular season; otherwise renders an **offseason countdown** empty state with hardcoded dates: **July 6 6:30pm ET (draft)** and **Sept 8 (Week 1)**.
- New `TrayDestination.archive` at the bottom of the tray, housing sub-sections:
  - Past standings (per year).
  - Past matchup history (link to existing `.matchupHistory`).
  - Past drafts (link into per-year Draft tab from F3).
- Use `nflStateStore` to detect "is there live data yet" for the offseason switch.

Out of scope for F4: rewriting `MatchupHistory` (it's already per-season and works); admin-driven announcement infra.

---

## Cross-Cutting Work

- **`AIReviewHomeCard` migration**: currently injected into `SearchView` (from ai-review F0). F2 must remove it from SearchView cleanly. Coordinate timing — F2's `/plan` should explicitly list the `SearchView.swift` diff.
- **`MatchupHistory` view stays as-is** — already per-season, F4 just links into it from Archive.
- **`HistoryStore` season chain** — F3 reuses it for the per-year selector; no new store work needed.
- **`nflStateStore`** — F2 (matchup empty state) and F4 (Standings offseason switch) both depend on it.

---

## Sequencing

Strict sequential. Each sub-feature gets its own `/plan` → `/execute` → review before the next starts.

```
F1 (Tray Surgery, S)
  │  ships first — clears tray clutter, zero risk
  ▼
F2 (Landing Page MVP, M-L)
  │  biggest user-visible change; default destination flips
  ▼
F3 (Draft Tab Restructure, M)
  │  Landing card from F2 deep-links into this surface
  ▼
F4 (Standings Wipe + Archive, M)
     last — needs F2 to have moved focus away from Standings
```

Rationale: F1 is 1-file groundwork. F2 delivers the headline win. F3 reorganizes Draft once Landing references it. F4 is safe to land last because by then Standings is no longer the cold-open default.

---

## Risks / Tradeoffs

- **Default destination flip**: existing users open the app and see a new home screen. Mitigate by ensuring Landing renders gracefully with empty AI report archive (backfill is the contingency).
- **`AIReviewHomeCard` migration**: F0 wired it into SearchView; F2 must remove it cleanly. Mitigate by F2's `/plan` explicitly listing the file diff before `/execute`.
- **Per-year Draft tabs**: 2024 + 2025 historical drafts need data sources. Mitigate by reusing existing `HistoryStore` season chain — no new store work.
- **Standings empty state**: offseason countdown depends on knowing NFL state. Mitigate by reading `nflStateStore` which already tracks this.
- **HeaderBar season chip side-effects**: switching chip to a past year in Draft changes other views' selected season too. Already true today; not a regression — but F3 `/plan` should sanity-check.
- **Tray real estate**: adding `.landing` + `.archive` pushes tray past 19 entries. F1 + F4 `/plan`s should each audit whether anything folds.

---

## Acceptance Criteria

- App opens to Landing Page by default.
- Landing Page surfaces latest AI Review as a tappable card (deep-links to detail).
- Draft tab (renamed label) has per-year selection; current year shows Live / Mocks / Recap; past years show Picks / Recap.
- Draft Order Proposal still accessible but at the bottom of the League section.
- Standings shows an offseason countdown empty state when out of season (July 6 draft + Sept 8 Week 1 dates).
- New Archive tray destination at the bottom of the tray houses historical data.
- No regressions in existing features (Trade Analyzer, Admin, Team Analyzer, World Cup, Taxi, etc.).
- All `XomperTests` pass; build green; manual QA across all nav destinations.

---

## Open Questions for Sub-Feature Plans

(Each gets resolved at the corresponding sub-feature's `/plan` time, not at epic time.)

- [ ] **F2**: Exact Landing Page card priority order (lock at F2 `/plan` time).
- [ ] **F2**: `AIReviewHomeCard` removal — does it strip from SearchView in F2 or earlier?
- [ ] **F3**: Year switcher in Draft — HeaderBar chip (planned) or local control? Sanity-check cross-view side effects.
- [ ] **F3**: Exact sub-tab labels — "Live" / "Picks" / "Mocks" / "Recap" wording confirm.
- [ ] **F2**: What "live games" lookup currently exists vs. needs new work (research at F2 `/plan` time).
- [ ] **F4**: Whether Archive section needs its own brand of empty state per sub-page (lock at F4 `/plan` time).
- [ ] **F4**: Archive entry shape — single `.archive` hub OR multi-entry section?

---

## Skills / Agents to Use

- **planner**: invoked per sub-feature (F1 → F4) to turn this scaffolding into executable `/plan` documents.
- **executor**: invoked per sub-feature after its `/plan` flips to Ready.
- **swiftui-reviewer** (if available): post-`/execute` for F2 and F3 since those touch real view composition.
- **/orchestrate**: next command — splits this epic into the 4 sub-feature stubs.

---

## Out of Scope (Epic-Level Non-Goals)

- Backfilling 2024 + 2025 AI reports (running separately).
- Admin UI for editing announcements (v2).
- News stripe pulling from external feeds.
- Push notifications for new Landing cards.
- Time-aware Landing card priority function (defer — v1 ships static order).
- Light mode (app stays dark-only).
