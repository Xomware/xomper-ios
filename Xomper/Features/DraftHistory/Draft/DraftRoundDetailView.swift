import SwiftUI

/// Full-screen detail view for a single draft round. Shows all picks
/// in order with player details, team info, and navigation to team
/// detail views.
///
/// Pushed from `DraftRecapView` via `router.navigate(to: .draftRoundDetail(season:round:))`.
struct DraftRoundDetailView: View {
    let season: String
    let round: Int
    var historyStore: HistoryStore
    var playerStore: PlayerStore
    var router: AppRouter

    @State private var selectedPlayer: Player?

    /// All picks for this round, sorted by pick number.
    private var picks: [DraftHistoryRecord] {
        historyStore.draftHistory
            .filter { $0.season == season && $0.round == round }
            .sorted { $0.pickNo < $1.pickNo }
    }

    /// Position breakdown for this round.
    private var positionCounts: [(position: String, count: Int)] {
        var counts: [String: Int] = [:]
        for pick in picks {
            counts[pick.playerPosition, default: 0] += 1
        }
        return counts
            .map { (position: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                headerSection
                positionBreakdownCard
                picksListCard
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("\(season) Draft - Round \(round)")
                    .font(.headline)
                    .foregroundStyle(XomperColors.textPrimary)
            }
        }
        .sheet(item: $selectedPlayer) { player in
            PlayerDetailView(player: player, playerStore: playerStore)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "list.clipboard")
                        .font(.caption.weight(.bold))
                    Text("ROUND \(round)")
                        .font(.caption.weight(.heavy))
                        .tracking(1)
                }
                .foregroundStyle(XomperColors.bgDark)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(XomperColors.championGold)
                .clipShape(Capsule())

                Spacer()

                Text("\(season) Draft")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(XomperColors.textSecondary)
            }

            Text("\(picks.count) Picks")
                .font(.title2.weight(.bold))
                .foregroundStyle(XomperColors.textPrimary)

            // First pick highlight
            if let firstPick = picks.first {
                HStack(spacing: 8) {
                    Text("First pick:")
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textSecondary)
                    Text(firstPick.playerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.championGold)
                    Text("(\(firstPick.playerPosition))")
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textMuted)
                }
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Position Breakdown

    private var positionBreakdownCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text("POSITION BREAKDOWN")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(XomperColors.championGold)

            HStack(spacing: XomperTheme.Spacing.sm) {
                ForEach(positionCounts, id: \.position) { item in
                    VStack(spacing: 4) {
                        Text("\(item.count)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(XomperColors.textPrimary)
                        Text(item.position)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(XomperColors.bgDark)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(positionColor(item.position))
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
    }

    // MARK: - Picks List

    private var picksListCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            Text("ALL PICKS")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(XomperColors.championGold)

            ForEach(picks) { pick in
                pickRow(pick)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
    }

    private func pickRow(_ pick: DraftHistoryRecord) -> some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            // Pick number
            Text("\(pick.draftSlot)")
                .font(.caption.weight(.bold))
                .foregroundStyle(XomperColors.textMuted)
                .frame(width: 24, alignment: .center)
                .monospacedDigit()

            // Player image
            PlayerImageView(playerID: pick.playerId, size: XomperTheme.AvatarSize.md)
                .overlay(
                    Circle()
                        .stroke(positionColor(pick.playerPosition).opacity(0.5), lineWidth: 1.5)
                )

            // Player info
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedPlayer = playerStore.players[pick.playerId]
                } label: {
                    HStack(spacing: 4) {
                        Text(pick.playerName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(XomperColors.textPrimary)
                            .lineLimit(1)
                        if playerStore.players[pick.playerId] != nil {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(XomperColors.textMuted)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(playerStore.players[pick.playerId] == nil)

                HStack(spacing: 6) {
                    Text(pick.playerPosition)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.bgDark)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(positionColor(pick.playerPosition))
                        .clipShape(Capsule())

                    if !pick.playerTeam.isEmpty {
                        Text(pick.playerTeam)
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                    }
                }
            }

            Spacer()

            // Team that drafted - clickable
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                router.navigate(to: .teamDetail(rosterId: pick.pickedByRosterId))
            } label: {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(pick.pickedByTeamName.isEmpty ? pick.pickedByUsername : pick.pickedByTeamName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(XomperColors.championGold)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.textMuted)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(XomperTheme.Spacing.sm)
        .background(XomperColors.surfaceLight.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
    }

    // MARK: - Helpers

    private func positionColor(_ pos: String) -> Color {
        switch pos.uppercased() {
        case "QB": return Color(red: 0.95, green: 0.30, blue: 0.42)
        case "RB": return Color(red: 0.20, green: 0.80, blue: 0.50)
        case "WR": return Color(red: 0.30, green: 0.55, blue: 0.95)
        case "TE": return Color(red: 0.95, green: 0.65, blue: 0.20)
        case "K":  return Color(red: 0.65, green: 0.55, blue: 0.85)
        case "DEF", "DST": return Color(red: 0.55, green: 0.55, blue: 0.55)
        default: return XomperColors.surfaceLight
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DraftRoundDetailView(
            season: "2024",
            round: 1,
            historyStore: HistoryStore(),
            playerStore: PlayerStore(),
            router: AppRouter()
        )
    }
    .preferredColorScheme(.dark)
}
