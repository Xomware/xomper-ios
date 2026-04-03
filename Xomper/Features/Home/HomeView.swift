import SwiftUI

struct HomeView: View {
    var authStore: AuthStore
    var leagueStore: LeagueStore
    var userStore: UserStore
    var teamStore: TeamStore
    var nflStateStore: NflStateStore
    var router: AppRouter

    var body: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.lg) {
                headerSection
                leagueCard
                myTeamCard
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

    // MARK: - League Card

    private var leagueCard: some View {
        Group {
            if leagueStore.isLoading {
                loadingCard
            } else if let league = leagueStore.myLeague {
                leagueCardContent(league)
            } else if leagueStore.error != nil {
                errorCard
            }
        }
    }

    private func leagueCardContent(_ league: League) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            router.switchTab(.league)
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
                        Label("\(league.totalRosters) teams", systemImage: "person.3")
                    }
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)

                    if league.isDynasty {
                        Text("Dynasty")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(XomperColors.deepNavy)
                            .padding(.horizontal, XomperTheme.Spacing.sm)
                            .padding(.vertical, XomperTheme.Spacing.xxs)
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

    // MARK: - My Team Card

    private var myTeamCard: some View {
        Group {
            if let team = teamStore.myTeam {
                myTeamCardContent(team)
            }
        }
    }

    private func myTeamCardContent(_ team: StandingsTeam) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            HStack {
                Text("My Team")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(XomperColors.textSecondary)
                Spacer()
                Text("#\(team.leagueRank)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(XomperColors.championGold)
            }

            HStack(spacing: XomperTheme.Spacing.md) {
                AvatarView(avatarID: team.avatarId, size: XomperTheme.AvatarSize.md)

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
                    Text(team.teamName)
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)

                    Text(team.record)
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: XomperTheme.Spacing.xxs) {
                    Text(team.fpts.formattedPoints)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(XomperColors.textPrimary)

                    Text("PF")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                }
            }
        }
        .xomperCard()
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .stroke(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(team.teamName), record \(team.record), rank \(team.leagueRank)")
    }

    // MARK: - Loading / Error Cards

    private var loadingCard: some View {
        HStack(spacing: XomperTheme.Spacing.md) {
            ProgressView()
                .tint(XomperColors.championGold)
            Text("Loading league...")
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
            Text("Failed to load league")
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
            teamStore: TeamStore(),
            nflStateStore: NflStateStore(),
            router: AppRouter()
        )
    }
    .preferredColorScheme(.dark)
}
