import SwiftUI

struct DraftHistoryView: View {
    var leagueStore: LeagueStore
    var historyStore: HistoryStore
    var playerStore: PlayerStore
    var userStore: UserStore

    @Environment(\.selectedSeason) private var seasonStore: SeasonStore?

    @State private var filterMode: PickFilter = .all
    @State private var viewMode: DraftViewMode = .rounds
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
        VStack(spacing: 0) {
            controlsBar

            switch viewMode {
            case .rounds:
                ScrollView {
                    VStack(spacing: XomperTheme.Spacing.md) {
                        roundsList
                    }
                    .padding(.horizontal, XomperTheme.Spacing.md)
                    .padding(.vertical, XomperTheme.Spacing.sm)
                }
                .refreshable {
                    historyStore.reset()
                    await loadDraftHistory()
                }
            case .board:
                draftBoard
            }
        }
        .background(XomperColors.bgDark)
    }

    // MARK: - Controls bar (filter + view-mode toggle)

    private var controlsBar: some View {
        HStack(alignment: .center, spacing: XomperTheme.Spacing.sm) {
            filterPicker

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                ForEach(DraftViewMode.allCases) { mode in
                    Button {
                        let g = UIImpactFeedbackGenerator(style: .light)
                        g.impactOccurred()
                        withAnimation(XomperTheme.defaultAnimation) {
                            viewMode = mode
                        }
                    } label: {
                        Image(systemName: mode.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(viewMode == mode ? XomperColors.bgDark : XomperColors.textSecondary)
                            .frame(width: 36, height: 30)
                            .background(viewMode == mode ? XomperColors.championGold : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
                    }
                    .buttonStyle(.pressableCard)
                    .accessibilityLabel(mode.label)
                    .accessibilityAddTraits(viewMode == mode ? .isSelected : [])
                }
            }
            .padding(2)
            .background(XomperColors.surfaceLight.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md + 2))
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
        .padding(.vertical, XomperTheme.Spacing.sm)
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

    // MARK: - Draft Board (snake / linear grid)

    /// Snake-style draft board. Columns = draft slots (1...N), rows =
    /// rounds. Each pick lives at its (round, draft_slot) cell. Sleeper
    /// already records `draft_slot` correctly for both linear and
    /// snake drafts (snake's "reverse" rounds reuse the team's anchor
    /// slot), so a single grid layout works for either.
    /// Horizontal-scrollable since 12 columns is too wide for portrait.
    private var draftBoard: some View {
        let picks = historyStore.draftPicksByRound(forSeason: currentSeason)
            .flatMap(\.picks)
        let slots = Array(1...max(slotCount(picks), 1))
        let roundsByNum: [Int: [DraftHistoryRecord]] = Dictionary(grouping: picks) { $0.round }
        let sortedRounds = roundsByNum.keys.sorted()

        return ScrollView([.horizontal, .vertical], showsIndicators: false) {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                slotHeaderRow(slots: slots)
                ForEach(sortedRounds, id: \.self) { round in
                    boardRoundRow(
                        round: round,
                        slots: slots,
                        picks: roundsByNum[round] ?? []
                    )
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
        .refreshable {
            historyStore.reset()
            await loadDraftHistory()
        }
    }

    private func slotCount(_ picks: [DraftHistoryRecord]) -> Int {
        picks.map(\.draftSlot).max() ?? 12
    }

    private func slotHeaderRow(slots: [Int]) -> some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            // Round-number gutter
            Text("R")
                .font(.caption2.weight(.bold))
                .foregroundStyle(XomperColors.textMuted)
                .frame(width: 22)

            ForEach(slots, id: \.self) { slot in
                Text("\(slot)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.textMuted)
                    .frame(width: boardCellWidth, alignment: .center)
            }
        }
    }

    private func boardRoundRow(round: Int, slots: [Int], picks: [DraftHistoryRecord]) -> some View {
        let bySlot = Dictionary(uniqueKeysWithValues: picks.map { ($0.draftSlot, $0) })
        return HStack(spacing: XomperTheme.Spacing.xs) {
            Text("\(round)")
                .font(.caption.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
                .frame(width: 22)

            ForEach(slots, id: \.self) { slot in
                if let pick = bySlot[slot] {
                    boardPickCell(pick)
                } else {
                    boardEmptyCell()
                }
            }
        }
    }

    private var boardCellWidth: CGFloat { 78 }
    private var boardCellHeight: CGFloat { 64 }

    private func boardPickCell(_ pick: DraftHistoryRecord) -> some View {
        Button {
            selectPlayer(pick.playerId)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(pick.playerName.isEmpty ? "—" : pick.playerName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 3) {
                    Text(pick.playerPosition)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.bgDark)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(positionColor(pick.playerPosition))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    if !pick.playerTeam.isEmpty {
                        Text(pick.playerTeam)
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textSecondary)
                    }
                }

                Text("#\(pick.pickNo)")
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
            }
            .frame(width: boardCellWidth, height: boardCellHeight, alignment: .topLeading)
            .padding(6)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(
            "Round \(pick.round), pick \(pick.pickNo). \(pick.playerName), \(pick.playerPosition), \(pick.playerTeam)."
        )
    }

    private func boardEmptyCell() -> some View {
        RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
            .fill(XomperColors.surfaceLight.opacity(0.2))
            .frame(width: boardCellWidth, height: boardCellHeight)
    }

    private func positionColor(_ pos: String) -> Color {
        switch pos.uppercased() {
        case "QB": return Color(red: 0.95, green: 0.30, blue: 0.42)
        case "RB": return Color(red: 0.20, green: 0.80, blue: 0.50)
        case "WR": return Color(red: 0.30, green: 0.55, blue: 0.95)
        case "TE": return Color(red: 0.95, green: 0.65, blue: 0.20)
        case "K":  return Color(red: 0.65, green: 0.55, blue: 0.85)
        case "DEF","DST": return Color(red: 0.55, green: 0.55, blue: 0.55)
        default: return XomperColors.surfaceLight
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
        .buttonStyle(PressableCardButtonStyle(pressedScale: 0.95))
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Draft Pick Card

private struct DraftPickCard: View {
    let pick: DraftHistoryRecord
    let playerStore: PlayerStore
    let onTap: () -> Void

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
        .buttonStyle(.pressableCard)
        .disabled(!hasPlayerDetail)
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

// MARK: - View Mode

enum DraftViewMode: String, CaseIterable, Identifiable {
    case rounds
    case board

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rounds: "Rounds list"
        case .board: "Draft board grid"
        }
    }

    var systemImage: String {
        switch self {
        case .rounds: "list.bullet"
        case .board: "square.grid.3x3.fill"
        }
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
