import SwiftUI

/// Thin pass-through that hosts `MainShell`. The shell owns navigation,
/// drawer state, and bootstrap tasks. This view exists purely for backward
/// compatibility with the existing `AuthGateView` injection bag.
struct ContentView: View {
    var authStore: AuthStore
    var leagueStore: LeagueStore
    var userStore: UserStore
    var teamStore: TeamStore
    var nflStateStore: NflStateStore
    var playerStore: PlayerStore
    var historyStore: HistoryStore
    var worldCupStore: WorldCupStore
    var taxiSquadStore: TaxiSquadStore
    var rulesStore: RulesStore

    var body: some View {
        MainShell(
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
    }
}

#Preview {
    ContentView(
        authStore: AuthStore(),
        leagueStore: LeagueStore(),
        userStore: UserStore(),
        teamStore: TeamStore(),
        nflStateStore: NflStateStore(),
        playerStore: PlayerStore(),
        historyStore: HistoryStore(),
        worldCupStore: WorldCupStore(),
        taxiSquadStore: TaxiSquadStore(),
        rulesStore: RulesStore()
    )
    .preferredColorScheme(.dark)
}
