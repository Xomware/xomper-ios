# Plan: Admin Portal — F5 CloudWatch Log Viewer

**Epic**: admin-portal
**Sub-feature ID**: F5
**Phase**: Phase 5 — Log Viewer
**Status**: Draft
**Created**: 2026-05-26
**Depends on**: F1 (admin home menu — logs sub-screen plugs into menu from F1)

## Summary
New `api_admin_logs_query` lambda backed by CloudWatch `FilterLogEvents` against an allowlisted set of log groups. Server-side regex redacts emails and `sleeper_user_id` values before return. 60s server-side cache on identical queries; pagination via `next_token`. New IAM role scoped to `logs:FilterLogEvents` against allowlisted ARNs only (separate role — does NOT contaminate other admin lambdas). iOS log tail with log group picker, level filter, search, "Load older" pager, 5s minimum client-side refresh interval.

## Repos Touched
- `xomper-infrastructure` — API GW route `GET /admin/logs/query`; new IAM role with `logs:FilterLogEvents` scoped to allowlisted log group ARNs
- `xomper-back-end` — `lambdas/api_admin_logs_query/`; allowlist enforcement; PII regex redaction; pagination
- `xomper-ios` — "Logs" sub-screen with `Picker`, level filter, search field, "Load older" button

## Open Questions (this sub-feature)
- [ ] Definitive log group allowlist — expected `/aws/lambda/api_admin_ai_review_*`, `/aws/lambda/notif_ai_review_weekly`, `/aws/lambda/notif_*`, `/aws/lambda/email_*`. Need final list at plan time.
- [ ] PII regex coverage — golden-file test over sample log lines (emails + sleeper IDs); any other PII shapes to redact?
- [ ] Cache TTL confirmation (60s server-side, 5s client min refresh).

## TODO
- [ ] Flesh out this stub via `/plan admin-portal/f5-logs` before executing
- [ ] Flip Status to Ready
