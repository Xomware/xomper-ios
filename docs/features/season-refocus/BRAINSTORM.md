# Brainstorm: Season Refocus + Landing Page

**Status**: Draft
**Created**: 2026-05-21
**Scope**: One combined epic covering (a) UI/UX restructure to face forward into the 2026 season, and (b) a new Landing Page surfacing AI Reviews as headline news.
**Related epic**: `docs/features/ai-review/` (F0/F1/F2/F3 shipping this session)
**Backfill assumption**: 2024 + 2025 AI reports will be populated into the archive in parallel — treat the archive as eventually-full.

---

## Problem Statement

It's offseason May 2026. Draft is July 6 2026; season starts Sept 2026. The app still looks mid-2025:

- Standings tab proudly displays 2025 final standings (stale and demoralizing on cold open).
- Draft History is the only "draft" surface — it conflates last year's data with the upcoming draft.
- The Reverse-HPP rule idea ("Draft Order Proposal") sits in the League nav section as if it were a committed thing, when it's just a proposal.
- The Live + Mocks + Proposal sub-tabs live on the Draft Order screen, not where users would intuitively look (the Draft tab).
- AI Reviews — the big new content investment landing this session — are surfaced via a single banner card embedded in SearchView. They deserve top billing, not an ambient drop-zone above a search box.
- The app has no concept of a "landing page" / news surface — it opens onto Standings, which after Sept 2026 will be inert in May.

The user wants the app to feel like *"what's coming next"* not *"what just happened,"* and AI Reviews to be the central new artifact users come back for.

---

## Phase 1 — Explore (raw idea pool)

Loose dump of angles before converging:

- Make Landing Page the new default destination; relegate Standings to a deeper tray entry.
- Use the AI Review home card as the heart of the Landing Page — full-bleed hero treatment, not a 60pt strip.
- Year-pill picker at the top of a unified Draft tab (2026 | 2025 | 2024 | ...) with sub-tabs that vary per year.
- Draft tab = "this year's draft is the live one; older years are post-mortems."
- Demote Draft Order Proposal into a new "Ideas" or "Proposals" subsection nested under League with the rule proposals it actually relates to.
- Rename Draft Order Proposal to something honest: "Reverse-HPP Proposal" or "Rule Idea: Draft Order".
- Add a "History" / "Archive" tray section at the bottom that holds all stale-after-this-year surfaces: prior Standings, prior Matchup History, prior Drafts (linked-in).
- Standings becomes a live-only widget — empty state in offseason ("Season starts Sept 8 — see you then"); historical standings auto-shunt to Archive.
- Or: Standings keeps a season picker like Draft does, so the same surface shows live or historical based on chip.
- Pluck the AI Review home card out of SearchView entirely — Search reverts to pure search.
- Landing Page composed of "stripes" — each stripe is a different surface (announcements, latest AI report, scoreboard, standings tickertape, news).
- Landing Page as a vertical scroll feed (Instagram-style) of mixed card types ordered by recency.
- Hardcoded announcements via a Swift constant `LeagueAnnouncements.current` in v1; defer admin-driven announcements to v2.
- Pull league announcements from existing `xomper_announcements` table if one exists (it doesn't — would need infra).
- Use the existing Sleeper trending API for "News" (most adds/drops this week).
- Skip news entirely v1 — not enough signal in offseason.
- Scrolling horizontal standings strip = small commitment, big "league heartbeat" feel.
- Countdown card: "67 days until draft" / "112 days until Week 1" — cheap and high-value during offseason.
- Phase the rollout: demote + rename first (low-risk), then build Landing Page MVP, then restructure Draft, then wipe Standings + create Archive.
- One big bang PR — would touch every nav touchpoint and need full QA pass; risky but cohesive.
- Per-year Draft sub-tab structure: "Live" (upcoming-draft view, this year only), "Picks" (rounds + board, the existing view), "Mocks" (this year only), "Recap" (AI post-draft report, any year that has one).
- Could fold Mocks into Live (one screen with a "this is mocked from BPA" pill) — but user explicitly named Mocks as a sub-tab, leave it.
- Past-year Draft sub-tabs: just "Picks" + "Recap" (no Live, no Mocks).
- Year selector implementations: dropdown menu, horizontal pill scroller, segmented control, or "season chip" matching the existing SeasonStore pattern (HeaderBar already has a season picker — could reuse it).
- Reusing the existing SeasonStore season chip in HeaderBar is the cleanest — fewer year selectors on screen.
- "Recap" tab for past years requires the backfilled AI reports to actually exist; if backfill is incomplete, render empty state per year ("No recap generated for 2024 draft yet").
- Landing Page card priority order needs spelling out — what's at the top changes through the calendar year. Offseason: AI report + countdown. Preseason: AI report + draft countdown + mocks. In-season: This week's matchup + last week's weekly recap + standings stripe. Playoffs: bracket card. Could be dynamic and time-aware.
- Single Card prioritization function that takes a date + report set and returns ordered card list — extracted into something testable.
- Reconciling the existing `AIReviewHomeCard` inside `SearchView`: kill it there once Landing Page exists, since Search is no longer the cold-open home.
- Cold-open performance: Landing Page composes ~5 cards each with their own data dependency — need to make sure they degrade gracefully (each card loads independently, shows skeleton + own retry).
- Empty state for landing page during offseason when no AI report has run yet: hero card becomes "Stay tuned — first report after the July 6 draft."
- Should Landing Page have a refresh control? Yes — pull-to-refresh re-fetches all stripes in parallel.
- "Things to check out" copy from the user — could be a hand-picked "you might want to see" card that rotates through Team Analyzer, Trade Analyzer, Rule Proposals, etc. Like a feature spotlight.
- Onboarding-ish: surface unread rule proposals as a CTA card ("3 open proposals — vote by Sat").
- Tray reordering: move Standings out of the top "Compete" section once it's gutted; replace it with the new Landing Page entry. Or keep Standings up top but make it offseason-aware (renders countdown when no live data).
- New section in tray: "League HQ" containing Landing Page, Announcements; "Compete" reserved for in-season live surfaces (Matchups, Standings, Playoffs).

---

## Phase 2 — Converge (per-question options)

### Q1 — Draft tab restructure

**Current**: `TrayDestination.draftHistory` → "Draft History", renders `DraftHistoryView` which already auto-switches into an "upcoming draft" mode when the selected season chip equals `nflStateStore.currentSeason` and no picks have been ingested yet. The Live / Mocks / Proposal sub-tabs live on a *separate* tray entry (`.draftOrder` → "Draft Order Proposal" → `DraftOrderView`).

**Target**: Rename to "Draft". Per-year experience. This year = Live + Mocks + Recap. Past years = Picks + Recap.

#### Option A — Reuse HeaderBar SeasonStore chip + dynamic sub-tabs
Rename `.draftHistory` → `.draft`. Keep using the existing season chip in `HeaderBar` (already powered by `SeasonStore` and bound to many feature views). When the selected season equals `nflStateStore.currentSeason`, render sub-tabs `[Live, Mocks, Recap]`; otherwise render `[Picks, Recap]`. The `DraftOrderView` proposal mode moves out entirely (see Q2).

- Pros: Reuses existing season picker — no new chrome. Consistent with how Matchup History etc. already work. Low net new UI.
- Cons: HeaderBar chip is global — selecting "2024" for Draft will also drift other views looking at the same store. (Already true today; not a regression.)
- Best if: We want minimum new navigation surface and tight integration with the existing season state.

#### Option B — In-tab year pill scroller + sub-tabs
Replace the global chip dependency in the Draft tab with a Draft-local horizontal pill scroller (`2026 | 2025 | 2024 | 2023 | ...`). Sub-tabs change per year as above. Keeps the season chip in HeaderBar for other views unaffected.

- Pros: Draft tab feels self-contained — moving inside Draft doesn't side-effect other tray destinations.
- Cons: Two season selectors visible at once (HeaderBar chip + Draft pill scroller) is confusing. Net new component to build + maintain.
- Best if: We discover that the global SeasonStore chip is causing too many cross-view side effects.

#### Option C — Year as primary nav (collapsible accordion of all years)
One long scrolling page: 2026 expanded by default at top, prior years collapsed below. Each year has its own embedded sub-tabs.

- Pros: Everything in one place — no picker UI at all.
- Cons: Heavy scrolling. Sub-tabs nested inside each year section are noisy. Mock list could be very long. Less discoverable than chips.
- Best if: Years are very few (≤3) and content per year is short.

### Q2 — Draft Order Proposal (Reverse-HPP) demotion

**Current**: `.draftOrder` lives in the "League" section right next to Payouts, AI Review, Rulebook etc. — looks like an established feature.

**Target**: Demote and re-frame as a rule idea, not a fact.

#### Option A — Move into Rule Proposals as a sub-page
`DraftOrderView` becomes a linked sub-page of `RulesView(page: .ruleProposals)`. The dedicated tray entry disappears. Live / Mocks / Recap sub-tabs absorb into the new Draft tab; Proposal sub-tab becomes its own linked screen inside Rule Proposals.

- Pros: Cleanest IA — proposals live with proposals. Frees a tray slot. Strongest signal that this is "just an idea."
- Cons: Buries it more than just "down the sidebar." Requires `RulesView` work to add a sub-page anchor.
- Best if: We want the strongest demotion + tight conceptual grouping.

#### Option B — Rename + sink to bottom of League section
Rename `.draftOrder` → "Reverse-HPP (Idea)" or "Draft Order Idea". Keep it in the tray but move it to the bottom of the League section (after `.ruleProposals`).

- Pros: Cheap. Still discoverable. Doesn't require restructuring Rule Proposals page.
- Cons: Still pretends to be a top-level destination.
- Best if: We don't want to touch `RulesView` in this epic.

#### Option C — Kill the tray entry entirely; only reachable from Rule Proposals
Same as A but no soft landing — `DraftOrderView` only reachable by tapping the corresponding Rule Proposal card.

- Pros: Maximum demotion.
- Cons: User said "move further down the sidebar" not "remove from sidebar." Risks under-shooting their intent.
- Best if: We confirm with the user that out-of-sidebar is acceptable.

### Q3 — Standings wipe

**Current**: `StandingsView` builds standings from `myLeagueRosters` + `myLeagueUsers`. Whenever the league is live (in-season), it shows live records; in offseason it shows the *final* records from the previous season (which is exactly the staleness the user is calling out).

**Target**: "Standings needs to be wiped. Historical data on seasons past is shown somewhere in app."

#### Option A — Standings = live-only with offseason empty state
`StandingsView` checks `nflStateStore.season` vs `leagueStore.myLeague.season` and renders an offseason empty state when there are no live records. Historical standings move to an Archive tray entry (see Q6).

- Pros: Standings stays in the same tray slot for in-season muscle memory. Offseason state can be informative (countdown + "Season starts...").
- Cons: Need infra to detect "is there live data yet" — Sleeper rosters carry last season's W-L until Week 1 rolls over, so this isn't trivial.
- Best if: We want one canonical "Standings" surface that's offseason-smart.

#### Option B — Delete Standings outright; replace with offseason-aware tile on Landing Page
Remove `.standings` from the tray. Landing Page shows a "Standings Tickertape" stripe in-season; absent in offseason. Historical Standings live in Archive.

- Pros: Forces the user to the new front door (Landing Page) for league pulse. Tray gets simpler.
- Cons: In-season users will hunt for the dedicated screen. Lose the full-screen detail view.
- Best if: We're confident the Landing Page tickertape + drilling into team detail covers everyone's needs.

#### Option C — Keep Standings but auto-route to History when offseason
`.standings` tray entry stays, but tapping it during offseason renders the *latest-season-with-completed-data* view (essentially the Archive view inline). Once Week 1 ships, it auto-rolls over to live.

- Pros: Single entry point. No "missing screen" feeling.
- Cons: Confusing — same tray label, different behavior. Hides the "wipe."
- Best if: We don't want to give up tray real estate.

### Q4 — Landing Page composition

**Target**: "Quick league hitters. Announcements, weekly reports, things to check out. Voting CTAs. Standings tickertape. News. Scores."

#### Option A — Static stripe order
Vertical scroll of cards in a fixed order:
1. **AI Report Hero** — full-bleed card for the most recent post-draft / preseason / weekly report (the right one bubbles up by recency).
2. **Announcements** — hardcoded constants for v1 (`LeagueAnnouncements.current`), 1-3 short cards with optional CTA (link to a rule proposal, payment reminder, draft date).
3. **Countdown** — days until draft / Week 1 / playoffs.
4. **Standings Tickertape** — horizontal scroll, only in-season.
5. **This Week's Matchups** — horizontal scroll of cards, only in-season.
6. **Spotlight** — "Try out: Team Analyzer" rotating CTA into another feature.
7. **AI Report Archive teaser** — "Read past reports →" linking to `.aiReview`.

- Pros: Predictable layout, easy to QA, easy to grow.
- Cons: Off-season Landing Page is sparse if there's nothing live (just AI hero + countdown + spotlight).

#### Option B — Time-aware ordering function
Same stripes as A but ordered by a `LandingCardPriority` function that takes today's date + league state and reorders. Offseason: AI report + countdown + spotlight up top. Preseason: AI report + mocks + draft countdown. In-season: matchups + AI weekly recap + standings + report archive. Playoffs: bracket card.

- Pros: Always feels relevant. Encodes the "what's coming next" mission directly.
- Cons: More complex; testing/QA matrix grows; needs the priority function itself to be testable.

#### Option C — Single hero + linear archive list
Hero = latest AI report. Below it, a flat newest-first list of past reports + announcement cards interleaved by date. Standings/matchups deferred entirely; users open the dedicated tabs.

- Pros: Cleanest implementation. Closest to the existing `AIReviewView` archive — could be a fast iteration.
- Cons: Loses the "league heartbeat" feeling the user described (no tickertape, no scores).

### Q5 — New default landing destination

**Current**: `NavigationStore.currentDestination = .standings` is the cold-open default (per `NavigationStore.swift` line 22).

#### Option A — New `.landing` becomes the default
Add `case landing` to `TrayDestination`. Set `currentDestination = .landing` by default. Map it to a new `LandingView`. Pin it at the top of the tray (above "Compete" section, or as its own pinned section).

- Pros: Honors the user's intent that AI reviews are headline news. The first thing users see is the new front door.
- Cons: Wholesale change to first-load behavior — heavy QA touch point.
- Best if: This is the right answer; user explicitly described it as "front page news."

#### Option B — Make Landing reachable only via tray, keep Standings as default
Add `.landing` but don't change the default. Users navigate to it explicitly.

- Pros: Lowest blast radius.
- Cons: Defeats the entire purpose. Reject.

### Q6 — Historical data archival

#### Option A — New `.archive` (or `.history`) tray section at bottom
Add a new tray destination(s) that aggregate stale-after-this-year content:
- Prior-season Standings (year-pick → renders historical `StandingsView`).
- Prior-season Drafts (already covered by the new Draft tab's year picker — link out from Archive into Draft tab pre-selected on a year).
- Prior-season Matchup History (already exists as `.matchupHistory`).
- Past AI Reports archive (already exists as `.aiReview`).

Could be a single "Archive" tray entry that opens a hub view, or a new "Archive" *section* at the bottom of the drawer with multiple entries.

- Pros: Centralizes "stale stuff" under one roof, reduces clutter in the active sections.
- Cons: Requires net-new "Archive" view if we go with a hub model. If just a section, it's mostly relabeling existing entries.

#### Option B — Each historical surface stays where it is; Standings flips to live-only
No new Archive. `.matchupHistory` stays in History section, `.aiReview` stays in League, Standings becomes offseason-aware. Past drafts live inside the new Draft tab year picker.

- Pros: Minimum tray churn.
- Cons: User's wording ("historical data on seasons pasts is shown somewhere in app") suggests they want it grouped, not scattered.

### Q7 — Implementation strategy

#### Option A — Phased sub-features under one epic (orchestrate-friendly)
Split into 4 ordered phases:
1. **F1 — Demote + rename**: Rename `draftHistory` → `draft`, demote `.draftOrder`. Pure cosmetic + tray surgery. (~S)
2. **F2 — Landing Page MVP**: New `.landing` destination + LandingView + cards. Reconcile/remove `AIReviewHomeCard` from `SearchView`. Set default destination. (~M-L)
3. **F3 — Draft tab restructure**: Per-year sub-tabs (Live/Mocks/Recap for current, Picks/Recap for past). Wire AI report into Recap tab. (~M)
4. **F4 — Standings wipe + Archive**: Offseason-aware Standings, new Archive tray entry/section, historical drilldowns. (~M)

- Pros: Each phase ships independently; we can pause / revisit after F1 with the user. Matches the `/orchestrate` pattern. Easier QA at each step.
- Cons: Multi-week elapsed time; partial states (e.g., post-F1, post-F2 but pre-F3) might feel incomplete.

#### Option B — Big bang single PR
One PR that rewrites nav + adds Landing + restructures Draft + wipes Standings.

- Pros: One coherent change. No "weird intermediate state."
- Cons: Massive QA surface. Hard to bisect regressions. Hard to review. Hard to roll back partial wins.

### Q8 — Backfill content surface

Once 2024+2025 reports are populated:

#### Option A — Recap sub-tab in Draft tab per year + Archive in tray
Each year's Draft tab Recap sub-tab queries the AI archive for `type=postDraft AND season=<year>`. Weekly reports for past years live in `.aiReview` (already paginated, already capable). Preseason reports surface the same way.

- Pros: Reuses already-shipping infra. No new endpoints.
- Cons: Past-year Weekly Report surfacing is "scroll the archive" which is fine but not a dedicated per-year view.

#### Option B — Per-year report hub in Archive
New view in the Archive section that groups all reports by season. "2024 Reports → [Post-Draft] [Preseason] [Week 1] [Week 2]...". Landing within Draft tab still pulls in the post-draft recap.

- Pros: Per-year browse is nice for retrospection.
- Cons: Net-new view; AI archive already does newest-first; this is a power-user surface.

---

## Phase 3 — Recommendation (winners per question)

| Q | Pick | Why |
|---|------|-----|
| Q1 — Draft restructure | **Option A** — Reuse HeaderBar season chip + dynamic sub-tabs | Lowest new chrome; consistent with existing season-aware screens. Already-implemented "upcoming draft" mode in `DraftHistoryView` becomes the Live sub-tab basically free. |
| Q2 — Proposal demote | **Option A** — Fold into Rule Proposals | User said "it's just an idea we are thinking of" — that's literally what Rule Proposals is for. Strongest demotion + clean IA. |
| Q3 — Standings wipe | **Option A** — Live-only with offseason empty state | Keeps muscle memory for the in-season slot, but stops lying in May. Offseason empty state = countdown card. Historical drilldowns live in Archive. |
| Q4 — Landing composition | **Option B** — Time-aware ordering | Matches user's "what's coming next" intent — landing changes through the year. Worth the extra complexity. Implement the priority function with a unit test for each calendar phase. |
| Q5 — Default destination | **Option A** — `.landing` becomes default | Non-negotiable per user's "front page news" framing. |
| Q6 — Archive | **Option A** — New Archive section in tray | Groups stale-after-this-year content. Pin at the bottom. Two entries to start: Archive → Past Standings (by year) and Archive → Past Reports (link to `.aiReview`). Past drafts reachable inside Draft tab itself, no Archive entry needed. |
| Q7 — Strategy | **Option A** — Phased sub-features | Orchestrate-friendly. Phase 1 ships in a day, immediate UX win. Each subsequent phase is independently reviewable. |
| Q8 — Backfill surface | **Option A** — Recap tab in Draft + existing archive | Reuses shipping infra. No new endpoints. |

**One-line summary of the recommended path**: Phased epic — rename + demote first, then build a time-aware Landing Page that becomes the default, then restructure Draft tab around the HeaderBar season chip, then wipe Standings and add an Archive section.

---

## Phasing Recommendation for `/orchestrate`

Four sub-features, sequenced strictly. Each gets its own `/plan` pass before `/execute`.

```
F1 — Tray Surgery: Rename + Demote          docs/features/season-refocus/f1-tray-surgery/PLAN.md
  │  rename .draftHistory → .draft, fold .draftOrder into Rule Proposals, demote out of League section
  │  Effort: S. Pure SwiftUI relabeling + enum case rename + RulesView sub-page anchor.
  ▼
F2 — Landing Page MVP                       docs/features/season-refocus/f2-landing/PLAN.md
  │  new .landing TrayDestination + LandingView, time-aware card priority,
  │  remove AIReviewHomeCard injection from SearchView,
  │  set default destination to .landing
  │  Effort: M-L. New top-level view + several card components + priority logic.
  ▼
F3 — Draft Tab Restructure                  docs/features/season-refocus/f3-draft-tab/PLAN.md
  │  per-year sub-tabs (Live/Mocks/Recap | Picks/Recap), reuse SeasonStore,
  │  wire AI post-draft report into Recap, port DraftOrderView's live/mocks
  │  modes into sub-tabs of Draft
  │  Effort: M. Mostly refactor + new sub-tab control + recap wiring.
  ▼
F4 — Standings Wipe + Archive Section       docs/features/season-refocus/f4-standings-archive/PLAN.md
     offseason-aware StandingsView, new Archive tray section,
     historical Standings drilldown
     Effort: M. New tray section + per-year standings view.
```

F2 unblocks the user-visible win (Landing Page is the headline change). F1 ships first because it's the lowest-risk groundwork that won't bite us during F2/F3.

---

## Epic-Level Risks

- **Wholesale nav restructure means everywhere has regression potential**: deep-link routes, drawer state, default destination, edge-swipe gesture all touch the same surface. Mitigate with phased rollout (F1 first, then halt and QA before F2).
- **`AIReviewHomeCard` reconciliation**: F0 of the ai-review epic placed this card inside `SearchView`. F2 of this epic needs to remove it and migrate the visual treatment to the Landing Page hero card. Coordinate timing so we don't end up with the card in *both* places or *neither*.
- **`NavigationStore.currentDestination = .standings` is the cold-open default**: changing this is high blast radius. Make sure F2 ships with the new default and a fallback path if the Landing view crashes (don't trap users on a broken landing surface).
- **Backfill timing**: F3's Draft Recap sub-tab depends on backfilled 2024+2025 AI reports existing. If backfill hasn't landed when F3 ships, the past-year Recap tabs will show empty states. Plan for empty-state copy that doesn't look like a bug.
- **User may dislike new home layout**: this is a wholesale UX rethink. Recommend asking the user to walk through the F2 mockup *before* `/execute` runs.
- **Time-aware priority function is testable but date-dependent**: unit tests need to inject `Date` rather than read `Date()`. Easy to get wrong on first pass. Build it with explicit injection from day one.
- **HeaderBar season chip side-effects**: switching the chip to a past year in Draft will change other views' selected season too. Already true today, but the Draft restructure makes this more visible. Consider whether F3 needs a Draft-local season picker (Q1 Option B) instead — open question for `/plan`.
- **Tray real estate**: tray is already 17 entries deep (per `TrayDestination`). Adding `.landing` + `.archive` brings it past 19. Consider whether some current entries fold together (e.g., is `.worldCup` worth a top-level slot or could it move into Archive?).

---

## Open Questions for `/plan`

These need user confirmation or `/plan`-level decisions:

1. **Exact tray ordering after this epic**: where does `.landing` pin (top section called "Home"? new "League HQ" section?)? Where does Archive section live (bottom of tray, above or below Settings footer)?
2. **Landing Page exact card priority order per calendar phase** — need a concrete spec for what shows in each window (offseason / preseason / in-season / playoffs / post-season). User mentioned scores, announcements, weekly reports, standings, news; rank them in each phase.
3. **Announcements model**: hardcoded constants for v1 confirmed in our recommendation — but who maintains them? Commit to repo + ship updates via app store? Or punt to v2 with admin-managed table?
4. **News stripe**: confirm with user — pull from Sleeper trending API (waiver activity), skip entirely v1, or hardcode an "NFL news" RSS source?
5. **Scores card**: this week's matchups inline on Landing, or just a deep link to `.matchups`?
6. **Draft tab sub-tab naming**: "Live" / "Picks" / "Mocks" / "Recap" — confirm exact wording. Past years would have "Picks" (the existing rounds/board view) and "Recap" (AI report).
7. **DraftOrder Proposal sub-page location**: which page inside `RulesView` does it nest under — `.ruleProposals`? Or its own anchor inside that page?
8. **Standings offseason copy**: what exactly does the empty state say? Countdown component? "Season starts Sept 8" hardcoded date?
9. **Archive entry shape**: single `.archive` hub OR multi-entry section ("Past Standings", "Past Drafts", "All AI Reports")?
10. **Cold-open destination override**: should we honor a stored "last visited" destination on next launch, or always cold-open to `.landing`? (Currently `NavigationStore` doesn't persist; this is a freebie if we want it.)
11. **`AIReviewHomeCard` removal timing in F2**: does it stay in SearchView until F2 ships and then both move together? Or do we strip it from SearchView in F1 and leave Search bare for a phase?
12. **Header season chip vs. Draft-local picker** — Q1 picked Option A (reuse HeaderBar chip) but `/plan` should sanity-check whether cross-view side effects bite us in practice.
13. **Per-year season list in Draft tab** — does it match `SeasonStore.availableSeasons` exactly, or do we filter (e.g., only years with completed drafts + this year)?

---

## Files Touched (preview for `/plan`)

The phases below will touch (at least) these:

- `Xomper/Features/Shell/TrayDestination.swift` (add `.landing`, `.archive`; rename `.draftHistory` → `.draft`; remove `.draftOrder`)
- `Xomper/Features/Shell/DrawerView.swift` (sections rebuild)
- `Xomper/Features/Shell/NavigationStore.swift` (default destination flip)
- `Xomper/Features/Shell/MainShell.swift` (new `destinationRoot` cases)
- `Xomper/Features/DraftHistory/DraftHistoryView.swift` (becomes the new Draft tab with sub-tab control)
- `Xomper/Features/DraftOrder/DraftOrderView.swift` (sub-tabs split: Live/Mocks move into Draft tab, Proposal mode becomes sub-page of `RulesView`)
- `Xomper/Features/Home/SearchView.swift` (remove `AIReviewHomeCard` injection)
- `Xomper/Features/AIReview/AIReviewHomeCard.swift` (repurpose as the Landing Page hero or fork into a `LandingAIReportHero`)
- `Xomper/Features/League/StandingsView.swift` (offseason-aware empty state)
- **NEW**: `Xomper/Features/Landing/LandingView.swift` + landing card components + `LandingCardPriority.swift`
- **NEW**: `Xomper/Features/Archive/ArchiveView.swift` (or section-level wiring only)
- **NEW**: `Xomper/Core/Config/LeagueAnnouncements.swift` (hardcoded constants for v1)

---

## Out of Scope (explicit non-goals)

- Backfilling 2024 + 2025 AI reports — running in parallel as separate work.
- Building an admin UI to edit announcements — v2 if dynamic announcements prove worth it.
- News stripe pulling from external feeds — defer until we know it's wanted.
- Push notifications for new Landing Page cards — separate concern.
- Light mode anything — app remains dark-only.
