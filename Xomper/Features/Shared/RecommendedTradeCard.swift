import SwiftUI

/// Card rendering a single `RecommendedTrade` suggestion. Used in the
/// Team Analyzer Trade tab's recommended-trades section and on the My
/// Team Trades tab.
///
/// Pure presentation — the button action (load into builder, or
/// pre-load via controller + navigate) is the caller's responsibility.
struct RecommendedTradeCard: View {

    let rec: RecommendedTrade

    init(_ rec: RecommendedTrade) {
        self.rec = rec
    }

    var body: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.sm) {
                Text(rec.partnerTeamName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.0f%% gap", rec.percentGap * 100))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.bgDark)
                    .padding(.horizontal, XomperTheme.Spacing.xs)
                    .background(XomperColors.successGreen)
                    .clipShape(Capsule())
            }

            HStack(alignment: .top, spacing: XomperTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Give")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.textMuted)
                        .textCase(.uppercase)
                    Text(rec.give.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)
                    Text("\(rec.give.position) · \(rec.give.value)")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(XomperColors.textMuted)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Receive")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XomperColors.championGold)
                        .textCase(.uppercase)
                    Text(rec.receive.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)
                    Text("\(rec.receive.position) · \(rec.receive.value)")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Tap to load into the builder above.")
                .font(.caption2)
                .foregroundStyle(XomperColors.textMuted)
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
    }
}
