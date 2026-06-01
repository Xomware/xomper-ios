# Plan: Admin Cron Settings — Kill Switch + Test Mode

**Status**: Ready
**Created**: 2026-06-01
**Last updated**: 2026-06-01
**Repos touched**: xomper-infrastructure, xomper-back-end, xomper-ios

---

## Summary

Give admin (Dominick) two switches per scheduled lambda: an **Enabled** kill switch (no-op the lambda) and a **Test Mode** flag (run normally but restrict delivery to admin's Sleeper user_id `594625531702460416`). Backed by a new Supabase `admin_cron_settings` table, two new admin-gated API endpoints, lambda-side wraps on five notif lambdas, and a new iOS sub-screen under `AdminView`. Test mode lets us preview AI Review newsletters + recap emails before they fan out to the league; the kill switch is a safety belt against the offseason guard.

---

## Approach

- One row per **lambda** (not per EventBridge rule) in `admin_cron_settings`. `notif_close_game_alert` fires from two rules but has a single setting.
- Lambdas read `admin_cron_settings` on cold start via a `lambdas/common/cron_settings.py` helper. **Best-effort read**: on Supabase failure, default to `{enabled: True, test_mode: False}` — the offseason guard is the primary safety, so we prefer "send" over "skip" when settings are unreachable.
- Test mode reuses each lambda's existing recipient-resolution code path: filter the active-user list down to admin only before SES/SNS fanout. For F3's AI Review weekly orchestrator (already has `dry_run`), pass `test_mode` through as `dry_run=True`.
- EventBridge rules stay enabled regardless — disabling a cron just makes the lambda no-op cheaply. Cheaper to administer (single Supabase write) and avoids Terraform churn on every toggle.
- Migration applied **out-of-band** via Supabase dashboard (same pattern as F4's `admin_audit`). SQL committed under `xomper-back-end/sql/`.
- Two admin endpoints (`GET` list, `POST` update), each as its own API GW resource since the API GW module is one-method-per-`path_part`. Update writes an `admin_audit` row.

---

## Affected Files / Components

### xomper-infrastructure

| File | Change | Why |
|------|--------|-----|
| `terraform/lambdas_api.tf` | Add `admin-cron-settings-list` (GET) + `admin-cron-settings-update` (POST) entries | Expose endpoints behind API GW with admin auth |

### xomper-back-end

| File | Change | Why |
|------|--------|-----|
| `sql/admin_cron_settings_migration.sql` | New: create table + seed 5 rows | Schema applied manually via Supabase dashboard |
| `lambdas/common/cron_settings.py` | New: `get_cron_setting`, `update_cron_setting`, `list_cron_settings` | Shared helper across all five notif lambdas + both endpoints |
| `lambdas/common/constants.py` | Add `ADMIN_DOMINICK_USER_ID = "594625531702460416"` if not present | Used by every lambda's test-mode filter |
| `lambdas/api_admin_cron_settings_list/__init__.py` + `handler.py` | New: GET endpoint returning all rows | iOS list source |
| `lambdas/api_admin_cron_settings_update/__init__.py` + `handler.py` | New: POST endpoint patching one row + writing `admin_audit` | iOS edit target |
| `lambdas/notif_weekly_recap/handler.py` | Add enabled check + test-mode recipient filter | Wrap with kill switch + preview gate |
| `lambdas/notif_lineup_not_set/handler.py` | Same | Same |
| `lambdas/notif_close_game_alert/handler.py` | Same | Single setting covers both Sun + Mon firings |
| `lambdas/notif_worldcup_movement/handler.py` | Same | Same |
| `lambdas/notif_ai_review_weekly/handler.py` | Add enabled check + map `test_mode -> dry_run=True` on orchestrator call | Reuse F3's existing dry-run path instead of duplicating filter logic |
| `tests/common/test_cron_settings.py` | New: helper unit tests (failure default, patch round-trip) | Lock the best-effort failure mode |
| `tests/api/test_admin_cron_settings_list.py` | New | Endpoint coverage |
| `tests/api/test_admin_cron_settings_update.py` | New: include audit-row assertion | Endpoint + audit plumbing |
| `tests/notif/test_*_settings_gate.py` (5 files) | New: per-lambda — assert skip when `enabled=false`, assert admin-only when `test_mode=true` | Pin per-lambda integration |

### xomper-ios

| File | Change | Why |
|------|--------|-----|
| `Xomper/Core/Models/CronSetting.swift` | New: Codable struct `{cronKey, enabled, testMode, description, updatedAt}` | Model for list + patch responses |
| `Xomper/Core/Stores/CronSettingsStore.swift` | New: `@Observable @MainActor` — `load()`, `toggleEnabled(key:)`, `toggleTestMode(key:)`, optimistic update + rollback on failure | Drives the new sub-screen |
| `Xomper/Core/Networking/XomperAPIClient.swift` | Add `fetchCronSettings()` + `updateCronSetting(key:enabled:testMode:)` | Wire to the two new endpoints |
| `Xomper/Features/Admin/CronSettingsView.swift` | New: list view, one row per cron with two toggles + description | Admin UI |
| `Xomper/Features/Admin/AdminView.swift` | Add menu row "Cron Settings" with `clock.badge.checkmark` icon between AI Review and Tables | Entry point |
| `Xomper/Navigation/AppRouter.swift` | Add `.adminCronSettings` route case | Routing |
| `Xomper/Features/Shell/MainShell.swift` | Wire route to `CronSettingsView` | Navigation glue |
| `Xomper/Config/Config.swift.template` | Add `AdminFlags.showCronSettings = true` flag | Feature flag (consistency w/ other admin sub-screens) |
| `.github/workflows/testflight-deploy.yml` | Update Config.swift heredoc to match template | Lesson learned from PR #113 — heredoc must mirror template |
| `XomperTests/Stores/CronSettingsStoreTests.swift` | New: load + toggle round-trip + rollback-on-failure tests | Store coverage |
| `XomperTests/Features/Admin/CronSettingsViewTests.swift` | New: snapshot or render assertions | UI coverage |

---

## Implementation Steps

### Phase 1 — Infrastructure (PR #1: xomper-infrastructure)

- [ ] Add `admin-cron-settings-list` GET entry to `terraform/lambdas_api.tf`
- [ ] Add `admin-cron-settings-update` POST entry to `terraform/lambdas_api.tf`
- [ ] Verify both routes flow through the existing admin authorizer
- [ ] `terraform plan` — confirm only the two new resources are added
- [ ] Open PR, merge, apply via CI

### Phase 2 — Backend (PR #2: xomper-back-end)

- [ ] Write `sql/admin_cron_settings_migration.sql` with table + 5 seeded rows
- [ ] Apply migration manually via Supabase dashboard (document in PR body)
- [ ] Add `ADMIN_DOMINICK_USER_ID` constant if missing
- [ ] Write `lambdas/common/cron_settings.py`:
  - `get_cron_setting(cron_key)` — Supabase select; on exception, log warn + return `{enabled: True, test_mode: False, description: None}`
  - `update_cron_setting(cron_key, enabled, test_mode)` — upsert with `updated_at = now()`; raise on failure
  - `list_cron_settings()` — select all, order by `cron_key`
- [ ] Write `tests/common/test_cron_settings.py` — failure-mode default + happy path
- [ ] Implement `api_admin_cron_settings_list` (GET, admin-gated, returns array)
- [ ] Implement `api_admin_cron_settings_update` (POST, admin-gated, body `{cron_key, enabled?, test_mode?}`, writes `admin_audit` row with `action="cron_settings.update"` and the diff)
- [ ] Write endpoint tests including the audit-row assertion
- [ ] Wrap `notif_weekly_recap/handler.py`:
  ```python
  setting = get_cron_setting("notif_weekly_recap")
  if not setting["enabled"]:
      log.info("notif_weekly_recap disabled — skipping")
      return success_response({"Success": True, "skipped": True, "reason": "disabled"})
  test_mode = setting["test_mode"]
  # ... existing logic ...
  if test_mode:
      recipients = [u for u in recipients if u["sleeper_user_id"] == ADMIN_DOMINICK_USER_ID]
  ```
- [ ] Wrap `notif_lineup_not_set/handler.py` — same pattern
- [ ] Wrap `notif_close_game_alert/handler.py` — same pattern (one setting covers both rule firings)
- [ ] Wrap `notif_worldcup_movement/handler.py` — same pattern
- [ ] Wrap `notif_ai_review_weekly/handler.py` — enabled check + map `test_mode -> dry_run=True` into orchestrator invocation
- [ ] Write 5 per-lambda integration tests (skip-on-disabled, admin-only-on-test-mode)
- [ ] Run full test suite — all green
- [ ] Open PR

### Phase 3 — iOS (PR #3: xomper-ios)

- [ ] Add `CronSetting` model with snake_case ↔ camelCase Codable
- [ ] Add API client methods `fetchCronSettings`, `updateCronSetting`
- [ ] Build `CronSettingsStore` with optimistic toggle + rollback on patch failure
- [ ] Build `CronSettingsView` — `List` of rows, each row: title (description), `Toggle("Enabled")`, `Toggle("Test mode")`, subtle disabled-state styling when `enabled=false`
- [ ] Add `Config.AdminFlags.showCronSettings` (default `true`)
- [ ] Update `testflight-deploy.yml` heredoc to mirror template (PR #113 lesson)
- [ ] Add `.adminCronSettings` to `AppRouter`
- [ ] Wire route in `MainShell`
- [ ] Add menu row to `AdminView` with `clock.badge.checkmark` icon, gated on `Config.AdminFlags.showCronSettings`
- [ ] Write `CronSettingsStoreTests` — load, toggle, rollback
- [ ] Write `CronSettingsViewTests` — render with mock store
- [ ] `xcodegen generate` + build for iPhone 17 Pro simulator — green
- [ ] Open PR

### Phase 4 — Cutover & Validation

- [ ] Merge PRs in order: infra → backend → iOS
- [ ] Confirm rows visible in iOS app, all defaulting to `enabled=true, test_mode=false`
- [ ] Flip `notif_ai_review_weekly` to `test_mode=true`, wait for next Tue 2pm ET cron, confirm only admin receives email
- [ ] Flip back to `test_mode=false` before league-wide send
- [ ] Confirm `admin_audit` rows captured every toggle

---

## Out of Scope

- Per-EventBridge-rule control (close_game_alert stays as one setting)
- Rescheduling / changing cron expressions from the iOS app
- Disabling EventBridge rules themselves (lambdas no-op instead)
- Surfacing cron settings to non-admin users
- Historical view of past toggle states (only `updated_at` on the row; full history lives in `admin_audit`)
- Adjusting the offseason guard behavior (separate concern)

---

## Risks / Tradeoffs

- **Supabase outage during cron fire**: helper defaults to `enabled=true` — lambda will run. Accepted because the offseason guard is the actual safety. Documented in helper docstring and PR body.
- **Test mode forgotten in "true"**: admin sets `test_mode=true` before AI Review preview, then forgets to flip back. Mitigation: optional follow-up — surface "Test mode active" badge in iOS Admin home. Not included in this plan.
- **Recipient filter drift across lambdas**: each lambda implements the test-mode filter inline. Risk of divergence over time. Mitigation: small helper (`filter_to_admin_only(recipients)`) in `lambdas/common/cron_settings.py` so all five share one function. Add to step list.
- **EventBridge fires twice for close_game_alert** but only one setting: confirmed acceptable — single lambda body, single setting toggles both invocations.
- **Audit row noise**: every toggle writes an audit row. Acceptable — already the established pattern for other admin edits.

---

## Open Questions

- [ ] Should `CronSettingsView` show the **next scheduled fire time** for each cron (parsed from the EventBridge cron expression)? Nice-to-have, can defer.
- [ ] Should the iOS view surface a **"Last toggled by / when"** indicator? `updated_at` is already on the row — cheap to display.
- [ ] Do we need a **"Test mode active" warning banner** on `AdminView` home when any cron has `test_mode=true`? Considered helpful given the "forgot to flip back" risk.
- [ ] If `enabled=false`, should the **Test mode toggle in iOS UI be visually disabled** (greyed) so the admin doesn't accidentally toggle test mode on a disabled cron? Recommend yes — implement.

---

## Skills / Agents to Use

- **swift-engineer**: build `CronSettingsView`, `CronSettingsStore`, model + routing. iOS-side work in Phase 3.
- **python-engineer** (if defined; else execute manually): backend helper, endpoints, lambda wraps in Phase 2.
- **terraform-engineer** (if defined; else execute manually): API GW route additions in Phase 1.
- **test-writer**: scaffold the 8+ new test files (5 per-lambda, 1 helper, 2 endpoint, 2 iOS).

---

## Test Plan

### Backend
- `test_cron_settings.py`: `get_cron_setting` returns default on Supabase exception; round-trip via `update_cron_setting`.
- `test_admin_cron_settings_list.py`: returns all rows; 403 for non-admin.
- `test_admin_cron_settings_update.py`: patches enabled-only, test_mode-only, both; writes audit row with diff; 403 for non-admin; 400 for missing `cron_key`.
- `test_notif_*_settings_gate.py` (×5): mock helper to `enabled=false` → assert lambda returns skipped without calling SES/SNS; mock `test_mode=true` → assert recipient list filtered to admin only.

### iOS
- `CronSettingsStoreTests`: load populates list; toggle calls API; failure rolls back optimistic state.
- `CronSettingsViewTests`: renders all rows from store; toggles invoke store methods.

### Manual / Integration
- Apply migration to Supabase staging; confirm 5 rows seeded.
- Hit `/admin/cron-settings` via iOS app; confirm list renders.
- Toggle `notif_ai_review_weekly` test_mode in iOS; wait for next Tue 2pm cron; confirm only admin email received.
- Toggle `notif_weekly_recap` enabled=false; confirm Tue 9am cron logs "skipped" and sends no notifications.
- Verify `admin_audit` rows show up for each toggle.

---

## Acceptance Checklist

- [ ] `admin_cron_settings` table exists in Supabase with 5 seeded rows
- [ ] `GET /admin/cron-settings` returns all rows for admin, 403 otherwise
- [ ] `POST /admin/cron-settings` patches a row and writes `admin_audit`
- [ ] All 5 notif lambdas honor `enabled=false` (no-op skip)
- [ ] All 5 notif lambdas honor `test_mode=true` (admin-only delivery)
- [ ] `notif_ai_review_weekly` passes `test_mode` through as `dry_run` on the orchestrator
- [ ] iOS `CronSettingsView` lists all crons and toggles persist
- [ ] iOS optimistic toggle rolls back on API failure
- [ ] `admin_audit` entry created on every toggle
- [ ] All new tests pass; full suites green in CI
- [ ] PR bodies document the manual Supabase migration step
- [ ] TestFlight build deploys without Config.swift heredoc drift (PR #113 lesson applied)
