import SwiftUI

struct TeamView: View {
    let team: StandingsTeam
    let roster: Roster
    let league: League
    let playerStore: PlayerStore
    /// Shared stores added to power the Strengths + Trades tabs and
    /// the Quick Hitters strip. Quick Hitters needs dynasty values
    /// for the totalValue tile; Trades tab needs the controller to
    /// preload a recommendation before deep-linking into the Analyzer.
    let leagueStore: LeagueStore
    let valuesStore: PlayerValuesStore
    let authStore: AuthStore
    let navStore: NavigationStore
    let router: AppRouter
    let tradeController: TradeAnalyzerController

    @State private var selectedPlayer: Player?
    @State private var isRefreshing = false
    /// Active sub-section. Defaults to `.roster` — it's the
    /// highest-traffic surface and matches today's behavior.
    @State private var activeSection: TeamSection = .roster

    private var rosterPositions: [String] {
        league.rosterPositions ?? []
    }

    private var hasPlayers: Bool {
        !playerStore.players.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.lg) {
                teamHeader

                // Quick Hitters surfaces six at-a-glance stats above
                // the section picker. Hidden until both player data
                // and dynasty values are loaded — otherwise tiles
                // would show "0" placeholders.
                if hasPlayers, valuesStore.hasValues {
                    QuickHittersStrip(
                        data: quickHittersData(),
                        onTapStrength: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                activeSection = .strengths
                            }
                        }
                    )
                }

                sectionPicker

                switch activeSection {
                case .roster:
                    rosterContent
                case .strengths:
                    strengthsContent
                case .trades:
                    tradesContent
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.bottom, XomperTheme.Spacing.xl)
        }
        .refreshable {
            await refreshAll()
        }
        .task {
            if !hasPlayers {
                await playerStore.loadPlayers()
            }
            if !valuesStore.hasValues {
                await valuesStore.loadValues()
            }
        }
        .background(XomperColors.bgDark)
        .sheet(item: $selectedPlayer) { player in
            PlayerDetailView(player: player, playerStore: playerStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Section picker

    private var sectionPicker: some View {
        Picker("Section", selection: $activeSection) {
            ForEach(TeamSection.allCases) { section in
                Text(section.label).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, XomperTheme.Spacing.xs)
    }

    // MARK: - Roster section content

    @ViewBuilder
    private var rosterContent: some View {
        if !hasPlayers && (playerStore.isLoading || isRefreshing) {
            LoadingView(message: "Loading players...")
                .frame(height: 200)
        } else if !hasPlayers {
            VStack(spacing: XomperTheme.Spacing.md) {
                EmptyStateView(
                    icon: "arrow.clockwise",
                    title: "Players Not Loaded",
                    message: "Player data hasn't loaded yet."
                )
                Button {
                    Task { await refreshAll() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.bgDark)
                        .padding(.horizontal, XomperTheme.Spacing.lg)
                        .padding(.vertical, XomperTheme.Spacing.sm)
                        .background(XomperColors.championGold)
                        .clipShape(Capsule())
                }
                .accessibilityLabel("Retry loading players")
            }
        } else {
            startersSection
            benchSection
            taxiSection
            irSection
        }
    }

    // MARK: - Strengths section content

    @ViewBuilder
    private var strengthsContent: some View {
        if !valuesStore.hasValues && valuesStore.isLoading {
            LoadingView(message: "Loading player values…")
                .frame(height: 200)
        } else if let my = myAnalysis() {
            VStack(spacing: XomperTheme.Spacing.lg) {
                HexagonChartView(
                    primary: my.hexAxes,
                    comparison: nil,
                    leagueAverage: leagueAverages(),
                    axisMaxes: axisMaxes()
                )
                .frame(maxWidth: .infinity)

                PositionBreakdownCard(
                    my: my,
                    opp: nil,
                    averages: leagueAverages(),
                    maxes: axisMaxes()
                )
            }
        } else {
            EmptyStateView(
                icon: "chart.pie",
                title: "Strengths Unavailable",
                message: "Couldn't compute your team's strength profile yet. Pull to refresh."
            )
        }
    }

    // MARK: - Trades section content

    @ViewBuilder
    private var tradesContent: some View {
        if !valuesStore.hasValues && valuesStore.isLoading {
            LoadingView(message: "Loading player values…")
                .frame(height: 200)
        } else if let my = myAnalysis() {
            let recs = RecommendedTradeBuilder.recommend(
                myAnalysis: my,
                analyses: allAnalyses(),
                rosters: leagueStore.myLeagueRosters,
                playerStore: playerStore,
                valuesStore: valuesStore
            )
            if recs.isEmpty {
                EmptyStateView(
                    icon: "arrow.left.arrow.right.circle",
                    title: "No Recommendations",
                    message: "We didn't find any fair-value swaps that improve your weak positions right now. Check back after your next move."
                )
            } else {
                VStack(spacing: XomperTheme.Spacing.md) {
                    Text("Tap a recommendation to open it in the Trade Analyzer.")
                        .font(.caption)
                        .foregroundStyle(XomperColors.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, XomperTheme.Spacing.xs)

                    ForEach(recs) { rec in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            tradeController.preload(rec)
                            navStore.select(.teamAnalyzer, router: router)
                        } label: {
                            RecommendedTradeCard(rec)
                        }
                        .buttonStyle(.pressableCard)
                    }
                }
            }
        } else {
            EmptyStateView(
                icon: "arrow.left.arrow.right.circle",
                title: "Trades Unavailable",
                message: "Couldn't compute trade recommendations yet. Pull to refresh."
            )
        }
    }

    // MARK: - Refresh

    private func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        async let players: () = playerStore.loadPlayers()
        async let values:  () = valuesStore.loadValues(forceRefresh: true)
        _ = await (players, values)
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
            SectionHeader(title: title)
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

// MARK: - Analyses + Quick Hitters builders

private extension TeamView {

    /// Build per-team analyses once. Cheap enough to re-run per body
    /// invocation — matches `TeamAnalyzerView.content`'s pattern.
    /// Returns an empty array when prerequisites haven't loaded.
    func allAnalyses() -> [TeamAnalysis] {
        guard !leagueStore.myLeagueRosters.isEmpty, valuesStore.hasValues else {
            return []
        }
        return TeamAnalysisBuilder.build(
            rosters: leagueStore.myLeagueRosters,
            users: leagueStore.myLeagueUsers,
            playerStore: playerStore,
            valuesStore: valuesStore
        )
    }

    /// My team's analysis. Falls back to the first analysis if the
    /// signed-in user isn't owner of any roster (shouldn't happen in
    /// the home league, but defensive).
    func myAnalysis() -> TeamAnalysis? {
        let analyses = allAnalyses()
        guard let myUserId = authStore.sleeperUserId else { return analyses.first }
        return analyses.first { $0.userId == myUserId } ?? analyses.first
    }

    func axisMaxes() -> [String: Int] {
        TeamAnalysisBuilder.axisMaxes(allAnalyses())
    }

    func leagueAverages() -> [TeamAnalysis.HexAxis] {
        TeamAnalysisBuilder.leagueAverageAxes(allAnalyses())
    }

    /// Builds the Quick Hitters payload from `team`, the cached
    /// analyses, and `leagueStore.myLeagueRosters`. Safe to call when
    /// analyses are empty — the strength tiles fall back to a "—"
    /// placeholder.
    func quickHittersData() -> QuickHittersData {
        let analyses = allAnalyses()
        let mine = analyses.first { $0.userId == authStore.sleeperUserId } ?? analyses.first
        let averages = TeamAnalysisBuilder.leagueAverageAxes(analyses)

        // Record + streak. The streak tile coloring matches the
        // existing teamHeader's `streakBadge`.
        let recordStr: String
        if team.ties > 0 {
            recordStr = "\(team.wins)-\(team.losses)-\(team.ties)"
        } else {
            recordStr = "\(team.wins)-\(team.losses)"
        }
        let streakLabel = team.streak.displayString
        let streakAccent: Color? = {
            switch team.streak.type {
            case .win:  return XomperColors.successGreen
            case .loss: return XomperColors.errorRed
            case .none: return nil
            }
        }()

        // League rank ordinal.
        let rank = team.leagueRank
        let rankStr = "\(rank)\(ordinalSuffix(rank))"
        let isTop3 = rank > 0 && rank <= 3

        // Dynasty total + delta vs league mean.
        let total = mine?.totalValue ?? 0
        let totalDisplay = formatThousands(total)
        let totalDelta: Int? = {
            guard !analyses.isEmpty else { return nil }
            let mean = analyses.map(\.totalValue).reduce(0, +) / max(analyses.count, 1)
            return total - mean
        }()

        // Season FPTS straight from standings.
        let fptsDisplay = formatFpts(team.fpts)

        // Best / worst axis by ratio to league average.
        let (bestLabel, weakestLabel) = bestAndWeakest(
            for: mine?.hexAxes ?? [],
            averages: averages
        )

        return QuickHittersData(
            record: recordStr,
            streakLabel: streakLabel,
            streakAccent: streakAccent,
            rankDisplay: rankStr,
            rankIsTop3: isTop3,
            totalValueDisplay: totalDisplay,
            totalValueDelta: totalDelta,
            fptsDisplay: fptsDisplay,
            bestPosition: bestLabel,
            weakestPosition: weakestLabel
        )
    }

    /// Compute the axis labels with the highest / lowest ratio of
    /// `axis.value` to the league average. Falls back to "—" when
    /// the data isn't ready.
    func bestAndWeakest(
        for axes: [TeamAnalysis.HexAxis],
        averages: [TeamAnalysis.HexAxis]
    ) -> (best: String, weakest: String) {
        guard !axes.isEmpty, !averages.isEmpty else {
            return ("—", "—")
        }
        let avgByLabel: [String: Int] = Dictionary(
            uniqueKeysWithValues: averages.map { ($0.label, $0.value) }
        )
        var bestLabel = axes[0].label
        var weakestLabel = axes[0].label
        var bestRatio: Double = -.infinity
        var weakestRatio: Double = .infinity
        for axis in axes {
            let avg = max(avgByLabel[axis.label] ?? 0, 1)
            let ratio = Double(axis.value) / Double(avg)
            if ratio > bestRatio {
                bestRatio = ratio
                bestLabel = axis.label
            }
            if ratio < weakestRatio {
                weakestRatio = ratio
                weakestLabel = axis.label
            }
        }
        return (bestLabel, weakestLabel)
    }

    func formatThousands(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    func formatFpts(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}

// MARK: - Section enum

/// Three top-level tabs inside My Team. Roster leads (highest-traffic
/// surface); Strengths and Trades follow in dependency order
/// (Strengths reads the data Trades acts on).
enum TeamSection: String, CaseIterable, Identifiable, Hashable {
    case roster
    case strengths
    case trades

    var id: String { rawValue }

    var label: String {
        switch self {
        case .roster:    "Roster"
        case .strengths: "Strengths"
        case .trades:    "Trades"
        }
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
        .buttonStyle(PressableCardButtonStyle(pressedScale: 0.97))
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
        playerStore: store,
        leagueStore: LeagueStore(),
        valuesStore: PlayerValuesStore(),
        authStore: AuthStore(),
        navStore: NavigationStore(),
        router: AppRouter(),
        tradeController: TradeAnalyzerController()
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
