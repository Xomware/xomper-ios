import SwiftUI

struct HomeView: View {
    var authStore: AuthStore
    var leagueStore: LeagueStore
    var userStore: UserStore
    var nflStateStore: NflStateStore
    var router: AppRouter

    var body: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.lg) {
                headerSection
                leaguesSection
            }
            .padding(XomperTheme.Spacing.md)
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    router.navigate(to: .search)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(XomperColors.championGold)
                }
                .accessibilityLabel("Search")
                .accessibilityHint("Double tap to search for users or leagues")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: XomperTheme.Spacing.sm) {
            if let nflState = nflStateStore.nflState {
                Text(nflState.displayLabel)
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
            }

            if let user = userStore.myUser {
                Text("Welcome, \(user.resolvedDisplayName)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(XomperColors.textPrimary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, XomperTheme.Spacing.sm)
    }

    // MARK: - Leagues Section

    private var leaguesSection: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
            HStack {
                Text("My Leagues")
                    .font(.headline)
                    .foregroundStyle(XomperColors.textPrimary)
                Spacer()
                if leagueStore.isLoadingUserLeagues {
                    ProgressView()
                        .tint(XomperColors.championGold)
                        .scaleEffect(0.8)
                }
            }

            if leagueStore.isLoading && leagueStore.userLeagues.isEmpty {
                loadingCard
            } else if leagueStore.userLeagues.isEmpty {
                if let league = leagueStore.myLeague {
                    leagueCardContent(league)
                } else if leagueStore.error != nil {
                    errorCard
                }
            } else {
                ForEach(leagueStore.userLeagues, id: \.leagueId) { league in
                    leagueCardContent(league)
                }
            }
        }
    }

    private func leagueCardContent(_ league: League) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            Task {
                await leagueStore.switchToLeague(id: league.leagueId)
                leagueStore.leagueChainCache = nil
                router.switchTab(.league)
            }
        } label: {
            HStack(spacing: XomperTheme.Spacing.md) {
                AvatarView(avatarID: league.avatar, size: XomperTheme.AvatarSize.lg, isTeam: true)

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                    Text(league.displayName)
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: XomperTheme.Spacing.sm) {
                        Label("\(league.season)", systemImage: "calendar")
                        Label("\(league.totalRosters ?? 0) teams", systemImage: "person.3")
                    }
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)

                    if league.isDynasty {
                        Text("Dynasty")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(XomperColors.deepNavy)
                            .padding(.horizontal, XomperTheme.Spacing.sm)
                            .padding(.vertical, XomperTheme.Spacing.xs)
                            .background(XomperColors.championGold)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
            }
            .xomperCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View \(league.displayName) league dashboard")
        .accessibilityHint("Double tap to open league standings")
    }

    // MARK: - Loading / Error Cards

    private var loadingCard: some View {
        HStack(spacing: XomperTheme.Spacing.md) {
            ProgressView()
                .tint(XomperColors.championGold)
            Text("Loading leagues...")
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .xomperCard()
    }

    private var errorCard: some View {
        VStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(XomperColors.errorRed)
            Text("Failed to load leagues")
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .xomperCard()
    }
}

#Preview {
    NavigationStack {
        HomeView(
            authStore: AuthStore(),
            leagueStore: LeagueStore(),
            userStore: UserStore(),
            nflStateStore: NflStateStore(),
            router: AppRouter()
        )
    }
    .preferredColorScheme(.dark)
}
