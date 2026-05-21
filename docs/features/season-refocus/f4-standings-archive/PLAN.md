# Plan: Season Refocus — F4 Standings Wipe + Archive

**Epic**: season-refocus
**Phase**: 4 of 4
**Status**: Draft
**Created**: 2026-05-21
**Depends on**: F1, F2, F3 (safe to land last because by then Standings is no longer the cold-open default)
**Repos touched**: xomper-ios

---

## Summary

`StandingsView` becomes live-only — shows current-season standings during regular season; otherwise renders an **offseason countdown** empty state with hardcoded dates: **July 6 6:30pm ET (draft)** and **Sept 8 (Week 1)**. Add a new `TrayDestination.archive` at the bottom of the tray housing sub-sections: past standings (per year), past matchup history (link to existing `.matchupHistory`), past drafts (link into per-year Draft tab from F3). Use `nflStateStore` to detect "is there live data yet" for the offseason switch.

---

## Open questions to resolve in `/plan`

- Whether Archive section needs its own brand of empty state per sub-page — lock at `/plan` time.
- Archive entry shape — single `.archive` hub view OR multi-entry section in the tray ("Past Standings", "Past Drafts", "All AI Reports")?
- Exact offseason copy for `StandingsView` empty state — countdown component design, hardcoded date strings.
- Tray real estate audit — adding `.archive` brings total entries past 19; confirm nothing else folds.

---

<!-- /plan f4-standings-archive to fill in scope, architecture, file-by-file steps, test plan -->
