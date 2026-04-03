import SwiftUI

/// Standalone H2H history between two specific users across all seasons.
/// Shows running record and chronological list of all matchups with scores.
struct MatchupHistoryView: View {
    let user1Id: String
    let user2Id: String
    let user1Name: String
    let user2Name: String
    var historyStore: HistoryStore

    @Environment(\.dismiss) private var dismiss

    private var h2h: HeadToHeadRecord {
        historyStore.headToHead(userId1: user1Id, userId2: user2Id)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.md) {
                recordHeader
                matchupsList
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle("Head to Head")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Record Header

    private var recordHeader: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            HStack(alignment: .top) {
                // User 1
                VStack(spacing: XomperTheme.Spacing.xs) {
                    Text(user1Name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            h2h.user1Wins > h2h.user2Wins
                                ? XomperColors.championGold
                                : XomperColors.textPrimary
                        )
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text("\(h2h.user1Wins)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            h2h.user1Wins > h2h.user2Wins
                                ? XomperColors.championGold
                                : XomperColors.textPrimary
                        )
                        .monospacedDigit()

                    Text("Wins")
                        .font(.caption)
                        .foregroundStyle(XomperColors.textMuted)
                }
                .frame(maxWidth: .infinity)

                // Center divider
                VStack(spacing: XomperTheme.Spacing.xs) {
                    Text("VS")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(XomperColors.textMuted)

                    if h2h.ties > 0 {
                        Text("\(h2h.ties) ties")
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                    }

                    Text("\(h2h.totalGames) games")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                }
                .padding(.top, XomperTheme.Spacing.lg)

                // User 2
                VStack(spacing: XomperTheme.Spacing.xs) {
                    Text(user2Name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            h2h.user2Wins > h2h.user1Wins
                                ? XomperColors.championGold
                                : XomperColors.textPrimary
                        )
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text("\(h2h.user2Wins)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            h2h.user2Wins > h2h.user1Wins
                                ? XomperColors.championGold
                                : XomperColors.textPrimary
                        )
                        .monospacedDigit()

                    Text("Wins")
                        .font(.caption)
                        .foregroundStyle(XomperColors.textMuted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .xomperShadow(.md)
    }

    // MARK: - Matchups List

    private var matchupsList: some View {
        let grouped = groupedBySeason

        return LazyVStack(spacing: XomperTheme.Spacing.md) {
            if grouped.isEmpty {
                EmptyStateView(
                    icon: "sportscourt",
                    title: "No Matchups",
                    message: "These teams have never played each other."
                )
            } else {
                ForEach(grouped, id: \.season) { group in
                    seasonSection(group)
                }
            }
        }
    }

    private func seasonSection(_ group: SeasonGroup) -> some View {
        VStack(spacing: XomperTheme.Spacing.sm) {
            HStack {
                Text(group.season)
                    .font(.headline)
                    .foregroundStyle(XomperColors.textPrimary)

                Spacer()

                Text(seasonRecord(group.matchups))
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
            }

            ForEach(group.matchups) { matchup in
                h2hMatchupRow(matchup)
            }
        }
    }

    private func h2hMatchupRow(_ matchup: MatchupHistoryRecord) -> some View {
        let isUser1TeamA = matchup.teamAUserId == user1Id
        let user1Points = isUser1TeamA ? matchup.teamAPoints : matchup.teamBPoints
        let user2Points = isUser1TeamA ? matchup.teamBPoints : matchup.teamAPoints
        let user1RosterId = isUser1TeamA ? matchup.teamARosterId : matchup.teamBRosterId
        let user1Won = matchup.winnerRosterId == user1RosterId

        return HStack {
            Text(matchup.isPlayoff ? "Wk \(matchup.week) (P)" : "Week \(matchup.week)")
                .font(.caption)
                .foregroundStyle(XomperColors.textMuted)
                .frame(width: 72, alignment: .leading)

            Spacer()

            Text(String(format: "%.2f", user1Points))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(user1Won ? XomperColors.championGold : XomperColors.textSecondary)
                .monospacedDigit()

            Text("-")
                .font(.caption)
                .foregroundStyle(XomperColors.textMuted)
                .padding(.horizontal, XomperTheme.Spacing.xs)

            Text(String(format: "%.2f", user2Points))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(!user1Won && matchup.winnerRosterId != nil ? XomperColors.championGold : XomperColors.textSecondary)
                .monospacedDigit()

            Spacer()

            resultBadge(user1Won: user1Won, isTie: matchup.winnerRosterId == nil)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.vertical, XomperTheme.Spacing.xs)
        .padding(.horizontal, XomperTheme.Spacing.sm)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Week \(matchup.week), \(String(format: "%.2f", user1Points)) to \(String(format: "%.2f", user2Points))")
    }

    private func resultBadge(user1Won: Bool, isTie: Bool) -> some View {
        Group {
            if isTie {
                Text("T")
                    .foregroundStyle(XomperColors.textMuted)
            } else if user1Won {
                Text("W")
                    .foregroundStyle(XomperColors.championGold)
            } else {
                Text("L")
                    .foregroundStyle(XomperColors.accentRed)
            }
        }
        .font(.caption)
        .fontWeight(.bold)
    }

    // MARK: - Helpers

    private var groupedBySeason: [SeasonGroup] {
        let matchups = h2h.matchups
        var map: [String: [MatchupHistoryRecord]] = [:]

        for m in matchups {
            map[m.season, default: []].append(m)
        }

        return map.map { SeasonGroup(season: $0.key, matchups: $0.value.sorted { $0.week < $1.week }) }
            .sorted { (Int($0.season) ?? 0) > (Int($1.season) ?? 0) }
    }

    private func seasonRecord(_ matchups: [MatchupHistoryRecord]) -> String {
        var wins = 0
        var losses = 0
        var ties = 0

        for m in matchups {
            let user1RosterId = m.teamAUserId == user1Id ? m.teamARosterId : m.teamBRosterId
            if m.winnerRosterId == user1RosterId {
                wins += 1
            } else if m.winnerRosterId == nil {
                ties += 1
            } else {
                losses += 1
            }
        }

        if ties > 0 {
            return "\(wins)-\(losses)-\(ties)"
        }
        return "\(wins)-\(losses)"
    }
}

// MARK: - Season Group

private struct SeasonGroup: Sendable {
    let season: String
    let matchups: [MatchupHistoryRecord]
}

#Preview {
    NavigationStack {
        MatchupHistoryView(
            user1Id: "u1",
            user2Id: "u2",
            user1Name: "Team Alpha",
            user2Name: "Team Beta",
            historyStore: HistoryStore()
        )
    }
    .preferredColorScheme(.dark)
}
