import SwiftUI

/// Pure renderer for a list of `StandingsTeam`s. Extracted from `StandingsView`
/// during F4 so the same layout serves both the live league context and the
/// per-year historical context surfaced via the new Archive destination.
///
/// Owns the league/division view-mode toggle and the row layout — no data
/// fetching, no store dependencies beyond the data passed in. The caller is
/// responsible for providing already-built `StandingsTeam`s plus the few
/// presentation hints below.
struct StandingsListView: View {
    /// League-wide standings, pre-sorted (wins desc, then PF desc).
    let standings: [StandingsTeam]

    /// Whether the data has resolvable divisions. When false the toggle is
    /// hidden and the view renders the league-wide layout only.
    let hasDivisions: Bool

    /// Per-division grouping, only consulted when `hasDivisions == true`.
    let divisionStandings: [String: [StandingsTeam]]

    /// League-wide playoff cutoff used to draw a separator under the last
    /// playoff-bound row. Pass `nil` to suppress the divider (e.g. historical
    /// view where league metadata isn't available).
    let playoffCutoff: Int?

    /// The signed-in user's Sleeper user id, used to highlight their row.
    /// Pass `nil` to never highlight (historical view).
    let myUserId: String?

    /// Tap on a team row — typically pushes a team-detail view.
    let onTeamTap: (StandingsTeam) -> Void

    /// Long-press / context-menu "View Owner Profile". Pass an empty closure
    /// when the source can't resolve to a profile (historical view v1).
    let onProfileTap: (StandingsTeam) -> Void

    @State private var viewMode: StandingsListViewMode = .league

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
    }

    // MARK: - View Mode Toggle

    private var viewModeToggle: some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            ForEach(StandingsListViewMode.allCases) { mode in
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
                .buttonStyle(.pressableCard)
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
                    isMyTeam: team.userId == myUserId,
                    playoffCutoff: playoffCutoff
                ) {
                    onTeamTap(team)
                } onProfileTap: {
                    onProfileTap(team)
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
                    isMyTeam: team.userId == myUserId,
                    playoffCutoff: nil
                ) {
                    onTeamTap(team)
                } onProfileTap: {
                    onProfileTap(team)
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
}

// MARK: - Standings Row

private struct StandingsRowView: View {
    let team: StandingsTeam
    let rank: Int
    let isMyTeam: Bool
    let playoffCutoff: Int?
    let onTap: () -> Void
    var onProfileTap: (() -> Void)?

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
        .buttonStyle(.pressableCard)
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

/// Local toggle state for `StandingsListView`. Named to avoid collision with
/// any future shared enum and to keep the extraction self-contained.
private enum StandingsListViewMode: String, CaseIterable, Identifiable {
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
