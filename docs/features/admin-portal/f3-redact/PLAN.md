# Plan: Admin Portal — F3 Redact + Do-Not-Broadcast + broadcast_at

**Epic**: admin-portal
**Sub-feature ID**: F3
**Phase**: Phase 3 — Broadcast Safety Loop
**Status**: Draft
**Created**: 2026-05-26
**Depends on**: F2 (DNB checkbox lives in F2's preview surface)

## Summary
Two new metadata flags (`is_redacted`, `do_not_broadcast`) plus universal stamping of `broadcast_at` on every successful real broadcast (already done for post-draft; replicate for preseason + weekly). New flag endpoint. Broadcast path re-reads metadata post-generation and aborts 409 if `do_not_broadcast`. Read paths filter `is_redacted == true` for non-admin callers.

## Repos Touched
- `xomper-infrastructure` — API GW route `POST /admin/reports/{league_id}/{report_type}/{period}/flag`
- `xomper-back-end` — `lambdas/api_admin_reports_flag/`, broadcast path DNB check, read-path redact filter
- `xomper-ios` — "Hide from app" button on report rows; "Do not broadcast" checkbox on preview screen

## Open Questions (this sub-feature)
- [ ] Reports list screen scope: "most recent of each type" (recommended for F3) vs full paginated archive (defer to F4)?
- [ ] Button label confirmation — "Hide from app" not "Unsend" (cannot recall already-delivered email).

## TODO
- [ ] Flesh out this stub via `/plan admin-portal/f3-redact` before executing
- [ ] Flip Status to Ready
