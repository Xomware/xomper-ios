import SwiftUI

struct MatchupDetailView: View {
    let record: MatchupHistoryRecord
    var historyStore: HistoryStore
    var playerStore: PlayerStore

    @Environment(\.dismiss) private var dismiss
    @State private var matchupPair: MatchupPair?
    @State private var isLoading = true
    @State private var loadError: Error?

    var body: some View {
        Group {
            if isLoading {
                LoadingView(message: "Loading lineup details...")
            } else if let error = loadError {
                ErrorView(message: error.localizedDescription) {
                    Task { await loadDetail() }
                }
            } else if let pair = matchupPair {
                detailContent(pair)
            } else {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Could Not Load",
                    message: "Unable to load matchup details."
                )
            }
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle("Week \(record.week)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .foregroundStyle(XomperColors.championGold)
            }
        }
        .task {
            await loadDetail()
        }
    }

    // MARK: - Detail Content

    private func detailContent(_ pair: MatchupPair) -> some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.md) {
                scoreHeader(pair)
                seasonLabel
                startersSection(pair)
                benchSection(pair)
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
        .background(XomperColors.bgDark)
    }

    // MARK: - Score Header

    private func scoreHeader(_ pair: MatchupPair) -> some View {
        let teamAWon = record.winnerRosterId == record.teamARosterId
        let teamBWon = record.winnerRosterId == record.teamBRosterId

        return VStack(spacing: XomperTheme.Spacing.md) {
            HStack(alignment: .top) {
                // Team A
                VStack(spacing: XomperTheme.Spacing.xs) {
                    Text(record.teamATeamName.isEmpty ? record.teamAUsername : record.teamATeamName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(teamAWon ? XomperColors.championGold : XomperColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if !record.teamATeamName.isEmpty {
                        Text(record.teamAUsername)
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                    }

                    Text(String(format: "%.2f", record.teamAPoints))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(teamAWon ? XomperColors.championGold : XomperColors.textPrimary)
                        .monospacedDigit()

                    if teamAWon {
                        winBadge
                    }
                }
                .frame(maxWidth: .infinity)

                // VS
                VStack(spacing: XomperTheme.Spacing.xs) {
                    Text("VS")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(XomperColors.textMuted)

                    Text("\(pointsDiff) pts")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                }
                .padding(.top, XomperTheme.Spacing.lg)

                // Team B
                VStack(spacing: XomperTheme.Spacing.xs) {
                    Text(record.teamBTeamName.isEmpty ? record.teamBUsername : record.teamBTeamName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(teamBWon ? XomperColors.championGold : XomperColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if !record.teamBTeamName.isEmpty {
                        Text(record.teamBUsername)
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                    }

                    Text(String(format: "%.2f", record.teamBPoints))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(teamBWon ? XomperColors.championGold : XomperColors.textPrimary)
                        .monospacedDigit()

                    if teamBWon {
                        winBadge
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(XomperTheme.Spacing.md)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
            .xomperShadow(.md)
        }
    }

    private var winBadge: some View {
        Text("WINNER")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(XomperColors.deepNavy)
            .padding(.horizontal, XomperTheme.Spacing.sm)
            .padding(.vertical, XomperTheme.Spacing.xs)
            .background(XomperColors.championGold)
            .clipShape(Capsule())
    }

    private var seasonLabel: some View {
        HStack {
            if record.isChampionship {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(XomperColors.championGold)
                Text("Championship")
                    .fontWeight(.semibold)
                    .foregroundStyle(XomperColors.championGold)
            } else if record.isPlayoff {
                Image(systemName: "star.fill")
                    .foregroundStyle(XomperColors.steelBlue)
                Text("Playoff")
                    .fontWeight(.semibold)
                    .foregroundStyle(XomperColors.steelBlue)
            }

            Spacer()

            Text("\(record.season) Season")
                .foregroundStyle(XomperColors.textMuted)
        }
        .font(.caption)
    }

    // MARK: - Starters Section

    private func startersSection(_ pair: MatchupPair) -> some View {
        let rawA = resolvedTeamA(pair)
        let rawB = resolvedTeamB(pair)

        let startersA = rawA.starters ?? []
        let startersB = rawB.starters ?? []
        let pointsA = rawA.startersPoints ?? []
        let pointsB = rawB.startersPoints ?? []

        let maxCount = max(startersA.count, startersB.count)

        return VStack(spacing: XomperTheme.Spacing.xs) {
            // Header
            HStack {
                Text("Starters")
                    .font(.headline)
                    .foregroundStyle(XomperColors.textPrimary)
                Spacer()
            }

            // Column headers
            HStack {
                Text(teamAName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(XomperColors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)

                Text("PTS")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(XomperColors.textMuted)
                    .frame(width: 44, alignment: .trailing)

                Spacer()
                    .frame(width: XomperTheme.Spacing.sm)

                Text("PTS")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(XomperColors.textMuted)
                    .frame(width: 44, alignment: .leading)

                Text(teamBName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(XomperColors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .lineLimit(1)
            }
            .padding(.horizontal, XomperTheme.Spacing.sm)

            // Player rows
            ForEach(0..<maxCount, id: \.self) { index in
                starterRow(
                    playerIdA: index < startersA.count ? startersA[index] : nil,
                    pointsA: index < pointsA.count ? pointsA[index] : nil,
                    playerIdB: index < startersB.count ? startersB[index] : nil,
                    pointsB: index < pointsB.count ? pointsB[index] : nil
                )
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
    }

    private func starterRow(playerIdA: String?, pointsA: Double?, playerIdB: String?, pointsB: Double?) -> some View {
        let playerA = playerIdA.flatMap { playerStore.player(for: $0) }
        let playerB = playerIdB.flatMap { playerStore.player(for: $0) }

        return HStack(spacing: 0) {
            // Team A player
            playerCell(player: playerA, playerId: playerIdA, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Team A points
            Text(pointsA.map { String(format: "%.1f", $0) } ?? "-")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(XomperColors.textPrimary)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)

            Spacer()
                .frame(width: XomperTheme.Spacing.sm)

            // Team B points
            Text(pointsB.map { String(format: "%.1f", $0) } ?? "-")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(XomperColors.textPrimary)
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)

            // Team B player
            playerCell(player: playerB, playerId: playerIdB, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, XomperTheme.Spacing.xs)
        .padding(.horizontal, XomperTheme.Spacing.sm)
    }

    private func playerCell(player: Player?, playerId: String?, alignment: HorizontalAlignment) -> some View {
        let isLeading = alignment == .leading
        let textAlignment: TextAlignment = isLeading ? .leading : .trailing
        let frameAlignment: Alignment = isLeading ? .leading : .trailing

        return VStack(alignment: alignment, spacing: 0) {
            Text(player?.fullDisplayName ?? playerId ?? "-")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(1)
                .multilineTextAlignment(textAlignment)

            Text(player?.displayPosition ?? "")
                .font(.caption2)
                .foregroundStyle(positionColor(player?.displayPosition))
                .multilineTextAlignment(textAlignment)
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    // MARK: - Bench Section

    private func benchSection(_ pair: MatchupPair) -> some View {
        let rawA = resolvedTeamA(pair)
        let rawB = resolvedTeamB(pair)

        let starterSetA = Set(rawA.starters ?? [])
        let starterSetB = Set(rawB.starters ?? [])
        let allA = rawA.players ?? []
        let allB = rawB.players ?? []
        let pointsMapA = rawA.playersPoints ?? [:]
        let pointsMapB = rawB.playersPoints ?? [:]

        let benchA = allA.filter { !starterSetA.contains($0) && $0 != "0" }
        let benchB = allB.filter { !starterSetB.contains($0) && $0 != "0" }

        let maxCount = max(benchA.count, benchB.count)

        if maxCount == 0 { return AnyView(EmptyView()) }

        return AnyView(
            VStack(spacing: XomperTheme.Spacing.xs) {
                HStack {
                    Text("Bench")
                        .font(.headline)
                        .foregroundStyle(XomperColors.textPrimary)
                    Spacer()
                }

                ForEach(0..<maxCount, id: \.self) { index in
                    let idA = index < benchA.count ? benchA[index] : nil
                    let idB = index < benchB.count ? benchB[index] : nil
                    starterRow(
                        playerIdA: idA,
                        pointsA: idA.flatMap { pointsMapA[$0] },
                        playerIdB: idB,
                        pointsB: idB.flatMap { pointsMapB[$0] }
                    )
                }
            }
            .padding(XomperTheme.Spacing.md)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        )
    }

    // MARK: - Helpers

    private var teamAName: String {
        record.teamATeamName.isEmpty ? record.teamAUsername : record.teamATeamName
    }

    private var teamBName: String {
        record.teamBTeamName.isEmpty ? record.teamBUsername : record.teamBTeamName
    }

    private func resolvedTeamA(_ pair: MatchupPair) -> Matchup {
        if pair.teamA.rosterId == record.teamARosterId {
            return pair.teamA
        }
        return pair.teamB
    }

    private func resolvedTeamB(_ pair: MatchupPair) -> Matchup {
        if pair.teamB.rosterId == record.teamBRosterId {
            return pair.teamB
        }
        return pair.teamA
    }

    private var pointsDiff: String {
        let diff = abs(record.teamAPoints - record.teamBPoints)
        return String(format: "%.2f", diff)
    }

    private func positionColor(_ position: String?) -> Color {
        switch position {
        case "QB": Color(hex: 0xFF6B6B)
        case "RB": Color(hex: 0x69DB7C)
        case "WR": Color(hex: 0x74C0FC)
        case "TE": Color(hex: 0xFFD43B)
        case "K": Color(hex: 0xDA77F2)
        case "DEF": Color(hex: 0xFFA94D)
        default: XomperColors.textMuted
        }
    }

    private func loadDetail() async {
        isLoading = true
        loadError = nil

        do {
            let pairs = try await historyStore.fetchRawMatchups(
                leagueId: record.leagueId,
                week: record.week
            )

            // Find the pair matching our record by matchup_id
            let matched = pairs.first { pair in
                pair.teamA.matchupId == record.matchupId ||
                pair.teamB.matchupId == record.matchupId
            }

            matchupPair = matched
        } catch {
            loadError = error
        }

        isLoading = false
    }
}

#Preview {
    let record = MatchupHistoryRecord(
        leagueId: "123",
        season: "2024",
        week: 1,
        matchupId: 1,
        teamARosterId: 1,
        teamAUserId: "u1",
        teamAUsername: "user1",
        teamATeamName: "Team Alpha",
        teamAPoints: 125.42,
        teamBRosterId: 2,
        teamBUserId: "u2",
        teamBUsername: "user2",
        teamBTeamName: "Team Beta",
        teamBPoints: 118.76,
        winnerRosterId: 1,
        isPlayoff: false,
        isChampionship: false,
        teamADivision: 1,
        teamBDivision: 2
    )

    NavigationStack {
        MatchupDetailView(
            record: record,
            historyStore: HistoryStore(),
            playerStore: PlayerStore()
        )
    }
    .preferredColorScheme(.dark)
}
