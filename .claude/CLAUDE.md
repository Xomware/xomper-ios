# xomper-ios

> Native SwiftUI fantasy football companion for the Xomper league.

## Stack
- SwiftUI, iOS 17+ deployment target, Swift 6
- Supabase Swift SDK (auth, database)
- Sleeper API (league data, players, matchups)
- URLSession + async/await (networking)

## Architecture
- `@Observable` stores (NOT ObservableObject)
- `@MainActor` on all stores and views
- Lean MVVM: views read from stores, stores own async logic
- `NavigationSplitView` for adaptive layout (collapses on iPhone)

## Theme
- Midnight Emerald dark theme (always dark, no light mode)
- Colors defined in `XomperColors.swift`
- 8pt spacing grid via `XomperTheme.swift`
- Dynamic Type only, no hardcoded font sizes

## Key Commands
```bash
xcodegen generate                             # regenerate .xcodeproj
open Xomper.xcodeproj                         # open in Xcode
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Xomper -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Important Paths
```
Xomper/
  App/              # Entry point, ContentView
  Config/           # Config.swift (gitignored), template committed
  Core/
    Networking/     # SleeperAPIClient, SupabaseManager, XomperAPIClient
    Stores/         # @Observable store classes
    Models/         # Codable structs
    Theme/          # Colors, typography, spacing
    Extensions/     # Swift extensions
  Features/         # Feature-area views (Auth, Home, League, Team, etc.)
  Navigation/       # Tab enum, router
  Resources/        # Assets, Info.plist
```

## Project Config
```yaml
pm_tool: none
base_branch: master
build_commands:
  - DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Xomper -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Constraints
- iOS 17+ only: use @Observable, SwiftData-era APIs
- Portrait-only on iPhone, all orientations on iPad
- Always dark mode (no light mode support needed)
- 12-person league, hardcoded whitelistedLeagueId
- Config.swift is gitignored (contains secrets)
- No Co-Authored-By lines in commits

## Lessons
- xcode-select points to CommandLineTools, not Xcode.app. Must use DEVELOPER_DIR env var for xcodebuild.
- Available simulators: iPhone 17 Pro, iPhone 17 Pro Max, iPhone Air, iPhone 16e, iPad Air/Pro/mini.
