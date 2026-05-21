# Brainstorm — Weekly AI Review / Draft Review (Issue #79)

Status: Draft
Date: 2026-05-21
Author: brainstorm agent

---

## Problem (restated)

We want Claude (Haiku) to write three personality-driven, league-aware reports for the Xomper league, each delivered through two surfaces (email-to-every-manager + iOS landing page):

1. **Weekly recap** — runs on cron Tue/Wed AM during the season. Roasts every manager by name using a persistent "lore" pack (favorite teams, schools, embarrassing stories, life events). Mixes matchup results + league-wide notes + light NFL news.
2. **Preseason blast** — one-shot before the season. Team-by-team "last year's grade + this year's outlook," dripping with league in-jokes.
3. **Post-draft analysis** — one-shot after the rookie draft. Team-by-team grade and outlook on each manager's picks.

All three are LLM-generated. The user wants the output to feel mean, funny, personal — not corporate-AI. Lore must persist (and ideally grow over the season).

This is fundamentally a **content-generation pipeline** bolted onto an existing cron + email/push stack — not a model-research project. The infrastructure pattern (EventBridge → scheduled Lambda → SES + SNS + DynamoDB → API GW endpoint for iOS) already exists for `notif_weekly_recap`. The new work is: add Claude API call, persist generated content, add a personalization "lore" store, and surface in iOS.

**This is a multi-repo feature.** It touches:
- `xomper-back-end` — new lambdas + email templates + Claude helper
- `xomper-infrastructure` — new cron triggers, new DynamoDB table, new SSM secret, new API endpoint
- `xomper-ios` — new tray destination + API client + store + view

I'd recommend planning it as an **epic** (one parent stub, three child features — one per report type plus shared infra), not a single feature. See "Shipping order" below.

---

## Phase 1 — Wide exploration

Loose dump of every angle worth considering, no filtering:

- Single mega-lambda that handles all three report types (`notif_ai_review` with a `report_type` event arg)
- Three separate lambdas, one per report type
- One "generator" lambda + one "deliverer" lambda, decoupled via DynamoDB
- Use Bedrock (Anthropic-via-AWS) instead of api.anthropic.com — IAM auth, no key in SSM
- Use direct Anthropic API — cheaper per token, easier to swap models, but key lives in SSM
- Store reports in DynamoDB (per-league + per-period key)
- Store reports in S3 as JSON or Markdown blobs
- Store nothing — fire-and-forget email only
- Pre-generate once globally vs per-manager personalization (1 LLM call vs 12)
- Hybrid: 1 LLM call for league section + 12 cheap LLM calls for per-manager roasts, then template-stitch
- Lore lives in a Python constant in `lambdas/common/league_lore.py` — easy to start, gated behind PR review
- Lore lives in a new DynamoDB table `xomper-league-lore` — editable via admin endpoint without redeploy
- Lore lives in Supabase profiles — already exists, but extending RLS-protected user schema for joke data feels off
- Lore as a hand-authored Markdown file checked into the backend repo, loaded at lambda cold-start — diffable + reviewable + no infra
- Weekly recap auto-appends new "memories" each week (e.g. "Greg blew an 80% win prob") so the lore grows automatically
- Manual lore-update endpoint for the admin portal so the user can drop in real events ("Tony got engaged")
- Push notification is just a teaser ("Your Week 4 roast is in"), email + landing page have the full content
- Personalized email per manager (12 LLM calls) vs one league-wide newsletter (1 LLM call, identical for all)
- Hybrid: shared league newsletter content but a personalized subject line + opening paragraph per manager
- Use Anthropic's web_search tool for live NFL news — gated behind a feature flag, costs more, real injury context
- Skip live NFL news in v1, lean on Sleeper's trending players + matchup numbers + Claude's training-cutoff knowledge
- Pull a free news feed (ESPN RSS, FantasyPros) into a sidecar lambda, pass blurbs into the prompt
- Have Claude output structured JSON (sections, roasts, headlines) so iOS can render it natively styled, not HTML
- Have Claude output Markdown — easy to render both in email (markdown-to-HTML) and iOS (AttributedString)
- Have Claude output HTML for email + plain text for iOS — annoying to keep aligned, rule out
- Store the prompt template itself as a versioned constant in the repo so tone can be tuned in PRs
- Allow the admin portal to override/tune the prompt at runtime (overkill for v1, defer)
- Run a "dry-run" mode where the lambda generates the report and emails it only to the admin for review before broadcasting
- Add a "regenerate" button in the iOS admin portal — fires the lambda manually, useful when the AI writes something flat
- Add a "send now" admin button that pulls the latest stored report and re-emails the league
- Idempotency key on the DynamoDB store: `(league_id, report_type, period_key)` — re-running the cron updates in place, no double-email
- Make the landing page show an archive (Week 1, Week 2, ...) with a tap-to-open detail view, not just the latest
- Inject the latest report card into the Home screen as a "What's New" banner that opens the full read view
- Show only the most recent report (no archive) — simpler, ship faster
- Both — Home banner + tray destination with archive
- Make the post-draft report block-driven so each team's section can be tapped to expand into round-by-round breakdown
- Add a "fan favorite line of the week" social-share screenshot button in iOS
- Add CloudWatch alarms on Claude API spend (per-day token budget cap)
- Use Haiku-3.5 for all three reports (cheapest); reserve Sonnet for explicit "premium roast" mode if cost allows
- Use Sonnet for post-draft (richer analysis), Haiku for weekly + preseason (volume)
- Cache an output sample in DynamoDB so the iOS landing page renders fast even on first load
- Have the lambda write to S3 as static markdown so xomware.com web hub could surface it too (future-proof)
- Build a "season journal" — append per-manager memorable events as JSONL each week, then feed last N entries into the next week's prompt as context
- Manual "block list" — phrases or topics the LLM must never include (legal/safety guard for the very dark jokes the issue body hints at)
- Have the LLM produce two passes: draft → self-critique → final, to squeeze out generic ChatGPT-isms
- Pre-bake five "voice samples" in the prompt — paragraphs that exemplify the tone — to anchor style
- A/B test two prompt voices on Week 1 and let the league vote which one to keep
- Add a small "regenerate just my section" affordance in iOS (rate-limited)
- Defer iOS landing page entirely in v1 — ship email only, add the page in v1.1 once we know the format stabilizes

---

## Phase 2 — Converge

For each architectural question (Q1–Q6), narrow to 2–3 viable options with tradeoffs.

### Q1: Where does the Claude API get called?

#### Option A: Inline in the scheduled lambda
- Same handler does Sleeper fetch → Claude call → SES send.
- One lambda, one trigger, one log group. Reuses existing `notif_weekly_recap` pattern almost identically.
- **Pros**: simplest; matches existing scheduled-lambda template; minimal new infra.
- **Cons**: Claude call latency (5–30s for a long roast × 12 managers) bumps against Lambda 60s timeout — but we can raise to 5min for scheduled lambdas. If Claude API fails mid-loop, partial sends are messy to retry.
- **Best if** the per-run wall clock stays under ~3 minutes and we accept "regenerate all on retry" semantics.

#### Option B: Two lambdas — generator + deliverer, decoupled via DynamoDB
- `notif_ai_review_generate` runs on cron, calls Claude, writes to `xomper-ai-reports` table.
- `notif_ai_review_deliver` runs 10 min later, reads from table, sends email + push.
- iOS reads from the same table via a new GET endpoint.
- **Pros**: retry-friendly (generator can fail independently of delivery); idempotent on the generation side; iOS can read latest report even if delivery hasn't fired yet.
- **Cons**: two lambdas, two crons, more moving parts; possible "report ready but not sent" gap.
- **Best if** we want operational safety + the iOS surface to lead the email by minutes.

#### Option C: Claude on the iOS client
- Ruled out as stated. API key leak + per-user cost + no email surface.

### Q2: Where does the generated report live?

#### Option A: New DynamoDB table `xomper-ai-reports`
- PK = `league_id_report_type` (e.g. `1234567890_weekly`), SK = `period_key` (e.g. `2026-W04`, `2026-preseason`, `2026-draft`).
- Item value = `{ markdown, generated_at, model, prompt_version, sections: [...] }`.
- iOS queries by PK with `ScanIndexForward=false` to get newest first.
- **Pros**: matches existing Dynamo-first persistence pattern in this codebase (matchup_history, worldcup_snapshots, notification_log all follow it); cheap; PITR + KMS already wired in `dynamodb.tf` locals.
- **Cons**: harder to expose to web hub if/when xomware.com wants to render reports too.

#### Option B: S3 markdown blobs
- One markdown file per report at `s3://xomper-ai-reports/<league_id>/<report_type>/<period>.md`, with a `latest.md` symlink object.
- **Pros**: web-friendly; cheap; trivially diffable in console.
- **Cons**: yet another infra surface, IAM, signed URLs for iOS, no native query API like Dynamo. Doesn't match existing patterns.

#### Option C: Don't persist — email only
- Skip the landing page. The issue explicitly asks for both surfaces, so this is a hard no.

### Q3: Where does personalization "lore" live?

#### Option A: Hand-authored Python module `lambdas/common/league_lore.py`
- A dict-of-dicts keyed by `sleeper_user_id`. Reviewed in PR. Loaded at cold-start.
- **Pros**: zero new infra; diffable; one source of truth; can include long strings of stories without DB pain; perfect for "fixed" lore (favorite team, school, life events).
- **Cons**: every lore edit requires a PR + deploy; can't add a memory mid-week without redeploying.

#### Option B: New DynamoDB table `xomper-league-lore`
- PK = `sleeper_user_id`, item value = `{ fixed: {...}, memories: [{week, text, source}] }`.
- Edited via an admin endpoint that the iOS admin portal calls.
- **Pros**: editable without deploy; the "season journal" idea (auto-append memories each week) becomes trivial.
- **Cons**: new table, new endpoints, new iOS admin UI. Heavier for v1.

#### Option C: Hybrid — module for fixed lore, Dynamo for growing memories
- Static "who this person is" stays in `league_lore.py` (PR-reviewable, biographical).
- Growing "what happened this season" lives in a new table that the weekly lambda writes to + reads from.
- **Pros**: each piece of data lives in the right place; static lore stays diffable; dynamic memories don't need a deploy.
- **Cons**: two-source merge inside the prompt builder. Slightly more code but conceptually clean.

### Q4: Email shape — one newsletter or 12 personalized?

#### Option A: One league-wide newsletter, identical for all recipients
- One LLM call, ~5k input + ~3k output tokens. ~$0.005 per send.
- Each manager gets roasted in the body by name, but everyone reads the same email.
- **Pros**: cheapest, simplest, single artifact; matches a real newsletter feel.
- **Cons**: less "personalization magic" — but the issue mostly wants league-wide content that roasts everyone, not one secret email per manager.

#### Option B: 12 personalized emails (one LLM call per manager)
- Each manager's email leads with their own arc, then league section is appended.
- **Pros**: feels exclusive; each manager gets a longer roast of themselves.
- **Cons**: 12 LLM calls per recap; harder to retry; ~$0.04/run; subtle inconsistencies across emails ("Manager A's email says X about Manager B, Manager B's email says Y about Manager B").

#### Option C: Hybrid — one LLM call produces full newsletter, then a thin templated personalized header per manager
- Single LLM call generates the league newsletter body. Personalization is a static "Hey {name}, here's your Week N roast — find yours below" header that links to the manager's anchor in the email.
- **Pros**: one source of truth, cost = 1 call, mild personalization without inconsistency risk.
- **Cons**: less "wow" than Option B.

### Q5: iOS landing page

#### Option A: New tray destination `.aiReview`
- New `TrayDestination` case with archive list + detail view that renders markdown.
- **Pros**: matches existing nav model; archive is a real value-add ("read Week 3 roast again"); doesn't compete with Home screen.
- **Cons**: extra clicks to discover.

#### Option B: Home banner for the latest report
- Inject a "What's New" card on Home that opens the report detail.
- **Pros**: discoverable; users see fresh content immediately.
- **Cons**: pushes other Home content down; only surfaces the latest.

#### Option C: Both
- Home shows latest card (tap → detail); tray destination shows the full archive.
- **Pros**: best UX.
- **Cons**: a bit more work, but the components are shared (one detail view, two entry points).

### Q6: Live NFL news ingestion

#### Option A: Skip live news in v1
- Rely on Sleeper trending players API (free, already in `sleeper_helper`) for "who's hot" and on matchup numbers for "biggest blowout."
- Claude's training data covers most player narratives up to its cutoff.
- **Pros**: ship faster; zero new dependencies; cost stays predictable.
- **Cons**: jokes about injuries / arrests / breaking news will be stale or hallucinated. Need to instruct the prompt to NOT invent news.

#### Option B: Anthropic web_search beta in the prompt
- Add `web_search` tool to the API call. Claude pulls real news mid-generation.
- **Pros**: actually current; matches the issue's "real arrests / injuries / upsets" ask.
- **Cons**: extra cost (~$0.01 per search), more latency, occasional flakiness. Worth doing in v2 once base pipeline works.

#### Option C: Sidecar news-feed lambda
- Pre-fetch ESPN RSS / FantasyPros headlines into a small JSON blob before the recap runs, pass into the prompt.
- **Pros**: predictable cost, the LLM gets curated headlines instead of free-form web access.
- **Cons**: another moving part. Defer.

---

## Phase 3 — Recommendations

| Question | Pick | One-line reason |
|---|---|---|
| Q1 (where Claude runs) | **Option A** (inline scheduled lambda) | Matches `notif_weekly_recap` exactly; with timeout bumped to 5 min and Option C from Q4 (one LLM call) the runtime is well within budget. |
| Q2 (storage) | **Option A** (DynamoDB `xomper-ai-reports`) | Matches existing persistence pattern, easy iOS query, idempotent upsert on re-run. |
| Q3 (lore) | **Option C** (hybrid module + Dynamo memories) | Fixed bio stays diffable in PRs (where the sensitive personal data belongs); season memories grow automatically without a deploy. Start with just Option A in v1, add the Dynamo `memories` table when we get to Weekly. |
| Q4 (email shape) | **Option C** (one LLM call + thin templated header) | Cost-efficient, no cross-email inconsistency, still feels personal in the subject + greeting. |
| Q5 (iOS) | **Option C** (Home banner + tray archive) | Banner drives discovery, tray drives revisit. Shared detail view means it's barely more work than just one. |
| Q6 (news) | **Option A** (skip in v1) | Defer web_search to v2; v1 leans on Sleeper trending + matchup data. Prompt instructs Claude not to invent news. |

### Why this combo holds together

- One scheduled lambda per report type (3 total: `notif_ai_review_weekly`, `notif_ai_review_preseason`, `notif_ai_review_postdraft`) each calling a shared `lambdas/common/claude_helper.py`.
- All three write to the same `xomper-ai-reports` table.
- All three pull fixed lore from `lambdas/common/league_lore.py` (and weekly additionally reads/writes the season-memory table once it exists).
- All three send a single league-wide email via the existing `send_emails_concurrently` (one HTML body, 12 recipients) plus a teaser push.
- iOS adds one new tray destination + one Home banner widget + one new API endpoint (`GET /api/ai-reports/latest?type=weekly|preseason|postdraft`).

### Q7: Shipping order

**Recommend: post-draft first**, then preseason, then weekly. Reasons:

1. **Post-draft** is most time-urgent — July 6 2026 draft is ~6 weeks out. Shipping this first proves the end-to-end pipeline (Claude + Dynamo + email + iOS) with a low-stakes one-shot run.
2. **Preseason** runs once in late August / early September. It's structurally similar to post-draft (one-shot, team-by-team outlook), so most of the lambda + prompt scaffolding is reusable. Low risk, ship next.
3. **Weekly** is the highest-volume, most personalization-heavy, requires the season-memory store and a tighter tone — best done last, after we've calibrated voice on the two one-shots.

Each ships as its own PR / feature plan, but they share the `claude_helper.py` + `xomper-ai-reports` table + `league_lore.py` + new iOS surfaces, so a parent epic doc should declare those shared pieces upfront.

### Q8: Cost analysis (Haiku 3.5 pricing)

- Input: $0.80/1M, Output: $4.00/1M (Haiku 3.5 current rates — sanity-check at plan time).
- Per **weekly recap** (one LLM call, league newsletter):
  - Input ~5k tokens (lore + matchup data + last 3 weeks of memories + prompt) = $0.004
  - Output ~3k tokens (full newsletter) = $0.012
  - **~$0.016 per week**, **~$0.30 per regular season**, **~$0.40 with playoffs**.
- Per **preseason blast**: input ~6k + output ~6k = **~$0.029 once per season**.
- Per **post-draft analysis**: input ~6k + output ~5k = **~$0.025 once per draft**.
- **Total season cost: well under $1.** Even with 10x prompt growth or Sonnet for post-draft, under $5/season.
- Set a CloudWatch billing alarm at $5/month against the Anthropic API integration anyway (alarm only — don't block).
- Block-list / safety guard: keep an explicit list of named topics the prompt forbids (e.g. specific tragedies; this isn't about model refusal — it's about not letting the bot wander into actually mean territory by accident).

---

## Phase 4 — Open questions for `/plan` to nail down

These are loose threads the brainstorm doesn't resolve:

1. **Exact DynamoDB schema for `xomper-ai-reports`** — settle on PK shape (`league_id_report_type` vs `league_id#report_type` vs separate PK+SK with report_type as part of SK) before writing terraform.
2. **Exact prompt skeleton** — system prompt, lore injection format, structured output (Markdown? JSON sections?), tone anchor examples. Worth a dedicated `prompts/` folder in `xomper-back-end`.
3. **API endpoint shape** — `GET /api/ai-reports/latest?type=weekly` returns latest only; do we also want `GET /api/ai-reports/list?type=weekly` for archive? Probably yes, but confirm.
4. **iOS markdown renderer** — use Swift's built-in `AttributedString(markdown:)` or pull in a third-party (e.g. swift-markdown-ui)? Built-in is simpler but doesn't render tables or headings as nicely.
5. **Cron times** — Tue 11am ET seems right for weekly (after `notif_weekly_recap` at 9am, after `notif_worldcup_movement` at 10am). Preseason + post-draft fire via admin button or one-time cron? Probably admin button (more control over timing).
6. **Lore module structure** — confirm shape: `{ sleeper_user_id: { display_name, real_name, nicknames, favorite_teams: {nfl, college, mlb, nba}, schools, life_events: [...], stories: [...] } }`. PR-reviewed.
7. **Block-list / safety rails** — list of topics the prompt must never touch (specific people not in the league, specific tragedies, etc).
8. **Anthropic API key storage** — SSM `SecureString` at `/xomper/api/ANTHROPIC_API_KEY` matches existing convention. Add to `ssm.tf`, grant lambdas read.
9. **Push notification copy** — what does the teaser push say? ("Week 4 roast is live. Tap to find out how badly you got cooked.")
10. **Dry-run / preview mode** — should the first run of each report fire to admin email only? Strongly yes — bake into Phase 1 lambda design.
11. **Lore growth automation** — for weekly, does the lambda auto-mine memories from matchup results ("biggest blowout this week was X") and append them to the season-memory table for next week's prompt? Worth doing in v1.1 of weekly.
12. **iOS read-state** — do we mark reports as "read" per user (badge unread count)? Probably yes but defer to a v1.1 polish pass.

---

## Concrete next steps

1. **Plan as an epic.** Run `/plan ai-review --epic` to produce the parent stub. Sub-features: `ai-review-shared-infra` (claude_helper, lore module, Dynamo table, SSM key, API endpoint, iOS shared views), `ai-review-postdraft`, `ai-review-preseason`, `ai-review-weekly`. Ship in that order.
2. **Lock the lore module first.** Before any lambda code, have the user fill in `lambdas/common/league_lore.py` with the 12 manager profiles from the issue body. This is the irreducible blocker — no AI joke is possible without it.
3. **Spike a one-shot post-draft prototype.** Build the minimal pipeline (Claude call → write to Dynamo → email admin only → render in iOS) end-to-end for the post-draft report. Run it once against the 2025 draft to validate tone before opening it to the league. This becomes the template for the other two.

---

## Repo touch list (for the plan)

**`xomper-back-end`**
- `lambdas/common/claude_helper.py` (new) — wraps Anthropic API calls
- `lambdas/common/league_lore.py` (new) — manager bio dict
- `lambdas/common/ai_reports_store.py` (new) — Dynamo read/write helpers for `xomper-ai-reports`
- `lambdas/common/email_templates/ai_review.py` (new) — wraps markdown → HTML using existing `base.py` chrome
- `lambdas/notif_ai_review_postdraft/handler.py` (new)
- `lambdas/notif_ai_review_preseason/handler.py` (new)
- `lambdas/notif_ai_review_weekly/handler.py` (new)
- `lambdas/api_ai_reports_latest/handler.py` (new)
- `lambdas/api_ai_reports_list/handler.py` (new)

**`xomper-infrastructure`**
- `terraform/dynamodb.tf` — add `xomper-ai-reports` table
- `terraform/ssm.tf` — add `/xomper/api/ANTHROPIC_API_KEY`
- `terraform/lambdas_scheduled.tf` — add 3 cron entries (or 1 + admin-triggered for one-shots)
- `terraform/lambdas_api.tf` — add `ai-reports-latest` and `ai-reports-list` to the `api_lambdas` local
- `terraform/iam_lambdas.tf` — grant lambdas SSM read on the Anthropic key + Dynamo R/W on the new table

**`xomper-ios`**
- `Xomper/Features/Shell/TrayDestination.swift` — add `.aiReview`
- `Xomper/Features/AIReview/` (new dir)
  - `AIReviewView.swift` — archive list
  - `AIReviewDetailView.swift` — markdown renderer
  - `AIReviewStore.swift` — `@Observable` store
- `Xomper/Core/Networking/XomperAPIClient.swift` — add `aiReportsLatest`, `aiReportsList` methods + response models
- `Xomper/Features/Home/` — add latest-report banner card
- (optional v1.1) `Xomper/Features/Admin/` — add "regenerate report" + "send now" admin actions
