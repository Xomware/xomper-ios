import SwiftUI

struct PlayoffBracketView: View {
    var leagueStore: LeagueStore
    var historyStore: HistoryStore
    var playerStore: PlayerStore

    @State private var standings: [StandingsTeam] = []
    @State private var bracketType: BracketType = .winners
    @State private var selectedMatch: PlayoffBracketMatch?
    @State private var cardFrames: [String: CGRect] = [:]

    private var seedMap: [Int: Int] {
        Dictionary(uniqueKeysWithValues: standings.map { ($0.rosterId, $0.leagueRank) })
    }

    /// First NFL week of the playoffs, parsed from `league.settings.additional_settings.playoff_week_start`.
    /// Used by the match detail sheet to fetch real per-team scores.
    private var playoffWeekStart: Int? {
        guard let value = leagueStore.myLeague?.settings?.additionalSettings?["playoff_week_start"] else {
            return nil
        }
        if let i = value.intValue { return i }
        if let d = value.doubleValue { return Int(d) }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.lg) {
                if leagueStore.isLoadingBrackets {
                    LoadingView(message: "Loading bracket...")
                } else if let error = leagueStore.bracketError {
                    ErrorView(message: error.localizedDescription) {
                        Task { await loadBrackets() }
                    }
                } else if let winners = leagueStore.winnersBracket {
                    bracketToggle
                    bracketContent(winners)
                } else {
                    EmptyStateView(
                        icon: "trophy.fill",
                        title: "No Bracket Available",
                        message: "Playoff brackets will appear once the season is configured."
                    )
                }
            }
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
        .background(XomperColors.bgDark)
        .refreshable {
            await loadBrackets()
        }
        .onAppear {
            buildStandings()
            if leagueStore.winnersBracket == nil {
                Task { await loadBrackets() }
            }
        }
        .sheet(item: $selectedMatch) { match in
            NavigationStack {
                BracketMatchDetailSheet(
                    match: match,
                    standings: standings,
                    leagueId: leagueStore.myLeague?.leagueId,
                    playoffWeekStart: playoffWeekStart,
                    season: leagueStore.myLeague?.season,
                    historyStore: historyStore,
                    playerStore: playerStore
                )
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Bracket Toggle

    private var bracketToggle: some View {
        HStack(spacing: XomperTheme.Spacing.xs) {
            ForEach(BracketType.allCases) { type in
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(XomperTheme.defaultAnimation) {
                        bracketType = type
                        cardFrames.removeAll()
                    }
                } label: {
                    Text(type.title)
                        .font(.subheadline)
                        .fontWeight(bracketType == type ? .semibold : .regular)
                        .foregroundStyle(bracketType == type ? XomperColors.deepNavy : XomperColors.textSecondary)
                        .padding(.horizontal, XomperTheme.Spacing.md)
                        .padding(.vertical, XomperTheme.Spacing.sm)
                        .frame(minHeight: XomperTheme.minTouchTarget)
                        .background(bracketType == type ? XomperColors.championGold : XomperColors.surfaceLight)
                        .clipShape(Capsule())
                }
                .buttonStyle(.pressableCard)
                .accessibilityLabel(type.title)
                .accessibilityAddTraits(bracketType == type ? .isSelected : [])
            }
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    // MARK: - Bracket Content

    @ViewBuilder
    private func bracketContent(_ winners: [PlayoffBracketMatch]) -> some View {
        let matches: [PlayoffBracketMatch] = {
            switch bracketType {
            case .winners: return winners
            case .consolation: return leagueStore.losersBracket ?? []
            }
        }()

        let rounds = groupByRound(matches)

        if rounds.isEmpty {
            EmptyStateView(
                icon: bracketType == .winners ? "trophy.fill" : "figure.run",
                title: "No \(bracketType.title) Matches",
                message: "This bracket has no matches yet."
            )
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                BracketGridView(
                    rounds: rounds,
                    cardFrames: $cardFrames,
                    selectedMatch: $selectedMatch,
                    standings: standings,
                    seedMap: seedMap,
                    teamForRoster: teamForRoster,
                    teamDisplayName: teamDisplayName
                )
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.bottom, XomperTheme.Spacing.md)
            }
        }
    }

    // MARK: - Helpers

    private func teamDisplayName(rosterId: Int?, source: BracketSource?) -> String {
        if let rosterId, let team = teamForRoster(rosterId) {
            return team.teamName
        }
        if let rosterId {
            return "Roster \(rosterId)"
        }
        if let source {
            if let w = source.winnerOfMatch {
                return "W of Match \(w)"
            }
            if let l = source.loserOfMatch {
                return "L of Match \(l)"
            }
        }
        return "TBD"
    }

    private func teamForRoster(_ rosterId: Int?) -> StandingsTeam? {
        guard let rosterId else { return nil }
        return standings.first { $0.rosterId == rosterId }
    }

    private func groupByRound(_ matches: [PlayoffBracketMatch]) -> [BracketRound] {
        var roundMap: [Int: [PlayoffBracketMatch]] = [:]
        for match in matches {
            roundMap[match.round, default: []].append(match)
        }
        let minRound = roundMap.keys.min() ?? 1
        return roundMap.keys.sorted().map { round in
            BracketRound(round: round, matches: roundMap[round] ?? [], minRound: minRound)
        }
    }

    private func buildStandings() {
        guard let league = leagueStore.myLeague else { return }
        standings = StandingsBuilder.buildStandings(
            rosters: leagueStore.myLeagueRosters,
            users: leagueStore.myLeagueUsers,
            league: league
        )
    }

    private func loadBrackets() async {
        guard let league = leagueStore.myLeague else { return }
        await leagueStore.fetchBrackets(leagueId: league.leagueId)
    }
}

// MARK: - Bracket Grid with Connector Lines

private struct BracketGridView: View {
    @Binding var cardFrames: [String: CGRect]
    @Binding var selectedMatch: PlayoffBracketMatch?

    let rounds: [BracketRound]
    let standings: [StandingsTeam]
    let seedMap: [Int: Int]
    let teamForRoster: (Int?) -> StandingsTeam?
    let teamDisplayName: (Int?, BracketSource?) -> String

    private static let cardWidth: CGFloat = 200
    private static let roundSpacing: CGFloat = XomperTheme.Spacing.xxl

    init(
        rounds: [BracketRound],
        cardFrames: Binding<[String: CGRect]>,
        selectedMatch: Binding<PlayoffBracketMatch?>,
        standings: [StandingsTeam],
        seedMap: [Int: Int],
        teamForRoster: @escaping (Int?) -> StandingsTeam?,
        teamDisplayName: @escaping (Int?, BracketSource?) -> String
    ) {
        self.rounds = rounds
        self._cardFrames = cardFrames
        self._selectedMatch = selectedMatch
        self.standings = standings
        self.seedMap = seedMap
        self.teamForRoster = teamForRoster
        self.teamDisplayName = teamDisplayName
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Connector lines layer
            connectorLines

            // Cards layer
            HStack(alignment: .top, spacing: Self.roundSpacing) {
                ForEach(rounds, id: \.round) { roundData in
                    roundColumn(roundData)
                }
            }
        }
        .coordinateSpace(name: "bracket")
    }

    // MARK: - Round Column

    private func roundColumn(_ roundData: BracketRound) -> some View {
        let roundIndex = roundData.round - (rounds.first?.round ?? 1)
        let verticalSpacing = verticalSpacingFor(roundIndex: roundIndex)

        return VStack(spacing: verticalSpacing) {
            Text(roundData.label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(XomperColors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.bottom, XomperTheme.Spacing.xs)

            ForEach(roundData.matches) { match in
                matchCard(match, isFirstRound: roundData.round == roundData.minRound)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(
                                    key: CardFramePreferenceKey.self,
                                    value: [match.id: geo.frame(in: .named("bracket"))]
                                )
                        }
                    )
            }
        }
        .frame(width: Self.cardWidth)
        .onPreferenceChange(CardFramePreferenceKey.self) { frames in
            cardFrames.merge(frames) { _, new in new }
        }
    }

    private func verticalSpacingFor(roundIndex: Int) -> CGFloat {
        switch roundIndex {
        case 0: return XomperTheme.Spacing.md
        case 1: return XomperTheme.Spacing.xxl + XomperTheme.Spacing.md
        case 2: return XomperTheme.Spacing.xxxl + XomperTheme.Spacing.xxl
        default: return XomperTheme.Spacing.xxxl * 2
        }
    }

    // MARK: - Connector Lines

    private var connectorLines: some View {
        Canvas { context, _ in
            let lineColor = XomperColors.surfaceLight
            for roundData in rounds {
                for match in roundData.matches {
                    drawConnectorsForMatch(match, in: &context, color: lineColor)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawConnectorsForMatch(
        _ match: PlayoffBracketMatch,
        in context: inout GraphicsContext,
        color: Color
    ) {
        // Draw lines from source matches to this match
        let targetFrame = cardFrames[match.id]
        guard let targetFrame else { return }

        let sources: [(BracketSource?, Bool)] = [
            (match.team1From, true),
            (match.team2From, false)
        ]

        for (source, isTop) in sources {
            guard let source else { continue }
            let sourceMatchId = sourceMatchIdString(source: source, currentRound: match.round)
            guard let sourceFrame = cardFrames[sourceMatchId] else { continue }

            let startX = sourceFrame.maxX
            let startY = sourceFrame.midY
            let endX = targetFrame.minX
            let endY = isTop ? targetFrame.minY + targetFrame.height * 0.25
                             : targetFrame.minY + targetFrame.height * 0.75
            let midX = (startX + endX) / 2

            var path = Path()
            path.move(to: CGPoint(x: startX, y: startY))
            path.addLine(to: CGPoint(x: midX, y: startY))
            path.addLine(to: CGPoint(x: midX, y: endY))
            path.addLine(to: CGPoint(x: endX, y: endY))

            context.stroke(
                path,
                with: .color(color),
                lineWidth: 1.5
            )
        }
    }

    private func sourceMatchIdString(source: BracketSource, currentRound: Int) -> String {
        let sourceRound = currentRound - 1
        if let matchNum = source.winnerOfMatch {
            return "r\(sourceRound)-m\(matchNum)"
        }
        if let matchNum = source.loserOfMatch {
            return "r\(sourceRound)-m\(matchNum)"
        }
        return ""
    }

    // MARK: - Match Card

    private func matchCard(_ match: PlayoffBracketMatch, isFirstRound: Bool) -> some View {
        let isChampionship = match.placement == 1

        return Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            selectedMatch = match
        } label: {
            VStack(spacing: 0) {
                if let label = matchLabel(match) {
                    Text(label)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(isChampionship ? XomperColors.championGold : XomperColors.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .padding(.vertical, XomperTheme.Spacing.xs)
                        .frame(maxWidth: .infinity)
                        .background(
                            isChampionship
                                ? XomperColors.championGold.opacity(0.1)
                                : XomperColors.surfaceLight.opacity(0.3)
                        )
                }

                teamRow(
                    rosterId: match.team1RosterId,
                    source: match.team1From,
                    isWinner: match.winnerRosterId != nil && match.winnerRosterId == match.team1RosterId,
                    isLoser: match.winnerRosterId != nil && match.winnerRosterId != match.team1RosterId,
                    showSeed: isFirstRound
                )

                Divider()
                    .background(XomperColors.surfaceLight.opacity(0.3))

                teamRow(
                    rosterId: match.team2RosterId,
                    source: match.team2From,
                    isWinner: match.winnerRosterId != nil && match.winnerRosterId == match.team2RosterId,
                    isLoser: match.winnerRosterId != nil && match.winnerRosterId != match.team2RosterId,
                    showSeed: isFirstRound
                )
            }
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                    .stroke(
                        isChampionship
                            ? XomperColors.championGold.opacity(0.5)
                            : XomperColors.surfaceLight.opacity(0.3),
                        lineWidth: isChampionship ? 2 : 1
                    )
            )
            .xomperShadow(.sm)
        }
        .buttonStyle(BracketCardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(matchAccessibilityLabel(match))
        .accessibilityHint("Double tap to view match details")
    }

    // MARK: - Team Row

    private func teamRow(
        rosterId: Int?,
        source: BracketSource?,
        isWinner: Bool,
        isLoser: Bool,
        showSeed: Bool
    ) -> some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            teamAvatar(rosterId: rosterId)
                .frame(width: 28, height: 28)

            Text(teamDisplayName(rosterId, source))
                .font(.subheadline)
                .fontWeight(isWinner ? .bold : .regular)
                .foregroundStyle(
                    isWinner ? XomperColors.successGreen :
                    isLoser ? XomperColors.textMuted :
                    XomperColors.textPrimary
                )
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showSeed, let rosterId, let seed = seedMap[rosterId] {
                Text("#\(seed)")
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundStyle(XomperColors.textMuted)
                    .padding(.horizontal, XomperTheme.Spacing.xs)
                    .padding(.vertical, XomperTheme.Spacing.xs)
                    .background(XomperColors.surfaceLight.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.sm))
            }
        }
        .padding(.horizontal, XomperTheme.Spacing.sm)
        .padding(.vertical, 10)
        .background(isWinner ? XomperColors.successGreen.opacity(0.1) : .clear)
        .opacity(isLoser ? 0.6 : 1.0)
    }

    // MARK: - Team Avatar

    private func teamAvatar(rosterId: Int?) -> some View {
        Group {
            if let team = teamForRoster(rosterId) {
                AsyncImage(url: team.avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundStyle(XomperColors.textMuted)
                }
            } else {
                Image(systemName: "questionmark.circle.fill")
                    .resizable()
                    .foregroundStyle(XomperColors.textMuted)
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(XomperColors.surfaceLight, lineWidth: 1))
    }

    // MARK: - Label Helpers

    private func matchLabel(_ match: PlayoffBracketMatch) -> String? {
        switch match.placement {
        case 1: return "Championship"
        case 3: return "3rd Place"
        case 5: return "5th Place"
        case 7: return "7th Place"
        default: return nil
        }
    }

    private func matchAccessibilityLabel(_ match: PlayoffBracketMatch) -> String {
        let t1 = teamDisplayName(match.team1RosterId, match.team1From)
        let t2 = teamDisplayName(match.team2RosterId, match.team2From)
        let label = matchLabel(match).map { "\($0): " } ?? ""
        if let winnerId = match.winnerRosterId {
            let winner = teamDisplayName(winnerId, nil)
            return "\(label)\(t1) vs \(t2), winner: \(winner)"
        }
        return "\(label)\(t1) vs \(t2)"
    }
}

// MARK: - Button Style

private struct BracketCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preference Key for Card Frames

private struct CardFramePreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Match Detail Sheet

private struct BracketMatchDetailSheet: View {
    let match: PlayoffBracketMatch
    let standings: [StandingsTeam]
    let leagueId: String?
    let playoffWeekStart: Int?
    let season: String?
    var historyStore: HistoryStore
    var playerStore: PlayerStore

    @Environment(\.dismiss) private var dismiss

    @State private var team1Points: Double?
    @State private var team2Points: Double?
    @State private var isLoadingScores = false
    @State private var matchupId: Int?

    private let apiClient: SleeperAPIClientProtocol = SleeperAPIClient()

    /// NFL week this bracket round maps to. Sleeper's default is 1 round
    /// = 1 week, so round 1 → playoff_week_start, round 2 → +1, etc.
    /// Multi-week rounds (`playoff_round_type=1` two-week rounds) aren't
    /// modeled here — points display still works for the second week
    /// since most leagues only score the final week.
    private var matchWeek: Int? {
        guard let start = playoffWeekStart else { return nil }
        return start + match.round - 1
    }

    private var team1: StandingsTeam? {
        guard let id = match.team1RosterId else { return nil }
        return standings.first { $0.rosterId == id }
    }

    private var team2: StandingsTeam? {
        guard let id = match.team2RosterId else { return nil }
        return standings.first { $0.rosterId == id }
    }

    private var isChampionship: Bool { match.placement == 1 }

    var body: some View {
        VStack(spacing: XomperTheme.Spacing.lg) {
            if let label = placementLabel {
                HStack(spacing: XomperTheme.Spacing.xs) {
                    if isChampionship {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(XomperColors.championGold)
                    }
                    Text(label)
                        .font(.headline)
                        .foregroundStyle(isChampionship ? XomperColors.championGold : XomperColors.textSecondary)
                }
            }

            HStack(alignment: .top, spacing: XomperTheme.Spacing.md) {
                teamColumn(
                    team: team1,
                    rosterId: match.team1RosterId,
                    isWinner: match.winnerRosterId == match.team1RosterId,
                    points: team1Points
                )
                vsColumn
                teamColumn(
                    team: team2,
                    rosterId: match.team2RosterId,
                    isWinner: match.winnerRosterId == match.team2RosterId,
                    points: team2Points
                )
            }
            .padding(XomperTheme.Spacing.md)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                    .stroke(
                        isChampionship ? XomperColors.championGold.opacity(0.5) : XomperColors.surfaceLight.opacity(0.3),
                        lineWidth: isChampionship ? 2 : 1
                    )
            )

            if isLoadingScores {
                ProgressView()
                    .tint(XomperColors.championGold)
            } else if match.winnerRosterId == nil && team1Points == nil && team2Points == nil {
                Text("Match not yet played")
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textMuted)
            }

            if let week = matchWeek {
                Text("Week \(week)")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
            }

            if let lineupRecord = derivedLineupRecord() {
                NavigationLink {
                    MatchupDetailView(
                        record: lineupRecord,
                        historyStore: historyStore,
                        playerStore: playerStore
                    )
                } label: {
                    Label("View Player Lineups", systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.bgDark)
                        .padding(.horizontal, XomperTheme.Spacing.lg)
                        .padding(.vertical, XomperTheme.Spacing.sm)
                        .background(XomperColors.championGold)
                        .clipShape(Capsule())
                }
                .accessibilityHint("Opens player lineups and per-player points for this matchup")
            }

            Spacer()
        }
        .task(id: match.id) {
            await loadScores()
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle("Match Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .foregroundStyle(XomperColors.championGold)
            }
        }
    }

    private func teamColumn(team: StandingsTeam?, rosterId: Int?, isWinner: Bool, points: Double?) -> some View {
        let hasWinner = match.winnerRosterId != nil
        let isLoser = hasWinner && !isWinner

        return VStack(spacing: XomperTheme.Spacing.sm) {
            if let team {
                AsyncImage(url: team.avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundStyle(XomperColors.textMuted)
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .overlay(Circle().stroke(isWinner ? XomperColors.successGreen : XomperColors.surfaceLight, lineWidth: 2))

                Text(team.teamName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isWinner ? XomperColors.successGreen : isLoser ? XomperColors.textMuted : XomperColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let points {
                    Text(String(format: "%.1f pts", points))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(isWinner ? XomperColors.championGold : XomperColors.textPrimary)
                        .monospacedDigit()
                }

                Text(team.record)
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)

                if let seed = standings.first(where: { $0.rosterId == team.rosterId })?.leagueRank {
                    Text("Seed #\(seed)")
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .foregroundStyle(XomperColors.textMuted)
                        .padding(.horizontal, XomperTheme.Spacing.sm)
                        .padding(.vertical, XomperTheme.Spacing.xs)
                        .background(XomperColors.surfaceLight.opacity(0.3))
                        .clipShape(Capsule())
                }

                if isWinner {
                    Text("WINNER")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(XomperColors.deepNavy)
                        .padding(.horizontal, XomperTheme.Spacing.sm)
                        .padding(.vertical, XomperTheme.Spacing.xs)
                        .background(XomperColors.championGold)
                        .clipShape(Capsule())
                }
            } else {
                Image(systemName: "questionmark.circle.fill")
                    .resizable()
                    .frame(width: 48, height: 48)
                    .foregroundStyle(XomperColors.textMuted)

                Text("TBD")
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(isLoser ? 0.6 : 1.0)
    }

    /// Synthesize a `MatchupHistoryRecord` for this bracket match so
    /// `MatchupDetailView` can render player-level lineups + points.
    /// Returns nil until both teams' roster data and the matchup_id are
    /// resolved via the loadScores fetch. The record is ad-hoc — not
    /// stored anywhere — and is purely a vehicle for the detail view's
    /// existing fetch flow (it calls historyStore.fetchRawMatchups(
    /// leagueId:week:) using these fields).
    private func derivedLineupRecord() -> MatchupHistoryRecord? {
        guard let leagueId,
              let week = matchWeek,
              let mid = matchupId,
              let r1 = match.team1RosterId,
              let r2 = match.team2RosterId,
              let team1 = standings.first(where: { $0.rosterId == r1 }),
              let team2 = standings.first(where: { $0.rosterId == r2 }) else {
            return nil
        }

        return MatchupHistoryRecord(
            leagueId: leagueId,
            season: season ?? "",
            week: week,
            matchupId: mid,
            teamARosterId: r1,
            teamAUserId: team1.userId,
            teamAUsername: team1.username,
            teamATeamName: team1.teamName,
            teamAPoints: team1Points ?? 0,
            teamBRosterId: r2,
            teamBUserId: team2.userId,
            teamBUsername: team2.username,
            teamBTeamName: team2.teamName,
            teamBPoints: team2Points ?? 0,
            winnerRosterId: match.winnerRosterId,
            isPlayoff: true,
            isChampionship: match.placement == 1,
            teamADivision: 0,
            teamBDivision: 0
        )
    }

    private func loadScores() async {
        guard let leagueId, let week = matchWeek,
              let r1 = match.team1RosterId, let r2 = match.team2RosterId else { return }
        isLoadingScores = true
        defer { isLoadingScores = false }

        do {
            let raw = try await apiClient.fetchLeagueMatchups(leagueId, week: week)
            // Find the matchup_id that contains both r1 and r2
            var grouped: [Int: [Matchup]] = [:]
            for m in raw {
                guard let mid = m.matchupId else { continue }
                grouped[mid, default: []].append(m)
            }
            for (mid, pair) in grouped where pair.count >= 2 {
                let rids = pair.map(\.rosterId)
                if rids.contains(r1) && rids.contains(r2) {
                    if let t1 = pair.first(where: { $0.rosterId == r1 }) {
                        team1Points = t1.resolvedPoints
                    }
                    if let t2 = pair.first(where: { $0.rosterId == r2 }) {
                        team2Points = t2.resolvedPoints
                    }
                    matchupId = mid
                    return
                }
            }
        } catch {
            // Non-fatal — sheet still shows the bracket info, just no scores.
        }
    }

    private var vsColumn: some View {
        VStack(spacing: XomperTheme.Spacing.xs) {
            Spacer().frame(height: XomperTheme.Spacing.md)
            Text("VS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(XomperColors.textMuted)
        }
    }

    private var placementLabel: String? {
        switch match.placement {
        case 1: return "Championship"
        case 3: return "3rd Place Match"
        case 5: return "5th Place Match"
        case 7: return "7th Place Match"
        default: return "Round \(match.round)"
        }
    }
}

// MARK: - Supporting Types

private enum BracketType: String, CaseIterable, Identifiable {
    case winners
    case consolation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .winners: "Winners"
        case .consolation: "Consolation"
        }
    }
}

private struct BracketRound {
    let round: Int
    let matches: [PlayoffBracketMatch]
    let minRound: Int

    var label: String {
        let totalRounds = round - minRound + 1
        return "Round \(totalRounds)"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PlayoffBracketView(
            leagueStore: LeagueStore(),
            historyStore: HistoryStore(),
            playerStore: PlayerStore()
        )
    }
    .preferredColorScheme(.dark)
}
