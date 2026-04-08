import SwiftUI

struct StandingsView: View {
    var leagueStore: LeagueStore
    var teamStore: TeamStore
    var authStore: AuthStore
    var router: AppRouter

    @State private var viewMode: StandingsViewMode = .league
    @State private var standings: [StandingsTeam] = []
    @State private var divisionStandings: [String: [StandingsTeam]] = [:]
    @State private var hasDivisions = false

    var body: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.md) {
                if hasDivisions {
                    viewModeToggle
                }

                switch viewMode {
                case .league:
                    leagueStandingsView
                case .division:
                    divisionStandingsView
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
        .background(XomperColors.bgDark)
        .refreshable {
            await refreshStandings()
        }
        .onAppear {
            buildStandings()
        }
    }

    // MARK: - View Mode Toggle

    private var viewModeToggle: some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            ForEach(StandingsViewMode.allCases) { mode in
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(XomperTheme.defaultAnimation) {
                        viewMode = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.subheadline)
                        .fontWeight(viewMode == mode ? .semibold : .regular)
                        .foregroundStyle(viewMode == mode ? XomperColors.deepNavy : XomperColors.textSecondary)
                        .padding(.horizontal, XomperTheme.Spacing.md)
                        .padding(.vertical, XomperTheme.Spacing.sm)
                        .frame(minHeight: XomperTheme.minTouchTarget)
                        .background(viewMode == mode ? XomperColors.championGold : XomperColors.surfaceLight)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.title) view")
                .accessibilityAddTraits(viewMode == mode ? .isSelected : [])
            }
            Spacer()
        }
    }

    // MARK: - League Standings

    private var leagueStandingsView: some View {
        LazyVStack(spacing: XomperTheme.Spacing.md) {
            standingsHeader
            ForEach(standings) { team in
                StandingsRowView(
                    team: team,
                    rank: team.leagueRank,
                    isMyTeam: team.userId == authStore.sleeperUserId,
                    playoffCutoff: leagueStore.currentLeague?.settings?.playoffTeams
                ) {
                    selectTeam(team)
                } onProfileTap: {
                    navigateToProfile(team)
                }
            }
        }
    }

    // MARK: - Division Standings

    private var divisionStandingsView: some View {
        LazyVStack(spacing: XomperTheme.Spacing.lg) {
            let sortedKeys = divisionStandings.keys.sorted()
            ForEach(sortedKeys, id: \.self) { divisionName in
                if let teams = divisionStandings[divisionName] {
                    divisionSection(name: divisionName, teams: teams)
                }
            }
        }
    }

    private func divisionSection(name: String, teams: [StandingsTeam]) -> some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            HStack(spacing: XomperTheme.Spacing.sm) {
                if let avatarId = teams.first?.divisionAvatar {
                    AvatarView(avatarID: avatarId, size: XomperTheme.AvatarSize.sm, isTeam: true)
                }
                Text(name)
                    .font(.headline)
                    .foregroundStyle(XomperColors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, XomperTheme.Spacing.md)

            standingsHeader

            ForEach(teams) { team in
                StandingsRowView(
                    team: team,
                    rank: team.divisionRank,
                    isMyTeam: team.userId == authStore.sleeperUserId,
                    playoffCutoff: nil
                ) {
                    selectTeam(team)
                } onProfileTap: {
                    navigateToProfile(team)
                }
            }
        }
    }

    // MARK: - Header

    private var standingsHeader: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Text("#")
                .frame(width: 28, alignment: .center)
            Text("Team")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("W")
                .frame(width: 28, alignment: .center)
            Text("L")
                .frame(width: 28, alignment: .center)
            Text("Str")
                .frame(width: 36, alignment: .center)
            Text("PF")
                .frame(width: 64, alignment: .trailing)
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(XomperColors.textMuted)
        .padding(.horizontal, XomperTheme.Spacing.md)
        .padding(.vertical, XomperTheme.Spacing.sm)
        .accessibilityHidden(true)
    }

    // MARK: - Actions

    private func navigateToProfile(_ team: StandingsTeam) {
        router.navigate(to: .userProfile(userId: team.userId))
    }

    private func selectTeam(_ team: StandingsTeam) {
        let user = leagueStore.currentLeagueUsers.first { $0.userId == team.userId }
        teamStore.setCurrentTeam(team, user: user)
        router.navigate(to: .teamDetail(rosterId: team.rosterId))
    }

    private func buildStandings() {
        guard let league = leagueStore.currentLeague else { return }

        standings = StandingsBuilder.buildStandings(
            rosters: leagueStore.currentLeagueRosters,
            users: leagueStore.currentLeagueUsers,
            league: league
        )

        divisionStandings = StandingsBuilder.buildDivisionStandings(from: standings)
        hasDivisions = standings.contains { $0.hasDivision }
    }

    private func refreshStandings() async {
        await leagueStore.loadMyLeague()
        buildStandings()

        if let league = leagueStore.myLeague {
            let freshStandings = StandingsBuilder.buildStandings(
                rosters: leagueStore.myLeagueRosters,
                users: leagueStore.myLeagueUsers,
                league: league
            )
            teamStore.loadMyTeam(from: freshStandings, userId: authStore.sleeperUserId)
        }
    }
}

// MARK: - Standings Row

private struct StandingsRowView: View {
    let team: StandingsTeam
    let rank: Int
    let isMyTeam: Bool
    let playoffCutoff: Int?
    let onTap: () -> Void
    var onProfileTap: (() -> Void)?

    @State private var isPressed = false

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            onTap()
        } label: {
            HStack(spacing: 0) {
                rankBadge
                teamInfo
                statsColumns
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
            .frame(minHeight: XomperTheme.minTouchTarget)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                    .stroke(
                        isMyTeam ? XomperColors.championGold.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
            .xomperShadow(.sm)
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(XomperTheme.defaultAnimation, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Double tap to view team details")
        .contextMenu {
            if let onProfileTap {
                Button {
                    onProfileTap()
                } label: {
                    Label("View Owner Profile", systemImage: "person.circle")
                }
            }
        }
    }

    private var rankBadge: some View {
        Text("\(rank)")
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(rankColor)
            .frame(width: 28, alignment: .center)
    }

    private var teamInfo: some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            AvatarView(avatarID: team.avatarId, size: XomperTheme.AvatarSize.sm)

            VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                Text(team.teamName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)

                Text(team.displayName)
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsColumns: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Text("\(team.wins)")
                .frame(width: 28, alignment: .center)
                .foregroundStyle(XomperColors.textPrimary)

            Text("\(team.losses)")
                .frame(width: 28, alignment: .center)
                .foregroundStyle(XomperColors.textSecondary)

            Text(team.streak.displayString)
                .frame(width: 36, alignment: .center)
                .foregroundStyle(streakColor)

            Text(team.fpts.formattedPoints)
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(XomperColors.textPrimary)
        }
        .font(.caption)
        .fontWeight(.medium)
    }

    // MARK: - Helpers

    private var rankColor: Color {
        switch rank {
        case 1: XomperColors.championGold
        case 2: Color(hex: 0xC0C0C0)
        case 3: Color(hex: 0xCD7F32)
        default: XomperColors.textMuted
        }
    }

    private var streakColor: Color {
        switch team.streak.type {
        case .win: XomperColors.successGreen
        case .loss: XomperColors.accentRed
        case .none: XomperColors.textMuted
        }
    }

    private var accessibilityDescription: String {
        var parts = [
            "Rank \(rank)",
            team.teamName,
            team.displayName,
            "\(team.wins) wins, \(team.losses) losses",
            "\(team.fpts.formattedPoints) points for"
        ]
        if isMyTeam {
            parts.insert("Your team", at: 0)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - View Mode Enum

private enum StandingsViewMode: String, CaseIterable, Identifiable {
    case league
    case division

    var id: String { rawValue }

    var title: String {
        switch self {
        case .league: "League"
        case .division: "Divisions"
        }
    }
}

#Preview {
    NavigationStack {
        StandingsView(
            leagueStore: LeagueStore(),
            teamStore: TeamStore(),
            authStore: AuthStore(),
            router: AppRouter()
        )
    }
    .preferredColorScheme(.dark)
}
