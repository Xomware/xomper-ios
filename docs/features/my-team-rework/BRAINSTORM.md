# My Team — Page Rework

Status: Draft
Owner: Dominick
Source: screenshot review feedback

## TL;DR + Recommendation

The current My Team page is a single dense scroll: header card, then four
position sections (Starters → Bench → Taxi → IR). The user wants navigation
within it (tabs), an embedded hexagon strengths chart, trade suggestions, and
"quick hitters" up top — and **we already own the data and algorithms for all
four**. `TeamAnalysisBuilder`, `HexagonChartView`, and `RecommendedTradeBuilder`
exist and are battle-tested inside `TeamAnalyzerView`. The rework is mostly an
IA + extraction job, not a data job.

**Recommended: Option B — Sectioned tabs with a sticky summary header.** Three
tabs (Roster · Strengths · Trades), one always-visible quick-hitter header.
Biggest tradeoff: tabs inside an already-nested `NavigationStack` add a third
selection layer (drawer → tab → in-page tab) that the user has to learn.

---

## Current-State Audit

| Section | Role today | Status |
|---|---|---|
| `teamHeader` (avatar, name, record, streak, league/division rank) | Identity + standings snapshot | Keep — already does double duty |
| `startersSection` | Slot-ordered starting lineup | Keep, but cramped: 9+ rows before bench |
| `benchSection` | Position-sorted bench | Keep — dynasty value is mostly here |
| `taxiSection` | Taxi rows | Often empty mid-season — wastes vertical space |
| `irSection` | Reserve rows | Often empty — same |
| (none) | Dynasty value totals | **Missing** — exists in `TeamAnalysis` but never shown on My Team |
| (none) | Position strengths vs league | **Missing** — exists, lives only in TeamAnalyzer |
| (none) | Trade ideas | **Missing** — exists as `RecommendedTradeBuilder`, locked inside Analyzer's Trade tab |
| (none) | Recent form / weekly points | **Missing** — `PlayerPointsStore` + `HistoryStore` already populated |

Net: today's page is roster-only. Everything the screenshot asks for already
exists elsewhere in the app — the rework is consolidation + extraction.

---

## The 4 Asks, Unpacked

### 1. Navigation / tabs

"Good" here means: the user can land on the page and reach roster, strengths,
or trade ideas in one tap without scrolling past the full bench. Inside an
already-pushed `NavigationStack` (TeamView is the root of the My Team
destination — see `MainShell.myTeamRoot`), a SwiftUI `Picker(.segmented)` or a
local `HStack` tab bar is the right shape — **not** a sub-`NavigationStack` and
**not** `TabView` (which would conflict with the system tab bar pattern and
swallow swipe-to-pop).

Pattern to copy: `TeamAnalyzerView.tabBar` (custom `HStack` with underline +
`championGold` active state). It already matches the theme and handles
`UIImpactFeedbackGenerator`.

**Data plumbing**: none — pure view state, `@State private var activeTab`.

### 2. Quick hitters

What's the right set? Argue for **four**, all derivable from already-loaded
data, sized for a single horizontal row of badges:

- **Total dynasty value** (`TeamAnalysis.totalValue`) + delta vs league avg
  ("+842 vs avg" with up/down arrow color)
- **League rank by value** (sort `analyses.totalValue` desc, find self) — this
  is the *real* power ranking, distinct from record-based standings
- **Record + streak** (already in `teamHeader`, just compacted into the strip)
- **Biggest weakness** — the axis where my value falls furthest below league
  avg, expressed as "Weakness: TE" with a tap-jumps-to-Strengths-tab affordance

Not picked: total points (FPTS) — already in standings table and not
actionable. Win projection / playoff odds — needs model we don't have.

**Data plumbing**: build the strip from `TeamAnalysis` for self +
`leagueAverageAxes(analyses)` for delta. The team store doesn't currently hold
`TeamAnalysis`; the rework needs to either (a) compute it in `TeamView.body`
each render (cheap — 12 rosters × ~25 players each, integer sums) or (b) cache
it in a new `MyTeamAnalysisStore` keyed by leagueId. **Recommend (a)** — same
pattern Analyzer uses, no new store.

### 3. Embedded hexagon chart

Three placements considered:

- **Full hex on its own tab** — clearest, but burns a tap when the chart is
  what the user came for.
- **Mini hex in header strip** (~120pt) — too small to read 6 axis labels.
- **Hex as hero on Strengths tab + thumbnail glance in Quick Hitters** — best
  of both. The thumbnail is decorative (no labels, primary polygon only); the
  full chart with league-average underlay lives on the Strengths tab.

Recommend the third. **`HexagonChartView` is already reusable** — it takes
plain `[HexAxis]` arrays and an `axisMaxes` dict. No extraction needed beyond
passing it `nil` for `comparison` and giving it a smaller `minHeight` when used
as the thumbnail.

**Data plumbing**: call `TeamAnalysisBuilder.build(...)` and `axisMaxes(...)`
in `TeamView` exactly as `TeamAnalyzerView` does today. Same inputs, same
outputs. No backend change.

### 4. Trade suggestions

Algorithm is already implemented in `RecommendedTradeBuilder.recommend(...)`:

1. Find my weak positions (≤85% of league avg).
2. Find my strong positions (≥105% of league avg).
3. For each league partner, find positions where they're surplus and I'm weak.
4. Match their best player at that position against one of my strong-position
   players whose FantasyCalc value is within 5%.
5. Return ranked by my-side improvement, capped at 5 suggestions.

This is exactly the algorithm the user asked for and it's working in
`TeamAnalyzerView.tradeTab`. The My Team rework just needs to call it. The
"What" question is purely presentation: pairs (full give/receive) vs outbound
only vs inbound only. The existing builder produces **pairs**, so present them
as pairs — the inbound/outbound split is unnecessary complexity.

**Data plumbing**: `RecommendedTradeBuilder.recommend(myAnalysis:analyses:rosters:playerStore:valuesStore:)`
returns `[RecommendedTrade]` ready to render. Tap on one should deep-link into
the existing `TeamAnalyzerView` Trade tab with the trade pre-loaded — that
already works for the in-Analyzer recommended trades, we just need the deep
link via `AppRouter`.

---

## Open Design Questions (with positions)

### Q1: Tabs vs accordion vs sub-page push

**Position: in-page segmented tabs.** Accordion makes the page feel like a
form. Sub-page push doubles the nav stack (TeamView is already on the stack;
pushing again creates `… → TeamView → StrengthsView → PlayerDetail` chains
that get confusing with system swipe-to-pop). Tabs keep the user grounded.

**Case against**: three tabs inside a drawer destination inside a nav stack is
three selection layers. If a future tab is added, this gets noisy. Mitigation:
hard-cap at three tabs in the spec.

### Q2: Hex placement — top, sticky, or own tab

**Position: hero of its own Strengths tab.** Sticky-pinned hex eats ~280pt on
iPhone 17 Pro (smaller phones worse), leaving ~400pt for the roster — not
worth it. The Quick Hitters strip already shows the "weakness" callout, so the
hex isn't needed permanently visible.

**Case against**: forces a tap to see the chart. Acceptable given the strip
already names the weak axis.

### Q3: Trade suggestions — outbound, inbound, or pairs

**Position: pairs.** `RecommendedTradeBuilder` already builds pairs and the
user can see give/receive at a glance. Splitting into "players to acquire"
and "players to shop" doubles the work to read a suggestion and breaks the
existing builder contract. Tap on a pair → push to Analyzer Trade tab
pre-loaded.

**Case against**: pairs hide the fact that *some* of my players are
universally tradeable. If we want a "league shopping list," that's a separate
feature on the Analyzer page, not My Team.

### Q4: Quick hitters — which 4 stats?

**Position: Value + Value Rank + Record/Streak + Weakness axis.** Argued
above. Reject "total FPTS" (not actionable) and "playoff odds" (model not
built).

---

## IA Mapping — Proposed Structure

```
┌─────────────────────────────────────────────┐
│ teamHeader (avatar + name + record + ranks) │  ← unchanged, slim it
├─────────────────────────────────────────────┤
│ QuickHittersStrip                            │  ← NEW
│  [Value 12,400 ▲842] [#3 by Value]           │
│  [8-3 · W3]          [Weakness: TE →]        │
├─────────────────────────────────────────────┤
│ ┌─Roster─┬─Strengths─┬─Trades─┐              │  ← in-page tab bar
│ └────────┴───────────┴────────┘              │
├─────────────────────────────────────────────┤
│                                              │
│ Tab content                                  │
│                                              │
└─────────────────────────────────────────────┘
```

- **Roster tab**: today's Starters → Bench → Taxi → IR sections, unchanged.
- **Strengths tab**: hero `HexagonChartView` (mine + league avg underlay) +
  per-position breakdown grid (reuse `breakdownGrid` from Analyzer's Compare
  tab — only it without an opponent column).
- **Trades tab**: list of `RecommendedTrade` cards (reuse `recommendedTradeRow`
  from Analyzer). Empty state when no fair-value matches. Tap → deep-link into
  Analyzer Trade tab.

---

## Risks

- **Nav stack interactions**: TeamView already presents `PlayerDetailView` as
  a sheet — safe. The Trades-tab deep-link to Analyzer needs a new
  `AppRoute.tradeAnalyzer(preload:)` case (or push and set state via a shared
  store). Don't double-push from inside a tab.
- **TeamAnalysis compute cost on render**: 12 rosters × ~25 players = ~300
  dict lookups. Cheap, but `TeamView.body` runs on every roster change.
  Memoize via `let analyses = ...` outside the tab switch (already the pattern
  in Analyzer).
- **Taxi/IR edge cases**: today's view hides empty taxi/IR sections. Keep
  that behavior in the Roster tab. The hex chart's Taxi axis will read zero
  for most teams — that's fine, it's already designed for it.
- **PlayerValuesStore freshness**: if the user opens My Team before
  Analyzer has ever loaded, `valuesStore.hasValues` is false and the
  Strengths/Trades tabs need to either load on-tab-activate or show an
  empty-loading state. Recommend loading in `TeamView.task` (mirrors
  Analyzer).
- **Refresh contract**: the existing pull-to-refresh reloads
  `playerStore.loadPlayers()`. Strengths/Trades depend on `valuesStore` and
  league rosters — add those to the refresh.

---

## Phase 0 Pre-work

1. **Verify `HexagonChartView` is reusable as-is.** It already lives in
   `Features/TeamAnalyzer/` and takes plain structs — no extraction needed.
   Just import the file and instantiate. Future polish: move to
   `Features/Shared/` if a third surface ever needs it.
2. **Extract `breakdownGrid` and `breakdownRow`** from `TeamAnalyzerView` into
   a `PositionBreakdownView` so My Team's Strengths tab and Analyzer's Compare
   tab share one implementation. Single source of truth for the per-position
   bars + delta colors.
3. **Extract `recommendedTradeRow`** into a `RecommendedTradeCard` view for
   the same reason. The card already renders standalone (no internal state).
4. **Add `AppRoute.tradeAnalyzer(preload: RecommendedTrade?)`** so the My Team
   Trades tab can deep-link into the Analyzer with a trade pre-loaded into the
   builder. Today the Analyzer's own "Recommended trades" section sets the
   trade-builder state directly via `@State` — we need to surface those
   setters via a small `TradeAnalyzerController` or pass a `preload` argument
   on the view init.

---

## Converged Options

### Option A: Quick Hitters strip only

**What**: Add the four-badge summary strip at the top of TeamView. Leave the
roster sections as-is. Skip embedded hex and trade suggestions.

**How it works**: Compute `TeamAnalysis` for self in `TeamView`, compute
`leagueAverageAxes` for delta, render strip. Roster sections unchanged.

**Pros**:
- ~1-day scope. One file changed.
- Zero nav stack risk, zero new routes.
- Delivers the most-glanceable improvement first.

**Cons / Risks**:
- Doesn't address the user's "tabs" or "octagon" asks.
- Probably needs a follow-up feature within weeks.

**Best if**: We want to ship something this week and re-evaluate trade
suggestions/hex placement after seeing the strip in production.

### Option B: Sectioned tabs with sticky Quick Hitters (RECOMMENDED)

**What**: Quick Hitters strip + three-tab in-page nav (Roster · Strengths ·
Trades). Hex chart on Strengths tab. Recommended trades on Trades tab.

**How it works**: Wrap today's roster sections in a `Roster` tab. Add
`Strengths` tab pulling `HexagonChartView` + extracted breakdown grid. Add
`Trades` tab pulling `RecommendedTradeBuilder.recommend(...)`. All data
sourced from existing stores. Deep-link Trades cards to Analyzer.

**Feature breakdown for `/orchestrate`**:
- F1: extract shared views (`PositionBreakdownView`, `RecommendedTradeCard`)
- F2: Quick Hitters strip + value/rank/weakness compute
- F3: in-page tab bar + Roster tab (move existing sections)
- F4: Strengths tab (hex + breakdown)
- F5: Trades tab + Analyzer deep-link route

**Pros**:
- Hits all four user asks.
- Reuses every existing algorithm — zero backend change.
- Aligns My Team with Analyzer visually (same tab bar, same cards).

**Cons / Risks**:
- Three nesting layers (drawer → page → in-page tab).
- Trades tab requires the new `AppRoute` case.
- Phase 0 extraction is upfront cost before any user-visible change.

**Best if**: We want the full rework in one epic, batched cleanly.

### Option C: Tabs without Trades (minimum complete rework)

**What**: Quick Hitters + two tabs (Roster · Strengths). Drop the embedded
Trades tab; users still get trade suggestions via the Analyzer.

**How it works**: Same as B without F5. Roster tab + Strengths tab only.

**Pros**:
- No new `AppRoute` case, no Analyzer deep-link.
- Two-tab UX is genuinely simpler than three.
- Hex is the visually flashy ask; covering it with the breakdown is enough.

**Cons / Risks**:
- The user explicitly asked for trade suggestions. Punting them feels like
  a partial answer.

**Best if**: The deep-link or new route plumbing turns out to be heavier than
expected, and we want to ship B-minus.

---

## Recommendation

**Option B.** All four asks are addressable, all data exists, and the
biggest risk (the new route) is well-scoped to one feature in the breakdown.
The user's framing — "we already have like all the data" — is correct, and
the rework is a consolidation play.

Depends on: how heavy `AppRoute.tradeAnalyzer(preload:)` ends up being. If
the Analyzer's trade-builder state can't be hoisted into a `@State` parent
or a small controller without rewriting the view, fall back to **Option C**
and re-spec the deep-link as its own follow-up.
