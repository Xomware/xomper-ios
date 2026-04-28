# Plan: F3 — League Nav Tray + Profile-on-Tray-Header

**Status**: Done
**Created**: 2026-04-28
**Last updated**: 2026-04-28
**Scope**: L (largest in epic)
**Parent epic**: `docs/features/xomper-overhaul/PLAN.md`

## Goal

Replace the three-tab `TabView` shell (`Home / League / Profile`) with a Xomify-style slide-in left drawer. The drawer is the single place to navigate the app: it owns a profile-card header (tap to push profile), grouped destination sections (Compete / History / Roster / Meta) and a pinned Settings footer. `HomeView` and the `AppTab.profile` tab go away. The `LeagueDashboardView` internal segmented picker is dissolved — each former segment becomes a first-class tray destination so the tray drives all top-level navigation. iPhone and iPad share the same shell; no `NavigationSplitView`, no sheet, no tab bar.

## Approach

Build a new `Shell/` feature module that hosts a `MainShell` view: header bar + `NavigationStack` rooted on a single `currentDestination`, with `DrawerView` and `DrawerScrim` overlaid in a `ZStack`. State is owned by a new `@Observable @MainActor NavigationStore` (drawer open/closed + selected destination). `AppRouter` continues to own the `NavigationPath` for downstream pushes (team detail, user profile, matchup history, etc.) — drawer-driven destination changes pop the stack to root.

Mechanics ported verbatim from Xomify (see `/Users/dom/code/xomify-ios/Xomify-iOS/Views/Shell/`): `min(screenWidth * 0.82, 320)` width, `.easeInOut(duration: 0.25)` offset animation, `Color.black.opacity(0.45)` scrim, edge-drag (start `<30pt`, drag `>60pt`, mostly horizontal) and avatar-tap to open. Tray rows extracted into reusable `TraySection` + `TrayItem` components. Theme tokens reused from `XomperColors` — Midnight Emerald palette covers the drawer cleanly.

## Affected files

| File | Change | Why |
|------|--------|-----|
| `Xomper/App/ContentView.swift` | Strip `TabView`. Replace with `MainShell()`. Move `bootstrapPhase1`/`bootstrapPhase2` `.task` modifiers to `MainShell` verbatim. | Shell is no longer tabbed; ContentView becomes thin pass-through. |
| `Xomper/App/XomperApp.swift` | No change to env-injection bag. | Bootstrap shape preserved. |
| `Xomper/Navigation/AppTab.swift` | **Delete file.** | No more tabs. |
| `Xomper/Navigation/AppRouter.swift` | Remove `selectedTab` and `switchTab(_:)`. Keep `path`, `navigate(to:)`, `popToRoot()`. | Tray state lives in `NavigationStore`; `AppRouter` owns only nav path. |
| `Xomper/Features/League/LeagueDashboardView.swift` | **Delete file.** Sub-views (`StandingsView`, `MatchupsView`, etc.) become tray destinations directly. | Tray drives top-level destination; segmented picker redundant. |
| `Xomper/Features/Home/HomeView.swift` | **Delete file.** Default tray destination is `.standings`. | Home was a redirector; tray makes it unnecessary. |
| `Xomper/Features/Profile/MyProfileView.swift` | Remove `.gearshape` toolbar item (Settings now in tray footer). Reroute league-row taps from `router.switchTab(.league)` to `navStore.select(.standings)`. | Settings moved out; profile no longer launches it. |

## New files

All under `Xomper/Features/Shell/`:

- `MainShell.swift` — root view: ZStack of bg + header bar + `NavigationStack { destinationRoot }` + `DrawerScrim` + `DrawerView`. Hosts edge-drag gesture. Owns `@State NavigationStore` + `@State AppRouter`. Hosts `.task` bootstraps moved from `ContentView`.
- `NavigationStore.swift` — `@Observable @MainActor final class` with `var isDrawerOpen`, `var currentDestination`, `openDrawer()`, `closeDrawer()`, `select(_:)`.
- `TrayDestination.swift` — enum: `standings`, `matchups`, `playoffs`, `draftHistory`, `matchupHistory`, `worldCup`, `myTeam`, `taxiSquad`, `rules`, `profile`, `settings`. `Hashable`. Computed `title` + `systemImage`.
- `TraySection.swift` — struct: `title: String?`, `entries: [TrayDestination]`.
- `TrayItem.swift` — reusable row view (icon + label + selected state + chevron).
- `DrawerView.swift` — left panel: profile card → `ScrollView` of `TraySection` blocks → Divider → pinned Settings.
- `DrawerScrim.swift` — full-screen `Color.black.opacity(0.45)` overlay; tap closes; `.transition(.opacity)`.
- `HeaderBar.swift` — top bar: leading avatar (tap → open drawer), centered "Xomper" wordmark, trailing magnifying-glass button (→ `.search`).
- `TrayProfileCard.swift` — gradient header card (avatar + name + email + chevron). Tap → `navStore.select(.profile)`.

## Data flow / state

```
XomperApp
  └─ AuthGateView
       └─ ContentView (thin pass-through)
            └─ MainShell                              ← owns @State NavigationStore + AppRouter
                  ├─ XomperColors.bgDark.ignoresSafeArea()
                  ├─ VStack
                  │    ├─ HeaderBar(navStore, router)
                  │    └─ NavigationStack(path: $router.path)
                  │         └─ destinationRoot(navStore.currentDestination)
                  │              .navigationDestination(for: AppRoute.self) { … push views }
                  ├─ DrawerScrim(navStore)
                  └─ DrawerView(navStore, profile data)
```

State ownership:
- **`NavigationStore`**: drawer open/closed + current top-level destination. Single source of truth for tray.
- **`AppRouter`**: pushes/pops within `NavigationStack`. Existing call sites (`router.navigate(to: .teamDetail(rosterId:))`) keep working.
- **Coordination**: `NavigationStore.select(_:)` calls `router.popToRoot()` → sets `currentDestination` → `closeDrawer()`. All inside one `withAnimation(.easeInOut(duration: 0.25))`.

## Implementation steps

Each step is independently buildable in the simulator.

1. **Create `Shell/` directory + skeleton files.** Empty `NavigationStore`, `TrayDestination`, `TraySection`, `TrayItem`, `MainShell`, `DrawerView`, `DrawerScrim`, `HeaderBar`, `TrayProfileCard`. xcodegen picks them up. Build green with empty bodies.
2. **Implement `TrayDestination`** with all 11 cases + `title`, `systemImage`, `Hashable`.
3. **Implement `NavigationStore`.** `@Observable @MainActor`. Defaults: `isDrawerOpen = false`, `currentDestination = .standings`. `select(_:)` takes optional `AppRouter` and calls `popToRoot()` before changing destination. Wrap in `withAnimation(.easeInOut(duration: 0.25))`.
4. **Implement `TrayItem` view** per visual spec below. Use `XomperColors` + `XomperTheme.Spacing` only.
5. **Implement `TrayProfileCard`** as `Button` with `AvatarView(.md)` + name + email + chevron, gradient bg `XomperColors.goldAccentGradient.opacity(0.25)` over `XomperColors.bgCard`.
6. **Implement `DrawerView`.** Sections: Compete = `[standings, matchups, playoffs]`, History = `[draftHistory, matchupHistory, worldCup]`, Roster = `[myTeam, taxiSquad]`, Meta = `[rules]`. Pinned footer = `[settings]`. Profile card above scroll. Width `min(UIScreen.main.bounds.width * 0.82, 320)`. Bg: vertical gradient `[bgDark, bgCard.opacity(0.85)]`. Trailing 1pt hairline `Color.white.opacity(0.06)`. Offset: `.offset(x: navStore.isDrawerOpen ? 0 : -drawerWidth)`. Internal close drag.
7. **Implement `DrawerScrim`** — `if navStore.isDrawerOpen` then `Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { navStore.closeDrawer() }.transition(.opacity)`.
8. **Implement `HeaderBar`.** 36pt avatar leading button → `openDrawer()`. Center: `Text("Xomper").font(.title3).fontWeight(.bold)` (text wordmark; banner asset polish later). Trailing: `Image(systemName: "magnifyingglass")` → `router.navigate(to: .search)`. Height 44, bg `XomperColors.bgDark`, horizontal padding `Spacing.sm`.
9. **Implement `MainShell`.** ZStack `.leading` alignment. Children: `XomperColors.bgDark.ignoresSafeArea()` → VStack(HeaderBar + `NavigationStack(path: $router.path)` containing destinationRoot + `.navigationDestination(for: AppRoute.self)`) → DrawerScrim → DrawerView. Edge-drag gesture (`DragGesture(minimumDistance: 12, coordinateSpace: .global)`): `startLocation.x < 30 && translation.width > 60 && abs(width) > abs(height) * 1.5 && !isDrawerOpen && router.path.count == 0`. `@State private var navStore = NavigationStore()`, `@State private var router = AppRouter()`.
10. **Move bootstrap tasks** from `ContentView` to `MainShell` verbatim, preserving `.task` and `.task(id: authStore.sleeperUserId)` modifiers.
11. **Implement `destinationRoot` switch** in `MainShell` — one case per `TrayDestination`. For `standings`, render `StandingsView(...)` directly. For `myTeam`, look up via `teamStore.myTeam`, fall back to `EmptyStateView`. Apply `.navigationTitle(currentDestination.title)` + `.toolbarColorScheme(.dark, for: .navigationBar)`.
12. **Drop `.gearshape` toolbar from `MyProfileView`** since Settings is in the tray footer.
13. **Rewire `ContentView`.** Replace body with `MainShell(authStore: …, leagueStore: …, …)`. Delete `tabContent(for:)`, `destinationView(for:)`, `bootstrapPhase1`, `bootstrapPhase2` from `ContentView` (they live in `MainShell` now).
14. **Delete `AppTab.swift`** and remove `selectedTab`/`switchTab(_:)` from `AppRouter`.
15. **Rewire `MyProfileView` league row taps.** Replace `router.switchTab(.league)` with `navStore.select(.standings)` after `leagueStore.switchToLeague(id:)`.
16. **Delete `HomeView.swift` and `LeagueDashboardView.swift`.** Verify all references gone.
17. **Audit `selectedTab` references.** Grep for any leftover `selectedTab` or `AppTab` references (push notifications, deep links). Specifically locate `PushNotificationManager` (referenced in `XomperApp.swift:21` and `ContentView.swift:150` — find file path and rewire). Replace with `navStore.select(...)`. Pass `navStore` to whatever singleton needs it (mirror Xomify's pattern of `NotificationsService.shared.navigationStore = navStore` set in `MainShell.task`).
18. **Build + simulator smoke test.** Build for `iPhone 17 Pro` and `iPad Pro 13" (M4)`. Verify edge-drag opens drawer, avatar-tap opens drawer, scrim-tap closes, drawer-row-tap navigates + closes. Verify each tray destination renders. Verify deep pushes (Standings → tap roster → `TeamView`).
19. **Accessibility pass.** `TrayItem` gets `.accessibilityLabel(entry.title)` + `.accessibilityAddTraits(isSelected ? .isSelected : [])`. Avatar button label "Open menu". Scrim label "Close menu".
20. **Mark plan Done** after build + simulator validation pass.

## View rendering spec

Concrete values — no improvising during execution.

**Drawer panel**
- Width: `min(UIScreen.main.bounds.width * 0.82, 320)`
- Background: vertical `LinearGradient([XomperColors.bgDark, XomperColors.bgCard.opacity(0.85)])`
- Trailing hairline: 1pt `Color.white.opacity(0.06)` overlay
- Offset animation: `.easeInOut(duration: 0.25)` on `.offset(x:)`

**Profile card** (`TrayProfileCard`)
- Padding: `.horizontal 14`, `.vertical 12`
- Corner radius: `XomperTheme.CornerRadius.xl` (16)
- Background: `XomperColors.goldAccentGradient.opacity(0.25)` over `XomperColors.bgCard`
- Border: 1pt `Color.white.opacity(0.12)` stroke
- Avatar: `XomperTheme.AvatarSize.md` (40pt)
- Name: `.headline`, `XomperColors.textPrimary`, `lineLimit(1)`
- Email: `.caption`, `XomperColors.textSecondary`, `lineLimit(1)`
- Chevron: `.footnote.weight(.semibold)`, `XomperColors.textMuted`

**TrayItem (row)**
- Padding: `.horizontal 14`, `.vertical 12`, `frame(minHeight: 44)`
- Corner radius: `XomperTheme.CornerRadius.lg` (12)
- Icon: `.body.weight(.semibold)`, frame width 26 — `XomperColors.championGold` unselected, `XomperColors.textPrimary` selected
- Label: `.body`, weight `.regular` (unselected) / `.semibold` (selected), color `XomperColors.textPrimary`
- Selected bg: `XomperColors.goldAccentGradient`
- Unselected bg: `Color.white.opacity(0.04)`
- Trailing chevron only when selected: `.footnote.weight(.bold)`, `XomperColors.textPrimary.opacity(0.85)`

**TraySection header**
- Optional title: `.caption.weight(.semibold)`, `XomperColors.textMuted`, uppercase
- Padding: `.horizontal 14`, `.top 12`, `.bottom 4`

**Edge-drag gesture (open)**
- `DragGesture(minimumDistance: 12, coordinateSpace: .global)`
- Trigger: `value.startLocation.x < 30 && value.translation.width > 60 && abs(width) > abs(height) * 1.5 && !isDrawerOpen && router.path.count == 0`

**Close drag (inside drawer)**
- `DragGesture(minimumDistance: 12)` on drawer panel
- Trigger: `value.translation.width < -60 && abs(width) > abs(height) * 1.5 && isDrawerOpen`

**Header bar**
- Height 44
- Background `XomperColors.bgDark`
- Avatar button: 36pt avatar inside 44pt hit target
- Wordmark: `Text("Xomper").font(.title3).fontWeight(.bold).foregroundStyle(XomperColors.textPrimary)`
- Search button: `Image(systemName: "magnifyingglass").foregroundStyle(XomperColors.championGold)` inside 44pt hit target

## Resolved open questions

1. **Delete `AppTab` vs. keep as placeholder** → **Delete the file.** `TrayDestination` is the new top-level taxonomy.
2. **What happens to `HomeView`** → **Delete.** Default tray destination is `.standings`.
3. **Edge-drag vs. NavigationStack swipe-to-pop** → **Coexist by gating on `router.path.count == 0`.** Edge-drag only opens drawer at root of stack; swipe-to-pop wins inside pushed views. Avatar tap always works.
4. **iPad layout** → **Same as iPhone, no `NavigationSplitView`.** Drawer caps at 320pt; remaining space behind scrim is acceptable per Xomify pattern.
5. **`LeagueDashboardView`'s segmented picker** → **Actively delete.** Each segment is a tray destination.
6. **Drawer-close behavior on selection** → **Drawer closes, destination shown immediately.** All in one `withAnimation` block.
7. **Bootstrap tasks** → **Move verbatim to `MainShell`.** `.task` semantics identical.
8. **Drawer background token** → **Reuse existing `XomperColors.bgDark`.** Inline gradient; no new token.

## Acceptance criteria

- Cold open lands on **Standings** (no `HomeView`, no `Home` tab).
- Tapping avatar in header opens drawer.
- Edge-drag from leading 30pt opens drawer when at root of nav stack.
- Edge-drag does NOT open drawer when `router.path.count > 0`.
- Scrim tap and leftward drawer drag both close drawer.
- Tapping a tray row navigates + closes drawer in one animation.
- Selected tray row shows gradient bg + bold label + chevron + white icon.
- Profile card shows user avatar + display name + email; tap pushes profile destination.
- `Settings` pinned to drawer footer below divider; tap navigates to `SettingsView`.
- `MyProfileView` no longer has `.gearshape` toolbar.
- `LeagueDashboardView`'s segmented picker gone; segments become tray destinations.
- Deep pushes still work (Standings → roster → TeamView).
- Bootstrap (`bootstrapPhase1`/`Phase2`) runs once per cold open and re-runs on `sleeperUserId` change.
- No `TabView`, no `AppTab`, no `selectedTab` references in codebase.
- Build clean with Swift 6 strict concurrency on iPhone 17 Pro + iPad simulator.
- Always-dark mode preserved.

## Test plan

Simulator-first.

**iPhone (`iPhone 17 Pro`)**
1. Cold launch → lands on Standings.
2. Edge-drag from leftmost 20pt rightward 80pt → drawer opens.
3. Tap avatar → drawer opens.
4. Tap scrim → drawer closes.
5. Tap "Matchups" row → drawer closes, MatchupsView renders.
6. From Standings, tap roster → TeamView pushes. Edge-drag → swipe-to-pop fires (drawer does NOT open). Pop back → edge-drag opens drawer.
7. Open drawer → tap profile card → MyProfileView renders.
8. Open drawer → tap Settings → SettingsView renders.
9. Sign out → AuthGate → re-login → lands on Standings, drawer closed.

**iPad (`iPad Pro 13" (M4)`)**
10. Cold launch → Standings, drawer closed.
11. Drawer width caps at 320pt.
12. Avatar tap opens drawer; scrim full screen.
13. Rotate to landscape → drawer still 320pt, functional.

**Cross-cutting**
14. Push notification routing → `navStore.select(...)` invoked, not `router.switchTab(...)`.
15. VoiceOver: avatar reads "Open menu, button"; scrim "Close menu, button"; rows announce selected state.
16. Dynamic Type AX5 → tray labels reflow without truncation.

## Risks & mitigations

- **Edge-drag fights swipe-to-pop.** Mitigated by `path.count == 0` gate.
- **Push notification deep-link breakage.** Step 17 audits + rewires. Search-and-replace `selectedTab`.
- **Bootstrap ordering regression.** Bootstrap moves verbatim; `.task` semantics identical. Test by sign-out and back in.
- **iPad cramping.** Accepted per Xomify pattern. Permanent-drawer fallback is future work, not blocking.
- **`StandingsView` not designed as top-level destination.** Step 11 wraps with title + bg modifiers.
- **`myTeam` requires `teamStore.myTeam` resolved.** EmptyStateView fallback if not loaded.
- **Banner asset missing.** Text wordmark fallback. Polish item.

## Out of scope

- **Season switcher** (F5).
- **Search bar inside drawer.** Tray-header magnifying-glass only.
- **Inbox / notifications bell.** Defer.
- **AmbientBackground decorative blobs.** Use `bgDark` solid for now.
- **Permanent drawer on iPad.** Future.
- **Home / Overview landing page.** Default is Standings.
- **Reordering tray sections.** Static, code-defined.
- **Light mode toggle.** Always dark.
- **Push deep-link schema migration.** Only dispatch target changes.
- **Renaming `AppRouter`/`AppRoute`.**

## Skills / Agents to use

- **`ios-specialist`** — primary executor. Owns SwiftUI + Swift 6 strict concurrency, `@Observable`, gesture composition, `NavigationStack`. Expected duration: 1–2 days.

## Notes for the executor

- Build incrementally. After step 9 you should have a Hello-World drawer that opens and closes over the existing `TabView` content (don't rip the TabView yet). Steps 10–13 do the swap.
- `xcodegen generate` once at the start; new files under `Xomper/` auto-pick up.
- Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild …` for sim builds.
- For this autonomous run, single squashed commit at the end is acceptable.
