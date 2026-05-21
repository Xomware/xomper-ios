import SwiftUI

/// Horizontal scroll of all 12 team chips — avatar + team name + W-L.
/// Tapping a chip pushes the team detail route. Pure read-only surface
/// for the Landing page; no internal state beyond the derived
/// `[StandingsTeam]` array.
///
/// In offseason (`!nflStateStore.isRegularSeason`) or when standings
/// haven't loaded yet, renders a compact empty-state card instead so
/// the slot is always populated.
struct StandingsScrollBar: View {
    var leagueStore: LeagueStore
    var nflStateStore: NflStateStore
    var authStore: AuthStore
    var router: AppRouter

    @State private var standings: [StandingsTeam] = []

    var body: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            sectionHeader

            if !nflStateStore.isRegularSeason {
                offseasonEmptyState
            } else if standings.isEmpty {
                loadingPlaceholder
            } else {
                chipScroller
            }
        }
        .task(id: leagueStore.myLeague?.leagueId) {
            buildStandings()
        }
        .onChange(of: leagueStore.myLeagueRosters.count) { _, _ in
            buildStandings()
        }
        .onChange(of: leagueStore.myLeagueUsers.count) { _, _ in
            buildStandings()
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            Image(systemName: "list.number")
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.textSecondary)
            Text("STANDINGS")
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(XomperColors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, XomperTheme.Spacing.xs)
        .accessibilityHidden(true)
    }

    // MARK: - Chip scroller

    private var chipScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XomperTheme.Spacing.sm) {
                ForEach(standings) { team in
                    teamChip(team)
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.xs)
        }
    }

    private func teamChip(_ team: StandingsTeam) -> some View {
        let isMine = team.userId == authStore.sleeperUserId

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            router.navigate(to: .teamDetail(rosterId: team.rosterId))
        } label: {
            HStack(spacing: XomperTheme.Spacing.sm) {
                AvatarView(
                    avatarID: team.avatarId,
                    size: XomperTheme.AvatarSize.sm,
                    isTeam: true
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(team.teamName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)
                    Text(team.record)
                        .font(.caption2)
                        .foregroundStyle(
                            isMine ? XomperColors.championGold : XomperColors.textSecondary
                        )
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.sm)
            .padding(.vertical, XomperTheme.Spacing.sm)
            .frame(minWidth: 140, alignment: .leading)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                    .strokeBorder(
                        isMine ? XomperColors.championGold.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(team.teamName), \(team.record)\(isMine ? ", your team" : "")")
        .accessibilityHint("Double tap to open team")
    }

    // MARK: - Empty / loading states

    private var offseasonEmptyState: some View {
        emptyCard(
            icon: "moon.zzz.fill",
            message: "Standings unlock once Week 1 kicks off."
        )
    }

    private var loadingPlaceholder: some View {
        emptyCard(
            icon: "list.number",
            message: "Loading standings…"
        )
    }

    private func emptyCard(icon: String, message: String) -> some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textMuted)
            Text(message)
                .font(.caption)
                .foregroundStyle(XomperColors.textSecondary)
            Spacer()
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    // MARK: - Build

    private func buildStandings() {
        guard let league = leagueStore.myLeague else {
            standings = []
            return
        }
        standings = StandingsBuilder.buildStandings(
            rosters: leagueStore.myLeagueRosters,
            users: leagueStore.myLeagueUsers,
            league: league
        )
    }
}

#Preview {
    StandingsScrollBar(
        leagueStore: LeagueStore(),
        nflStateStore: NflStateStore(),
        authStore: AuthStore(),
        router: AppRouter()
    )
    .padding()
    .background(XomperColors.bgDark)
    .preferredColorScheme(.dark)
}
