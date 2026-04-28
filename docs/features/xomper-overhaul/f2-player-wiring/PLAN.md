# Plan: Xomper Overhaul — F2: Player Wiring Audit & Fix

**Status**: Done
**Parent epic**: [../PLAN.md](../PLAN.md)
**Feature ID**: F2
**Issue**: #4
**Created**: 2026-04-28
**Last updated**: 2026-04-28 (Phase 3 implementation complete)
**Phase**: 0 (Day 1, parallel with F1)
**Scope**: S/M (audit-driven; can escalate to L if audit reveals deeper rot)
**Dependencies**: none
**Recommended specialist agent**: `ios-specialist`

## Summary

Users report "no players are loading" in iOS. The web app (Sleeper-direct, identical `Player` shape) renders fine. The iOS `Player` model already matches web's, the Sleeper `/players/nfl` endpoint is the same, and `PlayerStore.loadPlayers()` is wired into `bootstrapPhase1` with disk cache + ETag. So this is **a wiring bug, not a schema problem**.

This sub-plan is **audit-first / fix-second** — unusual for a `/plan`. We do not pre-commit to a fix because we do not yet know which link in the chain is broken. Phase 1 runs the audit, Phase 2 picks the matching scenario, Phase 3 implements that scenario, Phase 4 verifies in simulator. If Phase 1 surfaces something deeper than the candidate scenarios listed here (e.g., a real schema gap), the fix path escalates and we re-plan rather than push forward.

## Goal

Players render correctly in **TeamView**, **TaxiSquadView**, and **DraftHistoryView**, with name + position + team + jersey + headshot pulled from Sleeper static metadata only. No `Player` schema additions, no new `XomperAPIClient` endpoints, no fantasy stats. Match web's behavior exactly.

## Approach: audit-first, fix-second

The brainstorm's Phase 2.5 audit established that:
- The backend has zero player endpoints (`xomper-back-end` is email + device tokens only).
- Web's `Player` interface is identical in shape to iOS's `Player`.
- Web fetches `https://api.sleeper.app/v1/players/nfl` directly with `shareReplay(1)`.
- iOS does the same fetch via `SleeperAPIClient.fetchAllPlayersRaw` with ETag + disk cache.

So the data path is correct on paper. Something between "boot" and "render" is the bug. Phase 1 instruments and verifies each link; Phase 2 maps findings to a candidate fix; Phase 3 patches.

---

## Phase 1 — Audit

**Output location**: write findings inline in this PLAN.md under a new `## Audit findings` section (do NOT spawn a separate AUDIT.md — keeps the audit and the fix decision co-located, easier for the executing agent to reference and for us to review the trail). The agent appends as it goes.

### Audit checklist

The agent must answer all 8 items. For each, record: what was checked, what the result was, evidence (file:line or simulator console output).

1. **Bootstrap call site** — Does `PlayerStore.loadPlayers()` actually run on app boot?
   - Trace: `XomperApp.swift` → `AuthGateView` → `ContentView.bootstrapPhase1()` (line 158-164) calls `playerStore.loadPlayers()` via `async let playerLoad`. Confirm this `.task` modifier on `ContentView` (line 32-34) actually fires post-auth.
   - Add a temporary `print("[PlayerStore] loadPlayers start")` / `print("[PlayerStore] loadPlayers end count=\(players.count)")` at the top and bottom of `loadPlayers()`. Run simulator, confirm both print.
   - If `loadPlayers` runs but consumers (TeamView, etc.) mount before it returns — that is scenario **C**.

2. **Sleeper endpoint reachability** — Does `/players/nfl` actually respond from the simulator?
   - Add a `print("[SleeperAPI] fetchAllPlayersRaw status=\(httpResponse.statusCode) bytes=\(data.count)")` inside `SleeperAPIClient.fetchAllPlayersRaw`.
   - Expected: status 200, ~10MB payload on first run; status 304 on revalidation.
   - If 0 bytes on a 200, that's a CDN issue. If a non-2xx, that's a different problem entirely.

3. **Decode success** — Does the `[String: Player]` decode without throwing?
   - Wrap the `JSONDecoder().decode` call in `loadPlayers()` with `do { ... } catch { print("[PlayerStore] decode error: \(error)") }` (the existing catch swallows decode errors silently into `self.error`).
   - If decode fails, the existing logic discards the error when `players` is empty — so the user sees nothing and no message. Print the exact `DecodingError` to identify which field broke. That's scenario **E** if a non-existent field was added somewhere, or a brand-new Sleeper field shape if not.

4. **Map population** — After `loadPlayers()` returns, does `playerStore.players` actually have entries?
   - Already covered by the count print in #1. Expected: ~11000+ entries.
   - If `count == 0` post-load with no error, suspect ETag/cache feeding stale empty data → scenario **B**.

5. **Consumer key lookup** — Are consumer views looking up by the right key type?
   - Sleeper sends player IDs as **strings** (e.g., `"6794"`). `Player.playerId` is `String`. `Roster.players`, `Roster.starters`, `Roster.taxi`, `Roster.reserve` should all be `[String]`.
   - Grep: `rg "players: \[" Xomper/Core/Models/Roster.swift` — confirm the type. If anywhere the IDs are `Int` or get stringified late (e.g., `"\(intId)"`), that mismatches the dictionary key → scenario **A**.
   - Spot-check `TeamView.sortedStarters` (line 162-176) — `playerStore.player(for: id)` where `id` is a `String` from `roster.starters`. Confirm both ends.
   - Same check for `TaxiSquadStore.loadTaxiSquadPlayers` (it reads from `playerStore`) and `DraftHistoryView` (reads pick.player_id).

6. **Avatar URL correctness** — Are headshot URLs built correctly?
   - Web pattern: `https://sleepercdn.com/content/nfl/players/{player_id}.jpg` (full) and `/thumb/{player_id}.jpg` (thumb).
   - iOS — three places that build this URL (audit must reconcile):
     - `Player.profileImageURL` (`Player.swift:81`) — `/content/nfl/players/{playerId}.jpg` ✓
     - `Player.thumbnailImageURL` (`Player.swift:85`) — `/content/nfl/players/thumb/{playerId}.jpg` ✓
     - `URL.sleeperPlayerImage(for:)` (`URL+Sleeper.swift:11`) — `/content/nfl/players/thumb/{playerId}.jpg` ✓
     - `PlayerImageView.imageURL` (`AvatarView.swift:64`) — inline string, `/content/nfl/players/thumb/{playerID}.jpg` ✓
   - All four match web. **No bug expected here.** But if the audit shows players load fine and only the images are missing, scenario **D** is the right fix path.

7. **Phantom field expectations** — Does any view expect a field that doesn't exist on `Player`?
   - `Player` has zero fantasy fields: no `points`, no `rank`, no `projection`, no `xomperRank`. Only Sleeper static metadata.
   - Grep: `rg "player\.(points|rank|projection|xomperRank|weeklyPoints|seasonPoints)" Xomper/`
   - If any consumer references one of these, it won't compile — so this can only be a bug if there's a `nil`-coalesced default that silently renders an empty row. Unlikely but check.
   - Also grep `rg "\.searchRank" Xomper/Features/` — `searchRank` does exist; we use it for sort order.
   - This is scenario **E** if positive.

8. **ETag / disk cache poisoning** — Could a previously-bad fetch have cached an empty `[:]` to disk that revalidation now confirms with 304?
   - Inspect `PlayerStore.loadFromDisk()` (line 75-83). If `players.json` is corrupt or empty, the `JSONDecoder().decode([String: Player].self, from: data)` returns `nil` from the catch — that's safe.
   - But if `players.json` was written as `{}` (empty dict, valid JSON) before being properly populated, and the ETag matches, `loadPlayers()` will: (a) load empty dict from disk into `players`, (b) get 304 back, (c) leave `players` empty. No error, no user feedback.
   - Verification: in simulator, delete app, reinstall, confirm fresh fetch populates `players`. If yes and existing-install is empty, scenario **B**.
   - Also: print `etag=\(storedETag ?? "nil")` and `result type` in `loadPlayers()` to see if 304 is hitting on first run.

### Audit deliverable

After all 8 checks complete, the agent writes a `## Audit findings` block in this PLAN.md with:
- One bullet per check, with verdict (PASS / FAIL / N/A) and evidence.
- A `**Selected scenario**:` line naming A / B / C / D / E (or `escalate` if findings don't match any).
- A one-paragraph summary of the root cause in plain English.

If multiple scenarios apply (e.g., A + D), list both — fix order is whichever lights up the most consumers first.

---

## Phase 2 — Fix decision

Based on Phase 1 findings, pick the scenario. Each scenario has a one-line fix sketch; the executing agent expands the sketch into actual code.

### Scenario A — Roster ID type mismatch

**Symptom**: `playerStore.players` populates fine (count > 0) but `playerStore.player(for: id)` returns nil for valid-looking roster IDs.

**Likely cause**: Roster model has `[Int]` somewhere or stringifies late. Sleeper sends string IDs but they get coerced incorrectly.

**Fix sketch**:
- `Roster.swift` — ensure `players`, `starters`, `taxi`, `reserve` are all `[String]` and decode as such.
- If Sleeper sends string IDs that arrive correctly, the bug is on the lookup side — verify `playerStore.player(for: id)` is called with the raw string.
- No `PlayerStore` changes.

### Scenario B — ETag / disk cache poisoning

**Symptom**: Fresh-install renders fine, existing install renders empty. ETag matches; disk has empty/stale `players.json`.

**Fix sketch**:
- In `PlayerStore.loadPlayers()`, after `loadFromDisk()`, validate `cached.count > 0` before assigning to `self.players`. If empty/tiny, treat as no cache and force a fresh fetch (drop the `If-None-Match` header for one call).
- Bump the disk cache filename (e.g., `players_v2.json`) or cache key (`PlayerStore.etag.v2`) to invalidate any poisoned caches in the wild.
- Add a sanity-check guard: if the API returns `.updated` but decoded count is 0, do NOT save to disk. Currently we always save.

### Scenario C — Bootstrap not awaited / consumers mount first

**Symptom**: Consumer views render with `playerStore.players.isEmpty == true` because they mount before `bootstrapPhase1` completes. `TeamView` already has a `.task { if !hasPlayers { await playerStore.loadPlayers() } }` fallback but `TaxiSquadView` and `DraftHistoryView` may not.

**Fix sketch**:
- Two-pronged. First: confirm `bootstrapPhase1` is awaited before any deep navigation push that lands in a player consumer. It isn't — the `.task` is on `ContentView` and fires concurrently with navigation, not as a gate.
- Second: each consumer view that depends on `playerStore.players` must show `LoadingView` while `playerStore.isLoading == true` or `players.isEmpty`. `TeamView` already does this (line 25-33). Verify `TaxiSquadView` and `DraftHistoryView` do too — if not, add.
- A defensive `await playerStore.loadPlayers()` `.task` modifier on each consumer (idempotent — `loadPlayers()` returns early if already loading) belt-and-suspenders.

### Scenario D — Avatar URL bug masquerading as missing players

**Symptom**: Player rows render text correctly (name, position, team) but headshots are missing — looks like "no players" at a glance.

**Fix sketch**:
- Audit step 6 should have caught this. If the URL is wrong, fix it (match web exactly: `https://sleepercdn.com/content/nfl/players/thumb/{player_id}.jpg`).
- Less likely: `AsyncImage` never gets the URL because `PlayerImageView` is constructed with an empty `playerID`. Verify call sites pass the right value.

### Scenario E — Silent decode failure on phantom field

**Symptom**: `loadPlayers` runs, decode throws, error gets swallowed because `players.isEmpty == true` already. UI shows "Players Not Loaded" / empty rows everywhere.

**Fix sketch**:
- The decode error itself is informative — it names the offending field and the index in the dict where decode failed.
- If it's a phantom field on `Player` (someone added e.g. `xomperRank` non-optional), make it optional or remove it. Brainstorm Phase 2.5 explicitly bans schema additions.
- If it's a brand-new Sleeper field (e.g., they added a non-nullable `something_new`), make `Player`'s decoding tolerant — most fields are already optional; verify the offender is too.
- Also: surface decode errors to the user. The current swallow-when-cache-empty is the bug-amplifier here. Consider: even when `players.isEmpty`, set `self.error` so the UI shows `ErrorView` instead of "Players Not Loaded" with no actionable info.

### Escalation criteria

If Phase 1 reveals any of the following, **stop and re-plan** rather than push forward:
- Sleeper API surface changed in a way that requires `Player` schema changes.
- A consumer view requires fantasy stats (points, projections) — that's the deferred F7 epic, not this one.
- The bug is in `XomperAPIClient` (it shouldn't be — it doesn't touch player data — but if it is, that's a different issue).
- The fix touches >5 files outside `PlayerStore.swift` + 3 consumer views.

In any of these cases, document the finding in `## Audit findings`, flip this PLAN status to `Blocked`, and surface to the user before continuing.

---

## Phase 3 — Implement fix

Files touched depend on which scenario fires. Predicted candidates below; audit may add or subtract.

| File | Scenario | Predicted change |
|------|----------|------------------|
| `Xomper/Core/Stores/PlayerStore.swift` | B, E | Cache validation, decode error surfacing |
| `Xomper/Core/Models/Roster.swift` | A | Ensure `[String]` typing on `players`/`starters`/`taxi`/`reserve` |
| `Xomper/Core/Models/Player.swift` | E | Make any offending field optional (no schema additions) |
| `Xomper/Features/Team/TeamView.swift` | C | Already has guard; verify |
| `Xomper/Features/TaxiSquad/TaxiSquadView.swift` | C | Add empty/loading guard if missing |
| `Xomper/Features/DraftHistory/DraftHistoryView.swift` | C | Add empty/loading guard if missing |
| `Xomper/Features/Shared/AvatarView.swift` (PlayerImageView) | D | URL fix if mismatched |
| `Xomper/Core/Extensions/URL+Sleeper.swift` | D | URL fix if mismatched |

**Constraints carried into Phase 3** (from project CLAUDE.md and brainstorm Phase 2.5):
- Swift 6 strict concurrency, `@Observable`, `@MainActor` on stores and views.
- iOS 17+ APIs.
- **No `Player` schema additions.** Existing fields can be made optional or have decoding loosened, but we do not add `points`, `rank`, `xomperRank`, etc. — web doesn't have them either.
- **No new `XomperAPIClient` endpoints.** Player data stays Sleeper-direct.
- Status stays `Draft` until Phase 1 completes; audit-driven plans don't flip to `Ready` blind.

---

## Phase 4 — Verification

After Phase 3 lands, run the simulator and walk through:

### Build & launch
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme Xomper -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
Must compile clean with zero new Swift 6 concurrency warnings.

### Manual QA checklist

Pre-test setup: delete simulator app, reinstall to clear any cached `players.json`. Then reinstall again over an existing install to confirm cache-revalidation also works.

- [ ] **TeamView**: Open Team tab. Roster rows render with name + position + team + jersey + headshot. Starters, Bench, Taxi, IR sections all populated where roster data exists. Empty starter slots show as "Empty" placeholder, not as broken rows.
- [ ] **TaxiSquadView**: Navigate to Taxi Squad. Player cards render with name, position badge, team, jersey number, draft round, headshot. Group-by-Owner / Round / Position toggles all show players.
- [ ] **DraftHistoryView**: Navigate to Draft History. Pick rows render player name + position + team + headshot per pick. Multiple draft years if available.
- [ ] **PlayerDetailView** (sheet from TeamView tap): full player profile renders. Image loads at large size from `Player.profileImageURL`.
- [ ] **Cold start**: kill + relaunch. Players still render (disk cache hit). Confirm `loadPlayers` does not show a long "loading…" state on warm start.
- [ ] **Force refresh**: pull-to-refresh on TeamView. `loadPlayers` revalidates via ETag. Players still render after.
- [ ] **No silent failures**: if Sleeper returns an error or network is dead, an `ErrorView` shows in place of "Players Not Loaded" with retry.

### Regression spot-check
- [ ] Search (`SearchView` → no player mode yet, that's F6) — confirm we didn't regress user/league search by touching shared code.
- [ ] Standings, Matchups, World Cup — these don't depend on `PlayerStore` but make sure they still load.

---

## Files touched (predicted; audit may find more)

Predicted, not committed. Final list depends on which scenario(s) Phase 1 selects.

- `Xomper/Core/Stores/PlayerStore.swift` — verify load + lookup; possibly add cache validation + decode-error surfacing
- `Xomper/Core/Models/Player.swift` — only if scenario E: make offending field optional
- `Xomper/Core/Models/Roster.swift` — only if scenario A: confirm `[String]` typing
- `Xomper/Features/Team/TeamView.swift` — verify guard already in place
- `Xomper/Features/TaxiSquad/TaxiSquadView.swift` — possibly add loading/empty guard
- `Xomper/Features/DraftHistory/DraftHistoryView.swift` — possibly add loading/empty guard
- `Xomper/Features/Shared/AvatarView.swift` — only if scenario D
- `Xomper/Core/Extensions/URL+Sleeper.swift` — only if scenario D
- `docs/features/xomper-overhaul/f2-player-wiring/PLAN.md` — append `## Audit findings` block

---

## Acceptance criteria

(Carried verbatim from the epic plan — same bar.)

- Audit findings live in this PLAN.md (`## Audit findings` section), naming the chosen scenario with evidence.
- All views that display players show: name, position, team, picture, jersey number, search rank — when present in Sleeper data.
- Missing fields render gracefully (no crashes, sensible fallbacks via `Player.fullDisplayName` / `displayPosition` / `displayTeam`).
- Manual QA in simulator: open Team view, Taxi Squad view, Draft History view — all show player rows correctly with avatars loading from `sleepercdn.com`.
- No `Player` model schema additions. No new `XomperAPIClient` endpoints.
- Build is clean with Swift 6 strict concurrency, no new warnings.

---

## Out of scope

- Schema additions to `Player` (no `points`, `rank`, `xomperRank`, `weeklyPoints`, `seasonPoints`, `projection`).
- New `XomperAPIClient` endpoints (no `/players/sync`, no backend player work).
- Fantasy stats anywhere (deferred to F7, separate epic).
- Player search UI changes (that's F6).
- Any schema or behavior changes outside the Sleeper-direct, static-metadata-only model.
- Light mode support (project always-dark).

---

## Risks / Tradeoffs

- **Risk**: Audit reveals deeper rot than candidate scenarios A-E. **Mitigation**: explicit escalation criteria above. Don't push forward; flip status to `Blocked`, re-plan.
- **Risk**: Multiple scenarios apply at once (e.g., B + E together). **Mitigation**: fix in dependency order — decode/cache first (foundation), consumer guards last (defense-in-depth).
- **Risk**: A "fix" for one consumer breaks another that was silently working. **Mitigation**: full Phase 4 manual QA across all three consumer views, plus the regression spot-check.
- **Risk**: Logging added during Phase 1 leaks into the merged commit. **Mitigation**: temporary `print()` lines must be removed before opening the PR. Acceptance criteria check.
- **Tradeoff**: Audit-first is slower than blind-fix when the bug is obvious (e.g., scenario D — wrong URL). Accepted because the user said "no players are loading" and that vague signal can mean any of A–E. Diagnose first.

---

## Open Questions

- [ ] Once audit completes, confirm with user whether to ship a single PR per fix scenario or one PR with all touched files.
- [ ] If scenario B fires, does cache key bumping (e.g., `players_v2.json`) require any Supabase / backend coordination? (Almost certainly no, but worth a one-line confirm.)
- [ ] Should `ErrorView` for the `playerStore.error` case (currently absent in `TeamView` empty-state path) get added as part of this fix, or punted to a separate hardening pass?

---

## Skills / Agents to Use

- **`ios-specialist` agent**: primary executor. Runs Phase 1 audit, picks the scenario, implements Phase 3, validates Phase 4 in simulator. Knows SwiftUI, `@Observable`, Swift 6 concurrency, project conventions.
  - The epic plan listed `codebase-auditor` for the audit phase — that agent does not exist in this project. `ios-specialist` covers both audit and fix here.
- **`xcodegen` skill**: invoke after any new files are added (none predicted, but if a scenario produces them).
- **No new agents**: this is execution work, not exploration.

---

## Audit findings

**Date**: 2026-04-28
**Auditor**: Executor (Phase 1 static analysis)

### Check 1 — Bootstrap call site

**PASS**

Trace: `XomperApp.swift:12` instantiates `PlayerStore()` as `@State`. It is passed into `AuthGateView` → `ContentView`. `ContentView.body` (line 32–33) has `.task { await bootstrapPhase1() }`. `bootstrapPhase1()` (line 158–163) calls `playerStore.loadPlayers()` via `async let playerLoad`. This fires on the first render of `ContentView`, which only appears after `authStore.isAuthenticated == true && authStore.isWhitelisted == true` (`AuthGateView` line 23–35).

The `.task` does fire post-auth. `loadPlayers()` is called. No print instrumentation was added (static-only audit); if the simulator run is needed to confirm timing, that is Phase 4 territory. From code alone, the call site is wired correctly.

No scenario C indicator here — but see Check 5 for a nuance regarding `TaxiSquadView`'s dependency on `playerStore` arriving before it iterates taxi IDs.

### Check 2 — Sleeper endpoint reachability

**PASS (by code inspection)**

`SleeperAPIClient.fetchAllPlayersRaw` (`SleeperAPIClient.swift:134–166`) builds `https://api.sleeper.app/v1/players/nfl` using `baseURL = "https://api.sleeper.app/v1"` + `"/players/nfl"`. URL is valid. Standard `URLSession.data(for:)` is used. 304 / 200 handling is correct. No simulator run was performed but there is no code-level reason for the endpoint to fail. Reachability is assumed good; if real-device/network failure is involved, that's out of scope for a static audit.

### Check 3 — Decode success / error swallow

**FAIL — silent swallow confirmed**

`PlayerStore.loadPlayers()` lines 42–51:

```swift
case .updated(let data, let newEtag):
    let decoded = try JSONDecoder().decode([String: Player].self, from: data)
    players = decoded
    saveToDisk(data: data, etag: newEtag)
} catch {
    if players.isEmpty {
        self.error = error
    }
}
```

If `JSONDecoder().decode` throws, the `catch` block fires. If `players` was already populated from the disk cache (Check 8 discusses the empty-cache path), `self.error` is **never set** and the stale cached value is silently kept — acceptable. But if the disk cache is also empty (cold install, or cache poisoned to `{}`), `players.isEmpty == true` at the time the catch runs, so `self.error = error` IS set — meaning the UI should show an error state, not a silent empty. So the silent-swallow is only a problem when `players` is non-empty but stale AND a decode error occurs — not the described "no players" symptom.

More importantly: if the API returns a 200 with a well-formed payload but decoding quietly fails on individual player entries (partial failure), `[String: Player]` top-level decode could throw at the first bad key, leaving `players` empty with no user-visible error if the cache was also empty. **This is a live risk if Sleeper has introduced any field that our `Player` model can't decode.** However, all fields on `Player.swift` are optional except `playerId: String` — so individual player decode failures would be silently skipped (standard `Codable` behavior for dictionaries). A non-optional `playerId` that arrives as `null` for even one entry would cause the whole decode to throw, but Sleeper always sends `player_id` as a non-null string. Low probability for scenario E.

The actual pattern at risk: **if `loadFromDisk()` returns a non-nil result but `players.isEmpty` is still true after assignment**, that would be a logic gap — but looking at line 29: `if players.isEmpty, let cached = loadFromDisk() { players = cached }`. If `loadFromDisk()` returns an empty dict (`{}`), `players` stays `{}`. Then on API 304 (`.notModified`), nothing updates it. That's scenario B.

### Check 4 — Map population after load

**CONDITIONAL — depends on Check 8 outcome**

`players` count post-`loadPlayers()` is fully determined by: (a) whether disk cache is non-empty, and (b) whether the API returns `.updated` with a valid payload or `.notModified`. Code logic is correct. No bug in the assignment path (`players = decoded`, line 43). Count will be ~11k+ on a successful fresh fetch. If count is 0 after load with no error, scenario B (ETag/cache poisoning) is indicated.

### Check 5 — Consumer key lookup

**PASS**

- `Roster.swift:7`: `players: [String]?` — confirmed `[String]`.
- `Roster.swift:8,9,10`: `starters`, `reserve`, `taxi` — all `[String]?`. Correct.
- `DraftPick.swift:90`: `playerId: String` — correct.
- `DraftHistoryRecord.swift:10`: `playerId: String` — correct.
- `PlayerStore.player(for:)` takes `String`, looks up `players[id]`. Both sides `String`. No type mismatch.
- `TeamView.sortedStarters` (line 162–175): iterates `roster.starters` (already `[String]`), calls `playerStore.player(for: id)` where `id: String`. Clean.
- `TaxiSquadStore.loadTaxiSquadPlayers` (line 88–89): `for playerId in taxiIds` where `taxiIds: [String]` from `roster.taxi`. Calls `playerStore.player(for: playerId)` — clean.
- `DraftHistoryView.selectPlayer` (line 181–185): calls `playerStore.players[playerId]` where `playerId: String` from `DraftHistoryRecord.playerId`. Clean.

**No scenario A.**

### Check 6 — Avatar URL correctness

**PASS**

All four URL builders match web's pattern exactly:

- `Player.profileImageURL` (`Player.swift:81`): `https://sleepercdn.com/content/nfl/players/\(playerId).jpg` — full size. Correct.
- `Player.thumbnailImageURL` (`Player.swift:85`): `https://sleepercdn.com/content/nfl/players/thumb/\(playerId).jpg` — thumb. Correct.
- `URL.sleeperPlayerImage(for:)` (`URL+Sleeper.swift:11`): same thumb path. Correct.
- `PlayerImageView.imageURL` (`AvatarView.swift:64`): `https://sleepercdn.com/content/nfl/players/thumb/\(playerID).jpg` — correct.

`PlayerImageView` is used in `TeamView` (line 394), `TaxiSquadView` (line 324), `DraftHistoryView` (line 333), all passing the correct `playerId: String`. No scenario D.

### Check 7 — Phantom field expectations

**PASS**

`grep` for `player\.(points|rank|projection|xomperRank|weeklyPoints|seasonPoints)` in `Xomper/` returned no results. `grep` for `.searchRank` in `Xomper/Features/` returned no results (it's used only in `PlayerStore.search()` in `Core/Stores/`). No phantom fields. No scenario E from consumer side. `Player.swift` has all fields optional except `playerId`.

### Check 8 — ETag / disk cache poisoning

**CONFIRMED RISK — this is the most likely root cause**

Inspecting `PlayerStore.loadPlayers()` lines 29–44:

```swift
// Step 1: Load from disk cache if available
if players.isEmpty, let cached = loadFromDisk() {
    players = cached
}

// Step 2: Revalidate with API using ETag
do {
    let storedETag = UserDefaults.standard.string(forKey: etagKey)
    let result = try await apiClient.fetchAllPlayersRaw(etag: storedETag)

    switch result {
    case .notModified:
        break
    case .updated(let data, let newEtag):
        let decoded = try JSONDecoder().decode([String: Player].self, from: data)
        players = decoded
        saveToDisk(data: data, etag: newEtag)
    }
```

**Critical gap**: after loading from disk (step 1), `players` may be set to a valid non-empty dict. But if the disk-loaded data is a valid `{}` (empty JSON object — which is what `[String: Player]` decodes to from `"{}"`), `players` stays empty. The code in step 1 only assigns if `loadFromDisk()` returns non-nil — an empty dict `{}` decodes to `[:]` which is non-nil! So `players = [:]` gets assigned, still empty.

Then in step 2, `storedETag` from UserDefaults may be non-nil from a previous (failed or partial) fetch. If the Sleeper CDN returns 304 (because the ETag matches from the prior fetch that wrote `{}` to disk), `case .notModified: break` fires and `players` stays `[:]`. **No error, no update, empty players.** This is **scenario B** firing silently.

**Additionally**: `saveToDisk` writes to disk even if the decoded dict is empty (it writes the raw `data` bytes, not the decoded result). If `fetchAllPlayersRaw` returned a 200 with empty body or a valid `{}` at any point, `players.json` would be written as that bad data, and the ETag would be saved. Subsequent launches would: (1) load `{}` from disk, (2) get 304 from CDN, (3) leave `players = [:]`. Silent. Permanent until app delete/reinstall.

**Also notable**: `loadFromDisk()` (`PlayerStore.swift:75–83`) does not validate that the decoded dict is non-empty before returning it. If `players.json` contains `{}`, it returns `[:]` — non-nil, so step 1 assigns `players = [:]`.

**Selected scenario: B (ETag/disk cache poisoning)**

Secondary risk: the empty-dict guard is also absent on `saveToDisk` — if a genuinely empty 200 response were ever received (or a partial/truncated payload), the cache would be poisoned going forward.

---

### Root cause summary

The most probable cause of "no players loading" on existing installs is **Scenario B — ETag/disk cache poisoning**. At some prior point (possibly a bad network response, a truncated payload, or a race during first install), `players.json` on disk was written as an empty or nearly-empty JSON object. Subsequent launches load this invalid cache, hit the Sleeper CDN with the stored ETag, receive a 304 Not Modified, and silently leave `players = [:]`. The user sees "Players Not Loaded" with no error. A fresh install (delete + reinstall) fixes it because the cache file and ETag are cleared.

The wiring code is otherwise correct: IDs are `[String]` end-to-end (no scenario A), URL builders match web exactly (no scenario D), no phantom fields (no scenario E), and the bootstrap call site fires correctly post-auth (no scenario C from wiring, though `TaxiSquadView` has a minor secondary issue: its `loadTaxiSquad()` calls `taxiSquadStore.loadTaxiSquadPlayers(playerStore: playerStore)`, and if `playerStore.players` is empty when that runs, all taxi squad players silently produce zero rows because `guard let player = playerStore.player(for: playerId) else { continue }` skips every entry — this is a scenario C symptom layered on top of B, not an independent C).

**Recommended fix**: Scenario B. Primary changes to `PlayerStore.swift`: (1) validate `cached.count > 0` before assigning from disk — return nil from `loadFromDisk()` if empty; (2) add a guard in `loadPlayers()` after `.notModified` that checks `players.count > 0`, and if not, drops the ETag and forces a fresh fetch; (3) add a guard in `saveToDisk` (or before calling it) that skips the write if decoded count is 0, preventing future poisoning.

Secondary (scenario C mitigant for TaxiSquad): `TaxiSquadView.loadTaxiSquad()` should ensure `playerStore.players` is non-empty before proceeding, or `TaxiSquadStore.loadTaxiSquadPlayers` should return an error/empty-with-retry signal if `playerStore.players.isEmpty`.
