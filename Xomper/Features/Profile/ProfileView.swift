import SwiftUI

struct ProfileView: View {
    let userId: String
    var leagueStore: LeagueStore
    var router: AppRouter

    @State private var user: SleeperUser?
    @State private var leagues: [League] = []
    @State private var isLoadingUser = true
    @State private var isLoadingLeagues = false
    @State private var errorMessage: String?

    private let apiClient: SleeperAPIClientProtocol = SleeperAPIClient()
    private let currentSeason = String(Calendar.current.component(.year, from: Date()))

    var body: some View {
        Group {
            if isLoadingUser {
                LoadingView(message: "Loading profile...")
            } else if let errorMessage {
                ErrorView(message: errorMessage) {
                    Task { await loadUser() }
                }
            } else if let user {
                profileContent(user)
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle(user?.resolvedDisplayName ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await loadUser()
        }
    }

    // MARK: - Content

    private func profileContent(_ user: SleeperUser) -> some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.lg) {
                profileHeader(user)
                leaguesSection
            }
            .padding(XomperTheme.Spacing.md)
        }
    }

    // MARK: - Profile Header

    private func profileHeader(_ user: SleeperUser) -> some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            AvatarView(
                avatarID: user.avatar,
                size: XomperTheme.AvatarSize.xl
            )

            VStack(spacing: XomperTheme.Spacing.xs) {
                Text(user.resolvedDisplayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(XomperColors.textPrimary)

                if let username = user.username,
                   username != user.displayName {
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, XomperTheme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Profile for \(user.resolvedDisplayName)")
    }

    // MARK: - Leagues Section

    @ViewBuilder
    private var leaguesSection: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text("\(currentSeason) Leagues")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(XomperColors.textSecondary)
                .padding(.leading, XomperTheme.Spacing.xs)

            if isLoadingLeagues {
                leaguesLoadingCard
            } else if leagues.isEmpty {
                leaguesEmptyCard
            } else {
                ForEach(leagues) { league in
                    leagueRow(league)
                }
            }
        }
    }

    private func leagueRow(_ league: League) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            navigateToLeague(league)
        } label: {
            HStack(spacing: XomperTheme.Spacing.md) {
                AvatarView(
                    avatarID: league.avatar,
                    size: XomperTheme.AvatarSize.md,
                    isTeam: true
                )

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
                    Text(league.displayName)
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: XomperTheme.Spacing.sm) {
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
        .accessibilityLabel("View \(league.displayName)")
        .accessibilityHint("Double tap to open league")
    }

    private var leaguesLoadingCard: some View {
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

    private var leaguesEmptyCard: some View {
        HStack(spacing: XomperTheme.Spacing.md) {
            Image(systemName: "trophy")
                .foregroundStyle(XomperColors.textMuted)
                .accessibilityHidden(true)
            Text("No leagues found for \(currentSeason)")
                .font(.subheadline)
                .foregroundStyle(XomperColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .xomperCard()
    }

    // MARK: - Data Loading

    private func loadUser() async {
        isLoadingUser = true
        errorMessage = nil

        do {
            let fetchedUser = try await apiClient.fetchUser(userId)
            user = fetchedUser
            isLoadingUser = false
            if let uid = fetchedUser.userId {
                await loadLeagues(for: uid)
            }
        } catch {
            errorMessage = "Could not load this profile."
            isLoadingUser = false
        }
    }

    private func loadLeagues(for userId: String) async {
        isLoadingLeagues = true

        do {
            leagues = try await apiClient.fetchUserLeagues(userId, season: currentSeason)
        } catch {
            // Non-fatal -- just show empty
            leagues = []
        }

        isLoadingLeagues = false
    }

    // MARK: - Navigation

    private func navigateToLeague(_ league: League) {
        Task {
            await leagueStore.switchToLeague(id: league.leagueId)
            router.switchTab(.league)
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView(
            userId: "457981263849623552",
            leagueStore: LeagueStore(),
            router: AppRouter()
        )
    }
    .preferredColorScheme(.dark)
}
