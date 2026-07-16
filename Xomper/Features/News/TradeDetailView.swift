import SwiftUI

/// Full-screen detail view for a trade from the News feed. Provides an
/// expanded view of all trade details with clickable team names that
/// navigate to the team detail view.
///
/// Pushed from `NewsView` via `router.navigate(to: .tradeDetail(transactionId:))`.
struct TradeDetailView: View {
    let item: NewsItem
    let router: AppRouter

    /// The winning side (if not fair) for highlight treatment.
    private var winner: NewsSide? {
        guard let grade = item.grade, !grade.isFair else { return nil }
        return item.sides.first { $0.rosterId == grade.winnerRosterId }
    }

    /// The losing side (if not fair).
    private var loser: NewsSide? {
        guard let grade = item.grade, !grade.isFair else { return nil }
        return item.sides.first { $0.rosterId != grade.winnerRosterId }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                headerSection
                verdictCard
                tradeSidesSection
                summaryCard
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Trade Details")
                    .font(.headline)
                    .foregroundStyle(XomperColors.textPrimary)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            // Trade banner
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption.weight(.bold))
                    Text("TRADE")
                        .font(.caption.weight(.heavy))
                        .tracking(1)
                }
                .foregroundStyle(XomperColors.bgDark)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(XomperColors.championGold)
                .clipShape(Capsule())

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Week \(item.week)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(XomperColors.textSecondary)
                    Text(formattedDate(item.createdAt))
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                }
            }

            // Headline
            Text(item.headline)
                .font(.title2.weight(.bold))
                .foregroundStyle(XomperColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Teams involved - clickable
            HStack(spacing: 8) {
                ForEach(item.sides) { side in
                    teamChip(side)
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

    private func teamChip(_ side: NewsSide) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            router.navigate(to: .teamDetail(rosterId: side.rosterId))
        } label: {
            HStack(spacing: 6) {
                Text(side.teamName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(XomperColors.championGold)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(XomperColors.surfaceLight.opacity(0.5))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Verdict Card

    @ViewBuilder
    private var verdictCard: some View {
        if let grade = item.grade {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
                Text("VERDICT")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(XomperColors.championGold)

                HStack(spacing: XomperTheme.Spacing.md) {
                    if grade.isFair {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(XomperColors.championGold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fair Trade")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(XomperColors.textPrimary)
                            Text("Both sides received comparable value")
                                .font(.subheadline)
                                .foregroundStyle(XomperColors.textSecondary)
                        }
                    } else if let winnerSide = winner {
                        Image(systemName: "trophy.fill")
                            .font(.title)
                            .foregroundStyle(XomperColors.championGold)
                        VStack(alignment: .leading, spacing: 2) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                router.navigate(to: .teamDetail(rosterId: winnerSide.rosterId))
                            } label: {
                                HStack(spacing: 4) {
                                    Text(winnerSide.teamName)
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(XomperColors.championGold)
                                    Text("wins")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(XomperColors.textPrimary)
                                }
                            }
                            .buttonStyle(.plain)
                            Text("by \(grade.differential) dynasty points (\(Int(grade.percentGap * 100))% gap)")
                                .font(.subheadline)
                                .foregroundStyle(XomperColors.textSecondary)
                        }
                    }
                    Spacer()
                }
            }
            .padding(XomperTheme.Spacing.md)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        }
    }

    // MARK: - Trade Sides Section

    private var tradeSidesSection: some View {
        VStack(spacing: XomperTheme.Spacing.md) {
            ForEach(item.sides) { side in
                sideCard(side)
            }
        }
    }

    private func sideCard(_ side: NewsSide) -> some View {
        let isWinner = winner?.rosterId == side.rosterId
        let isLoser = loser?.rosterId == side.rosterId
        let letter = item.grade?.letter(for: side.rosterId)

        return VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            // Header: Team name + grade
            HStack {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    router.navigate(to: .teamDetail(rosterId: side.rosterId))
                } label: {
                    HStack(spacing: 8) {
                        Text(side.teamName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(XomperColors.championGold)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(XomperColors.textMuted)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if let letter = letter {
                    GradeBadge(grade: letter)
                }
            }

            // Received section
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                Text("RECEIVED")
                    .font(.caption2.weight(.bold))
                    .tracking(0.5)
                    .foregroundStyle(XomperColors.textMuted)

                if side.acquired.isEmpty {
                    Text("Nothing")
                        .font(.subheadline)
                        .foregroundStyle(XomperColors.textMuted)
                        .italic()
                } else {
                    ForEach(side.acquired) { asset in
                        AssetRow(asset: asset)
                    }
                }

                // Total value
                if side.acquiredValue > 0 {
                    HStack {
                        Text("Total Value:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(XomperColors.textMuted)
                        Text("\(side.acquiredValue) pts")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(isWinner ? XomperColors.successGreen : (isLoser ? XomperColors.accentRed : XomperColors.textSecondary))
                    }
                    .padding(.top, 4)
                }
            }

            // Gave up section (if any)
            if !side.relinquished.isEmpty {
                Divider()
                    .background(XomperColors.surfaceLight)

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                    Text("GAVE UP")
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(XomperColors.textMuted)

                    ForEach(side.relinquished) { asset in
                        AssetRow(asset: asset)
                    }
                }
            }

            // FAAB (if any)
            if let faab = side.faab, faab != 0 {
                HStack {
                    Text("FAAB:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(XomperColors.textMuted)
                    Text(faab > 0 ? "+$\(faab)" : "-$\(abs(faab))")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(faab > 0 ? XomperColors.successGreen : XomperColors.accentRed)
                }
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .fill(isWinner ? XomperColors.successGreen.opacity(0.08) : XomperColors.bgCard)
        )
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(isWinner ? XomperColors.successGreen.opacity(0.4) : XomperColors.surfaceLight.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Summary Card

    @ViewBuilder
    private var summaryCard: some View {
        if !item.summary.isEmpty {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
                Text("ANALYSIS")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(XomperColors.championGold)

                Text(item.summary)
                    .font(.body)
                    .foregroundStyle(XomperColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(XomperTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TradeDetailView(
            item: NewsItem(
                id: "preview-1",
                type: .trade,
                week: 5,
                createdAt: Date(),
                rosterIds: [1, 2],
                sides: [
                    NewsSide(
                        rosterId: 1,
                        teamName: "Dynasty Warriors",
                        acquired: [
                            NewsAsset(id: "p1", name: "Josh Allen", position: "QB", value: 8500, isPick: false),
                            NewsAsset(id: "p2", name: "2026 1st", position: "PICK", value: 2000, isPick: true)
                        ],
                        relinquished: [],
                        faab: nil
                    ),
                    NewsSide(
                        rosterId: 2,
                        teamName: "Gridiron Kings",
                        acquired: [
                            NewsAsset(id: "p3", name: "Jalen Hurts", position: "QB", value: 6000, isPick: false),
                            NewsAsset(id: "p4", name: "Breece Hall", position: "RB", value: 5500, isPick: false)
                        ],
                        relinquished: [],
                        faab: nil
                    )
                ],
                grade: TradeGrade.grade(
                    sideA: (rosterId: 1, value: 10500),
                    sideB: (rosterId: 2, value: 11500)
                ),
                headline: "Josh Allen Moves in Blockbuster Deal",
                summary: "A fairly balanced trade that sees both teams addressing needs. Dynasty Warriors acquire elite QB talent while Gridiron Kings add depth at multiple positions."
            ),
            router: AppRouter()
        )
    }
    .preferredColorScheme(.dark)
}
