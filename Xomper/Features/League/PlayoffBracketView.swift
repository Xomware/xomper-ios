import SwiftUI

struct PlayoffBracketView: View {
    var leagueStore: LeagueStore

    @State private var standings: [StandingsTeam] = []
    @State private var bracketType: BracketType = .winners

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
                .buttonStyle(.plain)
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
                HStack(alignment: .top, spacing: XomperTheme.Spacing.lg) {
                    ForEach(rounds, id: \.round) { roundData in
                        roundColumn(roundData)
                    }
                }
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.bottom, XomperTheme.Spacing.md)
            }
        }
    }

    // MARK: - Round Column

    private func roundColumn(_ roundData: BracketRound) -> some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            Text(roundData.label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(XomperColors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            ForEach(roundData.matches) { match in
                matchCard(match, isFirstRound: roundData.round == roundData.minRound)
            }
        }
        .frame(width: 200)
    }

    // MARK: - Match Card

    private func matchCard(_ match: PlayoffBracketMatch, isFirstRound: Bool) -> some View {
        let isChampionship = match.placement == 1

        return VStack(spacing: 0) {
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
                    lineWidth: 1
                )
        )
        .xomperShadow(.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(matchAccessibilityLabel(match))
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

            Text(teamDisplayName(rosterId: rosterId, source: source))
                .font(.subheadline)
                .fontWeight(isWinner ? .bold : .regular)
                .foregroundStyle(
                    isWinner ? XomperColors.successGreen :
                    isLoser ? XomperColors.textMuted :
                    XomperColors.textPrimary
                )
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showSeed, let seed = rosterId {
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
        let t1 = teamDisplayName(rosterId: match.team1RosterId, source: match.team1From)
        let t2 = teamDisplayName(rosterId: match.team2RosterId, source: match.team2From)
        let label = matchLabel(match).map { "\($0): " } ?? ""
        if let winnerId = match.winnerRosterId {
            let winner = teamDisplayName(rosterId: winnerId, source: nil)
            return "\(label)\(t1) vs \(t2), winner: \(winner)"
        }
        return "\(label)\(t1) vs \(t2)"
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
        guard let league = leagueStore.currentLeague else { return }
        standings = StandingsBuilder.buildStandings(
            rosters: leagueStore.currentLeagueRosters,
            users: leagueStore.currentLeagueUsers,
            league: league
        )
    }

    private func loadBrackets() async {
        guard let league = leagueStore.currentLeague else { return }
        await leagueStore.fetchBrackets(leagueId: league.leagueId)
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
        PlayoffBracketView(leagueStore: LeagueStore())
    }
    .preferredColorScheme(.dark)
}
