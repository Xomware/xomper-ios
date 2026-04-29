import SwiftUI

/// Pushed view used when the user taps a non-home league in profile or
/// search. Fetches the target league + rosters + users on its own and
/// renders standings — never touches the global `LeagueStore.myLeague`,
/// so the user's home-league state is preserved.
///
/// Drill-down (tap a team) pushes a `.teamDetail` route, but resolves
/// against the locally-loaded rosters rather than `myLeagueRosters`,
/// since this league isn't the home league.
struct LeagueOverviewView: View {
    let leagueId: String
    var router: AppRouter

    @State private var league: League?
    @State private var rosters: [Roster] = []
    @State private var users: [SleeperUser] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let apiClient: SleeperAPIClientProtocol = SleeperAPIClient()

    var body: some View {
        Group {
            if isLoading {
                LoadingView(message: "Loading league...")
            } else if let errorMessage {
                ErrorView(message: errorMessage) {
                    Task { await load() }
                }
            } else if let league {
                content(league: league)
            } else {
                EmptyStateView(
                    icon: "trophy",
                    title: "League Not Found",
                    message: "Could not load this league."
                )
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle(league?.displayName ?? "League")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await load()
        }
    }

    // MARK: - Content

    private func content(league: League) -> some View {
        let standings = StandingsBuilder.buildStandings(
            rosters: rosters,
            users: users,
            league: league
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.lg) {
                leagueHeader(league: league)
                standingsSection(standings: standings)
            }
            .padding(XomperTheme.Spacing.md)
            .padding(.bottom, XomperTheme.Spacing.xl)
        }
    }

    // MARK: - Header

    private func leagueHeader(league: League) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text(league.displayName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(XomperColors.textPrimary)

            HStack(spacing: XomperTheme.Spacing.sm) {
                Label(league.season, systemImage: "calendar")
                Label("\(league.totalRosters ?? 0) teams", systemImage: "person.3")
                if league.isDynasty {
                    Text("Dynasty")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(XomperColors.bgDark)
                        .padding(.horizontal, XomperTheme.Spacing.sm)
                        .padding(.vertical, XomperTheme.Spacing.xs)
                        .background(XomperColors.championGold)
                        .clipShape(Capsule())
                }
            }
            .font(.caption)
            .foregroundStyle(XomperColors.textSecondary)

            Text("Browsing — your home league is unchanged.")
                .font(.caption2)
                .foregroundStyle(XomperColors.textMuted)
                .padding(.top, XomperTheme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .xomperCard()
    }

    // MARK: - Standings

    private func standingsSection(standings: [StandingsTeam]) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text("Standings")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(XomperColors.textSecondary)
                .padding(.leading, XomperTheme.Spacing.xs)

            if standings.isEmpty {
                Text("No standings available yet.")
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textMuted)
                    .frame(maxWidth: .infinity)
                    .xomperCard()
            } else {
                VStack(spacing: XomperTheme.Spacing.xs) {
                    ForEach(standings) { team in
                        teamRow(team: team)
                    }
                }
            }
        }
    }

    private func teamRow(team: StandingsTeam) -> some View {
        HStack(spacing: XomperTheme.Spacing.md) {
            Text("\(team.leagueRank)")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(XomperColors.textMuted)
                .frame(width: 24, alignment: .leading)

            AvatarView(avatarID: team.avatarId, size: XomperTheme.AvatarSize.md, isTeam: true)

            VStack(alignment: .leading, spacing: 2) {
                Text(team.teamName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)

                Text("@\(team.username)")
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(recordString(team: team))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(XomperColors.textPrimary)
                    .monospacedDigit()
                Text(String(format: "%.1f PF", team.fpts))
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
        .padding(.vertical, XomperTheme.Spacing.sm)
        .background(XomperColors.bgCard.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md, style: .continuous))
    }

    private func recordString(team: StandingsTeam) -> String {
        if team.ties > 0 {
            return "\(team.wins)-\(team.losses)-\(team.ties)"
        }
        return "\(team.wins)-\(team.losses)"
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let leagueLoad = apiClient.fetchLeague(leagueId)
            async let rostersLoad = apiClient.fetchLeagueRosters(leagueId)
            async let usersLoad = apiClient.fetchLeagueUsers(leagueId)
            let (l, r, u) = try await (leagueLoad, rostersLoad, usersLoad)
            self.league = l
            self.rosters = r
            self.users = u
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
