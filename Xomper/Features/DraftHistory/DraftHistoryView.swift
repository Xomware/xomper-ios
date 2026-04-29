import SwiftUI

struct DraftHistoryView: View {
    var leagueStore: LeagueStore
    var historyStore: HistoryStore
    var playerStore: PlayerStore
    var userStore: UserStore

    @Environment(\.selectedSeason) private var seasonStore: SeasonStore?

    @State private var filterMode: PickFilter = .all
    @State private var selectedPlayer: Player?

    private var currentSeason: String {
        seasonStore?.selectedSeason ?? ""
    }

    var body: some View {
        Group {
            if historyStore.isLoadingDrafts {
                LoadingView(message: "Loading draft history...")
            } else if let error = historyStore.draftError {
                ErrorView(message: error.localizedDescription) {
                    Task { await loadDraftHistory() }
                }
            } else if historyStore.hasDrafts {
                draftContent
            } else {
                EmptyStateView(
                    icon: "list.clipboard",
                    title: "No Draft History",
                    message: "Draft picks will appear here once a draft is complete."
                )
            }
        }
        .task(id: leagueStore.myLeague?.leagueId) {
            await loadDraftHistory()
        }
        .sheet(item: $selectedPlayer) { player in
            PlayerDetailView(player: player, playerStore: playerStore)
        }
    }

    // MARK: - Content

    private var draftContent: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.md) {
                filterPicker
                roundsList
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
        .background(XomperColors.bgDark)
        .refreshable {
            historyStore.reset()
            await loadDraftHistory()
        }
    }

    // MARK: - Filter Picker

    private var filterPicker: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            ForEach(PickFilter.allCases, id: \.self) { filter in
                FilterButton(
                    label: filter.label,
                    isSelected: filterMode == filter
                ) {
                    withAnimation(XomperTheme.defaultAnimation) {
                        filterMode = filter
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - Rounds List

    private var roundsList: some View {
        let rounds = filteredRounds

        return LazyVStack(spacing: XomperTheme.Spacing.md) {
            if rounds.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "No Picks",
                    message: filterMode == .myPicks
                        ? "No picks found for your team this season."
                        : "No draft data for this season."
                )
            } else {
                ForEach(rounds) { round in
                    roundSection(round)
                }
            }
        }
    }

    // MARK: - Round Section

    private func roundSection(_ round: DraftRound) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text("Round \(round.round)")
                .font(.headline)
                .foregroundStyle(XomperColors.championGold)
                .padding(.leading, XomperTheme.Spacing.xs)
                .accessibilityAddTraits(.isHeader)

            ForEach(round.picks) { pick in
                DraftPickCard(pick: pick, playerStore: playerStore) {
                    selectPlayer(pick.playerId)
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadDraftHistory() async {
        // Fall back to home league if currentLeague hasn't resolved yet
        // (bootstrap-vs-view-mount race).
        guard let leagueId = leagueStore.myLeague?.leagueId else { return }

        await leagueStore.loadLeagueChain(startingFrom: leagueId)
        let chain = leagueStore.leagueChain

        guard !chain.isEmpty else { return }

        await historyStore.loadDraftHistory(chain: chain)
        // `MainShell` reacts to `historyStore.draftHistory.count` changes and
        // refreshes `seasonStore.availableSeasons` automatically — nothing to
        // seed here.
    }

    // MARK: - Filtering

    private var filteredRounds: [DraftRound] {
        let allRounds = historyStore.draftPicksByRound(forSeason: currentSeason)

        switch filterMode {
        case .all:
            return allRounds
        case .myPicks:
            guard let myUserId = userStore.myUser?.userId else { return [] }
            return allRounds.compactMap { round in
                let filtered = round.picks.filter { $0.pickedByUserId == myUserId }
                guard !filtered.isEmpty else { return nil }
                return DraftRound(round: round.round, picks: filtered)
            }
        }
    }

    // MARK: - Player Selection

    private func selectPlayer(_ playerId: String) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        selectedPlayer = playerStore.players[playerId]
    }
}

// MARK: - Pick Filter

private enum PickFilter: CaseIterable, Sendable {
    case all
    case myPicks

    var label: String {
        switch self {
        case .all: "All Picks"
        case .myPicks: "My Picks"
        }
    }
}

// MARK: - Filter Button

private struct FilterButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? XomperColors.deepNavy : XomperColors.textSecondary)
                .padding(.horizontal, XomperTheme.Spacing.sm)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .frame(minHeight: 36)
                .background(isSelected ? XomperColors.championGold : XomperColors.surfaceLight)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(XomperTheme.defaultAnimation, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Draft Pick Card

private struct DraftPickCard: View {
    let pick: DraftHistoryRecord
    let playerStore: PlayerStore
    let onTap: () -> Void

    @State private var isPressed = false

    private var teamColor: NFLTeamColor {
        NFLTeamColors.color(for: pick.playerTeam)
    }

    private var hasPlayerDetail: Bool {
        playerStore.players[pick.playerId] != nil
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: XomperTheme.Spacing.sm) {
                pickNumber
                playerImage
                playerInfo
                Spacer()
                teamLogo
            }
            .padding(XomperTheme.Spacing.sm)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                    .stroke(XomperColors.surfaceLight, lineWidth: 0.5)
            )
            .xomperShadow(.sm)
        }
        .buttonStyle(.plain)
        .disabled(!hasPlayerDetail)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(XomperTheme.defaultAnimation, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(hasPlayerDetail ? "Double tap to view player details" : "")
    }

    // MARK: - Pick Number

    private var pickNumber: some View {
        Text("\(pick.pickNo)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(XomperColors.textMuted)
            .monospacedDigit()
            .frame(width: 28, alignment: .center)
    }

    // MARK: - Player Image

    private var playerImage: some View {
        PlayerImageView(playerID: pick.playerId, size: XomperTheme.AvatarSize.md)
            .overlay(
                Circle()
                    .stroke(teamColor.primary.opacity(0.5), lineWidth: 1.5)
            )
    }

    // MARK: - Player Info

    private var playerInfo: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Text(pick.playerName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)

                if pick.isKeeper {
                    keeperBadge
                }
            }

            HStack(spacing: XomperTheme.Spacing.xs) {
                PositionBadge(position: pick.playerPosition)

                Text(pick.playerTeam.isEmpty ? "FA" : pick.playerTeam)
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
            }

            HStack(spacing: XomperTheme.Spacing.xs) {
                Text("Picked by:")
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)

                Text(pick.pickedByTeamName.isEmpty ? pick.pickedByUsername : pick.pickedByTeamName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(XomperColors.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Team Logo

    @ViewBuilder
    private var teamLogo: some View {
        if !pick.playerTeam.isEmpty,
           let url = URL(string: "https://sleepercdn.com/images/team_logos/nfl/\(pick.playerTeam.lowercased()).png") {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                default:
                    EmptyView()
                }
            }
            .frame(width: 28, height: 28)
            .opacity(0.6)
        }
    }

    // MARK: - Keeper Badge

    private var keeperBadge: some View {
        Text("K")
            .font(.caption2.weight(.bold))
            .foregroundStyle(XomperColors.deepNavy)
            .frame(width: 18, height: 18)
            .background(XomperColors.championGold)
            .clipShape(Circle())
            .accessibilityLabel("Keeper pick")
    }

    // MARK: - Card Background

    private var cardBackground: some View {
        LinearGradient(
            colors: [
                teamColor.primary.opacity(0.08),
                XomperColors.bgCard
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var desc = "Pick \(pick.pickNo), Round \(pick.round), \(pick.playerName), \(pick.playerPosition)"
        if !pick.playerTeam.isEmpty {
            desc += ", \(pick.playerTeam)"
        }
        desc += ", picked by \(pick.pickedByTeamName.isEmpty ? pick.pickedByUsername : pick.pickedByTeamName)"
        if pick.isKeeper {
            desc += ", keeper"
        }
        return desc
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DraftHistoryView(
            leagueStore: LeagueStore(),
            historyStore: HistoryStore(),
            playerStore: PlayerStore(),
            userStore: UserStore()
        )
    }
    .preferredColorScheme(.dark)
}
