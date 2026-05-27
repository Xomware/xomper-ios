# Plan: Admin Portal — F4 Table Editor + Audit

**Epic**: admin-portal
**Sub-feature ID**: F4
**Phase**: Phase 4 — Table Edits + Audit
**Status**: Draft
**Created**: 2026-05-26
**Depends on**: F3 (reuses flag endpoint; introduces audit table that retroactively wraps F1 + F3 writes)

## Summary
Three typed Supabase write endpoints (users, leagues, reports flag — reuses F3 endpoint). iOS typed forms per table with field-level validation. Ships new Supabase `admin_audit` table via Terraform-managed migration — every mutating admin endpoint writes one row per call (F1 test-email and F3 flag lambdas get backfilled audit writes here). New "Audit" sub-screen with paginated feed.

## Repos Touched
- `xomper-infrastructure` — API GW routes `POST /admin/users/{id}`, `POST /admin/leagues/{id}`; Terraform-managed Supabase `admin_audit` migration
- `xomper-back-end` — `lambdas/api_admin_users_update/`, `lambdas/api_admin_leagues_update/`; backfill audit writes into F1 + F3 lambdas
- `xomper-ios` — "Tables" sub-screen (Users + Leagues + Reports children); `UsersEditView`, `LeaguesEditView`; "Audit" sub-screen

## Open Questions (this sub-feature)
- [ ] Audit log home: Supabase (recommended) vs Dynamo — confirm before migration.
- [ ] `is_active` semantics on leagues: downstream effect of deactivating mid-season is out of scope for the editor, but flag it in the form copy.
- [ ] Exact editable field allowlist per table (users: `email`, `display_name`, `sleeper_user_id`, `is_admin`, `is_active`; leagues: `is_active`).

## TODO
- [ ] Flesh out this stub via `/plan admin-portal/f4-tables` before executing
- [ ] Flip Status to Ready
