# Plan: Admin Portal — F2 Pre-flight Email Preview

**Epic**: admin-portal
**Sub-feature ID**: F2
**Phase**: Phase 2 — Pre-broadcast Safety
**Status**: Draft
**Created**: 2026-05-26
**Depends on**: F1 (previews live under the AI Review sub-screen from F1 menu)

## Summary
Extend the three dry-run trigger lambdas (`run_postdraft`, `run_preseason`, `run_weekly`) to return rendered payloads in the response when `dry_run=true`. iOS surface displays the 12 previews and lets admin scan subject + body before clicking "Broadcast" (which calls trigger with `dry_run=false, force=true`). Zero new endpoints — reuses existing trigger flow so preview can never drift from real broadcast.

## Repos Touched
- `xomper-back-end` — extend three trigger lambdas with `previews: [{ recipient, subject, text_body }]`
- `xomper-ios` — previews list under AI Review trigger card, tap-to-expand row, Broadcast button

## Open Questions (this sub-feature)
- [ ] Preview response shape: `text_body` only vs include `html_body` (~10x larger)? Recommend text-only for V1.
- [ ] Cap on `text_body` length per preview (recommend 4KB) — confirm payload size budget.

## TODO
- [ ] Flesh out this stub via `/plan admin-portal/f2-preview` before executing
- [ ] Flip Status to Ready
