# Plan: AI Review — F3 Weekly Recap (Phase 3)

**Epic**: `docs/features/ai-review/EPIC_PLAN.md`
**Phase**: 3
**Status**: Draft
**Created**: 2026-05-21
**Depends on**: F0 (shared infra), F1 (pipeline pattern), F2 (tone validation across two one-shots before going volume + personalization)

## Summary
Cron-triggered (Tue/Wed AM during the season) Claude-generated league newsletter that roasts every manager by name using matchup results + season memories + lore. Evolves the existing `notif_weekly_recap` lambda pattern: new `notif_ai_review_weekly` lambda pulls matchup results + last N memories + lore, generates + persists + sends, and auto-appends new memories to a season-memory store for next week's prompt. Introduces the `xomper_ai_memories` table (incremental from Phase 0) + season-memory helpers (read last N, append new). Adds weekly cron entry to `lambdas_scheduled.tf`, stronger tone anchors + block-list guard in the prompt, and iOS archive pagination once we accumulate 18+ weeks. Effort tier: **L** (highest volume, most personalization, tone risk highest, memory loop is genuinely new).

## Repos touched
- `xomper-back-end` (new `lambdas/notif_ai_review_weekly/handler.py`, season-memory Dynamo helpers, weekly prompt skeleton with block-list)
- `xomper-infrastructure` (weekly cron trigger in `lambdas_scheduled.tf`, new `xomper_ai_memories` table + IAM grants)
- `xomper-ios` (paginated archive list — lazy-load cutoff)

## Open questions to resolve in `/plan`
- [ ] Exact cron expression (brainstorm suggests Tue 11am ET; confirm against existing scheduled-lambda times — after `notif_weekly_recap` 9am and `notif_worldcup_movement` 10am).
- [ ] Season-memory table schema if separate from `xomper_ai_reports` (PK = `sleeper_user_id`, SK = `week_key`? Or `league_id` PK with appended memory list?).
- [ ] Memory auto-mining rules — which matchup events get auto-appended ("biggest blowout", "lineup-not-set loss", closest squeaker, manager-of-the-week, etc.)?
- [ ] iOS archive pagination cutoff (e.g. lazy load after 10 items).
- [ ] Read-state badges — deferred to v1.1 unless tackled here.
- [ ] Block-list content — specific forbidden topics for weekly (more aggressive tone = more risk).
- [ ] Relationship to existing `notif_weekly_recap` — sibling lambda or replacement?

<!-- /plan f3-weekly to fill in scope, architecture, file-by-file steps, test plan -->
