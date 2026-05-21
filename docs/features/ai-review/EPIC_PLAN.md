# Epic Plan: AI Review (Issue #79)

**Status**: Ready
**Created**: 2026-05-21
**Last updated**: 2026-05-21
**Issue**: https://github.com/Xomware/xomper-ios/issues/79
**Brainstorm**: `docs/features/ai-review/BRAINSTORM.md`

---

## Orchestration

Four sub-feature stubs (Draft) sequenced strictly by phase dependency. Each must be fleshed out via `/plan [stub]` and flipped to Ready before `/execute`.

```
F0 — Shared Infra (Phase 0)         docs/features/ai-review/f0-shared-infra/PLAN.md
  │  cross-cutting pre-req: Dynamo table, SSM key, IAM, billing alarm,
  │  common modules, read API lambdas, iOS shared surfaces
  ▼
F1 — Post-Draft Analysis (Phase 1)  docs/features/ai-review/f1-post-draft/PLAN.md
  │  one-shot lambda + prompt + admin trigger, dry-run first
  ▼
F2 — Preseason Blast (Phase 2)      docs/features/ai-review/f2-preseason/PLAN.md
  │  one-shot lambda + prompt + admin trigger (reuses F1 scaffolding)
  ▼
F3 — Weekly Recap (Phase 3)         docs/features/ai-review/f3-weekly/PLAN.md
     cron lambda + season-memory table + memory loop, iOS archive pagination
```

Strict sequential order — no parallelization. F0 unblocks all three; F1 calibrates tone and establishes the dry-run + email pattern that F2 and F3 reuse; F3's volume + personalization risk is highest so it goes last after two one-shots have validated voice.

---

## Epic Overview

AI Review is a content-generation pipeline that turns Sleeper league data + a hand-authored "lore" pack into three personality-driven, Claude-written reports (post-draft, preseason, weekly) delivered through two surfaces: a league-wide email + an in-app archive in `xomper-ios`. The three sub-features share the same scaffolding — Claude API helper, DynamoDB report store, lore module, SSM key, email chrome, iOS surfaces — and differ only in trigger cadence, prompt skeleton, and data inputs. Ship order is post-draft → preseason → weekly so we calibrate tone on low-stakes one-shots before tackling the volume + personalization of the weekly recap.

Architectural decisions are fixed by the brainstorm (Q1–Q8). This plan exists to scaffold the work into a shape `/orchestrate` can split into per-feature plans.

---

## Sub-Feature Breakdown

### F1 — Post-Draft Analysis (ships first)
- **Scope**: One-shot Claude-generated team-by-team grade + outlook report fired after the rookie draft. Admin-triggered (button or one-time cron). Writes to `xomper_ai_reports`, emails the league, surfaces in iOS Home + tray.
- **Repos touched**: `xomper-back-end` (new `notif_ai_review_postdraft` lambda + prompt skeleton), `xomper-infrastructure` (admin-trigger wiring; reuses the shared infra from Phase 0), `xomper-ios` (consumes existing shared surfaces; type-specific labels).
- **Primary deliverables**:
  - `lambdas/notif_ai_review_postdraft/handler.py` — fetches draft picks via Sleeper, builds prompt with lore, calls Claude, persists report, sends email + teaser push.
  - Prompt skeleton in `lambdas/notif_ai_review_postdraft/prompt.py` (or `prompts/postdraft.md`).
  - Dry-run mode flag (admin-only delivery on first invocation).
  - iOS report type label `.postDraft` rendered in archive list.
- **Depends on**: Phase 0 (shared infra) must be merged + deployed.
- **Effort tier**: **M** — first end-to-end run through the new pipeline; tone calibration consumes more time than code.

### F2 — Preseason Blast
- **Scope**: One-shot Claude-generated "last year's grade + this year's outlook" per team. Admin-triggered before Week 1 kickoff. Structurally identical to F1, different prompt + data inputs (prior-season standings + offseason moves).
- **Repos touched**: `xomper-back-end` (new `notif_ai_review_preseason` lambda + prompt), `xomper-ios` (type label only).
- **Primary deliverables**:
  - `lambdas/notif_ai_review_preseason/handler.py` — fetches prior-season final standings + current roster snapshot, builds prompt, generates + persists + sends.
  - Prompt skeleton tuned for "year over year" tone.
  - iOS report type label `.preseason`.
- **Depends on**: F1 — reuses the prompt scaffolding, dry-run pattern, and email template established there.
- **Effort tier**: **S** — mostly a remix of F1 with different data sources.

### F3 — Weekly Recap
- **Scope**: Cron-triggered (Tue/Wed AM during the season) Claude-generated league newsletter that roasts every manager by name using matchup results + season memories + lore. Auto-appends new memories to the season-memory store for next week's prompt.
- **Repos touched**: `xomper-back-end` (new `notif_ai_review_weekly` lambda, season-memory Dynamo helpers), `xomper-infrastructure` (weekly cron trigger; optional new `xomper_ai_memories` table if not already provisioned in Phase 0), `xomper-ios` (paginated archive list once we accumulate 18+ weeks).
- **Primary deliverables**:
  - `lambdas/notif_ai_review_weekly/handler.py` — pulls matchup results + last N memories + lore, generates + persists report + appends new memories, sends.
  - Season-memory store helpers (read last N entries, append new ones).
  - Weekly cron entry in `lambdas_scheduled.tf`.
  - Prompt skeleton with stronger tone anchors + block-list guard.
- **Depends on**: F1 (pipeline), F2 (tone validation), and optionally an extension to Phase 0 if season memories ship as a separate table.
- **Effort tier**: **L** — highest-volume, most personalization-heavy, tone risk is highest, season-memory loop is genuinely new work.

---

## Cross-Cutting Work

These are shared across F1/F2/F3. Decision on each: **pre-req** (must land before any sub-feature) vs **incremental** (lands with the first sub-feature that needs it).

| Item | Type | Lands in |
|------|------|----------|
| `lambdas/common/league_lore.py` — 12 manager profiles | **Pre-req** | Phase 0 |
| `lambdas/common/claude_helper.py` — Anthropic API wrapper | **Pre-req** | Phase 0 |
| `lambdas/common/ai_reports_store.py` — Dynamo R/W for `xomper_ai_reports` | **Pre-req** | Phase 0 |
| Terraform: `xomper_ai_reports` DynamoDB table | **Pre-req** | Phase 0 |
| Terraform: `/xomper/api/ANTHROPIC_API_KEY` SSM SecureString | **Pre-req** | Phase 0 |
| Terraform: IAM grants (Dynamo R/W + SSM read) on a shared lambda role or per-lambda | **Pre-req** | Phase 0 |
| Terraform: CloudWatch billing alarm ($5/month) | **Pre-req** | Phase 0 |
| `lambdas/common/email_templates/ai_review.py` — markdown→HTML chrome | **Pre-req** | Phase 0 |
| `lambdas/api_ai_reports_latest/handler.py` + `lambdas/api_ai_reports_list/handler.py` | **Pre-req** | Phase 0 (so iOS can ship against a real endpoint) |
| iOS `AIReviewStore` + `XomperAPIClient` methods + response models | **Pre-req** | Phase 0 |
| iOS `AIReviewView` (archive list) + `AIReviewDetailView` (markdown renderer) | **Pre-req** | Phase 0 |
| iOS `TrayDestination.aiReview` case | **Pre-req** | Phase 0 |
| iOS Home banner card for latest report | **Pre-req** | Phase 0 |
| Per-user subject + greeting templating (hybrid email) | **Pre-req** | Phase 0 (used by all three) |
| Season-memory store (`xomper_ai_memories` table + helpers) | **Incremental** | Lands with F3 (weekly is the only consumer) |
| Push notification teaser copy template | **Incremental** | Lands with F1, parameterized by report type |
| Admin "regenerate" / "send now" actions | **Deferred** | Phase 4 (v1.1) |

---

## Recommended Orchestration Order

`/orchestrate` should produce these stubs under `docs/features/ai-review/`:

- **Phase 0 — `f0-shared-infra/PLAN.md`**: lore module, claude_helper, Dynamo table + SSM key + IAM + billing alarm, email-template foundation, API endpoints, iOS shared surfaces (store, views, tray destination, Home banner). Ship as one PR per repo (3 PRs total). No sub-feature can start until this lands.
- **Phase 1 — `f1-post-draft/PLAN.md`**: post-draft lambda + prompt + admin trigger + iOS label. End-to-end smoke test against 2025 draft data, dry-run to admin only first.
- **Phase 2 — `f2-preseason/PLAN.md`**: preseason lambda + prompt + admin trigger + iOS label. Reuses F1 scaffolding; pure data + tone swap.
- **Phase 3 — `f3-weekly/PLAN.md`**: weekly lambda + cron + season-memory table & helpers + prompt with block-list + iOS archive pagination.
- **Phase 4 — deferred (no plan stubs yet)**: live NFL news ingestion (Anthropic `web_search` or RSS sidecar), admin portal regenerate/send-now actions, iOS read-state badges, lore-growth automation beyond season memories.

---

## Cross-Repo Dependencies

For every sub-feature, the repo-level merge + deploy order is:

1. **`xomper-infrastructure`** — terraform must apply first to create any new Dynamo table, SSM param, IAM grants, cron rule, or API GW route.
2. **`xomper-back-end`** — lambda code can only ship once the infra it depends on (table, SSM key, IAM role) exists.
3. **`xomper-ios`** — client can only ship once the API endpoint returns real data.

Per-phase ordering:

- **Phase 0**: infra (Dynamo + SSM + IAM + billing alarm + API GW routes) → backend (claude_helper, lore module, store helpers, email template, two API lambdas) → iOS (store + views + tray + Home banner against the new endpoints, will return empty list until F1 runs).
- **Phase 1 (F1)**: backend-only change (admin-triggered lambda); no new infra if Phase 0 provisioned the IAM + role; iOS already renders any report type generically — only adds the `.postDraft` label.
- **Phase 2 (F2)**: same shape as F1, backend-only.
- **Phase 3 (F3)**: infra (weekly cron rule + optional `xomper_ai_memories` table + IAM) → backend (weekly lambda + memory helpers) → iOS (archive pagination if needed).

---

## Rollout Risks (Epic Level)

| Risk | Mitigation |
|------|-----------|
| Claude API outage on cron day | Lambda retries with exponential backoff; on terminal failure, send a "report delayed" SNS to admin instead of silently dropping. Dynamo upsert is idempotent so re-runs are safe. |
| Prompt drift over time (tone gets stale or generic) | Pin prompt skeleton as a versioned constant; store `prompt_version` on each Dynamo report row; require a tone review on any prompt change PR. |
| Tone calibration off (too mean / too tame) | Dry-run mode mandatory on first invocation of each new prompt version — admin-only email before broadcast. Block-list of forbidden topics enforced in system prompt. |
| Lore staleness (engagements, marriages, new jobs change) | Lore module is a PR-reviewed Python file — easy to update; season-memory table (F3) auto-grows in-season; defer a runtime lore editor to v1.1. |
| Cost runaway from bug (e.g. infinite retry loop) | CloudWatch billing alarm at $5/month; lambda timeout capped at 5 min; Anthropic SDK retries capped at 3. |
| Sensitive personal data in lore module leaking via repo | `league_lore.py` lives in the private `xomper-back-end` repo; PR review required; no PII beyond what league members have publicly shared in group chat. |

---

## Acceptance Criteria (Epic "Done")

- [ ] All three reports (post-draft, preseason, weekly) generate end-to-end on their target trigger (admin-button for F1/F2, cron for F3).
- [ ] Each report type has been dry-run reviewed by at least one human (admin) before its first broadcast.
- [ ] Reports archive correctly in `xomper_ai_reports` and render in iOS via both Home banner (latest) and tray archive (history).
- [ ] Hybrid email shape works: one shared body + per-user subject + per-user greeting line for all 12 managers.
- [ ] Push notification teaser fires alongside email.
- [ ] CloudWatch billing alarm armed at $5/month against Anthropic spend.
- [ ] Total season cost under $5 (target under $1) as measured at end of 2026 regular season.
- [ ] No prompt-injection / block-list violations in any shipped report (verified by admin review log).

---

## Open Questions (Punted to Sub-Feature Plans)

Each per-feature `PLAN.md` from `/orchestrate` must resolve the items relevant to its phase. Listing them here so nothing gets lost.

**Phase 0 (shared infra)**:
- [ ] Exact `xomper_ai_reports` schema — PK shape (`league_id#report_type` composite vs PK+SK with `report_type` in SK), GSI for cross-type "latest" queries?
- [ ] Markdown renderer choice on iOS — Apple `AttributedString(markdown:)` vs `swift-markdown-ui` (tables + headings)?
- [ ] API endpoint shape — `GET /api/ai-reports/latest?type=X` only, or also `GET /api/ai-reports/list?type=X&limit=N`? (Brainstorm leans yes to both.)
- [ ] Lore module exact shape — confirm fields: `display_name`, `real_name`, `nicknames`, `favorite_teams`, `schools`, `life_events`, `stories`.
- [ ] Block-list / safety-rail content (specific forbidden topics).
- [ ] Push teaser copy template + per-report-type variations.

**Phase 1 (F1 post-draft)**:
- [ ] Admin trigger shape — new admin-only API endpoint vs one-time EventBridge rule vs both?
- [ ] Prompt skeleton + tone anchor paragraphs for post-draft.
- [ ] Exact data inputs — full draft pick list, ADP comparisons, pre-draft rankings?

**Phase 2 (F2 preseason)**:
- [ ] Prior-season data source — Sleeper league history endpoint vs Dynamo snapshot from end-of-season?
- [ ] Admin trigger reuses F1's shape (assumed yes — confirm in plan).

**Phase 3 (F3 weekly)**:
- [ ] Exact cron expression (brainstorm suggests Tue 11am ET; confirm against existing scheduled-lambda times).
- [ ] Season-memory table schema if separate from `xomper_ai_reports`.
- [ ] Memory auto-mining rules — which matchup events get auto-appended ("biggest blowout", "lineup-not-set loss", etc.)?
- [ ] iOS archive pagination cutoff (e.g. lazy load after 10 items).
- [ ] Read-state badges — deferred to v1.1 unless tackled here.

---

## Skills / Agents to Use

- **`/orchestrate ai-review`** — once this epic plan flips to Ready, generates the four stub PLAN.md files (Phase 0 + F1 + F2 + F3) for individual planning.
- **`/plan f0-shared-infra`** (etc.) — fills each stub with file-level steps.
- **brainstorm agent** — already used (BRAINSTORM.md). Re-invoke only if Phase 4 (live news, lore editor) gets pulled forward.
- **research agent** — invoke before Phase 0 if `AttributedString(markdown:)` vs `swift-markdown-ui` decision needs concrete evidence; otherwise skip.
- **execute agent** — drives each phase's PLAN.md to merged PRs.
