# Plan: AI Review — F1 Post-Draft Analysis (Phase 1)

**Epic**: `docs/features/ai-review/EPIC_PLAN.md`
**Phase**: 1
**Status**: Draft
**Created**: 2026-05-21
**Depends on**: F0 (shared infra must be merged + deployed)

## Summary
First end-to-end run through the new AI Review pipeline: a one-shot Claude-generated team-by-team grade + outlook report fired after the 2026 rookie draft. Admin-triggered (button or one-time EventBridge rule). New `notif_ai_review_postdraft` lambda fetches draft picks via Sleeper, builds a prompt with lore, calls Claude through the shared `claude_helper`, persists to `xomper_ai_reports`, sends the league-wide email via the shared chrome, and fires a teaser push. First invocation runs in dry-run mode (admin-only delivery) for tone calibration before broadcast. iOS already renders any report generically — F1 only adds the `.postDraft` type label in the archive list. Effort tier: **M** (tone calibration dominates).

## Repos touched
- `xomper-back-end` (new `lambdas/notif_ai_review_postdraft/handler.py` + prompt skeleton in `prompt.py` or `prompts/postdraft.md`)
- `xomper-infrastructure` (admin trigger wiring — admin-only API endpoint or one-time EventBridge rule; reuses Phase 0 IAM + role)
- `xomper-ios` (single-line addition: `.postDraft` label in the report-type rendering)

## Open questions to resolve in `/plan`
- [ ] Admin trigger shape — new admin-only API endpoint vs one-time EventBridge rule vs both?
- [ ] Prompt skeleton + tone anchor paragraphs for post-draft.
- [ ] Exact data inputs — full draft pick list, ADP comparisons, pre-draft rankings?
- [ ] Push teaser copy for post-draft (parameterized template from F0).
- [ ] Dry-run delivery mechanism — env flag, event payload arg, or both?

<!-- /plan f1-post-draft to fill in scope, architecture, file-by-file steps, test plan -->
