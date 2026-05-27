# Plan: Admin Portal — F1 Test Email Sender + Admin Home Refactor

**Epic**: admin-portal
**Sub-feature ID**: F1
**Phase**: Phase 1 — Foundation
**Status**: Ready
**Created**: 2026-05-26
**Last updated**: 2026-05-26
**Depends on**: none (foundation phase; F0 admin home refactor folded in)
**Related**: `docs/features/admin-portal/EPIC_PLAN.md`, `docs/features/admin-portal/BRAINSTORM.md`

---

## Summary

F1 ships two coupled deliverables behind a single PR triplet:

1. **Admin home refactor** — `AdminView` becomes a `NavigationLink` menu (5 entries: AI Review, Test Email, Tables, Logs, Audit). Existing trigger cards + activity feed move under the new "AI Review" sub-screen **verbatim** (no UX redesign). Tables / Logs / Audit are scaffolded as "Coming soon" stubs so F4/F5 have a place to plug in.
2. **Test Email sender** — new backend lambda `POST /admin/email/test` that reuses `build_email_payload` + `ses_helper.send_emails_concurrently` to deliver an existing AI Review report to a single whitelisted recipient. Writes a `notification_log` row with `template = "ai_review_test"`. **Never** writes `metadata.broadcast_at`. New iOS `TestEmailView` + `TestEmailStore` with recipient + report pickers, send button, and a receipt list of recent test sends.

Success: admin can iterate on AI Review email copy by firing any of the three latest reports to any whitelisted user without polluting broadcast state; existing trigger/activity UX survives the refactor unchanged.

---

## Approach

Locked in from `BRAINSTORM.md` Phase 2 (Option A across the board) and refined here:

- **Auth**: reuse `admin_gate.require_admin`. Identical pattern to `api_admin_test_send`.
- **Rendering**: reuse `lambdas.common.email_templates.ai_review.build_email_payload(...)`. Zero duplication of the report→email path.
- **Delivery**: reuse `ses_helper.send_emails_concurrently` with a single-recipient list. Captures success/failure on a per-row basis, which `notification_log.log_email` already records.
- **Isolation invariant**: the test-email lambda must never call `update_metadata` on the report. Enforced via unit test (grep-style assertion: no `update_metadata` import or call).
- **iOS routing**: extend the existing `AppRouter.AppRoute` enum with five admin sub-routes; `MainShell.destinationView(for:)` registers them. `AdminView` (now the menu) calls `router.navigate(to: .adminTestEmail)` etc. — same pattern as `archivePastStandings` introduced in season-refocus F4.
- **Visual treatment**: menu rows mirror the existing AI Review card style — `XomperColors.bgCard` background, `XomperTheme.CornerRadius.lg`, `championGold` accent stroke at 0.3 opacity, `XomperTheme.Spacing.md` internal padding. Each row: SF Symbol icon (left) + title + subtitle (center) + chevron (right).
- **Feature flag (Tables/Logs/Audit)**: per epic acceptance criterion #9, unfinished sub-screens are hidden behind `Config.adminFlags`. F1 ships the menu entries but hides Tables/Logs/Audit by default (they render "Coming soon" if the flag is flipped). AI Review + Test Email are always visible for admin users.

---

## Design Questions — Resolved

| # | Question | Resolution |
|---|----------|------------|
| 1 | Recipient picker source | **`leagueStore.myLeagueUsers` filtered against whitelisted_users from backend** — `historyStore.upcomingUsers` is only populated when the user has tapped into the upcoming-season chip in Draft History; not reliable for the admin tab. Instead, ship a new `XomperAPIClient.fetchWhitelistedUsers()` thin call against the existing Supabase-backed list (or, cheaper, expose the list through the test-email lambda's `GET` companion — see step 6b). v1: server-side enumeration in a single new `GET /admin/email/test/recipients` endpoint that returns `{ rows: [{ sleeper_user_id, display_name, email }] }` from `whitelisted_users where is_active = true`. |
| 2 | Report picker shape | **Latest-per-type for v1.** Three rows: Post-Draft, Preseason, Weekly. Source from `AIReviewStore.latestByType` (already populated for the existing AI Review sub-screen). Full archive view defers to F4. |
| 3 | iOS routing pattern | **`NavigationLink(value:)` with `AppRoute`** — mirror `AppRouter` + typed enum. Add five new cases: `.adminAIReview`, `.adminTestEmail`, `.adminTables`, `.adminLogs`, `.adminAudit`. `MainShell.destinationView(for:)` handles each. |
| 4 | Backend response shape | `{ "Success": true, "recipient_email": "...", "message_id": "ses-mid-...", "sent_at": "2026-05-26T17:42:33Z", "template": "ai_review_test", "report_type": "weekly", "report_period": "2025W04" }`. Includes the SES message_id when available (`ses_helper` already returns this). 4xx errors return `{ "Success": false, "Message": "..." }` shape to match existing admin lambdas. |
| 5 | Activity feed behaviour after refactor | **Unchanged** — filter chips (channel + status) move under AI Review sub-screen as-is. No new filter for `template=ai_review_test`; receipts list in TestEmailView is the dedicated surface for that. |
| 6 | Notification log filter | `api_admin_list_notifications` already accepts `kind` + `status` query params. v1: TestEmailView's receipts list calls the existing endpoint with `kind=email` and post-filters client-side for `template == "ai_review_test"` (we already pull body_snippet + recipient, so template is a small additional field). Backend change: include `template` in `log_email` write + the row's returned shape. **Confirmed**: `log_email` in `notification_log.py` does not currently persist `template` — we'll add it as an optional kwarg threaded through `ses_helper.send_email`. |
| 7 | AdminView visual treatment | Menu rows = `XomperColors.bgCard` + 16pt corner radius + 0.3 opacity champion-gold stroke. Row internals: 28pt SF Symbol (gold), title (`.subheadline.weight(.bold)`, `textPrimary`), subtitle (`.caption`, `textSecondary`), chevron (`.caption`, `textMuted`). Vertical separation = `XomperTheme.Spacing.sm` between rows. Matches existing trigger cards' look. |
| 8 | Tab nesting hazard | Confirmed via `MainShell.swift:51-57` — the existing `NavigationStack(path: $router.path)` wraps every top-level destination, so pushing new `AppRoute.adminTestEmail` from inside the Admin destination root is identical to how `.archivePastStandings` is pushed from `ArchiveView`. **No sub-router needed**. Just register the five new routes alongside the existing season-refocus archive cases. |

---

## Affected Files / Components

### Infrastructure (`xomper-infrastructure`)

| File | Change | Why |
|------|--------|-----|
| `terraform/lambdas_api.tf` | Add 2 entries to `local.api_lambdas`: `admin-email-test` (POST) and `admin-email-test-recipients` (GET) | Routes get registered + lambda stub created via existing `aws_lambda_function.api` for-each. Backend deploy script then overlays real code. |

### Backend (`xomper-back-end`)

| File | Change | Why |
|------|--------|-----|
| `lambdas/api_admin_email_test/__init__.py` | New empty module init | Standard layout for backend lambdas. |
| `lambdas/api_admin_email_test/handler.py` | New `POST` handler | The test-email surface. ~150 lines. |
| `lambdas/api_admin_email_test_recipients/__init__.py` | New empty module init | Companion `GET` for the iOS recipient picker. |
| `lambdas/api_admin_email_test_recipients/handler.py` | New `GET` handler | Returns active whitelisted users. ~40 lines. |
| `lambdas/common/notification_log.py` | Add optional `template` kwarg to `log_email(...)` | Lets us distinguish test sends from real broadcasts in the activity feed + receipts query. |
| `lambdas/common/ses_helper.py` | Thread `template` kwarg through `send_email` → `log_email` | Plumbing only; no behavior change for existing callers. |
| `tests/test_api_admin_email_test.py` | New pytest module | Asserts admin gate, no-`update_metadata` invariant, single-recipient SES call, `notification_log` write with `template="ai_review_test"`. |
| `tests/test_api_admin_email_test_recipients.py` | New pytest module | Asserts admin gate + filtered Supabase query. |

### iOS (`xomper-ios`)

| File | Change | Why |
|------|--------|-----|
| `Xomper/Features/Admin/AdminView.swift` | **Radical simplification** — becomes the menu. Drop all trigger cards, test sender card, filter bar, activity feed. ~100 lines max. | The F0 fold-in. Trigger/feed code relocates into `AIReviewSubScreen.swift`. |
| `Xomper/Features/Admin/AIReviewSubScreen.swift` | **New** — extracts the existing 3 trigger cards + activity feed + filter chips + test sender card. Wraps in its own view, takes `AdminStore` injected from the menu. | Preserves existing UX verbatim. No redesign. Today's `AdminStore` powers this verbatim. |
| `Xomper/Features/Admin/TestEmailView.swift` | **New** — recipient picker (Menu), report picker (latest-per-type), Send button, success/error toast, recent sends list. | F1 deliverable. |
| `Xomper/Features/Admin/TablesStubView.swift` | **New** — single `EmptyStateView` with "Coming soon (F4)" message. | Placeholder; F4 replaces. |
| `Xomper/Features/Admin/LogsStubView.swift` | **New** — single `EmptyStateView` with "Coming soon (F5)" message. | Placeholder; F5 replaces. |
| `Xomper/Features/Admin/AuditStubView.swift` | **New** — single `EmptyStateView` with "Coming soon (F4)" message. | Placeholder; F4 replaces. |
| `Xomper/Core/Stores/TestEmailStore.swift` | **New** `@Observable @MainActor` — owns recipient list, report list, in-flight state, last result. | Per-feature store pattern from the epic plan. |
| `Xomper/Core/Stores/AdminStore.swift` | **No change for F1** | Survives untouched under the AI Review sub-screen. Re-org of this store deferred to F2 (`AIReviewAdminStore`). |
| `Xomper/Navigation/AppRouter.swift` | Add five `AppRoute` cases: `.adminAIReview`, `.adminTestEmail`, `.adminTables`, `.adminLogs`, `.adminAudit` | Routing scaffold for the menu. |
| `Xomper/Features/Shell/MainShell.swift` | Register five new cases in `destinationView(for:)` | Hooks the new routes into the existing nav stack. |
| `Xomper/Core/Networking/XomperAPIClient.swift` | Add `sendTestEmail(recipientSleeperId:reportId:)` → returns `TestEmailResponse`. Add `fetchTestEmailRecipients()` → returns `[TestEmailRecipient]`. Both Decodable structs land in this file alongside existing admin response types. | Public API surface for `TestEmailStore`. |
| `Xomper/Config/Config.swift` (template) | Add `AdminFlags` struct: `showTables`, `showLogs`, `showAudit`, all default `false` | Feature flag gating per epic AC #9. |
| `XomperTests/TestEmailStoreTests.swift` | **New** — verifies recipient + report loading, send success path, error surface, no-op when picker selections nil. | Required for store correctness. |

---

## Implementation Steps

Dependency-ordered. **Infra PR merges first**, then backend, then iOS. Within each PR, commits follow the order below.

### Phase A — Infrastructure (PR #1, `xomper-infrastructure`)

- [ ] **A1**. Add two entries to `local.api_lambdas` in `terraform/lambdas_api.tf`:
  ```hcl
  { name = "admin-email-test",            description = "Admin: send a single AI Review report to one whitelisted user", path_part = "email-test",            http_method = "POST" },
  { name = "admin-email-test-recipients", description = "Admin: list whitelisted users for the test-email picker",       path_part = "email-test-recipients", http_method = "GET"  },
  ```
- [ ] **A2**. Run `terraform plan` locally — should show 2 new `aws_lambda_function`, 2 new API GW routes, 2 new permission attachments. No IAM changes (existing `xomper-lambda-exec` already has SES send + Supabase access).
- [ ] **A3**. Open PR titled `infra(admin-portal F1): add /admin/email-test + /admin/email-test-recipients`. Body: links epic plan + F1 plan, paste plan output, calls out SES quota (already 200/day so within budget).
- [ ] **A4**. After CI green: apply via GitHub Actions (per Terraform-only infra rule — no local apply).
- [ ] **A5**. Confirm via `aws apigateway get-resources` that both new resources exist and are wired to lambda stubs.

### Phase B — Backend (PR #2, `xomper-back-end`)

- [ ] **B1**. Extend `lambdas/common/notification_log.py`:
  - Add `template: Optional[str] = None` kwarg to `log_email(...)`.
  - When non-empty, persist as `item["template"] = template` before `_put`.
  - Add same kwarg to `log_push(...)` for symmetry (future-proofs F2 preview tracking).
- [ ] **B2**. Extend `lambdas/common/ses_helper.py`:
  - Thread `template` through `send_email(...)` → `send_emails_concurrently(...)` signatures.
  - Existing callers pass nothing → keeps behaviour stable.
- [ ] **B3**. Create `lambdas/api_admin_email_test/handler.py`:
  - Imports: `parse_body`, `success_response`, `require_admin`, `NotAdmin`, `build_email_payload`, `send_emails_concurrently`, `get_whitelisted_user_by_sleeper_id`, `ai_reports_table` (Dynamo `get_item` by composite PK/SK).
  - Body schema: `{ "recipient_sleeper_user_id": str, "report_id": str }`. The `report_id` matches the iOS `AIReport.id` (composite `pk|sk`). The handler splits on `|` to derive the Dynamo key.
  - Flow: gate admin → load report (404 if not found) → load recipient (404 if not found / inactive) → derive `report_type` + `period_label` from report metadata → call `build_email_payload(...)` → call `send_emails_concurrently([(email, subject, html, text)], template="ai_review_test")` → return `{Success, recipient_email, message_id, sent_at, template, report_type, report_period}`.
  - **Invariant**: no import of `update_metadata`; no write to Dynamo `ai_reports`. The lambda is read-only against the report table.
- [ ] **B4**. Create `lambdas/api_admin_email_test_recipients/handler.py`:
  - Imports: `success_response`, `require_admin`, `NotAdmin`, `get_active_whitelisted_users`.
  - Flow: gate admin → fetch active users → map to `[{sleeper_user_id, display_name, email}]` (drop is_admin + other fields) → `success_response({"rows": [...], "count": N})`.
- [ ] **B5**. Write `tests/test_api_admin_email_test.py`:
  - **Test 1**: non-admin → 403.
  - **Test 2**: happy path → SES called with single recipient, `notification_log.log_email` called with `template="ai_review_test"`, response includes `message_id`.
  - **Test 3**: missing report → 404.
  - **Test 4**: missing recipient → 404.
  - **Test 5** (invariant): patch `update_metadata` to raise on call; happy-path test still passes (no call made).
- [ ] **B6**. Write `tests/test_api_admin_email_test_recipients.py`:
  - **Test 1**: non-admin → 403.
  - **Test 2**: happy path → returns expected rows from mocked Supabase response.
- [ ] **B7**. Run `pytest lambdas/` + `pytest tests/` → green.
- [ ] **B8**. Open PR titled `feat(admin-portal F1): test email sender lambda + recipients endpoint`. Body links F1 plan; calls out that this is the second of the three coordinated PRs.
- [ ] **B9**. After merge, the backend deploy GitHub Action pushes the lambdas to dev. Hit both routes manually with `curl` (using a known admin JWT) to verify.

### Phase C — iOS (PR #3, `xomper-ios`)

- [ ] **C1**. Add `AdminFlags` to `Config.swift` template + the gitignored `Config.swift`:
  ```swift
  struct AdminFlags {
      static let showTables: Bool = false
      static let showLogs:   Bool = false
      static let showAudit:  Bool = false
  }
  ```
- [ ] **C2**. Extend `AppRouter.AppRoute` with five new cases (`.adminAIReview`, `.adminTestEmail`, `.adminTables`, `.adminLogs`, `.adminAudit`). Doc-comment each.
- [ ] **C3**. Extend `XomperAPIClient`:
  - Add `TestEmailRecipient` Decodable (`sleeper_user_id`, `display_name`, `email`).
  - Add `TestEmailResponse` Decodable (`Success`, `recipient_email`, `message_id`, `sent_at`, `template`, `report_type`, `report_period`).
  - Add `func fetchTestEmailRecipients() async throws -> [TestEmailRecipient]` → GET `/admin/email-test-recipients`.
  - Add `func sendTestEmail(recipientSleeperUserId: String, reportId: String) async throws -> TestEmailResponse` → POST `/admin/email-test`.
  - Add both to `XomperAPIClientProtocol`.
- [ ] **C4**. Create `TestEmailStore.swift`:
  - `@Observable @MainActor final class TestEmailStore`.
  - State: `recipients: [TestEmailRecipient] = []`, `selectedRecipient: TestEmailRecipient? = nil`, `selectedReport: AIReport? = nil`, `isSending = false`, `lastResult: Result<TestEmailResponse, Error>? = nil`, `recentSends: [AdminNotificationLogEntry] = []`.
  - Methods: `loadRecipients()`, `loadRecentSends(sleeperUserId:)` (calls `adminListNotifications` then filters by template), `sendTest()` (uses selected pickers; pre-condition both non-nil), `reset()`.
- [ ] **C5**. Create `TestEmailView.swift`:
  - Reads `aiReviewStore.latestByType` for the report picker (latest of `.postDraft`, `.preseason`, `.weekly`).
  - Recipient picker: `Menu { ForEach(store.recipients) { Button(...) { store.selectedRecipient = $0 } } }`.
  - Report picker: same pattern, 3 rows max.
  - Send button: gold capsule, disabled when either picker is nil or `store.isSending`.
  - Toast: green check on success ("Sent to <email> at <time>"), red X on error (`error.localizedDescription`).
  - Receipts list: `recentSends` filtered to `template == "ai_review_test"`, newest first, 10 visible. Each row: recipient + subject + timestamp + status icon.
  - `.task` loads recipients + recent sends. `.refreshable` re-runs both.
- [ ] **C6**. Create `TablesStubView.swift` / `LogsStubView.swift` / `AuditStubView.swift` — each is a single `EmptyStateView(icon:, title:, message:)` with respective "Coming soon (F4/F5)" copy.
- [ ] **C7**. Create `AIReviewSubScreen.swift`:
  - **Cut + paste** the current `AdminView.content` body verbatim into this view: trigger cards (post-draft, preseason, weekly), test sender card, filter bar, activity feed, all helpers.
  - Accept `AdminStore`, `authStore`, `callerSleeperId`, `callerEmail` as injected props.
  - Move the `.task` + `.refreshable` modifiers in here too.
  - **Verification step**: visual diff a screenshot of the pre-refactor AdminView vs the post-refactor AIReviewSubScreen — must be pixel-identical save for the navigation title.
- [ ] **C8**. Rewrite `AdminView.swift`:
  - Drop all trigger / feed / test-sender content.
  - Keep `isAdmin` gate + EmptyStateView fallback for non-admins.
  - Body becomes a `ScrollView` of 5 menu rows:
    - **AI Review** — `sparkles`, "Trigger reports + activity feed", → `.adminAIReview`. Always visible.
    - **Test Email** — `paperplane`, "Send an AI Review report to one user", → `.adminTestEmail`. Always visible.
    - **Tables** — `tablecells`, "Edit users / leagues / reports", → `.adminTables`. Gated by `Config.AdminFlags.showTables`.
    - **Logs** — `terminal`, "CloudWatch tail + search", → `.adminLogs`. Gated by `Config.AdminFlags.showLogs`.
    - **Audit** — `clock.arrow.circlepath`, "Recent admin actions", → `.adminAudit`. Gated by `Config.AdminFlags.showAudit`.
  - Take `router: AppRouter` as a new param. Pass through from `MainShell`.
- [ ] **C9**. Update `MainShell.swift`:
  - Pass `router` into `AdminView` in the `.admin` destination root case.
  - Add five new cases to `destinationView(for:)`:
    - `.adminAIReview` → `AIReviewSubScreen(authStore:, leagueStore:, aiReviewStore: ?)` — note AIReviewSubScreen takes the same params AdminView used to.
    - `.adminTestEmail` → `TestEmailView(authStore:, aiReviewStore:)` — initialises its own `TestEmailStore`.
    - `.adminTables` → `TablesStubView()`.
    - `.adminLogs` → `LogsStubView()`.
    - `.adminAudit` → `AuditStubView()`.
- [ ] **C10**. Add `xcodegen generate` step. Run iOS build:
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -scheme Xomper -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
  ```
- [ ] **C11**. Write `XomperTests/TestEmailStoreTests.swift`:
  - Mock `XomperAPIClientProtocol`.
  - **Test 1**: `loadRecipients()` populates `recipients`.
  - **Test 2**: `sendTest()` with nil selections → no-op (no API call, `lastResult` stays nil).
  - **Test 3**: `sendTest()` happy path → `isSending` flips, `lastResult` becomes `.success`.
  - **Test 4**: `sendTest()` API error → `lastResult` becomes `.failure`, error message surfaced.
- [ ] **C12**. Manual QA pass on iPhone 17 Pro simulator (per `.claude/CLAUDE.md` available sims):
  - AdminView shows 5 menu rows (or 2 + 3 hidden if flags off).
  - Tap AI Review → trigger cards + activity feed render identically to pre-refactor.
  - Tap Test Email → recipient + report pickers populate; send → toast + receipts row.
  - Tap back → menu intact.
  - Non-admin user → "Admin only" empty state still renders.
- [ ] **C13**. Open PR titled `feat(admin-portal F1): admin home menu refactor + test email sender`. Body links epic plan + F1 plan; tags PRs #1 (infra) and #2 (backend) as merged; calls out screen recordings of the AI Review sub-screen pixel-parity.

### Phase D — Coordination + Sign-off

- [ ] **D1**. After all three PRs merge: `/end-session` to log learnings into `.claude/memory/session-log.md`.
- [ ] **D2**. Update epic plan `EPIC_PLAN.md` orchestration block — flip F1 from Draft to Done; flag F2 as ready to start.
- [ ] **D3**. Flip this plan's Status to `Done`. Update `Last updated` field.

---

## Test Plan

### Backend (`xomper-back-end/tests/`)

| Test | File | Asserts |
|------|------|---------|
| Non-admin returns 403 | `test_api_admin_email_test.py::test_non_admin_403` | Calling without admin claim → 403 + Success=False |
| Happy path single send | `test_api_admin_email_test.py::test_send_success` | SES called with 1 recipient; response has `message_id`, `recipient_email`, `template="ai_review_test"` |
| Missing report → 404 | `test_api_admin_email_test.py::test_missing_report_404` | Unknown `report_id` → 404 |
| Missing recipient → 404 | `test_api_admin_email_test.py::test_missing_recipient_404` | Unknown `recipient_sleeper_user_id` → 404 |
| Never writes metadata | `test_api_admin_email_test.py::test_no_metadata_write` | Patched `update_metadata` raises if called; happy path still green |
| Recipients endpoint admin gate | `test_api_admin_email_test_recipients.py::test_non_admin_403` | 403 without admin claim |
| Recipients endpoint happy | `test_api_admin_email_test_recipients.py::test_returns_active_users` | Returns mapped `[{sleeper_user_id, display_name, email}]` for active users |
| `notification_log` template field | `test_notification_log.py::test_log_email_with_template` | New `template` kwarg persists to Dynamo item; absent when None |

### iOS (`XomperTests/`)

| Test | File | Asserts |
|------|------|---------|
| Store loads recipients | `TestEmailStoreTests.swift::test_loadRecipients_populates` | After `loadRecipients()`, `store.recipients` matches mock |
| No-op without selections | `TestEmailStoreTests.swift::test_sendTest_noop_when_nil` | No API call, no state change when selections nil |
| Send success surfaces result | `TestEmailStoreTests.swift::test_sendTest_success` | `lastResult` is `.success` with correct `recipient_email` |
| Send error surfaces failure | `TestEmailStoreTests.swift::test_sendTest_failure` | `lastResult` is `.failure` with mapped error |
| Recipients endpoint mock | `XomperAPIClientTests.swift::test_fetchTestEmailRecipients_decodes` | Decoder handles the response shape |
| Send endpoint mock | `XomperAPIClientTests.swift::test_sendTestEmail_encodesBody` | POST body matches expected JSON keys |

### Manual QA Checklist

- [ ] Admin sees 5-row menu (or 2 visible + 3 hidden if flags off).
- [ ] AI Review sub-screen identical to pre-refactor AdminView (trigger cards + activity feed + test-sender card).
- [ ] Test Email sub-screen: recipient picker shows 12 active users; report picker shows latest 3.
- [ ] Send button disables while in flight; success toast shows after; receipts row appears within ~3s.
- [ ] Backend SES inbox confirms exactly 1 email delivered per "Send" click.
- [ ] Dynamo `xomper-ai-reports` row's `broadcast_at` metadata field is **untouched** by a test send (verify via console).
- [ ] Non-admin still gets "Admin only" empty state.
- [ ] Hidden Tables/Logs/Audit entries don't appear in the menu when flags are false.
- [ ] When flags are flipped to true (manual `Config.swift` edit), stub screens render "Coming soon" copy.

---

## Acceptance Checklist

- [ ] `POST /admin/email/test` returns `{Success: true, message_id, recipient_email, sent_at, template: "ai_review_test"}` for a happy-path admin call.
- [ ] `GET /admin/email-test-recipients` returns `{rows: [...], count: N}` for active whitelisted users.
- [ ] Both endpoints return 403 for non-admin callers.
- [ ] `notification_log` row written with `template = "ai_review_test"` for every test send.
- [ ] No `update_metadata` call from the test-email handler (enforced by unit test).
- [ ] `AdminView` is < 200 lines and contains zero trigger/activity code.
- [ ] `AIReviewSubScreen` preserves the pre-refactor trigger + activity UX pixel-identically.
- [ ] `TestEmailView` renders pickers + send + receipts; tests pass.
- [ ] `AppRoute` enum has 5 new admin cases; `MainShell.destinationView(for:)` handles each.
- [ ] Three PRs merged in order: infra → backend → iOS.
- [ ] Epic plan's F1 row flipped to Done.

---

## Out of Scope (deferred to later F-features or polish)

- Full reports archive picker for test email (latest-per-type is the V1 surface; F4's Tables sub-feature may add a paginated archive).
- HTML preview in iOS before sending (deferred to F2 which renders the full 12-recipient preview list).
- Audit log row for test sends (F4 retrofits this after the `admin_audit` table ships).
- Pre-flight "do not broadcast" flag (F3).
- Server-side rate limiting on test sends (current SES quota is 200/day — plenty of headroom).
- Push channel for test email (intentional: AI Review reports are email-only).
- Tables / Logs / Audit sub-screens (stubs only here; F4/F5 fill in).

---

## Risks / Tradeoffs

| Risk | Mitigation |
|------|------------|
| AI Review sub-screen UX regression during the cut+paste refactor | Pixel-diff QA step in C7; manual QA item before C13 PR. Reviewer instructed to focus on the trigger card visuals. |
| `notification_log.log_email` signature change ripples into untested callers | New `template` kwarg is optional with `None` default; existing callers untouched. Backend test `test_log_email_no_template_back_compat` asserts. |
| Test email accidentally counted as a broadcast | Code-path isolation + unit test `test_no_metadata_write`. Reviewer checklist: grep PR for any `update_metadata` or `xomper-ai-reports.put_item` reference inside `api_admin_email_test/`. |
| Recipient picker drifts from Supabase (stale list) | `loadRecipients()` runs on every `.task` mount + `.refreshable` pull. ~12 rows so re-fetch cost is trivial. |
| Feature flag misconfiguration ships Tables/Logs/Audit visible | Defaults to `false` in both committed template and gitignored `Config.swift`; reviewer checks no PR diff toggles them. |
| Multiple admins racing send → SES throttling | Send concurrency = 1 (single-recipient list). Within SES burst limit; not a real risk for our 1-admin league. |
| Pushed sub-screens don't survive drawer-driven destination switches | Verified pattern: `archivePastStandings` already works the same way. `router.popToRoot()` fires when drawer switches `currentDestination`. Confirmed in `MainShell.swift:78`. |

---

## Open Questions

- [ ] Confirm SES `Message-ID` is exposed by `ses_helper.send_email` return today — if not, B2 must add it to the return tuple. Quick check before B-phase work begins.
- [ ] Should the Tables/Logs/Audit menu entries render at all when flags are `false`, or be hidden entirely? **Recommendation**: hide entirely (current plan). Discoverability isn't a problem — admin knows when F4/F5 land.
- [ ] Should the receipts list use a dedicated endpoint with `template=ai_review_test` server-side filter, or piggyback on `/admin/notifications` with client-side filter? **Recommendation**: client-side for V1 (simpler), revisit in F4 alongside the audit feed.

---

## Skills / Agents to Use

- **`backend-engineer` agent** for Phase B (lambda + tests + `notification_log` extension).
- **`ios-engineer` agent** for Phase C (AdminView refactor, new views, store, routing).
- **Terraform skill** for Phase A (single `lambdas_api.tf` edit, plan/apply via GitHub Actions per the Terraform-only infra rule).
- **`/execute admin-portal/f1-test-email`** kicks off the three-phase delegation preview after Status flips to Ready.
