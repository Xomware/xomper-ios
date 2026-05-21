# Plan: Season Refocus — F1 Tray Surgery

**Epic**: season-refocus
**Phase**: 1 of 4
**Status**: Ready
**Created**: 2026-05-21
**Last updated**: 2026-05-21
**Depends on**: none (first sub-feature)
**Repos touched**: xomper-ios

---

## Summary

Pure tray/label surgery to clear clutter before the bigger Landing Page work lands in F2. Two user-visible changes:

1. Rename the `.draftHistory` tray entry from **"Draft History"** to **"Draft"** (enum case stays `.draftHistory` for backward-compat — only the display string changes; the nav title cascades for free because `MainShell` reads `navStore.currentDestination.title`).
2. Demote `.draftOrder` (Reverse-HPP proposal) to the **bottom of the League section** in the drawer. No tray entry removed, no rename of the screen title — only the row position changes.

Success = open the drawer, see "Draft" under History; open the League section, find "Draft Order Proposal" as the last row.

---

## Approach

Locked decisions from `BRAINSTORM.md` + epic `/orchestrate` review:

- **Lighter demote** of `.draftOrder` (NOT folded into Rule Proposals as `BRAINSTORM` Q2 Option A originally proposed; NOT hidden in Rulebook). Just sink to bottom of League section.
- **Keep enum case** `.draftHistory` — only user-facing label flips. Avoids churn in `AppRouter`, `HistoryStore`, `MainShell` switches, and any preserved nav state.
- **`DraftOrderView` screen title stays "Draft Order Proposal"** — it's an honest description of what the screen is.

This is a single-iOS-PR change. Expected diff: ~3 files, < 10 lines.

---

## Affected Files / Components

| File | Change | Why |
|------|--------|-----|
| `Xomper/Features/Shell/TrayDestination.swift` | Line 40: `case .draftHistory: "Draft History"` → `case .draftHistory: "Draft"` | User-facing label for the drawer row + the nav title (since `MainShell.swift:253` calls `navigationTitle(navStore.currentDestination.title)`). |
| `Xomper/Features/Shell/DrawerView.swift` | Line 43: reorder League section `entries` array. Current: `[.payouts, .draftOrder, .aiReview, .rulebook, .scoring, .leagueSettings, .ruleProposals]`. New: `[.payouts, .aiReview, .rulebook, .scoring, .leagueSettings, .ruleProposals, .draftOrder]`. | Demotes Reverse-HPP proposal without removing it from the tray. |
| `Xomper/Features/DraftHistory/DraftHistoryView.swift` | Line 47: `EmptyStateView(... title: "No Draft History", ...)` → `title: "No Draft Picks Yet"` | The empty-state heading inside the view repeats the old screen name. Since the screen is now labeled "Draft", swap the empty-state title to a string that doesn't reuse the old surface name. (Defensive — the user already noticed the staleness; we don't want a "Draft → No Draft History" double-take.) |

**Files NOT touched** (deliberately, verified by search):
- `Xomper/Navigation/AppRouter.swift` — `case draftHistory` is an internal route token, no user-facing string.
- `Xomper/Core/Stores/HistoryStore.swift` — `draftHistory` property + "Draft History" code comments are internal API surface, no UX impact.
- `Xomper/Features/Shell/MainShell.swift` — all `.draftHistory` switch cases stay; nav title is driven by `TrayDestination.title` so the rename cascades automatically.
- `Xomper/Features/Shell/HeaderBar.swift` — the season-scoped destinations list `[.matchups, .draftHistory, .worldCup]` is by enum case, unaffected.
- Test files — no user-facing "Draft History" strings to update (verified via grep).

---

## Implementation Steps

- [ ] Step 1 — Edit `TrayDestination.swift`: in the `title` switch (line 40), change `"Draft History"` to `"Draft"`. Leave the enum case, the `systemImage` (`list.clipboard.fill`), and the file-top section-grouping comment as-is (the comment naming "History: draftHistory" still accurately describes the enum case grouping).
- [ ] Step 2 — Edit `DrawerView.swift`: in the `sections` computed property (line 43), reorder the League section's `entries` array to move `.draftOrder` to the end. Final order: `[.payouts, .aiReview, .rulebook, .scoring, .leagueSettings, .ruleProposals, .draftOrder]`.
- [ ] Step 3 — Edit `DraftHistoryView.swift`: change the `EmptyStateView` `title` argument from `"No Draft History"` to `"No Draft Picks Yet"` (line 47). Leave the `icon` and `message` props untouched.
- [ ] Step 4 — Build green: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Xomper -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`.
- [ ] Step 5 — Manual QA in simulator (see Test Plan below).
- [ ] Step 6 — Commit `#<issue> tray label + draftOrder demote (F1 of season-refocus)` and open PR using `Closes #<issue>` in body.

---

## Test Plan

**Build**: green via the xcodebuild command above.

**Manual QA** (single 60-second pass on iPhone 17 Pro sim):

1. Cold launch → swipe right (or tap hamburger) to open the drawer.
2. Under **HISTORY** section: row reads **Draft** (not "Draft History"). Icon unchanged (`list.clipboard.fill`).
3. Tap the row → screen pushes; nav title at top reads **Draft**.
4. (If the league has no completed drafts for the selected season) confirm empty-state heading reads **No Draft Picks Yet** with unchanged icon + body copy.
5. Open the drawer again, scroll to **LEAGUE** section. Confirm order top-to-bottom: Payouts → AI Review → Rulebook → Scoring → League Settings → Rule Proposals → Draft Order Proposal.
6. Tap **Draft Order Proposal** → screen title still reads "Draft Order Proposal" (unchanged).
7. Verify other tray destinations (Standings, Matchups, Team Analyzer, etc.) still render — quick sanity scroll, no regressions expected since only label + array order changed.

**Automated tests**: none required. This is label + ordering. No new logic to cover. (Agent may add a trivial XCTAssertEqual against `TrayDestination.draftHistory.title == "Draft"` if it costs < 2 minutes to wire into the existing `XomperTests` target; otherwise skip.)

---

## Acceptance Checklist

- [ ] Drawer "HISTORY" section's first row reads "Draft" (not "Draft History").
- [ ] Tapping that row pushes a screen whose nav title is "Draft".
- [ ] Empty-state heading on `DraftHistoryView` (when there are no picks for the selected season) reads "No Draft Picks Yet".
- [ ] Drawer "LEAGUE" section ends with the "Draft Order Proposal" row (was previously second from the top of that section).
- [ ] `DraftOrderView` opens normally from its new tray position; its own screen title is unchanged ("Draft Order Proposal").
- [ ] Build is green.
- [ ] No regressions to any other tray destination (visual spot-check).

---

## Out of Scope

- Any change to `DraftHistoryView` internals beyond the empty-state title string.
- Any change to `DraftOrderView` internals.
- Adding, removing, or renaming any tray destination case.
- Restructuring tray sections (no new "Home" or "Archive" section here — those land in F2 / F4).
- Renaming the `.draftHistory` enum case to `.draft` (deferred indefinitely; backward-compat win outweighs naming purity).
- Folding `.draftOrder` into Rule Proposals as a sub-page (was Brainstorm Q2 Option A; superseded by the locked "lighter demote" decision).
- Wiring AI post-draft Recap into the Draft surface (that's F3).

---

## Risks / Tradeoffs

- **"Draft" label collides with the future `.draftOrder` row in the same drawer** (two League-section rows mentioning "Draft"). Accepted — they're in different sections (History vs. League) and `.draftOrder`'s full label "Draft Order Proposal" is distinct enough. F3 will further differentiate when Live/Mocks/Recap sub-tabs land inside the Draft surface.
- **Drawer screenshot tests (if any exist) will fail on the label diff**. Mitigation: update snapshots as part of this PR if hits surface during build.
- **Comment drift**: `TrayDestination.swift` file-top comment groups cases by section ("History: draftHistory, matchupHistory, worldCup"). The comment still references the case name, not the label, so it remains accurate.

---

## Open Questions

None remaining. All locked at brainstorm + epic review:
- Label = "Draft" (singular).
- `.draftOrder` stays in tray, sinks to bottom of League section.
- `DraftOrderView` screen title stays "Draft Order Proposal".
- Enum case stays `.draftHistory`.

---

## Skills / Agents to Use

- **ios-specialist**: invoke directly via `/execute f1-tray-surgery` once status flips to Ready. This is small enough to skip a delegation preview — single agent, < 10-line diff, no branching decisions.
- No swiftui-reviewer needed (no view composition changes).
