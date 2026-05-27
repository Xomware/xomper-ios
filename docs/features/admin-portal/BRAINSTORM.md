# Admin Portal — Brainstorm

> Epic: full ops dashboard for the Xomper league commissioner. Expands the current
> single-screen `AdminView` (trigger cards + activity feed + test send) into a
> multi-screen control surface covering log tailing, table editing, preview-before-
> broadcast, test email, and reverse-out. Issue #91.

Status: Draft
Date: 2026-05-26
Owner: Dominick
Related: existing `AdminView`, `AdminStore`, admin lambdas under
`xomper-back-end/lambdas/api_admin_*`.

---

## Problem statement

`AdminView` started as a "trigger + recent activity" panel and has grown into a
wall: 3 trigger cards, a test-send card, an activity feed, a filter bar, and
result lines — all in one `ScrollView`. As we add real ops capabilities (log
tailing, table edits, broadcast preview, redaction) the single-screen pattern
breaks:

1. Cognitive load: everything competes for vertical space.
2. State bloat: `AdminStore` would balloon to manage 6+ unrelated domains.
3. Safety: high-blast-radius actions (broadcast, edit user) live next to
   low-stakes actions (refresh feed) with the same visual weight.
4. Discoverability: features added later get buried below the fold.

We need an architecture for an admin portal that can absorb 5+ new capabilities
without becoming a `ScrollView` of doom, plus backend endpoints + a phasing plan
that delivers value in safe-to-merge increments.

---

## Phase 1 — Explore (wide)

Loose set of ideas, not all are good. Filter happens in Phase 2.

- iOS-side: convert AdminView into a "menu" of NavigationLinks to per-feature
  screens (Log Viewer, Tables, Test Email, Preview, Reports).
- iOS-side: collapsible `DisclosureGroup` sections per feature, keep one screen.
- iOS-side: sub-tab bar inside admin (mimics main app tabs).
- iOS-side: dashboard summary card on the menu screen (3 KPIs: last broadcast,
  last error, admins online) above the sub-nav links.
- Backend: log viewer via CloudWatch Logs Insights query → API GW lambda.
- Backend: log viewer via Dynamo log mirror (write side fans logs into Dynamo).
- Backend: log viewer via `notification_log` table extension (lambda name + level).
- Backend: streaming logs via WebSocket / API GW v2 / SSE.
- Backend: paginated logs only (cheaper, simpler).
- Backend: table editor with per-table generic endpoints (`POST /admin/table/{x}/{id}`).
- Backend: table editor with table-specific endpoints (`POST /admin/users/{id}`,
  `POST /admin/leagues/{id}`, `POST /admin/reports/{id}/flag`).
- Backend: raw JSON form for table edits (admin-only, fast to ship).
- Backend: typed forms per table with field validation.
- Backend: audit log via Dynamo `admin_audit` table (one row per write).
- Backend: audit log via CloudWatch (free, but harder to query).
- Backend: audit log via Supabase `admin_audit` (closer to the data being edited).
- Backend: preview endpoint that renders all 12 emails without sending.
- Backend: preview endpoint that returns just subject + greeting (cheap).
- Backend: preview baked into the existing trigger response (dry-run already
  generates payloads — extend it to return them).
- Backend: test email reuses `build_email_payload` + SES helper, new lambda
  `api_admin_email_test`.
- Backend: test email piggybacks on existing `api_admin_test_send` with a new
  `kind=ai_review_test`.
- Backend: redact = `metadata.is_redacted=true` via `update_metadata` (existing
  helper — no new Dynamo plumbing needed).
- Backend: redact = soft-delete via a separate `redacted_reports` table.
- Backend: "do not broadcast" pre-flight flag (separate from post-broadcast
  redact) so an admin can mark a dry-run report as DNB before confirming.
- Pre-flight UX: 12-card carousel, swipe to preview each manager's email.
- Pre-flight UX: aggregate "subject diversity check" (are 12 subjects
  meaningfully different?) — bonus QA.
- Permission scope: keep current `is_admin` gate, no need for fine-grained roles.
- Permission scope: introduce role tiers (super-admin vs read-only admin) — over-
  kill for a 12-person league with one commissioner.
- IAM: each new admin lambda gets `logs:FilterLogEvents` only on the AI Review +
  notif log groups (least privilege).
- IAM: shared admin role across all admin lambdas — simpler, less granular.
- PII: redact emails in log viewer output server-side before returning.
- PII: client-side redaction — wrong, server still leaks.
- Audit log surfacing: a 5th tab in admin portal that just shows the audit feed.
- Audit log surfacing: badge on each editable row showing last edited by/when.
- Phasing: ship test email first (smallest), then preview, then tables, then
  logs, then redact.
- Phasing: ship logs first (highest novelty / ops value).
- Phasing: ship preview first (highest pre-broadcast safety value).
- Phasing: bundle preview + redact into the same PR (both touch the trigger
  flow + metadata).
- Off-the-wall: integrate CloudWatch via AWS Console deep link — open in Safari
  with prefilled filter (zero backend work, lossy UX).
- Off-the-wall: replace the log viewer with a "Slack me when this errors" alert
  pipeline. Solves a different problem (proactive vs reactive) but might be the
  better investment.

---

## Phase 2 — Converge

Answers per architectural question. For each, the chosen option is marked and
justified; alternatives are listed with why they lose.

### Q1 — Log viewer

#### Option A: CloudWatch Logs Insights via admin lambda  ← **chosen**

**What**: New lambda `api_admin_logs_query` accepts `{ log_group, level, search,
since_minutes, limit }` and runs a `logs:FilterLogEvents` (not Insights — cheaper
+ better fit for tail-style queries) against the requested group, returning
parsed events with timestamp + level + message.

**How it works**: Lambda holds an allowlist of permitted log groups
(`/aws/lambda/ai_review_*`, `/aws/lambda/notif_*`). Filter pattern built from
`level` (`?ERROR ?WARN`) and `search` (literal). Returns paginated events with a
`next_token`. iOS renders a tail view (newest first) and a "Load older" pager.

**Pros**:
- Zero new storage / write-side instrumentation.
- Real logs, including stack traces — not a curated subset.
- Allowlist gives us least-privilege scope.

**Cons / Risks**:
- CloudWatch FilterLogEvents has rate limits per log group; under repeated tail
  refreshes from an admin in-flight, we'd see throttling. Mitigation: enforce
  client-side 5s minimum between refreshes + server-side cache (60s TTL) on
  identical queries.
- PII in logs (emails, sleeper IDs in traces) — must redact in lambda before
  returning. Pattern: post-filter regex on the message string for email +
  sleeper_user_id-looking values.

**Best if**: We want real logs without writing a parallel logging pipeline.

#### Option B: Dynamo log mirror (rejected)

Write-side instrumentation in every lambda; introduces drift between what
CloudWatch shows and what the admin portal shows. Adds storage cost. Only wins
if we need sub-second tail latency — we don't.

#### Option C: Extend `notification_log` (rejected)

`notification_log` is about delivery outcomes (push + email sends), not lambda
execution logs. Repurposing it conflates two concerns. The "old notif lambdas"
already write here; the AI Review lambdas would have to be retrofitted with
write-side instrumentation we don't currently need.

### Q2 — Table editor

#### Option A: Typed endpoints + typed iOS forms per table  ← **chosen**

**What**: Three new endpoints — `POST /admin/users/{id}`, `POST /admin/leagues/
{id}`, `POST /admin/reports/{league_id}/{report_type}/{period}/flag` — each
accepts only the fields it knows about. iOS renders a typed form per table.

**How it works**: Each endpoint has a strict allowlist of editable fields
(users: `email`, `display_name`, `sleeper_user_id`, `is_admin`, `is_active`;
leagues: `is_active`; reports: `is_redacted`, `do_not_broadcast`). Validation
lives in the lambda (email regex, sleeper_user_id non-empty, bool casts).
Audit row written to Supabase `admin_audit` (actor, table, row_id, before,
after, at) inside the same transaction where possible (Supabase) or as a
follow-up write (Dynamo metadata).

**Pros**:
- Hard guardrails — admin can't accidentally edit `id` or `created_at`.
- Field-level validation server-side; iOS form just mirrors it.
- Compiler-checked iOS Codable models per table.

**Cons / Risks**:
- More endpoints = more code. Three new lambdas + three new iOS forms.
- Schema drift: if we add a new column to `whitelisted_users` we have to update
  the endpoint allowlist. Mitigation: documented checklist + tests that fail
  when a column lacks an allow/deny decision.

**Best if**: We value safety + clear field semantics over endpoint count.

#### Option B: Generic `POST /admin/table/{name}/{id}` (rejected)

Open-ended `{ field: value, ... }` body. Faster to ship but the cost is paid in
audit/safety: now a typo in `is_amdin` (vs `is_admin`) is a silent no-op, and
the endpoint must defend against every possible column at runtime.

#### Option C: Raw JSON editor (rejected)

A `TextEditor` of the JSON row + a save button. No. The 1% of edits that need
this can be done in Supabase directly.

### Q3 — Test email sender

#### Option A: New `POST /admin/email/test`  ← **chosen**

**What**: Body `{ target_sleeper_user_id, report_id }`. Lambda loads the report,
loads the target user, calls `build_email_payload` with their first_name +
email, hands it to `ses_helper.send_emails_concurrently` (single-recipient
list). Does **not** flip `metadata.broadcast_at`. Does **not** increment any
"sent" counter on the report.

**How it works**: Reuses existing helpers (`get_whitelisted_user_by_sleeper_id`,
`get_latest` / direct report fetch, `build_email_payload`, `ses_helper`). The
key invariant: this path **never** writes to the report's metadata, so a test
send doesn't pollute "last broadcast at" state.

**Pros**:
- Small surface area: one new lambda, fully reuses existing rendering + SES.
- Clear separation from broadcast — no risk of test sends being counted as
  broadcasts.
- Useful early: ships in F1 and unblocks every later phase that benefits from
  rapid email iteration.

**Cons / Risks**:
- `notification_log` write: should the test send appear in the activity feed?
  Recommend yes, tagged `kind=email` + `template=ai_review_test`, so it's
  visually distinct from real broadcasts.

**Best if**: We want to iterate on AI Review email layout without firing the
12-person broadcast cannon.

#### Option B: `dry_run=true` extended to per-user delivery (rejected)

Today `dry_run=true` means "deliver only to the admin". We could add
`dry_run_target` to override the recipient. Reusable but couples the broadcast
trigger to the test path; harder to reason about which code path wrote which
metadata.

### Q4 — Pre-flight preview

#### Option A: New `GET /admin/reports/{id}/preview` (rejected for cost)

Fetch report + iterate 12 users + render 12 payloads, return all 12. Clean but
duplicates rendering logic with the broadcast path; risk of drift.

#### Option B: Extend dry-run trigger response to include rendered payloads  ← **chosen**

**What**: When `dry_run=true`, the existing trigger lambdas already render the
emails (they have to — they send a copy to the admin). Extend the trigger
response to also return the full 12-user rendered payload set.

**How it works**: Inside `run_postdraft` / `run_preseason` / `run_weekly`, after
the dry-run send completes, attach the rendered payloads (without `html_body`
to keep the response small — just `recipient`, `subject`, `text_body`) to the
response under `previews: [...]`. iOS admin portal: "Generate dry run" now
ALSO populates a "Preview" view. Admin scans previews; when satisfied, clicks
"Broadcast" which calls the trigger with `dry_run=false, force=true`.

Optional polish: a separate `GET /admin/reports/{id}/preview` for previewing
the most recent dry-run report **without** re-running generation. Falls back
to fetching the report from Dynamo + rendering on the fly.

**Pros**:
- Zero new rendering paths — same code that does broadcast does preview.
- One round-trip: dry-run gives the admin both the SES-delivered admin copy AND
  the 12 previews.
- Drift-proof: if `build_email_payload` changes, preview changes with it.

**Cons / Risks**:
- Response payload grows by ~12 × (subject + text body). Estimate ~30KB.
  Acceptable for an admin-only endpoint, but cap text body length to 4KB to be
  safe.

**Best if**: We want preview to never lie about what the broadcast will send.

### Q5 — Reverse-out / undo

#### Option A: `metadata.is_redacted` + `metadata.broadcast_at`  ← **chosen**

**What**: Two metadata flags. `broadcast_at` is set on first successful broadcast
(F1 already does this for post-draft; replicate for preseason + weekly).
`is_redacted` is admin-only writable via `POST /admin/reports/.../flag`.

**How it works**: Read paths (`api_ai_reports_latest`, `api_ai_reports_list`)
filter out `metadata.is_redacted == true` for non-admin callers. Admin views
show redacted reports with a strikethrough + "redacted by X on Y" badge.
Email already-delivered: nothing to recall.

**Pros**:
- Uses existing `update_metadata` helper — no schema change.
- Read-side filter is one predicate.
- Admins still see history (recoverable by un-redacting).

**Cons / Risks**:
- Doesn't recall already-sent email. Mitigation: name the button "Hide from
  app" not "Unsend" — set correct expectations.
- Pre-broadcast "do not broadcast" flag is separate. Recommend a second
  metadata key `do_not_broadcast: true` checked by the broadcast path before
  fan-out. If set, broadcast aborts with a 409.

**Best if**: We accept "redact in our surfaces" as the bounded promise.

### Q6 — Permission scope + auth

**Decision**: Keep the current `is_admin` gate. No role tiers. Audit log
captures who did what; that's the read-back.

**Rationale**: 12-person league with one human commissioner. Role tiers are
process complexity solving a problem we don't have.

### Q7 — Phasing

5 sub-features. Recommended order:

| Phase | Feature                       | Why this order                                                                 |
|-------|-------------------------------|---------------------------------------------------------------------------------|
| F1    | Test email sender             | Smallest scope, immediate value, unblocks copy/template iteration before F2.    |
| F2    | Pre-flight email preview      | Highest safety value before any real broadcast. Builds on F1's rendering reuse. |
| F3    | Redact / "do not broadcast" + broadcast_at | Small but completes the broadcast safety story. Wraps F2 nicely.   |
| F4    | Table editor                  | Largest scope (3 endpoints + 3 forms + audit log). Lower urgency.               |
| F5    | Log viewer                    | Highest novelty value but lowest urgency — we have CloudWatch console today.    |

**Why F3 before F4**: F3 is small and closes the broadcast-safety loop alongside
F2; doing it third keeps the "AI Review safety" arc together before pivoting to
table edits. F4 + F5 are unrelated to AI Review broadcast and can stand alone.

### Q8 — iOS UI organization

#### Option A: NavigationLink sub-screens off an admin home menu  ← **chosen**

**What**: AdminView becomes a menu of NavigationLinks: "AI Review", "Tables",
"Logs", "Audit", with a small dashboard summary card at top (last broadcast
times per report type, recent error count).

**How it works**: Each link pushes onto the existing tray's NavigationStack.
Per-feature stores: `AILogsStore`, `AdminTablesStore`, `AdminPreviewStore`,
`AdminAuditStore`. The current `AdminStore` shrinks to the menu + dashboard
summary; trigger logic moves into `AILogsStore` or a dedicated `AIReviewAdminStore`.

**Pros**:
- Clear mental model: one feature per screen.
- State isolation: bug in log viewer can't corrupt trigger state.
- Each PR gets to add its own screen without touching the others.

**Cons / Risks**:
- More files, more navigation tap depth.
- Existing AdminView refactor is a precondition for F1+ — recommend doing the
  menu refactor as F0 (or first half of F1).

**Best if**: We're building a portal that will keep growing.

#### Option B: Collapsible sections within one ScrollView (rejected)

Defers the problem. We end up with a 1000-line `AdminView` after 5 features.

#### Option C: Sub-tab bar (rejected)

Two levels of tabs is a navigation smell. SwiftUI handles `NavigationLink` push
gestures better than nested tab bars anyway.

---

## Phase 3 — Recommendation

**Recommended path**: Take Option A on every question above. The shape:

- Restructure `AdminView` into a menu with sub-screen NavigationLinks (F1 carries this).
- Ship in this order: **F1 test email → F2 preview → F3 redact/broadcast_at → F4 tables → F5 logs**.
- Backend pattern: one new lambda per surface, reusing `admin_gate.require_admin`,
  `build_email_payload`, `update_metadata`, and `ses_helper`.
- New Supabase table: `admin_audit { id, actor_sleeper_id, table, row_id,
  before, after, at }`. Written by every table-editor endpoint and the
  redact/DNB endpoint.

Depends on:
- Whether we want streaming logs (no — paginated only).
- Whether we want role tiers (no — `is_admin` is enough).
- Confirmation that the existing dry-run trigger response can grow by ~30KB
  (yes — admin-only path).

---

## Sub-feature decomposition (for `/orchestrate`)

### F0 — Admin home refactor (folded into F1)

Convert `AdminView` from one ScrollView to a menu + dashboard summary. Move
existing trigger cards under a child screen "AI Review". No new backend work.
Done as the first commit inside F1's PR so F1 has somewhere to put its UI.

### F1 — Test email sender

**iOS**: New "Test Email" screen reached from admin menu. Form: pick recipient
(picker over whitelisted users), pick report (picker over recent reports per
type). Send button. Result row.
**Backend**: `POST /admin/email/test` lambda. Reuses `build_email_payload` +
`ses_helper`. Writes a `notification_log` row with `template=ai_review_test`.
**Acceptance**: Admin can send any of the latest 3 reports to any whitelisted
user; `notification_log` shows the send; the report's `metadata.broadcast_at`
is untouched.

### F2 — Pre-flight email preview

**iOS**: After a dry-run trigger, show a "Previews (12)" list under the
trigger card. Each row: subject + first 200 chars of body. Tap to expand to
full subject + text body. "Broadcast" button at top fires
`dry_run=false, force=true`.
**Backend**: Extend `run_postdraft` / `run_preseason` / `run_weekly` response
with `previews: [{ recipient, subject, text_body }]` when `dry_run=true`.
Cap text_body at 4KB per preview.
**Acceptance**: After dry-run, admin sees all 12 rendered subjects + bodies in
the iOS portal without any further backend call.

### F3 — Redact + DNB + broadcast_at

**iOS**: "Hide from app" button on every report row in the admin's reports list
(new screen under menu). "Do not broadcast" checkbox on the preview screen
(blocks the broadcast button when checked).
**Backend**: `POST /admin/reports/{league_id}/{report_type}/{period}/flag` body
`{ is_redacted?: bool, do_not_broadcast?: bool }`. Broadcast path checks
`metadata.do_not_broadcast` and aborts with 409 if true. Read paths for
non-admin callers filter `metadata.is_redacted == true`.
**Acceptance**: Admin can mark any report as redacted; non-admin app surfaces
no longer show it. Admin can mark a dry-run report as DNB; subsequent broadcast
attempt fails with a clear message.

### F4 — Table editor

**iOS**: "Tables" screen with three sub-screens: Users, Leagues, Reports
metadata. Each is a list with edit buttons that push to typed forms.
**Backend**: Three new lambdas — `POST /admin/users/{id}`,
`POST /admin/leagues/{id}`, `POST /admin/reports/.../flag` (reuses F3 endpoint).
Each writes an `admin_audit` row.
**Acceptance**: Admin can toggle `is_active` on a user / league via the iOS
form; the change is reflected in Supabase and in `admin_audit`. Email regex
validation rejects bad addresses.

### F5 — Log viewer

**iOS**: "Logs" screen with: log group picker (allowlist), level filter,
search box, "Load more" pager.
**Backend**: `GET /admin/logs/query?log_group=...&level=...&search=...&
since_minutes=60&limit=100&next_token=...`. Server-side regex redacts emails +
sleeper_user_ids in returned messages. Returns paginated events.
**Acceptance**: Admin can filter logs for any allowlisted log group, filter by
ERROR/WARN/INFO, search for a substring, and paginate.

---

## Cross-cutting concerns

### IAM scope
- F1–F4: same IAM as existing admin lambdas (DynamoDB R/W on `xomper-ai-reports`,
  Supabase via env-var key, SES send for F1).
- F5: add `logs:FilterLogEvents` scoped to the allowlist of log group ARNs only.
  Use a separate IAM role for `api_admin_logs_query` to avoid contaminating the
  other admin lambdas with log-read perms.

### Audit log
- New Supabase table `admin_audit` (`id`, `actor_sleeper_id`, `actor_email`,
  `surface` enum ('users','leagues','reports','email_test','broadcast'),
  `row_id`, `before` jsonb, `after` jsonb, `at` timestamptz).
- Every mutating admin endpoint writes one row before returning success.
- F4 adds a "Audit" sub-screen that lists recent audit rows (paginated).

### PII redaction
- Log viewer (F5): server-side regex replaces emails and sleeper_user_ids with
  `<redacted-email>` / `<redacted-sleeper-id>` before returning. Done in the
  lambda, not the client.
- Audit log: `before` / `after` blobs can contain email — they're admin-only
  read, so no redaction needed, but mark the surface as admin-only in the
  endpoint's docstring.

### Test email vs broadcast separation
- The test email path must NEVER write `metadata.broadcast_at`. Enforce by code
  review + a unit test that asserts the test email handler does not call
  `update_metadata`.

### `do_not_broadcast` guardrail
- Broadcast path checks the flag every time, not just on the first call.
  Otherwise a regenerate-and-broadcast could blow past the flag.

---

## Risks (epic level)

| Risk                                                                          | Mitigation                                                                                          |
|-------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------|
| CloudWatch FilterLogEvents throttles under repeated admin tail refreshes      | Client-side 5s rate limit + server-side 60s cache on identical queries                              |
| Preview payload bloat (12 × text_body) pushes API GW response over limit      | Cap each text_body at 4KB; drop html_body from preview response                                     |
| Test email accidentally treated as a broadcast (metadata pollution)           | Code path isolation + unit test asserting no `update_metadata` call                                 |
| Schema drift between table editor allowlist and actual Supabase columns       | Doc checklist on adding new columns + lambda test that fails when an unmapped column is touched     |
| `do_not_broadcast` flag bypassed by `force=true` regenerate-and-broadcast     | Broadcast path re-reads metadata after generation and aborts if flag is true                        |
| Redact only hides from app — admin/users assume it "unsends"                  | Button label is "Hide from app", not "Unsend"; docstring + UI tooltip clarify                       |
| AdminView refactor (F0/F1) ships without parity with current trigger UX       | Refactor preserves all existing trigger cards verbatim under the new "AI Review" sub-screen          |

---

## Open questions for `/plan`

1. **Audit log home**: Supabase table vs Dynamo table. Recommendation says
   Supabase (closer to the rows being edited; easier to query from a future web
   dashboard). Confirm before F4.
2. **Test email "kind" in `notification_log`**: should it use a new kind
   `email_test` or a new template name under existing `kind=email`? Affects the
   activity feed filter UI.
3. **Reports list screen for F3**: do we need a paginated archive view in
   admin, or does "most recent of each type" suffice? Recommend "most recent of
   each type" for F3 and a full archive in F4.
4. **Preview response shape**: include `html_body` (richer preview, ~10x bigger)
   or only `text_body`? Recommend text_body only for V1; html preview becomes
   an F2.5 polish if asked for.
5. **Log allowlist**: confirm the exact log group names to allowlist.
   Expected: `/aws/lambda/api_admin_ai_review_*`, `/aws/lambda/notif_ai_review_weekly`,
   `/aws/lambda/notif_*`, `/aws/lambda/email_*`. Need a definitive list at plan
   time.
6. **iOS form pickers in F4**: native `Picker` over whitelisted users (~12
   rows) is fine, but for `is_active` we need to confirm what happens when a
   league is deactivated mid-season. Out of scope for the editor, but flag it.

---

## Acceptance criteria (epic)

The admin portal epic is done when:

- AdminView is a menu of NavigationLinks; no single screen is > 300 lines.
- Admin can send a test of any of the 3 AI Review report types to any
  whitelisted user without polluting broadcast state. (F1)
- Admin can preview all 12 rendered emails before broadcast and confirm or
  abort. (F2)
- Admin can mark any report as "do not broadcast" before sending, and as
  "hidden from app" after sending. `metadata.broadcast_at` is stamped on every
  real broadcast. (F3)
- Admin can edit `whitelisted_users` and `whitelisted_leagues` rows via typed
  forms with field validation, and every edit lands in `admin_audit`. (F4)
- Admin can filter / search CloudWatch logs for the AI Review + notif lambdas
  with PII redacted server-side. (F5)
- All endpoints behind `require_admin`; non-admin callers get 403.
- Audit log surface ships with F4 and captures every mutating admin action
  going forward.

---

## Notes

- The current `AdminStore` will need to split into multiple stores during F0/F1.
  The trigger logic + activity feed should move to `AIReviewAdminStore`; new
  stores cover Test Email (F1), Preview (F2, may co-locate with AI Review),
  Tables (F4), Logs (F5), Audit (F4).
- Each sub-feature should land behind a feature flag in `Config.swift` so the
  menu screen can hide unfinished sub-screens during incremental rollout.
- Backend deploy: each new lambda is its own dir under `lambdas/api_admin_*`,
  zipped in isolation per existing deploy script behavior.

Brainstorm saved: docs/features/admin-portal/BRAINSTORM.md
Recommendation: Option A across all 8 questions — start with F1 (test email + admin home refactor)
Next: /plan admin-portal — I'll use this doc as context
