# Plan: Admin-Editable League Announcements

**Status**: Ready
**Created**: 2026-06-01
**Last updated**: 2026-06-01
**Issue**: #100
**Repos touched**: xomper-back-end (infra + backend), xomper-ios (UI + store)

---

## Summary

Replace the hardcoded `LeagueAnnouncements.current` array (shipped in Season Refocus F2) with a Supabase-backed `league_announcements` table, four admin-gated CRUD endpoints, and one public-read endpoint. Add an admin sub-screen for create/edit/soft-delete. iOS Landing reads from a new `AnnouncementsStore`; on API failure, falls back to the existing hardcoded list so the Landing page never blanks.

Success = commissioner adds/edits/expires announcements without an app deploy, league members see them on Landing within one cache refresh, and the audit trail captures every admin write.

---

## Approach

Mirror the F4 admin pattern (users/leagues edit forms) on the iOS side and the F4 backend pattern (typed CRUD lambdas + `admin_audit` writes via `require_admin`) on the backend side. Add one new public-read endpoint that is JWT-gated but not admin-gated — any signed-in league member can read announcements.

Soft delete only (`is_active=false`) — preserves audit trail. Hard delete is a Supabase dashboard chore if it ever comes up.

Markdown support in body — small lift via `AttributedString(markdown:)` on iOS, lets the commissioner bold key dates.

3 coordinated PRs:
1. **Infra** — `terraform/lambdas_api.tf` with 5 new routes (1 public + 4 admin).
2. **Backend** — migration, `announcements_store.py`, 5 lambda handlers, tests.
3. **iOS** — `AnnouncementsStore`, API client methods, admin sub-screen, Landing card swap, feature flag, tests.

PRs land in that order because backend depends on the infra routes, and iOS depends on the deployed backend.

---

## Affected Files / Components

### xomper-back-end

| File | Change | Why |
|------|--------|-----|
| `sql/announcements_migration.sql` | New — table + index + 3 seed rows | Manual-apply migration (same pattern as F4 `admin_audit` + `admin_cron_settings`). Seeds match current hardcoded entries so Landing content is preserved on cutover. |
| `lambdas/common/announcements_store.py` | New — `list_active`, `list_all`, `create`, `update`, `delete` helpers | Single source of truth for query/filter/sort logic. Mirrors `cron_settings_store.py` shape. |
| `lambdas/api_announcements/handler.py` | New — public read | Filters `is_active=true AND (expires_at IS NULL OR expires_at > now())`, sorted critical-first then `display_order`. JWT-gated but not admin-gated. |
| `lambdas/api_admin_announcements_list/handler.py` | New — admin list (all rows) | Returns inactive + expired so admin can manage them. |
| `lambdas/api_admin_announcements_create/handler.py` | New — admin create | Writes row + `admin_audit` entry (action=`announcements.create`). |
| `lambdas/api_admin_announcements_update/handler.py` | New — admin update | Partial update via `fields` dict. Writes `admin_audit` (action=`announcements.update`) with before/after. |
| `lambdas/api_admin_announcements_delete/handler.py` | New — admin soft delete | Sets `is_active=false`. Writes `admin_audit` (action=`announcements.delete`). |
| `tests/test_announcements_store.py` | New | Unit-test store helpers (filter, sort, partial-update merge). |
| `tests/test_api_announcements.py` | New | Integration-test public-read filter + sort. |
| `tests/test_api_admin_announcements_*.py` | New (4 files) | Test each admin handler including admin gate + audit-row writes. |

### terraform

| File | Change | Why |
|------|--------|-----|
| `terraform/lambdas_api.tf` | Add 5 entries to lambda+route module list | 1 public (`GET /announcements`) + 4 admin (`GET /admin/announcements-list`, `POST /admin/announcements-create`, `POST /admin/announcements-update`, `POST /admin/announcements-delete`). Path-flattened per existing convention. |

### xomper-ios

| File | Change | Why |
|------|--------|-----|
| `Xomper/Features/Landing/LeagueAnnouncement.swift` | Modify — add `displayOrder: Int`, change `id` to `String` (or keep UUID and add separate `serverId: String?`), add `Codable` for wire decode | Match wire shape from `/announcements`. Keep `LeagueAnnouncements.current` as fallback. |
| `Xomper/Core/Stores/AnnouncementsStore.swift` | New — `@Observable @MainActor` | Public surface state + admin CRUD. 5-min freshness cache for Landing reads. |
| `Xomper/Core/Networking/XomperAPIClient.swift` | Modify — add `fetchAnnouncements()`, `adminListAnnouncements()`, `adminCreateAnnouncement(…)`, `adminUpdateAnnouncement(id:fields:)`, `adminDeleteAnnouncement(id:)` | Wire 5 new endpoints into protocol + impl. |
| `Xomper/Features/Landing/AnnouncementsCard.swift` | Modify — read from `AnnouncementsStore`, render markdown body, fallback to hardcoded list on API error or while loading first time | Drop direct `LeagueAnnouncements.current` reference. Keep shimmer briefly on first load. |
| `Xomper/Features/Admin/AnnouncementsListView.swift` | New | Lists all rows with status chips (ACTIVE/INACTIVE/EXPIRED) + priority chip. "+ New" button top-right pushes empty edit form. Swipe-to-delete on rows. |
| `Xomper/Features/Admin/AnnouncementEditView.swift` | New | Form: title `TextField`, body `TextEditor`, priority `Picker`, `expires_at` `DatePicker` with "no expiry" toggle, `is_active` `Toggle`, `display_order` `Stepper`. Save → create or update. |
| `Xomper/Features/Admin/AdminView.swift` | Modify — add menu row "Announcements" between AI Review and Tables (after Test Email / Cron Settings, before Tables) | Gated by `Config.AdminFlags.showAnnouncements`. |
| `Xomper/Navigation/AppRouter.swift` | Modify — add `.adminAnnouncements` + `.adminAnnouncementEdit(id: String?)` cases | Two new routes; `id == nil` means new row. |
| `Xomper/Features/Shell/MainShell.swift` | Modify — instantiate `AnnouncementsStore`, route `.adminAnnouncements` / `.adminAnnouncementEdit(id:)`, pass store to Landing + admin sub-screens | Single owner of the store; pass by reference per existing pattern. |
| `Xomper/Config/Config.swift.template` | Modify — add `static let showAnnouncements: Bool = true` to `AdminFlags` | Match other admin flags. |
| `Xomper/Config/Config.swift` | Modify (local) — same | Local copy. |
| `.github/workflows/testflight-deploy.yml` | Modify — extend Config heredoc with new `showAnnouncements` flag | Keep CI Config in sync. |
| `XomperTests/AnnouncementsStoreTests.swift` | New | Load happy path, API failure → fallback, 5-min cache hit, admin CRUD optimism. |
| `XomperTests/LeagueAnnouncementDecoderTests.swift` | New | Wire decode + nullable `expires_at` handling + priority enum mapping. |

---

## Implementation Steps

### Phase 1 — Infra (PR 1)

- [ ] Add 5 lambda+route entries to `terraform/lambdas_api.tf`:
  - [ ] `GET /announcements` (auth: jwt, not admin)
  - [ ] `GET /admin/announcements-list` (auth: jwt + require_admin)
  - [ ] `POST /admin/announcements-create` (auth: jwt + require_admin)
  - [ ] `POST /admin/announcements-update` (auth: jwt + require_admin)
  - [ ] `POST /admin/announcements-delete` (auth: jwt + require_admin)
- [ ] `terraform plan` → confirm 5 lambdas, 5 routes, 5 integrations, 5 log groups
- [ ] Merge + apply via existing TF GitHub Action

### Phase 2 — Backend (PR 2)

- [ ] Write `sql/announcements_migration.sql` with table + index + 3 seed rows (matching current hardcoded entries — draft date, rule proposals, season start)
- [ ] Apply migration manually via Supabase dashboard SQL editor
- [ ] Verify rows seeded via `SELECT * FROM league_announcements`
- [ ] Write `lambdas/common/announcements_store.py`:
  - [ ] `list_active() -> list[dict]` — apply filter + sort in SQL
  - [ ] `list_all() -> list[dict]` — no filter, sort by `created_at DESC`
  - [ ] `create(title, body, priority='info', expires_at=None, is_active=True, display_order=0) -> dict`
  - [ ] `update(id, fields: dict) -> dict` — raise `NotFoundError` if no row matches
  - [ ] `delete(id) -> dict` — soft delete via `is_active=false`
- [ ] Write 5 handlers (each ~40 lines, mirror `api_admin_cron_settings_update/handler.py` shape):
  - [ ] `api_announcements` — public read, no admin check
  - [ ] `api_admin_announcements_list` — `require_admin`, returns all rows
  - [ ] `api_admin_announcements_create` — `require_admin`, audit write
  - [ ] `api_admin_announcements_update` — `require_admin`, partial fields, audit write with before/after
  - [ ] `api_admin_announcements_delete` — `require_admin`, soft delete, audit write
- [ ] Write tests:
  - [ ] `test_announcements_store.py` — filter/sort/update-merge unit tests
  - [ ] `test_api_announcements.py` — public-read filter behavior
  - [ ] `test_api_admin_announcements_list.py` — admin gate + returns inactive
  - [ ] `test_api_admin_announcements_create.py` — happy path + audit write
  - [ ] `test_api_admin_announcements_update.py` — partial update + audit before/after
  - [ ] `test_api_admin_announcements_delete.py` — soft delete + audit
- [ ] Run full backend test suite, confirm green
- [ ] Smoke-test `/announcements` against staging from Postman/curl with a real JWT
- [ ] Merge PR

### Phase 3 — iOS (PR 3)

- [ ] Extend `LeagueAnnouncement.swift`:
  - [ ] Conform to `Codable` with `CodingKeys` mapping snake_case → camelCase
  - [ ] Add `displayOrder: Int` (default 0 for hardcoded fallback)
  - [ ] Keep `LeagueAnnouncements.current` array intact (used as fallback)
- [ ] Build `AnnouncementsStore`:
  - [ ] State: `announcements: [LeagueAnnouncement]`, `isLoading`, `error`, `lastLoadedAt: Date?`
  - [ ] Admin state: `adminRows: [LeagueAnnouncement]`, `isLoadingAdmin`, `adminError`, `pendingIds: Set<String>`, `lastWriteError`
  - [ ] `func load(force: Bool = false) async` — 5-min freshness gate, falls back to `LeagueAnnouncements.current` on failure
  - [ ] `func loadAdmin() async`
  - [ ] `func create(…) async throws -> LeagueAnnouncement`
  - [ ] `func update(id:fields:) async throws -> LeagueAnnouncement`
  - [ ] `func delete(id:) async throws` — optimistic flip then refetch
- [ ] Add 5 methods to `XomperAPIClientProtocol` + impl with proper request/response codables
- [ ] Modify `AnnouncementsCard.swift`:
  - [ ] Take `store: AnnouncementsStore` parameter
  - [ ] `visible` reads `store.announcements` (post-fallback)
  - [ ] First-load shimmer (3 placeholder rows) — only when `isLoading && announcements.isEmpty`
  - [ ] Render body via `AttributedString(markdown:)` with fallback to plain Text on parse failure
- [ ] Build `AnnouncementsListView`:
  - [ ] List of all rows from `store.adminRows`
  - [ ] Each row: title + priority chip (red for critical) + status chips (ACTIVE/INACTIVE/EXPIRED)
  - [ ] Top-trailing toolbar "+ New" → `router.navigate(to: .adminAnnouncementEdit(id: nil))`
  - [ ] Swipe-to-delete calls `store.delete(id:)` with confirmation alert
  - [ ] Pull-to-refresh
  - [ ] Loading/error/empty states matching `LeagueEditView` chrome
- [ ] Build `AnnouncementEditView`:
  - [ ] If `id == nil` → empty form; else load row from `store.adminRows`
  - [ ] Title `TextField`, body `TextEditor` (min height 120pt), priority `Picker` (info/critical), `expires_at` row (Toggle "Has expiry" + `DatePicker`), `is_active` `Toggle`, `display_order` `Stepper`
  - [ ] Save button → call `store.create` or `store.update`, pop on success, inline error on failure
  - [ ] Disabled save button while title or body empty
- [ ] Add 2 routes to `AppRouter.swift`:
  - [ ] `.adminAnnouncements`
  - [ ] `.adminAnnouncementEdit(id: String?)`
- [ ] Wire routes in `MainShell.swift`:
  - [ ] Instantiate `AnnouncementsStore` at `MainShell` level
  - [ ] Pass to `AnnouncementsCard` + admin sub-screens
  - [ ] Add `.navigationDestination` cases for both routes
- [ ] Add `AdminView` menu row "Announcements" between AI Review and Tables (icon: `megaphone.fill`)
- [ ] Add `Config.AdminFlags.showAnnouncements = true` to template + local + CI heredoc
- [ ] Write `AnnouncementsStoreTests.swift`:
  - [ ] Happy load → populates `announcements`
  - [ ] API error → falls back to `LeagueAnnouncements.current`
  - [ ] 5-min cache short-circuits
  - [ ] `force: true` bypasses cache
  - [ ] Admin create/update/delete happy paths
- [ ] Write `LeagueAnnouncementDecoderTests.swift`:
  - [ ] Valid JSON with all fields
  - [ ] Null `expires_at`
  - [ ] Unknown priority string → default to `.info`
- [ ] `xcodegen generate` + build for iPhone 17 Pro simulator
- [ ] Manual QA against deployed backend:
  - [ ] Landing renders DB rows (not hardcoded array)
  - [ ] Markdown bolding works
  - [ ] Admin create → appears in list + Landing after refresh
  - [ ] Admin edit → reflects on Landing
  - [ ] Admin soft delete → disappears from Landing, still visible in admin list with INACTIVE chip
  - [ ] Expired entry — filtered from Landing, EXPIRED chip in admin list
  - [ ] Kill backend → Landing still shows hardcoded fallback
- [ ] Merge PR

---

## Out of Scope

- Hard delete from app UI — Supabase dashboard only
- Multi-league announcement scoping — single league (Charlotte Dynasty) for v1, no `league_id` column
- Rich-text editor beyond markdown — markdown is plain `TextEditor`, no formatting toolbar
- Push notification on new announcement creation — explicitly punted; could be a follow-up
- Announcement scheduling (`publish_at`) — only `expires_at`; if you need to schedule, just create when ready
- Image/attachment support — text-only
- Per-user dismissal / read state — every member sees every active announcement
- Real-time updates (Supabase Realtime) — 5-min poll is fine for announcement volume

---

## Risks / Tradeoffs

- **Risk**: API outage blanks Landing. **Mitigation**: hardcoded `LeagueAnnouncements.current` fallback survives indefinitely. Worth accepting that fallback may go stale if API is down for >24h.
- **Risk**: Admin accidentally hard-deletes a row from Supabase dashboard and breaks audit trail. **Mitigation**: documented soft-delete-only pattern; Supabase dashboard access is already gated to commissioner.
- **Risk**: Markdown parse failure crashes the row. **Mitigation**: wrap `AttributedString(markdown:)` in `try?` and fall back to plain `Text(body)` on failure.
- **Risk**: 5-min cache means an admin's fresh announcement may not appear on Landing for up to 5 minutes. **Tradeoff accepted**: announcements are not time-critical at the minute granularity. Admin can pull-to-refresh on Landing to force.
- **Risk**: Seed migration runs twice → duplicate rows. **Mitigation**: gate seed inserts with `ON CONFLICT DO NOTHING` on a deterministic key (use fixed UUIDs in the seed rows).
- **Risk**: `expires_at` timezone confusion (UTC stored vs local DatePicker). **Mitigation**: always store + transmit as ISO8601 UTC; iOS `DatePicker` reads/writes `Date` which is timezone-neutral.

---

## Open Questions

- [ ] Should the admin list show count of total/active/expired in a header chip? (Nice-to-have, low cost — recommend yes)
- [ ] Should "+ New" button live in the list's nav bar trailing or as a top card row in the list body? (Recommend nav bar trailing — matches iOS patterns)
- [ ] Confirm seed-row UUIDs: do we want deterministic strings (e.g. `00000000-0000-0000-0000-000000000001`) or just `gen_random_uuid()`? Deterministic is safer for repeat migrations — recommend deterministic.
- [ ] Markdown render — should we also support links (`[text](url)`)? `AttributedString(markdown:)` supports it out of the box; recommend yes, no extra work.
- [ ] Does the 5-min cache TTL belong as a `Config` constant or a store-internal const? Recommend store-internal — no other consumer needs it.

---

## Acceptance Checklist

Tied to issue #100. All must be checked to merge PR 3 / close issue.

- [ ] Table `league_announcements` exists in Supabase with index + 3 seed rows
- [ ] `GET /announcements` returns active rows ordered critical-first then `display_order`
- [ ] `GET /admin/announcements-list` returns all rows (including inactive/expired) and rejects non-admin
- [ ] `POST /admin/announcements-create|update|delete` work + write to `admin_audit`
- [ ] Landing page reads from backend (verified by editing a row in Supabase and seeing it reflect after refresh)
- [ ] Markdown bolding in body renders correctly
- [ ] Backend down → Landing shows hardcoded fallback (test by pointing iOS to a dead URL)
- [ ] Admin sub-screen menu row visible in `AdminView`
- [ ] Admin can create, edit, soft-delete announcements end-to-end
- [ ] Status chips render correctly (ACTIVE / INACTIVE / EXPIRED)
- [ ] All new unit tests pass (backend + iOS)
- [ ] `Config.AdminFlags.showAnnouncements` flag wired in template + local + CI heredoc
- [ ] No regression on Landing page layout (visual diff with current build)

---

## Skills / Agents to Use

- **swift-engineer**: build `AnnouncementsStore`, `AnnouncementsCard` rewire, admin views — owns the iOS PR
- **backend-engineer**: write `announcements_store.py`, 5 lambda handlers + tests — owns the backend PR
- **terraform-engineer**: extend `lambdas_api.tf` — owns the infra PR
- **test-writer**: backend pytest suite + iOS `AnnouncementsStoreTests` / `LeagueAnnouncementDecoderTests`
- **qa-runner**: final end-to-end manual QA pass on simulator against staging
