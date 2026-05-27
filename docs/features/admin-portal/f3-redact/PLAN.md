# Plan: Admin Portal — F3 Redact + Do-Not-Broadcast + broadcast_at

**Epic**: admin-portal
**Sub-feature ID**: F3
**Phase**: Phase 3 — Broadcast Safety Loop
**Status**: Ready
**Created**: 2026-05-26
**Last updated**: 2026-05-27
**Depends on**: F2 (DNB checkbox lives on `AIReviewPreviewView`)
**Related**: `docs/features/admin-portal/EPIC_PLAN.md`, `docs/features/admin-portal/BRAINSTORM.md` (Q5), `docs/features/admin-portal/f1-test-email/PLAN.md`, `docs/features/admin-portal/f2-preview/PLAN.md`

---

## Summary

F3 closes the broadcast-safety loop with three coordinated capabilities, shipped behind one PR triplet:

1. **Two new metadata flags on AI report rows.** `is_redacted` hides a report from non-admin app surfaces (post-broadcast cleanup). `do_not_broadcast` blocks the broadcast path from sending it (pre-broadcast lock). Both live in the existing `metadata` map on the `xomper-ai-reports` Dynamo row — no schema change, reuses the existing `update_metadata` helper.
2. **Universal `broadcast_at` stamping.** Every successful real broadcast writes `metadata.broadcast_at = <iso8601>`. Post-draft already does this; F3 verifies and replicates for preseason + weekly so all three orchestrators are uniform.
3. **One new flag endpoint + read-side redact filter.** `POST /admin/reports/{league_id}/{report_type}/{period}/flag` toggles either flag (admin-gated). `api_ai_reports_latest` + `api_ai_reports_list` filter out `is_redacted == true` rows for non-admin callers.

iOS surfaces: a "Do not broadcast" checkbox at the top of `AIReviewPreviewView` (locks the Broadcast button when checked); a "Hide from app" kebab action on each row in `AIReviewView` (the archive). Admin-only "Show redacted" toggle in the archive so admins can still see + un-redact rows.

Success: admin can hide any sent report from non-admin surfaces; admin can lock a dry-run report so it cannot be broadcast; every broadcast lands with a `broadcast_at` timestamp; the broadcast path aborts 409 on the second send attempt of a DNB-locked report.

---

## Approach

Locked in from `BRAINSTORM.md` Q5 (Option A) and the epic plan's F3 section:

- **Endpoint shape**: one flag endpoint, body carries `{flag, value}`. Easier to extend (F4 will reuse this exact endpoint for the Reports row of the table editor — no new lambda needed there).
- **Storage**: `metadata.is_redacted = "true"` / `metadata.do_not_broadcast = "true"` via `ai_reports_store.update_metadata`. Booleans persist as strings because the existing flat-map accessor (`AIReport.metadata: [String: String]`) collapses Dynamo `BOOL` to `"true"`/`"false"` already (see `AIReport.swift:46-58`).
- **DNB enforcement point**: re-read the report metadata immediately **before** the SES fan-out, not before Anthropic generation. Reasons: (a) cheap — one `get_item` — and (b) catches the race where an admin checks DNB after generation but before broadcast. Generation is wasteful only when the report is regenerated (`force=true`); the dry-run path doesn't broadcast at all, so DNB doesn't apply there.
- **`broadcast_at` ordering**: stamp **after** `send_emails_concurrently` returns, not before. Matches the epic risk row "race condition on `broadcast_at` write" — partial fan-out failures must not leave the report marked broadcast.
- **Admin detection in read paths**: pass the caller's `is_admin` claim through to `api_ai_reports_latest` / `api_ai_reports_list`. These endpoints don't currently require admin (they're read-only for any authed user), but they do have access to the JWT claims via API GW. Use `admin_gate.is_admin(event)` — a non-raising sibling of `require_admin` — to branch the filter. If the helper doesn't exist yet, add it in `lambdas/common/admin_gate.py` as a 5-line function that returns `bool`.
- **Audit retrofit**: F4 ships the `admin_audit` Supabase table. F3 leaves a `# TODO(F4): admin_audit row` comment block at every mutation point in `api_admin_reports_flag/handler.py`. F4's plan already calls out the retrofit (see EPIC_PLAN.md row "Audit log gaps").
- **iOS routing**: no new routes. The DNB checkbox lives inside the existing `AIReviewPreviewView` (already pushed via `.adminAIReviewPreview(reportType:)`). The Hide-from-app action lives inline on existing `AIReviewView` rows via `Menu`/`.contextMenu`.
- **Store ownership**: extend the existing `AdminStore` (which already owns the preview state) with `setReportFlag(...)`. Also add a `showRedacted: Bool = false` admin toggle on `AIReviewStore` so admins can opt-in to seeing redacted rows. New `ReportFlag` enum is a small `Sendable` type colocated with the API client.

---

## Design Questions — Resolved

| # | Question | Resolution |
|---|----------|------------|
| 1 | Endpoint shape | **Single endpoint, body `{flag, value}`**. Extensible for future flags + reused by F4's reports row of the table editor with zero new code. |
| 2 | Admin detection in read endpoints | **Add `admin_gate.is_admin(event) -> bool`** (non-raising). `api_ai_reports_latest` + `api_ai_reports_list` call it and branch the filter. Avoids passing an explicit `?include_redacted` query param (clients can't be trusted to set it; security through JWT claim is the safer surface). |
| 3 | Confirm dialog wording (iOS Hide action) | **Alert title**: `"Hide \(report.displayTitle)?"` **Message**: `"This removes the report from the league archive. Admins can still see it and un-hide it later. Already-delivered emails are unaffected."` **Primary**: `"Hide"` (destructive). **Secondary**: `"Cancel"`. |
| 4 | DNB checkbox visual treatment | **Checkbox + explanation block at top of `AIReviewPreviewView`, above the Broadcast button.** Row: `Image(systemName: "lock.fill")` (red when checked, muted when unchecked) + Toggle bound to `report.doNotBroadcast` + caption "Locks this report from broadcast. Toggle off to re-enable." When checked the Broadcast button becomes disabled with label `"Locked — DNB flag set"` and a red accent. Destructive-adjacent so we err on the side of "user knows what they did". |
| 5 | Admin view of redacted reports | **Yes — `showRedacted: Bool = false` toggle on `AIReviewView`.** Visible only to admins (gated by `authStore.isAdmin`). When on, redacted rows render with a "REDACTED" badge + 50% opacity + disabled tap (no detail push). Un-redact action is the same kebab → "Show in app". |
| 6 | Audit retrofit | **Stub now, retrofit in F4.** F3 lambda writes a TODO comment at every mutation point and uses the existing `notification_log` table with `kind="admin_action"` as a poor-man's audit trail. F4's backend PR replaces the `notification_log` writes with proper `admin_audit` rows. |
| 7 | `broadcast_at` parity across orchestrators | **Verify post-draft (already implements per F1 epic notes), add to preseason + weekly orchestrators if missing.** Single helper in `lambdas/common/ai_reports_store.py` — `stamp_broadcast_at(league_id, report_type, period)` — called from all three orchestrators after `send_emails_concurrently` returns success. |
| 8 | Read-path filter shape | **Filter in lambda, not Dynamo.** Both `api_ai_reports_latest` and `api_ai_reports_list` already pull the row(s) into Python before serializing. Post-filter list-comprehension `[r for r in rows if is_admin or r["metadata"].get("is_redacted") != "true"]` is one line per endpoint. Dynamo-side filter expression would require a GSI rebuild — not worth it for ~52 rows/year. |

---

## Affected Files / Components

### Infrastructure (`xomper-infrastructure`)

| File | Change | Why |
|------|--------|-----|
| `terraform/lambdas_api.tf` | Add 1 entry to `local.api_lambdas`: `admin-reports-flag` (POST) at path `admin/reports/{league_id}/{report_type}/{period}/flag` | Routes the new flag endpoint via existing `aws_lambda_function.api` for-each. No IAM change — existing exec role already has Dynamo R/W on `xomper-ai-reports`. |

### Backend (`xomper-back-end`)

| File | Change | Why |
|------|--------|-----|
| `lambdas/api_admin_reports_flag/__init__.py` | **New** empty module init | Standard layout. |
| `lambdas/api_admin_reports_flag/handler.py` | **New** `POST` handler. ~90 lines. | The flag endpoint. Validates `flag in {"is_redacted","do_not_broadcast"}` + `value: bool`, calls `update_metadata`, returns the new metadata blob. |
| `lambdas/common/admin_gate.py` | Add `def is_admin(event) -> bool` non-raising helper | Read-path filter needs to branch on caller admin status without raising. |
| `lambdas/common/ai_reports_store.py` | Add `stamp_broadcast_at(league_id, report_type, period)` helper that calls `update_metadata` with `{"broadcast_at": now_iso()}` | Single canonical place to write the stamp. Used by all three orchestrators. |
| `lambdas/api_admin_ai_review_postdraft_trigger/orchestrator.py` | **Verify** DNB check exists immediately before `send_emails_concurrently`. **Verify** `stamp_broadcast_at` is called after a successful broadcast. Refactor to use the new helper if it inlines the metadata write today. | Per session notes post-draft already stamps; confirm + normalize. |
| `lambdas/api_admin_ai_review_preseason_trigger/orchestrator.py` | **Add** DNB pre-fan-out check (409 abort). **Add** `stamp_broadcast_at` call after success. | Replicate post-draft pattern. |
| `lambdas/common/weekly_orchestrator.py` | **Add** DNB pre-fan-out check (409 abort). **Add** `stamp_broadcast_at` call after success. | Replicate post-draft pattern. |
| `lambdas/api_ai_reports_latest/handler.py` | After fetching the row, return `None`/empty when `metadata.is_redacted == "true"` AND caller is **not** admin (use `admin_gate.is_admin`). | Hide redacted from non-admin clients. |
| `lambdas/api_ai_reports_list/handler.py` | After fetching the page, filter out `is_redacted == "true"` rows for non-admin callers. Keep pagination cursor stable — filter is post-query (acceptable for our row counts). | Same as latest. |
| `tests/test_api_admin_reports_flag.py` | **New** pytest module | Non-admin 403; happy path for both flags; rejects unknown flag; rejects missing report; round-trips through `update_metadata`. |
| `tests/test_orchestrator_dnb_abort.py` | **New** pytest module | Each of the three orchestrators aborts with 409 when `metadata.do_not_broadcast == "true"` AND `dry_run=false`. Dry-run path is unaffected. |
| `tests/test_orchestrator_broadcast_at_stamp.py` | **New** pytest module | Each of the three orchestrators calls `stamp_broadcast_at` after `send_emails_concurrently` returns success. Partial-failure case does **not** stamp. |
| `tests/test_api_ai_reports_redact_filter.py` | **New** pytest module | `api_ai_reports_latest` returns the row for admin + omits/returns 404 for non-admin when redacted. `api_ai_reports_list` filters redacted rows for non-admin + includes them for admin. |

### iOS (`xomper-ios`)

| File | Change | Why |
|------|--------|-----|
| `Xomper/Core/Models/AIReport.swift` | Add three computed accessors: `var isRedacted: Bool { metadata["is_redacted"] == "true" }`, `var doNotBroadcast: Bool { metadata["do_not_broadcast"] == "true" }`, `var broadcastAt: Date? { metadata["broadcast_at"].flatMap { Self.parseISO($0) } }`. Expose `parseISO` as `static` (currently `private static`). | The flat-map already collapses Dynamo BOOL to string per `metadata` computed property (lines 46–58) — these are one-liners over the same source of truth. |
| `Xomper/Core/Models/ReportFlag.swift` | **New** — small `enum ReportFlag: String, Sendable { case isRedacted = "is_redacted"; case doNotBroadcast = "do_not_broadcast" }` | Typed input for the API call. |
| `Xomper/Core/Networking/XomperAPIClient.swift` | Add `func setReportFlag(report: AIReport, flag: ReportFlag, value: Bool) async throws -> ReportFlagResponse` to `XomperAPIClientProtocol` + concrete impl. POST to `/admin/reports/<league_id>/<report_type>/<period>/flag` with body `{ "flag": ..., "value": ... }`. Add `ReportFlagResponse: Decodable` with the returned metadata. | The store calls this. |
| `Xomper/Core/Stores/AdminStore.swift` | Add `func setReportFlag(report: AIReport, flag: ReportFlag, value: Bool) async throws`. On success, mutate `lastPreviewsByType` IS NOT applicable (previews aren't the source of truth) — instead, re-fetch the affected `*Latest` report so the trigger card reflects the new flag state. | The store is already the broadcast surface owner; the flag write is broadcast-adjacent. |
| `Xomper/Core/Stores/AIReviewStore.swift` | Add `var showRedacted: Bool = false` (admin-only toggle source of truth) + `func setReportFlag(report:flag:value:) async throws` that delegates to the API client and mutates `archive` in place so the row reflects the change without a full refetch. Re-fetch on flag change is also fine — single-call latency is fast and avoids stale state. | Archive view needs to mutate rows on hide/show. |
| `Xomper/Features/Admin/AIReviewPreviewView.swift` | Add a "Do not broadcast" lock row above `broadcastButton`. When checked, Broadcast button disables with label "Locked — DNB flag set" + `XomperColors.errorRed` accent. Tapping the toggle calls `adminStore.setReportFlag(report: latestReportForType, flag: .doNotBroadcast, value: newValue)`. Source the report via `adminStore.<type>Latest` (the store already loads this). | F3 deliverable; F2's preview surface is the right home per epic plan. |
| `Xomper/Features/AIReview/AIReviewView.swift` | Add `.contextMenu` on each `AIReportCardRow` with two actions: "Hide from app" (when not redacted) / "Show in app" (when redacted). Confirm via `.alert(...)`. Calls `store.setReportFlag(report: report, flag: .isRedacted, value: ...)`. Render redacted rows with a "REDACTED" badge + 50% opacity + disabled `Button(action:)` when `!authStore.isAdmin`. Add a top toolbar toggle "Show redacted" gated by `authStore.isAdmin` — bound to `store.showRedacted`. Filter `store.archive` client-side by `showRedacted` (defense-in-depth — server already filters for non-admin). | F3 deliverable. |
| `Xomper/Features/AIReview/AIReviewView.swift` (continued) | Inject `authStore` + `adminStore` (the latter is optional — only the archive's own `AIReviewStore.setReportFlag` is needed). | Need admin status to gate the toggle + the hide action. |
| `Xomper/Features/Shell/MainShell.swift` | Pass `authStore` into `AIReviewView` initializer (the call site already exists; just thread one more parameter). | Hookup. |
| `XomperTests/AIReportFlagsTests.swift` | **New** — unit tests for the three computed accessors on `AIReport`. | Correctness of the metadata accessor surface. |
| `XomperTests/AdminStoreReportFlagTests.swift` | **New** — mock `XomperAPIClientProtocol`. Asserts: happy path POSTs the right body, error surfaces in `lastError`, no state mutation on failure. | Store correctness. |
| `XomperTests/AIReviewStoreRedactTests.swift` | **New** — asserts `showRedacted` toggle filters `archive` correctly; `setReportFlag` mutates the row in place. | Store correctness. |

---

## Implementation Steps

Dependency-ordered. **Infra PR merges first**, then backend, then iOS. Within each PR, commits follow the order below.

### Phase A — Infrastructure (PR #1, `xomper-infrastructure`)

- [ ] **A1**. Add 1 entry to `local.api_lambdas` in `terraform/lambdas_api.tf`:
  ```hcl
  { name = "admin-reports-flag",
    description = "Admin: toggle is_redacted / do_not_broadcast on an AI report row",
    path_part = "reports/{league_id}/{report_type}/{period}/flag",
    http_method = "POST" },
  ```
  Note: path is nested under `admin/`; confirm the existing for-each handles multi-segment paths (the F1 entries used flat paths, so a small adjustment to the path module may be needed).
- [ ] **A2**. Run `terraform plan` locally — expect 1 new `aws_lambda_function`, 1 new API GW resource chain (`/admin/reports`, `/admin/reports/{league_id}`, etc.), 1 new method, 1 new permission.
- [ ] **A3**. Open PR titled `infra(admin-portal F3): add POST /admin/reports/{...}/flag`. Body links epic plan + F3 plan.
- [ ] **A4**. After CI green: apply via GitHub Actions (Terraform-only infra rule — no local apply).
- [ ] **A5**. Verify via `aws apigateway get-resources` that the four nested path resources exist and the POST method is wired.

### Phase B — Backend (PR #2, `xomper-back-end`)

- [ ] **B1**. Add `lambdas/common/admin_gate.py::is_admin(event) -> bool` non-raising helper. Mirrors `require_admin` minus the raise. Returns `False` when the claim is missing.
- [ ] **B2**. Add `lambdas/common/ai_reports_store.py::stamp_broadcast_at(league_id, report_type, period)` that calls `update_metadata(... {"broadcast_at": datetime.now(timezone.utc).isoformat()})`.
- [ ] **B3**. Audit post-draft orchestrator (`api_admin_ai_review_postdraft_trigger/orchestrator.py`):
  - Confirm there's a DNB metadata check between `build_email_payload(...)` and `send_emails_concurrently(...)`. If missing, add one — abort with 409 + `{"Success": false, "Message": "Report is marked do_not_broadcast. Toggle the flag off to broadcast."}`.
  - Confirm `broadcast_at` is stamped after the SES fan-out returns. If inline today, refactor to call `stamp_broadcast_at(...)`.
  - Add a dry-run guard around the DNB check + stamp — both only apply when `dry_run == False`.
- [ ] **B4**. Repeat B3 for `api_admin_ai_review_preseason_trigger/orchestrator.py`. Replicate the post-draft pattern (probably missing today per the input notes).
- [ ] **B5**. Repeat B3 for `lambdas/common/weekly_orchestrator.py`. Same pattern.
- [ ] **B6**. Create `lambdas/api_admin_reports_flag/handler.py`:
  - Imports: `parse_body`, `success_response`, `error_response`, `require_admin`, `NotAdmin`, `get_report`, `update_metadata`, plus `log_email` (or a new `log_admin_action`) from `notification_log`.
  - Flow:
    1. `require_admin(event)` → raises NotAdmin (caught → 403).
    2. Parse path params: `league_id`, `report_type`, `period`.
    3. Parse body: `flag` (must be `"is_redacted"` or `"do_not_broadcast"`), `value` (must be bool). Reject 400 on anything else.
    4. `get_report(league_id, report_type, period)` → 404 if missing.
    5. `update_metadata(league_id, report_type, period, {flag: "true" if value else "false"})`.
    6. `# TODO(F4): admin_audit row` (or call the placeholder `log_admin_action` helper if cheap).
    7. Return `success_response({"Success": true, "flag": flag, "value": value, "metadata": <full updated map>})`.
- [ ] **B7**. Modify `lambdas/api_ai_reports_latest/handler.py`:
  - After fetching the row, if `metadata.get("is_redacted") == "true"` AND `not is_admin(event)` → return 404 (treat as "not found" so non-admin clients don't even learn the row exists).
- [ ] **B8**. Modify `lambdas/api_ai_reports_list/handler.py`:
  - After fetching the page, filter rows: `rows = [r for r in rows if is_admin(event) or r.get("metadata", {}).get("is_redacted") != "true"]`.
  - **Cursor caveat**: filter is post-query. Page size can shrink below the requested limit. Acceptable — iOS infinite scroll already handles short pages.
- [ ] **B9**. Write `tests/test_api_admin_reports_flag.py`:
  - **T1**: non-admin → 403.
  - **T2**: invalid `flag` → 400.
  - **T3**: missing `value` → 400.
  - **T4**: unknown report → 404.
  - **T5**: happy path `is_redacted=true` → returns metadata with flag set, `update_metadata` called once.
  - **T6**: happy path `do_not_broadcast=true` → same.
  - **T7**: round-trip — set then unset (idempotency).
- [ ] **B10**. Write `tests/test_orchestrator_dnb_abort.py`:
  - For each of the three orchestrators:
    - **T1**: report has `do_not_broadcast=true`, `dry_run=false` → 409 + clear message; `send_emails_concurrently` NOT called.
    - **T2**: report has `do_not_broadcast=true`, `dry_run=true` → dry-run path unaffected (no abort).
    - **T3**: report has `do_not_broadcast=false`, `dry_run=false` → normal send path runs.
- [ ] **B11**. Write `tests/test_orchestrator_broadcast_at_stamp.py`:
  - For each orchestrator:
    - **T1**: `dry_run=false` + successful SES → `stamp_broadcast_at` called once.
    - **T2**: `dry_run=false` + partial failure (SES raises) → `stamp_broadcast_at` NOT called.
    - **T3**: `dry_run=true` → `stamp_broadcast_at` NOT called.
- [ ] **B12**. Write `tests/test_api_ai_reports_redact_filter.py`:
  - **T1**: `latest` returns row for admin caller when `is_redacted=true`.
  - **T2**: `latest` returns 404 for non-admin caller when `is_redacted=true`.
  - **T3**: `list` includes redacted rows for admin caller.
  - **T4**: `list` filters out redacted rows for non-admin caller.
- [ ] **B13**. Run `pytest lambdas/` + `pytest tests/` → green.
- [ ] **B14**. Open PR titled `feat(admin-portal F3): reports flag endpoint + DNB enforcement + broadcast_at stamp`. Body links F3 plan; calls out the three orchestrators + the two read-path changes.
- [ ] **B15**. After merge, backend deploy lambda push. Hit `POST /admin/reports/.../flag` via `curl` with a known admin JWT + a known report; verify metadata via Dynamo console.

### Phase C — iOS (PR #3, `xomper-ios`)

- [ ] **C1**. Extend `AIReport.swift`:
  - Make `parseISO` `internal static` (currently `private static`) so the new accessor can use it. Alternatively keep private and call it through a wrapper computed property — pick the lighter touch.
  - Add `var isRedacted: Bool { metadata["is_redacted"] == "true" }`.
  - Add `var doNotBroadcast: Bool { metadata["do_not_broadcast"] == "true" }`.
  - Add `var broadcastAt: Date? { metadata["broadcast_at"].flatMap { AIReport.parseISO($0) } }`.
- [ ] **C2**. Create `Xomper/Core/Models/ReportFlag.swift`:
  ```swift
  enum ReportFlag: String, Sendable {
      case isRedacted = "is_redacted"
      case doNotBroadcast = "do_not_broadcast"
  }
  ```
- [ ] **C3**. Extend `XomperAPIClient`:
  - Add `ReportFlagResponse: Decodable` with `success: Bool`, `flag: String`, `value: Bool`, `metadata: [String: JSONValue]?` (raw map; iOS doesn't need to consume it but it's there for forward compat).
  - Add `func setReportFlag(report: AIReport, flag: ReportFlag, value: Bool) async throws -> ReportFlagResponse` to `XomperAPIClientProtocol`. Concrete impl parses `report.id` (composite `LEAGUE#<id>|REPORT#<type>#<period>`) to derive path params, then POSTs to `/admin/reports/<league_id>/<report_type>/<period>/flag` with body `{ "flag": flag.rawValue, "value": value }`.
- [ ] **C4**. Extend `AdminStore.swift`:
  - Add `func setReportFlag(report: AIReport, flag: ReportFlag, value: Bool) async throws`. On success: re-load the affected `*Latest` (`postDraftLatest`, `preseasonLatest`, or `weeklyLatest`) so the trigger card / preview view reflects the new state.
- [ ] **C5**. Extend `AIReviewStore.swift`:
  - Add `var showRedacted: Bool = false` (admin opt-in to see redacted rows in the archive).
  - Add `func setReportFlag(report: AIReport, flag: ReportFlag, value: Bool) async throws`. On success: mutate the matching entry in `archive` in place (find by `report.id`, replace with a re-fetched copy or apply the flag locally — pick local mutation via a memberwise rebuild for instant UI feedback).
- [ ] **C6**. Modify `AIReviewPreviewView.swift`:
  - Resolve `currentReport: AIReport?` from `adminStore.<type>Latest` (switch on `reportType`).
  - Above `broadcastButton`, render a `dnbLockRow`:
    - `HStack(spacing: XomperTheme.Spacing.sm) { Image(systemName: doNotBroadcast ? "lock.fill" : "lock.open"); Toggle("Do not broadcast", isOn: dnbBinding); Spacer() }`
    - Caption below: `Text("Locks this report from being broadcast. Toggle off to re-enable.")`.
    - Toggle binding fires `Task { try? await adminStore.setReportFlag(report: currentReport, flag: .doNotBroadcast, value: $0) }`.
  - `broadcastButton.disabled(...)` now also disables when `currentReport?.doNotBroadcast == true`. When disabled for DNB reason, change the label to `"Locked — DNB flag set"` and tint the background `XomperColors.errorRed.opacity(0.5)`.
  - Add a small `@State private var dnbInFlight = false` so the toggle disables itself during the round-trip.
- [ ] **C7**. Modify `AIReviewView.swift`:
  - Pass `authStore: AuthStore` as a new init param.
  - Add `@State private var pendingHide: AIReport?` for the confirm dialog state.
  - Wrap each `AIReportCardRow` with a `.contextMenu` (long-press) that exposes:
    - **Hide from app** (when `!report.isRedacted`, admin only) → sets `pendingHide = report`.
    - **Show in app** (when `report.isRedacted`, admin only) → calls `store.setReportFlag(... .isRedacted, value: false)` directly (less destructive — no confirm).
  - Add `.alert("Hide \(pendingHide?.displayTitle ?? "")?", isPresented: pendingHideBinding) { Button("Cancel", role: .cancel) {}; Button("Hide", role: .destructive) { Task { ... } } } message: { Text("This removes the report from the league archive. Admins can still see it and un-hide it later. Already-delivered emails are unaffected.") }`.
  - Add a top toolbar `Toggle("Show redacted", isOn: $store.showRedacted)` gated by `authStore.isAdmin`.
  - Render redacted rows with a "REDACTED" badge (red caps text, top-right corner) + `.opacity(0.5)` + `.disabled(!authStore.isAdmin)` on the underlying Button so non-admins can't tap.
  - Client-side filter (defense-in-depth): `let visible = store.archive.filter { !$0.isRedacted || store.showRedacted }`. Replace `store.archive` with `visible` in the existing `ForEach`.
- [ ] **C8**. Modify `MainShell.swift`:
  - Pass `authStore` into the `AIReviewView` call site.
- [ ] **C9**. Run `xcodegen generate` + iOS build:
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -scheme Xomper -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
  ```
- [ ] **C10**. Write `XomperTests/AIReportFlagsTests.swift`:
  - **T1**: `isRedacted` true when `metadata["is_redacted"] == "true"`.
  - **T2**: `doNotBroadcast` true when `metadata["do_not_broadcast"] == "true"`.
  - **T3**: `broadcastAt` parses ISO8601 with and without fractional seconds.
  - **T4**: all three default to false/nil when metadata absent.
- [ ] **C11**. Write `XomperTests/AdminStoreReportFlagTests.swift`:
  - Mock `XomperAPIClientProtocol`.
  - **T1**: `setReportFlag` happy path → mock client called with right args; latest re-fetched.
  - **T2**: API error → throws, latest not mutated.
- [ ] **C12**. Write `XomperTests/AIReviewStoreRedactTests.swift`:
  - **T1**: `showRedacted=false` filters out redacted entries (caller view derivation).
  - **T2**: `setReportFlag(... .isRedacted, value: true)` mutates the entry in place after API success.
  - **T3**: API failure leaves the entry unchanged.
- [ ] **C13**. Manual QA pass on iPhone 17 Pro simulator (admin acct):
  - Fire dry-run for any report type → preview opens. Toggle "Do not broadcast" on → Broadcast button greys out + label changes. Toggle off → button restored. Sleeper-DB inspection: `metadata.do_not_broadcast` round-trips.
  - Attempt broadcast on a DNB-locked report (toggle off → broadcast → back → toggle on → broadcast) → 409 surfaces inline in the preview view (existing `broadcastError` path).
  - Open AI Review archive. Long-press a row → "Hide from app" → confirm. Row disappears from non-admin view (toggle showRedacted off). Toggle showRedacted on → row reappears with REDACTED badge + dim. Long-press → "Show in app" → row reverts.
  - Non-admin acct: archive does not show the toggle; redacted rows never appear at all (server filter).
- [ ] **C14**. Open PR titled `feat(admin-portal F3): redact + DNB + broadcast_at stamping`. Body links epic plan + F3 plan; tags PRs #1 (infra) + #2 (backend) as merged; screen recordings of both the preview DNB lock + the archive hide action.

### Phase D — Coordination + Sign-off

- [ ] **D1**. After all three PRs merge: `/end-session` to log learnings into `.claude/memory/session-log.md`.
- [ ] **D2**. Update `EPIC_PLAN.md` orchestration block — flip F3 from Draft to Done; flag F4 as ready to start (F4 retrofits audit writes into F1 + F3 lambdas).
- [ ] **D3**. Flip this plan's Status to `Done`. Update `Last updated` field.

---

## Test Plan

### Backend (`xomper-back-end/tests/`)

| Test | File | Asserts |
|------|------|---------|
| Non-admin 403 | `test_api_admin_reports_flag.py::test_non_admin_403` | 403 + `Success=False` |
| Invalid flag rejected | `test_api_admin_reports_flag.py::test_invalid_flag_400` | 400 on `flag="bogus"` |
| Missing value rejected | `test_api_admin_reports_flag.py::test_missing_value_400` | 400 when body lacks `value` |
| Unknown report | `test_api_admin_reports_flag.py::test_unknown_report_404` | 404 |
| Set is_redacted | `test_api_admin_reports_flag.py::test_set_is_redacted` | `update_metadata` called with `{"is_redacted": "true"}` |
| Set do_not_broadcast | `test_api_admin_reports_flag.py::test_set_do_not_broadcast` | same for DNB |
| Idempotent unset | `test_api_admin_reports_flag.py::test_round_trip` | set+unset = original metadata |
| DNB aborts broadcast (postdraft) | `test_orchestrator_dnb_abort.py::test_postdraft_dnb_abort` | 409, no SES call |
| DNB aborts broadcast (preseason) | `test_orchestrator_dnb_abort.py::test_preseason_dnb_abort` | 409, no SES call |
| DNB aborts broadcast (weekly) | `test_orchestrator_dnb_abort.py::test_weekly_dnb_abort` | 409, no SES call |
| DNB does NOT abort dry-run | `test_orchestrator_dnb_abort.py::test_dry_run_unaffected` | dry-run path runs |
| broadcast_at stamped on success (×3 orchestrators) | `test_orchestrator_broadcast_at_stamp.py::test_*_stamps_on_success` | `stamp_broadcast_at` called once |
| broadcast_at NOT stamped on SES failure | `test_orchestrator_broadcast_at_stamp.py::test_*_no_stamp_on_failure` | helper not called |
| Redact filter: latest hides for non-admin | `test_api_ai_reports_redact_filter.py::test_latest_hides_for_non_admin` | 404 returned |
| Redact filter: latest visible for admin | `test_api_ai_reports_redact_filter.py::test_latest_visible_for_admin` | row returned |
| Redact filter: list filters for non-admin | `test_api_ai_reports_redact_filter.py::test_list_filters_for_non_admin` | redacted rows absent |
| Redact filter: list includes for admin | `test_api_ai_reports_redact_filter.py::test_list_includes_for_admin` | redacted rows present |

### iOS (`XomperTests/`)

| Test | File | Asserts |
|------|------|---------|
| `isRedacted` accessor | `AIReportFlagsTests.swift::test_isRedacted_true_when_metadata` | true/false branches |
| `doNotBroadcast` accessor | `AIReportFlagsTests.swift::test_doNotBroadcast_true_when_metadata` | true/false branches |
| `broadcastAt` parses ISO | `AIReportFlagsTests.swift::test_broadcastAt_parses_iso` | with + without fractional seconds |
| `AdminStore.setReportFlag` happy | `AdminStoreReportFlagTests.swift::test_setReportFlag_happy` | mock client called; latest re-fetched |
| `AdminStore.setReportFlag` error | `AdminStoreReportFlagTests.swift::test_setReportFlag_error` | throws, latest not mutated |
| `AIReviewStore.showRedacted` filter | `AIReviewStoreRedactTests.swift::test_showRedacted_filters` | derived view respects toggle |
| `AIReviewStore.setReportFlag` mutates | `AIReviewStoreRedactTests.swift::test_setReportFlag_mutates_in_place` | matching row replaced |
| `AIReviewStore.setReportFlag` error | `AIReviewStoreRedactTests.swift::test_setReportFlag_error_no_mutation` | archive untouched |

### Manual QA Checklist

- [ ] Dry-run a report → open preview → toggle DNB on → Broadcast button shows "Locked — DNB flag set" + red tint + disabled.
- [ ] Toggle DNB off → Broadcast button restored.
- [ ] DNB state survives app restart (Dynamo persistence).
- [ ] Force a real broadcast on a DNB-locked report by toggling off, broadcasting, then locking — second broadcast attempt 409s with clear message in `broadcastError`.
- [ ] After successful broadcast (any of the 3 types) → Dynamo row has `metadata.broadcast_at` populated.
- [ ] Long-press archive row → "Hide from app" → confirm dialog → row disappears from non-admin view.
- [ ] Admin toggle "Show redacted" on → redacted row visible with REDACTED badge + dim.
- [ ] Long-press redacted row → "Show in app" → row reverts to normal.
- [ ] Non-admin acct: archive never shows redacted rows AND no "Show redacted" toggle.
- [ ] Non-admin acct: `/ai-reports/latest` returns 404 for a redacted report; `/ai-reports/list` omits it.

---

## Acceptance Checklist

- [ ] `POST /admin/reports/{league_id}/{report_type}/{period}/flag` returns `{Success: true, flag, value, metadata}` for happy-path admin call.
- [ ] Endpoint returns 403 for non-admin callers.
- [ ] Endpoint returns 400 for unknown flag names or non-bool values.
- [ ] All three orchestrators abort with 409 when `metadata.do_not_broadcast == "true"` AND `dry_run=false`.
- [ ] All three orchestrators stamp `metadata.broadcast_at` after successful SES fan-out (and only after).
- [ ] `api_ai_reports_latest` returns 404 for non-admin callers when the row is redacted.
- [ ] `api_ai_reports_list` filters redacted rows for non-admin callers.
- [ ] `AIReport` exposes `isRedacted`, `doNotBroadcast`, `broadcastAt` computed properties.
- [ ] `AIReviewPreviewView` has a DNB lock row; Broadcast button locks when checked.
- [ ] `AIReviewView` has a context-menu hide/show action with confirm dialog.
- [ ] `AIReviewView` admin "Show redacted" toggle works; redacted rows render with badge + dim when visible.
- [ ] All backend + iOS tests pass.
- [ ] Three PRs merged in order: infra → backend → iOS.
- [ ] Epic plan's F3 row flipped to Done.

---

## Out of Scope (deferred to F4 or polish)

- `admin_audit` Supabase table + row writes (F4 ships the table and retrofits audit writes into F3's flag endpoint).
- Bulk redact / un-redact actions (e.g. "Hide all preseason reports"). Single-row only for V1.
- "Redacted by X on Y" badge metadata (would require capturing `actor_sleeper_id` + `redacted_at` in metadata; deferred since the audit table covers this in F4).
- Paginated archive picker for setting DNB pre-emptively on rows that aren't the latest (V1 only locks the latest report per type — that's the only one the preview surface ever shows).
- Push notification when a report is redacted (no use case yet).
- Recall already-delivered email (impossible — the dialog wording is "Hide from app" for this exact reason).
- iOS detail-view UX for redacted reports (V1: detail still opens for admin tap on a redacted row in `showRedacted=true` mode; non-admin can never reach the detail anyway because the row is filtered).

---

## Risks / Tradeoffs

| Risk | Mitigation |
|------|------------|
| DNB check runs after Anthropic generation (wasteful when admin sets DNB between dry-run and broadcast) | Accepted: the alternative (check before generation) misses the race where DNB is set between generation and broadcast. Generation cost is bounded (≤1 Claude call per broadcast attempt). |
| `broadcast_at` race: stamping fires before SES fan-out completes, partial failure leaves report marked broadcast | Stamp AFTER `send_emails_concurrently` returns success. Unit test `test_*_no_stamp_on_failure` enforces. |
| Audit gap between F3 ship and F4 retrofit | `# TODO(F4): admin_audit row` comments at every mutation point + grep gate in F4's PR review. Acceptable risk for a 12-person league with one admin. |
| Redact filter applied post-query → pages can shrink below requested limit | Acceptable — infinite scroll already handles short pages. Documented in B8 step. |
| `parseISO` visibility change ripples | Either make it `internal static` (small surface change) or add a thin wrapper accessor — pick lighter touch in C1. |
| `metadata` Dynamo Map writes overwrite vs merge | `update_metadata` merges by design (used by every other path already). Test T7 round-trips to confirm. |
| iOS `setReportFlag` race when admin double-taps the toggle | `@State dnbInFlight` disables the toggle during the round-trip. |
| Non-admin learns redacted reports exist (timing attack on 404 vs 200) | Acceptable for a closed-league app. The 404 is identical to a missing report so no info leak. |
| Existing post-draft orchestrator already stamps but in a different shape than the new helper | B3 explicitly refactors to use `stamp_broadcast_at` so all three orchestrators write the same key with the same format. |

---

## Open Questions

- [ ] Verify post-draft orchestrator's current `broadcast_at` write — if it stamps a non-ISO format or a different key, B3 normalizes. Confirm at start of Phase B.
- [ ] Should the DNB toggle on the preview view also clear the local previews so the admin re-runs dry-run to confirm? **Recommendation**: no — DNB is reversible and previews are still useful for inspection. The Broadcast button being locked is enough signal.
- [ ] Should `AIReviewStore.setReportFlag` re-fetch the row from the backend after success, or mutate locally? **Recommendation**: mutate locally for instant UI feedback; the backend's `update_metadata` is the source of truth, but the flag is the only thing changing so the local mutation is safe. Documented in C5.
- [ ] Do we want a "broadcast at" timestamp surfaced anywhere in the iOS UI in F3, or defer to F4? **Recommendation**: defer — `AIReport.broadcastAt` is exposed on the model but no view consumes it in F3. F4's table editor naturally shows it as a row column.

---

## Skills / Agents to Use

- **`backend-engineer` agent** for Phase B (lambda + helpers + orchestrator updates + tests).
- **`ios-engineer` agent** for Phase C (model accessors, store extensions, preview + archive view edits).
- **Terraform skill** for Phase A (single `lambdas_api.tf` edit + GitHub Actions apply per the Terraform-only infra rule).
- **`/execute admin-portal/f3-redact`** kicks off the three-phase delegation preview after Status flips to Ready.
