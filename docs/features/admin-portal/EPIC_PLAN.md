# Epic Plan: Admin Portal

**Status**: Ready
**Created**: 2026-05-26
**Last updated**: 2026-05-26
**Issue**: #91 (Xomware/xomper-ios)
**Related docs**: `docs/features/admin-portal/BRAINSTORM.md`

---

## Orchestration

Stubs created (each Status: Draft — flesh out via `/plan` before executing):

```
F1 ──► F2 ──► F3 ──► F4 ──► F5
```

- F1 — `docs/features/admin-portal/f1-test-email/PLAN.md` (no deps; foundation — admin home refactor folded in)
- F2 — `docs/features/admin-portal/f2-preview/PLAN.md` (depends on F1)
- F3 — `docs/features/admin-portal/f3-redact/PLAN.md` (depends on F2)
- F4 — `docs/features/admin-portal/f4-tables/PLAN.md` (depends on F3 — ships `admin_audit` table + retrofits F1/F3 audit writes)
- F5 — `docs/features/admin-portal/f5-logs/PLAN.md` (depends on F1 for the menu slot; otherwise standalone)

Execution mode: sequential F1 → F2 → F3 → F4 → F5. F4 and F5 can parallelize after F3 lands if needed, but linear order keeps PR review load manageable.

---

## Overview

The Admin Portal epic expands the current single-screen `AdminView` (trigger cards + activity feed + test send) into a proper multi-screen commissioner control surface, addressing the five capability gaps called out in issue #91: **test email send**, **pre-broadcast preview**, **reverse-out / redact**, **table edits**, and **log tailing**. Delivery is sliced into five sub-features (F1–F5) shipped in safety-first order so each PR triplet (infra → backend → iOS) is mergeable on its own, behind feature flags, without breaking the existing AI Review broadcast flow. The decisions captured in `BRAINSTORM.md` (Option A across all 8 architectural questions) are locked in — this plan is the scaffolding `/orchestrate` will consume to produce per-feature stubs.

---

## Sub-feature breakdown

### F1 — Test email sender + admin home refactor

- **Scope**: New `POST /admin/email/test` lambda. iOS admin home refactored from one ScrollView into a NavigationLink menu (this is the F0 work folded into F1). New "Test Email" sub-screen with recipient + report pickers.
- **Repos touched**: `xomper-infrastructure`, `xomper-back-end`, `xomper-ios`
- **Primary deliverables**:
  - Infra: API Gateway route `POST /admin/email/test`, new lambda Terraform module, SES send IAM
  - Backend: `lambdas/api_admin_email_test/` (reuses `build_email_payload`, `ses_helper`, `admin_gate.require_admin`); writes `notification_log` row with `template=ai_review_test`; never writes `metadata.broadcast_at`
  - iOS: `AdminView` → menu of `NavigationLink`s (AI Review, Tables, Logs, Audit); new `TestEmailView` + `TestEmailStore`; existing trigger cards move under "AI Review" sub-screen
- **Depends on**: nothing (foundation phase)
- **Effort tier**: **M** (small backend, but the AdminView refactor adds scope)

### F2 — Pre-flight email preview

- **Scope**: Extend the three dry-run trigger lambdas (`run_postdraft`, `run_preseason`, `run_weekly`) to return rendered payloads in the response. iOS surface to display + scan the 12 previews before clicking "Broadcast".
- **Repos touched**: `xomper-back-end`, `xomper-ios` (no infra changes — existing endpoints)
- **Primary deliverables**:
  - Backend: extend trigger response with `previews: [{ recipient, subject, text_body }]` when `dry_run=true`; cap `text_body` at 4KB; drop `html_body` from preview payload
  - iOS: previews list under the AI Review trigger card; tap-to-expand row → full subject + body; "Broadcast" button calls trigger with `dry_run=false, force=true`
- **Depends on**: F1 (admin home refactor — previews live under the AI Review sub-screen)
- **Effort tier**: **M** (zero new endpoints, but three lambdas to touch + iOS preview UI)

### F3 — Redact + do-not-broadcast + broadcast_at

- **Scope**: Two new metadata flags (`is_redacted`, `do_not_broadcast`) plus universal stamping of `broadcast_at` on every successful real broadcast (already done for post-draft; replicate for preseason + weekly). New flag endpoint. Read-side filtering of redacted reports for non-admin callers.
- **Repos touched**: `xomper-infrastructure`, `xomper-back-end`, `xomper-ios`
- **Primary deliverables**:
  - Infra: API Gateway route `POST /admin/reports/{league_id}/{report_type}/{period}/flag`
  - Backend: `lambdas/api_admin_reports_flag/` (uses `update_metadata`); broadcast path re-reads metadata after generation and aborts with 409 if `do_not_broadcast`; read paths (`api_ai_reports_latest`, `api_ai_reports_list`) filter out `is_redacted == true` for non-admin callers; first endpoint to write `admin_audit`
  - iOS: "Hide from app" button on report rows; "Do not broadcast" checkbox on preview screen that disables the broadcast button when checked
- **Depends on**: F2 (DNB checkbox lives in the preview surface)
- **Effort tier**: **S**

### F4 — Table editor

- **Scope**: Three typed Supabase write endpoints (users, leagues, reports flag — reuses F3 endpoint). iOS forms per table. New Supabase `admin_audit` table — every mutating admin endpoint backfills writes here. New "Audit" sub-screen.
- **Repos touched**: `xomper-infrastructure`, `xomper-back-end`, `xomper-ios`
- **Primary deliverables**:
  - Infra: API Gateway routes `POST /admin/users/{id}`, `POST /admin/leagues/{id}`; Terraform-managed Supabase migration for `admin_audit` table
  - Backend: `lambdas/api_admin_users_update/`, `lambdas/api_admin_leagues_update/`; strict field allowlists per table; email regex + bool cast validation; every endpoint writes one `admin_audit` row; backfill audit writes into F1's test-email lambda + F3's flag lambda
  - iOS: "Tables" sub-screen with Users + Leagues + Reports children; typed forms (`UsersEditView`, `LeaguesEditView`); "Audit" sub-screen with paginated feed
- **Depends on**: F3 (reuses flag endpoint + introduces the audit table that retroactively wraps F1 + F3 writes)
- **Effort tier**: **L** (largest sub-feature — 2 new lambdas, new Supabase table, 3 iOS forms, audit retrofit)

### F5 — Log viewer

- **Scope**: New `api_admin_logs_query` lambda backed by CloudWatch `FilterLogEvents`. iOS log tail screen with allowlisted log group picker, level filter, search, paginator.
- **Repos touched**: `xomper-infrastructure`, `xomper-back-end`, `xomper-ios`
- **Primary deliverables**:
  - Infra: API Gateway route `GET /admin/logs/query`; new IAM role scoped to `logs:FilterLogEvents` against the allowlisted log group ARNs only (do NOT contaminate other admin lambdas)
  - Backend: `lambdas/api_admin_logs_query/`; allowlist enforcement; server-side regex redaction of emails + sleeper_user_ids; 60s server-side cache on identical queries; pagination via `next_token`
  - iOS: "Logs" sub-screen — log group `Picker`, level filter, search field, "Load older" button, client-side 5s minimum refresh interval
- **Depends on**: F1 (admin home menu — logs sub-screen plugs in)
- **Effort tier**: **M–L** (single lambda but unfamiliar IAM surface + PII redaction + pagination UI)

---

## Cross-cutting work

| Concern | When it lands | Notes |
|---|---|---|
| Admin home `NavigationLink` menu refactor | **F1** | Folded in as the first commit of F1's PR. Preserves existing trigger cards verbatim under the new "AI Review" sub-screen. Precondition for F2–F5 having a place to live. |
| `admin_gate.require_admin` reuse | All sub-features | Already exists in backend. No changes needed — every new admin lambda imports it at the top. |
| `admin_audit` Supabase table | **F4** (first sub-feature whose endpoints write multiple kinds of audit rows) | Terraform-managed migration. F1 and F3 endpoints retroactively gain audit writes during F4. Pragmatic: avoids shipping a table with one consumer in F1. |
| Per-feature `@Observable` stores | All sub-features | Each sub-feature owns one store (`TestEmailStore`, `AdminPreviewStore`, `AdminReportsAdminStore`, `AdminTablesStore` + `AdminAuditStore`, `AdminLogsStore`). Existing `AdminStore` shrinks to menu + dashboard summary. |
| Common iOS sub-screen pattern | F1 establishes; F2–F5 inherit | All sub-screens: `NavigationLink` destination from `AdminView`; `@MainActor` `@Observable` store; loading/error/empty states identical; result rows reuse the same row component. |
| PII redaction | F5 (logs) primarily | Server-side regex in the lambda — emails + sleeper IDs replaced before return. Not client-side. |
| Feature flags | All sub-features | Each new sub-screen gated behind a `Config.swift` flag so partial rollout is safe. Menu hides unfinished entries. |

---

## Recommended orchestration order

`/orchestrate` should create these stubs in this order:

1. `docs/features/admin-portal/f1-test-email/PLAN.md`
2. `docs/features/admin-portal/f2-preview/PLAN.md`
3. `docs/features/admin-portal/f3-redact/PLAN.md`
4. `docs/features/admin-portal/f4-tables/PLAN.md`
5. `docs/features/admin-portal/f5-logs/PLAN.md`

Rationale: each stub depends on the immediately preceding one (F1 establishes the menu; F2 lives in the AI Review sub-screen; F3 plugs into F2's preview surface; F4 introduces the audit table that retroactively wraps F1 + F3; F5 is the standalone bookend). F4 and F5 can be parallelized after F3 lands if needed, but the linear order keeps PR review load manageable.

---

## Dependencies that span repos

Each sub-feature is a PR triplet. Order within a sub-feature is always **infra → backend → iOS**.

| Sub-feature | Infra PR | Backend PR | iOS PR |
|---|---|---|---|
| **F1** | API GW route for `/admin/email/test`; SES send permission on lambda role | `api_admin_email_test` lambda merged after route exists | Admin home refactor + TestEmailView merged after lambda is live in dev |
| **F2** | (none — existing endpoints) | Trigger lambdas extended with `previews` field — merge before iOS expects it | Preview UI merged after backend returns the new field |
| **F3** | API GW route for `/admin/reports/.../flag` | `api_admin_reports_flag` lambda + broadcast path DNB check + read-path redact filter | Flag UI + DNB checkbox merged after backend live |
| **F4** | API GW routes for users/leagues update; Terraform migration creating `admin_audit` Supabase table | Two new lambdas + retrofit audit writes into F1 + F3 lambdas; runs only after `admin_audit` table exists | Three typed forms + Audit feed merged after backend live |
| **F5** | API GW route for `/admin/logs/query`; new IAM role with `logs:FilterLogEvents` scoped to allowlisted log group ARNs | `api_admin_logs_query` lambda — depends on the new IAM role | Log tail UI merged after backend returns paginated events |

Cross-sub-feature: **F4's audit table migration is a soft blocker for closing out F1 + F3.** Audit retrofit writes for those two are part of F4's backend PR.

---

## Rollout risks (epic level)

| Risk | Mitigation |
|---|---|
| **Auth scope creep** — temptation to introduce role tiers mid-epic when one endpoint feels like it should be "read-only admin" | Hard rule: `is_admin` only. Anything finer goes to a separate epic. Re-read Q6 of brainstorm before merging any auth change. |
| **PII leakage in log viewer** — emails/sleeper IDs slip through CloudWatch returns | Server-side regex in F5 lambda before return; never client-side. Unit test: golden-file regex over a sample log line. |
| **Audit log gaps** — F1 and F3 ship before `admin_audit` exists, then retrofit is forgotten | F4's backend PR has a checklist item to backfill audit writes into F1 + F3 lambdas. Code-review gate: grep for `update_metadata` and `send_emails_concurrently` in any admin lambda — every match must be paired with an audit row write. |
| **Accidental admin actions** — table editor toggles `is_active` on a user by misclick | Confirmation dialog on every destructive iOS form action ("Set is_admin=false for X — confirm?"). All edits land in audit log for forensic recovery. |
| **Race condition on `broadcast_at` write** — broadcast path stamps metadata before fan-out completes; partial failure leaves report marked broadcast when only 3/12 emails sent | Stamp `broadcast_at` AFTER successful fan-out (after `send_emails_concurrently` returns). Track per-recipient delivery status in the response so retries are idempotent. |

---

## Acceptance criteria (epic done when)

The admin portal epic is **done** when:

1. `AdminView` is a `NavigationLink` menu; no single admin screen exceeds 300 lines. Existing trigger cards live under an "AI Review" sub-screen with no UX regression.
2. Admin can send a test of any of the 3 AI Review report types to any whitelisted user without polluting `metadata.broadcast_at`. (F1)
3. Admin can preview all 12 rendered emails (subject + text body) before broadcast in a single round-trip with the dry-run trigger. (F2)
4. Admin can mark any report as "Hide from app" (post-broadcast) and "Do not broadcast" (pre-broadcast), and every successful broadcast stamps `metadata.broadcast_at`. (F3)
5. Admin can edit `whitelisted_users` and `whitelisted_leagues` rows via typed forms with field-level validation. (F4)
6. `admin_audit` Supabase table exists; every mutating admin endpoint (test email, flag, users update, leagues update) writes one row per call. Audit sub-screen renders a paginated feed. (F4)
7. Admin can filter / search CloudWatch logs for the AI Review + notif lambdas with PII redacted server-side. (F5)
8. All admin endpoints sit behind `admin_gate.require_admin`; non-admin callers receive 403.
9. Each sub-feature ships behind a `Config.swift` feature flag and the menu hides unfinished entries.

---

## Open questions for sub-feature plans

Carry forward from `BRAINSTORM.md` § "Open questions for /plan":

- [ ] **Audit log home** (Supabase vs Dynamo): brainstorm recommends Supabase. Confirm before F4.
- [ ] **Test email `kind` in `notification_log`**: new `kind=email_test` vs new `template` under existing `kind=email`. Resolve in F1 plan.
- [ ] **Reports list screen for F3**: "most recent of each type" vs full paginated archive. Recommend recent-only in F3, archive in F4.
- [ ] **Preview response shape**: `text_body` only vs include `html_body` (~10x larger). Recommend text-only for V1; html is an F2.5 polish.
- [ ] **Log allowlist exact group names**: expected `/aws/lambda/api_admin_ai_review_*`, `/aws/lambda/notif_ai_review_weekly`, `/aws/lambda/notif_*`, `/aws/lambda/email_*` — need definitive list at F5 plan time.
- [ ] **iOS F4 `is_active` semantics**: native `Picker` is fine for ~12 users, but downstream effect of deactivating a league mid-season is out of scope for the editor itself. Flag for F4 plan.

---

## Skills / Agents to Use

- **`/plan f1-test-email`** → first per-feature plan. Resolves the test-email-kind question + admin home refactor scope.
- **`/plan f2-preview`** → resolves preview payload shape (text vs html).
- **`/plan f3-redact`** → resolves reports archive scope decision.
- **`/plan f4-tables`** → resolves audit-log-home decision and F4 `is_active` flag scope.
- **`/plan f5-logs`** → resolves the definitive log group allowlist.
- **`/orchestrate`** (after this epic plan is approved) → creates the 5 sub-feature stub directories + skeleton PLAN.md files.
- **`backend-engineer` agent** during each sub-feature's `/execute` → handles the lambda + Terraform PRs.
- **`ios-engineer` agent** during each sub-feature's `/execute` → handles the iOS view + store PRs.
