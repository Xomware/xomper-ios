import SwiftUI

struct TaxiSquadView: View {
    var leagueStore: LeagueStore
    var playerStore: PlayerStore
    var authStore: AuthStore
    var taxiSquadStore: TaxiSquadStore

    @State private var groupMode: TaxiGroupMode = .owner
    @State private var sortDescending: Bool = false
    @State private var positionFilter: PositionFilter = .all
    @State private var selectedPlayer: TaxiSquadPlayer?
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if taxiSquadStore.isLoading {
                LoadingView(message: "Loading taxi squad...")
            } else if let error = taxiSquadStore.error {
                ErrorView(message: error.localizedDescription) {
                    Task { await loadTaxiSquad() }
                }
            } else if taxiSquadStore.players.isEmpty {
                EmptyStateView(
                    icon: "bus.fill",
                    title: "No Taxi Squad Players",
                    message: "No players are currently on taxi squads in this league."
                )
            } else {
                taxiSquadContent
            }
        }
        .task {
            guard !hasLoaded else { return }
            await loadTaxiSquad()
            hasLoaded = true
        }
        .sheet(item: $selectedPlayer) { player in
            TaxiStealConfirmView(
                player: player,
                taxiSquadStore: taxiSquadStore,
                leagueId: leagueStore.myLeague?.leagueId ?? "",
                leagueName: leagueStore.myLeague?.name ?? "",
                stealerName: resolvedStealerName,
                alreadyStolen: taxiSquadStore.stolenPlayerIds.contains(player.playerId),
                isOwnPlayer: player.ownerUserId == authStore.sleeperUserId
            )
        }
    }

    // MARK: - Content

    private var taxiSquadContent: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.md) {
                groupModePicker
                filterToolbar
                groupedPlayerList
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
        .background(XomperColors.bgDark)
        .refreshable {
            hasLoaded = false
            taxiSquadStore.reset()
            await loadTaxiSquad()
            hasLoaded = true
        }
    }

    // MARK: - Group Mode Picker

    private var groupModePicker: some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            ForEach(TaxiGroupMode.allCases) { mode in
                TaxiGroupModeButton(
                    mode: mode,
                    isSelected: groupMode == mode
                ) {
                    withAnimation(XomperTheme.defaultAnimation) {
                        groupMode = mode
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - Filter Toolbar

    /// Position chips + sort-direction toggle. Position chips filter the
    /// underlying player list; the sort toggle flips ordering of group
    /// headers (e.g. round 1 → 5 vs round 5 → 1, owner A → Z vs Z → A).
    private var filterToolbar: some View {
        VStack(spacing: XomperTheme.Spacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: XomperTheme.Spacing.xs) {
                    ForEach(PositionFilter.allCases) { filter in
                        FilterChip(
                            label: filter.label,
                            isSelected: positionFilter == filter
                        ) {
                            withAnimation(XomperTheme.defaultAnimation) {
                                positionFilter = filter
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    let g = UIImpactFeedbackGenerator(style: .light)
                    g.impactOccurred()
                    withAnimation(XomperTheme.defaultAnimation) {
                        sortDescending.toggle()
                    }
                } label: {
                    HStack(spacing: XomperTheme.Spacing.xs) {
                        Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                            .font(.caption.weight(.bold))
                        Text(sortDescending ? "Desc" : "Asc")
                            .font(.caption)
                    }
                    .foregroundStyle(XomperColors.textSecondary)
                    .padding(.horizontal, XomperTheme.Spacing.sm)
                    .padding(.vertical, XomperTheme.Spacing.xs)
                    .background(XomperColors.surfaceLight.opacity(0.4))
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressableCard)
                .accessibilityLabel(sortDescending ? "Sort descending" : "Sort ascending")
            }
        }
    }

    // MARK: - Grouped Player List

    private var groupedPlayerList: some View {
        LazyVStack(spacing: XomperTheme.Spacing.md) {
            switch groupMode {
            case .owner:
                ForEach(groupedByOwner, id: \.owner) { group in
                    playerSection(
                        title: group.owner,
                        subtitle: group.teamName,
                        players: group.players
                    )
                }
            case .round:
                ForEach(groupedByRound, id: \.round) { group in
                    playerSection(
                        title: group.round == -1 ? "Undrafted" : "Round \(group.round)",
                        players: group.players
                    )
                }
            case .position:
                ForEach(groupedByPosition, id: \.position) { group in
                    playerSection(
                        title: group.position,
                        players: group.players
                    )
                }
            }
        }
    }

    // MARK: - Player Section

    private func playerSection(
        title: String,
        subtitle: String? = nil,
        players: [TaxiSquadPlayer]
    ) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(XomperColors.championGold)

                if let subtitle, !subtitle.isEmpty {
                    Text("(\(subtitle))")
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textSecondary)
                }
            }
            .padding(.leading, XomperTheme.Spacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(players) { player in
                TaxiPlayerCard(
                    player: player,
                    isStolen: taxiSquadStore.stolenPlayerIds.contains(player.playerId),
                    isOwnPlayer: player.ownerUserId == authStore.sleeperUserId
                ) {
                    selectPlayer(player)
                }
            }
        }
    }

    // MARK: - Grouping Logic

    /// Player list with the active position filter applied. All grouping
    /// helpers below operate on this view, so toggling the filter
    /// shrinks every group at once.
    private var filteredPlayers: [TaxiSquadPlayer] {
        switch positionFilter {
        case .all: return taxiSquadStore.players
        case .position(let p):
            return taxiSquadStore.players.filter { $0.player.displayPosition == p }
        }
    }

    private var groupedByOwner: [(owner: String, teamName: String, players: [TaxiSquadPlayer])] {
        let players = filteredPlayers
        let owners = Set(players.map(\.ownerDisplayName))
        let sortedOwners = owners.sorted { sortDescending ? $0 > $1 : $0 < $1 }
        return sortedOwners.map { owner in
            let ownerPlayers = players.filter { $0.ownerDisplayName == owner }
            let teamName = ownerPlayers.first?.ownerTeamName ?? ""
            return (owner: owner, teamName: teamName, players: ownerPlayers)
        }.filter { !$0.players.isEmpty }
    }

    private var groupedByRound: [(round: Int, players: [TaxiSquadPlayer])] {
        let players = filteredPlayers
        let rounds = Set(players.map { $0.draftRound ?? -1 })
        let sortedRounds = rounds.sorted { a, b in
            // Undrafted (-1) always sinks to the bottom regardless of direction.
            if a == -1 { return false }
            if b == -1 { return true }
            return sortDescending ? a > b : a < b
        }
        return sortedRounds.map { round in
            let roundPlayers = players.filter { ($0.draftRound ?? -1) == round }
            return (round: round, players: roundPlayers)
        }.filter { !$0.players.isEmpty }
    }

    private var groupedByPosition: [(position: String, players: [TaxiSquadPlayer])] {
        let players = filteredPlayers
        let order = sortDescending ? ["TE", "WR", "RB", "QB"] : ["QB", "RB", "WR", "TE"]
        return order.compactMap { pos in
            let posPlayers = players.filter { $0.player.displayPosition == pos }
            guard !posPlayers.isEmpty else { return nil }
            return (position: pos, players: posPlayers)
        }
    }

    // MARK: - Actions

    private func selectPlayer(_ player: TaxiSquadPlayer) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        selectedPlayer = player
    }

    private func loadTaxiSquad() async {
        guard let leagueId = leagueStore.myLeague?.leagueId else { return }

        // Defensive preflight: TaxiSquadStore.loadTaxiSquadPlayers skips players
        // via `guard let player = playerStore.player(for:)` when the store is empty.
        // Ensure players are loaded before we ask for taxi squad members.
        if playerStore.players.isEmpty {
            await playerStore.loadPlayers()
        }

        async let playersLoad: () = taxiSquadStore.loadTaxiSquadPlayers(
            rosters: leagueStore.myLeagueRosters,
            users: leagueStore.myLeagueUsers,
            playerStore: playerStore,
            leagueId: leagueId
        )
        async let stealsLoad: () = taxiSquadStore.loadStealRequests(leagueId: leagueId)

        _ = await (playersLoad, stealsLoad)
    }

    // MARK: - Helpers

    private var resolvedStealerName: String {
        authStore.userDisplayName
            ?? authStore.userEmail?.components(separatedBy: "@").first
            ?? "Unknown"
    }
}

// MARK: - Group Mode

private enum TaxiGroupMode: String, CaseIterable, Identifiable {
    case owner
    case round = "Draft Round"
    case position

    var id: String { rawValue }

    var label: String {
        switch self {
        case .owner: "Owner"
        case .round: "Draft Round"
        case .position: "Position"
        }
    }
}

// MARK: - Group Mode Button

private struct TaxiGroupModeButton: View {
    let mode: TaxiGroupMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        } label: {
            Text(mode.label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? XomperColors.deepNavy : XomperColors.textSecondary)
                .padding(.horizontal, XomperTheme.Spacing.sm)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .frame(minHeight: 36)
                .background(isSelected ? XomperColors.championGold : XomperColors.surfaceLight)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableCardButtonStyle(pressedScale: 0.95))
        .accessibilityLabel("\(mode.label) grouping")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Taxi Player Card

private struct TaxiPlayerCard: View {
    let player: TaxiSquadPlayer
    let isStolen: Bool
    let isOwnPlayer: Bool
    let onTap: () -> Void

    private var teamColor: NFLTeamColor {
        NFLTeamColors.color(for: player.player.displayTeam)
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: XomperTheme.Spacing.sm) {
                playerImage
                playerInfo
                Spacer()
                trailingContent
            }
            .padding(XomperTheme.Spacing.md)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                    .stroke(
                        isOwnPlayer ? XomperColors.championGold.opacity(0.3) : XomperColors.surfaceLight,
                        lineWidth: isOwnPlayer ? 1 : 0.5
                    )
            )
            .xomperShadow(.sm)
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Double tap to view details")
    }

    // MARK: - Player Image

    private var playerImage: some View {
        PlayerImageView(playerID: player.playerId, size: XomperTheme.AvatarSize.md)
            .overlay(
                Circle()
                    .stroke(teamColor.primary.opacity(0.5), lineWidth: 1.5)
            )
    }

    // MARK: - Player Info

    private var playerInfo: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            Text(player.player.fullDisplayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(1)

            HStack(spacing: XomperTheme.Spacing.xs) {
                PositionBadge(position: player.player.displayPosition)

                Text(player.player.displayTeam)
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)

                if let number = player.player.number {
                    Text("#\(number)")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                }
            }

            HStack(spacing: XomperTheme.Spacing.xs) {
                Text(draftText)
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textSecondary)
            }
        }
    }

    // MARK: - Trailing Content

    @ViewBuilder
    private var trailingContent: some View {
        if isStolen {
            Text("STOLEN")
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.accentRed)
                .padding(.horizontal, XomperTheme.Spacing.sm)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .background(XomperColors.accentRed.opacity(0.15))
                .clipShape(Capsule())
                .accessibilityLabel("Steal requested")
        } else if let url = player.player.teamLogoURL {
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

    // MARK: - Helpers

    private var draftText: String {
        guard let round = player.draftRound, round > 0 else {
            return "Undrafted"
        }
        if let pick = player.draftPickNo, pick > 0 {
            return "Rd \(round), Pick \(pick)"
        }
        return "Rd \(round)"
    }

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

    private var accessibilityDescription: String {
        var parts = [
            player.player.fullDisplayName,
            player.player.displayPosition,
            player.player.displayTeam,
            "Owner: \(player.ownerDisplayName)"
        ]
        if isStolen {
            parts.append("Steal requested")
        }
        if isOwnPlayer {
            parts.insert("Your player", at: 0)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Position Filter

enum PositionFilter: Hashable, Identifiable, CaseIterable {
    case all
    case position(String)

    static var allCases: [PositionFilter] {
        [.all, .position("QB"), .position("RB"), .position("WR"), .position("TE")]
    }

    var id: String {
        switch self {
        case .all: "all"
        case .position(let p): p
        }
    }

    var label: String {
        switch self {
        case .all: "All"
        case .position(let p): p
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? XomperColors.bgDark : XomperColors.textSecondary)
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .background(isSelected ? XomperColors.championGold : XomperColors.surfaceLight.opacity(0.4))
                .clipShape(Capsule())
        }
        .buttonStyle(.pressableCard)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TaxiSquadView(
            leagueStore: LeagueStore(),
            playerStore: PlayerStore(),
            authStore: AuthStore(),
            taxiSquadStore: TaxiSquadStore()
        )
    }
    .preferredColorScheme(.dark)
}
