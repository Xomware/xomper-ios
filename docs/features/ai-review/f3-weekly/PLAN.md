# Plan: AI Review — F3 Weekly Recap (Phase 3)

**Epic**: `docs/features/ai-review/EPIC_PLAN.md`
**Phase**: 3
**Status**: Ready
**Created**: 2026-05-21
**Last updated**: 2026-05-21
**Depends on**: F0 (shared infra — shipped, PRs #80/#57/#81), F1 (post-draft trigger — shipped, PRs #103/#58/#83), F2 (preseason trigger — shipped, PRs #104/#105/#59 — locks shared `lore_prompt.py` and the admin-trigger-card UI pattern)

---

## Summary
F3 is the highest-volume, highest-tone-risk phase of the AI Review epic: a **cron-triggered** Claude-generated league newsletter that runs every Tuesday afternoon during the season, roasts every manager by name using that week's matchup results + league-wide season memories + lore, persists the report to `xomper-ai-reports`, broadcasts the hybrid email + push teaser, and **auto-appends 3–5 new season memories** to a new Dynamo table (`xomper-ai-memories`) so the next week's prompt carries continuity.

Ships as a **new sibling lambda** to the existing `notif_weekly_recap` (not a remix of it) so the AI recap can be deployed, A/B-tested, scheduled, and disabled independently of the existing non-AI weekly recap email. Adds a parallel **admin trigger lambda + AdminView card** so the recap can be fired manually for dry-run calibration before Week 1 and for retry / on-demand generation during the season.

Success = three coordinated PRs (infra → backend → iOS) merged + deployed; the cron fires for Week 1 in September 2026 and lands a roast in inboxes + iOS archive; the memory table accumulates 3–5 entries per week and feeds back into Week N+1's prompt; total Anthropic spend across the full 22-week regular + playoff schedule stays under **$1**.

---

## Approach
A genuine new artifact, not a remix. Three reasons F3 needs its own lambda rather than extending `notif_weekly_recap`:

1. **Different product**: the existing weekly recap is a deterministic scoring email; F3 is a Claude-generated narrative. They should ship to inboxes separately so the user can tell them apart.
2. **Different cadence**: existing recap runs Tue 09:00 ET; F3 should run later in the day to (a) not collide with the morning recap email and (b) give Monday Night Football's stats time to settle through Sleeper's snapshot.
3. **Different blast radius on failure**: if Claude API is down on a Tuesday, the existing recap should still fire normally; F3 should fail independently with a "report delayed" SNS to admin.

F3's architecture mirrors F2's admin-trigger pipeline (orchestrator + prompts + tests) but adds:

- A new EventBridge cron rule
- A new `ai_memories_store.py` common module backed by a new `xomper-ai-memories` Dynamo table
- A **memory loop**: read last N memories → inject into Claude's user prompt → ask for a structured JSON envelope (recap markdown + 3–5 new memories) → persist both
- A new admin trigger endpoint (`POST /admin/ai-review-weekly-trigger`) for manual fires + dry-runs (uses the same orchestrator)
- Symmetric iOS admin card (third card below F1/F2 in `AdminView`)

Architectural decisions resolved (rationale in **Open Design Decisions** below):

| # | Decision | Pick |
|---|----------|------|
| 1 | New lambda vs. extend `notif_weekly_recap` | **New sibling lambda** `notif_ai_review_weekly` |
| 2 | Cron expression | `cron(0 14 ? * TUE *)` (Tue 14:00 ET) |
| 3 | Memory storage | **New Dynamo table** `xomper-ai-memories` |
| 4 | Memory schema | `SeasonMemory` dataclass — `memory_id`, `season`, `week`, `manager_user_id`, `text`, `sentiment`, `created_at` |
| 5 | Memory generation | **Single-pass** — Claude returns structured JSON envelope `{ "body_markdown": "...", "new_memories": [...] }` |
| 6 | Idempotency | Period key `2026W<NN>`; if a row exists for that key + `force=false` → skip with 409 (mirrors F1/F2) |
| 7 | Week selection | Cron resolves "the just-completed week" as `sleeper_nfl_state.week - 1` (or `sleeper_nfl_state.previous_season_week` if available); pin defensively |
| 8 | Admin trigger | Yes — `POST /admin/ai-review-weekly-trigger` with optional `week`, `dry_run`, `force` (reuses orchestrator) |
| 9 | iOS admin card | Yes — third trigger card on `AdminView` below preseason |
| 10 | Memory season scoping | PK includes `SEASON#<year>` so 2027 starts fresh without manual purge |
| 11 | Lookback window | Last **6 memories** by recency (not "last 6 weeks") — caps token cost regardless of how chatty a week was |
| 12 | Dry-run calibration | Run 2–3 dry-runs against **2025 matchup data** (via `previous_league_id` chain) before Week 1 2026 ships |

---

## Repos Touched
- `xomper-infrastructure` — new `xomper-ai-memories` DynamoDB table (mirror `xomper-ai-reports` schema), new EventBridge cron rule in `lambdas_scheduled.tf` matching the `notif_weekly_recap` pattern, one new API GW route in `lambdas_api.tf` for the admin trigger lambda. IAM wildcards from F0 already cover the new table + lambdas — verify only.
- `xomper-back-end` — new `lambdas/notif_ai_review_weekly/` dir (`__init__.py`, `handler.py`, `orchestrator.py`, `prompts.py`); new `lambdas/api_admin_ai_review_weekly_trigger/` dir (`__init__.py`, `handler.py`); new `lambdas/common/ai_memories_store.py`. Extend `sleeper_helper.py` only if missing matchup helpers. New test files.
- `xomper-ios` — extend `XomperAPIClient` with `triggerWeeklyAIReview(week:dryRun:force:)`; extend `AdminStore` with weekly state + methods; add `weeklyTriggerCard` to `AdminView` directly below `preseasonTriggerCard`.

---

## Affected Files / Components

### `xomper-infrastructure/terraform/`
| File | Change | Why |
|------|--------|-----|
| `dynamodb.tf` | Add `aws_dynamodb_table.ai_memories` resource mirroring `xomper-ai-reports`: PK `pk` (S), SK `sk` (S), KMS encryption, PITR, PAY_PER_REQUEST, standard tags. No GSI in v1 (queries are always by PK + SK prefix). Name = `xomper-ai-memories` | Storage for season-memory entries; intentionally separate from reports table to keep schema crisp |
| `lambdas_scheduled.tf` | Append a new scheduled-lambda entry mirroring the existing `notif_weekly_recap` block: `name = "notif_ai_review_weekly"`, `cron_expression = "cron(0 14 ? * TUE *)"` (Tue 14:00 UTC — verify timezone semantics against existing entries; if existing crons are interpreted UTC and `notif_weekly_recap` is 13:00 UTC = 09:00 ET, then 14:00 UTC = 10:00 ET — too early; use `cron(0 18 ? * TUE *)` = 14:00 ET. **Pin the actual UTC offset by reading the existing file at execute-time and matching ET intent**), `description = "AI Review: weekly recap — fires every Tuesday afternoon during NFL season; orchestrator no-ops outside Weeks 1-22"`, lambda timeout 300s, memory 1024MB | New cron trigger — sibling to `notif_weekly_recap`, not a replacement |
| `lambdas_api.tf` | Append one entry to `api_lambdas` local mirroring F1/F2's trigger shape: `name = "api-admin-ai-review-weekly-trigger"`, `path_part = "ai-review-weekly-trigger"`, `http_method = "POST"`, `description = "AI Review: admin-triggered weekly recap (dry-run + week override + force)"`, parented under `/admin/*` | Admin override endpoint for dry-runs + retries |
| `iam_lambdas.tf` | **Verify only** — F0 wildcards cover Dynamo R/W on `xomper-ai-*` and SSM read on `/xomper/api/*`. Add a one-line comment naming `xomper-ai-memories` as covered. No statement edits expected | Confirms coverage |
| `outputs.tf` | Add `ai_memories_table_name` + `ai_memories_table_arn` outputs (mirror reports table outputs) | Future-proof; non-blocking |

### `xomper-back-end/lambdas/common/ai_memories_store.py` (new)
| File | Change | Why |
|------|--------|-----|
| `ai_memories_store.py` (new) | Top-of-file docstring documents schema (see **Open Design Decisions §4**). Functions: `append_memories(league_id, season, week, memories: list[SeasonMemory]) -> list[dict]` (BatchWriteItem; one Dynamo row per memory); `list_recent_memories(league_id, season, limit=6) -> list[SeasonMemory]` (Query on PK with SK `begins_with MEMORY#`, `ScanIndexForward=False`, `Limit=limit`); `clear_season(league_id, season) -> int` (delete-all helper for season teardown — admin-only utility, not called by the cron); `SeasonMemory` dataclass with fields enumerated below | Dynamo R/W for the new memory table |

Schema doc (top of file):
```
PK: LEAGUE#<league_id>#SEASON#<year>          (e.g. LEAGUE#1234#SEASON#2026)
SK: MEMORY#<week:02d>#<memory_id>             (e.g. MEMORY#04#0aef-uuid)
Attributes:
  memory_id     S   uuid4 hex
  season        N   2026
  week          N   4
  manager_user_id S OPTIONAL — Sleeper user_id this memory primarily concerns; absent = league-wide
  text          S   one-line memory ("Connor benched LeBron James and lost by 0.5")
  sentiment     S   "roast" | "praise" | "lore"
  created_at    S   ISO 8601 UTC
```

### `xomper-back-end/lambdas/notif_ai_review_weekly/` (new dir)
| File | Change | Why |
|------|--------|-----|
| `__init__.py` (new, empty) | Package marker | Lambda discovery |
| `handler.py` (new) | EventBridge entry point. Reads `event.get("week")` if present (manual override path), otherwise resolves the just-completed week via `sleeper_helper.get_nfl_state()` (`week - 1`, floor-clamped to 1). Resolves active league via `supabase_helper.get_active_whitelisted_league`. Pre-flight check: if `week < 1 or week > 22` → log and return early (off-season no-op). Idempotency: if `force=False` and `ai_reports_store.get_latest(league_id, "weekly")` returns a row with `period == f"2026W{week:02d}"` → log "already generated" and exit 0 with the existing report id. Otherwise call `orchestrator.run(league_id, week, dry_run=False, force=False)` synchronously. On terminal Claude failure → publish a "report delayed" SNS to admin and re-raise so EventBridge logs the failure | Cron entry — owns scheduling logic + idempotency + safe failure |
| `orchestrator.py` (new) | `def run(league_id: str, week: int, dry_run: bool, force: bool) -> dict`. Steps: (1) fetch matchup data via `sleeper_helper.get_sleeper_league_matchups(league_id, week)`; (2) fetch rosters + users for owner-name resolution; (3) compute per-matchup result summary (winner, loser, margin, top scorer, bench points left on bench); (4) read last 6 memories via `ai_memories_store.list_recent_memories(league_id, 2026, limit=6)`; (5) call `prompts.build_system_blocks()` + `prompts.build_user_prompt(week, matchups, prior_memories)`; (6) call `claude_helper.generate(system=blocks, user=prompt, model="claude-haiku-4-5", max_tokens=6000, response_format="json")` — request structured JSON envelope; (7) parse JSON `{body_markdown, new_memories}`; on parse failure, log + fall back to "treat entire response as markdown, skip memory append"; (8) `ai_reports_store.write_report(league_id, "weekly", f"2026W{week:02d}", body_markdown, metadata={prompt_version, model, token_usage_in, token_usage_out, dry_run, week, memory_count_in=len(prior), memory_count_out=len(new)})`; (9) `ai_memories_store.append_memories(league_id, 2026, week, parsed_memories)`; (10) deliver email per `dry_run` flag (same hybrid pattern as F1/F2 — admin only on dry-run; all 12 managers on broadcast); (11) fire teaser push notification. Returns `AIReviewTriggerResponse`-shaped dict | Pipeline glue — the longest orchestrator of the epic |
| `prompts.py` (new) | Two builders. `build_system_blocks() -> list[dict]` returns three `{type, text, cache_control}` blocks: **block 1** (cached) = weekly-tuned tone + safety rails (the strictest of the three — explicit "your job is to roast results that actually happened; never invent injuries / trades / off-field news; never mention named non-league people; never make jokes about real-world tragedies; lean on lore + matchup data + prior memories"); **block 2** (cached) = lore dump via `lore_prompt.build_lore_block()` (factored in F2); **block 3** (cached) = **output-format spec** — explicit JSON schema for the envelope, with worked example. `build_user_prompt(week, matchups, prior_memories) -> str` composes the per-call user prompt: week-N matchup table (winner/loser/scores/margin/bench-left), top performer + biggest dud per matchup, list of prior memories as bullets, "Your task" footer. Pin `PROMPT_VERSION = "f3-weekly-2026-05-21"` | Tone-calibrated prompt skeleton + JSON-envelope contract |

### `xomper-back-end/lambdas/api_admin_ai_review_weekly_trigger/` (new dir)
| File | Change | Why |
|------|--------|-----|
| `__init__.py` (new, empty) | Package marker | Lambda discovery |
| `handler.py` (new) | POST handler. Auth: admin-only via `whitelisted_users.is_admin`. Parse JSON body: `week` (optional int, defaults to "current just-completed week" resolved like the cron handler does), `dry_run` (default `true`), `force` (default `false`). Resolve active league. Idempotency: same as cron handler. Invoke `from notif_ai_review_weekly.orchestrator import run` directly (cross-package import — both lambdas zip with `lambdas/` as the package root in the existing build) **OR** factor the orchestrator into `lambdas/common/weekly_orchestrator.py` if cross-package imports are brittle — confirm at execute time by reading how F1/F2's admin trigger lambdas reach their orchestrators | Manual override endpoint — for dry-runs, retries, week-override |

### `xomper-back-end/lambdas/common/` (verify / extend)
| File | Change | Why |
|------|--------|-----|
| `sleeper_helper.py` (edit if needed) | Verify the following exist (added in F1 PR #58 per epic notes): `get_sleeper_league_matchups(league_id, week)`, `get_nfl_state()` returning `{week, season, season_type}`, `get_sleeper_league_rosters(league_id)`, `get_sleeper_league_users(league_id)`. If `get_nfl_state` is missing, add it (one-line wrapper around `/state/nfl`) | Matchup fetch + week resolution |
| `lore_prompt.py` (verify) | F2 should have factored `build_lore_block() -> dict` into this module. If not, factor on the F3 PR (small) | Shared system-block builder |
| `ai_reports_store.py` | **No change** — `write_report` accepts arbitrary `report_type` + `period` | F0 contract holds |
| `email_templates/ai_review.py` | **No change** — generic renderer; F3 passes `"weekly"` as the report type | F0 contract holds |
| `errors.py` | Add `class MemoryStoreError(XomperError)` next to `ClaudeAPIError` | Typed error path for Dynamo memory I/O |
| `constants.py` | Add `AI_MEMORIES_TABLE = os.environ.get("APP_NAME", "xomper") + "-ai-memories"`. Add `AI_REVIEW_WEEKLY_PROMPT_VERSION = "f3-weekly-2026-05-21"` (or let `prompts.py` own its own constant — pick one and stick to it) | Centralized table name + prompt version stamp |

### `xomper-back-end/tests/`
| File | Change | Why |
|------|--------|-----|
| `tests/test_ai_memories_store.py` (new) | With moto-mocked Dynamo: `append_memories` batch-writes N rows with correct PK/SK/created_at; `list_recent_memories` returns newest-first respecting limit; cross-season isolation (memories from SEASON#2025 don't leak into SEASON#2026 query); `clear_season` deletes all rows for a season; appending an empty list is a no-op | Schema + pagination + isolation guards |
| `tests/test_weekly_prompts.py` (new) | Unit-test `prompts.build_system_blocks()` — exactly 3 blocks returned, all `cache_control={"type": "ephemeral"}`, block 1 contains "roast" + the forbidden-topics list, block 2 contains every `display_name`, block 3 contains valid JSON schema example. `build_user_prompt(...)` includes "Week N Matchups" header + every matchup as a row + prior-memories bullet list. `PROMPT_VERSION` is the pinned constant | Catches prompt drift during PR review |
| `tests/test_weekly_orchestrator.py` (new) | With moto + mocked Sleeper + mocked Claude (returns valid JSON envelope): `run("L1", week=4, dry_run=True, force=False)` writes one report row with `period="2026W04"`, appends 3-5 memory rows for season 2026 week 4, dry-run delivers 1 email (admin); non-dry-run delivers 12; mid-run Claude failure raises `ClaudeAPIError` and does NOT persist report or memories; JSON parse failure persists report markdown but skips memory append; idempotent re-run with `force=False` short-circuits before Claude call | End-to-end orchestrator behavior under mocks |
| `tests/test_api_admin_ai_review_weekly_trigger.py` (new) | Mirror F1/F2's trigger-handler tests, plus: `week` override honored when present in body; `week` omitted → resolved from `get_nfl_state` mock; `dry_run` default true; non-admin → 403 | Locks down the manual-trigger handler |
| `tests/test_notif_ai_review_weekly.py` (new) | EventBridge handler tests: `week < 1` → no-op exit; existing report + `force=False` → no-op exit; happy path calls orchestrator once; Claude failure → SNS published + raises | Cron handler behavior |

### `xomper-ios/Xomper/Core/Networking/XomperAPIClient.swift`
| Change | Why |
|--------|-----|
| Extend `XomperAPIClientProtocol` with `func triggerWeeklyAIReview(week: Int?, dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse`. Implement on the concrete class by POSTing to `/admin/ai-review-weekly-trigger` with `{week, dry_run, force}` JSON body (omit `week` from the payload when nil). Reuse the existing `AIReviewTriggerResponse` Decodable — no new response struct | Single new method; same wire shape as F1/F2 |

### `xomper-ios/Xomper/Core/Stores/AdminStore.swift`
| Change | Why |
|--------|-----|
| Add Weekly state mirroring the Preseason state. New properties: `private(set) var weeklyLatest: AIReport?`, `private(set) var isTriggeringWeekly = false`, `private(set) var weeklyError: Error?`, `private(set) var weeklyResult: AIReviewTriggerResponse?`, `var weeklyDryRun: Bool = true`, `var weeklyWeekOverride: Int? = nil`. New methods: `func loadWeeklyLatest() async` (silent on failure); `func triggerWeekly(week: Int?, dryRun: Bool, force: Bool) async throws -> AIReviewTriggerResponse` (mirrors `triggerPreseason` — sets `isTriggeringWeekly`, calls `apiClient.triggerWeeklyAIReview(...)`, refreshes `weeklyLatest` on success) | Third trigger flow |

### `xomper-ios/Xomper/Features/Admin/AdminView.swift`
| Change | Why |
|--------|-----|
| In `content`, insert a new `weeklyTriggerCard` directly below `preseasonTriggerCard`. Add `weeklyTriggerCard` computed view + supporting helpers (`weeklyStatusLine`, `weeklyPrimaryButtonLabel`, `weeklyResultLine`, `triggerWeekly(force:)`) as structural copies of the preseason equivalents. UI additions specific to weekly: an optional **week-override stepper** (1...22) gated by a "Override week" toggle below the dry-run toggle — when off, the orchestrator resolves the week from NFL state; when on, the override is passed in. In `.task(id:)` and `.refreshable`, also call `await store.loadWeeklyLatest()` next to the other two | Third trigger card stacked below the first two; identical UX + week-override affordance |

### `xomper-ios/XomperTests/`
| File | Change | Why |
|------|--------|-----|
| `AdminStoreWeeklyTests.swift` (new) OR extension to `AdminStoreTests.swift` | Mirror existing preseason store tests: `loadWeeklyLatest` populates `weeklyLatest` on mocked-200 with a weekly `AIReport`; `triggerWeekly(week: nil, dryRun: true, force: false)` calls the mock client with the correct path + omitted `week` field; `triggerWeekly(week: 5, dryRun: false, force: true)` includes `week=5` in the payload; error path populates `weeklyError`, clears `isTriggeringWeekly`, rethrows | Store unit tests |

### `xomper-ios/project.yml`
| Change | Why |
|--------|-----|
| No edits expected — only `AdminStoreWeeklyTests.swift` is a new file; `xcodegen generate` picks it up automatically | Build inclusion |

---

## Open Design Decisions (resolved)

### 1. New lambda vs. extend `notif_weekly_recap`
**Pick: new sibling lambda `notif_ai_review_weekly`.**

Rationale: the existing weekly recap is a non-AI deterministic-scoring product with its own email body, recipients, and ops profile. F3's AI recap is a separate product that the user has explicitly framed as additive ("alongside the existing recap", per epic). Forking gives independent: schedule (different time of day), deploy cadence, failure isolation (Claude outage doesn't block the score email), feature-flag-ability (disable F3 without touching F0/F1/F2), and metric/log isolation. Cost: roughly +0 — one new lambda + one new cron rule.

### 2. Cron expression
**Pick: `cron(0 14 ? * TUE *)` if existing crons are ET-anchored, OR `cron(0 18 ? * TUE *)` if EventBridge expressions are UTC and existing entries encode ET as `cron(0 13 ? * TUE *)` for 09:00 ET.**

Read `terraform/lambdas_scheduled.tf` at execute-time. The existing `notif_weekly_recap` entry's expression establishes the convention — match it. The user's expressed intent is **Tue 14:00 ET** because:
- Monday Night Football ends ~23:30 ET Monday
- Sleeper's `nfl_state.week` typically increments Tuesday morning (after the league's final stat sync)
- 14:00 ET leaves a 6-hour buffer past `notif_weekly_recap` (09:00 ET) — clear inbox separation, no operational collision
- The `notif_worldcup_movement` cron at 10:00 ET is also clear

If the existing convention is UTC (most likely — AWS EventBridge native interpretation), `cron(0 18 ? * TUE *)` = 18:00 UTC = 14:00 ET (Daylight) / 13:00 ET (Standard). Document the DST drift as acceptable (the recap landing 13:00 vs 14:00 ET across the November DST flip is fine).

### 3. Memory storage location
**Pick: new Dynamo table `xomper-ai-memories`** (Option B from the input questions).

Rationale: F0 deferred memory storage to F3 ("Incremental — lands with F3"). Two viable paths:
- Reuse `xomper-ai-reports` with `report_type="memory"` — cheap but blurs schema (queries on the reports table now have to filter out memories).
- Separate table — clean separation, mirror the existing pattern (`xomper-matchup-history`, `xomper-worldcup-snapshots`, `xomper-notification-log` are all single-purpose tables).

The separate table is **~$0/year** at this volume (12 managers × 22 weeks × 5 memories = ~1,300 items, all under 1KB). Adding a new table is one terraform block. Schema isolation is worth it.

### 4. Memory schema
```python
from dataclasses import dataclass, field
from typing import Literal
import uuid

@dataclass(frozen=True)
class SeasonMemory:
    memory_id: str = field(default_factory=lambda: uuid.uuid4().hex)
    season: int = 2026
    week: int = 0                                       # 1-18 regular, 19-22 playoffs
    manager_user_id: str | None = None                  # Sleeper user_id; None = league-wide
    text: str = ""                                       # one-line, ~120 char target
    sentiment: Literal["roast", "praise", "lore"] = "roast"
    created_at: str = ""                                # ISO 8601 UTC
```

Stored in Dynamo as:
- PK: `LEAGUE#<league_id>#SEASON#<year>`
- SK: `MEMORY#<week:02d>#<memory_id>`
- Attributes: every field above mapped directly

Why season is in the PK (not the SK): so a 2027 season starts as an empty query result without manual purge. The `clear_season` helper exists for explicit reset but isn't called by the cron.

### 5. Memory generation — single-pass vs two-pass
**Pick: single-pass with structured JSON output.**

Claude returns:
```json
{
  "body_markdown": "# Week 4 Roast\n\n## The Headline\n...",
  "new_memories": [
    {
      "text": "Connor benched LeBron James and lost by 0.5",
      "manager_user_id": "865328062403870720",
      "sentiment": "roast"
    },
    {
      "text": "Tony's RB1 went off for 40 — first time he didn't whine since Week 1",
      "manager_user_id": "1127420529155227648",
      "sentiment": "roast"
    },
    {
      "text": "Jim went 5-0 in the first 5 weeks, undefeated in lore",
      "manager_user_id": "866444821185843200",
      "sentiment": "praise"
    }
  ]
}
```

Orchestrator enforces:
- Validate JSON parse; on failure, persist the raw response as markdown body and skip memory append (don't lose the recap)
- Validate each memory has `text` (non-empty, ≤200 chars), `sentiment` ∈ valid set; drop malformed entries with a log warning
- Cap at 5 memories per call (truncate excess)
- Auto-stamp `memory_id`, `season=2026`, `week=N`, `created_at=now()` server-side (don't trust Claude with these)

Single-pass saves a full LLM call (~$0.02 per call × 22 weeks = ~$0.44 saved vs two-pass).

### 6. Idempotency
Mirror F1/F2:
- Period key for week N is `f"2026W{N:02d}"` (e.g. `"2026W04"`)
- On cron + admin both: `ai_reports_store.get_latest(league_id, "weekly")` returns the most recent weekly row
- If its period matches and `force == False` → skip with a log line ("week N already generated"); the cron returns 200 to EventBridge, the admin endpoint returns 409 with the existing report
- `force == True` writes over the row (same SK) and re-appends memories (which means duplicate memory entries — accepted, dedup is not worth the complexity in v1; admin uses force sparingly)

### 7. Week resolution
The cron handler resolves "which week to roast" as:
```python
nfl_state = sleeper_helper.get_nfl_state()      # {"week": int, "season": int, "season_type": str}
# At Tue 14:00 ET, Sleeper has typically already incremented nfl_state.week to the upcoming week
week_to_roast = max(1, nfl_state["week"] - 1)
```
Defensive checks:
- If `season_type != "regular"` and `season_type != "post"` → no-op (skip the cron run; off-season)
- If `nfl_state.season != 2026` → no-op (wrong season, fail safe)
- If `week_to_roast < 1 or week_to_roast > 22` → no-op + log

Admin trigger can override `week` explicitly, bypassing all of these (useful for dry-run calibration against 2025 data via `previous_league_id`).

### 8. Admin trigger endpoint
**Yes, ship it.** `POST /admin/ai-review-weekly-trigger` body:
```json
{
  "week": 4,                        // optional; defaults to resolved current week
  "dry_run": true,                  // default true
  "force": false                    // default false
}
```
Symmetric with F1/F2's trigger contract. The orchestrator is the same function the cron calls — both paths go through it.

### 9. iOS admin card
**Yes, ship it.** Third card stacked below preseason. Same chrome. One UX addition: a week-override stepper (1...22) below the dry-run toggle, gated by an "Override week" toggle that, when off, leaves week resolution to the backend.

### 10. Memory season scoping
PK = `LEAGUE#<id>#SEASON#<year>`. 2027 starts fresh as an empty query; no migration needed. The `clear_season` helper exists for explicit purge but isn't part of the cron path.

### 11. Lookback window
**Pick: last 6 memories by recency** (not "last 6 weeks").

Rationale: a slow week may produce 5 lore-tier memories (e.g. a wild Monday Night Football boatrace); a chill week might produce 1. Capping at "last 6 entries" means the user-prompt memory section is roughly constant in token count regardless of week-to-week chaos. Tunable constant — make it a module-level `MEMORY_LOOKBACK = 6` in `orchestrator.py`.

### 12. Dry-run calibration
Before Week 1 2026 fires, run 2–3 dry-runs against **last year's data** by:
1. Manually invoking `POST /admin/ai-review-weekly-trigger` with `{"week": 4, "dry_run": true, "force": true}` and a code-level toggle that swaps the matchup fetch to `previous_league_id`
2. OR a CLI helper `lambdas/scripts/dry_run_weekly.py` that calls the orchestrator with mocked Sleeper output

**Pick option 1**: cleaner. Add a `use_previous_season: bool = False` orchestrator param (default false) that the admin handler honors when present in the body. The cron never sets it. Document in the dry-run runbook.

### 13. Cost projection
- Per-week generation (cached lore + tone + format spec ~3.5k input, fresh prompt ~1.5k input, output ~3k):
  - Input cached: ~3.5k × $0.08/1M = $0.0003 (90% cache hit)
  - Input fresh: ~1.5k × $0.80/1M = $0.0012
  - Output: ~3k × $4.00/1M = $0.012
  - **~$0.014 per week**
- 18 regular-season weeks + 4 playoff weeks = 22 weeks × $0.014 = **~$0.31**
- Plus 2-3 dry-run calibration cycles × $0.014 = ~$0.05
- **F3 total season cost: ~$0.36**
- Adding F1 + F2 + F3 = well under **$1 for the whole season**, comfortably below the $5/month CloudWatch alarm from F0

---

## Implementation Steps (dependency-ordered, file-by-file)

### Repo 1: `xomper-infrastructure`

- [ ] **Step 1** — Read `terraform/lambdas_scheduled.tf` end-to-end. Confirm the existing `notif_weekly_recap` block's exact shape (cron expression timezone semantics, timeout, memory, role, env vars, log retention). The F3 cron entry will mirror this structure exactly.
- [ ] **Step 2** — Read `terraform/dynamodb.tf` and copy the `aws_dynamodb_table.ai_reports` block as the template for `aws_dynamodb_table.ai_memories`. Append the new resource. Name = `xomper-ai-memories`. No GSI in v1.
- [ ] **Step 3** — In `terraform/lambdas_scheduled.tf`, append the `notif_ai_review_weekly` block. Cron expression: match the `notif_weekly_recap` convention (pin UTC vs ET at read-time) targeting Tue 14:00 ET. Timeout 300s, memory 1024MB.
- [ ] **Step 4** — In `terraform/lambdas_api.tf`, append the `api-admin-ai-review-weekly-trigger` entry to the `api_lambdas` local. Mirror F2's `ai-review-preseason-trigger` entry exactly, swap path + description.
- [ ] **Step 5** — **Verify only** — `iam_lambdas.tf` wildcards already cover the new table + the new lambda's Dynamo R/W + SSM read. Add a one-line code-comment confirming `xomper-ai-memories` is covered. No statement edits expected (F0/F1/F2 all relied on this).
- [ ] **Step 6** — In `terraform/outputs.tf`, expose `ai_memories_table_name` + `ai_memories_table_arn`.
- [ ] **Step 7** — Open infra PR (no issue-number tag per repo convention). Merge → `terraform apply` deploys the table + cron rule + API GW route (stub lambdas return 502 until backend ships).
- [ ] **Step 8** — Post-apply smoke check: `aws dynamodb describe-table --table-name xomper-ai-memories` returns the new table; `aws events list-rules --name-prefix notif_ai_review_weekly` returns the new rule with the pinned cron expression; API GW console shows `/admin/ai-review-weekly-trigger` as a POST route.

### Repo 2: `xomper-back-end` (after Step 7 merged + applied)

- [ ] **Step 9** — Pull F2's `lambdas/api_admin_ai_review_preseason_trigger/` as the structural template for the admin trigger lambda. Pull the existing `lambdas/notif_weekly_recap/` for the cron handler shape (event signature, logging conventions, error handling).
- [ ] **Step 10** — In `lambdas/common/constants.py`, add `AI_MEMORIES_TABLE` and `AI_REVIEW_WEEKLY_PROMPT_VERSION` constants.
- [ ] **Step 11** — In `lambdas/common/errors.py`, add `class MemoryStoreError(XomperError)`.
- [ ] **Step 12** — Create `lambdas/common/ai_memories_store.py` per the schema docstring + three functions (`append_memories`, `list_recent_memories`, `clear_season`) + `SeasonMemory` dataclass.
- [ ] **Step 13** — Verify `lambdas/common/lore_prompt.py` exists with `build_lore_block() -> dict` (F2 should have factored this — if not, factor it on this PR).
- [ ] **Step 14** — Verify `lambdas/common/sleeper_helper.py` exposes `get_nfl_state()`, `get_sleeper_league_matchups(league_id, week)`, `get_sleeper_league_rosters(league_id)`, `get_sleeper_league_users(league_id)`. Add any missing one-line wrappers.
- [ ] **Step 15** — Create `lambdas/notif_ai_review_weekly/__init__.py` (empty).
- [ ] **Step 16** — Create `lambdas/notif_ai_review_weekly/prompts.py` — three system blocks + user-prompt builder + JSON envelope contract. Pin `PROMPT_VERSION`.
- [ ] **Step 17** — Create `lambdas/notif_ai_review_weekly/orchestrator.py` — full pipeline (steps 1–11 from the **Affected Files** orchestrator description). Defensive parse of Claude's JSON response. `use_previous_season: bool = False` param for dry-run calibration.
- [ ] **Step 18** — Create `lambdas/notif_ai_review_weekly/handler.py` — EventBridge entry. Week resolution from `get_nfl_state`. Off-season + already-generated short-circuits. SNS on terminal failure.
- [ ] **Step 19** — Create `lambdas/api_admin_ai_review_weekly_trigger/__init__.py` (empty).
- [ ] **Step 20** — Create `lambdas/api_admin_ai_review_weekly_trigger/handler.py`. Admin gate, body parse, optional `week` + `dry_run` + `force` + `use_previous_season`. Import orchestrator from `notif_ai_review_weekly.orchestrator` (cross-package — verify the build system zips both lambdas with shared root access; if brittle, factor orchestrator into `lambdas/common/weekly_orchestrator.py`).
- [ ] **Step 21** — Create `tests/test_ai_memories_store.py` (moto-mocked, batch-write + read-back + cross-season isolation + empty-append no-op + `clear_season` purge).
- [ ] **Step 22** — Create `tests/test_weekly_prompts.py` (block structure + cache flags + JSON schema example presence).
- [ ] **Step 23** — Create `tests/test_weekly_orchestrator.py` (moto + mocked Sleeper + mocked Claude returning valid JSON; happy path + parse-failure fallback + Claude-failure rollback + idempotent short-circuit).
- [ ] **Step 24** — Create `tests/test_api_admin_ai_review_weekly_trigger.py` (auth + body parse + week override + idempotency, mirroring F1/F2 trigger tests).
- [ ] **Step 25** — Create `tests/test_notif_ai_review_weekly.py` (cron handler — off-season no-op, already-generated short-circuit, happy path, SNS on failure).
- [ ] **Step 26** — Run `pytest tests/` — all green, including F0/F1/F2 suites.
- [ ] **Step 27** — Open backend PR. CI picks up the two new lambda dirs and zips them. On merge, `deploy-backend.yml` deploys both over the infra stubs.
- [ ] **Step 28** — Smoke-test post-deploy with a dry-run against 2025 data:
  ```bash
  curl -X POST -H "Authorization: Bearer <admin-jwt>" -H "Content-Type: application/json" \
    -d '{"week": 4, "dry_run": true, "force": true, "use_previous_season": true}' \
    $API/admin/ai-review-weekly-trigger
  ```
  Expect 200 with `AIReviewTriggerResponse`. Dry-run email lands in admin inbox. Dynamo row written at PK `LEAGUE#<id>` / SK `REPORT#weekly#2026W04`. 3–5 memory rows written at PK `LEAGUE#<id>#SEASON#2026` / SK `MEMORY#04#<uuid>`.

### Repo 3: `xomper-ios` (after Step 28 verified)

- [ ] **Step 29** — Edit `Xomper/Core/Networking/XomperAPIClient.swift`. Add `triggerWeeklyAIReview(week:dryRun:force:)` to the protocol + concrete impl, mirroring `triggerPreseasonAIReview` and POSTing to `/admin/ai-review-weekly-trigger`. Omit `week` from JSON when nil.
- [ ] **Step 30** — Edit `Xomper/Core/Stores/AdminStore.swift`. Add the six weekly state vars + two methods inside a `// MARK: - Weekly AI Review` block directly below the preseason block.
- [ ] **Step 31** — Edit `Xomper/Features/Admin/AdminView.swift`. Add `weeklyTriggerCard` computed view + four helpers, structural copy of `preseasonTriggerCard`. Add the week-override stepper + toggle below the dry-run toggle. Insert into `content`'s `VStack` directly below `preseasonTriggerCard`. Add `await store.loadWeeklyLatest()` next to the other two `.task(id:)` + `.refreshable` calls.
- [ ] **Step 32** — Add `XomperTests/AdminStoreWeeklyTests.swift` with the four cases enumerated.
- [ ] **Step 33** — Run `xcodegen generate` (only `AdminStoreWeeklyTests.swift` is new).
- [ ] **Step 34** — Build via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Xomper -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`. Run `XomperTests` — all green.
- [ ] **Step 35** — Manual QA on simulator: AdminView shows three cards stacked (Post-Draft, Preseason, Weekly). Weekly card has the week-override stepper hidden behind a toggle. Fire dry-run → spinner → success line + email lands. Force a Week 4 run with override → row appears in AI Review archive with `period = "2026W04"` and `displayName = "Weekly"`. Home banner picks up the new latest report.
- [ ] **Step 36** — Open iOS PR. Three coordinated PRs merged in order (infra → backend → iOS).

### Post-merge (F3 follow-ups, separate PRs / not blocking F3 merge)

- [ ] **Follow-up 1** — Schedule 2 more dry-runs against 2025 weeks 8 + 14 to validate tone across mid-season + late-season variance.
- [ ] **Follow-up 2** — Before Week 1 2026 (early September), schedule a final dry-run against 2025 Week 17 as the live calibration check. Tone-review with a second human if available.
- [ ] **Follow-up 3** — Document the dry-run + force + use_previous_season runbook in `docs/runbooks/ai-review-weekly.md` (separate PR after F3 ships).

---

## Test Plan

### Backend (pytest)
- `test_ai_memories_store.py`:
  - `append_memories(league, season=2026, week=4, [m1,m2,m3])` creates 3 rows; each row has PK `LEAGUE#<id>#SEASON#2026`, SK `MEMORY#04#<uuid>`, all attributes present
  - `list_recent_memories(league, 2026, limit=6)` returns at most 6 rows in newest-first order
  - `list_recent_memories(league, 2025)` returns `[]` if only 2026 rows exist (cross-season isolation)
  - `append_memories(..., [])` is a no-op (does not call BatchWriteItem)
  - `clear_season(league, 2026)` deletes all 2026 rows; 2025 rows remain
- `test_weekly_prompts.py`:
  - `build_system_blocks()` returns exactly 3 blocks, all `cache_control={"type": "ephemeral"}`
  - Block 1 contains "roast", "matchup", and every forbidden topic name
  - Block 2 contains every `display_name` from `LEAGUE_LORE`
  - Block 3 contains "new_memories", "body_markdown", and a valid JSON schema example
  - `build_user_prompt(week=4, matchups=[...], prior_memories=[...])` includes "Week 4 Matchups" header + every matchup row + prior memories as bullets
- `test_weekly_orchestrator.py` (moto + mocked Sleeper + mocked Claude):
  - Happy path: `run("L1", week=4, dry_run=True, force=False)` writes 1 report row + 3-5 memory rows; dry-run sends 1 email
  - Non-dry-run: sends 12 emails
  - Claude JSON parse failure: report markdown persisted (whole response as body), memory append skipped (0 memory rows added); a warning logged
  - Claude API failure: `ClaudeAPIError` raised; NO report row, NO memory rows written (transactional)
  - Idempotent re-run with `force=False` and existing same-period row: orchestrator short-circuits before Claude call (mock asserts not-called)
  - Idempotent re-run with `force=True`: orchestrator runs again, overwrites Dynamo row (same SK), appends new memories (accepted duplication)
  - `use_previous_season=True` swaps the matchup fetch to `previous_league_id` (mock asserts)
- `test_api_admin_ai_review_weekly_trigger.py`:
  - Non-admin → 403
  - Admin + `week` omitted → handler resolves via mocked `get_nfl_state`
  - Admin + `week=5` explicit → handler honors override
  - Admin + `dry_run` omitted → defaults to true
  - Admin + existing report + `force=false` → 409 with existing report
  - Admin + existing report + `force=true` → orchestrator called, new response
  - Malformed JSON body → 400
- `test_notif_ai_review_weekly.py`:
  - Event with `week` payload → handler honors override
  - Event without `week` → resolves from `get_nfl_state`
  - `season_type=="offseason"` → no-op return, no orchestrator call
  - `nfl_state.week==1` → `week_to_roast=0` clamped to 1 (edge case — Week 1 Tuesday morning before any games)
  - Existing report + `force=False` → no-op exit 0
  - Orchestrator raises `ClaudeAPIError` → handler publishes SNS to admin topic + re-raises

### iOS (XCTest)
- `AdminStoreWeeklyTests`:
  - `loadWeeklyLatest()` populates `weeklyLatest` on mocked-200 with a weekly `AIReport`
  - `loadWeeklyLatest()` silently nils on mocked-error
  - `triggerWeekly(week: nil, dryRun: true, force: false)` calls the mock client with path `/admin/ai-review-weekly-trigger` and body **without** the `week` field
  - `triggerWeekly(week: 5, dryRun: false, force: true)` body includes `week=5`, `dry_run=false`, `force=true`
  - Error path populates `weeklyError`, clears `isTriggeringWeekly`, rethrows

### Smoke (post-deploy)
- 2025-data dry-run via admin endpoint with `use_previous_season=true` returns 200, dry-run email lands at admin inbox with a roast of 2025 Week 4
- Dynamo row written at PK `LEAGUE#<id>` / SK `REPORT#weekly#2026W04`; 3-5 memory rows at PK `LEAGUE#<id>#SEASON#2026` / SK `MEMORY#04#<uuid>`
- Re-running the same call with `force=False` returns 409 with the existing report
- iOS AdminView shows three trigger cards stacked; tapping Weekly + week override 4 + dry-run + force → matches the backend smoke
- iOS `AIReviewView` archive lists the new weekly row at the top with `displayName = "Weekly"` and `period = "2026W04"`
- `AIReviewHomeCard` on Home picks up the new weekly report
- Cron rule is armed in EventBridge with the pinned expression; first scheduled fire is the upcoming Tuesday afternoon
- CloudWatch alarm from F0 reads $0 spend after 24h (no real season data yet, only dry-runs)

---

## Out of Scope
- Touching the existing `notif_weekly_recap` lambda (deterministic scoring email stays unchanged)
- F1 / F2 regressions (only touch shared modules if F3 genuinely needs a factoring)
- Memory deduplication on `force=True` reruns (accepted duplication; admin uses force sparingly)
- A "send now" / "regenerate just my section" admin action beyond the dry-run + force flags (Phase 4)
- Live NFL news ingestion via Anthropic `web_search` or RSS sidecar (Phase 4)
- Per-manager personalized recap body (already settled in epic Q4 — hybrid shared body + per-user header)
- Player name resolution from `/players/nfl` (v1.1 if dry-runs reveal player-ID degradation in the recap)
- iOS read-state badges (Phase 4)
- Mid-season prompt-version migration tooling (admin manually opens a PR to bump the version; cache invalidates naturally)
- Sleeper trending players API ingestion (defer to a v1.1 if dry-runs reveal Claude needs more "who's hot" context)
- A xomware.com / web hub surface for weekly reports (Phase 5; reports remain Dynamo-bound + iOS-rendered in v1)
- Auto-mining of specific event types ("biggest blowout of the week", "lineup-not-set loss") as separate memory categories — Claude infers these naturally from the matchup data + JSON envelope contract; no separate code path

---

## Risks / Tradeoffs
- **Highest tone risk of the epic** — Claude is roasting real outcomes against real lore. Mitigation: strictest system block 1 in the epic, 2-3 mandatory dry-runs against 2025 data before Week 1 fires, all 3 dry-runs reviewed by user before broadcast toggle
- **Cron timezone drift across DST** — `cron(0 18 ? * TUE *)` UTC = 14:00 ET DST / 13:00 ET Standard. The November DST flip means recaps arrive an hour earlier in standard time. Accepted; documented; alternative would be two crons swapped at DST boundaries (overkill)
- **`nfl_state.week` increment timing** — Sleeper's API increments week on an undocumented schedule; if it's still pre-incremented at Tue 14:00 ET, the orchestrator roasts the wrong week. Mitigation: log the resolved `week_to_roast` + `nfl_state.week` on every cron run for the first 2-3 weeks; flip to explicit week override in EventBridge input if drift is detected
- **JSON envelope parse failures** — Claude occasionally drifts from JSON output even with explicit schema in the prompt. Mitigation: prompts.py block 3 gives a worked example; orchestrator falls back to "treat entire response as markdown, skip memory append" rather than failing the whole run
- **Memory pollution from `force=True` reruns** — admin re-running a week creates duplicate memories. Accepted in v1 (admin uses force sparingly; duplicates are funny-looking but not harmful). Future: dedupe by (week, manager_user_id, text)
- **Cross-package import for orchestrator** — admin trigger imports from `notif_ai_review_weekly.orchestrator`. May fail if the build script zips lambdas in isolated dirs. Mitigation: confirm at execute-time by reading the deploy script; fallback is to factor orchestrator into `lambdas/common/weekly_orchestrator.py`
- **GSI not added to memories table** — query is always PK + SK begins_with, so no GSI needed. If a "by manager" query becomes a thing in v1.1, add a GSI then; defer the cost
- **No new IAM** — F0 wildcards cover the new table + lambdas. **Verify during step 5** — if F0 pinned per-lambda statements (not wildcards), F3 needs IAM additions
- **Claude API outage on Tuesday** — handler raises after retries; SNS publishes "report delayed" to admin topic. Idempotent re-run on Wednesday via admin trigger with `dry_run=false, force=false` recovers cleanly
- **Memory drift over season** — by Week 17, the last-6 memories are a small slice of the season's actual lore. Accepted in v1 (lookback cap protects token cost); future v1.1 could pre-rank memories by sentiment intensity rather than recency
- **Hot partition on the memories table** — single PK `LEAGUE#<id>#SEASON#2026` carries all writes for the season. At 22 weeks × 5 writes = 110 writes/season, no heat. Non-issue
- **Prompt drift from F1/F2** — system block 1 is weekly-tuned (strictest of the three). Risk that F3 feels off-voice. Mitigation: dry-run mandatory; user can compare across F1/F2/F3 outputs side-by-side before broadcast
- **EventBridge silent failure** — if the cron rule mis-fires, no one notices until Wednesday. Mitigation: CloudWatch alarm on the lambda invocation count (0 invocations/week between September and December = alarm)

---

## Open Questions
- [ ] Confirm the exact UTC offset convention in `terraform/lambdas_scheduled.tf` at execute-time (existing `notif_weekly_recap` cron sets the precedent — match it)
- [ ] Confirm whether F2 actually factored `lore_prompt.build_lore_block()` into `lambdas/common/` — if not, F3 does the factoring on this PR
- [ ] Confirm whether the admin trigger lambda can cross-import from `notif_ai_review_weekly.orchestrator` (read the deploy script); fallback is to factor into `lambdas/common/weekly_orchestrator.py`
- [ ] Decide whether to add a CloudWatch alarm on "0 invocations of `notif_ai_review_weekly` between Tue 14:00 ET and Tue 18:00 ET" during the season — F4 polish or F3 nice-to-have? Default: defer to F4
- [ ] Decide whether the Home banner deserves a "new this week" badge once weeklies start landing — defer to F4 (read-state work)
- [ ] Confirm at dry-run time whether to bump `max_tokens` from 6000 to 8000 if Claude truncates with 12 manager sections + 5 memories — wait until first dry-run output is reviewed

---

## Acceptance Checklist — F3 Done When
- [ ] Infra PR merged + `terraform apply` clean: `xomper-ai-memories` table exists with KMS + PITR; EventBridge rule `notif_ai_review_weekly` armed with the pinned cron expression; `/admin/ai-review-weekly-trigger` route returns 200 with admin JWT, 401 without
- [ ] Backend PR merged + deployed: `lambdas/notif_ai_review_weekly/` ships; `lambdas/api_admin_ai_review_weekly_trigger/` ships; `lambdas/common/ai_memories_store.py` ships
- [ ] Admin dry-run cycle against 2025 Week 4 succeeds: 200 response, dry-run email renders correctly, Dynamo report row + 3-5 memory rows written
- [ ] Admin force-rerun against same week succeeds (overwrites report, appends new memories)
- [ ] Idempotency check: `force=False` against the same period returns 409 with the existing report
- [ ] iOS PR merged: AdminView shows three trigger cards stacked (Post-Draft + Preseason + Weekly); Weekly card has the week-override stepper + toggle
- [ ] iOS dry-run via Weekly card fires end-to-end; updates status line; report appears in `AIReviewView` archive with `displayName = "Weekly"` and `period = "2026W04"`
- [ ] Home banner picks up the new weekly report if it's the most recent across all types
- [ ] Pagination on `AIReviewView` performs at 20+ rows (verified manually by force-generating across multiple periods during dry-run calibration)
- [ ] All backend pytest + iOS XCTest suites green; no regressions on F0/F1/F2
- [ ] Cost: total Anthropic spend for the full F3 calibration cycle (3 dry-runs + 1 force) < $0.20; full season projection (via metadata token usage × 22) < $1
- [ ] CloudWatch logs from the first real cron fire (Week 1 2026, ~September) show successful end-to-end run with 1 report row + 3-5 memory rows persisted and 12 emails delivered
- [ ] Three PRs merged in order: infra → backend → iOS (none reference issue numbers per repo conventions)

---

## Skills / Agents to Use
- **execute agent** — drives this plan to merged PRs once status flips to Ready
- **research agent** — invoke only if the Anthropic SDK's structured-output API (`response_format`) has changed since F2 or if the cron timezone semantics in EventBridge are ambiguous after reading `lambdas_scheduled.tf`
- **brainstorm agent** — not needed; F3's open questions are mechanical, not design-level

---

## Appendix A: Memory module quick-reference

```python
# lambdas/common/ai_memories_store.py — public surface
def append_memories(league_id: str, season: int, week: int, memories: list[SeasonMemory]) -> list[dict]: ...
def list_recent_memories(league_id: str, season: int, limit: int = 6) -> list[SeasonMemory]: ...
def clear_season(league_id: str, season: int) -> int: ...  # admin-only, not called by cron
```

Schema doc lives at the top of the file. Dataclass enforces type via `@dataclass(frozen=True)`.

## Appendix B: Claude JSON envelope contract

System block 3 (cached) tells Claude to respond ONLY with this JSON shape:

```json
{
  "body_markdown": "# Week N Roast\n\n## Headline\n...full markdown recap...",
  "new_memories": [
    {
      "text": "<one-line memory under 200 chars>",
      "manager_user_id": "<sleeper_user_id or null for league-wide>",
      "sentiment": "roast" | "praise" | "lore"
    }
  ]
}
```

Orchestrator parse rules:
- `json.loads` the response; on `JSONDecodeError`, persist the raw response as `body_markdown`, append zero memories, log a warning
- Validate `body_markdown` is a non-empty string; if missing, fail loudly (raise)
- Validate `new_memories` is a list (default `[]` if missing); cap at 5; drop entries failing schema validation
- Auto-stamp `memory_id`, `season`, `week`, `created_at` server-side

## Appendix C: Dry-run runbook (executes in Follow-up 3)

1. Admin opens iOS AdminView → Weekly card
2. Toggle "Override week" ON, set stepper to a 2025 week (e.g. 4)
3. Toggle "Dry run" ON (default)
4. (Optional, not exposed in UI v1) — admin uses curl with `use_previous_season=true` to roast 2025 data; v1 UI does not expose this flag, so the curl path is the calibration path
5. Tap Generate
6. Open admin email inbox → review the rendered recap
7. Tone passes → toggle Dry run OFF, force ON, regenerate to broadcast
8. Tone fails → open backend PR adjusting `prompts.py` block 1, redeploy, retry
