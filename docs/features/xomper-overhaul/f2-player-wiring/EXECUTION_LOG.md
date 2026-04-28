# Execution Log: F2 — Player Wiring Audit & Fix

## 2026-04-28 — Phase 1: Audit (all 8 checks)

- **Action**: Static analysis of all 8 audit checklist items. No production code changes.
- **Files read**: `PlayerStore.swift`, `Player.swift`, `Roster.swift`, `XomperApp.swift`, `AuthGateView.swift`, `ContentView.swift`, `SleeperAPIClient.swift`, `TeamView.swift`, `TaxiSquadView.swift`, `TaxiSquadStore.swift`, `DraftHistoryView.swift`, `DraftHistory.swift`, `Draft.swift`, `AvatarView.swift`, `URL+Sleeper.swift`
- **Files changed**: `PLAN.md` (appended `## Audit findings` section)
- **Decisions**: No simulator run performed — static analysis was sufficient to identify root cause. All 8 checks resolved from code inspection alone.
- **Result**: Phase 1 complete. Selected scenario: **B (ETag/disk cache poisoning)**. Awaiting user approval before proceeding to Phase 3.

### Findings summary

| Check | Result | Scenario |
|-------|--------|----------|
| 1. Bootstrap call site | PASS — `loadPlayers()` fires via `ContentView.bootstrapPhase1()` post-auth | — |
| 2. Endpoint reachability | PASS — URL correct, `URLSession` standard | — |
| 3. Decode error handling | FAIL — silent swallow confirmed when cache is also empty; but `Player` fields are all optional so full decode failure is low risk | E (low) |
| 4. Map population | CONDITIONAL — correct if fresh fetch succeeds; 0 if scenario B fires | B |
| 5. Consumer key lookup | PASS — all `[String]` end-to-end, no type mismatch | A cleared |
| 6. Avatar URL correctness | PASS — all 4 builders match web exactly | D cleared |
| 7. Phantom fields | PASS — no phantom field usage found | E cleared |
| 8. ETag/disk cache poisoning | FAIL — empty dict `{}` from disk + 304 from CDN leaves `players = [:]` silently; `saveToDisk` has no empty-guard | **B confirmed** |

---

## 2026-04-28 — Phase 3: Implementation

- **Action**: Implemented Scenario B fix across two files. No schema changes, no new files.
- **Files changed**:
  - `Xomper/Core/Stores/PlayerStore.swift`
  - `Xomper/Features/TaxiSquad/TaxiSquadView.swift`
- **Decisions**:
  - Extracted the fetch+apply logic from `loadPlayers()` into a private `fetchAndApplyPlayers()` method. This keeps the recursive retry (ETag clear → re-fetch) clean and avoids inlining a recursive call inside `loadPlayers` itself.
  - `PlayerStoreError.emptyPayload` added as a module-level enum — lightweight, no new files needed, does not conflict with xcodegen (no new source files).
  - `loadFromDisk()` now returns `nil` for empty dicts rather than `[:]` — single-line guard, backward-compatible.
  - `TaxiSquadView.loadTaxiSquad()` adds a preflight `if playerStore.players.isEmpty { await playerStore.loadPlayers() }` before invoking `taxiSquadStore.loadTaxiSquadPlayers`. Pattern matches `TeamView.task` defensive load.
  - `saveToDisk` is only called from the `decoded.isEmpty == false` branch in `fetchAndApplyPlayers`, so the empty-guard on writes is implicit.
- **Build result**: `** BUILD SUCCEEDED **` — zero errors, zero warnings.

### Manual test procedure (Phase 4 — for human verification)

Automated simulator test not run (no XCTest harness for this path). Manual steps to verify poisoned-cache fix:

1. **Poisoned-cache test**:
   - Launch simulator (iPhone 17 Pro).
   - Install and run app once (fresh install creates `players.json` with real data).
   - Locate the app container: `xcrun simctl get_app_container booted com.Xomware.Xomper data`.
   - Navigate to `Library/Caches/` and overwrite `players.json` with `{}`.
   - Relaunch app. With old code: players empty, no error. With new code: `loadFromDisk()` returns `nil` (empty dict), no ETag match possible since disk is empty so cache was poisoned → ETag may still be set in UserDefaults. On `.notModified`, the new guard fires, clears ETag, retries fresh → players load.
   - Alternatively: set `players.json` to `{}` AND ensure `PlayerStore.etag` is set in UserDefaults (simulating a past poisoned write). This exercises the full unpoison path.

2. **Cold-start regression**: delete + reinstall. Confirm fresh fetch populates players.

3. **Warm-start regression**: kill + relaunch with valid `players.json`. 304 path should still work (players non-empty after disk load, `.notModified` break fires normally).

- **Result**: Phase 3 complete. Plan status set to Done.
