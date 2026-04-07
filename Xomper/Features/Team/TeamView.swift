import SwiftUI

struct TeamView: View {
    let team: StandingsTeam
    let roster: Roster
    let league: League
    let playerStore: PlayerStore

    @State private var selectedPlayer: Player?
    @State private var isRefreshing = false

    private var rosterPositions: [String] {
        league.rosterPositions ?? []
    }

    var body: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.lg) {
                teamHeader
                startersSection
                benchSection
                taxiSection
                irSection
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.bottom, XomperTheme.Spacing.xl)
        }
        .refreshable {
            await refreshRoster()
        }
        .background(XomperColors.bgDark)
        .sheet(item: $selectedPlayer) { player in
            PlayerDetailView(player: player)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Team Header

private extension TeamView {
    var teamHeader: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            HStack(spacing: XomperTheme.Spacing.md) {
                AvatarView(avatarID: team.avatarId, size: XomperTheme.AvatarSize.xl, isTeam: true)
                    .overlay(
                        Circle()
                            .stroke(XomperColors.championGold, lineWidth: 2)
                    )

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                    Text(team.teamName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(team.displayName)
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.steelBlue)

                    HStack(spacing: XomperTheme.Spacing.sm) {
                        RecordBadge(wins: team.wins, losses: team.losses, ties: team.ties)
                        streakBadge
                    }
                }

                Spacer()
            }

            HStack(spacing: XomperTheme.Spacing.sm) {
                rankBadge(
                    label: league.displayName,
                    rank: team.leagueRank
                )

                if team.hasDivision {
                    DivisionBadge(name: team.divisionName)
                    rankBadge(
                        label: team.divisionName,
                        rank: team.divisionRank
                    )
                }

                Spacer()
            }
        }
        .xomperCard()
    }

    var streakBadge: some View {
        Text(team.streak.displayString)
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(streakColor)
            .padding(.horizontal, XomperTheme.Spacing.sm)
            .padding(.vertical, XomperTheme.Spacing.xs)
            .background(streakColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.sm))
            .accessibilityLabel("Streak: \(team.streak.displayString)")
    }

    var streakColor: Color {
        switch team.streak.type {
        case .win: XomperColors.successGreen
        case .loss: XomperColors.errorRed
        case .none: XomperColors.textMuted
        }
    }

    func rankBadge(label: String, rank: Int) -> some View {
        Text("\(label): \(rank)\(ordinalSuffix(rank))")
            .font(.caption2.weight(.medium))
            .foregroundStyle(XomperColors.textSecondary)
            .padding(.horizontal, XomperTheme.Spacing.sm)
            .padding(.vertical, XomperTheme.Spacing.xs)
            .background(XomperColors.darkNavy.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.sm)
                    .stroke(XomperColors.surfaceLight, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.sm))
            .accessibilityLabel("\(label) rank: \(rank)\(ordinalSuffix(rank))")
    }

    func ordinalSuffix(_ n: Int) -> String {
        let mod100 = n % 100
        if mod100 >= 11 && mod100 <= 13 { return "th" }
        switch n % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}

// MARK: - Roster Sections

private extension TeamView {
    var sortedStarters: [RosterSlot] {
        let starterIDs = roster.starters ?? []
        // Build slots matching the league's roster position order
        let positions = rosterPositions.filter { $0 != "BN" && $0 != "IR" }
        var slots: [RosterSlot] = []

        for (index, posLabel) in positions.enumerated() {
            let playerID = index < starterIDs.count ? starterIDs[index] : nil
            let player: Player? = playerID.flatMap { id in
                id == "0" ? nil : playerStore.player(for: id)
            }
            slots.append(RosterSlot(slotLabel: posLabel, player: player))
        }
        return slots
    }

    var benchPlayers: [Player] {
        let starterSet = Set(roster.starters ?? [])
        let taxiSet = Set(roster.taxi ?? [])
        let reserveSet = Set(roster.reserve ?? [])
        return (roster.players ?? [])
            .filter { !starterSet.contains($0) && !taxiSet.contains($0) && !reserveSet.contains($0) }
            .compactMap { playerStore.player(for: $0) }
            .sorted { positionOrder($0) < positionOrder($1) }
    }

    var taxiPlayers: [Player] {
        (roster.taxi ?? [])
            .compactMap { playerStore.player(for: $0) }
            .sorted { positionOrder($0) < positionOrder($1) }
    }

    var irPlayers: [Player] {
        (roster.reserve ?? [])
            .compactMap { playerStore.player(for: $0) }
            .sorted { positionOrder($0) < positionOrder($1) }
    }

    @ViewBuilder
    var startersSection: some View {
        let slots = sortedStarters
        if !slots.isEmpty {
            rosterSection(title: "Starters") {
                ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                    if let player = slot.player {
                        PlayerRow(
                            player: player,
                            slotLabel: slot.slotLabel
                        ) {
                            selectedPlayer = player
                        }
                    } else {
                        emptySlotRow(position: slot.slotLabel)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var benchSection: some View {
        let players = benchPlayers
        if !players.isEmpty {
            rosterSection(title: "Bench") {
                ForEach(players) { player in
                    PlayerRow(player: player, slotLabel: "BN") {
                        selectedPlayer = player
                    }
                }
            }
        }
    }

    @ViewBuilder
    var taxiSection: some View {
        let players = taxiPlayers
        if !players.isEmpty {
            rosterSection(title: "Taxi Squad") {
                ForEach(players) { player in
                    PlayerRow(player: player, slotLabel: "TAXI") {
                        selectedPlayer = player
                    }
                }
            }
        }
    }

    @ViewBuilder
    var irSection: some View {
        let players = irPlayers
        if !players.isEmpty {
            rosterSection(title: "IR") {
                ForEach(players) { player in
                    PlayerRow(player: player, slotLabel: "IR") {
                        selectedPlayer = player
                    }
                }
            }
        }
    }

    func rosterSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
                .padding(.bottom, XomperTheme.Spacing.xs)
                .accessibilityAddTraits(.isHeader)

            content()
        }
    }

    func emptySlotRow(position: String) -> some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            PositionBadge(position: position)

            Text("Empty")
                .font(.subheadline)
                .foregroundStyle(XomperColors.textMuted)
                .italic()

            Spacer()
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .accessibilityLabel("Empty \(position) slot")
    }

    func positionOrder(_ player: Player) -> Int {
        let order = ["QB", "RB", "WR", "TE", "K", "DEF"]
        return order.firstIndex(of: player.displayPosition) ?? 99
    }
}

// MARK: - Refresh

private extension TeamView {
    func refreshRoster() async {
        isRefreshing = true
        await playerStore.loadPlayers()
        isRefreshing = false
    }
}

// MARK: - Supporting Types

private struct RosterSlot {
    let slotLabel: String
    let player: Player?
}

// MARK: - Position Badge

struct PositionBadge: View {
    let position: String

    private var backgroundColor: Color {
        switch position.uppercased() {
        case "QB": Color(hex: 0xD32F2F)
        case "RB": Color(hex: 0x2E7D32)
        case "WR": Color(hex: 0x1565C0)
        case "TE": Color(hex: 0xE65100)
        case "K": Color(hex: 0x6A1B9A)
        case "DEF": Color(hex: 0x546E7A)
        case "FLEX", "SUPER_FLEX", "REC_FLEX": Color(hex: 0x6D4C41)
        default: XomperColors.surfaceLight
        }
    }

    var body: some View {
        Text(positionLabel)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 24)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.sm))
            .accessibilityLabel(positionAccessibilityLabel)
    }

    private var positionLabel: String {
        switch position.uppercased() {
        case "SUPER_FLEX": "SF"
        case "REC_FLEX": "RF"
        case "FLEX": "FLX"
        default: position.uppercased()
        }
    }

    private var positionAccessibilityLabel: String {
        switch position.uppercased() {
        case "QB": "Quarterback"
        case "RB": "Running back"
        case "WR": "Wide receiver"
        case "TE": "Tight end"
        case "K": "Kicker"
        case "DEF": "Defense"
        case "FLEX": "Flex"
        case "SUPER_FLEX": "Super flex"
        case "REC_FLEX": "Receiving flex"
        case "BN": "Bench"
        case "IR": "Injured reserve"
        default: position
        }
    }
}

// MARK: - Player Row

struct PlayerRow: View {
    let player: Player
    var slotLabel: String?
    let onTap: () -> Void

    @State private var isPressed = false

    private var teamColor: NFLTeamColor {
        NFLTeamColors.color(for: player.displayTeam)
    }

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            onTap()
        }) {
            HStack(spacing: XomperTheme.Spacing.sm) {
                if let slot = slotLabel {
                    PositionBadge(position: slot)
                }

                PlayerImageView(playerID: player.playerId, size: XomperTheme.AvatarSize.sm)

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                    Text(player.fullDisplayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: XomperTheme.Spacing.xs) {
                        Text(player.displayPosition)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(XomperColors.textSecondary)

                        Text(player.displayTeam)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(XomperColors.textMuted)

                        if player.isInjured, let status = player.injuryStatus {
                            Text(status.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(XomperColors.errorRed)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
            }
            .padding(XomperTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                    .fill(XomperColors.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                            .fill(
                                LinearGradient(
                                    colors: [teamColor.primary.opacity(0.08), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(XomperTheme.defaultAnimation, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(playerAccessibilityLabel)
        .accessibilityHint("Double tap to view player details")
    }

    private var playerAccessibilityLabel: String {
        var parts = [player.fullDisplayName, player.displayPosition, player.displayTeam]
        if player.isInjured, let status = player.injuryStatus {
            parts.append("Injury: \(status)")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Preview

#Preview("Team View") {
    let store = PlayerStore()
    TeamView(
        team: StandingsTeam(
            rosterId: 1,
            userId: "user1",
            username: "domgiordano",
            displayName: "Dom",
            teamName: "Goon Squad",
            avatarId: nil,
            division: 1,
            divisionName: "East",
            divisionAvatar: nil,
            wins: 8,
            losses: 3,
            ties: 0,
            fpts: 1450.5,
            fptsAgainst: 1380.2,
            streak: Streak(type: .win, total: 3),
            leagueRank: 2,
            divisionRank: 1
        ),
        roster: Roster(
            rosterId: 1,
            ownerId: "user1",
            leagueId: "league1",
            players: [],
            starters: [],
            reserve: nil,
            taxi: nil,
            coOwners: nil,
            keepers: nil,
            settings: .previewSettings,
            metadata: nil,
            playerMap: nil
        ),
        league: League(
            leagueId: "league1",
            name: "Dynasty League",
            season: "2025",
            seasonType: "regular",
            sport: "nfl",
            status: "in_season",
            totalRosters: 12,
            shard: nil,
            draftId: nil,
            previousLeagueId: nil,
            bracketId: nil,
            groupId: nil,
            avatar: nil,
            settings: .previewSettings,
            scoringSettings: nil,
            rosterPositions: ["QB", "RB", "RB", "WR", "WR", "TE", "FLEX", "FLEX", "SUPER_FLEX", "BN", "BN", "BN", "BN", "BN", "IR"],
            metadata: nil
        ),
        playerStore: store
    )
    .preferredColorScheme(.dark)
}

// MARK: - Preview Helpers

private extension RosterSettings {
    static var previewSettings: RosterSettings {
        let json = """
        {"wins":8,"losses":3,"ties":0,"division":1,"fpts":1450,"fpts_decimal":50,"fpts_against":1380,"fpts_against_decimal":20}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(RosterSettings.self, from: json)
    }
}

private extension LeagueSettings {
    static var previewSettings: LeagueSettings {
        let json = """
        {"num_teams":12}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(LeagueSettings.self, from: json)
    }
}
