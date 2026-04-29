import SwiftUI

/// Defines all navigable destinations within the app.
///
/// `leagueDashboard` is retained as a defensive case post-F3 (the legacy
/// dashboard view was dissolved into individual tray destinations). If
/// anything still pushes this route, `MainShell` falls through to standings.
enum AppRoute: Hashable {
    case leagueDashboard
    case teamDetail(rosterId: Int)
    case userProfile(userId: String)
    case draftHistory
    case matchupHistory
    case taxiSquad
    case search
    case settings
    case playerDetail(playerId: String)
    /// Browse another league at high level (standings + basic info). Used
    /// when the user taps a non-home league in profile or search. The
    /// view fetches its own data — does NOT mutate `LeagueStore.myLeague`.
    case leagueOverview(leagueId: String)
}

/// Owns the inner `NavigationStack` path inside `MainShell`. The drawer
/// (via `NavigationStore`) drives top-level destination selection; this
/// router is purely about pushes / pops within the current destination's
/// stack.
@Observable
@MainActor
final class AppRouter {
    var path = NavigationPath()

    func navigate(to route: AppRoute) {
        path.append(route)
    }

    func popToRoot() {
        path = NavigationPath()
    }
}
