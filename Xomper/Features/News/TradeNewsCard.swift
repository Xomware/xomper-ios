import SwiftUI

/// Feed card for a completed trade. Shows a per-side letter grade, each
/// team's haul, the raw dynasty-value differential, and a deterministic
/// write-up. Grades + differential come pre-computed on the `NewsItem`.
struct TradeNewsCard: View {
    let item: NewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            NewsCardHeader(item: item)

            Text(item.headline)
                .font(.title3.weight(.bold))
                .foregroundStyle(XomperColors.championGold)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            ForEach(item.sides) { side in
                sideBlock(side)
            }

            differentialRow

            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.summary.isEmpty ? item.headline : item.summary)
    }

    // MARK: - Side block

    private func sideBlock(_ side: NewsSide) -> some View {
        HStack(alignment: .top, spacing: XomperTheme.Spacing.sm) {
            if let grade = item.grade {
                GradeBadge(grade: grade.letter(for: side.rosterId))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(side.teamName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)

                if side.acquired.isEmpty {
                    Text("Received nothing")
                        .font(.caption)
                        .foregroundStyle(XomperColors.textMuted)
                } else {
                    ForEach(side.acquired) { AssetRow(asset: $0) }
                }

                if let faab = side.faab, faab != 0 {
                    Text("\(faab > 0 ? "+" : "")\(faab) FAAB")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(XomperColors.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(XomperTheme.Spacing.sm)
        .background(XomperColors.surfaceLight.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
    }

    // MARK: - Differential

    @ViewBuilder
    private var differentialRow: some View {
        if let grade = item.grade {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Image(systemName: "chart.bar.fill")
                    .font(.caption2)
                Text(differentialText(grade))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(grade.isFair ? XomperColors.textSecondary : XomperColors.championGold)
        }
    }

    private func differentialText(_ grade: TradeGrade) -> String {
        if grade.isFair {
            return "Even value — within \(Int(grade.percentGap * 100))%"
        }
        let winner = item.sides.first { $0.rosterId == grade.winnerRosterId }?.teamName ?? "Winner"
        return "Differential \(grade.differential) · \(winner) +\(Int(grade.percentGap * 100))%"
    }
}
