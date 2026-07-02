# Draft Recap Structure Rework

**Status:** Draft
**Date:** 2026-07-02
**Owner:** Dom
**Scope:** Backend recap generation (separate API repo) — NOT the iOS client.

## Problem

The post-draft recap renders as a wall of text with no reliable structure.
User feedback: *"no structure, no grades per pick, seems so random."* Two
root causes:

1. **Generation** produces free-form prose. Section breaks, per-team
   groupings, and per-pick grades are inconsistent or absent, so the iOS
   `MarkdownReflow` heuristics have to guess where paragraphs go.
2. **Disconnect from real grades.** The client already computes objective
   per-pick grades (`DraftGradeCalculator` → value-over-expected vs the
   best-available curve, surfaced in `DraftGradesCard`). The AI prose never
   references these numbers, so the narrative and the grades can disagree.

The iOS side has been patched to render `## / ###` headers, `> ` callouts,
and `- ` bullets cleanly (see `StyledMarkdownView` + `MarkdownReflow`). This
spec covers making the **generated content** actually use that structure.

## Target format (what the generator must emit)

Markdown, in this order, using the tokens the client renders:

```
# {Season} Draft Recap

## Round-by-Round
### Round 1 — {one-line theme}
- **{pick} {manager}** — {Player} ({POS}, {NFL}). {1-2 sentence take.} **Grade: {A+..F}**
- ...

## Steals & Reaches
> {The single biggest steal, one sentence.}
- **Steal — {manager}**: {Player} at {pick}. {why}
- **Reach — {manager}**: {Player} at {pick}. {why}

## Team Grades
### {manager} — {overall letter}
- {2-3 bullet summary of their draft: best pick, biggest risk, positional fit}

## Season Awards
- **{Award}** — {manager} ({reason})
```

Rules for the generator:
- **One `- ` bullet per pick / per point.** Never chain picks inside one
  paragraph with inline em-dashes.
- **Every pick line ends with `**Grade: X**`.** Grades must come from the
  structured input (below), not invented.
- Blank line (`\n\n`) between every block. Do not rely on the client to
  re-flow.
- Keep each bullet to ~1–2 sentences ("bite-sized").

## Feed the model the real grades

Pass the `DraftGradeCalculator` output (or its server equivalent) into the
prompt as structured JSON so the narrative is anchored to objective values:

```json
{
  "picks": [
    {"pick": "1.01", "manager": "cfolk", "player": "Patrick Mahomes",
     "pos": "QB", "nfl": "KC", "value": 4200, "expected": 5100,
     "delta": -900, "grade": "C+"}
  ],
  "teams": [
    {"manager": "lukenovak", "team_name": "Gangsters of Love",
     "voe": 8056, "letter": "A+"}
  ]
}
```

The model narrates; it does not compute grades. This kills the
"grades disagree with the story" problem.

## Naming: use display names, not `username`

Sleeper's `/league/{id}/users` returns `username: null` for everyone — only
`display_name` is populated, and `team_name` is set for a minority. The
recap should reference `team_name` when present, else `display_name`
(mirror the client's `SleeperUser.resolvedDisplayName`). This is the same
bug that produced blank rows in the client grades card (fixed there in
`HistoryStore.fetchDraftRecords`).

## Out of scope

- iOS rendering (already handled).
- Re-generating historical reports already in DynamoDB — decide separately
  whether to backfill or only apply to new reports.

## Acceptance

- 2026 post-draft recap renders as: title → round-by-round bullets w/ grades
  → steals/reaches → per-team grades → awards, with visible spacing.
- Every pick bullet shows a grade that matches the Team Grades card.
- No blank manager names anywhere in the recap.
