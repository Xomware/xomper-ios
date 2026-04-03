import SwiftUI

@main
struct XomperApp: App {
    @State private var authStore = AuthStore()
    @State private var leagueStore = LeagueStore()
    @State private var userStore = UserStore()
    @State private var teamStore = TeamStore()
    @State private var nflStateStore = NflStateStore()
    @State private var playerStore = PlayerStore()
    @State private var historyStore = HistoryStore()
    @State private var worldCupStore = WorldCupStore()
    @State private var taxiSquadStore = TaxiSquadStore()
    @State private var rulesStore = RulesStore()

    var body: some Scene {
        WindowGroup {
            AuthGateView(
                authStore: authStore,
                leagueStore: leagueStore,
                userStore: userStore,
                teamStore: teamStore,
                nflStateStore: nflStateStore,
                playerStore: playerStore,
                historyStore: historyStore,
                worldCupStore: worldCupStore,
                taxiSquadStore: taxiSquadStore,
                rulesStore: rulesStore
            )
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                authStore.handleOpenURL(url)
            }
        }
    }
}
