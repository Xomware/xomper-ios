import SwiftUI

/// Per-position breakdown grid used on the Analyzer Compare tab and
/// (without an opponent column) on the My Team Strengths tab.
///
/// Shows each hex axis as a labeled progress bar. My value is color-
/// coded gold (above league avg) or red (significantly below). When
/// an opponent analysis is supplied their values appear in cyan as a
/// second column; otherwise the league-average value fills that slot.
struct PositionBreakdownCard: View {

    let my: TeamAnalysis
    let opp: TeamAnalysis?
    let averages: [TeamAnalysis.HexAxis]
    let maxes: [String: Int]

    var body: some View {
        VStack(spacing: XomperTheme.Spacing.xs) {
            ForEach(Array(my.hexAxes.enumerated()), id: \.offset) { idx, axis in
                let oppValue = opp?.hexAxes[idx].value
                let avgValue = idx < averages.count ? averages[idx].value : 0
                breakdownRow(
                    label: axis.label,
                    myValue: axis.value,
                    oppValue: oppValue,
                    avgValue: avgValue,
                    leagueMax: maxes[axis.label] ?? axis.value
                )
            }
            Divider().background(XomperColors.surfaceLight.opacity(0.4))
            HStack {
                Text("Total roster value")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(XomperColors.textSecondary)
                Spacer()
                Text("\(my.totalValue)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                    .monospacedDigit()
                if let opp {
                    Text("vs \(opp.totalValue)")
                        .font(.subheadline)
                        .foregroundStyle(.cyan)
                        .monospacedDigit()
                }
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(Color.clear, lineWidth: 0)
        )
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    // MARK: - Private

    private func breakdownRow(
        label: String,
        myValue: Int,
        oppValue: Int?,
        avgValue: Int,
        leagueMax: Int
    ) -> some View {
        HStack(spacing: XomperTheme.Spacing.sm) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XomperColors.textPrimary)
                .frame(width: 60, alignment: .leading)

            ProgressView(
                value: leagueMax > 0 ? Double(myValue) / Double(leagueMax) : 0
            )
            .tint(XomperColors.championGold)
            .frame(maxWidth: .infinity)

            Text("\(myValue)")
                .font(.caption.weight(.bold))
                .foregroundStyle(deltaColor(myValue: myValue, avgValue: avgValue))
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)

            if let oppValue {
                Text("\(oppValue)")
                    .font(.caption)
                    .foregroundStyle(.cyan)
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            } else {
                Text("\(avgValue)")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }
}

/// Color the my-team value gold when above league average and red
/// when significantly below — a glance-readable health check on
/// position depth without needing to do the math.
private func deltaColor(myValue: Int, avgValue: Int) -> Color {
    guard avgValue > 0 else { return XomperColors.textPrimary }
    let ratio = Double(myValue) / Double(avgValue)
    if ratio >= 1.05 { return XomperColors.championGold }
    if ratio <= 0.85 { return XomperColors.errorRed }
    return XomperColors.textPrimary
}
