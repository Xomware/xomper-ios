import SwiftUI

/// Compact "trophy bar" card rendering one championship win.
/// Static layout — no tap action in v1 (drill-in deferred to F7).
struct TrophyCaseCard: View {
    let championship: Championship

    var body: some View {
        HStack(spacing: XomperTheme.Spacing.md) {
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundStyle(XomperColors.championGold)
                .frame(width: 32, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                Text("\(championship.season) Champion")
                    .font(.headline)
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)

                Text(championship.teamName)
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textSecondary)
                    .lineLimit(1)

                Text("vs \(championship.opponentTeamName)")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: XomperTheme.Spacing.xs) {
                Text(String(format: "%.1f", championship.pointsFor))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(XomperColors.championGold)
                    .monospacedDigit()

                Text(String(format: "%.1f", championship.pointsAgainst))
                    .font(.caption)
                    .foregroundStyle(XomperColors.textMuted)
                    .monospacedDigit()
            }
        }
        .xomperCard()
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(
                    XomperColors.championGold.opacity(0.35),
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let scoreFor = String(format: "%.1f", championship.pointsFor)
        let scoreAgainst = String(format: "%.1f", championship.pointsAgainst)
        return "\(championship.season) champion. \(championship.teamName), "
            + "\(scoreFor) to \(scoreAgainst), versus \(championship.opponentTeamName)."
    }
}

#Preview {
    VStack(spacing: XomperTheme.Spacing.md) {
        TrophyCaseCard(
            championship: Championship(
                season: "2024",
                leagueId: "abc",
                week: 17,
                teamName: "Dom's Dynasty",
                pointsFor: 127.4,
                pointsAgainst: 119.8,
                opponentTeamName: "The Other Guy"
            )
        )

        TrophyCaseCard(
            championship: Championship(
                season: "2022",
                leagueId: "abc",
                week: 16,
                teamName: "Dom's Dynasty",
                pointsFor: 154.2,
                pointsAgainst: 98.6,
                opponentTeamName: "Some Rival"
            )
        )
    }
    .padding()
    .background(XomperColors.bgDark)
    .preferredColorScheme(.dark)
}
