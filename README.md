# Xomper iOS

Native SwiftUI companion app for the Xomper dynasty fantasy football platform.

## Stack

- SwiftUI (iOS 17+), Universal (iPhone + iPad)
- Swift 6, `@Observable` stores
- Supabase (auth + database)
- Sleeper API (fantasy football data)

## Setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
2. Copy `Xomper/Config/Config.swift.template` to `Xomper/Config/Config.swift`
3. Fill in real values (Supabase URL, anon key, league ID, API Gateway URL)
4. Run `xcodegen generate`
5. Open `Xomper.xcodeproj` in Xcode
6. Build and run

## Architecture

- **Stores**: `@Observable` service classes (`AuthStore`, `LeagueStore`, `PlayerStore`, etc.)
- **Networking**: Protocol-based `SleeperAPIClient` + Supabase Swift SDK
- **Navigation**: `TabView` + `NavigationSplitView` (adaptive layout)
- **Theme**: Midnight Emerald dark palette (`XomperColors`)

## Features

- Google OAuth + email auth via Supabase
- League dashboard with standings (league-wide + divisional)
- Team/roster management with player details
- Playoff bracket visualization
- World Cup divisional tournament (4-year cycle)
- Multi-season draft history (dynasty chain traversal)
- Matchup history with H2H tracking
- Rule proposals with voting (2/3 threshold)
- Taxi squad management with steal requests
- User profiles and Sleeper user search

## Deployment

Xcode Cloud workflow deploys to TestFlight on push to `main`. The `ci_scripts/ci_post_clone.sh` script handles version bumping and Config.swift generation from environment variables.

## Related Repos

- [xomper-front-end](https://github.com/Xomware/xomper-front-end) — Angular web app
- [xomper-back-end](https://github.com/Xomware/xomper-back-end) — Python/Lambda backend
- [xomper-infrastructure](https://github.com/Xomware/xomper-infrastructure) — Terraform/AWS
