# Plan: AI Review — F2 Preseason Blast (Phase 2)

**Epic**: `docs/features/ai-review/EPIC_PLAN.md`
**Phase**: 2
**Status**: Draft
**Created**: 2026-05-21
**Depends on**: F0 (shared infra), F1 (reuses prompt scaffolding, dry-run pattern, and email template established there)

## Summary
One-shot Claude-generated "last year's grade + this year's outlook" per team, admin-triggered before Week 1 kickoff. Structurally identical to F1 — different prompt skeleton + different data inputs (prior-season standings + offseason moves instead of draft picks). New `notif_ai_review_preseason` lambda pulls prior-season final standings + current roster snapshot, builds a "year over year" prompt, generates + persists + sends. iOS surface only adds the `.preseason` type label. Effort tier: **S** (remix of F1 with different data sources).

## Repos touched
- `xomper-back-end` (new `lambdas/notif_ai_review_preseason/handler.py` + preseason prompt skeleton)
- `xomper-ios` (single-line addition: `.preseason` label)

## Open questions to resolve in `/plan`
- [ ] Prior-season data source — Sleeper league history endpoint vs Dynamo snapshot from end-of-season?
- [ ] Admin trigger reuses F1's shape (assumed yes — confirm in plan).
- [ ] Preseason prompt tone — how distinct from post-draft? (Year-over-year framing vs forward-looking outlook.)
- [ ] Offseason-moves data inputs — trades log, waiver activity, keeper declarations?

<!-- /plan f2-preseason to fill in scope, architecture, file-by-file steps, test plan -->
