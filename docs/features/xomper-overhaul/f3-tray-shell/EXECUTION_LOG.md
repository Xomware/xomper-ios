# F3 Execution Log

Branch: `feature/tray-shell`
Started: 2026-04-28

## Audit findings (pre-execution)

- `PushNotificationManager` (`Xomper/Core/Notifications/PushNotificationManager.swift`) **does NOT** dispatch tabs or routes — it only owns device token + permission state. Step 17: nothing to rewire.
- `selectedTab`/`switchTab(_:)` callers (4 sites):
  - `Xomper/App/ContentView.swift` (the root TabView itself — replaced in step 13)
  - `Xomper/Features/Home/HomeView.swift:98` — `router.switchTab(.league)` after `switchToLeague` (file is deleted in step 16)
  - `Xomper/Features/Profile/MyProfileView.swift:151` — `router.switchTab(.league)` (rewired in step 15)
  - `Xomper/Features/Profile/ProfileView.swift:214` — `router.switchTab(.league)` after `switchToLeague`
  - `Xomper/Features/Home/SearchView.swift:397` — `router.switchTab(.league)` after `switchToLeague`
- `LeagueDashboardView` is referenced from `ContentView.tabContent(for:)` and `ContentView.destinationView(for:)` only. Both go away.
- `AppRoute.leagueDashboard` is unused outside `ContentView.destinationView` once dashboard is dissolved — leaving the case in the enum is harmless (no enforcement of exhaustiveness once we remove the destination match), but the case will become dead code. Per plan we keep `AppRoute` shape; the case is now defensive only.

## Step log

### Step 1 — Shell directory + skeleton files
Created `Xomper/Features/Shell/` and seeded all 9 files. xcodegen will pick them up after step 13's regenerate.

### Step 2 — TrayDestination
11 cases as planned. `Hashable` is automatic (no associated values). `title` + `systemImage` switch-statement.

### Step 3 — NavigationStore
`@Observable @MainActor`. `select(_:router:)` wraps `popToRoot` + destination change + drawer close in one `withAnimation(.easeInOut(duration: 0.25))`.

### Step 4 — TrayItem
Pure view; selection / icon / chevron / row-bg styles per spec. Accessibility traits wired.

### Step 5 — TrayProfileCard
Gradient bg uses `XomperColors.goldAccentGradient.opacity(0.25)` over `XomperColors.bgCard` via a `ZStack`. Rounded `xl` (16) corner radius + 1pt white-12% stroke.

### Step 6 — DrawerView
Sections defined inline (Compete / History / Roster / Meta). Pinned Settings footer below `Divider`. Width `min(screen * 0.82, 320)`. Vertical-gradient bg `[bgDark, bgCard.opacity(0.85)]`. Trailing 1pt hairline. Internal close-drag gesture matches spec.

### Step 7 — DrawerScrim
`Color.black.opacity(0.45)` overlay; tap closes; `.transition(.opacity)`.

### Step 8 — HeaderBar
ZStack: centered "Xomper" wordmark; HStack with leading 44pt avatar (`AvatarView` 36pt inside) and trailing 44pt magnifying-glass. Background `XomperColors.bgDark`, height 44, horizontal padding `Spacing.sm`.

### Step 9 — MainShell
ZStack(alignment: .leading) of bgDark + VStack(HeaderBar + NavigationStack(path:$router.path)) + DrawerScrim + DrawerView. Edge-drag gesture: 30pt edge, 60pt threshold, 1.5x horizontal-vs-vertical, gated on `!isDrawerOpen && router.path.count == 0`. `@State private var navStore` + `@State private var router`.

### Step 10 — bootstrap tasks
Moved `bootstrapPhase1` + `bootstrapPhase2` verbatim from `ContentView` to `MainShell`. `.task` and `.task(id: authStore.sleeperUserId)` semantics preserved.

### Step 11 — destinationRoot switch
One case per `TrayDestination`. `.standings`/`.matchups`/`.playoffs`/`.draftHistory`/`.matchupHistory`/`.worldCup`/`.taxiSquad`/`.rules`/`.profile`/`.settings` wired to existing views; `.myTeam` → `TeamView` resolved via `teamStore.myTeam` + roster lookup, with `EmptyStateView` fallback. `.rules` falls back when no league loaded. Title + dark toolbar applied to the `Group`.

### Step 12 — MyProfileView toolbar
Removed `.gearshape` toolbar item. Also removed `navigationTitle("Profile")` since `MainShell` sets it via `currentDestination.title`.

### Step 13 — ContentView rewire
Replaced body with `MainShell(...)`. Stripped `tabContent(for:)`, `destinationView(for:)`, both bootstrap funcs. Now a thin pass-through. Preview kept.

### Step 14 — AppTab + AppRouter prune
Deleted `Xomper/Navigation/AppTab.swift`. Removed `selectedTab` and `switchTab(_:)` from `AppRouter`. Kept `path`, `navigate(to:)`, `popToRoot()`. `AppRoute.leagueDashboard` retained as defensive case (falls through to standings).

### Step 15 — MyProfileView league row tap
`router.switchTab(.league)` → `navStore.select(.standings, router: router)`. Added `navStore` parameter. Updated preview.

### Step 16 — delete HomeView + LeagueDashboardView
Both files deleted. No remaining call sites (verified via grep).

### Step 17 — push notification audit
`PushNotificationManager` (`Xomper/Core/Notifications/PushNotificationManager.swift`) does NOT dispatch tabs / routes. It owns `deviceToken`, `permissionGranted`, and `UNUserNotificationCenterDelegate` callbacks that just call the completion handler with no navigation side effect. **No rewire needed.** Logged as pre-execution audit.

### Step 18 — builds
- iPhone 17 Pro: BUILD SUCCEEDED, no F3-introduced warnings.
- iPad Pro 13-inch (M5): BUILD SUCCEEDED. (Note: M4 is no longer in the simulator catalog under Xcode 26 / iOS 26 SDK; M5 used as the closest analogue for the 13" form factor.)
- Launch test on booted iPhone 17 Pro: process running, no crash on cold open.

### Step 19 — accessibility
- `TrayItem`: `.accessibilityLabel(destination.title)` + `.accessibilityAddTraits(isSelected ? .isSelected : [])`. Icon `.accessibilityHidden(true)`.
- `DrawerScrim`: label "Close menu", hint, button trait.
- `HeaderBar` avatar button: label "Open menu", hint, button trait.
- `HeaderBar` search button: label "Search", hint.
- `TrayProfileCard`: label "Open profile for &lt;name&gt;".
- "Xomper" wordmark: `.accessibilityAddTraits(.isHeader)`.

### Step 20 — plan status flipped to Done.

## Final state

- iPhone build: clean.
- iPad build: clean.
- No `selectedTab` / `switchTab` / `AppTab` / `HomeView` / `LeagueDashboardView` references anywhere.
- Strict Swift 6 concurrency: no F3-introduced warnings.

## Deviations from plan

- **iPad simulator name**: plan called for "iPad Pro 13" (M4)" but the active simulator catalog (Xcode 26 / iOS 26.2 SDK) lists M5 only. Used `iPad Pro 13-inch (M5)` for the smoke build.
- **MyProfileView**: removed the inline `navigationTitle("Profile")` because `MainShell.destinationRoot` already applies the title from `currentDestination.title`. Without removing it the inner `.navigationTitle` would override the shell's.
- **`ProfileView` (other-user) and `SearchView`**: also accept `navStore` parameter so their league-row taps land on `.standings` instead of the deleted `.league` tab. Plan only called this out for `MyProfileView`; the other two were uncovered during the audit and rewired the same way.
- **Avatar in drawer**: `TrayProfileCard` uses the existing `AvatarView(avatarID:)` (Sleeper-CDN-aware) rather than an `AsyncImage(URL?)` like Xomify. This matches Xomper's avatar conventions and reuses the SF-symbol fallback already in use across the app.
- No other deviations.
