# Plan: Season Refocus — F3 Draft Tab Restructure

**Epic**: season-refocus
**Phase**: 3 of 4
**Status**: Draft
**Created**: 2026-05-21
**Depends on**: F1, F2 (Landing card from F2 deep-links into this surface)
**Repos touched**: xomper-ios

---

## Summary

Restructure the Draft surface around per-year sub-tabs driven by the existing `HeaderBar` season chip + `SeasonStore`. When viewing 2026 (current season): show three sub-tabs — **Live order**, **Mocks**, **Recap** (Recap loads AIReport `type=postDraft` for that year). When viewing past year (2024, 2025): show two sub-tabs — **Picks**, **Recap**. Port `DraftOrderView`'s `.live` and `.mocks` content into the new sub-tabs. After this refactor, `DraftOrderView` only renders the reverse-HPP Proposal (single view, no internal tabs).

---

## Open questions to resolve in `/plan`

- Year switcher in Draft — confirm HeaderBar chip is the right call vs. local control. Sanity-check cross-view side effects (chip is global; changing it in Draft drifts other season-aware views).
- Exact sub-tab labels — confirm wording: "Live order" vs. "Live", "Picks" vs. "Board", "Mocks", "Recap".
- Per-year season list — match `SeasonStore.availableSeasons` exactly, or filter to years with completed drafts + current year?
- Empty-state copy for past-year Recap tab when AI report backfill hasn't landed yet.

---

<!-- /plan f3-draft-tab to fill in scope, architecture, file-by-file steps, test plan -->
