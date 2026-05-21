# Plan: AI Review — F0 Shared Infra (Phase 0)

**Epic**: `docs/features/ai-review/EPIC_PLAN.md`
**Phase**: 0
**Status**: Ready
**Created**: 2026-05-21
**Last updated**: 2026-05-21
**Depends on**: none (cross-cutting pre-req for F1/F2/F3)

---

## Summary
F0 provisions every reusable surface F1 (post-draft), F2 (preseason), and F3 (weekly) consume: the `xomper-ai-reports` DynamoDB table + GSI, the `/xomper/api/ANTHROPIC_API_KEY` SSM SecureString, a $5/month CloudWatch billing-or-invocation alarm, two read API lambdas (`api_ai_reports_latest` + `api_ai_reports_list`), the `claude_helper.py` / `league_lore.py` / `ai_reports_store.py` / `email_templates/ai_review.py` common modules in `xomper-back-end`, and the iOS shared surfaces (`AIReviewStore`, `AIReviewView`, `AIReviewDetailView`, `XomperAPIClient` methods, `TrayDestination.aiReview`, Home banner). Ships as three coordinated PRs (infra → backend → iOS). On merge the iOS endpoints return an empty list until F1 first generates a report.

Success = all three repos merged, terraform applied, iOS builds against the new endpoints showing an empty archive, all unit tests green, IAM permits the new lambda role to R/W the new Dynamo table and read the new SSM key.

---

## Approach
Locks the decisions from `BRAINSTORM.md` Q1–Q8 and the per-phase open questions from `EPIC_PLAN.md` into concrete file-level changes. Pattern templates lifted from the most recently shipped admin-portal PRs (`api_admin_list_notifications` + `notification_log` + iOS `AdminStore`/`AdminView` + `.draftOrder` tray case) — those are the cleanest in-tree references for "GET endpoint + Dynamo helper + Observable store + tray destination" across the three repos.

Architectural decisions resolved (rationale in **Open Design Decisions** below):

| # | Decision | Pick |
|---|----------|------|
| 1 | Lore module shape | Dataclass `ManagerProfile` with `display_name`, `nicknames`, `favorite_teams`, `school`, `notable_stories`, `life_events` |
| 2 | User ID lookup | Manual one-time lookup post-F0-plan-approval; commit IDs as a follow-up; placeholders `# TODO` until then |
| 3 | API endpoint auth | Reuse existing `lambdas/authorizer/` JWT path — endpoints sit behind the same custom authorizer that gates `/admin/*` |
| 4 | Dynamo schema | PK `LEAGUE#<league_id>` / SK `REPORT#<report_type>#<period>`; GSI1 PK `LEAGUE#<league_id>` / GSI1 SK `CREATED#<iso8601>` |
| 5 | Report body storage | Markdown string in attribute `body_markdown`; JSON metadata in attribute `metadata` |
| 6 | Prompt caching | `cache_control` on the *system* prompt only (lore + tone + safety rails). User prompt is per-report data + instructions and stays uncached |
| 7 | Markdown render on iOS | Native `AttributedString(markdown:)` (iOS 17 already in our deployment target; no new SPM dep) |
| 8 | Home card placement | Topmost banner card, above `searchControls` in `SearchView` (rebrand to `HomeView` later if needed). Pushes search down by one card height — acceptable per epic |

---

## Repos Touched
- `xomper-infrastructure` — Dynamo table + GSI, SSM SecureString, billing/invocation alarm, two API GW routes + lambda stubs. (IAM already covers `${app_name}*` Dynamo + `/${app_name}/*` SSM read; no IAM file changes expected — verify in step 3.)
- `xomper-back-end` — four new `lambdas/common/*` modules, two new API lambda dirs, tests, dependency bump for the Anthropic SDK.
- `xomper-ios` — new `Core/Stores/AIReviewStore.swift`, response models, two `XomperAPIClient` methods, `Features/AIReview/` directory (3 views), `TrayDestination.aiReview` case + drawer entry + `MainShell` wiring, Home banner widget injected into `SearchView`. Run `xcodegen generate` after adding new files.

---

## Affected Files / Components

### `xomper-infrastructure/terraform/`
| File | Change | Why |
|------|--------|-----|
| `dynamodb.tf` | Add `aws_dynamodb_table.ai_reports` resource with PK `pk` (S), SK `sk` (S), GSI `created-at-index` on `pk` (HASH) + `created_at` (RANGE), KMS encryption, PITR, PAY_PER_REQUEST, standard tags | Storage for all three report types; GSI for "recency" queries used by `list` endpoint |
| `ssm.tf` | Add `aws_ssm_parameter.anthropic_api_key` (SecureString) at `/${var.app_name}/api/ANTHROPIC_API_KEY`, value sourced from new `variables.tf` var `anthropic_api_key`, `ignore_changes = [tags, tags_all]` per existing convention | Anthropic key storage; matches the `SUPABASE_*` pattern |
| `variables.tf` | Add `variable "anthropic_api_key"` (sensitive = true, no default) | Wires the secret into TF without checking in |
| `lambdas_api.tf` | Add two entries to the `api_lambdas` local: `{ name = "ai-reports-latest", path_part = "latest", http_method = "GET", description = "AI Review: latest report by type" }` and `{ name = "ai-reports-list", path_part = "list", http_method = "GET", description = "AI Review: paginated archive" }`. Comment block describing routes `/ai-reports/latest?type=X` and `/ai-reports/list?type=X&cursor=&limit=` | Provisions the lambda stubs + API GW routes; backend repo deploys the code over the stub |
| `api_gateway.tf` | Verify the existing path-building logic groups these under `/ai-reports/*` (read existing file to confirm — likely zero changes if the loop derives paths from `path_part`); if not, add an explicit resource group | API routing |
| `iam_lambdas.tf` | **Verify only** — existing `DynamoDBRuntime` statement already covers `${app_name}*` tables; existing `SSMParameters` statement already covers `/${app_name}/*`. Add a comment noting `xomper-ai-reports` + `ANTHROPIC_API_KEY` are covered by the wildcards. If naming deviates from `${app_name}*`, add a tight statement | Confirms least-privilege without widening |
| `cloudwatch.tf` (new) | `aws_cloudwatch_metric_alarm.ai_review_cost_alarm` at $5/month against the AWS/Billing `EstimatedCharges` metric scoped to the AI lambdas' tag (if available in this account); fallback alarm = invocation-count alarm against the three `notif_ai_review_*` lambdas firing more than N times/day | Cost runaway protection from the brainstorm |
| `outputs.tf` | Add `ai_reports_table_name` + `ai_reports_table_arn` outputs for downstream reference | Future-proof; non-blocking |

### `xomper-back-end/lambdas/common/`
| File | Change | Why |
|------|--------|-----|
| `league_lore.py` (new) | Codifies 12 manager profiles as `LEAGUE_LORE: dict[str, ManagerProfile]` keyed by Sleeper `user_id`. Dataclass shape pinned below. Placeholders `# TODO: fill in user_id` until the manual lookup runs | Personality fuel for all three report types |
| `claude_helper.py` (new) | `def generate(prompt: str, system: str \| None = None, model: str = "claude-haiku-4-5", max_tokens: int = 4000) -> str`. Lazy-loads Anthropic SDK client (API key from `ssm_helpers.get_parameter("/xomper/api/ANTHROPIC_API_KEY")`, module-level cache). Sets `cache_control = {"type": "ephemeral"}` on the system prompt blocks. Retries on `anthropic.APIConnectionError` and 5xx with exponential backoff (max 3). Logs token usage. Raises `ClaudeAPIError` (new entry in `errors.py`) on terminal failure | Shared LLM wrapper used by F1/F2/F3 |
| `ai_reports_store.py` (new) | Top-of-file docstring documents schema. Functions: `write_report(league_id, report_type, period, body_markdown, metadata) -> dict` (PutItem with computed `pk`/`sk`/`created_at` + GSI fields); `get_latest(league_id, report_type) -> dict \| None` (Query on PK with SK `begins_with REPORT#<type>#`, `ScanIndexForward=False`, `Limit=1`); `list_recent(league_id, limit=20, cursor=None) -> tuple[list[dict], str \| None]` (Query GSI1 with PK, ScanIndexForward=False, optional `ExclusiveStartKey` from `cursor`) | Dynamo R/W for the new table |
| `email_templates/ai_review.py` (new) | `def render_ai_review_email(manager_name: str, report_type: str, period_label: str, body_markdown: str, league_name: str) -> tuple[str, str, str]` returns `(subject, html_body, text_body)`. Per-user subject/greeting injection happens here (hybrid email shape from Q4). Uses `base.wrap_email_html` chrome. Markdown→HTML via a small stdlib renderer (use the `markdown` PyPI package added in `requirements.txt`) | Email rendering with per-user header on shared body |
| `errors.py` (edit) | Add `class ClaudeAPIError(XomperError)` next to `SleeperAPIError` | Typed error path |
| `constants.py` (edit) | Add `AI_REPORTS_TABLE = os.environ.get("APP_NAME", "xomper") + "-ai-reports"`. Add `AI_REVIEW_PROMPT_VERSION = "f0-2026-05-21"` placeholder | Centralized table name + prompt version stamp |

### `xomper-back-end/lambdas/api_ai_reports_latest/`
| File | Change | Why |
|------|--------|-----|
| `__init__.py` (new, empty) | Package marker | Lambda discovery |
| `handler.py` (new) | GET handler. Reads `type` query param (validate against `{"postDraft","preseason","weekly"}`), resolves the active league via `supabase_helper.get_active_whitelisted_league`, calls `ai_reports_store.get_latest(league_id, report_type)`, returns `{"report": {...} \| None}` via `success_response`. JWT auth enforced upstream by the existing authorizer; no `require_admin` — all signed-in league members can read | Latest-by-type endpoint that iOS hits for the Home banner |

### `xomper-back-end/lambdas/api_ai_reports_list/`
| File | Change | Why |
|------|--------|-----|
| `__init__.py` (new, empty) | Package marker | Lambda discovery |
| `handler.py` (new) | GET handler. Reads `type` (optional), `limit` (default 20, max 50), `cursor` (optional). Resolves active league. Calls `ai_reports_store.list_recent(league_id, limit, cursor)`. Filters by `report_type` in-process if `type` provided. Returns `{"rows": [...], "next_cursor": "..." \| None}` | Paginated archive for iOS `AIReviewView` |

### `xomper-back-end/requirements.txt`
| Change | Why |
|--------|-----|
| Add `anthropic==0.50.0` (pin to latest stable, sanity-check at install) and `markdown==3.6` | SDK + markdown-to-HTML renderer |

### `xomper-back-end/tests/`
| File | Change | Why |
|------|--------|-----|
| `tests/test_league_lore.py` (new) | Schema validation: every `ManagerProfile` has required fields, all 12 user_ids are unique (once filled in), no field is `None` where required, `notable_stories` and `life_events` are lists of strings | Catches typos before lambdas crash mid-prompt |
| `tests/test_claude_helper.py` (new) | Mock `anthropic.Anthropic` client. Assert `generate` passes `cache_control={"type":"ephemeral"}` on system prompt blocks. Assert retry-then-raise on 5xx. Assert API key fetched from SSM exactly once (module-level cache) | Locks down the wrapper contract |
| `tests/test_ai_reports_store.py` (new) | With moto-mocked Dynamo: `write_report` puts an item with correct PK/SK/created_at; `get_latest` returns newest of N writes; `list_recent` paginates correctly with `cursor`; out-of-range `report_type` raises | Schema and pagination guards |
| `tests/conftest.py` (edit) | Add a fixture that creates the `xomper-ai-reports` mock table matching the terraform schema | Test infra |

### `xomper-ios/Xomper/Core/Models/`
| File | Change | Why |
|------|--------|-----|
| `AIReport.swift` (new) | `struct AIReport: Decodable, Identifiable, Sendable, Hashable` with fields `id`, `leagueId`, `reportType: AIReportType`, `period`, `bodyMarkdown`, `metadata: [String: AnyCodable]?`, `createdAt: Date`, `model: String?`, `promptVersion: String?`. `enum AIReportType: String, Decodable, Sendable, CaseIterable { case postDraft = "postDraft"; case preseason; case weekly }` with `displayName` + `systemImage` computed | Codable layer for the two new endpoints |

### `xomper-ios/Xomper/Core/Networking/`
| File | Change | Why |
|------|--------|-----|
| `XomperAPIClient.swift` (edit) | Append protocol methods + concrete impls: `aiReportsLatest(type: AIReportType) async throws -> AIReport?` (GET `/ai-reports/latest?type=...`) and `aiReportsList(type: AIReportType?, limit: Int, cursor: String?) async throws -> AIReportsListResponse` (GET `/ai-reports/list?...`). Add `AIReportsListResponse` Decodable struct with `rows: [AIReport]` and `nextCursor: String?`. Mirror the existing `adminListNotifications` pattern for query encoding | Two new API methods |

### `xomper-ios/Xomper/Core/Stores/`
| File | Change | Why |
|------|--------|-----|
| `AIReviewStore.swift` (new) | `@Observable @MainActor final class AIReviewStore`. State: `latestByType: [AIReportType: AIReport]`, `archive: [AIReport]`, `archiveCursor: String?`, `isLoading`, `errorMessage`. Methods: `loadLatest(type: AIReportType) async`, `loadArchive(reset: Bool = false) async`, `loadNextPage() async`. Caches via in-memory dicts; no persistence (matches `AdminStore` pattern) | Single source of truth for AI review state |

### `xomper-ios/Xomper/Features/Shell/`
| File | Change | Why |
|------|--------|-----|
| `TrayDestination.swift` (edit) | Add `case aiReview`. `title = "AI Review"`. `systemImage = "sparkles"` | Tray entry |
| `DrawerView.swift` (edit) | Insert `.aiReview` into the `League` section (after `.draftOrder`, before `.rulebook`), or create a new `Reports` section sitting between `Roster` and `League` — confirm during implementation. Default = append to `League` to minimize disruption | Discoverable nav entry |
| `MainShell.swift` (edit) | Add `case .aiReview` to `destinationRoot` switch, returning `AIReviewView(store: aiReviewStore, router: router)`. Hold `@State private var aiReviewStore = AIReviewStore(apiClient: XomperAPIClient(...))` next to existing stores | Wires the tray case to the view |

### `xomper-ios/Xomper/Features/AIReview/` (new dir)
| File | Change | Why |
|------|--------|-----|
| `AIReviewView.swift` (new) | Archive list view. `ScrollView` + `LazyVStack` over `store.archive`. Row = `AIReportRow` (title = `report.reportType.displayName + " — " + report.period`, subtitle = relative-date of `createdAt`, chevron). Tap pushes `AIReviewDetailView`. `.task` calls `store.loadArchive()` on first appear. Empty-state when `archive.isEmpty && !isLoading` ("No AI reports yet — your first one drops after the next draft."). Infinite-scroll trigger: when the last row appears, call `store.loadNextPage()` | Browseable history |
| `AIReviewDetailView.swift` (new) | Title = `report.reportType.displayName + " " + report.period`. `ScrollView` rendering `Text(AttributedString(markdown: report.bodyMarkdown, options: .init(interpretedSyntax: .full)))`. Footer = `createdAt` + `model` + `promptVersion` in muted text | Markdown rendering with native iOS 17 API |
| `AIReviewHomeCard.swift` (new) | Banner card showing latest report's title + first-paragraph snippet + "Tap to read" CTA. Driven by `store.latestByType[.weekly] ?? .preseason ?? .postDraft` resolution (most recent across types). Wrapped in `Button` that calls `navStore.select(.aiReview, router: router)` then pushes the detail view. Renders nothing when no report exists | Discovery surface on Home |

### `xomper-ios/Xomper/Features/Home/`
| File | Change | Why |
|------|--------|-----|
| `SearchView.swift` (edit) | Inject `AIReviewHomeCard` as the topmost element of the `VStack(spacing: 0)` body, *above* `searchControls`. Pass `aiReviewStore` + `navStore` + `router` via init. On `.task`, call `aiReviewStore.loadLatest(type: .weekly)` (and `.postDraft` / `.preseason` in parallel — pick whichever is most recent for the banner) | Home banner placement decision from Q7 |

### `xomper-ios/XomperTests/`
| File | Change | Why |
|------|--------|-----|
| `AIReviewStoreTests.swift` (new) | Mock `XomperAPIClientProtocol`. Test: `loadLatest` populates `latestByType[type]`; `loadArchive(reset: true)` replaces archive; `loadNextPage` appends + advances cursor; errors set `errorMessage` and clear `isLoading` | Store unit tests on the existing test target |

### `xomper-ios/project.yml`
| Change | Why |
|--------|-----|
| No edits needed if `xcodegen` auto-discovers new Swift files. Otherwise add `Xomper/Features/AIReview` to the source paths | Build inclusion |

---

## Open Design Decisions (resolved)

### 1. Lore module shape — `ManagerProfile` dataclass
```python
@dataclass(frozen=True)
class ManagerProfile:
    display_name: str                # "Tony" — what the bot calls them in copy
    nicknames: list[str]             # ["Antman", "T-Bone"]
    favorite_teams: list[str]        # ["Eagles", "Phillies", "Penn State"] (NFL + college + other)
    school: str | None               # "Penn State"
    notable_stories: list[str]       # One-liners; ["Fell asleep on toilet at SEC championship"]
    life_events: list[str]           # ["Engaged 2025", "New job at Stripe 2026"]
```
Justification — kept the brainstorm's seven-field spec but collapsed `real_name` into `display_name` (private repo; no separation needed) and merged `schools` (plural) into `school` (singular) since the issue body lists one per manager. `notable_stories` vs `life_events` stays split: stories are evergreen embarrassments useful for roasts, events are time-bounded context the lambda may want to re-evaluate yearly.

### 2. User ID lookup
**Pick (a) — manual one-time lookup**. After F0 plan approval, run a quick `lambdas/scripts/list_league_users.py` one-off (or `curl` the Sleeper users endpoint for the active league via `get_sleeper_league_users(league_id)`) to grab `(display_name, user_id)` pairs for all 12 managers. Commit the IDs as a follow-up PR before F1. Until then, `league_lore.py` carries `# TODO: fill in user_id` placeholders so the dataclass shape is reviewable.

### 3. API endpoint auth
Confirmed by reading `lambdas/authorizer/handler.py`: the JWT authorizer is wired to API GW at the route level via `iam_api_gateway.tf` / `lambda_authorizer.tf`. The two new GET routes (`/ai-reports/latest`, `/ai-reports/list`) inherit the same authorizer automatically — no per-lambda `require_admin` (these are league-member reads, not admin actions). Unauthenticated calls are denied at API GW before the lambda is invoked.

### 4. DynamoDB key / index schema
- **PK**: `LEAGUE#<league_id>`
- **SK**: `REPORT#<report_type>#<period>` where `period` ∈ `{"2026-POSTDRAFT", "2026-PRE", "2026W01"..."2026W17"}`
- **GSI1 (`created-at-index`)**:
  - PK: `LEAGUE#<league_id>` (same as base PK)
  - SK: `CREATED#<iso8601_utc>` (e.g. `CREATED#2026-05-21T15:42:11Z`)
- **Attributes**: `body_markdown` (S), `metadata` (M), `model` (S), `prompt_version` (S), `created_at` (S, ISO 8601)

Justification — `begins_with(SK, "REPORT#weekly#")` + `ScanIndexForward=False` yields newest weekly. GSI lets archive list query newest-first across all report types in one shot.

### 5. Markdown vs JSON storage
Body = markdown string in `body_markdown`. Metadata = Dynamo Map attribute `metadata` carrying `{prompt_version, model, token_usage_in, token_usage_out, source_data_keys}`. Claude generates markdown natively; iOS renders via `AttributedString(markdown:)`; email renders via the `markdown` PyPI lib.

### 6. Prompt caching
`claude_helper.py` always sets `cache_control={"type": "ephemeral"}` on each block of the **system prompt** (which carries lore + tone guidelines + safety rails — stable across all three report types and across calls within a 5-min window). User prompts (per-report data + instructions) are not cached. Concretely the system prompt is composed as:
```
[block 1, cached]   Tone + safety rails (~500 tokens)
[block 2, cached]   League lore dump (~3000 tokens)
[block 3, uncached] (none — user prompt carries the per-report data)
```
At Haiku 3.5 rates, cache hits save ~$0.003/call after the first call — material when F3 fires weekly.

### 7. Markdown renderer on iOS
Native `AttributedString(markdown: report.bodyMarkdown, options: .init(interpretedSyntax: .full))`. Pros: no SPM dep; ships on iOS 17. Cons: no table rendering — accepted (reports lean on headings + bold + lists, not tables, per the brainstorm's tone anchors). If table need surfaces in F1 dry-run review, revisit with `swift-markdown-ui`.

### 8. Home card placement
Read `Xomper/Features/Home/SearchView.swift` — the body is a `VStack(spacing: 0)` containing `searchControls` then `resultArea`. The card slots in as a new topmost child:
```
VStack(spacing: 0) {
    AIReviewHomeCard(...)          // new — only renders when latest report exists
    searchControls
    resultArea
}
```
Topmost so it's immediately visible. Renders nothing (zero height) when no reports exist, so empty-state Home is unchanged.

---

## Implementation Steps (dependency-ordered, file-by-file)

### Repo 1: `xomper-infrastructure`

- [ ] **Step 1** — In `terraform/variables.tf`, add `variable "anthropic_api_key" { type = string; sensitive = true }`. Update `terraform.tfvars` (gitignored) locally with the real key.
- [ ] **Step 2** — In `terraform/ssm.tf`, add the `aws_ssm_parameter.anthropic_api_key` resource at `/${var.app_name}/api/ANTHROPIC_API_KEY` with `lifecycle.ignore_changes = [tags, tags_all]`.
- [ ] **Step 3** — In `terraform/dynamodb.tf`, add the `aws_dynamodb_table.ai_reports` resource (PK `pk` S, SK `sk` S, GSI `created-at-index` on `pk` + `created_at`, KMS, PITR, PAY_PER_REQUEST, standard tags).
- [ ] **Step 4** — In `terraform/iam_lambdas.tf`, **read only** — verify the `DynamoDBRuntime` wildcard `${var.app_name}*` covers the new table (it does) and `SSMParameters` covers `/${var.app_name}/api/ANTHROPIC_API_KEY` (it does). Add a one-line comment marking the new resources are covered. No code change.
- [ ] **Step 5** — In `terraform/lambdas_api.tf`, append two entries to the `api_lambdas` local: `{ name = "ai-reports-latest", path_part = "latest", http_method = "GET", description = "..." }` and `{ name = "ai-reports-list", path_part = "list", http_method = "GET", description = "..." }`. Update or confirm `api_gateway.tf` builds them under `/ai-reports/*`.
- [ ] **Step 6** — Add `terraform/cloudwatch.tf` (new file) with `aws_cloudwatch_metric_alarm.ai_review_cost_alarm`. Prefer billing dim if available in the account; fall back to a `Lambda Invocations` alarm against the three `notif_ai_review_*` function names firing > 50/day (conservative ceiling).
- [ ] **Step 7** — In `terraform/outputs.tf`, expose `ai_reports_table_name` + `ai_reports_table_arn`.
- [ ] **Step 8** — **terraform apply** — required before backend deploys. Verify the SSM key exists (`aws ssm get-parameter --name /xomper/api/ANTHROPIC_API_KEY --with-decryption`), the table exists, and the API GW shows the two new routes returning 502s (stub lambdas).

### Repo 2: `xomper-back-end` (after Step 8)

- [ ] **Step 9** — In `requirements.txt`, append `anthropic==0.50.0` and `markdown==3.6`. Run `pip install -r requirements.txt` locally + sanity-test the Anthropic SDK import.
- [ ] **Step 10** — In `lambdas/common/errors.py`, add `class ClaudeAPIError(XomperError)` next to `SleeperAPIError`.
- [ ] **Step 11** — In `lambdas/common/constants.py`, add `AI_REPORTS_TABLE` + `AI_REVIEW_PROMPT_VERSION`.
- [ ] **Step 12** — Create `lambdas/common/league_lore.py` with the `ManagerProfile` dataclass + `LEAGUE_LORE` dict carrying 12 entries with `# TODO: fill in user_id` placeholders + populated `display_name`/`nicknames`/`favorite_teams`/`school`/`notable_stories`/`life_events` lifted verbatim from issue #79's body.
- [ ] **Step 13** — Create `lambdas/common/claude_helper.py` per the spec above. Cache the Anthropic client at module load. SSM key fetched lazily via `ssm_helpers.get_parameter`.
- [ ] **Step 14** — Create `lambdas/common/ai_reports_store.py` with `write_report` / `get_latest` / `list_recent`, schema docs at top.
- [ ] **Step 15** — Create `lambdas/common/email_templates/ai_review.py` with `render_ai_review_email`. Use `base.wrap_email_html` + `markdown.markdown(body, extensions=["extra"])`.
- [ ] **Step 16** — Create `lambdas/api_ai_reports_latest/__init__.py` (empty) and `handler.py` per spec. Validate `type` param against the three known values.
- [ ] **Step 17** — Create `lambdas/api_ai_reports_list/__init__.py` (empty) and `handler.py` per spec.
- [ ] **Step 18** — Create `tests/test_league_lore.py`, `tests/test_claude_helper.py`, `tests/test_ai_reports_store.py`. Add the mock-Dynamo fixture to `tests/conftest.py`.
- [ ] **Step 19** — Run `pytest tests/` — all green.
- [ ] **Step 20** — Deploy lambdas via the existing CI/CD pipeline (the two new lambda dirs get picked up by the deploy script that zips each subdir). Smoke-test the routes with `curl` and a valid JWT — both should return `{"report": null}` / `{"rows": [], "next_cursor": null}` against the empty table.
- [ ] **Step 21** — **Follow-up PR (not part of F0 merge, but a hard pre-req for F1)**: user runs the manual Sleeper lookup, replaces `# TODO: fill in user_id` placeholders in `league_lore.py` with real IDs, opens a small follow-up PR.

### Repo 3: `xomper-ios` (after Step 20)

- [ ] **Step 22** — Create `Xomper/Core/Models/AIReport.swift` with `AIReport` + `AIReportType` enum.
- [ ] **Step 23** — Edit `Xomper/Core/Networking/XomperAPIClient.swift`: extend protocol with `aiReportsLatest` + `aiReportsList`, add `AIReportsListResponse` struct, implement both methods on the concrete class. Mirror the `adminListNotifications` query-encoding pattern.
- [ ] **Step 24** — Create `Xomper/Core/Stores/AIReviewStore.swift` per spec.
- [ ] **Step 25** — Edit `Xomper/Features/Shell/TrayDestination.swift` — add `case aiReview` + title/icon.
- [ ] **Step 26** — Edit `Xomper/Features/Shell/DrawerView.swift` — append `.aiReview` to the `League` section.
- [ ] **Step 27** — Create `Xomper/Features/AIReview/` directory + three view files (`AIReviewView`, `AIReviewDetailView`, `AIReviewHomeCard`).
- [ ] **Step 28** — Edit `Xomper/Features/Shell/MainShell.swift` — hold `@State private var aiReviewStore = AIReviewStore(apiClient: ...)`, add `case .aiReview:` to `destinationRoot` switch.
- [ ] **Step 29** — Edit `Xomper/Features/Home/SearchView.swift` — inject `AIReviewHomeCard` as the topmost child of the body `VStack`, pipe `aiReviewStore` + `navStore` + `router` through `init`. Update `MainShell` call site accordingly.
- [ ] **Step 30** — Add `Xomper/XomperTests/AIReviewStoreTests.swift` with mock client tests.
- [ ] **Step 31** — Run `xcodegen generate` to pick up the new files into the Xcode project.
- [ ] **Step 32** — Build via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Xomper -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`. Run unit tests.
- [ ] **Step 33** — Manual QA on simulator: drawer shows AI Review row, tap opens empty-state archive, Home renders unchanged (banner card renders nothing when no reports exist).

---

## Test Plan

### Backend (pytest)
- `test_league_lore.py`:
  - All 12 entries present
  - Every `display_name` non-empty
  - Every `nicknames` / `favorite_teams` / `notable_stories` / `life_events` is a list of non-empty strings
  - (Skipped until follow-up PR) every key is a real Sleeper user_id (string, non-empty)
- `test_claude_helper.py`:
  - `generate` injects `cache_control={"type":"ephemeral"}` on system prompt blocks
  - SSM `get_parameter` called once per cold start
  - Retries 3x on 5xx then raises `ClaudeAPIError`
  - Passes through `model` + `max_tokens` overrides
- `test_ai_reports_store.py` (moto-mocked Dynamo):
  - `write_report` creates an item with correct PK/SK + ISO `created_at`
  - `get_latest("L1", "weekly")` returns the most recent weekly even with other types present
  - `list_recent("L1", limit=2)` returns 2 items + a cursor; passing cursor yields the next 2
  - Unknown `report_type` raises `ValueError`

### iOS (XCTest)
- `AIReviewStoreTests`:
  - `loadLatest(type: .weekly)` populates `latestByType[.weekly]` on mocked-200
  - `loadArchive(reset: true)` resets `archive` + `archiveCursor`
  - `loadNextPage()` appends rows and advances cursor; no-ops when `archiveCursor` is nil
  - Error path sets `errorMessage`, clears `isLoading`

### Smoke (post-deploy)
- `curl -H "Authorization: Bearer <jwt>" "$API/ai-reports/latest?type=weekly"` returns `{"report": null}` with 200
- `curl -H "Authorization: Bearer <jwt>" "$API/ai-reports/list?limit=20"` returns `{"rows": [], "next_cursor": null}` with 200
- iOS app launches, drawer shows AI Review, tap → empty-state archive renders, Home banner is hidden

---

## Out of Scope
- Any one of the three report generators (F1/F2/F3 own those)
- Season-memory table (`xomper-ai-memories`) — lands with F3
- Admin "regenerate" / "send now" actions — Phase 4
- Live NFL news ingestion (`web_search`, RSS sidecar) — Phase 4
- iOS read-state badges — Phase 4
- Email recipient fan-out / per-user subject building beyond the `render_ai_review_email` helper — the *helper* ships in F0 but the actual fan-out call is in F1/F2/F3 lambdas
- Push notification teaser dispatch — F1 wires the first one through

---

## Risks / Tradeoffs
- **Lore PII risk**: `league_lore.py` carries sensitive personal jokes — mitigated because `xomper-back-end` is private and PR-reviewed. Document in a top-of-file comment.
- **`# TODO: fill in user_id` placeholders ship to main**: acceptable because the lore module isn't imported by any deployed lambda yet — F1 is the first consumer. Add a `pytest` skip-marker that flips to failure once F1 lands.
- **Anthropic SDK pin churn**: SDK is < 1.0 and moves fast. Pin to a specific minor and re-validate on each F1/F2/F3 entry.
- **Cache invalidation if lore edits land mid-week**: Anthropic's ephemeral cache lives ~5 min, so a lore edit + redeploy invalidates naturally. Document the implication.
- **`AttributedString(markdown:)` rendering quality**: limited to inline styling — no tables, no images. Accepted; revisit during F1 dry-run.
- **GSI hot partition**: GSI1 PK `LEAGUE#<league_id>` is a single value for the active league — but volume is ~25 writes/year total, so partition heat is a non-issue.
- **API GW route conflict**: `/ai-reports/list` and `/ai-reports/latest` are siblings — verify the existing path-builder in `api_gateway.tf` handles two distinct `path_part`s under the same parent. Likely fine since `/admin/notifications` + `/admin/test-send` already coexist.

---

## Open Questions (carry forward to F1)
- [ ] Final block-list / safety-rail content (specific forbidden topics) — F1 prompt PR
- [ ] Push teaser copy template + per-report-type variations — F1 wires the first
- [ ] Whether the "League" drawer section is the right home for the tray entry or whether a new "Reports" section makes more sense once F1 lands — defer to UX feel after first report exists

---

## Acceptance Checklist — F0 Done When
- [ ] `terraform apply` clean against main: `xomper-ai-reports` table + `created-at-index` GSI exist; SSM param `/xomper/api/ANTHROPIC_API_KEY` exists and is decryptable by the lambda role; two new API GW routes return 200 (with empty payloads); CloudWatch alarm armed
- [ ] `lambdas/common/league_lore.py` exists with all 12 `ManagerProfile` entries (user_id `# TODO` markers OK at F0 merge; **must be filled** before F1 ships)
- [ ] `lambdas/common/claude_helper.py` exists, exports `generate(...)`, applies `cache_control` to system prompt, retries on 5xx, fetches SSM key lazily, has passing unit tests
- [ ] `lambdas/common/ai_reports_store.py` exists, has passing R/W tests under moto
- [ ] `lambdas/common/email_templates/ai_review.py` exists and renders sample markdown into HTML using the existing `base.wrap_email_html` chrome
- [ ] `lambdas/api_ai_reports_latest/handler.py` + `lambdas/api_ai_reports_list/handler.py` deployed, authenticated via the existing JWT authorizer, return correctly-shaped empty payloads against the new table
- [ ] iOS: `AIReport` + `AIReportType` models exist; `XomperAPIClient` exposes `aiReportsLatest` + `aiReportsList`; `AIReviewStore` exists with passing unit tests; `TrayDestination.aiReview` case routes to `AIReviewView`; `AIReviewView` shows empty state; `AIReviewDetailView` renders markdown via native `AttributedString`; `AIReviewHomeCard` renders nothing when no report exists
- [ ] `xcodegen generate` + build green on iPhone 17 Pro sim; all `XomperTests` green
- [ ] Three PRs merged in order: infra → backend → iOS (none reference issue numbers per repo conventions)

---

## Skills / Agents to Use
- **execute agent** — drives this plan to merged PRs once status flips to Ready
- **research agent** — invoke only if the Anthropic SDK pin (`anthropic==0.50.0`) is stale at execute time; otherwise skip
- **brainstorm agent** — not needed; all relevant decisions already locked in `BRAINSTORM.md`

---

## Appendix A: Sleeper user_id → manager mapping

Resolved via `GET https://api.sleeper.app/v1/league/1181789700187090944/users` on 2026-05-21. Use these IDs as `LEAGUE_LORE` keys in `lambdas/common/league_lore.py`.

| user_id | Sleeper handle | Manager | Confidence |
|---|---|---|---|
| `594625531702460416` | domgiordano | Dominick — Ravens / Orioles / Hornets / UNC | confirmed |
| `418511574492270592` | reesegriffin | Reese — Chicago sports / UNC | confirmed |
| `867213342836711424` | gtatich | Grant Tatich — Panthers / Braves / UNC | confirmed |
| `1132215311643787264` | ktatich | Kyle Tatich — Wake → Notre Dame Law / Panthers / engaged / Grant's older brother | confirmed |
| `867213779035906048` | lukenovak | Luke Novak — Pittsburgh sports / USC (South Carolina) / Alex's younger brother | confirmed |
| `609168618525110272` | alexnovak02 | Alex Novak — USC (South Carolina) / Steelers / Luke's older brother (team name "Shane Beamer's Burner" confirms USC) | confirmed |
| `865328062403870720` | cfolk | Connor Folk — Dolphins / UNC | confirmed |
| `1001254799347658752` | mwynne16 | Michael Wynne — Panthers / college baseball / married Ashley | confirmed |
| `992955241630896128` | Tibor100 | Tibor — big golfer (team name "The Goffather" confirms) | confirmed |
| `741140723985997824` | dmurchis | Duncan Murchison — Commanders / UNC undergrad / Michigan Law | confirmed |
| `1127420529155227648` | andrewga23 | Tony (Anthony Hendricks) — UGA / Bulldogs / fell asleep on SEC championship toilet | confirmed 2026-05-21 |
| `866444821185843200` | gniadek | Jim / Jimbo — Hickory NC / UNC | confirmed 2026-05-21 |

All 12 mappings confirmed by user 2026-05-21. Safe to commit `LEAGUE_LORE` with real Sleeper user_ids in F0.

## Appendix B: Anthropic API key handling

**Terraform is the single source of truth for the SSM value.** Never set via AWS CLI or console. Flow:

1. User adds `ANTHROPIC_API_KEY` to GitHub Secrets on the `xomper-infrastructure` repo BEFORE merging the F0 infra PR.
2. `.github/workflows/terraform.yml` passes it as `TF_VAR_anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}` in both the Plan and Apply steps' `env:` blocks.
3. `variable "anthropic_api_key"` is declared `sensitive = true`, no default — terraform apply fails fast if the GitHub Secret is missing.
4. `aws_ssm_parameter.anthropic_api_key.value = var.anthropic_api_key`. No `ignore_changes = [value]`.
5. Rotation = update the GitHub Secret + push to master (or workflow_dispatch the Terraform workflow) to trigger a new apply. Lambda picks up the new value on next cold start because `claude_helper.py` reads SSM lazily and caches at module level.

F1 cannot be /execute'd until the GitHub Secret is set and the infra PR has merged + applied successfully.
