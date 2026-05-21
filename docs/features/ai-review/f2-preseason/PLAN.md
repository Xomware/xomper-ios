# Plan: AI Review — F2 Preseason Blast (Phase 2)

**Epic**: `docs/features/ai-review/EPIC_PLAN.md`
**Phase**: 2
**Status**: Ready
**Created**: 2026-05-21
**Last updated**: 2026-05-21
**Depends on**: F0 (shared infra — shipped), F1 (post-draft trigger — shipped via infra PR #104, backend PR #58, iOS PR #82)

---

## Summary
F2 is a near-twin of F1: a one-shot, admin-triggered Claude-generated **preseason blast** that gives every team a "last year's grade + this year's outlook" writeup, fired sometime in late August / early September before Week 1 kickoff. Reuses every F0 + F1 surface (Dynamo table, SSM key, `claude_helper`, `league_lore`, `ai_reports_store`, `email_templates/ai_review`, iOS `AIReviewStore` / `AIReviewView` / `AIReviewDetailView` / `AIReviewHomeCard`, `AIReviewTriggerResponse` model) and adds three things only: a new preseason-tuned prompt + orchestrator, a new admin trigger lambda + API GW route (`/admin/ai-review-preseason-trigger`), and a second trigger card on `AdminView` directly below the existing Post-Draft card.

Success = three coordinated PRs (infra → backend → iOS) merged + deployed; admin can hit the new card, fire a dry-run, see the report land in the iOS archive with `report_type=preseason` and `period=2026-PRESEASON`, then toggle off dry-run and broadcast to all 12 managers; total Anthropic spend for the F2 calibration cycle stays under $0.50.

---

## Approach
Pure remix of F1 — no new architectural decisions. Lift F1's lambda structure (`handler.py` + `orchestrator.py` + `prompts.py` + `__init__.py`) verbatim, swap the prompt + data inputs, swap the period key, register a new API GW route, mirror the admin card UI. Reuses the cached system prompt blocks (tone + lore) via `claude_helper`'s `system: list[dict]` support so cache hits across F1 + F2 + F3 amortize the lore tokens.

Architectural decisions resolved (rationale in **Open Design Decisions** below):

| # | Decision | Pick |
|---|----------|------|
| 1 | Trigger mechanism | Admin POST endpoint with `dry_run` (default true) + `force` flag — identical to F1 |
| 2 | Period string | `"2026-PRESEASON"` (distinct from F1's `"2026"` for postDraft to avoid SK collisions in the same year) |
| 3 | System prompt composition | Reuse F1's exact tone-and-safety block 1 (re-anchored on "year-in-review + outlook" instead of "draft grade") + verbatim lore block 2 from `league_lore.LEAGUE_LORE`. Both blocks cached |
| 4 | Data inputs | Sleeper: last year's league (`previous_league_id` walked), last year's final rosters (wins/losses/fpts → final standings), this year's roster snapshot + users. Skip player-name resolution from `/players/nfl` in v1 — reference player IDs only, let Claude lean on training data for player narratives |
| 5 | Idempotency key | `(league_id, "preseason", "2026-PRESEASON")` — full period string, matches F1's `(league_id, "postDraft", "2026")` shape (whatever string F1 used as `period`, we use a distinct one) |
| 6 | iOS admin card | Direct copy of the F1 post-draft card, swapping title + button copy + endpoint. No new tray destination, no new model |
| 7 | Reused response shape | `AIReviewTriggerResponse` from F1 — backend returns the same fields. No new Decodable struct |
| 8 | Cron / scheduled trigger | None. Admin button only in v1, same as F1. v1.1 could add a one-time EventBridge rule timed to early September |

---

## Repos Touched
- `xomper-infrastructure` — one new entry in `lambdas_api.tf` (`{ name = "ai-review-preseason-trigger", path_part = "ai-review-preseason-trigger", http_method = "POST", description = "..." }`), no IAM changes (wildcards from F0 already cover the new lambda + table + SSM key).
- `xomper-back-end` — new `lambdas/api_admin_ai_review_preseason_trigger/` dir (`__init__.py`, `handler.py`, `orchestrator.py`, `prompts.py`). New `lambdas/common/sleeper_helper.py` helpers if any are missing for prior-league standings (verify during execute — F1 already added `previous_league_id` walking). New test file.
- `xomper-ios` — extend `XomperAPIClient` with `triggerPreseasonAIReview(dryRun:force:)`; extend `AdminStore` with `loadPreseasonLatest()` + `triggerPreseason(dryRun:force:)` + matching state vars; add `preseasonTriggerCard` to `AdminView` directly below `postDraftTriggerCard`.

---

## Affected Files / Components

### `xomper-infrastructure/terraform/`
| File | Change | Why |
|------|--------|-----|
| `lambdas_api.tf` | Append one entry to the existing `api_lambdas` local mirroring the F1 post-draft trigger's shape: `{ name = "api-admin-ai-review-preseason-trigger", path_part = "ai-review-preseason-trigger", http_method = "POST", description = "AI Review: admin-triggered preseason report (dry-run first, then broadcast)", parent_path = "admin" }` (or whatever key the local uses to nest under `/admin/*`; mirror the postdraft entry exactly) | Provisions the new lambda stub + API GW route under `/admin/*` (auth via existing JWT authorizer + admin gate enforced server-side) |
| `iam_lambdas.tf` | **Verify only** — F0's wildcard statements already cover the new lambda's Dynamo R/W + SSM read. No code change | Confirms least-privilege without widening |
| `outputs.tf` | No change | n/a |

### `xomper-back-end/lambdas/api_admin_ai_review_preseason_trigger/` (new dir)
Direct structural mirror of `lambdas/api_admin_ai_review_postdraft_trigger/` from F1.

| File | Change | Why |
|------|--------|-----|
| `__init__.py` (new, empty) | Package marker | Lambda discovery |
| `handler.py` (new) | POST handler. Re-uses the F1 handler's shape: require admin (server-side check via `whitelisted_users.is_admin`), parse `dry_run` (default true) + `force` (default false) from JSON body, resolve active league via `supabase_helper.get_active_whitelisted_league`, idempotency: if `force == false` AND `ai_reports_store.get_latest(league_id, "preseason")` returns a row for the same period → return 409 with the existing report. Otherwise call `orchestrator.run(league_id, dry_run, force)` synchronously, return the F1-shaped `AIReviewTriggerResponse` JSON | Admin entry point — owns auth + idempotency + response shape |
| `orchestrator.py` (new) | `def run(league_id: str, dry_run: bool, force: bool) -> dict`. Pulls data via `sleeper_helper` (this year's rosters + users; last year's league metadata + rosters via `previous_league_id`). Builds final-standings + roster-snapshot summary structs. Calls `prompts.build_system_blocks()` + `prompts.build_user_prompt(...)`. Calls `claude_helper.generate(system=system_blocks, user=user_prompt, ...)`. Writes the resulting markdown + metadata via `ai_reports_store.write_report(league_id, "preseason", "2026-PRESEASON", body_markdown, metadata)`. If `dry_run` → send the rendered email to the caller (admin) only via `email_templates.ai_review.render_ai_review_email` + existing send helper; if not dry-run → fan out to all 12 managers via `whitelisted_users` lookup. Returns `{report_id, dry_run, delivery_count, model, token_usage, report}` matching `AIReviewTriggerResponse` | Pipeline glue. Same shape as F1's orchestrator, swapped data sources |
| `prompts.py` (new) | Two builders: `build_system_blocks() -> list[dict]` returns two `{type, text, cache_control}` blocks — block 1 is the **preseason-tuned tone + safety** (re-anchored from F1: "year in review + season outlook" instead of "draft grade"; same forbidden-topics list; same voice anchors); block 2 is the **lore dump** generated from `league_lore.LEAGUE_LORE` exactly as F1 generates it (same helper or inlined-identical code — pull out into `lambdas/common/lore_prompt.py` if duplication itches). Both blocks carry `cache_control={"type": "ephemeral"}`. `build_user_prompt(prior_standings, current_rosters, narratives) -> str` composes the per-report data: prior-season final standings table, current roster snapshot per team, 2-3 offseason narratives (returning-from-injury notes, breakout candidates, etc — bullet-list authored by the LLM from the roster + standings inputs; no hand-curated narrative authoring). Pin `PROMPT_VERSION = "f2-preseason-2026-05-21"` and include in metadata | Tone-calibrated prompt skeleton — the heart of the feature |

### `xomper-back-end/lambdas/common/` (verify / extend)
| File | Change | Why |
|------|--------|-----|
| `sleeper_helper.py` (edit if needed) | Verify F1 already added `get_previous_league_id(league_id)` / `get_sleeper_league_rosters(league_id)` / `walk_previous_league_chain(...)` helpers. If anything F2 needs is missing (e.g. `get_sleeper_league(league_id)` for the prior-season league metadata, or a `summarize_final_standings(rosters)` convenience), add it here so F3 can reuse | DRY against F3 weekly which will also need standings |
| `lore_prompt.py` (new, OPTIONAL) | If F1's orchestrator inlines the "render lore dict → cache-controlled system block" logic, extract it during F2 into a shared `build_lore_block() -> dict` helper. If F1 already factored it out, no change | Only if duplication actually exists at execute-time; otherwise skip |
| `ai_reports_store.py` | **No change** — F0's `write_report` / `get_latest` already accept arbitrary `report_type` + `period` strings | F0 contract holds |
| `email_templates/ai_review.py` | **No change** — F0 ships a generic renderer that takes `report_type` and a per-user manager name; F2 just passes `"preseason"` | F0 contract holds |
| `constants.py` | Add `AI_REVIEW_PRESEASON_PROMPT_VERSION = "f2-preseason-2026-05-21"` next to F1's prompt-version constant (optional — `prompts.py` can carry its own version constant) | Version stamp for metadata |

### `xomper-back-end/tests/`
| File | Change | Why |
|------|--------|-----|
| `tests/test_api_admin_ai_review_preseason_trigger.py` (new) | Mirror F1's trigger-handler tests. Mock `orchestrator.run`, mock Supabase admin check, mock `ai_reports_store.get_latest`. Cases: (a) non-admin caller → 403; (b) admin + no existing report → orchestrator called, 200 response with `dry_run=true` honored; (c) admin + existing report + `force=false` → 409 with `existing_report`; (d) admin + existing report + `force=true` → orchestrator called, new report returned; (e) malformed body → 400 | Locks down the handler contract |
| `tests/test_preseason_prompts.py` (new) | Unit-test `prompts.build_system_blocks()` — assert exactly two blocks returned, both with `cache_control={"type": "ephemeral"}`, block 1 mentions "preseason" / "season outlook", block 2 mentions every manager's `display_name`. Assert `build_user_prompt(...)` includes a "Final Standings" header and every team's win/loss/fpts | Catches prompt drift during PR review |
| `tests/test_preseason_orchestrator.py` (new) | With moto-mocked Dynamo + mocked Sleeper client + mocked Claude client: `run("L1", dry_run=True, force=False)` writes a row with `report_type="preseason"`, `period="2026-PRESEASON"`, `prompt_version="f2-preseason-..."`; dry-run delivery sends 1 email (to caller); non-dry-run sends 12 (one per whitelisted manager) | End-to-end orchestrator behavior under mocks |

### `xomper-ios/Xomper/Core/Networking/XomperAPIClient.swift`
| Change | Why |
|--------|-----|
| Extend the `XomperAPIClientProtocol` with `func triggerPreseasonAIReview(dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse`. Implement on the concrete class by mirroring `triggerPostDraftAIReview` and POSTing to `/admin/ai-review-preseason-trigger`. Reuse the `AIReviewTriggerResponse` Decodable — no new response struct | Single new method; same wire shape as F1 |

### `xomper-ios/Xomper/Core/Stores/AdminStore.swift`
| Change | Why |
|--------|-----|
| Add Preseason state mirroring the Post-Draft state. New properties: `private(set) var preseasonLatest: AIReport?`, `private(set) var isTriggeringPreseason = false`, `private(set) var preseasonError: Error?`, `private(set) var preseasonResult: AIReviewTriggerResponse?`, `var preseasonDryRun: Bool = true`. New methods: `func loadPreseasonLatest() async` (silent on failure like postdraft), `func triggerPreseason(dryRun:force:) async throws -> AIReviewTriggerResponse` (mirrors `triggerPostDraft` — sets `isTriggeringPreseason`, calls `apiClient.triggerPreseasonAIReview(...)`, refreshes `preseasonLatest` on success) | Second trigger flow alongside post-draft |

### `xomper-ios/Xomper/Features/Admin/AdminView.swift`
| Change | Why |
|--------|-----|
| In `content`, insert a new `preseasonTriggerCard` directly below `postDraftTriggerCard` in the `VStack`. Add `preseasonTriggerCard` computed view that is a structural copy of `postDraftTriggerCard` — different title ("Preseason AI Review"), different status-line method (`preseasonStatusLine`), different button label method (`preseasonPrimaryButtonLabel`), different result-line method (`preseasonResultLine`), bound to `store.preseasonDryRun` / `store.isTriggeringPreseason` / `store.preseasonLatest` / `store.preseasonResult` / `store.preseasonError`. In the `.task(id:)` and `.refreshable` blocks, also call `await store.loadPreseasonLatest()` next to `loadPostDraftLatest()` | Second trigger card stacked below the first; identical UX |

### `xomper-ios/XomperTests/`
| File | Change | Why |
|--------|-----|------|
| `AdminStoreTests.swift` (edit, if it exists) OR new `AdminStorePreseasonTests.swift` | Mirror existing post-draft store tests: `loadPreseasonLatest` populates `preseasonLatest` on success and nils on failure; `triggerPreseason(dryRun:true, force:false)` calls the mock client with the right path + flags, populates `preseasonResult`, and re-runs `loadPreseasonLatest`; error path populates `preseasonError` and rethrows | Store unit tests on the existing test target |

### `xomper-ios/project.yml`
| Change | Why |
|--------|-----|
| No edits expected — no new files outside existing source roots | Build inclusion |

---

## Open Design Decisions (resolved)

### 1. Trigger mechanism
Same as F1: admin-triggered `POST /admin/ai-review-preseason-trigger` with `{dry_run: bool, force: bool}`. Default `dry_run=true`. Server enforces admin-only via `whitelisted_users.is_admin`. No EventBridge cron in v1 — we want manual control over timing relative to Sleeper roster moves + injury news. v1.1 could add a one-time scheduled rule for early September.

### 2. Period string format
**Pick: `"2026-PRESEASON"`** (string suffix, not a separate year).

Per `ai_reports_store.py`'s docstring (read at execute time to confirm), `period` is a free-form string used in SK `REPORT#<report_type>#<period>`. F1 chose `"2026"` (per the F1 PR descriptions). To avoid collision risk on the same year — and to keep human-readable distinct from F1 — F2 uses `"2026-PRESEASON"`. This makes the SK `REPORT#preseason#2026-PRESEASON`, fully distinct from F1's `REPORT#postDraft#2026`. F3 will follow the same suffixing convention (`2026W01`, etc.).

If F1 in fact used `"2026-POSTDRAFT"` (read PR descriptions to confirm), update this section and use `"2026-PRESEASON"` symmetrically. Either way, the F2 period **must include the year + the phase suffix** so the same league can re-run preseason next year without overwriting.

### 3. Prompt skeleton

**System block 1 — tone + safety** (cache-controlled, ~500 tokens). Reuse F1's structure but re-anchor:
- Voice anchors: "you're roasting your friends about their fantasy futures, leaning on last year's wins and losses and the lineup they're walking into Week 1 with. Personal but never cruel. Specific, not generic."
- Forbidden topics: same block-list as F1 (specific tragedies + named non-league people).
- Output format: markdown with one `## <team name>` header per manager, 2-3 paragraphs each, in order of last-year's final standing (worst-to-first or first-to-worst — orchestrator decides at compose-time).
- Required: every paragraph must reference at least one concrete data point (last year's record, last year's PF, a specific player on the current roster, a known lore tidbit).

**System block 2 — lore** (cache-controlled, ~3000 tokens). Verbatim reuse of F1's lore-block generation from `LEAGUE_LORE`. If F1 factored this into a `lambdas/common/lore_prompt.py` helper already, just import. Otherwise factor it out during F2 (still cheap; bonus prep for F3).

**User prompt** (uncached, per-call):
```
This is the 2026 preseason. Here is the data for the league:

## Final 2025 Standings
1. <manager_display_name> — 11-3, 1654.2 PF
2. ...
12. <manager_display_name> — 3-11, 1102.5 PF

## 2026 Rosters
<manager_display_name> (Pick 1, 2025 finish: 3-11):
  QB: <player_id>
  RB: <player_id>, <player_id>
  WR: ...
  ...

<manager_display_name> (Pick 2, 2025 finish: 11-3):
  ...

## Your task
Write a preseason recap that grades each manager on last year and previews this year, in order from worst-2025-finish to best. Use the lore. Use the data. Don't invent injuries, trades, or news that isn't in the data.
```

Player IDs (not names) ship in v1. Claude knows the majority of NFL player IDs via training data; misses degrade gracefully ("the Ravens RB you drafted at pick 24"). v1.1: add a Sleeper `/players/nfl` fetch + cache to resolve names — punt for now.

### 4. Data inputs (Sleeper endpoints)
- `GET /league/<current_league_id>` — for `previous_league_id`
- `GET /league/<previous_league_id>` — last year's league metadata (name, season)
- `GET /league/<previous_league_id>/rosters` — last year's final rosters; derive standings via `settings.wins / settings.losses / settings.fpts + settings.fpts_decimal`
- `GET /league/<current_league_id>/rosters` — this year's roster snapshot
- `GET /league/<current_league_id>/users` — owner display names + user_ids for lore lookup

If F1 already exposes `walk_previous_league_chain` in `sleeper_helper.py` (per PR #58), use it. If not, F2 adds a one-hop `get_previous_league_id(league_id)` + `get_sleeper_league_rosters(prev_id)`.

**Player names**: skipped in v1. Reference `player_id` strings in the user prompt. Acceptable degradation — Claude resolves most via training data, and the worst-case roast still works ("your Round 4 pick").

### 5. Idempotency key
`(league_id, "preseason", "2026-PRESEASON")`. Matches F1's `(league_id, "postDraft", <F1-period>)` shape — whatever string F1 actually used as its period, F2 mirrors the structure. `get_latest(league_id, "preseason")` returns the most-recent preseason row; handler checks `force=false` + row-exists → 409.

### 6. Trigger timing
Admin button only in v1. User fires it manually after the August 30 roster freeze when injury status is mostly settled but before Week 1 Thursday kickoff. ~1 dry-run + tone tweak + 1 broadcast — 2 invocations total expected.

### 7. iOS admin card
Direct copy of F1's `postDraftTriggerCard`. Lives directly below it in `AdminView.content`. Identical visual chrome (championGold accent, dry-run toggle, Generate / Regenerate buttons with the same dynamic label rules, status line + result/error line). Only differences:
- Title: "Preseason AI Review"
- Status copy: "No report yet — first run will be dry-run." → unchanged; "Last dry-run completed at..." → unchanged; "Broadcast on..." → unchanged. The status-line method gets renamed (`preseasonStatusLine`) but the format is identical
- Bound to `store.preseason*` properties instead of `store.postDraft*`
- Calls `store.triggerPreseason(...)` instead of `store.triggerPostDraft(...)`

### 8. Cost
- Input: ~5k tokens (~3.5k cached lore + ~500 cached tone + ~1k user prompt) = $0.001 cached + $0.0008 fresh = ~$0.002
- Output: ~5k tokens (12 manager sections × ~400 tokens each) = $0.020
- Per-generation: ~$0.022
- Expected calibration: 2-3 dry-runs + 1 broadcast = **~$0.10** for the F2 cycle
- Hard ceiling: **<$0.50** for the F2 cycle (acceptance criterion)

---

## Implementation Steps (dependency-ordered, file-by-file)

### Repo 1: `xomper-infrastructure`

- [ ] **Step 1** — Read `terraform/lambdas_api.tf` to confirm the local's shape and how F1's `api-admin-ai-review-postdraft-trigger` entry was structured. Match it exactly.
- [ ] **Step 2** — In `terraform/lambdas_api.tf`, append the new entry under the existing `api_lambdas` local: `name = "api-admin-ai-review-preseason-trigger"`, `path_part = "ai-review-preseason-trigger"`, `http_method = "POST"`, `description = "AI Review: admin-triggered preseason report (dry-run first, then broadcast)"`, parented under `/admin/*` to match F1.
- [ ] **Step 3** — **Verify only** — `iam_lambdas.tf` wildcards from F0 cover the new lambda role's Dynamo R/W + SSM read. Add a one-line code-comment noting the new lambda is covered. No statement edits.
- [ ] **Step 4** — Open infra PR; pass plan output through `gh pr create`. Merge → `terraform apply` deploys the API GW route (stub lambda returns 502 until backend ships).

### Repo 2: `xomper-back-end` (after Step 4 merged + applied)

- [ ] **Step 5** — Pull F1's `lambdas/api_admin_ai_review_postdraft_trigger/` as the structural template. Read all four files end-to-end so the F2 copy is a true mirror.
- [ ] **Step 6** — Create `lambdas/api_admin_ai_review_preseason_trigger/__init__.py` (empty).
- [ ] **Step 7** — Create `lambdas/api_admin_ai_review_preseason_trigger/handler.py`. Copy F1's handler verbatim, swap: route description, `report_type="preseason"`, `period="2026-PRESEASON"`, call into `from .orchestrator import run` (local-module import).
- [ ] **Step 8** — Create `lambdas/api_admin_ai_review_preseason_trigger/orchestrator.py`. Lift F1's orchestrator structure; replace the draft-pick fetch with the four Sleeper endpoints in **Data inputs** above; build prior-standings + current-roster summary dicts; call into `prompts.build_system_blocks()` + `prompts.build_user_prompt(...)`; call `claude_helper.generate(system=blocks, user=prompt, model="claude-haiku-4-5", max_tokens=6000)`; call `ai_reports_store.write_report(league_id, "preseason", "2026-PRESEASON", body_markdown=resp.body, metadata={prompt_version, model, token_usage_in, token_usage_out, dry_run})`; deliver email per `dry_run` flag.
- [ ] **Step 9** — Create `lambdas/api_admin_ai_review_preseason_trigger/prompts.py`. Implement `build_system_blocks()` (2 blocks, both `cache_control` ephemeral) and `build_user_prompt(prior_standings, current_rosters, narrative_hints=None)`. Pin `PROMPT_VERSION = "f2-preseason-2026-05-21"`. Lore block 2 either imports `lore_prompt.build_lore_block()` (if F1 already factored it) or inlines the same generation logic.
- [ ] **Step 10** — If F1 left lore-block generation duplicated, factor it now into `lambdas/common/lore_prompt.py` with `build_lore_block() -> dict` returning the `{type, text, cache_control}` shape. Replace F1's inlined version with the import in a follow-up commit on the same PR.
- [ ] **Step 11** — Verify `sleeper_helper.py` has `get_previous_league_id` + `get_sleeper_league_rosters` (added in F1 per PR description). If anything's missing for the prior-season-standings derivation, add it here.
- [ ] **Step 12** — Add `AI_REVIEW_PRESEASON_PROMPT_VERSION` to `constants.py` (optional; `prompts.py` may own its own constant — pick one and stick to it).
- [ ] **Step 13** — Create `tests/test_api_admin_ai_review_preseason_trigger.py` — five cases enumerated in the **Tests** table above.
- [ ] **Step 14** — Create `tests/test_preseason_prompts.py` — asserts block structure + cache flags + lore content.
- [ ] **Step 15** — Create `tests/test_preseason_orchestrator.py` — moto + mocked Sleeper/Claude end-to-end.
- [ ] **Step 16** — Run `pytest tests/` — all green, including the existing F0/F1 suites.
- [ ] **Step 17** — Open backend PR. CI pipeline picks up the new lambda dir and zips it. On merge, `deploy-backend.yml` deploys the lambda over the infra stub.
- [ ] **Step 18** — Smoke-test post-deploy: `curl -X POST -H "Authorization: Bearer <admin-jwt>" -H "Content-Type: application/json" -d '{"dry_run": true, "force": false}' $API/admin/ai-review-preseason-trigger` → expect 200 with `AIReviewTriggerResponse` shape; dry-run email arrives at admin inbox; row visible in Dynamo at PK `LEAGUE#<id>` / SK `REPORT#preseason#2026-PRESEASON`.

### Repo 3: `xomper-ios` (after Step 18 verified)

- [ ] **Step 19** — Edit `Xomper/Core/Networking/XomperAPIClient.swift`. Add `triggerPreseasonAIReview(dryRun:force:)` to the protocol (one new line below `triggerPostDraftAIReview`) + impl on the concrete class (mirror F1's impl, swap path to `/admin/ai-review-preseason-trigger`).
- [ ] **Step 20** — Edit `Xomper/Core/Stores/AdminStore.swift`. Add the five preseason state vars + two methods (`loadPreseasonLatest` + `triggerPreseason`) as a structural copy of the existing post-draft block. Anchor the new code in a `// MARK: - Preseason AI Review` block directly below the existing `// MARK: - Post-Draft AI Review` block for readability.
- [ ] **Step 21** — Edit `Xomper/Features/Admin/AdminView.swift`. Add `preseasonTriggerCard` computed view + supporting helpers (`preseasonStatusLine`, `preseasonPrimaryButtonLabel`, `preseasonResultLine`, `triggerPreseason(force:)`) as structural copies of the post-draft equivalents. Insert it into `content`'s `VStack` directly below `postDraftTriggerCard`. Add `await store.loadPreseasonLatest()` next to `loadPostDraftLatest()` in both `.task(id:)` and `.refreshable`.
- [ ] **Step 22** — Add `XomperTests/AdminStorePreseasonTests.swift` (or extend `AdminStoreTests.swift` if it exists) with the four cases enumerated above.
- [ ] **Step 23** — Run `xcodegen generate` (only needed if new files were added — `AdminStorePreseasonTests.swift` is the only candidate).
- [ ] **Step 24** — Build via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Xomper -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`. Run `XomperTests` — all green.
- [ ] **Step 25** — Manual QA on simulator: AdminView shows two cards stacked (Post-Draft above, Preseason below). Tap Preseason → "Generate Dry Run" → spinner → success line + email lands. Toggle off dry-run → "Generate & Broadcast" → 12 emails fan out. Refresh → "Broadcast on <date>" status line. Tap AI Review in drawer → archive shows the new preseason row above the post-draft row.
- [ ] **Step 26** — Open iOS PR. Three coordinated PRs (infra → backend → iOS) merged in order.

---

## Test Plan

### Backend (pytest)
- `test_api_admin_ai_review_preseason_trigger.py`:
  - Non-admin caller → 403 (Supabase admin check fails)
  - Admin + no existing report → 200, orchestrator called once, `dry_run=true` honored, response shape matches `AIReviewTriggerResponse`
  - Admin + existing report + `force=false` → 409 with the existing report in the body
  - Admin + existing report + `force=true` → 200, orchestrator called, new row written (overwrites SK in Dynamo)
  - Malformed JSON body → 400
- `test_preseason_prompts.py`:
  - `build_system_blocks()` returns exactly 2 blocks
  - Both blocks carry `cache_control={"type": "ephemeral"}`
  - Block 1 text contains "preseason" + "outlook" + forbidden-topics list
  - Block 2 text contains every `display_name` from `LEAGUE_LORE`
  - `build_user_prompt(...)` includes "Final 2025 Standings" header + every team's W-L-PF + every team's current roster
  - `PROMPT_VERSION` is the pinned constant
- `test_preseason_orchestrator.py` (moto + mocked Sleeper + mocked Claude):
  - `run("L1", dry_run=True, force=False)` writes one row with `report_type="preseason"`, `period="2026-PRESEASON"`, `prompt_version="f2-preseason-..."`, `model="claude-haiku-4-5"`
  - Dry-run sends 1 email (to caller); non-dry-run sends 12 (one per whitelisted manager)
  - Sleeper calls hit `previous_league_id` chain exactly once
  - Claude `system` arg is a list of 2 dicts (not a string)

### iOS (XCTest)
- `AdminStorePreseasonTests` (or extension to `AdminStoreTests`):
  - `loadPreseasonLatest()` populates `preseasonLatest` on mocked-200 with a preseason `AIReport`
  - `loadPreseasonLatest()` silently nils `preseasonLatest` on mocked-error
  - `triggerPreseason(dryRun: true, force: false)` calls the mock client with the right path + flags, populates `preseasonResult`, triggers a follow-up `loadPreseasonLatest` (verified by call-count on mock)
  - Error path populates `preseasonError`, clears `isTriggeringPreseason`, rethrows

### Smoke (post-deploy)
- `curl -X POST -H "Authorization: Bearer <admin-jwt>" -H "Content-Type: application/json" -d '{"dry_run":true,"force":false}' $API/admin/ai-review-preseason-trigger` returns 200 with valid `AIReviewTriggerResponse`
- Dry-run email arrives at admin inbox with the new report rendered as HTML
- Dynamo row written at PK `LEAGUE#<id>` / SK `REPORT#preseason#2026-PRESEASON`
- iOS AdminView shows the new preseason trigger card; tapping "Generate Dry Run" succeeds end-to-end and updates the status line
- iOS AIReviewView archive lists the new preseason row at the top with the correct `displayName` (Preseason) and `period` (2026-PRESEASON)
- `AIReviewHomeCard` on Home banner picks up the preseason report if it's the most recent across all types

---

## Out of Scope
- F1 post-draft regressions / changes (F1 is shipped; only touch if F2 needs a shared-module factoring)
- F3 weekly recap (separate plan + epic phase)
- Live NFL news ingestion (`web_search`, RSS sidecar) — Phase 4
- Player name resolution from `/players/nfl` — v1.1 follow-up; v1 references player IDs
- Hand-curated offseason narrative paragraphs (injuries returning, big keepers, etc.) — the LLM authors these from the data inputs; no human intervention in v1
- Scheduled / cron-triggered preseason fire — v1.1 follow-up; v1 is admin-button only
- Push notification teaser dispatch — wires through F1's existing pipeline; F2 reuses without modification (orchestrator's broadcast leg calls the same push helper F1 set up)
- Read-state badges on iOS — Phase 4
- Per-manager personalized roasts (different email body per recipient) — out of scope per epic Q4 (hybrid shared body + per-user header was the pick)
- Admin "regenerate" / "send now" surfaced separately from the dry-run + force flags — already covered by the F1 button pattern; no new actions

---

## Risks / Tradeoffs
- **Player ID degradation**: referencing `player_id` strings instead of names risks Claude producing generic copy ("the running back you drafted") for less-famous players. Acceptable for v1 — preseason content leans on lore + standings, not deep player-specific takes. Mitigation: revisit during the dry-run review; if quality drops, add a `/players/nfl` cache lookup in v1.1
- **Period-string collision**: if F1 actually used `"2026"` (not `"2026-POSTDRAFT"`) as its period, F2's `"2026-PRESEASON"` is fine. If F1 used `"2026-POSTDRAFT"`, also fine. **Read F1 PR descriptions during execute and confirm before merging**
- **Prior-season league walk**: relies on Sleeper exposing `previous_league_id` correctly on the active league. If the chain is broken (e.g. league wasn't carried over), the orchestrator should gracefully fall back to "no prior standings available" and still generate a forward-looking outlook. Add a defensive branch in `orchestrator.py`
- **Lore staleness**: 2025 → 2026 may have new engagements, jobs, etc. that aren't in `league_lore.py` yet. Out-of-scope to update lore here, but flag in the dry-run review for a follow-up lore PR
- **Prompt drift between F1 and F2**: tone block 1 is *re-anchored* but not identical to F1's. Risk that F2 feels off-voice compared to F1. Mitigation: dry-run mandatory; admin compares F1 + F2 outputs side-by-side before broadcast
- **Idempotency edge case**: if admin runs dry-run, then forces broadcast, then forces a second broadcast within the same minute, the second one overwrites the first in Dynamo (same SK). Acceptable — broadcast is idempotent on the email side too (12 sends per call), so re-broadcasting just sends 12 more emails. Document the behavior; don't add a debounce in v1
- **Cache invalidation**: any edit to `LEAGUE_LORE` or to system block 1 invalidates the Anthropic ephemeral cache and the next call pays full lore tokens (~$0.003 extra). Negligible
- **No new IAM**: F0 wildcards cover the new lambda. **Verify during step 3** — if F0 actually pinned per-lambda statements (not wildcards), F2 needs a one-line IAM addition

---

## Open Questions
- [ ] Confirm F1's exact period string (`"2026"` vs `"2026-POSTDRAFT"`) by reading PR #58 + PR #82 descriptions before merging F2's period choice
- [ ] Confirm whether F1 factored `build_lore_block()` into `lambdas/common/lore_prompt.py` already, or if F2 should do that factoring on the same PR
- [ ] Confirm `sleeper_helper.py` exposes `get_previous_league_id` and a rosters-fetch + standings-derivation helper, or if F2 adds them
- [ ] Decide at dry-run time whether to ship player IDs (v1) or hold F2 for a v1.1 with name resolution — default to ship-with-IDs unless dry-run reveals it's broken
- [ ] Drawer placement: does the AI Review tray destination need any F2-specific update, or does F0's generic archive handle the new `report_type` without any change? Default assumption is no iOS UI change beyond AdminView

---

## Acceptance Checklist — F2 Done When
- [ ] Infra PR merged + `terraform apply` clean: new `/admin/ai-review-preseason-trigger` route exists in API GW, returns 200 with admin JWT, 401 without
- [ ] Backend PR merged + deployed: `lambdas/api_admin_ai_review_preseason_trigger/` ships; admin POST returns valid `AIReviewTriggerResponse`; row written to Dynamo at PK `LEAGUE#<id>` / SK `REPORT#preseason#2026-PRESEASON`
- [ ] iOS PR merged: AdminView shows two trigger cards stacked (Post-Draft + Preseason); Preseason card behavior mirrors Post-Draft (dry-run default, force flag, regenerate button, status line, result/error line)
- [ ] Dry-run cycle: admin fires dry-run → receives email rendering ~12 manager sections with correct lore references + correct 2025 standings + correct 2026 roster snapshot
- [ ] Broadcast cycle: admin toggles off dry-run → fires → 12 emails delivered (verify via notification_log)
- [ ] iOS archive: new preseason row appears in `AIReviewView` with `displayName = "Preseason"` and `period = "2026-PRESEASON"`; detail view renders markdown correctly
- [ ] Home banner: if preseason report is the most recent, `AIReviewHomeCard` surfaces it
- [ ] Cost: total Anthropic spend for F2 calibration cycle < $0.50
- [ ] All backend pytest + iOS XCTest suites green
- [ ] No regression on F1 — post-draft trigger still works end-to-end

---

## Skills / Agents to Use
- **execute agent** — drives this plan to merged PRs once status flips to Ready
- **research agent** — invoke only if `claude_helper.py`'s `system: list[dict]` signature changed since F1; otherwise skip
- **brainstorm agent** — not needed; F2 is a structural remix of F1 with locked decisions
