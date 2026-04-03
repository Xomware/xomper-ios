import SwiftUI

struct AuthGateView: View {
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
        Group {
            if authStore.isLoading {
                LoadingView(message: "Checking session...")
            } else if !authStore.isAuthenticated {
                LoginView(authStore: authStore)
            } else if !authStore.isWhitelisted {
                notAuthorizedView
            } else if authStore.needsSleeperLink {
                LinkSleeperView(authStore: authStore)
            } else {
                ContentView(
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
        .animation(XomperTheme.defaultAnimation, value: authStore.isLoading)
        .animation(XomperTheme.defaultAnimation, value: authStore.isAuthenticated)
        .animation(XomperTheme.defaultAnimation, value: authStore.isWhitelisted)
        .animation(XomperTheme.defaultAnimation, value: authStore.needsSleeperLink)
    }

    private var notAuthorizedView: some View {
        VStack(spacing: XomperTheme.Spacing.lg) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: XomperTheme.IconSize.xl))
                .foregroundStyle(XomperColors.errorRed)
                .accessibilityHidden(true)

            Text("Not Authorized")
                .font(.headline)
                .foregroundStyle(XomperColors.textPrimary)

            Text("Your email is not on the whitelist. Contact the league admin for access.")
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, XomperTheme.Spacing.lg)

            signOutButton
        }
        .padding(XomperTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(XomperColors.bgDark.ignoresSafeArea())
    }

    private var signOutButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            Task { await authStore.signOut() }
        } label: {
            Text("Sign Out")
                .font(.headline)
                .foregroundStyle(XomperColors.textPrimary)
                .padding(.horizontal, XomperTheme.Spacing.lg)
                .padding(.vertical, XomperTheme.Spacing.sm)
                .frame(minHeight: XomperTheme.minTouchTarget)
                .background(XomperColors.surfaceLight)
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        }
        .accessibilityLabel("Sign out")
    }
}

#Preview {
    AuthGateView(
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
