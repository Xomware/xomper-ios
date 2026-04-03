import SwiftUI

/// Defines all navigable destinations within the app.
enum AppRoute: Hashable {
    case leagueDashboard
    case teamDetail(rosterId: Int)
    case userProfile(userId: String)
    case draftHistory
    case matchupHistory
    case taxiSquad
    case search
}

@Observable
@MainActor
final class AppRouter {
    var selectedTab: AppTab = .home
    var path = NavigationPath()

    func navigate(to route: AppRoute) {
        path.append(route)
    }

    func popToRoot() {
        path = NavigationPath()
    }

    func switchTab(_ tab: AppTab) {
        if selectedTab == tab {
            popToRoot()
        } else {
            selectedTab = tab
        }
    }
}
